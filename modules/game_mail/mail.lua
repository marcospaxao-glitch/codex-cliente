-- ============================================================
-- CORREIO (cliente) - opcode 99
-- Abre pelo terminal de correio. Escolha o destinatario pelo ID,
-- monte a encomenda (equipe, PC pokemons, PC itens, mochila) e envie.
-- So envia opcodes a partir de cliques/teclas do jogador.
-- ============================================================

local OPCODE = 99
local POKE_ICON = '/modules/game_pokemonbar/bar_icon/'
local TABS = { 'TEAM', 'PCP', 'PCI', 'BAG' }
local TAB_HINT = {
  TEAM = 'Pokemons da sua equipe (os que estao fora da ball nao aparecem).',
  PCP = 'Pokemons guardados no seu PC.',
  PCI = 'Itens guardados no seu PC.',
  BAG = 'Itens da sua mochila.',
}
local SHORT = { ['Pokebolas'] = 'Balls', ['Mega Stones'] = 'Megas', ['Held Items'] = 'Held', ['Vitaminas'] = 'Vitamin.' }

local window = nil
local view = { tab = 'TEAM', page = 1, pages = 1, search = '', category = 0 }
local basket = {}          -- { key, kind, ref, count, name, clientId, poke }
local recipient = nil      -- { id, name }
local myId = 0
local fee = 0
local maxEntries = 30
local balance = 0
local sendArmed = false
local pendingParts = {}

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

local function requestList(tab, page, category)
  view.tab = tab or view.tab
  local search = W('searchEdit'):getText():gsub('[|\n\r]', ''):sub(1, 30)
  send('LIST|' .. view.tab .. '|' .. (page or 1) .. '|' .. search .. '|' .. (category or view.category or 0))
end

-- ============================================================
-- encomenda (cesta)
-- ============================================================
local function basketKey(kind, ref)
  return kind .. ':' .. ref
end

local function findBasket(key)
  for i, entry in ipairs(basket) do
    if entry.key == key then return i, entry end
  end
  return nil
end

local renderBasket

local function resetSend()
  sendArmed = false
  local button = W('sendButton')
  if button then button:setText('Enviar encomenda') end
end

local function addToBasket(entry)
  local index, existing = findBasket(entry.key)
  if existing then
    if entry.poke then return end
    existing.count = math.min(entry.max, existing.count + entry.count)
  else
    if #basket >= maxEntries then
      modules.game_textmessage.displayFailureMessage('A encomenda aceita no maximo ' .. maxEntries .. ' linhas.')
      return
    end
    basket[#basket + 1] = entry
  end
  resetSend()
  renderBasket()
end

renderBasket = function()
  local list = W('basketList')
  list:destroyChildren()
  for i, entry in ipairs(basket) do
    local row = g_ui.createWidget('MailBasketRow', list)
    if entry.poke then
      row:getChildById('item'):setVisible(false)
      row:getChildById('portrait'):setVisible(true)
      row:getChildById('portrait'):setImageSource(pokeIcon(entry.name))
      row:getChildById('name'):setText(entry.name .. '  Lv ' .. entry.level)
    else
      row:getChildById('item'):setItemId(entry.clientId)
      row:getChildById('name'):setText(fmt(entry.count) .. 'x ' .. entry.name)
    end
    row:setTooltip(entry.source)
    row:getChildById('removeButton').onClick = function()
      table.remove(basket, i)
      resetSend()
      renderBasket()
      -- os cards da lista mostram de novo o botao de adicionar
      if window then
        for _, card in ipairs(W('grid'):getChildren()) do
          if card.basketKey == entry.key and card.refreshState then card.refreshState() end
        end
      end
    end
  end
  W('basketTitle'):setText('ENCOMENDA (' .. #basket .. '/' .. maxEntries .. ')')
  local ready = #basket > 0 and recipient ~= nil
  W('sendButton'):setEnabled(ready)
  if fee > 0 then
    local enough = balance >= fee
    W('feeLabel'):setText('Envio: ' .. fmt(fee) .. ' gp  |  Banco: ' .. fmt(balance) .. ' gp')
    W('feeLabel'):setColor(enough and '#f2c400' or '#e04848')
    W('sendButton'):setEnabled(ready and enough)
    if not enough then W('sendButton'):setTooltip('Saldo insuficiente no banco para pagar o envio.') end
  else
    W('feeLabel'):setText(recipient and ('Para: ' .. recipient.name .. ' (ID ' .. recipient.id .. ')') or 'Escolha o destinatario pelo ID.')
  end
  for _, card in ipairs(W('grid'):getChildren()) do
    if card.refreshState then card.refreshState() end
  end
end

-- ============================================================
-- lista (cards)
-- ============================================================
local function showList(buffer)
  local grid = W('grid')
  grid:destroyChildren()
  local cats = W('catPanel')
  cats:destroyChildren()
  local shown = 0
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'LIST' then
      view.tab = f[2] or view.tab
      view.page = tonumber(f[3]) or 1
      view.pages = tonumber(f[4]) or 1
      view.category = tonumber(f[6]) or 0
    elseif f[1] == 'C' then
      local index, name, count = tonumber(f[2]) or 0, f[3] or '?', tonumber(f[4]) or 0
      local button = g_ui.createWidget('MailCat', cats)
      button:setText(SHORT[name] or name)
      button:setTooltip(name .. ': ' .. count)
      styleTab(button, index == view.category)
      if index ~= view.category and count == 0 then button:setColor('#4a5f7a') end
      button.onClick = function() requestList('PCI', 1, index) end
    elseif f[1] == 'P' or f[1] == 'I' then
      shown = shown + 1
      local poke = f[1] == 'P'
      local card = g_ui.createWidget('MailCard', grid)
      local qty, add = card:getChildById('qty'), card:getChildById('addButton')
      local entry
      if poke then
        local kind = view.tab == 'TEAM' and 'T' or 'P'
        local iv = tonumber(f[6]) or -1
        entry = { key = basketKey(kind, f[2]), kind = kind, ref = f[2], count = 1, max = 1, poke = true,
          name = f[4] or '?', level = f[5] or '1', clientId = tonumber(f[3]) or 0, source = f[7] or '' }
        card:getChildById('item'):setVisible(false)
        card:getChildById('portrait'):setVisible(true)
        card:getChildById('portrait'):setImageSource(pokeIcon(entry.name))
        card:getChildById('name'):setText(entry.name)
        card:getChildById('sub'):setText('Lv ' .. entry.level .. (iv >= 0 and ('  |  IV ' .. iv .. '%') or ''))
        qty:setVisible(false)
        add:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        add:setMarginLeft(6)
      else
        local kind = view.tab == 'PCI' and 'I' or 'B'
        local total = tonumber(f[5]) or 1
        entry = { key = basketKey(kind, f[2]), kind = kind, ref = f[2], count = 1, max = total, poke = false,
          name = f[4] or '?', clientId = tonumber(f[3]) or 0, source = view.tab == 'PCI' and 'Do PC' or 'Da mochila' }
        card:getChildById('item'):setItemId(entry.clientId)
        card:getChildById('name'):setText(entry.name)
        card:getChildById('sub'):setText('Tem: ' .. fmt(total))
        qty:setText(tostring(total))
      end
      card:setTooltip(entry.name)
      card.basketKey = entry.key
      card.refreshState = function()
        local _, inBasket = findBasket(entry.key)
        if poke then
          add:setEnabled(not inBasket)
          add:setText(inBasket and 'No pacote' or '+ Pacote')
        else
          local left = entry.max - (inBasket and inBasket.count or 0)
          add:setEnabled(left > 0)
          add:setText(left > 0 and '+ Pacote' or 'No pacote')
        end
        card:setBorderColor(inBasket and '#2e7d4a' or '#1d3557')
      end
      add.onClick = function()
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        if not poke then
          local _, inBasket = findBasket(entry.key)
          local left = entry.max - (inBasket and inBasket.count or 0)
          copy.count = math.max(1, math.min(left, tonumber((qty:getText() or ''):match('%d+')) or 1))
        end
        addToBasket(copy)
      end
      card.refreshState()
    end
  end
  for _, tab in ipairs(TABS) do
    styleTab(W('tab' .. tab), tab == view.tab)
  end
  W('catPanel'):setVisible(view.tab == 'PCI')
  W('listHint'):setText(shown > 0 and TAB_HINT[view.tab] or 'Nada encontrado aqui.')
  W('pageLabel'):setText('Pagina ' .. view.page .. ' de ' .. view.pages)
  W('prevPage'):setEnabled(view.page > 1)
  W('nextPage'):setEnabled(view.page < view.pages)
end

local function showRecipient(f)
  local id = tonumber(f[2]) or 0
  if id <= 0 then
    recipient = nil
    W('rcptAvatar'):setText('?')
    W('rcptAvatar'):setBackgroundColor('#24415f')
    W('rcptName'):setText(f[3] or 'Nao encontrado')
    W('rcptName'):setColor('#e04848')
    W('rcptInfo'):setText('Digite o ID do jogador.')
  else
    recipient = { id = id, name = f[3] or '?' }
    W('rcptAvatar'):setText((recipient.name:match('%a') or '?'):upper())
    W('rcptAvatar'):setBackgroundColor('#2e7d4a')
    W('rcptName'):setText(recipient.name)
    W('rcptName'):setColor('#ffffff')
    local online = f[5] == '1'
    W('rcptInfo'):setText('ID ' .. id .. '  |  Lv ' .. (f[4] or '?') .. '  |  ' .. (online and 'online' or 'offline'))
    W('rcptInfo'):setColor(online and '#5fd35f' or '#8fa7c4')
  end
  resetSend()
  renderBasket()
end

local function clearRecipientCard()
  recipient = nil
  W('rcptAvatar'):setText('?')
  W('rcptAvatar'):setBackgroundColor('#24415f')
  W('rcptName'):setText('Ninguem escolhido')
  W('rcptName'):setColor('#8fa7c4')
  W('rcptInfo'):setText('Digite o ID e clique em Buscar.')
  W('rcptInfo'):setColor('#6f86a8')
end

-- ============================================================
-- servidor
-- ============================================================
local function onMailOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  local head = buffer:match('^([^|\n]*)')
  if head == 'OPEN' then
    local f = splitFields(buffer)
    myId = tonumber(f[2]) or 0
    fee = tonumber(f[3]) or 0
    maxEntries = tonumber(f[4]) or 30
    balance = tonumber(f[5]) or 0
    W('myIdLabel'):setText('Seu ID: ' .. myId)
    if not window:isVisible() then
      basket = {}
      clearRecipientCard()
      W('rcptEdit'):setText('')
      W('noteEdit'):setText('')
      W('searchEdit'):setText('')
      view = { tab = 'TEAM', page = 1, pages = 1, search = '', category = 0 }
    end
    renderBasket()
    window:show()
    window:raise()
    window:focus()
  elseif head == 'LIST' then
    showList(buffer)
  elseif head == 'R' then
    showRecipient(splitFields(buffer))
  elseif head == 'DONE' then
    balance = tonumber(splitFields(buffer)[2]) or balance
    basket = {}
    W('noteEdit'):setText('')
    resetSend()
    renderBasket()
  elseif head == 'CLOSE' then
    hide(true)
  end
end

-- ============================================================
-- acoes
-- ============================================================
local function doSend()
  if not recipient or #basket == 0 then return end
  local button = W('sendButton')
  if not sendArmed then
    sendArmed = true
    button:setText(fee > 0 and ('Confirmar (' .. fmt(fee) .. ' gp)') or ('Confirmar envio para ' .. recipient.name))
    return
  end
  resetSend()
  local note = W('noteEdit'):getText():gsub('[|\n\r]', ' '):sub(1, 120)
  local search = W('searchEdit'):getText():gsub('[|\n\r]', ''):sub(1, 30)
  local lines = { table.concat({ 'SEND', recipient.id, view.tab, view.page, view.category, search, note }, '|') }
  for _, entry in ipairs(basket) do
    if entry.kind == 'T' or entry.kind == 'P' then
      lines[#lines + 1] = entry.kind .. '|' .. entry.ref
    else
      lines[#lines + 1] = entry.kind .. '|' .. entry.ref .. '|' .. entry.count
    end
  end
  send(table.concat(lines, '\n'))
end

local function findRecipient()
  local id = tonumber(W('rcptEdit'):getText():match('%d+'))
  if id then send('RCPT|' .. id) end
end

local function onEnter(id, fn)
  W(id).onKeyPress = function(widget, keyCode)
    if keyCode == KeyEnter or keyCode == KeyReturn then
      fn()
      return true
    end
    return false
  end
end

function hide(fromServer)
  if window and window:isVisible() then
    window:hide()
    if not fromServer then send('CLOSE') end
  end
end

local function onGameEnd()
  if window then window:hide() end
  basket = {}
end

function init()
  window = g_ui.displayUI('mail')
  window:hide()
  for _, tab in ipairs(TABS) do
    W('tab' .. tab).onClick = function()
      W('searchEdit'):setText('')
      requestList(tab, 1, 0)
    end
  end
  W('searchButton').onClick = function() requestList(view.tab, 1, view.category) end
  onEnter('searchEdit', function() requestList(view.tab, 1, view.category) end)
  W('prevPage').onClick = function() requestList(view.tab, view.page - 1, view.category) end
  W('nextPage').onClick = function() requestList(view.tab, view.page + 1, view.category) end
  W('rcptButton').onClick = findRecipient
  onEnter('rcptEdit', findRecipient)
  W('rcptEdit').onTextChange = function()
    if recipient then
      recipient = nil
      clearRecipientCard()
      renderBasket()
    end
  end
  W('clearButton').onClick = function()
    basket = {}
    resetSend()
    renderBasket()
  end
  W('sendButton').onClick = doSend
  clearRecipientCard()
  ProtocolGame.registerExtendedOpcode(OPCODE, onMailOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if window then
    window:destroy()
    window = nil
  end
end
