-- ============================================================
-- TROCA (cliente) - opcode 87
-- Clique direito no jogador > "Trocar com Fulano".
-- Oferta: itens da mochila e pokemons da equipe.
-- Pronto (os dois) > Confirmar troca (os dois) > troca feita.
-- So envia opcodes a partir de cliques/teclas do jogador.
-- ============================================================

local OPCODE = 87
local POKE_ICON = '/modules/game_pokemonbar/bar_icon/'
local TABS = { 'BAG', 'TEAM' }
local TAB_HINT = {
  BAG = 'Itens da sua mochila. Escolha a quantidade e clique em Ofertar.',
  TEAM = 'Pokemons da sua equipe (recolha antes os que estao fora da ball).',
}

local window = nil
local inviteBox = nil
local inviteEvent = nil
local pendingParts = {}

local view = { tab = 'BAG', search = '' }
local listLines = {}
local mine, theirs = {}, {}
local theirKey = ''
local changedNotice = false
local st = { myReady = false, theirReady = false, myConfirm = false, theirConfirm = false }
local otherName = '?'
local maxEntries = 20

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

local function fmt(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  local formatted = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
  return (formatted:gsub('^%.', ''))
end

local function pokeIcon(name)
  local lower = tostring(name or ''):lower()
  local path = POKE_ICON .. lower .. '.png'
  if g_resources.fileExists(path) then return path end
  if lower:sub(1, 6) == 'shiny ' then
    local base = POKE_ICON .. lower:sub(7) .. '.png'
    if g_resources.fileExists(base) then return base end
  end
  return path
end

local function joinParts(buffer)
  local index, total, rest = buffer:match('^@P|(%d+)|(%d+)\n(.*)$')
  if not index then return buffer end
  index, total = tonumber(index), tonumber(total)
  if index == 1 then pendingParts = {} end
  pendingParts[index] = rest
  if index < total then return nil end
  local full = table.concat(pendingParts, '\n', 1, total)
  pendingParts = {}
  return full
end

local function styleTab(button, active)
  button:setColor(active and '#1a1200' or '#dce8f5')
  button:setBackgroundColor(active and '#f2c400' or '#101f3e')
  button:setBorderColor(active and '#ffe27a' or '#24415f')
end

local function styleStatus(label, confirmed, ready)
  if confirmed then
    label:setText('Confirmado')
    label:setColor('#0a1320')
    label:setBackgroundColor('#5fd35f')
    label:setBorderColor('#a6f0a6')
  elseif ready then
    label:setText('Pronto')
    label:setColor('#1a1200')
    label:setBackgroundColor('#f2c400')
    label:setBorderColor('#ffe27a')
  else
    label:setText('Montando')
    label:setColor('#8fa7c4')
    label:setBackgroundColor('#101f3e')
    label:setBorderColor('#24415f')
  end
end

-- quanto deste item/pokemon ja esta na minha oferta
local function offered(kind, ref)
  for _, entry in ipairs(mine) do
    if entry.kind == kind and entry.ref == ref then
      return entry.count, entry
    end
  end
  return 0, nil
end

-- ============================================================
-- seletor (mochila / equipe)
-- ============================================================
local function renderList()
  if not window then return end
  local grid = W('grid')
  grid:destroyChildren()
  local shown = 0
  for _, f in ipairs(listLines) do
    if f[1] == 'P' or f[1] == 'I' then
      shown = shown + 1
      local poke = f[1] == 'P'
      local card = g_ui.createWidget('TradeCard', grid)
      local qty, add = card:getChildById('qty'), card:getChildById('addButton')
      local ref = tonumber(f[2]) or 0
      local name = f[4] or '?'
      card:setTooltip(name)
      if poke then
        local level, iv, busy = f[5] or '1', tonumber(f[6]) or -1, f[7] == '1'
        card:getChildById('item'):setVisible(false)
        card:getChildById('portrait'):setVisible(true)
        card:getChildById('portrait'):setImageSource(pokeIcon(name))
        card:getChildById('name'):setText(name)
        card:getChildById('sub'):setText('Lv ' .. level .. (iv >= 0 and ('  |  IV ' .. iv .. '%') or ''))
        qty:setVisible(false)
        add:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        add:setMarginLeft(6)
        local inOffer = offered('T', ref) > 0
        if busy then
          add:setEnabled(false)
          add:setText('Fora da ball')
          card:setTooltip(name .. ' esta fora da ball. Recolha para oferecer.')
        else
          add:setEnabled(not inOffer)
          add:setText(inOffer and 'Na troca' or '+ Ofertar')
        end
        card:setBorderColor(inOffer and '#2e7d4a' or '#1d3557')
        add.onClick = function()
          send('ADD|T|' .. ref)
        end
      else
        local total = tonumber(f[5]) or 1
        local inOffer = offered('B', ref)
        local left = math.max(0, total - inOffer)
        card:getChildById('item'):setItemId(tonumber(f[3]) or 0)
        card:getChildById('name'):setText(name)
        card:getChildById('sub'):setText(inOffer > 0 and ('Tem ' .. fmt(total) .. '  |  troca ' .. fmt(inOffer)) or ('Tem: ' .. fmt(total)))
        qty:setText(tostring(left))
        add:setEnabled(left > 0)
        add:setText(left > 0 and '+ Ofertar' or 'Na troca')
        card:setBorderColor(inOffer > 0 and '#2e7d4a' or '#1d3557')
        add.onClick = function()
          local amount = math.max(1, math.min(left, tonumber((qty:getText() or ''):match('%d+')) or 1))
          send('ADD|B|' .. ref .. '|' .. amount)
        end
        qty.onKeyPress = function(widget, keyCode)
          if (keyCode == KeyEnter or keyCode == KeyReturn) and add:isEnabled() then
            add.onClick()
            return true
          end
          return false
        end
      end
    end
  end
  for _, tab in ipairs(TABS) do
    styleTab(W('tab' .. tab), tab == view.tab)
  end
  W('listHint'):setText(shown > 0 and TAB_HINT[view.tab] or (view.tab == 'TEAM' and 'Nenhum pokemon na equipe.' or 'Nada encontrado na mochila.'))
end

local function requestList(tab)
  view.tab = tab or view.tab
  local search = W('searchEdit'):getText():gsub('[|\n\r]', ''):sub(1, 30)
  send('LIST|' .. view.tab .. '|' .. search)
end

-- ============================================================
-- ofertas
-- ============================================================
local function fillRow(row, entry, removable)
  if entry.kind == 'T' then
    row:getChildById('item'):setVisible(false)
    row:getChildById('portrait'):setVisible(true)
    row:getChildById('portrait'):setImageSource(pokeIcon(entry.name))
    row:getChildById('name'):setText(entry.name)
    row:getChildById('sub'):setText('Pokemon  |  Lv ' .. entry.level .. (entry.iv >= 0 and ('  |  IV ' .. entry.iv .. '%') or ''))
    row:getChildById('sub'):setColor('#f2c400')
  else
    row:getChildById('item'):setItemId(entry.clientId)
    row:getChildById('name'):setText(entry.name)
    row:getChildById('sub'):setText('Quantidade: ' .. fmt(entry.count))
  end
  row:setTooltip(entry.name)
  local remove = row:getChildById('removeButton')
  if removable then
    remove:setTooltip('Tirar da troca')
    remove.onClick = function() send('DEL|' .. entry.index) end
  else
    remove:setVisible(false)
    row:getChildById('name'):setMarginRight(8)
  end
end

local function renderOffers()
  if not window then return end
  local myList, theirList = W('myList'), W('theirList')
  myList:destroyChildren()
  theirList:destroyChildren()
  for _, entry in ipairs(mine) do
    fillRow(g_ui.createWidget('TradeRow', myList), entry, true)
  end
  for _, entry in ipairs(theirs) do
    local row = g_ui.createWidget('TradeRow', theirList)
    fillRow(row, entry, false)
    if changedNotice then row:setBorderColor('#8a6d00') end
  end
  local pokes, items = 0, 0
  for _, entry in ipairs(theirs) do
    if entry.kind == 'T' then pokes = pokes + 1 else items = items + 1 end
  end
  W('myCount'):setText(#mine .. '/' .. maxEntries .. ' linhas')
  W('theirCount'):setText(#theirs == 0 and 'Nada ainda.' or (pokes .. ' pokemon(s)  |  ' .. items .. ' tipo(s) de item'))
  styleStatus(W('myStatus'), st.myConfirm, st.myReady)
  styleStatus(W('theirStatus'), st.theirConfirm, st.theirReady)

  local empty = #mine == 0 and #theirs == 0
  W('readyButton'):setEnabled(not st.myReady and not empty)
  W('confirmButton'):setEnabled(st.myReady and st.theirReady and not st.myConfirm)
  local stage, color = '', '#dce8f5'
  if changedNotice and not st.myReady then
    stage, color = 'A oferta de ' .. otherName .. ' mudou. Confira antes de aceitar.', '#f2c400'
  elseif empty then
    stage = 'Escolha itens e pokemons a esquerda para montar sua oferta.'
  elseif not st.myReady then
    stage = 'Quando terminar, clique em Pronto.'
  elseif not st.theirReady then
    stage, color = 'Aguardando ' .. otherName .. ' ficar pronto...', '#8fa7c4'
  elseif not st.myConfirm then
    stage, color = 'Os dois estao prontos. Confira tudo e clique em Confirmar troca.', '#5fd35f'
  else
    stage, color = 'Aguardando ' .. otherName .. ' confirmar...', '#8fa7c4'
  end
  W('stageLabel'):setText(stage)
  W('stageLabel'):setColor(color)
  renderList()
end

local function parseEntry(f)
  return {
    index = tonumber(f[2]) or 0, kind = f[3], clientId = tonumber(f[4]) or 0, name = f[5] or '?',
    count = tonumber(f[6]) or 1, level = tonumber(f[7]) or 0, iv = tonumber(f[8]) or -1, ref = tonumber(f[9]) or 0,
  }
end

local function showState(buffer)
  local wasReady = st.myReady
  local newMine, newTheirs = {}, {}
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'STATE' then
      st.myReady, st.theirReady = f[2] == '1', f[3] == '1'
      st.myConfirm, st.theirConfirm = f[4] == '1', f[5] == '1'
    elseif f[1] == 'M' then
      newMine[#newMine + 1] = parseEntry(f)
    elseif f[1] == 'O' then
      newTheirs[#newTheirs + 1] = parseEntry(f)
    end
  end
  local parts = {}
  for _, entry in ipairs(newTheirs) do parts[#parts + 1] = entry.kind .. entry.ref .. 'x' .. entry.count end
  local key = table.concat(parts, ',')
  if key ~= theirKey then
    changedNotice = theirKey ~= '' or wasReady
    theirKey = key
  end
  mine, theirs = newMine, newTheirs
  renderOffers()
end

-- ============================================================
-- convite
-- ============================================================
local function closeInvite()
  if inviteEvent then
    removeEvent(inviteEvent)
    inviteEvent = nil
  end
  if inviteBox then
    inviteBox:destroy()
    inviteBox = nil
  end
end

local function showInvite(f)
  closeInvite()
  local fromId, name, level, seconds = tonumber(f[2]) or 0, f[3] or '?', f[4] or '?', tonumber(f[5]) or 30
  inviteBox = g_ui.createWidget('TradeInvite', rootWidget)
  inviteBox:getChildById('inviteText'):setText(name .. ' (Lv ' .. level .. ') quer trocar itens/pokemons com voce.')
  inviteBox:getChildById('acceptInvite').onClick = function()
    send('ANSWER|' .. fromId .. '|1')
    closeInvite()
  end
  inviteBox:getChildById('refuseInvite').onClick = function()
    send('ANSWER|' .. fromId .. '|0')
    closeInvite()
  end
  local left = seconds
  local function tick()
    if not inviteBox then return end
    if left <= 0 then
      closeInvite() -- expira sozinho (sem mandar nada ao servidor)
      return
    end
    inviteBox:getChildById('inviteTime'):setText('Expira em ' .. left .. 's')
    left = left - 1
    inviteEvent = scheduleEvent(tick, 1000)
  end
  tick()
  inviteBox:raise()
  inviteBox:focus()
end

-- ============================================================
-- servidor
-- ============================================================
local function openWindow(f)
  otherName = f[3] or '?'
  maxEntries = tonumber(f[5]) or 20
  mine, theirs, listLines = {}, {}, {}
  theirKey, changedNotice = '', false
  st = { myReady = false, theirReady = false, myConfirm = false, theirConfirm = false }
  view = { tab = 'BAG', search = '' }
  W('searchEdit'):setText('')
  W('titleLabel'):setText('TROCA COM ' .. otherName:upper())
  W('subtitleLabel'):setText('Lv ' .. (f[4] or '?') .. '  |  fiquem a ate ' .. (f[6] or '3') .. ' sqm')
  W('theirTitle'):setText('OFERTA DE ' .. otherName:upper())
  renderOffers()
  window:show()
  window:raise()
  window:focus()
end

local function onTradeOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  local head = buffer:match('^([^|\n]*)')
  if head == 'INVITE' then
    showInvite(splitFields(buffer))
  elseif head == 'OPEN' then
    closeInvite()
    openWindow(splitFields(buffer))
  elseif head == 'LIST' then
    listLines = {}
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'LIST' then
        view.tab = f[2] or view.tab
      else
        listLines[#listLines + 1] = f
      end
    end
    renderList()
  elseif head == 'STATE' then
    showState(buffer)
  elseif head == 'DONE' or head == 'CLOSE' then
    window:hide()
    mine, theirs, listLines = {}, {}, {}
  end
end

-- ============================================================
-- acoes
-- ============================================================
function invite(creature)
  if not creature or not creature:isPlayer() or creature:isLocalPlayer() then return end
  send('INVITE|' .. creature:getId() .. '|' .. creature:getName())
end

function cancel()
  if window and window:isVisible() then
    window:hide()
    send('CANCEL')
  end
end

local function onGameEnd()
  closeInvite()
  if window then window:hide() end
  mine, theirs, listLines = {}, {}, {}
end

function init()
  window = g_ui.displayUI('trade')
  window:hide()
  for _, tab in ipairs(TABS) do
    W('tab' .. tab).onClick = function()
      W('searchEdit'):setText('')
      requestList(tab)
    end
  end
  W('searchButton').onClick = function() requestList(view.tab) end
  W('searchEdit').onKeyPress = function(widget, keyCode)
    if keyCode == KeyEnter or keyCode == KeyReturn then
      requestList(view.tab)
      return true
    end
    return false
  end
  W('readyButton').onClick = function()
    changedNotice = false
    send('READY')
  end
  W('confirmButton').onClick = function() send('CONFIRM') end
  W('cancelButton').onClick = cancel
  W('closeButton').onClick = cancel
  ProtocolGame.registerExtendedOpcode(OPCODE, onTradeOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  closeInvite()
  if window then
    window:destroy()
    window = nil
  end
end
