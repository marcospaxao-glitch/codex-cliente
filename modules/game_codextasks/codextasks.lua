-- ============================================================
-- TASKS DE ABATE (cliente) - opcode 133
-- Servidor: data/lib/core/codextasks.lua
-- Abre pelo Mural de Tasks (item no mapa). Ctrl+Shift+Y ou o botao
-- do topo abrem so para ver o progresso: aceitar e entregar
-- precisam estar perto de um mural.
-- ============================================================

local OPCODE = 133
local HOTKEY = 'Ctrl+Shift+Y'
local TYPE_DIR = '/modules/game_pokemonmanager/images/'

local window = nil
local topButton = nil
local page = 'mine'
local filter = 0            -- 0 = todas as faixas
local searchText = ''
local onlyAvailable = false
local pageIndex = 1
local perPage = 12
local cancelArmed = nil     -- chave da task esperando confirmacao de cancelar
local cancelEvent = nil

local catalog = {}          -- lista na ordem do servidor
local byKey = {}
local tiers = {}            -- [i] = {name, color}
local catVersion = nil
local catParts, catTotal, catWaiting = {}, 0, nil
local asked = false

local refresh, setPage

local state = { open = false, atMural = false, active = 0, max = 3, total = 0, tasks = {}, done = {} }

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, text)
  end
end

local function split(line)
  local f = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    f[#f + 1] = field
  end
  return f
end

local function fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', ''))
end

local function curto(n)
  n = tonumber(n) or 0
  if n >= 1000000 then
    return (string.format('%.1fkk', n / 1000000):gsub('%.0kk', 'kk'))
  elseif n >= 10000 then
    return math.floor(n / 1000) .. 'k'
  end
  return fmt(n)
end

local function duration(sec)
  sec = math.max(0, math.floor(sec))
  if sec >= 3600 then
    return math.floor(sec / 3600) .. 'h' .. string.format('%02d', math.floor(sec % 3600 / 60))
  end
  return math.max(1, math.ceil(sec / 60)) .. ' min'
end

local function tierOf(e)
  return tiers[e.tier] or { name = '?', color = '#8fa7c4' }
end

local function setCreature(widget, look)
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

local function setTypes(card, e)
  local t1, t2 = card:getChildById('type1'), card:getChildById('type2')
  local function put(w, t)
    if t and t ~= '' then
      w:setImageSource(TYPE_DIR .. t)
      w:setVisible(true)
      w:setTooltip(t)
    else
      w:setVisible(false)
    end
  end
  put(t1, e.type1)
  put(t2, e.type2)
end

local function setRewardItems(panel, e)
  panel:destroyChildren()
  for _, it in ipairs(e.items) do
    local w = g_ui.createWidget('TkRewardItem', panel)
    pcall(function() w:setItemId(it.id) end)
    if it.count > 1 then pcall(function() w:setItemCount(it.count) end) end
    w:setTooltip(it.count .. 'x ' .. it.name .. (#e.items > 1 and ' (sorteia um)' or ''))
  end
end

-- ============================================================
-- celular: arrastar com o dedo rola a lista
-- ============================================================
local function isPhone()
  return type(codexCelular) == 'function' and codexCelular() and true or false
end

local function inside(w, parent)
  while w do
    if w == parent then return true end
    w = w:getParent()
  end
  return false
end

local function dragScroll(area)
  if not area or area.tkDrag then return end
  area.tkDrag = true
  local lastY, lastMs = nil, 0
  area.onMouseMove = function(self, pos)
    local bar = self.verticalScrollBar
    local pressed = g_ui.getPressedWidget()
    if not bar or not pressed or g_ui.getDraggingWidget() or inside(pressed, bar) or not inside(pressed, self)
        or bar:getMaximum() <= bar:getMinimum() then
      lastY = nil
      return false
    end
    local now = g_clock.millis()
    if lastY and now - lastMs < 250 then
      local dy = pos.y - lastY
      if dy ~= 0 then bar:setValue(bar:getValue() - dy) end
    end
    lastY, lastMs = pos.y, now
    return true
  end
end

-- ============================================================
-- Minhas Tasks
-- ============================================================
local function buildMine()
  local list = W('minePage')
  list:destroyChildren()
  local shown = 0
  for _, t in ipairs(state.tasks) do
    local e = byKey[t.key] or { key = t.key, name = t.key, look = {}, tier = 1, gold = 0, exp = 0, items = {}, minLv = 0, maxLv = 0 }
    local tier = tierOf(e)
    local card = g_ui.createWidget('TkActiveCard', list)
    local complete = t.progress >= t.goal
    shown = shown + 1
    card:getChildById('accent'):setBackgroundColor(tier.color)
    setCreature(card:getChildById('creature'), e.look)
    card:getChildById('nameLabel'):setText(e.name)
    local tl = card:getChildById('tierLabel')
    tl:setText(tier.name)
    tl:setBackgroundColor(tier.color)
    tl:setWidth(#tier.name * 7 + 16)
    setTypes(card, e)

    local ratio = t.goal > 0 and math.min(1, t.progress / t.goal) or 0
    local track, fill = card:getChildById('track'), card:getChildById('fill')
    local function sizeFill()
      if fill:isDestroyed() then return end
      local width = track:getWidth()
      if not width or width <= 6 then width = 420 end
      fill:setWidth(math.max(0, math.floor((width - 6) * ratio)))
    end
    sizeFill()
    scheduleEvent(sizeFill, 60)
    fill:setBackgroundColor(complete and '#2e9d55' or '#3a6ea5')
    card:getChildById('progressLabel'):setText(complete and ('CONCLUIDA  ' .. fmt(t.goal) .. ' / ' .. fmt(t.goal))
      or (fmt(t.progress) .. ' / ' .. fmt(t.goal) .. ' abates'))

    card:getChildById('rewardLabel'):setText('Recompensa:  ' .. fmt(e.gold) .. ' gp   +   ' .. fmt(e.exp) .. ' exp' ..
      (#e.items > 0 and '   +' or ''))
    setRewardItems(card:getChildById('rewardItems'), e)
    local d = state.done[t.key]
    card:getChildById('infoLabel'):setText('Nivel ' .. e.minLv .. '-' .. e.maxLv ..
      (d and d.times > 0 and ('   |   voce ja fez ' .. d.times .. 'x') or '') ..
      (complete and '   |   entregue em qualquer Mural de Tasks' or ''))

    local claim = card:getChildById('claimButton')
    if complete then
      claim:setStyle('TkGoldButton')
      claim:setSize({ width = 140, height = 32 })
      claim:setText(state.atMural and 'Entregar' or 'Va ao mural')
      claim:setEnabled(state.atMural)
      claim:setTooltip(state.atMural and 'Receber a recompensa' or 'Chegue perto de um Mural de Tasks para entregar')
    else
      claim:setText(math.floor(ratio * 100) .. '%')
      claim:setEnabled(false)
      claim:setTooltip('Derrote mais ' .. fmt(t.goal - t.progress) .. ' ' .. e.name)
    end
    local key = t.key
    claim.onClick = function() send('CLAIM|' .. key) end

    local cancel = card:getChildById('cancelButton')
    cancel:setText(cancelArmed == key and 'Confirmar?' or 'Cancelar')
    cancel:setTooltip('O progresso desta task e perdido')
    cancel.onClick = function()
      if cancelArmed == key then
        cancelArmed = nil
        send('CANCEL|' .. key)
        return
      end
      cancelArmed = key
      cancel:setText('Confirmar?')
      if cancelEvent then removeEvent(cancelEvent) end
      cancelEvent = scheduleEvent(function()
        cancelEvent = nil
        cancelArmed = nil
        if cancel and not cancel:isDestroyed() then cancel:setText('Cancelar') end
      end, 3000)
    end
  end
  for _ = shown + 1, state.max do
    local empty = g_ui.createWidget('TkEmptyCard', list)
    empty:getChildById('goBoardButton').onClick = function() setPage('board') end
  end
end

-- ============================================================
-- Mural (catalogo)
-- ============================================================
local function activeTask(key)
  for _, t in ipairs(state.tasks) do
    if t.key == key then return t end
  end
  return nil
end

local function waitLeft(key)
  local d = state.done[key]
  if not d or d.wait <= 0 then return 0 end
  return d.wait - (os.time() - d.at)
end

local function filtered()
  local out = {}
  local s = searchText:lower()
  for _, e in ipairs(catalog) do
    if (filter == 0 or e.tier == filter) and (s == '' or e.name:lower():find(s, 1, true)) then
      if not onlyAvailable or (not activeTask(e.key) and waitLeft(e.key) <= 0) then
        out[#out + 1] = e
      end
    end
  end
  return out
end

local function buildFilters()
  local panel = W('filtersPanel')
  panel:destroyChildren()
  local counts = {}
  for _, e in ipairs(catalog) do
    counts[e.tier] = (counts[e.tier] or 0) + 1
  end
  local function add(index, name, color, count)
    local b = g_ui.createWidget('TkFilter', panel)
    b:setText(name)
    b:setOn(filter == index)
    b:getChildById('countLabel'):setText(tostring(count))
    local dot = b:getChildById('dot')
    if color then dot:setBackgroundColor(color) else dot:setVisible(false) end
    b.onClick = function()
      filter = index
      pageIndex = 1
      refresh()
    end
  end
  add(0, 'Todas', nil, #catalog)
  for i, t in ipairs(tiers) do
    add(i, t.name, t.color, counts[i] or 0)
  end
end

local function computePerPage()
  local grid = W('grid')
  local layout = grid:getLayout()
  local width = grid:getWidth()
  local height = grid:getHeight()
  if width <= 10 then width = 856 end
  if height <= 10 then height = 400 end
  local cols = math.max(1, math.floor((width + 8) / (211 + 8)))
  local rows = math.max(1, math.floor((height + 8) / (160 + 8)))
  pcall(function() layout:setNumColumns(cols) end)
  perPage = cols * rows
end

local function buildBoard()
  buildFilters()
  computePerPage()
  local list = filtered()
  local pages = math.max(1, math.ceil(#list / perPage))
  pageIndex = math.max(1, math.min(pageIndex, pages))
  W('pageLabel'):setText('Pagina ' .. pageIndex .. ' / ' .. pages)
  W('prevButton'):setEnabled(pageIndex > 1)
  W('nextButton'):setEnabled(pageIndex < pages)
  W('resultLabel'):setText(#list .. (#list == 1 and ' pokemon' or ' pokemons'))

  local grid = W('grid')
  grid:destroyChildren()
  local emptyLabel = W('emptyGridLabel')
  if #catalog == 0 then
    emptyLabel:setText('Carregando o mural...')
  else
    emptyLabel:setText('Nenhum pokemon encontrado.')
  end
  emptyLabel:setVisible(#list == 0)

  local full = state.active >= state.max
  for i = (pageIndex - 1) * perPage + 1, math.min(#list, pageIndex * perPage) do
    local e = list[i]
    local tier = tierOf(e)
    local card = g_ui.createWidget('TkBoardCard', grid)
    card:getChildById('accent'):setBackgroundColor(tier.color)
    setCreature(card:getChildById('creature'), e.look)
    card:getChildById('nameLabel'):setText(e.name)
    local tl = card:getChildById('tierLabel')
    tl:setText(tier.name)
    tl:setColor(tier.color)
    card:getChildById('levelLabel'):setText('Nivel ' .. e.minLv .. '-' .. e.maxLv)
    setTypes(card, e)
    card:getChildById('goalLabel'):setText(fmt(e.goal) .. ' abates')
    card:getChildById('goldLabel'):setText(curto(e.gold) .. ' gp')
    card:getChildById('expLabel'):setText('+' .. curto(e.exp) .. ' exp')
    setRewardItems(card:getChildById('rewardItems'), e)
    local d = state.done[e.key]
    local badge = card:getChildById('doneBadge')
    badge:setVisible(d ~= nil and d.times > 0)
    if d then
      badge:setText(d.times .. 'x')
      badge:setTooltip('Voce ja fez esta task ' .. d.times .. 'x')
    end
    card:setTooltip(e.name .. ' - ' .. tier.name .. '\nDerrote ' .. fmt(e.goal) .. '\nRecompensa: ' .. fmt(e.gold) ..
      ' gp + ' .. fmt(e.exp) .. ' exp')

    local button = card:getChildById('actionButton')
    local t = activeTask(e.key)
    local wait = waitLeft(e.key)
    local key = e.key
    if t and t.progress >= t.goal then
      button:setStyle('TkGoldButton')
      button:setHeight(26)
      button:setText(state.atMural and 'Entregar' or 'Concluida - va ao mural')
      button:setEnabled(state.atMural)
      button.onClick = function() send('CLAIM|' .. key) end
    elseif t then
      button:setText('Ativa  ' .. fmt(t.progress) .. ' / ' .. fmt(t.goal))
      button:setEnabled(false)
      button:setColor('#7ee08f')
    elseif wait > 0 then
      button:setText('Repetir em ' .. duration(wait))
      button:setEnabled(false)
    elseif full then
      button:setText('Limite ' .. state.active .. ' / ' .. state.max)
      button:setEnabled(false)
      button:setTooltip('Entregue ou cancele uma task para pegar outra')
    elseif not state.atMural then
      button:setText('Aceitar no mural')
      button:setEnabled(false)
      button:setTooltip('Chegue perto de um Mural de Tasks para aceitar')
    else
      button:setStyle('TkGoldButton')
      button:setHeight(26)
      button:setText('Aceitar')
      button.onClick = function() send('ACCEPT|' .. key) end
    end
  end
end

-- ============================================================
-- tela
-- ============================================================
function refreshTasks()
  if not window then return end
  W('summaryLabel'):setText('Ativas ' .. state.active .. ' / ' .. state.max .. '    |    Concluidas: ' .. fmt(state.total))
  local hint = W('hintLabel')
  if state.atMural then
    hint:setText('Voce esta no Mural: pode aceitar e entregar')
    hint:setColor('#7ee08f')
  else
    hint:setText('So visualizacao: va ate um Mural de Tasks para aceitar e entregar')
    hint:setColor('#ffb347')
  end
  hint:setWidth(hint:getTextSize().width + 24)

  local tabMine, tabBoard = W('tabMine'), W('tabBoard')
  tabMine:setOn(page == 'mine')
  tabBoard:setOn(page == 'board')
  tabMine:getChildById('countLabel'):setText(state.active .. '/' .. state.max)
  tabBoard:getChildById('countLabel'):setText(tostring(#catalog))
  W('minePage'):setVisible(page == 'mine')
  W('boardPage'):setVisible(page == 'board')
  local scroll = W('mineScroll')
  if page == 'mine' then
    buildMine()
    scroll:setVisible(isPhone() or scroll:getMaximum() > scroll:getMinimum())
  else
    scroll:setVisible(false)
    buildBoard()
  end
end

function setTasksPage(name)
  page = name
  cancelArmed = nil
  refresh()
  if page == 'board' then
    scheduleEvent(function() if window and window:isVisible() and page == 'board' then refresh() end end, 50)
  end
end

refresh, setPage = refreshTasks, setTasksPage

local function fitScreen()
  local root = g_ui.getRootWidget()
  local w, h = 896, 700
  if root:getWidth() - 8 < w then w = root:getWidth() - 8 end
  if root:getHeight() - 8 < h then h = root:getHeight() - 8 end
  window:setSize({ width = w, height = h })
end


-- ============================================================
-- mensagens do servidor
-- ============================================================
local function parseCatalog(lines)
  local list, keys, tierList = {}, {}, {}
  for _, line in ipairs(lines) do
    local f = split(line)
    if f[1] == 'F' then
      tierList[tonumber(f[2]) or (#tierList + 1)] = { name = f[3] or '?', color = f[4] or '#ffffff' }
    elseif f[1] == 'C' then
      local look = {}
      for n in (f[4] or ''):gmatch('[^%.]+') do look[#look + 1] = tonumber(n) or 0 end
      local items = {}
      for chunk in (f[11] or ''):gmatch('[^,]+') do
        local id, count, name = chunk:match('^(%d+):(%d+):(.*)$')
        if id then items[#items + 1] = { id = tonumber(id), count = tonumber(count), name = name } end
      end
      local e = {
        key = f[2] or '', name = f[3] or '?', look = look, minLv = tonumber(f[5]) or 0, maxLv = tonumber(f[6]) or 0,
        tier = tonumber(f[7]) or 1, goal = tonumber(f[8]) or 0, gold = tonumber(f[9]) or 0, exp = tonumber(f[10]) or 0,
        items = items, type1 = f[12] or '', type2 = f[13] or '',
      }
      list[#list + 1] = e
      keys[e.key] = e
    end
  end
  catalog, byKey, tiers = list, keys, tierList
end

local function onTasksOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = buffer or ''
  local first = buffer:match('^[^\n]*')
  local h = split(first)

  if h[1] == 'CAT' then
    local part, total, version = tonumber(h[2]) or 1, tonumber(h[3]) or 1, h[4]
    if catWaiting ~= version then
      catParts, catWaiting = {}, version
    end
    catTotal = total
    local lines = {}
    for line in (buffer:sub(#first + 2) .. '\n'):gmatch('(.-)\n') do
      if line ~= '' then lines[#lines + 1] = line end
    end
    catParts[part] = lines
    for i = 1, catTotal do
      if not catParts[i] then return end
    end
    local all = {}
    for i = 1, catTotal do
      for _, l in ipairs(catParts[i]) do all[#all + 1] = l end
    end
    parseCatalog(all)
    catVersion, catParts, catWaiting, asked = version, {}, nil, false
    if window:isVisible() then refresh() end
    return
  end

  if h[1] ~= 'S' then return end
  local open = h[2] == '1'
  if not open and not window:isVisible() then return end
  state.atMural = h[3] == '1'
  state.active = tonumber(h[4]) or 0
  state.max = tonumber(h[5]) or 3
  state.total = tonumber(h[6]) or 0
  local version = h[7]
  local tasks, done = {}, {}
  local now = os.time()
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = split(line)
    if f[1] == 'A' then
      tasks[#tasks + 1] = { key = f[2] or '', progress = tonumber(f[3]) or 0, goal = tonumber(f[4]) or 1 }
    elseif f[1] == 'D' then
      done[f[2] or ''] = { times = tonumber(f[3]) or 0, wait = tonumber(f[4]) or 0, at = now }
    end
  end
  table.sort(tasks, function(a, b) return a.key < b.key end)
  state.tasks, state.done = tasks, done

  if version ~= catVersion and not asked then
    asked = true
    send('CAT')
  end
  if open and not window:isVisible() then
    fitScreen()
    window:show()
    window:raise()
    window:focus()
    if topButton then topButton:setOn(true) end
    -- veio do mural: com tasks ativas abre nelas, sem nenhuma abre o mural
    page = (#tasks == 0 and state.atMural) and 'board' or 'mine'
    setPage(page)
    return
  end
  refresh()
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
  cancelArmed = nil
  if topButton then topButton:setOn(false) end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

local function onGameEnd()
  if window then window:hide() end
  if topButton then topButton:setOn(false) end
  catalog, byKey, tiers, catVersion, asked = {}, {}, {}, nil, false
  catParts, catWaiting = {}, nil
  state = { open = false, atMural = false, active = 0, max = 3, total = 0, tasks = {}, done = {} }
end

function init()
  window = g_ui.displayUI('codextasks')
  window:hide()
  fitScreen()

  W('closeButton').onClick = function() hide() end
  W('tabMine').onClick = function() setPage('mine') end
  W('tabBoard').onClick = function() setPage('board') end
  W('prevButton').onClick = function() pageIndex = pageIndex - 1; refresh() end
  W('nextButton').onClick = function() pageIndex = pageIndex + 1; refresh() end
  W('searchEdit').onTextChange = function(self, text)
    searchText = text or ''
    pageIndex = 1
    if page == 'board' then refresh() end
  end
  W('hideDoneBox').onCheckChange = function(self, checked)
    onlyAvailable = checked
    pageIndex = 1
    if page == 'board' then refresh() end
  end
  if isPhone() then
    dragScroll(W('minePage'))
  end

  ProtocolGame.registerExtendedOpcode(OPCODE, onTasksOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, toggle)

  local ok, button = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton('codexTasksButton',
      'Tasks de abate (' .. HOTKEY .. ')', '/images/topbuttons/codex/pin', toggle)
  end)
  if ok then topButton = button end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown(HOTKEY)
  if cancelEvent then
    removeEvent(cancelEvent)
    cancelEvent = nil
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

