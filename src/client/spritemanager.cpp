/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "spritemanager.h"

#include "game.h"
#include "gameconfig.h"
#include "spriteappearances.h"
#include "framework/core/asyncdispatcher.h"
#include "framework/core/filestream.h"
#include "framework/core/graphicalapplication.h"
#include "framework/core/resourcemanager.h"
#include "framework/graphics/image.h"

#if defined(__EMSCRIPTEN__) || defined(ANDROID)
#if defined(__EMSCRIPTEN__) || defined(ANDROID)
#include <emscripten/fetch.h>
#else
#include "framework/core/pknet.h"
#endif
#include <atomic>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/drawpoolmanager.h>
#include <thread>
#endif

SpriteManager g_sprites;

FileMetadata::FileMetadata(const FileStreamPtr& file) {
    offset = file->getU32();
    fileSize = file->getU32();
    fileName = file->getString();
    spriteId = std::stoi(fileName);
}

void SpriteManager::init() {}
void SpriteManager::terminate() { unload(); }

void SpriteManager::reload() {
    if (g_app.isEncrypted())
        return;

    if (m_lastFileName.empty())
        return;

    load();
}

void SpriteManager::load() {
    // CODEX: dentro do codex.dat o spr e criptografado e vira arquivo em memoria;
    // uma copia so (uma por thread estouraria a memoria)
    const bool umaCopia = g_resources.isPackaged();
    m_spritesFiles.clear();
    m_spritesFiles.resize(umaCopia ? 1 : g_asyncDispatcher->get_thread_count());
    if (g_app.isLoadingAsyncTexture() && !umaCopia) {
        for (auto& file : m_spritesFiles)
            file = std::make_unique<FileStream_m>(g_resources.openFile(m_lastFileName));
    } else (m_spritesFiles[0] = std::make_unique<FileStream_m>(g_resources.openFile(m_lastFileName)))->file->cache(true);
}

bool SpriteManager::loadSpr(std::string file)
{
    m_spritesCount = 0;
    m_signature = 0;
    m_loaded = false;
    m_spritesHd = false;
    m_remote = false;

    const auto cwmFile = g_resources.guessFilePath(file, "cwm");
    if (g_resources.fileExists(cwmFile)) {
        m_spritesHd = true;
        return loadCwmSpr(cwmFile);
    }

    const auto sprFile = g_resources.guessFilePath(file, "spr");
    if (g_resources.fileExists(sprFile)) {
        return loadRegularSpr(sprFile);
    }

#if defined(__EMSCRIPTEN__) || defined(ANDROID)
    // [codex] sem Tibia.spr local: baixa sob demanda do site
    return loadRemoteSpr();
#else
    return false;
#endif
}

bool SpriteManager::loadRegularSpr(std::string file)
{
    try {
        m_lastFileName = g_resources.guessFilePath(file, "spr");
        load();

        m_signature = getSpriteFile()->getU32();
        m_spritesCount = g_game.getFeature(Otc::GameSpritesU32) ? getSpriteFile()->getU32() : getSpriteFile()->getU16();
        m_spritesOffset = getSpriteFile()->tell();

        m_loaded = true;
        g_lua.callGlobalField("g_sprites", "onLoadSpr", file);
        return true;
    } catch (const stdext::exception& e) {
        g_logger.error("Failed to load sprites from '{}': {}", file, e.what());
        return false;
    }
}

bool SpriteManager::loadCwmSpr(std::string file)
{
    m_cwmSpritesMetadata.clear();

    if (g_gameConfig.getSpriteSize() <= 32) {
        g_logger.error("Change your sprite size to 64x64 or larger for CWM support '{}'", file);
        return false;
    }

    try {
        m_lastFileName = g_resources.guessFilePath(file, "cwm");
        load();

        const auto& spritesFile = getSpriteFile();

        const uint8_t version = spritesFile->getU8();
        if (version != 0x01) {
            g_logger.error("Invalid CWM file version - {}", file);
            return false;
        }

        m_spritesCount = spritesFile->getU16();

        const uint32_t entries = spritesFile->getU32();
        m_cwmSpritesMetadata.reserve(entries);
        for (uint32_t i = 0; i < entries; ++i) {
            FileMetadata spriteMetadata{ spritesFile };
            m_cwmSpritesMetadata[spriteMetadata.getSpriteId()] = std::move(spriteMetadata);
        }

        m_spritesOffset = spritesFile->tell();

        if (m_spritesCount == 0) {
            g_logger.error("Failed to load sprites from '{}' - no sprites", file);
            return false;
        }

        m_loaded = true;
        g_lua.callGlobalField("g_sprites", "onLoadCWMSpr", file);
        return true;
    } catch (stdext::exception& e) {
        g_logger.error("Failed to load sprites from '{}': {}", file, e.what());
        return false;
    }
}

#ifdef FRAMEWORK_EDITOR
void SpriteManager::saveSpr(const std::string& fileName)
{
    if (!m_loaded)
        throw Exception("failed to save, spr is not loaded");

    static constexpr uint32_t SPRITE_SIZE = 32;
    static constexpr uint32_t SPRITE_DATA_SIZE = SPRITE_SIZE * SPRITE_SIZE * 4;

    try {
        const auto& fin = g_resources.createFile(fileName);
        if (!fin)
            throw Exception("failed to open file '{}' for write", fileName);

        fin->cache();

        fin->addU32(m_signature);
        if (g_game.getFeature(Otc::GameSpritesU32))
            fin->addU32(m_spritesCount);
        else
            fin->addU16(m_spritesCount);

        const uint32_t offset = fin->tell();
        uint32_t spriteAddress = offset + 4 * m_spritesCount;
        for (uint_fast32_t i = 1; i <= m_spritesCount; ++i)
            fin->addU32(0);

        for (uint_fast32_t i = 1; i <= m_spritesCount; ++i) {
            getSpriteFile()->seek((i - 1) * 4 + m_spritesOffset);
            const uint32_t fromAdress = getSpriteFile()->getU32();
            if (fromAdress != 0) {
                fin->seek(offset + (i - 1) * 4);
                fin->addU32(spriteAddress);
                fin->seek(spriteAddress);

                getSpriteFile()->seek(fromAdress);
                fin->addU8(getSpriteFile()->getU8());
                fin->addU8(getSpriteFile()->getU8());
                fin->addU8(getSpriteFile()->getU8());

                const uint16_t dataSize = getSpriteFile()->getU16();
                fin->addU16(dataSize);
                char spriteData[SPRITE_DATA_SIZE];
                getSpriteFile()->read(spriteData, dataSize);
                fin->write(spriteData, dataSize);

                spriteAddress = fin->tell();
            }
            //TODO: Check for overwritten sprites.
        }

        fin->flush();
        fin->close();
    } catch (const std::exception& e) {
        g_logger.error("Failed to save '{}': {}", fileName, e.what());
    }
}
#endif

void SpriteManager::unload()
{
    m_spritesCount = 0;
    m_signature = 0;
    m_spritesFiles.clear();
}

ImagePtr SpriteManager::getSpriteImage(const int id, bool& isLoading)
{
    if (g_game.getProtocolVersion() >= 1281 && !g_game.getFeature(Otc::GameLoadSprInsteadProtobuf)) {
        return g_spriteAppearances.getSpriteImage(id, isLoading);
    }

#if defined(__EMSCRIPTEN__) || defined(ANDROID)
    if (m_remote)
        return getRemoteSpriteImage(id, isLoading);
#endif
    if (m_spritesFiles.empty())
        return nullptr;

    const auto threadId = g_app.isLoadingAsyncTexture() ? stdext::getThreadId() : 0;
    if (const auto& sf = m_spritesFiles[threadId % m_spritesFiles.size()]) {
        if (sf->m_loadingState.exchange(SpriteLoadState::LOADING, std::memory_order_acq_rel) == SpriteLoadState::LOADING) {
            isLoading = true;
            return nullptr;
        }

        auto image = m_spritesHd ? getSpriteImageHd(id, sf->file) : getSpriteImage(id, sf->file);

        sf->m_loadingState.store(SpriteLoadState::LOADED, std::memory_order_release);

        return image;
    }

    return nullptr;
}

ImagePtr SpriteManager::getSpriteImageHd(const int id, const FileStreamPtr& file)
{
    const auto it = m_cwmSpritesMetadata.find(id);
    if (it == m_cwmSpritesMetadata.end())
        return nullptr;

    const auto& metadata = it->second;

    std::string buffer(metadata.getFileSize(), 0);

    file->seek(m_spritesOffset + metadata.getOffset());
    file->read(buffer.data(), metadata.getFileSize());

    return Image::loadPNG(buffer.data(), buffer.size());
}

uint16_t readU16FromBuffer(const uint8_t* data, size_t& offset) {
    uint16_t val = data[offset] | (data[offset + 1] << 8);
    offset += 2;
    return val;
}

ImagePtr SpriteManager::getSpriteImage(const int id, const FileStreamPtr& file)
{
    if (id == 0 || !file)
        return nullptr;

    try {
        file->seek(((id - 1) * 4) + m_spritesOffset);
        const uint32_t spriteAddress = file->getU32();
        if (spriteAddress == 0)
            return nullptr;

        file->seek(spriteAddress);
        file->skip(3); // Skip RGB color key

        const uint16_t pixelDataSize = file->getU16();

        static thread_local std::vector<uint8_t> spriteBuffer;
        spriteBuffer.resize(pixelDataSize);
        file->read(spriteBuffer.data(), pixelDataSize);

        return decodeSprite(id, spriteBuffer.data(), pixelDataSize);
    } catch (const stdext::exception& e) {
        g_logger.error("Failed to get sprite id {}: {}", id, e.what());
        return nullptr;
    }
}

ImagePtr SpriteManager::decodeSprite(const int /*id*/, const uint8_t* spriteData, const uint16_t pixelDataSize)
{
    {
        const int spriteSize = g_gameConfig.getSpriteSize();
        const int totalPixels = spriteSize * spriteSize;
        const int maxWriteSize = totalPixels * 4;

        const bool useAlpha = g_game.getFeature(Otc::GameSpritesAlphaChannel);
        const uint8_t channels = useAlpha ? 4 : 3;

        size_t offset = 0;
        auto image = std::make_shared<Image>(Size(spriteSize));
        uint8_t* pixels = image->getPixelData();
        int writePos = 0;
        bool hasAlpha = false;
        int transparentCount = 0;

        static constexpr int MAX_PIXEL_BLOCK = 4096;
        static thread_local uint8_t tempBuffer[MAX_PIXEL_BLOCK * 4];

        while (offset + 4 <= pixelDataSize && writePos < maxWriteSize) {
            const uint16_t transparentPixels = readU16FromBuffer(spriteData, offset);
            const uint16_t coloredPixels = readU16FromBuffer(spriteData, offset);

            transparentCount += transparentPixels;

            const int transparentBytes = transparentPixels * 4;
            if (writePos + transparentBytes > maxWriteSize)
                break;

            std::memset(pixels + writePos, 0, transparentBytes);
            writePos += transparentBytes;

            const int actualColoredPixels = (coloredPixels > MAX_PIXEL_BLOCK) ? MAX_PIXEL_BLOCK : coloredPixels;
            const int bytesToRead = actualColoredPixels * channels;

            if (offset + bytesToRead > pixelDataSize)
                break;

            std::memcpy(tempBuffer, spriteData + offset, bytesToRead);
            offset += bytesToRead;

            if (useAlpha) {
                for (int i = 0, src = 0; i < actualColoredPixels && writePos + 4 <= maxWriteSize; ++i, src += 4) {
                    pixels[writePos + 0] = tempBuffer[src + 0];
                    pixels[writePos + 1] = tempBuffer[src + 1];
                    pixels[writePos + 2] = tempBuffer[src + 2];
                    const uint8_t alpha = tempBuffer[src + 3];
                    pixels[writePos + 3] = alpha;

                    if (alpha != 0xFF) hasAlpha = true;
                    else if (transparentCount <= 4 && alpha == 0x00) ++transparentCount;

                    writePos += 4;
                }
            } else {
                for (int i = 0, src = 0; i < actualColoredPixels && writePos + 4 <= maxWriteSize; ++i, src += 3) {
                    pixels[writePos + 0] = tempBuffer[src + 0];
                    pixels[writePos + 1] = tempBuffer[src + 1];
                    pixels[writePos + 2] = tempBuffer[src + 2];
                    pixels[writePos + 3] = 0xFF;
                    writePos += 4;
                }
            }
        }

        if (writePos < maxWriteSize) {
            std::memset(pixels + writePos, 0, maxWriteSize - writePos);
            transparentCount += maxWriteSize - writePos;
        }

        if (hasAlpha || transparentCount > 4)
            image->setTransparentPixel(true);

        return image;
    }
}

// ---------------------------------------------------------------------------
// [codex] Sprites sob demanda para a versao navegador.
// O site guarda o Tibia.spr fatiado:
//   spr/indice.bin                 "CDXS" + u32 tamanhoBloco + u32 tamanhoArquivo + cabecalho original do spr
//   spr/<assinatura hex>/<n>.bin   blocos de tamanhoBloco bytes do spr original
// ---------------------------------------------------------------------------
bool SpriteManager::prefetchSprites(const std::vector<uint32_t>& ids)
{
#if defined(__EMSCRIPTEN__) || defined(ANDROID)
    if (!m_remote)
        return true;
    bool pronto = true;
    for (const uint32_t id : ids) {
        if (id != 0 && !spriteBlocksReady(id, true))
            pronto = false;
    }
    return pronto;
#else
    (void)ids;
    return true;
#endif
}

#if defined(__EMSCRIPTEN__) || defined(ANDROID)
namespace {
#ifdef ANDROID
    // CODEX (Android): baixa do site e guarda no aparelho; da proxima vez le do disco
    const std::string CODEX_SITE = "https://codexpoketibia.com.br/jogar/";

    bool lerArquivo(const std::string& caminho, std::vector<uint8_t>& out)
    {
        char* buf = nullptr;
        long long len = 0;
        if (!pkfs_readAll(caminho.c_str(), &buf, &len))
            return false;
        out.assign(reinterpret_cast<uint8_t*>(buf), reinterpret_cast<uint8_t*>(buf) + len);
        pkfs_free(buf);
        return len > 0;
    }

    bool codexBaixar(const std::string& url, std::vector<uint8_t>& out)
    {
        std::string dir = g_resources.getWriteDir();
        if (!dir.empty() && dir.back() != '/')
            dir += '/';
        const std::string local = dir + "sprcache/" + url;
        // o indice muda quando o spr muda: sempre baixa de novo (os blocos tem a assinatura no caminho)
        const bool ehIndice = url.find("indice.bin") != std::string::npos;
        if (!ehIndice && lerArquivo(local, out))
            return true;
        pkfs_mkdirs(local.substr(0, local.rfind('/')).c_str());
        const std::string tmp = local + ".tmp" + std::to_string(stdext::getThreadId());
        char err[128] = { 0 };
        if (!pknet_download((CODEX_SITE + url).c_str(), tmp.c_str(), nullptr, nullptr, err, sizeof(err))) {
            if (ehIndice && lerArquivo(local, out))
                return true; // sem internet: usa o indice guardado
            return false;
        }
        pkfs_move(tmp.c_str(), local.c_str());
        return lerArquivo(local, out);
    }
#else
    bool codexBaixar(const std::string& url, std::vector<uint8_t>& out)
    {
        emscripten_fetch_attr_t attr;
        emscripten_fetch_attr_init(&attr);
        strcpy(attr.requestMethod, "GET");
        attr.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY | EMSCRIPTEN_FETCH_SYNCHRONOUS | EMSCRIPTEN_FETCH_REPLACE;
        emscripten_fetch_t* f = emscripten_fetch(&attr, url.c_str());
        if (!f)
            return false;
        const bool ok = f->status == 200 && f->numBytes > 0;
        if (ok)
            out.assign(reinterpret_cast<const uint8_t*>(f->data), reinterpret_cast<const uint8_t*>(f->data) + f->numBytes);
        emscripten_fetch_close(f);
        return ok;
    }
#endif

    uint32_t lerU32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | (static_cast<uint32_t>(p[3]) << 24); }

    constexpr size_t CODEX_CACHE_MAX = 256u * 1024u * 1024u;
    constexpr uint32_t CODEX_SPRITE_MAX = 5 + 8200; // cabecalho + pior caso RLE 32x32 RGBA
    constexpr int CODEX_THREADS = 6;
}

bool SpriteManager::loadRemoteSpr()
{
    std::vector<uint8_t> idx;
    if (!codexBaixar("spr/indice.bin", idx) || idx.size() < 20 || memcmp(idx.data(), "CDXS", 4) != 0) {
        g_logger.error("[codex] nao consegui baixar spr/indice.bin");
        return false;
    }

    m_remoteBlockSize = lerU32(&idx[4]);
    m_remoteFileSize = lerU32(&idx[8]);
    const uint8_t* h = &idx[12];
    const size_t hsize = idx.size() - 12;

    m_signature = lerU32(h);
    size_t pos = 4;
    if (g_game.getFeature(Otc::GameSpritesU32)) {
        m_spritesCount = lerU32(h + pos);
        pos += 4;
    } else {
        m_spritesCount = h[pos] | (h[pos + 1] << 8);
        pos += 2;
    }
    m_spritesOffset = pos;

    if (m_remoteBlockSize == 0 || hsize < pos + static_cast<size_t>(m_spritesCount) * 4) {
        g_logger.error("[codex] indice de sprites incompleto");
        return false;
    }

    m_remoteAddr.resize(m_spritesCount);
    for (uint32_t i = 0; i < m_spritesCount; ++i)
        m_remoteAddr[i] = lerU32(h + pos + i * 4);

    m_remoteBase = fmt::format("spr/{:08x}/", m_signature);

    {
        std::lock_guard lock(m_remoteMutex);
        m_remoteBlocks.clear();
        m_remoteOrder.clear();
        m_remoteQueue.clear();
        m_remotePending.clear();
        m_remoteBytes = 0;
    }

    if (!m_remoteThreads) {
        m_remoteThreads = true;
        for (int i = 0; i < CODEX_THREADS; ++i)
            std::thread([this] { remoteWorker(); }).detach();
    }

    m_lastFileName.clear();
    m_spritesFiles.clear();
    m_remote = true;
    m_loaded = true;
    g_logger.info("[codex] sprites remotos: {} sprites, assinatura {:08x}", m_spritesCount, m_signature);
    g_lua.callGlobalField("g_sprites", "onLoadSpr", std::string("remoto"));
    return true;
}

void SpriteManager::remoteWorker()
{
    for (;;) {
        uint32_t n;
        std::string base;
        {
            std::unique_lock lock(m_remoteMutex);
            m_remoteCv.wait(lock, [this] { return !m_remoteQueue.empty(); });
            n = m_remoteQueue.front();
            m_remoteQueue.pop_front();
            base = m_remoteBase;
        }

        auto data = std::make_shared<std::vector<uint8_t>>();
        bool ok = false;
        for (int tentativa = 0; tentativa < 3 && !ok; ++tentativa) {
            ok = codexBaixar(base + std::to_string(n) + ".bin", *data);
            if (!ok)
                std::this_thread::sleep_for(std::chrono::milliseconds(500 * (tentativa + 1)));
        }

        std::lock_guard lock(m_remoteMutex);
        m_remotePending.erase(n);
        if (!ok) {
            g_logger.warning("[codex] falha ao baixar bloco de sprites {}", n);
            continue;
        }
        m_remoteBytes += data->size();
        m_remoteBlocks[n] = std::move(data);
        // CODEX: a interface (janela de outfit, itens) so redesenha quando pedem: avisa que chegou sprite
        static std::atomic_bool avisoPendente{ false };
        if (!avisoPendente.exchange(true)) {
            g_dispatcher.scheduleEvent([] {
                avisoPendente = false;
                g_drawPool.repaint(DrawPoolType::FOREGROUND);
                g_drawPool.repaint(DrawPoolType::MAP);
            }, 50);
        }
        m_remoteOrder.push_back(n);
        while (m_remoteBytes > CODEX_CACHE_MAX && !m_remoteOrder.empty()) {
            const uint32_t velho = m_remoteOrder.front();
            m_remoteOrder.pop_front();
            if (const auto it = m_remoteBlocks.find(velho); it != m_remoteBlocks.end()) {
                m_remoteBytes -= it->second->size();
                m_remoteBlocks.erase(it);
            }
        }
    }
}

std::shared_ptr<std::vector<uint8_t>> SpriteManager::getBlock(const uint32_t n)
{
    const auto it = m_remoteBlocks.find(n);
    return it == m_remoteBlocks.end() ? nullptr : it->second;
}

bool SpriteManager::spriteBlocksReady(const uint32_t id, const bool queue)
{
    if (id == 0 || id > m_remoteAddr.size())
        return true;
    const uint32_t addr = m_remoteAddr[id - 1];
    if (addr == 0 || addr >= m_remoteFileSize)
        return true;

    const uint32_t fim = std::min<uint32_t>(addr + CODEX_SPRITE_MAX, m_remoteFileSize) - 1;
    const uint32_t b0 = addr / m_remoteBlockSize;
    const uint32_t b1 = fim / m_remoteBlockSize;

    bool pronto = true;
    std::lock_guard lock(m_remoteMutex);
    for (uint32_t b = b0; b <= b1; ++b) {
        if (m_remoteBlocks.count(b))
            continue;
        pronto = false;
        if (queue && m_remotePending.insert(b).second) {
            m_remoteQueue.push_back(b);
            m_remoteCv.notify_one();
        }
    }
    return pronto;
}

ImagePtr SpriteManager::getRemoteSpriteImage(const int id, bool& isLoading)
{
    if (id <= 0 || static_cast<uint32_t>(id) > m_remoteAddr.size())
        return nullptr;
    const uint32_t addr = m_remoteAddr[id - 1];
    if (addr == 0 || addr >= m_remoteFileSize)
        return nullptr;

    if (!spriteBlocksReady(id, true)) {
        isLoading = true;
        return nullptr;
    }

    // monta os bytes do sprite (pode atravessar 2 blocos)
    static thread_local std::vector<uint8_t> buf;
    const uint32_t fim = std::min<uint32_t>(addr + CODEX_SPRITE_MAX, m_remoteFileSize);
    buf.resize(fim - addr);
    {
        std::lock_guard lock(m_remoteMutex);
        uint32_t copiado = 0;
        while (copiado < buf.size()) {
            const uint32_t p = addr + copiado;
            const auto bloco = getBlock(p / m_remoteBlockSize);
            if (!bloco) { // descartado do cache no meio do caminho
                isLoading = true;
                return nullptr;
            }
            const uint32_t dentro = p % m_remoteBlockSize;
            if (dentro >= bloco->size())
                break;
            const uint32_t n = std::min<uint32_t>(static_cast<uint32_t>(bloco->size()) - dentro, static_cast<uint32_t>(buf.size()) - copiado);
            memcpy(buf.data() + copiado, bloco->data() + dentro, n);
            copiado += n;
        }
        buf.resize(copiado);
    }

    if (buf.size() < 5)
        return nullptr;
    const uint16_t pixelDataSize = buf[3] | (buf[4] << 8);
    if (5u + pixelDataSize > buf.size())
        return nullptr;
    return decodeSprite(id, buf.data() + 5, pixelDataSize);
}
#endif
