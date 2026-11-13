-- ============================================================
-- FUNDIR HELDS (cliente) - opcode 125
-- Abre pelo Vendedor de Helds: diga "fundir".
-- 3 helds iguais do mesmo tier = 1 do tier seguinte (custo do banco).
-- ============================================================
local OPCODE = 125
local window = nil

local function W(id) return window and window:recursiveGetChildById(id) or nil end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function split(line)
  local f = {}
  for v in (line .. '|'):gmatch('(.-)|') do f[#f + 1] = v end
  return f
end

local function money(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  while true do
    local r, k = s:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
    s = r
    if k == 0 then break end
  end
  return s
end

local function render(buffer)
  local list = W('list')
  list:destroyChildren()
  local lines = {}
  for l in (buffer .. '\n'):gmatch('(.-)\n') do if l ~= '' then lines[#lines + 1] = l end end
  local head = split(lines[1] or 'HF|0|3')
  local balance, need = tonumber(head[2]) or 0, tonumber(head[3]) or 3
  local rows = 0
  for i = 2, #lines do
    local f = split(lines[i])
    if f[1] == 'R' then
      rows = rows + 1
      local id, cid, name, count, tier = f[2], tonumber(f[3]) or 0, f[4], tonumber(f[5]) or 0, tonumber(f[6]) or 1
      local nid, ncid, nname, cost = tonumber(f[8]) or 0, tonumber(f[9]) or 0, f[10], tonumber(f[11]) or 0
      local row = g_ui.createWidget('HFRow', list)
      row:getChildById('fromItem'):setItemId(cid)
      row:getChildById('fromName'):setText(name .. '  [' .. (f[7] or 'X') .. ']')
      row:getChildById('fromCount'):setText('Voce tem ' .. count .. '  (tier ' .. tier .. ')')
      local one, all = row:getChildById('fuseOne'), row:getChildById('fuseAll')
      if nid == 0 then
        row:getChildById('arrow'):setText('')
        row:getChildById('toName'):setText('Tier maximo')
        row:getChildById('cost'):setText('')
        one:setEnabled(false)
        all:setEnabled(false)
      else
        row:getChildById('toItem'):setItemId(ncid)
        row:getChildById('toName'):setText(nname)
        local times = math.floor(count / need)
        if cost > 0 then times = math.min(times, math.floor(balance / cost)) end
        row:getChildById('cost'):setText(need .. 'x  =  1x' .. (cost > 0 and ('   |   ' .. money(cost) .. ' gp') or ''))
        one:setEnabled(times >= 1)
        all:setEnabled(times >= 2)
        all:setText(times >= 2 and ('x' .. times) or 'Todos')
        one.onClick = function() send('FUSE|' .. id .. '|1') end
        all.onClick = function() send('FUSE|' .. id .. '|' .. times) end
        if times < 1 then
          row:getChildById('cost'):setColor(count < need and '#8fa7c4' or '#ff6b6b')
        end
      end
    end
  end
  W('infoLabel'):setText('Junte ' .. need .. ' helds iguais (mesmo tipo e tier) para criar 1 do tier seguinte. 100% de sucesso. ' ..
    'Pago do banco: ' .. money(balance) .. ' gp.' .. (rows == 0 and '   Voce nao tem helds na mochila.' or ''))
end

local function onOpcode(protocol, opcode, buffer)
  if not window then return end
  if buffer:sub(1, 3) == 'HF|' then
    render(buffer)
    window:show()
    window:raise()
    window:focus()
  end
end

function hide()
  if window and window:isVisible() then
    window:hide()
    send('CLOSE')
  end
end

local function onGameEnd() if window then window:hide() end end

function init()
  window = g_ui.displayUI('heldfusion')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if window then window:destroy() window = nil end
end
