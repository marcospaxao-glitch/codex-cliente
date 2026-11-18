-- ============================================================
-- JORNADA DO TREINADOR - tutorial em missoes (opcode 132)
--   Janela com o Professor + lista das missoes, e um quadro na tela
--   com a missao atual (tocar abre a janela).
--   Botao "Jornada" no topo (PC) ou no MENU (celular), Ctrl+Shift+J, !jornada.
--   Servidor: data/lib/core/codexjornada.lua. Textos: jornada_textos.lua
-- ============================================================
local OPCODE = 132
local HOTKEY = 'Ctrl+Shift+J'
-- aparencia do Professor (outfit de NPC). Troque o type se quiser outro.
local PROFESSOR_LOOK = {type = 2007, head = 0, body = 0, legs = 0, feet = 0}
local CHAVE_QUADRO = 'codexJornadaQuadro'      -- mostrar o quadro na tela
local CHAVE_POS = 'codexJornadaQuadroPos'

local window, button, quadro
local estado = {passo = 0, total = 0, prog = 0, meta = 0, pronto = false, fim = false, premio = ''}
local vendo = nil         -- missao mostrada na janela (nil = a atual)
local digitando = nil     -- evento do texto aparecendo aos poucos
local textoCheio = ''
local abriuSozinho = false

local function celular()
  return type(codexCelular) == 'function' and codexCelular() and true or false
end

local function enviar(cmd)
  local proto = g_game.getProtocolGame()
  if proto then proto:sendExtendedOpcode(OPCODE, cmd) end
end

local function missao(i) return JORNADA_MISSOES[i] end

-- ---------------- texto do Professor aparecendo aos poucos ----------------
local function pararDigitar()
  if digitando then removeEvent(digitando) digitando = nil end
end

local function falar(texto)
  pararDigitar()
  local fala = window:recursiveGetChildById('fala')
  textoCheio = texto or ''
  local n = 0
  fala:setText('')
  digitando = cycleEvent(function()
    n = n + 3
    if n >= #textoCheio then
      fala:setText(textoCheio)
      pararDigitar()
      return
    end
    fala:setText(textoCheio:sub(1, n))
  end, 25)
end

-- ---------------- quadro na tela ----------------
local function quadroLigado() return g_settings.getString(CHAVE_QUADRO) ~= 'nao' end

local function posicionarQuadro()
  if not quadro then return end
  local p = quadro:getParent()
  local x, y = string.match(g_settings.getString(CHAVE_POS) or '', '^(%-?%d+),(%-?%d+)$')
  x, y = tonumber(x), tonumber(y)
  if not x or x < 0 or y < 0 or x > p:getWidth() - 40 or y > p:getHeight() - 30 then
    if celular() then
      x, y = 170, 150 -- ao lado da coluna de icones (SUBIR/DESCER, auto)
    else
      local gi = modules.game_interface
      local mapa = gi and gi.getMapPanel and gi.getMapPanel()
      x = (mapa and mapa:getX() or 0) + 12
      y = (mapa and mapa:getY() or 0) + 60
    end
  end
  quadro:setPosition({x = x, y = y})
end

local function atualizarQuadro()
  if not quadro then return end
  local m = missao(estado.passo)
  local mostrar = g_game.isOnline() and quadroLigado() and estado.passo > 0 and not estado.fim and m ~= nil
    and not (window and window:isVisible())
  quadro:setVisible(mostrar)
  if not mostrar then return end
  quadro:raise()
  quadro:getChildById('cabeca'):setText('JORNADA  ' .. estado.passo .. '/' .. estado.total ..
    (estado.pronto and '   PREMIO!' or ''))
  quadro:getChildById('missao'):setText(m.titulo)
  local fundo = quadro:getChildById('barraFundo')
  local barra = fundo:getChildById('barra')
  local frac = estado.meta > 0 and math.min(1, estado.prog / estado.meta) or 0
  barra:setWidth(math.floor(fundo:getWidth() * frac))
  barra:setBackgroundColor(estado.pronto and '#4fe07a' or '#4fa3ff')
  quadro:setBorderColor(estado.pronto and '#4fe07a' or '#b08a14')
end

local function criarQuadro()
  if quadro then return end
  local gi = modules.game_interface
  local raiz = gi and gi.getRootPanel and gi.getRootPanel()
  if not raiz then return end
  quadro = g_ui.createWidget('JornadaQuadro', raiz)
  quadro:setDraggable(true)
  quadro:setTooltip('Jornada do Treinador: clique para abrir. Arraste para mudar de lugar.')
  local soltouEm = 0
  quadro.onDragEnter = function(self, pos)
    self.off = {x = pos.x - self:getX(), y = pos.y - self:getY()}
    return true
  end
  quadro.onDragMove = function(self, pos)
    local off = self.off or {x = 0, y = 0}
    local p = self:getParent()
    self:setPosition({x = math.max(4, math.min(pos.x - off.x, p:getWidth() - self:getWidth() - 4)),
                      y = math.max(4, math.min(pos.y - off.y, p:getHeight() - self:getHeight() - 4))})
    return true
  end
  quadro.onDragLeave = function(self)
    soltouEm = g_clock.millis()
    local pos = self:getPosition()
    g_settings.set(CHAVE_POS, pos.x .. ',' .. pos.y)
    return true
  end
  quadro.onClick = function()
    if g_clock.millis() - soltouEm < 300 then return true end
    show()
    return true
  end
  quadro:hide()
  scheduleEvent(posicionarQuadro, 300)
end

-- ---------------- janela ----------------
local function corDaLinha(i)
  if estado.fim or i < estado.passo then return '#72e6a0', '#3fbf6a' end   -- feita
  if i == estado.passo and estado.passo > 0 then return '#ffffff', '#f2c400' end -- atual
  return '#56698a', '#2a3c56'                                              -- trancada
end

local function montarLista()
  local lista = window:getChildById('lista')
  lista:destroyChildren()
  local cap = 0
  for i, m in ipairs(JORNADA_MISSOES) do
    if m.cap ~= cap then
      cap = m.cap
      local c = g_ui.createWidget('JornadaCap', lista)
      c:setText('Capitulo ' .. cap .. ': ' .. (JORNADA_CAPITULOS[cap] or ''))
    end
    local row = g_ui.createWidget('JornadaRow', lista)
    row:setId('missao' .. i)
    row:setText(m.titulo)
    local cor, marca = corDaLinha(i)
    row:setColor(cor)
    row:getChildById('marca'):setBackgroundColor(marca)
    row.onClick = function()
      if estado.fim or i <= estado.passo then
        vendo = (i == estado.passo and not estado.fim) and nil or i
        modules.game_jornada.atualizar(true)
      end
    end
  end
end

local function botao(texto, ativo)
  local b = window:getChildById('botaoAcao')
  b:setText(texto)
  b:setEnabled(ativo ~= false)
end

-- mostra na janela: inicio, missao atual, missao ja feita ou o fim
function atualizar(refalar)
  atualizarQuadro()
  if not window or not window:isVisible() then return end
  montarLista()
  local titulo = window:getChildById('tituloMissao')
  local progTxt = window:getChildById('progressoTexto')
  local fundo = window:getChildById('barraFundo')
  local barra = fundo:getChildById('barra')
  local dica = window:getChildById('dica')
  local premio = window:getChildById('premio')
  local function barraEm(frac, cor)
    barra:setWidth(math.floor((fundo:getWidth() - 2) * math.max(0, math.min(1, frac))))
    barra:setBackgroundColor(cor or '#4fa3ff')
  end

  -- ainda nao comecou
  if estado.passo == 0 and not estado.fim then
    if refalar then falar(JORNADA_INICIO) end
    titulo:setText(#JORNADA_MISSOES .. ' missoes para aprender a jogar')
    progTxt:setText('')
    barraEm(0)
    dica:setText('Clique em Comecar Jornada. Os premios de cada missao sao entregues uma vez so.')
    premio:setText('Experiencia, gold e itens em todas as missoes.')
    botao('Comecar Jornada', true)
    return
  end

  -- terminou tudo
  if estado.fim and not vendo then
    if refalar then falar(JORNADA_FIM) end
    titulo:setText('Jornada completa!')
    progTxt:setText(#JORNADA_MISSOES .. '/' .. #JORNADA_MISSOES)
    barraEm(1, '#4fe07a')
    dica:setText('Clique numa missao da lista para ler de novo.')
    premio:setText('Todos os premios ja foram entregues.')
    botao('Fechar', true)
    return
  end

  local i = vendo or estado.passo
  local m = missao(i)
  if not m then return end
  local atual = (i == estado.passo) and not estado.fim
  titulo:setText(i .. '. ' .. m.titulo)
  dica:setText((celular() and m.cel) or m.dica or '')
  if not atual then
    if refalar then falar(m.feito or m.fala) end
    progTxt:setText('Feita')
    barraEm(1, '#4fe07a')
    premio:setText('Premio ja entregue.')
    botao('Voltar para a atual', not estado.fim)
    if estado.fim then botao('Fechar', true) end
    return
  end
  progTxt:setText(math.min(estado.prog, estado.meta) .. ' / ' .. estado.meta)
  barraEm(estado.meta > 0 and estado.prog / estado.meta or 0, estado.pronto and '#4fe07a' or '#4fa3ff')
  premio:setText(estado.premio ~= '' and estado.premio or '...')
  if estado.pronto then
    if refalar then falar(m.feito or 'Muito bem!') end
    botao('Pegar premio', true)
  else
    if refalar then falar(m.fala) end
    local ler = (i == 1)
    botao(ler and 'Entendi!' or 'Em andamento...', ler)
  end
end

function acao()
  if not window then return end
  if vendo then
    vendo = nil
    if estado.fim then hide() return end
    atualizar(true)
    return
  end
  if estado.passo == 0 and not estado.fim then
    enviar('COMECAR')
  elseif estado.fim then
    hide()
  elseif estado.pronto then
    enviar('PEGAR')
  elseif estado.passo == 1 then
    enviar('LIDO')
  end
end

function abrirGuia()
  local g = modules.game_tutorial
  if g and g.show then pcall(g.show) elseif g and g.toggle then pcall(g.toggle) end
end

function onMostrarQuadro(ligado)
  g_settings.set(CHAVE_QUADRO, ligado and 'sim' or 'nao')
  atualizarQuadro()
end

function show()
  if not window then return end
  vendo = nil
  window:show()
  window:raise()
  window:focus()
  local cb = window:getChildById('mostrarQuadro')
  if cb then cb:setChecked(quadroLigado()) end
  local r = window:recursiveGetChildById('retrato')
  pcall(function() r:setOutfit(PROFESSOR_LOOK) end)
  window:recursiveGetChildById('professor'):setText(JORNADA_PROFESSOR or 'Professor')
  enviar('INFO')
  atualizar(true)
end

function hide()
  pararDigitar()
  if window then window:hide() end
  atualizarQuadro()
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

-- ---------------- servidor ----------------
local function onOpcode(protocol, opcode, buffer)
  buffer = buffer or ''
  if buffer == 'ABRIR' then show() return end
  local c = {}
  for v in (buffer .. '|'):gmatch('([^|]*)|') do c[#c + 1] = v end
  if c[1] ~= 'S' then return end
  local antes, antesPronto = estado.passo, estado.pronto
  estado.passo = tonumber(c[2]) or 0
  estado.total = tonumber(c[3]) or #JORNADA_MISSOES
  estado.prog = tonumber(c[4]) or 0
  estado.meta = tonumber(c[5]) or 0
  estado.pronto = c[6] == '1'
  estado.fim = c[7] == '1'
  estado.premio = c[8] or ''
  local mudou = antes ~= estado.passo or antesPronto ~= estado.pronto
  -- personagem novo: abre a Jornada sozinho uma vez
  if estado.passo == 1 and not estado.pronto and not abriuSozinho then
    local chave = 'codexJornadaAbriu_' .. tostring(g_game.getCharacterName())
    if not g_settings.getBoolean(chave) then
      g_settings.set(chave, true)
      abriuSozinho = true
      scheduleEvent(show, 800)
    end
  end
  atualizar(mudou)
end

local function onGameStart()
  abriuSozinho = false
  criarQuadro()
  scheduleEvent(function() if g_game.isOnline() then enviar('INFO') end end, 2000)
end

local function onGameEnd()
  hide()
  if quadro then quadro:destroy() quadro = nil end
  estado = {passo = 0, total = 0, prog = 0, meta = 0, pronto = false, fim = false, premio = ''}
end

function init()
  g_ui.importStyle('jornada')
  window = g_ui.displayUI('jornada')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onOpcode)
  local tm = modules.client_topmenu
  if tm and tm.addRightGameButton then
    button = tm.addRightGameButton('codexJornadaButton', 'Jornada do Treinador (' .. HOTKEY .. ')',
      '/images/topbuttons/codex/shieldstar', toggle)
  end
  g_keyboard.bindKeyDown(HOTKEY, toggle)
  connect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  pararDigitar()
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = onGameEnd})
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE) end)
  g_keyboard.unbindKeyDown(HOTKEY)
  if button then button:destroy() button = nil end
  if quadro then quadro:destroy() quadro = nil end
  if window then window:destroy() window = nil end
end
