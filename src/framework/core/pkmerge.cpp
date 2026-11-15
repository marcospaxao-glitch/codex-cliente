#include "pkmerge.h"
#include "packcrypt.h"

#include <filesystem>
#include <set>
#include <zlib.h>

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <map>
#include <sstream>
#include <thread>
#include <chrono>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

namespace fs = std::filesystem;

namespace {

#ifdef _WIN32
std::wstring widen(const std::string& s)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, NULL, 0);
    std::wstring w(n > 0 ? n - 1 : 0, L'\0');
    if(n > 1)
        MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, &w[0], n);
    return w;
}
fs::path toPath(const std::string& s) { return fs::path(widen(s)); }
FILE* openFile(const std::string& path, const char* mode)
{
    std::wstring m(mode, mode + strlen(mode));
    return _wfopen(widen(path).c_str(), m.c_str());
}
bool seekTo(FILE* f, uint64_t pos) { return _fseeki64(f, (long long)pos, SEEK_SET) == 0; }
uint64_t fileSize(FILE* f) { _fseeki64(f, 0, SEEK_END); return (uint64_t)_ftelli64(f); }
bool replaceFile(const std::string& from, const std::string& to)
{
    return MoveFileExW(widen(from).c_str(), widen(to).c_str(), MOVEFILE_REPLACE_EXISTING) != 0;
}
#else
fs::path toPath(const std::string& s) { return fs::path(s); }
FILE* openFile(const std::string& path, const char* mode) { return fopen(path.c_str(), mode); }
bool seekTo(FILE* f, uint64_t pos) { return fseeko(f, (off_t)pos, SEEK_SET) == 0; }
uint64_t fileSize(FILE* f) { fseeko(f, 0, SEEK_END); return (uint64_t)ftello(f); }
bool replaceFile(const std::string& from, const std::string& to) { return rename(from.c_str(), to.c_str()) == 0; }
#endif

uint16_t rd16(const unsigned char* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
uint32_t rd32(const unsigned char* p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
void put16(std::string& s, uint16_t v) { s.push_back((char)(v & 0xFF)); s.push_back((char)(v >> 8)); }
void put32(std::string& s, uint32_t v) { for(int i = 0; i < 4; ++i) s.push_back((char)((v >> (8 * i)) & 0xFF)); }

struct ZipEntry { std::string name; uint32_t crc, size, localOffset; };

// le o diretorio central do zip gerado pelo pkpacker (sem compressao)
bool readEntries(FILE* f, std::vector<ZipEntry>& out)
{
    uint64_t size = fileSize(f);
    if(size < 22) return false;
    unsigned char eocd[22];
    if(!seekTo(f, size - 22) || fread(eocd, 1, 22, f) != 22 || rd32(eocd) != 0x06054b50)
        return false;
    uint16_t count = rd16(eocd + 10);
    uint32_t cdSize = rd32(eocd + 12), cdOffset = rd32(eocd + 16);
    std::vector<unsigned char> cd(cdSize);
    if(cdSize == 0 || !seekTo(f, cdOffset) || fread(cd.data(), 1, cdSize, f) != cdSize)
        return false;
    size_t pos = 0;
    for(uint16_t i = 0; i < count; ++i) {
        if(pos + 46 > cd.size() || rd32(&cd[pos]) != 0x02014b50) return false;
        ZipEntry e;
        e.crc = rd32(&cd[pos + 16]);
        e.size = rd32(&cd[pos + 20]);
        uint16_t nameLen = rd16(&cd[pos + 28]), extraLen = rd16(&cd[pos + 30]), commentLen = rd16(&cd[pos + 32]);
        e.localOffset = rd32(&cd[pos + 42]);
        if(pos + 46 + nameLen > cd.size()) return false;
        e.name.assign((const char*)&cd[pos + 46], nameLen);
        pos += 46 + nameLen + extraLen + commentLen;
        out.push_back(e);
    }
    return true;
}

bool readEntryData(FILE* f, const ZipEntry& e, std::string& out)
{
    unsigned char lh[30];
    if(!seekTo(f, e.localOffset) || fread(lh, 1, 30, f) != 30 || rd32(lh) != 0x04034b50)
        return false;
    uint64_t dataPos = (uint64_t)e.localOffset + 30 + rd16(lh + 26) + rd16(lh + 28);
    out.resize(e.size);
    return seekTo(f, dataPos) && (e.size == 0 || fread(&out[0], 1, e.size, f) == e.size);
}

bool readWhole(const std::string& path, std::string& out)
{
    FILE* f = openFile(path, "rb");
    if(!f) return false;
    uint64_t size = fileSize(f);
    out.resize((size_t)size);
    bool ok = seekTo(f, 0) && (size == 0 || fread(&out[0], 1, (size_t)size, f) == size);
    fclose(f);
    return ok;
}

class ZipWriter {
public:
    explicit ZipWriter(FILE* f) : m_f(f) {}
    bool add(const std::string& name, const std::string& data)
    {
        ZipEntry e;
        e.name = name;
        e.crc = crc32(0L, (const Bytef*)data.data(), (uInt)data.size());
        e.size = (uint32_t)data.size();
        e.localOffset = (uint32_t)m_pos;
        std::string h;
        put32(h, 0x04034b50); put16(h, 20); put16(h, 0); put16(h, 0);
        put16(h, 0); put16(h, 0x5A21);
        put32(h, e.crc); put32(h, e.size); put32(h, e.size);
        put16(h, (uint16_t)name.size()); put16(h, 0);
        h += name;
        if(!write(h) || !write(data)) return false;
        m_entries.push_back(e);
        return m_pos < 0xF0000000ull;
    }
    bool finish()
    {
        uint32_t cdStart = (uint32_t)m_pos;
        std::string cd;
        for(auto& e : m_entries) {
            put32(cd, 0x02014b50); put16(cd, 20); put16(cd, 20); put16(cd, 0); put16(cd, 0);
            put16(cd, 0); put16(cd, 0x5A21);
            put32(cd, e.crc); put32(cd, e.size); put32(cd, e.size);
            put16(cd, (uint16_t)e.name.size()); put16(cd, 0); put16(cd, 0); put16(cd, 0); put16(cd, 0);
            put32(cd, 0); put32(cd, e.localOffset);
            cd += e.name;
        }
        std::string end;
        put32(end, 0x06054b50); put16(end, 0); put16(end, 0);
        put16(end, (uint16_t)m_entries.size()); put16(end, (uint16_t)m_entries.size());
        put32(end, (uint32_t)cd.size()); put32(end, cdStart); put16(end, 0);
        return m_entries.size() < 0xFFFF && write(cd) && write(end);
    }
private:
    bool write(const std::string& d)
    {
        if(!d.empty() && fwrite(d.data(), 1, d.size(), m_f) != d.size()) return false;
        m_pos += d.size();
        return true;
    }
    FILE* m_f;
    uint64_t m_pos = 0;
    std::vector<ZipEntry> m_entries;
};

// "F\t<crc>\t<tamanho>\t<caminho>" -> mapa caminho -> linha
void parseLines(const std::string& text, std::string& build, std::map<std::string, std::string>& files)
{
    std::istringstream in(text);
    std::string line;
    while(std::getline(in, line)) {
        if(!line.empty() && line.back() == '\r') line.pop_back();
        if(line.size() < 3 || line[1] != '\t') continue;
        if(line[0] == 'B') { build = line.substr(2); continue; }
        if(line[0] != 'F') continue;
        size_t a = line.find('\t', 2), b = a == std::string::npos ? a : line.find('\t', a + 1);
        if(b != std::string::npos) files[line.substr(b + 1)] = line;
    }
}

const std::string LIST_FILE = "codex_arquivos.txt";

bool fail(std::string* error, const std::string& msg)
{
    if(error) *error = msg;
    return false;
}

}

namespace PkMerge {

bool mergeUpdates(const std::string& baseDirIn, const std::string& package, std::string* error)
{
    std::string baseDir = baseDirIn;
    for(char& c : baseDir) if(c == '\\') c = '/';
    if(!baseDir.empty() && baseDir.back() != '/') baseDir += '/';

    const std::string datPath = baseDir + package;
    const std::string newPath = datPath + ".new";
    const std::string updatesDir = baseDir + "updates";
    std::error_code ec;

    // sobra de uma juncao anterior que nao conseguiu trocar o arquivo
    if(fs::exists(toPath(newPath), ec)) {
        bool swapped = false;
        for(int i = 0; i < 25 && !swapped; ++i) {
            swapped = replaceFile(newPath, datPath);
            if(!swapped) std::this_thread::sleep_for(std::chrono::milliseconds(200));
        }
        if(!swapped) return fail(error, "nao conseguiu trocar o pacote (em uso)");
    }

    if(!fs::is_directory(toPath(updatesDir), ec))
        return false;

    // arquivos baixados
    std::string stateText;
    readWhole(updatesDir + "/__pkstate.txt", stateText);
    std::string overlayBuild;
    std::map<std::string, std::string> overlayLines;
    parseLines(stateText, overlayBuild, overlayLines);

    std::map<std::string, std::string> overlayFiles; // caminho no pacote -> caminho no disco
    for(auto& it : overlayLines) {
        std::string disk = updatesDir + "/" + it.first;
        if(fs::is_regular_file(toPath(disk), ec))
            overlayFiles[it.first] = disk;
    }
    if(overlayFiles.empty()) {
        fs::remove_all(toPath(updatesDir), ec);
        return false;
    }

    FILE* in = openFile(datPath, "rb");
    if(!in) return fail(error, "nao abriu " + package);
    std::vector<ZipEntry> entries;
    if(!readEntries(in, entries)) {
        fclose(in);
        return fail(error, "pacote invalido");
    }

    // manifesto interno atualizado com as versoes baixadas
    std::string baseBuild, manifestText, listText;
    std::map<std::string, std::string> baseLines;
    for(auto& e : entries) {
        if(e.name == "__pkmanifest.txt" || (e.name == LIST_FILE && !overlayFiles.count(LIST_FILE))) {
            std::string raw;
            if(readEntryData(in, e, raw)) {
                std::string plain;
                try { plain = PackCrypt::decrypt(raw); } catch(...) { plain.clear(); }
                (e.name == LIST_FILE ? listText : manifestText) = plain;
            }
        }
    }
    if(overlayFiles.count(LIST_FILE)) {
        std::string raw;
        if(readWhole(overlayFiles[LIST_FILE], raw)) {
            try { listText = PackCrypt::decrypt(raw); } catch(...) { listText.clear(); }
        }
    }
    // CODEX: lista completa do cliente (gerada pelo pkpacker): o que nao esta nela saiu do cliente
    std::set<std::string> keep;
    {
        std::istringstream ls(listText);
        std::string l;
        while(std::getline(ls, l)) {
            if(!l.empty() && l.back() == '\r') l.pop_back();
            if(!l.empty()) keep.insert(l);
        }
    }
    const bool prune = keep.count("init.lua") > 0; // lista valida (sempre tem o init.lua)
    parseLines(manifestText, baseBuild, baseLines);
    for(auto& it : overlayFiles)
        baseLines[it.first] = overlayLines[it.first];
    if(prune) {
        for(auto it = baseLines.begin(); it != baseLines.end();)
            it = (keep.count(it->first) || it->first == LIST_FILE) ? std::next(it) : baseLines.erase(it);
    }
    std::string manifest = "B\t" + baseBuild + "\n";
    for(auto& it : baseLines)
        manifest += it.second + "\n";

    FILE* out = openFile(newPath, "wb");
    if(!out) {
        fclose(in);
        return fail(error, "sem permissao para gravar na pasta do jogo");
    }
    ZipWriter zip(out);
    bool ok = true;
    std::string data;
    for(auto& e : entries) {
        if(e.name == "__pkmanifest.txt" || overlayFiles.count(e.name))
            continue;
        if(prune && !keep.count(e.name) && e.name != LIST_FILE)
            continue; // CODEX: arquivo que saiu do cliente
        if(!readEntryData(in, e, data) || !zip.add(e.name, data)) { ok = false; break; }
    }
    for(auto& it : overlayFiles) {
        if(!ok) break;
        if(!readWhole(it.second, data) || !PackCrypt::isEncrypted(data) || !zip.add(it.first, data))
            ok = false;
    }
    if(ok)
        ok = zip.add("__pkmanifest.txt", PackCrypt::encrypt(manifest, true)) && zip.finish();
    fclose(in);
    if(fclose(out) != 0) ok = false;

    if(!ok) {
        fs::remove(toPath(newPath), ec);
        return fail(error, "falha ao juntar as atualizacoes");
    }

    bool swapped = false;
    for(int i = 0; i < 25 && !swapped; ++i) {
        swapped = replaceFile(newPath, datPath);
        if(!swapped) std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    if(!swapped)
        return fail(error, "nao conseguiu trocar o pacote (em uso); tenta de novo na proxima vez");

    fs::remove_all(toPath(updatesDir), ec);
    return true;
}

}
