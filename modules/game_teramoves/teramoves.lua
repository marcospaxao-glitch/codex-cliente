-- ============================================================
-- CODEX GOLPES TERA
--   Botao "GOLPES TERA" na aba Moves do Pokemon Manager.
--   Lista os golpes do tipo do Tera do Pokemon; o player escolhe
--   (limite e custo definidos no servidor: data/lib/core/codexteramoves.lua)
-- ============================================================
OPCODE = 124
local TYPE_PT = {normal = 'Normal', fire = 'Fogo', fighting = 'Lutador', water = 'Agua', flying = 'Voador',
  grass = 'Planta', poison = 'Veneno', electric = 'Eletrico', ground = 'Terra', psychic = 'Psiquico',
  rock = 'Pedra', ice = 'Gelo', bug = 'Inseto', dragon = 'Dragao', ghost = 'Fantasma',
  dark = 'Sombrio', steel = 'Aco', fairy = 'Fada', none = '-'}

local window = nil
local team, catalog, costInfo = {}, {}, {name = 'CD', count = 0, max = 2}
local selected = nil
local hooked = false

local function split(text, sep)
  local out = {}
  for v in string.gmatch((text or '') .. sep, '(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = v end
  return out
end

local function send(text)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if proto then proto:sendExtendedOpcode(OPCODE, text) end
end

local function cap(s) return (tostring(s or ''):gsub('^%l', string.upper)) end

local function setIcon(row, name)
  local pm = modules.game_pokemonmoves
  local w = row:getChildById('icon')
  if pm and pm.applyMoveIcon and pcall(pm.applyMoveIcon, w, name, 20) then return end
  w:hide()
end

local function current()
  for _, p in ipairs(team) do if p.slot == selected then return p end end
  return team[1]
end

function refresh()
  if not window then return end
  window:getChildById('costLabel'):setText(cap(costInfo.name) .. ': ' .. costInfo.count)
  local tp = window:getChildById('teamPanel')
  tp:destroyChildren()
  local p = current()
  if p then selected = p.slot end
  for _, poke in ipairs(team) do
    local b = g_ui.createWidget('TMPokeButton', tp)
    b:getChildById('name'):setText(poke.name)
    b:getChildById('info'):setText('Tera ' .. (TYPE_PT[poke.tera] or poke.tera) .. ' - ' .. #poke.learned .. '/' .. costInfo.max)
    if poke.look > 0 then b:getChildById('creature'):setOutfit({type = poke.look}) end
    b:setOn(p ~= nil and poke.slot == p.slot)
    b.onClick = function() selected = poke.slot refresh() end
  end
  local info = window:getChildById('infoLabel')
  local lp, mp = window:getChildById('learnedPanel'), window:getChildById('movesPanel')
  lp:destroyChildren()
  mp:destroyChildren()
  if not p then info:setText('Nenhum Pokemon na equipe.') return end
  if p.tera == 'none' then
    info:setText(p.name .. ' nao tem Tera. Use um Tera Crystal na pokebola para ganhar um tipo Tera.')
    return
  end
  local warn = p.inUse and '  |  Recolha o Pokemon para aprender/esquecer.' or ''
  info:setText(p.name .. ' (Nv ' .. p.level .. ')  -  Tera ' .. (TYPE_PT[p.tera] or p.tera) ..
    '  -  slots livres: ' .. p.free .. warn)
  local known = {}
  for _, n in ipairs(p.learned) do
    known[n] = true
    local row = g_ui.createWidget('TMMoveRow', lp)
    row:getChildById('name'):setText(cap(n))
    setIcon(row, n)
    row:getChildById('info'):setText('golpe Tera')
    local btn = row:getChildById('action')
    btn:setText('Esquecer')
    btn:setEnabled(not p.inUse)
    btn.onClick = function() send('FORGET|' .. p.slot .. '|' .. n) end
  end
  if #p.learned == 0 then
    local row = g_ui.createWidget('TMMoveRow', lp)
    row:getChildById('name'):setText('(nenhum)')
    row:getChildById('icon'):hide()
    row:getChildById('info'):setText('')
    row:getChildById('action'):hide()
  end
  local list = {}
  for _, m in ipairs(catalog) do if m.tipo == p.tera then list[#list + 1] = m end end
  table.sort(list, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end)
  for _, m in ipairs(list) do
    local row = g_ui.createWidget('TMMoveRow', mp)
    row:getChildById('name'):setText(cap(m.name))
    setIcon(row, m.name)
    local lvOk = p.level >= m.level
    row:getChildById('info'):setText('Nv ' .. m.level .. '  -  ' .. m.cost .. 'x ' .. costInfo.name)
    row:getChildById('info'):setColor(lvOk and '#8fa7c4' or '#ff7070')
    local btn = row:getChildById('action')
    if known[m.name] then
      btn:setText('Aprendido')
      btn:setEnabled(false)
    else
      btn:setText('Aprender')
      btn:setEnabled(not p.inUse and lvOk and #p.learned < costInfo.max and p.free > 0 and costInfo.count >= m.cost)
      btn.onClick = function() send('LEARN|' .. p.slot .. '|' .. m.name) end
    end
  end
end

local function onOpcode(protocol, opcode, buffer)
  local lines = split(buffer or '', '\n')
  local head = split(lines[1] or '', '|')
  if head[1] == 'MSG' then
    modules.game_textmessage.displayStatusMessage('[Tera] ' .. (head[2] or ''))
    return
  end
  if head[1] ~= 'DATA' then return end
  team, catalog = {}, {}
  for i = 2, #lines do
    local f = split(lines[i], '|')
    if f[1] == 'C' then
      costInfo = {name = f[2] or 'CD', count = tonumber(f[4]) or 0, max = tonumber(f[5]) or 2}
    elseif f[1] == 'P' then
      local learned = {}
      for _, n in ipairs(split(f[7] or '', ',')) do if n ~= '' then learned[#learned + 1] = n end end
      team[#team + 1] = {slot = tonumber(f[2]) or 0, name = f[3] or '?', level = tonumber(f[4]) or 1, tera = f[5] or 'none',
        free = tonumber(f[6]) or 0, learned = learned, inUse = f[8] == '1', look = tonumber(f[9]) or 0}
    elseif f[1] == 'M' then
      catalog[#catalog + 1] = {tipo = f[2], name = f[3], level = tonumber(f[4]) or 1, cost = tonumber(f[5]) or 0}
    end
  end
  refresh()
end

function openWindow(pokeName)
  if not g_game.isOnline() then return end
  if not window then
    window = g_ui.createWidget('TMWindow', modules.game_interface.getRootPanel())
    window.onVisibilityChange = function(self, visible)
      if not visible then
        scheduleEvent(function() local r = modules.game_interface.getRootPanel() if r then r:focus() end end, 1)
      end
    end
  end
  if pokeName then
    for _, p in ipairs(team) do if p.name:lower() == tostring(pokeName):lower() then selected = p.slot end end
  end
  window:show()
  window:raise()
  window:focus()
  refresh()
  send('REQ')
end

function closeWindow()
  if window then window:hide() end
end

-- botao na aba Moves do Manager
local function getPM()
  local m = modules.game_pokemonmanager
  return (m and m.PokemonManager) or rawget(_G, 'PokemonManager')
end

local function addManagerButton()
  local PM = getPM()
  if not PM or not PM.window or PM.window:isDestroyed() then return end
  local bar = PM.window:recursiveGetChildById('movesTitleBar')
  if not bar or bar:getChildById('teraMovesButton') then return end
  local btn = g_ui.createWidget('Button', bar)
  btn:setId('teraMovesButton')
  btn:setText('GOLPES TERA')
  btn:setWidth(96)
  btn:setHeight(18)
  btn:addAnchor(AnchorRight, 'parent', AnchorRight)
  btn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  btn.onClick = function()
    local p = PM.pokemon and PM.pokemon[PM.selected]
    openWindow(p and p.name)
  end
end

local function hookManager()
  if hooked then return end
  local PM = getPM()
  if not PM or type(PM.showPage) ~= 'function' then return end
  hooked = true
  local original = PM.showPage
  PM.showPage = function(page, ...)
    local r = original(page, ...)
    if page == 'moves' then pcall(addManagerButton) end
    return r
  end
end

local function tryHook(n)
  hookManager()
  if not hooked and n < 10 then scheduleEvent(function() tryHook(n + 1) end, 2000) end
end

local function onGameStart()
  scheduleEvent(function() tryHook(1) end, 1000)
end

local function onGameEnd()
  team, catalog = {}, {}
  closeWindow()
end

function init()
  g_ui.importStyle('teramoves')
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  if window then window:destroy() window = nil end
end
