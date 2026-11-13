-- ============================================================
-- TV (Codex) - opcode 114
-- Abre quando o jogador usa a TV (itens 32031 / 32032).
-- Assistindo: faixa no topo com "Parar" (ou Esc).
-- ============================================================
local OPCODE = 114

local window = nil
local listPanel = nil
local watchingBar = nil
local blinkEvent = nil
local escHandler = nil

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

function hide()
  if window then window:hide() end
end

function refresh()
  send('LIST')
end

function stop()
  send('STOP')
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function placeBar()
  local map = mapPanel()
  if not watchingBar or not map then return end
  local r = map:getRect()
  watchingBar:setPosition({x = r.x + math.floor((r.width - watchingBar:getWidth()) / 2), y = r.y + r.height - watchingBar:getHeight() - 12})
end

local function blink()
  blinkEvent = nil
  if not watchingBar or not watchingBar:isVisible() then return end
  local dot = watchingBar:getChildById('dot')
  dot:setVisible(not dot:isVisible())
  placeBar()
  blinkEvent = scheduleEvent(blink, 600)
end

local function setWatching(name)
  if name then
    watchingBar:getChildById('text'):setText('AO VIVO  -  assistindo ' .. name)
    watchingBar:show()
    watchingBar:raise()
    placeBar()
    hide()
    if not blinkEvent then blinkEvent = scheduleEvent(blink, 600) end
  else
    watchingBar:hide()
    if blinkEvent then removeEvent(blinkEvent) blinkEvent = nil end
  end
end

local function renderList(entries)
  listPanel:destroyChildren()
  for _, e in ipairs(entries) do
    local row = g_ui.createWidget('TvRow', listPanel)
    row:getChildById('name'):setText(e.name)
    row:getChildById('info'):setText('Nivel ' .. e.level .. '  -  ' .. e.place)
    row:getChildById('watch').onClick = function() send('WATCH|' .. e.name) end
  end
  window:getChildById('empty'):setVisible(#entries == 0)
end

local function onOpcode(protocol, opcode, buffer)
  buffer = tostring(buffer or '')
  if buffer == 'OPEN' then
    window:show()
    window:raise()
    window:focus()
    return
  elseif buffer == 'OFF' then
    setWatching(nil)
    return
  end
  local on = buffer:match('^ON|(.*)$')
  if on then
    setWatching(on)
    return
  end
  if buffer:sub(1, 4) == 'LIST' then
    local entries = {}
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = {}
      for field in (line .. '|'):gmatch('(.-)|') do f[#f + 1] = field end
      if f[1] == 'L' then
        entries[#entries + 1] = {name = f[2] or '?', level = f[3] or '?', place = f[4] or ''}
      end
    end
    renderList(entries)
  end
end

local function onGameEnd()
  hide()
  setWatching(nil)
end

function init()
  window = g_ui.displayUI('tv')
  window:hide()
  listPanel = window:getChildById('list')
  watchingBar = g_ui.createWidget('TvWatching', rootWidget)
  watchingBar:hide()
  watchingBar:getChildById('stop').onClick = stop
  escHandler = function()
    if watchingBar and watchingBar:isVisible() then stop() end
  end
  g_keyboard.bindKeyPress('Escape', escHandler)
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, {onGameEnd = onGameEnd})
  if escHandler then g_keyboard.unbindKeyPress('Escape', escHandler) escHandler = nil end
  if blinkEvent then removeEvent(blinkEvent) blinkEvent = nil end
  if watchingBar then watchingBar:destroy() watchingBar = nil end
  if window then window:destroy() window = nil end
end
