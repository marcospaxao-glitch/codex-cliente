/*
 * pkpacker - empacota e criptografa os arquivos do cliente
 *
 *   pkpacker --newkey > ../src/framework/core/packkey.h
 *       gera uma chave nova (depois compile de novo o cliente e o pkpacker)
 *
 *   pkpacker <pasta do cliente> <saida.zip> [itens...]
 *       criptografa e junta num zip. Itens padrao: init.lua data modules layouts mods
 *
 *   pkpacker --publicar <pasta do cliente> <pasta do site> [--exe <PokeFans.exe>] [itens...]
 *       gera a pasta de atualizacao (manifest.txt + files/) para subir no site.
 *       So regrava os arquivos que mudaram desde a ultima publicacao.
 *
 *   pkpacker --colar <otclient.exe> <data.zip> <saida.exe>
 *       cola o zip dentro do .exe (fica um arquivo so)
 *
 *   pkpacker --abrir <arquivo criptografado> <saida>
 *       descriptografa um arquivo (para conferir)
 */
#include "../framework/core/packcrypt.h"

#include <filesystem>
#include <set>
#include <openssl/rand.h>
#include <zlib.h>

#include <cstdio>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <algorithm>
#include <map>
#include <ctime>

namespace fs = std::filesystem;

static std::string readAll(const std::string& path)
{
    std::ifstream in(path, std::ios::binary);
    if(!in)
        throw std::runtime_error("nao abriu " + path);
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

static void writeAll(const std::string& path, const std::string& data)
{
    fs::path parent = fs::path(path).parent_path();
    if(!parent.empty())
        fs::create_directories(parent);
    std::ofstream out(path, std::ios::binary);
    if(!out)
        throw std::runtime_error("nao criou " + path);
    out.write(data.data(), data.size());
}

static void u16(std::string& s, uint16_t v) { s.push_back(v & 0xFF); s.push_back((v >> 8) & 0xFF); }
static void u32(std::string& s, uint32_t v) { for(int i = 0; i < 4; ++i) s.push_back((v >> (8 * i)) & 0xFF); }

struct Entry { std::string name; uint32_t crc, size, offset; };

static bool skipFile(const fs::path& p)
{
    std::string ext = p.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    std::string name = p.filename().string();
    return ext == ".rar" || ext == ".log" || ext == ".bak" || name == "Thumbs.db" || name == "desktop.ini" || name[0] == '.';
}

typedef std::vector<std::pair<std::string, std::string>> FileList; // nome no zip, caminho real

static FileList collect(const std::string& root, std::vector<std::string> items)
{
    if(items.empty())
        items = {"init.lua", "data", "modules", "layouts", "mods", "config.ini", "otclientrc.lua", "cacert.pem"};

    FileList files;
    for(const std::string& item : items) {
        fs::path p = fs::path(root) / item;
        if(!fs::exists(p)) {
            std::cout << "  (ignorado, nao existe) " << item << "\n";
            continue;
        }
        if(fs::is_regular_file(p)) {
            files.push_back({item, p.string()});
            continue;
        }
        for(fs::recursive_directory_iterator it(p), end; it != end; ++it) {
            if(it->is_directory() && it->path().filename().string().size() > 0 && it->path().filename().string()[0] == '.') {
                it.disable_recursion_pending();
                continue;
            }
            if(!fs::is_regular_file(it->path()) || skipFile(it->path()))
                continue;
            std::string rel = fs::relative(it->path(), root).generic_string();
            files.push_back({rel, it->path().string()});
        }
    }
    std::sort(files.begin(), files.end());
    return files;
}

// CODEX: lista de todos os arquivos do cliente. O cliente novo apaga do codex.dat
// o que nao estiver nela (modulos que sairam do cliente).
static const char* LIST_FILE = "codex_arquivos.txt";
static std::string fileList(const FileList& files)
{
    std::string out;
    for(auto& f : files)
        out += f.first + "\n";
    return out;
}

static std::string hex8(uint32_t v)
{
    char buf[16];
    snprintf(buf, sizeof(buf), "%08x", v);
    return buf;
}

static int pack(const std::string& root, const std::string& outPath, std::vector<std::string> items)
{
    FileList files = collect(root, items);

    // manifesto interno: o atualizador compara com o do site
    std::string manifest = "B\t" + std::to_string((long long)time(nullptr)) + "\n";
    std::string zip;
    std::vector<Entry> entries;
    uint64_t original = 0;
    auto addEntry = [&](const std::string& name, const std::string& enc) {
        Entry e;
        e.name = name;
        e.crc = crc32(0L, (const Bytef*)enc.data(), (uInt)enc.size());
        e.size = (uint32_t)enc.size();
        e.offset = (uint32_t)zip.size();
        // local file header (stored)
        u32(zip, 0x04034b50); u16(zip, 20); u16(zip, 0); u16(zip, 0);
        u16(zip, 0); u16(zip, 0x5A21); // hora/data fixas
        u32(zip, e.crc); u32(zip, e.size); u32(zip, e.size);
        u16(zip, (uint16_t)e.name.size()); u16(zip, 0);
        zip += e.name;
        zip += enc;
        entries.push_back(e);
        if(zip.size() > 0xF0000000u)
            throw std::runtime_error("pacote passou de 4 GB");
    };
    for(auto& f : files) {
        std::string data = readAll(f.second);
        original += data.size();
        uint32_t plainCrc = crc32(0L, (const Bytef*)data.data(), (uInt)data.size());
        std::string enc = PackCrypt::encrypt(data, true);
        manifest += "F\t" + hex8(plainCrc) + "\t" + std::to_string(enc.size()) + "\t" + f.first + "\n";
        addEntry(f.first, enc);
    }
    {
        std::string list = fileList(files);
        uint32_t listCrc = crc32(0L, (const Bytef*)list.data(), (uInt)list.size());
        std::string enc = PackCrypt::encrypt(list, true);
        manifest += "F\t" + hex8(listCrc) + "\t" + std::to_string(enc.size()) + "\t" + LIST_FILE + "\n";
        addEntry(LIST_FILE, enc);
    }
    addEntry("__pkmanifest.txt", PackCrypt::encrypt(manifest, true));
    uint32_t cdStart = (uint32_t)zip.size();
    for(auto& e : entries) {
        u32(zip, 0x02014b50); u16(zip, 20); u16(zip, 20); u16(zip, 0); u16(zip, 0);
        u16(zip, 0); u16(zip, 0x5A21);
        u32(zip, e.crc); u32(zip, e.size); u32(zip, e.size);
        u16(zip, (uint16_t)e.name.size()); u16(zip, 0); u16(zip, 0); u16(zip, 0); u16(zip, 0);
        u32(zip, 0); u32(zip, e.offset);
        zip += e.name;
    }
    uint32_t cdSize = (uint32_t)zip.size() - cdStart;
    u32(zip, 0x06054b50); u16(zip, 0); u16(zip, 0);
    u16(zip, (uint16_t)entries.size()); u16(zip, (uint16_t)entries.size());
    u32(zip, cdSize); u32(zip, cdStart); u16(zip, 0);
    writeAll(outPath, zip);
    std::cout << entries.size() << " arquivos, " << (original / 1024) << " KB originais -> "
              << (zip.size() / 1024) << " KB em " << outPath << "\n";
    return 0;
}

struct PubInfo { std::string crc; std::string size; };

static int publish(const std::string& root, const std::string& site, const std::string& exePath, std::vector<std::string> items)
{
    FileList files = collect(root, items);
    fs::path siteDir(site);
    fs::path filesDir = siteDir / "files";
    fs::create_directories(filesDir);

    // publicacao anterior: o que nao mudou nao e regravado
    std::map<std::string, PubInfo> old;
    fs::path manifestPath = siteDir / "manifest.txt";
    if(fs::exists(manifestPath)) {
        std::istringstream in(readAll(manifestPath.string()));
        std::string line;
        while(std::getline(in, line)) {
            if(line.size() < 3 || line[0] != 'F' || line[1] != '\t')
                continue;
            size_t a = line.find('\t', 2), b = line.find('\t', a + 1);
            if(b == std::string::npos)
                continue;
            old[line.substr(b + 1)] = {line.substr(2, a - 2), line.substr(a + 1, b - a - 1)};
        }
    }

    std::string manifest;
    int changed = 0, kept = 0;
    uint64_t changedBytes = 0;
    for(auto& f : files) {
        std::string data = readAll(f.second);
        std::string crc = hex8(crc32(0L, (const Bytef*)data.data(), (uInt)data.size()));
        fs::path out = filesDir / fs::path(f.first);
        auto o = old.find(f.first);
        if(o != old.end() && o->second.crc == crc && fs::exists(out) &&
           std::to_string(fs::file_size(out)) == o->second.size) {
            manifest += "F\t" + crc + "\t" + o->second.size + "\t" + f.first + "\n";
            old.erase(o);
            ++kept;
            continue;
        }
        if(o != old.end())
            old.erase(o);
        std::string enc = PackCrypt::encrypt(data, true);
        fs::create_directories(out.parent_path());
        writeAll(out.string(), enc);
        manifest += "F\t" + crc + "\t" + std::to_string(enc.size()) + "\t" + f.first + "\n";
        std::cout << "  atualizado: " << f.first << "\n";
        ++changed;
        changedBytes += enc.size();
    }
    {
        std::string list = fileList(files);
        std::string crc = hex8(crc32(0L, (const Bytef*)list.data(), (uInt)list.size()));
        fs::path out = filesDir / LIST_FILE;
        auto o = old.find(LIST_FILE);
        if(o != old.end() && o->second.crc == crc && fs::exists(out) && std::to_string(fs::file_size(out)) == o->second.size) {
            manifest += "F\t" + crc + "\t" + o->second.size + "\t" + LIST_FILE + "\n";
        } else {
            std::string enc = PackCrypt::encrypt(list, true);
            writeAll(out.string(), enc);
            manifest += "F\t" + crc + "\t" + std::to_string(enc.size()) + "\t" + LIST_FILE + "\n";
            ++changed;
        }
        if(o != old.end())
            old.erase(o);
    }
    // arquivos que sairam do cliente
    for(auto& o : old) {
        fs::path out = filesDir / fs::path(o.first);
        if(fs::exists(out))
            fs::remove(out);
    }

    if(!exePath.empty()) {
        std::string exe = readAll(exePath);
        uint32_t crc = crc32(0L, (const Bytef*)exe.data(), (uInt)exe.size());
        writeAll((filesDir / "client.exe").string(), exe);
        manifest += "E\t" + hex8(crc) + "\t" + std::to_string(exe.size()) + "\tclient.exe\n";
        std::cout << "  executavel: " << exePath << "\n";
    }

    writeAll(manifestPath.string(), manifest);
    std::cout << files.size() << " arquivos na lista: " << changed << " novos/alterados ("
              << (changedBytes / 1024) << " KB), " << kept << " iguais. Suba a pasta " << site << " no site.\n";
    return 0;
}

static int newKey()
{
    unsigned char a[32], b[32];
    if(RAND_bytes(a, 32) != 1 || RAND_bytes(b, 32) != 1)
        return 1;
    auto dump = [](const char* name, unsigned char* k) {
        printf("static const unsigned char %s[32] = {\n    ", name);
        for(int i = 0; i < 32; ++i)
            printf("0x%02x%s", k[i], i == 31 ? "\n" : (i == 15 ? ",\n    " : ", "));
        printf("};\n");
    };
    printf("/* Chave gerada pelo pkpacker --newkey. GUARDE UMA COPIA DESTE ARQUIVO. */\n");
    printf("#ifndef PACKKEY_H\n#define PACKKEY_H\n\n");
    dump("PACK_KEY_A", a);
    dump("PACK_KEY_B", b);
    printf("\n#endif\n");
    return 0;
}

int main(int argc, char* argv[])
{
    try {
        std::vector<std::string> args(argv + 1, argv + argc);
        if(args.size() == 1 && args[0] == "--newkey")
            return newKey();
        if(args.size() == 4 && args[0] == "--colar") {
            std::string exe = readAll(args[1]);
            std::string zip = readAll(args[2]);
            writeAll(args[3], exe + zip);
            std::cout << "Pronto: " << args[3] << " (" << ((exe.size() + zip.size()) / 1024) << " KB)\n";
            return 0;
        }
        if(args.size() >= 3 && args[0] == "--publicar") {
            std::string exe;
            std::vector<std::string> items;
            for(size_t i = 3; i < args.size(); ++i) {
                if(args[i] == "--exe" && i + 1 < args.size())
                    exe = args[++i];
                else
                    items.push_back(args[i]);
            }
            return publish(args[1], args[2], exe, items);
        }
        if(args.size() == 3 && args[0] == "--abrir") {
            writeAll(args[2], PackCrypt::decrypt(readAll(args[1])));
            std::cout << "Descriptografado em " << args[2] << "\n";
            return 0;
        }
        if(args.size() >= 2 && args[0].rfind("--", 0) != 0) {
            std::vector<std::string> items(args.begin() + 2, args.end());
            return pack(args[0], args[1], items);
        }
        std::cout << "Uso:\n"
                     "  pkpacker --newkey > packkey.h\n"
                     "  pkpacker <pasta do cliente> <saida.zip> [itens...]\n"
                     "  pkpacker --publicar <pasta do cliente> <pasta do site> [--exe <arquivo.exe>] [itens...]\n"
                     "  pkpacker --colar <otclient.exe> <data.zip> <saida.exe>\n"
                     "  pkpacker --abrir <arquivo> <saida>\n";
        return 1;
    } catch(std::exception& e) {
        std::cerr << "ERRO: " << e.what() << "\n";
        return 2;
    }
}
