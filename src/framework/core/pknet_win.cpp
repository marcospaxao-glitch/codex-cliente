// pknet para Windows: WinINet (HTTP e HTTPS) + API de arquivos em UTF-16
#ifdef _WIN32
#include "pknet.h"

#include <windows.h>
#include <wininet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static wchar_t* toWide(const char* s)
{
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    if(n <= 0)
        return NULL;
    wchar_t* w = (wchar_t*)malloc(sizeof(wchar_t) * n);
    if(w)
        MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}

static void setErr(char* err, int errLen, const char* msg, unsigned long code)
{
    if(err && errLen > 0)
        _snprintf(err, errLen - 1, "%s (%lu)", msg, code), err[errLen - 1] = 0;
}

void pknet_setCaFile(const char*) {} // Windows usa os certificados do sistema (WinINet)

int pknet_download(const char* url, const char* destPath, PkNetProgress cb, void* user, char* err, int errLen)
{
    int ok = 0;
    HINTERNET net = NULL, req = NULL;
    HANDLE file = INVALID_HANDLE_VALUE;
    wchar_t* wurl = toWide(url);
    wchar_t* wdest = toWide(destPath);
    char buf[64 * 1024];
    DWORD status = 0, statusLen = sizeof(status), got = 0;

    if(!wurl || !wdest) { setErr(err, errLen, "caminho invalido", 0); goto done; }

    net = InternetOpenW(L"PokeFansUpdater/1.0", INTERNET_OPEN_TYPE_PRECONFIG, NULL, NULL, 0);
    if(!net) { setErr(err, errLen, "InternetOpen falhou", GetLastError()); goto done; }
    {
        DWORD timeout = 20000;
        InternetSetOptionW(net, INTERNET_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
        InternetSetOptionW(net, INTERNET_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));
    }
    req = InternetOpenUrlW(net, wurl, L"Cache-Control: no-cache\r\n", (DWORD)-1L,
                           INTERNET_FLAG_RELOAD | INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_PRAGMA_NOCACHE |
                           INTERNET_FLAG_KEEP_CONNECTION | INTERNET_FLAG_NO_UI, 0);
    if(!req) { setErr(err, errLen, "sem conexao com o site", GetLastError()); goto done; }

    if(HttpQueryInfoW(req, HTTP_QUERY_STATUS_CODE | HTTP_QUERY_FLAG_NUMBER, &status, &statusLen, NULL) && status != 200) {
        setErr(err, errLen, "o site respondeu erro HTTP", status);
        goto done;
    }

    file = CreateFileW(wdest, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if(file == INVALID_HANDLE_VALUE) { setErr(err, errLen, "nao criou o arquivo", GetLastError()); goto done; }

    for(;;) {
        DWORD written = 0;
        if(!InternetReadFile(req, buf, sizeof(buf), &got)) { setErr(err, errLen, "download interrompido", GetLastError()); goto done; }
        if(got == 0)
            break;
        if(!WriteFile(file, buf, got, &written, NULL) || written != got) { setErr(err, errLen, "disco cheio ou sem permissao", GetLastError()); goto done; }
        if(cb && !cb(user, got)) { setErr(err, errLen, "cancelado", 0); goto done; }
    }
    ok = 1;

done:
    if(file != INVALID_HANDLE_VALUE) {
        CloseHandle(file);
        if(!ok)
            DeleteFileW(wdest);
    }
    if(req) InternetCloseHandle(req);
    if(net) InternetCloseHandle(net);
    free(wurl);
    free(wdest);
    return ok;
}

int pkfs_move(const char* from, const char* to)
{
    wchar_t* a = toWide(from);
    wchar_t* b = toWide(to);
    int ok = a && b && MoveFileExW(a, b, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
    free(a); free(b);
    return ok ? 1 : 0;
}

int pkfs_remove(const char* path)
{
    wchar_t* w = toWide(path);
    int ok = w && DeleteFileW(w);
    free(w);
    return ok ? 1 : 0;
}

int pkfs_exists(const char* path)
{
    wchar_t* w = toWide(path);
    DWORD attr = w ? GetFileAttributesW(w) : INVALID_FILE_ATTRIBUTES;
    free(w);
    return attr != INVALID_FILE_ATTRIBUTES ? 1 : 0;
}

int pkfs_mkdirs(const char* dirPath)
{
    size_t len = strlen(dirPath);
    char* tmp = (char*)malloc(len + 1);
    size_t i;
    if(!tmp)
        return 0;
    memcpy(tmp, dirPath, len + 1);
    for(i = 1; i <= len; ++i) {
        if(tmp[i] == '/' || tmp[i] == '\\' || tmp[i] == 0) {
            char c = tmp[i];
            tmp[i] = 0;
            if(i > 2 || tmp[1] != ':') { // pula "C:"
                wchar_t* w = toWide(tmp);
                if(w) { CreateDirectoryW(w, NULL); free(w); }
            }
            tmp[i] = c;
        }
    }
    free(tmp);
    return pkfs_exists(dirPath);
}

int pkfs_exePath(char* out, int outLen)
{
    wchar_t w[MAX_PATH * 4];
    DWORD n = GetModuleFileNameW(NULL, w, MAX_PATH * 4);
    if(n == 0 || n >= MAX_PATH * 4)
        return 0;
    return WideCharToMultiByte(CP_UTF8, 0, w, -1, out, outLen, NULL, NULL) > 0 ? 1 : 0;
}

int pkfs_readAll(const char* path, char** outBuf, long long* outLen)
{
    wchar_t* w = toWide(path);
    HANDLE f = w ? CreateFileW(w, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL) : INVALID_HANDLE_VALUE;
    LARGE_INTEGER size;
    char* buf = NULL;
    long long pos = 0;
    free(w);
    if(f == INVALID_HANDLE_VALUE)
        return 0;
    if(!GetFileSizeEx(f, &size) || size.QuadPart > 0x7FFFFFFF) { CloseHandle(f); return 0; }
    buf = (char*)malloc((size_t)size.QuadPart + 1);
    if(!buf) { CloseHandle(f); return 0; }
    while(pos < size.QuadPart) {
        DWORD got = 0;
        DWORD want = (DWORD)((size.QuadPart - pos) > (1 << 20) ? (1 << 20) : (size.QuadPart - pos));
        if(!ReadFile(f, buf + pos, want, &got, NULL) || got == 0) { free(buf); CloseHandle(f); return 0; }
        pos += got;
    }
    CloseHandle(f);
    buf[pos] = 0;
    *outBuf = buf;
    *outLen = pos;
    return 1;
}

void pkfs_free(char* buf)
{
    free(buf);
}

int pkfs_readHead(const char* path, char* buf, int n)
{
    wchar_t* w = toWide(path);
    HANDLE f = w ? CreateFileW(w, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL) : INVALID_HANDLE_VALUE;
    DWORD got = 0;
    free(w);
    if(f == INVALID_HANDLE_VALUE)
        return 0;
    if(!ReadFile(f, buf, (DWORD)n, &got, NULL))
        got = 0;
    CloseHandle(f);
    return (int)got;
}

int pkfs_writeAll(const char* path, const char* buf, long long len)
{
    wchar_t* w = toWide(path);
    HANDLE f = w ? CreateFileW(w, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL) : INVALID_HANDLE_VALUE;
    DWORD written = 0;
    int ok;
    free(w);
    if(f == INVALID_HANDLE_VALUE)
        return 0;
    ok = WriteFile(f, buf, (DWORD)len, &written, NULL) && written == (DWORD)len;
    CloseHandle(f);
    return ok ? 1 : 0;
}
#endif
