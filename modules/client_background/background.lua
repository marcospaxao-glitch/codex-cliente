-- private variables
local background
local clientVersionLabel

-- public functions
function init()
  background = g_ui.displayUI('background')
  background:lower()

  -- a versao aparece no rodape do painel de login (client_entergame)
  clientVersionLabel = background:getChildById('clientVersionLabel')
  clientVersionLabel:setText(g_app.getName() .. ' v' .. g_app.getVersion())

  connect(g_game, { onGameStart = hide })
  connect(g_game, { onGameEnd = show })
end

function terminate()
  disconnect(g_game, { onGameStart = hide })
  disconnect(g_game, { onGameEnd = show })
  background:destroy()
  background = nil
  Background = nil
end

function hide()
  background:hide()
end

function show()
  background:show()
end

function hideVersionLabel()
  clientVersionLabel:hide()
end

function setVersionText(text)
  clientVersionLabel:setText(text)
end

function getBackground()
  return background
end
