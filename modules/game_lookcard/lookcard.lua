-- ============================================================
-- LOOK EM CARTAO (cliente) - opcode 105
-- Servidor: data/lib/core/lookcard.lua
-- O servidor manda o cartao quando o jogador da Look. O cliente
-- nunca envia nada por este opcode.
-- ============================================================

local OPCODE = 105
local SHOW_TIME = 8000
local OFFSET_X = 40   -- distancia a direita do personagem
local OFFSET_Y = -90  -- negativo = mais para cima

local root = nil
local card = nil
local hideEvent = nil

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    fields[#fields + 1] = field
  end
  return fields
end

-- texto escuro em fundo claro, branco em fundo escuro
local function textColorFor(hex)
  local r = tonumber(hex:sub(2, 3), 16) or 0
  local g = tonumber(hex:sub(4, 5), 16) or 0
  local b = tonumber(hex:sub(6, 7), 16) or 0
  return (r * 0.299 + g * 0.587 + b * 0.114) > 150 and '#0a1320' or '#ffffff'
end

local function destroyCard()
  if hideEvent then
    removeEvent(hideEvent)
    hideEvent = nil
  end
  if card then
    card:destroy()
    card = nil
  end
end

local function lineHeight(text, charsPerLine)
  local lines = math.max(1, math.ceil(#(text or '') / charsPerLine))
  return lines * 14 + 1
end

local ZEBRA = { '#0a1320', '#0c1828' }

local function build(lines)
  destroyCard()
  local mapPanel = modules.game_interface.getMapPanel()
  if not root or not mapPanel then return end

  card = g_ui.createWidget('LcCard', root)
  -- ao lado do personagem (o personagem fica no centro do mapa)
  card:addAnchor(AnchorLeft, 'parent', AnchorHorizontalCenter)
  card:addAnchor(AnchorTop, 'parent', AnchorVerticalCenter)
  card:setMarginLeft(OFFSET_X)
  card:setMarginTop(OFFSET_Y)

  local topBar = g_ui.createWidget('LcTopBar', card)
  local header, tags, pendingGrid = nil, nil, nil
  local accent = '#f2c400'
  local zebra = 0
  local function stripe(widget)
    zebra = zebra + 1
    widget:setBackgroundColor(ZEBRA[zebra % 2 + 1])
  end

  for _, line in ipairs(lines) do
    local f = splitFields(line)
    local kind = f[1]
    if kind == 'H' then
      accent = (f[5] and f[5]:match('^#%x+$')) and f[5] or '#f2c400'
      header = g_ui.createWidget('LcHeader', card)
      header:getChildById('title'):setText(f[3] or '')
      local sub = header:getChildById('subtitle')
      sub:setText(f[4] or '')
      sub:setVisible((f[4] or '') ~= '')
      card:setBorderColor(accent)
      topBar:setBackgroundColor(accent)
      header:getChildById('slot'):setBorderColor(accent)
    elseif kind == 'IC' and header then
      if f[2] == 'I' then
        local item = header:getChildById('item')
        item:setVisible(true)
        item:setItemId(tonumber(f[3]) or 0)
        local count = tonumber(f[4]) or 1
        if count > 1 then item:setItemCount(count) end
      elseif f[2] == 'C' then
        local creature = header:getChildById('creature')
        local outfit = {
          type = tonumber(f[3]) or 0, head = tonumber(f[4]) or 0, body = tonumber(f[5]) or 0,
          legs = tonumber(f[6]) or 0, feet = tonumber(f[7]) or 0, addons = tonumber(f[8]) or 0,
          auxType = tonumber(f[9]) or 0,
        }
        if outfit.type > 0 then
          creature:setVisible(true)
          creature:setOutfit(outfit)
        elseif outfit.auxType > 0 then
          local item = header:getChildById('item')
          item:setVisible(true)
          item:setItemId(outfit.auxType)
        end
      end
    elseif kind == 'TG' then
      if not tags then tags = g_ui.createWidget('LcTags', card) end
      local tag = g_ui.createWidget('LcTag', tags)
      local color = (f[3] and f[3]:match('^#%x+$')) and f[3] or '#24415f'
      local text = f[2] or ''
      tag:setText(text)
      tag:setBackgroundColor(color)
      tag:setColor(textColorFor(color))
      -- largura = texto + 8px de cada lado (texto sempre centralizado)
      local width = nil
      pcall(function() width = tag:getTextSize().width end)
      if not width or width <= 0 then width = #text * 7 end
      tag:setWidth(width + 16)
    elseif kind == 'SC' then
      pendingGrid = nil
      zebra = 0
      local section = g_ui.createWidget('LcSection', card)
      section:getChildById('title'):setText(f[2] or '')
      local color = (f[2] == 'STAFF') and '#e04848' or accent
      section:getChildById('bar'):setBackgroundColor(color)
      section:getChildById('title'):setColor(color)
      if f[2] == 'STAFF' then section:setBackgroundColor('#2a1418') end
    elseif kind == 'GR' then
      if pendingGrid then
        pendingGrid:getChildById('label2'):setText(f[2] or '')
        pendingGrid:getChildById('value2'):setText(f[3] or '')
        pendingGrid = nil
      else
        pendingGrid = g_ui.createWidget('LcGrid', card)
        stripe(pendingGrid)
        pendingGrid:getChildById('label1'):setText(f[2] or '')
        pendingGrid:getChildById('value1'):setText(f[3] or '')
      end
    elseif kind == 'RW' then
      pendingGrid = nil
      local row = g_ui.createWidget('LcRow', card)
      stripe(row)
      row:getChildById('label'):setText(f[2] or '')
      local value = row:getChildById('value')
      value:setText(f[3] or '')
      if f[4] and f[4]:match('^#%x+$') then value:setColor(f[4]) end
      local h = lineHeight(f[3], 32)
      row:setHeight(h + 3)
      value:setHeight(h)
    elseif kind == 'TX' then
      pendingGrid = nil
      local text = g_ui.createWidget('LcText', card)
      text:setText(f[2] or '')
    end
  end
  g_ui.createWidget('LcSpacer', card)

  -- qualquer clique (esquerdo ou direito) fecha
  card:setPhantom(false)
  card.onMousePress = function()
    destroyCard()
    return true
  end
  hideEvent = scheduleEvent(function()
    hideEvent = nil
    destroyCard()
  end, SHOW_TIME)
end

-- clique no mapa tambem fecha (o Look com botao direito abre o proximo)
local function onMapMousePress()
  if card then destroyCard() end
  return false
end

local function onLookOpcode(protocol, opcode, buffer)
  local lines = {}
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then lines[#lines + 1] = line end
  end
  if #lines == 0 then return end
  local ok, err = pcall(build, lines)
  if not ok then
    g_logger.error('[LookCard] ' .. tostring(err))
    destroyCard()
  end
end

local function onGameEnd()
  destroyCard()
end

function init()
  root = g_ui.loadUI('lookcard', modules.game_interface.getRootPanel())
  ProtocolGame.registerExtendedOpcode(OPCODE, onLookOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  local mapPanel = modules.game_interface.getMapPanel()
  if mapPanel then connect(mapPanel, { onMousePress = onMapMousePress }, true) end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  local mapPanel = modules.game_interface.getMapPanel()
  if mapPanel then disconnect(mapPanel, { onMousePress = onMapMousePress }) end
  destroyCard()
  if root then
    root:destroy()
    root = nil
  end
end
