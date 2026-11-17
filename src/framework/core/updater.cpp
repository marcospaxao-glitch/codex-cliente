#include "updater.h"
#include "pknet.h"

#include <zlib.h>
#include <cctype>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <sstream>
#include <vector>

#ifndef UPDATER_STANDALONE
#include <framework/pch.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/application.h>
#include <framework/core/graphicalapplication.h>
#include <framework/platform/platform.h>
#endif
#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

#ifndef CLIENT_UPDATE_URL
#define CLIENT_UPDATE_URL "https://codexpoketibia.com.br/updates/"
#endif

Updater g_updater;

static const char* STATE_FILE = "__pkstate.txt";
static const char* EXE_REMOTE_NAME = "client.exe";

static std::string urlEncodePath(const std::string& path)
{
    static const char* hex = "0123456789ABCDEF";
    std::string out;
    for(unsigned char c : path) {
        if(isalnum(c) || c == '/' || c == '-' || c == '_' || c == '.' || c == '~')
            out += (char)c;
        else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
    return out;
}

static bool readText(const std::string& path, std::string& out)
{
    char* buf = nullptr;
    long long len = 0;
    if(!pkfs_readAll(path.c_str(), &buf, &len))
        return false;
    out.assign(buf, (size_t)len);
    pkfs_free(buf);
    return true;
}

static bool fileCrc(const std::string& path, unsigned long& crc, long long& size)
{
    char* buf = nullptr;
    long long len = 0;
    if(!pkfs_readAll(path.c_str(), &buf, &len))
        return false;
    crc = crc32(0L, (const Bytef*)buf, (uInt)len);
    size = len;
    pkfs_free(buf);
    return true;
}

// caminho seguro: sem "..", sem barra no inicio, sem arquivos internos
static bool safePath(const std::string& p)
{
    if(p.empty() || p[0] == '/' || p[0] == '\\' || p.find("..") != std::string::npos || p.find(':') != std::string::npos)
        return false;
    if(p.compare(0, 2, "__") == 0)
        return false;
    return true;
}

static std::string dirOf(const std::string& path)
{
    size_t p = path.find_last_of("/\\");
    return p == std::string::npos ? std::string() : path.substr(0, p);
}

// linhas: "B\t<build>" | "F\t<crc>\t<tamanho>\t<caminho>" | "E\t<crc>\t<tamanho>\tclient.exe"
bool Updater::parseManifest(const std::string& text, FileMap& files, std::string* build, FileInfo* exe)
{
    std::istringstream in(text);
    std::string line;
    bool any = false;
    while(std::getline(in, line)) {
        if(!line.empty() && line.back() == '\r')
            line.pop_back();
        if(line.size() < 3 || line[1] != '\t')
            continue;
        char kind = line[0];
        if(kind == 'B') {
            if(build) *build = line.substr(2);
            any = true;
            continue;
        }
        size_t a = line.find('\t', 2);
        size_t b = a == std::string::npos ? a : line.find('\t', a + 1);
        if(b == std::string::npos)
            continue;
        FileInfo info;
        info.crc = strtoul(line.substr(2, a - 2).c_str(), nullptr, 16);
        info.size = strtoll(line.substr(a + 1, b - a - 1).c_str(), nullptr, 10);
        std::string path = line.substr(b + 1);
        if(kind == 'F') {
            files[path] = info;
            any = true;
        } else if(kind == 'E' && exe) {
            *exe = info;
            any = true;
        }
    }
    return any;
}

void Updater::setup(const std::string& baseDir, const std::string& url, const std::string& baseManifest, const std::string& exePath)
{
    m_baseDir = baseDir;
    for(char& c : m_baseDir)
        if(c == '\\') c = '/';
    if(!m_baseDir.empty() && m_baseDir.back() != '/')
        m_baseDir += '/';
    m_url = url;
    if(!m_url.empty() && m_url.back() != '/')
        m_url += '/';
    m_baseManifest = baseManifest;
    m_exePath = exePath;
}

void codexPrepararCertificados()
{
#if defined(ANDROID) && !defined(UPDATER_STANDALONE)
    static bool feito = false;
    if(feito)
        return;
    try {
        const std::string pem = g_resources.readFileContents("/cacert.pem");
        std::string dir = g_resources.getWriteDir();
        if(!dir.empty() && dir.back() != '/')
            dir += '/';
        const std::string dst = dir + "cacert.pem";
        if(!pem.empty() && pkfs_writeAll(dst.c_str(), pem.data(), (long long)pem.size()))
            pknet_setCaFile(dst.c_str());
        feito = true;
    } catch(...) {
    }
#endif
}

void Updater::start()
{
    codexPrepararCertificados();
#ifndef UPDATER_STANDALONE
    if(m_state == Checking || m_state == Downloading)
        return;
    if(m_thread.joinable())
        m_thread.join();

    std::string url = CLIENT_UPDATE_URL;
    std::string manifest;
#if defined(__EMSCRIPTEN__) || defined(ANDROID)
    // CODEX: navegador/Android: a base sao os arquivos que vieram com o cliente
    m_local = true;
#if defined(__EMSCRIPTEN__)
    url = "/updates/"; // mesmo site da pagina (com ou sem www)
#endif
    std::string baseDir = g_resources.getWriteDir();
    if(baseDir.empty()) {
        m_state = Disabled;
        return;
    }
    setup(baseDir, url, "", "");
#else
    m_local = false;
    if(g_resources.isPackaged()) {
        try {
            manifest = g_resources.readFileContents("/__pkmanifest.txt");
        } catch(...) {
        }
    }
    char exe[4096] = {0};
    pkfs_exePath(exe, sizeof(exe));
    setup(g_resources.getBaseDir(), url, manifest, exe);

    // sobra de uma troca de .exe anterior
    pkfs_remove((m_exePath + ".old").c_str());

    if(url.empty() || !g_resources.isPackaged() || manifest.empty()) {
        m_state = Disabled; // cliente de desenvolvimento (pastas soltas) ou sem URL
        return;
    }
#endif
    m_abort = false;
    m_needsRestart = false;
    m_bytesDone = m_bytesTotal = 0;
    m_filesDone = m_filesTotal = 0;
    m_state = Checking;
    m_thread = std::thread([this] { run(); });
#endif
}

void Updater::terminate()
{
    m_abort = true;
    if(m_thread.joinable())
        m_thread.join();
}

void Updater::restart()
{
#ifndef UPDATER_STANDALONE
    terminate();
#if defined(__EMSCRIPTEN__)
    // CODEX: grava o que foi baixado no armazenamento do navegador e recarrega a pagina
    MAIN_THREAD_ASYNC_EM_ASM({
        try { FS.syncfs(false, function() { location.reload(); }); } catch (e) { location.reload(); }
    });
    return;
#elif defined(ANDROID)
    g_app.exit();
    return;
#endif
    std::string exe = m_exePath;
    if(exe.empty()) {
        char buf[4096] = {0};
        pkfs_exePath(buf, sizeof(buf));
        exe = buf;
    }
    g_platform.spawnProcess(exe, {});
    g_app.exit();
#endif
}

std::string Updater::getError()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_error;
}

std::string Updater::getCurrentFile()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_currentFile;
}

std::string Updater::getUrl()
{
    return m_url.empty() ? std::string(CLIENT_UPDATE_URL) : m_url;
}

bool Updater::fail(const std::string& msg)
{
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_error = msg;
    }
    m_state = Failed;
    return false;
}

int Updater::onProgress(void* user, unsigned int bytes)
{
    Updater* self = (Updater*)user;
    self->m_bytesDone += bytes;
    return self->m_abort ? 0 : 1;
}

bool Updater::download(const std::string& url, const std::string& dest, std::string& err)
{
    char buf[512] = {0};
    if(pknet_download(url.c_str(), dest.c_str(), &Updater::onProgress, this, buf, sizeof(buf)))
        return true;
    err = buf;
    return false;
}

void Updater::saveState(const FileMap& overlay, const std::string& build)
{
    std::string out = "B\t" + build + "\n";
    char line[64];
    for(auto& it : overlay) {
        snprintf(line, sizeof(line), "F\t%08lx\t%lld\t", it.second.crc, it.second.size);
        out += line + it.first + "\n";
    }
    std::string path = m_baseDir + "updates/" + STATE_FILE;
    std::string tmp = path + ".tmp";
    if(pkfs_writeAll(tmp.c_str(), out.data(), (long long)out.size()))
        pkfs_move(tmp.c_str(), path.c_str());
}

// CODEX: caminho do manifesto -> caminho no cliente (data/, modules/ e mods/ ficam montados na raiz)
static bool localVirtualPath(const std::string& path, std::string& out)
{
    for(const char* pre : { "data/", "modules/", "mods/" }) {
        size_t n = strlen(pre);
        if(path.compare(0, n, pre) == 0) {
            out = "/" + path.substr(n);
            return true;
        }
    }
    return false;
}

static bool localSkip(const std::string& path)
{
    std::string v;
    if(!localVirtualPath(path, v))
        return true; // init.lua, config.ini...: vem com o cliente
    std::string low = path;
    for(char& c : low) c = (char)tolower((unsigned char)c);
    return low.size() > 4 && low.compare(low.size() - 4, 4, ".spr") == 0; // sprites vem do site em blocos
}

static bool localCrc(const std::string& path, unsigned long& crc)
{
#ifndef UPDATER_STANDALONE
    std::string v;
    if(!localVirtualPath(path, v))
        return false;
    try {
        if(!g_resources.fileExists(v))
            return false;
        const std::string data = g_resources.readFileContents(v);
        crc = crc32(0L, (const Bytef*)data.data(), (uInt)data.size());
        return true;
    } catch(...) {
        return false;
    }
#else
    (void)path; (void)crc;
    return false;
#endif
}

void Updater::run()
{
    m_state = Checking;
    std::string updatesDir = m_baseDir + "updates/";
    if(!pkfs_mkdirs(updatesDir.substr(0, updatesDir.size() - 1).c_str()))
        return (void)fail("Sem permissao para gravar na pasta do jogo.");

    // 1) manifesto do site
    std::string remotePath = updatesDir + "__remote.tmp";
    std::string err;
    if(!download(m_url + "manifest.txt", remotePath, err))
        return (void)fail("Nao foi possivel verificar atualizacoes: " + err);
    m_bytesDone = 0;
    std::string remoteText;
    readText(remotePath, remoteText);
    pkfs_remove(remotePath.c_str());
    FileMap remote;
    FileInfo remoteExe{0, -1};
    if(!parseManifest(remoteText, remote, nullptr, &remoteExe))
        return (void)fail("Lista de atualizacao do site esta vazia ou invalida.");

    // CODEX: so aceita publicacao do cliente novo (o pkpacker novo sempre inclui a lista).
    // Enquanto o site tiver o cliente antigo, nao baixa nada (evita voltar modulos antigos).
    if(remote.find("codex_arquivos.txt") == remote.end()) {
        m_state = UpToDate;
        return;
    }

    // 2) o que o jogador ja tem: pokefans.dat + pasta updates
    FileMap base, overlay;
    std::string baseBuild, overlayBuild, stateText;
    parseManifest(m_baseManifest, base, &baseBuild, nullptr);
    if(readText(updatesDir + STATE_FILE, stateText))
        parseManifest(stateText, overlay, &overlayBuild, nullptr);

    bool changed = false;
    if(m_local) {
        // overlay que sumiu do disco
        for(auto it = overlay.begin(); it != overlay.end();) {
            if(!pkfs_exists((updatesDir + it->first).c_str())) {
                it = overlay.erase(it);
                changed = true;
            } else
                ++it;
        }
        // arquivos do proprio cliente: crc calculado na hora
        for(auto& it : remote) {
            if(localSkip(it.first) || overlay.count(it.first))
                continue;
            unsigned long crc = 0;
            if(localCrc(it.first, crc))
                base[it.first] = FileInfo{ crc, 0 };
        }
    } else if(!overlay.empty() && overlayBuild != baseBuild) {
        // pokefans.dat novo (reinstalacao): a pasta updates antiga nao vale mais
        for(auto& it : overlay)
            pkfs_remove((updatesDir + it.first).c_str());
        overlay.clear();
        changed = true;
    }
    for(auto it = overlay.begin(); !m_local && it != overlay.end();) {
        auto b = base.find(it->first);
        bool sameAsBase = b != base.end() && b->second.crc == it->second.crc;
        bool missing = !pkfs_exists((updatesDir + it->first).c_str());
        if(sameAsBase || missing) {
            pkfs_remove((updatesDir + it->first).c_str());
            it = overlay.erase(it);
            changed = true;
        } else
            ++it;
    }
    if(changed)
        saveState(overlay, baseBuild);

    // 3) diferencas
    std::vector<std::pair<std::string, FileInfo>> needed;
    long long total = 0;
    for(auto& it : remote) {
        if(!safePath(it.first))
            continue;
        if(m_local && localSkip(it.first))
            continue;
        auto o = overlay.find(it.first);
        unsigned long have = 0;
        bool exists = false;
        if(o != overlay.end()) {
            have = o->second.crc;
            exists = true;
        } else {
            auto b = base.find(it.first);
            if(b != base.end()) {
                have = b->second.crc;
                exists = true;
            }
        }
        if(!exists || have != it.second.crc) {
            needed.push_back(it);
            total += it.second.size;
        }
    }
    bool exeNeeded = false;
    if(!m_local && remoteExe.size > 0 && !m_exePath.empty()) {
        unsigned long crc = 0;
        long long size = 0;
        if(fileCrc(m_exePath, crc, size) && (crc != remoteExe.crc || size != remoteExe.size)) {
            exeNeeded = true;
            total += remoteExe.size;
        }
    }

    if(needed.empty() && !exeNeeded) {
        m_state = UpToDate;
        return;
    }

    // 4) baixa
    m_filesTotal = (int)needed.size() + (exeNeeded ? 1 : 0);
    m_bytesTotal = total;
    m_bytesDone = 0;
    m_state = Downloading;
    for(auto& it : needed) {
        if(m_abort)
            return (void)fail("Cancelado.");
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_currentFile = it.first;
        }
        std::string dest = updatesDir + it.first;
        std::string part = dest + ".part";
        pkfs_mkdirs(dirOf(dest).c_str());
        long long before = m_bytesDone;
        if(!download(m_url + "files/" + urlEncodePath(it.first), part, err))
            return (void)fail("Falha ao baixar " + it.first + ": " + err);
        long long got = m_bytesDone - before;
        char head[4] = {0};
        bool valid = got == it.second.size && pkfs_readHead(part.c_str(), head, 4) == 4 &&
                     head[0] == 'P' && head[1] == 'K' && head[2] == 'F' && head[3] == '1';
        if(!valid) {
            pkfs_remove(part.c_str());
            return (void)fail("Arquivo corrompido no site: " + it.first + " (publique de novo).");
        }
        if(!pkfs_move(part.c_str(), dest.c_str()))
            return (void)fail("Nao conseguiu gravar " + it.first + ".");
        overlay[it.first] = it.second;
        saveState(overlay, baseBuild);
        m_filesDone++;
    }

    if(exeNeeded) {
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_currentFile = EXE_REMOTE_NAME;
        }
        std::string fresh = m_exePath + ".new";
        if(!download(m_url + "files/" + EXE_REMOTE_NAME, fresh, err))
            return (void)fail("Falha ao baixar o executavel: " + err);
        unsigned long crc = 0;
        long long size = 0;
        if(!fileCrc(fresh, crc, size) || crc != remoteExe.crc || size != remoteExe.size) {
            pkfs_remove(fresh.c_str());
            return (void)fail("Executavel corrompido no site (publique de novo).");
        }
        std::string old = m_exePath + ".old";
        pkfs_remove(old.c_str());
        if(!pkfs_move(m_exePath.c_str(), old.c_str())) {
            pkfs_remove(fresh.c_str());
            return (void)fail("Nao conseguiu trocar o executavel (sem permissao na pasta?).");
        }
        if(!pkfs_move(fresh.c_str(), m_exePath.c_str())) {
            pkfs_move(old.c_str(), m_exePath.c_str());
            return (void)fail("Nao conseguiu trocar o executavel.");
        }
        m_filesDone++;
    }

    m_needsRestart = true;
    m_state = Updated;
}
