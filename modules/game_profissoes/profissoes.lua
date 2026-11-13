Profissoes = {
  OPCODE = 90,
  window = nil,
  opcodeRegistered = false,
  retryEvent = nil,
  profession = 'none',
  level = 0,
  exp = 0,
  maxLevel = 250,
  categories = {},
  recipes = {},
  crafting = nil,
  queue = {},
  queueCount = 0,
  craftTimer = nil,
  craftWindow = nil,
  rewards = {},
  activeQueueCard = nil,
  selectedCategory = nil,
  categoryOrder = {},
  expNeeded = 1,
  professionName = '',
  -- Profissao secundaria (liberada pelo Cartao de Profissao)
  secondary = 'none',
  secLevel = 0,
  secExp = 0,
  secExpNeeded = 1,
  secUnlocked = false,
  changeCost = 500,
  pokecoins = 0,
  chooserSlot = nil,
  chooserSelected = nil
}

-- Ordem fixa quando existir; receitas novas (sem ordem definida) entram
-- ordenadas por nivel minimo e nome, entao nao precisa mexer aqui.
local RECIPE_ORDER_BY_CATEGORY = {
  pokebolas = {'base_ball', 'pokeball', 'greatball', 'ultraball'},
  varas = {'old_rod', 'great_rod', 'super_rod', 'ultra_rod'}
}

-- Identidade visual de cada profissao (cor, icone e descricao curta).
local PROFESSION_INFO = {
  engineer   = {name = 'ENGENHEIRO',  color = '#FFC83D', icon = 'device_icon.png',   desc = 'Tecnologia, maquinas e equipamentos',
                lines = 'Pokebolas: Base Ball ate Ultraball\nAparelhos: detectores, scanners e maquinas'},
  fisher     = {name = 'PESCADOR',    color = '#45A8FF', icon = 'fishing_icon.png',  desc = 'Pesca, recursos aquaticos e iscas',
                lines = 'Varas: Old Rod ate Ultra Rod\nIscas: simples, aquatica, rara e dourada'},
  adventurer = {name = 'AVENTUREIRO', color = '#72E6A0', icon = 'pokeball_icon.png', desc = 'Exploracao, descoberta e coleta',
                lines = 'Exploracao: kits, bussola e lanterna\nReliquias: fragmentos ate artefatos'},
  stylist    = {name = 'ESTILISTA',   color = '#C46BE0', icon = 'pokeball_icon.png', desc = 'Roupas, acessorios e personalizacao',
                lines = 'Roupas: camisas, capas e chapeus\nBolsas: backpacks tematicas por tipo'}
}
local PROFESSION_ORDER = {'engineer', 'fisher', 'adventurer', 'stylist'}
local QUEUE_MAX = 5

-- Cor de raridade por receita. Pinta a faixa superior do card e o titulo.
local RARITY = {
  base_ball = '#8FA3B8',
  pokeball  = '#E8484A',
  greatball = '#45A8FF',
  ultraball = '#FFC83D',
  masterball = '#C46BE0',
  old_rod   = '#8FA3B8',
  great_rod = '#45A8FF',
  super_rod = '#FFC83D',
  ultra_rod = '#C46BE0'
}

local CATEGORY_ICON = {
  pokebolas  = 'pokeball_icon.png',
  varas      = 'fishing_icon.png',
  iscas      = 'fishing_icon.png',
  aparelhos  = 'device_icon.png'
}

local COLOR_OK      = '#72E6A0'
local COLOR_FAIL    = '#FF9A7A'
local COLOR_NEUTRAL = '#7F94B1'

-- Corta textos longos para nao invadirem o widget vizinho.
local function ellipsis(text, maxChars)
  text = tostring(text or '')
  if #text <= maxChars then return text end
  return string.sub(text, 1, math.max(1, maxChars - 1)) .. '.'
end

local function safeDestroy(widget)
  if widget and not widget:isDestroyed() then widget:destroy() end
end

-- Separa por '|' PRESERVANDO campos vazios. O padrao antigo '[^|]+'
-- descartava campos vazios e deslocava tudo (ex: QUEUE_STATE||0|0| sem
-- craft ativo virava activeId='0').
local function parseParts(buffer)
  local parts = {}
  buffer = tostring(buffer or '')
  local start = 1
  while true do
    local pos = string.find(buffer, '|', start, true)
    if not pos then
      parts[#parts + 1] = string.sub(buffer, start)
      break
    end
    parts[#parts + 1] = string.sub(buffer, start, pos - 1)
    start = pos + 1
  end
  return parts
end

-- Largura real de um trilho de barra (com fallback antes do layout).
local function fillBar(fill, ratio, color, fallback)
  if not fill then return end
  local track = fill:getParent()
  local width = track and track:getWidth() or 0
  if not width or width <= 0 then width = fallback or 100 end
  ratio = math.max(0, math.min(1, tonumber(ratio) or 0))
  fill:setWidth(math.floor(width * ratio))
  if color then fill:setBackgroundColor(color) end
end

local function isProfessionKey(key)
  return key ~= nil and key ~= '' and key ~= 'none'
end

-- true se o jogador tem pelo menos uma profissao (principal ou secundaria).
local function hasProfession()
  return isProfessionKey(Profissoes.profession) or isProfessionKey(Profissoes.secondary)
end

-- Nivel do jogador na profissao dona da receita.
local function levelFor(professionKey)
  if isProfessionKey(professionKey) then
    if professionKey == Profissoes.secondary then return tonumber(Profissoes.secLevel) or 0 end
    if professionKey == Profissoes.profession then return tonumber(Profissoes.level) or 0 end
  end
  return tonumber(Profissoes.level) or 0
end

local function formatThousands(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  while true do
    local changed
    text, changed = text:gsub('^(-?%d+)(%d%d%d)', '%1.%2')
    if changed == 0 then break end
  end
  return text
end

local function formatTime(seconds)
  seconds = math.max(0, tonumber(seconds) or 0)
  return string.format('%02d:%02d', math.floor(seconds / 60), seconds % 60)
end

-- Mostra/esconde um label de estado vazio sobreposto a um painel.
local function setEmptyState(window, id, visible, text)
  if not window or window:isDestroyed() then return end
  local label = window:recursiveGetChildById(id)
  if not label then return end
  if text then label:setText(text) end
  label:setVisible(visible)
end

function Profissoes.tryRegisterOpcode()
  if Profissoes.opcodeRegistered or not g_game.isOnline() then return Profissoes.opcodeRegistered end
  local proto = g_game.getProtocolGame()
  if not proto then return false end
  local ok, err = pcall(function() ProtocolGame.registerExtendedOpcode(Profissoes.OPCODE, Profissoes.onExtendedOpcode) end)
  if ok then Profissoes.opcodeRegistered = true; g_logger.info('[Profissoes] Opcode 90 registrado.'); return true end
  g_logger.error('[Profissoes] Erro ao registrar Opcode 90: ' .. tostring(err))
  if not Profissoes.retryEvent then
    Profissoes.retryEvent = scheduleEvent(function() Profissoes.retryEvent = nil; Profissoes.tryRegisterOpcode() end, 1000)
  end
  return false
end

function Profissoes.onExtendedOpcode(protocol, opcode, buffer)
  if opcode ~= Profissoes.OPCODE then return end
  local parts = parseParts(buffer)
  local command = parts[1] or ''

  if command == 'STATE' then
    Profissoes.profession = (parts[2] ~= nil and parts[2] ~= '') and parts[2] or 'none'
    Profissoes.level = tonumber(parts[3]) or 0; Profissoes.exp = tonumber(parts[4]) or 0; Profissoes.maxLevel = tonumber(parts[5]) or 250
    -- Campos novos (servidor novo). Servidor antigo: exp necessaria = level + 1.
    Profissoes.expNeeded = tonumber(parts[6]) or (Profissoes.level + 1)
    Profissoes.professionName = parts[7] or ''
    -- Secundaria / troca (servidor novo).
    Profissoes.secondary = (parts[8] ~= nil and parts[8] ~= '') and parts[8] or 'none'
    Profissoes.secLevel = tonumber(parts[9]) or 0
    Profissoes.secExp = tonumber(parts[10]) or 0
    Profissoes.secExpNeeded = tonumber(parts[11]) or (Profissoes.secLevel + 1)
    Profissoes.secUnlocked = parts[13] == '1'
    Profissoes.changeCost = tonumber(parts[14]) or Profissoes.changeCost
    Profissoes.pokecoins = tonumber(parts[15]) or 0
    Profissoes.updateHeader(); Profissoes.refreshCategories(); Profissoes.refreshRecipes(); Profissoes.updateCraftWindow()
    -- Sem profissao principal: a tela de escolha e o unico conteudo util.
    if not isProfessionKey(Profissoes.profession) then
      Profissoes.openChooser('primary')
    elseif Profissoes.chooserSlot then
      Profissoes.refreshChooser()
    end
    return
  end
  if command == 'CHOSEN' then
    Profissoes.closeChooser(); return
  end
  if command == 'SECONDARY_UNLOCKED' then
    -- O aviso pode chegar antes do STATE: marca a vaga como liberada aqui.
    Profissoes.secUnlocked = true
    Profissoes.updateHeader()
    if Profissoes.window and not Profissoes.window:isDestroyed() and Profissoes.window:isVisible() then
      Profissoes.openChooser('secondary')
    end
    return
  end
  if command == 'CATALOG_RESET' then
    Profissoes.categories = {}; Profissoes.categoryOrder = {}; Profissoes.recipes = {}; Profissoes.categoryProfession = {}
    Profissoes.refreshCategories(); Profissoes.refreshRecipes(); return
  end
  if command == 'CATEGORY' then
    local id = parts[2] or ''
    if id ~= '' then
      if not Profissoes.categories[id] then table.insert(Profissoes.categoryOrder, id) end
      Profissoes.categories[id] = parts[3] or id
      Profissoes.categoryProfession = Profissoes.categoryProfession or {}
      Profissoes.categoryProfession[id] = parts[4] or ''
    end
    Profissoes.refreshCategories(); return
  end
  if command == 'RECIPE' then
    local id = parts[2] or ''
    Profissoes.recipes[id] = {id=id, category=parts[3] or '', name=parts[4] or '', outputId=tonumber(parts[5]) or 0, outputCount=tonumber(parts[6]) or 0, duration=tonumber(parts[7]) or 180, minLevel=tonumber(parts[8]) or 0, exp=tonumber(parts[10]) or 1, profession=(parts[11] ~= nil and parts[11] ~= '') and parts[11] or Profissoes.profession, materials={}}
    for material in string.gmatch(parts[9] or '', '[^;]+') do
      local mid, mcount, mname, mhave = material:match('([^:]+):([^:]+):([^:]+):?(.*)')
      if mid and mcount then table.insert(Profissoes.recipes[id].materials, {id=tonumber(mid), count=tonumber(mcount), have=tonumber(mhave) or 0, name=mname or mid}) end
    end
    Profissoes.refreshCategories()
    Profissoes.refreshRecipes()
    Profissoes.updateCraftWindow()
    if Profissoes.craftWindow and not Profissoes.craftWindow:isDestroyed() and Profissoes.craftWindow.recipeId == id then
      Profissoes.updateCraftMaterials(id)
    end
    return
  end
  if command == 'REWARD_STATE' then
    Profissoes.rewards = {}
    for entry in string.gmatch(parts[3] or '', '[^;]+') do
      local slot, rid, name, outputId, outputCount = entry:match('([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)')
      if slot and rid then
        Profissoes.rewards[#Profissoes.rewards + 1] = {slot=tonumber(slot), recipeId=rid, name=name, outputId=tonumber(outputId) or 0, outputCount=tonumber(outputCount) or 0}
      end
    end
    Profissoes.updateRewardWidget()
    return
  end
  if command == 'REWARD_COLLECTED' then
    Profissoes.updateRewardWidget()
    return
  end
  if command == 'QUEUE_STATE' then
    local activeId = parts[2] or ''
    local remaining = tonumber(parts[3]) or 0
    Profissoes.queue = {}; Profissoes.queueCount = tonumber(parts[4]) or 0

    for entry in string.gmatch(parts[5] or '', '[^;]+') do
      local rid, name = entry:match('([^:]+):(.+)')
      if rid then table.insert(Profissoes.queue, {id=rid, name=name}) end
    end

    if activeId ~= '' and remaining > 0 then
      local recipe = Profissoes.recipes[activeId]
      local duration = recipe and tonumber(recipe.duration) or remaining
      local name = recipe and recipe.name or activeId
      local outputCount = recipe and tonumber(recipe.outputCount) or 0
      Profissoes.crafting = {
        recipeId = activeId,
        finishAt = g_clock.seconds() + remaining,
        name = name,
        outputCount = outputCount,
        duration = math.max(duration, remaining)
      }
      Profissoes.startCraftTimer()
    elseif activeId == '' then
      Profissoes.crafting = nil
      Profissoes.stopCraftTimer()
    end

    Profissoes.updateQueueWidgets()
    Profissoes.updateCraftStatus()
    Profissoes.updateCraftWindow()
    return
  end
  if command == 'CRAFT_START' then
    Profissoes.onCraftStart(parts[2] or '', tonumber(parts[3]) or 0, parts[4] or '', tonumber(parts[5]) or 0); return
  end
  if command == 'CRAFT_RESUME' then
    Profissoes.onCraftStart(parts[2] or '', tonumber(parts[3]) or 0, parts[4] or '', tonumber(parts[5]) or 0); return
  end
  if command == 'CRAFT_COMPLETE' then
    Profissoes.crafting = nil; Profissoes.stopCraftTimer(); Profissoes.updateCraftStatus(); Profissoes.updateCraftWindow(); Profissoes.updateRewardWidget()
    local doneRecipe = Profissoes.recipes[parts[2] or '']
    modules.game_textmessage.displayStatusMessage('Craft concluido: ' .. tostring(doneRecipe and doneRecipe.name or parts[2] or '') .. '. Colete na janela de fabricacao.'); return
  end
  if command == 'QUEUE_ADDED' then
    modules.game_textmessage.displayStatusMessage((parts[3] or 'Receita') .. ' adicionada a fila.'); return
  end
  if command == 'MESSAGE' then
    modules.game_textmessage.displayStatusMessage(parts[2] or '')
  end
end

-- ------------------------------------------------------------------ header

-- Preenche uma das duas metades do cabecalho (principal / secundaria).
local function fillProfessionSlot(win, ids, key, level, exp, needed, locked)
  local info = PROFESSION_INFO[key]
  local active = isProfessionKey(key)
  local color = info and info.color or '#7F94B1'
  local maxLevel = math.max(1, tonumber(Profissoes.maxLevel) or 250)
  level = math.max(0, math.min(maxLevel, tonumber(level) or 0))
  exp = math.max(0, tonumber(exp) or 0)
  needed = math.max(1, tonumber(needed) or (level + 1))
  local isMax = level >= maxLevel
  local function get(id) return win:recursiveGetChildById(id) end

  local value = get(ids.value)
  if value then
    if active then
      value:setText(info and info.name or string.upper(key))
      value:setColor(color)
    else
      value:setText(locked and 'BLOQUEADA' or 'SEM PROFISSAO')
      value:setColor(locked and '#5F7596' or '#7F94B1')
    end
  end
  local accent = get(ids.accent)
  if accent then accent:setBackgroundColor(active and color or '#3A5170') end
  local box = get(ids.box)
  if box then box:setBorderColor(active and color or '#1C3350') end
  local icon = get(ids.icon)
  if icon then
    if info and info.icon then icon:setImageSource('/game_profissoes/images/' .. info.icon) end
    icon:setImageColor(active and '#ffffff' or '#ffffff44')
  end
  local levelLabel = get(ids.level)
  if levelLabel then
    levelLabel:setText(active and ('NIVEL ' .. tostring(level) .. ' / ' .. tostring(maxLevel)) or '')
  end
  local expLabel = get(ids.exp)
  if expLabel then
    if not active then expLabel:setText('')
    elseif isMax then expLabel:setText('NIVEL MAXIMO')
    else expLabel:setText(tostring(exp) .. ' / ' .. tostring(needed) .. ' EXP') end
  end
  -- Barra = progresso DENTRO do nivel atual.
  fillBar(get(ids.fill), active and (isMax and 1 or exp / needed) or 0, active and color or '#3A5170', 370)
  local desc = get(ids.desc)
  if desc then
    if active then
      desc:setText((info and info.desc or '') .. '  -  CARREIRA ' .. tostring(math.floor(level * 100 / maxLevel)) .. '%')
    elseif locked then
      desc:setText('Use um Cartao de Profissao para liberar esta vaga.')
    else
      desc:setText('Escolha uma profissao para acessar as receitas.')
    end
  end
end

function Profissoes.updateHeader()
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  local win = Profissoes.window

  fillProfessionSlot(win, {value = 'professionValue', accent = 'professionAccent', box = 'professionIconBox', icon = 'professionIcon',
    level = 'levelValue', exp = 'expValue', fill = 'expFill', desc = 'professionDesc'},
    Profissoes.profession, Profissoes.level, Profissoes.exp, Profissoes.expNeeded, false)
  fillProfessionSlot(win, {value = 'secValue', accent = 'secAccent', box = 'secIconBox', icon = 'secIcon',
    level = 'secLevelValue', exp = 'secExpValue', fill = 'secExpFill', desc = 'secDesc'},
    Profissoes.secondary, Profissoes.secLevel, Profissoes.secExp, Profissoes.secExpNeeded, not Profissoes.secUnlocked)

  local primaryButton = win:recursiveGetChildById('primaryChangeButton')
  if primaryButton then
    local has = isProfessionKey(Profissoes.profession)
    primaryButton:setText(has and 'TROCAR' or 'ESCOLHER')
    primaryButton:setEnabled(true)
    primaryButton.onClick = function() Profissoes.openChooser('primary') end
  end
  local secondaryButton = win:recursiveGetChildById('secondaryButton')
  if secondaryButton then
    if not Profissoes.secUnlocked then
      secondaryButton:setText('BLOQUEADA')
      secondaryButton:setEnabled(false)
    else
      secondaryButton:setText(isProfessionKey(Profissoes.secondary) and 'TROCAR' or 'ESCOLHER')
      secondaryButton:setEnabled(true)
    end
    secondaryButton.onClick = function() if Profissoes.secUnlocked then Profissoes.openChooser('secondary') end end
  end
end

-- --------------------------------------------------------- tela de escolha

function Profissoes.openChooser(slot)
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  slot = (slot == 'secondary') and 'secondary' or 'primary'
  if slot == 'secondary' and not Profissoes.secUnlocked then return end
  Profissoes.chooserSlot = slot
  Profissoes.chooserSelected = nil
  local panel = Profissoes.window:recursiveGetChildById('chooserPanel')
  if panel then panel:setVisible(true); panel:raise() end
  Profissoes.refreshChooser()
end

function Profissoes.closeChooser()
  Profissoes.chooserSlot = nil
  Profissoes.chooserSelected = nil
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  local panel = Profissoes.window:recursiveGetChildById('chooserPanel')
  if panel then panel:setVisible(false) end
end

function Profissoes.selectChoice(key)
  Profissoes.chooserSelected = key
  Profissoes.refreshChooser()
end

function Profissoes.confirmChoice()
  local slot, key = Profissoes.chooserSlot, Profissoes.chooserSelected
  if not slot or not key then return end
  local proto = g_game.getProtocolGame(); if not proto then return end
  proto:sendExtendedOpcode(Profissoes.OPCODE, 'CHOOSE|' .. slot .. '|' .. key)
end

function Profissoes.refreshChooser()
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  local win = Profissoes.window
  local slot = Profissoes.chooserSlot
  if not slot then return end
  local current = slot == 'secondary' and Profissoes.secondary or Profissoes.profession
  local other = slot == 'secondary' and Profissoes.profession or Profissoes.secondary
  local isChange = isProfessionKey(current)
  local cost = tonumber(Profissoes.changeCost) or 0
  local canPay = (tonumber(Profissoes.pokecoins) or 0) >= cost

  local title = win:recursiveGetChildById('chooserTitle')
  if title then
    if slot == 'secondary' then
      title:setText(isChange and 'TROCAR PROFISSAO SECUNDARIA' or 'ESCOLHA SUA PROFISSAO SECUNDARIA')
    else
      title:setText(isChange and 'TROCAR PROFISSAO PRINCIPAL' or 'ESCOLHA SUA PROFISSAO')
    end
  end
  local subtitle = win:recursiveGetChildById('chooserSubtitle')
  if subtitle then
    if isChange then
      subtitle:setText('A troca custa ' .. formatThousands(cost) .. ' Pokecoins e zera o nivel e a EXP desta vaga. Voce tem ' .. formatThousands(Profissoes.pokecoins) .. '.')
    elseif slot == 'secondary' then
      subtitle:setText('Sua vaga secundaria foi liberada. A primeira escolha e gratuita.')
    else
      subtitle:setText('Cada profissao tem receitas proprias. A primeira escolha e gratuita; trocar depois custa Pokecoins.')
    end
  end

  local cards = win:recursiveGetChildById('chooserCards')
  if cards then
    for _, child in ipairs(cards:getChildren()) do child:destroy() end
    for _, key in ipairs(PROFESSION_ORDER) do
      local info = PROFESSION_INFO[key]
      local card = g_ui.createWidget('ProfessionChoiceCard', cards)
      card:setId('choice_' .. key)
      local isCurrent = key == current
      local isOther = key == other
      local selected = key == Profissoes.chooserSelected
      local selectable = not isCurrent and not isOther

      local strip = card:getChildById('cardStrip')
      if strip then strip:setBackgroundColor(selectable and info.color or '#3A5170') end
      local box = card:getChildById('cardIconBox')
      if box then box:setBorderColor(selected and info.color or '#1C3350') end
      local icon = card:getChildById('cardIcon')
      if icon then
        icon:setImageSource('/game_profissoes/images/' .. info.icon)
        icon:setImageColor(selectable and '#ffffff' or '#ffffff55')
      end
      local name = card:getChildById('cardName')
      if name then name:setText(info.name); name:setColor(selectable and info.color or '#5F7596') end
      local desc = card:getChildById('cardDesc')
      if desc then desc:setText(info.desc) end
      local lines = card:getChildById('cardLines')
      if lines then lines:setText(info.lines or '') end
      local tag = card:getChildById('cardTag')
      if tag then
        if isCurrent then
          tag:setText(slot == 'secondary' and 'SUA SECUNDARIA ATUAL' or 'SUA PROFISSAO ATUAL'); tag:setColor('#FFD24A')
        elseif isOther then
          tag:setText(slot == 'secondary' and 'JA E SUA PRINCIPAL' or 'JA E SUA SECUNDARIA'); tag:setColor('#7F94B1')
        elseif selected then
          tag:setText('SELECIONADA'); tag:setColor('#72E6A0')
        else
          tag:setText('CLIQUE PARA SELECIONAR'); tag:setColor('#5F7596')
        end
      end
      card:setBorderColor(selected and info.color or '#1C3350')
      card:setEnabled(selectable)
      card.onClick = function() if selectable then Profissoes.selectChoice(key) end end
    end
  end

  local selectedInfo = PROFESSION_INFO[Profissoes.chooserSelected or '']
  local selection = win:recursiveGetChildById('chooserSelection')
  if selection then
    if selectedInfo then
      selection:setText((isChange and 'TROCAR PARA ' or 'ESCOLHER ') .. selectedInfo.name)
      selection:setColor(selectedInfo.color)
    else
      selection:setText('SELECIONE UMA PROFISSAO')
      selection:setColor('#7F94B1')
    end
  end
  local costLabel = win:recursiveGetChildById('chooserCost')
  if costLabel then
    if isChange then
      costLabel:setText('CUSTO: ' .. formatThousands(cost) .. ' POKECOINS  -  SALDO: ' .. formatThousands(Profissoes.pokecoins))
      costLabel:setColor(canPay and '#FFD24A' or '#FF9A7A')
    else
      costLabel:setText('GRATUITO')
      costLabel:setColor('#72E6A0')
    end
  end
  local footerAccent = win:recursiveGetChildById('chooserFooterAccent')
  if footerAccent then footerAccent:setBackgroundColor(selectedInfo and selectedInfo.color or '#3A5170') end

  local confirm = win:recursiveGetChildById('chooserConfirm')
  if confirm then
    confirm:setEnabled(selectedInfo ~= nil and (not isChange or canPay))
    confirm:setText(isChange and ('TROCAR (' .. formatThousands(cost) .. ')') or 'CONFIRMAR')
    confirm.onClick = function() Profissoes.confirmChoice() end
  end
  local cancel = win:recursiveGetChildById('chooserCancel')
  if cancel then
    -- Sem profissao principal nao ha para onde voltar.
    cancel:setVisible(isProfessionKey(Profissoes.profession))
    cancel.onClick = function() Profissoes.closeChooser() end
  end
end

-- -------------------------------------------------------------- categorias

local function countRecipes(category)
  local total = 0
  for _, recipe in pairs(Profissoes.recipes) do
    if recipe.category == category then total = total + 1 end
  end
  return total
end

function Profissoes.refreshCategories()
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  local list = Profissoes.window:recursiveGetChildById('categoryList'); if not list then return end
  for _, child in ipairs(list:getChildren()) do child:destroy() end

  -- Garante uma categoria selecionada valida para a profissao atual.
  local order = Profissoes.categoryOrder or {}
  local selectedValid = false
  for _, id in ipairs(order) do if id == Profissoes.selectedCategory then selectedValid = true end end
  if not selectedValid then Profissoes.selectedCategory = order[1] end

  for _, id in ipairs(order) do
    local button = g_ui.createWidget('ProfessionCategoryButton', list)
    button:setId(id)
    local count = countRecipes(id)
    local name = string.upper(tostring(Profissoes.categories[id] or id))
    button:setText(count > 0 and (name .. ' (' .. tostring(count) .. ')') or (name .. ' - EM BREVE'))
    button:setChecked(id == Profissoes.selectedCategory)
    local owner = Profissoes.categoryProfession and Profissoes.categoryProfession[id]
    local ownerInfo = owner and PROFESSION_INFO[owner]
    if ownerInfo and id ~= Profissoes.selectedCategory then
      pcall(function() button:setBorderColorLeft(ownerInfo.color) end)
    end
    local iconFile = CATEGORY_ICON[id]
    if iconFile then button:setIcon('/game_profissoes/images/' .. iconFile) end
    button.onClick = function() Profissoes.selectCategory(id) end
  end

  local title = Profissoes.window:recursiveGetChildById('products')
  if title and Profissoes.selectedCategory then
    title:setText('RECEITAS - ' .. string.upper(tostring(Profissoes.categories[Profissoes.selectedCategory] or Profissoes.selectedCategory)))
    title.categoryId = Profissoes.selectedCategory
  elseif title then
    title:setText('RECEITAS')
    title.categoryId = nil
  end
end

function Profissoes.selectCategory(category)
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  Profissoes.selectedCategory = category
  local categoryList = Profissoes.window:recursiveGetChildById('categoryList')
  if categoryList then
    for _, child in ipairs(categoryList:getChildren()) do
      if child.setChecked then child:setChecked(child:getId() == category) end
    end
  end
  local title = Profissoes.window:recursiveGetChildById('products')
  if title then
    title:setText('RECEITAS - ' .. string.upper(tostring(Profissoes.categories[category] or category)))
    title.categoryId = category
  end
  Profissoes.refreshRecipes(category)
end

-- ----------------------------------------------------------------- imagens

function Profissoes.materialImage(id)
  local map = {
    [39358] = 'barra_ferro.png',
    [39356] = 'bolas_carvao.png',
    [1294]  = 'small_stone.png',
    [39346] = 'base_ball.png',
    [39342] = 'fruta_vermelha.png',
    [39339] = 'fruta_azul.png',
    [39341] = 'fruta_amarela.png',
    [39344] = 'fruta_preta.png',

    -- Materiais do Pescador
    [2120]  = 'rope.png',
    [5901]  = 'wood.png',
    [27668] = 'water-gem.png',
    [27678] = 'water-pendant.png',
    [27721] = 'water-orb.png',
    [26662] = 'pokeball.png',
    [26660] = 'greatball.png',
    [26688] = 'utraball.png'
  }
  return map[id]
end

function Profissoes.outputImage(id)
  local map = {
    [39346] = 'base_ball.png',
    [26662] = 'pokeball.png',
    [26660] = 'greatball.png',
    [26688] = 'utraball.png',

    -- Varas do Pescador
    [26820] = 'old-rod.png',
    [38897] = 'great-rod.png',
    [38898] = 'super-rod.png',
    [38899] = 'ultra-rod.png'
  }
  return map[id]
end

local function createMaterialLine(parent, material, index)
  local line = g_ui.createWidget('ProfessionMaterialLine', parent); line:setId('material' .. index)
  local icon=line:getChildById('materialIcon'); local itemIcon=line:getChildById('materialItem'); local name=line:getChildById('materialName'); local count=line:getChildById('materialCount')
  if icon and material.image then
    icon:setImageSource('/game_profissoes/images/' .. material.image)
    icon:setImageColor('#ffffff')
    icon:setVisible(true)
  elseif icon then
    icon:setVisible(false)
  end
  if itemIcon and material.id then
    itemIcon:setItemId(tonumber(material.id) or 0)
    itemIcon:setVisible(not material.image and true or false)
  end
  if name then name:setText(material.name) end
  local have=tonumber(material.have) or 0
  local enough = have >= material.count
  if count then
    count:setText(tostring(have)..' / '..tostring(material.count))
    count:setColor(enough and COLOR_OK or COLOR_FAIL)
  end
  line:setBorderColor(enough and '#2C5A4A' or '#5A2C2C')
  local accent = line:getChildById('materialAccent')
  if accent then accent:setBackgroundColor(enough and COLOR_OK or COLOR_FAIL) end
  return line
end

-- ----------------------------------------------------------------- receitas

-- Verifica se o jogador possui todos os materiais de uma receita.
local function hasAllMaterials(recipe)
  for _, mat in ipairs(recipe.materials or {}) do
    if (tonumber(mat.have) or 0) < mat.count then return false end
  end
  return true
end

-- Monta o tooltip do card com a lista de materiais.
local function buildRecipeTooltip(recipe)
  local lines = {recipe.name}
  lines[#lines + 1] = 'Produz: x' .. tostring(recipe.outputCount)
  lines[#lines + 1] = 'Tempo: ' .. formatTime(recipe.duration)
  lines[#lines + 1] = 'Experiencia: +' .. tostring(recipe.exp or 1)
  if #(recipe.materials or {}) > 0 then
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'Materiais:'
    for _, mat in ipairs(recipe.materials) do
      lines[#lines + 1] = '  ' .. tostring(mat.name) .. '  ' .. tostring(tonumber(mat.have) or 0) .. '/' .. tostring(mat.count)
    end
  end
  return table.concat(lines, '\n')
end

local function orderedRecipes(category)
  local list, seen = {}, {}
  for _, recipeId in ipairs(RECIPE_ORDER_BY_CATEGORY[category] or {}) do
    local recipe = Profissoes.recipes[recipeId]
    if recipe and recipe.category == category then list[#list + 1] = recipe; seen[recipeId] = true end
  end
  local extra = {}
  for recipeId, recipe in pairs(Profissoes.recipes) do
    if recipe.category == category and not seen[recipeId] then extra[#extra + 1] = recipe end
  end
  table.sort(extra, function(a, b)
    if (a.minLevel or 0) ~= (b.minLevel or 0) then return (a.minLevel or 0) < (b.minLevel or 0) end
    return tostring(a.name) < tostring(b.name)
  end)
  for _, recipe in ipairs(extra) do list[#list + 1] = recipe end
  return list
end

function Profissoes.refreshRecipes(category)
  if not Profissoes.window or Profissoes.window:isDestroyed() then return end
  local win = Profissoes.window
  local list = win:recursiveGetChildById('recipeList'); if not list then return end
  local counter = win:recursiveGetChildById('recipeCount')

  for _, child in ipairs(list:getChildren()) do child:destroy() end

  if not hasProfession() then
    setEmptyState(win, 'recipeEmpty', true, 'Voce ainda nao possui uma profissao. Clique em ESCOLHER no topo para comecar.')
    if counter then counter:setText('') end
    return
  end

  local currentCategory = category
  if not currentCategory then
    local title = win:recursiveGetChildById('products')
    currentCategory = title and title.categoryId or Profissoes.selectedCategory
  end
  if not currentCategory then
    setEmptyState(win, 'recipeEmpty', true, 'Carregando receitas...')
    if counter then counter:setText('') end
    return
  end

  local total, readyCount = 0, 0
  for _, recipe in ipairs(orderedRecipes(currentCategory)) do
    total = total + 1
    local card = g_ui.createWidget('ProfessionProductCard', list); card:setId(recipe.id)

    local image  = card:getChildById('productImage')
    local itemImage = card:getChildById('productItem')
    local title  = card:getChildById('productTitle')
    local amount = card:getChildById('productAmount')
    local level  = card:getChildById('productLevel')
    local expLabel = card:getChildById('productExp')
    local lock   = card:getChildById('productLock')
    local strip  = card:getChildById('rarityStrip')
    local status = card:getChildById('statusBar')
    local slot   = card:getChildById('productSlot')

    local rarity = RARITY[recipe.id] or '#8FA3B8'
    if strip then strip:setBackgroundColor(rarity) end
    if title then title:setText(ellipsis(string.upper(recipe.name), 16)); title:setColor(rarity) end

    local outputImage = Profissoes.outputImage(recipe.outputId)
    if image then
      image:setVisible(outputImage ~= nil)
      if outputImage then image:setImageSource('/game_profissoes/images/' .. outputImage) end
    end
    if itemImage then
      itemImage:setItemId(tonumber(recipe.outputId) or 0)
      itemImage:setVisible(outputImage == nil)
    end

    local unlocked = levelFor(recipe.profession) >= (recipe.minLevel or 0)
    local ready = unlocked and hasAllMaterials(recipe)
    if ready then readyCount = readyCount + 1 end

    if amount then amount:setText('x' .. recipe.outputCount .. '  -  ' .. formatTime(recipe.duration)) end
    if level then
      level:setText(recipe.minLevel > 0 and ('NIVEL ' .. recipe.minLevel) or 'LIVRE')
      level:setColor(unlocked and '#FFD24A' or '#FF9A7A')
    end
    if expLabel then expLabel:setText('+' .. tostring(recipe.exp or 1) .. ' EXP') end

    if lock then
      lock:setVisible(not unlocked)
      lock:setText('NIVEL ' .. tostring(recipe.minLevel or 0))
    end
    if slot then slot:setBorderColor(ready and '#2C5A4A' or (unlocked and '#294765' or '#1C3350')) end
    if status then
      if not unlocked then status:setBackgroundColor('#3A2430')
      elseif ready then status:setBackgroundColor('#72E6A0')
      else status:setBackgroundColor('#FF9A7A') end
    end

    card:setEnabled(unlocked)
    card:setTooltip(buildRecipeTooltip(recipe))
    card.onClick = function() if unlocked then Profissoes.openCraftWindow(recipe.id) end end
  end

  setEmptyState(win, 'recipeEmpty', total == 0, 'Receitas desta categoria em breve.')
  if counter then
    if total == 0 then
      counter:setText('')
    else
      counter:setText(tostring(total) .. (total == 1 and ' RECEITA' or ' RECEITAS') .. '  -  ' .. tostring(readyCount) .. ' PRONTA(S)')
    end
  end
end

-- ------------------------------------------------------------ janela craft

function Profissoes.updateCraftMaterials(recipeId)
  local win = Profissoes.craftWindow
  if not win or win:isDestroyed() or not recipeId then return end

  local recipe = Profissoes.recipes[recipeId]
  if not recipe then return end

  local materials = win:recursiveGetChildById('materialList')
  if not materials then return end

  for _, child in ipairs(materials:getChildren()) do
    child:destroy()
  end

  for i, mat in ipairs(recipe.materials or {}) do
    mat.image = Profissoes.materialImage(mat.id)
    createMaterialLine(materials, mat, i)
  end

  local recipeLevel = levelFor(recipe.profession)
  local canCraft = recipeLevel >= (recipe.minLevel or 0) and hasAllMaterials(recipe)

  local totalJobs = Profissoes.queueCount + (Profissoes.crafting and 1 or 0)
  if totalJobs >= QUEUE_MAX then
    canCraft = false
  end

  local status = win:recursiveGetChildById('materialStatus')
  if status then
    if recipeLevel < (recipe.minLevel or 0) then
      status:setText('Requer nivel ' .. tostring(recipe.minLevel or 0) .. '.')
      status:setColor(COLOR_FAIL)
    elseif totalJobs >= QUEUE_MAX then
      status:setText('Fila cheia (' .. totalJobs .. '/' .. QUEUE_MAX .. ').')
      status:setColor(COLOR_FAIL)
    elseif canCraft then
      status:setText(Profissoes.crafting and 'Pronto para entrar na fila de fabricacao.' or 'Materiais suficientes. Pronto para fabricar.')
      status:setColor(COLOR_OK)
    else
      status:setText('Materiais insuficientes.')
      status:setColor(COLOR_FAIL)
    end
  end

  local craftButton = win:recursiveGetChildById('craftButton')
  if craftButton then
    craftButton:setEnabled(canCraft)
    craftButton:setText(Profissoes.crafting and 'ADICIONAR A FILA' or 'FABRICAR')
  end
end

function Profissoes.openCraftWindow(recipeId)
  local recipe = Profissoes.recipes[recipeId]; if not recipe then return end
  Profissoes.closeCraftWindow()
  Profissoes.craftWindow = g_ui.createWidget('ProfessionCraftWindow', rootWidget)

  local win = Profissoes.craftWindow
  win:show(); win:raise(); win:focus()
  local craftTitle = win:recursiveGetChildById('craftTitle')
  if craftTitle then craftTitle:setText('FABRICAR - ' .. string.upper(recipe.name)) end
  win.recipeId = recipeId

  local outputImageWidget = win:recursiveGetChildById('outputImage')
  local outputItemWidget  = win:recursiveGetChildById('outputItem')
  local outputName        = win:recursiveGetChildById('outputName')
  local outputAmount      = win:recursiveGetChildById('outputAmount')
  local requiredLevel     = win:recursiveGetChildById('requiredLevel')
  local craftTime         = win:recursiveGetChildById('craftTime')
  local outputBox         = win:recursiveGetChildById('outputBox')

  local outputImage = Profissoes.outputImage(recipe.outputId)
  if outputImageWidget then
    outputImageWidget:setVisible(outputImage ~= nil)
    if outputImage then
      outputImageWidget:setImageSource('/game_profissoes/images/' .. outputImage)
      outputImageWidget:setImageColor('#ffffff')
    end
  end
  local outputAccent = win:recursiveGetChildById('outputAccent')
  if outputItemWidget then
    outputItemWidget:setItemId(tonumber(recipe.outputId) or 0)
    outputItemWidget:setVisible(outputImage == nil)
  end

  local rarity = RARITY[recipe.id] or '#8FA3B8'
  if outputBox then outputBox:setBorderColor(rarity) end
  if outputAccent then outputAccent:setBackgroundColor(rarity) end
  if outputName then outputName:setText(string.upper(recipe.name)); outputName:setColor(rarity) end
  if outputAmount then outputAmount:setText('PRODUCAO: x' .. recipe.outputCount .. '   -   +' .. tostring(recipe.exp or 1) .. ' EXP') end
  if requiredLevel then requiredLevel:setText('NIVEL NECESSARIO: ' .. recipe.minLevel) end
  if craftTime then craftTime:setText('TEMPO DE FABRICACAO: ' .. formatTime(recipe.duration)) end

  win:recursiveGetChildById('craftButton').onClick = function() Profissoes.requestCraft(recipe.id) end
  win:recursiveGetChildById('cancelButton').onClick = function() Profissoes.closeCraftWindow() end

  Profissoes.updateCraftMaterials(recipeId)
  Profissoes.updateCraftWindow()
  Profissoes.updateRewardWidget()

  if Profissoes.crafting then
    Profissoes.startCraftTimer()
  end
end

function Profissoes.closeCraftWindow()
  safeDestroy(Profissoes.craftWindow); Profissoes.craftWindow = nil
end

function Profissoes.requestCraft(recipeId)
  if not hasProfession() then modules.game_textmessage.displayFailureMessage('Voce ainda nao possui uma profissao.'); return end
  local proto = g_game.getProtocolGame(); if not proto then return end
  proto:sendExtendedOpcode(Profissoes.OPCODE, 'CRAFT|' .. tostring(recipeId))
end

function Profissoes.sendCollect(slot)
  local proto = g_game.getProtocolGame()
  if not proto then return end
  proto:sendExtendedOpcode(Profissoes.OPCODE, 'COLLECT|' .. tostring(slot))
end

-- --------------------------------------------------------------- premios

function Profissoes.updateRewardWidget()
  local win = Profissoes.craftWindow
  if not win or win:isDestroyed() then return end
  local box = win:recursiveGetChildById('readyBox')
  if not box then return end

  for _, child in ipairs(box:getChildren()) do child:destroy() end

  if #Profissoes.rewards == 0 then
    setEmptyState(win, 'readyEmpty', true)
    return
  end
  setEmptyState(win, 'readyEmpty', false)

  for i, reward in ipairs(Profissoes.rewards) do
    local card = g_ui.createWidget('ProfessionRewardCard', box)
    local pos    = card:recursiveGetChildById('rewardPosition')
    local icon   = card:recursiveGetChildById('rewardIcon')
    local itemIcon = card:recursiveGetChildById('rewardItem')
    local name   = card:recursiveGetChildById('rewardName')
    local amount = card:recursiveGetChildById('rewardAmount')
    local button = card:recursiveGetChildById('rewardCollect')
    local image  = Profissoes.outputImage(reward.outputId)

    if pos then pos:setText('PRONTO') end
    if icon then
      icon:setVisible(image ~= nil)
      if image then
        icon:setImageSource('/game_profissoes/images/' .. image)
        icon:setImageColor('#ffffff')
      end
    end
    if itemIcon then
      itemIcon:setItemId(tonumber(reward.outputId) or 0)
      itemIcon:setVisible(image == nil)
    end
    if name then name:setText(ellipsis(reward.name, 12)) end
    if amount then amount:setText('x' .. tostring(reward.outputCount or 0)) end
    if button then
      button:setEnabled(true)
      button.onClick = function() Profissoes.sendCollect(reward.slot) end
    end
  end
end

-- ------------------------------------------------------------------- fila

function Profissoes.updateQueueWidgets()
  local win = Profissoes.craftWindow; if not win or win:isDestroyed() then return end
  local list = win:recursiveGetChildById('queueList'); if not list then return end
  for _, child in ipairs(list:getChildren()) do child:destroy() end

  Profissoes.activeQueueCard = nil

  local function createCard(position, recipeId, recipeName, stateText, active)
    local card = g_ui.createWidget('ProfessionQueueCard', list)
    local icon = card:getChildById('queueIcon')
    local itemIcon = card:getChildById('queueItem')
    local positionLabel = card:getChildById('queuePosition')
    local name = card:getChildById('queueName')
    local state = card:getChildById('queueState')
    local recipe = Profissoes.recipes[recipeId]
    local image = recipe and Profissoes.outputImage(recipe.outputId)

    if positionLabel then
      positionLabel:setText(position)
      positionLabel:setColor(active and '#72E6A0' or '#FFD24A')
    end
    if name then name:setText(ellipsis(recipeName or (recipe and recipe.name) or '', 9)) end
    if state then state:setText(stateText or 'Fila') end
    if active then card:setBorderColor('#2C5A4A'); Profissoes.activeQueueCard = card end
    if icon then
      icon:setVisible(image ~= nil)
      if image then
        icon:setImageSource('/game_profissoes/images/' .. image)
        icon:setImageColor('#ffffff')
      end
    end
    if itemIcon then
      itemIcon:setItemId(recipe and tonumber(recipe.outputId) or 0)
      itemIcon:setVisible(image == nil and recipe ~= nil)
    end
  end

  if Profissoes.crafting then
    local left = math.max(0, Profissoes.crafting.finishAt - g_clock.seconds())
    createCard('ATUAL', Profissoes.crafting.recipeId, Profissoes.crafting.name, formatTime(left), true)
  end

  for i, entry in ipairs(Profissoes.queue) do
    createCard(tostring((Profissoes.crafting and 1 or 0) + i), entry.id or entry.recipeId, entry.name, 'Aguardando', false)
  end

  local isEmpty = (not Profissoes.crafting) and #Profissoes.queue == 0
  setEmptyState(win, 'queueEmpty', isEmpty)

  local queueCount = win:recursiveGetChildById('queueCount')
  if queueCount then
    local used = (Profissoes.crafting and 1 or 0) + Profissoes.queueCount
    queueCount:setText(used .. ' / ' .. QUEUE_MAX)
    queueCount:setColor(used >= QUEUE_MAX and COLOR_FAIL or '#8FD3FF')
  end
end

-- --------------------------------------------------------------- progresso

function Profissoes.updateCraftProgress()
  local win = Profissoes.craftWindow
  if not win or win:isDestroyed() then return end

  local currentName    = win:recursiveGetChildById('currentCraftName')
  local currentTime    = win:recursiveGetChildById('currentCraftTime')
  local currentPercent = win:recursiveGetChildById('currentCraftPercent')
  local currentFill    = win:recursiveGetChildById('currentCraftFill')
  local currentAccent  = win:recursiveGetChildById('currentCraftAccent')

  if not Profissoes.crafting then
    if currentName then currentName:setText('NENHUMA FABRICACAO EM ANDAMENTO'); currentName:setColor(COLOR_NEUTRAL) end
    if currentTime then currentTime:setText('--:--') end
    if currentPercent then currentPercent:setText('') end
    fillBar(currentFill, 0, '#5AA9E6', 380)
    if currentAccent then currentAccent:setBackgroundColor('#3A5170') end
    return
  end

  local left = math.max(0, Profissoes.crafting.finishAt - g_clock.seconds())
  local total = math.max(1, tonumber(Profissoes.crafting.duration) or 1)
  local percent = math.floor(((total - left) / total) * 100)
  percent = math.max(0, math.min(100, percent))

  if currentName then
    currentName:setText(string.upper(tostring(Profissoes.crafting.name or '')))
    currentName:setColor('#FFFFFF')
  end
  if currentTime then currentTime:setText('RESTANTE: ' .. formatTime(left)) end
  if currentAccent then currentAccent:setBackgroundColor(left > 0 and '#5AA9E6' or '#72E6A0') end

  -- Atualiza o contador do primeiro card da fila sem recriar os widgets.
  local activeCard = Profissoes.activeQueueCard
  if activeCard and not activeCard:isDestroyed() then
    local state = activeCard:getChildById('queueState')
    if state then state:setText(formatTime(left)) end
  end
  if currentPercent then currentPercent:setText(tostring(percent) .. '%') end
  fillBar(currentFill, percent / 100, percent >= 100 and '#72E6A0' or '#5AA9E6', 380)
end

function Profissoes.updateCraftWindow()
  local win = Profissoes.craftWindow
  if not win or win:isDestroyed() then return end

  local currentIcon = win:recursiveGetChildById('currentCraftImage')
  local currentItem = win:recursiveGetChildById('currentCraftItem')
  if Profissoes.crafting then
    local recipe = Profissoes.recipes[Profissoes.crafting.recipeId]
    local img = recipe and Profissoes.outputImage(recipe.outputId)
    if currentIcon then
      currentIcon:setVisible(img ~= nil)
      if img then
        currentIcon:setImageSource('/game_profissoes/images/' .. img)
        currentIcon:setImageColor('#ffffff')
      end
    end
    if currentItem then
      currentItem:setItemId(recipe and tonumber(recipe.outputId) or 0)
      currentItem:setVisible(img == nil and recipe ~= nil)
    end
  else
    if currentIcon then currentIcon:setVisible(false) end
    if currentItem then currentItem:setVisible(false) end
  end

  Profissoes.updateCraftProgress()
  Profissoes.updateQueueWidgets()

  if win.recipeId then Profissoes.updateCraftMaterials(win.recipeId) end
end

function Profissoes.updateCraftStatus()
  Profissoes.updateCraftProgress()
end

function Profissoes.onCraftStart(recipeId, duration, name, outputCount)
  duration = tonumber(duration or 0) or 0

  Profissoes.crafting = {
    recipeId = recipeId,
    finishAt = g_clock.seconds() + duration,
    name = name,
    outputCount = tonumber(outputCount or 0),
    duration = duration
  }

  Profissoes.startCraftTimer()
  Profissoes.updateCraftWindow()
end

function Profissoes.startCraftTimer()
  if not Profissoes.crafting then return end

  Profissoes.stopCraftTimer()

  Profissoes.craftTimer = cycleEvent(function()
    if not Profissoes.crafting then
      Profissoes.stopCraftTimer()
      return
    end
    Profissoes.updateCraftStatus()
  end, 250)

  Profissoes.updateCraftStatus()
end

function Profissoes.stopCraftTimer()
  if Profissoes.craftTimer then
    if Profissoes.craftTimer.cancel then
      Profissoes.craftTimer:cancel()
    else
      removeEvent(Profissoes.craftTimer)
    end
    Profissoes.craftTimer = nil
  end
end

-- ------------------------------------------------------------------ ciclo

function Profissoes.request()
  if not g_game.isOnline() then return end
  if not Profissoes.opcodeRegistered and not Profissoes.tryRegisterOpcode() then return end
  local proto = g_game.getProtocolGame(); if not proto then return end
  Profissoes.categories = {}; Profissoes.categoryOrder = {}; Profissoes.recipes = {}
  proto:sendExtendedOpcode(Profissoes.OPCODE, 'REQUEST')
end

function Profissoes.show()
  if not Profissoes.window or Profissoes.window:isDestroyed() then Profissoes.window = g_ui.displayUI('profissoes') end
  Profissoes.window:show(); Profissoes.window:raise(); Profissoes.window:focus()
  Profissoes.updateHeader(); Profissoes.refreshCategories(); Profissoes.refreshRecipes(); Profissoes.request()
end

function Profissoes.hide()
  if Profissoes.window and not Profissoes.window:isDestroyed() then Profissoes.window:hide() end
  Profissoes.closeCraftWindow()
end

function Profissoes.toggle()
  if Profissoes.window and not Profissoes.window:isDestroyed() and Profissoes.window:isVisible() then Profissoes.hide() else Profissoes.show() end
end

function Profissoes.onGameStart()
  Profissoes.opcodeRegistered=false; Profissoes.profession='none'; Profissoes.selectedCategory=nil; Profissoes.categoryOrder={}; Profissoes.categories={}; Profissoes.recipes={}; Profissoes.expNeeded=1; Profissoes.secondary='none'; Profissoes.secLevel=0; Profissoes.secExp=0; Profissoes.secUnlocked=false; Profissoes.chooserSlot=nil; Profissoes.chooserSelected=nil; Profissoes.level=0; Profissoes.exp=0; Profissoes.crafting=nil; Profissoes.queue={}; Profissoes.queueCount=0; Profissoes.rewards={}; Profissoes.stopCraftTimer(); Profissoes.tryRegisterOpcode()
end

function Profissoes.onGameEnd()
  if Profissoes.retryEvent then removeEvent(Profissoes.retryEvent); Profissoes.retryEvent=nil end
  Profissoes.stopCraftTimer(); Profissoes.closeCraftWindow(); Profissoes.crafting=nil; Profissoes.queue={}; Profissoes.queueCount=0; Profissoes.rewards={}
  if Profissoes.opcodeRegistered then pcall(function() ProtocolGame.unregisterExtendedOpcode(Profissoes.OPCODE) end) end
  Profissoes.opcodeRegistered=false; Profissoes.hide()
end

function init()
  if Profissoes.window and not Profissoes.window:isDestroyed() then Profissoes.window:destroy() end
  if Profissoes.craftWindow and not Profissoes.craftWindow:isDestroyed() then Profissoes.craftWindow:destroy() end
  Profissoes.window = g_ui.displayUI('profissoes'); Profissoes.window:hide()
  local root = modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
  g_keyboard.bindKeyPress('Ctrl+J', Profissoes.toggle, root)
  connect(g_game, {onGameStart=Profissoes.onGameStart, onGameEnd=Profissoes.onGameEnd}, true)
  modules.game_profissoes = Profissoes; g_logger.info('[Profissoes] Modulo carregado. Atalho: Ctrl+J. OPCODE=90')
  if g_game.isOnline() then Profissoes.tryRegisterOpcode() end
end

function terminate()
  local root = modules.game_interface and modules.game_interface.getRootPanel() or rootWidget
  g_keyboard.unbindKeyPress('Ctrl+J', root); if Profissoes.retryEvent then removeEvent(Profissoes.retryEvent); Profissoes.retryEvent=nil end
  Profissoes.stopCraftTimer(); Profissoes.closeCraftWindow()
  if Profissoes.opcodeRegistered then pcall(function() ProtocolGame.unregisterExtendedOpcode(Profissoes.OPCODE) end) end
  disconnect(g_game, {onGameStart=Profissoes.onGameStart, onGameEnd=Profissoes.onGameEnd}); safeDestroy(Profissoes.window); Profissoes.window=nil; Profissoes.opcodeRegistered=false; modules.game_profissoes=nil
end
