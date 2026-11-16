-- ============================================================
-- BARRA DE MOVES (Codex)
-- Base: spell bar de Pota/drakylucas. Mesmo opcode 52 e mesmo
-- formato que o servidor ja manda (doReleaseSummon):
--   nomes, recarga, recarga restante, level, liberado(1/0), level do pokemon
--
-- Icones: moveicons.lua (fundo do tipo + simbolo pelo nome).
-- Clique esquerdo: usa a move (m1..m12, igual ao atalho).
-- Clique direito: horizontal/vertical, numeros, travar posicao.
-- Arraste a barra para mover (a posicao fica salva).
-- ============================================================

local OPCODE_SKILLBAR = 52
local MAX_MOVES = 12
local SLOT = 36
local GAP = 4
local PAD = 6
local SETTINGS_KEY = 'codexMovesBar'

local TYPE_NAMES = {
  fire = 'Fogo', grass = 'Planta', water = 'Agua', electric = 'Eletrico', ice = 'Gelo',
  fighting = 'Lutador', poison = 'Veneno', ground = 'Terra', flying = 'Voador',
  psychic = 'Psiquico', bug = 'Inseto', rock = 'Pedra', ghost = 'Fantasma',
  dragon = 'Dragao', dark = 'Sombrio', steel = 'Aco', fairy = 'Fada', normal = 'Normal'
}

local sbw = nil
local mainPanel = nil
local spells = {}
local slots = {}          -- [i] = widget
local level = 0
local options = {side = 'horizontal', numbers = true, locked = false, pos = nil}
local tickEvent = nil

-- ============================================================
-- opcoes
-- ============================================================
local function loadOptions()
  local saved = g_settings.getNode(SETTINGS_KEY)
  if type(saved) == 'table' then
    if saved.side == 'vertical' or saved.side == 'horizontal' then options.side = saved.side end
    if saved.numbers ~= nil then options.numbers = saved.numbers == true or saved.numbers == 'true' end
    if saved.locked ~= nil then options.locked = saved.locked == true or saved.locked == 'true' end
    if tonumber(saved.x) and tonumber(saved.y) then
      options.pos = {x = tonumber(saved.x), y = tonumber(saved.y)}
    end
  end
end

local function saveOptions()
  local node = {side = options.side, numbers = options.numbers, locked = options.locked}
  if options.pos then
    node.x = options.pos.x
    node.y = options.pos.y
  end
  g_settings.setNode(SETTINGS_KEY, node)
end

-- ============================================================
-- recarga
-- ============================================================
local function setCooling(widget, cooling)
  widget:setImageColor(cooling and '#6a6a6a' or '#e6e6e6')
  local glyph = widget:getChildById('glyph')
  if glyph then
    local base = widget.glyphColor or '#ffffff'
    glyph:setImageColor(cooling and '#7a7a7a' or base)
  end
end

local function updateSlot(widget)
  local cooldown = widget:getChildById('cooldown')
  if not widget.cdEnd then
    cooldown:setPercent(100)
    cooldown:setText('')
    return false
  end
  local now = g_clock.millis()
  local left = widget.cdEnd - now
  if left <= 0 then
    widget.cdEnd = nil
    cooldown:setPercent(100)
    cooldown:setText('')
    setCooling(widget, false)
    return false
  end
  local total = math.max(1, widget.cdTotal or 1)
  cooldown:setPercent(math.max(0, math.min(99, math.floor((1 - left / total) * 100))))
  if left >= 10000 then
    cooldown:setText(math.ceil(left / 1000))
  else
    cooldown:setText(string.format('%.1f', left / 1000))
  end
  return true
end

local function tick()
  tickEvent = nil
  local running = false
  for _, widget in pairs(slots) do
    if updateSlot(widget) then running = true end
  end
  if running then
    tickEvent = scheduleEvent(tick, 100)
  end
end

local function ensureTick()
  if not tickEvent then
    tickEvent = scheduleEvent(tick, 50)
  end
end

local function startCooldown(i, total, remaining)
  local widget = slots[i]
  if not widget then return end
  total = tonumber(total) or 0
  remaining = tonumber(remaining) or total
  if total <= 0 or remaining <= 0 then return end
  widget.cdTotal = total
  widget.cdEnd = g_clock.millis() + remaining
  setCooling(widget, true)
  updateSlot(widget)
  ensureTick()
end

-- ============================================================
-- arrastar: pela alca (pontinhos na ponta da barra)
-- ============================================================
local HANDLE = (type(codexCelular) == 'function' and codexCelular()) and 24 or 12 -- CODEX: alca maior no celular (dedo)
local dragRef = nil

local function setupHandle()
  local handle = sbw:getChildById('dragHandle')
  handle.onDragEnter = function(self, mousePos)
    if options.locked then return false end
    sbw:breakAnchors()
    dragRef = {x = mousePos.x - sbw:getX(), y = mousePos.y - sbw:getY()}
    return true
  end
  handle.onDragMove = function(self, mousePos, mouseMoved)
    if not dragRef then return false end
    sbw:setPosition({x = mousePos.x - dragRef.x, y = mousePos.y - dragRef.y})
    pcall(function() sbw:bindRectToParent() end)
    return true
  end
  handle.onDragLeave = function(self, droppedWidget, mousePos)
    dragRef = nil
    options.pos = {x = sbw:getX(), y = sbw:getY()}
    saveOptions()
    return true
  end
end

function handleSize()
  return options.locked and 0 or HANDLE
end

local function layoutHandle(length)
  local handle = sbw:getChildById('dragHandle')
  handle:setVisible(not options.locked)
  handle:breakAnchors()
  handle:addAnchor(AnchorTop, 'parent', AnchorTop)
  handle:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  if options.side == 'horizontal' then
    handle:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    handle:setWidth(HANDLE)
    handle:setMarginTop(2)
    handle:setMarginLeft(0)
  else
    handle:addAnchor(AnchorRight, 'parent', AnchorRight)
    handle:setHeight(HANDLE)
    handle:setMarginTop(2)
    handle:setMarginLeft(0)
  end
end

-- ============================================================
-- nome da move ao passar o mouse
-- ============================================================
local tip = nil

local function showTip(widget)
  if not tip then
    tip = g_ui.createWidget('MoveTip', rootWidget)
  end
  tip:getChildById('tipName'):setText(widget.tipName or '')
  tip:getChildById('tipInfo'):setText(widget.tipInfo or '')
  local nameW = tip:getChildById('tipName'):getWidth()
  local infoW = tip:getChildById('tipInfo'):getWidth()
  local w = math.max(nameW, infoW) + 12
  local h = tip:getChildById('tipName'):getHeight() + tip:getChildById('tipInfo'):getHeight() + 10
  tip:setSize({width = w, height = h})
  local pos = widget:getPosition()
  local x = pos.x + math.floor((widget:getWidth() - w) / 2)
  local y = pos.y - h - 8
  if y < 0 then y = pos.y + widget:getHeight() + 8 end
  local rootW = rootWidget:getWidth()
  x = math.max(2, math.min(x, rootW - w - 2))
  tip:setPosition({x = x, y = y})
  tip:show()
  tip:raise()
end

local function hideTip()
  if tip then tip:hide() end
end

-- ============================================================
-- montagem da barra
-- ============================================================
local function clearSlots()
  if tip then tip:hide() end
  for _, widget in pairs(slots) do
    widget:destroy()
  end
  slots = {}
end

local function placeWindow()
  if not sbw then return end
  if options.pos then
    sbw:breakAnchors()
    sbw:setPosition(options.pos)
    pcall(function() sbw:bindRectToParent() end)
  else
    local root = sbw:getParent()
    if root then
      local size = root:getSize()
      sbw:setPosition({x = math.floor((size.width - sbw:getWidth()) / 2), y = size.height - sbw:getHeight() - 140})
    end
  end
end

-- CODEX celular: na primeira vez a barra vai para o alto, centralizada.
-- Se o jogador ja arrastou a barra neste aparelho, respeita a posicao dele.
function codexModoCelular(y)
  if not sbw or options.pos then return end
  local root = sbw:getParent()
  if not root then return end
  options.pos = { x = math.floor((root:getWidth() - sbw:getWidth()) / 2), y = y or 6 }
  placeWindow()
end

local function prettyName(words)
  return (tostring(words or ''):gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

-- devolve: nome da move, linhas de detalhe
local function tooltipFor(spell, icon)
  local typeName = TYPE_NAMES[icon.type] or icon.type
  local lines = {
    'Tipo: ' .. typeName .. '   Nivel: ' .. tostring(spell.lvl or 0),
    'Recarga: ' .. tostring(math.floor((spell.exhaustion or 0) / 100) / 10) .. ' s'
  }
  if level and spell.lvl and level < spell.lvl then
    table.insert(lines, 'Seu Pokemon precisa do nivel ' .. spell.lvl)
  end
  return prettyName(spell.words), table.concat(lines, '\n')
end

function getSpells(list)
  if not sbw or not mainPanel then return end
  clearSlots()
  local shown = 0
  for i = 1, #list do
    local spell = list[i]
    -- Pokemon Manager: moves ainda nao compradas com pontos nao aparecem
    if spell.unlocked ~= 0 then
      shown = shown + 1
      local icon = getMoveIcon(spell.words)
      local widget = g_ui.createWidget('MoveSlot', mainPanel)
      widget:setId('spell' .. i)
      if icon.custom then
        widget:setImageSource(icon.custom)
        widget:getChildById('glyph'):setVisible(false)
      else
        widget:setImageSource(icon.background)
        local glyph = widget:getChildById('glyph')
        glyph:setImageSource(icon.glyph)
        glyph:setImageColor(icon.glyphColor)
      end
      widget.glyphColor = icon.custom and '#ffffff' or icon.glyphColor
      widget.words = spell.words
      widget.tipName, widget.tipInfo = tooltipFor(spell, icon)

      local x, y
      if options.side == 'horizontal' then
        x = PAD + handleSize() + (shown - 1) * (SLOT + GAP)
        y = PAD + 1
      else
        x = PAD
        y = PAD + 1 + handleSize() + (shown - 1) * (SLOT + GAP)
      end
      widget:setMarginLeft(x)
      widget:setMarginTop(y)

      local keyLabel = widget:getChildById('keyLabel')
      keyLabel:setText(tostring(i))
      keyLabel:setVisible(options.numbers)

      local locked = level and spell.lvl and level < spell.lvl
      local lockLabel = widget:getChildById('lockLabel')
      if locked then
        lockLabel:setText('Nv ' .. spell.lvl)
        lockLabel:setVisible(true)
        widget:setEnabled(false)
      end

      local ring = widget:getChildById('hoverRing')
      -- connect (nao substitui) para nao quebrar outros modulos que usam o hover
      connect(widget, {onHoverChange = function(self, hovered)
        ring:setVisible(hovered and self:isEnabled())
        if hovered then showTip(self) else hideTip() end
      end})
      widget.onClick = function() useSpell(i) end
      slots[i] = widget

      -- recarga que ja estava correndo quando o Pokemon saiu
      local total = tonumber(spell.exhaustion) or 0
      local remaining = tonumber(spell.cooldownRemaining) or 0
      if remaining > 0 and total > 0 then
        startCooldown(i, total, math.min(total, remaining))
      end
    end
  end

  if shown == 0 then
    sbw:hide()
    return
  end
  local length = PAD * 2 + shown * SLOT + (shown - 1) * GAP
  local thick = PAD * 2 + SLOT + 1
  length = length + handleSize()
  if options.side == 'horizontal' then
    sbw:setSize({width = length, height = thick})
  else
    sbw:setSize({width = thick, height = length + 1})
  end
  layoutHandle(length)
  sbw:show()
  placeWindow()
end

-- ============================================================
-- opcode 52
-- ============================================================
function getOpCode(protocol, opcode, buffer)
  local moves, cooldowns, cooldownRemaining, levelNeed, unlockedList = {}, {}, {}, {}, {}
  spells = {}
  for match in string.gmatch(buffer or '', '([^,]+),%s*') do
    if tonumber(match) == nil then
      moves[#moves + 1] = match
    else
      local value = tonumber(match)
      if #cooldowns < #moves then
        cooldowns[#cooldowns + 1] = value
      elseif #cooldownRemaining < MAX_MOVES then -- o servidor manda sempre 12
        cooldownRemaining[#cooldownRemaining + 1] = value
      elseif #levelNeed < #moves then
        levelNeed[#levelNeed + 1] = value
      elseif #unlockedList < #moves then
        unlockedList[#unlockedList + 1] = value
      else
        level = value
      end
    end
  end
  for i = 1, #moves do
    spells[#spells + 1] = {
      id = i, words = moves[i], lvl = levelNeed[i] or 0, exhaustion = cooldowns[i] or 0,
      cooldownRemaining = cooldownRemaining[i] or 0, unlocked = unlockedList[i] or 1
    }
  end
  getSpells(spells)
end

-- ============================================================
-- uso
-- ============================================================
function useSpell(i)
  local widget = slots[i]
  if not widget or not g_game.isOnline() then return end
  if not widget:isEnabled() then
    return modules.game_textmessage.displayFailureMessage('Seu Pokemon ainda nao tem nivel para essa move.')
  end
  if widget.cdEnd then
    return modules.game_textmessage.displayFailureMessage('Essa move esta recarregando.')
  end
  g_game.talk('m' .. i)
end

local function msgcontains(message, keyword)
  message, keyword = message:lower(), keyword:lower()
  if message == keyword then return true end
  return message:find(keyword, 1, true) ~= nil
end

-- o servidor faz o jogador falar "<Pokemon>, use <move>!" quando a move sai
local function messageSentCallback(name, lvl, mode, text, channelId, pos)
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player or player:getName() ~= name then return end
  if mode ~= 34 then return end
  if msgcontains(text, 'use') then
    local parts = {}
    for part in (text .. ', '):gmatch('(.-),%s*') do parts[#parts + 1] = part end
    local used = parts[2] or ''
    used = used:gsub('^%s*use%s+', ''):gsub('!', ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
    for i, spell in ipairs(spells) do
      if spell.words:lower() == used then
        startCooldown(i, spell.exhaustion, spell.exhaustion)
        break
      end
    end
  elseif msgcontains(text, 'thanks') then
    if sbw then sbw:hide() end
  end
end

local function onLevelChange()
  if #spells > 0 and sbw and sbw:isVisible() then
    getSpells(spells)
  end
end

-- ============================================================
-- menu / arrastar
-- ============================================================
function createMenu()
  local menu = g_ui.createWidget('PopupMenu')
  if options.side == 'horizontal' then
    menu:addOption('Barra na vertical', function() options.side = 'vertical' saveOptions() getSpells(spells) end)
  else
    menu:addOption('Barra na horizontal', function() options.side = 'horizontal' saveOptions() getSpells(spells) end)
  end
  menu:addOption(options.numbers and 'Esconder numeros' or 'Mostrar numeros', function()
    options.numbers = not options.numbers
    saveOptions()
    getSpells(spells)
  end)
  menu:addOption(options.locked and 'Destravar posicao' or 'Travar posicao', function()
    options.locked = not options.locked
    saveOptions()
    getSpells(spells)
  end)
  menu:addOption('Voltar para o centro', function()
    options.pos = nil
    saveOptions()
    placeWindow()
  end)
  menu:display()
end

local function onGameEnd()
  if sbw then sbw:hide() end
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  clearSlots()
end

-- ============================================================
-- ciclo de vida
-- ============================================================
function init()
  loadOptions()
  sbw = g_ui.displayUI('pokemonmoves')
  mainPanel = sbw:getChildById('mainWindow')
  g_mouse.bindPress(sbw, function() createMenu() end, MouseRightButton)

  setupHandle()

  sbw:hide()
  connect(g_game, {onTalk = messageSentCallback, onGameEnd = onGameEnd})
  connect(LocalPlayer, {onLevelChange = onLevelChange})
  ProtocolGame.registerExtendedOpcode(OPCODE_SKILLBAR, getOpCode)
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE_SKILLBAR)
  disconnect(g_game, {onTalk = messageSentCallback, onGameEnd = onGameEnd})
  disconnect(LocalPlayer, {onLevelChange = onLevelChange})
  if tickEvent then
    removeEvent(tickEvent)
    tickEvent = nil
  end
  clearSlots()
  if tip then
    tip:destroy()
    tip = nil
  end
  if sbw then
    sbw:destroy()
    sbw = nil
  end
end
