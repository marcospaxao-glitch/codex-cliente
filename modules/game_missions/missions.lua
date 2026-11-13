-- ============================================================
-- MISSOES DIARIAS (cliente) - opcode 103
-- Servidor: data/lib/core/missions.lua
-- Abre pelo atalho Ctrl+Shift+Q, pelo botao do topo ou pelo NPC.
-- So envia opcodes a partir de cliques/teclas do jogador.
-- ============================================================

local OPCODE = 103
local HOTKEY = 'Ctrl+Shift+Q'

local DIFF_COLORS = { '#5fd35f', '#f2c400', '#e04848' }
local KIND_TEXT = {
  kill = 'Derrotar - conta quando voce ou seu pokemon derrota um selvagem',
  catch = 'Capturar - conta a cada captura com sucesso',
  fish = 'Pescar - conta a cada pokemon pescado',
  deliver = 'Entregar - clique em Entregar com os itens na mochila',
}

local window = nil
local topButton = nil
local timerEvent = nil
local resetAt = 0
local page = 'missions'
local data = { points = 0, rerolls = 0, bonus = 0, bonusText = '', done = 0, total = 0, missions = {}, shop = {} }

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

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

local function fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  return (s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', ''))
end

local function styleTab(button, active)
  button:setColor(active and '#0a1320' or '#dce8f5')
  button:setBackgroundColor(active and '#f2c400' or '#101f3e')
  button:setBorderColor(active and '#ffe27a' or '#24415f')
end

-- ============================================================
-- contagem para o proximo dia
-- ============================================================
local function updateTimer()
  timerEvent = nil
  if not window or not window:isVisible() then return end
  local left = math.max(0, resetAt - os.time())
  local h, m, s = math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60
  W('timerLabel'):setText(string.format('Novas missoes em %02d:%02d:%02d', h, m, s))
  timerEvent = scheduleEvent(updateTimer, 1000)
end

-- ============================================================
-- missoes
-- ============================================================
local function buildCards()
  local cards = W('cards')
  cards:destroyChildren()
  for slot = 1, 3 do
    local m = data.missions[slot]
    if m then
      local card = g_ui.createWidget('MsCard', cards)
      local color = DIFF_COLORS[slot] or '#5fd35f'
      local complete = m.progress >= m.goal
      card:getChildById('accent'):setBackgroundColor(color)
      local diff = card:getChildById('diffLabel')
      diff:setText(m.diff)
      diff:setBackgroundColor(color)
      diff:setColor(slot == 3 and '#ffffff' or '#0a1320')
      card:getChildById('icon'):setItemId(m.icon)
      card:getChildById('description'):setText(m.text)
      card:getChildById('kindLabel'):setText(KIND_TEXT[m.kind] or '')
      card:getChildById('rewardLabel'):setText('Recompensa: ' .. m.reward)

      local progressLabel = card:getChildById('progressLabel')
      progressLabel:setText(m.claimed and 'RESGATADA' or (fmt(m.progress) .. ' / ' .. fmt(m.goal)))
      local track = card:getChildById('track')
      local fill = card:getChildById('fill')
      local ratio = m.goal > 0 and math.min(1, m.progress / m.goal) or 0
      local function sizeFill()
        if fill:isDestroyed() then return end
        local width = track:getWidth()
        if not width or width <= 2 then width = 458 end
        fill:setWidth(math.floor((width - 2) * ratio))
      end
      sizeFill()
      scheduleEvent(sizeFill, 50) -- depois do layout calcular a largura
      fill:setBackgroundColor(complete and '#2e7d4a' or '#3a6ea5')

      local claim = card:getChildById('claimButton')
      claim:setText(m.claimed and 'Resgatada' or 'Resgatar')
      claim:setEnabled(complete and not m.claimed)
      claim.onClick = function() send('CLAIM|' .. slot) end

      local deliver = card:getChildById('deliverButton')
      deliver:setVisible(m.kind == 'deliver' and not complete)
      deliver:setText('Entregar (' .. fmt(m.owned) .. ')')
      deliver:setEnabled(m.owned > 0)
      deliver:setTooltip('Entrega o que voce tem na mochila (falta ' .. fmt(m.goal - m.progress) .. ')')
      deliver.onClick = function() send('DELIVER|' .. slot) end

      local reroll = card:getChildById('rerollButton')
      reroll:setVisible(not m.claimed)
      reroll:setEnabled(data.rerolls > 0 and not m.claimed)
      reroll:setTooltip(data.rerolls > 0 and 'Sorteia outra missao da mesma dificuldade (o progresso desta e perdido)' or 'Voce ja usou a troca de hoje')
      reroll.onClick = function() send('REROLL|' .. slot) end

      if m.claimed then
        card:setBorderColor('#2f6b3a')
        card:getChildById('description'):setColor('#8fa7c4')
      elseif complete then
        card:setBorderColor('#5fd35f')
      end
    end
  end

  local bonusButton = W('bonusButton')
  if data.bonus == 2 then
    bonusButton:setText('Bonus resgatado')
    bonusButton:setEnabled(false)
  else
    bonusButton:setText('Resgatar bonus')
    bonusButton:setEnabled(data.bonus == 1)
  end
  W('bonusLabel'):setText('Complete as 3 missoes de hoje (' .. data.done .. '/3): ' .. data.bonusText)
  W('rerollLabel'):setText(data.rerolls > 0 and ('Trocas gratis hoje: ' .. data.rerolls) or 'Troca de hoje ja usada.')
end

-- ============================================================
-- loja
-- ============================================================
local function buildShop()
  local list = W('shopList')
  list:destroyChildren()
  for _, entry in ipairs(data.shop) do
    local row = g_ui.createWidget('MsShopRow', list)
    row:getChildById('item'):setItemId(entry.clientId)
    row:getChildById('name'):setText(entry.name)
    row:getChildById('sub'):setText(entry.count > 1 and ('Pacote com ' .. entry.count) or 'Unidade')
    row:getChildById('price'):setText(fmt(entry.price) .. ' pts')
    row:setTooltip(entry.count .. 'x ' .. entry.name)
    local qty = row:getChildById('qty')
    local button = row:getChildById('buyButton')
    local function update()
      local n = tonumber((qty:getText() or ''):match('%d+')) or 0
      local cost = n * entry.price
      button:setEnabled(n > 0 and cost <= data.points)
      button:setTooltip(n > 0 and ('Total: ' .. fmt(cost) .. ' pontos') or '')
    end
    qty.onTextChange = update
    update()
    local index = entry.index
    button.onClick = function()
      local n = tonumber((qty:getText() or ''):match('%d+')) or 0
      if n > 0 then send('BUY|' .. index .. '|' .. n) end
    end
  end
end

local function refresh(withShop)
  if not window then return end
  W('pointsLabel'):setText('Pontos: ' .. fmt(data.points))
  W('subtitleLabel'):setText('Hoje: ' .. data.done .. ' / 3 concluidas   -   Total: ' .. fmt(data.total) .. ' missoes')
  styleTab(W('tabMissions'), page == 'missions')
  styleTab(W('tabShop'), page == 'shop')
  W('missionsPage'):setVisible(page == 'missions')
  W('shopPage'):setVisible(page == 'shop')
  buildCards()
  if withShop then buildShop() end
end

-- ============================================================
-- mensagens do servidor
-- ============================================================
local function onMissionsOpcode(protocol, opcode, buffer)
  if not window then return end
  local header = nil
  local missions, shop = {}, {}
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'MS' then
      header = f
    elseif f[1] == 'M' then
      local slot = tonumber(f[2])
      if slot then
        missions[slot] = {
          diff = f[3] or '', kind = f[4] or '', text = f[5] or '',
          goal = tonumber(f[6]) or 1, progress = tonumber(f[7]) or 0, claimed = f[8] == '1',
          icon = tonumber(f[9]) or 0, reward = f[10] or '', owned = tonumber(f[11]) or 0,
        }
      end
    elseif f[1] == 'SH' then
      shop[#shop + 1] = { index = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, name = f[4] or '?',
        count = tonumber(f[5]) or 1, price = tonumber(f[6]) or 0 }
    end
  end
  if not header then return end
  local open = header[2] == '1'
  -- atualizacao sem a janela aberta e sem pedido de abrir: ignora
  if not open and not window:isVisible() then return end
  resetAt = os.time() + (tonumber(header[3]) or 0)
  data.rerolls = tonumber(header[5]) or 0
  data.bonus = tonumber(header[6]) or 0
  data.bonusText = header[7] or ''
  data.done = tonumber(header[8]) or 0
  data.total = tonumber(header[9]) or 0
  data.missions = missions
  local pointsChanged = data.points ~= (tonumber(header[4]) or 0)
  data.points = tonumber(header[4]) or 0
  if #shop > 0 then data.shop = shop end

  if open and not window:isVisible() then
    window:show()
    window:raise()
    window:focus()
    if topButton then topButton:setOn(true) end
  end
  refresh(#shop > 0 or pointsChanged)
  if not timerEvent then
    updateTimer()
  end
end

-- ============================================================
-- abrir / fechar
-- ============================================================
function show()
  if not g_game.isOnline() then return end
  send('OPEN') -- o servidor responde com os dados e a janela abre
end

function hide()
  if window and window:isVisible() then
    window:hide()
    send('CLOSE')
  end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
  if topButton then topButton:setOn(false) end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

local function setPage(name)
  page = name
  refresh(false)
end

local function onGameEnd()
  if window then window:hide() end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
  if topButton then topButton:setOn(false) end
end

function init()
  window = g_ui.displayUI('missions')
  window:hide()

  W('closeButton').onClick = function() hide() end
  W('tabMissions').onClick = function() setPage('missions') end
  W('tabShop').onClick = function() setPage('shop') end
  W('bonusButton').onClick = function() send('BONUS') end

  ProtocolGame.registerExtendedOpcode(OPCODE, onMissionsOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, toggle)

  local ok, button = pcall(function()
    return modules.client_topmenu.addRightGameToggleButton('missionsButton',
      'Missoes diarias (' .. HOTKEY .. ')', '/modules/game_missions/images/icon', toggle)
  end)
  if ok then topButton = button end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.unbindKeyDown(HOTKEY)
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
  if topButton then
    topButton:destroy()
    topButton = nil
  end
  if window then
    window:destroy()
    window = nil
  end
end
