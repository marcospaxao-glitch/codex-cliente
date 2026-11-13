-- ============================================================
-- POKEDEX (cliente) - opcode 102
-- Abre pelo botao do topmenu ou usando a Pokedex (item ao lado
-- do inventario) em um pokemon selvagem.
-- So envia pacotes a partir de cliques do jogador.
-- ============================================================

local OPCODE = 102
local PER_PAGE = 20

local window = nil
local topButton = nil

local species = {}        -- {dex, name, look, t1, t2, state, gen}
local incoming = nil      -- lista sendo recebida
local totals = { seen = 0, caught = 0, total = 0 }
local maxStat = { 1, 1, 1, 1, 1, 1 }
local view = { filter = 'all', type = 'all', gen = 0, search = '', page = 1 }
local filtered = {}
local selectedName = nil
local current = nil       -- detalhe aberto
local currentTab = 'status'

local TYPES = { 'all', 'normal', 'fire', 'water', 'electric', 'grass', 'ice', 'fighting', 'poison', 'ground',
  'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy' }

local TYPE_INFO = {
  normal   = { 'Normal',   '#a8a77a' },
  fire     = { 'Fogo',     '#ee8130' },
  water    = { 'Agua',     '#6390f0' },
  electric = { 'Eletrico', '#f7d02c' },
  grass    = { 'Planta',   '#7ac74c' },
  ice      = { 'Gelo',     '#96d9d6' },
  fighting = { 'Lutador',  '#c22e28' },
  poison   = { 'Veneno',   '#a33ea1' },
  ground   = { 'Terra',    '#e2bf65' },
  flying   = { 'Voador',   '#a98ff3' },
  psychic  = { 'Psiquico', '#f95587' },
  bug      = { 'Inseto',   '#a6b91a' },
  rock     = { 'Pedra',    '#b6a136' },
  ghost    = { 'Fantasma', '#735797' },
  dragon   = { 'Dragao',   '#6f35fc' },
  dark     = { 'Sombrio',  '#705746' },
  steel    = { 'Aco',      '#b7b7ce' },
  fairy    = { 'Fada',     '#d685ad' },
}

local STAT_ROWS = {
  { id = 'statHp',  label = 'Vida',     color = '#5fd35f' },
  { id = 'statAtk', label = 'Ataque',   color = '#e04848' },
  { id = 'statSpa', label = 'Atq. Esp', color = '#ee8130' },
  { id = 'statDef', label = 'Defesa',   color = '#6390f0' },
  { id = 'statSpd', label = 'Def. Esp', color = '#96d9d6' },
  { id = 'statSpe', label = 'Veloc.',   color = '#f2c400' },
}

local TABS = {
  status = { button = 'tabStatus', page = 'pageStatus' },
  moves  = { button = 'tabMoves',  page = 'pageMoves' },
  evo    = { button = 'tabEvo',    page = 'pageEvo' },
  drops  = { button = 'tabDrops',  page = 'pageDrops' },
}

-- ------------------------------------------------------------ util
local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function split(line, sep)
  sep = sep or '|'
  local out = {}
  for field in (line .. sep):gmatch('(.-)%' .. sep) do out[#out + 1] = field end
  return out
end

local function typeName(t)
  local info = TYPE_INFO[t or '']
  return info and info[1] or 'Todos'
end

local function textColorFor(hex)
  local r = tonumber(hex:sub(2, 3), 16) or 0
  local g = tonumber(hex:sub(4, 5), 16) or 0
  local b = tonumber(hex:sub(6, 7), 16) or 0
  return (r * 0.299 + g * 0.587 + b * 0.114) > 150 and '#0a1320' or '#ffffff'
end

local function paintType(label, t)
  if not label then return end
  local info = TYPE_INFO[t or '']
  if not info then
    label:setVisible(false)
    return
  end
  label:setVisible(true)
  label:setText(info[1])
  label:setFont('verdana-11px-antialised') -- fonte com contorno fica ilegivel em fundo claro
  label:setBackgroundColor(info[2])
  label:setColor(textColorFor(info[2]))
end

local function setOutfit(widget, look)
  if not widget then return end
  if look and look[1] and look[1] > 0 then
    widget:setVisible(true)
    pcall(function()
      widget:setOutfit({ type = look[1], head = look[2] or 0, body = look[3] or 0, legs = look[4] or 0, feet = look[5] or 0 })
    end)
  else
    widget:setVisible(false)
  end
end

local function numText(n)
  return string.format('#%03d', tonumber(n) or 0)
end

-- ------------------------------------------------------------ lista
local function matches(s)
  if view.filter == 'seen' and s.state < 1 then return false end
  if view.filter == 'caught' and s.state < 2 then return false end
  if view.filter == 'missing' and s.state >= 2 then return false end
  if view.type ~= 'all' and s.t1 ~= view.type and s.t2 ~= view.type then return false end
  if view.gen > 0 and s.gen ~= view.gen then return false end
  if view.search ~= '' then
    local q = view.search
    local num = tonumber(q)
    if num then
      if s.dex ~= num and not tostring(s.dex):find(q, 1, true) then return false end
    elseif not s.name:lower():find(q, 1, true) then
      return false
    end
  end
  return true
end

local function refreshFilterButtons()
  for key, id in pairs({ all = 'filterAll', seen = 'filterSeen', caught = 'filterCaught', missing = 'filterMissing' }) do
    local b = W(id)
    if b then b:setOn(view.filter == key) end
  end
  local tb = W('typeButton')
  if tb then tb:setText('Tipo: ' .. typeName(view.type)) end
  local gb = W('genButton')
  if gb then gb:setText(view.gen > 0 and ('Geracao: ' .. view.gen) or 'Geracao: Todas') end
end

local function renderGrid()
  local grid = W('grid')
  if not grid then return end
  grid:destroyChildren()
  local pages = math.max(1, math.ceil(#filtered / PER_PAGE))
  view.page = math.max(1, math.min(view.page, pages))
  local first = (view.page - 1) * PER_PAGE + 1
  for i = first, math.min(#filtered, first + PER_PAGE - 1) do
    local s = filtered[i]
    local card = g_ui.createWidget('DexCard', grid)
    card:getChildById('number'):setText(numText(s.dex))
    local known = s.name ~= '???'
    card:getChildById('name'):setText(known and s.name or '???')
    card:getChildById('name'):setColor(known and '#dce8f5' or '#5f7596')
    card:getChildById('unknown'):setVisible(not known)
    card:getChildById('caught'):setVisible(s.state >= 2)
    setOutfit(card:getChildById('creature'), known and s.look or nil)
    card:setTooltip(known and (numText(s.dex) .. ' ' .. s.name .. '\nLooktype ' .. tostring(s.look[1] or 0)) or 'Nao registrado')
    card:setOn(known and selectedName ~= nil and s.name:lower() == selectedName:lower())
    card.onClick = function()
      if not known then
        showLocked(s)
        return
      end
      selectedName = s.name
      for _, c in ipairs(grid:getChildren()) do c:setOn(false) end
      card:setOn(true)
      send('DETAIL|' .. s.name)
    end
  end
  W('emptyLabel'):setVisible(#filtered == 0)
  W('pageLabel'):setText(string.format('%d / %d  (%d)', view.page, pages, #filtered))
  W('prevPage'):setEnabled(view.page > 1)
  W('nextPage'):setEnabled(view.page < pages)
end

local function applyFilters(keepPage)
  filtered = {}
  for _, s in ipairs(species) do
    if matches(s) then filtered[#filtered + 1] = s end
  end
  if not keepPage then view.page = 1 end
  refreshFilterButtons()
  renderGrid()
end

local function goToSpecies(name)
  if not name or name == '' then return end
  local lname = name:lower()
  for i, s in ipairs(filtered) do
    if s.name:lower() == lname then
      view.page = math.floor((i - 1) / PER_PAGE) + 1
      selectedName = s.name
      renderGrid()
      return true
    end
  end
  return false
end

local function renderProgress()
  W('progressLabel'):setText(string.format('Vistos %d   Capturados %d   Total %d', totals.seen, totals.caught, totals.total))
  local track = W('progressTrack')
  local fill = W('progressFill')
  if track and fill then
    local pct = totals.total > 0 and (totals.caught / totals.total) or 0
    fill:setWidth(math.floor((track:getWidth() - 2) * pct))
  end
end

-- ------------------------------------------------------------ detalhe
local function showTab(name)
  currentTab = name
  for key, t in pairs(TABS) do
    local b, p = W(t.button), W(t.page)
    if b then b:setOn(key == name) end
    if p then p:setVisible(key == name) end
  end
end

function showLocked(s)
  current = nil
  W('content'):setVisible(false)
  local ph = W('placeholder')
  ph:setVisible(true)
  ph:setText(numText(s.dex) .. '  ???\nUse a Pokedex em um pokemon selvagem para registrar.')
end

-- codex: tooltip seguro (alguns clientes nao tem removeTooltip)
local function setTip(w, text)
  if not w then return end
  if text and text ~= '' then
    pcall(function() w:setTooltip(text) end)
  else
    local ok = w.removeTooltip and pcall(function() w:removeTooltip() end)
    if not ok then pcall(function() w:setTooltip('') end) end
  end
end

-- codex: "Nivel 16" -> "Nv. 16"
local function howShort(how)
  how = tostring(how or '')
  if how == '' or how == '-' then return '?' end
  return (how:gsub('Nivel ', 'Nv. '))
end
-- codex: proxima evolucao do pokemon aberto (texto curto e completo)
local function evoSummary(d)
  local idx
  for i, e in ipairs(d.evos) do
    if e.name:lower() == tostring(d.base or ''):lower() then idx = i break end
  end
  if not idx then return '', '' end
  local cur, kids = d.evos[idx].depth, {}
  for i = idx + 1, #d.evos do
    local e = d.evos[i]
    if e.depth <= cur then break end
    if e.depth == cur + 1 then kids[#kids + 1] = e end
  end
  if #kids == 0 then return (#d.evos > 1) and 'Ultima evolucao' or '', '' end
  local parts = {}
  for _, e in ipairs(kids) do parts[#parts + 1] = e.name .. ' (' .. howShort(e.how) .. ')' end
  local full = 'Evolui para: ' .. table.concat(parts, ', ')
  local short = #kids == 1 and ('Evolui: ' .. parts[1]) or ('Evolui: ' .. #kids .. ' opcoes (aba Evolucao)')
  if #short > 42 then short = short:sub(1, 40) .. '..' end
  return short, full
end

local function renderDetail()
  local d = current
  if not d then return end
  W('placeholder'):setVisible(false)
  W('content'):setVisible(true)

  setOutfit(W('bigCreature'), d.look)
  W('portrait'):setTooltip(d.name .. '\nLooktype ' .. tostring(d.look[1] or 0))
  W('dexName'):setText(d.name)
  W('dexNumber'):setText(numText(d.dex) .. '   Geracao ' .. d.gen)
  paintType(W('type1'), d.t1)
  paintType(W('type2'), d.t2 ~= 'none' and d.t2 or nil)

  local tag = W('stateTag')
  tag:setFont('verdana-11px-antialised')
  if d.state >= 2 then
    tag:setText('CAPTURADO'); tag:setBackgroundColor('#5fd35f'); tag:setColor('#0a1320')
  elseif d.state == 1 then
    tag:setText('VISTO'); tag:setBackgroundColor('#6390f0'); tag:setColor('#ffffff')
  else
    tag:setText('NAO REGISTRADO'); tag:setBackgroundColor('#3a5170'); tag:setColor('#dce8f5')
  end
  -- codex: placar da garantia de captura
  local TIER_NAME = { comum = 'Comum', incomum = 'Incomum', raro = 'Raro', shiny = 'Shiny/Mega', lendario = 'Lendario' }
  local hasPity = d.pity and d.pity >= 0 and d.pityMax and d.pityMax > 0
  W('expLabel'):setText('Experiencia base ' .. d.exp)
  W('expLabel'):setColor('#8fa7c4')
  if hasPity then
    local falta = d.pityMax - d.pity
    W('catchLabel'):setText(string.format('Tentativas %d/%d   Capturas %d', d.pity, d.pityMax, d.catches))
    W('catchLabel'):setColor(falta <= 1 and '#5fd35f' or '#f2c400')
    local tip = (falta <= 1 and 'A proxima pokebola captura com certeza!'
      or ('Faltam ' .. falta .. ' pokebolas erradas para a captura garantida.')) ..
      '\nRaridade: ' .. (TIER_NAME[d.pityTier] or '-') .. ' (garantia em ' .. d.pityMax .. ').' ..
      '\nAo capturar, volta a zero.\nTotal de pokebolas jogadas: ' .. d.tries .. '.'
    setTip(W('catchLabel'), tip)
    W('pityTrack'):setVisible(true)
    setTip(W('pityTrack'), tip)
    local full = W('pityTrack'):getWidth()
    W('pityFill'):setWidth(math.floor(full * math.min(1, d.pity / d.pityMax)))
    W('pityFill'):setBackgroundColor(falta <= 1 and '#5fd35f' or '#f2c400')
  else
    W('catchLabel'):setText(string.format('Tentativas %d   Capturas %d', d.tries, d.catches))
    W('catchLabel'):setColor('#8fa7c4')
    setTip(W('catchLabel'), '')
    W('pityTrack'):setVisible(false)
  end
  local evoShort, evoFull = evoSummary(d)
  W('evoLabel'):setText(evoShort)
  setTip(W('evoLabel'), evoFull)

  -- formas
  local forms = W('forms')
  forms:destroyChildren()
  for _, f in ipairs(d.forms) do
    local b = g_ui.createWidget('DexFormButton', forms)
    local label = f.name
    if f.name:lower() == d.base:lower() then
      label = 'Normal'
    else
      label = label:gsub((d.base:gsub('%p', '%%%0')), ''):gsub('%s+', ' '):gsub('^%s', ''):gsub('%s$', '')
      if label == '' then label = f.name end
    end
    b:setText(' ' .. label .. ' ')
    b:setOn(f.name:lower() == d.name:lower())
    b.onClick = function() send('DETAIL|' .. f.name) end
  end
  forms:setVisible(#d.forms > 1)

  -- status
  local values = { d.hp, d.atk, d.spa, d.def, d.spd, d.spe }
  for i, row in ipairs(STAT_ROWS) do
    local w = W(row.id)
    if w then
      w:getChildById('label'):setText(row.label)
      w:getChildById('value'):setText(tostring(values[i]))
      local track = w:getChildById('track')
      local fill = w:getChildById('fill')
      local pct = math.min(1, (values[i] or 0) / math.max(1, maxStat[i] or 1))
      fill:setWidth(math.max(values[i] > 0 and 2 or 0, math.floor((track:getWidth() - 2) * pct)))
      fill:setBackgroundColor(row.color)
    end
  end
  if d.abilityName ~= '' then
    W('abilityName'):setText(d.abilityName)
    W('abilityDesc'):setText(d.abilityDesc)
  else
    W('abilityName'):setText('Nenhuma')
    W('abilityDesc'):setText('Este pokemon nao tem hidden ability.')
  end
  W('fieldLabel'):setText(d.fields ~= '' and d.fields:gsub(',', '   ') or 'Nenhuma')

  -- golpes
  local list = W('movesList')
  list:destroyChildren()
  for i, m in ipairs(d.moves) do
    local row = g_ui.createWidget('DexMoveRow', list)
    row:setBackgroundColor(i % 2 == 0 and '#0c1828' or '#101f3e')
    row:getChildById('level'):setText(m.level > 0 and tostring(m.level) or '-')
    row:getChildById('name'):setText(m.name)
    -- icone da move (mesmo da barra de moves)
    local barMod = modules.game_pokemonmoves
    if barMod and barMod.applyMoveIcon then
      pcall(barMod.applyMoveIcon, row:getChildById('moveIcon'), m.name, 18)
    end
    paintType(row:getChildById('type'), m.type)
    row:getChildById('power'):setText(m.power > 0 and tostring(m.power) or '-')
    row:getChildById('cooldown'):setText(m.cooldown > 0 and (m.cooldown .. 's') or '-')
  end

  -- evolucao
  local evo = W('evoList')
  evo:destroyChildren()
  for _, e in ipairs(d.evos) do
    local row = g_ui.createWidget('DexEvoRow', evo)
    row:getChildById('indent'):setWidth(4 + e.depth * 22)
    row:getChildById('arrow'):setText(e.depth > 0 and '>' or '')
    local known = e.name ~= '???'
    setOutfit(row:getChildById('creature'), known and e.look or nil)
    row:getChildById('name'):setText(e.name)
    local howW = row:getChildById('how')
    if e.depth > 0 and tostring(e.how):find('Nivel') then
      howW:setText((tostring(e.how):gsub('Nivel', 'Evolui no nivel')))
      howW:setColor('#f2c400')
    else
      howW:setText(e.depth > 0 and e.how or 'Forma inicial')
      howW:setColor('#8fa7c4')
    end
    local st = row:getChildById('state')
    st:setText(e.state >= 2 and 'Capturado' or (e.state == 1 and 'Visto' or 'Nao visto'))
    st:setColor(e.state >= 2 and '#5fd35f' or (e.state == 1 and '#8fa7c4' or '#5f7596'))
    row:setOn(known and e.name:lower() == d.base:lower())
    if known then
      row.onClick = function()
        selectedName = e.name
        goToSpecies(e.name)
        send('DETAIL|' .. e.name)
      end
    end
  end
  if #d.evos <= 1 then
    local row = g_ui.createWidget('DexLabel', evo)
    row:setText(#d.evos == 0 and 'Sem dados de evolucao.' or 'Este pokemon nao evolui.')
    row:setHeight(18)
  end

  -- drops
  local drops = W('dropsList')
  drops:destroyChildren()
  for _, it in ipairs(d.drops) do
    local cell = g_ui.createWidget('DexDropCell', drops)
    local item = cell:getChildById('item')
    pcall(function() item:setItemId(it.id) end)
    cell:setTooltip(it.name)
    cell:getChildById('chance'):setText(it.chance .. '%')
    cell:getChildById('count'):setText(it.max > 1 and ('ate ' .. it.max) or '1x')
  end
  W('dropsEmpty'):setVisible(#d.drops == 0)

  showTab(currentTab)
end

local function parseDetail(buffer)
  local d = { forms = {}, moves = {}, evos = {}, drops = {} }
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = split(line)
    local head = f[1]
    if head == 'DETAIL' then
      d.name, d.base, d.dex = f[2], f[3], tonumber(f[4]) or 0
      d.look = { tonumber(f[5]) or 0, tonumber(f[6]) or 0, tonumber(f[7]) or 0, tonumber(f[8]) or 0, tonumber(f[9]) or 0 }
      d.t1, d.t2, d.state = f[10], f[11], tonumber(f[12]) or 0
      d.exp = tonumber(f[13]) or 0
      d.hp, d.atk, d.spa = tonumber(f[14]) or 0, tonumber(f[15]) or 0, tonumber(f[16]) or 0
      d.def, d.spd, d.spe = tonumber(f[17]) or 0, tonumber(f[18]) or 0, tonumber(f[19]) or 0
      d.tries, d.catches = tonumber(f[20]) or 0, tonumber(f[21]) or 0
      d.abilityName, d.abilityDesc = f[22] or '', f[23] or ''
      d.fields, d.gen = f[24] or '', tonumber(f[25]) or 1
      d.pity, d.pityMax, d.pityTier = tonumber(f[26]) or -1, tonumber(f[27]) or 0, f[28] or ''
    elseif head == 'FORM' then
      d.forms[#d.forms + 1] = { name = f[2], look = { tonumber(f[3]) or 0, tonumber(f[4]) or 0, tonumber(f[5]) or 0, tonumber(f[6]) or 0, tonumber(f[7]) or 0 } }
    elseif head == 'MOVE' then
      d.moves[#d.moves + 1] = { level = tonumber(f[2]) or 0, name = f[3] or '?', power = tonumber(f[4]) or 0,
        cooldown = tonumber(f[5]) or 0, type = f[6] or 'normal' }
    elseif head == 'EVO' then
      d.evos[#d.evos + 1] = { depth = tonumber(f[2]) or 0, name = f[3] or '???',
        look = { tonumber(f[4]) or 0, tonumber(f[5]) or 0, tonumber(f[6]) or 0, tonumber(f[7]) or 0, tonumber(f[8]) or 0 },
        how = f[9] or '', state = tonumber(f[10]) or 0 }
    elseif head == 'DROP' then
      d.drops[#d.drops + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '', chance = f[4] or '0', max = tonumber(f[5]) or 1 }
    end
  end
  return d
end

-- ------------------------------------------------------------ rede
local function showWindow()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
end

local function onOpcode(protocol, opcode, buffer)
  buffer = buffer or ''
  local head = buffer:match('^([^|\n]*)')
  if head == 'LIST' then
    incoming = incoming or {}
    for line in (buffer .. '\n'):gmatch('(.-)\n') do
      local f = split(line)
      if f[1] == 'L' then
        incoming[#incoming + 1] = {
          dex = tonumber(f[2]) or 0, name = f[3] or '???',
          look = { tonumber(f[4]) or 0, tonumber(f[5]) or 0, tonumber(f[6]) or 0, tonumber(f[7]) or 0, tonumber(f[8]) or 0 },
          t1 = f[9] or 'none', t2 = f[10] or 'none', state = tonumber(f[11]) or 0, gen = tonumber(f[12]) or 1,
        }
      end
    end
  elseif head == 'LIST_END' then
    local f = split(buffer)
    species = incoming or {}
    incoming = nil
    totals.seen, totals.caught, totals.total = tonumber(f[2]) or 0, tonumber(f[3]) or 0, tonumber(f[4]) or #species
    for i = 1, 6 do maxStat[i] = math.max(1, tonumber(f[4 + i]) or 1) end
    local focus = f[11] or ''
    showWindow()
    renderProgress()
    if focus ~= '' then
      selectedName = focus
      view.filter, view.type, view.gen, view.search = 'all', 'all', 0, ''
      W('searchEdit'):setText('')
      applyFilters()
      if not goToSpecies(focus) then
        -- forma (Shiny/Mega): marca a especie base quando o detalhe chegar
      end
    else
      applyFilters(true)
    end
  elseif head == 'DETAIL' then
    current = parseDetail(buffer)
    selectedName = current.base
    goToSpecies(current.base)
    renderDetail()
    showWindow()
  elseif head == 'DENY' then
    local f = split(buffer)
    current = nil
    W('content'):setVisible(false)
    local ph = W('placeholder')
    ph:setVisible(true)
    ph:setText((f[3] or 'Pokemon nao registrado.'))
  end
end

-- ------------------------------------------------------------ abrir / fechar
function toggle()
  if not window then return end
  if window:isVisible() then
    window:hide()
  elseif g_game.isOnline() then
    send('OPEN')
  end
end

local function bind()
  W('closeButton').onClick = function() window:hide() end
  W('filterAll').onClick = function() view.filter = 'all'; applyFilters() end
  W('filterSeen').onClick = function() view.filter = 'seen'; applyFilters() end
  W('filterCaught').onClick = function() view.filter = 'caught'; applyFilters() end
  W('filterMissing').onClick = function() view.filter = 'missing'; applyFilters() end

  local function cycleType(step)
    local idx = 1
    for i, t in ipairs(TYPES) do if t == view.type then idx = i end end
    idx = ((idx - 1 + step) % #TYPES) + 1
    view.type = TYPES[idx]
    applyFilters()
  end
  local function cycleGen(step)
    view.gen = (view.gen + step) % 10
    applyFilters()
  end
  local tb, gb = W('typeButton'), W('genButton')
  tb.onClick = function() cycleType(1) end
  tb.onMouseRelease = function(widget, pos, button)
    if button == MouseRightButton then cycleType(-1) return true end
  end
  gb.onClick = function() cycleGen(1) end
  gb.onMouseRelease = function(widget, pos, button)
    if button == MouseRightButton then cycleGen(-1) return true end
  end
  tb:setTooltip('Clique: proximo tipo | Botao direito: anterior')
  gb:setTooltip('Clique: proxima geracao | Botao direito: anterior')

  W('prevPage').onClick = function() view.page = view.page - 1; renderGrid() end
  W('nextPage').onClick = function() view.page = view.page + 1; renderGrid() end
  W('grid').onMouseWheel = function(widget, mousePos, direction)
    if direction == MouseWheelUp then view.page = view.page - 1 else view.page = view.page + 1 end
    renderGrid()
    return true
  end

  W('searchEdit').onTextChange = function(widget, text)
    view.search = (text or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
    applyFilters()
  end

  for key, t in pairs(TABS) do
    W(t.button).onClick = function() showTab(key) end
  end
end

local function onGameStart()
  if topButton then return end
  local topmenu = modules.client_topmenu
  local ok, button = pcall(function()
    if topmenu.addCenterGameButton then
      return topmenu.addCenterGameButton('pokedexButton', 'Pokedex', '/modules/game_pokedex/images/topbutton.png', toggle)
    end
    return topmenu.addRightGameToggleButton('pokedexButton', 'Pokedex', '/modules/game_pokedex/images/topbutton', toggle)
  end)
  if ok then topButton = button end
end

local function onGameEnd()
  if window then window:hide() end
  species, filtered, current, incoming, selectedName = {}, {}, nil, nil, nil
  if topButton then
    pcall(function() topButton:destroy() end)
    topButton = nil
  end
end

function init()
  print('[Pokedex] CODEX V3 carregada (tentativas X/Y + evolucao)')
  window = g_ui.displayUI('pokedex')
  window:hide()
  bind()
  showTab('status')
  refreshFilterButtons()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if topButton then pcall(function() topButton:destroy() end) topButton = nil end
  if window then window:destroy() window = nil end
end
