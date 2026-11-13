-- ============================================================
-- RECOMPENSAS DIARIAS (cliente) - opcode 95
-- Abre pelo atalho Ctrl+Shift+D, pelo botao do topo, ou sozinha no
-- login quando ha recompensa. Envio ao servidor so por clique/tecla.
-- ============================================================

local OPCODE = 95
local PER_PAGE = 7
local HOTKEY = 'Ctrl+Shift+D'

local window = nil
local topButton = nil
local data = { day = 0, canClaim = false, premium = false, pending = 0, total = 0, cycle = 1, days = {} }
local resetAt = 0
local page = 1
local timerEvent = nil

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

local function shortCount(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return math.floor(n / 100000) / 10 .. 'kk' end
  if n >= 1000 then return math.floor(n / 100) / 10 .. 'k' end
  return tostring(n)
end

-- ============================================================
-- contagem para o proximo dia (so atualiza o texto)
-- ============================================================
local function updateTimer()
  timerEvent = nil
  if not window or not window:isVisible() then return end
  local left = math.max(0, resetAt - os.time())
  local h, m, s = math.floor(left / 3600), math.floor(left % 3600 / 60), left % 60
  local text = string.format('Novo dia em %02d:%02d:%02d', h, m, s)
  W('timerLabel'):setText(text)
  timerEvent = scheduleEvent(updateTimer, 1000)
end

-- ============================================================
-- desenho
-- ============================================================
local function fillCell(cell, reward, locked, claimed)
  local item = cell:getChildById('item')
  local amount = cell:getChildById('amount')
  local name = cell:getChildById('name')
  if reward.kind == 'N' then
    item:setVisible(false)
    amount:setText('-')
    name:setText('')
    cell:setTooltip('Sem recompensa')
  else
    item:setVisible(true)
    item:setItemId(reward.clientId)
    if reward.kind == 'C' then
      amount:setText(fmt(reward.count))
      name:setText(reward.name)
    else
      amount:setText('x' .. fmt(reward.count))
      name:setText(reward.name)
    end
    cell:setTooltip(reward.kind == 'C' and (fmt(reward.count) .. ' ' .. reward.name) or (reward.count .. 'x ' .. reward.name))
  end
  cell:getChildById('shade'):setVisible(locked or claimed)
  cell:getChildById('lock'):setVisible(locked and not claimed)
  cell:getChildById('check'):setVisible(claimed and not locked)
  amount:setColor((locked or claimed) and '#6f86a8' or '#ffffff')
end

local function buildDays()
  local track = W('track')
  track:destroyChildren()
  local first = (page - 1) * PER_PAGE + 1
  local last = math.min(data.total, first + PER_PAGE - 1)
  local nextDay = data.day + 1
  local premiumUpto = data.premium and (data.day - data.pending) or 0
  for n = first, last do
    local entry = data.days[n]
    if entry then
      local column = g_ui.createWidget('DRColumn', track)
      local label = column:getChildById('dayLabel')
      local band = column:getChildById('band')
      local claimed = n <= data.day
      local isToday = data.canClaim and n == nextDay
      label:setText('DIA ' .. n)

      fillCell(column:getChildById('freeCell'), entry.free, false, claimed)
      fillCell(column:getChildById('premiumCell'), entry.premium, not data.premium, n <= premiumUpto)

      if isToday then
        band:setBackgroundColor('#f2c400')
        band:setBorderColor('#ffe27a')
        label:setFont('verdana-11px-antialised')
        label:setColor('#1a1200')
        label:setText('HOJE  -  DIA ' .. n)
        column:getChildById('freeCell'):setBorderColor('#f2c400')
        column:getChildById('premiumCell'):setBorderColor('#f2c400')
      elseif claimed then
        band:setBackgroundColor('#13301c')
        band:setBorderColor('#2f6b3a')
        label:setColor('#5fd35f')
      elseif n % 7 == 0 then
        band:setBackgroundColor('#1f1a06')
        band:setBorderColor('#6b5a10')
        label:setColor('#f2c400')
      end
    end
  end

  local pages = math.max(1, math.ceil(data.total / PER_PAGE))
  W('pageLabel'):setText('Semana ' .. page .. ' / ' .. pages)
  W('prevPage'):setEnabled(page > 1)
  W('nextPage'):setEnabled(page < pages)
end

local function refresh()
  if not window then return end
  W('subtitleLabel'):setText('Ciclo ' .. data.cycle .. '  -  ' .. data.day .. ' / ' .. data.total .. ' dias')

  local claim = W('claimButton')
  if data.canClaim then
    claim:setText('RESGATAR DIA ' .. (data.day + 1))
    claim:setEnabled(true)
  else
    claim:setText(data.day >= data.total and 'CICLO COMPLETO' or 'VOLTE AMANHA')
    claim:setEnabled(false)
  end

  local premiumLabel = W('premiumLabel')
  if data.premium then
    premiumLabel:setText('Premium ativo: voce recebe as duas linhas.')
    premiumLabel:setColor('#f2c400')
  else
    premiumLabel:setText('Linha premium bloqueada. Vire premium para receber tambem a recompensa dourada.')
    premiumLabel:setColor('#8fa7c4')
  end

  local pending = W('pendingButton')
  pending:setVisible(data.premium and data.pending > 0)
  pending:setText('Pegar premium pendente (' .. data.pending .. ')')

  buildDays()
end

-- ============================================================
-- mensagens do servidor
-- ============================================================
local function onDailyOpcode(protocol, opcode, buffer)
  if not window then return end
  local days, header = {}, nil
  for line in ((buffer or '') .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'DR' then
      header = f
    elseif f[1] == 'D' then
      local n = tonumber(f[2])
      if n then
        days[n] = {
          free = { kind = f[3], clientId = tonumber(f[4]) or 0, count = tonumber(f[5]) or 0, name = f[6] or '' },
          premium = { kind = f[7], clientId = tonumber(f[8]) or 0, count = tonumber(f[9]) or 0, name = f[10] or '' },
        }
      end
    end
  end
  if not header then return end
  data.day = tonumber(header[2]) or 0
  data.canClaim = header[3] == '1'
  data.premium = header[4] == '1'
  data.pending = tonumber(header[5]) or 0
  resetAt = os.time() + (tonumber(header[6]) or 0)
  data.total = tonumber(header[7]) or 0
  data.cycle = tonumber(header[8]) or 1
  data.days = days
  -- mostra a pagina do dia atual
  page = math.max(1, math.ceil(math.max(1, data.day + (data.canClaim and 1 or 0)) / PER_PAGE))

  refresh()
  if not window:isVisible() then
    window:show()
    window:raise()
    window:focus()
  end
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
  if window then
    window:hide()
  end
  if timerEvent then
    removeEvent(timerEvent)
    timerEvent = nil
  end
  if topButton then pcall(function() topButton:setOn(false) end) end
end

function toggle()
  if window and window:isVisible() then
    hide()
  else
    show()
  end
end

local function onGameEnd()
  hide()
end

function init()
  window = g_ui.displayUI('dailyreward')
  window:hide()

  W('claimButton').onClick = function() send('CLAIM') end
  W('pendingButton').onClick = function() send('PREMIUM') end
  W('prevPage').onClick = function()
    page = math.max(1, page - 1)
    buildDays()
  end
  W('nextPage').onClick = function()
    page = math.min(math.max(1, math.ceil(data.total / PER_PAGE)), page + 1)
    buildDays()
  end

  ProtocolGame.registerExtendedOpcode(OPCODE, onDailyOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  g_keyboard.bindKeyDown(HOTKEY, toggle)

  -- botao no centro do topo, junto com os outros (game_healthinfo)
  local topmenu = modules.client_topmenu
  local tooltip = 'Recompensas diarias.\nAtalho: ' .. HOTKEY
  local ok, button = pcall(function()
    if topmenu.addCenterGameButton then
      return topmenu.addCenterGameButton('dailyRewardButton', tooltip, '/modules/game_dailyreward/images/topbutton.png', toggle)
    end
    return topmenu.addRightGameToggleButton('dailyRewardButton', tooltip, '/modules/game_dailyreward/images/icon', toggle)
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
