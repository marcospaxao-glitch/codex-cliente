-- ============================================================
-- CODEX TM SYSTEM (janela nova)
--   Abre pelo menu do Pokemon (botao direito > TM System).
--   Servidor: data/talkactions/scripts/#tmsystem.lua (opcode 66)
--   Lista com busca e filtro por tipo, detalhes do golpe e os
--   12 slots (M1..M12) mostrando o golpe que esta em cada um.
--   Tambem tira o "EV System" do menu do botao direito.
-- ============================================================
local TYPES = {'normal', 'fire', 'water', 'grass', 'electric', 'ice', 'fighting', 'poison', 'ground',
  'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy'}
local TYPE_PT = {normal = 'Normal', fire = 'Fogo', water = 'Agua', grass = 'Planta', electric = 'Eletrico',
  ice = 'Gelo', fighting = 'Lutador', poison = 'Veneno', ground = 'Terra', flying = 'Voador',
  psychic = 'Psiquico', bug = 'Inseto', rock = 'Pedra', ghost = 'Fantasma', dragon = 'Dragao',
  dark = 'Sombrio', steel = 'Aco', fairy = 'Fada'}
local IMG = '/modules/game_tmsystem/interface/'

local moves = {}            -- {name, cd, cost, target, range, level, tipo}
local info = {poke = '', level = 0, disks = 0, slots = {}}
local filterType, query = nil, ''
local selectedMove, selectedSlot = nil, nil
local confirmBox = nil
local typeChips = {}

local function cap(s)
  return (tostring(s or ''):gsub("(%a)([%w%-']*)", function(a, b) return a:upper() .. b end))
end

local function iconOf(m)
  return IMG .. m.tipo .. '.png'
end

-- icone igual ao da barra de moves (modules/game_pokemonmoves)
local function setMoveIcon(widget, name, tipo, size)
  local pm = modules.game_pokemonmoves
  if pm and pm.applyMoveIcon and pcall(pm.applyMoveIcon, widget, name, size) then return end
  widget:setImageSource(tipo and (IMG .. tipo .. '.png') or '')
end

local function costText(m)
  if tonumber(m.cost) then return m.cost .. 'x' end
  return '1 ' .. cap(m.cost)
end

local function canPay(m)
  if not tonumber(m.cost) then return true end
  return info.disks >= tonumber(m.cost)
end

-- ---------------- tela ----------------
local function updateDetail()
  local d = tmsystem:recursiveGetChildById('detailPanel')
  local m = selectedMove
  local big = d:getChildById('bigIcon')
  if m then setMoveIcon(big, m.name, m.tipo, 40) else big:setImageSource('') local g = big:getChildById('codexGlyph') if g then g:setVisible(false) end end
  d:getChildById('moveName'):setText(m and cap(m.name) or 'Escolha um golpe na lista')
  d:getChildById('moveType'):setText(m and ('Tipo ' .. (TYPE_PT[m.tipo] or cap(m.tipo))) or '')
  if m then
    local lines = {
      'Nivel minimo: ' .. m.level .. '     Recarga: ' .. (m.cd / 1000) .. 's',
      'Alvo: ' .. (m.target == '1' and 'Sim' or 'Nao') .. (m.range ~= '0' and ('     Alcance: ' .. m.range) or ''),
      'Custo: ' .. (tonumber(m.cost) and (m.cost .. 'x Clean Disk') or ('1 ' .. cap(m.cost)))
    }
    d:getChildById('moveStats'):setText(table.concat(lines, '\n'))
  else
    d:getChildById('moveStats'):setText('')
  end

  local sp = d:getChildById('slotPanel')
  sp:destroyChildren()
  for i = 1, 12 do
    local b = g_ui.createWidget('TMSlotButton', sp)
    b:getChildById('slot'):setText('M' .. i)
    local cur = info.slots[i] or '-'
    b:getChildById('move'):setText(cur ~= '-' and cap(cur) or '(vazio)')
    b:getChildById('move'):setColor(cur ~= '-' and '#c9d6e6' or '#5f7596')
    if cur ~= '-' then setMoveIcon(b:getChildById('icon'), cur, nil, 16) else b:getChildById('icon'):hide() end
    b:setOn(selectedSlot == i)
    b:setTooltip(cur ~= '-' and ('M' .. i .. ': ' .. cap(cur) .. '\nEnsinar aqui substitui esse golpe.') or ('M' .. i .. ': livre'))
    b.onClick = function() selectedSlot = i updateDetail() end
  end

  local hint, btn = d:getChildById('hintLabel'), d:getChildById('learnButton')
  local ok = m ~= nil and selectedSlot ~= nil
  local why = ''
  if m and info.level < m.level then ok = false why = 'Seu pokemon precisa do nivel ' .. m.level .. '.' end
  if m and not canPay(m) then ok = false why = 'Clean Disk insuficiente (' .. info.disks .. '/' .. m.cost .. ').' end
  if m and selectedSlot and (info.slots[selectedSlot] or '-') ~= '-' and why == '' then
    why = 'Vai substituir ' .. cap(info.slots[selectedSlot]) .. ' no M' .. selectedSlot .. '.'
  elseif m and not selectedSlot and why == '' then
    why = 'Escolha um slot acima.'
  end
  hint:setText(why)
  hint:setColor(ok and '#8fa7c4' or '#ff9a7a')
  btn:setEnabled(ok)
end

local function rebuildList()
  local lp = tmsystem:recursiveGetChildById('listPanel')
  lp:destroyChildren()
  local q = query:lower()
  local shown = 0
  for _, m in ipairs(moves) do
    if (not filterType or m.tipo == filterType) and (q == '' or m.name:find(q, 1, true)) then
      shown = shown + 1
      local row = g_ui.createWidget('TMRow', lp)
      setMoveIcon(row:getChildById('icon'), m.name, m.tipo, 24)
      row:getChildById('name'):setText(cap(m.name))
      local lvOk = info.level >= m.level
      row:getChildById('info'):setText((TYPE_PT[m.tipo] or cap(m.tipo)) .. '  -  Nv ' .. m.level .. '  -  ' .. (m.cd / 1000) .. 's')
      row:getChildById('info'):setColor(lvOk and '#8fa7c4' or '#ff7070')
      row:getChildById('cost'):setText(costText(m))
      row:getChildById('cost'):setColor(canPay(m) and '#f2c400' or '#ff7070')
      row:setOn(selectedMove == m)
      row.onClick = function()
        selectedMove = m
        for _, c in ipairs(lp:getChildren()) do c:setOn(false) end
        row:setOn(true)
        updateDetail()
      end
    end
  end
  if shown == 0 then
    local row = g_ui.createWidget('TMRow', lp)
    row:getChildById('name'):setText('Nenhum golpe encontrado')
    row:getChildById('info'):setText('')
    row:getChildById('cost'):setText('')
  end
end

local function rebuildTypes()
  local tp = tmsystem:recursiveGetChildById('typePanel')
  tp:destroyChildren()
  typeChips = {}
  local present = {}
  for _, m in ipairs(moves) do present[m.tipo] = true end
  local all = g_ui.createWidget('TMTypeChip', tp)
  all:setImageSource(IMG .. 'tm system.png')
  all:setTooltip('Todos os tipos')
  all:setOn(filterType == nil)
  all.onClick = function() filterType = nil rebuildTypes() rebuildList() end
  for _, t in ipairs(TYPES) do
    if present[t] then
      local chip = g_ui.createWidget('TMTypeChip', tp)
      chip:setImageSource(IMG .. t .. '.png')
      chip:setTooltip(TYPE_PT[t])
      chip:setOn(filterType == t)
      chip.onClick = function() filterType = (filterType == t) and nil or t rebuildTypes() rebuildList() end
    end
  end
end

local function refreshAll()
  tmsystem:getChildById('pokeLabel'):setText(info.poke ~= '' and (info.poke .. '  (Nv ' .. info.level .. ')') or '')
  tmsystem:getChildById('diskLabel'):setText('Clean Disk: ' .. info.disks)
  local di = tmsystem:getChildById('diskItem')
  if di and info.diskClient > 0 then di:setItemId(info.diskClient) di:show() elseif di then di:hide() end
  rebuildTypes()
  rebuildList()
  updateDetail()
end

-- ---------------- servidor ----------------
function parse(protocol, opcode, buffer)
  buffer = buffer or ''
  local list, extra = buffer, nil
  local cut = buffer:find('#CODEX#', 1, true)
  if cut then list, extra = buffer:sub(1, cut - 1), buffer:sub(cut + 7) end
  local f = {}
  for v in string.gmatch(list, '([^|]+)') do f[#f + 1] = v end
  local keepName = selectedMove and selectedMove.name
  moves = {}
  for i = 1, #f - 6, 7 do
    moves[#moves + 1] = {name = f[i], cd = tonumber(f[i + 1]) or 0, cost = f[i + 2], target = f[i + 3],
      range = f[i + 4], level = tonumber(f[i + 5]) or 1, tipo = tostring(f[i + 6]):lower()}
  end
  table.sort(moves, function(a, b) if a.tipo ~= b.tipo then return a.tipo < b.tipo end return a.level < b.level end)
  info = {poke = '', level = 999, disks = 0, slots = {}, diskClient = 0}
  if extra then
    local e = {}
    for v in string.gmatch(extra .. '|', '(.-)|') do e[#e + 1] = v end
    info.poke = e[1] or ''
    info.level = tonumber(e[2]) or 999
    info.disks = tonumber(e[3]) or 0
    info.diskClient = tonumber(e[5]) or 0
    local i = 0
    for v in string.gmatch((e[4] or '') .. ';', '(.-);') do i = i + 1 info.slots[i] = v end
  end
  selectedMove = nil
  for _, m in ipairs(moves) do if m.name == keepName then selectedMove = m end end
  show()
  refreshAll()
end

local function doLearn()
  local m, s = selectedMove, selectedSlot
  if not m or not s or confirmBox then return end
  local yes = function()
    g_game.talk('#tmsystem ' .. m.name .. '|' .. s)
    confirmBox:destroy() confirmBox = nil
    -- o servidor solta o pokemon de novo; pede a lista atualizada
    -- codex tm sem timer: o servidor manda a janela atualizada sozinho (o timer era bloqueado pelo anti-bot)
  end
  local no = function() confirmBox:destroy() confirmBox = nil end
  local cur = info.slots[s] or '-'
  local text = 'Ensinar ' .. cap(m.name) .. ' no M' .. s .. '?' .. (cur ~= '-' and ('\nO golpe ' .. cap(cur) .. ' sera substituido.') or '')
  confirmBox = displayGeneralBox('TM System', text, {{text = 'Sim', callback = yes}, {text = 'Nao', callback = no}, anchor = AnchorHorizontalCenter}, yes, no)
end

-- ---------------- menu do botao direito: tira o "EV System" ----------------
local origAddOption = nil
local function hookMenu()
  if origAddOption or not UIPopupMenu or type(UIPopupMenu.addOption) ~= 'function' then return end
  origAddOption = UIPopupMenu.addOption
  UIPopupMenu.addOption = function(self, text, ...)
    if text == 'EV System' or text == tr('EV System') then return end
    return origAddOption(self, text, ...)
  end
end
local function unhookMenu()
  if origAddOption and UIPopupMenu then UIPopupMenu.addOption = origAddOption end
  origAddOption = nil
end

-- ---------------- modulo ----------------
function hide()
  if tmsystem and tmsystem:isVisible() then tmsystem:hide() end
  if confirmBox then confirmBox:destroy() confirmBox = nil end
end

function show()
  tmsystem:show()
  tmsystem:raise()
  tmsystem:focus()
end

function init()
  tmsystem = g_ui.displayUI('tmsystem')
  tmsystem:hide()
  tmsystem.onVisibilityChange = function(self, visible)
    if not visible then
      scheduleEvent(function() local r = modules.game_interface.getRootPanel() if r then r:focus() end end, 1)
    end
  end
  local edit = tmsystem:recursiveGetChildById('searchEdit')
  edit.onTextChange = function(self, text) query = text or '' rebuildList() end
  tmsystem:recursiveGetChildById('learnButton').onClick = doLearn
  connect(g_game, {onGameEnd = hide})
  ProtocolGame.registerExtendedOpcode(66, parse)
  hookMenu()
end

function terminate()
  disconnect(g_game, {onGameEnd = hide})
  pcall(function() ProtocolGame.unregisterExtendedOpcode(66) end)
  unhookMenu()
  if tmsystem then tmsystem:destroy() tmsystem = nil end
end
