-- ============================================================
-- AVISO DE MENSAGEM (celular / WhatsApp)
-- Icone de envelope no canto de cima/direita do mapa com o numero de
-- mensagens nao lidas. Fica la ate o jogador ler (o servidor manda o
-- numero novo pelo opcode 111). Clique: abre o celular.
-- ============================================================
local OPCODE = 111
local MARGIN = 8

local widget = nil
local unread = 0
local blinkEvent = nil
local blinkOn = false

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function place()
  local map = mapPanel()
  if not widget or not map then return end
  local r = map:getRect()
  widget:setPosition({x = r.x + r.width - widget:getWidth() - MARGIN, y = r.y + MARGIN})
end

local function blink()
  blinkEvent = nil
  if not widget or unread <= 0 then return end
  blinkOn = not blinkOn
  widget:setBorderColor(blinkOn and '#f2c400' or '#6f86a8')
  widget:getChildById('icon'):setImageColor(blinkOn and '#f2c400' or '#dce8f5')
  place()   -- acompanha se a janela mudar de tamanho
  blinkEvent = scheduleEvent(blink, 700)
end

local function update()
  if not widget then return end
  if unread > 0 and g_game.isOnline() then
    widget:getChildById('badge'):setText(unread > 99 and '99+' or tostring(unread))
    widget:setTooltip(unread == 1 and '1 mensagem nao lida\nClique para abrir o celular'
      or (unread .. ' mensagens nao lidas\nClique para abrir o celular'))
    widget:show()
    widget:raise()
    place()
    if not blinkEvent then blinkEvent = scheduleEvent(blink, 700) end
  else
    widget:hide()
    if blinkEvent then removeEvent(blinkEvent) blinkEvent = nil end
  end
end

local function onNotify(protocol, opcode, buffer)
  local n = tostring(buffer or ''):match('^N|(%d+)')
  unread = tonumber(n) or 0
  update()
end

local function onGameEnd()
  unread = 0
  update()
end

function init()
  g_ui.importStyle('phonenotify')
  widget = g_ui.createWidget('PhoneNotify', rootWidget)
  widget:hide()
  widget.onClick = function()
    local phone = modules.game_phone
    if phone and phone.show then phone.show() end
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onNotify)
  connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, {onGameEnd = onGameEnd})
  if blinkEvent then removeEvent(blinkEvent) blinkEvent = nil end
  if widget then widget:destroy() widget = nil end
end
