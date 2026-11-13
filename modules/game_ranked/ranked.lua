-- ============================================================
-- RANKED 1v1 (cliente) - opcode 115
-- Janela: Jogar (escolher 3 pokemons e buscar partida), Ranking e
-- Recompensas. Popup de partida encontrada, placar durante a luta
-- e resultado no fim. So envia pacotes a partir de cliques.
-- Abre pelo botao do topo ou com !ranked.
-- ============================================================

local OPCODE = 115
local IMG = '/modules/game_ranked/img/'
local BAR_WIDTH = 186 -- largura interna da barra de progresso (card 220 - margens)

local window, found, hud, finish = nil, nil, nil, nil
local topButton = nil
local info = nil
local team = {}
local picked = {}      -- slot -> ordem
local pickedOrder = {}
local teamSize = 3
local inQueue, queueSince = false, 0
local foundId, foundUntil = nil, 0
local tickEvent = nil
local forfeitArmed = false

local TIER_COLOR = { bronze = '#c98a4b', prata = '#c9d6e6', ouro = '#f2c400', platina = '#5fd3c4',
  diamante = '#7ab8ff', mestre = '#d07aff' }
local TIER_NAME = { bronze = 'Bronze', prata = 'Prata', ouro = 'Ouro', platina = 'Platina', diamante = 'Diamante', mestre = 'Mestre' }

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function W(root, id)
  return root and root:recursiveGetChildById(id) or nil
end

local function split(line, sep)
  sep = sep or '|'
  local out = {}
  for field in (line .. sep):gmatch('(.-)' .. (sep == '|' and '|' or sep)) do out[#out + 1] = field end
  return out
end

local function lines(buffer)
  local out = {}
  for line in (buffer .. '\n'):gmatch('(.-)\n') do out[#out + 1] = line end
  return out
end

local function emblem(key)
  return IMG .. (TIER_NAME[key] and key or 'bronze')
end

local function clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format('%d:%02d', math.floor(seconds / 60), seconds % 60)
end

local function longTime(seconds)
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  if d > 0 then return d .. 'd ' .. h .. 'h' end
  local m = math.floor((seconds % 3600) / 60)
  return h .. 'h ' .. m .. 'min'
end

local function thousands(n)
  local s = tostring(math.floor(n or 0))
  local out = s:reverse():gsub('(%d%d%d)', '%1.'):reverse()
  return (out:gsub('^%.', ''))
end

-- ------------------------------------------------------------
-- abas
-- ------------------------------------------------------------
local TABS = { play = { 'tabPlay', 'panelPlay' }, top = { 'tabTop', 'panelTop' }, rewards = { 'tabRewards', 'panelRewards' } }

local function showTab(name)
  for key, t in pairs(TABS) do
    W(window, t[1]):setOn(key == name)
    W(window, t[2]):setVisible(key == name)
  end
  if name == 'top' then send('TOP') end
  if name == 'rewards' then send('REWARDS') end
end

-- ------------------------------------------------------------
-- aba Jogar
-- ------------------------------------------------------------
local function updateSearch()
  if not window then return end
  local button, status = W(window, 'searchButton'), W(window, 'statusLabel')
  local count = #pickedOrder
  W(window, 'pickCount'):setText(count .. ' / ' .. teamSize)
  if info and info.rooms == 0 then
    button:setText('Arena em construcao')
    button:setEnabled(false)
    status:setText('A Ranked abre assim que as salas da arena estiverem prontas.')
    return
  end
  if info and info.state == 'match' then
    button:setText('Em partida')
    button:setEnabled(false)
    status:setText('')
    return
  end
  if inQueue then
    button:setText('Cancelar busca  (' .. clock(os.time() - queueSince) .. ')')
    button:setEnabled(true)
    status:setText('Procurando adversario do seu rank, um acima ou um abaixo...')
    status:setColor('#dce8f5')
  else
    button:setText('Buscar partida')
    button:setEnabled(count == teamSize)
    if count < teamSize then
      status:setText('Clique em ' .. teamSize .. ' pokemons da sua equipe para lutar.')
      status:setColor('#8fa7c4')
    else
      status:setText('Pronto! Fique em uma area protegida e clique em Buscar.')
      status:setColor('#5fd35f')
    end
  end
end

local function renderTeam()
  if not window then return end
  local grid = W(window, 'slots')
  grid:destroyChildren()
  -- mantem a escolha se os pokemons continuam na equipe e de pe
  local still = {}
  for _, p in ipairs(team) do still[p.slot] = p.alive end
  local order = {}
  for _, slot in ipairs(pickedOrder) do
    if still[slot] then order[#order + 1] = slot end
  end
  pickedOrder = order
  picked = {}
  for i, slot in ipairs(pickedOrder) do picked[slot] = i end

  for _, p in ipairs(team) do
    local card = g_ui.createWidget('RkPokeSlot', grid)
    pcall(function() card:getChildById('creature'):setOutfit({ type = p.look }) end)
    card:getChildById('name'):setText(p.name)
    card:getChildById('level'):setText(p.alive and ('Nv ' .. p.level) or 'desmaiado')
    card:getChildById('level'):setColor(p.alive and '#6f86a8' or '#e04848')
    local mark = card:getChildById('pick')
    if picked[p.slot] then
      card:setOn(true)
      mark:setText(tostring(picked[p.slot]))
      mark:setVisible(true)
    end
    card:setEnabled(p.alive and not inQueue)
    if not p.alive then card:setTooltip('Cure no Centro Pokemon para usar na Ranked') end
    card.onClick = function()
      if inQueue or not p.alive then return end
      if picked[p.slot] then
        for i, s in ipairs(pickedOrder) do
          if s == p.slot then table.remove(pickedOrder, i) break end
        end
      elseif #pickedOrder < teamSize then
        pickedOrder[#pickedOrder + 1] = p.slot
      end
      renderTeam()
    end
  end
  W(window, 'emptyTeam'):setVisible(#team == 0)
  updateSearch()
end

local function renderInfo()
  if not window or not info then return end
  W(window, 'seasonLabel'):setText('Temporada ' .. info.season .. '  -  termina em ' .. longTime(info.remaining))
  W(window, 'emblem'):setImageSource(emblem(info.tier))
  local tierName = W(window, 'tierName')
  tierName:setText(info.tierName:upper())
  tierName:setColor(TIER_COLOR[info.tier] or '#dce8f5')
  W(window, 'points'):setText(thousands(info.points) .. ' pontos')
  local fill = W(window, 'barFill')
  local nextLabel = W(window, 'nextLabel')
  local minHere = 0
  local mins = { bronze = 0, prata = 1000, ouro = 1500, platina = 2000, diamante = 2500, mestre = 3000 }
  minHere = mins[info.tier] or 0
  if info.nextMin > 0 then
    local pct = math.max(0, math.min(1, (info.points - minHere) / math.max(1, info.nextMin - minHere)))
    fill:setWidth(math.floor(BAR_WIDTH * pct))
    nextLabel:setText('faltam ' .. (info.nextMin - info.points) .. ' para o proximo rank')
  else
    fill:setWidth(BAR_WIDTH)
    nextLabel:setText('rank maximo!')
  end
  fill:setBackgroundColor(TIER_COLOR[info.tier] or '#f2c400')
  W(window, 'record'):setText(info.wins .. ' V   ' .. info.losses .. ' D   ' .. info.draws .. ' E')
  local total = info.wins + info.losses + info.draws
  W(window, 'winrate'):setText(total > 0 and (math.floor(info.wins * 100 / total) .. '% de vitorias') or 'nenhuma partida ainda')
  W(window, 'position'):setText(total > 0 and ('#' .. info.position .. ' no ranking') or '')
  W(window, 'rules'):setText(teamSize .. ' contra ' .. teamSize .. '  -  nivel real\nsem pocao e revive  -  ' .. info.minutes .. ' min')
  updateSearch()
end

-- ------------------------------------------------------------
-- ranking e recompensas
-- ------------------------------------------------------------
local function renderTop(buffer)
  local list = W(window, 'topList')
  list:destroyChildren()
  local count = 0
  local myName = g_game.getCharacterName and g_game.getCharacterName() or ''
  for _, line in ipairs(lines(buffer)) do
    local f = split(line)
    if f[1] == 'R' then
      count = count + 1
      local row = g_ui.createWidget('RkTopRow', list)
      row:getChildById('pos'):setText('#' .. f[2])
      row:getChildById('emblem'):setImageSource(emblem(f[5]))
      row:getChildById('name'):setText(f[3])
      row:getChildById('points'):setText(thousands(tonumber(f[4]) or 0))
      row:getChildById('points'):setColor(TIER_COLOR[f[5]] or '#dce8f5')
      row:getChildById('record'):setText((f[6] or 0) .. ' V  /  ' .. (f[7] or 0) .. ' D')
      row:setOn(f[3] == myName)
    end
  end
  W(window, 'topEmpty'):setVisible(count == 0)
end

local function renderRewards(buffer)
  local list = W(window, 'rewardList')
  list:destroyChildren()
  local tops = {}
  local minMatches = buffer:match('^REWARDS|(%d+)') or '10'
  for _, line in ipairs(lines(buffer)) do
    local f = split(line)
    if f[1] == 'W' then
      local row = g_ui.createWidget('RkRewardRow', list)
      row:getChildById('emblem'):setImageSource(emblem(f[2]))
      row:getChildById('tier'):setText(f[3])
      row:getChildById('tier'):setColor(TIER_COLOR[f[2]] or '#dce8f5')
      row:getChildById('min'):setText('a partir de ' .. thousands(tonumber(f[4]) or 0))
      row:getChildById('reward'):setText(f[5] ~= '' and f[5] or '-')
    elseif f[1] == 'T' then
      tops[#tops + 1] = f[2] .. 'o lugar: ' .. f[3]
    end
  end
  W(window, 'topRewards'):setText(#tops > 0 and table.concat(tops, '     ') or '-')
  W(window, 'rewardNote'):setText('Vale o rank em que voce TERMINAR a temporada. Precisa jogar pelo menos ' .. minMatches ..
    ' partidas. Na virada os pontos baixam (ex.: Diamante comeca a proxima no Ouro).')
end

-- ------------------------------------------------------------
-- popup / placar / resultado
-- ------------------------------------------------------------
local function hideFound()
  foundId = nil
  if found then found:hide() end
end

local function makeDots(panel, alive)
  panel:destroyChildren()
  for i = 1, teamSize do
    local dot = g_ui.createWidget('RkDot', panel)
    dot:setBackgroundColor(i <= alive and '#5fd35f' or '#3a4a60')
  end
end

local function showHud(myAlive, oppAlive, remaining, oppName, started, goIn)
  if not hud then return end
  hud:show()
  hud:raise()
  makeDots(hud:getChildById('myDots'), myAlive)
  makeDots(hud:getChildById('oppDots'), oppAlive)
  hud:getChildById('opp'):setText(oppName)
  local c = hud:getChildById('clock')
  if started then
    c:setText(clock(remaining))
    c:setColor(remaining <= 30 and '#e04848' or '#f2c400')
  else
    c:setText('Comeca em ' .. goIn)
    c:setColor('#5fd35f')
  end
end

local function showEnd(res, delta, points, tierKey, tierName, reason, changed)
  if hud then hud:hide() end
  if not finish then return end
  local title = finish:getChildById('result')
  if res == 'win' then
    title:setText('VITORIA!') title:setColor('#5fd35f')
  elseif res == 'loss' then
    title:setText('DERROTA') title:setColor('#e04848')
  else
    title:setText('EMPATE') title:setColor('#dce8f5')
  end
  local d = tonumber(delta) or 0
  local why = ({ tempo = '  (tempo esgotado)', fuga = '  (desistencia)', queda = '  (queda de conexao)' })[reason] or ''
  finish:getChildById('delta'):setText((d >= 0 and '+' or '') .. d .. ' pontos' .. why)
  finish:getChildById('emblem'):setImageSource(emblem(tierKey))
  finish:getChildById('info'):setText(thousands(tonumber(points) or 0) .. ' pontos  -  ' .. tierName ..
    (changed == '1' and (d > 0 and '  (subiu!)' or '  (caiu)') or ''))
  finish:show()
  finish:raise()
  finish:focus()
end

-- ------------------------------------------------------------
-- relogio local (fila e popup)
-- ------------------------------------------------------------
local function tick()
  tickEvent = nil
  if inQueue then updateSearch() end
  if foundId and found and found:isVisible() then
    local left = foundUntil - os.time()
    found:getChildById('timer'):setText('Aceite em ' .. math.max(0, left) .. 's')
  end
  if inQueue or foundId then tickEvent = scheduleEvent(tick, 1000) end
end

local function startTick()
  if not tickEvent then tickEvent = scheduleEvent(tick, 1000) end
end

-- ------------------------------------------------------------
-- pacotes do servidor
-- ------------------------------------------------------------
local function onOpcode(protocol, opcode, buffer)
  buffer = buffer or ''
  local head = buffer:match('^([^|\n]*)')
  if head == 'OPEN' then
    window:show()
    window:raise()
    window:focus()
    showTab('play')
  elseif head == 'INFO' then
    local f = split(buffer)
    info = { season = tonumber(f[2]) or 1, remaining = tonumber(f[3]) or 0, points = tonumber(f[4]) or 0, tier = f[5] or 'bronze',
      tierName = f[6] or '', nextMin = tonumber(f[7]) or 0, wins = tonumber(f[8]) or 0, losses = tonumber(f[9]) or 0,
      draws = tonumber(f[10]) or 0, position = tonumber(f[11]) or 0, state = f[12] or 'idle', queueSecs = tonumber(f[13]) or 0,
      rooms = tonumber(f[14]) or 0, minutes = tonumber(f[16]) or 5 }
    teamSize = tonumber(f[15]) or 3
    inQueue = info.state == 'queue'
    if inQueue then queueSince = os.time() - info.queueSecs startTick() end
    renderInfo()
    renderTeam()
  elseif head == 'TEAM' then
    team = {}
    for _, line in ipairs(lines(buffer)) do
      local f = split(line)
      if f[1] == 'K' then
        team[#team + 1] = { slot = tonumber(f[2]) or 0, name = f[3] or '?', level = tonumber(f[4]) or 0, alive = f[5] == '1',
          look = tonumber(f[6]) or 0 }
      end
    end
    renderTeam()
  elseif head == 'TOP' then
    renderTop(buffer)
  elseif head == 'REWARDS' then
    renderRewards(buffer)
  elseif head == 'QUEUE' then
    inQueue = buffer == 'QUEUE|1'
    if inQueue then queueSince = os.time() startTick() end
    renderTeam()
  elseif head == 'ERR' then
    local status = W(window, 'statusLabel')
    if status then
      status:setText(buffer:sub(5))
      status:setColor('#e04848')
    end
  elseif head == 'FOUND' then
    local f = split(buffer)
    foundId = f[2]
    foundUntil = os.time() + (tonumber(f[6]) or 15)
    inQueue = false
    found:getChildById('title'):setText('PARTIDA ENCONTRADA!')
    found:getChildById('emblem'):setImageSource(emblem(f[5]))
    found:getChildById('opponent'):setText('contra ' .. (f[3] or '?') .. '  -  ' .. (TIER_NAME[f[5]] or '') .. ' ' ..
      thousands(tonumber(f[4]) or 0))
    found:getChildById('acceptButton'):setEnabled(true)
    found:getChildById('acceptButton'):setText('Aceitar')
    found:show()
    found:raise()
    found:focus()
    pcall(function() g_window.flash() end)
    startTick()
  elseif head == 'ACCEPTED' then
    if found then
      found:getChildById('acceptButton'):setEnabled(false)
      found:getChildById('acceptButton'):setText('Esperando...')
    end
  elseif head == 'CANCEL' then
    hideFound()
  elseif head == 'START' then
    hideFound()
    inQueue = false
    forfeitArmed = false
    if window then window:hide() end
    if hud then hud:getChildById('forfeitButton'):setText('Desistir') end
  elseif head == 'SCORE' then
    local f = split(buffer)
    showHud(tonumber(f[3]) or 0, tonumber(f[4]) or 0, tonumber(f[5]) or 0, f[6] or '', f[7] == '1', tonumber(f[8]) or 0)
  elseif head == 'END' then
    local f = split(buffer)
    showEnd(f[3], f[4], f[5], f[6], f[7] or '', f[8] or '', f[9])
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
    send('OPEN')
  end
end

local function onGameEnd()
  if window then window:hide() end
  hideFound()
  if hud then hud:hide() end
  if finish then finish:hide() end
  inQueue = false
  info = nil
end

function init()
  g_ui.importStyle('ranked')
  window = g_ui.createWidget('RankedWindow', rootWidget)
  window:hide()
  found = g_ui.createWidget('RankedFound', rootWidget)
  found:hide()
  finish = g_ui.createWidget('RankedEnd', rootWidget)
  finish:hide()
  local mapPanel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel() or rootWidget
  hud = g_ui.createWidget('RankedHud', mapPanel)
  hud:addAnchor(AnchorTop, 'parent', AnchorTop)
  hud:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  hud:setMarginTop(8)
  hud:hide()

  W(window, 'closeButton').onClick = function() window:hide() end
  W(window, 'tabPlay').onClick = function() showTab('play') end
  W(window, 'tabTop').onClick = function() showTab('top') end
  W(window, 'tabRewards').onClick = function() showTab('rewards') end
  W(window, 'topRefresh').onClick = function() send('TOP') end
  W(window, 'searchButton').onClick = function()
    if inQueue then
      send('LEAVE')
    elseif #pickedOrder == teamSize then
      send('JOIN|' .. table.concat(pickedOrder, ','))
    end
  end
  found:getChildById('acceptButton').onClick = function() if foundId then send('ACCEPT|' .. foundId) end end
  found:getChildById('declineButton').onClick = function()
    if foundId then send('DECLINE|' .. foundId) end
    hideFound()
  end
  finish:getChildById('okButton').onClick = function() finish:hide() end
  hud:getChildById('forfeitButton').onClick = function(self)
    if forfeitArmed then
      forfeitArmed = false
      send('FORFEIT')
      return
    end
    forfeitArmed = true
    self:setText('Confirmar?')
    scheduleEvent(function()
      if forfeitArmed and not self:isDestroyed() then
        forfeitArmed = false
        self:setText('Desistir')
      end
    end, 3000)
  end

  local topmenu = modules.client_topmenu
  local ok, button = pcall(function()
    return topmenu.addRightGameToggleButton('rankedButton', 'Ranked 1v1 (!ranked)', '/images/topbuttons/codex/ranked', toggle)
  end)
  if ok and button then topButton = button end

  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if topButton then pcall(function() topButton:destroy() end) topButton = nil end
  for _, w in ipairs({ window, found, hud, finish }) do
    if w then w:destroy() end
  end
  window, found, hud, finish = nil, nil, nil, nil
end
