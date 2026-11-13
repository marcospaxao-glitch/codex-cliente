-- ============================================================
-- CLA / CASTELOS / GUERRA (cliente) - opcode 104
-- Servidor: data/lib/core/clans.lua
-- Abre pelo atalho Ctrl+Shift+C ou pelo botao do topo.
-- So envia opcodes a partir de cliques/teclas do jogador.
-- ============================================================

local OPCODE = 104
local HOTKEY = 'Ctrl+Shift+C'
local RANKS = { 'Membro', 'Vice-lider', 'Lider' }

local window = nil
local topButton = nil
local timerEvent = nil
local page = 'overview'
local selectedCastle = nil
local warEndsAt = 0
local data = nil
-- codex castelos v2: lugares dos guardioes e bau virtual (mensagem CX do servidor)
local extra = { pos = {}, vault = {}, info = {} }
local sideMode = 'guard'   -- painel da direita: 'guard' (guardioes) ou 'vault' (bau)

local NAV = {
  overview = 'navOverview', members = 'navMembers', allies = 'navAllies', castles = 'navCastles',
  bank = 'navBank', shop = 'navShop', ranking = 'navRanking',
}
local PAGES = {
  none = 'pageNone', overview = 'pageOverview', members = 'pageMembers', allies = 'pageAllies',
  castles = 'pageCastles', bank = 'pageBank', shop = 'pageShop', ranking = 'pageRanking',
}

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

local function numberOf(widget)
  return tonumber(((widget:getText() or ''):gsub('[^%d]', ''))) or 0
end

local function textOf(widget)
  return ((widget:getText() or ''):gsub('[|\n\r]', ' '))
end

-- botao que pede um segundo clique para confirmar
local function confirmClick(button, label, action)
  button:setText(label)
  button.armed = false
  button.onClick = function()
    if button.armed then
      button.armed = false
      button:setText(label)
      action()
    else
      button.armed = true
      button:setText('Confirmar?')
      scheduleEvent(function()
        if button and not button:isDestroyed() and button.armed then
          button.armed = false
          button:setText(label)
        end
      end, 3000)
    end
  end
end

local function myRank()
  return data and data.rank or 0
end

-- ============================================================
-- relogio da guerra
-- ============================================================
local function updateWarLabel()
  local label = W('warLabel')
  if not label or not data then return end
  if data.war then
    local left = math.max(0, warEndsAt - os.time())
    label:setText(string.format('GUERRA ATIVA  %02d:%02d', math.floor(left / 60), left % 60))
    label:setColor('#e04848')
  else
    label:setText('Sem guerra no momento')
    label:setColor('#8fa7c4')
  end
end

local function tickTimer()
  timerEvent = nil
  if not window or not window:isVisible() then return end
  updateWarLabel()
  timerEvent = scheduleEvent(tickTimer, 1000)
end

-- ============================================================
-- paginas
-- ============================================================
local function buildNone()
  W('createHint'):setText('Escolha um nome (so letras, 3 a 20). Custa ' .. fmt(data.createCost) .. ' gp do PokeBank.')
  local list = W('invitesList')
  list:destroyChildren()
  if #data.invites == 0 then
    local row = g_ui.createWidget('ClPairRow', list)
    row:getChildById('name'):setText('Nenhum convite.')
    row:getChildById('name'):setColor('#8fa7c4')
    row:getChildById('firstButton'):setVisible(false)
    row:getChildById('secondButton'):setVisible(false)
  end
  for _, inv in ipairs(data.invites) do
    local row = g_ui.createWidget('ClPairRow', list)
    row:getChildById('name'):setText(inv.name)
    row:getChildById('info'):setText(inv.members .. ' membros')
    local accept, decline = row:getChildById('firstButton'), row:getChildById('secondButton')
    accept:setText('Aceitar')
    decline:setText('Recusar')
    local id = inv.id
    accept.onClick = function() send('ACCEPT|' .. id) end
    decline.onClick = function() send('DECLINE|' .. id) end
  end
end

local function buildOverview()
  W('clanName'):setText(data.name)
  W('myRank'):setText(RANKS[data.rank] or '')
  W('leaderLabel'):setText('Lider: ' .. data.leader)
  W('membersLabel'):setText('Membros: ' .. data.members .. ' / ' .. data.maxMembers)
  W('pointsLabel'):setText('Pontos: ' .. fmt(data.points) .. (data.rankPos > 0 and ('   -   #' .. data.rankPos .. ' no ranking') or ''))
  local owned = {}
  for _, c in ipairs(data.castles) do
    if c.ours then owned[#owned + 1] = c.name end
  end
  W('castlesLabel'):setText('Castelos: ' .. (#owned > 0 and table.concat(owned, ', ') or 'nenhum'))
  W('bonusLabel'):setText(data.bonus ~= '' and ('Bonus ativo para todos os membros: ' .. data.bonus) or 'Domine um castelo para ganhar bonus de exp e loot.')
  W('bonusLabel'):setColor(data.bonus ~= '' and '#5fd35f' or '#8fa7c4')
  W('motdLabel'):setText(data.motd ~= '' and data.motd or 'Sem aviso.')
  local canEdit = myRank() >= 2
  W('motdEdit'):setVisible(canEdit)
  W('motdButton'):setVisible(canEdit)
  W('disbandButton'):setVisible(myRank() == 3)
  W('dangerHint'):setText(myRank() == 3 and 'O lider so sai passando a lideranca (aba Membros) ou desfazendo o cla.' or '')
end

local function buildMembers()
  local canInvite = myRank() >= 2
  W('inviteEdit'):setVisible(canInvite)
  W('inviteButton'):setVisible(canInvite)
  W('membersHint'):setText(canInvite and 'Digite o nome de um jogador online.' or 'So lider e vice convidam.')
  local list = W('membersList')
  list:destroyChildren()
  table.sort(data.memberList, function(a, b)
    if a.rank ~= b.rank then return a.rank > b.rank end
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  for _, m in ipairs(data.memberList) do
    local row = g_ui.createWidget('ClMemberRow', list)
    row:getChildById('dot'):setBackgroundColor(m.online and '#5fd35f' or '#5f7596')
    row:getChildById('dot'):setTooltip(m.online and 'Online' or 'Offline')
    row:getChildById('name'):setText(m.name)
    row:getChildById('name'):setColor(m.online and '#ffffff' or '#8fa7c4')
    row:getChildById('rank'):setText(RANKS[m.rank] or '')
    row:getChildById('level'):setText('Nv ' .. m.level)
    row:getChildById('donated'):setText('Doou ' .. fmt(m.donated))
    local isMe = m.name == data.me
    local name = m.name
    local leader = myRank() == 3
    local promote, demote = row:getChildById('promoteButton'), row:getChildById('demoteButton')
    local kick, transfer = row:getChildById('kickButton'), row:getChildById('transferButton')
    promote:setVisible(leader and not isMe and m.rank == 1)
    demote:setVisible(leader and not isMe and m.rank == 2)
    promote:setTooltip('Promover a Vice-lider')
    demote:setTooltip('Rebaixar a Membro')
    promote.onClick = function() send('PROMOTE|' .. name) end
    demote.onClick = function() send('DEMOTE|' .. name) end
    kick:setVisible(not isMe and myRank() >= 2 and m.rank < myRank())
    confirmClick(kick, 'Expulsar', function() send('KICK|' .. name) end)
    transfer:setVisible(leader and not isMe)
    transfer:setTooltip('Passar a lideranca para ' .. name)
    confirmClick(transfer, 'Lideranca', function() send('TRANSFER|' .. name) end)
  end
end

local function buildAllies()
  local leader = myRank() == 3
  W('allyEdit'):setVisible(leader)
  W('allyButton'):setVisible(leader)
  W('alliesHint'):setText('Aliados nao tomam dano um do outro na guerra e nao quebram o Emperium do aliado. Maximo ' ..
    data.maxAllies .. ' aliancas.' .. (leader and '' or ' So o lider negocia aliancas.'))
  local list = W('alliesList')
  list:destroyChildren()
  local function row(name, info, first, second, firstAction, secondAction, color)
    local r = g_ui.createWidget('ClPairRow', list)
    r:getChildById('name'):setText(name)
    if color then r:getChildById('name'):setColor(color) end
    r:getChildById('info'):setText(info)
    local b1, b2 = r:getChildById('firstButton'), r:getChildById('secondButton')
    b1:setVisible(first ~= nil and leader)
    b2:setVisible(second ~= nil and leader)
    if first then b1:setText(first) b1.onClick = firstAction end
    if second then
      if second == 'Romper' then
        confirmClick(b2, second, secondAction)
      else
        b2:setText(second)
        b2.onClick = secondAction
      end
    end
  end
  for _, a in ipairs(data.allies) do
    local id = a.id
    row(a.name, a.members .. ' membros  -  ' .. fmt(a.points) .. ' pts', nil, 'Romper', nil, function() send('ALLYBREAK|' .. id) end, '#5fd35f')
  end
  for _, r in ipairs(data.requests) do
    local id = r.id
    if r.dir == 'in' then
      row(r.name, 'quer ser seu aliado', 'Aceitar', 'Recusar',
        function() send('ALLYACCEPT|' .. id) end, function() send('ALLYDECLINE|' .. id) end, '#f2c400')
    else
      row(r.name, 'pedido enviado', nil, 'Cancelar', nil, function() send('ALLYDECLINE|' .. id) end, '#8fa7c4')
    end
  end
  if #data.allies == 0 and #data.requests == 0 then
    row('Nenhuma alianca.', '', nil, nil, nil, nil, '#8fa7c4')
  end
end

local function sinceText(since)
  if since <= 0 then return '' end
  local days = math.floor((os.time() - since) / 86400)
  return days > 0 and (' ha ' .. days .. ' dia(s)') or ' desde hoje'
end

local function positionOf(draggedWidget)
  if not draggedWidget or draggedWidget:getClassName() ~= 'UIItem' then return nil end
  local item = draggedWidget:getItem()
  local pos = item and item:getPosition()
  if not pos or pos.x ~= 65535 then
    modules.game_textmessage.displayFailureMessage('Arraste um item da sua mochila.')
    return nil
  end
  return pos
end

local function buildVault(castle)
  local list = W('guardList')
  local info = extra.info[castle.id] or { ready = false, manage = false, max = 60 }
  local items = extra.vault[castle.id] or {}
  W('guardTitle'):setText('BAU - ' .. castle.name:upper())
  W('guardHint'):setText('Arraste itens da mochila para ca para guardar (' .. #items .. ' / ' .. info.max .. '). ' ..
    'Se o castelo for perdido, tudo vai para o PC do lider.')
  local function onDrop(self, dragged)
    local pos = positionOf(dragged)
    if not pos then return false end
    send('VDEP|' .. castle.id .. '|' .. pos.x .. '|' .. pos.y .. '|' .. pos.z)
    return true
  end
  list.onDrop = onDrop
  if info.manage then
    local row = g_ui.createWidget('ClVaultRow', list)
    row.onDrop = onDrop
    row:getChildById('name'):setText('Recompensa do dia')
    row:getChildById('info'):setText(info.ready and 'Pronta: cai dentro do bau' or 'Ja pega hoje. Volte amanha.')
    row:getChildById('icon'):setVisible(false)
    local b = row:getChildById('actionButton')
    b:setText('Pegar')
    b:setEnabled(info.ready)
    local id = castle.id
    b.onClick = function() send('VDAY|' .. id) end
    row:setBackgroundColor('#1f1a06')
  end
  for _, it in ipairs(items) do
    local row = g_ui.createWidget('ClVaultRow', list)
    row.onDrop = onDrop
    row:getChildById('icon'):setItemId(it.clientId)
    row:getChildById('name'):setText(it.name)
    row:getChildById('info'):setText(fmt(it.count) .. 'x')
    local b = row:getChildById('actionButton')
    b:setVisible(info.manage)
    local id, index = castle.id, it.index
    confirmClick(b, 'Retirar', function() send('VWD|' .. id .. '|' .. index .. '|0') end)
  end
  if #items == 0 then
    local row = g_ui.createWidget('ClVaultRow', list)
    row.onDrop = onDrop
    row:getChildById('icon'):setVisible(false)
    row:getChildById('name'):setText('Bau vazio')
    row:getChildById('info'):setText('Arraste um item da mochila ate aqui')
    row:getChildById('actionButton'):setVisible(false)
  end
end

local function buildGuardians()
  local list = W('guardList')
  list:destroyChildren()
  list.onDrop = nil
  local castle = nil
  for _, c in ipairs(data.castles) do
    if c.id == selectedCastle and c.ours then castle = c end
  end
  if castle and sideMode == 'vault' then return buildVault(castle) end
  if not castle then
    W('guardTitle'):setText('GUARDIOES')
    W('guardHint'):setText('Seu cla precisa dominar um castelo. Os guardioes nascem quando a guerra comeca.')
    return
  end
  local canManage = myRank() >= 2
  W('guardTitle'):setText('GUARDIOES - ' .. castle.name:upper())
  W('guardHint'):setText(#castle.guardians .. ' / ' .. data.maxGuardians .. ' contratados. Pagos com o banco do cla (' .. fmt(data.bank) .. ' gp).')
  if #castle.guardians > 0 then
    local top = g_ui.createWidget('ClVaultRow', list)
    top:setHeight(30)
    top:getChildById('icon'):setVisible(false)
    top:getChildById('name'):setText('Onde ficam na guerra')
    top:getChildById('info'):setText('Fique no lugar e use Aqui')
    local b = top:getChildById('actionButton')
    b:setText('Mostrar')
    local id = castle.id
    b.onClick = function() send('GSHOW|' .. id) end
  end
  for slot, name in ipairs(castle.guardians) do
    local row = g_ui.createWidget('ClGuardHiredRow', list)
    row:getChildById('name'):setText(name)
    local p = (extra.pos[castle.id] or {})[slot]
    row:getChildById('info'):setText(p and ('Fica em ' .. p) or 'Lugar automatico')
    row:getChildById('info'):setColor(p and '#5fd35f' or '#f2c400')
    for _, g in ipairs(data.catalog) do
      if g.monster == name and g.look > 0 then row:getChildById('look'):setOutfit({ type = g.look }) end
    end
    local id, s = castle.id, slot
    local here = row:getChildById('posButton')
    here:setVisible(canManage and not data.war)
    here:setTooltip('Fique em cima do lugar, dentro do castelo, e clique.\nO guardiao nasce ai quando a guerra comecar.')
    here.onClick = function() send('GPOS|' .. id .. '|' .. s) end
    local auto = row:getChildById('autoButton')
    auto:setVisible(canManage and not data.war and p ~= nil)
    auto.onClick = function() send('GPOSCLR|' .. id .. '|' .. s) end
    local b = row:getChildById('actionButton')
    b:setVisible(canManage and not data.war)
    confirmClick(b, 'Dispensar', function() send('GREMOVE|' .. id .. '|' .. s) end)
  end
  for _, g in ipairs(data.catalog) do
    local row = g_ui.createWidget('ClGuardRow', list)
    row:getChildById('name'):setText(g.monster)
    row:getChildById('info'):setText(fmt(g.price) .. ' gp')
    if g.look > 0 then row:getChildById('look'):setOutfit({ type = g.look }) end
    row:setBackgroundColor('#101f3e')
    local b = row:getChildById('actionButton')
    b:setText('Contratar')
    b:setVisible(canManage)
    b:setEnabled(#castle.guardians < data.maxGuardians and data.bank >= g.price)
    local id, idx = castle.id, g.index
    b.onClick = function() send('GBUY|' .. id .. '|' .. idx) end
  end
end

local function buildCastles()
  local list = W('castlesList')
  list:destroyChildren()
  for _, c in ipairs(data.castles) do
    local card = g_ui.createWidget('ClCastleCard', list)
    card:getChildById('name'):setText(c.name)
    card:getChildById('owner'):setText(c.owner ~= '' and ('Dono: ' .. c.owner .. sinceText(c.since)) or 'Sem dono')
    local status = card:getChildById('status')
    local accent = card:getChildById('accent')
    if c.inWar then
      status:setText('EM GUERRA - quebre o Emperium para conquistar')
      status:setColor('#e04848')
      accent:setBackgroundColor('#e04848')
    else
      status:setText(c.ours and ('Seu castelo  -  ' .. #c.guardians .. ' guardiao(es)') or 'Aguardando a proxima guerra')
      status:setColor(c.ours and '#5fd35f' or '#8fa7c4')
      accent:setBackgroundColor(c.ours and '#f2c400' or '#5f7596')
    end
    if c.ours then card:setBorderColor('#6b5a10') end
    local track, fill, hpText = card:getChildById('hpTrack'), card:getChildById('hpFill'), card:getChildById('hpText')
    local showHp = c.inWar and c.max > 0
    track:setVisible(showHp)
    fill:setVisible(showHp)
    hpText:setVisible(showHp)
    if showHp then
      local ratio = math.max(0, math.min(1, c.hp / c.max))
      hpText:setText('Emperium  ' .. fmt(c.hp) .. ' / ' .. fmt(c.max))
      local function size()
        if fill:isDestroyed() then return end
        local w = track:getWidth()
        if not w or w <= 2 then w = 330 end
        fill:setWidth(math.floor((w - 2) * ratio))
      end
      size()
      scheduleEvent(size, 50)
    end
    local go, chest, guard = card:getChildById('gotoButton'), card:getChildById('chestButton'), card:getChildById('guardButton')
    go:setVisible(c.ours and c.hasHome)
    chest:setVisible(c.ours)
    chest:setEnabled(true)
    chest:setText('Abrir bau')
    guard:setVisible(c.ours)
    local id = c.id
    go.onClick = function() send('GOTO|' .. id) end
    chest.onClick = function()
      selectedCastle = id
      sideMode = 'vault'
      buildGuardians()
    end
    guard.onClick = function()
      selectedCastle = id
      sideMode = 'guard'
      buildGuardians()
    end
  end
  if not selectedCastle then
    for _, c in ipairs(data.castles) do
      if c.ours then selectedCastle = c.id break end
    end
  end
  buildGuardians()
end

local function buildBank()
  W('bankLabel'):setText('Banco do cla: ' .. fmt(data.bank) .. ' gp')
  W('withdrawEdit'):setVisible(myRank() == 3)
  W('withdrawButton'):setVisible(myRank() == 3)
  local list = W('logList')
  list:destroyChildren()
  for _, l in ipairs(data.log) do
    local row = g_ui.createWidget('ClLogRow', list)
    row:getChildById('when'):setText(l.when)
    row:getChildById('text'):setText(l.text)
  end
end

local function buildShop()
  local list = W('shopList')
  list:destroyChildren()
  local hasCastle = false
  for _, c in ipairs(data.castles) do
    if c.ours then hasCastle = true end
  end
  for _, entry in ipairs(data.shop) do
    local row = g_ui.createWidget('ClShopRow', list)
    row:getChildById('item'):setItemId(entry.clientId)
    row:getChildById('name'):setText(entry.name)
    row:getChildById('name'):setColor(entry.castle and '#f2c400' or '#ffffff')
    row:getChildById('sub'):setText((entry.count > 1 and ('Pacote com ' .. entry.count) or 'Unidade') ..
      (entry.castle and '  -  exige castelo' or ''))
    row:getChildById('price'):setText(fmt(entry.price) .. ' gp')
    local button = row:getChildById('buyButton')
    local locked = entry.castle and not hasCastle
    button:setEnabled(not locked)
    button:setText(locked and 'Bloqueado' or 'Comprar')
    local qty = row:getChildById('qty')
    local index = entry.index
    button.onClick = function()
      local n = numberOf(qty)
      if n > 0 then send('BUY|' .. index .. '|' .. n) end
    end
  end
end

local function buildRanking()
  local list = W('rankList')
  list:destroyChildren()
  for _, r in ipairs(data.ranking) do
    local row = g_ui.createWidget('ClRankRow', list)
    row:getChildById('pos'):setText('#' .. r.pos)
    row:getChildById('name'):setText(r.name)
    row:getChildById('points'):setText(fmt(r.points) .. ' pts')
    row:getChildById('castles'):setText(r.castles .. ' castelo(s)')
    row:getChildById('members'):setText(r.members .. ' membros')
    if r.name == data.name then row:setBorderColor('#f2c400') end
  end
end

local function refresh()
  if not window or not data then return end
  local hasClan = data.hasClan
  if not hasClan and (page ~= 'castles' and page ~= 'ranking') then page = 'overview' end
  W('titleLabel'):setText(hasClan and ('CLA ' .. data.name:upper()) or 'CLAS')
  W('subtitleLabel'):setText(hasClan and ((RANKS[data.rank] or '') .. '  -  ' .. data.members .. ' membros  -  ' .. fmt(data.points) .. ' pontos')
    or 'Voce ainda nao faz parte de um cla.')
  W('navOverview'):setText(hasClan and 'Visao geral' or 'Fundar / convites')
  for _, key in ipairs({ 'members', 'allies', 'bank', 'shop' }) do
    W(NAV[key]):setVisible(hasClan)
  end
  for key, id in pairs(NAV) do
    local button = W(id)
    local active = key == page
    button:setColor(active and '#0a1320' or '#dce8f5')
    button:setBackgroundColor(active and '#f2c400' or '#0c1828')
    button:setBorderColor(active and '#ffe27a' or '#1d3557')
  end
  local current = (page == 'overview' and not hasClan) and 'none' or page
  for key, id in pairs(PAGES) do
    W(id):setVisible(key == current)
  end
  if current == 'none' then buildNone()
  elseif current == 'overview' then buildOverview()
  elseif current == 'members' then buildMembers()
  elseif current == 'allies' then buildAllies()
  elseif current == 'castles' then buildCastles()
  elseif current == 'bank' then buildBank()
  elseif current == 'shop' then buildShop()
  elseif current == 'ranking' then buildRanking()
  end
  updateWarLabel()
end

-- ============================================================
-- mensagens do servidor
-- ============================================================
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

local function parseCastle(f)
  local guardians = {}
  local gField = f[12] or ''
  local ours = f[10] == '1'
  if ours then
    for name in gField:gmatch('[^,]+') do guardians[#guardians + 1] = name end
  end
  return {
    id = tonumber(f[2]) or 0, name = f[3] or '?', owner = f[4] or '', ownerId = tonumber(f[5]) or 0,
    since = tonumber(f[6]) or 0, hp = tonumber(f[7]) or 0, max = tonumber(f[8]) or 0,
    inWar = f[9] == '1', ours = ours, chestReady = f[11] == '1', guardians = guardians, hasHome = f[13] == '1',
  }
end

local function onClansOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  local lines = {}
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then lines[#lines + 1] = splitFields(line) end
  end
  if #lines == 0 then return end

  -- codex castelos v2: lugares dos guardioes e bau
  if lines[1][1] == 'CX' then
    extra = { pos = {}, vault = {}, info = {} }
    for i = 2, #lines do
      local f = lines[i]
      local cid = tonumber(f[2]) or 0
      if f[1] == 'GP' then
        extra.pos[cid] = extra.pos[cid] or {}
        extra.pos[cid][tonumber(f[3]) or 0] = (f[4] or ''):gsub(',', ', ')
      elseif f[1] == 'VB' then
        extra.info[cid] = { ready = f[3] == '1', manage = f[4] == '1', max = tonumber(f[5]) or 60 }
      elseif f[1] == 'VI' then
        extra.vault[cid] = extra.vault[cid] or {}
        table.insert(extra.vault[cid], { index = tonumber(f[3]) or 0, clientId = tonumber(f[4]) or 0, name = f[5] or '?', count = tonumber(f[6]) or 1 })
      end
    end
    if data and window:isVisible() and page == 'castles' then buildGuardians() end
    return
  end

  -- atualizacao rapida (vida do Emperium durante a guerra)
  if lines[1][1] == 'UPD' then
    if not data or not window:isVisible() then return end
    data.castles = {}
    for i = 2, #lines do
      local f = lines[i]
      if f[1] == 'WAR' then
        data.war = f[2] == '1'
        warEndsAt = os.time() + (tonumber(f[3]) or 0)
      elseif f[1] == 'CA' then
        data.castles[#data.castles + 1] = parseCastle(f)
      end
    end
    if page == 'castles' then buildCastles() end
    updateWarLabel()
    return
  end

  local fresh = {
    memberList = {}, invites = {}, allies = {}, requests = {}, castles = {}, catalog = {}, shop = {}, ranking = {}, log = {},
    maxGuardians = 6,
  }
  local open = false
  for _, f in ipairs(lines) do
    local kind = f[1]
    if kind == 'CL' then
      fresh.hasClan = f[2] == '1'
      fresh.id = tonumber(f[3]) or 0
      fresh.name = f[4] or ''
      fresh.rank = tonumber(f[5]) or 0
      fresh.leader = f[6] or ''
      fresh.members = tonumber(f[7]) or 0
      fresh.maxMembers = tonumber(f[8]) or 0
      fresh.points = tonumber(f[9]) or 0
      fresh.bank = tonumber(f[10]) or 0
      fresh.motd = f[11] or ''
      fresh.rankPos = tonumber(f[12]) or 0
      fresh.bonus = f[13] or ''
      fresh.createCost = tonumber(f[14]) or 0
      fresh.maxAllies = tonumber(f[15]) or 0
      open = f[16] == '1'
    elseif kind == 'ME' then
      fresh.memberList[#fresh.memberList + 1] = { name = f[2] or '?', rank = tonumber(f[3]) or 1, level = tonumber(f[4]) or 0,
        online = f[5] == '1', donated = tonumber(f[6]) or 0 }
    elseif kind == 'IN' then
      fresh.invites[#fresh.invites + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', members = tonumber(f[4]) or 0 }
    elseif kind == 'AL' then
      fresh.allies[#fresh.allies + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', members = tonumber(f[4]) or 0, points = tonumber(f[5]) or 0 }
    elseif kind == 'AR' then
      fresh.requests[#fresh.requests + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', dir = f[4] or 'in' }
    elseif kind == 'WAR' then
      fresh.war = f[2] == '1'
      warEndsAt = os.time() + (tonumber(f[3]) or 0)
    elseif kind == 'CA' then
      fresh.castles[#fresh.castles + 1] = parseCastle(f)
    elseif kind == 'GC' then
      fresh.catalog[#fresh.catalog + 1] = { index = tonumber(f[2]) or 0, monster = f[3] or '?', price = tonumber(f[4]) or 0, look = tonumber(f[5]) or 0 }
    elseif kind == 'SH' then
      fresh.shop[#fresh.shop + 1] = { index = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, name = f[4] or '?',
        count = tonumber(f[5]) or 1, price = tonumber(f[6]) or 0, castle = f[7] == '1' }
    elseif kind == 'RK' then
      fresh.ranking[#fresh.ranking + 1] = { pos = tonumber(f[2]) or 0, name = f[3] or '?', points = tonumber(f[4]) or 0,
        castles = tonumber(f[5]) or 0, members = tonumber(f[6]) or 0 }
    elseif kind == 'LG' then
      fresh.log[#fresh.log + 1] = { when = f[2] or '', text = f[3] or '' }
    end
  end
  if fresh.hasClan == nil then return end
  if not open and not window:isVisible() then return end
  local player = g_game.getLocalPlayer()
  fresh.me = player and player:getName() or ''
  data = fresh

  if open and not window:isVisible() then
    window:show()
    window:raise()
    window:focus()
    if topButton then topButton:setOn(true) end
  end
  refresh()
  if not timerEvent then tickTimer() end
end

-- ============================================================
-- abrir / fechar
-- ============================================================
function show()
  if not g_game.isOnline() then return end
  send('OPEN')
end

function hide()
  if window and window:isVisible() then
    window:hide()
    send('CLOSE')
  end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
  if topButton then topButton:setOn(false) end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

local function setPage(name)
  page = name
  refresh()
end

local function onGameEnd()
  if window then window:hide() end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
  if topButton then topButton:setOn(false) end
  data = nil
end

function init()
  window = g_ui.displayUI('clans')
  window:hide()

  W('closeButton').onClick = function() hide() end
  for key, id in pairs(NAV) do
    W(id).onClick = function() setPage(key) end
  end
  W('createButton').onClick = function() send('CREATE|' .. textOf(W('createEdit'))) end
  W('motdButton').onClick = function()
    send('MOTD|' .. textOf(W('motdEdit')))
    W('motdEdit'):setText('')
  end
  W('inviteButton').onClick = function()
    local name = textOf(W('inviteEdit'))
    if name ~= '' then
      send('INVITE|' .. name)
      W('inviteEdit'):setText('')
    end
  end
  W('allyButton').onClick = function()
    local name = textOf(W('allyEdit'))
    if name ~= '' then
      send('ALLYREQ|' .. name)
      W('allyEdit'):setText('')
    end
  end
  W('donateButton').onClick = function()
    local n = numberOf(W('donateEdit'))
    if n > 0 then
      send('DONATE|' .. n)
      W('donateEdit'):setText('')
    end
  end
  W('withdrawButton').onClick = function()
    local n = numberOf(W('withdrawEdit'))
    if n > 0 then
      send('WITHDRAW|' .. n)
      W('withdrawEdit'):setText('')
    end
  end
  confirmClick(W('leaveButton'), 'Sair do cla', function() send('LEAVE') end)
  confirmClick(W('disbandButton'), 'Desfazer cla', function() send('DISBAND') end)

  ProtocolGame.registerExtendedOpcode(OPCODE, onClansOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, toggle)

  local ok, button = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton('clansButton',
      'Cla e castelos (' .. HOTKEY .. ')', '/modules/game_clans/images/icon', toggle)
  end)
  if ok then topButton = button end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown(HOTKEY)
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
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
