/*
 * Junta a pasta "updates" (arquivos baixados pelo atualizador) dentro do
 * pacote do cliente (codex.dat) quando o jogo abre. Assim a pasta do jogo
 * fica so com o .exe e o .dat.
 */
#ifndef PKMERGE_H
#define PKMERGE_H

#include <string>

namespace PkMerge {
    // baseDir: pasta do .exe (UTF-8, com / no fim); package: "codex.dat"
    // Retorna true se juntou alguma coisa. Se der erro, nada e perdido:
    // a pasta updates continua valendo como antes.
    bool mergeUpdates(const std::string& baseDir, const std::string& package, std::string* error = nullptr);
}

#endif
