-- ============================================================
-- CELULAR (cliente) - opcode 97
-- Apps: Aluguel, WhatsApp (contatos por ID + grupos), Loc e Market.
-- So envia opcodes a partir de cliques/teclas do jogador.
-- ============================================================

local OPCODE = 97
local HOTKEY = 'Ctrl+Shift+T'
local IMG = '/modules/game_phone/images/'
local POKE_ICON = '/modules/game_pokemonbar/bar_icon/'
local CHAR_W = 6.2       -- largura media de um caractere (verdana 11)
local LINE_H = 14

local CURRENCIES = { 'GOLD', 'POKECOINS', 'TOKENS', 'DONATE' }
local CURRENCY_NAME = { GOLD = 'gp', POKECOINS = 'PokeCoins', TOKENS = 'Tokens', DONATE = 'Donate' }
local FILTER_NAME = { [-1] = 'Todas', [-2] = 'Meus', [-3] = 'GP', [-4] = 'Coins', [-5] = 'Tokens', [-6] = 'Donate', [-7] = 'Evento' }
local FILTER_ORDER = { -1, -3, -4, -5, -6, -7, -2 }
local AVATAR_COLORS = { '#2e7d4a', '#3478dc', '#a0522d', '#7b4bb3', '#b8860b', '#1f7a7a', '#a83250', '#4a6b8a' }

local window = nil
local topButton = nil
local clockEvent = nil
local theme = '#3478dc'
local view = 'home'
local myId = 0
local device = nil       -- 'phone' ou 'notebook'
local chatMode = 'chat'  -- 'chat' ou 'loc' (escolher para quem mandar a localizacao)
local idMode = 'contact' -- 'contact' (buscar ID) ou 'group' (nome do novo grupo)
local conv = { kind = 'P', id = 0, lastId = 0, owner = false, contact = true }
local membersGroup = 0
local lookup = nil       -- jogador encontrado pelo ID
local market = { tab = -1, page = 1, pages = 1 }
local sell = { entry = nil, currency = 1 }
local confirmKey = nil   -- botao aguardando o segundo clique
local contacts = {}      -- agenda recebida do servidor
local editing = nil      -- contato aberto na tela de edicao

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

local function eachLine(buffer, fn)
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then fn(splitFields(line)) end
  end
end

local function formatNumber(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  local formatted = text:reverse():gsub('(%d%d%d)', '%1.'):reverse()
  return (formatted:gsub('^%.', ''))
end

local function timeText(stamp)
  stamp = tonumber(stamp) or 0
  if stamp <= 0 then return '' end
  if os.date('%d/%m', stamp) == os.date('%d/%m') then
    return os.date('%H:%M', stamp)
  end
  return os.date('%d/%m', stamp)
end

local function initial(name)
  return (tostring(name or '?'):match('%a') or '?'):upper()
end

local function avatarColor(id)
  return AVATAR_COLORS[(math.floor(tonumber(id) or 0) % #AVATAR_COLORS) + 1]
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

-- dois cliques para confirmar (o primeiro troca o texto do botao)
local function confirmClick(button, key, text)
  if not confirmKey or confirmKey.key ~= key then
    if confirmKey and confirmKey.button and not confirmKey.button:isDestroyed() then
      confirmKey.button:setText(confirmKey.text)
    end
    confirmKey = { key = key, button = button, text = button:getText() }
    button:setText(text or 'Confirmar')
    return false
  end
  confirmKey = nil
  return true
end

local function resetConfirm()
  confirmKey = nil
end

-- ============================================================
-- tema / navegacao
-- ============================================================
local function applyTheme(color)
  theme = color or theme
  window:setBorderColor(theme)
  W('notch'):setBackgroundColor(theme)
  W('titleBar'):setBackgroundColor(theme)
  W('homeButton'):setBackgroundColor(theme)
  W('lookupCard'):setBorderColor(theme)
  W('optionsCard'):setBorderColor(theme)
end

local function setBadge(label, count)
  count = tonumber(count) or 0
  if count > 0 then
    label:setText(count > 99 and '99+' or tostring(count))
    label:setVisible(true)
  else
    label:setVisible(false)
  end
end

local function updateUnread(count)
  setBadge(W('appChat'):getChildById('badge'), count)
end

local VIEWS = { 'homeView', 'housesView', 'chatsView', 'convView', 'membersView', 'marketView', 'sellView', 'contactsView', 'contactEditView' }

local function hideCard()
  W('lookupCard'):setVisible(false)
  W('optionsCard'):setVisible(false)
  lookup = nil
end

-- menu de opcoes: { text, fn, danger } (as perigosas pedem 2 cliques)
local function showOptions(title, options)
  W('optionsTitle'):setText(title)
  for i = 1, 3 do
    local button = W('option' .. i)
    local option = options[i]
    if option then
      button:setText(option.text)
      button:setColor(option.danger and '#ff8a8a' or '#dce8f5')
      button:setBorderColor(option.danger and '#e04848' or '#24415f')
      button:setVisible(true)
      button.onClick = function()
        if option.danger and not confirmClick(button, 'O' .. i .. title, 'Clique de novo: ' .. option.text) then
          return
        end
        hideCard()
        option.fn()
      end
    else
      button:setVisible(false)
    end
  end
  resetConfirm()
  W('lookupCard'):setVisible(false)
  W('optionsCard'):setVisible(true)
  W('optionsCard'):raise()
end

local function contactOptions(id, name, isContact)
  local options = {}
  if isContact then
    options[#options + 1] = { text = 'Editar contato', fn = function() send('LOOKUP|' .. id .. '|K') end }
    options[#options + 1] = { text = 'Remover contato', danger = true, fn = function() send('DEL|' .. id) end }
  else
    options[#options + 1] = { text = 'Adicionar contato', fn = function() send('LOOKUP|' .. id .. '|K') end }
  end
  options[#options + 1] = { text = 'Apagar conversa', danger = true, fn = function() send('HIDE|' .. id) end }
  showOptions(name, options)
end

local function groupOptions(id, name, owner)
  local options = {
    { text = owner and 'Membros / adicionar' or 'Ver membros', fn = function() send('GMEMBERS|' .. id) end },
    { text = 'Sair do grupo', danger = true, fn = function() send('GLEAVE|' .. id) end },
  }
  if owner then
    options[#options + 1] = { text = 'Apagar grupo', danger = true, fn = function() send('GDELETE|' .. id) end }
  end
  showOptions(name, options)
end

local function setView(name, title, action)
  view = name
  for _, id in ipairs(VIEWS) do
    W(id):setVisible(id == name .. 'View')
  end
  W('backButton'):setVisible(name ~= 'home')
  W('titleLabel'):setText(title or 'Inicio')
  local button = W('titleAction')
  if action then
    button:setText(action.text)
    button.onClick = action.fn
    button:setVisible(true)
  else
    button:setVisible(false)
  end
  hideCard()
  resetConfirm()
end

local function showWindow()
  if not window:isVisible() then
    window:show()
  end
  window:raise()
  window:focus()
end

local function goHome()
  setView('home', 'Inicio')
end

local function goBack()
  if W('lookupCard'):isVisible() or W('optionsCard'):isVisible() then
    hideCard()
  elseif view == 'conv' then
    -- marca como lido o que chegou enquanto a conversa estava aberta
    if conv.kind == 'G' then
      send('GREAD|' .. conv.id .. '|' .. conv.lastId)
    else
      send('READ|' .. conv.id)
    end
  elseif view == 'members' then
    send('GCONV|' .. membersGroup)
  elseif view == 'contactEdit' then
    send('CONTACTS')
  elseif view == 'sell' then
    send('MKT')
  else
    goHome()
  end
end

-- ============================================================
-- Aluguel
-- ============================================================
local houses = { list = {}, header = nil }

local function renderHouses()
  local list = W('housesList')
  list:destroyChildren()
  local header = houses.header
  local period = header and header[3] or 'periodo'
  local hasHouse = header and (tonumber(header[2]) or 0) > 0
  local filter = W('houseSearch'):getText():lower()
  local shown = 0
  for _, house in ipairs(houses.list) do
    local text = (house.name .. ' ' .. house.town .. ' ' .. house.id):lower()
    -- a casa do jogador aparece sempre (no topo)
    if house.mine or filter == '' or text:find(filter, 1, true) then
      shown = shown + 1
      local row = g_ui.createWidget('PhoneHouse', list)
      row:getChildById('name'):setText(house.name)
      row:getChildById('name'):setColor(house.mine and '#5fd35f' or '#ffffff')
      row:getChildById('info'):setText((house.town ~= '' and (house.town .. '  |  ') or '') .. house.sqm .. ' sqm  |  ' .. house.beds .. ' cama(s)')
      local priceText = house.price > 0 and (formatNumber(house.price) .. ' gp') or 'Gratis'
      if house.rent > 0 then
        priceText = priceText .. '  +' .. formatNumber(house.rent) .. '/' .. period
      end
      row:getChildById('price'):setText(priceText)
      row:getChildById('price'):setColor(house.price > 0 and '#f2c400' or '#5fd35f')
      row:setTooltip('Preco: ' .. (house.price > 0 and (formatNumber(house.price) .. ' gp') or 'gratis') ..
        (house.rent > 0 and ('\nAluguel: ' .. formatNumber(house.rent) .. ' gp por ' .. period) or '\nSem aluguel'))
      if house.mine then
        row:setBorderColor('#5fd35f')
      end
      local houseId = house.id
      row:getChildById('markButton').onClick = function()
        send('HMARK|' .. houseId)
      end
      local button = row:getChildById('actionButton')
      if house.mine then
        button:setText('Sair')
        button.onClick = function()
          if confirmClick(button, 'L' .. houseId) then send('LEAVE') end
        end
      elseif hasHouse then
        -- ja tem casa: pode ver as outras, mas nao alugar
        button:setText('Alugar')
        button:setEnabled(false)
        button:setTooltip('Voce ja tem uma casa. Saia dela para alugar outra.')
      else
        button:setText('Alugar')
        button.onClick = function()
          if confirmClick(button, 'R' .. houseId) then send('RENT|' .. houseId) end
        end
      end
    end
  end
  if shown == 0 then
    local empty = g_ui.createWidget('PhoneHint', list)
    empty:setText(#houses.list == 0 and 'Nenhuma casa livre no momento.' or 'Nenhuma casa encontrada.')
    empty:setTextAlign(AlignCenter)
  end
end

local function showHouses(buffer)
  houses = { list = {}, header = nil }
  eachLine(buffer, function(f)
    if f[1] == 'HOUSES' then
      houses.header = f
    elseif f[1] == 'H' then
      houses.list[#houses.list + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', town = f[4] or '', price = tonumber(f[5]) or 0,
        sqm = tonumber(f[6]) or 0, beds = tonumber(f[7]) or 0, mine = f[8] == '1', rent = tonumber(f[12]) or 0 }
    end
  end)
  setView('houses', 'Aluguel de casas')
  local header = houses.header
  if header then
    local hasHouse = (tonumber(header[2]) or 0) > 0
    W('housesInfo'):setText('Saldo no banco: ' .. formatNumber(header[4]) .. ' gp\n' ..
      (hasHouse and 'Voce ja tem casa (em verde). Limite: 1.' or (#houses.list .. ' casa(s) livre(s). Busque por nome ou cidade:')))
  end
  renderHouses()
  showWindow()
end

-- ============================================================
-- Conversas (WhatsApp / Loc)
-- ============================================================
local function setIdMode(mode)
  idMode = mode
  W('idEdit'):setText('')
  if mode == 'group' then
    W('chatsHint'):setText('Nome do novo grupo:')
    W('idButton'):setText('Criar')
    W('groupModeButton'):setText('Cancelar')
  else
    W('chatsHint'):setText(chatMode == 'loc' and 'Toque em quem vai receber seu local:' or 'Adicionar contato pelo ID:')
    W('idButton'):setText('Buscar')
    W('groupModeButton'):setText('+ Grupo')
  end
end

local function showChats(buffer)
  local list = W('chatsList')
  list:destroyChildren()
  eachLine(buffer, function(f)
    if f[1] == 'CHATS' then
      updateUnread(f[2])
      myId = tonumber(f[3]) or myId
    elseif f[1] == 'C' then
      local kind, id = f[2], tonumber(f[3]) or 0
      local isGroup = kind == 'G'
      local row = g_ui.createWidget('PhoneChat', list)
      local avatar = row:getChildById('avatar')
      avatar:setText(isGroup and '#' or initial(f[4]))
      avatar:setBackgroundColor(isGroup and '#b8860b' or avatarColor(id))
      row:getChildById('name'):setText(f[4] or '?')
      row:getChildById('last'):setText(f[5] or '')
      row:getChildById('time'):setText(timeText(f[6]))
      setBadge(row:getChildById('badge'), f[7])
      local dot = row:getChildById('dot')
      if isGroup then
        dot:setVisible(false)
        row:setTooltip((f[8] or 0) .. ' membros\nBotao direito: opcoes')
      else
        dot:setBackgroundColor(f[8] == '1' and '#5fd35f' or '#6f86a8')
        row:setTooltip((f[8] == '1' and 'Online' or 'Offline') .. '\nBotao direito: opcoes')
      end
      local rowName, isContact = f[4] or '?', f[9] == '1'
      row.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == MouseRightButton and chatMode ~= 'loc' then
          if isGroup then
            groupOptions(id, rowName, false)
          else
            contactOptions(id, rowName, isContact)
          end
          return true
        end
        return false
      end
      row.onClick = function()
        if chatMode == 'loc' then
          send((isGroup and 'GLOC|' or 'LOC|') .. id)
        else
          send((isGroup and 'GCONV|' or 'CONV|') .. id)
        end
      end
    end
  end)
  W('chatsMyId'):setText('Seu ID: ' .. myId)
  setView('chats', chatMode == 'loc' and 'Loc - enviar local' or 'WhatsApp')
  setIdMode('contact')
  W('groupModeButton'):setVisible(chatMode ~= 'loc')
  W('idEdit'):setVisible(chatMode ~= 'loc')
  W('idButton'):setVisible(chatMode ~= 'loc')
  showWindow()
end

local function onIdButton()
  local text = W('idEdit'):getText():gsub('[|\n\r]', '')
  if idMode == 'group' then
    if #text >= 2 then
      send('GNEW|' .. text:sub(1, 24))
    end
    return
  end
  local id = tonumber(text:match('%d+'))
  if id then
    send('LOOKUP|' .. id .. '|C')
  end
end

-- cartao com o jogador encontrado pelo ID
local function showLookup(f)
  local purpose, id = f[2], tonumber(f[3]) or 0
  local name, level = f[4] or '?', f[5] or '?'
  local online, isContact, groupId = f[6] == '1', f[7] == '1', tonumber(f[8]) or 0
  lookup = { purpose = purpose, id = id, group = groupId }
  W('cardTitle'):setText(purpose == 'G' and 'Adicionar ao grupo?' or (isContact and 'Ja esta nos contatos' or 'Adicionar contato?'))
  W('cardAvatar'):setText(initial(name))
  W('cardAvatar'):setBackgroundColor(avatarColor(id))
  W('cardName'):setText(name)
  W('cardInfo'):setText('ID ' .. id .. '  |  Level ' .. level .. '  |  ' .. (online and 'Online' or 'Offline'))
  W('cardInfo'):setColor(online and '#5fd35f' or '#8fa7c4')
  local main = W('cardMain')
  if purpose == 'G' then
    main:setText('Adicionar ao grupo')
    main.onClick = function() send('GADD|' .. groupId .. '|' .. id); hideCard() end
    W('cardChat'):setVisible(false)
  else
    main:setText(isContact and 'Abrir conversa' or 'Adicionar e conversar')
    main.onClick = function() send((isContact and 'CONV|' or 'ADD|') .. id); hideCard() end
    W('cardChat'):setVisible(not isContact)
    W('cardChat').onClick = function() send('CONV|' .. id); hideCard() end
  end
  W('lookupCard'):setVisible(true)
  W('lookupCard'):raise()
  showWindow()
end

-- ============================================================
-- mensagens (baloes)
-- ============================================================
local function wrapLines(text, width)
  local perLine = math.max(8, math.floor(width / CHAR_W))
  local lines, longest = 0, 0
  for paragraph in ((text or '') .. '\n'):gmatch('(.-)\n') do
    local used = 0
    lines = lines + 1
    for word in paragraph:gmatch('%S+') do
      local size = #word
      if used > 0 and used + 1 + size > perLine then
        lines = lines + 1
        longest = math.max(longest, used)
        used = 0
      end
      while size > perLine do
        lines = lines + 1
        longest = perLine
        size = size - perLine
      end
      used = used + (used > 0 and 1 or 0) + size
    end
    longest = math.max(longest, used)
  end
  return math.max(1, lines), longest
end

local function addBubble(messageId, mine, text, stamp, locX, locY, locZ, author)
  local list = W('messagesList')
  local row = g_ui.createWidget('PhoneMsgRow', list)
  local bubble = row:getChildById('bubble')
  local isLoc = (tonumber(locX) or 0) > 0
  local showAuthor = true -- toda mensagem mostra quem enviou
  local listWidth = list:getWidth()
  if listWidth < 100 then listWidth = 262 end
  local maxWidth = math.floor(listWidth * 0.78)

  local body = text or ''
  local textLeft = 8
  if isLoc then
    body = 'Localizacao ' .. locX .. ', ' .. locY .. ', ' .. locZ .. '\nClique para marcar no mapa'
    textLeft = 28
  end
  local timeLabel = bubble:getChildById('time')
  timeLabel:setText(timeText(stamp))
  local lines, longest = wrapLines(body, maxWidth - textLeft - 8)
  local authorWidth = showAuthor and ((#(author or '') + (mine and 7 or 0)) * CHAR_W) or 0
  local width = math.max(longest * CHAR_W + textLeft + 10, authorWidth + 16, 70)
  width = math.min(maxWidth, math.floor(width))
  -- se a hora nao cabe na ultima linha, ganha uma linha propria
  local timeRow = 13
  local textHeight = lines * LINE_H

  local authorLabel = bubble:getChildById('author')
  if showAuthor then
    authorLabel:setText(mine and ((author or 'Voce') .. ' (voce)') or (author or '?'))
    local hash = 0
    for i = 1, #(author or '') do hash = hash + author:byte(i) end
    authorLabel:setColor(mine and '#8fe08f' or ({ '#f2c400', '#6fb7ff', '#ff8fb8', '#ffa64d', '#b48cff' })[hash % 5 + 1])
    authorLabel:setHeight(14)
  else
    authorLabel:setText('')
    authorLabel:setHeight(0)
    authorLabel:setMarginTop(4)
  end
  local textLabel = bubble:getChildById('text')
  textLabel:setText(body)
  textLabel:setHeight(textHeight)
  textLabel:setMarginLeft(textLeft)
  textLabel:setMarginTop(showAuthor and 2 or 1)
  local pin = bubble:getChildById('pin')
  pin:setVisible(isLoc)
  pin:setMarginTop(showAuthor and 4 or 2)

  bubble:setWidth(width)
  row:setHeight((showAuthor and 21 or 5) + textHeight + timeRow + 5)

  if mine then
    bubble:removeAnchor(AnchorLeft)
    bubble:addAnchor(AnchorRight, 'parent', AnchorRight)
    bubble:setBackgroundColor('#123a26')
    bubble:setBorderColor('#2e7d4a')
  end
  if isLoc then
    bubble:setBorderColor('#e04848')
    bubble:setPhantom(false)
    bubble:setTooltip('Clique para marcar no seu mapa')
    bubble.onClick = function()
      send('MARK|' .. conv.kind .. '|' .. messageId)
    end
  end
  conv.lastId = math.max(conv.lastId, tonumber(messageId) or 0)
  return row
end

local function scrollToEnd()
  scheduleEvent(function()
    local bar = W('messagesScroll')
    if bar and window and window:isVisible() then
      bar:setValue(bar:getMaximum())
    end
  end, 60)
end

local function showConversation(buffer)
  local list = W('messagesList')
  list:destroyChildren()
  local header
  eachLine(buffer, function(f)
    if f[1] == 'CONV' then
      header = f
      conv = { kind = f[2], id = tonumber(f[3]) or 0, lastId = 0, owner = f[2] == 'G' and f[6] == '1', contact = f[2] == 'P' and f[6] == '1' }
      updateUnread(f[7])
    elseif f[1] == 'M' then
      addBubble(tonumber(f[2]) or 0, f[3] == '1', f[4], f[5], f[6], f[7], f[8], f[9])
    end
  end)
  if not header then return end
  chatMode = 'chat'
  local title, action
  local id, name, owner, isContact = conv.id, header[4] or '?', conv.owner, conv.contact
  conv.name = name
  if conv.kind == 'G' then
    title = name .. '  (' .. (header[5] or 0) .. ')'
    action = { text = 'Opcoes', fn = function() groupOptions(id, name, owner) end }
  else
    title = name .. (header[5] == '1' and '  - online' or '')
    action = { text = 'Opcoes', fn = function() contactOptions(id, name, isContact) end }
  end
  setView('conv', title, action)
  if list:getChildCount() == 0 then
    W('msgEdit'):setText('')
  end
  showWindow()
  W('msgEdit'):focus()
  scrollToEnd()
end

local function onPush(f)
  -- PUSH|tipo|id|nome|texto|msgId|hora|x|y|z|naolidas|autor
  local kind, id = f[2], tonumber(f[3]) or 0
  updateUnread(f[11])
  if window:isVisible() and view == 'conv' and conv.kind == kind and conv.id == id then
    addBubble(tonumber(f[6]) or 0, false, f[5], f[7], f[8], f[9], f[10], kind == 'P' and conv.name or f[12])
    scrollToEnd()
  end
end

local function sendMessage()
  local edit = W('msgEdit')
  local text = edit:getText():gsub('[|\n\r]', ' ')
  if text:match('^%s*$') or conv.id <= 0 then return end
  edit:setText('')
  send((conv.kind == 'G' and 'GSEND|' or 'SEND|') .. conv.id .. '|' .. text:sub(1, 200))
end

local function sendLocation()
  if conv.id > 0 then
    send((conv.kind == 'G' and 'GLOC|' or 'LOC|') .. conv.id)
  end
end

-- ============================================================
-- membros do grupo
-- ============================================================
local function showMembers(buffer)
  local list = W('membersList')
  list:destroyChildren()
  local owner, groupName = false, ''
  eachLine(buffer, function(f)
    if f[1] == 'GMEMBERS' then
      membersGroup = tonumber(f[2]) or 0
      groupName = f[3] or ''
      owner = f[4] == '1'
      W('membersInfo'):setText((f[5] or 0) .. ' de ' .. (f[6] or 100) .. ' membros' .. (owner and '  |  voce e o dono' or ''))
    elseif f[1] == 'U' then
      local id = tonumber(f[2]) or 0
      local row = g_ui.createWidget('PhoneMember', list)
      row:getChildById('dot'):setBackgroundColor(f[4] == '1' and '#5fd35f' or '#6f86a8')
      row:getChildById('name'):setText((f[3] or '?') .. (f[5] == '1' and '  (dono)' or '') .. '  #' .. id)
      row:getChildById('name'):setColor(f[5] == '1' and '#f2c400' or '#ffffff')
      local kick = row:getChildById('kickButton')
      kick:setVisible(owner and id ~= myId)
      kick.onClick = function()
        if confirmClick(kick, 'K' .. id, 'Certeza?') then
          send('GKICK|' .. membersGroup .. '|' .. id)
        end
      end
    end
  end)
  W('memberHint'):setText(owner and 'Adicionar membro pelo ID:' or 'So o dono adiciona membros.')
  W('memberIdEdit'):setVisible(owner)
  W('memberIdButton'):setVisible(owner)
  local full = W('membersView'):getWidth()
  if full < 100 then full = 298 end
  W('leaveGroupButton'):setWidth(owner and math.floor((full - 16) / 2) or (full - 12))
  W('deleteGroupButton'):setVisible(owner)
  W('memberIdEdit'):setText('')
  setView('members', groupName)
  showWindow()
end

-- ============================================================
-- Market do celular
-- ============================================================
local function setFilterStyle(button, active)
  button:setColor(active and '#1a1200' or '#8fa7c4')
  button:setBackgroundColor(active and '#f2c400' or '#101f3e')
  button:setBorderColor(active and '#ffe27a' or '#1d3557')
end

local function showMarket(buffer)
  local list = W('marketList')
  list:destroyChildren()
  local counts = {}
  local mineTab = false
  eachLine(buffer, function(f)
    if f[1] == 'MKT' then
      market.tab = tonumber(f[2]) or -1
      market.page = tonumber(f[3]) or 1
      market.pages = tonumber(f[4]) or 1
      mineTab = market.tab == -2
      market.bal = { GOLD = tonumber(f[5]) or 0, POKECOINS = tonumber(f[6]) or 0, TOKENS = tonumber(f[7]) or 0, DONATE = tonumber(f[8]) or 0 }
      W('balanceLabel'):setText('GP ' .. formatNumber(f[5]) .. '  |  Coins ' .. formatNumber(f[6]) .. '  |  Tk ' .. formatNumber(f[7]) .. '  |  Dn ' .. formatNumber(f[8]))
      if not W('searchEdit'):isFocused() then
        W('searchEdit'):setText(f[9] or '')
      end
    elseif f[1] == 'F' then
      counts[tonumber(f[2]) or 0] = tonumber(f[4]) or 0
    elseif f[1] == 'M' or f[1] == 'O' then
      local offerId = tonumber(f[2]) or 0
      local isPoke = f[3] == 'P'
      local row = g_ui.createWidget('PhoneOffer', list)
      if isPoke then
        row:getChildById('item'):setVisible(false)
        row:getChildById('portrait'):setVisible(true)
        row:getChildById('portrait'):setImageSource(pokeIcon(f[5]))
      else
        row:getChildById('item'):setItemId(tonumber(f[4]) or 0)
      end
      local count = tonumber(f[6]) or 1
      local unit = f[13] == '1' -- preco por unidade (comprador escolhe a quantidade)
      local name = (count > 1 and (count .. 'x ') or '') .. (f[5] or '?')
      if unit and not isPoke then name = (f[5] or '?') .. ' (' .. formatNumber(count) .. ' disp.)' end
      if isPoke then name = name .. '  Lv ' .. (f[7] or 1) end
      row:getChildById('name'):setText(name)
      row:getChildById('price'):setText(formatNumber(f[8]) .. ' ' .. (CURRENCY_NAME[f[9]] or f[9] or '') .. (unit and ' /un' or ''))
      local button = row:getChildById('actionButton')
      if f[1] == 'M' then
        local info = f[11] ~= '' and f[11] or ('Vendedor: ' .. (f[10] or '?'))
        row:getChildById('info'):setText(info)
        row:setTooltip('Vendedor: ' .. (f[10] or '?') .. (f[11] ~= '' and ('\n' .. f[11]) or ''))
        if f[12] == '1' then
          button:setText('Cancelar')
          button.onClick = function()
            if confirmClick(button, 'C' .. offerId) then send('MCANCEL|' .. offerId) end
          end
        elseif unit then
          local unitPrice = tonumber(f[8]) or 0
          local qtyEdit = row:getChildById('qtyEdit')
          local infoLabel = row:getChildById('info')
          local qty = 1
          qtyEdit:setVisible(true)
          qtyEdit:setText('1')
          qtyEdit:setTooltip('Quantidade (1 a ' .. formatNumber(count) .. ')')
          local function showTotal()
            local total = unitPrice * qty
            local falta = total > ((market.bal or {})[f[9]] or 0)
            infoLabel:setText('TOTAL ' .. formatNumber(qty) .. 'x: ' .. formatNumber(total) .. ' ' .. (CURRENCY_NAME[f[9]] or f[9] or '') .. (falta and '  (sem saldo)' or ''))
            infoLabel:setColor(falta and '#ff6b6b' or '#ffd84a')
            button:setEnabled(not falta)
            button:setText(falta and 'Sem saldo' or 'Comprar')
            resetConfirm()
          end
          qtyEdit.onTextChange = function(self, text)
            local digits = tostring(text or ''):gsub('%D', '')
            if digits ~= text then self:setText(digits) return end
            local n = tonumber(digits)
            if n and n > count then self:setText(tostring(count)) return end
            qty = math.max(1, n or 1)
            showTotal()
          end
          button.onClick = function()
            if confirmClick(button, 'B' .. offerId .. 'x' .. qty) then send('MBUY|' .. offerId .. '|' .. qty) end
          end
          showTotal()
        else
          button:setText('Comprar')
          button.onClick = function()
            if confirmClick(button, 'B' .. offerId) then send('MBUY|' .. offerId) end
          end
        end
      else
        local status = f[10] or ''
        local info = status
        if status == 'VENDIDO' and f[11] ~= '' then info = 'Vendido para ' .. f[11] end
        row:getChildById('info'):setText(info)
        row:getChildById('info'):setColor(status == 'ATIVO' and '#5fd35f' or (status == 'VENDIDO' and '#f2c400' or '#6f86a8'))
        if status == 'ATIVO' then
          button:setText('Cancelar')
          button.onClick = function()
            if confirmClick(button, 'C' .. offerId) then send('MCANCEL|' .. offerId) end
          end
        else
          button:setVisible(false)
        end
      end
    end
  end)

  local grid = W('filterGrid')
  grid:destroyChildren()
  for _, index in ipairs(FILTER_ORDER) do
    local button = g_ui.createWidget('PhoneFilter', grid)
    button:setText(FILTER_NAME[index])
    if counts[index] and counts[index] > 0 and index ~= -1 then
      button:setTooltip(counts[index] .. ' anuncio(s)')
    end
    setFilterStyle(button, market.tab == index)
    button.onClick = function()
      send('MKT|' .. index .. '|1|' .. W('searchEdit'):getText():gsub('[|\n\r]', ''))
    end
  end
  local sellTab = g_ui.createWidget('PhoneFilter', grid)
  sellTab:setText('Anunciar')
  sellTab:setColor('#5fd35f')
  sellTab:setBorderColor('#2e7d4a')
  sellTab.onClick = function() send('MSELLLIST') end -- volta na aba/pagina em que estava

  W('pageLabel'):setText('Pagina ' .. market.page .. ' de ' .. market.pages)
  W('prevPage'):setEnabled(market.page > 1)
  W('nextPage'):setEnabled(market.page < market.pages)
  if list:getChildCount() == 0 then
    local empty = g_ui.createWidget('PhoneHint', list)
    empty:setText(mineTab and 'Voce nao tem anuncios.' or 'Nenhum anuncio encontrado.')
    empty:setTextAlign(AlignCenter)
  end
  setView('market', 'Market')
  showWindow()
end

local function searchMarket()
  send('MKT|' .. market.tab .. '|1|' .. W('searchEdit'):getText():gsub('[|\n\r]', ''):sub(1, 30))
end

local function updateSellPanel()
  local entry = sell.entry
  local currency = CURRENCIES[sell.currency]
  W('sellCurrency'):setText(CURRENCY_NAME[currency])
  if not entry then
    W('sellSelected'):setText('Escolha um item ou pokemon da lista.')
    W('sellSelected'):setColor('#6f86a8')
    W('sellButton'):setEnabled(false)
    W('sellCount'):setEnabled(false)
    return
  end
  W('sellSelected'):setText(entry.label)
  W('sellSelected'):setColor('#ffffff')
  W('sellButton'):setEnabled(true)
  W('sellCount'):setEnabled(entry.kind == 'I')
  W('sellCount'):setText(entry.kind == 'I' and tostring(entry.total) or '1')
  W('sellPriceHint'):setText((entry.kind == 'I' and entry.total > 1) and 'Preco por unid.' or 'Preco')
end

-- nomes curtos das abas do PC (cabem no botao)
local SELL_TAB_SHORT = { ['Pokemons'] = 'Pokemons', ['Pokebolas'] = 'Balls', ['Mega Stones'] = 'Megas', ['Pocoes'] = 'Pocoes',
  ['Held Items'] = 'Held', ['Vitaminas'] = 'Vitamin.', ['Moedas'] = 'Moedas', ['Outros'] = 'Outros', ['Stones'] = 'Stones', ['Pesca'] = 'Pesca' }

local function requestSell(cat, page)
  local search = W('sellSearch'):getText():gsub('[|\n\r]', ''):sub(1, 30)
  send('MSELLLIST|' .. (cat or sell.cat or 0) .. '|' .. (page or 1) .. '|' .. search)
end

local function showSellList(buffer)
  local list = W('sellList')
  list:destroyChildren()
  sell.entry = nil
  local total = 0
  local tabs = {}
  eachLine(buffer, function(f)
    local entry
    if f[1] == 'SELLLIST' then
      sell.cat = tonumber(f[2]) or 0
      sell.page = tonumber(f[3]) or 1
      sell.pages = tonumber(f[4]) or 1
      if not W('sellSearch'):isFocused() then
        W('sellSearch'):setText(f[5] or '')
      end
    elseif f[1] == 'ST' then
      tabs[#tabs + 1] = { index = tonumber(f[2]) or 0, name = f[3] or '?', count = tonumber(f[4]) or 0 }
    elseif f[1] == 'SP' then
      local iv = tonumber(f[7]) or -1
      entry = { kind = 'P', a = f[2], b = f[3], label = (f[5] or '?') .. '  Lv ' .. (f[6] or 1),
        info = 'Box ' .. f[2] .. '  |  ' .. (iv >= 0 and ('IV ' .. iv .. '%') or 'Pokemon'), name = f[5], clientId = tonumber(f[4]) or 0 }
    elseif f[1] == 'SI' then
      entry = { kind = 'I', a = f[2], total = tonumber(f[5]) or 1, label = f[4] or '?', info = 'No PC: ' .. formatNumber(f[5]),
        clientId = tonumber(f[3]) or 0 }
    end
    if entry then
      total = total + 1
      local row = g_ui.createWidget('PhoneSellRow', list)
      if entry.kind == 'P' then
        row:getChildById('item'):setVisible(false)
        row:getChildById('portrait'):setVisible(true)
        row:getChildById('portrait'):setImageSource(pokeIcon(entry.name))
      else
        row:getChildById('item'):setItemId(entry.clientId)
      end
      row:getChildById('name'):setText(entry.label)
      row:getChildById('info'):setText(entry.info)
      row.onClick = function()
        for _, child in ipairs(list:getChildren()) do
          child:setBorderColor('#1d3557')
        end
        row:setBorderColor('#f2c400')
        sell.entry = entry
        resetConfirm()
        W('sellButton'):setText('Anunciar')
        updateSellPanel()
      end
    end
  end)
  -- abas (iguais as do PC)
  local grid = W('sellCats')
  grid:destroyChildren()
  local catName = ''
  for _, tab in ipairs(tabs) do
    local button = g_ui.createWidget('PhoneFilter', grid)
    button:setText(SELL_TAB_SHORT[tab.name] or tab.name:sub(1, 8))
    button:setTooltip(tab.name .. ': ' .. tab.count)
    local active = tab.index == sell.cat
    if active then catName = tab.name end
    setFilterStyle(button, active)
    if not active and tab.count == 0 then
      button:setColor('#3d5470')
    end
    button.onClick = function() requestSell(tab.index, 1) end
  end
  local searching = W('sellSearch'):getText() ~= ''
  if total > 0 then
    W('sellHint'):setText(catName .. ' no seu PC' .. (searching and ' (busca)' or '') .. ':')
  else
    W('sellHint'):setText(searching and 'Nada encontrado nessa aba.' or ('Nenhum item em ' .. catName .. '.'))
  end
  W('sellPageLabel'):setText('Pagina ' .. (sell.page or 1) .. ' de ' .. (sell.pages or 1))
  W('sellPrev'):setEnabled((sell.page or 1) > 1)
  W('sellNext'):setEnabled((sell.page or 1) < (sell.pages or 1))
  setView('sell', 'Anunciar no Market')
  W('sellButton'):setText('Anunciar')
  updateSellPanel()
  showWindow()
end

local function doSell()
  local entry = sell.entry
  if not entry then return end
  local price = tonumber(W('sellPrice'):getText():match('%d+'))
  if not price or price < 1 then
    W('sellSelected'):setText('Digite o preco.')
    W('sellSelected'):setColor('#e04848')
    return
  end
  local count = 1
  if entry.kind == 'I' then
    count = math.max(1, math.min(entry.total, tonumber(W('sellCount'):getText():match('%d+')) or 1))
  end
  local button = W('sellButton')
  local confirmText = 'Confirmar ' .. formatNumber(price) .. ' ' .. CURRENCY_NAME[CURRENCIES[sell.currency]]
  if entry.kind == 'I' and count > 1 then confirmText = 'Confirmar ' .. formatNumber(price) .. '/un' end
  if not confirmClick(button, 'S', confirmText) then
    return
  end
  button:setText('Anunciar')
  local b = entry.kind == 'I' and count or entry.b
  -- item com quantidade: preco digitado e POR UNIDADE (o comprador escolhe quantas)
  local porUnidade = entry.kind == 'I' and count > 1
  send('MSELL|' .. entry.kind .. '|' .. entry.a .. '|' .. b .. '|' .. price .. '|' .. CURRENCIES[sell.currency] .. (porUnidade and '|U' or ''))
end

-- ============================================================
-- Agenda (Contatos)
-- ============================================================
local function displayName(contact)
  return contact.alias ~= '' and contact.alias or contact.name
end

local function renderContacts()
  local list = W('contactsList')
  list:destroyChildren()
  local filter = W('contactSearch'):getText():lower()
  local shown = 0
  for _, contact in ipairs(contacts) do
    local text = (displayName(contact) .. ' ' .. contact.name .. ' ' .. contact.id .. ' ' .. contact.note):lower()
    if filter == '' or text:find(filter, 1, true) then
      shown = shown + 1
      local row = g_ui.createWidget('PhoneContact', list)
      row:getChildById('avatar'):setText(initial(displayName(contact)))
      row:getChildById('avatar'):setBackgroundColor(avatarColor(contact.id))
      row:getChildById('dot'):setBackgroundColor(contact.online and '#5fd35f' or '#6f86a8')
      row:getChildById('fav'):setVisible(contact.favorite)
      row:getChildById('name'):setText(displayName(contact))
      local sub = (contact.alias ~= '' and (contact.name .. '  ') or '') .. '#' .. contact.id
      if contact.note ~= '' then sub = sub .. '  |  ' .. contact.note end
      row:getChildById('sub'):setText(sub)
      row:setTooltip((contact.online and 'Online' or 'Offline') .. '  |  Level ' .. contact.level)
      row.onClick = function() openContactEdit(contact, false) end
    end
  end
  if shown == 0 then
    local empty = g_ui.createWidget('PhoneHint', list)
    empty:setText(#contacts == 0 and 'Agenda vazia. Toque em + Novo.' or 'Nenhum contato encontrado.')
    empty:setTextAlign(AlignCenter)
  end
end

local function showContacts(buffer)
  contacts = {}
  local total, max = 0, 0
  eachLine(buffer, function(f)
    if f[1] == 'CONTACTS' then
      total, max = tonumber(f[2]) or 0, tonumber(f[3]) or 0
    elseif f[1] == 'K' then
      contacts[#contacts + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', alias = f[4] or '', note = f[5] or '',
        favorite = f[6] == '1', online = f[7] == '1', level = tonumber(f[8]) or 0 }
    end
  end)
  -- favoritos primeiro, depois em ordem alfabetica
  table.sort(contacts, function(a, b)
    if a.favorite ~= b.favorite then return a.favorite end
    return displayName(a):lower() < displayName(b):lower()
  end)
  setView('contacts', 'Contatos')
  W('contactsInfo'):setText(total .. ' de ' .. max .. ' contatos')
  renderContacts()
  showWindow()
end

local function setEditField(id, visible)
  W(id):setVisible(visible)
end

local function updateFavButton()
  W('favButton'):setText(editing and editing.favorite and '* Favorito (toque para tirar)' or 'Marcar como favorito')
  W('favButton'):setColor(editing and editing.favorite and '#f2c400' or '#dce8f5')
end

-- abre a ficha do contato. isNew = adicionando um novo (ainda sem jogador escolhido)
function openContactEdit(contact, isNew)
  editing = contact
  setView('contactEdit', isNew and 'Novo contato' or 'Editar contato')
  local hasPlayer = contact ~= nil
  for _, id in ipairs({ 'newIdHint', 'newIdEdit', 'newIdButton' }) do
    setEditField(id, isNew)
  end
  for _, id in ipairs({ 'editAvatar', 'editRealName', 'editInfo', 'aliasHint', 'aliasEdit', 'noteHint', 'noteEdit', 'favButton', 'saveContactButton' }) do
    setEditField(id, hasPlayer)
  end
  local saved = hasPlayer and contact.saved
  for _, id in ipairs({ 'msgContactButton', 'locContactButton' }) do
    setEditField(id, hasPlayer)
  end
  setEditField('deleteContactButton', saved)
  W('deleteContactButton'):setText('Apagar contato')
  if isNew and not hasPlayer then
    W('newIdEdit'):setText('')
    W('newIdEdit'):focus()
  end
  if not hasPlayer then return end
  W('editAvatar'):setText(initial(displayName(contact)))
  W('editAvatar'):setBackgroundColor(avatarColor(contact.id))
  W('editRealName'):setText(contact.name)
  W('editInfo'):setText('ID ' .. contact.id .. '  |  Level ' .. contact.level .. '  |  ' .. (contact.online and 'Online' or 'Offline'))
  W('editInfo'):setColor(contact.online and '#5fd35f' or '#8fa7c4')
  W('aliasEdit'):setText(contact.alias)
  W('noteEdit'):setText(contact.note)
  W('saveContactButton'):setText(saved and 'Salvar alteracoes' or 'Salvar na agenda')
  updateFavButton()
end

local function saveContact()
  if not editing then return end
  local alias = W('aliasEdit'):getText():gsub('[|\n\r]', ''):sub(1, 32)
  local note = W('noteEdit'):getText():gsub('[|\n\r]', ' '):sub(1, 64)
  send('CSAVE|' .. editing.id .. '|' .. (editing.favorite and 1 or 0) .. '|' .. alias .. '|' .. note)
end

local function searchNewContact()
  local id = tonumber(W('newIdEdit'):getText():match('%d+'))
  if id then send('LOOKUP|' .. id .. '|K') end
end

-- ============================================================
-- mensagens do servidor
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

local function onPhoneOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  local head = (buffer or ''):match('^([^|\n]*)')
  if head == 'HOME' then
    local f = splitFields(buffer)
    applyTheme(f[2] ~= '' and f[2] or theme)
    applyDevice(f[6] == 'notebook' and 'notebook' or 'phone')
    W('modelLabel'):setText((device == 'notebook' and 'Notebook ' or 'Celular ') .. (f[3] or ''))
    updateUnread(f[4])
    myId = tonumber(f[5]) or myId
    W('myIdLabel'):setText('Seu ID: ' .. myId)
    goHome()
    showWindow()
  elseif head == 'HOUSES' then
    showHouses(buffer)
  elseif head == 'CHATS' then
    showChats(buffer)
  elseif head == 'INFO' then
    local f = splitFields(buffer)
    if f[2] == 'K' then
      -- nova entrada na agenda (ou ja existente: abre para editar)
      local saved = f[7] == '1'
      openContactEdit({ id = tonumber(f[3]) or 0, name = f[4] or '?', level = tonumber(f[5]) or 0, online = f[6] == '1',
        alias = f[9] or '', note = f[10] or '', favorite = f[11] == '1', saved = saved }, not saved)
      if not saved then W('newIdEdit'):setText(f[3] or '') end
      showWindow()
    else
      showLookup(f)
    end
  elseif head == 'CONTACTS' then
    showContacts(buffer)
  elseif head == 'CONV' then
    showConversation(buffer)
  elseif head == 'PUSH' then
    onPush(splitFields(buffer))
  elseif head == 'GMEMBERS' then
    showMembers(buffer)
  elseif head == 'MKT' then
    showMarket(buffer)
  elseif head == 'SELLLIST' then
    showSellList(buffer)
  elseif head == 'CLOSE' then
    hide()
  end
end

-- ============================================================
-- abrir / fechar
-- ============================================================
local function tickClock()
  clockEvent = nil
  if not window or not window:isVisible() then return end
  W('clockLabel'):setText(os.date('%H:%M'))
  clockEvent = scheduleEvent(tickClock, 15000)
end

function show()
  if g_game.isOnline() then
    send('OPEN')
  end
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

local function onGameEnd()
  hide()
  conv = { kind = 'P', id = 0, lastId = 0, owner = false, contact = true }
end

-- celular ou notebook: o notebook e maior e tem PC, PokeBank e Mark
local NOTEBOOK_APPS = { 'appPC', 'appBank', 'appMark' }

function applyDevice(kind)
  if kind == device then return end
  device = kind
  local notebook = kind == 'notebook'
  window:setSize(notebook and { width = 780, height = 540 } or { width = 320, height = 620 })
  W('notch'):setSize(notebook and { width = 8, height = 8 } or { width = 70, height = 6 })
  W('homeButton'):setSize(notebook and { width = 110, height = 8 } or { width = 46, height = 14 })
  for _, id in ipairs(NOTEBOOK_APPS) do
    W(id):setVisible(notebook)
  end
  local grid = W('appGrid')
  local layout = grid:getLayout()
  local columns = notebook and 4 or 3
  local spacing = notebook and 34 or 15
  layout:setNumColumns(columns)
  layout:setCellSpacing(spacing)
  grid:setSize({ width = columns * 72 + (columns - 1) * spacing, height = 2 * 80 + spacing })
  W('appMarket'):setTooltip(notebook and 'Abre o Market do PC' or '')
  W('homeHint'):setText(notebook and 'Notebook: PC e Market completos de qualquer lugar.\nPasse o seu ID para os amigos te adicionarem.'
    or 'Passe o seu ID para os amigos te adicionarem.')
end

local function setupApp(id, name, icon, fn)
  local app = W(id)
  app:getChildById('name'):setText(name)
  app:getChildById('icon'):setImageSource(IMG .. icon)
  app.onClick = fn
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

function init()
  window = g_ui.displayUI('phone')
  window:hide()

  setupApp('appHouses', 'Aluguel', 'app_house', function() send('HOUSES') end)
  setupApp('appChat', 'WhatsApp', 'app_chat', function() chatMode = 'chat'; send('CHATS') end)
  setupApp('appContacts', 'Contatos', 'app_contacts', function() send('CONTACTS') end)
  setupApp('appLoc', 'Loc', 'app_loc', function() chatMode = 'loc'; send('CHATS') end)
  setupApp('appMarket', 'Market', 'app_market', function()
    -- notebook: Market do PC (janela do PC). Celular: Market do celular
    send(device == 'notebook' and 'NBMARKET' or 'MKT')
  end)
  setupApp('appPC', 'PC', 'app_pc', function() send('NBPC') end)
  setupApp('appBank', 'PokeBank', 'app_bank', function() send('NBBANK') end)
  setupApp('appMark', 'Mark', 'app_mark', function()
    local mart = modules.game_mart
    if mart and mart.open then
      mart.open()
    end
  end)
  W('homeHint'):setText('Passe o seu ID para os amigos te adicionarem.')

  W('homeButton').onClick = goHome
  W('backButton').onClick = goBack
  -- conversa
  W('sendButton').onClick = sendMessage
  W('locButton'):setTooltip('Enviar minha localizacao')
  W('locButton').onClick = sendLocation
  onEnter('msgEdit', sendMessage)
  -- contatos / grupos
  W('idButton').onClick = onIdButton
  onEnter('idEdit', onIdButton)
  W('groupModeButton').onClick = function()
    setIdMode(idMode == 'group' and 'contact' or 'group')
    W('idEdit'):focus()
  end
  W('cardCancel').onClick = hideCard
  local function findMember()
    local id = tonumber(W('memberIdEdit'):getText():match('%d+'))
    if id then send('LOOKUP|' .. id .. '|G|' .. membersGroup) end
  end
  W('memberIdButton').onClick = findMember
  onEnter('memberIdEdit', findMember)
  W('optionsCancel').onClick = hideCard
  W('houseSearch'):setTooltip('Buscar por nome ou cidade')
  W('houseSearch').onTextChange = function() resetConfirm(); renderHouses() end
  -- agenda
  W('newContactButton').onClick = function() openContactEdit(nil, true) end
  W('contactSearch').onTextChange = function() renderContacts() end
  W('newIdButton').onClick = searchNewContact
  onEnter('newIdEdit', searchNewContact)
  W('saveContactButton').onClick = saveContact
  onEnter('aliasEdit', saveContact)
  onEnter('noteEdit', saveContact)
  W('favButton').onClick = function()
    if editing then
      editing.favorite = not editing.favorite
      updateFavButton()
    end
  end
  W('msgContactButton').onClick = function()
    if editing then chatMode = 'chat'; send('CONV|' .. editing.id) end
  end
  W('locContactButton').onClick = function()
    if editing then send('LOC|' .. editing.id) end
  end
  W('deleteContactButton').onClick = function()
    local button = W('deleteContactButton')
    if editing and confirmClick(button, 'CD' .. editing.id, 'Clique de novo para apagar') then
      send('CDEL|' .. editing.id)
    end
  end
  W('deleteGroupButton').onClick = function()
    local button = W('deleteGroupButton')
    if confirmClick(button, 'GD' .. membersGroup, 'Confirmar') then
      button:setText('Apagar grupo')
      send('GDELETE|' .. membersGroup)
    end
  end
  W('leaveGroupButton').onClick = function()
    local button = W('leaveGroupButton')
    if confirmClick(button, 'GL' .. membersGroup, 'Confirmar') then
      button:setText('Sair do grupo')
      send('GLEAVE|' .. membersGroup)
    end
  end
  -- market
  W('searchButton').onClick = searchMarket
  onEnter('searchEdit', searchMarket)
  W('prevPage').onClick = function() send('MKT|' .. market.tab .. '|' .. (market.page - 1)) end
  W('nextPage').onClick = function() send('MKT|' .. market.tab .. '|' .. (market.page + 1)) end
  W('sellCurrency').onClick = function()
    sell.currency = sell.currency % #CURRENCIES + 1
    resetConfirm()
    W('sellButton'):setText('Anunciar')
    updateSellPanel()
  end
  W('sellButton').onClick = doSell
  W('sellSearchButton').onClick = function() requestSell(sell.cat, 1) end
  onEnter('sellSearch', function() requestSell(sell.cat, 1) end)
  W('sellPrev').onClick = function() requestSell(sell.cat, (sell.page or 1) - 1) end
  W('sellNext').onClick = function() requestSell(sell.cat, (sell.page or 1) + 1) end

  window.onVisibilityChange = function(widget, visible)
    if visible and not clockEvent then tickClock() end
  end
  applyTheme(theme)
  applyDevice('phone')
  goHome()

  ProtocolGame.registerExtendedOpcode(OPCODE, onPhoneOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, toggle)

  local topmenu = modules.client_topmenu
  local ok, button = pcall(function()
    local tooltip = 'Celular / Notebook.\nAtalho: ' .. HOTKEY
    if topmenu.addCenterGameButton then
      return topmenu.addCenterGameButton('phoneButton', tooltip, IMG .. 'topbutton.png', toggle)
    end
    return topmenu.addRightGameToggleButton('phoneButton', tooltip, IMG .. 'topbutton', toggle)
  end)
  if ok then topButton = button end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown(HOTKEY)
  if clockEvent then
    removeEvent(clockEvent)
    clockEvent = nil
  end
  if topButton then
    topButton:destroy()
    topButton = nil
  end
  if window then
    window:destroy()
    window = nil
  end
end
