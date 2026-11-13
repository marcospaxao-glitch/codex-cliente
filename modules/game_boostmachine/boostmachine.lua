-- ============================================================
-- MAQUINA DE BOOST (cliente) - opcode 126
-- O botao da maquina abre esta janela com o calculo; o boost so
-- acontece ao clicar Confirmar (o servidor confere tudo de novo).
-- Custo por nivel = ceil(1.3 x boost novo) stones.
-- ============================================================
local OPCODE = 126
local window = nil
local m = nil          -- dados da maquina
local target = 0

local function W(id) return window and window:recursiveGetChildById(id) or nil end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function cost(level) return math.ceil(1.3 * level) end
local function costRange(from, to)
  local t = 0
  for b = from + 1, to do t = t + cost(b) end
  return t
end

local function update()
  if not m then return end
  target = math.max(m.boost + 1, math.min(m.max, target))
  local need = costRange(m.boost, target)
  local ok = need <= m.stones
  W('targetLabel'):setText('+' .. m.boost .. '  ->  +' .. target)
  W('calc1'):setText('Stones gastas: ' .. need .. '  (tem ' .. m.stones .. ')')
  W('calc1'):setColor(ok and '#7dff8a' or '#ff6b6b')
  W('calc2'):setText('Sobram na maquina: ' .. math.max(0, m.stones - need) ..
    (ok and '' or ('   |   faltam ' .. (need - m.stones))))
  W('calc3'):setText('Status (HP, Atk, Def, Sp.Atk, Sp.Def): +' .. (m.boost * m.pct) .. '%  ->  +' .. (target * m.pct) .. '%')
  W('calc4'):setText('Proximo nivel (+' .. (target + 1 <= m.max and (target + 1) or m.max) .. ') custa ' ..
    (target < m.max and cost(target + 1) or 0) .. ' stones')
  W('calc5'):setText('Com essas stones da para ir ate +' .. m.reach .. '  (maximo +' .. m.max .. ')')
  W('confirmButton'):setEnabled(ok)
  W('confirmButton'):setText(ok and ('Confirmar +' .. target) or 'Faltam stones')
  W('minus'):setEnabled(target > m.boost + 1)
  W('plus'):setEnabled(target < m.max)
  W('plus5'):setEnabled(target < m.max)
end

local function onOpcode(protocol, opcode, buffer)
  if not window then return end
  local f = {}
  for v in (buffer .. '|'):gmatch('(.-)|') do f[#f + 1] = v end
  if f[1] == 'BM' then
    m = { name = f[2], look = tonumber(f[3]) or 0, boost = tonumber(f[4]) or 0, max = tonumber(f[5]) or 50,
      stones = tonumber(f[6]) or 0, stoneName = f[7], stoneClient = tonumber(f[8]) or 0,
      reach = tonumber(f[9]) or 0, pct = tonumber(f[10]) or 1 }
    W('poke'):setOutfit({ type = m.look })
    W('pokeName'):setText(m.name)
    W('boostNow'):setText('Boost atual: +' .. m.boost .. '  (maximo +' .. m.max .. ')')
    W('stoneItem'):setItemId(m.stoneClient)
    W('stoneInfo'):setText(m.stones .. 'x ' .. m.stoneName)
    target = m.reach > m.boost and m.reach or m.boost + 1
    update()
    window:show()
    window:raise()
    window:focus()
  elseif f[1] == 'DONE' then
    m = nil
    window:hide()
  end
end

function hide()
  if window and window:isVisible() then
    window:hide()
    m = nil
    send('CLOSE')
  end
end

local function onGameEnd() if window then window:hide() end m = nil end

function init()
  window = g_ui.displayUI('boostmachine')
  window:hide()
  W('minus').onClick = function() target = target - 1 update() end
  W('plus').onClick = function() target = target + 1 update() end
  W('plus5').onClick = function() target = target + 5 update() end
  W('maxButton').onClick = function()
    if m then target = m.reach > m.boost and m.reach or m.max end
    update()
  end
  W('confirmButton').onClick = function()
    if m then send('CONFIRM|' .. target) end
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if window then window:destroy() window = nil end
end
