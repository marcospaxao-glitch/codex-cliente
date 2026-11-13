-- ============================================================
-- VARAS - vara em uso + isca
-- Servidor: data/lib/core/fishinggear.lua (opcode 93)
--
-- Vara em uso : slot NECKLACE (2) de verdade, escondido no inventario.
--               Arraste uma vara da mochila para ca: a atual volta
--               para a mochila.
-- Isca        : arraste a isca da mochila; ela fica dentro da vara.
--               "Retirar iscas" devolve para a mochila.
-- Outras varas e iscas ficam livres na mochila (sem reserva).
-- ============================================================

-- texto direto (sem passar pelo sistema de traducao, evita spam no log)
local function T(text, ...)
  if select('#', ...) > 0 then
    return string.format(text, ...)
  end
  return text
end

local OPCODE = 93
local NECK_SLOT = 2

local window = nil
local rodSlot = nil
local baitSlot = nil
local mini = nil            -- janela compacta
local compact = false

local function active()
  return compact and mini or window
end
local gear = { requireBait = false, maxBait = 0, rodName = nil, bait = nil }

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, text)
  end
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    fields[#fields + 1] = field
  end
  return fields
end

local function splitLines(buffer)
  local lines = {}
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    if line ~= '' then
      lines[#lines + 1] = line
    end
  end
  return lines
end

-- posicao do item arrastado (so inventario/bags abertas)
local function getDraggedPosition(draggedWidget, errorText)
  if not draggedWidget or draggedWidget:getClassName() ~= 'UIItem' then
    return nil
  end
  local item = draggedWidget:getItem()
  if not item then
    return nil
  end
  local pos = item:getPosition()
  if not pos or pos.x ~= 65535 then
    modules.game_textmessage.displayFailureMessage(T(errorText))
    return nil
  end
  return pos
end

function refresh()
  if not window then return end

  local rodBox = window:getChildById('rodBox')
  local baitBox = window:getChildById('baitBox')
  rodBox:getChildById('boxTitle'):setText(T('Vara em uso'))
  baitBox:getChildById('boxTitle'):setText(T('Isca'))

  local player = g_game.getLocalPlayer()
  local rodItem = player and player:getInventoryItem(NECK_SLOT) or nil
  rodSlot:setItem(rodItem)
  rodBox:getChildById('boxInfo'):setText(gear.rodName or T('Sem vara'))

  local bonusLabel = window:getChildById('infoPanel'):getChildById('bonusLabel')
  local descLabel = window:getChildById('infoPanel'):getChildById('descLabel')

  if gear.bait then
    baitSlot:setItemId(gear.bait.clientId)
    baitSlot:setItemCount(gear.bait.count)
    baitBox:getChildById('boxInfo'):setText(gear.bait.name .. ' x' .. gear.bait.count)
    local bonus = {}
    if gear.bait.rarity > 0 then
      bonus[#bonus + 1] = T('Raridade +%d', gear.bait.rarity)
    end
    if gear.bait.tera > 0 then
      bonus[#bonus + 1] = T('Tera +%d', gear.bait.tera)
    end
    if gear.bait.shiny > 0 then
      bonus[#bonus + 1] = T('Shiny %d%%', math.floor(gear.bait.shiny / 10))
    end
    if gear.bait.mega > 0 then
      bonus[#bonus + 1] = T('Mega +%d%%', gear.bait.mega)
    end
    bonusLabel:setText(#bonus > 0 and table.concat(bonus, '   ') or T('Sem bonus'))
    descLabel:setText(gear.bait.desc ~= '' and gear.bait.desc or T('Cada pesca consome 1 isca.'))
  else
    baitSlot:setItem(nil)
    baitBox:getChildById('boxInfo'):setText(T('Sem isca'))
    bonusLabel:setText(T('Nenhuma isca equipada'))
    if not gear.rodName then
      descLabel:setText(T('Arraste uma vara da mochila para o slot da vara.'))
    elseif gear.requireBait then
      descLabel:setText(T('Voce precisa de isca para pescar. Arraste uma isca da mochila.'))
    else
      descLabel:setText(T('Arraste uma isca da mochila (maximo %d). Cada pesca consome 1.', gear.maxBait))
    end
  end

  window:getChildById('unbaitButton'):setEnabled(gear.bait ~= nil)
  window:getChildById('toReserveButton'):setEnabled(gear.rodName ~= nil)
  window:getChildById('mainCpButton'):setEnabled(gear.rodName ~= nil)

  -- janela compacta
  if mini then
    local mRod, mBait = mini:getChildById('miniRod'), mini:getChildById('miniBait')
    mRod:setItem(rodItem)
    mRod:setTooltip(gear.rodName or T('Sem vara. Arraste uma vara da mochila.'))
    if gear.bait then
      mBait:setItemId(gear.bait.clientId)
      mBait:setItemCount(gear.bait.count)
      mBait:setTooltip(gear.bait.name .. ' x' .. gear.bait.count .. (gear.bait.desc ~= '' and ('\n' .. gear.bait.desc) or ''))
      mini:getChildById('miniBonus'):setText(bonusLabel:getText())
      mini:getChildById('miniInfo'):setText(gear.bait.name)
    else
      mBait:setItem(nil)
      mBait:setTooltip(T('Sem isca. Arraste uma isca da mochila.'))
      mini:getChildById('miniBonus'):setText(gear.rodName or T('Sem vara'))
      mini:getChildById('miniInfo'):setText(T('Sem isca'))
    end
    mini:getChildById('unbaitButton'):setEnabled(gear.bait ~= nil)
    mini:getChildById('toReserveButton'):setEnabled(gear.rodName ~= nil)
    mini:getChildById('mainCpButton'):setEnabled(gear.rodName ~= nil)
  end
  window:getChildById('reserveHint'):setText(T('Para trocar, arraste outra vara ou isca da mochila. A vara que sai volta para a mochila com as iscas dela.'))
end

local function onBaitDrop(self, draggedWidget, mousePos)
  local pos = getDraggedPosition(draggedWidget, 'Arraste a isca da mochila ou de uma bag aberta.')
  if not pos then return false end
  send('SETBAIT|' .. pos.x .. '|' .. pos.y .. '|' .. pos.z)
  return true
end

local function onRodDrop(self, draggedWidget, mousePos)
  if draggedWidget == rodSlot then return false end
  local pos = getDraggedPosition(draggedWidget, 'Arraste a vara da mochila ou de uma bag aberta.')
  if not pos then return false end
  send('SETROD|' .. pos.x .. '|' .. pos.y .. '|' .. pos.z)
  return true
end

local function onGearOpcode(protocol, opcode, buffer)
  local lines = splitLines(buffer)
  if #lines == 0 then return end
  local header = splitFields(lines[1])
  if header[1] ~= 'GEAR' then return end

  gear.requireBait = header[2] == '1'
  gear.maxBait = tonumber(header[3]) or 0
  gear.rodName = nil
  gear.bait = nil

  for i = 2, #lines do
    local f = splitFields(lines[i])
    if f[1] == 'MAIN' then
      gear.rodName = f[2]
      if f[3] and f[3] ~= '' then
        gear.bait = {
          clientId = tonumber(f[3]) or 0,
          name = f[4] or '?',
          count = tonumber(f[5]) or 0,
          rarity = tonumber(f[6]) or 0,
          tera = tonumber(f[7]) or 0,
          desc = f[8] or '',
          shiny = tonumber(f[9]) or 0,
          mega = tonumber(f[10]) or 0
        }
      end
    end
  end
  refresh()
end

local function onInventoryChange(player, slot, item, oldItem)
  if slot == NECK_SLOT and window and window:isVisible() then
    rodSlot:setItem(item)
  end
  if slot == NECK_SLOT and mini and mini:isVisible() then
    mini:getChildById('miniRod'):setItem(item)
  end
end

function init()
  window = g_ui.displayUI('varas')
  window:hide()
  rodSlot = window:recursiveGetChildById('rodSlot')
  baitSlot = window:recursiveGetChildById('baitSlot')

  baitSlot.onDrop = onBaitDrop
  window:getChildById('baitBox').onDrop = onBaitDrop
  rodSlot.onDrop = onRodDrop
  window:getChildById('rodBox').onDrop = onRodDrop

  mini = g_ui.createWidget('VRMiniWindow', window:getParent())
  mini:hide()
  mini:getChildById('miniBait').onDrop = onBaitDrop
  mini:getChildById('miniRod').onDrop = function(self, w, p)
    if w == self then return false end
    return onRodDrop(self, w, p)
  end
  mini:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  mini:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  compact = g_settings.getBoolean('codexVarasCompact')

  ProtocolGame.registerExtendedOpcode(OPCODE, onGearOpcode)
  connect(LocalPlayer, { onInventoryChange = onInventoryChange })
  connect(g_game, { onGameEnd = hide })
  g_keyboard.bindKeyDown('Ctrl+Shift+F', toggle)
  refresh()
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(LocalPlayer, { onInventoryChange = onInventoryChange })
  disconnect(g_game, { onGameEnd = hide })
  g_keyboard.unbindKeyDown('Ctrl+Shift+F')
  if mini then
    mini:destroy()
    mini = nil
  end
  if window then
    window:destroy()
    window = nil
  end
end

function show()
  if not g_game.isOnline() or not window then return end
  local w = active()
  w:show()
  w:raise()
  w:focus()
  refresh()
  send('REQ')
end

function hide()
  if window then
    window:hide()
  end
  if mini then
    mini:hide()
  end
end

function toggleCompact()
  local wasOpen = (window and window:isVisible()) or (mini and mini:isVisible())
  hide()
  compact = not compact
  g_settings.set('codexVarasCompact', compact)
  if wasOpen then show() end
end

function toggle()
  local w = active()
  if w and w:isVisible() then
    hide()
  else
    show()
  end
end

function removeBait()
  send('UNBAIT')
end

-- botao "Para mochila" (o servidor aceita MAINTORES e MAINTOBAG)
function mainToReserve()
  send('MAINTOBAG')
end

function mainToCp()
  send('MAINTOCP')
end
