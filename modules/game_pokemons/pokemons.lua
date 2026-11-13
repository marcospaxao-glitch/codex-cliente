-- ============================================================
-- POKEMONS - equipe de 6 Pokemons em slots fixos
-- Servidor: data/lib/poketeam.lua (opcode 91)
--
-- * Clique em um slot para selecionar; clique em outro para trocar
--   os dois de posicao (funciona tambem com slot vazio).
-- * Duplo clique usa/recolhe o Pokemon.
-- * Arraste uma ball do deposito (CP) para um slot para coloca-la
--   na equipe.
-- * Cada card mostra a ball REAL (item do container da equipe). Qualquer
--   item com "Usar com" (revive, pocao, tera, equipavel...) funciona
--   clicando nela, usando o action que ja existe no servidor.
--   O container da equipe e aberto de forma invisivel pelo cliente.
-- ============================================================

-- texto direto (sem passar pelo sistema de traducao, evita spam no log)
local function T(text, ...)
  if select('#', ...) > 0 then
    return string.format(text, ...)
  end
  return text
end

local OPCODE = 91
local TEAM_SLOT = 4 -- slot body no servidor (PokeTeam.SLOT)
local SIZE = 6
local PORTRAIT_PATH = '/modules/game_pokemonbar/bar_icon/'

local window = nil
local compact = false        -- true nos modos compacto e horizontal
local mode = 'full'          -- 'full' | 'compact' | 'horizontal' (salvo por player)
local MODE_NEXT = {full = 'compact', compact = 'horizontal', horizontal = 'full'}
local MODE_NAME = {full = 'Completo', compact = 'Compacto', horizontal = 'Horizontal'}
local LOOK_FALLBACK = {}
local slotsPanel = nil
local cards = {}
local team = {}
local enabled = true
local selected = nil
local teamContainer = nil   -- container da equipe aberto (escondido)
local openRequested = 0     -- evita abrir a equipe varias vezes seguidas
local reqEvent = nil

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, text)
  end
end

local function splitLines(buffer)
  local lines = {}
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then
      lines[#lines + 1] = line
    end
  end
  return lines
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    fields[#fields + 1] = field
  end
  return fields
end

local function hpColor(percent)
  if percent > 50 then
    return '#5fd35f'
  elseif percent > 20 then
    return '#f2c400'
  end
  return '#e04848'
end

local function setHint(text)
  if window then
    window:getChildById('hintLabel'):setText(text)
  end
end

local function defaultHint()
  if not enabled then
    setHint(T('A equipe ainda nao foi ativada no servidor.'))
  elseif selected then
    setHint(T('Slot %d selecionado. Clique em outro slot para trocar de posicao.', selected))
  else
    setHint(T('Clique para selecionar, duplo clique para usar. Use itens (revive, pocao...) direto na ball do card.'))
  end
end

-- ============================================================
-- Container da equipe (slot body) aberto sem janela
-- ============================================================
local function getTeamBag()
  local player = g_game.getLocalPlayer()
  return player and player:getInventoryItem(TEAM_SLOT) or nil
end

-- a equipe: container aberto por nos (id guardado). Comparar so o id do item
-- confundia com outra mochila do mesmo tipo e escondia a mochila do player.
local expectedTeamId = nil
local function isTeamContainer(container)
  local bag = getTeamBag()
  local containerItem = container and container:getContainerItem()
  if not bag or not containerItem or containerItem:getId() ~= bag:getId() then return false end
  if expectedTeamId ~= nil then return container:getId() == expectedTeamId end
  local player = g_game.getLocalPlayer()
  local backpack = player and player:getInventoryItem(InventorySlotBack or 3)
  if backpack and backpack:getId() == bag:getId() then return false end
  return true
end

local function hideContainerWindow(container)
  local function doHide()
    if container.window and container.window:isVisible() then
      container.window:hide()
    end
  end
  doHide()
  scheduleEvent(doHide, 50) -- caso o game_containers mostre depois
end

-- Abre a equipe escondida. So pode ser chamado a partir de uma acao do
-- jogador (clique/atalho): a protecao anti-bot do cliente cancela
-- g_game.open vindo de pacote do servidor ou de timer.
local function ensureTeamOpen(fromUser)
  if not enabled or not g_game.isOnline() then return end
  if teamContainer then return end
  for _, container in pairs(g_game.getContainers()) do
    if isTeamContainer(container) then
      teamContainer = container
      hideContainerWindow(container)
      return
    end
  end
  if not fromUser then return end
  local bag = getTeamBag()
  if not bag then
    g_logger.info('[Pokemons] Equipe (slot 4) nao encontrada no inventario.')
    return
  end
  if g_clock.millis() - openRequested > 1000 then
    openRequested = g_clock.millis()
    g_logger.info('[Pokemons] Abrindo a equipe (item ' .. bag:getId() .. ').')
    local cid = g_game.open(bag, nil)
    if type(cid) == 'number' then expectedTeamId = cid end
  end
end

local function getRealBall(data)
  if not teamContainer or not data or not data.bagIndex or data.bagIndex < 0 then
    return nil
  end
  return teamContainer:getItem(data.bagIndex)
end

-- slot do card a partir de um item que ja esta no container da equipe
local function slotOfTeamItem(item)
  if not teamContainer then return nil end
  local pos = item:getPosition()
  if not pos or pos.x ~= 65535 or pos.y ~= 64 + teamContainer:getId() then
    return nil
  end
  for slot = 1, SIZE do
    if team[slot] and team[slot].bagIndex == pos.z then
      return slot
    end
  end
  return nil
end

-- Genes: sexo, estrelas (IV) e etiquetas no card
local GENES_IMG = '/modules/game_pokeinfo/images/'
local GENES_GENDER = { M = 'male', F = 'female', N = 'none' }
local GENES_TAG_COLOR = { Shiny = '#ffd84a', Mega = '#c890ff', Tera = '#5fe0ff', Lendario = '#ff9a3c' }
local function fillGenes(card, data)
  local gender, box, tags = card:getChildById('genderIcon'), card:getChildById('starsBox'), card:getChildById('tagsLabel')
  if not gender or not box or not tags then return end
  local has = data ~= nil and (data.ivPct or -1) >= 0
  gender:setVisible(data ~= nil)
  box:setVisible(has)
  tags:setVisible(data ~= nil)
  box:destroyChildren()
  if not data then return end
  gender:setImageSource(GENES_IMG .. (GENES_GENDER[data.gender] or 'none'))
  if has then
    for i = 1, 5 do
      local star = g_ui.createWidget('UIWidget', box)
      star:setSize({ width = 11, height = 11 })
      star:setPhantom(true)
      star:setImageSource(GENES_IMG .. (i <= data.stars and (data.ivPct >= 100 and 'star_perfect' or 'star') or 'star_off'))
    end
  end
  local words = {}
  for name in (data.tags or ''):gmatch('[^,]+') do words[#words + 1] = name end
  if (data.boost or 0) > 0 then table.insert(words, 1, '+' .. data.boost) end
  tags:setText(table.concat(words, ' '))
  tags:setColor(GENES_TAG_COLOR[words[#words] or ''] or '#f2c400')
end

local function refreshCards()
  local count = 0
  for slot = 1, SIZE do
    local card = cards[slot]
    local data = team[slot]
    card:getChildById('slotLabel'):setText(compact and tostring(slot) or T('Slot %d', slot))

    local portrait = card:getChildById('portrait')
    local nameLabel = card:getChildById('nameLabel')
    local levelLabel = card:getChildById('levelLabel')
    local hpBar = card:getChildById('hpBar')
    local statusLabel = card:getChildById('statusLabel')
    local emptyLabel = card:getChildById('emptyLabel')
    local ballSlot = card:getChildById('ballSlot')

    if data then
      count = count + 1
      -- sprite do Pokemon (igual a Pokedex); sem sprite usa a imagem antiga
      local creature = card:getChildById('creature')
      local bar = modules.game_pokemonbar
      local look = bar and bar.getLook and bar.getLook(data.name) or nil
      if creature and look then
        creature:setOutfit(look)
        creature:setOpacity(data.health <= 0 and 0.4 or 1)
        creature:setVisible(true)
        portrait:setImageSource('')
      else
        if creature then creature:setVisible(false) end
        local path = PORTRAIT_PATH .. data.name:lower() .. '.png'
        if data.name:lower():sub(1, 5) == 'mega ' and not g_resources.fileExists(path) then
          path = PORTRAIT_PATH .. data.name:lower():sub(6):gsub(' [xy]$', '') .. '.png'
        end
        portrait:setImageSource(g_resources.fileExists(path) and path or '')
      end
      portrait:setVisible(true)
      nameLabel:setText(data.name)
      nameLabel:setVisible(true)
      levelLabel:setText(T('Nivel %d', data.level))
      levelLabel:setVisible(mode ~= 'horizontal')

      local percent = 0
      if data.maxHealth > 0 then
        percent = math.max(0, math.min(100, math.floor(data.health * 100 / data.maxHealth)))
      end
      hpBar:setPercent(percent)
      hpBar:setBackgroundColor(hpColor(percent))
      hpBar:setTooltip(T('HP: %d / %d', data.health, data.maxHealth))
      hpBar:setVisible(true)

      if data.inUse then
        statusLabel:setText(T('EM USO'))
        statusLabel:setColor('#5fd35f')
      elseif data.health <= 0 then
        statusLabel:setText(T('DESMAIADO'))
        statusLabel:setColor('#e04848')
      else
        statusLabel:setText('')
      end
      emptyLabel:setText('')
      card:setTooltip(data.name .. ' - ' .. T('Nivel %d', data.level) ..
        ((data.ivPct or -1) >= 0 and ('\nIV ' .. data.ivPct .. '% (' .. data.stars .. ' estrelas)') or ''))
      fillGenes(card, data)

      local realBall = getRealBall(data)
      if realBall and realBall:getId() == data.ballClientId then
        ballSlot:setItem(realBall)
        ballSlot:setVirtual(false)
        ballSlot:setPhantom(false)
        ballSlot:setBorderColor('#f2c400')
        ballSlot:setTooltip(T('Ball de %s. Use itens aqui (Usar com).', data.name))
      else
        -- sem a ball real o "Usar com" acertaria outro item: bloqueia
        ballSlot:setItemId(data.ballClientId)
        ballSlot:setVirtual(true)
        ballSlot:setPhantom(true)
        ballSlot:setBorderColor('#4a5f7a')
        ballSlot:setTooltip(T('Clique no card para carregar a ball.'))
      end
      ballSlot:setVisible(true)
    else
      portrait:setVisible(false)
      if card:getChildById('creature') then card:getChildById('creature'):setVisible(false) end
      nameLabel:setVisible(false)
      levelLabel:setVisible(false)
      hpBar:setVisible(false)
      statusLabel:setText('')
      ballSlot:setVisible(false)
      emptyLabel:setText(T('Vazio'))
      fillGenes(card, nil)
      card:setTooltip(T('Slot vazio. Arraste uma ball do CP para ca.'))
    end

    if selected == slot then
      card:setBorderColor('#f2c400')
      card:setBorderWidth(2)
    else
      -- borda verde = em uso, vermelha = desmaiado (no horizontal o texto nao cabe)
      local d = team[slot]
      card:setBorderColor(d and d.inUse and '#3fae5f' or (d and d.health <= 0 and '#9a3030' or '#1d3557'))
      card:setBorderWidth(1)
    end
    if mode == 'horizontal' then card:getChildById('statusLabel'):setText('') end
  end

  window:getChildById('countLabel'):setText(count .. ' / ' .. SIZE)
  local hasSelection = selected ~= nil and team[selected] ~= nil
  window:getChildById('useButton'):setEnabled(enabled and hasSelection)
  window:getChildById('cpButton'):setEnabled(enabled and hasSelection and not team[selected].inUse)
  window:getChildById('cancelButton'):setEnabled(selected ~= nil)
  defaultHint()
end

local function onCardClick(slot)
  if not enabled then return end
  ensureTeamOpen(true)
  if selected == nil then
    if team[slot] then
      selected = slot
    end
  elseif selected == slot then
    selected = nil
  else
    send('SWAP|' .. selected .. '|' .. slot)
    selected = nil
  end
  refreshCards()
end

local function onCardDrop(slot, draggedWidget)
  if not enabled or not draggedWidget or draggedWidget:getClassName() ~= 'UIItem' then
    return false
  end
  local item = draggedWidget:getItem()
  if not item then
    return false
  end
  -- ball que ja esta na equipe (arrastada de outro card): troca de posicao
  local fromSlot = slotOfTeamItem(item)
  if fromSlot then
    if fromSlot ~= slot then
      send('SWAP|' .. fromSlot .. '|' .. slot)
    end
    return true
  end
  send('PREF|' .. slot)
  g_game.move(item, {x = 65535, y = TEAM_SLOT, z = 0}, 1)
  return true
end

local function onTeamOpcode(protocol, opcode, buffer)
  local lines = splitLines(buffer or '')
  if #lines == 0 then return end
  local header = splitFields(lines[1])
  if header[1] ~= 'TEAM' then return end

  enabled = header[2] == '1'
  team = {}
  for i = 2, #lines do
    local f = splitFields(lines[i])
    local slot = tonumber(f[1])
    if slot then
      team[slot] = {
        name = f[2] or '?',
        level = tonumber(f[3]) or 1,
        health = tonumber(f[4]) or 0,
        maxHealth = tonumber(f[5]) or 0,
        inUse = f[6] == '1',
        ballClientId = tonumber(f[7]) or 0,
        bagIndex = tonumber(f[8]),
        type1 = f[9] or 'none',
        type2 = f[10] or 'none',
        -- Genes
        gender = f[11] or 'N',
        stars = tonumber(f[12]) or 0,
        ivPct = tonumber(f[13]) or -1,
        boost = tonumber(f[14]) or 0,
        tags = f[15] or ''
      }
    end
  end
  if selected and not team[selected] then
    selected = nil
  end
  -- barra de Pokemons usa os mesmos dados (vida, tipo, revive)
  local bar = modules.game_pokemonbar
  if bar and bar.onTeamData then
    pcall(bar.onTeamData, team, enabled, tonumber(header[4]) or 0, tonumber(header[5]) or 0, tonumber(header[6]) or 0, tonumber(header[7]) or 0)
  end
  if window then
    if window:isVisible() then
      ensureTeamOpen(false)
    end
    refreshCards()
  end
end

-- ============================================================
-- API usada pela barra de Pokemons (game_pokemonbar)
-- ============================================================
function getTeam()
  return team
end

-- ball real do slot (precisa da equipe aberta). Abre se fechada:
-- chamar so a partir de clique do jogador (protecao anti-bot).
function getRealBallForSlot(slot)
  if not teamContainer then
    ensureTeamOpen(true)
    return nil
  end
  local data = team[slot]
  local ball = getRealBall(data)
  if ball and data and ball:getId() == data.ballClientId then
    return ball
  end
  return nil
end

function requestTeam()
  send('REQ')
end

local function onContainerOpen(container, previousContainer)
  if isTeamContainer(container) then
    g_logger.info('[Pokemons] Equipe aberta (container ' .. container:getId() .. ').')
    teamContainer = container
    hideContainerWindow(container)
    if window then refreshCards() end
  elseif previousContainer and previousContainer == teamContainer then
    teamContainer = nil -- codex mochila livre: outra janela (mochila) entrou no lugar da equipe
    expectedTeamId = nil
    if window then refreshCards() end
  end
end

local function onContainerClose(container)
  if container == teamContainer then
    teamContainer = nil
    if window then refreshCards() end
  end
end

-- revive/tera/etc. transformam a ball: atualiza a ball mostrada no card.
-- (o REQ da equipe sai junto com o "Usar com"; pedido por timer seria
-- cancelado pela protecao anti-bot do cliente)
local function onContainerChange(container)
  if container == teamContainer and window then
    refreshCards()
  end
end

-- ============================================================
-- "Usar com" na ball do card
-- O game_interface decide o alvo do "Usar com" por conta propria. Para nao
-- depender de onde a janela esta, envolvemos o onUseWith dele: se o clique
-- caiu na janela Pokemons, o alvo e a ball real do card.
-- ============================================================
local originalOnUseWith = nil
local hookedEnv = nil

local function findBallUnder(mousePosition)
  if not window or not window:isVisible() then return nil, false end
  if not window:containsPoint(mousePosition) then return nil, false end
  for slot = 1, SIZE do
    local card = cards[slot]
    local ballSlot = card and card:getChildById('ballSlot')
    if ballSlot and ballSlot:isVisible() and ballSlot:containsPoint(mousePosition) then
      if not ballSlot:isVirtual() and ballSlot:getItem() then
        return ballSlot:getItem(), true
      end
      return nil, true
    end
  end
  return nil, true -- clicou na janela, mas fora de uma ball
end

local function useWithHook(clickedWidget, mousePosition, ...)
  local ball, insideWindow = findBallUnder(mousePosition)
  if insideWindow then
    local thing = hookedEnv and hookedEnv.selectedThing
    if ball and thing then
      g_logger.info('[Pokemons] Usar com na ball do slot (item ' .. ball:getId() .. ').')
      g_game.useWith(thing, ball)
      -- pede a equipe atualizada no mesmo clique (a protecao anti-bot
      -- cancela pedidos feitos depois, por timer). O servidor processa
      -- na ordem: primeiro o item, depois o REQ.
      send('REQ')
    elseif not ball then
      setHint(T('Use o item em cima da ball (quadrado dourado) do card.'))
    end
    return
  end
  return originalOnUseWith(clickedWidget, mousePosition, ...)
end

local function installUseWithHook()
  if originalOnUseWith then return end
  local env = modules.game_interface
  local fn = env and env.onUseWith
  if type(fn) ~= 'function' and _G and type(rawget(_G, 'onUseWith')) == 'function' then
    env = _G -- game_interface nao sandboxed
    fn = rawget(_G, 'onUseWith')
  end
  if type(fn) ~= 'function' then
    g_logger.info('[Pokemons] onUseWith do game_interface nao encontrado.')
    return
  end
  hookedEnv = env
  originalOnUseWith = fn
  env.onUseWith = useWithHook
end

local function removeUseWithHook()
  if hookedEnv and originalOnUseWith then
    hookedEnv.onUseWith = originalOnUseWith
  end
  hookedEnv, originalOnUseWith = nil, nil
end

local function onGameEnd()
  teamContainer = nil
  expectedTeamId = nil
  openRequested = 0
  hide()
end

function init()
  -- A janela precisa ser filha do painel do jogo: o "Usar com" do
  -- game_interface procura o alvo com gameRootPanel:recursiveGetChildByPos.
  -- Como filha do rootWidget, o clique "atravessava" a janela e o item era
  -- usado no chao do mapa ("You can only use on pokeballs").
  local parent = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel() or nil
  window = g_ui.displayUI('pokemons', parent)
  window:hide()
  slotsPanel = window:getChildById('slotsPanel')
  mode = g_settings.getString('codexTeamMode')
  if not MODE_NEXT[mode] then mode = g_settings.getBoolean('codexTeamCompact') and 'compact' or 'full' end
  buildCards()
  ProtocolGame.registerExtendedOpcode(OPCODE, onTeamOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  connect(Container, {
    onOpen = onContainerOpen,
    onClose = onContainerClose,
    onAddItem = onContainerChange,
    onRemoveItem = onContainerChange,
    onUpdateItem = onContainerChange
  })
  g_keyboard.bindKeyDown('Ctrl+Shift+P', toggle)
  installUseWithHook()
  refreshCards()
end

-- monta os 6 cards no modo atual (completo 3x2 / compacto 2x3)
function buildCards()
  slotsPanel:destroyChildren()
  cards = {}
  local layout = slotsPanel:getLayout()
  compact = mode ~= 'full'
  -- compacto/horizontal: sem rodape (acoes no clique direito do card)
  if mode == 'horizontal' then
    layout:setCellSize({width = 68, height = 76})
    layout:setCellSpacing(3)
    layout:setNumColumns(6)
    slotsPanel:setHeight(76)
    window:setSize({width = 12 + 6 * 68 + 5 * 3 + 12, height = 42 + 76 + 10})
  elseif compact then
    layout:setCellSize({width = 184, height = 54})
    layout:setCellSpacing(6)
    layout:setNumColumns(2)
    slotsPanel:setHeight(3 * 54 + 2 * 6)
    window:setSize({width = 398, height = 42 + 174 + 10})
  else
    layout:setCellSize({width = 176, height = 96})
    layout:setCellSpacing(8)
    layout:setNumColumns(3)
    slotsPanel:setHeight(202)
    window:setSize({width = 568, height = 42 + 202 + 6 + 28 + 8 + 24 + 12})
  end
  window:getChildById('hintLabel'):setVisible(not compact)
  for _, id in ipairs({'useButton', 'cpButton', 'cancelButton'}) do window:getChildById(id):setVisible(not compact) end
  window:getChildById('countLabel'):setTooltip(compact and T('Clique direito no Pokemon: usar, enviar ao CP') or '')
  local mb = window:getChildById('modeButton')
  mb:setText(({full = '-', compact = '=', horizontal = '+'})[mode])
  mb:setTooltip(T('Modo: %s (clique: %s)', MODE_NAME[mode], MODE_NAME[MODE_NEXT[mode]]))
  for slot = 1, SIZE do
    local card = g_ui.createWidget(({full = 'PTSlotCard', compact = 'PTSlotRow', horizontal = 'PTSlotMini'})[mode], slotsPanel)
    card:setId('teamSlot' .. slot)
    card.onClick = function() onCardClick(slot) end
    card.onDoubleClick = function()
      if team[slot] then
        send('USE|' .. slot)
      end
      return true
    end
    card.onDrop = function(self, draggedWidget, mousePos)
      return onCardDrop(slot, draggedWidget)
    end
    -- clique direito: menu com as acoes do rodape
    card.onMouseRelease = function(self, mousePos, button)
      if button ~= MouseRightButton or not team[slot] then return false end
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption(team[slot].inUse and T('Recolher') or T('Usar'), function() send('USE|' .. slot) end)
      if not team[slot].inUse then
        menu:addOption(T('Enviar ao CP'), function() send('TOCP|' .. slot) selected = nil end)
      end
      if selected and selected ~= slot then
        menu:addOption(T('Trocar com o slot %d', selected), function() send('SWAP|' .. selected .. '|' .. slot) selected = nil end)
      end
      menu:display(mousePos)
      return true
    end
    -- a ball do card tambem aceita o drop/clique do proprio card
    -- (Usar com, Look e menu de clique direito continuam do UIItem)
    local ballSlot = card:getChildById('ballSlot')
    ballSlot.onDrop = card.onDrop
    ballSlot.onClick = card.onClick
    ballSlot.onDoubleClick = card.onDoubleClick
    cards[slot] = card
  end
end

function toggleCompact()
  mode = MODE_NEXT[mode] or 'full'
  g_settings.set('codexTeamMode', mode)
  buildCards()
  refreshCards()
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(Container, {
    onOpen = onContainerOpen,
    onClose = onContainerClose,
    onAddItem = onContainerChange,
    onRemoveItem = onContainerChange,
    onUpdateItem = onContainerChange
  })
  if reqEvent then
    removeEvent(reqEvent)
    reqEvent = nil
  end
  g_keyboard.unbindKeyDown('Ctrl+Shift+P')
  removeUseWithHook()
  cards = {}
  if window then
    window:destroy()
    window = nil
  end
end

function show()
  if not g_game.isOnline() or not window then return end
  window:show()
  window:raise()
  window:focus()
  ensureTeamOpen(true)
  send('REQ')
end

function hide()
  selected = nil
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

function useSelected()
  if selected and team[selected] then
    send('USE|' .. selected)
  end
end

function sendSelectedToCp()
  if selected and team[selected] then
    send('TOCP|' .. selected)
    selected = nil
  end
end

function clearSelection()
  selected = nil
  refreshCards()
end
