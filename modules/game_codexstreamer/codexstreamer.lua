-- ============================================================
-- CODEX STREAMER (cliente) - opcode 130
--   * Painel do Streamer: botao "Streamer" no topo (so aparece para streamers)
--   * Cor diferente no chat para streamers (roxo) e para quem esta ao vivo
--     (o console chama modules.game_codexstreamer.chatStyle)
-- ============================================================
local OPCODE = 130
local HOTKEY = 'Ctrl+Shift+L'
local COLOR_STREAMER = '#b48cff'
local COLOR_LIVE = '#ff6b8b'

local window, button
local streamers = {}        -- [nome] = true (ao vivo) / false
local me = nil              -- dados do painel
local prizeKeys, emotesBuilt = {}, ''

local function proto() return g_game.getProtocolGame() end

function send(text)
  local p = proto()
  if p then p:sendExtendedOpcode(OPCODE, text) end
end

local function split(s, sep)
  local out = {}
  for v in (tostring(s or '') .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = v end
  return out
end

-- ---------------- chat ----------------
local CHAT_MODES = nil
local function chatModes()
  if CHAT_MODES then return CHAT_MODES end
  CHAT_MODES = {}
  for _, k in ipairs({'Say', 'Whisper', 'Yell', 'PrivateFrom', 'PrivateTo', 'Channel', 'ChannelHighlight', 'GamemasterChannel', 'GamemasterPrivateFrom'}) do
    if MessageModes[k] then CHAT_MODES[MessageModes[k]] = true end
  end
  return CHAT_MODES
end

function chatStyle(name, mode, speaktype)
  local live = streamers[name]
  if live == nil or not chatModes()[mode] or not speaktype then return nil end
  local st = {}
  for k, v in pairs(speaktype) do st[k] = v end
  st.color = live and COLOR_LIVE or COLOR_STREAMER
  st.codexStreamer = true
  return st
end

-- ---------------- painel ----------------
local function fmtWait(s)
  s = tonumber(s) or 0
  if s <= 0 then return nil end
  return math.floor(s / 3600) .. 'h ' .. math.floor((s % 3600) / 60) .. 'min'
end

local function fillCombo(combo, list, keep)
  local cur = keep and combo:getText() or nil
  combo:clearOptions()
  for _, v in ipairs(list) do combo:addOption(v) end
  if cur and cur ~= '' then pcall(function() combo:setCurrentOption(cur) end) end
end

local function refresh()
  if not window or not me then return end
  local st = window:getChildById('liveState')
  if me.live then st:setText('AO VIVO') st:setColor(COLOR_LIVE) else st:setText('FORA DO AR') st:setColor('#8ea4c2') end
  window:getChildById('stats'):setText(string.format('No mes: %dh %02dmin ao vivo  |  Indicacoes: %d (pontos: %d)',
    math.floor(me.minutes / 60), me.minutes % 60, me.refs, me.points))
  local link = window:getChildById('link')
  if not link:isFocused() then link:setText(me.link) end
  local lb = window:getChildById('liveButton')
  lb:setText(me.live and 'Encerrar live' or 'Ir ao vivo (com o link acima)')
  window:getChildById('tDraw'):setText('SORTEIO PARA O CHAT  -  livres: ' .. me.draws .. '  (1 a cada ' .. me.every .. ' min ao vivo)')
  window:getChildById('drawButton'):setEnabled(me.live and me.draws > 0)
  local wait = fmtWait(me.lure)
  local lure = window:getChildById('lureButton')
  lure:setText(wait and ('Chamariz disponivel em ' .. wait) or 'Chamar pokemon raro perto de mim')
  lure:setEnabled(me.live and not wait)
  window:getChildById('travelButton'):setEnabled(me.live)
  local prize = window:getChildById('prize')
  local labels = {}
  prizeKeys = {}
  for _, pr in ipairs(me.prizes) do labels[#labels + 1] = pr[2]; prizeKeys[pr[2]] = pr[1] end
  fillCombo(prize, labels, true)
  fillCombo(window:getChildById('town'), me.towns, true)
  local key = table.concat(me.emotes, ',')
  if key ~= emotesBuilt then
    emotesBuilt = key
    local box = window:getChildById('emotes')
    box:destroyChildren()
    for _, e in ipairs(me.emotes) do
      local b = g_ui.createWidget('CSEmote', box)
      b:setText(e:upper())
      b.onClick = function() send('EMOTE|' .. e) end
    end
  end
  window:getChildById('tips'):setText('Ao vivo, quem fica perto de voce (ou no seu grupo) ganha +' .. me.aexp .. '% de exp e +' .. me.acatch ..
    '% de captura. O link aparece para todos ao entrar ao vivo e no comando !lives.')
end

function show(fromServer)
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if not fromServer then send('REQ') end   -- pedido so por clique (anti-bot do cliente)
  refresh()
end

function hide()
  if window then window:hide() end
end

function toggle()
  if not me then return end
  if window:isVisible() then hide() else show() end
end

function sendLink()
  local t = window:getChildById('link'):getText()
  send('LINK|' .. t:gsub('|', ''))
end

function toggleLive()
  if not me then return end
  if me.live then
    send('LIVEOFF')
  else
    local t = window:getChildById('link'):getText():gsub('|', '')
    if t == '' then
      modules.game_textmessage.displayFailureMessage('Coloque o link da sua live primeiro.')
      window:getChildById('link'):focus()
      return
    end
    send('LIVEON|' .. t)
  end
end

function doDraw()
  local name = window:getChildById('drawName'):getText():gsub('|', '')
  local key = prizeKeys[window:getChildById('prize'):getText()]
  if name == '' or not key then
    modules.game_textmessage.displayFailureMessage('Digite o nome do jogador e escolha o premio.')
    return
  end
  send('DRAW|' .. name .. '|' .. key)
end

function doTravel()
  local t = window:getChildById('town'):getText()
  if t ~= '' then send('TRAVEL|' .. t) end
end

local function setButton(on)
  if on and not button and modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('codexStreamerButton', 'Painel do Streamer (' .. HOTKEY .. ')', 'streamer', toggle)
  elseif not on and button then
    button:destroy()
    button = nil
    hide()
  end
end

-- ---------------- rede ----------------
local function onOpcode(protocol, opcode, data)
  data = tostring(data or '')
  local f = split(data, '|')
  if f[1] == 'NAMES' then
    streamers = {}
    for _, e in ipairs(split(f[2] or '', ';')) do
      local n, l = e:match('^(.-):(%d)$')
      if n and n ~= '' then streamers[n] = (l == '1') end
    end
  elseif f[1] == 'ME' then
    if f[2] ~= '1' then me = nil setButton(false) return end
    local prizes = {}
    for _, e in ipairs(split(f[10] or '', ';')) do
      local k, v = e:match('^(.-):(.*)$')
      if k and k ~= '' then prizes[#prizes + 1] = {k, v} end
    end
    local towns = {}
    for _, t in ipairs(split(f[11] or '', ';')) do if t ~= '' then towns[#towns + 1] = t end end
    local emotes = {}
    for _, e in ipairs(split(f[12] or '', ';')) do if e ~= '' then emotes[#emotes + 1] = e end end
    me = {live = f[3] == '1', link = f[4] or '', minutes = tonumber(f[5]) or 0, draws = tonumber(f[6]) or 0, lure = tonumber(f[7]) or 0,
      refs = tonumber(f[8]) or 0, points = tonumber(f[9]) or 0, prizes = prizes, towns = towns, emotes = emotes,
      every = tonumber(f[13]) or 30, aexp = tonumber(f[14]) or 10, acatch = tonumber(f[15]) or 10}
    setButton(true)
    refresh()
  elseif f[1] == 'OPEN' then
    if me and (f[2] or '') ~= '' then me.link = f[2] end
    show(true)
    if window then window:getChildById('link'):focus() end
  end
end

local function onGameEnd()
  hide()
  streamers, me = {}, nil
  setButton(false)
end

function init()
  window = g_ui.displayUI('codexstreamer')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  g_keyboard.bindKeyDown(HOTKEY, toggle)
  connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
  disconnect(g_game, {onGameEnd = onGameEnd})
  g_keyboard.unbindKeyDown(HOTKEY)
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  if button then button:destroy() button = nil end
  if window then window:destroy() window = nil end
end
