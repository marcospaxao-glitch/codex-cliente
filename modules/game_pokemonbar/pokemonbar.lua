-- ============================================================
-- POKEMON BAR - barra lateral da equipe
--
-- Dados:
--   * opcode 53 (servidor antigo): so os nomes, na ordem do !p
--   * equipe completa (vida, tipo, em uso, revive) chega pela janela
--     Pokemons (game_pokemons, opcode 91), que repassa via onTeamData.
--
-- Clique no card: solta/recolhe (!p N)
-- Botao verde no retrato (Pokemon desmaiado): usa revive na ball
-- Ctrl+1..6: solta/recolhe o Pokemon da posicao
-- Botao direito: vertical/horizontal, modo (completo/compacto/so foto),
--                travar/destravar posicao
-- Arraste pela alca (faixa fina na ponta da barra) para mover
-- ============================================================

local OPCODE_POKEBAR = 53
local ICON_PATH = '/modules/game_pokemonbar/bar_icon/'
local HOTKEYS = {'Ctrl+1', 'Ctrl+2', 'Ctrl+3', 'Ctrl+4', 'Ctrl+5', 'Ctrl+6'}

local TYPE_COLORS = {
  fire = '#ff5c5c', grass = '#67d56f', water = '#55aaff', electric = '#ffd34d',
  ice = '#79d9ff', fighting = '#ff8b62', poison = '#c77dff', ground = '#d6a86b',
  flying = '#9aa9ff', psychic = '#ff72b6', bug = '#a8d84f', rock = '#c6a66b',
  ghost = '#9b7acb', dragon = '#8f7cff', dark = '#9a8b9f', steel = '#aebbd0',
  fairy = '#ff9bd2', normal = '#c7c7b8'
}
local TYPE_NAMES = {
  fire = 'Fogo', grass = 'Planta', water = 'Agua', electric = 'Eletrico', ice = 'Gelo',
  fighting = 'Lutador', poison = 'Veneno', ground = 'Terra', flying = 'Voador',
  psychic = 'Psiquico', bug = 'Inseto', rock = 'Pedra', ghost = 'Fantasma',
  dragon = 'Dragao', dark = 'Sombrio', steel = 'Aco', fairy = 'Fada', normal = 'Normal'
}

local pkb = nil
local listPanel = nil
local names = {}            -- lista do opcode 53 (fallback)
local looks = {}            -- codex sprites: nome (minusculo) -> outfit do servidor
local entries = {}          -- {slot, order, name, level, health, maxHealth, inUse, type1, type2}
local reviveClientId = 0
local reviveCount = 0
-- codex max revive: o jogador escolhe qual revive fica no botao (botao direito no revive)
local revives = {normal = {id = 0, count = 0}, max = {id = 0, count = 0}}
local REVIVE_NAMES = {normal = 'Revive', max = 'Max Revive'}
local function reviveChoice()
  local c = g_settings.getString('codexReviveChoice')
  if c ~= 'max' then c = 'normal' end
  if revives[c].id <= 0 then c = 'normal' end
  return c
end
local function applyReviveChoice()
  local r = revives[reviveChoice()]
  reviveClientId, reviveCount = r.id, r.count
end
local hasTeamData = false
local side = 'vertical'
local mode = 'full'        -- 'full' | 'compact' (foto + vida) | 'photo' (so foto)
local locked = false
local savedPos = nil
local dragOffset = nil
local userHidden = false   -- escondida pelo botao do topmenu (fica salvo)
local topButton = nil
local CELULAR = (type(codexCelular) == 'function' and codexCelular()) and true or false
local HANDLE = CELULAR and 20 or 8 -- CODEX: alca maior no celular (dedo)

-- ============================================================
-- util
-- ============================================================
local function iconFor(name)
  local lower = tostring(name or ''):lower()
  local path = ICON_PATH .. lower .. '.png'
  if lower:sub(1, 5) == 'mega ' and not g_resources.fileExists(path) then
    path = ICON_PATH .. lower:sub(6):gsub(' [xy]$', '') .. '.png'
  end
  return path
end

-- codex sprites: outfit do Pokemon (igual a Pokedex). nil = usa a imagem
local function lookFor(name)
  local lower = tostring(name or ''):lower()
  local o = looks[lower]
  if not o and lower:sub(1, 5) == 'mega ' then o = looks[lower:sub(6):gsub(' [xy]$', '')] end
  return o
end

-- usado pela janela POKEMONS (game_pokemons)
function getLook(name)
  return lookFor(name)
end

local function setPortrait(card, name, alpha)
  local portrait = card:getChildById('portrait')
  local creature = card:getChildById('creature')
  local o = lookFor(name)
  if creature and o then
    creature:setOutfit(o)
    creature:setOpacity(alpha)
    creature:setVisible(true)
    portrait:setVisible(false)
  else
    if creature then creature:setVisible(false) end
    local path = iconFor(name)
    portrait:setVisible(g_resources.fileExists(path))
    portrait:setImageSource(path)
    portrait:setImageColor(alpha < 1 and '#ffffff55' or '#ffffff')
  end
end

local function hpColor(percent)
  if percent > 50 then return '#5fd35f' end
  if percent > 20 then return '#f2c400' end
  return '#e04848'
end

local function fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', ''))
end

local function typeText(t1, t2)
  t1, t2 = tostring(t1 or 'none'):lower(), tostring(t2 or 'none'):lower()
  local parts = {}
  if t1 ~= '' and t1 ~= 'none' then parts[#parts + 1] = TYPE_NAMES[t1] or t1 end
  if t2 ~= '' and t2 ~= 'none' then parts[#parts + 1] = TYPE_NAMES[t2] or t2 end
  return table.concat(parts, ' / '), TYPE_COLORS[t1] or '#9bb6dc'
end

-- ============================================================
-- acoes
-- ============================================================
function usePoke(order)
  if not g_game.isOnline() or not order then return end
  g_game.talk('!p ' .. order)
end

-- CODEX celular: um botao so. Recolhe o Pokemon que esta fora; se nenhum
-- estiver fora, solta o primeiro da equipe.
function codexAlternarPokemon()
  for _, e in ipairs(entries) do
    if e.inUse then usePoke(e.order) return end
  end
  local primeiro = entries[1]
  usePoke(primeiro and primeiro.order or 1)
end

local function useRevive(entry)
  if reviveClientId <= 0 or reviveCount <= 0 then
    modules.game_textmessage.displayFailureMessage('Voce nao tem ' .. REVIVE_NAMES[reviveChoice()] .. '. Botao direito no revive para trocar.')
    return
  end
  local team = modules.game_pokemons
  if not team or not team.getRealBallForSlot then
    modules.game_textmessage.displayFailureMessage('Abra a janela Pokemons (Ctrl+Shift+P) e use o revive na ball.')
    return
  end
  local ball = team.getRealBallForSlot(entry.slot)
  if not ball then
    -- a equipe acabou de ser aberta: o proximo clique ja funciona
    modules.game_textmessage.displayStatusMessage('Preparando a ball... clique no revive de novo.')
    return
  end
  g_game.useInventoryItemWith(reviveClientId, ball)
  if team.requestTeam then team.requestTeam() end
end

-- ============================================================
-- desenho
-- ============================================================
local function applyCardMode(card)
  local ids = {'nameLabel', 'levelLabel', 'typeLabel', 'statusLabel'}
  for _, id in ipairs(ids) do
    card:getChildById(id):setVisible(mode == 'full')
  end
  local hpBg = card:getChildById('hpBg')
  if mode ~= 'full' then
    card:setWidth(54)
    hpBg:removeAnchor(AnchorLeft)
    hpBg:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    hpBg:setMarginLeft(6)
  else
    card:setWidth(184)
  end
end

local function fillCard(card, entry)
  card:getChildById('slotLabel'):setText(tostring(entry.order))
  card:getChildById('nameLabel'):setText(entry.name)

  local levelLabel = card:getChildById('levelLabel')
  local typeLabel = card:getChildById('typeLabel')
  local statusLabel = card:getChildById('statusLabel')
  local stripe = card:getChildById('stripe')
  local hpFill = card:getChildById('hpFill')
  local hpBg = card:getChildById('hpBg')
  local revive = card:getChildById('reviveButton')

  local tooltip = entry.name
  if entry.level then
    levelLabel:setText('Nv ' .. entry.level)
    tooltip = tooltip .. ' - Nivel ' .. entry.level
  else
    levelLabel:setText('')
  end

  local text, color = typeText(entry.type1, entry.type2)
  typeLabel:setText(text)
  typeLabel:setColor(color)

  local percent = 100
  if entry.maxHealth and entry.maxHealth > 0 then
    percent = math.max(0, math.min(100, math.floor((entry.health or 0) * 100 / entry.maxHealth)))
    tooltip = tooltip .. '\nHP ' .. fmt(entry.health) .. ' / ' .. fmt(entry.maxHealth)
  elseif entry.livePercent then
    percent = entry.livePercent
    tooltip = tooltip .. '\nHP ' .. percent .. '%'
  end
  local hasHp = entry.maxHealth ~= nil or entry.livePercent ~= nil
  hpBg:setVisible(hasHp and mode ~= 'photo')
  -- largura interna fixa da barra de vida (o layout ainda nao calculou)
  local innerWidth = mode ~= 'full' and 40 or 118
  hpFill:setWidth(math.floor(innerWidth * percent / 100))
  hpFill:setBackgroundColor(hpColor(percent))
  hpFill:setVisible(hasHp and percent > 0 and mode ~= 'photo')

  local fainted = hasHp and percent <= 0 and not entry.inUse
  if entry.inUse then
    statusLabel:setText('EM USO')
    statusLabel:setColor('#5fd35f')
    stripe:setBackgroundColor('#5fd35f')
    card:setBorderColor('#2f6b3a')
    setPortrait(card, entry.name, 1)
    tooltip = tooltip .. '\nClique para recolher'
  elseif fainted then
    statusLabel:setText('DESMAIADO')
    statusLabel:setColor('#e04848')
    stripe:setBackgroundColor('#e04848')
    card:setBorderColor('#5a1f1f')
    setPortrait(card, entry.name, 0.35)
    tooltip = tooltip .. '\nDesmaiado: use um revive'
  else
    statusLabel:setText('')
    stripe:setBackgroundColor('#1d3557')
    card:setBorderColor('#1d3557')
    setPortrait(card, entry.name, 1)
    tooltip = tooltip .. '\nClique para soltar'
  end
  -- Genes: sexo no canto do retrato, estrelas (modo completo) e dica
  local genesImg = '/modules/game_pokeinfo/images/'
  local genderIcon, starsBox = card:getChildById('genderIcon'), card:getChildById('starsBox')
  if genderIcon then
    local genderName = ({ M = 'male', F = 'female', N = 'none' })[entry.gender or '']
    genderIcon:setVisible(genderName ~= nil)
    if genderName then genderIcon:setImageSource(genesImg .. genderName) end
  end
  if starsBox then
    starsBox:destroyChildren()
    local showStars = mode == 'full' and (entry.ivPct or -1) >= 0 and statusLabel:getText() == ''
    starsBox:setVisible(showStars)
    if showStars then
      for i = 1, 5 do
        local star = g_ui.createWidget('UIWidget', starsBox)
        star:setSize({ width = 8, height = 8 })
        star:setPhantom(true)
        star:setImageSource(genesImg .. (i <= (entry.stars or 0) and (entry.ivPct >= 100 and 'star_s_perfect' or 'star_s') or 'star_s_off'))
      end
    end
  end
  if (entry.ivPct or -1) >= 0 then
    tooltip = tooltip .. '\nIV ' .. entry.ivPct .. '% (' .. (entry.stars or 0) .. ' estrelas)'
  end
  if (entry.boost or 0) > 0 then tooltip = tooltip .. '  +' .. entry.boost end
  if entry.tags and entry.tags ~= '' then tooltip = tooltip .. '\n' .. entry.tags:gsub(',', ' / ') end

  if entry.order and entry.order <= #HOTKEYS then
    tooltip = tooltip .. ' (' .. HOTKEYS[entry.order] .. ')'
  end
  card:setTooltip(tooltip)

  -- botao revive
  if fainted and reviveClientId > 0 then
    revive:setItemId(reviveClientId)
    revive:setVisible(true)
    local rname = REVIVE_NAMES[reviveChoice()]
    if reviveCount > 0 then
      revive:setTooltip('Usar ' .. rname .. ' (' .. reviveCount .. ' na mochila)\nBotao direito: escolher Revive ou Max Revive')
      revive:setOpacity(1)
    else
      revive:setTooltip('Voce nao tem ' .. rname .. '\nBotao direito: escolher Revive ou Max Revive')
      revive:setOpacity(0.4)
    end
    revive.onClick = function() useRevive(entry) return true end
    revive.onMouseRelease = function(widget, mousePos, mouseButton) return mouseButton == MouseRightButton end
    revive.onMousePress = function(widget, mousePos, mouseButton) -- codex max revive: menu (no aperto, antes do menu da barra)
      if mouseButton ~= MouseRightButton then return false end
      local menu = g_ui.createWidget('PopupMenu')
      pcall(function() menu:setGameMenu(true) end)
      local cur = reviveChoice()
      for _, k in ipairs({'normal', 'max'}) do
        local r = revives[k]
        if r.id > 0 then
          menu:addOption((cur == k and '> ' or '') .. REVIVE_NAMES[k] .. ' (' .. r.count .. ')', function()
            g_settings.set('codexReviveChoice', k)
            applyReviveChoice()
            refreshBar()
          end)
        end
      end
      menu:display(mousePos)
      return true
    end
  else
    revive:setVisible(false)
  end

  card.onClick = function() usePoke(entry.order) end
end

-- CODEX celular: na primeira vez a barra vai para a esquerda, na vertical e compacta.
-- Se o jogador ja arrastou a barra neste aparelho, respeita a posicao dele.
function codexModoCelular(x, y)
  if savedPos then return end
  side = 'vertical'
  mode = 'compact'
  savedPos = { x = x, y = y }
  refreshBar()
end

-- arrastar a barra (pela alca; no celular tambem pelos cartoes)
function arrastarInicio(self, mousePos)
  if locked then return false end
  pkb:breakAnchors()
  dragOffset = {x = mousePos.x - pkb:getX(), y = mousePos.y - pkb:getY()}
  return true
end

function arrastarMove(self, mousePos, mouseMoved)
  if not dragOffset then return false end
  pkb:setPosition({x = mousePos.x - dragOffset.x, y = mousePos.y - dragOffset.y})
  pcall(function() pkb:bindRectToParent() end)
  return true
end

-- retorna true: quem arrastou um cartao nao "clica" nele ao soltar
function arrastarFim(self, droppedWidget, mousePos)
  if not dragOffset then return false end
  dragOffset = nil
  savedPos = {x = pkb:getX(), y = pkb:getY()}
  saveOptions()
  return true
end

function refreshBar()
  if not pkb or not listPanel then return end
  listPanel:destroyChildren()

  if side == 'horizontal' then
    listPanel:setLayout(UIHorizontalLayout.create(listPanel))
  else
    listPanel:setLayout(UIVerticalLayout.create(listPanel))
  end
  listPanel:getLayout():setSpacing(3)

  for _, entry in ipairs(entries) do
    local card = g_ui.createWidget('PBarCard', listPanel)
    card:setId('poke' .. entry.order)
    applyCardMode(card)
    fillCard(card, entry)
    if CELULAR and not locked then
      -- CODEX celular: arrasta a barra segurando qualquer cartao (alca fina e dificil no dedo)
      card:setDraggable(true)
      card.onDragEnter = arrastarInicio
      card.onDragMove = arrastarMove
      card.onDragLeave = arrastarFim
    end
  end

  local count = #entries
  local cardW, cardH = mode == 'full' and 184 or 54, 54
  if count == 0 then
    pkb:hide()
    return
  end
  local handle = pkb:getChildById('dragHandle')
  local extra = locked and 0 or (HANDLE + 2)
  handle:breakAnchors()
  listPanel:breakAnchors()
  handle:setVisible(not locked)
  if side == 'horizontal' then
    handle:addAnchor(AnchorTop, 'parent', AnchorTop)
    handle:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    handle:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    handle:setWidth(HANDLE)
    listPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    listPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    listPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    listPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    listPanel:setMarginLeft(extra)
    listPanel:setMarginTop(0)
    pkb:setSize({width = count * cardW + (count - 1) * 3 + extra, height = cardH})
  else
    handle:addAnchor(AnchorTop, 'parent', AnchorTop)
    handle:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    handle:addAnchor(AnchorRight, 'parent', AnchorRight)
    handle:setHeight(HANDLE)
    listPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    listPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    listPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    listPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    listPanel:setMarginTop(extra)
    listPanel:setMarginLeft(0)
    pkb:setSize({width = cardW, height = count * cardH + (count - 1) * 3 + extra})
  end
  pkb:setVisible(not userHidden)
  if savedPos then
    pkb:breakAnchors()
    pkb:setPosition(savedPos)
    pcall(function() pkb:bindRectToParent() end)
  end
end

-- ============================================================
-- dados
-- ============================================================
-- Chamado pela janela Pokemons sempre que a equipe chega do servidor
function onTeamData(team, enabled, revClientId, revCount, maxClientId, maxCount)
  if not enabled then return end
  hasTeamData = true
  revives.normal = {id = tonumber(revClientId) or 0, count = tonumber(revCount) or 0}
  revives.max = {id = tonumber(maxClientId) or 0, count = tonumber(maxCount) or 0}
  applyReviveChoice()
  entries = {}
  local order = 0
  for slot = 1, 6 do
    local data = team[slot]
    if data then
      order = order + 1
      entries[#entries + 1] = {
        slot = slot, order = order, name = data.name, level = data.level,
        health = data.health, maxHealth = data.maxHealth, inUse = data.inUse,
        type1 = data.type1, type2 = data.type2,
        gender = data.gender, stars = data.stars, ivPct = data.ivPct, boost = data.boost, tags = data.tags
      }
    end
  end
  refreshBar()
end

-- opcode 53: lista antiga (so nomes). Usada quando a equipe nao veio.
local function onNamesOpcode(protocol, opcode, buffer)
  names = {}
  for match in string.gmatch(buffer or '', '([^,]+),%s*') do
    -- codex sprites: "Nome@looktype@head@body@legs@feet"
    local nm, lt, h, b, l, f = match:match('^(.-)@(%d+)@(%d+)@(%d+)@(%d+)@(%d+)$')
    if nm then
      match = nm
      if tonumber(lt) > 0 then
        looks[nm:lower()] = {type = tonumber(lt), head = tonumber(h), body = tonumber(b), legs = tonumber(l), feet = tonumber(f)}
      end
    end
    if tonumber(match) == nil then
      names[#names + 1] = match
    end
  end
  if hasTeamData then
    -- nomes atualizados (ex: evolucao/Mega); o resto chega no TEAM
    for i, entry in ipairs(entries) do
      if names[i] then entry.name = names[i] end
    end
  else
    entries = {}
    for i, name in ipairs(names) do
      entries[#entries + 1] = {order = i, name = name}
    end
  end
  refreshBar()
end

-- vida do Pokemon solto em tempo real.
-- Reconhece o summon pelo tipo (3 = summon proprio, quando o protocolo
-- informa) ou pelo nome + estar perto do jogador.
local function findEntryForCreature(creature)
  local isOwnSummon = false
  pcall(function() isOwnSummon = creature:getType() == 3 end)
  local name = tostring(creature:getName() or ''):lower()
  local player = g_game.getLocalPlayer()
  local near = false
  if player then
    local a, b = creature:getPosition(), player:getPosition()
    near = a and b and a.z == b.z and math.abs(a.x - b.x) <= 8 and math.abs(a.y - b.y) <= 6
  end
  if not isOwnSummon and not near then return nil end
  -- 1) o que o servidor marcou como em uso
  for _, entry in ipairs(entries) do
    if entry.inUse and (isOwnSummon or tostring(entry.name):lower() == name) then return entry end
  end
  -- 2) mesmo nome (o TEAM pode ainda nao ter chegado depois de soltar)
  if near then
    for _, entry in ipairs(entries) do
      if tostring(entry.name):lower() == name then return entry end
    end
  end
  return nil
end

local function onCreatureHealth(creature, healthPercent)
  if not creature or creature:isPlayer() then return end
  local entry = findEntryForCreature(creature)
  if not entry then return end
  entry.livePercent = math.max(0, math.min(100, tonumber(healthPercent) or 0))
  entry.inUse = true
  if entry.maxHealth and entry.maxHealth > 0 then
    entry.health = math.floor(entry.maxHealth * entry.livePercent / 100)
  end
  if entry.livePercent <= 0 then
    -- morreu: volta para a ball desmaiado (o servidor confirma no proximo TEAM)
    entry.health = 0
    entry.inUse = false
  end
  local card = listPanel and listPanel:getChildById('poke' .. entry.order)
  if card then fillCard(card, entry) end
end

-- ============================================================
-- menu / ciclo de vida
-- ============================================================
function createMenu()
  local menu = g_ui.createWidget('PopupMenu')
  if side == 'horizontal' then
    menu:addOption('Barra vertical', function() side = 'vertical' saveOptions() refreshBar() end)
  else
    menu:addOption('Barra horizontal', function() side = 'horizontal' saveOptions() refreshBar() end)
  end
  menu:addSeparator()
  if mode ~= 'full' then
    menu:addOption('Mostrar informacoes', function() mode = 'full' saveOptions() refreshBar() end)
  end
  if mode ~= 'compact' then
    menu:addOption('So foto e vida', function() mode = 'compact' saveOptions() refreshBar() end)
  end
  if mode ~= 'photo' then
    menu:addOption('So a foto', function() mode = 'photo' saveOptions() refreshBar() end)
  end
  menu:addSeparator()
  if locked then
    menu:addOption('Destravar posicao', function() locked = false saveOptions() refreshBar() end)
  else
    menu:addOption('Travar posicao', function() locked = true saveOptions() refreshBar() end)
  end
  menu:addOption('Esconder barra', function() toggle() end)
  menu:addOption('Voltar a posicao padrao', function()
    savedPos = nil
    saveOptions()
    pkb:breakAnchors()
    pkb:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    pkb:addAnchor(AnchorTop, 'parent', AnchorTop)
    pkb:setMarginLeft(10)
    pkb:setMarginTop(210)
    refreshBar()
  end)
  menu:display()
end

function saveOptions()
  pcall(function()
    g_settings.set('pokebarSide', side)
    g_settings.set('pokebarMode', mode)
    g_settings.set('pokebarLocked', locked and 'true' or 'false')
    g_settings.set('pokebarHidden', userHidden and 'true' or 'false')
    g_settings.set('pokebarX', savedPos and tostring(savedPos.x) or '')
    g_settings.set('pokebarY', savedPos and tostring(savedPos.y) or '')
  end)
end

local function loadOptions()
  pcall(function()
    local s = g_settings.getString('pokebarSide')
    if s == 'horizontal' or s == 'vertical' then side = s end
    local m = g_settings.getString('pokebarMode')
    if m == 'full' or m == 'compact' or m == 'photo' then mode = m end
    locked = g_settings.getString('pokebarLocked') == 'true'
    userHidden = g_settings.getString('pokebarHidden') == 'true'
    local x, y = tonumber(g_settings.getString('pokebarX')), tonumber(g_settings.getString('pokebarY'))
    if x and y then savedPos = {x = x, y = y} end
  end)
end

-- botao do topmenu / opcao do menu: mostra ou esconde a barra
function toggle()
  userHidden = not userHidden
  saveOptions()
  if userHidden then
    if pkb then pkb:hide() end
  else
    refreshBar()
  end
  if topButton and topButton.setOn then topButton:setOn(not userHidden) end
end

local function onGameEnd()
  entries, names, hasTeamData = {}, {}, false
  looks = {}
  if pkb then pkb:hide() end
end

function init()
  loadOptions()
  pkb = g_ui.displayUI('pokemonbar')
  pkb:setParent(modules.game_interface.getRootPanel(), true)
  pkb:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  pkb:addAnchor(AnchorTop, 'parent', AnchorTop)
  pkb:setMarginLeft(10)
  pkb:setMarginTop(210)
  listPanel = pkb:getChildById('mainWindow')
  g_mouse.bindPress(pkb, function() createMenu() end, MouseRightButton)

  -- arrastar pela alca
  local handle = pkb:getChildById('dragHandle')
  handle.onDragEnter = arrastarInicio
  handle.onDragMove = arrastarMove
  handle.onDragLeave = arrastarFim
  pkb:hide()

  connect(g_game, { onGameEnd = onGameEnd })
  connect(Creature, { onHealthPercentChange = onCreatureHealth })
  ProtocolGame.registerExtendedOpcode(OPCODE_POKEBAR, onNamesOpcode)

  for i, key in ipairs(HOTKEYS) do
    g_keyboard.bindKeyDown(key, function() usePoke(i <= #entries and entries[i].order or nil) end)
  end

  local topmenu = modules.client_topmenu
  local ok, button = pcall(function()
    local tooltip = 'Barra de Pokemon (mostrar/esconder)'
    if topmenu.addCenterGameButton then
      return topmenu.addCenterGameButton('pokebarButton', tooltip, '/modules/game_pokemonbar/topbutton.png', toggle)
    end
    return topmenu.addRightGameToggleButton('pokebarButton', tooltip, '/modules/game_pokemonbar/topbutton', toggle)
  end)
  if ok and button then
    topButton = button
    if topButton.setOn then topButton:setOn(not userHidden) end
  end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE_POKEBAR)
  disconnect(g_game, { onGameEnd = onGameEnd })
  disconnect(Creature, { onHealthPercentChange = onCreatureHealth })
  for _, key in ipairs(HOTKEYS) do
    g_keyboard.unbindKeyDown(key)
  end
  if topButton then
    pcall(function() topButton:destroy() end)
    topButton = nil
  end
  if pkb then
    pkb:destroy()
    pkb = nil
  end
end
