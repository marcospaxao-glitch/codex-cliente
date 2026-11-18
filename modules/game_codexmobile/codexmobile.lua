-- Codex: joystick na tela para jogar pelo navegador do celular.
-- So liga quando o cliente roda no navegador de um celular/tablet (codexCelular()).
local overlay
local keypad
local evento
local segurando = false

local function ehCelular()
  return type(codexCelular) == 'function' and codexCelular()
end

local function centralizar()
  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
end

-- joystick calibrado: direcao pelo angulo a partir do centro da base.
-- zona morta no meio; 8 fatias, com as diagonais um pouco mais estreitas
-- (fica mais facil andar reto).
local ZONA_MORTA = 12      -- px a partir do centro: nao anda
local RAIO = 52            -- quanto a bolinha anda
local MEIA_DIAGONAL = 18   -- graus para cada lado de 45 que contam como diagonal
local dx, dy = 0, 0

local function centroBase()
  return keypad:getX() + keypad:getWidth() / 2, keypad:getY() + keypad:getHeight() / 2
end

local function atualizarPos(widget, pos)
  local cx, cy = centroBase()
  dx, dy = pos.x - cx, pos.y - cy
end

local function direcao()
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < ZONA_MORTA then return nil end
  -- 0 = leste, 90 = sul (y cresce para baixo)
  local ang = math.deg(math.atan2(dy, dx))
  if ang < 0 then ang = ang + 360 end
  local function perto(alvo) return math.abs(((ang - alvo + 180) % 360) - 180) <= MEIA_DIAGONAL end
  if perto(45) then return Directions.SouthEast end
  if perto(135) then return Directions.SouthWest end
  if perto(225) then return Directions.NorthWest end
  if perto(315) then return Directions.NorthEast end
  if ang >= 315 or ang < 45 then return Directions.East end
  if ang < 135 then return Directions.South end
  if ang < 225 then return Directions.West end
  return Directions.North
end

local function moverBolinha()
  local dist = math.sqrt(dx * dx + dy * dy)
  local f = dist > RAIO and RAIO / dist or 1
  keypad.pointer:setMarginLeft(math.floor(dx * f))
  keypad.pointer:setMarginTop(math.floor(dy * f))
end

local ultimaDir
local function passo()
  removeEvent(evento)
  evento = nil
  if not segurando or not g_game.isOnline() then
    centralizar()
    return
  end
  evento = scheduleEvent(passo, 50)
  moverBolinha()
  local dir = direcao()
  if not dir then ultimaDir = nil return end
  local player = g_game.getLocalPlayer()
  -- trocou de direcao: vira na hora; mesma direcao: so pede o proximo passo
  if dir ~= ultimaDir or not (player and player:isWalking()) then
    g_game.walk(dir)
  end
  ultimaDir = dir
end

local function soltar()
  segurando = false
  ultimaDir = nil
  dx, dy = 0, 0
  removeEvent(evento)
  evento = nil
  centralizar()
end

-- chamado pelo cliente (C++) com o dedo do joystick, separado dos outros dedos.
-- tipo 0 = encostou, 1 = moveu, 2 = soltou
local function joystickToque(tipo, x, y)
  if not keypad or not keypad:isVisible() or not g_game.isOnline() then
    if tipo ~= 0 then soltar() end
    return false
  end
  local pos = { x = x, y = y }
  if tipo == 0 then
    -- area de toque um pouco maior que o desenho da base
    local cx, cy = centroBase()
    local alcance = math.max(keypad:getWidth(), keypad:getHeight()) / 2 + 4 -- quase so o circulo (nao pega os botoes do lado)
    if math.abs(x - cx) > alcance or math.abs(y - cy) > alcance then return false end
    -- so se o joystick for o que esta por cima nesse ponto (menu ou janela aberta
    -- por cima do joystick: o toque e deles)
    local ok, topo = pcall(function() return g_ui.getRootWidget():recursiveGetChildByPos(pos, false) end)
    if ok and topo and topo ~= keypad and topo ~= keypad.pointer then
      local dentro = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) <= keypad:getWidth() / 2
      local w, deJoystick = topo, false
      while w do
        if w == keypad then deJoystick = true break end
        w = w:getParent()
      end
      -- fora do circulo, ou outro widget por cima: nao e do joystick
      if not deJoystick and (not dentro or not topo:isPhantom()) then return false end
    end
    atualizarPos(keypad, pos)
    segurando = true
    passo()
    return true
  elseif tipo == 1 then
    atualizarPos(keypad, pos)
    return true
  end
  soltar()
  return true
end

-- mouse (cliente antigo do navegador sem o toque direto)
local function onPress(widget, pos, button)
  if button ~= MouseLeftButton then return false end
  atualizarPos(widget, pos)
  segurando = true
  passo()
  return true
end

local function onMove(widget, pos, offset)
  if segurando then atualizarPos(widget, pos) end
  return true
end

local function onRelease(widget, pos, button)
  if button ~= MouseLeftButton then return false end
  soltar()
  return true
end

-- ============================================================
-- botoes de acao (lado direito)
-- ============================================================
local acoes
local eventoPosicao

local function distancia(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function tipoDe(c)
  local t = -1
  pcall(function() t = c:getType() end)
  return t
end

local function monstrosPerto()
  local player = g_game.getLocalPlayer()
  if not player then return {} end
  local pos = player:getPosition()
  local ok, lista = pcall(function() return g_map.getSpectators(pos, false) end)
  local res = {}
  if not ok or not lista then return res end
  for _, c in ipairs(lista) do
    local cp = c:getPosition()
    -- 3 = meu pokemon, 4 = pokemon de outro jogador
    if c:isMonster() and tipoDe(c) ~= 3 and tipoDe(c) ~= 4 and cp and cp.z == pos.z and distancia(cp, pos) <= 7
        and c:getHealthPercent() > 0 then
      res[#res + 1] = { c = c, d = distancia(cp, pos) }
    end
  end
  table.sort(res, function(a, b)
    if a.d ~= b.d then return a.d < b.d end
    return a.c:getId() < b.c:getId()
  end)
  return res
end

local function atacarProximo()
  if not g_game.isOnline() then return end
  local lista = monstrosPerto()
  if #lista == 0 then
    modules.game_textmessage.displayFailureMessage('Nenhum alvo por perto.')
    return
  end
  local atual = g_game.getAttackingCreature()
  local escolha = lista[1].c
  if atual then
    for i, item in ipairs(lista) do
      if item.c:getId() == atual:getId() then
        escolha = (lista[i + 1] or lista[1]).c
        break
      end
    end
  end
  g_game.attack(escolha)
end

local FRENTE = {
  [Directions.North] = { 0, -1 }, [Directions.South] = { 0, 1 },
  [Directions.East] = { 1, 0 }, [Directions.West] = { -1, 0 },
  [Directions.NorthEast] = { 1, -1 }, [Directions.NorthWest] = { -1, -1 },
  [Directions.SouthEast] = { 1, 1 }, [Directions.SouthWest] = { -1, 1 },
}

local function usarFrente()
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()

  -- NPC perto: cumprimenta
  local ok, lista = pcall(function() return g_map.getSpectators(pos, false) end)
  if ok and lista then
    for _, c in ipairs(lista) do
      local cp = c:getPosition()
      if c:isNpc() and cp and cp.z == pos.z and distancia(cp, pos) <= 3 then
        g_game.talk('hi')
        return
      end
    end
  end

  -- senao usa o que estiver na frente
  local off = FRENTE[player:getDirection()] or { 0, 1 }
  local tile = g_map.getTile({ x = pos.x + off[1], y = pos.y + off[2], z = pos.z })
  local coisa = tile and tile:getTopUseThing()
  if coisa then
    g_game.use(coisa)
  else
    modules.game_textmessage.displayFailureMessage('Nada para usar na frente.')
  end
end

local function pokemon()
  local pb = modules.game_pokemonbar
  if pb and pb.codexAlternarPokemon then
    pb.codexAlternarPokemon()
  elseif g_game.isOnline() then
    g_game.talk('!p 1')
  end
end

-- ============================================================
-- USAR: liga o "modo usar"; o proximo toque no mapa (ou num item da mochila)
-- usa a coisa tocada (escada, alavanca, bau de quest, porta, item...), como o
-- clique de usar do PC. Se ja tiver algo usavel do lado, usa direto.
-- ============================================================
local modoUsar = false
local processarOriginal

local function marcarUsar(ligado)
  modoUsar = ligado
  local b = acoes and acoes:getChildById('usar')
  if b then b:setImageSource('/game_codexmobile/images/' .. (ligado and 'usar_ativo' or 'usar')) end
end

local function usarCoisa(coisa)
  local gi = modules.game_interface
  if coisa:isContainer() then
    if coisa:getParentContainer() then g_game.open(coisa, coisa:getParentContainer()) else g_game.open(coisa) end
  elseif coisa:isMultiUse() and gi and gi.startUseWith then
    gi.startUseWith(coisa) -- corda, pa, item de usar em algo: toque no alvo depois
  else
    g_game.use(coisa)
  end
end

-- algo claramente usavel colado no jogador (escada de mao, alavanca, bau)?
local function usavelDoLado()
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  local pos = player:getPosition()
  local off = FRENTE[player:getDirection()] or { 0, 1 }
  local ordem = { { off[1], off[2] }, { 0, 0 } }
  for dx = -1, 1 do
    for dy = -1, 1 do
      if not (dx == off[1] and dy == off[2]) and not (dx == 0 and dy == 0) then ordem[#ordem + 1] = { dx, dy } end
    end
  end
  for _, d in ipairs(ordem) do
    local tile = g_map.getTile({ x = pos.x + d[1], y = pos.y + d[2], z = pos.z })
    local coisa = tile and tile:getTopUseThing()
    if coisa and coisa:isItem() and not coisa:isGround() and (coisa:isUsable() or coisa:isContainer()) then
      return coisa
    end
  end
  return nil
end

local function botaoUsar()
  if not g_game.isOnline() then return end
  if modoUsar then marcarUsar(false) return end
  local coisa = usavelDoLado()
  if coisa then
    usarCoisa(coisa)
    return
  end
  marcarUsar(true)
  modules.game_textmessage.displayStatusMessage('Toque no que voce quer usar (escada, alavanca, bau, item...).')
end

local function processarComUsar(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
  if modoUsar and mouseButton == MouseLeftButton then
    marcarUsar(false)
    if useThing then
      usarCoisa(useThing)
      return true
    end
    if creatureThing and creatureThing:isNpc() then
      g_game.talk('hi')
      return true
    end
  end
  return processarOriginal(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
end

local function ligarUsar()
  local gi = modules.game_interface
  if gi and gi.processMouseAction and gi.processMouseAction ~= processarComUsar then
    processarOriginal = gi.processMouseAction
    gi.processMouseAction = processarComUsar
  end
end

local function desligarUsar()
  local gi = modules.game_interface
  if gi and processarOriginal and gi.processMouseAction == processarComUsar then
    gi.processMouseAction = processarOriginal
  end
  processarOriginal = nil
end

-- ATACAR: ataca o mais perto (se ja tem alvo vivo, continua nele)
local function atacar()
  if not g_game.isOnline() then return end
  local atual = g_game.getAttackingCreature()
  if atual and atual:getHealthPercent() > 0 then return end
  local lista = monstrosPerto()
  if #lista == 0 then
    modules.game_textmessage.displayFailureMessage('Nenhum alvo por perto.')
    return
  end
  g_game.attack(lista[1].c)
end

local function montaria()
  local player = g_game.getLocalPlayer()
  if not player or not g_game.isOnline() then return end
  if player.toggleMount then
    player:toggleMount()
  else
    g_game.mount(not player:isMounted())
  end
end

-- ============================================================
-- posicao dos botoes de ataque (arrastando a alca); nil = lugar padrao
-- ============================================================
local CHAVE_POS = 'codexMobileAcoesV3' -- V3: longe do canto (tela arredondada)
local CHAVE_TRAVA = 'codexMobileTravado'
local travado = false

local function posSalva()
  local p = g_settings.getNode(CHAVE_POS)
  if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) then
    return { x = tonumber(p.x), y = tonumber(p.y) }
  end
  return nil
end

local function aplicarPos(x, y)
  local root = g_ui.getRootWidget()
  x = math.max(10, math.min(x, root:getWidth() - acoes:getWidth() - 10))
  y = math.max(10, math.min(y, root:getHeight() - acoes:getHeight() - 8))
  acoes:setMarginLeft(x)
  acoes:setMarginTop(y)
end

-- padrao: canto de baixo, na direita
local function posicionar()
  removeEvent(eventoPosicao)
  eventoPosicao = nil
  if not acoes then return end
  local salva = posSalva()
  if salva then
    aplicarPos(salva.x, salva.y)
    return
  end
  local root = g_ui.getRootWidget()
  acoes:setMarginLeft(math.max(0, root:getWidth() - acoes:getWidth() - 24))
  acoes:setMarginTop(math.max(0, root:getHeight() - acoes:getHeight() - 14))
end

local function posicionarDepois()
  removeEvent(eventoPosicao)
  eventoPosicao = scheduleEvent(posicionar, 100)
end

-- ============================================================
-- HUD: barra do topo, cartao, minimapa, loot, chat, gaveta
-- ============================================================
local topo, cartao, miniMapa, botaoLoot, botaoMontaria
local gavetaAberta = false
local hudEscondido = false
local chatGrande = false
local ALTURA_CHAT, ALTURA_CHAT_GRANDE = 150, 290
local TOPO_ALTURA = 56

local function passo(nome, fn)
  local ok, err = pcall(fn)
  if not ok then g_logger.warning('[codex celular] ' .. nome .. ': ' .. tostring(err)) end
end

local function atualizarCartao()
  local player = g_game.getLocalPlayer()
  if not cartao or not player then return end
  cartao:getChildById('nome'):setText(player:getName())
  cartao:getChildById('nivel'):setText('Lv ' .. player:getLevel())
  local vida, maxVida = player:getHealth(), math.max(1, player:getMaxHealth())
  local fundo = cartao:getChildById('vidaFundo')
  fundo:getChildById('vida'):setWidth(math.max(16, math.floor(fundo:getWidth() * vida / maxVida)))
  fundo:getChildById('vida'):setVisible(vida > 0)
  fundo:getChildById('vidaTexto'):setText(vida .. ' / ' .. maxVida)
  local xpFundo = cartao:getChildById('xpFundo')
  local pct = 0
  pcall(function() pct = player:getLevelPercent() end)
  xpFundo:getChildById('xp'):setWidth(math.max(16, math.floor(xpFundo:getWidth() * pct / 100)))
  xpFundo:getChildById('xp'):setVisible(pct > 0)
  xpFundo:getChildById('xpTexto'):setText('XP ' .. pct .. '%')
  pcall(function() cartao:getChildById('retrato'):setOutfit(player:getOutfit()) end)
end

local function atualizarMapa()
  local player = g_game.getLocalPlayer()
  if not miniMapa or not player then return end
  local pos = player:getPosition()
  if not pos then return end
  pcall(function()
    local mapa = miniMapa:getChildById('mapa')
    mapa:setCameraPosition(pos)
    mapa:setCrossPosition(pos)
  end)
  miniMapa:getChildById('coords'):setText(pos.x .. ', ' .. pos.y .. ', ' .. pos.z)
end

-- gaveta = coluna da direita do PC (batalha, mochila, janelas), por cima do
-- mapa, abaixo da barra do topo. Abre/fecha pela BOLSA.
-- gaveta aberta: as janelas (mochila, batalha...) dividem a altura toda, porque a
-- borda de puxar para aumentar e pequena demais para o dedo
local ultimaQtdGaveta = -1
local function encherGaveta(forcar)
  local gi = modules.game_interface
  local direita = gi and gi.getRightPanel and gi.getRightPanel()
  if not direita or not direita:isVisible() then ultimaQtdGaveta = -1 return end
  local janelas = {}
  for _, w in ipairs(direita:getChildren()) do
    local ok, classe = pcall(function() return w:getClassName() end)
    local minimizada = false
    pcall(function() minimizada = w:isOn() end) -- miniwindow minimizada fica "on"
    if w:isVisible() and ok and classe == 'UIMiniWindow' and not minimizada then janelas[#janelas + 1] = w end
  end
  if #janelas == 0 or (#janelas == ultimaQtdGaveta and not forcar) then return end
  ultimaQtdGaveta = #janelas
  local cada = math.floor((direita:getHeight() - 8) / #janelas) - 2
  for _, w in ipairs(janelas) do pcall(function() w:setHeight(math.max(90, cada)) end) end
end

local function abrirGaveta(abrir)
  local gi = modules.game_interface
  local direita = gi and gi.getRightPanel and gi.getRightPanel()
  if not direita then return end
  gavetaAberta = abrir
  direita:setMarginTop(TOPO_ALTURA + 4)
  direita:setVisible(abrir)
  if abrir then
    direita:raise()
    scheduleEvent(function() encherGaveta(true) end, 200)
  end
  -- o que fica embaixo da gaveta sai da frente
  for _, w in ipairs({ miniMapa, botaoLoot, acoes }) do
    if w then w:setVisible(not abrir and not hudEscondido) end
  end
  if topo then topo:raise() end
end

-- sem a barra do topo do PC no celular: a interface do jogo vai ate o topo
local function esconderTopo()
  local tm = modules.client_topmenu and modules.client_topmenu.getTopMenu and modules.client_topmenu.getTopMenu()
  if not tm then return end
  if tm:isVisible() then tm:hide() end
  local gi = modules.game_interface
  local raiz = gi and gi.getRootPanel and gi.getRootPanel()
  if raiz then
    raiz:breakAnchors()
    raiz:fill('parent')
  end
  local btn = gi and gi.getShowTopMenuButton and gi.getShowTopMenuButton()
  if btn then btn:hide() end
end

-- ----- teclado do chat: so abre pelo botao -----
local tecladoAberto = false

local function campoDoChat()
  local con = modules.game_console
  local painel = con and con.consolePanel
  return painel and painel:getChildById('consoleTextEdit'), painel
end

local function marcarTeclado(aberto)
  tecladoAberto = aberto
  local _, painel = campoDoChat()
  local b = painel and painel:getChildById('codexChatTeclado')
  if b then b:setImageSource('/game_codexmobile/images/' .. (aberto and 'chat_teclado_on' or 'chat_teclado')) end
end

function alternarTeclado()
  if type(codexTeclado) ~= 'function' then return end
  local campo = campoDoChat()
  if tecladoAberto then
    pcall(codexTeclado, false, 0)
    marcarTeclado(false)
    return
  end
  if campo then
    pcall(function() campo:focus() end)
    pcall(codexTeclado, true, campo:getY() + campo:getHeight())
  end
  marcarTeclado(true)
end

-- ----- chat no estilo do celular -----
local function enviarMensagem()
  local con = modules.game_console
  if con and con.sendCurrentMessage then con.sendCurrentMessage() end
end

local function tamanhoChat()
  local gi = modules.game_interface
  local fundo = gi and gi.getBottomPanel and gi.getBottomPanel()
  if not fundo then return end
  local root = g_ui.getRootWidget()
  -- entre o joystick (esquerda) e o ATACAR (direita)
  local largura = math.max(380, math.min(math.floor(root:getWidth() * 0.5), root:getWidth() - 2 * 250))
  fundo:setWidth(largura)
  fundo:setHeight(chatGrande and ALTURA_CHAT_GRANDE or ALTURA_CHAT)
  local abrir = fundo:recursiveGetChildById('codexChatAbrir')
  if abrir then
    local img = chatGrande and 'chat_fechar' or 'chat_abrir'
    abrir:setImageSource('/game_codexmobile/images/' .. img)
  end
end

-- ----- chat escondido: some a janela, ficam so as ultimas mensagens por cima do jogo -----
local CHAVE_CHAT_OCULTO = 'codexChatOculto'
local chatOculto = false
local addTabTextOriginal = nil

local function linhaFlutuante(texto, cor)
  local box = overlay and overlay:getChildById('chatFlutuante')
  if not box or not chatOculto then return end
  if #texto > 78 then texto = texto:sub(1, 76) .. '...' end
  local l = g_ui.createWidget('UILabel', box)
  l:setFont('verdana-11px-rounded')
  l:setText(texto)
  l:setColor(cor or '#ffffff')
  l:setHeight(18)
  l:setTextAlign(AlignLeft)
  l:setTextOffset({ x = 6, y = 0 })
  l:setBackgroundColor('#00000088')
  l:setPhantom(true)
  while box:getChildCount() > 4 do box:getFirstChild():destroy() end
  box:setHeight(box:getChildCount() * 18)
  scheduleEvent(function()
    if not l:isDestroyed() then l:destroy() end
    if not box:isDestroyed() then box:setHeight(math.max(1, box:getChildCount() * 18)) end
  end, 12000)
end

local function ligarChatFlutuante()
  local con = modules.game_console
  if addTabTextOriginal or not con or type(con.addTabText) ~= 'function' then return end
  addTabTextOriginal = con.addTabText
  con.addTabText = function(text, speaktype, tab, creatureName)
    local r = addTabTextOriginal(text, speaktype, tab, creatureName)
    if chatOculto and text and tab then
      local atual = con.consoleTabBar and con.consoleTabBar:getCurrentTab()
      if tab == atual then pcall(linhaFlutuante, text, speaktype and speaktype.color) end
    end
    return r
  end
end

local function desligarChatFlutuante()
  local con = modules.game_console
  if addTabTextOriginal and con then con.addTabText = addTabTextOriginal end
  addTabTextOriginal = nil
end

local function ocultarChat(oculto)
  chatOculto = oculto and true or false
  g_settings.set(CHAVE_CHAT_OCULTO, chatOculto)
  local gi = modules.game_interface
  local fundo = gi and gi.getBottomPanel and gi.getBottomPanel()
  if fundo then fundo:setVisible(not chatOculto) end
  if not overlay then return end
  local box = overlay:getChildById('chatFlutuante')
  if box then
    box:setVisible(chatOculto)
    if not chatOculto then box:destroyChildren() end
  end
  local b = overlay:getChildById('chatMostrar')
  if b then b:setVisible(chatOculto and not hudEscondido and g_game.isOnline()) end
  if chatOculto and tecladoAberto then alternarTeclado() end
end

local function arrumarChat()
  local gi = modules.game_interface
  local fundo = gi.getBottomPanel()
  if not fundo then return end
  fundo:breakAnchors()
  fundo:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  fundo:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  fundo:setMarginBottom(4)
  if gi.bottomSplitter then gi.bottomSplitter:hide() end
  fundo:setImageSource('/game_codexmobile/images/chat_moldura')
  fundo:setImageBorder(14)
  fundo:setBackgroundColor('#00000000')

  local con = modules.game_console
  local painel = con and con.consolePanel
  if painel and not painel.codexCelular then
    painel.codexCelular = true
    painel:setImageSource('')
    painel:setBackgroundColor('#00000000')
    for _, id in ipairs({ 'toggleChat', 'prevChannelButton', 'nextChannelButton', 'closeChannelButton',
                          'clearChannelButton', 'ignoreButton', 'sayModeButton', 'channelsButton' }) do
      local w = painel:getChildById(id)
      if w then w:hide() end
    end
    -- abrir/fechar o chat (seta), no canto de cima
    local abrir = g_ui.createWidget('CodexImgBotao', painel)
    abrir:setId('codexChatAbrir')
    abrir:setSize({ width = 52, height = 28 })
    abrir:addAnchor(AnchorTop, 'parent', AnchorTop)
    abrir:addAnchor(AnchorRight, 'parent', AnchorRight)
    abrir:setMarginTop(4)
    abrir:setMarginRight(10)
    abrir.onClick = function()
      chatGrande = not chatGrande
      tamanhoChat()
    end
    -- esconder o chat (olho), ao lado da seta
    local ocultar = g_ui.createWidget('CodexImgBotao', painel)
    ocultar:setId('codexChatOcultar')
    ocultar:setSize({ width = 40, height = 28 })
    ocultar:addAnchor(AnchorTop, 'parent', AnchorTop)
    ocultar:addAnchor(AnchorRight, 'codexChatAbrir', AnchorLeft)
    ocultar:setMarginTop(4)
    ocultar:setMarginRight(4)
    ocultar:setImageSource('/game_codexmobile/images/chat_ocultar')
    ocultar.onClick = function() ocultarChat(true) end
    local abas = painel:getChildById('consoleTabBar')
    if abas then
      -- no dedo, arrastar a aba (trocar de lugar) engolia o toque: a aba nao era
      -- escolhida e a mensagem ia para o Padrao. No celular as abas nao arrastam.
      abas.tabsMoveable = false
      for _, t in ipairs(abas.tabs or {}) do t:setDraggable(false) end
      for _, t in ipairs(abas.preTabs or {}) do t:setDraggable(false) end
      for _, t in ipairs(abas.postTabs or {}) do t:setDraggable(false) end
      abas:breakAnchors()
      abas:addAnchor(AnchorTop, 'parent', AnchorTop)
      abas:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      abas:addAnchor(AnchorRight, 'codexChatOcultar', AnchorLeft)
      abas:setMarginTop(4)
      abas:setMarginLeft(10)
      abas:setMarginRight(6)
    end
    -- escolher canal (pessoas), embaixo a esquerda
    local velho = painel:getChildById('channelsButton')
    if velho then velho:hide() end
    local canal = g_ui.createWidget('CodexImgBotao', painel)
    canal:setId('codexChatCanal')
    canal:setSize({ width = 44, height = 38 })
    canal:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    canal:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    canal:setMarginBottom(8)
    canal:setMarginLeft(10)
    canal:setImageSource('/game_codexmobile/images/chat_canal')
    canal.onClick = function() g_game.requestChannels() end
    -- enviar, embaixo a direita
    local enviar = g_ui.createWidget('CodexImgBotao', painel)
    enviar:setId('codexChatEnviar')
    enviar:setSize({ width = 48, height = 38 })
    enviar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    enviar:addAnchor(AnchorRight, 'parent', AnchorRight)
    enviar:setMarginBottom(8)
    enviar:setMarginRight(10)
    enviar:setImageSource('/game_codexmobile/images/chat_enviar')
    enviar.onClick = enviarMensagem
    -- liga/desliga o teclado (no jogo, tocar no campo nao abre mais o teclado sozinho)
    local teclado = g_ui.createWidget('CodexImgBotao', painel)
    teclado:setId('codexChatTeclado')
    teclado:setSize({ width = 44, height = 38 })
    teclado:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    teclado:addAnchor(AnchorRight, 'codexChatEnviar', AnchorLeft)
    teclado:setMarginBottom(8)
    teclado:setMarginRight(6)
    teclado:setImageSource('/game_codexmobile/images/chat_teclado')
    teclado.onClick = function() alternarTeclado() end
    -- campo de digitar entre os dois
    local campo = painel:getChildById('consoleTextEdit')
    if campo then
      campo:breakAnchors()
      campo:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      campo:addAnchor(AnchorLeft, 'codexChatCanal', AnchorRight)
      campo:addAnchor(AnchorRight, 'codexChatTeclado', AnchorLeft)
      campo:setMarginBottom(10)
      campo:setMarginLeft(6)
      campo:setMarginRight(6)
      campo:setHeight(34)
      campo:setImageSource('/game_codexmobile/images/chat_campo')
      campo:setImageBorder(8)
      campo:setTextOffset({ x = 6, y = 9 })
      campo:setColor('#ffffff')
      pcall(function() campo:setPlaceholder('Toque aqui para digitar...') end)
    end
    local conteudo = painel:getChildById('consoleContentPanel')
    if conteudo then
      conteudo:breakAnchors()
      conteudo:addAnchor(AnchorTop, 'consoleTabBar', AnchorBottom)
      conteudo:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      conteudo:addAnchor(AnchorRight, 'parent', AnchorRight)
      conteudo:addAnchor(AnchorBottom, 'consoleTextEdit', AnchorTop)
      conteudo:setMarginTop(4)
      conteudo:setMarginLeft(12)
      conteudo:setMarginRight(12)
      conteudo:setMarginBottom(6)
    end
  end
  tamanhoChat()
end

local function organizarTela()
  local gi = modules.game_interface
  if not gi then return end
  local root = g_ui.getRootWidget()
  passo('mapa em tela cheia', function() gi.setupViewMode(2) end)
  passo('barra do topo', esconderTopo)
  passo('paineis', function()
    local esquerda = gi.getLeftPanel()
    if esquerda then esquerda:setOn(false) end
  end)
  passo('gaveta', function() abrirGaveta(gavetaAberta) end)
  passo('chat', arrumarChat)
  -- equipe no alto, no meio; golpes logo acima do chat (uma vez por aparelho)
  passo('barra de pokemons', function()
    local pb = modules.game_pokemonbar
    if pb and pb.codexModoCelularV2 then pb.codexModoCelularV2(TOPO_ALTURA + 8) end
  end)
  passo('barra de golpes', function()
    local pm = modules.game_pokemonmoves
    if pm and pm.codexModoCelularV2 then pm.codexModoCelularV2(root:getHeight() - ALTURA_CHAT - 12) end
  end)
  passo('chat oculto', function() ocultarChat(chatOculto) end)
  if overlay then overlay:raise() end
end

local function mostrarHud(mostrar)
  for _, w in ipairs({ topo, cartao, miniMapa, botaoLoot, botaoMontaria, overlay:getChildById('npcHi'), overlay:getChildById('npcTrade'), overlay:getChildById('vooSubir'), overlay:getChildById('vooDescer') }) do
    if w then w:setVisible(mostrar) end
  end
end

local function aplicarTrava()
  if not acoes then return end
  acoes:getChildById('mover'):setVisible(not travado)
  local b = topo and topo:getChildById('btnTrava')
  if b then b:setImageSource('/game_codexmobile/images/' .. (travado and 'ic_trava' or 'ic_destrava')) end
end

local function atualizarSom()
  local b = topo and topo:getChildById('btnSom')
  local opt = modules.client_options
  local ligado = true
  pcall(function() ligado = opt.getOption('enableAudio') ~= false end)
  if b then b:setImageSource('/game_codexmobile/images/' .. (ligado and 'ic_som' or 'ic_mudo')) end
end

local publicarJoystick -- (definida mais abaixo; app Android)

-- ============================================================
-- menu do celular: grupos a esquerda, sistemas grandes a direita
-- ============================================================
local menuCelular
local grupoAtual = 1

local function fecharMenu()
  if menuCelular then menuCelular:hide() end
  if publicarJoystick then publicarJoystick() end
end

local function mostrarGrupo(i)
  local tm = modules.client_topmenu
  local grupos = tm and tm.codexGruposMenu and tm.codexGruposMenu() or {}
  if #grupos == 0 then return end
  grupoAtual = math.max(1, math.min(i, #grupos))
  local painelGrupos = menuCelular:getChildById('grupos')
  local painelItens = menuCelular:getChildById('itens')
  painelGrupos:destroyChildren()
  painelItens:destroyChildren()
  for gi, g in ipairs(grupos) do
    local aba = g_ui.createWidget('CodexAba', painelGrupos)
    aba:setText(g.nome)
    if g.icon then aba:setIcon(g.icon) end
    aba:setOn(gi == grupoAtual)
    aba.onClick = function() mostrarGrupo(gi) end
  end
  for _, it in ipairs(grupos[grupoAtual].itens) do
    local tile = g_ui.createWidget('CodexTile', painelItens)
    tile:setText(it.label)
    if it.icon then tile:setIcon(it.icon) end
    tile.onClick = function()
      fecharMenu()
      if it.run then it.run() end
    end
  end
  menuCelular:getChildById('titulo'):setText('MENU  -  ' .. grupos[grupoAtual].nome)
end

local function abrirMenu()
  if not menuCelular then return end
  if menuCelular:isVisible() then fecharMenu() return end
  if gavetaAberta then abrirGaveta(false) end
  mostrarGrupo(grupoAtual)
  menuCelular:show()
  if publicarJoystick then publicarJoystick() end
  menuCelular:raise()
  if topo then topo:raise() end
end

-- ============================================================
-- janelas grandes: cabem na tela (abaixo da barra do topo), o HUD sai da
-- frente e aparece o FECHAR no topo
-- ============================================================
local eventoJanelas
local janelaAberta

local function ehDoHud(w)
  local gi = modules.game_interface
  if w == overlay then return true end
  if gi then
    for _, f in ipairs({ 'getRootPanel', 'getMapPanel', 'getBottomPanel', 'getRightPanel', 'getLeftPanel' }) do
      local ok, x = pcall(function() return gi[f] and gi[f]() end)
      if ok and x == w then return true end
    end
  end
  local tm = modules.client_topmenu
  if tm and tm.getTopMenu and tm.getTopMenu() == w then return true end
  return false
end

local function acharJanelaGrande()
  local root = g_ui.getRootWidget()
  local W, H = root:getWidth(), root:getHeight()
  local achada
  local gi = modules.game_interface
  local listas = { root:getChildren() }
  local raiz = gi and gi.getRootPanel and gi.getRootPanel()
  if raiz then listas[#listas + 1] = raiz:getChildren() end
  for _, lista in ipairs(listas) do
    for _, w in ipairs(lista) do
      if w:isVisible() and not w:isPhantom() and not ehDoHud(w)
          and w:getWidth() > W * 0.4 and w:getHeight() > H * 0.4
          and w:getWidth() < W + 400 then
        achada = w
      end
    end
  end
  return achada
end

local function caberNaTela(w)
  local root = g_ui.getRootWidget()
  local W, H = root:getWidth(), root:getHeight()
  local topoY = 2 -- a barra do topo sai enquanto a janela esta aberta
  local largura, altura = w:getWidth(), w:getHeight()
  if altura > H - topoY - 4 then altura = H - topoY - 4 end
  if largura > W - 8 then largura = W - 8 end
  local x, y = w:getX(), w:getY()
  local fora = y < topoY or x < 0 or x + largura > W or y + altura > H
  if altura ~= w:getHeight() or largura ~= w:getWidth() or fora then
    w:breakAnchors()
    w:setSize({ width = largura, height = altura })
    w:setPosition({ x = math.floor((W - largura) / 2), y = topoY + math.floor((H - topoY - altura) / 2) })
  end
end

-- janela grande aberta: o HUD inteiro sai (a janela usa a tela toda) e fica so
-- um X redondo no canto, fora da janela. Reaplica a cada volta (algo pode ter
-- mostrado de novo).
local function esconderHud(esconder)
  local mudou = hudEscondido ~= esconder
  hudEscondido = esconder
  if not esconder and not mudou then return end
  for _, w in ipairs({ topo, cartao, keypad, botaoMontaria, overlay:getChildById('npcHi'), overlay:getChildById('npcTrade'), overlay:getChildById('vooSubir'), overlay:getChildById('vooDescer') }) do
    if w then w:setVisible(not esconder) end
  end
  for _, w in ipairs({ miniMapa, botaoLoot, acoes }) do
    if w then w:setVisible(not esconder and not gavetaAberta) end
  end
  local cm = overlay and overlay:getChildById('chatMostrar')
  if cm then cm:setVisible(chatOculto and not esconder) end
  local cf = overlay and overlay:getChildById('chatFlutuante')
  if cf then cf:setVisible(chatOculto and not esconder) end
  local x = overlay and overlay:getChildById('fecharJanela')
  if x then
    x:setVisible(esconder)
    if esconder then x:raise() end
  end
  -- a janela pode estar acima do HUD (ex.: Terminal): o X tem que ficar por cima dela
  if esconder and overlay then overlay:raise() end
end

local function fecharJanela()
  local w = janelaAberta
  if not w or w:isDestroyed() then return end
  local b = w:recursiveGetChildById('closeButton') or w:recursiveGetChildById('btnClose') or w:recursiveGetChildById('close')
      or w:recursiveGetChildById('closeBtn') or w:recursiveGetChildById('cancelButton')
  if b and b:isVisible() and b.onClick then
    b:onClick()
  elseif w.onEscape then
    w:onEscape()
  end
  if w:isVisible() then w:hide() end
end

-- app Android: o cliente testa a area do joystick sozinho (fora do Lua); avisa onde
-- ele esta e se pode receber o dedo agora (sem menu ou janela grande por cima)
publicarJoystick = function()
  if type(codexJoystickArea) ~= 'function' or not keypad then return end
  local ativo = g_game.isOnline() and keypad:isVisible() and not hudEscondido
    and not (menuCelular and menuCelular:isVisible())
  pcall(codexJoystickArea, keypad:getX(), keypad:getY(), keypad:getWidth(), keypad:getHeight(), ativo and true or false)
end

-- botoes - e + no topo da janela: diminui/aumenta uma linha (36 px) por toque
local LINHA_JANELA = 36
local function botoesTamanho(w, rb)
  if rb.minimum and rb.maximum and rb.minimum >= rb.maximum then return end
  local ancora = w:getChildById('minimizeButton')
  if not ancora or not ancora:isVisible() then ancora = w:getChildById('closeButton') end
  if not ancora then return end
  local function mudar(sinal)
    local root = g_ui.getRootWidget()
    local minimo = math.max(rb.minimum or 48, 48)
    local maximo = math.min(rb.maximum or 2000, root:getHeight() - w:getY() - 4)
    local h = math.max(minimo, math.min(maximo, w:getHeight() + sinal * LINHA_JANELA))
    if w:isOn() then pcall(function() w:maximize() end) end -- minimizada: abre antes
    w:setHeight(h)
  end
  local mais = g_ui.createWidget('CodexImgBotao', w)
  mais:setId('codexJanMais')
  mais:setSize({ width = 26, height = 20 })
  mais:addAnchor(AnchorTop, 'parent', AnchorTop)
  mais:addAnchor(AnchorRight, ancora:getId(), AnchorLeft)
  mais:setMarginTop(2)
  mais:setMarginRight(6)
  mais:setImageSource('/game_codexmobile/images/jan_mais')
  mais.onClick = function() mudar(1) end
  local menos = g_ui.createWidget('CodexImgBotao', w)
  menos:setId('codexJanMenos')
  menos:setSize({ width = 26, height = 20 })
  menos:addAnchor(AnchorTop, 'parent', AnchorTop)
  menos:addAnchor(AnchorRight, 'codexJanMais', AnchorLeft)
  menos:setMarginTop(2)
  menos:setMarginRight(3)
  menos:setImageSource('/game_codexmobile/images/jan_menos')
  menos.onClick = function() mudar(-1) end
end

-- janelas pequenas (mochila, bolsa de loot...): a borda de baixo, que puxa para
-- aumentar/diminuir, fica grossa e sempre visivel (3 px era impossivel de pegar no dedo)
local function ajustarJanelas()
  local gi = modules.game_interface
  local listas = {}
  for _, f in ipairs({ 'getRootPanel', 'getRightPanel' }) do
    local ok, p = pcall(function() return gi and gi[f] and gi[f]() end)
    if ok and p then listas[#listas + 1] = p:getChildren() end
  end
  for _, lista in ipairs(listas) do
    for _, w in ipairs(lista) do
      if not w.codexAjustada and w:getClassName() == 'UIMiniWindow' then
        w.codexAjustada = true
        local rb = w:getChildById('bottomResizeBorder')
        if rb then
          rb:setHeight(16)
          rb:setBackgroundColor('#f5c51855')
          rb:setOpacity(1)
          rb.onHoverChange = function() end
          pcall(botoesTamanho, w, rb)
        end
      end
    end
  end
end

-- arrastar janela solta: no PC, passar por cima das outras janelas abria espaco
-- entre elas (e a janela grudava). No celular, com a gaveta fechada, ela so anda.
local arrastarJanelaOriginal = nil
local function ligarArrasteLivre()
  if arrastarJanelaOriginal or not UIMiniWindow then return end
  arrastarJanelaOriginal = UIMiniWindow.onDragMove
  UIMiniWindow.onDragMove = function(self, mousePos, mouseMoved)
    if not gavetaAberta then return UIWindow.onDragMove(self, mousePos, mouseMoved) end
    return arrastarJanelaOriginal(self, mousePos, mouseMoved)
  end
end
local function desligarArrasteLivre()
  if arrastarJanelaOriginal then UIMiniWindow.onDragMove = arrastarJanelaOriginal end
  arrastarJanelaOriginal = nil
end

local function verJanelas()
  publicarJoystick()
  pcall(ajustarJanelas)
  if gavetaAberta then encherGaveta(false) end -- abriu/fechou uma janela na gaveta
  if not g_game.isOnline() or not topo then return end
  local w = acharJanelaGrande()
  if w and w ~= janelaAberta then
    g_logger.info('[codex celular] janela grande na tela: ' .. tostring(w:getId()))
  end
  janelaAberta = w
  if w then
    pcall(caberNaTela, w)
    esconderHud(true)
    if topo then topo:raise() end
  else
    esconderHud(false)
  end
end

local function botaoTeclado(mostrar)
  if type(codexBotaoTeclado) == 'function' then pcall(codexBotaoTeclado, mostrar) end
end

local function onGameStart()
  if not keypad then return end
  botaoTeclado(false) -- no jogo, tocar no campo do chat ja abre o teclado
  ligarUsar()
  marcarUsar(false)
  overlay:raise()
  keypad:show()
  acoes:show()
  local hb = modules.game_codexhotbar
  if hb and hb.setHidden then hb.setHidden(true) end
  mostrarHud(true)
  chatOculto = g_settings.getBoolean(CHAVE_CHAT_OCULTO)
  ligarChatFlutuante()
  aplicarTrava()
  atualizarSom()
  for _, atraso in ipairs({ 300, 1500, 4000, 8000 }) do
    scheduleEvent(function()
      if not g_game.isOnline() then return end
      organizarTela()
      atualizarCartao()
      atualizarMapa()
      posicionar()
    end, atraso)
  end
  posicionarDepois()
  removeEvent(eventoJanelas)
  eventoJanelas = cycleEvent(verJanelas, 400)
end

local function onGameEnd()
  botaoTeclado(true)
  tecladoAberto = false
  marcarUsar(false)
  segurando = false
  removeEvent(evento)
  evento = nil
  if keypad then keypad:hide() end
  if acoes then acoes:hide() end
  removeEvent(eventoJanelas)
  eventoJanelas = nil
  hudEscondido = false
  janelaAberta = nil
  if overlay then
    overlay:getChildById('fecharJanela'):hide()
    overlay:getChildById('chatMostrar'):hide()
    overlay:getChildById('chatFlutuante'):hide()
    overlay:getChildById('chatFlutuante'):destroyChildren()
  end
  if type(codexJoystickArea) == 'function' then pcall(codexJoystickArea, 0, 0, 0, 0, false) end
  fecharMenu()
  mostrarHud(false)
  gavetaAberta = false
end

local function onVida() atualizarCartao() end
local function onPosicao() atualizarMapa() end

local function ligarBotoes()
  -- topo, esquerda
  topo:getChildById('btnSair').onClick = function()
    local gi = modules.game_interface
    if gi and gi.tryLogout then gi.tryLogout() end
  end
  topo:getChildById('btnOpcoes').onClick = function()
    local opt = modules.client_options
    if opt and opt.toggle then opt.toggle() end
  end
  topo:getChildById('btnSom').onClick = function()
    local opt = modules.client_options
    if opt and opt.toggleOption then opt.toggleOption('enableAudio') end
    atualizarSom()
  end
  topo:getChildById('btnTrava').onClick = function()
    travado = not travado
    g_settings.set(CHAVE_TRAVA, travado)
    aplicarTrava()
    modules.game_textmessage.displayStatusMessage(travado and 'Botoes travados no lugar.' or 'Botoes liberados: arraste pela alca.')
  end
  -- topo, direita
  topo:getChildById('btnMochila').onClick = function()
    if gavetaAberta then
      abrirGaveta(false)
      return
    end
    abrirGaveta(true)
    -- abre a mochila se ainda nao tem nenhuma janela aberta na gaveta
    local gi = modules.game_interface
    local direita = gi and gi.getRightPanel and gi.getRightPanel()
    local temJanela = false
    if direita then
      for _, w in ipairs(direita:getChildren()) do
        if w:isVisible() and w:getHeight() > 30 then temJanela = true break end
      end
    end
    local player = g_game.getLocalPlayer()
    local mochila = player and player:getInventoryItem(InventorySlotBack)
    if mochila and mochila:isContainer() then
      local aberta = false
      for _, c in pairs(g_game.getContainers()) do
        local it = c:getContainerItem()
        if it and it:getId() == mochila:getId() then aberta = true break end
      end
      if not aberta then g_game.open(mochila) end
    elseif not temJanela then
      modules.game_textmessage.displayFailureMessage('Sem mochila equipada.')
    end
  end
  topo:getChildById('btnPokemon').onClick = function()
    local pk = modules.game_pokemons
    if pk and pk.toggle then pk.toggle() end
  end
  topo:getChildById('btnMenu').onClick = abrirMenu
  topo:getChildById('btnFechar').onClick = fecharJanela
  overlay:getChildById('fecharJanela').onClick = fecharJanela
  menuCelular:getChildById('fechar').onClick = fecharMenu
  -- minimapa
  local mapa = miniMapa:getChildById('mapa')
  pcall(function() mapa:hideFloor() end)
  miniMapa:getChildById('zoomMais').onClick = function() pcall(function() mapa:zoomIn() end) end
  miniMapa:getChildById('zoomMenos').onClick = function() pcall(function() mapa:zoomOut() end) end
  miniMapa:getChildById('centralizar').onClick = function() atualizarMapa() end
  miniMapa:getChildById('expandir').onClick = function()
    local mm = modules.game_minimap
    if mm and mm.toggleFullMap then mm.toggleFullMap() end
  end
  -- direita / esquerda
  botaoLoot.onClick = function()
    local lb = modules.game_lootbag
    if lb and lb.toggle then
      lb.toggle()
      if not gavetaAberta then abrirGaveta(true) end
    end
  end
  -- ORDER (mover o pokemon): igual ao botao do meio do mouse; depois toque no lugar/alvo
  botaoMontaria.onClick = function()
    if not g_game.isOnline() then return end
    local hi, gi = modules.game_healthinfo, modules.game_interface
    if hi and hi.toggleOrder then hi.toggleOrder()
    elseif gi and gi.toggleOrder then gi.toggleOrder() end
  end
  -- HI / TRADE vao para a aba escolhida no chat (ex.: a aba do NPC), igual a digitar
  local function falarNaAba(texto)
    if not g_game.isOnline() then return end
    local con = modules.game_console
    if con and con.sendMessage then con.sendMessage(texto) else g_game.talk(texto) end
  end
  -- voando: subir / descer de andar (o mesmo que PageUp / PageDown do PC)
  overlay:getChildById('vooSubir').onClick = function() if g_game.isOnline() then g_game.talk('!up') end end
  overlay:getChildById('vooDescer').onClick = function() if g_game.isOnline() then g_game.talk('!down') end end
  overlay:getChildById('npcHi').onClick = function() falarNaAba('hi') end
  overlay:getChildById('npcTrade').onClick = function() falarNaAba('trade') end
  acoes:getChildById('atacar').onClick = atacar
  acoes:getChildById('trocar').onClick = atacarProximo
  acoes:getChildById('usar').onClick = botaoUsar
end

function init()
  if not ehCelular() then return end
  overlay = g_ui.displayUI('codexmobile')
  keypad = overlay:getChildById('keypad')
  connect(keypad, { onMousePress = onPress, onMouseMove = onMove, onMouseRelease = onRelease })
  _G.codexJoystickToque = joystickToque -- o cliente manda o dedo do joystick direto aqui
  ligarArrasteLivre()
  overlay:getChildById('chatMostrar').onClick = function() ocultarChat(false) end
  acoes = overlay:getChildById('acoes')
  topo = overlay:getChildById('topo')
  cartao = overlay:getChildById('cartao')
  miniMapa = overlay:getChildById('miniMapa')
  botaoLoot = overlay:getChildById('loot')
  botaoMontaria = overlay:getChildById('montaria')
  menuCelular = overlay:getChildById('menuCelular')
  travado = g_settings.getBoolean(CHAVE_TRAVA)
  ligarBotoes()

  -- alca: arrasta trocar + ATACAR; segurar parado = voltar ao lugar padrao
  local mover = acoes:getChildById('mover')
  local ref = nil
  mover.onDragEnter = function(self, mousePos)
    if travado then return false end
    ref = { x = mousePos.x - acoes:getX(), y = mousePos.y - acoes:getY() }
    return true
  end
  mover.onDragMove = function(self, mousePos)
    if not ref then return false end
    aplicarPos(mousePos.x - ref.x, mousePos.y - ref.y)
    return true
  end
  mover.onDragLeave = function()
    if not ref then return false end
    ref = nil
    g_settings.setNode(CHAVE_POS, { x = acoes:getMarginLeft(), y = acoes:getMarginTop() })
    return true
  end
  mover.onMouseRelease = function(self, mousePos, button)
    if button ~= MouseRightButton then return false end
    local menu = g_ui.createWidget('PopupMenu')
    menu:addOption('Voltar os botoes ao lugar padrao', function()
      g_settings.remove(CHAVE_POS)
      posicionar()
    end)
    menu:display(mousePos)
    return true
  end
  connect(g_ui.getRootWidget(), { onGeometryChange = posicionarDepois })
  connect(LocalPlayer, { onHealthChange = onVida, onLevelChange = onVida, onPositionChange = onPosicao })
  local tm = modules.client_topmenu and modules.client_topmenu.getTopMenu and modules.client_topmenu.getTopMenu()
  if tm then
    connect(tm, { onVisibilityChange = function(w, visivel)
      if visivel and g_game.isOnline() then scheduleEvent(function() passo('barra do topo', esconderTopo) end, 50) end
    end })
  end
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
  g_logger.info('[codex] modo celular ligado (HUD do celular)')
end

function terminate()
  _G.codexJoystickToque = nil
  desligarArrasteLivre()
  desligarChatFlutuante()
  desligarUsar()
  if not overlay then return end
  removeEvent(evento)
  removeEvent(eventoPosicao)
  removeEvent(eventoJanelas)
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  disconnect(g_ui.getRootWidget(), { onGeometryChange = posicionarDepois })
  disconnect(LocalPlayer, { onHealthChange = onVida, onLevelChange = onVida, onPositionChange = onPosicao })
  overlay:destroy()
  overlay = nil
  keypad = nil
  acoes = nil
end

function hide() if overlay then overlay:hide() end end
function show() if overlay then overlay:show() end end
