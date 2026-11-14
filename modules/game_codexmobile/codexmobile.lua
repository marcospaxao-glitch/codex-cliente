-- Codex: joystick na tela para jogar pelo navegador do celular.
-- So liga quando o cliente roda no navegador de um celular/tablet (codexCelular()).
local overlay
local keypad
local evento
local posRel = { x = 0.5, y = 0.5 }
local segurando = false

local function ehCelular()
  return type(codexCelular) == 'function' and codexCelular()
end

local function centralizar()
  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
end

local function atualizarPos(widget, pos)
  posRel = {
    x = (pos.x - widget:getX()) / widget:getWidth(),
    y = (pos.y - widget:getY()) / widget:getHeight()
  }
end

local function direcao()
  local x = math.min(1, math.max(0, posRel.x))
  local y = math.min(1, math.max(0, posRel.y))
  if y < 0.3 and x < 0.3 then return Directions.NorthWest end
  if y < 0.3 and x > 0.7 then return Directions.NorthEast end
  if y > 0.7 and x < 0.3 then return Directions.SouthWest end
  if y > 0.7 and x > 0.7 then return Directions.SouthEast end
  if math.abs(y - 0.5) <= 0.1 and math.abs(x - 0.5) <= 0.1 then return nil end
  if math.abs(y - 0.5) > math.abs(x - 0.5) then
    return y < 0.5 and Directions.North or Directions.South
  end
  return x < 0.5 and Directions.West or Directions.East
end

local function passo()
  removeEvent(evento)
  evento = nil
  if not segurando or not g_game.isOnline() then
    centralizar()
    return
  end
  evento = scheduleEvent(passo, 40)

  local x = math.min(1, math.max(0, posRel.x))
  local y = math.min(1, math.max(0, posRel.y))
  local ang = math.atan2(x - 0.5, y - 0.5)
  local maxTop = math.abs(math.cos(ang)) * 50
  local maxLeft = math.abs(math.sin(ang)) * 50
  keypad.pointer:setMarginTop(math.max(-maxTop, math.min(maxTop, (y - 0.5) * 100)))
  keypad.pointer:setMarginLeft(math.max(-maxLeft, math.min(maxLeft, (x - 0.5) * 100)))

  local dir = direcao()
  if dir then g_game.walk(dir) end
end

local function onPress(widget, pos, button)
  if button ~= MouseLeftButton then return false end
  atualizarPos(widget, pos)
  segurando = true
  passo()
  return true
end

local function onMove(widget, pos, offset)
  if segurando then atualizarPos(widget, pos) end
  return true
end

local function onRelease(widget, pos, button)
  if button ~= MouseLeftButton then return false end
  segurando = false
  removeEvent(evento)
  evento = nil
  centralizar()
  return true
end

local function onGameStart()
  if not keypad then return end
  overlay:raise()
  keypad:show()
end

local function onGameEnd()
  segurando = false
  removeEvent(evento)
  evento = nil
  if keypad then keypad:hide() end
end

function init()
  if not ehCelular() then return end
  overlay = g_ui.displayUI('codexmobile')
  keypad = overlay:getChildById('keypad')
  connect(keypad, { onMousePress = onPress, onMouseMove = onMove, onMouseRelease = onRelease })
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
  g_logger.info('[codex] modo celular ligado (joystick)')
end

function terminate()
  if not overlay then return end
  removeEvent(evento)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  overlay:destroy()
  overlay = nil
  keypad = nil
end

function hide() if overlay then overlay:hide() end end
function show() if overlay then overlay:show() end end
