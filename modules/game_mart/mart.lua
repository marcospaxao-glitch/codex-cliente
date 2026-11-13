-- ============================================================
-- MARK - loja (cliente) - opcode 98
-- Abas: Free (preco normal), VIP (premium, mais barato) e Vender.
-- Pago/recebido no GP do PokeBank, ou em tokens (Token Collector).
-- Pokemon Collector: aba "Meus pokemons" (vende pokemons da equipe).
-- So envia opcodes a partir de cliques do jogador.
-- ============================================================

local OPCODE = 98

local window = nil
local tab = 'FREE'          -- FREE, VIP, SELL, POKE
local ownedOnly = true      -- aba Vender: so o que o jogador tem
local inBag = false        -- receber a compra dentro de uma backpack
local data = { source = '', vip = false, discount = 0, balance = 0, buy = {}, sell = {}, pokes = {},
  currency = 'GOLD', mode = 'shop', vipEnabled = true }
local confirmIndex = nil   -- pokemon esperando o segundo clique

local function cur()
  if data.currency == 'PTS' then return ' ' .. (data.unit or 'pts') end -- codex moeda propria
  return data.currency == 'TOKENS' and ' tokens' or ' gp'
end

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

local function qtyOf(row, max)
  local value = tonumber((row:getChildById('qty'):getText() or ''):match('%d+')) or 0
  if max then value = math.min(value, max) end
  return value
end

local function styleTab(id, active)
  local button = W(id)
  if not button then return end
  button:setColor(active and '#1a1200' or '#dce8f5')
  button:setBackgroundColor(active and '#f2c400' or '#101f3e')
  button:setBorderColor(active and '#ffe27a' or '#24415f')
end

-- ============================================================
-- lista
-- ============================================================
local function render()
  if not window then return end
  local list = W('list')
  list:destroyChildren()
  local pokeMode = data.mode == 'pokemon'
  local tokens = data.currency ~= 'GOLD'
  -- abas visiveis conforme a loja
  W('tabFree'):setVisible(not pokeMode)
  W('tabVip'):setVisible(not pokeMode and data.vipEnabled)
  W('tabSell'):setVisible(pokeMode or #data.sell > 0)
  W('tabSell'):setText(pokeMode and 'Meus pokemons' or 'Vender')
  if pokeMode then
    tab = 'POKE'
  elseif tab == 'POKE' or (tab == 'VIP' and not data.vipEnabled) or (tab == 'SELL' and #data.sell == 0) then
    tab = 'FREE'
  end
  styleTab('tabFree', tab == 'FREE')
  styleTab('tabVip', tab == 'VIP')
  styleTab('tabSell', tab == 'SELL' or tab == 'POKE')
  local filter = W('searchEdit'):getText():lower()
  local selling = tab == 'SELL'
  W('ownedButton'):setVisible(selling)
  W('sellAllButton'):setVisible(selling or pokeMode)
  W('bagButton'):setVisible(not selling and not pokeMode and not tokens)
  W('bagIcon'):setVisible(not selling and not pokeMode and not tokens)

  if pokeMode then
    W('hintLabel'):setText('Clique duas vezes em Vender (o valor vai para o PokeBank). O botao do cadeado protege o pokemon da venda.')
    local shown = 0
    for index, poke in ipairs(data.pokes) do
      if filter == '' or poke.name:lower():find(filter, 1, true) then
        shown = shown + 1
        local card = g_ui.createWidget('MartCard', list)
        local creature = card:getChildById('creature')
        if poke.lookType > 0 then
          creature:setOutfit({ type = poke.lookType })
          creature:setVisible(true)
          card:getChildById('item'):setVisible(false)
        else
          card:getChildById('item'):setItemId(poke.clientId)
        end
        card:getChildById('name'):setText(poke.name)
        -- codex: simbolo de sexo (o mesmo do PC e da barra)
        local genderName = ({ M = 'male', F = 'female' })[poke.gender or '']
        local genderIcon = card:getChildById('genderIcon')
        genderIcon:setVisible(genderName ~= nil)
        if genderName then genderIcon:setImageSource('/modules/game_pokeinfo/images/' .. genderName) end
        -- codex: informacoes do pokemon (sexo, IV, natureza, Tera)
        local sexo = ({ M = 'Macho', F = 'Femea' })[poke.gender] or ''
        local ivLine = ''
        local iv = {}
        for v in (poke.ivs .. ','):gmatch('(.-),') do if v ~= '' then iv[#iv + 1] = v end end
        if #iv == 6 then
          ivLine = '\nIVs: HP ' .. iv[1] .. '  Atq ' .. iv[2] .. '  Def ' .. iv[3] .. '  Atq.Esp ' .. iv[4] .. '  Def.Esp ' .. iv[5] .. '  Vel ' .. iv[6]
        end
        card:setTooltip(poke.name .. ' - nivel ' .. poke.level .. (poke.boost > 0 and ('  +' .. poke.boost) or '') ..
          (sexo ~= '' and ('\nSexo: ' .. sexo) or '') ..
          (poke.ivPct >= 0 and ('\nIV ' .. poke.ivPct .. '% (' .. poke.stars .. ' estrelas)') or '') .. ivLine ..
          (poke.nature ~= '-' and ('\nNatureza: ' .. poke.nature) or '') ..
          (poke.tera ~= '-' and ('\nTera: ' .. poke.tera) or '') ..
          (poke.tags ~= '' and ('\n' .. poke.tags:gsub(',', ' / ')) or ''))
        card:getChildById('qty'):setVisible(false)
        local price, sub = card:getChildById('price'), card:getChildById('sub')
        price:setText(fmt(poke.price) .. ' gp')
        local button = card:getChildById('actionButton')
        -- codex: cadeado (equipe ou PC) direto no Collector
        local lockToggle = card:getChildById('lockToggle')
        lockToggle:setVisible(true)
        lockToggle:setBackgroundColor(poke.locked and '#8a6d00' or '#101f3e')
        lockToggle:setBorderColor(poke.locked and '#f2c400' or '#24415f')
        lockToggle:setTooltip(poke.locked and 'Destrancar (volta a poder vender)' or
          'Cadeado: nao vende, nao libera no PC e nao entra na Forja')
        lockToggle.onClick = function()
          confirmIndex = nil
          send('PKLOCKM|' .. index)
        end
        button:addAnchor(AnchorLeft, 'lockToggle', AnchorRight)
        button:setMarginLeft(5)
        if poke.locked then card:setBorderColor('#8a6d00') end
        if poke.block ~= '' then
          sub:setText(poke.locked and 'Com cadeado' or poke.block)
          sub:setColor(poke.locked and '#f2c400' or '#e04848')
          button:setText('Vender')
          button:setEnabled(false)
        else
          sub:setText('Nv ' .. poke.level .. (poke.boost > 0 and (' +' .. poke.boost) or '') ..
            (poke.ivPct >= 0 and ('  IV ' .. poke.ivPct .. '%') or ''))
          if poke.ivPct >= 80 then sub:setColor('#5fd35f') end
          local armed = confirmIndex == index
          button:setText(armed and 'Confirmar venda?' or 'Vender')
          if armed then card:setBorderColor('#e04848') end
          button.onClick = function()
            if confirmIndex == index then
              confirmIndex = nil
              send('SELLPOKE|' .. index .. '|' .. poke.name .. '|' .. poke.level)
            else
              confirmIndex = index
              render()
              scheduleEvent(function()
                if confirmIndex == index then
                  confirmIndex = nil
                  render()
                end
              end, 4000)
            end
          end
        end
      end
    end
    if shown == 0 then
      W('hintLabel'):setText(#data.pokes == 0 and 'Voce nao tem pokemons na equipe para vender.' or 'Nada encontrado.')
    else
      W('hintLabel'):setText('Passe o mouse para ver IVs, natureza e Tera. O botao do cadeado protege o pokemon (equipe ou PC) da venda.')
    end
    -- codex: vender todos (os que o Collector compra)
    local allCount, allTotal = 0, 0
    for _, poke in ipairs(data.pokes) do
      if poke.block == '' and poke.price > 0 then allCount = allCount + 1; allTotal = allTotal + poke.price end
    end
    local sellAll = W('sellAllButton')
    if not sellAll.armed then sellAll:setText('Vender todos (' .. allCount .. ' - ' .. fmt(allTotal) .. ' gp)') end
    sellAll:setEnabled(allCount > 0)
    return
  end
  W('ownedButton'):setText(ownedOnly and 'Mostrar todos' or 'So o que tenho')
  W('bagIcon'):setItemId(data.bagClientId or 0)
  W('bagButton'):setText((inBag and '[X] ' or '[  ] ') .. 'Receber dentro de backpack' ..
    ((data.bagPrice or 0) > 0 and (' (+' .. fmt(data.bagPrice) .. ')') or ''))
  W('bagButton'):setColor(inBag and '#5fd35f' or '#dce8f5')
  W('bagButton'):setBorderColor(inBag and '#5fd35f' or '#24415f')

  if tab == 'FREE' and tokens then
    W('hintLabel'):setText(data.currency == 'PTS' and ('Precos em ' .. ((data.label or '') ~= '' and data.label or 'pontos') .. '.') or 'Precos em tokens. Itens "surpresa" saem aleatorios.')
  elseif tab == 'FREE' then
    W('hintLabel'):setText(data.vip and ('Voce e VIP: na aba VIP tudo sai ' .. data.discount .. '% mais barato.') or 'Precos normais, pagos com o gp do PokeBank.')
  elseif tab == 'VIP' then
    W('hintLabel'):setText(data.vip and ('Precos VIP: ' .. data.discount .. '% de desconto.') or ('So para VIP (premium): ' .. data.discount .. '% mais barato.'))
  else
    W('hintLabel'):setText(tokens and 'O valor da venda vira tokens.' or 'O valor da venda vai para o gp do seu PokeBank.')
  end

  local shown, sellTotal = 0, 0
  local entries = selling and data.sell or data.buy
  for _, entry in ipairs(entries) do
    if selling then sellTotal = sellTotal + entry.price * entry.owned end
    local visible = (filter == '' or entry.name:lower():find(filter, 1, true)) and (not selling or not ownedOnly or entry.owned > 0)
    if visible then
      shown = shown + 1
      local card = g_ui.createWidget('MartCard', list)
      card:getChildById('item'):setItemId(entry.clientId)
      card:getChildById('name'):setText(entry.name)
      card:setTooltip(entry.name)
      local qty = card:getChildById('qty')
      local button = card:getChildById('actionButton')
      local price, sub = card:getChildById('price'), card:getChildById('sub')
      local itemId = entry.id
      if selling then
        price:setText(fmt(entry.price) .. cur() .. ' cada')
        sub:setText('Voce tem: ' .. fmt(entry.owned))
        sub:setColor(entry.owned > 0 and '#5fd35f' or '#8fa7c4')
        qty:setText(tostring(math.max(entry.owned, 1)))
        button:setText('Vender')
        button:setEnabled(entry.owned > 0)
        if entry.owned > 0 then card:setBorderColor('#2e7d4a') end
        button.onClick = function()
          local count = qtyOf(card, entry.owned)
          if count > 0 then send('SELL|' .. itemId .. '|' .. count) end
        end
      else
        local vipTab = tab == 'VIP'
        local unit = vipTab and entry.vipPrice or entry.price
        price:setText(fmt(unit) .. cur())
        price:setColor(vipTab and '#5fd35f' or '#f2c400')
        if vipTab then
          sub:setText('Normal: ' .. fmt(entry.price) .. cur())
        elseif entry.random then
          sub:setText('Item aleatorio')
        else
          sub:setText(data.vipEnabled and entry.vipPrice < entry.price and ('VIP: ' .. fmt(entry.vipPrice) .. cur()) or '')
        end
        if entry.req ~= '' then
          sub:setText((entry.reqOk and 'Requer ' or 'Falta: ') .. entry.req)
          sub:setColor(entry.reqOk and '#8fa7c4' or '#e04848')
        end
        qty:setText('1')
        local canBuy = (not vipTab or data.vip) and entry.reqOk
        button:setText(not entry.reqOk and 'Bloqueado' or (canBuy and 'Comprar' or 'So VIP'))
        button:setEnabled(canBuy)
        local function update()
          local count = qtyOf(card)
          button:setTooltip(count > 0 and ('Total: ' .. fmt(count * unit) .. cur()) or '')
        end
        qty.onTextChange = update
        update()
        button.onClick = function()
          local count = qtyOf(card)
          if count > 0 then send('BUY|' .. itemId .. '|' .. count .. '|' .. tab .. '|' .. (inBag and 1 or 0)) end
        end
      end
    end
  end
  if selling then
    W('sellAllButton'):setText('Vender tudo (' .. fmt(sellTotal) .. cur() .. ')')
    W('sellAllButton'):setEnabled(sellTotal > 0)
  end
  if shown == 0 then
    W('hintLabel'):setText(selling and ownedOnly and ('Voce nao tem nada que o ' .. (data.merchant or 'Mark') .. ' compra.') or 'Nada encontrado.')
  end
end

-- ============================================================
-- servidor
-- ============================================================
-- mensagens grandes chegam em partes ("@P|parte|total"); junta antes de usar
local pendingParts = {}
local function joinParts(buffer)
  local index, total, rest = buffer:match('^@P|(%d+)|(%d+)\n(.*)$')
  if not index then
    return buffer
  end
  index, total = tonumber(index), tonumber(total)
  if index == 1 then pendingParts = {} end
  pendingParts[index] = rest
  if index < total then
    return nil
  end
  local full = table.concat(pendingParts, '\n', 1, total)
  pendingParts = {}
  return full
end

local function onMartOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  buffer = buffer or ''
  if buffer == 'CLOSE' then
    hide(true)
    return
  end
  local fresh = { buy = {}, sell = {}, pokes = {} }
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'MART' then
      fresh.source = f[2] or ''
      fresh.vip = f[3] == '1'
      fresh.discount = tonumber(f[4]) or 0
      fresh.balance = tonumber(f[5]) or 0
      fresh.bagClientId = tonumber(f[6]) or 0
      fresh.bagPrice = tonumber(f[7]) or 0
      fresh.title = (f[8] and f[8] ~= '') and f[8] or 'MARK - LOJA'
      fresh.merchant = (f[9] and f[9] ~= '') and f[9] or 'Mark'
      fresh.currency = (f[10] == 'TOKENS' or f[10] == 'PTS') and f[10] or 'GOLD'
      fresh.label = f[13] or ''
      fresh.unit = (f[14] and f[14] ~= '') and f[14] or 'pts'
      fresh.mode = (f[11] and f[11] ~= '') and f[11] or 'shop'
      fresh.vipEnabled = f[12] ~= '0'
    elseif f[1] == 'B' then
      fresh.buy[#fresh.buy + 1] = { id = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, name = f[4] or '?',
        price = tonumber(f[5]) or 0, vipPrice = tonumber(f[6]) or 0,
        req = f[7] or '', reqOk = f[8] ~= '0', random = f[9] == '1' }
    elseif f[1] == 'S' then
      fresh.sell[#fresh.sell + 1] = { id = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, name = f[4] or '?',
        price = tonumber(f[5]) or 0, owned = tonumber(f[6]) or 0 }
    elseif f[1] == 'P' then
      fresh.pokes[#fresh.pokes + 1] = { index = tonumber(f[2]) or 0, lookType = tonumber(f[3]) or 0, clientId = tonumber(f[4]) or 0,
        name = f[5] or '?', level = tonumber(f[6]) or 1, boost = tonumber(f[7]) or 0, price = tonumber(f[8]) or 0, block = f[9] or '',
        -- codex: informacoes do pokemon
        nature = f[10] or '-', tera = f[11] or '-', ivs = f[12] or '', gender = f[13] or '', stars = tonumber(f[14]) or 0,
        ivPct = tonumber(f[15]) or -1, tags = f[17] or '', locked = f[18] == '1' }
    end
  end
  if not fresh.source then return end
  if data.merchant ~= fresh.merchant then
    confirmIndex = nil
    tab = 'FREE'
  end
  data = fresh
  confirmIndex = nil
  if data.currency == 'PTS' then W('balanceLabel'):setText(((data.label or '') ~= '' and data.label or 'Pontos') .. ': ' .. fmt(data.balance)) else
  W('balanceLabel'):setText(data.currency == 'TOKENS' and ('Tokens: ' .. fmt(data.balance)) or ('Banco: ' .. fmt(data.balance) .. ' gp'))
  end
  W('vipLabel'):setVisible(data.vipEnabled)
  W('vipLabel'):setText(data.vip and ('VIP  -' .. data.discount .. '%') or 'Sem VIP')
  W('vipLabel'):setColor(data.vip and '#5fd35f' or '#6f86a8')
  W('titleLabel'):setText(data.title .. (data.source == 'notebook' and ' (notebook)' or ''))
  local list = W('list')
  local scroll = W('listScroll')
  local keep = window:isVisible() and scroll and scroll:getValue() or 0
  render()
  if not window:isVisible() then
    window:show()
  end
  window:raise()
  window:focus()
  if keep > 0 then
    scheduleEvent(function() if scroll then scroll:setValue(keep) end end, 30)
  end
end

-- ============================================================
-- abrir / fechar
-- ============================================================
-- usado pelo app Mark do notebook
function open()
  if g_game.isOnline() then
    send('OPEN')
  end
end

function show()
  open()
end

function hide(fromServer)
  if window and window:isVisible() then
    window:hide()
    if not fromServer then
      send('CLOSE')
    end
  end
end

local function setTab(name)
  if data.mode == 'pokemon' then name = 'POKE' end
  tab = name
  render()
end

local function onGameEnd()
  if window then window:hide() end
end

function init()
  window = g_ui.displayUI('mart')
  window:hide()
  W('tabFree').onClick = function() setTab('FREE') end
  W('tabVip').onClick = function() setTab('VIP') end
  W('tabSell').onClick = function() setTab('SELL') end
  W('searchEdit').onTextChange = function() render() end
  W('bagButton').onClick = function()
    inBag = not inBag
    render()
  end
  W('ownedButton').onClick = function()
    ownedOnly = not ownedOnly
    render()
  end
  W('sellAllButton').onClick = function()
    local button = W('sellAllButton')
    if button.armed then
      button.armed = false
      send(data.mode == 'pokemon' and 'SELLALLPOKE' or 'SELL|0|0')
    else
      -- primeiro clique pede confirmacao
      button.armed = true
      button:setText('Clique de novo')
      scheduleEvent(function()
        if button and button.armed then
          button.armed = false
          render()
        end
      end, 3000)
    end
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onMartOpcode)
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
