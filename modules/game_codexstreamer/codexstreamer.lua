-- ============================================================
-- CODEX STREAMER 2.0 (cliente) - opcode 130
--   * Painel do Streamer: botao "Streamer" no topo (so aparece para streamers)
--   * Ranking, historico, regras e resumo da live
--   * Aviso para todos quando alguem entra ao vivo ou abre sorteio
--   * Cor diferente no chat para streamers (roxo) e para quem esta ao vivo
--     (o console chama modules.game_codexstreamer.chatStyle)
--   Servidor: data/lib/core/codexstreamer.lua
-- ============================================================
local OPCODE = 130
local HOTKEY = 'Ctrl+Shift+L'
local COLOR_STREAMER = '#b48cff'
local COLOR_LIVE = '#ff6b8b'
local CIDADES_POR_PAGINA = 8
local AVISO_SEGUNDOS = 20
local CHAVE_SILENCIO = 'codexStreamAvisoSilencio'
local PLATAFORMAS = {twitch = 'Twitch', youtube = 'YouTube', kick = 'Kick', tiktok = 'TikTok', facebook = 'Facebook', trovo = 'Trovo', link = 'Link'}
local EMOTE_IMG = {f = 'st_em_f', gg = 'st_em_gg', hype = 'st_em_hype', love = 'st_em_love', pog = 'st_em_pog', rip = 'st_em_rip'}

local window, extra, button
local streamers = {}        -- [nome] = true (ao vivo) / false
local me = nil              -- dados do painel
local recebidoEm = 0        -- g_clock.millis() do ultimo ME
local premioIdx, cidadePag, cidadeSel = 1, 1, nil
local relogio = nil
local avisos = {}
local emotesFeitos = ''

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

local function hm(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  return math.floor(s / 3600) .. 'h' .. string.format('%02d', math.floor((s % 3600) / 60)) .. 'min'
end

local function falha(t)
  if modules.game_textmessage then modules.game_textmessage.displayFailureMessage(t) end
end

local function celular() return type(codexCelular) == 'function' and codexCelular() and true or false end

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
local function w(id) return window and window:recursiveGetChildById(id) end

local function decorrido() return math.floor((g_clock.millis() - recebidoEm) / 1000) end

local function stat(id, icone, titulo, valor)
  local s = w(id)
  if not s then return end
  s:getChildById('icone'):setImageSource('/game_codexstreamer/images/' .. icone)
  s:getChildById('titulo'):setText(titulo)
  s:getChildById('valor'):setText(valor)
end

-- partes que mudam a cada segundo (relogio da live, proximo sorteio, chamariz)
local function atualizarTempo()
  if not window or not me or not window:isVisible() then return end
  local passou = decorrido()
  local pil = w('pilula')
  if me.live then
    pil:setImageSource('/game_codexstreamer/images/st_pill_live')
    pil:getChildById('ponto'):setImageSource('/game_codexstreamer/images/st_dot_live')
    pil:getChildById('texto'):setText('AO VIVO ha ' .. hm(me.liveSecs + passou))
  else
    pil:setImageSource('/game_codexstreamer/images/st_pill_off')
    pil:getChildById('ponto'):setImageSource('/game_codexstreamer/images/st_dot_off')
    pil:getChildById('texto'):setText(me.link == '' and 'SEM LINK' or 'FORA DO AR')
  end
  local contando = me.live and me.ativo
  local valid = me.valid + (contando and passou or 0)
  stat('statHoras', 'st_ic_relogio', 'Horas no mes', hm(valid))
  -- proximo sorteio
  local fundo = w('barraFundo')
  local barra, texto = fundo:getChildById('barra'), fundo:getChildById('barraTexto')
  local total = me.every * 60
  if me.nextDraw < 0 then
    barra:setWidth(fundo:getWidth() - 2)
    texto:setText('Todos os sorteios do mes liberados')
  else
    local falta = math.max(0, me.nextDraw - (contando and passou or 0))
    local frac = 1 - falta / total
    barra:setWidth(math.floor((fundo:getWidth() - 2) * math.max(0, math.min(1, frac))))
    if not me.live then texto:setText('Proximo sorteio: so contando ao vivo')
    elseif not me.ativo then texto:setText('Parado: o tempo nao esta contando')
    else texto:setText('Proximo em: ' .. math.ceil(falta / 60) .. ' min') end
  end
  -- chamariz
  local ec = w('estadoChamariz')
  local espera = math.max(0, me.lure - passou)
  if not me.live then
    ec:setImageSource('/game_codexstreamer/images/st_pill_off')
    ec:getChildById('texto'):setText('So ao vivo')
  elseif espera > 0 then
    ec:setImageSource('/game_codexstreamer/images/st_pill_wait')
    ec:getChildById('texto'):setText('Recarga: ' .. hm(espera))
  else
    ec:setImageSource('/game_codexstreamer/images/st_pill_ok')
    ec:getChildById('texto'):setText('Pronto!')
  end
  w('botaoChamariz'):setEnabled(me.live and espera <= 0)
end

local function mostrarPremio()
  if not me or #me.prizes == 0 then return end
  if premioIdx < 1 then premioIdx = #me.prizes end
  if premioIdx > #me.prizes then premioIdx = 1 end
  local p = me.prizes[premioIdx]
  if me.raffle then
    for i, pr in ipairs(me.prizes) do if pr.key == me.raffle.key then p, premioIdx = pr, i end end
  end
  local item = w('premioItem')
  pcall(function() item:setItemId(p.cid) item:setItemCount(p.count) end)
  w('premioNome'):setText(p.label)
  w('premioDesc'):setText((p.cat ~= '' and (p.cat .. ' - ') or '') .. p.desc)
  w('premioBox'):setTooltip(p.desc)
end

function trocarPremio(d)
  if not me or me.raffle then return end
  premioIdx = premioIdx + d
  mostrarPremio()
end

local function montarCidades()
  local box = w('cidades')
  if not box or not me then return end
  box:destroyChildren()
  local paginas = math.max(1, math.ceil(#me.towns / CIDADES_POR_PAGINA))
  if cidadePag > paginas then cidadePag = 1 end
  if cidadePag < 1 then cidadePag = paginas end
  local ini = (cidadePag - 1) * CIDADES_POR_PAGINA + 1
  for i = ini, math.min(#me.towns, ini + CIDADES_POR_PAGINA - 1) do
    local t = me.towns[i]
    local b = g_ui.createWidget('CSCidade', box)
    b:setText(t.name)
    b:setChecked(cidadeSel == t.id)
    b.onClick = function()
      cidadeSel = t.id
      montarCidades()
    end
  end
  w('paginaCidade'):setText(paginas > 1 and (cidadePag .. ' / ' .. paginas) or '')
  w('cidadeAnt'):setVisible(paginas > 1)
  w('cidadeProx'):setVisible(paginas > 1)
  local nome = nil
  for _, t in ipairs(me.towns) do if t.id == cidadeSel then nome = t.name end end
  local bv = w('botaoViajar')
  bv:setText(nome and ('Viajar para ' .. nome) or 'Escolha uma cidade')
  bv:setEnabled(me.live and nome ~= nil)
end

function paginaCidades(d)
  cidadePag = cidadePag + d
  montarCidades()
end

local function montarEmotes()
  local key = table.concat(me.emotes, ',')
  if key == emotesFeitos then return end
  emotesFeitos = key
  local box = w('emotes')
  box:destroyChildren()
  for _, e in ipairs(me.emotes) do
    local b = g_ui.createWidget('CSEmote', box)
    local img = EMOTE_IMG[e] or 'st_em_gg'
    b:setImageSource('/game_codexstreamer/images/' .. img)
    b:setTooltip(e:upper())
    b.onClick = function()
      if not me or not me.live then return falha('Os emotes funcionam ao vivo.') end
      send('EMOTE|' .. e)
    end
    -- efeito de apertar
    b.onMousePress = function(self) self:setImageSource('/game_codexstreamer/images/' .. img .. '_on') end
    b.onMouseRelease = function(self) self:setImageSource('/game_codexstreamer/images/' .. img) end
  end
end

local function refresh()
  if not window or not me then return end
  local player = g_game.getLocalPlayer()
  if player then
    pcall(function() w('retrato'):setOutfit(player:getOutfit()) end)
    w('nome'):setText(player:getName())
  end
  w('botaoLive'):setVisible(not me.live)
  w('botaoEncerrar'):setVisible(me.live)
  stat('statAura', 'st_ic_pessoas', 'Na aura agora', me.live and (me.aura .. ' jogador' .. (me.aura == 1 and '' or 'es')) or '-')
  w('statAura'):setTooltip('Quem esta perto de voce (ou no seu grupo) ganha +' .. me.aexp .. '% EXP e +' .. me.acatch .. '% captura.')
  stat('statIndic', 'st_ic_estrela', 'Indicacoes', me.refs .. ' (' .. me.points .. ' pts)')
  stat('statRank', 'st_ic_trofeu', 'Ranking do mes', me.rank > 0 and (me.rank .. 'o lugar') or '-')
  -- sorteio
  w('disponiveis'):setText('Sorteios disponiveis: ' .. me.draws)
  local bs, bc, est = w('botaoSorteio'), w('botaoCancelar'), w('estadoSorteio')
  if me.raffle then
    est:setText('Inscricoes abertas: ' .. me.raffle.count .. ' participante' .. (me.raffle.count == 1 and '' or 's'))
    est:setColor('#72e6a0')
    bs:setText('Sortear agora')
    bs:setEnabled(me.raffle.count > 0)
    bs:removeAnchor(AnchorRight)
    bs:addAnchor(AnchorRight, 'botaoCancelar', AnchorLeft)
    bs:setMarginRight(6)
    bc:setVisible(true)
  else
    bs:setText('Abrir sorteio')
    bs:setEnabled(me.live and me.draws > 0)
    bs:removeAnchor(AnchorRight)
    bs:addAnchor(AnchorRight, 'parent', AnchorRight)
    bs:setMarginRight(0)
    bc:setVisible(false)
    est:setColor('#8fa7c4')
    if not me.live then est:setText('Apenas durante a live')
    elseif me.draws <= 0 then est:setText('Aguarde liberar um sorteio')
    else est:setText('O chat entra com !participar') end
  end
  w('premioAnt'):setEnabled(not me.raffle)
  w('premioProx'):setEnabled(not me.raffle)
  mostrarPremio()
  -- chamariz
  w('ultimo'):setText(me.lastLure ~= '' and ('Ultimo: ' .. me.lastLure) or 'Nenhum chamariz usado ainda.')
  -- emotes, cidades, tv
  montarEmotes()
  montarCidades()
  -- link
  local link = w('link')
  if not link:isFocused() then link:setText(me.link) end
  link:setEnabled(not me.live)
  local le = w('linkEstado')
  if me.link ~= '' then
    le:setImageSource('/game_codexstreamer/images/st_pill_ok')
    le:getChildById('texto'):setText('Salvo')
  else
    le:setImageSource('/game_codexstreamer/images/st_pill_wait')
    le:getChildById('texto'):setText('Sem link')
  end
  w('plataforma'):setText(me.live and 'Para trocar o link, encerre a live.' or
    ('Plataforma: ' .. (me.link ~= '' and (PLATAFORMAS[me.platform] or 'Link') or '-') .. '.  Aceita Twitch, YouTube, Kick e TikTok.'))
  w('botaoSalvar'):setEnabled(not me.live)
  atualizarTempo()
end

function show(fromServer)
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if not fromServer then send('REQ') end
  refresh()
  if not relogio then relogio = cycleEvent(atualizarTempo, 1000) end
end

function hide()
  if window then window:hide() end
  if relogio then removeEvent(relogio) relogio = nil end
end

function toggle()
  if not me then return end
  if window:isVisible() then hide() else show() end
end

-- ---------------- acoes ----------------
function salvarLink()
  local t = w('link'):getText():gsub('[|;~]', '')
  if t == '' then return falha('Cole o link da sua live.') end
  send('LINK|' .. t)
end

function toggleLive()
  if not me then return end
  if me.live then
    send('LIVEOFF')
  else
    local t = w('link'):getText():gsub('[|;~]', '')
    if t == '' then
      falha('Coloque o link da sua live primeiro.')
      w('link'):focus()
      return
    end
    send('LIVEON|' .. t)
  end
end

function botaoSorteio()
  if not me then return end
  if me.raffle then
    send('RDRAW')
  else
    local p = me.prizes[premioIdx]
    if p then send('ROPEN|' .. p.key) end
  end
end

function cancelarSorteio() send('RCANCEL') end
function chamariz() send('LURE') end
function abrirTv() send('TV') end

function viajar()
  if cidadeSel then send('TRAVEL|' .. cidadeSel) end
end

-- ---------------- janelas extras ----------------
local function abrirExtra(titulo, subtitulo, rodape, botaoTexto, botaoAcao)
  extra:setText(titulo)
  extra:getChildById('subtitulo'):setText(subtitulo or '')
  extra:getChildById('rodape'):setText(rodape or '')
  local b = extra:getChildById('botaoExtra')
  b:setText(botaoTexto or 'Fechar')
  b.onClick = botaoAcao or function() extra:hide() end
  extra:getChildById('lista'):destroyChildren()
  extra:show()
  extra:raise()
  extra:focus()
  return extra:getChildById('lista')
end

local function linha(lista, texto, eu, cor)
  local l = g_ui.createWidget('CSLinha', lista)
  l:setText(texto)
  if eu then l:setImageSource('/game_codexstreamer/images/st_linha_eu') l:setColor('#ffe27a') end
  if cor then l:setColor(cor) end
  return l
end

function abrirRanking()
  abrirExtra('Ranking de Streamers', 'Carregando...')
  send('RANK')
end

function abrirHistorico()
  abrirExtra('Historico de Lives', 'Carregando...')
  send('HIST')
end

function abrirRegras()
  local lista = abrirExtra('Regras e Informacoes', 'Como funciona o Streamer Codex')
  local regras = {
    'A live deve ser do Poketibia Codex.',
    'Entre ao vivo pelo painel: o tempo e contado pelo servidor.',
    'Quem esta perto de voce ganha +' .. (me and me.aexp or 10) .. '% EXP e +' .. (me and me.acatch or 10) .. '% captura.',
    '1 sorteio a cada ' .. (me and me.every or 30) .. ' min ao vivo. O chat entra com !participar.',
    'Ganhador: 1 vez por dia do mesmo streamer, 1 inscricao por conta.',
    'Parado mais de 10 min: o tempo para de contar.',
    'O ranking do mes conta so as horas ao vivo valendo.',
    'Chamariz e viagem gratis: so ao vivo, com recarga.',
    'Jogadores novos podem usar !indicacao SeuNome.',
  }
  for _, r in ipairs(regras) do linha(lista, r) end
end

local function mostrarRanking(f)
  local lista = abrirExtra('Ranking de Streamers', 'Mes atual - so horas ao vivo valendo (desempate: indicacoes)')
  local minha = tonumber(f[2]) or 0
  local rows = split(f[4] or '', ';')
  local n = 0
  for i, row in ipairs(rows) do
    local c = split(row, '~')
    if c[1] and c[1] ~= '' then
      n = n + 1
      local medalha = ({'[1o] ', '[2o] ', '[3o] '})[i] or (i .. '. ')
      linha(lista, medalha .. c[1] .. '  -  ' .. hm(c[2]) .. '   (' .. (c[3] or 0) .. ' indicacoes)', i == minha,
        i == 1 and '#ffd84a' or (i == 2 and '#d8e2ee' or (i == 3 and '#e0a060' or nil)))
    end
  end
  if n == 0 then linha(lista, 'Ninguem fez live valendo neste mes ainda.') end
  local prev = split(f[11] or '', ';')
  if prev[1] and prev[1] ~= '' then
    linha(lista, 'Vencedores do mes passado:', false, '#8fa7c4')
    for _, row in ipairs(prev) do
      local c = split(row, '~')
      if c[2] then linha(lista, c[1] .. 'o  ' .. c[2] .. '  -  ' .. hm(c[3])) end
    end
  end
  extra:getChildById('rodape'):setText('Premios: 1o ' .. (f[5] or '') .. '.  2o ' .. (f[6] or '') .. '.  3o ' .. (f[7] or '') ..
    '.  Quem passar de ' .. (f[9] or 10) .. 'h: ' .. (f[8] or '') .. '.' ..
    (minha > 0 and ('  Voce: ' .. minha .. 'o lugar (' .. hm(f[3]) .. ').') or ''))
end

local function mostrarHistorico(f)
  local lista = abrirExtra('Historico de Lives', 'Suas ultimas lives')
  local n = 0
  for _, row in ipairs(split(f[2] or '', ';')) do
    local c = split(row, '~')
    if c[1] and c[1] ~= '' then
      n = n + 1
      local data = os.date('%d/%m %H:%M', tonumber(c[1]) or 0)
      local l = linha(lista, data .. '  -  ' .. hm(c[2]) .. ' (valendo ' .. hm(c[3]) .. ')  -  ' .. c[4] .. ' sorteios, ' .. c[5] ..
        ' chamariz, ' .. c[6] .. ' na aura')
      l:setTooltip('Capturas raras: ' .. (c[7] or 0) .. '  |  Viagens: ' .. (c[8] or 0))
    end
  end
  if n == 0 then linha(lista, 'Nenhuma live ainda.') end
end

local function mostrarResumo(texto)
  local lista = abrirExtra('Live encerrada!', 'Resumo da transmissao', 'Copie e poste nas suas redes!', 'Copiar resumo', function()
    pcall(function() g_window.setClipboardText(texto) end)
    if modules.game_textmessage then modules.game_textmessage.displayStatusMessage('Resumo copiado!') end
  end)
  for i, l in ipairs(split(texto, '\n')) do
    if i > 1 and l ~= '' then linha(lista, l) end
  end
end

-- ---------------- avisos para todos ----------------
local function silenciado()
  return (tonumber(g_settings.getString(CHAVE_SILENCIO)) or 0) > os.time()
end

local function arrumarAvisos()
  local root = g_ui.getRootWidget()
  local y = celular() and 64 or 40
  for _, a in ipairs(avisos) do
    if not a:isDestroyed() then
      a:setPosition({x = math.floor((root:getWidth() - a:getWidth()) / 2), y = y})
      y = y + a:getHeight() + 6
    end
  end
end

local function fecharAviso(a)
  for i, x in ipairs(avisos) do if x == a then table.remove(avisos, i) break end end
  if not a:isDestroyed() then a:destroy() end
  arrumarAvisos()
end

local function aviso(titulo, texto, botoes, ponto)
  if silenciado() then return end
  while #avisos >= 3 do fecharAviso(avisos[1]) end
  local a = g_ui.createWidget('CSAviso', g_ui.getRootWidget())
  a:getChildById('titulo'):setText(titulo)
  a:getChildById('texto'):setText(texto)
  if ponto then a:getChildById('ponto'):setImageSource('/game_codexstreamer/images/' .. ponto) end
  a:getChildById('fechar').onClick = function() fecharAviso(a) end
  local box = a:getChildById('botoes')
  for _, b in ipairs(botoes) do
    local bt = g_ui.createWidget(b.estilo or 'CSBotaoAzul', box)
    bt:setText(b.texto)
    bt:setHeight(28)
    bt:setWidth(b.largura or 110)
    bt.onClick = function() b.acao() fecharAviso(a) end
  end
  local silenciar = g_ui.createWidget('CSBotaoAzul', box)
  silenciar:setText('Silenciar 1h')
  silenciar:setHeight(28)
  silenciar:setWidth(88)
  silenciar.onClick = function()
    g_settings.set(CHAVE_SILENCIO, tostring(os.time() + 3600))
    fecharAviso(a)
  end
  avisos[#avisos + 1] = a
  a:raise()
  arrumarAvisos()
  scheduleEvent(function() fecharAviso(a) end, AVISO_SEGUNDOS * 1000)
end

local function avisoLive(nome, plat, link)
  aviso(nome .. ' esta AO VIVO!', (PLATAFORMAS[plat] or 'Live') .. '  -  quem fica perto ganha +EXP e +captura', {
    {texto = 'Abrir live', estilo = 'CSBotao', acao = function() if link ~= '' then g_platform.openUrl(link) end end},
    {texto = 'Ir ate la', acao = function() send('LOCATE|' .. nome) end},
    {texto = 'Ver na TV', largura = 90, acao = function() send('WATCH|' .. nome) end},
  }, 'st_dot_live')
end

-- ---------------- topo ----------------
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
local function lerMe(f)
  local prizes = {}
  for _, e in ipairs(split(f[17] or '', ';')) do
    local c = split(e, '~')
    if c[1] and c[1] ~= '' then
      prizes[#prizes + 1] = {key = c[1], cid = tonumber(c[2]) or 0, count = tonumber(c[3]) or 1, label = c[4] or c[1], desc = c[5] or '', cat = c[6] or ''}
    end
  end
  local towns = {}
  for _, e in ipairs(split(f[18] or '', ';')) do
    local c = split(e, '~')
    if c[1] and c[1] ~= '' then towns[#towns + 1] = {id = tonumber(c[1]) or 0, name = c[2] or ''} end
  end
  local emotes = {}
  for _, e in ipairs(split(f[19] or '', ';')) do if e ~= '' then emotes[#emotes + 1] = e end end
  local raffle = nil
  local rc = split(f[16] or '', '~')
  if rc[1] and rc[1] ~= '' then raffle = {key = rc[1], count = tonumber(rc[2]) or 0} end
  me = {live = f[3] == '1', link = f[4] or '', platform = f[5] or 'link', liveSecs = tonumber(f[6]) or 0, valid = tonumber(f[7]) or 0,
    draws = tonumber(f[8]) or 0, nextDraw = tonumber(f[9]) or 0, lure = tonumber(f[10]) or 0, refs = tonumber(f[11]) or 0,
    points = tonumber(f[12]) or 0, aura = tonumber(f[13]) or 0, rank = tonumber(f[14]) or 0, lastLure = f[15] or '',
    raffle = raffle, prizes = prizes, towns = towns, emotes = emotes, aexp = tonumber(f[20]) or 10, acatch = tonumber(f[21]) or 10,
    every = tonumber(f[22]) or 30, ativo = f[23] ~= '0', minLevel = tonumber(f[24]) or 5}
  recebidoEm = g_clock.millis()
end

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
    lerMe(f)
    setButton(true)
    refresh()
  elseif f[1] == 'OPEN' then
    if me and (f[2] or '') ~= '' then me.link = f[2] end
    show(true)
    if window then w('link'):focus() end
  elseif f[1] == 'POP' then
    if f[2] == 'LIVE' then
      avisoLive(f[3] or '', f[4] or 'link', f[5] or '')
    elseif f[2] == 'RAFFLE' then
      local nome = f[3] or ''
      aviso('Sorteio na live de ' .. nome .. '!', 'Premio: ' .. (f[4] or '') .. '  -  entre com !participar', {
        {texto = 'Participar', estilo = 'CSBotao', acao = function() send('JOIN|' .. nome) end},
      }, 'st_dot_live')
    end
  elseif f[1] == 'LIVES' then
    local l = split(f[2] or '', ';')
    if l[1] and l[1] ~= '' then
      local c = split(l[1], '~')
      if #l == 1 then avisoLive(c[1] or '', c[2] or 'link', c[3] or '')
      else
        aviso(#l .. ' streamers ao vivo agora!', 'Use !lives para ver a lista', {
          {texto = 'Ir ate ' .. (c[1] or ''), largura = 150, acao = function() send('LOCATE|' .. (c[1] or '')) end},
        }, 'st_dot_live')
      end
    end
  elseif f[1] == 'RANK' then
    mostrarRanking(f)
  elseif f[1] == 'HIST' then
    mostrarHistorico(f)
  elseif f[1] == 'SUMMARY' then
    mostrarResumo(table.concat(f, '|', 2))
  elseif f[1] == 'WINNER' then
    aviso('Ganhador: ' .. (f[2] or ''), (f[3] or '') .. '  -  ' .. (f[4] or 0) .. ' participantes', {}, 'st_dot_live')
  end
end

local function onGameEnd()
  hide()
  if extra then extra:hide() end
  for _, a in ipairs(avisos) do if not a:isDestroyed() then a:destroy() end end
  avisos = {}
  streamers, me = {}, nil
  emotesFeitos = ''
  setButton(false)
end

function init()
  g_ui.importStyle('cs_estilos')
  window = g_ui.displayUI('codexstreamer')
  window:hide()
  extra = g_ui.displayUI('cs_extra')
  extra:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  g_keyboard.bindKeyDown(HOTKEY, toggle)
  connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
  disconnect(g_game, {onGameEnd = onGameEnd})
  g_keyboard.unbindKeyDown(HOTKEY)
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  if relogio then removeEvent(relogio) relogio = nil end
  for _, a in ipairs(avisos) do if not a:isDestroyed() then a:destroy() end end
  avisos = {}
  if button then button:destroy() button = nil end
  if window then window:destroy() window = nil end
  if extra then extra:destroy() extra = nil end
end
