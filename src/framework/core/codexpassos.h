#pragma once
// CODEX: diagnostico da abertura. So grava se existir o arquivo "codex_debug.txt"
// na pasta do cliente; ai cada passo vai para codex_passos.txt (abre/fecha a cada
// linha, para o texto ficar salvo mesmo se o programa travar logo depois).
#include <cstdio>
#include <ctime>
inline bool codexDebugAtivo()
{
#if !defined(ANDROID) && !defined(__EMSCRIPTEN__)
    static const bool ativo = [] {
        FILE* f = std::fopen("codex_debug.txt", "r");
        if (!f) return false;
        std::fclose(f);
        return true;
    }();
    return ativo;
#else
    return false;
#endif
}
inline void codexPasso(const char* passo)
{
    if (!codexDebugAtivo()) return;
    static bool primeiro = true;
    FILE* f = std::fopen("codex_passos.txt", primeiro ? "w" : "a");
    primeiro = false;
    if (!f) return;
    std::fprintf(f, "%ld %s\n", static_cast<long>(std::clock()), passo);
    std::fflush(f);
    std::fclose(f);
}
