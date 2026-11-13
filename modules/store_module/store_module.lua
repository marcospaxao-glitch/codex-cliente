-- ============================================================
-- LOJA CODEX (cliente) - opcode 116
-- Catalogo, precos e saldo vem do servidor (data/lib/core/codexstore.lua).
-- Paga com Donate (PokeBank + diamond donate da mochila).
-- So envia opcodes a partir de cliques do jogador.
-- ============================================================

local OPCODE = 116

local window = nil
local shopButton = nil
local data = { balance = 0, bank = 0, pocket = 0, url = '', transfer = true, categories = {}, products = {} }
local currentCat = nil
local selected = nil
local waiting = false

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

local function unescape(text)
  return (tostring(text or ''):gsub('\\n', '\n'))
end

local function safe(text)
  return (tostring(text or ''):gsub('[|\n\r]', ' '))
end

-- trava contra clique duplo; libera sozinha se o servidor nao responder
local function setWaiting()
  waiting = true
  scheduleEvent(function() waiting = false end, 3000)
end

local function status(text, ok)
  local label = W('statusLabel')
  if not label then return end
  label:setText(text or '')
  if ok == nil then
    label:setColor('#8fa7c4')
  else
    label:setColor(ok and '#5fd35f' or '#e04848')
  end
end

local function updateBalance()
  local label = W('balanceLabel')
  if label then
    label:setText('Donate: ' .. data.balance)
    label:setTooltip('Banco (PokeBank): ' .. data.bank .. '\nNa mochila: ' .. data.pocket)
  end
  W('transferButton'):setVisible(data.transfer)
end

-- ------------------------------------------------------------
-- lista
-- ------------------------------------------------------------
local renderProducts

local function closePanels()
  W('confirmPanel'):hide()
  W('transferPanel'):hide()
  selected = nil
end

local function openConfirm(product)
  closePanels()
  selected = product
  local panel = W('confirmPanel')
  W('confirmTitle'):setText(product.name)
  W('confirmImage'):setImageSource(product.image)
  W('confirmText'):setText(product.tip ~= '' and product.tip or 'Deseja comprar este produto?')
  local after = data.balance - product.price
  if after >= 0 then
    W('confirmPrice'):setText(product.price .. ' Donate   (fica com ' .. after .. ')')
    W('confirmPrice'):setColor('#f2c400')
    W('confirmBuy'):setText('Comprar')
  else
    W('confirmPrice'):setText(product.price .. ' Donate   (faltam ' .. (-after) .. ')')
    W('confirmPrice'):setColor('#e04848')
    W('confirmBuy'):setText('Comprar Donate')
  end
  W('confirmBuy'):setEnabled(not product.owned)
  if product.owned then W('confirmPrice'):setText('Voce ja tem este produto.') end
  panel:show()
  panel:raise()
  panel:focus()
end

renderProducts = function()
  local list = W('productList')
  if not list then return end
  list:destroyChildren()
  local filter = (W('searchEdit'):getText() or ''):lower()
  local shown = 0
  for _, product in ipairs(data.products) do
    local inCat = filter ~= '' or product.cat == currentCat
    if inCat and (filter == '' or product.name:lower():find(filter, 1, true)) then
      shown = shown + 1
      local card = g_ui.createWidget('StoreCard', list)
      card:getChildById('name'):setText(product.name)
      card:getChildById('picture'):setImageSource(product.image)
      card:getChildById('price'):setText(product.price .. ' Donate')
      card:getChildById('price'):setColor(product.price <= data.balance and '#f2c400' or '#6f86a8')
      card:getChildById('owned'):setVisible(product.owned)
      if product.tip ~= '' then card:setTooltip(product.tip) end
      card.onClick = function() openConfirm(product) end
    end
  end
  W('countLabel'):setText(shown .. ' produto(s)')
end

local function selectCategory(id)
  currentCat = id
  W('searchEdit'):setText('')
  for _, child in ipairs(W('categoryList'):getChildren()) do
    child:setOn(child.catId == id)
  end
  for _, c in ipairs(data.categories) do
    if c.id == id then
      W('bannerImage'):setImageSource(c.image)
      W('bannerTitle'):setText(c.name)
      W('bannerText'):setText(c.desc)
    end
  end
  renderProducts()
  local scroll = W('productScroll')
  if scroll then scroll:setValue(0) end
end

local function renderCategories()
  local list = W('categoryList')
  list:destroyChildren()
  for _, c in ipairs(data.categories) do
    local button = g_ui.createWidget('StoreCategory', list)
    button:setText(c.name)
    button:setIcon(c.icon)
    button.catId = c.id
    button.onClick = function() closePanels() selectCategory(c.id) end
  end
end

-- ------------------------------------------------------------
-- servidor
-- ------------------------------------------------------------
local pendingParts = {}
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

local function onStoreOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  local head = buffer:match('^([^|\n]*)')

  if head == 'STORE' then
    local fresh = { categories = {}, products = {} }
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'STORE' then
        fresh.balance, fresh.bank, fresh.pocket = tonumber(f[2]) or 0, tonumber(f[3]) or 0, tonumber(f[4]) or 0
        fresh.url = f[5] or ''
        fresh.transfer = f[6] ~= '0'
      elseif f[1] == 'C' then
        fresh.categories[#fresh.categories + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', desc = unescape(f[4]),
          image = f[5] or '', icon = f[6] or '' }
      elseif f[1] == 'P' then
        fresh.products[#fresh.products + 1] = { id = tonumber(f[2]) or 0, cat = tonumber(f[3]) or 0, name = f[4] or '?',
          price = tonumber(f[5]) or 0, image = f[6] or '', tip = unescape(f[7]), owned = f[8] == '1' }
      end
    end
    data = fresh
    waiting = false
    updateBalance()
    renderCategories()
    local keep = currentCat
    local exists = false
    for _, c in ipairs(data.categories) do if c.id == keep then exists = true end end
    selectCategory(exists and keep or (data.categories[1] and data.categories[1].id or 0))
    status('Escolha um produto. Os precos estao em Donate.', nil)
    window:show()
    window:raise()
    window:focus()
    if shopButton then shopButton:setOn(true) end
  elseif head == 'BAL' then
    local f = splitFields(buffer)
    data.balance, data.bank, data.pocket = tonumber(f[2]) or 0, tonumber(f[3]) or 0, tonumber(f[4]) or 0
    updateBalance()
    renderProducts()
  elseif head == 'OWNED' then
    local id = tonumber(buffer:match('^OWNED|(%d+)'))
    for _, product in ipairs(data.products) do
      if product.id == id then product.owned = true end
    end
    renderProducts()
  elseif head == 'OK' then
    waiting = false
    status(buffer:sub(4), true)
  elseif head == 'ERR' then
    waiting = false
    status(buffer:sub(5), false)
  end
end

-- ------------------------------------------------------------
-- abrir / fechar
-- ------------------------------------------------------------
local function openSite()
  if data.url ~= '' then
    g_platform.openUrl(data.url)
    status('Abrindo o site para comprar Donate...', nil)
  end
end

function show()
  if g_game.isOnline() then
    send('OPEN') -- o servidor responde com o catalogo e abre a janela
  end
end

function hide()
  if window then
    closePanels()
    window:hide()
  end
  if shopButton then shopButton:setOn(false) end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

local function onGameEnd()
  hide()
end

function init()
  window = g_ui.displayUI('store_module')
  window:hide()

  shopButton = modules.client_topmenu.addRightGameToggleButton('shopButton', tr('Loja'), '/images/topbuttons/emerald_shop', toggle, true)
  shopButton:setOn(false)

  W('getButton').onClick = openSite
  W('searchEdit').onTextChange = function() renderProducts() end
  W('confirmCancel').onClick = closePanels
  W('confirmBuy').onClick = function()
    if not selected then return end
    if data.balance < selected.price then
      openSite()
      closePanels()
      return
    end
    if waiting then return end
    setWaiting()
    status('Comprando ' .. selected.name .. '...', nil)
    send('BUY|' .. selected.id .. '|' .. safe(selected.name))
    closePanels()
  end
  W('transferButton').onClick = function()
    closePanels()
    W('transferName'):setText('')
    W('transferAmount'):setText('')
    W('transferPanel'):show()
    W('transferPanel'):raise()
    W('transferName'):focus()
  end
  W('transferCancel').onClick = closePanels
  W('transferSend').onClick = function()
    local name = safe(W('transferName'):getText()):gsub('^%s+', ''):gsub('%s+$', '')
    local amount = tonumber((W('transferAmount'):getText() or ''):match('%d+')) or 0
    if name == '' then return status('Digite o nome de quem vai receber.', false) end
    if amount < 1 then return status('Digite a quantidade.', false) end
    if amount > data.balance then return status('Voce nao tem Donate suficiente.', false) end
    if waiting then return end
    setWaiting()
    status('Enviando...', nil)
    send('TRANSFER|' .. name .. '|' .. amount)
    closePanels()
  end

  ProtocolGame.registerExtendedOpcode(OPCODE, onStoreOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if shopButton then
    shopButton:destroy()
    shopButton = nil
  end
  if window then
    window:destroy()
    window = nil
  end
end
