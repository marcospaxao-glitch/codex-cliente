-- ============================================================
-- BOLSA DE LOOT (Codex)
-- Botao no topo: abre/fecha a Bolsa de Loot (slot 7, escondido).
-- O autoloot do servidor coloca o loot nela. Venda no NPC.
-- ============================================================
local SLOT = 7          -- InventorySlotLegs (LootBag.SLOT no servidor)
local BAG_HINT = 'Bolsa de Loot (40 espacos, sem peso)'

local button = nil

local function getBag()
  local player = g_game.getLocalPlayer()
  return player and player:getInventoryItem(SLOT) or nil
end

local function openContainerOf(bag)
  for _, container in pairs(g_game.getContainers()) do
    local item = container:getContainerItem()
    if item and bag and item:getId() == bag:getId() then
      return container
    end
  end
  return nil
end

function toggle()
  if not g_game.isOnline() then return end
  local bag = getBag()
  if not bag then
    modules.game_textmessage.displayFailureMessage('Bolsa de Loot nao encontrada. Relogue o personagem.')
    return
  end
  local open = openContainerOf(bag)
  if open then
    g_game.close(open)
  else
    g_game.open(bag, nil)
  end
end

local function updateButton()
  if not button then return end
  local bag = getBag()
  button:setOn(bag ~= nil and openContainerOf(bag) ~= nil)
end

function init()
  local ok, b = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton('lootBagButton', BAG_HINT, '/images/topbuttons/codex/loot', toggle)
  end)
  if ok then button = b end
  connect(Container, {onOpen = updateButton, onClose = updateButton})
end

function terminate()
  disconnect(Container, {onOpen = updateButton, onClose = updateButton})
  if button then button:destroy() button = nil end
end
