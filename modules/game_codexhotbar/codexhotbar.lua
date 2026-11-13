-- ============================================================
-- HOTBAR (Codex) = as mesmas HOTKEYS da janela Hotkeys (Ctrl+K)
-- Cada espaco e uma hotkey (F1, F2..., Shift+F1...). Clicar no espaco
-- faz o mesmo que apertar a tecla. Mudou na janela Hotkeys, a hotbar
-- muda junto (e vice-versa).
-- Arraste um item da mochila para um espaco: a hotkey passa a usar
-- aquele item. Arraste um espaco para outro: troca as duas hotkeys.
-- Botao direito: como usar o item (normal, no Pokemon, em mim, no
-- alvo, com mira), limpar, abrir Hotkeys, mostrar todas/so as usadas.
-- A quantidade do item vem do servidor (opcode 110).
-- ============================================================

local SIZE = 36
local GAP = 4
local PAD = 6
local HANDLE = 12
local MAX_SLOTS = 24
local SETTINGS_KEY = 'codexHotbar'
local OPCODE_COUNTS = 110

-- mesmos numeros do game_hotkeys
local USE, USE_SELF, USE_TARGET, USE_WITH, USE_SUMMON = nil, 1, 2, 3, 4
local MODES = {
  {key = 'auto', use = USE, label = nil, text = 'Usar (mira se precisar)'},
  {key = 'summon', use = USE_SUMMON, label = 'P', text = 'Usar no meu Pokemon'},
  {key = 'self', use = USE_SELF, label = 'V', text = 'Usar em mim'},
  {key = 'target', use = USE_TARGET, label = 'A', text = 'Usar no alvo'},
  {key = 'crosshair', use = USE_WITH, label = 'M', text = 'Usar com mira'},
}
local function modeOf(useType)
  for _, m in ipairs(MODES) do if m.use == useType then return m end end
  return MODES[1]
end

local bar = nil
local slotsPanel = nil
local slotWidgets = {}
local list = {}            -- hotkeys mostradas: {combo, itemId, subType, useType, value, autoSend}
local options = {side = 'horizontal', hidden = false, locked = false, pos = nil, showAll = true}
local topButton = nil
local countEvent = nil
local dragRef = nil
local serverCounts = nil

local function HK() return modules.game_hotkeys end

-- ============================================================
-- opcoes (posicao, lado...) por PC
-- ============================================================
local function charKey()
  local name = g_game.getCharacterName and g_game.getCharacterName() or ''
  return (G and G.host or '') .. '|' .. tostring(name)
end

local function loadOptions()
  local node = g_settings.getNode(SETTINGS_KEY) or {}
  local o = node.options
  if type(o) == 'table' then
    if o.side == 'vertical' or o.side == 'horizontal' then options.side = o.side end
    options.hidden = o.hidden == true or o.hidden == 'true'
    options.locked = o.locked == true or o.locked == 'true'
    options.showAll = not (o.showAll == false or o.showAll == 'false')
    if tonumber(o.x) and tonumber(o.y) then options.pos = {x = tonumber(o.x), y = tonumber(o.y)} end
  end
  return node
end

local function saveOptions()
  local node = g_settings.getNode(SETTINGS_KEY) or {}
  node.options = {side = options.side, hidden = options.hidden, locked = options.locked, showAll = options.showAll}
  if options.pos then node.options.x = options.pos.x; node.options.y = options.pos.y end
  g_settings.setNode(SETTINGS_KEY, node)
end

-- a hotbar antiga guardava itens em Shift+F1..F8: passa para as hotkeys (uma vez)
local function migrateOld()
  local node = g_settings.getNode(SETTINGS_KEY) or {}
  node.migrated = type(node.migrated) == 'table' and node.migrated or {}
  local key = charKey()
  if node.migrated[key] then return end
  local saved = node.chars and node.chars[key]
  local hk = HK()
  if type(saved) == 'string' and hk and hk.setHotkey then
    local current = {}
    for _, h in ipairs(hk.getHotkeyList()) do current[h.combo] = h end
    local i = 0
    for part in (saved .. ';'):gmatch('([^;]*);') do
      i = i + 1
      local id, sub, mode = part:match('^(%d+):(%-?%d*):(%a*)$')
      local combo = 'Shift+F' .. i
      local cur = current[combo]
      local empty = not cur or (not cur.itemId and (not cur.value or cur.value == ''))
      if id and tonumber(id) and tonumber(id) > 0 and empty then
        local use = USE
        for _, m in ipairs(MODES) do if m.key == mode then use = m.use end end
        hk.setHotkey(combo, {itemId = tonumber(id), subType = tonumber(sub), useType = use})
      end
      if i >= 8 then break end
    end
  end
  node.migrated[key] = true
  g_settings.setNode(SETTINGS_KEY, node)
end

-- ============================================================
-- contagem
-- ============================================================
local function countItem(itemId)
  if serverCounts then return serverCounts[itemId] or 0 end
  local total = 0
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  for slot = 1, 10 do
    local item = player:getInventoryItem(slot)
    if item and item:getId() == itemId then total = total + math.max(1, item:getCount()) end
  end
  for _, container in pairs(g_game.getContainers()) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then total = total + math.max(1, item:getCount()) end
    end
  end
  return total
end

local function refreshCounts()
  countEvent = nil
  for i, widget in pairs(slotWidgets) do
    local label = widget:getChildById('countLabel')
    local h = list[i]
    if h and h.itemId then
      local n = countItem(h.itemId)
      label:setText(n > 999 and '999+' or tostring(n))
      label:setVisible(true)
      label:setColor(n > 0 and '#dce8f5' or '#ff6b6b')
      widget:setOpacity(n > 0 and 1.0 or 0.55)
    else
      label:setVisible(false)
      widget:setOpacity(1.0)
    end
  end
end

local function scheduleCounts()
  if countEvent then return end
  countEvent = scheduleEvent(refreshCounts, 150)
end

-- ============================================================
-- textos
-- ============================================================
local function shortKey(combo)
  combo = tostring(combo or '')
  combo = combo:gsub('Shift%+', 'S+'):gsub('Ctrl%+', 'C+'):gsub('Alt%+', 'A+')
  return combo
end

local function shortValue(v)
  v = tostring(v or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if v == '' then return '' end
  local last = v:match('(%S+)$') or v
  last = last:gsub('^[#!/]+', '')
  if #last > 5 then last = last:sub(1, 5) end
  return last
end

-- ============================================================
-- espacos
-- ============================================================
local rebuild

local function save(h)
  local hk = HK()
  if hk and hk.setHotkey then hk.setHotkey(h.combo, h) end
end

local function slotMenu(i)
  local menu = g_ui.createWidget('PopupMenu')
  local h = i > 0 and list[i] or nil
  if h and h.itemId then
    local cur = modeOf(h.useType)
    for _, m in ipairs(MODES) do
      menu:addOption((cur.key == m.key and '> ' or '   ') .. m.text, function()
        h.useType = m.use
        save(h)
      end)
    end
    menu:addSeparator()
  end
  if h and (h.itemId or (h.value and h.value ~= '')) then
    menu:addOption('Limpar ' .. h.combo, function() save({combo = h.combo}) end)
    menu:addSeparator()
  end
  menu:addOption('Abrir Hotkeys (Ctrl+K)', function() if HK() and HK().show then HK().show() end end)
  menu:addOption(options.showAll and 'Mostrar so as hotkeys usadas' or 'Mostrar todas as hotkeys', function()
    options.showAll = not options.showAll
    saveOptions()
    rebuild()
  end)
  menu:addOption(options.side == 'horizontal' and 'Hotbar na vertical' or 'Hotbar na horizontal', function()
    options.side = options.side == 'horizontal' and 'vertical' or 'horizontal'
    saveOptions()
    rebuild()
  end)
  menu:addOption(options.locked and 'Destravar posicao' or 'Travar posicao', function()
    options.locked = not options.locked
    saveOptions()
    rebuild()
  end)
  menu:addOption('Esconder hotbar', function() setHidden(true) end)
  menu:display()
end

local function updateSlot(i)
  local widget = slotWidgets[i]
  if not widget then return end
  local h = list[i]
  local modeLabel = widget:getChildById('modeLabel')
  local textLabel = widget:getChildById('textLabel')
  widget:getChildById('keyLabel'):setText(shortKey(h.combo))
  if h.itemId then
    widget:setItemId(h.itemId)
    if h.subType then pcall(function() widget:setItemSubType(h.subType) end) end
    local m = modeOf(h.useType)
    modeLabel:setText(m.label or '')
    modeLabel:setVisible(m.label ~= nil)
    textLabel:setVisible(false)
    local name = ''
    pcall(function() name = widget:getItem():getMarketData().name end)
    widget:setTooltip((name ~= '' and (name .. '\n') or '') .. h.combo .. '  -  ' .. m.text .. '\nBotao direito: opcoes')
  else
    widget:clearItem()
    modeLabel:setVisible(false)
    local sv = shortValue(h.value)
    textLabel:setText(sv)
    textLabel:setVisible(sv ~= '')
    textLabel:setColor(h.autoSend and '#dce8f5' or '#8fa7c4')
    if sv ~= '' then
      widget:setTooltip(h.combo .. ': ' .. tostring(h.value) .. (h.autoSend and '' or '\n(so escreve no chat)') .. '\nBotao direito: opcoes')
    else
      widget:setTooltip(h.combo .. ' (vazio)\nArraste um item da mochila para ca')
    end
  end
end

local function onSlotDrop(self, widget, mousePos)
  if not widget then return false end
  local mine = list[self.hotbarIndex]
  if not mine then return false end
  -- troca entre espacos (troca o conteudo das duas hotkeys)
  if widget.hotbarIndex then
    local other = list[widget.hotbarIndex]
    if not other or other == mine then return true end
    local a = {combo = mine.combo, itemId = other.itemId, subType = other.subType, useType = other.useType, value = other.value, autoSend = other.autoSend}
    local b = {combo = other.combo, itemId = mine.itemId, subType = mine.subType, useType = mine.useType, value = mine.value, autoSend = mine.autoSend}
    save(a); save(b)
    return true
  end
  -- item vindo da mochila / equipamento
  local item = widget.getItem and widget:getItem()
  if not item then return false end
  local h = {combo = mine.combo, itemId = item:getId(), useType = item:isMultiUse() and USE_WITH or USE}
  if item:isFluidContainer() then h.subType = item:getSubType() end
  save(h)
  return true
end

local function handleSize()
  return options.locked and 0 or HANDLE
end

local function readList()
  list = {}
  local hk = HK()
  if not hk or not hk.getHotkeyList then return end
  for _, h in ipairs(hk.getHotkeyList()) do
    local used = h.itemId or (h.value and h.value ~= '')
    if options.showAll or used then list[#list + 1] = h end
    if #list >= MAX_SLOTS then break end
  end
end

rebuild = function()
  if not bar then return end
  readList()
  slotsPanel:destroyChildren()
  slotWidgets = {}
  local n = math.max(1, #list)
  for i = 1, #list do
    local widget = g_ui.createWidget('HotbarSlot', slotsPanel)
    widget:setId('slot' .. i)
    widget.hotbarIndex = i
    if options.side == 'horizontal' then
      widget:setMarginLeft(PAD + handleSize() + (i - 1) * (SIZE + GAP))
      widget:setMarginTop(PAD + 1)
    else
      widget:setMarginLeft(PAD)
      widget:setMarginTop(PAD + 1 + handleSize() + (i - 1) * (SIZE + GAP))
    end
    widget.onDrop = onSlotDrop
    widget.onDragEnter = function(self, mousePos)
      local h = list[self.hotbarIndex]
      if not h or not (h.itemId or (h.value and h.value ~= '')) then return false end
      g_mouse.pushCursor('target')
      return true
    end
    widget.onDragLeave = function(self, droppedWidget, mousePos)
      g_mouse.popCursor('target')
      return true
    end
    widget.onMouseRelease = function(self, mousePos, mouseButton)
      if mouseButton == MouseLeftButton and self:containsPoint(mousePos) then
        local h = list[self.hotbarIndex]
        if h and HK() and HK().runHotkey then HK().runHotkey(h.combo) end
        return true
      end
      return false
    end
    g_mouse.bindPress(widget, function() slotMenu(i) end, MouseRightButton)
    slotWidgets[i] = widget
    updateSlot(i)
  end
  local length = PAD * 2 + n * SIZE + (n - 1) * GAP + handleSize()
  local thick = PAD * 2 + SIZE + 1
  local handle = bar:getChildById('dragHandle')
  handle:setVisible(not options.locked)
  handle:breakAnchors()
  handle:addAnchor(AnchorTop, 'parent', AnchorTop)
  handle:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  handle:setMarginTop(2)
  if options.side == 'horizontal' then
    bar:setSize({width = length, height = thick})
    handle:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    handle:setWidth(HANDLE)
  else
    bar:setSize({width = thick, height = length + 1})
    handle:addAnchor(AnchorRight, 'parent', AnchorRight)
    handle:setHeight(HANDLE)
  end
  placeBar()
  scheduleCounts()
end

function placeBar()
  if not bar then return end
  bar:breakAnchors()
  if options.pos then
    bar:setPosition(options.pos)
  else
    local size = rootWidget:getSize()
    bar:setPosition({x = math.floor((size.width - bar:getWidth()) / 2), y = size.height - bar:getHeight() - 200})
  end
  pcall(function() bar:bindRectToParent() end)
end

function setHidden(value)
  options.hidden = value
  saveOptions()
  if bar then
    if value or not g_game.isOnline() then bar:hide() else bar:show() bar:raise() end
  end
  if topButton and topButton.setOn then topButton:setOn(not value) end
end

function toggle()
  setHidden(not options.hidden)
end

-- ============================================================
-- ciclo de vida
-- ============================================================
local function onCounts(protocol, opcode, buffer)
  serverCounts = {}
  for id, n in (buffer or ''):gmatch('(%d+):(%d+)') do
    serverCounts[tonumber(id)] = tonumber(n)
  end
  scheduleCounts()
end

local rebuildPending = false
local function onHotkeysChanged()
  if rebuildPending then return end
  rebuildPending = true
  scheduleEvent(function()
    rebuildPending = false
    if bar and g_game.isOnline() then rebuild() end
  end, 50)
end

local function onGameStart()
  serverCounts = nil
  loadOptions()
  scheduleEvent(function()
    migrateOld()
    rebuild()
    setHidden(options.hidden)
  end, 200)
end

local function onGameEnd()
  serverCounts = nil
  if bar then bar:hide() end
end

function init()
  bar = g_ui.displayUI('codexhotbar')
  slotsPanel = bar:getChildById('slots')
  bar:hide()

  local handle = bar:getChildById('dragHandle')
  handle.onDragEnter = function(self, mousePos)
    if options.locked then return false end
    bar:breakAnchors()
    dragRef = {x = mousePos.x - bar:getX(), y = mousePos.y - bar:getY()}
    return true
  end
  handle.onDragMove = function(self, mousePos, mouseMoved)
    if not dragRef then return false end
    bar:setPosition({x = mousePos.x - dragRef.x, y = mousePos.y - dragRef.y})
    pcall(function() bar:bindRectToParent() end)
    return true
  end
  handle.onDragLeave = function(self)
    dragRef = nil
    options.pos = {x = bar:getX(), y = bar:getY()}
    saveOptions()
    return true
  end
  g_mouse.bindPress(handle, function() slotMenu(0) end, MouseRightButton)

  local ok, button = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton('codexHotbarButton', 'Hotbar (as mesmas teclas do Hotkeys)', '/images/topbuttons/codex/hotbar', toggle)
  end)
  if ok and button then topButton = button end

  if HK() and HK().onHotkeysChanged then HK().onHotkeysChanged(onHotkeysChanged) end
  ProtocolGame.registerExtendedOpcode(OPCODE_COUNTS, onCounts)
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  connect(Container, {onOpen = scheduleCounts, onClose = scheduleCounts, onAddItem = scheduleCounts,
                      onRemoveItem = scheduleCounts, onUpdateItem = scheduleCounts})
  connect(LocalPlayer, {onInventoryChange = scheduleCounts})
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE_COUNTS)
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  disconnect(Container, {onOpen = scheduleCounts, onClose = scheduleCounts, onAddItem = scheduleCounts,
                         onRemoveItem = scheduleCounts, onUpdateItem = scheduleCounts})
  disconnect(LocalPlayer, {onInventoryChange = scheduleCounts})
  if countEvent then removeEvent(countEvent) countEvent = nil end
  if topButton then topButton:destroy() topButton = nil end
  if bar then bar:destroy() bar = nil end
end
