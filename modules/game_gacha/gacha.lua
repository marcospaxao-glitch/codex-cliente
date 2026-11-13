-- ============================================================
-- GACHA (cliente) - opcode 96
-- O servidor ja sorteou e entregou o pokemon. Aqui so mostramos a
-- roleta girando ate parar no premio (animacao local, sem envio).
-- ============================================================

local OPCODE = 96
local ICON_PATH = '/modules/game_pokemonbar/bar_icon/'
local CARD_W = 84
local STEP = 90          -- largura do card + espaco
local VISIBLE = 9        -- cards criados (reaproveitados durante o giro)
local DURATION = 4800    -- ms

local HOTKEY = 'Ctrl+Shift+G'
local ROLL_WIDGETS = { 'rollFrame', 'markerTop', 'markerLine', 'markerBottom', 'statusLabel' }

local window = nil
local topButton = nil
local rolling = false
local cards = {}
local strip = {}
local prize = nil
local animEvent = nil
local startTime = 0
local finalOffset = 0

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, text)
  end
end

-- alterna entre a tela inicial (lista de gachas) e a roleta
local function setMode(mode)
  local isLobby = mode == 'lobby'
  for _, id in ipairs(ROLL_WIDGETS) do
    W(id):setVisible(not isLobby)
  end
  W('lobbyPanel'):setVisible(isLobby)
  W('lobbyHint'):setVisible(isLobby)
  if isLobby then
    W('resultPanel'):hide()
    W('okButton'):setText('FECHAR')
    W('okButton'):setEnabled(true)
  else
    W('okButton'):setText('VOLTAR')
  end
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do
    fields[#fields + 1] = field
  end
  return fields
end

local function iconFor(name)
  local lower = tostring(name or ''):lower()
  local path = ICON_PATH .. lower .. '.png'
  if g_resources.fileExists(path) then return path end
  -- shiny sem imagem propria: usa a normal
  if lower:sub(1, 6) == 'shiny ' then
    local base = ICON_PATH .. lower:sub(7) .. '.png'
    if g_resources.fileExists(base) then return base end
  end
  if lower:sub(1, 5) == 'mega ' then
    return ICON_PATH .. lower:sub(6):gsub(' [xy]$', '') .. '.png'
  end
  return path
end

local function nowMs()
  return g_clock and g_clock.millis and g_clock.millis() or os.time() * 1000
end

-- ============================================================
-- roleta
-- ============================================================
local function frameWidth()
  return W('rollFrame'):getWidth()
end

local function placeCards(offset)
  local first = math.floor(offset / STEP)
  local shift = offset - first * STEP
  local width = frameWidth()
  for i, card in ipairs(cards) do
    local index = first + i
    local x = (i - 1) * STEP - shift + 6
    local name = strip[index]
    if name and x > -CARD_W / 2 and x < width - CARD_W / 2 then
      card:setVisible(true)
      card:setMarginLeft(x)
      if card.shownName ~= name then
        card.shownName = name
        card:getChildById('portrait'):setImageSource(iconFor(name))
        card:getChildById('name'):setText(name)
      end
      -- destaque no card do centro
      local center = x + CARD_W / 2
      local near = math.abs(center - width / 2) < STEP / 2
      card:setBorderColor(near and '#f2c400' or '#1d3557')
    else
      card:setVisible(false)
    end
  end
end

local function showResult()
  if not prize then return end
  local panel = W('resultPanel')
  W('resultPortrait'):setImageSource(iconFor(prize.name))
  W('resultName'):setText(prize.name .. '   -   Nivel ' .. prize.level)
  local tags = {}
  if prize.shiny then tags[#tags + 1] = 'SHINY' end
  if prize.perfect then tags[#tags + 1] = 'IVs PERFEITOS' end
  if prize.stone ~= '' then tags[#tags + 1] = 'Mega Stone: ' .. prize.stone end
  W('resultInfo'):setText(#tags > 0 and table.concat(tags, '   |   ') or (prize.iv >= 0 and ('IV ' .. prize.iv .. '%') or ''))
  local extra = 'IV ' .. (prize.iv >= 0 and (prize.iv .. '%') or '-') .. '   |   Amizade ' .. prize.love
  extra = extra .. (prize.toPc and '   |   Foi para o seu PC' or '   |   Entrou na sua equipe')
  W('resultExtra'):setText(extra)

  local grid = W('ivGrid')
  grid:destroyChildren()
  local names = { 'HP', 'Ataque', 'Defesa', 'Atq. Esp.', 'Def. Esp.', 'Velocidade' }
  for i, label in ipairs(names) do
    local value = prize.ivs[i] or 0
    local row = g_ui.createWidget('GachaIv', grid)
    row:setText(label .. ': ' .. value .. '/31')
    row:setColor(value >= 31 and '#5fd35f' or (value >= 25 and '#dce8f5' or '#8fa7c4'))
  end
  panel:show()
  W('statusLabel'):setText('Parabens!')
  W('statusLabel'):setColor('#f2c400')
  W('okButton'):setEnabled(true)
  rolling = false
end

local function animate()
  animEvent = nil
  if not window or not window:isVisible() then return end
  local t = math.min(1, (nowMs() - startTime) / DURATION)
  local eased = 1 - (1 - t) ^ 4
  placeCards(finalOffset * eased)
  if t < 1 then
    animEvent = scheduleEvent(animate, 16)
  else
    showResult()
  end
end

-- ============================================================
-- mensagens do servidor
-- ============================================================
local function showLobby(buffer)
  local panel = W('lobbyPanel')
  panel:destroyChildren()
  local total = 0
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'G' then
      local itemId, count = tonumber(f[2]) or 0, tonumber(f[6]) or 0
      local color = f[5] ~= '' and f[5] or '#f2c400'
      total = total + count
      local box = g_ui.createWidget('GachaBox', panel)
      box:getChildById('stripe'):setBackgroundColor(color)
      box:getChildById('icon'):setItemId(tonumber(f[3]) or 0)
      box:getChildById('name'):setText(f[4] or '')
      box:getChildById('name'):setColor(color)
      local countLabel = box:getChildById('count')
      countLabel:setText('Voce tem: ' .. count)
      countLabel:setColor(count > 0 and '#5fd35f' or '#6f86a8')
      box:getChildById('desc'):setText(f[7] or '')
      local button = box:getChildById('rollButton')
      button:setEnabled(count > 0)
      button.onClick = function()
        if rolling then return end
        rolling = true
        button:setEnabled(false)
        send('ROLL|' .. itemId)
      end
    end
  end
  W('titleLabel'):setText('GACHA POKEMON')
  W('titleLabel'):setColor('#f2c400')
  W('headerBar'):setBackgroundColor('#f2c400')
  window:setBorderColor('#f2c400')
  W('lobbyHint'):setText(total > 0 and 'Escolha um gacha e clique em GIRAR.' or 'Voce nao tem itens de gacha. Consiga-os em eventos, loja ou recompensas.')
  rolling = false
  setMode('lobby')
  if not window:isVisible() then
    window:show()
    window:raise()
    window:focus()
  end
end

local function onGachaOpcode(protocol, opcode, buffer)
  if not window then return end
  if (buffer or ''):sub(1, 5) == 'LOBBY' then
    showLobby(buffer)
    return
  end
  local header
  strip, prize = {}, nil
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'GACHA' then
      header = f
    elseif f[1] == 'PRIZE' then
      local ivs = {}
      for i = 10, 15 do ivs[#ivs + 1] = tonumber(f[i]) or 0 end
      prize = { name = f[2] or '?', level = tonumber(f[3]) or 1, iv = tonumber(f[4]) or -1, love = tonumber(f[5]) or 0,
        shiny = f[6] == '1', stone = f[7] or '', perfect = f[8] == '1', toPc = f[9] == '1', ivs = ivs }
    elseif f[1] == 'S' then
      local index = tonumber(f[2])
      if index then strip[index] = f[3] or '' end
    end
  end
  if not header or not prize then return end
  rolling = true
  setMode('roll')

  local color = header[3] ~= '' and header[3] or '#f2c400'
  W('titleLabel'):setText(header[2]:upper())
  W('titleLabel'):setColor(color)
  W('headerBar'):setBackgroundColor(color)
  window:setBorderColor(color)
  W('resultPanel'):hide()
  W('statusLabel'):setText('Girando...')
  W('statusLabel'):setColor('#8fa7c4')
  W('okButton'):setEnabled(false)

  -- para com o card do premio no centro (com um pequeno desvio aleatorio)
  local prizeIndex = tonumber(header[4]) or #strip
  local width = frameWidth()
  local jitter = math.random(-28, 28)
  finalOffset = (prizeIndex - 1) * STEP + 6 + CARD_W / 2 - width / 2 + jitter
  for _, card in ipairs(cards) do card.shownName = nil end
  placeCards(0)

  window:show()
  window:raise()
  window:focus()
  startTime = nowMs()
  if animEvent then removeEvent(animEvent) end
  animEvent = scheduleEvent(animate, 16)
end

-- ============================================================
-- abrir / fechar
-- ============================================================
function show()
  if g_game.isOnline() then
    send('OPEN')
  end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

function hide()
  rolling = false
  if animEvent then
    removeEvent(animEvent)
    animEvent = nil
  end
  if window then
    window:hide()
  end
end

local function onGameEnd()
  hide()
end

function init()
  window = g_ui.displayUI('gacha')
  window:hide()
  local frame = W('rollFrame')
  for i = 1, VISIBLE do
    cards[i] = g_ui.createWidget('GachaCard', frame)
  end
  W('okButton').onClick = function()
    if W('lobbyPanel'):isVisible() then
      hide()
    else
      show() -- volta para a lista (com as quantidades atualizadas)
    end
  end

  ProtocolGame.registerExtendedOpcode(OPCODE, onGachaOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, toggle)

  local topmenu = modules.client_topmenu
  local ok, button = pcall(function()
    local tooltip = 'Gacha Pokemon.\nAtalho: ' .. HOTKEY
    if topmenu.addCenterGameButton then
      return topmenu.addCenterGameButton('gachaButton', tooltip, '/modules/game_gacha/images/topbutton.png', toggle)
    end
    return topmenu.addRightGameToggleButton('gachaButton', tooltip, '/modules/game_gacha/images/topbutton', toggle)
  end)
  if ok then topButton = button end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown(HOTKEY)
  if topButton then
    topButton:destroy()
    topButton = nil
  end
  hide()
  if window then
    window:destroy()
    window = nil
  end
  cards = {}
end
