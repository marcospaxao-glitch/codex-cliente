-- ============================================================
-- CODEX - compatibilidade
-- Os modulos do Codex foram feitos no OTClient antigo (edubart 2019).
-- Aqui ficam as funcoes que mudaram de nome ou sairam no Redemption,
-- para os modulos continuarem funcionando sem mexer neles.
-- So define o que NAO existe (se o Redemption tiver, usa o dele).
-- ============================================================
local function def(obj, key, fn)
  if obj and obj[key] == nil then obj[key] = fn end
end

-- graficos: o Redemption so tem um motor (OpenGL moderno / WebGL)
def(g_graphics, 'canUseShaders', function() return true end)
def(g_graphics, 'canCacheBackbuffer', function() return true end)
def(g_graphics, 'getPainterEngine', function() return 2 end)
def(g_graphics, 'isPainterEngineAvailable', function(engine) return engine == 2 end)
def(g_graphics, 'selectPainterEngine', function() return true end)

-- FPS: antes eram dois paineis (fundo/frente), agora e um limite so
def(g_app, 'getBackgroundPaneFps', function() return g_app.getFps() end)
def(g_app, 'getBackgroundPaneMaxFps', function() return g_app.getMaxFps() end)
def(g_app, 'setBackgroundPaneMaxFps', function(v) g_app.setMaxFps(v) end)
def(g_app, 'setForegroundPaneMaxFps', function() end)

-- andar "dash" virou o andar normal (o Redemption ja faz pre-walk)
def(g_game, 'dashWalk', function(dir) return g_game.walk(dir) end)

-- piscar a janela na barra de tarefas (ranked): nao existe mais
def(g_window, 'flash', function() end)

-- mapa
if UIMap then
  def(UIMap, 'setDrawTexts', function(self, v) self:setDrawNames(v) end)
  -- setMapShader(shaderAntigo): agora o shader e pelo nome
  def(UIMap, 'setMapShader', function(self, shader)
    if type(shader) == 'string' then self:setShader(shader, 0, 0) end
  end)
end

-- retrato de criatura com tamanho fixo
if UICreature then
  def(UICreature, 'setFixedCreatureSize', function() end)
end

-- ============================================================
-- DIAGNOSTICO: ao entrar no jogo, grava em codex_passos.txt
-- cada funcao de modulo chamada pelos eventos (onGameStart etc.), para achar
-- qual modulo derruba o cliente. Desliga sozinho depois de 800 chamadas.
-- So liga com o arquivo codex_debug.txt na pasta do cliente.
-- ============================================================
if codexPasso and codexDebugAtivo and codexDebugAtivo() and signalcall then
  local rastrear, chamadas = false, 0
  local function nome(f)
    local ok, info = pcall(debug.getinfo, f, 'S')
    if ok and info then return (info.short_src or '?') .. ':' .. tostring(info.linedefined) end
    return '?'
  end
  local original = signalcall
  signalcall = function(param, ...)
    if not rastrear then return original(param, ...) end
    chamadas = chamadas + 1
    if chamadas > 800 then rastrear = false return original(param, ...) end
    if type(param) == 'function' then
      codexPasso('evento -> ' .. nome(param))
      local r = original(param, ...)
      codexPasso('evento ok')
      return r
    elseif type(param) == 'table' then
      for _, v in pairs(param) do
        codexPasso('evento -> ' .. nome(v))
        local status, ret = pcall(v, ...)
        codexPasso('evento ok')
        if status then
          if ret then return true end
        else
          perror(ret)
        end
      end
      return false
    end
    return original(param, ...)
  end
  connect(g_game, { onEnterGame = function() rastrear = true; chamadas = 0; codexPasso('lua: onEnterGame') end }, true)
end


-- ------------------------------------------------------------
-- Texto em cima do personagem (fala no chat) e textos animados:
-- o cliente antigo usava g_map.addThing(texto, pos, -1); na base nova
-- e g_map.addStaticText / g_map.addAnimatedText.
-- ------------------------------------------------------------
if g_map and g_map.addThing and not g_map.__codexAddThing then
  g_map.__codexAddThing = g_map.addThing
  g_map.addThing = function(thing, pos, stackPos)
    local cls
    if thing and thing.getClassName then
      pcall(function() cls = thing:getClassName() end)
    end
    cls = tostring(cls or '')
    if cls:find('StaticText') and g_map.addStaticText then
      return g_map.addStaticText(thing, pos)
    elseif cls:find('AnimatedText') and g_map.addAnimatedText then
      return g_map.addAnimatedText(thing, pos)
    end
    return g_map.__codexAddThing(thing, pos, stackPos)
  end
end


-- CODEX: salvar as configuracoes (senha lembrada, posicao das janelas, opcoes) de
-- tempos em tempos. No navegador e no app de celular o jogo quase nunca "fecha"
-- direito (a aba/o app e simplesmente encerrado), entao o salvamento do fim nunca
-- acontecia e tudo se perdia.
do
  local function salvar()
    pcall(function() g_settings.save() end)
  end
  local evento = cycleEvent(salvar, 20000)
  connect(g_game, { onGameStart = function() scheduleEvent(salvar, 3000) end, onGameEnd = salvar })
  local _terminate = terminate
  function terminate()
    removeEvent(evento)
    salvar()
    if _terminate then _terminate() end
  end
end
