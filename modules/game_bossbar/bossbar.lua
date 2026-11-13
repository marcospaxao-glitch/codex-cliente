-- ============================================================
-- BARRA DE VIDA DO EMPERIUM (estilo boss) - opcode 112
-- Aparece no topo do mapa para quem esta dentro de um castelo em
-- guerra. A barra desce suave e deixa um rastro dourado do dano.
-- So recebe do servidor (nao envia nada).
-- ============================================================
local OPCODE = 112
local MARGIN_TOP = 10

local bar = nil
local target, shown, trail = 0, 0, 0   -- porcentagens (0..1)
local animEvent = nil
local trailHold = 0

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function place()
  local map = mapPanel()
  if not bar or not map then return end
  local r = map:getRect()
  bar:setPosition({x = r.x + math.floor((r.width - bar:getWidth()) / 2), y = r.y + MARGIN_TOP})
end

local function fmt(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse()
  return (out:gsub('^%.', ''))
end

local function inner()
  return bar:getWidth() - 16 - 4   -- padding da caixa + margem da barra
end

local function draw()
  local w = inner()
  bar:getChildById('frame'):getChildById('fill'):setWidth(math.max(0, math.floor(w * shown)))
  bar:getChildById('frame'):getChildById('trail'):setWidth(math.max(0, math.floor(w * trail)))
end

local function animate()
  animEvent = nil
  if not bar or not bar:isVisible() then return end
  local moving = false
  if math.abs(shown - target) > 0.001 then
    shown = shown + (target - shown) * 0.35
    moving = true
  else
    shown = target
  end
  if trail > shown then
    if trailHold > 0 then
      trailHold = trailHold - 1
    else
      trail = math.max(shown, trail - 0.012)
    end
    moving = true
  else
    trail = shown
  end
  draw()
  place()
  if moving then animEvent = scheduleEvent(animate, 30) end
end

local function kick()
  if not animEvent then animEvent = scheduleEvent(animate, 30) end
end

local function hideBar()
  if not bar then return end
  bar:hide()
  target, shown, trail = 0, 0, 0
end

local function onBar(protocol, opcode, buffer)
  local f = {}
  for field in (tostring(buffer or '') .. '|'):gmatch('(.-)|') do f[#f + 1] = field end
  if f[1] ~= 'E' or f[2] == '0' or not f[3] then
    hideBar()
    return
  end
  local hp, max = tonumber(f[4]) or 0, math.max(1, tonumber(f[5]) or 1)
  local pct = math.max(0, math.min(1, hp / max))
  local wasHidden = not bar:isVisible()
  bar:getChildById('title'):setText('EMPERIUM  -  ' .. tostring(f[3]):upper())
  bar:getChildById('frame'):getChildById('value'):setText(fmt(hp) .. ' / ' .. fmt(max) .. '   (' .. math.floor(pct * 100 + 0.5) .. '%)')
  bar:getChildById('owner'):setText('Dono: ' .. tostring(f[6] or 'Sem dono'))
  -- cor: vermelho; abaixo de 25% pisca mais forte
  bar:getChildById('frame'):getChildById('fill'):setBackgroundColor(pct <= 0.25 and '#ff4a3d' or '#c9372f')
  if wasHidden then
    shown, trail, target = pct, pct, pct
    bar:show()
    bar:raise()
    place()
    draw()
    return
  end
  if pct < target then trailHold = 12 end   -- o rastro espera um pouco antes de descer
  if pct > trail then trail = pct end
  target = pct
  kick()
end

function init()
  g_ui.importStyle('bossbar')
  bar = g_ui.createWidget('BossBar', rootWidget)
  bar:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onBar)
  connect(g_game, {onGameEnd = hideBar})
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, {onGameEnd = hideBar})
  if animEvent then removeEvent(animEvent) animEvent = nil end
  if bar then bar:destroy() bar = nil end
end
