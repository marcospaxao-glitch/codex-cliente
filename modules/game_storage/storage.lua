-- ============================================================
-- PC STORAGE (cliente) - opcode 94
-- Abre quando o jogador usa o PC no mapa (o servidor manda os dados).
-- Todo envio ao servidor sai de clique/tecla/arraste do jogador.
-- ============================================================

local OPCODE = 94
local ICON_PATH = '/modules/game_pokemonbar/bar_icon/'

local CURRENCIES = { 'GOLD', 'POKECOINS', 'TOKENS', 'DONATE' }
local CURRENCY_LABEL = { GOLD = 'gp', POKECOINS = 'PokeCoins', TOKENS = 'Tokens', DONATE = 'Donate' }
local CART_MAX = 10
-- icones proprios das abas (modules/game_storage/icons). Sem o arquivo, usa o item.
local ICON_DIR = '/modules/game_storage/icons/'
local TAB_ICONS = {
  ['pokemons'] = ICON_DIR .. 'pokemons.png',
  ['pokebolas'] = ICON_DIR .. 'pokebolas.png',
  ['ovos'] = ICON_DIR .. 'ovos.png',
  ['stones'] = ICON_DIR .. 'stones.png',
  ['mega stones'] = ICON_DIR .. 'mega_stones.png',
  ['pocoes'] = ICON_DIR .. 'pocoes.png',
  ['held items'] = ICON_DIR .. 'held_items.png',
  ['vitaminas'] = ICON_DIR .. 'vitaminas.png',
  ['pesca'] = ICON_DIR .. 'pesca.png',
  ['moedas'] = ICON_DIR .. 'moedas.png',
  ['outros'] = ICON_DIR .. 'outros.png',
  ['market'] = ICON_DIR .. 'market.png',
  ['meus anuncios'] = ICON_DIR .. 'meus_anuncios.png',
  ['forja'] = ICON_DIR .. 'forja.png',
}

local window = nil
local tabsPanel, pokeGrid, itemGrid, marketPanel = nil, nil, nil, nil
local cart = {}           -- { kind = 'I'|'P', id, box, slot, name, max, count, price, currency }
local balances = {}
local armedOffer, armedAt = nil, 0  -- compra aguardando o 2o clique
local buyQty = {}  -- quantidade escolhida por anuncio (anuncio por unidade)
local releaseArmed, releaseAt = nil, 0  -- liberar pokemon aguardando confirmacao
local state = { tab = 0, page = 1, pages = 1, box = 1, boxes = 30, slots = 20 }
local pkSearch, pkHint = '', nil   -- codex: busca de pokemon no PC
local gSearch, gRes = '', nil      -- codex: busca geral (pokemons + itens de todo o PC)
local selected = nil      -- { kind = 'item'|'poke', id/slot, name, count }
local searchSent = ''

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

local function fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', ''))
end

-- numero curto para caber nos botoes de custo (7.030.000 -> 7,03M)
local function curto(n)
  n = math.floor(tonumber(n) or 0)
  if n >= 1000000000 then return (string.format('%.2f', n / 1000000000):gsub('%.?0+$', ''):gsub('%.', ',')) .. 'B' end
  if n >= 1000000 then return (string.format('%.2f', n / 1000000):gsub('%.?0+$', ''):gsub('%.', ',')) .. 'M' end
  if n >= 100000 then return (string.format('%.1f', n / 1000):gsub('%.?0+$', ''):gsub('%.', ',')) .. 'k' end
  return fmt(n)
end

local function iconFor(name)
  local lower = tostring(name or ''):lower()
  local path = ICON_PATH .. lower .. '.png'
  if lower:sub(1, 5) == 'mega ' and not g_resources.fileExists(path) then
    path = ICON_PATH .. lower:sub(6):gsub(' [xy]$', '') .. '.png'
  end
  return path
end

local function hpColor(percent)
  if percent > 50 then return '#5fd35f' end
  if percent > 20 then return '#f2c400' end
  return '#e04848'
end

-- ============================================================
-- selecao / rodape
-- ============================================================
local function money(currency, value)
  return fmt(value) .. ' ' .. (CURRENCY_LABEL[currency] or currency)
end

local function updateCart()
  if not window then return end
  local names = {}
  for _, entry in ipairs(cart) do
    names[#names + 1] = (entry.kind == 'I' and entry.count > 1) and (entry.count .. 'x ' .. entry.name) or entry.name
  end
  W('cartLabel'):setText('Carrinho (' .. #cart .. ')')
  W('cartSummary'):setText(#cart > 0 and table.concat(names, ', ') or 'Vazio - selecione algo e clique em + Carrinho')
  W('sellButton'):setEnabled(#cart > 0)
end

local function updateFooter()
  if not window then return end
  local isPoke = state.tab == 0
  local isMarket = state.tab < 0
  local label = W('selectedLabel')
  local amount = W('amountEdit')
  local withdraw = W('withdrawButton')
  local withdrawAll = W('withdrawAllButton')
  local depositTab = W('depositTabButton')
  local cartAdd = W('cartAddButton')

  amount:setVisible(not isPoke and not isMarket)
  withdraw:setVisible(not isMarket)
  withdrawAll:setVisible(not isPoke and not isMarket)
  depositTab:setVisible(not isPoke and not isMarket and state.tabIsOthers ~= true)
  cartAdd:setVisible(not isMarket)
  withdraw:setText(isPoke and 'Retirar' or 'Sacar')
  if isPoke then
    cartAdd:breakAnchors()
    cartAdd:addAnchor(AnchorVerticalCenter, 'withdrawButton', AnchorVerticalCenter)
    cartAdd:addAnchor(AnchorLeft, 'withdrawButton', AnchorRight)
  else
    cartAdd:breakAnchors()
    cartAdd:addAnchor(AnchorVerticalCenter, 'amountEdit', AnchorVerticalCenter)
    cartAdd:addAnchor(AnchorLeft, 'withdrawAllButton', AnchorRight)
  end

  if isMarket then
    label:setText('Saldo no PokeBank:  ' .. money('GOLD', balances.GOLD or 0) .. '   |   ' .. money('POKECOINS', balances.POKECOINS or 0) ..
      '   |   ' .. money('TOKENS', balances.TOKENS or 0) .. '   |   ' .. money('DONATE', balances.DONATE or 0))
    label:setColor('#8fa7c4')
  elseif selected then
    if selected.kind == 'poke' then
      label:setText(selected.name .. '  -  Nv ' .. selected.level)
    else
      label:setText(selected.name .. '  -  ' .. fmt(selected.count) .. ' no PC')
    end
    label:setColor('#ffffff')
  else
    label:setText(isPoke and 'Selecione um pokemon' or 'Selecione um item')
    label:setColor('#6f86a8')
  end
  withdraw:setEnabled(selected ~= nil)
  withdrawAll:setEnabled(selected ~= nil)
  cartAdd:setEnabled(selected ~= nil and #cart < CART_MAX)
  local summary = W('summaryButton')
  summary:setVisible(isPoke)
  summary:setEnabled(selected ~= nil and selected.kind == 'poke')
  local release = W('releaseButton')
  release:setVisible(isPoke)
  release:setEnabled(selected ~= nil and selected.kind == 'poke' and not selected.locked)
  local lockBtn = W('lockButton')
  if lockBtn then
    lockBtn:setVisible(isPoke)
    lockBtn:setEnabled(selected ~= nil and selected.kind == 'poke')
    lockBtn:setText((selected and selected.locked) and 'Destrancar' or 'Cadeado')
    lockBtn:setTooltip('Pokemon com cadeado nao aparece no Pokemon Collector, nao pode ser liberado e nao entra na Forja.')
  end
  if not releaseArmed or not selected or releaseArmed ~= selected.slot then
    releaseArmed = nil
    release:setText('Liberar')
  end

  if isMarket then
    local hint = 'Comprar: clique 2x no botao para confirmar  |  O que voce compra vai para o seu PC'
    if state.tab == -2 then
      hint = 'Anuncios expiram em 7 dias  |  Cancelado ou expirado volta para o seu PC'
    elseif state.tab == -7 then
      hint = 'Itens do evento vendidos pela staff  |  Clique 2x em Comprar  |  Vai para o seu PC'
    end
    W('hintLabel'):setText(hint)
  elseif isPoke then
    W('hintLabel'):setText(pkHint or 'Arraste para fora para retirar  |  Entre slots para trocar  |  Nas setas muda de caixa  |  Busque pelo nome no campo de busca')
  else
    W('hintLabel'):setText('Arraste para a mochila para retirar (usa a quantidade se estiver selecionado)  |  Da mochila para ca guarda')
  end
  updateCart()
end

local function selectEntry(entry, widget)
  selected = entry
  for _, grid in ipairs({ pokeGrid, itemGrid }) do
    for _, child in ipairs(grid:getChildren()) do
      child:setBorderColor(child == widget and '#f2c400' or (child.hasContent and '#2b4a75' or '#16294a'))
    end
  end
  updateFooter()
end

-- ============================================================
-- arrastar
-- ============================================================
local function positionOf(draggedWidget)
  if not draggedWidget or draggedWidget:getClassName() ~= 'UIItem' then
    return nil
  end
  local item = draggedWidget:getItem()
  local pos = item and item:getPosition()
  if not pos or pos.x ~= 65535 then
    modules.game_textmessage.displayFailureMessage('Arraste da mochila ou da equipe.')
    return nil
  end
  return pos
end

-- arrastar PARA FORA da janela (retirar)
local function isInsideWindow(widget)
  while widget do
    if widget == window then return true end
    widget = widget:getParent()
  end
  return false
end

-- devolve true se soltou fora do PC, e a posicao do slot/container de destino
local function dropTarget(droppedWidget, mousePos)
  if droppedWidget and isInsideWindow(droppedWidget) then
    return false
  end
  local hit = g_ui.getRootWidget():recursiveGetChildByPos(mousePos, false)
  if hit and isInsideWindow(hit) then
    return false
  end
  local widget = droppedWidget or hit
  while widget do
    if type(widget.position) == 'table' and widget.position.x == 65535 then
      return true, widget.position
    end
    widget = widget:getParent()
  end
  return true, nil
end

local function startDrag(widget)
  widget:setBorderColor('#f2c400')
  pcall(function() g_mouse.pushCursor('target') end)
  return true
end

local function endDrag(widget)
  widget:setBorderColor(widget.hasContent and '#2b4a75' or '#16294a')
  pcall(function() g_mouse.popCursor('target') end)
end

-- item vindo do inventario (qualquer lugar da janela)
local function onExternalDrop(self, draggedWidget, mousePos)
  local pos = positionOf(draggedWidget)
  if not pos then return false end
  send('DEP|' .. pos.x .. '|' .. pos.y .. '|' .. pos.z .. '|0')
  return true
end

local function onPokeSlotDrop(self, draggedWidget, mousePos)
  if draggedWidget and draggedWidget.pcSlot then
    if draggedWidget.pcSlot ~= self.pcSlot then
      send('PKMV|' .. draggedWidget.pcSlot .. '|' .. state.box .. '|' .. self.pcSlot)
    end
    return true
  end
  local pos = positionOf(draggedWidget)
  if not pos then return false end
  send('DEP|' .. pos.x .. '|' .. pos.y .. '|' .. pos.z .. '|' .. self.pcSlot)
  return true
end

local function boxArrowDrop(delta)
  return function(self, draggedWidget, mousePos)
    if draggedWidget and draggedWidget.pcSlot and state.tab == 0 then
      local box = state.box + delta
      if box < 1 then box = state.boxes end
      if box > state.boxes then box = 1 end
      send('PKMV|' .. draggedWidget.pcSlot .. '|' .. box .. '|0')
      return true
    end
    return onExternalDrop(self, draggedWidget, mousePos)
  end
end

-- ============================================================
-- desenho
-- ============================================================
local function buildPokeGrid(pokes)
  pokeGrid:destroyChildren()
  for slot = 1, state.slots do
    local cell = g_ui.createWidget('PCPokeSlot', pokeGrid)
    cell.pcSlot = slot
    cell:getChildById('slotLabel'):setText(tostring(slot))
    local poke = pokes[slot]
    if poke then
      cell.hasContent = true
      cell:setBorderColor('#2b4a75')
      cell:getChildById('portrait'):setImageSource(iconFor(poke.name))
      cell:getChildById('ball'):setItemId(poke.ball)
      cell:getChildById('nameLabel'):setText(poke.name)
      cell:getChildById('levelLabel'):setText('Nv ' .. poke.level .. (poke.iv >= 0 and ('   IV ' .. poke.iv .. '%') or ''))
      if poke.iv >= 80 then cell:getChildById('levelLabel'):setColor('#5fd35f') end
      local percent = 100
      if poke.maxHealth > 0 then
        percent = math.max(0, math.min(100, math.floor(poke.health * 100 / poke.maxHealth)))
      end
      local fill = cell:getChildById('hpFill')
      fill:setWidth(math.floor(116 * percent / 100))
      fill:setBackgroundColor(hpColor(percent))
      fill:setVisible(percent > 0)
      cell:setTooltip(poke.name .. '\nNivel ' .. poke.level .. '\nHP ' .. fmt(poke.health) .. ' / ' .. fmt(poke.maxHealth) ..
        (poke.iv >= 0 and ('\nIV ' .. poke.iv .. '% (' .. poke.stars .. ' estrelas)') or '') ..
        (poke.boost > 0 and ('\nBoost +' .. poke.boost) or '') .. (poke.tags ~= '' and ('\n' .. poke.tags:gsub(',', ' / ')) or '') ..
        (poke.locked and '\n[Cadeado] nao vende, nao libera, nao forja' or ''))
      -- Genes: sexo e estrelas na lateral; Tera / boost embaixo da ball
      local genesImg = '/modules/game_pokeinfo/images/'
      local genderName = ({ M = 'male', F = 'female', N = 'none' })[poke.gender or '']
      cell:getChildById('genderIcon'):setVisible(genderName ~= nil)
      if genderName then cell:getChildById('genderIcon'):setImageSource(genesImg .. genderName) end
      local col = cell:getChildById('starsCol')
      col:destroyChildren()
      if poke.iv >= 0 and poke.gender then
        for i = 1, 5 do
          local star = g_ui.createWidget('UIWidget', col)
          star:setSize({ width = 8, height = 8 })
          star:setPhantom(true)
          star:setImageSource(genesImg .. (i <= (6 - poke.stars) and 'star_s_off' or (poke.iv >= 100 and 'star_s_perfect' or 'star_s')))
        end
      end
      local tag = (poke.tags or ''):find('Tera') and 'Tera' or ''
      if poke.boost > 0 then tag = (tag ~= '' and (tag .. ' ') or '') .. '+' .. poke.boost end
      cell:getChildById('lockIcon'):setVisible(poke.locked) -- codex: cadeado
      if pkSearch ~= '' then -- codex: busca destaca quem bate e apaga o resto
        local hit = poke.name:lower():find(pkSearch, 1, true) ~= nil
        cell:setOpacity(hit and 1 or 0.3)
        if hit then cell:setBorderColor('#5fd3ff') end
      end
      if selected and selected.kind == 'poke' and selected.slot == slot then selected.locked = poke.locked end
      if poke.locked then cell:setBorderColor('#8a6d00') end
      cell:getChildById('tagLabel'):setText(tag)
      cell:getChildById('tagLabel'):setColor(tag:find('Tera') and '#5fe0ff' or '#f2c400')
      cell.onClick = function(widget)
        selectEntry({ kind = 'poke', slot = slot, name = poke.name, level = poke.level, locked = poke.locked }, widget)
      end
      cell.onDoubleClick = function()
        send('PKWD|' .. slot)
        return true
      end
      cell.onDragEnter = function(widget, mousePos)
        return startDrag(widget)
      end
      cell.onDragLeave = function(widget, droppedWidget, mousePos)
        endDrag(widget)
        local outside, pos = dropTarget(droppedWidget, mousePos)
        if outside then
          -- solto num container (ex.: parcel do correio): o servidor decide
          -- se vai para dentro dele; senao vai para a equipe
          local where = (pos and pos.y >= 64) and ('|' .. pos.y .. '|' .. pos.z) or ''
          send('PKWD|' .. slot .. where)
        end
        return true
      end
    else
      cell:setDraggable(false)
      cell:getChildById('hpBg'):setVisible(false)
      cell:getChildById('hpFill'):setVisible(false)
    end
    cell.onDrop = onPokeSlotDrop
  end
end

local function buildItemGrid(items)
  itemGrid:destroyChildren()
  for index = 1, 60 do
    local cell = g_ui.createWidget('PCItemSlot', itemGrid)
    local entry = items[index]
    if entry then
      cell.hasContent = true
      cell:setBorderColor('#2b4a75')
      cell:getChildById('item'):setItemId(entry.clientId)
      cell:getChildById('countLabel'):setText(entry.count > 1 and fmt(entry.count) or '')
      cell:setTooltip(entry.name .. '\nQuantidade: ' .. fmt(entry.count))
      cell.onClick = function(widget)
        selectEntry({ kind = 'item', id = entry.id, name = entry.name, count = entry.count }, widget)
      end
      cell.onDoubleClick = function()
        send('WD|' .. entry.id .. '|1')
        return true
      end
      cell.onDragEnter = function(widget, mousePos)
        return startDrag(widget)
      end
      cell.onDragLeave = function(widget, droppedWidget, mousePos)
        endDrag(widget)
        local outside, pos = dropTarget(droppedWidget, mousePos)
        if outside then
          -- item selecionado: usa a quantidade digitada; senao uma pilha
          local amount = -1
          if selected and selected.kind == 'item' and selected.id == entry.id then
            amount = math.max(1, math.floor(tonumber(W('amountEdit'):getText()) or 1))
          end
          local where = pos and ('|' .. pos.y .. '|' .. pos.z) or ''
          send('WD|' .. entry.id .. '|' .. amount .. where)
        end
        return true
      end
    else
      cell:setDraggable(false)
    end
    cell.onDrop = onExternalDrop
  end
end

local function buildMarket(rows, mine)
  marketPanel:destroyChildren()
  for _, row in ipairs(rows) do
    local widget = g_ui.createWidget('PCMarketRow', marketPanel)
    local isPoke = row.kind == 'P'
    widget:getChildById('icon'):setVisible(not isPoke)
    widget:getChildById('portrait'):setVisible(isPoke)
    if isPoke then
      widget:getChildById('portrait'):setImageSource(iconFor(row.name))
    else
      widget:getChildById('icon'):setItemId(row.clientId)
    end
    local title = isPoke and (row.name .. '  Nv ' .. row.level) or ((row.count > 1 and (fmt(row.count) .. 'x ') or '') .. row.name)
    if row.unit and not isPoke then title = row.name .. '  (' .. fmt(row.count) .. ' disponiveis)' end
    local qtyEdit = widget:getChildById('qtyEdit')
    local showQty = row.unit and not mine and not row.mine
    qtyEdit:setVisible(showQty)
    if not showQty then
      qtyEdit:setWidth(0)
      qtyEdit:setMarginRight(0)
    end
    if isPoke then
      widget.onClick = function() send('MINFO|' .. row.id) end
    end
    widget:getChildById('nameLabel'):setText(title)
    widget:getChildById('priceLabel'):setText(money(row.currency, row.price) .. (row.unit and ' /un' or ''))
    local button = widget:getChildById('actionButton')
    if mine then
      local info = row.status
      if row.status == 'ATIVO' then
        info = 'Ativo - expira em ' .. math.max(0, math.ceil((row.when - os.time()) / 86400)) .. ' dia(s)'
      elseif row.status == 'VENDIDO' then
        info = 'Vendido para ' .. row.buyer
      elseif row.status == 'EXPIRADO' or row.status == 'CANCELADO' then
        info = (row.status == 'EXPIRADO' and 'Expirou' or 'Cancelado') .. ' - voltou para o PC'
      end
      if row.status == 'ESGOTADO' then info = 'Esgotado - tudo vendido' end
      if row.unit and row.status == 'ATIVO' then info = info .. '  -  restam ' .. fmt(row.count) .. ' (preco por unidade)' end
      widget:getChildById('infoLabel'):setText(info)
      widget:getChildById('infoLabel'):setColor((row.status == 'VENDIDO' or row.status == 'ESGOTADO') and '#5fd35f' or (row.status == 'ATIVO' and '#8fa7c4' or '#6f86a8'))
      button:setText('Cancelar')
      button:setVisible(row.status == 'ATIVO')
      button.onClick = function() send('CANCEL|' .. row.id) end
    else
      local info = 'Vendedor: ' .. row.seller
      if row.info ~= '' then info = info .. '  -  ' .. row.info end
      if isPoke then info = info .. '  -  clique para ver o resumo' end
      local infoLabel = widget:getChildById('infoLabel')
      infoLabel:setText(info)
      widget:setTooltip(title .. '\n' .. info .. '\nPreco: ' .. money(row.currency, row.price) .. (row.unit and ' por unidade' or ''))
      local priceLabel = widget:getChildById('priceLabel')
      -- saldo: avisa na propria linha (sem saldo = botao desligado)
      local function checaSaldo(total)
        if row.mine then return end
        local tem = balances[row.currency] or 0
        local falta = total > tem
        button:setEnabled(not falta)
        if falta then
          button:setText('Sem saldo')
          button:setTooltip('Saldo no PokeBank: ' .. money(row.currency, tem) .. '\nPrecisa de: ' .. money(row.currency, total))
        else
          button:setTooltip('')
        end
        return falta
      end
      local refresh = function() checaSaldo(row.price) end
      if showQty then
        local qty = math.max(1, math.min(row.count, buyQty[row.id] or 1))
        buyQty[row.id] = qty
        priceLabel:setTextAlign(AlignCenter)
        priceLabel:setBackgroundColor('#2a2206')
        priceLabel:setBorderWidth(1)
        priceLabel:setBorderColor('#f2c400')
        local function showTotal()
          local n = buyQty[row.id] or 1
          local total = row.price * n
          infoLabel:setText('Vendedor: ' .. row.seller .. '  -  ' .. money(row.currency, row.price) .. ' por unidade')
          priceLabel:setText('TOTAL  ' .. money(row.currency, total))
          local falta = checaSaldo(total)
          priceLabel:setColor(falta and '#ff6b6b' or '#ffd84a')
          priceLabel:setBorderColor(falta and '#e04848' or '#f2c400')
          if not falta then
            local waiting = armedOffer == row.id and os.time() - armedAt <= 4
            button:setText(waiting and 'Confirmar?' or 'Comprar')
          end
        end
        qtyEdit:setText(tostring(qty))
        qtyEdit:setTooltip('Quantidade (1 a ' .. fmt(row.count) .. ')')
        refresh = showTotal
        qtyEdit.onTextChange = function(self, text)
          local digits = tostring(text or ''):gsub('%D', '')
          if digits ~= text then self:setText(digits) return end
          local n = tonumber(digits)
          if n and n > row.count then self:setText(tostring(row.count)) return end
          buyQty[row.id] = math.max(1, n or 1)
          if armedOffer == row.id then armedOffer = nil end
          showTotal()
        end
      end
      if row.mine then
        button:setText('Seu')
        button:setEnabled(false)
      else
        local waiting = armedOffer == row.id and os.time() - armedAt <= 4
        button:setText(waiting and 'Confirmar?' or 'Comprar')
        refresh()
        button.onClick = function(self)
          if armedOffer == row.id and os.time() - armedAt <= 4 then
            armedOffer = nil
          else
            armedOffer, armedAt = row.id, os.time()
          end
          send('BUY|' .. row.id .. (showQty and ('|' .. (buyQty[row.id] or 1)) or ''))
        end
      end
    end
  end
  if #rows == 0 then
    local empty = g_ui.createWidget('Label', marketPanel)
    empty:setText(mine and 'Voce nao tem anuncios. Use o carrinho para anunciar.' or 'Nenhum anuncio encontrado.')
    empty:setColor('#6f86a8')
    empty:setTextAlign(AlignCenter)
    empty:setHeight(30)
  end
end

-- ============================================================
-- carrinho / anunciar
-- ============================================================
local function addToCart()
  if not selected or #cart >= CART_MAX then return end
  local entry
  if selected.kind == 'poke' then
    for _, other in ipairs(cart) do
      if other.kind == 'P' and other.box == state.box and other.slot == selected.slot then return end
    end
    entry = { kind = 'P', box = state.box, slot = selected.slot, name = selected.name, max = 1, count = 1 }
  else
    for _, other in ipairs(cart) do
      if other.kind == 'I' and other.id == selected.id then return end
    end
    local amount = math.max(1, math.min(selected.count, math.floor(tonumber(W('amountEdit'):getText()) or 1)))
    entry = { kind = 'I', id = selected.id, name = selected.name, max = selected.count, count = amount }
  end
  entry.price = ''
  entry.currency = 'GOLD'
  cart[#cart + 1] = entry
  updateFooter()
end

local function buildSellList()
  local list = W('sellList')
  list:destroyChildren()
  for index, entry in ipairs(cart) do
    local row = g_ui.createWidget('PCSellRow', list)
    row:getChildById('nameLabel'):setText(entry.kind == 'P' and (entry.name .. ' (caixa ' .. entry.box .. ')') or entry.name)
    local nameLabel = row:getChildById('nameLabel')
    local baseName = entry.kind == 'P' and (entry.name .. ' (caixa ' .. entry.box .. ')') or entry.name
    local function showUnit()
      local price = tonumber(entry.price) or 0
      if entry.kind == 'I' and entry.count > 1 then
        local conta = fmt(entry.count) .. ' x ' .. fmt(price) .. ' = ' .. money(entry.currency, entry.count * price)
        nameLabel:setText(baseName .. '  -  ' .. conta)
        nameLabel:setColor('#ffe27a')
        row:setTooltip(baseName .. '\nPreco por unidade: ' .. money(entry.currency, price) .. '\nLote inteiro: ' .. conta .. '\nO comprador escolhe a quantidade.')
      else
        nameLabel:setText(baseName)
        nameLabel:setColor('#ffffff')
      end
    end
    local countEdit = row:getChildById('countEdit')
    countEdit:setText(tostring(entry.count))
    countEdit:setVisible(entry.kind == 'I')
    countEdit.onTextChange = function(self, text)
      local digits = tostring(text or ''):gsub('%D', '')
      if digits ~= text then self:setText(digits) return end
      entry.count = math.max(1, math.min(entry.max, tonumber(digits) or 1))
      showUnit()
    end
    local priceEdit = row:getChildById('priceEdit')
    priceEdit:setText(entry.price)
    priceEdit.onTextChange = function(self, text)
      local digits = tostring(text or ''):gsub('%D', '')
      if digits ~= text then self:setText(digits) return end
      entry.price = digits
      showUnit()
    end
    priceEdit:setTooltip(entry.kind == 'I' and 'Preco de UMA unidade (com quantidade maior que 1)' or 'Preco total')
    local currencyButton = row:getChildById('currencyButton')
    currencyButton:setText(CURRENCY_LABEL[entry.currency])
    currencyButton.onClick = function(self)
      local nextIndex = 1
      for i, code in ipairs(CURRENCIES) do
        if code == entry.currency then nextIndex = i % #CURRENCIES + 1 end
      end
      entry.currency = CURRENCIES[nextIndex]
      self:setText(CURRENCY_LABEL[entry.currency])
      showUnit()
    end
    showUnit()
    row:getChildById('removeButton').onClick = function()
      table.remove(cart, index)
      updateFooter()
      if #cart == 0 then
        W('sellPanel'):hide()
      else
        buildSellList()
      end
    end
  end
  local note = W('sellNote')
  note:setText('Com quantidade: preco POR UNIDADE. Volta pro PC em 7 dias.')
  note:setColor('#6f86a8')
end

local function openSellPanel()
  if #cart == 0 then return end
  buildSellList()
  local panel = W('sellPanel')
  panel:show()
  panel:raise()
end

local function confirmSell()
  for _, entry in ipairs(cart) do
    if (tonumber(entry.price) or 0) < 1 then
      local note = W('sellNote')
      note:setText('Defina o preco de ' .. entry.name .. '.')
      note:setColor('#e04848')
      return
    end
  end
  for _, entry in ipairs(cart) do
    if entry.kind == 'P' then
      send('SELL|P|' .. entry.box .. '|' .. entry.slot .. '|' .. entry.price .. '|' .. entry.currency)
    else
      send('SELL|I|' .. entry.id .. '|' .. entry.count .. '|' .. entry.price .. '|' .. entry.currency .. (entry.count > 1 and '|U' or ''))
    end
  end
  cart = {}
  W('sellPanel'):hide()
  send('TAB|-2')
end

local function buildFilters(filters)
  local panel = W('marketFilters')
  panel:destroyChildren()
  for _, filter in ipairs(filters) do
    local button = g_ui.createWidget('PCFilter', panel)
    button:setText(filter.name:upper())
    button:setTooltip(filter.count .. ' anuncio(s)')
    local qtd = button:getChildById('countLabel')
    qtd:setText(filter.count > 999 and '999+' or fmt(filter.count))
    qtd:setColor(filter.count > 0 and '#dce8f5' or '#5a6b84')
    button:setOn(filter.index == state.tab)
    button.onClick = function()
      if state.tab ~= filter.index then
        searchSent = ''
        W('searchEdit'):setText('')
        send('TAB|' .. filter.index)
      end
    end
  end
end

-- ============================================================
-- forja
-- ============================================================
local forgeCurrency = nil
local forgeArmedAt = 0

local function fillAttrs(data, show)
  local panel = W('forgeTable')
  panel:destroyChildren()
  for _, attribute in ipairs(data.attrs) do
    local row = g_ui.createWidget('PCForgeAttr', panel)
    row:getChildById('name'):setText(attribute.name)
    row:getChildById('best'):setText(show and tostring(attribute.best) or '-')
    row:getChildById('common'):setText(show and (attribute.common .. ' / ' .. attribute.max) or '-')
    local perfect = row:getChildById('perfect')
    perfect:setText(show and (attribute.perfect .. ' / ' .. attribute.max) or '-')
    if show and attribute.perfect >= attribute.max then perfect:setColor('#8ef08e') end
  end
end

-- ============================================================
-- forja 2: 1 slot de ORIGEM + slots de MATERIAL
-- ============================================================
local IV_NOMES = { 'HP', 'Ataque', 'Defesa', 'Atq. Esp.', 'Def. Esp.', 'Velocidade' }
local NAT_STAT = { Lonely = 2, Adamant = 2, Naughty = 2, Brave = 2, Bold = 3, Impish = 3, Lax = 3, Relaxed = 3,
  Modest = 4, Mild = 4, Rash = 4, Quiet = 4, Calm = 5, Gentle = 5, Careful = 5, Sassy = 5,
  Timid = 1, Hasty = 1, Jolly = 1, Naive = 1 }

local function setForgeV2(on)
  for _, id in ipairs({ 'forgeTitle', 'forgeAuto', 'forgePokeList', 'forgePokeScroll', 'forgePreview' }) do
    W(id):setVisible(not on)
  end
  W('forge2'):setVisible(on)
end

local function buildForge2(data)
  local current = data.current or ''
  local origem, mats, cands = data.origem, {}, {}
  for _, poke in ipairs(data.pokes) do
    if poke.selected then mats[#mats + 1] = poke end
    cands[#cands + 1] = poke
  end
  local maxMats = data.required or 3
  if current == '' then
    W('f2Title'):setText('Escolha um pokemon na lista ao lado')
  else
    W('f2Title'):setText(current:upper() .. '   -   1 origem + ate ' .. maxMats .. ' materiais')
  end
  W('f2Auto'):setEnabled(current ~= '')
  W('f2Clear'):setEnabled(current ~= '')

  -- slot de ORIGEM
  local box = W('f2Origem')
  local temOrigem = origem ~= nil
  for _, id in ipairs({ 'portrait', 'nameLabel', 'infoLabel', 'natLabel' }) do box:getChildById(id):setVisible(temOrigem) end
  box:getChildById('emptyLabel'):setVisible(not temOrigem)
  if temOrigem then
    box:getChildById('portrait'):setImageSource(iconFor(current))
    box:getChildById('nameLabel'):setText(current)
    box:getChildById('infoLabel'):setText('Nv ' .. origem.level .. '   IV ' .. origem.iv .. '%')
    local nat = origem.nature ~= '' and origem.nature or '?'
    local stat = NAT_STAT[origem.nature]
    box:getChildById('natLabel'):setText(nat .. (stat and ('  (+' .. IV_NOMES[stat] .. ')') or '  (neutra)'))
    box:setBorderColor('#5fd35f')
    box:setTooltip('ORIGEM: este fica com tudo (nivel, natureza, IVs, golpes...) e recebe os pontos.\nClique para tirar do slot.')
    box.onClick = function() send('FTOG|' .. origem.key) end
  else
    box:getChildById('emptyLabel'):setText(current == '' and 'Escolha um pokemon' or 'Clique num ' .. current .. ' abaixo para colocar aqui')
    box:setBorderColor('#2b4a75')
    box:setTooltip('')
    box.onClick = nil
  end

  -- slots de MATERIAL
  local slots = W('f2Mats')
  slots:destroyChildren()
  for i = 1, maxMats do
    local slot = g_ui.createWidget('PCForgeSlot', slots)
    local m = mats[i]
    slot:getChildById('title'):setText('MATERIAL ' .. i)
    if m then
      slot:getChildById('portrait'):setImageSource(iconFor(current))
      slot:getChildById('levelLabel'):setText('Nv ' .. m.level)
      slot:getChildById('ivLabel'):setText('IV ' .. m.iv .. '%')
      slot:getChildById('hint'):setText('clique p/ tirar')
      slot:setBorderColor('#f2c400')
      slot:setBackgroundColor('#1f1a06')
      slot:setTooltip('Sera consumido na forja (dando certo ou nao).')
      slot.onClick = function() send('FTOG|' .. m.key) end
    else
      slot:getChildById('levelLabel'):setText('vazio')
      slot:getChildById('levelLabel'):setColor('#3a4c64')
      slot:getChildById('hint'):setText(temOrigem and 'clique num abaixo' or '')
    end
  end

  -- resultado se der certo
  local ivPanel = W('f2Ivs')
  ivPanel:destroyChildren()
  local n = #mats
  local alvo = origem and origem.alvo or 0
  W('f2ResTitle'):setText(origem and ('SE DER CERTO: +' .. (n * (data.pmin or 1)) .. ' a +' .. (n * (data.pmax or 3)) ..
    ' pontos em ' .. (IV_NOMES[alvo] or '-') .. (n == 0 and '   (coloque materiais)' or
    ((origem.ivs[alvo] or 0) + n * (data.pmax or 3) > 31 and '   (sobra vai p/ o menor IV)' or ''))) or 'IVs DA ORIGEM')
  for i = 1, 6 do
    local row = g_ui.createWidget('PCForge2IV', ivPanel)
    local cur = origem and origem.ivs[i] or 0
    row:getChildById('name'):setText(IV_NOMES[i])
    local value = row:getChildById('value')
    local ganho = 0
    if origem and i == alvo and n > 0 then
      local lo, hi = math.min(31, cur + n * (data.pmin or 1)), math.min(31, cur + n * (data.pmax or 3))
      ganho = hi
      value:setText(cur .. '  ->  ' .. lo .. (hi > lo and (' a ' .. hi) or '') .. ' / 31')
      value:setColor('#f2c400')
      row:getChildById('name'):setColor('#f2c400')
    else
      value:setText(origem and (cur .. ' / 31') or '-')
      if cur >= 31 then value:setColor('#5fd35f') end
    end
    -- barras: a largura so existe depois do layout
    local function barras()
      if row:isDestroyed() then return end
      local full = math.max(1, row:getChildById('barBg'):getWidth())
      row:getChildById('bar'):setWidth(math.floor(full * cur / 31))
      row:getChildById('barGain'):setWidth(math.floor(full * ganho / 31))
    end
    barras()
    addEvent(barras)
  end
  if origem then
    W('f2Info'):setText('Chance: ' .. origem.chance .. '%   |   Forjas neste: ' .. origem.forjas ..
      '   |   Se falhar: origem igual, materiais perdidos')
  else
    W('f2Info'):setText('Cada material: +' .. (data.pmin or 1) .. ' a +' .. (data.pmax or 3) .. ' no IV da natureza da origem')
  end

  -- lista do PC
  local list = W('f2List')
  list:destroyChildren()
  W('f2ListTitle'):setText(current == '' and '' or ('SEUS ' .. current:upper() .. ' NO PC   -   clique: ' ..
    (temOrigem and 'material' or 'origem') .. '   |   clique direito: origem'))
  for _, poke in ipairs(cands) do
    local card = g_ui.createWidget('PCForgePoke', list)
    card:getChildById('portrait'):setImageSource(iconFor(current))
    card:getChildById('levelLabel'):setText('Nv ' .. poke.level)
    card:getChildById('ivLabel'):setText(poke.iv >= 0 and ('IV ' .. poke.iv .. '%') or 'IV -')
    local stateLabel = card:getChildById('stateLabel')
    if poke.selected then
      card:setBorderColor('#f2c400')
      card:setBackgroundColor('#1f1a06')
      stateLabel:setText('MATERIAL')
      stateLabel:setColor('#f2c400')
    else
      stateLabel:setText(temOrigem and 'clique: material' or 'clique: origem')
    end
    card:setTooltip('IVs: HP ' .. poke.ivs[1] .. '  Atq ' .. poke.ivs[2] .. '  Def ' .. poke.ivs[3] ..
      '  Atq.Esp ' .. poke.ivs[4] .. '  Def.Esp ' .. poke.ivs[5] .. '  Vel ' .. poke.ivs[6] ..
      '\n\nClique: ' .. (temOrigem and 'usar como material / tirar' or 'colocar na ORIGEM') .. '   |   Clique direito: ORIGEM')
    card.onClick = function() send('FTOG|' .. poke.key) end
    card.onMouseRelease = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        send('FORIG|' .. poke.key)
        return true
      end
      return false
    end
  end
end

local function buildForge(data)
  local list = W('forgeSpeciesList')
  list:destroyChildren()
  for _, species in ipairs(data.species) do
    local row = g_ui.createWidget('PCForgeSpecies', list)
    row:getChildById('portrait'):setImageSource(iconFor(species.name))
    row:getChildById('nameLabel'):setText(species.name)
    local v2 = data.version == 2
    row:getChildById('infoLabel'):setText(species.ready and 'Pronto para forjar' or
      (v2 and 'Precisa de 2 no PC' or ('Faltam ' .. math.max(0, (data.required or 10) - species.count))))
    row:getChildById('infoLabel'):setColor(species.ready and '#5fd35f' or '#6f86a8')
    local count = row:getChildById('countLabel')
    count:setText(v2 and ('x' .. species.count) or (species.count .. '/' .. (data.required or 10)))
    count:setColor(species.ready and '#5fd35f' or '#8fa7c4')
    row:setOn(species.name == data.current)
    row.onClick = function()
      if species.name ~= data.current then send('FSEL|' .. species.name) end
    end
  end
  if #data.species == 0 then
    local empty = g_ui.createWidget('Label', list)
    empty:setText('Nenhum pokemon no PC.')
    empty:setColor('#6f86a8')
  end

  local current = data.current or ''
  setForgeV2(data.version == 2)
  if data.version == 2 then
    buildForge2(data)
  end
  local pokeList = W('forgePokeList')
  pokeList:destroyChildren()
  if current == '' then
    W('forgeTitle'):setText('Escolha um pokemon na lista ao lado')
  else
    W('forgeTitle'):setText(current .. '   -   ' .. (data.selected or 0) .. ' / ' .. (data.required or 10) ..
      ' selecionados   |   clique direito = ORIGINAL (fica com ele)')
  end
  for _, poke in ipairs(data.pokes) do
    local card = g_ui.createWidget('PCForgePoke', pokeList)
    card:getChildById('portrait'):setImageSource(iconFor(current))
    card:getChildById('levelLabel'):setText('Nv ' .. poke.level)
    card:getChildById('ivLabel'):setText(poke.iv >= 0 and ('IV ' .. poke.iv .. '%') or 'IV -')
    local stateLabel = card:getChildById('stateLabel')
    if poke.selected and poke.base then -- codex: o ORIGINAL fica, os outros sao material
      card:setBorderColor('#5fd35f')
      card:setBackgroundColor('#0d2410')
      stateLabel:setText('ORIGINAL')
      stateLabel:setColor('#5fd35f')
    elseif poke.selected then
      card:setBorderColor('#f2c400')
      card:setBackgroundColor('#1f1a06')
      stateLabel:setText('MATERIAL')
      stateLabel:setColor('#f2c400')
    else
      stateLabel:setText('clique p/ usar')
    end
    card:setTooltip('IVs: HP ' .. poke.ivs[1] .. '  Atq ' .. poke.ivs[2] .. '  Def ' .. poke.ivs[3] ..
      '  Atq.Esp ' .. poke.ivs[4] .. '  Def.Esp ' .. poke.ivs[5] .. '  Vel ' .. poke.ivs[6] ..
      '\nEVs: ' .. poke.evs .. '   Boost: +' .. poke.boost .. '   Amizade: ' .. poke.love ..
      '\n\nClique: usar / tirar   |   Clique direito: escolher como ORIGINAL' ..
      (poke.base and '\nORIGINAL: este fica e recebe os atributos forjados' or (poke.selected and '\nMATERIAL: sera consumido na forja' or '')))
    card.onClick = function() send('FTOG|' .. poke.key) end
    card.onMouseRelease = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        send('FBASE|' .. poke.key)
        return true
      end
      return false
    end
  end

  W('hCommon'):setText('COMUM ' .. (100 - (data.perfect or 0)) .. '%')
  W('hPerfect'):setText('PERFEITO ' .. (data.perfect or 0) .. '%')
  fillAttrs(data, current ~= '')
  W('shinyLabel'):setText(data.hasShiny and ('Chance de sair SHINY: ' .. (data.shiny or 0) .. '%') or 'Esse pokemon nao tem versao shiny.')
  W('shinyLabel'):setColor(data.hasShiny and '#f2c400' or '#6f86a8')

  -- pagamento
  local costs = W('forgeCosts')
  costs:destroyChildren()
  local valid = false
  for _, cost in ipairs(data.costs) do
    if cost.currency == forgeCurrency and cost.balance >= cost.amount then valid = true end
  end
  if not valid then
    forgeCurrency = nil
    for _, cost in ipairs(data.costs) do
      if not forgeCurrency and cost.balance >= cost.amount then forgeCurrency = cost.currency end
    end
  end
  for _, cost in ipairs(data.costs) do
    local button = g_ui.createWidget('PCForgeCost', costs)
    -- codex: as moedas dividem a largura (4 ou mais cabem na linha)
    local n = #data.costs
    if n > 3 then
      local largura = costs:getWidth() > 0 and costs:getWidth() or 470
      button:setWidth(math.max(100, math.floor((largura - 6 * (n - 1)) / n)))
    end
    local enough = cost.balance >= cost.amount
    if cost.icon > 0 then button:getChildById('icon'):setItemId(cost.icon) end
    button:getChildById('amount'):setText(curto(cost.amount) .. ' ' .. (CURRENCY_LABEL[cost.currency] or cost.currency))
    button:setTooltip(fmt(cost.amount) .. ' ' .. (CURRENCY_LABEL[cost.currency] or cost.currency) .. '\nSaldo: ' .. fmt(cost.balance))
    button:getChildById('amount'):setColor(enough and '#ffffff' or '#6f86a8')
    local balance = button:getChildById('balance')
    balance:setText('Saldo: ' .. curto(cost.balance))
    balance:setColor(enough and '#5fd35f' or '#e04848')
    button:setOn(cost.currency == forgeCurrency)
    button:setEnabled(enough)
    button.onClick = function()
      forgeCurrency = cost.currency
      for _, other in ipairs(costs:getChildren()) do other:setOn(other == button) end
    end
  end

  local forgeButton = W('forgeButton')
  if data.version == 2 then
    local ready2 = current ~= '' and data.origem ~= nil and (data.selected or 0) >= 1 and forgeCurrency ~= nil and (data.origem.alvo or 0) > 0
    forgeButton:setEnabled(ready2)
    forgeArmedAt = 0
    if current == '' then
      forgeButton:setText('ESCOLHA UM POKEMON')
    elseif not data.origem then
      forgeButton:setText('COLOQUE UM POKEMON NA ORIGEM')
    elseif (data.origem.alvo or 0) == 0 then
      forgeButton:setText('TODOS OS IVs JA ESTAO NO MAXIMO')
    elseif (data.selected or 0) < 1 then
      forgeButton:setText('COLOQUE PELO MENOS 1 MATERIAL')
    elseif not forgeCurrency then
      forgeButton:setText('SALDO INSUFICIENTE')
    else
      forgeButton:setText('FORJAR (' .. data.selected .. (data.selected > 1 and ' MATERIAIS' or ' MATERIAL') .. ', ' .. data.origem.chance .. '% DE CHANCE)')
    end
    return
  end
  local ready = current ~= '' and (data.selected or 0) == (data.required or 10) and forgeCurrency ~= nil
  forgeButton:setEnabled(ready)
  forgeArmedAt = 0
  if current == '' then
    forgeButton:setText('ESCOLHA UM POKEMON')
  elseif (data.selected or 0) ~= (data.required or 10) then
    forgeButton:setText('SELECIONE ' .. (data.required or 10) .. ' (' .. (data.selected or 0) .. '/' .. (data.required or 10) .. ')')
  elseif not forgeCurrency then
    forgeButton:setText('SALDO INSUFICIENTE')
  else
    forgeButton:setText('FORJAR ' .. current:upper())
  end
end

-- ============================================================
-- codex: busca geral (todas as caixas e todas as abas de itens)
-- ============================================================
local function clearSearch()
  gSearch, gRes = '', nil
  searchSent = ''
  local edit = W('searchEdit')
  if edit and edit:getText() ~= '' then edit:setText('') end
end

local function buildSearch()
  local panel = W('searchPanel')
  panel:destroyChildren()
  local res = gRes
  if not res or res.text ~= gSearch:lower() then
    local wait = g_ui.createWidget('Label', panel)
    wait:setText('Buscando "' .. gSearch .. '"...')
    wait:setColor('#6f86a8')
    wait:setHeight(30)
    return
  end
  for _, p in ipairs(res.pokes) do
    local row = g_ui.createWidget('PCMarketRow', panel)
    row:getChildById('icon'):setVisible(false)
    row:getChildById('portrait'):setImageSource(iconFor(p.name))
    row:getChildById('nameLabel'):setText(p.name .. '  Nv ' .. p.level)
    row:getChildById('infoLabel'):setText('Pokemon  -  Caixa ' .. p.box .. ', slot ' .. p.slot ..
      (p.iv >= 0 and ('  -  IV ' .. p.iv .. '%') or '') .. (p.locked and '  -  com cadeado' or ''))
    row:getChildById('priceLabel'):setText('ver na caixa')
    row:getChildById('priceLabel'):setColor('#6f86a8')
    row:setTooltip('Clique para ir ate a caixa ' .. p.box .. '.\nRetirar manda o pokemon para a sua equipe/mochila.')
    if p.locked then row:setBorderColor('#8a6d00') end
    row.onClick = function()
      local text = gSearch
      clearSearch()
      pkSearch, pkHint = text:lower(), nil
      send('GFIND|')
      send('TAB|0')
      send('BOX|' .. p.box)
    end
    local button = row:getChildById('actionButton')
    button:setText('Retirar')
    button.onClick = function() send('GWDP|' .. p.key) end
  end
  for _, it in ipairs(res.items) do
    local row = g_ui.createWidget('PCMarketRow', panel)
    row:getChildById('portrait'):setVisible(false)
    row:getChildById('icon'):setItemId(it.clientId)
    row:getChildById('nameLabel'):setText(fmt(it.count) .. 'x ' .. it.name)
    row:getChildById('infoLabel'):setText('Item  -  aba ' .. it.tabName)
    row:getChildById('priceLabel'):setText('ver na aba')
    row:getChildById('priceLabel'):setColor('#6f86a8')
    row:setTooltip('Clique para ir ate a aba ' .. it.tabName .. '.\nRetirar usa a quantidade do campo de baixo (0 = tudo).')
    row.onClick = function()
      clearSearch()
      send('GFIND|')
      send('TAB|' .. it.tab)
    end
    local button = row:getChildById('actionButton')
    button:setText('Retirar')
    button.onClick = function()
      local amount = tonumber(W('amountEdit'):getText()) or 1
      send('WD|' .. it.id .. '|' .. amount)
    end
  end
  if #res.pokes + #res.items == 0 then
    local empty = g_ui.createWidget('Label', panel)
    empty:setText('Nada no PC com "' .. gSearch .. '".')
    empty:setColor('#6f86a8')
    empty:setHeight(30)
  elseif res.morePokes > #res.pokes or res.moreItems > #res.items then
    local more = g_ui.createWidget('Label', panel)
    more:setText('Mostrando os primeiros ' .. res.limit .. ' de cada. Digite mais letras para filtrar.')
    more:setColor('#f2c400')
    more:setHeight(24)
  end
end

local function applySearchView()
  local active = gSearch ~= '' and state.tab >= 0
  W('searchPanel'):setVisible(active)
  W('searchScroll'):setVisible(active)
  if not active then return end
  pokeGrid:setVisible(false)
  itemGrid:setVisible(false)
  marketPanel:setVisible(false)
  W('marketFilters'):setVisible(false)
  W('marketScroll'):setVisible(false)
  W('pageLabel'):setText('Busca no PC')
  W('hintLabel'):setText('Busca em todas as caixas e abas  |  Clique na linha para ir ate ela  |  Apague o texto para voltar')
  buildSearch()
end

local function sectionOf(index)
  if index == -20 then return 'FORJA' end
  if index == 0 then return 'POKEMONS' end
  if index > 0 then return 'ITENS' end
  return 'MERCADO'
end

-- nomes curtos para caber na linha de categorias (o nome inteiro fica no tooltip)
local SUB_CURTO = { ['mega stones'] = 'Megas', ['held items'] = 'Helds', ['pokebolas'] = 'Bolas' }


-- ============================================================
-- celular: arrastar com o dedo rola as listas (qualquer painel com barra)
-- ============================================================
local function codexDentro(w, pai)
  while w do
    if w == pai then return true end
    w = w:getParent()
  end
  return false
end

local function codexArrastoArea(area)
  if area.codexArrasto then return end
  area.codexArrasto = true
  local ultimoY, ultimoMs = nil, 0
  area.onMouseMove = function(self, pos, moved)
    local barra = self.verticalScrollBar
    local apertado = g_ui.getPressedWidget()
    if not barra or not apertado or g_ui.getDraggingWidget() or apertado:isDraggable()
        or codexDentro(apertado, barra) or not codexDentro(apertado, self)
        or barra:getMaximum() <= barra:getMinimum() then
      ultimoY = nil
      return false
    end
    local agora = g_clock.millis()
    if ultimoY and agora - ultimoMs < 250 then
      local dy = pos.y - ultimoY
      if dy ~= 0 then barra:setValue(barra:getValue() - dy) end
    end
    ultimoY, ultimoMs = pos.y, agora
    return true -- a lista de dentro rola; a de fora fica parada
  end
end

local function codexArrastoRolagem(raiz)
  if not raiz or raiz:isDestroyed() then return end
  local function varrer(w)
    if w.verticalScrollBar then codexArrastoArea(w) end
    for _, filho in ipairs(w:getChildren()) do varrer(filho) end
  end
  varrer(raiz)
end

-- celular: a janela cabe na altura da tela e as listas rolam arrastando o dedo
local function ajustarCelular()
  if not window then return end
  local alturaTela = g_ui.getRootWidget():getHeight()
  if window:getHeight() > alturaTela - 8 then
    window:setHeight(alturaTela - 8)
  end
  -- as listas sao recriadas, mas os paineis com barra ficam: varre sempre
  scheduleEvent(function() codexArrastoRolagem(window) end, 50)
end

local lastItemTab = nil -- ultima aba de itens aberta (a aba "Itens" volta nela)

local function setTabIcon(button, name, itemIcon)
  local image = TAB_ICONS[tostring(name):lower()]
  if image and g_resources.fileExists(image) then
    button:getChildById('icon'):setVisible(false)
    local iconImage = button:getChildById('iconImage')
    iconImage:setImageSource(image)
    iconImage:setVisible(true)
  elseif itemIcon and itemIcon > 0 then
    button:getChildById('icon'):setItemId(itemIcon)
  else
    button:getChildById('icon'):setVisible(false)
    button:setTextOffset({ x = 10, y = 0 })
  end
end

local function openTab(index)
  if state.tab ~= index then
    selected = nil
    searchSent = ''
    W('searchEdit'):setText('')
    pkSearch, pkHint = '', nil
    gSearch, gRes = '', nil
    send('TAB|' .. index)
  end
end

-- abas no topo: Pokemons | Itens | Market | Meus anuncios | Forja
-- "Itens" abre uma segunda linha com as categorias (Pokebolas, Ovos...)
local function buildTabs(tabs)
  tabsPanel:destroyChildren()
  local subPanel = W('subTabsPanel')
  subPanel:destroyChildren()
  local itemTabs, itemTotal = {}, 0
  for _, tab in ipairs(tabs) do
    if tab.index > 0 then
      itemTabs[#itemTabs + 1] = tab
      itemTotal = itemTotal + (tab.count or 0)
    end
  end
  if state.tab > 0 then lastItemTab = state.tab end
  local itemsDone = false
  local function mainTab(name, count, active, iconName, itemIcon, onClick, onDrop)
    local button = g_ui.createWidget('PCMainTab', tabsPanel)
    button:setText(name)
    local label = button:getChildById('countLabel')
    label:setText(count > 999 and '999+' or fmt(count))
    label:setColor(count > 0 and '#dce8f5' or '#5a6b84')
    setTabIcon(button, iconName, itemIcon)
    button:setOn(active)
    button.onClick = onClick
    if onDrop then button.onDrop = onDrop end
  end
  for _, tab in ipairs(tabs) do
    if tab.index > 0 then
      if not itemsDone then
        itemsDone = true
        mainTab('Itens', itemTotal, state.tab > 0, 'outros', 0, function()
          if state.tab > 0 then return end
          local target = lastItemTab
          local ok = false
          for _, t in ipairs(itemTabs) do if t.index == target then ok = true end end
          if not ok then
            target = itemTabs[1].index
            for _, t in ipairs(itemTabs) do
              if (t.count or 0) > 0 then target = t.index break end
            end
          end
          openTab(target)
        end)
      end
    else
      local active = tab.index == state.tab or (tab.index == -1 and state.tab <= -3 and state.tab > -20)
      mainTab(tab.name, tab.count or 0, active, tab.name, tab.icon, function() openTab(tab.index) end, onExternalDrop)
    end
  end
  -- categorias de itens
  local showSub = state.tab > 0 and #itemTabs > 0
  subPanel:setVisible(showSub)
  local linhas = math.ceil(#itemTabs / 5)
  subPanel:setHeight(showSub and (linhas * 30 + (linhas - 1) * 6) or 0)
  W('contentPanel'):setMarginTop(showSub and 6 or 0)
  -- o conteudo tem altura fixa (a do PC); no celular a janela fica mais baixa
  -- e o conteudo rola pela barra da direita
  W('contentInner'):setHeight(showSub and 558 or 630)
  local celular = type(codexCelular) == 'function' and codexCelular()
  W('pcScroll'):setVisible(celular and true or false)
  if celular then ajustarCelular() end
  if showSub then
    for _, tab in ipairs(itemTabs) do
      local button = g_ui.createWidget('PCSubTab', subPanel)
      local nome = button:getChildById('nameLabel')
      nome:setText(tab.name)
      local qtd = button:getChildById('countLabel')
      local n = tab.count or 0
      qtd:setText(n > 9999 and '9999+' or fmt(n))
      qtd:setColor(n > 0 and '#dce8f5' or '#5a6b84')
      if tab.index == state.tab then nome:setColor('#ffe27a') elseif n == 0 then nome:setColor('#6f86a8') end
      button:setTooltip(tab.name .. ': ' .. fmt(tab.count or 0) .. ' item(ns)')
      setTabIcon(button, tab.name, tab.icon)
      button:setOn(tab.index == state.tab)
      button.onClick = function() openTab(tab.index) end
      button.onDrop = onExternalDrop
    end
  end
end

-- ============================================================
-- mensagens do servidor
-- ============================================================
local function showSummary(buffer)
  local panel = W('infoPanel')
  local list = W('infoList')
  list:destroyChildren()
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'INFO' then
      W('infoPortrait'):setImageSource(iconFor(f[2]))
      W('infoName'):setText(f[2] or '')
      local iv = tonumber(f[5]) or -1
      W('infoSub'):setText('Nivel ' .. (f[3] or '?') .. (iv >= 0 and ('   -   IV ' .. iv .. '%') or ''))
    elseif f[1] == 'S' then
      local section = g_ui.createWidget('PCInfoSection', list)
      section:setText(f[2] or '')
    elseif f[1] == 'R' then
      local row = g_ui.createWidget('PCInfoRow', list)
      row:getChildById('key'):setText(f[2] or '')
      local value = row:getChildById('value')
      value:setText(f[3] or '')
      if f[4] and f[4] ~= '' then value:setColor(f[4]) end
    end
  end
  panel:show()
  panel:raise()
end

-- ============================================================
-- clique no PC (sprite 64x64): aceita os 4 quadrados do desenho
-- ============================================================
local pcClientIds = {}
local originalProcessMouseAction = nil

local function findPcNear(pos)
  if not pos then return nil end
  for _, delta in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    local tile = g_map.getTile({ x = pos.x + delta[1], y = pos.y + delta[2], z = pos.z })
    if tile then
      for _, thing in ipairs(tile:getItems() or {}) do
        if pcClientIds[thing:getId()] then return thing end
      end
    end
  end
  return nil
end

local function hookedProcessMouseAction(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
  if next(pcClientIds) and not creatureThing and not (useThing and pcClientIds[useThing:getId()]) then
    local plain = not useThing or useThing:isGround() or useThing:isNotMoveable()
    if plain then
      local pc = findPcNear(autoWalkPos)
      if pc then
        lookThing, useThing = pc, pc
      end
    end
  end
  return originalProcessMouseAction(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
end

local function installClickHook()
  local gi = modules.game_interface
  if gi and gi.processMouseAction and not originalProcessMouseAction then
    originalProcessMouseAction = gi.processMouseAction
    gi.processMouseAction = hookedProcessMouseAction
  end
end

local function removeClickHook()
  local gi = modules.game_interface
  if gi and originalProcessMouseAction then
    gi.processMouseAction = originalProcessMouseAction
    originalProcessMouseAction = nil
  end
end

local function onStorageOpcode(protocol, opcode, buffer)
  if not window then return end
  if buffer == 'CLOSE' then
    hide(true)
    return
  end
  if buffer:sub(1, 6) == 'PCIDS|' then
    pcClientIds = {}
    for _, value in ipairs(splitFields(buffer:sub(7))) do
      local id = tonumber(value)
      if id then pcClientIds[id] = true end
    end
    return
  end
  if buffer:sub(1, 5) == 'GRES|' then -- codex: resultado da busca geral
    local res = { pokes = {}, items = {}, morePokes = 0, moreItems = 0, limit = 60 }
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'GRES' then
        res.text = f[2] or ''
      elseif f[1] == 'GP' then
        res.pokes[#res.pokes + 1] = { key = tonumber(f[2]) or 0, box = tonumber(f[3]) or 1, slot = tonumber(f[4]) or 1,
          name = f[5] or '?', level = tonumber(f[6]) or 0, iv = tonumber(f[7]) or -1, locked = f[8] == '1' }
      elseif f[1] == 'GI' then
        res.items[#res.items + 1] = { id = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, count = tonumber(f[4]) or 1,
          name = f[5] or '?', tab = tonumber(f[6]) or 1, tabName = f[7] or '' }
      elseif f[1] == 'GN' then
        res.morePokes, res.moreItems, res.limit = tonumber(f[2]) or 0, tonumber(f[3]) or 0, tonumber(f[4]) or 60
      end
    end
    gRes = res
    if gSearch ~= '' and window and window:isVisible() then applySearchView() end
    return
  end
  if buffer:sub(1, 4) == 'PKS|' then -- codex: resultado da busca de pokemon
    local f = splitFields(buffer)
    pkSearch = (f[2] or ''):lower()
    if pkSearch == '' then
      pkHint = nil
    else
      local list = {}
      for part in ((f[3] or '') .. ','):gmatch('(.-),') do
        local b, n = part:match('(%d+):(%d+)')
        if b then list[#list + 1] = 'caixa ' .. b .. ' (' .. n .. ')' end
      end
      pkHint = #list > 0 and ('Busca "' .. pkSearch .. '": ' .. table.concat(list, ', ') .. '  |  Enter = proxima caixa') or ('Busca "' .. pkSearch .. '": nada encontrado')
    end
    updateFooter()
    return
  end
  if buffer:sub(1, 5) == 'INFO|' then
    showSummary(buffer)
    return
  end

  local tabs, pokes, items, markets, filters = {}, {}, {}, {}, {}
  local forgeData = { species = {}, pokes = {}, attrs = {}, costs = {} }
  local header
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'PC' then
      header = f
    elseif f[1] == 'T' then
      tabs[#tabs + 1] = { index = tonumber(f[2]) or 0, name = f[3] or '', icon = tonumber(f[4]) or 0, count = tonumber(f[5]) or 0 }
    elseif f[1] == 'P' then
      local slot = tonumber(f[2])
      if slot then
        pokes[slot] = { name = f[3] or '?', level = tonumber(f[4]) or 1, ball = tonumber(f[5]) or 0,
          health = tonumber(f[6]) or 0, maxHealth = tonumber(f[7]) or 0, iv = tonumber(f[8]) or -1,
          gender = f[9], stars = tonumber(f[10]) or 0, boost = tonumber(f[12]) or 0, tags = f[13] or '', locked = f[14] == '1' }
      end
    elseif f[1] == 'M' or f[1] == 'O' then
      markets[#markets + 1] = { id = tonumber(f[2]) or 0, kind = f[3] or 'I', clientId = tonumber(f[4]) or 0, name = f[5] or '',
        count = tonumber(f[6]) or 1, level = tonumber(f[7]) or 0, price = tonumber(f[8]) or 0, currency = f[9] or 'GOLD',
        seller = f[10] or '', info = f[11] or '', mine = f[12] == '1', unit = f[13] == '1',
        status = f[10] or '', buyer = f[11] or '', when = tonumber(f[12]) or 0 }
    elseif f[1] == 'F' then
      filters[#filters + 1] = { index = tonumber(f[2]) or 0, name = f[3] or '', count = tonumber(f[4]) or 0 }
    elseif f[1] == 'FS' then
      forgeData.species[#forgeData.species + 1] = { name = f[2] or '', count = tonumber(f[3]) or 0, ball = tonumber(f[4]) or 0,
        level = tonumber(f[5]) or 0, ready = f[6] == '1' }
    elseif f[1] == 'FP' then
      local ivs = {}
      for i = 5, 10 do ivs[#ivs + 1] = tonumber(f[i]) or 0 end
      forgeData.pokes[#forgeData.pokes + 1] = { key = tonumber(f[2]) or 0, level = tonumber(f[3]) or 0,
        iv = tonumber(f[4]) or -1, ivs = ivs, selected = f[11] == '1',
        boost = tonumber(f[12]) or 0, love = tonumber(f[13]) or 0, evs = tonumber(f[14]) or 0, base = f[15] == '1' }
    elseif f[1] == 'FO' then
      local ivs = {}
      for i = 5, 10 do ivs[#ivs + 1] = tonumber(f[i]) or 0 end
      forgeData.origem = { key = tonumber(f[2]) or 0, level = tonumber(f[3]) or 0, iv = tonumber(f[4]) or -1, ivs = ivs,
        nature = f[11] or '', alvo = tonumber(f[12]) or 0, forjas = tonumber(f[13]) or 0, chance = tonumber(f[14]) or 0 }
    elseif f[1] == 'FM' then
      local ivs = {}
      for i = 5, 10 do ivs[#ivs + 1] = tonumber(f[i]) or 0 end
      forgeData.pokes[#forgeData.pokes + 1] = { key = tonumber(f[2]) or 0, level = tonumber(f[3]) or 0,
        iv = tonumber(f[4]) or -1, ivs = ivs, selected = f[11] == '1', boost = 0, love = 0, evs = 0 }
    elseif f[1] == 'FA' then
      forgeData.attrs[#forgeData.attrs + 1] = { name = f[2] or '', best = tonumber(f[3]) or 0, common = tonumber(f[4]) or 0,
        perfect = tonumber(f[5]) or 0, max = tonumber(f[6]) or 0 }
    elseif f[1] == 'FC' then
      forgeData.costs[#forgeData.costs + 1] = { currency = f[2] or '', amount = tonumber(f[3]) or 0, balance = tonumber(f[4]) or 0,
        icon = tonumber(f[5]) or 0 }
    elseif f[1] == 'FX' then
      forgeData.current = f[2] or ''
      forgeData.selected = tonumber(f[3]) or 0
      forgeData.required = tonumber(f[4]) or 10
      forgeData.perfect = tonumber(f[5]) or 0
      forgeData.shiny = tonumber(f[6]) or 0
      forgeData.hasShiny = f[7] == '1'
      forgeData.bonus = tonumber(f[8]) or 20
      forgeData.version = tonumber(f[9]) or 1
      forgeData.pmin = tonumber(f[10]) or 1
      forgeData.pmax = tonumber(f[11]) or 3
    elseif f[1] == 'B' then
      balances = { GOLD = tonumber(f[2]) or 0, POKECOINS = tonumber(f[3]) or 0, TOKENS = tonumber(f[4]) or 0, DONATE = tonumber(f[5]) or 0 }
    elseif f[1] == 'I' then
      items[#items + 1] = { id = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, count = tonumber(f[4]) or 0, name = f[5] or '' }
    end
  end
  if not header then return end

  local pkUsed, pkMax, itemTotal = tonumber(header[2]) or 0, tonumber(header[3]) or 600, tonumber(header[4]) or 0
  local newTab = tonumber(header[5]) or 0
  if newTab ~= state.tab then selected = nil end
  state.tab = newTab
  state.page = tonumber(header[6]) or 1
  state.pages = tonumber(header[7]) or 1
  state.box = tonumber(header[8]) or 1
  state.boxes = tonumber(header[9]) or 30
  state.slots = tonumber(header[10]) or 20
  local extra = tonumber(header[11]) or 0
  state.tabIsOthers = false
  for _, tab in ipairs(tabs) do
    if tab.index == state.tab and tab.name == 'Outros' then state.tabIsOthers = true end
  end

  local summary = 'Pokemons ' .. pkUsed .. ' / ' .. pkMax .. '   -   Itens ' .. fmt(itemTotal)
  if extra > 0 then summary = summary .. '   -   ' .. extra .. ' sem vaga' end
  W('summaryLabel'):setText(summary)

  buildTabs(tabs)
  local isForge = state.tab == -20
  W('forgePanel'):setVisible(isForge)
  if isForge then
    selected = nil
    buildForge(forgeData)
  else
  local isPoke = state.tab == 0
  local isMarket = state.tab < 0
  pokeGrid:setVisible(isPoke)
  itemGrid:setVisible(not isPoke and not isMarket)
  marketPanel:setVisible(isMarket)
  local isOffers = isMarket and state.tab ~= -2
  W('marketFilters'):setVisible(isOffers)
  W('marketScroll'):setVisible(isMarket)
  if isOffers then
    local all = { index = -1, name = 'Todas', count = 0 }
    for _, tab in ipairs(tabs) do
      if tab.index == -1 then all.count = tab.count end
    end
    table.insert(filters, 1, all)
    buildFilters(filters)
  end
  W('searchEdit'):setVisible(true)
  if isMarket then
    selected = nil
    W('pageLabel'):setText('Pagina ' .. state.page .. ' / ' .. state.pages)
    buildMarket(markets, state.tab == -2)
  elseif isPoke then
    W('pageLabel'):setText('Caixa ' .. state.box .. ' / ' .. state.boxes)
    buildPokeGrid(pokes)
    if selected and selected.kind == 'poke' and not pokes[selected.slot] then selected = nil end
  else
    W('pageLabel'):setText('Pagina ' .. state.page .. ' / ' .. state.pages)
    buildItemGrid(items)
    if selected and selected.kind == 'item' then
      local still = nil
      for _, entry in ipairs(items) do
        if entry.id == selected.id then still = entry end
      end
      if still then selected.count = still.count else selected = nil end
    end
  end
  updateFooter()
  end
  applySearchView() -- codex: busca geral por cima da aba

  if not window:isVisible() then
    window:show()
    window:raise()
    window:focus()
  end
end

-- ============================================================
-- botoes
-- ============================================================
local function changePage(delta)
  if state.tab == 0 then
    local box = state.box + delta
    if box < 1 then box = state.boxes end
    if box > state.boxes then box = 1 end
    selected = nil
    send('BOX|' .. box)
  else
    local page = state.page + delta
    if page < 1 then page = state.pages end
    if page > state.pages then page = 1 end
    send('PAGE|' .. page)
  end
end

local function withdraw(all)
  if not selected then return end
  if selected.kind == 'poke' then
    send('PKWD|' .. selected.slot)
    return
  end
  local amount = all and 0 or math.floor(tonumber(W('amountEdit'):getText()) or 1)
  if not all and amount < 1 then amount = 1 end
  send('WD|' .. selected.id .. '|' .. amount)
end

local function onGameEnd()
  hide(true)
end

function init()
  window = g_ui.displayUI('storage')
  window:hide()
  tabsPanel = W('tabsPanel')
  pokeGrid = W('pokeGrid')
  itemGrid = W('itemGrid')
  marketPanel = W('marketPanel')

  window.onDrop = onExternalDrop
  itemGrid.onDrop = onExternalDrop
  pokeGrid.onDrop = onExternalDrop
  W('prevButton').onClick = function() changePage(-1) end
  W('nextButton').onClick = function() changePage(1) end
  W('prevButton').onDrop = boxArrowDrop(-1)
  W('nextButton').onDrop = boxArrowDrop(1)
  W('withdrawButton').onClick = function() withdraw(false) end
  W('withdrawAllButton').onClick = function() withdraw(true) end
  W('depositTabButton').onClick = function() send('DEPTAB') end
  W('cartAddButton').onClick = addToCart
  W('forgeAuto').onClick = function() send('FAUTO') end
  W('f2Auto').onClick = function() send('FAUTO') end
  W('f2Clear').onClick = function() send('FCLR') end
  W('forgeButton').onClick = function(self)
    if not forgeCurrency then return end
    if os.time() - forgeArmedAt <= 4 then
      forgeArmedAt = 0
      self:setText('FORJANDO...')
      send('FORGE|' .. forgeCurrency)
    else
      forgeArmedAt = os.time()
      self:setText('CLIQUE DE NOVO PARA CONFIRMAR')
    end
  end
  W('releaseButton').onClick = function(self)
    if not selected or selected.kind ~= 'poke' then return end
    if releaseArmed == selected.slot and os.time() - releaseAt <= 5 then
      releaseArmed = nil
      self:setText('Liberar')
      send('PKDEL|' .. selected.slot .. '|' .. selected.name)
    else
      releaseArmed, releaseAt = selected.slot, os.time()
      self:setText('Confirmar?')
      modules.game_textmessage.displayFailureMessage('Clique de novo em Confirmar para liberar ' .. selected.name .. '. Isso nao pode ser desfeito!')
    end
  end
  W('lockButton').onClick = function()
    if selected and selected.kind == 'poke' then send('PKLOCK|' .. selected.slot) end
  end
  W('summaryButton').onClick = function()
    if selected and selected.kind == 'poke' then send('PKINFO|' .. selected.slot) end
  end
  W('infoClose').onClick = function() W('infoPanel'):hide() end
  installClickHook()
  W('sellButton').onClick = openSellPanel
  W('sellConfirm').onClick = confirmSell
  W('sellCancel').onClick = function() W('sellPanel'):hide() end

  local searchEdit = W('searchEdit')
  searchEdit.onTextChange = function(self, text)
    text = tostring(text or ''):gsub('|', '')
    if text ~= searchSent and (text == '' or #text >= 2) then
      searchSent = text
      if state.tab >= 0 then
        -- codex: busca geral (pokemons de todas as caixas + itens de todas as abas)
        gSearch = text
        if text == '' then gRes = nil end
        applySearchView()
        send('GFIND|' .. text)
      else
        send('SEARCH|' .. text)
      end
    end
  end
  W('amountEdit').onTextChange = function(self, text)
    local clean = tostring(text or ''):gsub('%D', '')
    if clean ~= text then self:setText(clean) end
  end

  ProtocolGame.registerExtendedOpcode(OPCODE, onStorageOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  removeClickHook()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if window then
    window:destroy()
    window = nil
  end
end

-- fromServer = true: o servidor ja fechou (nao precisa avisar)
function hide(fromServer)
  if not window then return end
  if window:isVisible() and fromServer ~= true then
    send('CLOSE')
  end
  window:hide()
  W('sellPanel'):hide()
  W('infoPanel'):hide()
  selected = nil
  clearSearch() -- codex: a busca nao fica presa ao reabrir
end
