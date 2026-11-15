#include "packcrypt.h"
#include "packkey.h"

#include <openssl/evp.h>
#include <openssl/rand.h>
#include <zlib.h>
#include <cstring>
#include <stdexcept>

namespace {

void getKey(unsigned char key[32])
{
    for(int i = 0; i < 32; ++i)
        key[i] = PACK_KEY_A[i] ^ PACK_KEY_B[i];
}

std::string aesCtr(const std::string& in, const unsigned char iv[16])
{
    unsigned char key[32];
    getKey(key);
    std::string out(in.size(), '\0');
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if(!ctx)
        throw std::runtime_error("PackCrypt: EVP_CIPHER_CTX_new");
    int len = 0, total = 0;
    bool ok = EVP_EncryptInit_ex(ctx, EVP_aes_256_ctr(), nullptr, key, iv) == 1;
    if(ok && !in.empty())
        ok = EVP_EncryptUpdate(ctx, (unsigned char*)&out[0], &len, (const unsigned char*)in.data(), (int)in.size()) == 1;
    total = len;
    if(ok)
        ok = EVP_EncryptFinal_ex(ctx, (unsigned char*)&out[0] + total, &len) == 1;
    EVP_CIPHER_CTX_free(ctx);
    memset(key, 0, sizeof(key));
    if(!ok)
        throw std::runtime_error("PackCrypt: falha no AES");
    return out;
}

void putU32(std::string& s, uint32_t v)
{
    for(int i = 0; i < 4; ++i)
        s.push_back((char)((v >> (8 * i)) & 0xFF));
}

uint32_t getU32(const char* p)
{
    return (uint32_t)(unsigned char)p[0] | ((uint32_t)(unsigned char)p[1] << 8) |
           ((uint32_t)(unsigned char)p[2] << 16) | ((uint32_t)(unsigned char)p[3] << 24);
}

}

namespace PackCrypt {

bool isEncrypted(const char* data, size_t size)
{
    return size >= HEADER_SIZE && memcmp(data, MAGIC, 4) == 0;
}

bool isEncrypted(const std::string& data)
{
    return isEncrypted(data.data(), data.size());
}

std::string encrypt(const std::string& data, bool compress)
{
    std::string payload = data;
    unsigned char flags = 0;
    if(compress && !data.empty()) {
        uLongf bound = compressBound((uLong)data.size());
        std::string packed(bound, '\0');
        if(compress2((Bytef*)&packed[0], &bound, (const Bytef*)data.data(), (uLong)data.size(), 9) == Z_OK && bound < data.size()) {
            packed.resize(bound);
            payload.swap(packed);
            flags |= 1;
        }
    }
    unsigned char iv[16];
    if(RAND_bytes(iv, 16) != 1)
        throw std::runtime_error("PackCrypt: RAND_bytes");

    std::string out(MAGIC, 4);
    out.push_back((char)flags);
    putU32(out, (uint32_t)data.size());
    out.append((const char*)iv, 16);
    out += aesCtr(payload, iv);
    return out;
}

std::string decrypt(const std::string& data)
{
    if(!isEncrypted(data))
        return data;
    unsigned char flags = (unsigned char)data[4];
    uint32_t originalSize = getU32(&data[5]);
    unsigned char iv[16];
    memcpy(iv, &data[9], 16);
    std::string payload = aesCtr(data.substr(HEADER_SIZE), iv);
    if(!(flags & 1))
        return payload;
    std::string out(originalSize, '\0');
    uLongf outLen = originalSize;
    if(originalSize > 0 &&
       uncompress((Bytef*)&out[0], &outLen, (const Bytef*)payload.data(), (uLong)payload.size()) != Z_OK)
        throw std::runtime_error("PackCrypt: arquivo corrompido ou chave errada");
    out.resize(outLen);
    return out;
}

}
