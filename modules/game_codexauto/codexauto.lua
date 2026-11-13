-- ============================================================
-- codex itens: os quadros aparecem/somem usando os itens Auto Ball (50002)
-- e Auto Target (50003). Sem icones no menu do topo e sem atalhos.
-- Sem o item o servidor nao liga. Botao direito no quadro do Auto Ball abre a janela.
-- ============================================================
-- CODEX AUTO BALL + AUTO TARGET
--   Dois quadros arrastaveis separados (igual ao do Combo), cada um
--   com seu atalho e seu icone no menu do topo (categoria Combate):
--   * AUTO BALL   : joga a pokebola escolhida nos pokemons que voce
--                   derrotar
--   * AUTO TARGET : ataca sozinho o pokemon selvagem mais perto
--                   quando nao estiver atacando nada
--   O trabalho todo e feito no SERVIDOR (o client bloqueia ataque e uso
--   de item automaticos - protecao anti-bot). Aqui so liga/desliga e mostra.
--   Clique no quadro = liga/desliga.
--   Janela do Auto Ball (estilo Autoloot): icone do topo, botao direito
--   no quadro ou Ctrl+Shift+K. Bola, filtro e LISTA de pokemons
--   (busca por nome/numero, fica salva no servidor).
--   Icone do Auto Target = mostra / esconde o quadro dele.
-- ============================================================
HOTKEY_BALL = 'Ctrl+Shift+B'     -- troque aqui se quiser outra tecla
HOTKEY_TARGET = 'Ctrl+Shift+X'    -- (Ctrl+Shift+T e do Celular)
HOTKEY_WINDOW = 'Ctrl+Shift+K'    -- abre a janela do Auto Ball
OPCODE = 122
TARGET_RANGE = 6                 -- sqm (mesmo andar)
TARGET_TICK = 400                -- ms entre checagens do Auto Target
THROW_GAP = 1100                 -- ms entre uma bola e outra
DEBUG = false                    -- escreve no terminal do cliente (Ctrl+T) o que esta fazendo

local MODES = {
  {key = 'todos', label = 'Todos'},
  {key = 'nunca', label = 'Nunca capturei'},
  {key = 'shiny', label = 'So shiny'},
  {key = 'lista', label = 'So a lista'},
}

local panels, topButtons, window = {}, {}, nil
local ballOn, targetOn = false, false
local ballList = {}            -- {key, name, clientId, count}
local queue = {}
local nextThrow = 0
local throwEvent, targetEvent, reqEvent = nil, nil, nil
local targetState = {id = nil, since = 0, hp = 100, tries = {}}
local blacklist = {}           -- [creatureId] = ate quando ignorar
local lastInfo = ''
local targetText = ''
local pokeList, pokeMax = {}, 100   -- {name, look, num}
local results, resultsTotal, resultsQuery = {}, 0, ''

-- ---------------- utilidades ----------------
local function sendServer(text)
  if not g_game.isOnline() then return end
  local proto = g_game.getProtocolGame()
  if proto then proto:sendExtendedOpcode(OPCODE, text) end
end

local function split(text, sep)
  local out = {}
  for v in string.gmatch((text or '') .. sep, '(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = v end
  return out
end

local function now() return g_clock.millis() end
local function dbg(text) if DEBUG then g_logger.info('[Auto] ' .. text) end end

local function settingBall() local v = g_settings.getString('codexAutoBall') return v ~= '' and v or 'pokeball' end
local function settingMode() local v = g_settings.getString('codexAutoMode') return v ~= '' and v or 'todos' end

local function modeLabel(key)
  for _, m in ipairs(MODES) do if m.key == key then return m.label end end
  return MODES[1].label
end

local function chosenBall()
  local key = settingBall()
  for _, b in ipairs(ballList) do if b.key == key then return b end end
  return nil
end

local function shortMode(key)
  return ({todos = 'todos', nunca = 'nunca capturei', shiny = 'so shiny', lista = 'lista'})[key] or 'todos'
end

-- ---------------- visual do quadro ----------------
local function rowLook(row, on, title, info, infoColor)
  if not row then return end
  row:getChildById('title'):setText(title)
  local dot, state = row:getChildById('dot'), row:getChildById('state')
  dot:setBackgroundColor(on and '#4fe07a' or '#3a5170')
  state:setText(on and 'ON' or 'OFF')
  state:setColor(on and '#ffffff' or '#8fa7c4')
  state:setBackgroundColor(on and '#2e8b4f' or '#1a2a40')
  local lbl = row:getChildById('info')
  lbl:setText(info or '')
  lbl:setColor(infoColor or (on and '#c9d6e6' or '#6f86a8'))
end

local function refreshPanel()
  local bp, tp = panels.ball, panels.target
  if bp then
    local b = chosenBall()
    local ballText
    if b then
      ballText = b.name .. ' x' .. b.count .. '  |  ' .. shortMode(settingMode())
    else
      ballText = 'Botao direito: lista e ajustes'
    end
    if ballOn and lastInfo ~= '' then ballText = lastInfo end
    rowLook(bp:getChildById('row'), ballOn, 'AUTO BALL', ballText, (b and b.count == 0) and '#ff9a7a' or nil)
    bp:setBorderColor(ballOn and '#f2c400' or '#6b5a1a')
  end
  if tp then
    local tText = targetOn and (targetText ~= '' and targetText or 'Procurando...') or ('Clique ou ' .. HOTKEY_TARGET)
    rowLook(tp:getChildById('row'), targetOn, 'AUTO TARGET', tText)
    tp:setBorderColor(targetOn and '#f2c400' or '#6b5a1a')
  end
end

-- ---------------- Auto Ball ----------------
local function sendSettings()
  sendServer(table.concat({'SET', ballOn and 1 or 0, settingBall(), settingMode()}, '|'))
end

function toggleBall()
  if not g_game.isOnline() then return end
  if not ballOn then
    local b = chosenBall()
    if b and b.count <= 0 then
      modules.game_textmessage.displayFailureMessage('Voce nao tem ' .. b.name .. '. Escolha outra bola na janela (botao direito no quadro).')
      return
    end
    if settingMode() == 'lista' and #pokeList == 0 then
      modules.game_textmessage.displayFailureMessage('Sua lista do Auto Ball esta vazia. Adicione pokemons na janela (botao direito no quadro).')
      return
    end
  end
  ballOn = not ballOn
  lastInfo = ''
  if not ballOn then queue = {} end
  sendSettings()
  modules.game_textmessage.displayStatusMessage(ballOn and 'Auto Ball ligado.' or 'Auto Ball desligado.')
  refreshPanel()
  refreshWindow()
end

local function processQueue()
  throwEvent = nil
  if #queue > 0 and ballOn and g_game.isOnline() then
    if now() >= nextThrow then
      local job = table.remove(queue, 1)
      local tile = g_map.getTile(job.pos)
      local thing = tile and tile:getTopUseThing()
      dbg('jogando bola (client id ' .. job.clientId .. ') em ' .. job.name .. ' ' .. job.pos.x .. ',' .. job.pos.y .. ' thing=' .. tostring(thing and thing.getId and thing:getId()))
      if thing then
        g_game.useInventoryItemWith(job.clientId, thing)
        nextThrow = now() + THROW_GAP
        lastInfo = 'Bola em ' .. job.name
        refreshPanel()
      end
    end
  end
  if #queue > 0 then throwEvent = scheduleEvent(processQueue, 150) end
end

-- ---------------- Auto Target (roda no servidor) ----------------
function toggleTarget()
  if not g_game.isOnline() then return end
  targetOn = not targetOn
  targetText = targetOn and 'Procurando...' or ''
  sendServer('TGT|' .. (targetOn and 1 or 0))
  modules.game_textmessage.displayStatusMessage(targetOn and 'Auto Target ligado.' or 'Auto Target desligado.')
  refreshPanel()
end

-- ---------------- mensagens do servidor ----------------
local function onOpcode(protocol, opcode, buffer)
  local lines = split(buffer or '', '\n')
  local args = split(lines[1] or '', '|')
  local cmd = args[1]
  if cmd == 'BALLS' then
    ballList = {}
    for _, part in ipairs(split(args[2] or '', ';')) do
      local f = split(part, ':')
      if f[1] and f[1] ~= '' then
        ballList[#ballList + 1] = {key = f[1], name = f[2] or f[1], clientId = tonumber(f[3]) or 0, count = tonumber(f[4]) or 0}
      end
    end
    refreshPanel()
    refreshWindow()
  elseif cmd == 'LIST' then
    pokeList = {}
    pokeMax = tonumber(args[3]) or pokeMax
    for i = 2, #lines do
      local f = split(lines[i], '|')
      if f[1] and f[1] ~= '' then pokeList[#pokeList + 1] = {name = f[1], look = tonumber(f[2]) or 0, num = tonumber(f[3]) or 0, ball = f[4] or ''} end
    end
    refreshWindow()
  elseif cmd == 'RESULTS' then
    results = {}
    resultsQuery, resultsTotal = args[2] or '', tonumber(args[3]) or 0
    for i = 2, #lines do
      local f = split(lines[i], '|')
      if f[1] and f[1] ~= '' then results[#results + 1] = {name = f[1], look = tonumber(f[2]) or 0, num = tonumber(f[3]) or 0} end
    end
    refreshResults()
  elseif cmd == 'TSTATE' then
    targetOn = args[2] == '1'
    targetText = args[3] or ''
    refreshPanel()
  elseif cmd == 'THROW' then
    dbg('servidor pediu bola: ' .. tostring(lines[1]))
    if not ballOn then return end
    queue[#queue + 1] = {pos = {x = tonumber(args[2]), y = tonumber(args[3]), z = tonumber(args[4])},
      clientId = tonumber(args[5]) or 0, name = args[6] or '?'}
    if not throwEvent then throwEvent = scheduleEvent(processQueue, 50) end
  elseif cmd == 'SHOW' then -- codex itens: usou o item
    local key = args[2] == 'target' and 'target' or 'ball'
    if key == 'target' then toggleTargetPanel() else toggleBallPanel() end
    if key == 'ball' then
      if panels.ball and panels.ball:isVisible() then openWindow(true) else closeWindow() end
    end
  elseif cmd == 'HIDE' then -- codex itens esconder: o jogador nao tem o item
    local key = args[2] == 'target' and 'target' or 'ball'
    local panel = panels[key]
    if panel and panel:isVisible() then
      if key == 'target' then toggleTargetPanel() else toggleBallPanel() closeWindow() end
    end
    g_settings.set(key == 'target' and 'codexAutoTargetHiddenShown' or 'codexAutoBallHiddenShown', false)
  elseif cmd == 'OFF' then
    ballOn = false
    queue = {}
    lastInfo = ''
    if args[2] and args[2] ~= '' then modules.game_textmessage.displayFailureMessage('Auto Ball desligado: ' .. args[2]) end
    refreshPanel()
    refreshWindow()
  end
end

-- ---------------- janela do Auto Ball (estilo Autoloot) ----------------
local function isListed(name)
  local low = name:lower()
  for _, e in ipairs(pokeList) do if e.name:lower() == low then return true end end
  return false
end

local function setCreature(widget, look)
  if not widget then return end
  pcall(function() widget:setFixedCreatureSize(true) end)
  if look and look > 0 then pcall(function() widget:setOutfit({type = look}) end) end
end

local function dexText(num) return num and num > 0 and string.format('#%03d', num) or '' end

function refreshResults()
  if not window then return end
  local panel = window:getChildById('resultsPanel')
  panel:destroyChildren()
  for _, e in ipairs(results) do
    local cell = g_ui.createWidget('ABResult', panel)
    setCreature(cell:getChildById('creature'), e.look)
    local listed = isListed(e.name)
    cell:setBorderColor(listed and '#5fd35f' or '#1d3557')
    cell:setTooltip(e.name .. '  ' .. dexText(e.num) .. '\n' .. (listed and 'Ja esta na lista' or 'Clique para adicionar'))
    cell.onClick = function() if not isListed(e.name) then sendServer('ADD|' .. e.name) end end
  end
  local info = window:getChildById('resultsInfo')
  if resultsQuery == '' then
    info:setText('Digite parte do nome (ex: pidg, shiny, mega) ou o numero da dex.')
  elseif resultsTotal == 0 then
    info:setText('Nenhum pokemon encontrado para "' .. resultsQuery .. '".')
  elseif resultsTotal > #results then
    info:setText(resultsTotal .. ' encontrados (mostrando ' .. #results .. '). Refine a busca.')
  else
    info:setText(resultsTotal .. ' pokemon(s) encontrado(s).')
  end
end

function refreshWindow()
  if not window then return end
  local toggle = window:getChildById('toggleButton')
  if ballOn then
    toggle:setText('AUTO BALL LIGADO  (clique para desligar)  -  ' .. HOTKEY_BALL)
    toggle:setColor('#5fd35f')
  else
    toggle:setText('AUTO BALL DESLIGADO  (clique para ligar)  -  ' .. HOTKEY_BALL)
    toggle:setColor('#e04848')
  end
  -- bolas
  local bp = window:getChildById('ballsPanel')
  bp:destroyChildren()
  local want = settingBall()
  for _, b in ipairs(ballList) do
    local cell = g_ui.createWidget('ABBall', bp)
    cell:getChildById('itemIcon'):setItemId(b.clientId)
    local cnt = cell:getChildById('count')
    cnt:setText(b.count > 999 and '999+' or tostring(b.count))
    cnt:setColor(b.count > 0 and '#ffffff' or '#e04848')
    local sel = b.key == want
    cell:setBorderColor(sel and '#f2c400' or '#1d3557')
    cell:setBackgroundColor(sel and '#1a3560' or '#0c1828')
    cell:setTooltip(b.name .. '  (voce tem ' .. b.count .. ')' .. (sel and '\nEm uso' or '\nClique para usar esta'))
    cell.onClick = function()
      g_settings.set('codexAutoBall', b.key)
      sendSettings()
      refreshPanel()
      refreshWindow()
    end
  end
  local cb = chosenBall()
  window:getChildById('ballName'):setText(cb and ('Usando: ' .. cb.name) or 'Carregando bolas...')
  -- modos
  local mode = settingMode()
  for _, m in ipairs(MODES) do
    local btn = window:getChildById('mode_' .. m.key)
    if btn then
      btn:setOn(m.key == mode)
      btn:setColor(m.key == mode and '#f2c400' or '#9fb3c8')
    end
  end
  -- lista
  local lp = window:getChildById('listPanel')
  lp:destroyChildren()
  for _, e in ipairs(pokeList) do
    local row = g_ui.createWidget('ABRow', lp)
    setCreature(row:getChildById('creature'), e.look)
    row:getChildById('nameLabel'):setText(e.name)
    row:getChildById('numLabel'):setText(dexText(e.num))
    row:setTooltip(e.name .. (e.name:lower():find('^shiny ') and '' or '\n(vale tambem para o Shiny ' .. e.name .. ')'))
    row:getChildById('removeButton').onClick = function() sendServer('DEL|' .. e.name) end
    -- bola so deste pokemon (vazio = a bola padrao de cima)
    local own = nil
    for _, b in ipairs(ballList) do if b.key == e.ball then own = b end end
    local shown = own or chosenBall()
    local slot = row:getChildById('ballSlot')
    local icon = slot:getChildById('ballIcon')
    if shown then icon:setItemId(shown.clientId) end
    icon:setOpacity(own and 1.0 or 0.35)
    slot:setBorderColor(own and '#f2c400' or '#1d3557')
    slot:setTooltip(own and ('Bola deste pokemon: ' .. own.name .. ' (voce tem ' .. own.count .. ')\nClique para trocar')
      or 'Usa a bola padrao (a marcada em cima)\nClique para escolher uma bola so para ' .. e.name)
    slot.onClick = function(self)
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption('Padrao (a bola de cima)', function() sendServer('LBALL|' .. e.name .. '|') end)
      menu:addSeparator()
      for _, b in ipairs(ballList) do
        menu:addOption(b.name .. '  (x' .. b.count .. ')' .. (b.key == e.ball and '  *' or ''), function()
          sendServer('LBALL|' .. e.name .. '|' .. b.key)
        end)
      end
      menu:display(g_window.getMousePosition())
      return true
    end
  end
  window:getChildById('listTitle'):setText('MINHA LISTA  ' .. #pokeList .. ' / ' .. pokeMax)
  local empty = window:getChildById('emptyLabel')
  if #pokeList == 0 then
    empty:setText(mode == 'lista' and 'Lista vazia: nada sera capturado.' or 'Lista vazia. Ela so vale no modo "So a lista".')
  else
    empty:setText('')
  end
  local note = window:getChildById('modeNote')
  local notes = {todos = 'Joga a bola em todo pokemon que o seu derrotar.',
    nunca = 'So nos que voce ainda nao capturou nenhuma vez.',
    shiny = 'So nos shiny.', lista = 'So nos pokemons da lista abaixo.'}
  note:setText(notes[mode] or '')
  window:getChildById('panelButton'):setText(panels.ball and panels.ball:isVisible() and 'Esconder quadro' or 'Mostrar quadro')
  refreshResults()
end

function setMode(key)
  g_settings.set('codexAutoMode', key)
  sendSettings()
  refreshPanel()
  refreshWindow()
end

function doSearch()
  if not window then return end
  local text = window:getChildById('searchEdit'):getText() or ''
  text = text:gsub('^%s+', ''):gsub('%s+$', ''):gsub('|', '')
  if text == '' then return end
  if #text < 2 and not tonumber(text) then
    window:getChildById('resultsInfo'):setText('Digite pelo menos 2 letras.')
    return
  end
  window:getChildById('resultsInfo'):setText('Buscando...')
  sendServer('SEARCH|' .. text)
end

function clearList()
  if #pokeList == 0 then return end
  sendServer('CLEAR')
end

local function backToGame()
  scheduleEvent(function()
    local root = modules.game_interface.getRootPanel()
    if root then root:focus() end
  end, 1)
end

function openWindow(fromServer)
  if not g_game.isOnline() then return end
  if not window then
    window = g_ui.createWidget('ABWindow', modules.game_interface.getRootPanel())
    window:hide()
    window.onVisibilityChange = function(self, visible)
      -- devolve o foco para o jogo (senao atalhos como o Ctrl+J param ate clicar no mapa)
      if not visible then backToGame() end
    end
    local edit = window:getChildById('searchEdit')
    edit.onKeyPress = function(self, keyCode)
      if keyCode == KeyEnter then doSearch() return true end
      return false
    end
  end
  refreshWindow()
  window:show()
  window:raise()
  window:focus()
  window:getChildById('searchEdit'):focus()
  if not fromServer then sendServer('REQ') end -- codex: o servidor ja manda a lista junto
end

function closeWindow()
  if window then window:hide() end
end

function toggleWindow()
  if window and window:isVisible() then closeWindow() else openWindow() end
end

-- ---------------- quadros ----------------
local DEFS = {
  ball = {style = 'AutoPanel', posKey = 'codexAutoBallPos', hideKey = 'codexAutoBallHidden', dy = 215,
    buttonId = 'autoBallButton', icon = '/images/topbuttons/codex/autoball',
    tip = 'Auto Ball: lista e ajustes (' .. HOTKEY_WINDOW .. ')\nLigar/desligar: ' .. HOTKEY_BALL},
  target = {style = 'AutoPanel', posKey = 'codexAutoTargetPos', hideKey = 'codexAutoTargetHidden', dy = 175,
    buttonId = 'autoTargetButton', icon = '/images/topbuttons/codex/autotarget',
    tip = 'Auto Target: mostrar / esconder o quadro\nLigar/desligar: ' .. HOTKEY_TARGET},
}

local function refreshTopButtons()
  for key, btn in pairs(topButtons) do
    if btn and not btn:isDestroyed() and key == 'target' then btn:setOn(panels[key] ~= nil and panels[key]:isVisible()) end
  end
end

local function placePanel(key)
  local panel, def = panels[key], DEFS[key]
  if not panel then return end
  local root = modules.game_interface.getRootPanel()
  local x, y = string.match(g_settings.getString(def.posKey) or '', '^(%-?%d+),(%-?%d+)$')
  x, y = tonumber(x), tonumber(y)
  local rw, rh = root:getWidth(), root:getHeight()
  if not x or not y or x < 0 or y < 0 or x > rw - 20 or y > rh - 20 then
    x = math.floor(rw / 2) + 180
    y = rh - def.dy
  end
  panel:setPosition({x = x, y = y})
end

local function togglePanel(key)
  local panel = panels[key]
  if not panel then return end
  local show = not panel:isVisible()
  panel:setVisible(show)
  g_settings.set(DEFS[key].hideKey .. 'Shown', show)
  if show then panel:raise() end
  refreshTopButtons()
end
function toggleBallPanel() togglePanel('ball') refreshWindow() end
function toggleTargetPanel() togglePanel('target') end

local function createPanel(key)
  if panels[key] then return end
  local root = modules.game_interface.getRootPanel()
  if not root then return end
  local def = DEFS[key]
  local panel = g_ui.createWidget(def.style, root)
  panels[key] = panel
  local handle = panel:getChildById('handle')
  handle:setTooltip('Arraste para mudar de lugar')
  handle.onDragEnter = function(self, mousePos)
    panel.dragOffset = {x = mousePos.x - panel:getX(), y = mousePos.y - panel:getY()}
    return true
  end
  handle.onDragMove = function(self, mousePos)
    local off = panel.dragOffset or {x = 0, y = 0}
    local parent = panel:getParent()
    panel:setPosition({x = math.max(0, math.min(mousePos.x - off.x, parent:getWidth() - panel:getWidth())),
      y = math.max(0, math.min(mousePos.y - off.y, parent:getHeight() - panel:getHeight()))})
    return true
  end
  handle.onDragLeave = function()
    local pos = panel:getPosition()
    g_settings.set(def.posKey, pos.x .. ',' .. pos.y)
    return true
  end
  local row = panel:getChildById('row')
  if key == 'ball' then
    row:setTooltip('Clique: liga/desliga o Auto Ball\nBotao direito: lista, bola e filtro')
    row.onClick = function() toggleBall() end
    for _, w in ipairs({row, panel}) do
      w.onMouseRelease = function(self, mousePos, button)
        if button == MouseRightButton then openWindow() return true end
        return false
      end
    end
  else
    row:setTooltip('Clique: liga/desliga o Auto Target\nAtaca o selvagem mais perto')
    row.onClick = function() toggleTarget() end
  end
  if not g_settings.getBoolean(def.hideKey .. 'Shown') then panel:setVisible(false) end -- codex itens: escondido ate usar o item
  scheduleEvent(function() placePanel(key) end, 200)
end

local function createTopButtons()
  local tm = modules.client_topmenu
  if not tm or not tm.addCenterGameButton then return end
  for key, def in pairs(DEFS) do
    local btn = topButtons[key]
    if not btn or btn:isDestroyed() then
      topButtons[key] = tm.addCenterGameButton(def.buttonId, def.tip, def.icon,
        key == 'ball' and toggleWindow or toggleTargetPanel)
    end
  end
  refreshTopButtons()
end

local function resetState()
  ballOn, targetOn = false, false
  queue, ballList, blacklist = {}, {}, {}
  targetText = ''
  pokeList, results, resultsTotal, resultsQuery = {}, {}, 0, ''
  lastInfo = ''
  if throwEvent then removeEvent(throwEvent) throwEvent = nil end
  if reqEvent then removeEvent(reqEvent) reqEvent = nil end
end

function onGameStart()
  resetState()
  createPanel('ball')
  createPanel('target')
  refreshPanel()
end

function onGameEnd()
  resetState()
  if window then window:hide() end
  for key, p in pairs(panels) do p:destroy() end
  panels = {}
end

function init()
  g_ui.importStyle('codexauto')
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  local root = modules.game_interface.getRootPanel()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  local root = modules.game_interface.getRootPanel()
  pcall(function() g_keyboard.unbindKeyDown(HOTKEY_BALL, toggleBall, root) end)
  pcall(function() g_keyboard.unbindKeyDown(HOTKEY_TARGET, toggleTarget, root) end)
  pcall(function() g_keyboard.unbindKeyDown(HOTKEY_WINDOW, toggleWindow, root) end)
  resetState()
  for _, btn in pairs(topButtons) do if btn and not btn:isDestroyed() then btn:destroy() end end
  topButtons = {}
  if window then window:destroy() window = nil end
  for _, p in pairs(panels) do p:destroy() end
  panels = {}
end
