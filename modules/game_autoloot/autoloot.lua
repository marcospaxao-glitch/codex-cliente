-- ============================================================
-- AUTOLOOT - janela da lista de coleta automatica
-- Servidor: data/lib/autoloot.lua (opcode 92)
--
-- Adicionar item:
--   * buscar pelo nome e clicar no resultado (busca paginada);
--   * ou arrastar o item da mochila/bag para a janela.
-- Busca por ID: somente staff (o servidor informa no LIST).
-- ============================================================

-- texto direto (sem passar pelo sistema de traducao, evita spam no log)
local function T(text, ...)
  if select('#', ...) > 0 then
    return string.format(text, ...)
  end
  return text
end

local OPCODE = 92
local MODE_ALL = 0
local MODE_LIST = 1

local FILTER_HINTS = {
  name = 'Digite parte do nome (ex: stone, candy, gem)',
  id = 'Digite o ID do item (ex: 2160)'
}

local window = nil
local listPanel = nil
local resultsPanel = nil
local filter = 'name'
local state = { enabled = false, mode = MODE_ALL, max = 0, items = {}, staff = false }
local results = {}
local search = { query = '', mode = 'name', page = 1, pages = 1, total = 0 }
local clearArmed = false
local clearEvent = nil

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, text)
  end
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    fields[#fields + 1] = field
  end
  return fields
end

local function splitLines(buffer)
  local lines = {}
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then
      lines[#lines + 1] = line
    end
  end
  return lines
end

local function isListed(itemId)
  for _, entry in ipairs(state.items) do
    if entry.id == itemId then
      return true
    end
  end
  return false
end

local function itemTooltip(entry, extra)
  local text = entry.name
  if state.staff then
    text = text .. '\nID ' .. entry.id
  end
  if extra then
    text = text .. '\n' .. extra
  end
  return text
end

-- Item arrastado do inventario/bag -> manda a posicao para o servidor
local function onItemDrop(self, draggedWidget, mousePos)
  if not draggedWidget or draggedWidget:getClassName() ~= 'UIItem' then
    return false
  end
  local item = draggedWidget:getItem()
  if not item then
    return false
  end
  local pos = item:getPosition()
  if not pos or pos.x ~= 65535 then
    modules.game_textmessage.displayFailureMessage(T('Arraste um item do inventario ou de uma bag aberta.'))
    return false
  end
  send('ADDPOS|' .. pos.x .. '|' .. pos.y .. '|' .. pos.z)
  return true
end

local function refreshPager()
  if not window then return end
  local hasResults = search.total > 0
  local prev, nextButton = W('pagerPrev'), W('pagerNext')
  prev:setEnabled(hasResults and search.page > 1)
  nextButton:setEnabled(hasResults and search.page < search.pages)
  W('pagerLabel'):setText(hasResults and T('Pagina %d de %d', search.page, search.pages) or '')
end

local function refreshResults()
  if not window then return end
  resultsPanel:destroyChildren()
  for _, entry in ipairs(results) do
    local cell = g_ui.createWidget('ALResult', resultsPanel)
    cell:getChildById('itemIcon'):setItemId(entry.clientId)
    cell:getChildById('nameLabel'):setText(entry.name)
    local status = cell:getChildById('statusLabel')
    local listed = isListed(entry.id)
    if listed then
      status:setText(T('Na lista'))
      status:setColor('#5fd35f')
      cell:setBorderColor('#2f6b3a')
      cell:setTooltip(itemTooltip(entry, T('Ja esta na lista')))
    else
      status:setText(T('+ adicionar'))
      status:setColor('#6f86a8')
      cell:setTooltip(itemTooltip(entry, T('Clique para adicionar')))
    end
    cell.onClick = function()
      if not isListed(entry.id) then
        send('ADD|' .. entry.id)
      end
    end
    cell.onDrop = onItemDrop
  end
  refreshPager()
end

local function refreshFilter()
  if not window then return end
  if not state.staff then
    filter = 'name'
  end
  local nameButton, idButton = W('filterName'), W('filterId')
  nameButton:setVisible(state.staff)
  idButton:setVisible(state.staff)
  nameButton:setOn(filter == 'name')
  idButton:setOn(filter == 'id')
  W('searchEdit'):setTooltip(T(FILTER_HINTS[filter]))
  if #results == 0 and search.total == 0 then
    W('resultsInfo'):setText(T(FILTER_HINTS[filter]))
  end
end

local function setClearArmed(armed)
  clearArmed = armed
  if clearEvent then
    removeEvent(clearEvent)
    clearEvent = nil
  end
  local button = W('clearButton')
  if not button then return end
  if armed then
    button:setText(T('Confirmar'))
    button:setColor('#ff9a7a')
    clearEvent = scheduleEvent(function()
      clearEvent = nil
      setClearArmed(false)
    end, 4000)
  else
    button:setText(T('Limpar'))
    button:setColor('#dce8f5')
  end
end

local function refresh()
  if not window then return end

  -- status
  local on = state.enabled
  local color = on and '#5fd35f' or '#e04848'
  W('statusStripe'):setBackgroundColor(color)
  W('statusDot'):setBackgroundColor(color)
  local statusLabel = W('statusLabel')
  statusLabel:setText(on and T('AUTOLOOT LIGADO') or T('AUTOLOOT DESLIGADO'))
  statusLabel:setColor(color)
  local hint
  if not on then
    hint = T('Nenhum item sera coletado automaticamente.')
  elseif state.mode == MODE_LIST then
    hint = T('Coletando somente os itens da sua lista.')
  else
    hint = T('Coletando todos os itens dos corpos.')
  end
  W('statusHint'):setText(hint)

  local toggleButton = W('toggleButton')
  if on then
    toggleButton:setText(T('DESLIGAR'))
    toggleButton:setBackgroundColor('#7a1f1f')
    toggleButton:setBorderColor('#e04848')
  else
    toggleButton:setText(T('LIGAR'))
    toggleButton:setBackgroundColor('#1d5a31')
    toggleButton:setBorderColor('#5fd35f')
  end

  W('modeAllButton'):setOn(state.mode == MODE_ALL)
  W('modeListButton'):setOn(state.mode == MODE_LIST)

  -- lista
  listPanel:destroyChildren()
  for _, entry in ipairs(state.items) do
    local row = g_ui.createWidget('ALRow', listPanel)
    row:getChildById('itemIcon'):setItemId(entry.clientId)
    row:getChildById('nameLabel'):setText(entry.name)
    row:setTooltip(itemTooltip(entry))
    local removeButton = row:getChildById('removeButton')
    removeButton:setTooltip(T('Remover da lista'))
    removeButton.onClick = function()
      send('DEL|' .. entry.id)
    end
    row.onDrop = onItemDrop
  end

  W('listTitle'):setText(T('MINHA LISTA  %d / %d', #state.items, state.max))
  local usageBg, usage = W('listUsageBg'), W('listUsage')
  local ratio = state.max > 0 and math.min(1, #state.items / state.max) or 0
  usage:setWidth(math.floor(usageBg:getWidth() * ratio))
  usage:setBackgroundColor(ratio >= 1 and '#e04848' or (ratio >= 0.8 and '#ff9a3c' or '#f2c400'))
  W('clearButton'):setEnabled(#state.items > 0)
  if #state.items == 0 then setClearArmed(false) end

  local emptyLabel = W('emptyLabel')
  if #state.items == 0 then
    if state.mode == MODE_LIST then
      emptyLabel:setText(T('Lista vazia: nada sera coletado.'))
    else
      emptyLabel:setText(T('Lista vazia. No modo Tudo, coleta tudo.'))
    end
  else
    emptyLabel:setText('')
  end

  refreshFilter()
  -- marca na busca o que ja esta na lista
  refreshResults()
end

local function onListMessage(lines)
  local header = splitFields(lines[1])
  state.enabled = header[2] == '1'
  state.mode = tonumber(header[3]) or MODE_ALL
  state.max = tonumber(header[4]) or 0
  state.staff = header[5] == '1'
  state.items = {}
  for i = 2, #lines do
    local f = splitFields(lines[i])
    state.items[#state.items + 1] = {
      id = tonumber(f[1]) or 0,
      clientId = tonumber(f[2]) or 0,
      name = f[3] or '?'
    }
  end
  refresh()
end

-- RESULTS|modo|busca|total|pagina|paginas
local function onResultsMessage(lines)
  local header = splitFields(lines[1])
  search.total = tonumber(header[4]) or 0
  search.page = tonumber(header[5]) or 1
  search.pages = tonumber(header[6]) or 1
  results = {}
  for i = 2, #lines do
    local f = splitFields(lines[i])
    results[#results + 1] = {
      id = tonumber(f[1]) or 0,
      clientId = tonumber(f[2]) or 0,
      name = f[3] or '?'
    }
  end
  local info = W('resultsInfo')
  if search.total == 0 then
    info:setText(T('Nenhum item encontrado para "%s".', header[3] or ''))
    info:setColor('#ff9a7a')
  elseif search.total == 1 then
    info:setText(T('1 item encontrado.'))
    info:setColor('#8fa7c4')
  else
    info:setText(T('%d itens encontrados para "%s".', search.total, header[3] or ''))
    info:setColor('#8fa7c4')
  end
  refreshResults()
  local scroll = W('resultsScroll')
  if scroll then scroll:setValue(0) end
end

local function onAutolootOpcode(protocol, opcode, buffer)
  local lines = splitLines(buffer)
  if #lines == 0 or not window then return end
  local kind = splitFields(lines[1])[1]
  if kind == 'LIST' then
    onListMessage(lines)
  elseif kind == 'RESULTS' then
    onResultsMessage(lines)
  end
end

local function requestPage(page)
  if search.query == '' then return end
  W('resultsInfo'):setText(T('Buscando...'))
  W('resultsInfo'):setColor('#8fa7c4')
  send('SEARCH|' .. search.mode .. '|' .. search.query .. '|' .. page)
end

function init()
  window = g_ui.displayUI('autoloot')
  window:hide()
  listPanel = W('listPanel')
  resultsPanel = W('resultsPanel')

  window.onDrop = onItemDrop
  listPanel.onDrop = onItemDrop
  resultsPanel.onDrop = onItemDrop

  local searchEdit = W('searchEdit')
  searchEdit.onKeyPress = function(self, keyCode, keyboardModifiers)
    if keyCode == KeyEnter then
      doSearch()
      return true
    end
    return false
  end

  W('clearButton').onClick = function()
    if clearArmed then
      setClearArmed(false)
      send('CLEAR')
    else
      setClearArmed(true)
    end
  end

  ProtocolGame.registerExtendedOpcode(OPCODE, onAutolootOpcode)
  connect(g_game, { onGameEnd = hide })
  g_keyboard.bindKeyDown('Ctrl+Shift+A', toggle)
  refresh()
  refreshPager()
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = hide })
  g_keyboard.unbindKeyDown('Ctrl+Shift+A')
  if clearEvent then
    removeEvent(clearEvent)
    clearEvent = nil
  end
  if window then
    window:destroy()
    window = nil
  end
end

function show()
  if not g_game.isOnline() or not window then return end
  window:show()
  window:raise()
  window:focus()
  W('searchEdit'):focus()
  send('REQ')
end

function hide()
  if window then
    window:hide()
  end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

function toggleSystem()
  send('TOGGLE')
end

function setMode(mode)
  send('MODE|' .. mode)
end

function setFilter(newFilter)
  if not FILTER_HINTS[newFilter] then return end
  if newFilter == 'id' and not state.staff then return end
  filter = newFilter
  results = {}
  search = { query = '', mode = filter, page = 1, pages = 1, total = 0 }
  refreshResults()
  refreshFilter()
  W('searchEdit'):focus()
end

function doSearch()
  if not window then return end
  local text = W('searchEdit'):getText()
  text = text:gsub('^%s+', ''):gsub('%s+$', ''):gsub('|', '')
  if text == '' then return end
  local info = W('resultsInfo')
  if filter == 'id' and not tonumber(text) then
    info:setText(T('Digite so numeros para buscar por ID.'))
    return
  end
  if filter == 'name' and #text < 2 then
    info:setText(T('Digite pelo menos 2 letras.'))
    return
  end
  search.query = text
  search.mode = filter
  requestPage(1)
end

function prevPage()
  if search.page > 1 then
    requestPage(search.page - 1)
  end
end

function nextPage()
  if search.page < search.pages then
    requestPage(search.page + 1)
  end
end
