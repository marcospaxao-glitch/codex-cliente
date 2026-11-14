#pragma once
// CODEX: grava cada passo da abertura em codex_passos.txt (abre/fecha o arquivo a
// cada linha, para o texto ficar salvo mesmo se o programa travar logo depois).
#include <cstdio>
#include <ctime>
inline void codexPasso(const char* passo)
{
#if !defined(ANDROID) && !defined(__EMSCRIPTEN__)
    static bool primeiro = true;
    FILE* f = std::fopen("codex_passos.txt", primeiro ? "w" : "a");
    primeiro = false;
    if (!f) return;
    std::fprintf(f, "%ld %s\n", static_cast<long>(std::clock()), passo);
    std::fflush(f);
    std::fclose(f);
#else
    (void)passo;
#endif
}
