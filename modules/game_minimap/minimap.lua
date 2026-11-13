minimapWidget = nil
minimapButton = nil
minimapWindow = nil
otmm = true
preloaded = false
fullmapView = false
oldZoom = nil
oldPos = nil

local MAP_COMPOSITIONS, COMPOSITIONS = {}, {}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Viridian", position = {x = 715, y = 793, z = 7}}
-- MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Pallet", position = {x = 3292, y = 799, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Pewter", position = {x = 720, y = 879, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Cerulean", position = {x = 1024, y = 840, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Saffron", position = {x = 1018, y = 1017, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Celadon", position = {x = 889, y = 999, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Lavender", position = {x = 1195, y = 975, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Vermilion", position = {x = 1010, y = 1177, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Fuchsia", position = {x = 1017, y = 1329, z = 7}}
MAP_COMPOSITIONS[#MAP_COMPOSITIONS + 1] = {text = "Cinnabar", position = {x = 511, y = 1394, z = 7}}

MAPMARK_TICK = 0
MAPMARK_QUESTION = 1
MAPMARK_EXCLAMATION = 2
MAPMARK_STAR = 3
MAPMARK_CROSS = 4
MAPMARK_TEMPLE = 5
MAPMARK_KISS = 6
MAPMARK_SHOVEL = 7
MAPMARK_SWORD = 8
MAPMARK_FLAG = 9
MAPMARK_LOCK = 10
MAPMARK_BAG = 11
MAPMARK_SKULL = 12
MAPMARK_DOLLAR = 13
MAPMARK_REDNORTH = 14
MAPMARK_REDSOUTH = 15
MAPMARK_REDEAST = 16
MAPMARK_REDWEST = 17
MAPMARK_GREENNORTH = 18
MAPMARK_GREENSOUTH = 19

-- Icones proprios do minimapa (usados pelo celular).
-- O servidor manda o tipo 20 (GPS) ou 21 (Casa) no addMapMark.
MAPMARK_GPS = 20
MAPMARK_HOUSE = 21
local CUSTOM_FLAGS = {
  [MAPMARK_GPS] = '/modules/game_minimap/images/mm_gps',
  [MAPMARK_HOUSE] = '/modules/game_minimap/images/mm_house',
}
local CUSTOM_FLAG_SIZE = 12

local marksHidden = false

-- mostra / esconde todas as marcas do minimapa (botao da bandeira)
-- tamanhos do minimapa (botao no cabecalho)
local SIZES = { 190, 330, 500 }
function cycleSize()
  if not minimapWindow then return end
  local height = minimapWindow:getHeight()
  local nextHeight = SIZES[1]
  for _, size in ipairs(SIZES) do
    if size > height + 5 then
      nextHeight = size
      break
    end
  end
  if minimapWindow.isOn and minimapWindow:isOn() and minimapWindow.maximize then
    pcall(function() minimapWindow:maximize() end) -- se estava minimizado
  end
  minimapWindow:setHeight(nextHeight)
end

function toggleMarks()
  marksHidden = not marksHidden
  if minimapWidget then
    for _, flag in pairs(minimapWidget.flags or {}) do
      flag:setVisible(not marksHidden)
    end
    local button = minimapWidget:getChildById('marks')
    if button then button:setOn(marksHidden) end
  end
end

-- cidade mais proxima (usa os nomes de MAP_COMPOSITIONS)
local CITY_RADIUS = 90
local function cityAt(pos)
  local best, bestDist
  for _, city in pairs(MAP_COMPOSITIONS) do
    local dx, dy = math.abs(city.position.x - pos.x), math.abs(city.position.y - pos.y)
    local dist = math.max(dx, dy)
    if dist <= CITY_RADIUS and (not bestDist or dist < bestDist) then
      best, bestDist = city.text, dist
    end
  end
  return best
end

local function floorText(z)
  if z == 7 then return 'Terreo' end
  if z < 7 then return 'Andar +' .. (7 - z) end
  return 'Subsolo ' .. (z - 7)
end

local function styleCustomFlag(widget, flag, pos, icon)
  local path = CUSTOM_FLAGS[icon]
  if not flag or not path then return end
  flag:setSize({ width = CUSTOM_FLAG_SIZE, height = CUSTOM_FLAG_SIZE })
  flag:setIcon(path)
  flag:setIconSize({ width = CUSTOM_FLAG_SIZE, height = CUSTOM_FLAG_SIZE })
  flag:setIconClip({ x = 0, y = 0, width = CUSTOM_FLAG_SIZE, height = CUSTOM_FLAG_SIZE })
  if widget.centerInPosition then
    widget:centerInPosition(flag, pos)
  end
end

-- troca o desenho das marcas 20/21 sempre que o minimapa cria uma marca
-- (vinda do servidor, do arquivo salvo ou criada pelo jogador)
local attachRouteClick -- definida mais abaixo (GPS)

local function hookCustomFlags(widget)
  if widget.customFlagsHooked then return end
  widget.customFlagsHooked = true
  local baseAddFlag = widget.addFlag
  widget.addFlag = function(self, pos, icon, ...)
    local flag = baseAddFlag(self, pos, icon, ...)
    if not flag and self.getFlag then
      flag = self:getFlag(pos)
    end
    if CUSTOM_FLAGS[icon] then
      styleCustomFlag(self, flag, pos, icon)
    end
    if flag and marksHidden then
      flag:setVisible(false)
    end
    if attachRouteClick then attachRouteClick(flag) end
    return flag
  end
end


-- ============================================================
-- GPS: clique numa marca do minimapa e aparece um caminho verde
-- ate ela. O caminho vai sumindo conforme o jogador anda.
-- ============================================================
local ROUTE_COLOR = '#39d353'
local ROUTE_DOT = 3              -- tamanho do ponto (px)
local ROUTE_MAX_DOTS = 450       -- pontos desenhados (caminhos longos usam amostragem)
local ROUTE_COMPLEXITY = 80000   -- limite da busca de caminho
local ROUTE_RECALC_MS = 1500     -- intervalo minimo para recalcular
local DIRS = {
  [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 },
  [4] = { 1, -1 }, [5] = { 1, 1 }, [6] = { -1, 1 }, [7] = { -1, -1 },
}

local route = nil   -- { target, name, points = {pos...}, dots = {[i] = widget}, straight, lastCalc }

local function nowMs()
  return g_clock and g_clock.millis and g_clock.millis() or os.time() * 1000
end

local function routeLabel(text, color)
  local label = minimapWindow and minimapWindow:recursiveGetChildById('cityLabel')
  if label then
    label:setText(text)
    label:setColor(color or ROUTE_COLOR)
  end
end

local function clearDots()
  if not route then return end
  for _, dot in pairs(route.dots or {}) do
    if not dot:isDestroyed() then dot:destroy() end
  end
  route.dots = {}
end

local function stopButton()
  return minimapWidget and minimapWidget:getChildById('routeStop')
end

function stopRoute(arrived)
  clearDots()
  route = nil
  local button = stopButton()
  if button then button:hide() end
  if arrived and modules.game_textmessage then
    modules.game_textmessage.displayStatusMessage('GPS: voce chegou ao destino.')
  end
  updateCameraPosition()
end

local function drawRoute()
  clearDots()
  local points = route.points
  local step = math.max(1, math.ceil(#points / ROUTE_MAX_DOTS))
  for i = step, #points, step do
    local dot = g_ui.createWidget('UIWidget')
    dot:setSize({ width = ROUTE_DOT, height = ROUTE_DOT })
    dot:setBackgroundColor(route.straight and '#f2c400' or ROUTE_COLOR)
    dot:setPhantom(true)
    dot:setFocusable(false)
    minimapWidget:insertChild(1, dot)
    dot.pos = points[i]
    minimapWidget:centerInPosition(dot, points[i])
    route.dots[i] = dot
  end
end

-- linha reta (quando o caminho passa por area ainda nao explorada)
local function straightLine(from, to)
  local points = {}
  local dx, dy = to.x - from.x, to.y - from.y
  local steps = math.max(math.abs(dx), math.abs(dy))
  for i = 1, steps do
    points[#points + 1] = { x = from.x + math.floor(dx * i / steps + 0.5), y = from.y + math.floor(dy * i / steps + 0.5), z = from.z }
  end
  return points
end

local function calcRoute()
  local player = g_game.getLocalPlayer()
  if not route or not player then return end
  local from, to = player:getPosition(), route.target
  route.lastCalc = nowMs()
  if from.z ~= to.z then
    clearDots()
    route.points = {}
    local diff = to.z < from.z and ('suba ' .. (from.z - to.z)) or ('desca ' .. (to.z - from.z))
    routeLabel('GPS: ' .. diff .. ' andar(es)', '#f2c400')
    return
  end
  local points = {}
  local ok, dirs, result = pcall(function() return g_map.findPath(from, to, ROUTE_COMPLEXITY, PathFindFlags and PathFindFlags.AllowCreatures or 2) end)
  if ok and type(dirs) == 'table' and #dirs > 0 and (result == nil or result == 0) then
    local x, y = from.x, from.y
    for _, dir in ipairs(dirs) do
      local d = DIRS[dir] or { 0, 0 }
      x, y = x + d[1], y + d[2]
      points[#points + 1] = { x = x, y = y, z = from.z }
    end
    route.straight = false
  else
    points = straightLine(from, to)
    route.straight = true
  end
  route.points = points
  drawRoute()
end

-- chamado a cada passo do jogador
local function updateRoute(pos)
  if not route or not pos then return end
  local target = route.target
  if pos.z == target.z and math.max(math.abs(pos.x - target.x), math.abs(pos.y - target.y)) <= 1 then
    stopRoute(true)
    return
  end
  local points = route.points or {}
  if pos.z ~= target.z then
    -- outro andar: atualiza o aviso (sobe/desce) e apaga o caminho antigo
    if #points > 0 or route.lastZ ~= pos.z then calcRoute() end
    route.lastZ = pos.z
    return
  end
  if #points == 0 then
    calcRoute() -- chegou no andar do destino
    route.lastZ = pos.z
    return
  end
  if route.straight then
    calcRoute() -- linha reta: refaz a cada passo (e barato)
    return
  end
  -- acha onde o jogador esta no caminho (procura perto do inicio)
  local found
  for i = 1, math.min(#points, 40) do
    local p = points[i]
    if math.abs(p.x - pos.x) <= 1 and math.abs(p.y - pos.y) <= 1 then
      found = i
      if p.x == pos.x and p.y == pos.y then break end
    end
  end
  if not found then
    -- saiu do caminho: recalcula (com intervalo)
    if nowMs() - (route.lastCalc or 0) >= ROUTE_RECALC_MS then calcRoute() end
    return
  end
  -- apaga o trecho ja percorrido
  local newPoints, newDots = {}, {}
  for i = 1, #points do
    if i <= found then
      local dot = route.dots[i]
      if dot and not dot:isDestroyed() then dot:destroy() end
    else
      newPoints[#newPoints + 1] = points[i]
      newDots[#newPoints] = route.dots[i]
    end
  end
  route.points, route.dots = newPoints, newDots
end

function startRoute(target, name)
  if not target or not minimapWidget then return end
  stopRoute(false)
  route = { target = { x = target.x, y = target.y, z = target.z }, name = name or 'Destino', points = {}, dots = {} }
  local button = stopButton()
  if not button then
    button = g_ui.createWidget('MinimapCtrlButton', minimapWidget)
    button:setId('routeStop')
    button:setText('x')
    button:setColor('#e04848')
    button:setTooltip('Parar GPS')
    button:addAnchor(AnchorTop, 'marks', AnchorBottom)
    button:addAnchor(AnchorLeft, 'marks', AnchorLeft)
    button:setMarginTop(8)
    button.onClick = function() stopRoute(false) end
  end
  button:show()
  button:raise()
  calcRoute()
  updateCameraPosition()
end

local function routeInfo()
  if not route then return nil end
  local player = g_game.getLocalPlayer()
  local pos = player and player:getPosition()
  if pos and pos.z ~= route.target.z then return nil end
  local n = route.points and #route.points or 0
  return 'GPS ' .. n .. ' sqm' .. (route.straight and ' (aprox.)' or '')
end

-- clique nas marcas: esquerdo = tracar rota; direito = menu
attachRouteClick = function(flag)
  if not flag or flag.routeAttached then return end
  flag.routeAttached = true
  flag.onMouseRelease = function(widget, mousePos, button)
    if button == MouseLeftButton then
      startRoute(widget.pos, widget.description)
      return true
    elseif button == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption('Tracar rota (GPS)', function() startRoute(widget.pos, widget.description) end)
      if route then menu:addOption('Parar GPS', function() stopRoute(false) end) end
      menu:addSeparator()
      menu:addOption('Apagar marca', function() widget:destroy() end)
      menu:display(mousePos)
      return true
    end
    return false
  end
  local tip = flag.description and flag.description ~= '' and (flag.description .. '\n') or ''
  flag:setTooltip(tip .. 'Clique para tracar a rota')
end

local GUIDES = {}

GUIDES["Saffron"] = { -- Guide Andie
    -- {position = {x = 1069, y = 1027, z = 7}, type = MAPMARK_DOLLAR, description = "Poke Mart and Bank"},
    -- {position = {x = 1066, y = 1027, z = 7}, type = MAPMARK_DOLLAR, description = "Market venda de pokemons e itens"},
    -- {position = {x = 1029, y = 1018, z = 7}, type = MAPMARK_DOLLAR, description = "Task 3 horas"},
    -- {position = {x = 1029, y = 1011, z = 7}, type = MAPMARK_DOLLAR, description = "Comprador de Pokemons"},
    -- {position = {x = 1019, y = 1014, z = 7}, type = MAPMARK_TEMPLE, description = "Pokemon Center"},
	-- {position = {x = 1038, y = 1018, z = 7}, type = MAPMARK_STAR, description = "Compra Stone de Player"},
	-- {position = {x = 1037, y = 1012, z = 7}, type = MAPMARK_STAR, description = "Nick e Aura"},
    -- {position = {x = 3964, y = 448, z = 7}, type = MAPMARK_BAG, description = "Food Shop and Furniture Shop"},
    -- {position = {x = 3969, y = 462, z = 7}, type = MAPMARK_SWORD, description = "GYM"},
    -- {position = {x = 3876, y = 487, z = 7}, type = MAPMARK_STAR, description = "Silph Co."},
    -- {position = {x = 4006, y = 464, z = 7}, type = MAPMARK_STAR, description = "Guild House"},
    -- {position = {x = 3895, y = 464, z = 7}, type = MAPMARK_STAR, description = "Travel Fly"},
    -- {position = {x = 3886, y = 464, z = 7}, type = MAPMARK_STAR, description = "Travel Balloon"},
    -- {position = {x = 3945, y = 454, z = 7}, type = MAPMARK_BAG, description = "Berry Shop"},
}

local guideEnabled = true
local guideMarks = {}

local function removeGuides()
    for k, v in pairs(guideMarks) do
        v:destroy()
    end
    guideMarks = {}
end

local function addGuides()
    for k, city in pairs(GUIDES) do
        for _, mark in pairs(city) do
            guideMarks[#guideMarks + 1] = minimapWidget:addFlag(mark.position, mark.type, tr(mark.description))
        end
    end
end

function setGuidesDisplay(v)
    guideEnabled = v
    if (not guideEnabled) then
        removeGuides()
    end
end


function init()
  minimapButton = modules.client_topmenu.addRightGameToggleButton('minimapButton', 
    tr('Minimap') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
  minimapButton:setOn(true)

  minimapWindow = g_ui.loadUI('minimap', modules.game_interface.getRightPanel())
  minimapWindow:setContentMinimumHeight(64)

  minimapWidget = minimapWindow:recursiveGetChildById('minimap')
  hookCustomFlags(minimapWidget)

  local gameRootPanel = modules.game_interface.getRootPanel()
  g_keyboard.bindKeyPress('Alt+Left', function() minimapWidget:move(1,0) end, gameRootPanel)
  g_keyboard.bindKeyPress('Alt+Right', function() minimapWidget:move(-1,0) end, gameRootPanel)
  g_keyboard.bindKeyPress('Alt+Up', function() minimapWidget:move(0,1) end, gameRootPanel)
  g_keyboard.bindKeyPress('Alt+Down', function() minimapWidget:move(0,-1) end, gameRootPanel)
  g_keyboard.bindKeyDown('Ctrl+M', toggle)
  g_keyboard.bindKeyDown('Ctrl+Tab', toggleFullMap)

  minimapWindow:setup()

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  connect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  pcall(stopRoute, false)
  if g_game.isOnline() then
    saveMap()
  end

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  disconnect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  local gameRootPanel = modules.game_interface.getRootPanel()
  g_keyboard.unbindKeyPress('Alt+Left', gameRootPanel)
  g_keyboard.unbindKeyPress('Alt+Right', gameRootPanel)
  g_keyboard.unbindKeyPress('Alt+Up', gameRootPanel)
  g_keyboard.unbindKeyPress('Alt+Down', gameRootPanel)
  g_keyboard.unbindKeyDown('Ctrl+M')
  g_keyboard.unbindKeyDown('Ctrl+Shift+M')

  minimapWindow:destroy()
  minimapButton:destroy()
end

function toggle()
  if minimapButton:isOn() then
    minimapWindow:close()
    minimapButton:setOn(false)
  else
    minimapWindow:open()
    minimapButton:setOn(true)
  end
end

function onMiniWindowClose()
  minimapButton:setOn(false)
end

function preload()
  loadMap(false)
  preloaded = true
end

function online()
  loadMap(not preloaded)
  updateCameraPosition()
end

function offline()
  saveMap()
end

local function loadCompositions()
    g_minimap.loadImage('map', {x = 0, y = 0, z = 7}, 0.5)

    for _, composition in pairs(MAP_COMPOSITIONS) do
        local flag = g_ui.createWidget('MinimapFlag')
        minimapWidget:insertChild(1, flag)
        flag.pos = composition.position
        flag:setText(composition.text)
        flag:setFont("sans-bold-16px")
        flag:setTextAutoResize(true)
        flag:setVisible(false)
        minimapWidget:centerInPosition(flag, flag.pos)
        COMPOSITIONS[#COMPOSITIONS + 1] = flag
    end
end

function loadMap(clean)
  local clientVersion = g_game.getClientVersion()

  if clean then
    g_minimap.clean()
  end

  if otmm then
    local minimapFile = '/minimap.otmm'
    if g_resources.fileExists(minimapFile) then
      g_minimap.loadOtmm(minimapFile)
    end
  else
    local minimapFile = '/minimap_' .. clientVersion .. '.otcm'
    if g_resources.fileExists(minimapFile) then
      g_map.loadOtcm(minimapFile)
    end
  end
  loadCompositions()
  removeGuides()
  if (guideEnabled) then
    addGuides()
  end
  minimapWidget:load()
end

function saveMap()
  local clientVersion = g_game.getClientVersion()
  if otmm then
    local minimapFile = '/minimap.otmm'
    g_minimap.saveOtmm(minimapFile)
  else
    local minimapFile = '/minimap_' .. clientVersion .. '.otcm'
    g_map.saveOtcm(minimapFile)
  end
  minimapWidget:save()
end

function updateCameraPosition()
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  if not minimapWidget:isDragging() then
    if not fullmapView then
      minimapWidget:setCameraPosition(player:getPosition())
    end
    minimapWidget:setCrossPosition(player:getPosition())
  end
  local posLabel = minimapWindow:recursiveGetChildById('posLabel')
  if posLabel then posLabel:setText(pos.x .. ', ' .. pos.y .. ', ' .. pos.z) end
  local floorLabel = minimapWindow:recursiveGetChildById('floorLabel')
  if floorLabel then floorLabel:setText(floorText(pos.z)) end
  updateRoute(pos)
  local cityLabel = minimapWindow:recursiveGetChildById('cityLabel')
  local gps = routeInfo()
  if cityLabel and gps then
    cityLabel:setText(gps)
    cityLabel:setColor(route.straight and '#f2c400' or '#39d353')
  elseif cityLabel and not route then
    local city = cityAt(pos)
    cityLabel:setText(city or 'Rota')
    cityLabel:setColor(city and '#f2c400' or '#6f86a8')
  end
end

function toggleFullMap()
  if not fullmapView then
    fullmapView = true
    minimapWidget:setColor('#000000AA')
    minimapWindow:hide()
    minimapWidget:setParent(modules.game_interface.getRootPanel())
    minimapWidget:fill('parent')
    minimapWidget:setAlternativeWidgetsVisible(true)
  else
    fullmapView = false
    minimapWidget:setColor('#1F007A')
    minimapWidget:setParent(minimapWindow:getChildById('contentsPanel'))
    minimapWidget:fill('parent')
    minimapWindow:show()
    minimapWidget:setAlternativeWidgetsVisible(false)
	local player = g_game.getLocalPlayer()
  end

  local zoom = oldZoom or 0
  local pos = oldPos or minimapWidget:getCameraPosition()
  oldZoom = minimapWidget:getZoom()
  oldPos = minimapWidget:getCameraPosition()
  minimapWidget:setZoom(zoom)
  minimapWidget:setCameraPosition(pos)
  player = g_game.getLocalPlayer()  
end