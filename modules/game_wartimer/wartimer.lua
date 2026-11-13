-- ============================================================
-- CODEX - CONTADOR DA GUERRA DE CASTELOS (opcode 128)
-- Aparece no canto superior esquerdo da tela do jogo enquanto a
-- guerra estiver acontecendo. Servidor: data/lib/core/codexcastle.lua
--   WT|segundos|castelos  -> mostra     WT|0 -> esconde
-- Ajuste fino da posicao: MARGIN_TOP / MARGIN_LEFT
-- ============================================================
local OPCODE = 128
MARGIN_TOP = 50
MARGIN_LEFT = 6

local box = nil
local endsAt = 0
local tickEvent = nil

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function destroyBox()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if box then box:destroy() box = nil end
end

local function tick()
  tickEvent = nil
  if not box then return end
  local left = math.max(0, endsAt - os.time())
  local h = math.floor(left / 3600)
  local m = math.floor((left % 3600) / 60)
  local s = left % 60
  box:getChildById('clock'):setText(h > 0 and string.format('%d:%02d:%02d', h, m, s) or string.format('%02d:%02d', m, s))
  box:getChildById('clock'):setColor(left <= 60 and '#ff6b6b' or '#ffffff')
  if left <= 0 then
    destroyBox()
    return
  end
  tickEvent = scheduleEvent(tick, 1000)
end

local function showBox(seconds, castles)
  local map = mapPanel()
  if not map then return end
  if not box then
    box = g_ui.createWidget('WarTimerBox', map)
    box:addAnchor(AnchorTop, 'parent', AnchorTop)
    box:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    box:setMarginTop(MARGIN_TOP)
    box:setMarginLeft(MARGIN_LEFT)
  end
  endsAt = os.time() + seconds
  local label = box:getChildById('castles')
  label:setText(castles ~= '' and castles or 'Todos os castelos')
  label:setTooltip(castles)
  box:setTooltip('Guerra de castelos: quebre o Emperium para conquistar.\nPainel do cla: Ctrl+Shift+C')
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  tick()
end

local function onTimer(protocol, opcode, buffer)
  local seconds, castles = tostring(buffer or ''):match('^WT|(%d+)|?(.*)$')
  seconds = tonumber(seconds) or 0
  if seconds > 0 then
    showBox(seconds, castles or '')
  else
    destroyBox()
  end
end

local function onGameEnd()
  destroyBox()
end

function init()
  g_ui.importStyle('wartimer')
  ProtocolGame.registerExtendedOpcode(OPCODE, onTimer)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  destroyBox()
end
