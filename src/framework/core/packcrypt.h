/*
 * Arquivos criptografados do cliente (sprites, dat, scripts, imagens...)
 *
 * Formato de cada arquivo:
 *   "PKF1" | flags(1) | tamanho original(4, LE) | IV(16) | dados
 *   dados = AES-256-CTR( zlib(original) se flags&1, senao original )
 * Arquivos sem o cabecalho "PKF1" sao lidos normalmente.
 */
#ifndef PACKCRYPT_H
#define PACKCRYPT_H

#include <string>

namespace PackCrypt {
    static const char MAGIC[4] = { 'P', 'K', 'F', '1' };
    static const size_t HEADER_SIZE = 4 + 1 + 4 + 16;

    bool isEncrypted(const std::string& data);
    bool isEncrypted(const char* data, size_t size);
    // devolve o conteudo original (lanca excecao se estiver corrompido)
    std::string decrypt(const std::string& data);
    // usado pelo pkpacker
    std::string encrypt(const std::string& data, bool compress);
}

#endif
