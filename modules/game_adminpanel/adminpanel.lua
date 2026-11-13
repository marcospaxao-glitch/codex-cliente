-- ============================================================
-- PAINEL ADM (cliente) - opcode 101
-- So aparece para staff (o servidor avisa no login). Toda acao e
-- conferida no servidor. So envia pacotes a partir de cliques.
-- Atalho: Ctrl+Alt+A  |  comando: /painel
-- v2: abas Editar Pokemon e Castelos; Ctrl+Alt+D (depuracao) desligado
-- ============================================================

local OPCODE = 101
local HOTKEY = 'Ctrl+Alt+A'

local window = nil
local topButton = nil
local isStaff, isGod = false, false
-- cargos (servidor: data/lib/core/staff.lua)
local RANK = { TREINADOR = 1, AJUDANTE = 2, SUPORTE = 3, DIRETOR = 4, DONO = 5 }
local myRank, myRole = 0, ''
local staffMembers = {}
local currentTab = 'players'
local players = {}
local found = nil        -- resultado da busca no banco (nil = mostra os online)
local state = { name = '', x = 0, y = 0, z = 7, ghost = false, hidden = false, towns = {}, rates = {} }
local sel = { player = '', item = nil, mon = nil, currency = 'GOLD', itemDest = 'bag', sex = 'R', iv = 'random',
  ballDest = 'team', shiny = false, role = nil }
local armed = {}
local logLines = {}

local TABS = {
  players = { nav = 'navPlayers', panel = 'tabPlayers' },
  items = { nav = 'navItems', panel = 'tabItems' },
  mons = { nav = 'navMons', panel = 'tabMons' },
  edit = { nav = 'navEdit', panel = 'tabEdit' },
  castle = { nav = 'navCastle', panel = 'tabCastle' },
  tele = { nav = 'navTele', panel = 'tabTele' },
  server = { nav = 'navServer', panel = 'tabServer' },
  me = { nav = 'navMe', panel = 'tabMe' },
  staff = { nav = 'navStaff', panel = 'tabStaff' },
}

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function splitFields(line, sep)
  sep = sep or '|'
  local fields = {}
  for field in (line .. sep):gmatch('(.-)' .. (sep == '|' and '|' or sep)) do fields[#fields + 1] = field end
  return fields
end

local function txt(id)
  local w = W(id)
  return w and (w:getText() or '') or ''
end

local function safe(value)
  return (tostring(value or ''):gsub('[|\n\r]', ' '))
end

local function status(text, ok)
  local label = W('statusLabel')
  if label then
    label:setText(text)
    label:setColor(ok and '#5fd35f' or '#e04848')
  end
  table.insert(logLines, 1, os.date('%H:%M') .. '  ' .. text)
  while #logLines > 18 do table.remove(logLines) end
  local list = W('logList')
  if list then
    list:destroyChildren()
    for _, line in ipairs(logLines) do
      local l = g_ui.createWidget('AdmLabel', list)
      l:setText(line)
    end
  end
end

-- botao que pede 2 cliques (acoes perigosas)
local function confirm(key, button, label)
  if armed[key] then
    armed[key] = nil
    button:setText(label)
    return true
  end
  armed[key] = true
  button:setText('Confirmar?')
  scheduleEvent(function()
    if armed[key] and button and not button:isDestroyed() then
      armed[key] = nil
      button:setText(label)
    end
  end, 3000)
  return false
end

local function setOnGroup(ids, chosen)
  for _, id in ipairs(ids) do
    local w = W(id)
    if w then w:setOn(id == chosen) end
  end
end

-- ------------------------------------------------------------
-- abas
-- ------------------------------------------------------------
local function showTab(name)
  if name == 'staff' and myRank < RANK.DIRETOR then name = 'players' end
  currentTab = name
  if name == 'staff' then send('STAFFLIST') end
  if name == 'castle' then send('CASTLES') send('CLANS') end
  for key, t in pairs(TABS) do
    local nav, panel = W(t.nav), W(t.panel)
    if nav then nav:setOn(key == name) end
    if panel then panel:setVisible(key == name) end
  end
end

-- ------------------------------------------------------------
-- jogadores
-- ------------------------------------------------------------
local renderPlayers

local function idsText(p)
  if not p.guid or p.guid == 0 then return '' end
  return 'ID ' .. p.guid .. '   Conta ' .. (p.account or 0)
end

local function selectPlayer(p)
  sel.player = p.name
  W('playerName'):setText(p.name)
  if p.guid and p.guid > 0 then
    status(p.name .. ': Player ID ' .. p.guid .. ' | Account ID ' .. (p.account or 0) ..
      (p.online and ' | online' or ' | offline'), true)
  end
  renderPlayers()
end

renderPlayers = function()
  local list = W('playerList')
  if not list then return end
  list:destroyChildren()
  if found then
    -- resultado da busca no banco (online e offline)
    for _, p in ipairs(found) do
      local row = g_ui.createWidget('AdmPlayerRow', list)
      row:getChildById('name'):setText(p.name)
      row:getChildById('name'):setColor(p.online and '#5fd35f' or '#dce8f5')
      row:getChildById('ids'):setText(idsText(p))
      local info = 'Lv ' .. p.level .. (p.online and '   online' or ('   visto ' .. p.seen))
      if p.group > 1 then info = info .. '   [' .. p.role .. ']' end
      if p.banned then info = info .. '   [banido]' end
      row:getChildById('info'):setText(info)
      row:setOn(p.name == sel.player)
      row.onClick = function() selectPlayer(p) end
    end
    W('playerCount'):setText(#found .. ' encontrado(s)')
    return
  end
  local filter = txt('playerFilter'):lower()
  local shown = 0
  for _, p in ipairs(players) do
    if filter == '' or p.name:lower():find(filter, 1, true) or tostring(p.guid) == filter or tostring(p.account) == filter then
      shown = shown + 1
      local row = g_ui.createWidget('AdmPlayerRow', list)
      row:getChildById('name'):setText(p.name)
      row:getChildById('ids'):setText(idsText(p))
      row:getChildById('info'):setText('Lv ' .. p.level .. '   ' .. p.x .. ', ' .. p.y .. ', ' .. p.z ..
        (p.rank >= 1 and ('   [' .. p.role .. ']') or '') .. (p.ghost and '  [ghost]' or ''))
      row:setOn(p.name == sel.player)
      row.onClick = function() selectPlayer(p) end
    end
  end
  W('playerCount'):setText(shown .. ' / ' .. #players .. ' online')
end

-- busca no banco: nome (parte) ou ID do personagem / da conta
local function searchPlayers()
  local q = safe(txt('playerFilter')):gsub('^%s+', ''):gsub('%s+$', '')
  if q == '' then
    found = nil
    renderPlayers()
    return
  end
  send('PFIND|' .. q)
end

local function playerAction(action, extra)
  local name = safe(txt('playerName'))
  if name == '' then return status('Escolha um jogador.', false) end
  send('PACT|' .. action .. '|' .. name .. (extra or ''))
end

-- ------------------------------------------------------------
-- itens
-- ------------------------------------------------------------
local function selectItem(item)
  sel.item = item
  W('itemPreview'):setItemId(item.clientId)
  W('itemName'):setText(item.name)
  W('itemIdLabel'):setText('ID ' .. item.id .. (item.stackable and '  (empilha)' or ''))
  for _, row in ipairs(W('itemGrid'):getChildren()) do row:setOn(row.adminId == item.id) end
end

local function renderItems(buffer)
  local grid = W('itemGrid')
  grid:destroyChildren()
  local first = nil
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'I' then
      local item = { id = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, name = f[4] or '?', stackable = f[5] == '1' }
      local row = g_ui.createWidget('AdmItemRow', grid)
      row:getChildById('item'):setItemId(item.clientId)
      row:getChildById('name'):setText(item.name)
      row:getChildById('id'):setText('ID ' .. item.id)
      row.adminId = item.id
      row.onClick = function() selectItem(item) end
      first = first or item
    end
  end
  if first then selectItem(first) else status('Nenhum item encontrado.', false) end
end

-- ------------------------------------------------------------
-- monstros / pokemon
-- ------------------------------------------------------------
local function monName()
  if not sel.mon then return nil end
  local name = sel.mon.name
  if sel.shiny and name:sub(1, 6) ~= 'Shiny ' then name = 'Shiny ' .. name end
  return name
end

local function selectMon(mon)
  sel.mon = mon
  local outfit = { type = mon.look, head = mon.head, body = mon.body, legs = mon.legs, feet = mon.feet }
  pcall(function() W('monPreview'):setOutfit(outfit) end)
  W('monName'):setText(monName())
  for _, row in ipairs(W('monList'):getChildren()) do row:setOn(row.adminName == mon.name) end
end

local function renderMons(buffer)
  local list = W('monList')
  list:destroyChildren()
  local first = nil
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'M' then
      local mon = { name = f[2] or '?', look = tonumber(f[3]) or 0, head = tonumber(f[4]) or 0, body = tonumber(f[5]) or 0,
        legs = tonumber(f[6]) or 0, feet = tonumber(f[7]) or 0 }
      local row = g_ui.createWidget('AdmMonRow', list)
      row.adminName = mon.name
      row:getChildById('name'):setText(mon.name)
      pcall(function()
        row:getChildById('creature'):setOutfit({ type = mon.look, head = mon.head, body = mon.body, legs = mon.legs, feet = mon.feet })
      end)
      row.onClick = function() selectMon(mon) end
      first = first or mon
    end
  end
  if first then selectMon(first) else status('Nada encontrado.', false) end
end

-- ------------------------------------------------------------
-- atributos (IV / EV / bonus) usados em CRIAR SELVAGEM e DAR POKEMON
-- ------------------------------------------------------------
local STAT_LABELS = { 'Vida', 'Ataque', 'Defesa', 'Atq. Especial', 'Def. Especial', 'Velocidade' }

local function statRow(i)
  local rows = W('statRows')
  return rows and rows:getChildren()[i] or nil
end

local function buildStatRows()
  local rows = W('statRows')
  if not rows or #rows:getChildren() > 0 then return end
  for i = 1, 6 do
    local row = g_ui.createWidget('AdmStatRow', rows)
    row:getChildById('statName'):setText(STAT_LABELS[i])
    row:getChildById('iv'):setTooltip('Vazio = aleatorio. Pode passar de 31.')
    row:getChildById('ev'):setTooltip('Vazio = 0')
    row:getChildById('bonus'):setTooltip('Soma direto no status final. Vazio = 0')
  end
end

-- "iv1,..,iv6;ev1,..,ev6;b1,..,b6" (vazio = padrao). nil + mensagem se tiver erro
local function attrString()
  local parts = { {}, {}, {} }
  local keys = { 'iv', 'ev', 'bonus' }
  for i = 1, 6 do
    local row = statRow(i)
    for k, key in ipairs(keys) do
      local text = row and (row:getChildById(key):getText() or ''):gsub('%s', '') or ''
      if text ~= '' and not text:match('^%-?%d+$') then
        return nil, STAT_LABELS[i] .. ' (' .. key:upper() .. '): use so numeros inteiros.'
      end
      parts[k][i] = text
    end
  end
  return table.concat(parts[1], ',') .. ';' .. table.concat(parts[2], ',') .. ';' .. table.concat(parts[3], ',')
end

local function setAttrColumn(key, value)
  for i = 1, 6 do
    local row = statRow(i)
    if row then row:getChildById(key):setText(value) end
  end
end

-- ------------------------------------------------------------
-- teleporte
-- ------------------------------------------------------------
local function loadFavs()
  local favs = {}
  pcall(function()
    local raw = g_settings.getString('adminFavs') or ''
    for entry in raw:gmatch('[^;]+') do
      local name, x, y, z = entry:match('^(.-),(%d+),(%d+),(%d+)$')
      if name then favs[#favs + 1] = { name = name, x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
    end
  end)
  return favs
end

local function saveFavs(favs)
  local out = {}
  for _, f in ipairs(favs) do out[#out + 1] = f.name:gsub('[,;]', ' ') .. ',' .. f.x .. ',' .. f.y .. ',' .. f.z end
  pcall(function() g_settings.set('adminFavs', table.concat(out, ';')) end)
end

local function renderFavs()
  local list = W('favList')
  if not list then return end
  list:destroyChildren()
  local favs = loadFavs()
  for i, f in ipairs(favs) do
    local row = g_ui.createWidget('AdmFavRow', list)
    row:getChildById('name'):setText(f.name .. '   (' .. f.x .. ', ' .. f.y .. ', ' .. f.z .. ')')
    row:getChildById('goButton').onClick = function() send('GOTO|' .. f.x .. '|' .. f.y .. '|' .. f.z) end
    row:getChildById('removeButton').onClick = function()
      table.remove(favs, i)
      saveFavs(favs)
      renderFavs()
    end
  end
end

local function renderState()
  W('whoLabel'):setText(state.name .. '  (' .. (myRole ~= '' and myRole or (isGod and 'GOD' or 'GM')) .. ')')
  W('myPos'):setText('voce: ' .. state.x .. ', ' .. state.y .. ', ' .. state.z)
  W('meGhost'):setOn(state.ghost)
  W('meGhost'):setText(state.ghost and 'Invisivel: LIGADO' or 'Invisivel (ghost)')
  W('meHide'):setOn(state.hidden)
  W('meHide'):setText(state.hidden and 'Vida escondida: LIGADO' or 'Esconder vida')
  local towns = W('townList')
  towns:destroyChildren()
  for _, t in ipairs(state.towns) do
    local b = g_ui.createWidget('AdmButton', towns)
    b:setText(t.name)
    b:setTooltip(t.x .. ', ' .. t.y .. ', ' .. t.z)
    b.onClick = function() send('TOWN|' .. t.id) end
  end
  local rates = W('rateList')
  rates:destroyChildren()
  for _, r in ipairs(state.rates) do
    local row = g_ui.createWidget('AdmRateRow', rates)
    row:getChildById('name'):setText(r.key)
    row:getChildById('value'):setText(r.value)
    row:getChildById('applyButton').onClick = function()
      send('RATE|' .. r.key .. '|' .. safe(row:getChildById('value'):getText()))
    end
    row:getChildById('applyButton'):setEnabled(myRank >= RANK.DONO)
  end
  -- cada botao libera pelo cargo (o servidor confere de novo)
  local need = {
    pBan = RANK.SUPORTE, pUnban = RANK.SUPORTE, pKick = RANK.SUPORTE,
    itemCreate = RANK.DIRETOR, spawnButton = RANK.DIRETOR, ballButton = RANK.DIRETOR,
    pCoins = RANK.DIRETOR, curGOLD = RANK.DIRETOR, curTOKENS = RANK.DIRETOR,
    curPOKECOINS = RANK.DONO, curDONATE = RANK.DONO, pPremium = RANK.DONO,
    srvSave = RANK.DIRETOR, srvClean = RANK.DIRETOR,
    editSave = RANK.DIRETOR, editHeal = RANK.DIRETOR, editMovesAll = RANK.DIRETOR, editMovesLevel = RANK.DIRETOR,
    editMovesNone = RANK.DIRETOR, editUnexcl = RANK.DIRETOR, warAll = RANK.DIRETOR, warOne = RANK.DIRETOR, warStop = RANK.DIRETOR,
    castleGive = RANK.DIRETOR, castleClear = RANK.DIRETOR, castleCreate = RANK.DIRETOR,
  }
  for id, rank in pairs(need) do
    local w = W(id)
    if w then
      w:setEnabled(myRank >= rank)
      if myRank < rank then w:setTooltip('Seu cargo nao permite') else w:setTooltip('') end
    end
  end
  if (sel.currency == 'POKECOINS' or sel.currency == 'DONATE') and myRank < RANK.DONO then
    sel.currency = 'GOLD'
    setOnGroup({ 'curGOLD', 'curPOKECOINS', 'curDONATE', 'curTOKENS' }, 'curGOLD')
  end
  local nav = W('navStaff')
  if nav then nav:setVisible(myRank >= RANK.DIRETOR) end
  if W('navEdit') then W('navEdit'):setVisible(myRank >= RANK.DIRETOR) end
  if W('navCastle') then W('navCastle'):setVisible(myRank >= RANK.DIRETOR) end
  if (currentTab == 'edit' or currentTab == 'castle') and myRank < RANK.DIRETOR then showTab('players') end
  if currentTab == 'staff' and myRank < RANK.DIRETOR then showTab('players') end
end

-- ------------------------------------------------------------
-- equipe (Diretor / Dono)
-- ------------------------------------------------------------
local ROLE_IDS = { 'role1', 'role2', 'role3', 'role4', 'role5' }

local function selectRole(groupId)
  sel.role = groupId
  for i, id in ipairs(ROLE_IDS) do
    local w = W(id)
    if w then w:setOn(i == groupId) end
  end
end

local function renderStaff()
  local list = W('staffList')
  if not list then return end
  list:destroyChildren()
  local online = 0
  for _, m in ipairs(staffMembers) do
    local row = g_ui.createWidget('AdmStaffRow', list)
    row:getChildById('name'):setText(m.name)
    row:getChildById('role'):setText(m.role)
    row:getChildById('dot'):setBackgroundColor(m.online and '#5fd35f' or '#4a5f7a')
    row:getChildById('info'):setText(m.online and 'online' or ('Lv ' .. m.level))
    row:setOn(m.name == txt('staffName'))
    if m.online then online = online + 1 end
    row.onClick = function()
      W('staffName'):setText(m.name)
      selectRole(m.group <= 5 and m.group or nil)
      renderStaff()
    end
  end
  W('staffCount'):setText(#staffMembers .. ' na equipe, ' .. online .. ' online')
  -- so da cargo abaixo do seu
  for i, id in ipairs(ROLE_IDS) do
    local w = W(id)
    if w then w:setEnabled(i - 1 < myRank) end
  end
end

-- ------------------------------------------------------------
-- EDITAR POKEMON (tudo: especie, level, nature, IV, EV, vitaminas, bonus, helds...)
-- ------------------------------------------------------------
local edit = { target = '', slot = 0, gender = '', device = false, name = '' }

local function editRow(i)
  local rows = W('editRows')
  return rows and rows:getChildren()[i] or nil
end

local function buildEditRows()
  local rows = W('editRows')
  if not rows or #rows:getChildren() > 0 then return end
  for i = 1, 6 do
    local row = g_ui.createWidget('AdmEditStatRow', rows)
    row:getChildById('statName'):setText(STAT_LABELS[i])
    row:getChildById('iv'):setTooltip('IV (acima de 31 so pelo painel)')
    row:getChildById('ev'):setTooltip('EV')
    row:getChildById('vit'):setTooltip('Vitaminas usadas nesse status (limite normal: 10 no total)')
    row:getChildById('bonus'):setTooltip('Soma direto no status final')
  end
end

local function setEditColumn(key, value)
  for i = 1, 6 do local row = editRow(i) if row then row:getChildById(key):setText(value) end end
end

local function editTotals()
  local ev, vit = 0, 0
  for i = 1, 6 do
    local row = editRow(i)
    if row then
      ev = ev + (tonumber(row:getChildById('ev'):getText()) or 0)
      vit = vit + (tonumber(row:getChildById('vit'):getText()) or 0)
    end
  end
  W('editTotals'):setText('EV total: ' .. ev .. '     Vitaminas: ' .. vit .. ' / 10     ' .. (edit.moves or ''))
end

local function setGender(g)
  edit.gender = g
  W('editSexM'):setOn(g == 'M')
  W('editSexF'):setOn(g == 'F')
end

local function setDevice(on)
  edit.device = on
  W('editDevice'):setOn(on)
  W('editDevice'):setText(on and 'Device: LIGADO' or 'Attachment Device')
end

local function renderEditTeam(buffer)
  local list = W('editTeam')
  list:destroyChildren()
  local who = buffer:match('^PKTEAM|([^\n]*)') or ''
  edit.target = who
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'K' then
      local slot = tonumber(f[2]) or 0
      local row = g_ui.createWidget('AdmMonRow', list)
      row.slot = slot
      row:getChildById('name'):setText(slot .. ')  ' .. (f[3] or '?') .. '   Lv ' .. (f[4] or '?'))
      pcall(function()
        row:getChildById('creature'):setOutfit({ type = tonumber(f[5]) or 0, head = tonumber(f[6]) or 0, body = tonumber(f[7]) or 0,
          legs = tonumber(f[8]) or 0, feet = tonumber(f[9]) or 0 })
      end)
      row:setOn(slot == edit.slot)
      row.onClick = function()
        edit.slot = slot
        for _, r in ipairs(list:getChildren()) do r:setOn(r.slot == slot) end
        send('PKFULL|' .. safe(edit.target) .. '|' .. slot)
      end
    end
  end
  if #list:getChildren() == 0 then status(who .. ' nao tem pokemon na equipe.', false) end
end

local function fillEdit(buffer)
  local f = splitFields(buffer)
  -- PKFULL|alvo|slot|nome|lv|boost|nat|sexo|tera|amizade|excl|vitTotal|held|heldY|held3|device|movesOpen|movesTotal|hp|maxhp|iv6|ev6|vit6|bonus6|look5
  edit.target, edit.slot, edit.name = f[2] or '', tonumber(f[3]) or 0, f[4] or ''
  local look = {}
  for i = 45, 49 do look[#look + 1] = tonumber(f[i]) or 0 end
  pcall(function() W('editPreview'):setOutfit({ type = look[1], head = look[2], body = look[3], legs = look[4], feet = look[5] }) end)
  W('editName'):setText(edit.name .. '   (slot ' .. edit.slot .. ' de ' .. edit.target .. ')' .. (f[11] == '1' and '   [Exclusivo]' or ''))
  W('editInfo'):setText('Vida ' .. (f[19] or 0) .. ' / ' .. (f[20] or 0))
  edit.moves = 'Golpes liberados: ' .. (f[17] or 0) .. ' / ' .. (f[18] or 0)
  W('editSpecies'):setText(edit.name)
  W('editShiny'):setOn(edit.name:sub(1, 6) == 'Shiny ')
  W('editLevel'):setText(f[5] or '1')
  W('editBoost'):setText(f[6] or '0')
  W('editNature'):setText(f[7] or '')
  setGender(f[8] or '')
  W('editTera'):setText(f[9] or '0')
  W('editFriend'):setText(f[10] or '0')
  W('editHeld'):setText(f[13] or '')
  W('editHeldY'):setText(f[14] or '')
  W('editHeld3'):setText(f[15] or '')
  setDevice(f[16] == '1')
  for i = 1, 6 do
    local row = editRow(i)
    if row then
      row:getChildById('iv'):setText(f[20 + i] or '0')
      row:getChildById('ev'):setText(f[26 + i] or '0')
      row:getChildById('vit'):setText(f[32 + i] or '0')
      row:getChildById('bonus'):setText(f[38 + i] or '0')
    end
  end
  editTotals()
end

local function editSave()
  if edit.slot <= 0 then return status('Escolha um pokemon da equipe.', false) end
  local parts = { 'PKEDIT', safe(edit.target), edit.slot, safe(txt('editSpecies')), safe(txt('editLevel')), safe(txt('editBoost')),
    safe(txt('editNature')), edit.gender, safe(txt('editTera')), safe(txt('editFriend')), safe(txt('editHeld')), safe(txt('editHeldY')),
    safe(txt('editHeld3')), edit.device and '1' or '0' }
  for _, key in ipairs({ 'iv', 'ev', 'vit', 'bonus' }) do
    for i = 1, 6 do
      local v = (editRow(i):getChildById(key):getText() or ''):gsub('%s', '')
      if v == '' then v = '0' end
      if not v:match('^%-?%d+$') then return status(STAT_LABELS[i] .. ' (' .. key .. '): use so numeros.', false) end
      parts[#parts + 1] = v
    end
  end
  send(table.concat(parts, '|'))
end

local function editDo(action)
  if edit.slot <= 0 then return status('Escolha um pokemon da equipe.', false) end
  send('PKDO|' .. safe(edit.target) .. '|' .. edit.slot .. '|' .. action)
end

-- ------------------------------------------------------------
-- CASTELOS
-- ------------------------------------------------------------
local castles, castleSel, warActive = {}, 0, false
local clanChoices = {}   -- codex: { {name, leader} } para escolher o dono do castelo

local function renderCastles()
  local list = W('castleList')
  if not list then return end
  list:destroyChildren()
  for _, c in ipairs(castles) do
    local row = g_ui.createWidget('AdmCastleRow', list)
    row:getChildById('name'):setText(c.id .. ')  ' .. c.name)
    row:getChildById('info'):setText((c.owner ~= '' and ('Dono: ' .. c.owner) or 'Sem dono') .. (c.war and '   [EM GUERRA]' or ''))
    row:setOn(c.id == castleSel)
    row.onClick = function() castleSel = c.id renderCastles() end
  end
  local c = nil
  for _, x in ipairs(castles) do if x.id == castleSel then c = x end end
  if c then
    W('castleName'):setText(c.id .. ') ' .. c.name .. '   -   ' .. (c.owner ~= '' and ('dono: ' .. c.owner) or 'sem dono'))
    W('castleInfo'):setText('Area: ' .. c.a1 .. '  ate  ' .. c.a2 .. '\nEmperium: ' .. c.emp .. '   (vida ' .. c.hp .. ')\nEntrada: ' .. c.home ..
      '     Saida: ' .. c.exit .. '\nSala: ' .. c.room .. '     Guardioes: ' .. c.guards)
    W('castleHp'):setText(tostring(c.hp))
  else
    W('castleName'):setText(#castles == 0 and 'Nenhum castelo. Digite um nome e clique em Criar novo.' or 'Escolha um castelo na lista.')
    W('castleInfo'):setText('')
  end
end

local function castleAct(action, value, extra)
  if castleSel <= 0 and action ~= 'new' then return status('Escolha um castelo na lista.', false) end
  send('CASTLE|' .. action .. '|' .. castleSel .. '|' .. safe(value or '') .. (extra or ''))
end

-- desliga o Ctrl+Alt+D (informacoes de depuracao das criaturas) para todos
local function killDebugKey()
  local widgets = { rootWidget }
  pcall(function() widgets[#widgets + 1] = modules.game_interface.getRootPanel() end)
  pcall(function() widgets[#widgets + 1] = modules.game_interface.getMapPanel() end)
  for _, w in ipairs(widgets) do
    if w then
      pcall(function() g_keyboard.unbindKeyDown('Ctrl+Alt+D', nil, w) end)
      pcall(function() g_keyboard.unbindKeyPress('Ctrl+Alt+D', nil, w) end)
      pcall(function() g_keyboard.unbindKeyUp('Ctrl+Alt+D', nil, w) end)
    end
  end
end

function onGameStartDebug() scheduleEvent(killDebugKey, 1500) end

-- ------------------------------------------------------------
-- pacotes do servidor
-- ------------------------------------------------------------
local function onAdminOpcode(protocol, opcode, buffer)
  buffer = buffer or ''
  local head = buffer:match('^([^|\n]*)')
  if head == 'NOSTAFF' then
    isStaff, isGod, myRank = false, false, 0
    if window then window:hide() end
    if topButton then pcall(function() topButton:destroy() end) topButton = nil end
    return
  elseif head == 'STAFF' then
    isStaff = true
    local f = splitFields(buffer)
    isGod = f[2] == '1'
    myRank = tonumber(f[3]) or (isGod and RANK.DIRETOR or RANK.SUPORTE)
    if not topButton then
      local topmenu = modules.client_topmenu
      local ok, button = pcall(function()
        if topmenu.addCenterGameButton then
          return topmenu.addCenterGameButton('adminButton', 'Painel ADM (' .. HOTKEY .. ')', '/modules/game_adminpanel/topbutton.png', toggle)
        end
        return topmenu.addRightGameToggleButton('adminButton', 'Painel ADM (' .. HOTKEY .. ')', '/modules/game_adminpanel/topbutton', toggle)
      end)
      if ok then topButton = button end
    end
  elseif head == 'OPEN' then
    isStaff = true
    window:show()
    window:raise()
    window:focus()
    renderFavs()
  elseif head == 'STATE' then
    local f = splitFields(buffer)
    state.name = f[2] or ''
    isGod = f[4] == '1'
    state.x, state.y, state.z = tonumber(f[5]) or 0, tonumber(f[6]) or 0, tonumber(f[7]) or 7
    state.ghost, state.hidden = f[8] == '1', f[9] == '1'
    state.towns, state.rates = {}, {}
    for entry in (f[10] or ''):gmatch('[^,]+') do
      local t = splitFields(entry, ';')
      state.towns[#state.towns + 1] = { id = tonumber(t[1]) or 0, name = t[2] or '?', x = t[3] or 0, y = t[4] or 0, z = t[5] or 0 }
    end
    for entry in (f[11] or ''):gmatch('[^,]+') do
      local key, value = entry:match('^(.-);(.*)$')
      if key then state.rates[#state.rates + 1] = { key = key, value = value } end
    end
    myRank = tonumber(f[12]) or myRank
    myRole = f[13] or myRole
    renderState()
  elseif head == 'PLAYERS' then
    players = {}
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'P' then
        players[#players + 1] = { name = f[2] or '?', level = tonumber(f[3]) or 0, group = tonumber(f[4]) or 0,
          x = tonumber(f[5]) or 0, y = tonumber(f[6]) or 0, z = tonumber(f[7]) or 0, rank = tonumber(f[8]) or 0,
          ghost = f[9] == '1', role = f[10] or '', guid = tonumber(f[11]) or 0, account = tonumber(f[12]) or 0, online = true }
      end
    end
    renderPlayers()
  elseif head == 'PFOUND' then
    found = {}
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'F' then
        local last = tonumber(f[8]) or 0
        found[#found + 1] = { guid = tonumber(f[2]) or 0, name = f[3] or '?', account = tonumber(f[4]) or 0,
          level = tonumber(f[5]) or 0, group = tonumber(f[6]) or 1, online = f[7] == '1',
          seen = last > 0 and os.date('%d/%m/%y', last) or 'nunca', banned = f[9] == '1', role = f[10] or '' }
      end
    end
    if #found == 0 then status('Nenhum personagem encontrado.', false) end
    renderPlayers()
  elseif head == 'ITEMLIST' then
    renderItems(buffer)
  elseif head == 'MONLIST' then
    renderMons(buffer)
  elseif head == 'STAFFLIST' then
    staffMembers = {}
    myRank = tonumber(buffer:match('^STAFFLIST|(%d+)')) or myRank
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'S' then
        staffMembers[#staffMembers + 1] = { name = f[2] or '?', group = tonumber(f[3]) or 1, role = f[4] or '',
          level = tonumber(f[5]) or 0, online = f[6] == '1' }
      end
    end
    renderStaff()

  elseif head == 'PKTEAM' then
    renderEditTeam(buffer)
  elseif head == 'PKFULL' then
    fillEdit(buffer)
  elseif head == 'CASTLES' then
    castles = {}
    local h = splitFields(buffer:match('^([^\n]*)'))
    warActive = h[2] == '1'
    W('warState'):setText(warActive and ('ATIVA - termina em ' .. (h[3] or '?') .. ' min') or 'sem guerra agora')
    W('warState'):setColor(warActive and '#5fd35f' or '#8fa7c4')
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = splitFields(line)
      if f[1] == 'C' then
        castles[#castles + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', owner = f[4] or '', hp = tonumber(f[5]) or 0,
          a1 = f[6] or '-', a2 = f[7] or '-', emp = f[8] or '-', home = f[9] or '-', exit = f[10] or '-', room = f[11] or '-',
          guards = tonumber(f[12]) or 0, war = f[13] == '1' }
      end
    end
    if castleSel == 0 and castles[1] then castleSel = castles[1].id end
    renderCastles()
  elseif head == 'CLANS' then
    local names = buffer:sub(7)
    clanChoices = {}
    local shown = {}
    for part in (names .. ';'):gmatch('([^;]*);') do
      if part ~= '' then
        local name, leader = part:match('^(.-)~(.*)$')
        name = name or part
        clanChoices[#clanChoices + 1] = { name = name, leader = leader or '' }
        shown[#shown + 1] = name .. ((leader and leader ~= '') and (' (lider ' .. leader .. ')') or '')
      end
    end
    W('clanNames'):setText(#shown > 0 and ('Clas: ' .. table.concat(shown, ', ') .. '\nClique no campo do cla para escolher da lista.') or 'Nenhum cla criado ainda.')
  elseif head == 'OK' then
    status(buffer:sub(4), true)
  elseif head == 'ERR' then
    status(buffer:sub(5), false)
  end
end

-- ------------------------------------------------------------
-- abrir / fechar
-- ------------------------------------------------------------
function toggle()
  if not window then return end
  if window:isVisible() then
    window:hide()
  else
    send('OPEN') -- o servidor confere se e staff e responde OPEN
  end
end

local function bindStatButtons()
  buildStatRows()
  W('attrPerfect').onClick = function() setAttrColumn('iv', '31') end
  W('ballTarget'):setTooltip('Vazio = voce')
  W('ballNature'):setTooltip('Vazio = aleatoria (ex: Adamant, Modest, Jolly...)')
  W('attrClear').onClick = function()
    setAttrColumn('iv', '') setAttrColumn('ev', '') setAttrColumn('bonus', '')
  end
end

local function bindButtons()
  W('closeButton').onClick = function() window:hide() end
  for key, t in pairs(TABS) do
    W(t.nav).onClick = function() showTab(key) end
  end

  -- jogadores
  W('playerRefresh').onClick = function()
    found = nil
    W('playerFilter'):setText('')
    send('REFRESH')
  end
  W('playerSearch').onClick = function() searchPlayers() end
  W('playerFilter').onTextChange = function()
    if found then found = nil end
    renderPlayers()
  end
  W('playerFilter').onKeyPress = function(_, keyCode)
    if keyCode == KeyEnter or keyCode == KeyReturn then searchPlayers() return true end
  end
  W('pGoto').onClick = function() playerAction('goto') end
  W('pBring').onClick = function() playerAction('bring') end
  W('pHeal').onClick = function() playerAction('heal') end
  W('pTemple').onClick = function() playerAction('temple') end
  W('pKick').onClick = function(self) if confirm('kick', self, 'Expulsar') then playerAction('kick') end end
  W('pBan').onClick = function(self)
    if confirm('ban', self, 'Banir') then
      playerAction('ban', '|' .. safe(txt('banDays')) .. '|' .. safe(txt('banReason')))
    end
  end
  W('pUnban').onClick = function() playerAction('unban') end
  local currencies = { 'curGOLD', 'curPOKECOINS', 'curDONATE', 'curTOKENS' }
  for _, id in ipairs(currencies) do
    W(id).onClick = function()
      sel.currency = id:sub(4)
      setOnGroup(currencies, id)
    end
  end
  setOnGroup(currencies, 'curGOLD')
  W('pCoins').onClick = function() playerAction('coins', '|' .. sel.currency .. '|' .. safe(txt('coinAmount'))) end
  W('pPremium').onClick = function() playerAction('premium', '|' .. safe(txt('premDays'))) end

  -- itens
  local function searchItems()
    local q = safe(txt('itemSearch'))
    if q == '' then return status('Digite o nome ou ID.', false) end
    send('ITEMS|' .. q)
  end
  W('itemSearchButton').onClick = searchItems
  W('itemSearch').onKeyPress = function(_, keyCode) if keyCode == KeyEnter or keyCode == KeyReturn then searchItems() return true end end
  local dests = { 'itemToBag', 'itemToDepot' }
  W('itemToBag').onClick = function() sel.itemDest = 'bag' setOnGroup(dests, 'itemToBag') end
  W('itemToDepot').onClick = function() sel.itemDest = 'depot' setOnGroup(dests, 'itemToDepot') end
  setOnGroup(dests, 'itemToBag')
  W('itemCreate').onClick = function()
    if not sel.item then return status('Escolha um item.', false) end
    send('ITEM|' .. sel.item.id .. '|' .. safe(txt('itemCount')) .. '|' .. safe(txt('itemTarget')) .. '|' .. sel.itemDest)
  end

  -- monstros / pokemon
  local function searchMons()
    send('MONS|' .. safe(txt('monSearch')))
  end
  W('monSearchButton').onClick = searchMons
  W('monSearch').onKeyPress = function(_, keyCode) if keyCode == KeyEnter or keyCode == KeyReturn then searchMons() return true end end
  W('monShiny').onClick = function(self)
    sel.shiny = not sel.shiny
    self:setOn(sel.shiny)
    if sel.mon then W('monName'):setText(monName()) end
  end
  W('spawnButton').onClick = function()
    local name = monName()
    if not name then return status('Escolha um monstro.', false) end
    local attrs, err = attrString()
    if not attrs then return status(err, false) end
    send('SPAWN|' .. name .. '|' .. safe(txt('spawnCount')) .. '|' .. safe(txt('monLevel')) .. '|' .. safe(txt('monBoost')) .. '|' .. attrs)
  end
  local sexes = { 'sexR', 'sexM', 'sexF' }
  for _, id in ipairs(sexes) do
    W(id).onClick = function() sel.sex = id:sub(4) setOnGroup(sexes, id) end
  end
  setOnGroup(sexes, 'sexR')
  local ballDests = { 'ballToTeam', 'ballToDepot' }
  W('ballToTeam').onClick = function() sel.ballDest = 'team' setOnGroup(ballDests, 'ballToTeam') end
  W('ballToDepot').onClick = function() sel.ballDest = 'depot' setOnGroup(ballDests, 'ballToDepot') end
  setOnGroup(ballDests, 'ballToTeam')
  W('ballButton').onClick = function()
    local name = monName()
    if not name then return status('Escolha um pokemon.', false) end
    local attrs, err = attrString()
    if not attrs then return status(err, false) end
    local nature = safe(txt('ballNature'))
    send(table.concat({ 'BALL', name, safe(txt('ballTarget')), safe(txt('monLevel')), safe(txt('monBoost')), sel.sex, 'random',
      nature ~= '' and nature or 'R', sel.ballDest, attrs }, '|'))
  end

  -- editar pokemon
  buildEditRows()
  W('editLoad').onClick = function()
    edit.slot = 0
    send('PKTEAM|' .. safe(txt('editTarget')))
  end
  W('editTarget').onKeyPress = function(_, keyCode) if keyCode == KeyEnter or keyCode == KeyReturn then send('PKTEAM|' .. safe(txt('editTarget'))) return true end end
  W('editSave').onClick = editSave
  W('editSexM').onClick = function() setGender('M') end
  W('editSexF').onClick = function() setGender('F') end
  W('editDevice').onClick = function() setDevice(not edit.device) end
  W('editShiny').onClick = function(self)
    local name = txt('editSpecies')
    if name:sub(1, 6) == 'Shiny ' then name = name:sub(7) else name = 'Shiny ' .. name end
    W('editSpecies'):setText(name)
    self:setOn(name:sub(1, 6) == 'Shiny ')
    status('Clique em Salvar para aplicar (o Shiny precisa existir como pokemon).', true)
  end
  W('editIv31').onClick = function() setEditColumn('iv', '31') end
  W('editEvZero').onClick = function() setEditColumn('ev', '0') editTotals() end
  W('editVitZero').onClick = function() setEditColumn('vit', '0') editTotals() end
  W('editBonusZero').onClick = function() setEditColumn('bonus', '0') end
  W('editHeal').onClick = function() editDo('heal') end
  W('editUnexcl').onClick = function() editDo('unexclusive') end
  W('editMovesAll').onClick = function() editDo('movesall') end
  W('editMovesLevel').onClick = function() editDo('moveslevel') end
  W('editMovesNone').onClick = function(self) if confirm('movesnone', self, 'Travar golpes') then editDo('movesnone') end end

  -- castelos
  W('castleRefresh').onClick = function() send('CASTLES') send('CLANS') end
  for _, k in ipairs({ 'pos1', 'pos2', 'emperium', 'home', 'exit', 'room1', 'room2', 'noroom', 'guard', 'noguards', 'show' }) do
    W('mk_' .. k).onClick = function() castleAct(k) end
  end
  W('goHome').onClick = function() castleAct('goto', 'home') end
  W('goEmp').onClick = function() castleAct('goto', 'emperium') end
  W('goExit').onClick = function() castleAct('goto', 'exit') end
  W('castleHpApply').onClick = function() castleAct('hp', txt('castleHp')) end
  W('castleRename').onClick = function() castleAct('name', txt('castleNewName')) end
  W('castleCreate').onClick = function() send('CASTLE|new|0|' .. safe(txt('castleNewName'))) end
  W('castleGive').onClick = function(self) if confirm('give', self, 'Dar castelo') then castleAct('give', txt('castleClan')) end end
  -- codex: clicar no campo do cla abre a lista; escolher ja entrega o castelo ao cla (o lider toma posse)
  W('castleClan').onMouseRelease = function(self, mousePos, mouseButton)
    if mouseButton ~= MouseLeftButton then return false end
    if castleSel <= 0 then status('Escolha um castelo na lista.', false) return true end
    if #clanChoices == 0 then
      send('CLANS')
      status('Nenhum cla carregado. Clique em Atualizar ou crie um cla.', false)
      return true
    end
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    for _, c in ipairs(clanChoices) do
      local name = c.name
      menu:addOption(name .. (c.leader ~= '' and ('  -  lider ' .. c.leader) or ''), function()
        self:setText(name)
        castleAct('give', name)
      end)
    end
    menu:display(mousePos)
    return true
  end
  W('castleClear').onClick = function(self) if confirm('clear', self, 'Tirar dono') then castleAct('clear') end end
  W('warAll').onClick = function(self) if confirm('warall', self, 'Iniciar (todos)') then send('CASTLE|warstart|0||' .. safe(txt('warMinutes'))) end end
  W('warOne').onClick = function(self)
    if castleSel <= 0 then return status('Escolha um castelo.', false) end
    if confirm('warone', self, 'So o escolhido') then send('CASTLE|warstart|0|' .. castleSel .. '|' .. safe(txt('warMinutes'))) end
  end
  W('warStop').onClick = function(self) if confirm('warstop', self, 'Parar guerra') then send('CASTLE|warstop|0') end end
  W('clanReload').onClick = function() send('CASTLE|reload|0') end

  -- teleporte
  W('posGo').onClick = function() send('GOTO|' .. safe(txt('posX')) .. '|' .. safe(txt('posY')) .. '|' .. safe(txt('posZ'))) end
  W('posFill').onClick = function()
    W('posX'):setText(tostring(state.x)) W('posY'):setText(tostring(state.y)) W('posZ'):setText(tostring(state.z))
  end
  W('floorUp').onClick = function() send('FLOOR|up') end
  W('floorDown').onClick = function() send('FLOOR|down') end
  W('favAdd').onClick = function()
    local name = txt('favName')
    if name == '' then name = 'Ponto ' .. state.x .. ',' .. state.y end
    local favs = loadFavs()
    favs[#favs + 1] = { name = name, x = state.x, y = state.y, z = state.z }
    saveFavs(favs)
    W('favName'):setText('')
    renderFavs()
  end

  -- servidor
  W('bcRed').onClick = function() send('BCAST|red|' .. safe(txt('bcText'))) end
  W('bcWhite').onClick = function() send('BCAST|white|' .. safe(txt('bcText'))) end
  W('bcGreen').onClick = function() send('BCAST|green|' .. safe(txt('bcText'))) end
  W('srvSave').onClick = function() send('SERVER|save') end
  W('srvClean').onClick = function(self) if confirm('clean', self, 'Limpar mapa') then send('SERVER|clean') end end

  -- equipe
  W('staffRefresh').onClick = function() send('STAFFLIST') end
  for i, id in ipairs(ROLE_IDS) do
    W(id).onClick = function(self) if self:isEnabled() then selectRole(i) end end
  end
  W('staffApply').onClick = function(self)
    local name = safe(txt('staffName'))
    if name == '' then return status('Digite o nome do personagem.', false) end
    if not sel.role then return status('Escolha o novo cargo.', false) end
    if confirm('role', self, 'Aplicar cargo') then send('SETROLE|' .. name .. '|' .. sel.role) end
  end

  -- eu
  W('meGhost').onClick = function() send('ME|ghost') end
  W('meHide').onClick = function() send('ME|hide') end
  W('meHeal').onClick = function() send('ME|heal') end
  W('lookApply').onClick = function() send('ME|look|' .. safe(txt('lookValue'))) end
  W('effectApply').onClick = function() send('ME|effect|' .. safe(txt('effectValue'))) end
  W('effectNext').onClick = function()
    local n = (tonumber(txt('effectValue')) or 0) + 1
    W('effectValue'):setText(tostring(n))
    send('ME|effect|' .. n)
  end
end

local function onGameEnd()
  if window then window:hide() end
  isStaff, isGod, myRank, myRole = false, false, 0, ''
  if topButton then
    pcall(function() topButton:destroy() end)
    topButton = nil
  end
end

function init()
  window = g_ui.displayUI('adminpanel')
  window:hide()
  bindButtons()
  bindStatButtons()
  showTab('players')
  ProtocolGame.registerExtendedOpcode(OPCODE, onAdminOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, function() if isStaff then toggle() end end)
  -- Ctrl+Alt+D (depuracao) desligado: tira o atalho depois que todos os modulos carregaram
  scheduleEvent(killDebugKey, 3000)
  connect(g_game, { onGameStart = onGameStartDebug })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(g_game, { onGameStart = onGameStartDebug })
  g_keyboard.unbindKeyDown(HOTKEY)
  if topButton then pcall(function() topButton:destroy() end) topButton = nil end
  if window then window:destroy() window = nil end
end
