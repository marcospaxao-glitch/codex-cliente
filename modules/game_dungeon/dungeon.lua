-- ============================================================
-- TERMINAL DE DUNGEONS (Codex) - opcode 113
-- Abre quando o jogador usa o terminal (item 34087) no jogo.
-- Arte: a mesma do modulo antigo (banners e cartas), em arte/.
-- ============================================================
local OPCODE = 113
local ART = '/modules/game_dungeon/arte/'

local window = nil
local listPanel = nil
local tokens = 0
local rows = {}
local selectedKey = nil
local cards = {}

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

local function art(key, suffix)
  local path = ART .. key .. (suffix or '') .. '.png'
  if g_resources.fileExists(path) then return path end
  return nil
end

local function find(key)
  for _, d in ipairs(rows) do
    if d.key == key then return d end
  end
  return nil
end

local function showDetail(d)
  local detail = window:getChildById('detail')
  local enter = detail:getChildById('enterButton')
  if not d then
    detail:getChildById('name'):setText('')
    detail:getChildById('roomsInfo'):setText('Escolha uma dungeon')
    detail:getChildById('priceInfo'):setText('')
    enter:setEnabled(false)
    return
  end
  detail:getChildById('art'):setImageSource(art(d.key, '_info') or '')
  detail:getChildById('name'):setText(d.name:upper())
  local rooms, price = detail:getChildById('roomsInfo'), detail:getChildById('priceInfo')
  enter:setTooltip('')
  if not d.active then
    rooms:setText('Em breve')
    rooms:setColor('#6f86a8')
    price:setText('')
    enter:setEnabled(false)
    return
  end
  rooms:setText('Salas livres: ' .. d.free .. ' de ' .. d.rooms)
  rooms:setColor(d.free > 0 and '#5fd35f' or '#ff6b6b')
  price:setText('Entrada: ' .. d.price .. ' tokens')
  price:setColor(tokens >= d.price and '#dce8f5' or '#ff6b6b')
  local can = d.free > 0 and tokens >= d.price
  enter:setEnabled(can)
  if tokens < d.price then
    enter:setTooltip('Faltam ' .. (d.price - tokens) .. ' tokens')
  elseif d.free == 0 then
    enter:setTooltip('Todas as salas ocupadas')
  end
  enter.onClick = function()
    local box
    box = displayGeneralBox('Entrar na dungeon', 'Entrar na ' .. d.name .. ' por ' .. d.price .. ' tokens?', {
      {text = 'Sim', callback = function() box:destroy() send('ENTER|' .. d.key) end},
      {text = 'Nao', callback = function() box:destroy() end},
      anchor = AnchorHorizontalCenter
    }, function() box:destroy() send('ENTER|' .. d.key) end, function() box:destroy() end)
  end
end

local function select(key)
  selectedKey = key
  for k, card in pairs(cards) do card:setOn(k == key) end
  showDetail(find(key))
end

local function render()
  if not window then return end
  listPanel:destroyChildren()
  cards = {}
  window:getChildById('bottomBar'):getChildById('tokens'):setText('Seus tokens: ' .. tokens)
  for _, d in ipairs(rows) do
    local card = g_ui.createWidget('DungeonCard', listPanel)
    local banner = art(d.key)
    if banner then card:getChildById('banner'):setImageSource(banner) end
    if d.active then
      local rooms = card:getChildById('rooms')
      rooms:setText(d.free > 0 and ('Salas ' .. d.free .. '/' .. d.rooms) or 'Lotada')
      rooms:setColor(d.free > 0 and '#5fd35f' or '#ff6b6b')
      local price = card:getChildById('price')
      price:setText(d.price .. ' tokens')
      if tokens < d.price then price:setBackgroundColor('#6f86a8') end
    else
      card:getChildById('rooms'):hide()
      card:getChildById('price'):hide()
      card:getChildById('shade'):show()
      card:getChildById('soon'):show()
    end
    card:setTooltip(d.name)
    card.onClick = function() select(d.key) end
    cards[d.key] = card
  end
  if not selectedKey or not find(selectedKey) then
    selectedKey = rows[1] and rows[1].key or nil
  end
  select(selectedKey)
end

local function onOpcode(protocol, opcode, buffer)
  buffer = tostring(buffer or '')
  if buffer == 'OPEN' then
    window:show()
    window:raise()
    window:focus()
    return
  elseif buffer == 'CLOSE' then
    hide()
    return
  end
  local newRows = nil
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = {}
    for field in (line .. '|'):gmatch('(.-)|') do f[#f + 1] = field end
    if f[1] == 'D' then
      tokens = tonumber(f[2]) or 0
      newRows = {}
    elseif f[1] == 'R' and newRows then
      newRows[#newRows + 1] = {key = f[2], name = f[3], poke = f[4], price = tonumber(f[5]) or 0,
        free = tonumber(f[6]) or 0, rooms = tonumber(f[7]) or 3, active = f[8] == '1'}
    end
  end
  if newRows then
    rows = newRows
    render()
  end
end

function init()
  window = g_ui.displayUI('dungeon')
  window:hide()
  listPanel = window:getChildById('list')
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, {onGameEnd = hide})
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, {onGameEnd = hide})
  if window then window:destroy() window = nil end
end
