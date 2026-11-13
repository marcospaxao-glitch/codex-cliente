-- ============================================================
-- ATUALIZADOR AUTOMATICO (tela)
-- O trabalho pesado e feito no C++ (g_updater). Este modulo so
-- mostra o progresso e reinicia o cliente quando termina.
-- Estados: 0 parado, 1 desligado, 2 verificando, 3 baixando,
--          4 em dia, 5 atualizado, 6 falhou
-- ============================================================

local IDLE, DISABLED, CHECKING, DOWNLOADING, UPTODATE, UPDATED, FAILED = 0, 1, 2, 3, 4, 5, 6

local overlay = nil
local tickEvent = nil
local restartEvent = nil
local lastState = -1
local loginHidden = false

-- ---------- janela de login ----------
-- fica escondida enquanto a tela de atualizacao estiver aberta

local function getLoginWindow()
  return rootWidget:recursiveGetChildById('enterGame')
end

local function hideLogin()
  local login = getLoginWindow()
  if login and login:isVisible() then
    login:hide()
    loginHidden = true
  end
end

local function showLogin()
  if not loginHidden then return end
  loginHidden = false
  if EnterGame and EnterGame.show then
    pcall(EnterGame.show)
    return
  end
  local login = getLoginWindow()
  if login then
    login:show()
    login:raise()
    login:focus()
  end
end

-- ---------- tela ----------

local function mb(bytes)
  return string.format('%.1f MB', (bytes or 0) / 1048576)
end

local function setBar(fraction)
  if not overlay then return end
  local back = overlay:recursiveGetChildById('barBack')
  local fill = overlay:recursiveGetChildById('barFill')
  local width = math.max(0, back:getWidth() - 2)
  fraction = math.max(0, math.min(1, fraction or 0))
  fill:setWidth(math.floor(width * fraction))
end

local function setTexts(status, detail)
  if not overlay then return end
  overlay:recursiveGetChildById('status'):setText(status or '')
  overlay:recursiveGetChildById('detail'):setText(detail or '')
end

local function setButtons(visible)
  if not overlay then return end
  overlay:recursiveGetChildById('retryButton'):setVisible(visible)
  overlay:recursiveGetChildById('continueButton'):setVisible(visible)
end

local function stopTick()
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
end

local function keepOnTop()
  if not overlay then return end
  hideLogin()
  overlay:raise()
end

local function destroyOverlay()
  stopTick()
  if restartEvent then
    removeEvent(restartEvent)
    restartEvent = nil
  end
  if overlay then
    pcall(function() rootWidget:unlockChild(overlay) end)
    overlay:destroy()
    overlay = nil
  end
  showLogin()
end

local function createOverlay()
  if overlay then return end
  overlay = g_ui.createWidget('UpdaterOverlay', rootWidget)
  pcall(function() rootWidget:lockChild(overlay) end)
  keepOnTop()
  overlay:focus()
end

local function tick()
  local state = g_updater.getState()

  if state == UPTODATE or state == DISABLED or state == IDLE then
    destroyOverlay()
    return
  end

  -- o login pode abrir depois do atualizador; a tela continua por cima
  keepOnTop()

  if state == CHECKING then
    setTexts('Verificando atualizacoes...', '')
    setBar(0)
  elseif state == DOWNLOADING then
    local done, total = g_updater.getBytesDone(), g_updater.getBytesTotal()
    local file = g_updater.getCurrentFile() or ''
    setTexts(string.format('Baixando atualizacao (%d de %d arquivos)',
      g_updater.getFilesDone() + 1, g_updater.getFilesTotal()),
      string.format('%s / %s   %s', mb(done), mb(total), file:match('[^/]+$') or file))
    setBar(total > 0 and done / total or 0)
  elseif state == UPDATED and lastState ~= UPDATED then
    setTexts('Atualizacao concluida! Reiniciando o jogo...', '')
    setBar(1)
    restartEvent = scheduleEvent(function()
      restartEvent = nil
      g_updater.restart()
    end, 1500)
  elseif state == FAILED and lastState ~= FAILED then
    setTexts(g_updater.getError(), 'Voce pode tentar de novo ou jogar sem atualizar.')
    setBar(0)
    setButtons(true)
    overlay:focus()
  end
  lastState = state
end

local function begin()
  lastState = -1
  g_updater.start()
  local state = g_updater.getState()
  if state == DISABLED or state == UPTODATE then
    return
  end
  createOverlay()
  setButtons(false)
  setTexts('Verificando atualizacoes...', '')
  setBar(0)
  stopTick()
  tickEvent = cycleEvent(tick, 100)
end

function retry()
  setButtons(false)
  begin()
end

function close()
  destroyOverlay()
end

function init()
  if not g_updater then return end
  g_ui.importStyle('updater')
  begin()
end

function terminate()
  destroyOverlay()
end
