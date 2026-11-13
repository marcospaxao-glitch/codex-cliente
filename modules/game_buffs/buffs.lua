-- ============================================================
-- EFEITOS COM TEMPO (cliente) - opcode 84
-- Mostra no canto esquerdo do mapa cada efeito ativo (lupa, captura,
-- exp, loot...): icone do item, nome e o tempo correndo.
-- So recebe do servidor; o relogio corre aqui (nao envia nada).
-- ============================================================

local OPCODE = 84
local ICONS = '/modules/game_buffs/images/'   -- <icon>.png (catch, exp, loot, amizade...)
MARGIN_X = 8     -- distancia da borda esquerda do mapa
MARGIN_Y = 50     -- distancia do topo do mapa

local panel = nil
local buffs = {}       -- lista { key, left, total, clientId, name, color, desc }
local tickEvent = nil

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do fields[#fields + 1] = field end
  return fields
end

local function clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  if seconds >= 3600 then
    return string.format('%d:%02d:%02d', math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60)
  end
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- fica sempre no canto de cima/esquerda do mapa (acompanha se a janela mudar)
local function placePanel()
  local map = mapPanel()
  if not panel or not map then return end
  local r = map:getRect()
  panel:setPosition({ x = r.x + MARGIN_X, y = r.y + MARGIN_Y })
end

local function render()
  if not panel then return end
  panel:destroyChildren()
  for _, b in ipairs(buffs) do
    local row = g_ui.createWidget('BuffRow', panel)
    b.row = row
    row:getChildById('stripe'):setBackgroundColor(b.color)
    row:getChildById('fill'):setBackgroundColor(b.color)
    row:getChildById('name'):setText(b.name)
    local item, icon = row:getChildById('item'), row:getChildById('icon')
    local png = b.icon ~= '' and (ICONS .. b.icon .. '.png') or nil
    if png and g_resources.fileExists(png) then
      icon:setImageSource(png)
      item:hide()
    else
      icon:hide()
      if b.clientId > 0 then item:setItemId(b.clientId) end
    end
    row:setTooltip(b.name .. (b.desc ~= '' and ('\n' .. b.desc) or ''))
  end
  panel:setVisible(#buffs > 0)
  if #buffs > 0 then panel:raise() end
  placePanel()
end

local function refreshRows()
  for _, b in ipairs(buffs) do
    local row = b.row
    if row and not row:isDestroyed() then
      local time = row:getChildById('time')
      time:setText(clock(b.left))
      if b.left <= 10 then
        time:setColor(b.left % 2 == 0 and '#e04848' or '#ffffff')
      else
        time:setColor('#f2c400')
      end
      local back = row:getChildById('back')
      local width = back:getWidth()
      if width <= 0 then width = 105 end
      row:getChildById('fill'):setWidth(math.floor(width * math.min(1, b.left / math.max(1, b.total))))
    end
  end
end

local function tick()
  tickEvent = nil
  local changed = false
  for i = #buffs, 1, -1 do
    local b = buffs[i]
    b.left = b.left - 1
    if b.left <= 0 then
      table.remove(buffs, i)
      changed = true
    end
  end
  if changed then render() end
  refreshRows()
  placePanel()
  if #buffs > 0 then tickEvent = scheduleEvent(tick, 1000) end
end

local function onBuffs(protocol, opcode, buffer)
  local old = {}
  for _, b in ipairs(buffs) do old[b.key] = b end
  buffs = {}
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'B' then
      local left = tonumber(f[3]) or 0
      local prev = old[f[2]]
      -- total = maior tempo visto (para a barrinha); usar outro item aumenta
      local total = math.max(left, prev and prev.total or 0)
      if prev and left > prev.left + 2 then total = left end
      buffs[#buffs + 1] = { key = f[2], left = left, total = total, clientId = tonumber(f[4]) or 0,
        name = f[5] or '?', color = (f[6] or '') ~= '' and f[6] or '#f2c400', desc = f[7] or '', icon = f[8] or '' }
    end
  end
  render()
  refreshRows()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if #buffs > 0 then tickEvent = scheduleEvent(tick, 1000) end
end

local function onGameEnd()
  buffs = {}
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  render()
end

function init()
  g_ui.importStyle('buffs')
  panel = g_ui.createWidget('BuffPanel', rootWidget)
  panel:setVisible(false)
  ProtocolGame.registerExtendedOpcode(OPCODE, onBuffs)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if tickEvent then removeEvent(tickEvent) end
  if panel then panel:destroy() panel = nil end
end
