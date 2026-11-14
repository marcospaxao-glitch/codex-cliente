-- CODEX: modulo "client" adaptado ao Redemption.
-- O tamanho/posicao da janela agora e feito pelo modulo "startup" do Redemption.
-- Saiu daqui: g_window.poll() e o redimensionamento durante o carregamento
-- (no Redemption isso corrompia a memoria e fechava o cliente na abertura).
local musicFilename = '/sounds/startup'
local musicChannel = nil
if g_sounds then
  musicChannel = g_sounds.getChannel(1)
end

local function temMusica()
  return musicChannel and g_resources.fileExists(musicFilename .. '.ogg')
end

function setMusic(filename)
  musicFilename = filename
  if temMusica() and not g_game.isOnline() then
    musicChannel:stop()
    musicChannel:enqueue(musicFilename, 3)
  end
end

function reloadScripts()
  g_textures.clearCache()
  g_modules.reloadModules()

  local script = '/' .. g_app.getCompactName() .. 'rc.lua'
  if g_resources.fileExists(script) then
    dofile(script)
  end

  local message = tr('All modules and scripts were reloaded.')
  if modules.game_textmessage then
    modules.game_textmessage.displayGameMessage(message)
  end
  print(message)
end

local function onGameStart()
  if musicChannel then musicChannel:stop(3) end
end

local function onGameEnd()
  if temMusica() then
    g_sounds.stopAll()
    musicChannel:enqueue(musicFilename, 3)
  end
end

function startup()
  if temMusica() then musicChannel:enqueue(musicFilename, 3) end

  local errtitle, errmsg = nil, nil
  if g_graphics.getRenderer():lower():match('gdi generic') then
    errtitle = tr('Graphics card driver not detected')
    errmsg = tr('No graphics card detected, everything will be drawn using the CPU,\nthus the performance will be really bad.\nPlease update your graphics driver to have a better performance.')
  end

  if errmsg or errtitle then
    local msgbox = displayErrorBox(errtitle, errmsg)
    msgbox.onOk = function() EnterGame.firstShow() end
  else
    EnterGame.firstShow()
  end
end

function init()
  if codexPasso then codexPasso('client: init') end
  connect(g_app, { onRun = startup, onExit = exit })
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })

  if temMusica() then g_sounds.preload(musicFilename) end

  g_window.setTitle(g_app.getName())
  -- o icone agora vem do proprio Codex.exe (o setIcon do Lua nao e usado no Redemption)

  g_keyboard.bindKeyDown('Ctrl+Shift+R', reloadScripts)
  if codexPasso then codexPasso('client: uuid') end

  -- uuid da maquina (protege a senha salva)
  if not g_crypt.setMachineUUID(g_settings.get('uuid')) then
    g_settings.set('uuid', g_crypt.getMachineUUID())
    g_settings.save()
  end
  if codexPasso then codexPasso('client: init ok') end
end

function terminate()
  disconnect(g_app, { onRun = startup, onExit = exit })
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown('Ctrl+Shift+R')
end

function exit()
  g_logger.info('Exiting application..')
end
