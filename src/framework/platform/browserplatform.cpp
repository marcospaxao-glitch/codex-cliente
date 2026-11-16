/*
 * Copyright (c) 2010-2016 OTClient <https://github.com/edubart/otclient>
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

#ifdef __EMSCRIPTEN__

#include "platform.h"
#include <cstring>
#include <emscripten/emscripten.h>
#include <fstream>
#include <unistd.h>
#include <framework/stdext/stdext.h>
#include <framework/core/eventdispatcher.h>
#include <errno.h>

#include <sys/stat.h>

void Platform::init(std::vector<std::string>& args)
{
    processArgs(args);
    setDevice({ Browser, OsUnknown });
}

void Platform::processArgs(std::vector<std::string>& /*args*/)
{
    //nothing todo, linux args are already utf8 encoded
}

bool Platform::spawnProcess(std::string process, const std::vector<std::string>& args)
{
    return false;
}

int Platform::getProcessId()
{
    return getpid();
}

bool Platform::isProcessRunning(const std::string_view /*name*/)
{
    return false;
}

bool Platform::killProcess(const std::string_view /*name*/)
{
    return false;
}

std::string Platform::getTempPath()
{
    return std::filesystem::temp_directory_path();
}

std::string Platform::getCurrentDir()
{
    return std::filesystem::current_path();
}

bool Platform::copyFile(std::string from, std::string to)
{
    return std::filesystem::copy_file(from, to);
}

bool Platform::fileExists(std::string file)
{
    return std::filesystem::exists(file);
}

bool Platform::removeFile(std::string file)
{
    return std::filesystem::remove(file);
}

ticks_t Platform::getFileModificationTime(std::string file)
{
    return 0;
}

// CODEX: abre o site numa aba nova (se o navegador bloquear, abre nesta aba)
bool Platform::openUrl(std::string url, bool now)
{
    if (url.find("http://") == std::string::npos && url.find("https://") == std::string::npos)
        url.insert(0, "https://");
    MAIN_THREAD_ASYNC_EM_ASM({
        var u = UTF8ToString($0);
        if (location.protocol === "https:" && u.indexOf("http://") === 0) u = "https://" + u.substring(7);
        var w = null;
        try { w = window.open(u, "_blank"); } catch (e) {}
        if (!w) location.href = u;
    }, strdup(url.c_str()));
    return true;
}

bool Platform::openDir(std::string path, bool now)
{
    return true;
}

std::string Platform::getCPUName()
{
    return std::string();
}

double Platform::getTotalSystemMemory()
{
    return 0;
}

double Platform::getMemoryUsage()
{
    return 0;
}

std::string Platform::getOSName()
{
    return "browser";
}

std::string Platform::traceback(const std::string_view where, int level, int maxDepth)
{
    return "";
}


#endif
