-- ============================================================
-- NOMES NO MAPA (cliente) - opcode 86
-- Desliga o nome nativo e desenha um nome novo em cima de cada
-- criatura, acompanhando o passo (sem pular de sqm em sqm):
--   Pokemon: [sexo] Nome  Lv 39  +4     (acima da barra de vida)
--            Tipo  * * * * *  Shiny     (abaixo da barra de vida)
--   Jogador/NPC: nome igual ao nativo (cor da vida) + titulo do grupo.
-- A barra de vida continua sendo a nativa. Nao envia nada ao servidor.
-- ============================================================

local OPCODE = 86
local IMG = '/modules/game_pokeinfo/images/'

-- ajuste fino (pixels na tela, a partir do ponto da barra de vida nativa)
-- pokemon: o bloco fica logo ACIMA da cabeca (nao cobre o sprite)
HEAD_GAP = 4          -- espaco entre o topo do sprite e a barra
POKE_CHIPS_UP = 18    -- tipos: acima da barra
POKE_NAME_UP = 35     -- nome: acima da barra
BAR_Y = 0             -- barra de jogador/NPC (mesmo lugar da nativa)
PLAYER_NAME_Y = -15   -- nome de jogador/NPC
TITLE_GAP = 13        -- titulo (Administrador) acima do nome
SHOW_CAPTURED = true  -- tipos/estrelas tambem nos pokemons dos jogadores
SHOW_STARS = true     -- estrelas depois dos tipos
USE_TYPE_IMAGES = false -- true = usa images/types/<tipo>.png no lugar da pilula
CHIP_HEIGHT = 15      -- altura da pilula do tipo
CHIP_TEXT_Y = 0       -- sobe (-1) ou desce (1) o texto dentro da pilula
POKE_BAR_WIDTH = 46
PLAYER_BAR_WIDTH = 30
POKE_NAME_COLOR = '#ffffff'
LEVEL_COLOR = '#1a1200'   -- texto do selo de level
LEVEL_BG = '#f2c400'      -- cor do selo de level
TITLE_COLOR = '#ff6a3c'

local TYPE_PT = {
  bug = 'INSETO', dark = 'SOMBRIO', dragon = 'DRAGAO', electric = 'ELETRICO', fairy = 'FADA', fighting = 'LUTADOR',
  fire = 'FOGO', flying = 'VOADOR', ghost = 'FANTASMA', grass = 'PLANTA', ground = 'TERRA', ice = 'GELO',
  normal = 'NORMAL', poison = 'VENENO', psychic = 'PSIQUICO', rock = 'PEDRA', steel = 'ACO', water = 'AGUA',
}
local TYPE_COLOR = {
  bug = '#8fae1b', dark = '#5a4a40', dragon = '#5b3fd6', electric = '#f2c400', fairy = '#e86fb0', fighting = '#c0392b',
  fire = '#e8742a', flying = '#5e8de0', ghost = '#6a4fa0', grass = '#3fa53b', ground = '#c49a4a', ice = '#5fc7d6',
  normal = '#8f8f7a', poison = '#9a3fa0', psychic = '#e0457a', rock = '#a8903a', steel = '#5f8fb0', water = '#3a7be0',
}
-- tipos claros usam texto escuro
local TYPE_DARK_TEXT = { electric = true, ice = true }

local GENDER_ICON = { M = 'g_male', F = 'g_female', N = 'g_none' }

-- visual por grupo (vale o primeiro que o pokemon tiver):
-- icon = icone antes do nome (nil = sexo), name = cor do nome, bar = cor da barra de vida
NAME_STYLES = {
  { key = 'Perfeito', icon = 'perfect', name = '#ffe680', bar = '#f2c400' },
  { key = 'Lendario', icon = 'crown',   name = '#ffffff', bar = '#f2c400' },
  { key = 'Mega',     icon = nil,       name = '#ffffff', bar = '#a35cff' },
  { key = 'Shiny',    icon = 'shiny',   name = '#ffffff', bar = '#ff6ad5' },
  { key = 'Tera',     icon = nil,       name = '#ffffff', bar = '#3fd8ff' },
}

local info = {}       -- [cid] = dados do servidor (pokemon)
local titles = {}     -- [cid] = titulo do jogador
local tags = {}       -- [cid] = { key, name, line, title, plain }
local dispCache = {}
local loopEvent = nil
local pendingParts = {}
local localSpot = nil       -- onde fica o jogador local na tela (parado)
local localPos = nil
local localMoved = 0
local debugOn = false
local debugMarks = {}
local debugNext = 0

-- ------------------------------------------------------------
-- utilidades
-- ------------------------------------------------------------
local function joinParts(buffer)
  local index, total, rest = buffer:match('^@P|(%d+)|(%d+)\n(.*)$')
  if not index then return buffer end
  index, total = tonumber(index), tonumber(total)
  if index == 1 then pendingParts = {} end
  pendingParts[index] = rest
  if index < total then return nil end
  local full = table.concat(pendingParts, '\n', 1, total)
  pendingParts = {}
  return full
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do fields[#fields + 1] = field end
  return fields
end

local function mapPanel()
  local gi = modules.game_interface
  return gi and gi.getMapPanel and gi.getMapPanel() or nil
end

-- mesma cor do nome nativo (pela vida)
local function healthColor(p)
  if p > 92 then return '#00bc00' end
  if p > 60 then return '#50a150' end
  if p > 30 then return '#a1a100' end
  if p > 8 then return '#bf0a0a' end
  if p > 3 then return '#910f0f' end
  return '#850c0c'
end

local function displacement(creature)
  local outfit = creature:getOutfit()
  local lookType = outfit and outfit.type or 0
  local cached = dispCache[lookType]
  if not cached then
    cached = { 0, 0 }
    pcall(function()
      local thing = g_things.getThingType(lookType, ThingCategoryCreature or 1)
      if thing then cached = { thing:getDisplacementX(), thing:getDisplacementY() } end
    end)
    dispCache[lookType] = cached
  end
  return cached[1], cached[2]
end

-- altura real do desenho (sem a parte vazia), por outfit
local heightCache = {}
local function spriteHeight(creature)
  local outfit = creature:getOutfit()
  local lookType = outfit and outfit.type or 0
  local h = heightCache[lookType]
  if not h then
    h = 32
    pcall(function()
      local thing = g_things.getThingType(lookType, ThingCategoryCreature or 1)
      if thing then
        local exact = thing:getExactSize(0, 2, 0, 0, 0)
        if exact and exact > 0 then h = math.min(exact, thing:getHeight() * 32) end
      end
    end)
    heightCache[lookType] = h
  end
  return h
end

-- deslocamento do passo. O getStepProgress do seu cliente nao anda (fica
-- em 0), entao medimos o passo aqui: quando a posicao muda, o nome sai do
-- sqm antigo e chega no novo durante a duracao do passo.
local moves = {}   -- [cid] = { x, y, z, t0, sx, sy, dur, last }
local function stepDuration(creature)
  -- mesma duracao que o cliente usa na animacao do passo (sem fator diagonal)
  local ok, d = pcall(function() return creature:getStepDuration(true, 8) end)
  d = ok and tonumber(d) or nil
  if not d or d < 50 or d > 3000 then d = 400 end
  return d
end

local function walkOffset(creature, pos)
  local cid = creature:getId()
  local now = g_clock.millis()
  local m = moves[cid]
  if not m then
    moves[cid] = { x = pos.x, y = pos.y, z = pos.z, t0 = 0, sx = 0, sy = 0, dur = stepDuration(creature) }
    return 0, 0
  end
  if m.x ~= pos.x or m.y ~= pos.y or m.z ~= pos.z then
    local sx, sy = pos.x - m.x, pos.y - m.y
    if m.z == pos.z and math.abs(sx) <= 1 and math.abs(sy) <= 1 then
      -- andando sem parar, o tempo entre um passo e outro e a duracao real do passo
      m.sx, m.sy, m.t0, m.dur = sx, sy, now, stepDuration(creature)
    else
      m.sx, m.sy, m.t0 = 0, 0, 0 -- teleporte/troca de andar: sem animacao
    end
    m.x, m.y, m.z = pos.x, pos.y, pos.z
  end
  if m.t0 == 0 then return 0, 0 end
  local progress = (now - m.t0) / m.dur
  if progress >= 1 then
    m.t0 = 0
    return 0, 0
  end
  local left = math.floor(32 * (1 - progress))
  return -m.sx * left, -m.sy * left
end

-- tamanho do sqm na tela e origem do sqm central (testando o mapa)
local function calibrate(map)
  local rect = map:getRect()
  if not rect or rect.width <= 0 then return nil end
  local c = { x = rect.x + math.floor(rect.width / 2), y = rect.y + math.floor(rect.height / 2) }
  local p = map:getPosition(c)
  if not p then return nil end
  local function edge(axis, dir)
    local pt = { x = c.x, y = c.y }
    for _ = 1, 256 do
      pt[axis] = pt[axis] + dir
      local q = map:getPosition(pt)
      if not q or q[axis] ~= p[axis] then return pt[axis] - dir end
    end
    return pt[axis]
  end
  local x0, x1 = edge('x', -1), edge('x', 1)
  local y0, y1 = edge('y', -1), edge('y', 1)
  return { pos = p, x0 = x0, y0 = y0, tw = math.max(1, x1 - x0 + 1), th = math.max(1, y1 - y0 + 1), rect = rect }
end

local function namesWanted()
  local ok, value = pcall(function() return modules.client_options.getOption('displayNames') end)
  if ok and value == false then return false end
  return true
end

-- ------------------------------------------------------------
-- widgets
-- ------------------------------------------------------------
local function destroyTag(cid)
  local t = tags[cid]
  if not t then return end
  for _, key in ipairs({ 'name', 'line', 'title', 'bar' }) do
    if t[key] then t[key]:destroy() end
  end
  tags[cid] = nil
end

local function word(parent, text, color, style)
  local w = g_ui.createWidget(style or 'NameWord', parent)
  w:setText(text)
  w:setColor(color)
  return w
end

local function icon(parent, image, size)
  local w = g_ui.createWidget('UIWidget', parent)
  w:setSize({ width = size, height = size })
  w:setPhantom(true)
  w:setImageSource(IMG .. image)
  return w
end

local function chip(parent, race)
  -- etiqueta pronta (imagem) do tipo; sem imagem, usa a pilula com texto
  local path = IMG .. 'types/' .. race .. '.png'
  if USE_TYPE_IMAGES and g_resources.fileExists(path) then
    local c = g_ui.createWidget('TypeBadge', parent)
    c:setImageSource(path)
    return c
  end
  local c = g_ui.createWidget('TypeChip', parent)
  c:setText(TYPE_PT[race] or race:upper())
  c:setImageColor(TYPE_COLOR[race] or '#6f86a8')
  c:setColor(TYPE_DARK_TEXT[race] and '#1a1200' or '#ffffff')
  -- altura fixa depois do auto-resize: texto centralizado na pilula
  c:setHeight(CHIP_HEIGHT)
  if CHIP_TEXT_Y ~= 0 then pcall(function() c:setTextOffset({ x = 0, y = CHIP_TEXT_Y }) end) end
  return c
end

local function makeBar(map)
  return g_ui.createWidget('NameBar', map)
end

local function buildTag(map, creature, cid, key)
  destroyTag(cid)
  local t = { key = key }
  local name = creature:getName()
  local data = info[cid]
  if data and (data.kind ~= 'C' or SHOW_CAPTURED) then
    local base, level, rest = name:match('^(.-) %[(.-)%](.*)$')
    base = base or name
    level = level and level:gsub('%D', '') or ''
    local boost = data.boost > 0 and data.boost or tonumber((rest or ''):match('%+(%d+)'))

    -- grupo (Perfeito vem do IV 100%; Mega/Shiny tambem pelo nome da forma)
    local has = {}
    for tagName in (data.tags or ''):gmatch('[^,]+') do has[tagName] = true end
    if data.pct >= 100 then has.Perfeito = true end
    if base:find('^Mega ') then has.Mega = true end
    if base:find('^Shiny ') then has.Shiny = true end
    local style
    for _, st in ipairs(NAME_STYLES) do
      if has[st.key] then style = st break end
    end

    -- linha 1: icone + nome + level (+boost)
    t.name = g_ui.createWidget('NameLine', map)
    icon(t.name, (style and style.icon) or GENDER_ICON[data.gender] or 'g_none', 13)
    word(t.name, base, style and style.name or POKE_NAME_COLOR)
    if level ~= '' then
      local lv = g_ui.createWidget('LevelChip', t.name)
      lv:setText('Lv ' .. level)
      lv:setImageColor(LEVEL_BG)
      lv:setColor(LEVEL_COLOR)
      lv:setHeight(13)
    end
    if boost and boost > 0 then word(t.name, '+' .. boost, LEVEL_COLOR) end

    -- linha 2: tipos em pilula + estrelas
    t.line = g_ui.createWidget('NameLine', map)
    if data.t1 and TYPE_PT[data.t1] then chip(t.line, data.t1) end
    if data.t2 and TYPE_PT[data.t2] then chip(t.line, data.t2) end
    if SHOW_STARS and data.pct >= 0 then -- sem lupa o servidor nao manda (pct = -1)
      local perfect = data.pct >= 100
      for i = 1, 5 do
        local star = g_ui.createWidget('NameStar', t.line)
        if i <= data.stars then star:setImageSource(IMG .. (perfect and 'star_perfect' or 'star')) end
      end
    end

    -- barra de vida: cor do grupo ou do tipo principal
    t.bar = makeBar(map)
    t.barColor = (style and style.bar) or TYPE_COLOR[data.t1] or '#5fd35f'
    t.barWidth = POKE_BAR_WIDTH
    t.poke = true
  else
    t.name = g_ui.createWidget('NameLine', map)
    t.plain = word(t.name, name, healthColor(creature:getHealthPercent()))
    t.bar = makeBar(map)
    t.barWidth = PLAYER_BAR_WIDTH
  end
  if titles[cid] then
    t.title = g_ui.createWidget('NameLine', map)
    word(t.title, titles[cid], TITLE_COLOR)
  end
  tags[cid] = t
  return t
end

-- largura da linha = soma dos filhos (o layout so posiciona)
local function fitWidth(widget, padX)
  local w, n, right = 0, 0, nil
  local left = widget:getX()
  for _, child in ipairs(widget:getChildren()) do
    if child:isVisible() then
      w = w + child:getWidth()
      n = n + 1
      local r = child:getX() + child:getWidth() - left
      if not right or r > right then right = r end
    end
  end
  w = w + math.max(0, n - 1) * 3 + (padX or 0)
  -- depois que o layout posicionou os filhos, a borda do ultimo e a largura real
  if right and right > 0 and right <= w + 40 then w = right + math.floor((padX or 0) / 2) end
  if widget:getWidth() ~= w then widget:setWidth(w) end
  return w
end

local function place(widget, x, y, rect, padX)
  if not widget then return end
  local w, h = fitWidth(widget, padX), widget:getHeight()
  local px, py = math.floor(x - w / 2), math.floor(y)
  local inside = px + w > rect.x and px < rect.x + rect.width and py + h > rect.y and py < rect.y + rect.height
  widget:setVisible(inside)
  if inside then widget:setPosition({ x = px, y = py }) end
end

local function barsWanted()
  local ok, value = pcall(function() return modules.client_options.getOption('displayHealth') end)
  if ok and value == false then return false end
  return true
end

local function placeBar(t, x, y, rect, percent)
  local bar = t.bar
  if not bar then return end
  local w = t.barWidth or 30
  if bar:getWidth() ~= w then bar:setWidth(w) end
  local px, py = math.floor(x - w / 2), math.floor(y)
  local inside = px + w > rect.x and px < rect.x + rect.width and py + 5 > rect.y and py < rect.y + rect.height
  bar:setVisible(inside and barsWanted())
  if not inside then return end
  bar:setPosition({ x = px, y = py })
  local fill = bar:getChildById('fill')
  fill:setWidth(math.max(0, math.floor((w - 2) * percent / 100)))
  fill:setBackgroundColor(t.barColor or healthColor(percent))
end

local function hideAll()
  for cid in pairs(tags) do destroyTag(cid) end
  for cid, mark in pairs(debugMarks) do mark.label:destroy() mark:destroy() debugMarks[cid] = nil end
end

-- ------------------------------------------------------------
-- diagnostico (Ctrl+Alt+D): ponto vermelho onde o modulo acha que fica
-- a barra de vida + valores no terminal do cliente (1x por segundo)
-- ------------------------------------------------------------
local function debugMark(map, cid, x, y, text)
  local mark = debugMarks[cid]
  if not mark then
    mark = g_ui.createWidget('UIWidget', map)
    mark:setSize({ width = 5, height = 5 })
    mark:setBackgroundColor('#ff0000')
    mark:setPhantom(true)
    local label = g_ui.createWidget('NameWord', map)
    label:setColor('#ffff00')
    label:setBackgroundColor('#000000c0')
    mark.label = label
    debugMarks[cid] = mark
  end
  mark:setPosition({ x = math.floor(x) - 2, y = math.floor(y) - 2 })
  mark:setVisible(true)
  mark.label:setText(text)
  mark.label:setPosition({ x = math.floor(x) - 2, y = math.floor(y) + 30 })
end

local function toggleDebug()
  debugOn = not debugOn
  if not debugOn then
    for cid, mark in pairs(debugMarks) do mark.label:destroy() mark:destroy() debugMarks[cid] = nil end
  end
  modules.game_textmessage.displayStatusMessage('Diagnostico dos nomes: ' .. (debugOn and 'ligado (veja o terminal)' or 'desligado'))
end

-- ------------------------------------------------------------
-- quadro a quadro
-- ------------------------------------------------------------
local function update()
  local map = mapPanel()
  if not map or not g_game.isOnline() then return end
  if not namesWanted() then
    -- jogador desligou os nomes: volta tudo para o nativo
    hideAll()
    if map:isDrawingHealthBars() ~= barsWanted() then map:setDrawHealthBars(barsWanted()) end
    return
  end
  if map:isDrawingNames() then map:setDrawNames(false) end
  if map:isDrawingHealthBars() then map:setDrawHealthBars(false) end
  local cal = calibrate(map)
  if not cal then return end
  local k = cal.tw / 32
  local seen = {}
  local camera = map:getCameraPosition() or cal.pos
  local specs = g_map.getSpectators(camera, false) or {}
  for _, creature in ipairs(specs) do
    local pos = creature:getPosition()
    local cid = creature:getId()
    if pos and pos.z == cal.pos.z and not creature:isDead() and creature:getHealthPercent() > 0 and creature:canBeSeen() then
      seen[cid] = true
      local data = info[cid]
      local key = creature:getName() .. '|' .. (data and data.sig or '') .. '|' .. (titles[cid] or '')
      local t = tags[cid]
      if not t or t.key ~= key then t = buildTag(map, creature, cid, key) end
      if t.plain then t.plain:setColor(healthColor(creature:getHealthPercent())) end
      local dx, dy = displacement(creature)
      local wx, wy = 0, 0
      local isLocal = creature:isLocalPlayer()
      if not isLocal then wx, wy = walkOffset(creature, pos) end
      local tileX = cal.x0 + (pos.x - cal.pos.x) * cal.tw
      local tileY = cal.y0 + (pos.y - cal.pos.y) * cal.th
      local px = tileX + (16 - dx + wx) * k
      local py = tileY + (-dy - 2 + wy) * k
      if isLocal then
        -- a camera acompanha o jogador: parado, guarda o ponto; andando, usa o ponto guardado
        local now = g_clock.millis()
        if not localPos or localPos.x ~= pos.x or localPos.y ~= pos.y or localPos.z ~= pos.z then
          localPos = { x = pos.x, y = pos.y, z = pos.z }
          localMoved = now
        end
        local r = cal.rect
        if now - localMoved > 600 and not creature:isWalking() then
          localSpot = { x = px - r.x, y = py - r.y, w = r.width, h = r.height }
        elseif localSpot and localSpot.w == r.width and localSpot.h == r.height then
          px, py = r.x + localSpot.x, r.y + localSpot.y
        end
      end
      if t.poke then
        -- topo do desenho: base do sqm (menos o deslocamento) menos a altura do sprite
        local bottom = tileY + (32 - dy + wy) * k
        local barY = math.floor(bottom - spriteHeight(creature) * k - HEAD_GAP - 5)
        place(t.name, px, barY - POKE_NAME_UP, cal.rect)
        place(t.line, px, barY - POKE_CHIPS_UP, cal.rect)
        placeBar(t, px, barY, cal.rect, creature:getHealthPercent())
      else
        local nameY = py + PLAYER_NAME_Y
        place(t.name, px, nameY, cal.rect)
        place(t.title, px, nameY - TITLE_GAP, cal.rect)
        placeBar(t, px, py + BAR_Y, cal.rect, creature:getHealthPercent())
      end
      if debugOn then
        local vis = map:getVisibleDimension() or {}
        debugMark(map, cid, px, py, string.format('d%d,%d k%.2f t%d,%d c%d,%d p%d,%d w%d,%d v%sx%s r%d,%d,%d',
          dx, dy, k, cal.tw, cal.th, pos.x - cal.pos.x, pos.y - cal.pos.y, math.floor(px), math.floor(py), wx, wy,
          tostring(vis.width), tostring(vis.height), cal.rect.x, cal.rect.width, cal.x0))
        if g_clock.millis() >= debugNext then
          local okP, prog = pcall(function() return creature:getStepProgress() end)
          local outfit = creature:getOutfit() or {}
          g_logger.info(string.format('[nomes] %s pos=%d,%d cal=%d,%d x0=%d y0=%d tw=%d th=%d k=%.2f look=%s dx=%d dy=%d walk=%s dir=%s prog=%s wo=%d,%d p=%d,%d rect=%d,%d,%d,%d',
            creature:getName(), pos.x, pos.y, cal.pos.x, cal.pos.y, cal.x0, cal.y0, cal.tw, cal.th, k, tostring(outfit.type), dx, dy,
            tostring(creature:isWalking()), tostring(creature:getDirection()), tostring(okP and prog), wx, wy, px, py,
            cal.rect.x, cal.rect.y, cal.rect.width, cal.rect.height))
        end
      end
    end
  end
  for cid in pairs(tags) do
    if not seen[cid] then destroyTag(cid) end
  end
  for cid in pairs(moves) do
    if not seen[cid] then moves[cid] = nil end
  end
  for cid, mark in pairs(debugMarks) do
    if not seen[cid] then mark.label:destroy() mark:destroy() debugMarks[cid] = nil end
  end
  if debugOn and g_clock.millis() >= debugNext then debugNext = g_clock.millis() + 1000 end
end

local function startLoop()
  if not loopEvent then loopEvent = cycleEvent(update, 16) end
end

local function stopLoop()
  if loopEvent then
    removeEvent(loopEvent)
    loopEvent = nil
  end
end

-- ------------------------------------------------------------
-- servidor
-- ------------------------------------------------------------
-- ------------------------------------------------------------
-- lupa: icone com o tempo no canto do mapa
-- ------------------------------------------------------------
local lensBox = nil
local lensLeft = 0
local lensEvent = nil

local function lensTick()
  lensEvent = nil
  if not lensBox then return end
  if lensLeft <= 0 then
    lensBox:destroy()
    lensBox = nil
    return
  end
  local timeLabel = lensBox:getChildById('time')
  timeLabel:setText(string.format('%d:%02d', math.floor(lensLeft / 60), lensLeft % 60))
  timeLabel:setColor(lensLeft <= 10 and (lensLeft % 2 == 0 and '#e04848' or '#ffffff') or '#f2c400')
  lensLeft = lensLeft - 1
  lensEvent = scheduleEvent(lensTick, 1000)
end

local function showLens(seconds, clientId)
  lensLeft = math.max(0, math.floor(tonumber(seconds) or 0))
  if lensEvent then removeEvent(lensEvent) lensEvent = nil end
  if lensLeft <= 0 then
    if lensBox then lensBox:destroy() lensBox = nil end
    return
  end
  local map = mapPanel()
  if not map then return end
  if not lensBox then lensBox = g_ui.createWidget('LensBox', map) end
  local item = lensBox:getChildById('item')
  local icon = lensBox:getChildById('icon')
  clientId = tonumber(clientId) or 0
  item:setVisible(clientId > 0)
  icon:setVisible(clientId <= 0)
  if clientId > 0 then item:setItemId(clientId) end
  lensBox:setTooltip('Lupa ativa: voce ve as estrelas (IV) dos pokemons.')
  lensTick()
end

local function onInfo(protocol, opcode, buffer)
  buffer = joinParts(buffer or '')
  if not buffer then return end
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    local cid = tonumber(f[2])
    if f[1] == 'S' and cid then
      info[cid] = { gender = f[3], t1 = f[4], t2 = f[5] ~= '' and f[5] or nil, stars = tonumber(f[6]) or 1,
        pct = tonumber(f[7]) or 0, boost = tonumber(f[8]) or 0, kind = f[9], tags = f[10] or '',
        sig = table.concat(f, ',', 3) }
    elseif f[1] == 'L' then
      showLens(f[2], f[3])
    elseif f[1] == 'T' and cid then
      titles[cid] = f[3]
    elseif f[1] == 'R' and cid then
      info[cid] = nil
      titles[cid] = nil
    end
  end
end

local function onGameStart()
  startLoop()
end

local function onGameEnd()
  showLens(0)
  stopLoop()
  hideAll()
  info, titles = {}, {}
end

function init()
  g_ui.importStyle('pokeinfo')
  ProtocolGame.registerExtendedOpcode(OPCODE, onInfo)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then startLoop() end
  g_keyboard.bindKeyDown('Ctrl+Alt+D', toggleDebug)
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  g_keyboard.unbindKeyDown('Ctrl+Alt+D')
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  stopLoop()
  hideAll()
  showLens(0)
  local map = mapPanel()
  if map then
    map:setDrawNames(namesWanted())
    map:setDrawHealthBars(barsWanted())
  end
end
