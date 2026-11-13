-- ============================================================
-- CODEX - Recompensa por hora jogada (cliente) - opcode 131
--   Botao "Recompensas" no topo: progresso da hora, pontos,
--   premios possiveis e o botao da Loja de Horas.
-- ============================================================
local OPCODE = 131
local window, button
local data = nil

local function send(text)
  local p = g_game.getProtocolGame()
  if p then p:sendExtendedOpcode(OPCODE, text) end
end

local function split(s, sep)
  local out = {}
  for v in (tostring(s or '') .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = v end
  return out
end

local function refresh()
  if not window or not data then return end
  local W = function(id) return window:recursiveGetChildById(id) end
  local left = 60 - data.min
  if data.cap then
    W('nextPrize'):setText('Limite de hoje atingido')
  else
    W('nextPrize'):setText('Proximo premio em ' .. left .. ' min')
  end
  local bg = W('barBg')
  local w = math.max(1, math.floor((bg:getWidth() - 2) * math.min(60, data.min) / 60))
  W('barFill'):setWidth(w)
  W('barFill'):setBackgroundColor(data.afk and '#5a6b85' or (data.cap and '#5fd35f' or '#f2c400'))
  if data.afk then
    W('state'):setText('Voce esta parado: ande ou lute para o tempo contar')
    W('state'):setColor('#ff9b9b')
  elseif data.cap then
    W('state'):setText('Volte amanha para mais recompensas')
    W('state'):setColor('#5fd35f')
  else
    W('state'):setText(data.min .. ' de 60 minutos')
    W('state'):setColor('#8ea4c2')
  end
  W('points'):setText(data.points .. ' pontos')
  W('today'):setText(data.today .. (data.max > 0 and (' / ' .. data.max) or ''))
  W('total'):setText(tostring(data.total))
  W('streak'):setText(data.streak .. (data.streak == 1 and ' dia' or ' dias'))
  W('perHour'):setText('+' .. data.perHour)
  W('marco'):setText(data.marcoH > 0 and (data.marcoH .. 'h - ' .. data.marcoNome) or 'todos feitos!')
  local box = W('prizes')
  box:destroyChildren()
  for _, p in ipairs(data.prizes) do
    if p ~= '' then
      local l = g_ui.createWidget('CHPrize', box)
      l:setText('- ' .. p)
    end
  end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  send('REQ')   -- so por clique (anti-bot do cliente)
  refresh()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not window then return end
  if window:isVisible() then hide() else show() end
end

function openShop()
  send('SHOP')
end

local function onOpcode(protocol, opcode, buffer)
  local f = split(buffer, '|')
  if f[1] == 'ME' then
    data = {min = tonumber(f[2]) or 0, points = tonumber(f[3]) or 0, today = tonumber(f[4]) or 0, max = tonumber(f[5]) or 0,
      total = tonumber(f[6]) or 0, streak = tonumber(f[7]) or 0, afk = f[8] == '1', cap = f[9] == '1',
      marcoH = tonumber(f[10]) or 0, marcoNome = f[11] or '', perHour = tonumber(f[12]) or 0, prizes = split(f[13] or '', ';')}
    if button then
      button:setTooltip('Recompensas: ' .. (data.cap and 'limite de hoje atingido' or ('proximo premio em ' .. (60 - data.min) .. ' min')) .. ' | ' .. data.points .. ' pontos')
    end
    refresh()
  elseif f[1] == 'REWARD' then
    if button then pcall(function() g_effects.startBlink(button, 4000, 400) end) end
  end
end

local function onGameStart()
  if not button and modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('codexHorasButton', 'Recompensas por tempo jogado', 'horas', toggle)
  end
end

local function onGameEnd()
  hide()
  data = nil
end

function init()
  window = g_ui.displayUI('codexhoras')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  if button then button:destroy() button = nil end
  if window then window:destroy() window = nil end
end
