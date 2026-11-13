-- ============================================================
-- CRECHE POKEMON (cliente) - opcode 85
-- Abre pelo NPC Creche (completa) ou por !ovos (so os ovos).
-- So envia opcodes a partir de cliques do jogador.
-- ============================================================

local OPCODE = 85
local POKE_ICON = '/modules/game_pokemonbar/bar_icon/'
local STAR = '/modules/game_pokeinfo/images/'
local EGGS = '/modules/game_daycare/eggs/'
local GENDER_IMG = { M = 'male', F = 'female', N = 'none' }
local IV_NAMES = { 'HP', 'ATK', 'DEF', 'SpA', 'SpD', 'VEL' }
local TYPE_PT = {
  bug = 'Inseto', dark = 'Sombrio', dragon = 'Dragao', electric = 'Eletrico', fairy = 'Fada', fighting = 'Lutador',
  fire = 'Fogo', flying = 'Voador', ghost = 'Fantasma', grass = 'Planta', ground = 'Terra', ice = 'Gelo',
  normal = 'Normal', poison = 'Veneno', psychic = 'Psiquico', rock = 'Pedra', steel = 'Aco', water = 'Agua',
}

local window = nil
local pendingParts = {}
local state = { npc = false, can = false, reason = '', left = -1, total = 86400, eggs = 0, maxEggs = 6, fee = 0,
  npairs = 1, maxPairs = 1, unlockText = '', donate = 0 }
local pairs_ = {}          -- [casal] = { can, reason, left }
local accels = {}          -- { index, name, seconds, clientId, count }
local selPair = 1
local lastBuffer = nil
local unlockArmed = false
local prices = {}          -- [casal] = '20 Donate' 
local timerEvent = nil

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do fields[#fields + 1] = field end
  return fields
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

local function typesText(t1, t2)
  local a, b = TYPE_PT[t1], TYPE_PT[t2]
  if not a then return '' end
  return a .. (b and ('/' .. b) or '')
end

local function setStars(box, stars, pct)
  box:destroyChildren()
  for i = 1, 5 do
    local star = g_ui.createWidget('DayStar', box)
    if i <= stars then star:setImageSource(STAR .. (pct >= 100 and 'star_perfect' or 'star')) end
  end
end

local function clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  local h, m, s = math.floor(seconds / 3600), math.floor(seconds % 3600 / 60), seconds % 60
  if h > 0 then return string.format('%dh %02dm', h, m) end
  return string.format('%02d:%02d', m, s)
end

-- ------------------------------------------------------------
-- parse: T/D = name|level|sexo|iv%|estrelas|boost|ivs|tipo1|tipo2|natureza
-- ------------------------------------------------------------
local function pokeFields(f, start)
  return {
    name = f[start] or '?', level = tonumber(f[start + 1]) or 1, gender = f[start + 2] or 'N',
    pct = tonumber(f[start + 3]) or 0, stars = tonumber(f[start + 4]) or 1, boost = tonumber(f[start + 5]) or 0,
    ivs = f[start + 6] or '', t1 = f[start + 7] or '', t2 = f[start + 8] or '', nature = f[start + 9] or '',
  }
end

local function updateTimer()
  local label, fill, back = W('timerLabel'), W('timerFill'), W('timerBack')
  if not label then return end
  local width = math.max(0, back:getWidth() - 2)
  if not state.can or state.left < 0 then
    label:setText(state.npc and 'Deixe um casal compativel para fazer ovos.' or '')
    fill:setWidth(0)
    W('collectButton'):setEnabled(false)
    return
  end
  local ready = state.left <= 0
  if ready then
    label:setText('Tem um ovo pronto!')
    label:setColor('#5fd35f')
    fill:setWidth(width)
    fill:setBackgroundColor('#5fd35f')
  else
    label:setText('Ovo do casal ' .. selPair .. ' em ' .. clock(state.left))
    label:setColor('#8fa7c4')
    fill:setWidth(math.floor(width * (1 - state.left / math.max(1, state.total))))
    fill:setBackgroundColor('#f2c400')
  end
  local full = state.maxEggs > 0 and state.eggs >= state.maxEggs
  W('collectButton'):setEnabled(state.npc and ready and not full)
  W('collectButton'):setText(full and ('Voce ja tem ' .. state.maxEggs .. ' ovos') or
    (state.fee > 0 and ('Pegar ovo (' .. fmt(state.fee) .. ' gp)') or 'Pegar ovo'))
end

local function tick()
  timerEvent = nil
  if not window or not window:isVisible() then return end
  for _, pr in pairs(pairs_) do
    if pr.left > 0 then pr.left = pr.left - 1 end
  end
  local cur = pairs_[selPair]
  if cur then state.left = cur.left end
  updateTimer()
  timerEvent = scheduleEvent(tick, 1000)
end

local function fillSlot(slotWidget, index, poke)
  local has = poke ~= nil
  for _, id in ipairs({ 'name', 'gender', 'info', 'stars', 'ivLabel', 'ivPanel', 'actionButton' }) do
    slotWidget:getChildById(id):setVisible(has)
  end
  slotWidget:getChildById('empty'):setVisible(not has)
  slotWidget:getChildById('portrait'):setVisible(has)
  slotWidget:setBorderColor(has and '#24415f' or '#1d3557')
  if not has then return end
  slotWidget:getChildById('portrait'):setImageSource(pokeIcon(poke.name))
  slotWidget:getChildById('name'):setText(poke.name)
  slotWidget:getChildById('gender'):setImageSource(STAR .. (GENDER_IMG[poke.gender] or 'none'))
  local info = 'Lv ' .. poke.level .. '  |  ' .. typesText(poke.t1, poke.t2)
  if poke.nature ~= '' then info = info .. '  |  ' .. poke.nature end
  slotWidget:getChildById('info'):setText(info)
  setStars(slotWidget:getChildById('stars'), poke.stars, poke.pct)
  slotWidget:getChildById('ivLabel'):setText('IV ' .. poke.pct .. '%' .. (poke.pct >= 100 and '  PERFEITO' or ''))
  local panel = slotWidget:getChildById('ivPanel')
  panel:destroyChildren()
  local i = 0
  for value in poke.ivs:gmatch('(%d+)') do
    i = i + 1
    local bar = g_ui.createWidget('DayIvBar', panel)
    local v = tonumber(value) or 0
    bar:getChildById('label'):setText(IV_NAMES[i] or '?')
    bar:getChildById('value'):setText(tostring(v))
    bar:getChildById('value'):setColor(v >= 31 and '#f2c400' or '#dce8f5')
    local fill = bar:getChildById('fill')
    fill:setWidth(math.floor(v / 31 * 92))
    fill:setBackgroundColor(v >= 31 and '#f2c400' or (v >= 20 and '#5fd35f' or (v >= 10 and '#e8c050' or '#e04848')))
  end
  local button = slotWidget:getChildById('actionButton')
  button:setEnabled(state.npc)
  button.onClick = function() send('WD|' .. index) end
end

local render

local function styleTab(button, active, locked)
  button:setColor(active and '#1a1200' or (locked and '#6f86a8' or '#dce8f5'))
  button:setBackgroundColor(active and '#f2c400' or '#101f3e')
  button:setBorderColor(active and '#ffe27a' or '#24415f')
end

local function renderPairs(care, team)
  local bar = W('pairBar')
  bar:destroyChildren()
  for p = 1, state.maxPairs do
    local tab = g_ui.createWidget('DayPairTab', bar)
    local locked = p > state.npairs
    local pr = pairs_[p]
    local ready = pr and pr.can and pr.left == 0
    tab:setText((locked and 'x ' or '') .. 'Casal ' .. p .. (ready and ' !' or ''))
    tab:setWidth(math.floor((W('carePanel'):getWidth() - 16 - (state.maxPairs - 1) * 4) / state.maxPairs))
    styleTab(tab, p == selPair, locked)
    tab:setTooltip(locked and ('Bloqueado. Liberar custa ' .. (prices[p] or state.unlockText) .. '.') or (pr and pr.reason or ''))
    tab.onClick = function()
      selPair = p
      unlockArmed = false
      if lastBuffer then render(lastBuffer) end
    end
  end
  -- casal bloqueado
  local locked = selPair > state.npairs
  for _, id in ipairs({ 'lockPanel', 'lockText', 'unlockButton' }) do W(id):setVisible(locked) end
  W('slot1'):setVisible(not locked)
  W('slot2'):setVisible(not locked)
  if locked then
    local nextOne = selPair == state.npairs + 1
    W('lockText'):setText(nextOne and ('Casal ' .. selPair .. ' bloqueado') or ('Libere o casal ' .. (state.npairs + 1) .. ' antes'))
    local button = W('unlockButton')
    local price = prices[selPair] or state.unlockText
    button:setText(unlockArmed and ('Confirmar: ' .. price) or ('Liberar por ' .. price))
    button:setEnabled(state.npc and nextOne)
    button.onClick = function()
      if not unlockArmed then
        unlockArmed = true
        button:setText('Confirmar: ' .. price)
        return
      end
      unlockArmed = false
      send('UNLOCK|' .. selPair)
    end
  end
  W('walletLabel'):setText(fmt(state.donate))
  W('walletLabel'):setTooltip('Seu saldo de Donate')
end

local function renderAccels()
  local panel = W('accelPanel')
  panel:destroyChildren()
  local pr = pairs_[selPair]
  local running = pr and pr.can and pr.left > 0 and selPair <= state.npairs
  for _, acc in ipairs(accels) do
    local b = g_ui.createWidget('DayAccel', panel)
    if acc.clientId > 0 then b:setItemId(acc.clientId) end
    b:getChildById('count'):setText(acc.count > 0 and ('x' .. acc.count) or '0')
    local usable = state.npc and running and acc.count > 0
    b:setOpacity(usable and 1 or 0.45)
    b:setTooltip(acc.name .. (acc.seconds < 0 and ' (ovo pronto na hora)' or '') ..
      '\nVoce tem: ' .. acc.count .. (running and '' or '\n(so funciona com o casal cruzando)'))
    b.onClick = function()
      if usable then send('ACCEL|' .. selPair .. '|' .. acc.index) end
      return true
    end
  end
end

render = function(buffer)
  lastBuffer = buffer
  local team, care, eggs = {}, {}, {}
  pairs_, accels, prices = {}, {}, {}
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'STATE' then
      -- STATE|npc|casais|max|preco|ovos|maxOvos|taxa|tempo|gold|pokecoins|donate
      state.npc = f[2] == '1'
      state.npairs = tonumber(f[3]) or 1
      state.maxPairs = tonumber(f[4]) or 1
      state.unlockText = f[5] or ''
      state.eggs = tonumber(f[6]) or 0
      state.maxEggs = tonumber(f[7]) or 6
      state.fee = tonumber(f[8]) or 0
      state.total = tonumber(f[9]) or 86400
      state.donate = tonumber(f[12]) or 0
    elseif f[1] == 'P' then
      prices[tonumber(f[2]) or 0] = f[3] or ''
    elseif f[1] == 'C' then
      pairs_[tonumber(f[2]) or 0] = { can = f[3] == '1', reason = f[4] or '', left = tonumber(f[5]) or -1 }
    elseif f[1] == 'A' then
      accels[#accels + 1] = { index = tonumber(f[2]) or 0, name = f[3] or '?', seconds = tonumber(f[4]) or 0,
        clientId = tonumber(f[5]) or 0, count = tonumber(f[6]) or 0 }
    elseif f[1] == 'T' then
      local poke = pokeFields(f, 3)
      poke.slot = tonumber(f[2]) or 0
      poke.busy = f[13] == '1'
      team[#team + 1] = poke
    elseif f[1] == 'D' then
      care[tonumber(f[2]) or 0] = pokeFields(f, 3)
    elseif f[1] == 'E' then
      eggs[#eggs + 1] = { id = f[2] or '', species = f[3] or '?', t1 = f[4] or '', steps = tonumber(f[5]) or 0,
        need = tonumber(f[6]) or 1, pct = tonumber(f[7]) or 0, stars = tonumber(f[8]) or 1, gender = f[9] or 'N',
        clientId = tonumber(f[10]) or 0 }
    end
  end

  if selPair > state.maxPairs then selPair = 1 end
  local cur = pairs_[selPair] or { can = false, reason = '', left = -1 }
  state.can, state.reason, state.left = cur.can, cur.reason, cur.left
  W('subtitleLabel'):setText(state.npc and 'Deixe um macho e uma femea (ou um Ditto) e volte para pegar o ovo.' or
    'Seus ovos. Para deixar ou retirar pokemons, fale com o NPC Creche.')
  W('footerHint'):setText('Filhote nasce da especie da mae (forma inicial) e herda o melhor IV dos pais. Pais perfeitos = ovo perfeito. Diga !ovos em qualquer lugar.')

  -- equipe
  local list = W('teamList')
  list:destroyChildren()
  local s1, s2 = selPair * 2 - 1, selPair * 2
  local careFull = (care[s1] ~= nil and care[s2] ~= nil) or selPair > state.npairs
  for _, poke in ipairs(team) do
    local row = g_ui.createWidget('DayTeamRow', list)
    row:getChildById('portrait'):setImageSource(pokeIcon(poke.name))
    row:getChildById('name'):setText(poke.name .. '  Lv ' .. poke.level)
    row:getChildById('gender'):setImageSource(STAR .. (GENDER_IMG[poke.gender] or 'none'))
    setStars(row:getChildById('stars'), poke.stars, poke.pct)
    row:getChildById('sub'):setText(typesText(poke.t1, poke.t2) .. '  |  IV ' .. poke.pct .. '%' .. (poke.boost > 0 and ('  |  +' .. poke.boost) or ''))
    local button = row:getChildById('actionButton')
    button:setEnabled(state.npc and not careFull and not poke.busy and #team > 1)
    if poke.busy then
      button:setText('Fora')
      row:setTooltip('Recolha o pokemon para deixar na Creche.')
    end
    button.onClick = function() send('DEP|' .. poke.slot .. '|' .. selPair) end
  end
  if #team == 0 then
    W('teamTitle'):setText('SUA EQUIPE (vazia)')
  else
    W('teamTitle'):setText('SUA EQUIPE')
  end

  -- creche
  fillSlot(W('slot1'), s1, care[s1])
  fillSlot(W('slot2'), s2, care[s2])
  local status = W('statusLabel')
  status:setText(selPair > state.npairs and '' or state.reason)
  status:setColor(state.can and '#5fd35f' or ((care[s1] or care[s2]) and '#e04848' or '#8fa7c4'))
  renderPairs(care, team)
  renderAccels()

  -- ovos
  local eggList = W('eggList')
  eggList:destroyChildren()
  for _, egg in ipairs(eggs) do
    local row = g_ui.createWidget('DayEggRow', eggList)
    if egg.clientId > 0 then
      -- o proprio item do ovo (elemento) + o pokemon que esta dentro no canto
      row:getChildById('eggItem'):setItemId(egg.clientId)
      row:getChildById('egg'):hide()
    else
      local img = EGGS .. (egg.t1 ~= '' and egg.t1 or 'unknown') .. '.png'
      if not g_resources.fileExists(img) then img = EGGS .. 'unknown.png' end
      row:getChildById('egg'):setImageSource(img)
    end
    row:getChildById('poke'):setImageSource(pokeIcon(egg.species))
    local sexText = egg.gender == 'M' and ' (macho)' or (egg.gender == 'F' and ' (femea)' or '')
    row:getChildById('name'):setText('Ovo de ' .. egg.species .. sexText)
    local ready = egg.steps >= egg.need
    local back, fill = row:getChildById('back'), row:getChildById('fill')
    local ratio = math.min(1, egg.steps / math.max(1, egg.need))
    fill:setWidth(math.floor(ratio * 150))
    fill:setBackgroundColor(ready and '#5fd35f' or '#f2c400')
    row:getChildById('sub'):setText(ready and 'Pronto! Use o ovo ou clique em Chocar.' or (fmt(egg.steps) .. ' / ' .. fmt(egg.need) .. ' passos'))
    row:getChildById('sub'):setColor(ready and '#5fd35f' or '#8fa7c4')
    row:setTooltip(egg.species .. sexText .. '\nOvo de ' .. (TYPE_PT[egg.t1] or '?') .. '  |  IV ' .. egg.pct .. '%' ..
      (egg.pct >= 100 and ' (PERFEITO)' or '') .. '\nO ovo fica na sua mochila e choca andando.')
    if egg.pct >= 100 then row:setBorderColor('#f2c400') end
    local button = row:getChildById('hatchButton')
    button:setEnabled(ready)
    button.onClick = function() send('HATCH|' .. egg.id) end
    -- largura real da barra depois do layout
    scheduleEvent(function()
      if fill and not fill:isDestroyed() and back and not back:isDestroyed() then
        fill:setWidth(math.floor(ratio * math.max(0, back:getWidth() - 2)))
      end
    end, 50)
  end
  W('eggTitle'):setText(state.maxEggs > 0 and ('OVOS NA MOCHILA (' .. #eggs .. '/' .. state.maxEggs .. ')') or ('OVOS NA MOCHILA (' .. #eggs .. ')'))
  updateTimer()
  if not timerEvent then timerEvent = scheduleEvent(tick, 1000) end
end

local function onDaycareOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = joinParts(buffer or '')
  if not buffer then return end
  local head = buffer:match('^([^|\n]*)')
  if head == 'OPEN' then
    window:show()
    window:raise()
    window:focus()
  elseif head == 'STATE' then
    render(buffer)
  elseif head == 'CLOSE' then
    hide(true)
  end
end

function hide(fromServer)
  if window and window:isVisible() then
    window:hide()
    if not fromServer then send('CLOSE') end
  end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
end

local function onGameEnd()
  if window then window:hide() end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
end

function init()
  window = g_ui.displayUI('daycare')
  window:hide()
  W('closeButton').onClick = function() hide() end
  W('collectButton').onClick = function() send('COLLECT|' .. selPair) end
  ProtocolGame.registerExtendedOpcode(OPCODE, onDaycareOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if timerEvent then removeEvent(timerEvent) end
  if window then
    window:destroy()
    window = nil
  end
end
