/*
 * Atualizador automatico do cliente (g_updater no Lua)
 *
 * No site (CLIENT_UPDATE_URL):
 *   manifest.txt          lista gerada pelo "pkpacker --publicar"
 *   files/<caminho>       arquivos ja criptografados
 *   files/client.exe      o .exe novo (opcional)
 *
 * Windows (codex.dat): arquivos novos vao para a pasta "updates" ao lado do
 * .exe e sao juntados ao codex.dat na proxima abertura. O .exe e trocado
 * direto (o antigo vira .old).
 * Navegador / Android: vao para a pasta de escrita (updates/) e valem por
 * cima dos arquivos que vieram com o cliente. Sem troca de executavel.
 */
#ifndef UPDATER_H
#define UPDATER_H

#include <atomic>
#include <map>
#include <mutex>
#include <string>
#include <thread>

class Updater
{
public:
    enum State { Idle = 0, Disabled, Checking, Downloading, UpToDate, Updated, Failed };

    void start();
    void terminate();
    void restart();

    int getState() { return m_state; }
    std::string getError();
    std::string getCurrentFile();
    double getBytesDone() { return (double)m_bytesDone; }
    double getBytesTotal() { return (double)m_bytesTotal; }
    int getFilesDone() { return m_filesDone; }
    int getFilesTotal() { return m_filesTotal; }
    bool needsRestart() { return m_needsRestart; }
    std::string getUrl();

    // usado pelo teste e pelo start()
    void setup(const std::string& baseDir, const std::string& url, const std::string& baseManifest, const std::string& exePath);
    void runSync() { run(); }

private:
    struct FileInfo { unsigned long crc; long long size; };
    typedef std::map<std::string, FileInfo> FileMap;

    void run();
    bool fail(const std::string& msg);
    static int onProgress(void* user, unsigned int bytes);
    static bool parseManifest(const std::string& text, FileMap& files, std::string* build, FileInfo* exe);
    void saveState(const FileMap& overlay, const std::string& build);
    bool download(const std::string& url, const std::string& dest, std::string& err);

    std::thread m_thread;
    std::mutex m_mutex;
    std::atomic<int> m_state{Idle};
    std::atomic<long long> m_bytesDone{0};
    std::atomic<long long> m_bytesTotal{0};
    std::atomic<int> m_filesDone{0};
    std::atomic<int> m_filesTotal{0};
    std::atomic<bool> m_needsRestart{false};
    std::atomic<bool> m_abort{false};
    std::string m_error;
    std::string m_currentFile;

    std::string m_baseDir;      // pasta do .exe, com / no fim
    std::string m_url;          // com / no fim
    std::string m_baseManifest; // manifesto de dentro do pokefans.dat
    std::string m_exePath;
    bool m_local = false;       // CODEX: sem codex.dat (navegador/Android): base = arquivos do cliente
};

extern Updater g_updater;

#endif
