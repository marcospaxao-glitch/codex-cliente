-- this is the first file executed when the application starts
-- we have to load the first modules form here

-- ============================================================
-- CODEX - configuracao principal do cliente
-- ============================================================
-- Endereco do servidor de jogo:
--   teste no PC de casa: '127.0.0.1'
--   servidor oficial:    'jogo.codexpoketibia.com.br'
CODEX_SERVIDOR = 'jogo.codexpoketibia.com.br'
CODEX_PORTA = 7171
CODEX_VERSAO = 1098

Services = {}       -- sem updater/assets automaticos do Redemption
Servers_init = {}   -- a tela de login do Codex usa CODEX_SERVIDOR

g_app.setName("Codex");
g_app.setCompactName("codex");
g_app.setOrganizationName("codex");

g_app.hasUpdater = function()
    return (Services.updater and Services.updater ~= "" and g_modules.getModule("updater"))
end

-- setup logger
g_logger.setLogFile(g_resources.getWorkDir() .. g_app.getCompactName() .. '.log')
g_logger.info("Operating system: " .. g_platform.getOSName())

-- print first terminal message
g_logger.info(g_app.getName() .. ' ' .. g_app.getVersion() .. ' rev ' .. g_app.getBuildRevision() .. ' (' ..
    g_app.getBuildCommit() .. ') built on ' .. g_app.getBuildDate() .. ' for arch ' ..
    g_app.getBuildArch())

-- setup lua debugger
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
    require("lldebugger").start()
    g_logger.debug("Started LUA debugger.")
else
    g_logger.debug("LUA debugger not started (not launched with VSCode local-lua).")
end

-- add data directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'data', true) then
    g_logger.fatal('Unable to add data directory to the search path.')
end

-- add modules directory to the search path
if not g_resources.addSearchPath(g_resources.getWorkDir() .. 'modules', true) then
    g_logger.fatal('Unable to add modules directory to the search path.')
end

g_html.addGlobalStyle('/data/styles/html.css')
g_html.addGlobalStyle('/data/styles/custom.css')

-- try to add mods path too
g_resources.addSearchPath(g_resources.getWorkDir() .. 'mods', true)

-- setup directory for saving configurations
g_logger.info('[codex] passo: setupUserWriteDir')
g_resources.setupUserWriteDir(('%s/'):format(g_app.getCompactName()))

-- search all packages
g_logger.info('[codex] passo: searchAndAddPackages')
g_resources.searchAndAddPackages('/', '.otpkg', true)

-- load settings
-- CODEX: as configuracoes (posicao das janelas, opcoes, senha lembrada) vem SEMPRE da
-- pasta do usuario. Antes, um configdash.otml esquecido na pasta do jogo (ou num pacote)
-- podia ser lido no lugar e tudo "voltava ao padrao" a cada abertura. E se o arquivo
-- estragar (jogo fechado no meio do salvamento), volta a copia de seguranca.
g_logger.info('[codex] passo: loadSettings')
do
  local CFG, BAK = '/configdash.otml', '/configdash_copia.otml'
  local pasta = g_resources.getWriteDir()
  local outro = g_resources.getRealDir(CFG)
  local naFrente = pcall(function()
    g_resources.removeSearchPath(pasta)
    g_resources.addSearchPath(pasta, true)
  end)
  if outro ~= '' and outro ~= pasta then
    g_logger.warning('[codex] configdash.otml em ' .. outro .. ' ignorado; usando o de ' .. pasta)
  end
  local ok = g_configs.loadSettings(CFG)
  if not ok and g_resources.fileExists(BAK) then
    local lido, conteudo = pcall(g_resources.readFileContents, BAK)
    if lido and conteudo and #conteudo > 0 then
      g_resources.writeFileContents(CFG, conteudo)
      ok = g_configs.loadSettings(CFG)
      g_logger.warning('[codex] configdash.otml estragado ou sumido: copia de seguranca restaurada')
    end
  end
  if ok and g_resources.fileExists(CFG) then
    -- arquivo bom: guarda a copia para a proxima vez
    local lido, conteudo = pcall(g_resources.readFileContents, CFG)
    if lido and conteudo and #conteudo > 0 then g_resources.writeFileContents(BAK, conteudo) end
  end
  if naFrente then
    pcall(function()
      g_resources.removeSearchPath(pasta)
      g_resources.addSearchPath(pasta, false)
    end)
  end
  g_logger.info('[codex] configuracoes: ' .. pasta .. 'configdash.otml (' .. (ok and 'carregado' or 'novo') .. ')')
end

g_logger.info('[codex] passo: discoverModules')
g_modules.discoverModules()

-- libraries modules 0-99
g_modules.autoLoadModules(99)
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('modulelib')
g_modules.ensureModuleLoaded("startup")


local function loadModules()
    -- client modules 100-499
    g_modules.autoLoadModules(499)
    g_modules.ensureModuleLoaded('client')

    -- game modules 500-999
    g_modules.autoLoadModules(999)
    g_modules.ensureModuleLoaded('game_interface')

    -- mods 1000-9999
    g_modules.autoLoadModules(9999)

    local script = '/' .. g_app.getCompactName() .. 'rc.lua'

    if g_resources.fileExists(script) then
        dofile(script)
    end

    -- uncomment the line below so that modules are reloaded when modified. (Note: Use only mod dev)
    -- g_modules.enableAutoReload()
end

-- run updater, must use data.zip
if g_app.hasUpdater() then
    g_modules.ensureModuleLoaded("updater")
    return Updater.init(loadModules)
end

loadModules()
