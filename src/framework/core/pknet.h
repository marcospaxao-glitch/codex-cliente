/*
 * pknet - rede e arquivos para o atualizador (sem dependencias de C++)
 * Todos os caminhos sao UTF-8. Retornos: 1 = ok, 0 = falha.
 */
#ifndef PKNET_H
#define PKNET_H

// chamado a cada pedaco baixado; retorne 0 para cancelar
typedef int (*PkNetProgress)(void* user, unsigned int bytes);

// certificados (PEM) para https fora do Windows; vazio = sem verificar
void pknet_setCaFile(const char* path);

int pknet_download(const char* url, const char* destPath, PkNetProgress cb, void* user, char* err, int errLen);

int pkfs_move(const char* from, const char* to);   // substitui o destino
int pkfs_remove(const char* path);
int pkfs_mkdirs(const char* dirPath);              // cria a pasta e as de cima
int pkfs_exists(const char* path);
int pkfs_exePath(char* out, int outLen);           // caminho completo do .exe
// le o arquivo inteiro (libere com pkfs_free)
int pkfs_readAll(const char* path, char** outBuf, long long* outLen);
void pkfs_free(char* buf);
// le so os primeiros n bytes; retorna quantos leu (0 = falha)
int pkfs_readHead(const char* path, char* buf, int n);
int pkfs_writeAll(const char* path, const char* buf, long long len);

#endif
