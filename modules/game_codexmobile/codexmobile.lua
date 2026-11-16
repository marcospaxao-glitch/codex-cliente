-- Codex: joystick na tela para jogar pelo navegador do celular.
-- So liga quando o cliente roda no navegador de um celular/tablet (codexCelular()).
local overlay
local keypad
local evento
local posRel = { x = 0.5, y = 0.5 }
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

local function atualizarPos(widget, pos)
  posRel = {
    x = (pos.x - widget:getX()) / widget:getWidth(),
    y = (pos.y - widget:getY()) / widget:getHeight()
  }
end

local function direcao()
  local x = math.min(1, math.max(0, posRel.x))
  local y = math.min(1, math.max(0, posRel.y))
  if y < 0.3 and x < 0.3 then return Directions.NorthWest end
  if y < 0.3 and x > 0.7 then return Directions.NorthEast end
  if y > 0.7 and x < 0.3 then return Directions.SouthWest end
  if y > 0.7 and x > 0.7 then return Directions.SouthEast end
  if math.abs(y - 0.5) <= 0.1 and math.abs(x - 0.5) <= 0.1 then return nil end
  if math.abs(y - 0.5) > math.abs(x - 0.5) then
    return y < 0.5 and Directions.North or Directions.South
  end
  return x < 0.5 and Directions.West or Directions.East
end

local function passo()
  removeEvent(evento)
  evento = nil
  if not segurando or not g_game.isOnline() then
    centralizar()
    return
  end
  evento = scheduleEvent(passo, 40)

  local x = math.min(1, math.max(0, posRel.x))
  local y = math.min(1, math.max(0, posRel.y))
  local ang = math.atan2(x - 0.5, y - 0.5)
  local maxTop = math.abs(math.cos(ang)) * 50
  local maxLeft = math.abs(math.sin(ang)) * 50
  keypad.pointer:setMarginTop(math.max(-maxTop, math.min(maxTop, (y - 0.5) * 100)))
  keypad.pointer:setMarginLeft(math.max(-maxLeft, math.min(maxLeft, (x - 0.5) * 100)))

  local dir = direcao()
  if dir then g_game.walk(dir) end
end

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
  segurando = false
  removeEvent(evento)
  evento = nil
  centralizar()
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

local function golpe(n)
  -- mesma acao da barra de golpes (respeita nivel e recarga)
  local pm = modules.game_pokemonmoves
  if pm and pm.useSpell then
    pm.useSpell(n)
  elseif g_game.isOnline() then
    g_game.talk('m' .. n)
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

-- posicao escolhida pelo jogador (arrastando a alca); nil = lugar padrao
local CHAVE_POS = 'codexMobileAcoes'
local function posSalva()
  local p = g_settings.getNode(CHAVE_POS)
  if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) then
    return { x = tonumber(p.x), y = tonumber(p.y) }
  end
  return nil
end

local function aplicarPos(x, y)
  local root = g_ui.getRootWidget()
  x = math.max(0, math.min(x, root:getWidth() - acoes:getWidth()))
  y = math.max(0, math.min(y, root:getHeight() - acoes:getHeight()))
  acoes:setMarginLeft(x)
  acoes:setMarginTop(y)
end

-- coloca os botoes no canto inferior direito da area do mapa
local function posicionar()
  removeEvent(eventoPosicao)
  eventoPosicao = nil
  if not acoes or not acoes:isVisible() then return end
  local salva = posSalva()
  if salva then
    aplicarPos(salva.x, salva.y)
    return
  end
  local gi = modules.game_interface
  local mapa = gi and gi.getMapPanel and gi.getMapPanel()
  local root = g_ui.getRootWidget()
  local direita, baixo
  if mapa and mapa:getWidth() > 0 then
    direita = mapa:getX() + mapa:getWidth()
    baixo = mapa:getY() + mapa:getHeight()
  else
    direita = root:getWidth()
    baixo = root:getHeight()
  end
  -- fica acima do chat quando o chat esta aberto por cima do mapa
  local fundo = gi and gi.getBottomPanel and gi.getBottomPanel()
  -- (so se o chat estiver embaixo dos botoes; no celular ele fica no centro)
  if fundo and fundo:isVisible() and fundo:getHeight() > 0 and fundo:getY() < baixo
      and fundo:getX() + fundo:getWidth() > direita - acoes:getWidth() - 12 then
    baixo = fundo:getY()
  end
  acoes:setMarginLeft(math.max(0, direita - acoes:getWidth() - 12))
  acoes:setMarginTop(math.max(0, baixo - acoes:getHeight() - 8))
end

local function posicionarDepois()
  removeEvent(eventoPosicao)
  eventoPosicao = scheduleEvent(posicionar, 100)
end

-- ============================================================
-- HUD do celular: cartao do jogador, botoes do topo, minimapa,
-- gaveta da direita e chat compacto (so no celular)
-- ============================================================
local cartao, menuTopo, miniMapa
local gavetaAberta = false

local function botaoDoTopo(id)
  local tm = modules.client_topmenu
  local b = tm and tm.getButton and tm.getButton(id)
  if not b then
    b = g_ui.getRootWidget():recursiveGetChildById(id)
  end
  if b and b.onClick then
    b:onClick()
    return true
  end
  return false
end

local function atualizarCartao()
  local player = g_game.getLocalPlayer()
  if not cartao or not player then return end
  cartao:getChildById('nome'):setText(player:getName())
  cartao:getChildById('nivel'):setText('Lv ' .. player:getLevel())
  local vida, maxVida = player:getHealth(), math.max(1, player:getMaxHealth())
  local fundo = cartao:getChildById('vidaFundo')
  local barra = fundo:getChildById('vida')
  barra:setWidth(math.max(0, math.floor((fundo:getWidth() - 2) * vida / maxVida)))
  fundo:getChildById('vidaTexto'):setText(vida .. ' / ' .. maxVida)
  local xpFundo = cartao:getChildById('xpFundo')
  local pct = 0
  pcall(function() pct = player:getLevelPercent() end)
  xpFundo:getChildById('xp'):setWidth(math.max(0, math.floor((xpFundo:getWidth() - 2) * pct / 100)))
  pcall(function() cartao:getChildById('retrato'):setOutfit(player:getOutfit()) end)
end

local function atualizarMapa()
  local player = g_game.getLocalPlayer()
  if not miniMapa or not player then return end
  local pos = player:getPosition()
  if not pos then return end
  pcall(function() miniMapa:getChildById('mapa'):setCameraPosition(pos) end)
  miniMapa:getChildById('coords'):setText(pos.x .. ', ' .. pos.y .. ', ' .. pos.z)
end

-- gaveta = coluna da direita do PC (batalha, mochila, janelas). Fica escondida
-- por cima do mapa e abre pelos botoes do topo.
local function abrirGaveta(abrir)
  local gi = modules.game_interface
  local direita = gi and gi.getRightPanel and gi.getRightPanel()
  if not direita then return end
  gavetaAberta = abrir
  direita:setVisible(abrir)
  if abrir then direita:raise() end
  -- os botoes do topo andam para a esquerda da gaveta; minimapa e acoes saem da frente
  if menuTopo then menuTopo:setMarginRight(abrir and (direita:getWidth() + 6) or 6) end
  if miniMapa then miniMapa:setVisible(not abrir) end
  if acoes then acoes:setVisible(not abrir) end
  if overlay then overlay:raise() end
end

local function organizarTela()
  local gi = modules.game_interface
  if not gi then return end
  local root = g_ui.getRootWidget()
  -- mapa na tela toda (modo da propria interface do Codex)
  pcall(function() gi.setupViewMode(2) end)
  -- barra de icones do topo escondida (abre no botao MENU)
  local tm = modules.client_topmenu and modules.client_topmenu.getTopMenu()
  if tm then tm:hide() end
  local esquerda, direita = gi.getLeftPanel(), gi.getRightPanel()
  if esquerda then esquerda:setOn(false) end
  if direita then direita:setMarginTop(0) end
  abrirGaveta(false)
  -- chat compacto embaixo, no centro
  local fundo = gi.getBottomPanel()
  if fundo then
    fundo:breakAnchors()
    fundo:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    fundo:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    fundo:setWidth(math.max(360, math.floor(root:getWidth() * 0.46)))
    fundo:setHeight(150)
  end
  if gi.bottomSplitter then gi.bottomSplitter:hide() end
  -- barras do Codex nos lugares do celular (so na primeira vez)
  local pb = modules.game_pokemonbar
  if pb and pb.codexModoCelular then pcall(pb.codexModoCelular, 8, 88) end
  local pm = modules.game_pokemonmoves
  if pm and pm.codexModoCelular then pcall(pm.codexModoCelular, 6) end
end

local function mostrarHud(mostrar)
  for _, w in ipairs({ cartao, menuTopo, miniMapa }) do
    if w then w:setVisible(mostrar) end
  end
end

local function onGameStart()
  if not keypad then return end
  overlay:raise()
  keypad:show()
  acoes:show()
  -- a hotbar F1-F12 sai: os botoes grandes substituem
  local hb = modules.game_codexhotbar
  if hb and hb.setHidden then hb.setHidden(true) end
  mostrarHud(true)
  -- espera a interface do jogo terminar de montar
  scheduleEvent(function()
    if not g_game.isOnline() then return end
    organizarTela()
    atualizarCartao()
    atualizarMapa()
    posicionar()
  end, 300)
  posicionarDepois()
  scheduleEvent(posicionar, 1500) -- depois que as janelas laterais terminam de abrir
end

local function onGameEnd()
  segurando = false
  removeEvent(evento)
  evento = nil
  if keypad then keypad:hide() end
  if acoes then acoes:hide() end
  mostrarHud(false)
  gavetaAberta = false
end

local function onVida() atualizarCartao() end
local function onPosicao() atualizarMapa() end

function init()
  if not ehCelular() then return end
  overlay = g_ui.displayUI('codexmobile')
  keypad = overlay:getChildById('keypad')
  connect(keypad, { onMousePress = onPress, onMouseMove = onMove, onMouseRelease = onRelease })
  acoes = overlay:getChildById('acoes')
  for n = 1, 4 do
    acoes:getChildById('m' .. n).onClick = function() golpe(n) end
  end
  acoes:getChildById('atacar').onClick = atacarProximo
  acoes:getChildById('usar').onClick = usarFrente
  acoes:getChildById('poke').onClick = pokemon

  -- alca: arrasta o grupo de botoes; segurar parado = voltar ao lugar padrao
  local mover = acoes:getChildById('mover')
  local ref = nil
  mover.onDragEnter = function(self, mousePos)
    ref = { x = mousePos.x - acoes:getX(), y = mousePos.y - acoes:getY() }
    return true
  end
  mover.onDragMove = function(self, mousePos)
    if not ref then return false end
    aplicarPos(mousePos.x - ref.x, mousePos.y - ref.y)
    return true
  end
  mover.onDragLeave = function()
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

  cartao = overlay:getChildById('cartao')
  menuTopo = overlay:getChildById('menuTopo')
  miniMapa = overlay:getChildById('miniMapa')
  pcall(function() miniMapa:getChildById('mapa'):hideFloor() end)
  menuTopo:getChildById('btnMenu').onClick = function()
    if modules.client_topmenu and modules.client_topmenu.toggle then modules.client_topmenu.toggle() end
  end
  menuTopo:getChildById('btnMochila').onClick = function()
    abrirGaveta(true)
    botaoDoTopo('healthInfo_inventory')
  end
  menuTopo:getChildById('btnPokemon').onClick = function()
    abrirGaveta(true)
    botaoDoTopo('healthInfo_pokemons')
  end
  menuTopo:getChildById('btnLoot').onClick = function()
    abrirGaveta(true)
    botaoDoTopo('lootBagButton')
  end
  menuTopo:getChildById('btnPainel').onClick = function()
    abrirGaveta(not gavetaAberta)
  end
  connect(LocalPlayer, { onHealthChange = onVida, onLevelChange = onVida, onPositionChange = onPosicao })
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
  g_logger.info('[codex] modo celular ligado (joystick + botoes de acao)')
end

function terminate()
  if not overlay then return end
  removeEvent(evento)
  removeEvent(eventoPosicao)
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
