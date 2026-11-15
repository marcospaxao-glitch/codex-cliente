// pknet fora do Windows (navegador, Android, Linux). "file:///caminho" tambem funciona.
#ifndef _WIN32
#include "pknet.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

#ifdef __EMSCRIPTEN__
#include <emscripten/fetch.h>
#endif
#if !defined(__EMSCRIPTEN__) && __has_include(<httplib.h>)
#define CODEX_PKNET_HTTPLIB 1
#ifndef CPPHTTPLIB_OPENSSL_SUPPORT
#define CPPHTTPLIB_OPENSSL_SUPPORT
#endif
#include <httplib.h>
#endif

static int pkFail(char* err, int errLen, const char* m)
{
    if(err && errLen > 0) snprintf(err, errLen, "%s", m);
    return 0;
}

static int pkCopyLocal(const char* url, const char* destPath, PkNetProgress cb, void* user, char* err, int errLen)
{
    std::string src = url + 7;
    for(size_t p; (p = src.find("%20")) != std::string::npos;) src.replace(p, 3, " ");
    FILE* in = fopen(src.c_str(), "rb");
    if(!in) return pkFail(err, errLen, "o site respondeu erro HTTP (404)");
    FILE* out = fopen(destPath, "wb");
    if(!out) { fclose(in); return pkFail(err, errLen, "nao criou o arquivo"); }
    char buf[65536];
    size_t n;
    int ok = 1;
    while((n = fread(buf, 1, sizeof(buf), in)) > 0) {
        if(fwrite(buf, 1, n, out) != n) { ok = 0; break; }
        if(cb && !cb(user, (unsigned)n)) { ok = 0; break; }
    }
    fclose(in); fclose(out);
    if(!ok) { remove(destPath); return pkFail(err, errLen, "interrompido"); }
    return 1;
}

// CODEX: baixa da internet fora do Windows (navegador: fetch sincrono; Android/Linux: httplib)
int pknet_download(const char* url, const char* destPath, PkNetProgress cb, void* user, char* err, int errLen)
{
    if(strncmp(url, "file://", 7) == 0)
        return pkCopyLocal(url, destPath, cb, user, err, errLen);
#if defined(__EMSCRIPTEN__)
    emscripten_fetch_attr_t attr;
    emscripten_fetch_attr_init(&attr);
    strcpy(attr.requestMethod, "GET");
    attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY | EMSCRIPTEN_FETCH_SYNCHRONOUS | EMSCRIPTEN_FETCH_REPLACE;
    static const char* headers[] = { "Cache-Control", "no-cache", nullptr };
    attr.requestHeaders = headers;
    emscripten_fetch_t* f = emscripten_fetch(&attr, url);
    if(!f) return pkFail(err, errLen, "falha de rede");
    if(f->status != 200) {
        char m[64];
        snprintf(m, sizeof(m), "o site respondeu erro HTTP (%d)", (int)f->status);
        emscripten_fetch_close(f);
        return pkFail(err, errLen, m);
    }
    FILE* out = fopen(destPath, "wb");
    if(!out) { emscripten_fetch_close(f); return pkFail(err, errLen, "nao criou o arquivo"); }
    int ok = f->numBytes == 0 || fwrite(f->data, 1, (size_t)f->numBytes, out) == (size_t)f->numBytes;
    fclose(out);
    if(ok && cb) cb(user, (unsigned)f->numBytes);
    emscripten_fetch_close(f);
    if(!ok) { remove(destPath); return pkFail(err, errLen, "falha ao gravar"); }
    return 1;
#elif defined(CODEX_PKNET_HTTPLIB)
    std::string u = url;
    size_t sep = u.find("://");
    if(sep == std::string::npos) return pkFail(err, errLen, "endereco invalido");
    size_t slash = u.find('/', sep + 3);
    std::string host = u.substr(0, slash == std::string::npos ? u.size() : slash);
    std::string path = slash == std::string::npos ? "/" : u.substr(slash);
    httplib::Client cli(host);
    cli.set_follow_location(true);
    cli.set_connection_timeout(15);
    cli.set_read_timeout(30);
    FILE* out = fopen(destPath, "wb");
    if(!out) return pkFail(err, errLen, "nao criou o arquivo");
    bool writeOk = true;
    auto res = cli.Get(path, httplib::Headers{ { "Cache-Control", "no-cache" } },
        [&](const char* data, size_t len) {
            if(fwrite(data, 1, len, out) != len) { writeOk = false; return false; }
            return !cb || cb(user, (unsigned)len) != 0;
        });
    fclose(out);
    if(!res || res->status != 200 || !writeOk) {
        remove(destPath);
        char m[64];
        snprintf(m, sizeof(m), "o site respondeu erro HTTP (%d)", res ? res->status : 0);
        return pkFail(err, errLen, m);
    }
    return 1;
#else
    return pkFail(err, errLen, "download nao suportado nesta plataforma");
#endif
}

int pkfs_move(const char* from, const char* to) { return rename(from, to) == 0; }
int pkfs_remove(const char* path) { return remove(path) == 0; }
int pkfs_exists(const char* path) { struct stat st; return stat(path, &st) == 0; }
int pkfs_mkdirs(const char* dirPath)
{
    std::string p = dirPath;
    for(size_t i = 1; i <= p.size(); ++i)
        if(i == p.size() || p[i] == '/')
            mkdir(p.substr(0, i).c_str(), 0755);
    return pkfs_exists(dirPath);
}
int pkfs_exePath(char* out, int outLen)
{
#if defined(__EMSCRIPTEN__) || defined(ANDROID)
    (void)out; (void)outLen;
    return 0; // sem .exe para trocar
#endif
    ssize_t n = readlink("/proc/self/exe", out, outLen - 1);
    if(n <= 0) return 0;
    out[n] = 0;
    return 1;
}
int pkfs_readAll(const char* path, char** outBuf, long long* outLen)
{
    FILE* f = fopen(path, "rb");
    if(!f) return 0;
    fseek(f, 0, SEEK_END);
    long long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char* buf = (char*)malloc(len + 1);
    if(!buf || fread(buf, 1, len, f) != (size_t)len) { free(buf); fclose(f); return 0; }
    fclose(f);
    buf[len] = 0;
    *outBuf = buf;
    *outLen = len;
    return 1;
}
void pkfs_free(char* buf) { free(buf); }
int pkfs_readHead(const char* path, char* buf, int n)
{
    FILE* f = fopen(path, "rb");
    if(!f) return 0;
    int got = (int)fread(buf, 1, n, f);
    fclose(f);
    return got;
}
int pkfs_writeAll(const char* path, const char* buf, long long len)
{
    FILE* f = fopen(path, "wb");
    if(!f) return 0;
    int ok = fwrite(buf, 1, len, f) == (size_t)len;
    fclose(f);
    return ok;
}
#endif
