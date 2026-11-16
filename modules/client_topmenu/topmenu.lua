-- ============================================================
-- BARRA DO TOPO (Codex)
-- Mesmas funcoes de antes (addLeftButton, addCenterGameButton,
-- addRightGameToggleButton...), entao nenhum modulo precisa mudar.
--
-- Esquerda : botoes do sistema (sair, opcoes, som...)
-- Centro   : Mochila, Equipe, Bolsa de Loot, Pesca, Manager, Evoluir,
--            Pokedex, Mover, Celular | Combate | Atalhos | Social |
--            Recompensas | Informacoes, Loja, Painel ADM
--            Ordem e grupos na tabela LAYOUT. Busca dentro da grade.
-- Direita  : botoes do sistema da direita
-- Ctrl+L   : sair para a lista de personagens (igual Ctrl+Q)
-- Ctrl+Shift+M : abre a ultima categoria (com busca)
-- ============================================================

local ICON_DIR = '/images/topbuttons/codex/'
local SETTINGS_KEY = 'codexTopbar'


-- icone novo por id do botao (primeiro) ou pelo nome do arquivo do icone
local ICON_BY_ID = {
  logoutButton = 'logout', optionsButton = 'options', audioButton = 'audio', hotkeysButton = 'hotkeys',
  battleButton = 'battle', vipListButton = 'viplist', minimapButton = 'minimap',
  questLogButton = 'questlog', skillsButton = 'skills', inventoryButton = 'inventory', lootButton = 'loot',
  spellListButton = 'spelllist', terminalButton = 'terminal', moduleManagerButton = 'modulemanager',
  motdButton = 'motd', healthInfoButton = 'healthinfo', cooldownButton = 'cooldowns',
  combatControlsButton = 'combatcontrols', storeButton = 'emerald_shop', shopButton = 'emerald_shop',
  particlesButton = 'particles', unjustifiedPointsButton = 'unjustifiedpoints', enterGameButton = 'login',
  pokebarButton = 'pokeball', pokemonsButton = 'pokeball', teamButton = 'pokeball', pokedexButton = 'pokedex',
  phoneButton = 'phone', dailyRewardButton = 'gift', gachaButton = 'gacha', clansButton = 'castle',
  missionsButton = 'missions', adminButton = 'crown', mailButton = 'mail', bankButton = 'coins',
  pokebankButton = 'coins', varasButton = 'fishing', fishingButton = 'fishing', codexHotbarButton = 'hotbar',
  evolveButton = 'atom', evolutionButton = 'atom', gymButton = 'gym', badgeButton = 'gym', badgesButton = 'gym',
  orderButton = 'hand', infoButton = 'info', autolootButton = 'autoloot', autoLootButton = 'autoloot',
  pcButton = 'pc', pcStorageButton = 'pc', storageButton = 'pc', marketButton = 'pc', pcMarketButton = 'pc',
  castleButton = 'castle', castelosButton = 'castle', rankingButton = 'ranking', rankButton = 'ranking',
  comboButton = 'spelllist', rankedButton = 'ranking', lootBagButton = 'loot', lootbagButton = 'loot', celularButton = 'phone',
  notebookButton = 'questlog', creatureButton = 'pokeball', pokemonTeamButton = 'pokeball', poketeamButton = 'pokeball'
}

-- pelo nome do arquivo do icone (quando o id nao estiver na lista acima)
local ICON_BY_FILE = {
  order = 'hand', info = 'info', evolve = 'atom', badge = 'gym', coin = 'coins', balls = 'pokeball',
  pokemons = 'pokeball', varas = 'fishing', autoloot = 'autoloot', purse = 'coins', pokedex = 'pokedex',
  inventory = 'inventory', loot = 'loot', fishing = 'fishing'
}

-- botoes que nao aparecem (o guia saiu do topo)
local HIDDEN_IDS = {guideButton = true, helpButton = true, tutorialButton = true, manualButton = true}
local HIDDEN_WORDS = {'guide', 'guia', 'tutorial', 'manual'}

local function isHiddenButton(id, description, icon)
  if id == 'codexStreamerButton' then return false end
  if id == 'codexGuideButton' then return false end -- codex guia: botao do Guia Codex aparece
  if HIDDEN_IDS[id] then return true end
  local text = (tostring(id or '') .. ' ' .. tostring(description or '') .. ' ' .. tostring(icon or '')):lower()
  for _, w in ipairs(HIDDEN_WORDS) do
    if text:find(w, 1, true) then return true end
  end
  return false
end

local function keepHidden(button)
  button:setVisible(false)
  button.setVisible = function() end
  button.show = function() end
  button.codexHidden = true
end


local topMenu
local leftButtonsPanel
local rightButtonsPanel
local pinnedPanel
local storagePanel
local drawer
local pingLabel
local fpsLabel

-- ============================================================
-- LAYOUT FIXO (ordem pedida). Cada lugar acha o botao pelo id
-- (primeiro) ou por palavra no id/texto do botao. Cada botao aparece
-- uma vez so. Repetido ou sem lugar nao aparece (sai no terminal).
-- ============================================================
local LAYOUT = {
  left = {
    {label = 'Mochila', ids = {'healthInfo_inventory', 'inventoryButton'}, words = {'mochila', 'inventory'}},
    {label = 'Equipe', ids = {'healthInfo_pokemons', 'pokemonsButton', 'teamButton', 'poketeamButton', 'pokemonTeamButton'}, words = {'equipe'}},
    {label = 'Bolsa de Loot', ids = {'lootBagButton', 'lootbagButton', 'bolsaButton'}, words = {'bolsa de loot', 'bolsa', 'lootbag'}, exclude = {'autoloot'}},
    {label = 'Pesca', ids = {'healthInfo_varas', 'varasButton', 'fishingButton'}, words = {'pesca', 'vara', 'fishing'}},
    {label = 'Manager', ids = {'healthInfo_info', 'pokemonManagerButton', 'managerButton'}, words = {'manager'}},
    {label = 'Evoluir', ids = {'healthInfo_evolve', 'evolveButton', 'evolutionButton'}, words = {'evolu'}},
    {label = 'Pokedex', ids = {'healthInfo_pokedex', 'pokedexButton'}, words = {'pokedex'}},
    {label = 'Mover', ids = {'healthInfo_order', 'orderButton'}, words = {'move se', 'mover'}},
    {label = 'Celular', ids = {'phoneButton', 'celularButton'}, words = {'celular', 'telefone', 'phone'}},
  },
  cats = {
    {id = 'combate', name = 'Combate', icon = 'battle', slots = {
      {label = 'Ranked 1v1', ids = {'rankedButton', 'rankingButton', 'rankButton'}, words = {'ranked', '1v1', 'ranking'}},
      {label = 'Batalha', ids = {'battleButton'}, words = {'batalha', 'battle'}},
      {label = 'Cla e Castelos', ids = {'clansButton', 'clanButton', 'castleButton', 'castelosButton'}, words = {'castel', 'clan', 'cla '}},
      {label = 'Auto Ball', ids = {'autoBallButton'}, words = {'auto ball'}},
      {label = 'Auto Target', ids = {'autoTargetButton'}, words = {'auto target'}},
    }},
    {id = 'atalhos', name = 'Atalhos', icon = 'hotkeys', slots = {
      {label = 'Hotbar', ids = {'codexHotbarButton', 'hotbarButton'}, words = {'hotbar'}},
      {label = 'Hotkeys', ids = {'hotkeysButton'}, words = {'hotkey'}},
      {label = 'Combo', ids = {'comboButton'}, words = {'combo'}},
      {label = 'Barra Pokemon', ids = {'pokebarButton', 'pokemonBarButton', 'pokeTeamBarButton'}, words = {'barra pokemon', 'barra de pokemon', 'pokebar'}},
      {label = 'Mapa', ids = {'minimapButton', 'mapButton'}, words = {'mapa', 'minimap'}},
      {label = 'Autoloot', ids = {'healthInfo_autoloot', 'autolootButton', 'autoLootButton'}, words = {'autoloot'}},
    }},
    {id = 'social', name = 'Social', icon = 'perfil', icon2 = 'skills', slots = {
      {label = 'Insignias', ids = {'healthInfo_badge', 'badgeButton', 'badgesButton', 'gymButton'}, words = {'insign', 'badge'}},
      {label = 'VIP', ids = {'vipListButton', 'vipButton'}, words = {'vip'}},
    }},
    {id = 'recompensas', name = 'Recompensas', icon = 'gift', slots = {
      {label = 'Recompensa', ids = {'dailyRewardButton', 'rewardButton'}, words = {'recompensa', 'daily', 'reward'}},
      {label = 'Gacha', ids = {'gachaButton'}, words = {'gacha', 'gatcha'}},
      {label = 'Missoes Diarias', ids = {'missionsButton', 'dailyMissionsButton', 'tasksButton'}, words = {'miss', 'task'}},
      {label = 'Quests', ids = {'questLogButton', 'questButton'}, words = {'quest'}},
    }},
  },
  right = {
    {label = 'Recompensas', ids = {'codexHorasButton'}, words = {'recompensas por tempo'}},
    {label = 'Streamer', ids = {'codexStreamerButton'}, words = {'painel do streamer'}},
    {label = 'Guia', ids = {'codexGuideButton'}, words = {'guia do servidor'}},
    {label = 'Informacoes', ids = {'infoButton', 'informationButton', 'motdButton'}, words = {'informa'}, exclude = {'pokedex', 'pokemon', 'dex'}},
    {label = 'Loja', ids = {'shopButton', 'storeButton'}, words = {'loja', 'shop', 'store'}},
    {label = 'Painel ADM', ids = {'adminButton', 'admButton', 'adminPanelButton'}, words = {'painel adm', 'admin', 'adm'}},
  },
}

local pool = {}        -- id -> {button, order, callback, hidden, icon}
local poolOrder = 0
local gameOnline = false
local catButtons = {}  -- cat id -> botao
local assign = {}      -- botao id -> {where='left'|'right'|cat id, slot=n, label=}
local currentCat = nil
local searchText = ''

local function loadSettings() end

local function codexIcon(id, icon)
  local name = ICON_BY_ID[id]
  if not name and type(icon) == 'string' then
    name = icon:match('([^/]+)$')
    if name then
      name = name:gsub('%.png$', '')
      name = ICON_BY_FILE[name] or name
    end
  end
  if name then
    local path = ICON_DIR .. name
    if g_resources.fileExists(path .. '.png') then
      return path
    end
  end
  return nil
end

local function applyIcon(button, icon)
  local codex = codexIcon(button:getId(), icon)
  local entry = pool[button:getId()]
  if codex then
    button:setStyle('CodexTopButton')
    button.codexOriginalSetIcon(button, codex)
    if entry then entry.iconPath = codex; entry.raw = false end
  elseif icon then
    button:setStyle('CodexTopButtonRaw')
    button.codexOriginalSetIcon(button, icon)
    if entry then entry.iconPath = icon; entry.raw = true end
  end
end

local function textOf(id)
  local e = pool[id]
  return (tostring(id) .. ' ' .. tostring(e and e.button:getTooltip() or '')):lower()
end

-- distribui os botoes pelos lugares do LAYOUT (id primeiro, depois palavras)
local function computeAssign()
  assign = {}
  local used = {}
  local places = {}
  for i, s in ipairs(LAYOUT.left) do places[#places + 1] = {where = 'left', n = i, s = s} end
  for _, c in ipairs(LAYOUT.cats) do for i, s in ipairs(c.slots) do places[#places + 1] = {where = c.id, n = i, s = s} end end
  for i, s in ipairs(LAYOUT.right) do places[#places + 1] = {where = 'right', n = i, s = s} end
  local filled, icons = {}, {}
  for k, pl in ipairs(places) do
    for _, id in ipairs(pl.s.ids) do
      local e = pool[id]
      if e and not e.hidden and not used[id] then
        used[id] = true; filled[k] = true; assign[id] = {where = pl.where, n = pl.n, label = pl.s.label}
        if e.iconPath then icons[e.iconPath] = true end
        break
      end
    end
  end
  for k, pl in ipairs(places) do
    if not filled[k] then
      local best
      for id, e in pairs(pool) do
        if not used[id] and not e.hidden and not (e.iconPath and icons[e.iconPath]) then
          local t = textOf(id)
          local bad = false
          for _, x in ipairs(pl.s.exclude or {}) do if t:find(x, 1, true) then bad = true break end end
          if not bad then
            for _, w in ipairs(pl.s.words) do
              if t:find(w, 1, true) then if not best or e.order < pool[best].order then best = id end break end
            end
          end
        end
      end
      if best then
        used[best] = true; assign[best] = {where = pl.where, n = pl.n, label = pl.s.label}
        if pool[best].iconPath then icons[pool[best].iconPath] = true end
      end
    end
  end
  -- o que sobrou (repetido ou sem lugar) nao aparece
end

local function shortLabel(text)
  text = tostring(text or ''):gsub('\n.*$', '')
  text = text:gsub('%s*%b()', ''):gsub('^%s+', ''):gsub('%s+$', '')
  if #text > 12 then text = text:sub(1, 11) .. '.' end
  return text
end
local function labelOf(id)
  local a = assign[id]
  if a and a.label then return a.label end
  return shortLabel(pool[id] and pool[id].button:getTooltip())
end

-- ============================================================
-- grade da categoria
-- ============================================================
local function closeDrawer()
  if drawer then drawer:hide() end
  for _, b in pairs(catButtons) do b:setOn(false) end
  currentCat = nil
end

local refreshBar
local refreshPending = false
local function scheduleRefresh()
  if refreshPending then return end
  refreshPending = true
  scheduleEvent(function()
    refreshPending = false
    if topMenu then refreshBar() end
  end, 1)
end

local function entriesOf(cat, search)
  local list = {}
  for id, e in pairs(pool) do
    local a = assign[id]
    if a and not e.hidden and not e.button:isDestroyed() and e.button:isExplicitlyVisible() then
      local ok
      if search ~= '' then ok = (labelOf(id) .. ' ' .. textOf(id)):lower():find(search, 1, true) ~= nil
      else ok = (cat == '*') or a.where == cat end -- CODEX: '*' = todos (celular)
      if ok then list[#list + 1] = {id = id, n = (search ~= '' and e.order or a.n)} end
    end
  end
  table.sort(list, function(x, y) return x.n < y.n end)
  return list
end

local function placeDrawer(count)
  local cols = math.max(1, math.min(6, count))
  local rows = math.max(1, math.ceil(count / 6))
  local width = math.max(300, cols * 80 - 4 + 16)
  local height = 16 + 18 + 26 + rows * 72 - 4 + 4
  drawer:setSize({width = width, height = height})
  local anchor = currentCat and catButtons[currentCat] or pinnedPanel
  local pos = anchor:getPosition()
  local x = pos.x + math.floor(anchor:getWidth() / 2) - math.floor(width / 2)
  x = math.max(4, math.min(x, rootWidget:getWidth() - width - 4))
  drawer:setPosition({x = x, y = topMenu:getY() + topMenu:getHeight() + 4})
end

local function catName(id)
  for _, c in ipairs(LAYOUT.cats) do if c.id == id then return c.name end end
  return 'Menu'
end

local function renderDrawer()
  if not drawer or not currentCat then return end
  local grid = drawer:getChildById('grid')
  grid:destroyChildren()
  local search = searchText:lower()
  local list = entriesOf(currentCat, search)
  drawer:getChildById('title'):setText(search ~= '' and ('Busca: ' .. searchText) or catName(currentCat))
  for _, item in ipairs(list) do
    local entry = pool[item.id]
    local tile = g_ui.createWidget('CodexMenuTile', grid)
    tile:setId('tile_' .. item.id)
    local icon = g_ui.createWidget(entry.raw and 'CodexTopButtonRaw' or 'CodexTopButton', tile:getChildById('slot'))
    icon:addAnchor(AnchorTop, 'parent', AnchorTop)
    icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    icon:setPhantom(true)
    if entry.iconPath then icon:setIcon(entry.iconPath) end
    if entry.button:isOn() then icon:setOn(true) end
    tile:getChildById('label'):setText(labelOf(item.id))
    tile:setTooltip(entry.button:getTooltip())
    tile.onClick = function()
      closeDrawer()
      if entry.callback then entry.callback() end
    end
  end
  drawer:getChildById('empty'):setVisible(#list == 0)
  placeDrawer(#list)
end

local function openCategory(cat)
  if currentCat == cat and drawer:isVisible() then closeDrawer() return end
  closeDrawer()
  currentCat = cat
  searchText = ''
  local s = drawer:getChildById('search')
  s:setText('')
  if catButtons[cat] then catButtons[cat]:setOn(true) end
  renderDrawer()
  drawer:show()
  drawer:raise()
  drawer:focus()
  s:focus()
end

-- barra: soltos da esquerda | categorias | soltos da direita (fim)
refreshBar = function()
  if not topMenu then return end
  for id, e in pairs(pool) do if e.button:isDestroyed() then pool[id] = nil end end
  computeAssign()
  local lefts, rights = {}, {}
  for id, e in pairs(pool) do
    local a = assign[id]
    if a and a.where == 'left' then lefts[#lefts + 1] = {id = id, n = a.n}
    elseif a and a.where == 'right' then rights[#rights + 1] = {id = id, n = a.n}
    elseif e.button:getParent() ~= storagePanel then e.button:setParent(storagePanel) end
    if not a and not e.hidden and not e.reported then
      e.reported = true
      g_logger.info('[Topo Codex] escondido (repetido ou sem lugar): id=' .. tostring(id))
    end
  end
  table.sort(lefts, function(x, y) return x.n < y.n end)
  table.sort(rights, function(x, y) return x.n < y.n end)
  local idx = 1
  for _, it in ipairs(lefts) do
    local b = pool[it.id].button
    if b:getParent() ~= pinnedPanel then b:setParent(pinnedPanel) end
    pinnedPanel:moveChildToIndex(b, idx); idx = idx + 1
  end
  local sep = pinnedPanel:getChildById('favSep')
  if sep then pinnedPanel:moveChildToIndex(sep, idx); idx = idx + 1; sep:setVisible(#lefts > 0) end
  local cats = {}
  for _, c in ipairs(LAYOUT.cats) do cats[#cats + 1] = c.id end
  for _, cid in ipairs(cats) do
    local cb = catButtons[cid]
    if cb then
      local n = #entriesOf(cid, '')
      cb:setVisible(n > 0)
      pinnedPanel:moveChildToIndex(cb, idx); idx = idx + 1
    end
  end
  local sep2 = pinnedPanel:getChildById('rightSep')
  if sep2 then pinnedPanel:moveChildToIndex(sep2, idx); idx = idx + 1; sep2:setVisible(#rights > 0) end
  for _, it in ipairs(rights) do
    local b = pool[it.id].button
    if b:getParent() ~= pinnedPanel then b:setParent(pinnedPanel) end
    pinnedPanel:moveChildToIndex(b, idx); idx = idx + 1
  end
  if currentCat and drawer:isVisible() then renderDrawer() end
end

-- ============================================================
-- criacao dos botoes (mesma assinatura de antes)
-- ============================================================
local function prepareButton(button, id, description, icon, callback)
  button:setId(id)
  button:setTooltip(description)
  if not button.codexOriginalSetIcon then
    button.codexOriginalSetIcon = UIWidget.setIcon
    button.setIcon = function(self, path) applyIcon(self, resolvepath(path, 2)) end
  end
  applyIcon(button, icon)
  button.onMouseRelease = function(widget, mousePos, mouseButton)
    if widget:containsPoint(mousePos) and mouseButton == MouseLeftButton then
      closeDrawer()
      callback()
      return true
    end
  end
end

local function addSystemButton(id, description, icon, callback, panel, toggle, front)
  local button = panel:getChildById(id)
  if not button then
    button = g_ui.createWidget('CodexTopButton')
    if front then panel:insertChild(1, button) else panel:addChild(button) end
  end
  prepareButton(button, id, description, icon, callback)
  if isHiddenButton(id, description, icon) then keepHidden(button) end
  return button
end

local function addGameButton(id, description, icon, callback, toggle, front)
  local entry = pool[id]
  local button
  if entry and not entry.button:isDestroyed() then
    button = entry.button
  else
    button = g_ui.createWidget('CodexTopButton', storagePanel)
    poolOrder = poolOrder + 1
    entry = {button = button, order = front and -poolOrder or poolOrder}
    pool[id] = entry
  end
  entry.callback = callback
  entry.icon = icon
  prepareButton(button, id, description, icon, callback)
  if isHiddenButton(id, description, icon) then
    keepHidden(button)
    entry.hidden = true
  end
  if not button.codexVisHook then
    button.codexVisHook = true
    connect(button, {onVisibilityChange = function() scheduleRefresh() end})
  end
  g_logger.info('[Topo Codex] botao id=' .. tostring(id) .. '  texto=' .. tostring(description):gsub('\n', ' '))
  scheduleRefresh()
  return button
end

-- ============================================================
-- ciclo de vida
-- ============================================================
local function onGameMapPress()
  if drawer and drawer:isVisible() then closeDrawer() end
end

local function logoutToCharacterList()
  if not g_game.isOnline() then return end
  if modules.game_interface and modules.game_interface.tryLogout then
    modules.game_interface.tryLogout(false)
  end
end

function init()
  connect(g_game, { onGameStart = online,
                    onGameEnd = offline,
                    onPingBack = updatePing })
  connect(g_app, { onFps = updateFps })

  loadSettings()
  topMenu = g_ui.displayUI('topmenu')

  leftButtonsPanel = topMenu:getChildById('leftButtonsPanel')
  rightButtonsPanel = topMenu:getChildById('rightButtonsPanel')
  pinnedPanel = topMenu:getChildById('pinnedPanel')
  storagePanel = topMenu:getChildById('storagePanel')
  pingLabel = topMenu:getChildById('pingLabel')
  fpsLabel = topMenu:getChildById('fpsLabel')

  local sep = g_ui.createWidget('CodexTopSeparator', pinnedPanel)
  sep:setId('favSep')
  local all = {}
  for _, c in ipairs(LAYOUT.cats) do all[#all + 1] = c end
  for _, c in ipairs(all) do
    local cb = g_ui.createWidget('CodexCatButton', pinnedPanel)
    cb:setId('cat_' .. c.id)
    cb:setText(c.name)
    -- CODEX: largura pelo texto (a fonte do cliente novo e um pouco mais larga)
    pcall(function() cb:setWidth(math.max(96, 30 + cb:getTextSize().width + 10)) end)
    for _, ic in ipairs({c.icon, c.icon2}) do
      if ic and g_resources.fileExists(ICON_DIR .. ic .. '.png') then cb:setIcon(ICON_DIR .. ic) break end
    end
    cb:setTooltip('Abrir ' .. c.name)
    cb.onClick = function() openCategory(c.id) end
    catButtons[c.id] = cb
  end
  local sep2 = g_ui.createWidget('CodexTopSeparator', pinnedPanel)
  sep2:setId('rightSep')

  drawer = g_ui.createWidget('CodexMenuDrawer', rootWidget)
  drawer:hide()
  local search = drawer:getChildById('search')
  search.onTextChange = function(widget, text)
    searchText = text or ''
    renderDrawer()
  end
  g_keyboard.bindKeyPress('Enter', function()
    if not drawer:isVisible() then return end
    local list = entriesOf(currentCat, searchText:lower())
    if #list > 0 then
      local entry = pool[list[1].id]
      closeDrawer()
      if entry and entry.callback then entry.callback() end
    end
  end, search)
  g_keyboard.bindKeyPress('Escape', closeDrawer, search)

  g_keyboard.bindKeyDown('Ctrl+Shift+T', toggle)
  g_keyboard.bindKeyPress('Ctrl+L', logoutToCharacterList)
  g_keyboard.bindKeyDown('Ctrl+Shift+M', function() if gameOnline then openCategory(currentCat or 'combate') end end)

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, { onGameStart = online,
                       onGameEnd = offline,
                       onPingBack = updatePing })
  disconnect(g_app, { onFps = updateFps })
  g_keyboard.unbindKeyDown('Ctrl+Shift+T')
  g_keyboard.unbindKeyPress('Ctrl+L')
  g_keyboard.unbindKeyDown('Ctrl+Shift+M')

  if drawer then
    drawer:destroy()
    drawer = nil
  end
  topMenu:destroy()
  topMenu = nil
end

function online()
  gameOnline = true
  showGameButtons()
  local gameRoot = modules.game_interface and modules.game_interface.getRootPanel and modules.game_interface.getRootPanel()
  if gameRoot and not gameRoot.codexDrawerHook then
    gameRoot.codexDrawerHook = true
    g_mouse.bindPress(gameRoot, onGameMapPress, MouseLeftButton)
    g_mouse.bindPress(gameRoot, onGameMapPress, MouseRightButton)
  end

  addEvent(function()
    if modules.client_options.getOption('showPing') and (g_game.getFeature(GameClientPing) or g_game.getFeature(GameExtendedClientPing)) then
      pingLabel:show()
    else
      pingLabel:hide()
    end
  end)
end

function offline()
  gameOnline = false
  hideGameButtons()
  pingLabel:hide()
end

function updateFps(fps)
  fpsLabel:setText('FPS: ' .. fps)
end

function updatePing(ping)
  local text = 'Ping: '
  local color
  if ping < 0 then
    text = text .. '??'
    color = '#f2c400'
  else
    text = text .. ping .. ' ms'
    if ping >= 500 then
      color = '#ff6b6b'
    elseif ping >= 250 then
      color = '#f2c400'
    else
      color = '#5fd35f'
    end
  end
  pingLabel:setColor(color)
  pingLabel:setText(text)
end

function setPingVisible(enable)
  pingLabel:setVisible(enable)
end

function setFpsVisible(enable)
  fpsLabel:setVisible(enable)
end

function addLeftButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addSystemButton(id, description, icon, callback, leftButtonsPanel, false, front)
end

function addLeftToggleButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addSystemButton(id, description, icon, callback, leftButtonsPanel, true, front)
end

function addRightButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addSystemButton(id, description, icon, callback, rightButtonsPanel, false, front)
end

function addRightToggleButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addSystemButton(id, description, icon, callback, rightButtonsPanel, true, front)
end

function addLeftGameButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addGameButton(id, description, icon, callback, false, front)
end

function addLeftGameToggleButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addGameButton(id, description, icon, callback, true, front)
end

function addRightGameButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addGameButton(id, description, icon, callback, false, front)
end

function addRightGameToggleButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addGameButton(id, description, icon, callback, true, front)
end

function addCenterGameButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addGameButton(id, description, icon, callback, false, front)
end

function addCenterGameToggleButton(id, description, icon, callback, front)
  icon = resolvepath(icon, 2)
  return addGameButton(id, description, icon, callback, true, front)
end

function showGameButtons()
  pinnedPanel:show()
  refreshBar()
end

function hideGameButtons()
  pinnedPanel:hide()
  closeDrawer()
end

function getButton(id)
  if pool[id] and not pool[id].button:isDestroyed() then
    return pool[id].button
  end
  return topMenu:recursiveGetChildById(id)
end

function getTopMenu()
  return topMenu
end

-- CODEX celular: sem a barra do topo, o botao MENU abre a gaveta com TODOS os
-- sistemas, no centro da tela (a busca continua funcionando)
function codexMenuCelular()
  if not drawer then return end
  if drawer:isVisible() and currentCat == '*' then closeDrawer() return end
  closeDrawer()
  currentCat = '*'
  searchText = ''
  drawer:getChildById('search'):setText('')
  renderDrawer()
  drawer:getChildById('title'):setText('Sistemas')
  drawer:setPosition({x = math.floor((rootWidget:getWidth() - drawer:getWidth()) / 2), y = 70})
  drawer:show()
  drawer:raise()
end

-- CODEX celular: os sistemas separados por grupo, para o menu proprio do celular
function codexGruposMenu()
  local grupos = {}
  local function add(nome, icone, where)
    local itens = {}
    for _, it in ipairs(entriesOf(where, '')) do
      local e = pool[it.id]
      itens[#itens + 1] = { label = labelOf(it.id), icon = e.iconPath, run = e.callback }
    end
    if #itens > 0 then grupos[#grupos + 1] = { nome = nome, icon = icone, itens = itens } end
  end
  add('Pokemon', ICON_DIR .. 'pokeball', 'left')
  for _, c in ipairs(LAYOUT.cats) do add(c.name, ICON_DIR .. c.icon, c.id) end
  add('Servidor', ICON_DIR .. 'info', 'right')
  return grupos
end

function codexFecharMenu()
  closeDrawer()
end

-- abre uma categoria (para atalho de outro modulo): 'combate','atalhos','social','recompensas'
function toggleMenu(cat)
  openCategory(cat or 'combate')
end

function toggle()
  local menu = getTopMenu()
  if not menu then
    return
  end

  if menu:isVisible() then
    menu:hide()
    closeDrawer()
    modules.client_background.getBackground():addAnchor(AnchorTop, 'parent', AnchorTop)
    modules.game_interface.getRootPanel():addAnchor(AnchorTop, 'parent', AnchorTop)
    modules.game_interface.getShowTopMenuButton():show()
  else
    menu:show()
    modules.client_background.getBackground():addAnchor(AnchorTop, 'topMenu', AnchorBottom)
    modules.game_interface.getRootPanel():addAnchor(AnchorTop, 'topMenu', AnchorBottom)
    modules.game_interface.getShowTopMenuButton():hide()
  end
end
