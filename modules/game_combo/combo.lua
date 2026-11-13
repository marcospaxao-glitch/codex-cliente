-- ============================================================
-- codex itens: agora o quadro aparece/some usando o item Auto Combo (50001).
-- Sem icone no menu do topo e sem atalho de teclado. Sem o item o servidor nao liga.
-- ============================================================
-- CODEX COMBO - botao (arrastavel) + atalho para ativar o combo de
-- moves do pokemon que esta fora. O combo e montado no Pokemon
-- Manager > Moves. Clicar/apertar LIGA (repete o combo sem parar),
-- clicar/apertar de novo DESLIGA.
-- So manda algo quando o JOGADOR clica ou aperta a tecla.
-- Botao Combo da barra do topo: MOSTRA / ESCONDE o quadro do combo
-- (fica salvo). O atalho continua ligando/desligando mesmo escondido.
-- ============================================================
HOTKEY = 'Ctrl+Space'     -- troque aqui se quiser outra tecla
OPCODE = 120              -- servidor -> client (estado do combo)

local button = nil
local topButton = nil
local resetEvent = nil
local running = false

local function setInfo(text, color)
  if not button then return end
  local info = button:getChildById('info')
  if info then
    info:setText(text or '')
    info:setColor(color or '#8fa7c4')
  end
end

local function setProgress(stepN, total)
  if not button then return end
  local track = button:getChildById('track')
  local fill = button:getChildById('fill')
  if not track or not fill then return end
  local w = 0
  if total and total > 0 and stepN and stepN > 0 then
    w = math.floor(track:getWidth() * math.min(stepN, total) / total)
  end
  fill:setWidth(w)
end

local function setLook(on)
  if not button then return end
  local dot = button:getChildById('dot')
  local state = button:getChildById('state')
  if dot then dot:setBackgroundColor(on and '#4fe07a' or '#3a5170') end
  if state then
    state:setText(on and 'ON' or 'OFF')
    state:setColor(on and '#ffffff' or '#8fa7c4')
    state:setBackgroundColor(on and '#2e8b4f' or '#1a2a40')
  end
  button:setBorderColor(on and '#f2c400' or '#6b5a1a')
  button:setBackgroundColor(on and '#14263f' or '#0c1828')
end

local function idleInfo()
  setInfo('Clique ou ' .. HOTKEY, '#6f86a8')
  setProgress(0, 0)
end

function activate()
  if not g_game.isOnline() then return end
  g_game.talk('mcombo')
end

local function savePos()
  if not button then return end
  local pos = button:getPosition()
  g_settings.set('codexComboPos', pos.x .. ',' .. pos.y)
end

local function loadPos()
  local raw = g_settings.getString('codexComboPos')
  local x, y = string.match(raw or '', '^(%-?%d+),(%-?%d+)$')
  return tonumber(x), tonumber(y)
end

local function placeButton()
  if not button then return end
  local root = modules.game_interface.getRootPanel()
  local x, y = loadPos()
  local rw, rh = root:getWidth(), root:getHeight()
  if not x or not y or x < 0 or y < 0 or x > rw - 20 or y > rh - 20 then
    x = math.floor(rw / 2) + 180
    y = rh - 140
  end
  button:setPosition({x = x, y = y})
end

local function onState(protocol, opcode, buffer)
  local clean = {}
  for v in string.gmatch((buffer or '') .. '|', '([^|]*)|') do clean[#clean + 1] = v end
  if clean[1] == 'SHOW' then toggleWindow() return end -- codex itens: usou o item
  if clean[1] == 'HIDE' then -- codex itens esconder: o jogador nao tem o item
    if button and button:isVisible() then toggleWindow() end
    g_settings.set('codexComboShown', false)
    return
  end
  if clean[1] ~= 'STATE' then return end
  local on = clean[2] == '1'
  local stepN = tonumber(clean[3]) or 0
  local total = tonumber(clean[4]) or 0
  local text = clean[5] or ''
  running = on
  if resetEvent then removeEvent(resetEvent) resetEvent = nil end
  if not button then return end
  setLook(on)
  if on then
    if text ~= '' and text ~= 'Ligado' then
      setInfo(text, '#ffd24a')
      setProgress(0, 0)
    elseif total > 0 then
      setInfo('Golpe ' .. stepN .. ' de ' .. total, '#ffffff')
      setProgress(stepN, total)
    else
      setInfo('Ligado', '#4fe07a')
      setProgress(0, 0)
    end
  else
    setProgress(0, 0)
    if text ~= '' then
      setInfo(text, '#ff9a7a')
      if text == 'Combo concluido' then setInfo(text, '#72e6a0') end
      resetEvent = scheduleEvent(function() resetEvent = nil idleInfo() end, 2500)
    else
      idleInfo()
    end
  end
end

local function isHidden()
  return not g_settings.getBoolean('codexComboShown') -- codex itens: escondido ate usar o item
end

local function refreshTopButton()
  if topButton and not topButton:isDestroyed() then
    topButton:setOn(button ~= nil and button:isVisible())
  end
end

function toggleWindow()
  if not button then return end
  local show = not button:isVisible()
  button:setVisible(show)
  g_settings.set('codexComboShown', show)
  if show then button:raise() end
  refreshTopButton()
end

local function createButton()
  if button then return end
  local root = modules.game_interface.getRootPanel()
  if not root then return end
  button = g_ui.createWidget('ComboButton', root)
  button:setTooltip('Clique: liga/desliga o combo\nVale para todos os pokemons ate desligar\nMonte o combo no Pokemon Manager > Moves\nPara esconder: use o item Auto Combo de novo')
  setLook(false)
  idleInfo()

  -- arrastar SO pela alca da esquerda (os pontinhos)
  local handle = button:getChildById('handle')
  if handle then
    handle:setTooltip('Arraste para mudar de lugar')
    handle.onDragEnter = function(self, mousePos)
      button.dragOffset = {x = mousePos.x - button:getX(), y = mousePos.y - button:getY()}
      return true
    end
    handle.onDragMove = function(self, mousePos, mouseMoved)
      local off = button.dragOffset or {x = 0, y = 0}
      local parent = button:getParent()
      local x = math.max(0, math.min(mousePos.x - off.x, parent:getWidth() - button:getWidth()))
      local y = math.max(0, math.min(mousePos.y - off.y, parent:getHeight() - button:getHeight()))
      button:setPosition({x = x, y = y})
      return true
    end
    handle.onDragLeave = function(self)
      savePos()
      return true
    end
  end
  button.onClick = function(self)
    activate()
  end
  if isHidden() then button:setVisible(false) end
  scheduleEvent(placeButton, 200)
  refreshTopButton()
end

local function destroyButton()
  if resetEvent then removeEvent(resetEvent) resetEvent = nil end
  if button then button:destroy() button = nil end
  running = false
end

local function createTopButton()
  if topButton and not topButton:isDestroyed() then return end
  local tm = modules.client_topmenu
  if not tm or not tm.addCenterGameButton then return end
  topButton = tm.addCenterGameButton('comboButton', 'Combo: mostrar / esconder o quadro\nLigar/desligar: ' .. HOTKEY,
    '/images/topbuttons/codex/spelllist', toggleWindow)
  refreshTopButton()
end

function onGameStart()
  createButton()
end

function onGameEnd()
  destroyButton()
end

function init()
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  g_ui.importStyle('combo')
  ProtocolGame.registerExtendedOpcode(OPCODE, onState)
  local root = modules.game_interface.getRootPanel()
  if g_game.isOnline() then createButton() end
end

function terminate()
  if topButton and not topButton:isDestroyed() then topButton:destroy() end
  topButton = nil
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  local root = modules.game_interface.getRootPanel()
  pcall(function() g_keyboard.unbindKeyDown(HOTKEY, activate, root) end)
  destroyButton()
end
