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
