-- ============================================================
-- CODEX - SPRITES DOS POKEMONS EM TODAS AS JANELAS (opcode 127)
-- Toda janela que mostra a foto .png do pokemon
-- (/modules/game_pokemonbar/bar_icon/<nome>.png) passa a mostrar
-- o sprite do pokemon, igual a barra de pokemons: PC, Forja,
-- Manager, Creche, Correio, Celular, Troca, Gacha...
-- Sem precisar mexer em cada janela. Se o servidor nao tiver o
-- sprite, continua a foto .png.
-- Para desligar: ENABLED = false.
-- ============================================================
local OPCODE = 127
local ENABLED = true
local PREFIX = '^/modules/game_pokemonbar/bar_icon/(.+)%.png$'

local cache = {}      -- nome -> outfit | false (sem sprite)
local waiting = {}    -- nome -> { widgets }
local queue, queued = {}, {}
local flushEvent = nil
local originalSet = nil
local logged = 0
local firstHit = false     -- diagnostico no codex.log (so as primeiras vezes)

local function log(text)
  if logged < 30 then
    logged = logged + 1
    g_logger.info('[PokeLooks] ' .. text)
  end
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function alive(widget)
  return widget and not widget:isDestroyed()
end

local function attach(widget, outfit)
  local creature = widget:getChildById('codexLook')
  if not creature then
    creature = g_ui.createWidget('UICreature', widget)
    creature:setId('codexLook')
    creature:fill('parent')
    creature:setPhantom(true)
  end
  creature:setOutfit(outfit)
  if widget.codexLookSize then -- codex: janela pediu o sprite grande (ex.: retrato do Manager)
    pcall(function() creature:setCreatureSize(widget.codexLookSize); creature:setCenter(true) end)
  end
  creature:setVisible(true)
end

local function detach(widget)
  local creature = widget:getChildById('codexLook')
  if creature then creature:setVisible(false) end
end

local function flush()
  flushEvent = nil
  if #queue == 0 or not g_game.isOnline() then return end
  local chunk = {}
  for _, name in ipairs(queue) do
    chunk[#chunk + 1] = name
    if #chunk >= 40 then
      send('Q|' .. table.concat(chunk, ','))
      chunk = {}
    end
  end
  if #chunk > 0 then send('Q|' .. table.concat(chunk, ',')) end
  log('pedindo ' .. #queue .. ' sprite(s) ao servidor: ' .. table.concat(queue, ', '):sub(1, 120))
  queue = {}
end

local function request(name, widget)
  waiting[name] = waiting[name] or {}
  table.insert(waiting[name], widget)
  if not queued[name] then
    queued[name] = true
    queue[#queue + 1] = name
    if not flushEvent then flushEvent = scheduleEvent(flush, 30) end
  end
end

local function hookedSet(self, path, ...)
  local name = ENABLED and type(path) == 'string' and path:match(PREFIX)
  if name and name ~= '' and not name:find('[,;=|]') then
    self.codexLookName = name
    local outfit = cache[name]
    if outfit == nil and CODEX_LOOKS_DATA then
      local d = CODEX_LOOKS_DATA[name]
      if not d and name:sub(1, 5) == 'mega ' then d = CODEX_LOOKS_DATA[name:sub(6):gsub(' [xy]$', '')] end
      if d then
        outfit = { type = d[1], head = d[2], body = d[3], legs = d[4], feet = d[5] }
        cache[name] = outfit
      end
    end
    if not firstHit then
      firstHit = true
      log('primeira foto trocada: ' .. name .. (outfit and ' (sprite ' .. outfit.type .. ')' or ' (sem sprite na lista, perguntando ao servidor)'))
    end
    if outfit then
      attach(self, outfit)
      return originalSet(self, '', ...)
    end
    detach(self)
    if outfit == nil then cache[name] = false end -- codex looks sem pedido (o anti-bot do cliente bloqueava)
    if g_resources.fileExists(path) then return originalSet(self, path, ...) end
    return originalSet(self, '', ...)
  end
  if self.codexLookName then
    self.codexLookName = nil
    detach(self)
  end
  return originalSet(self, path, ...)
end

local function onLooks(protocol, opcode, buffer)
  local list = tostring(buffer or ''):match('^L|(.*)$')
  if not list then return end
  local got, none = 0, 0
  for entry in (list .. ';'):gmatch('([^;]*);') do
    local name, look = entry:match('^(.-)=(.*)$')
    if name then
      local t, h, b, l, f = look:match('^(%d+),(%d+),(%d+),(%d+),(%d+)$')
      local outfit = t and { type = tonumber(t), head = tonumber(h), body = tonumber(b), legs = tonumber(l), feet = tonumber(f) } or false
      cache[name] = outfit
      if outfit then got = got + 1 else none = none + 1 end
      queued[name] = nil
      for _, widget in ipairs(waiting[name] or {}) do
        if outfit and alive(widget) and widget.codexLookName == name then
          attach(widget, outfit)
          originalSet(widget, '')
        end
      end
      waiting[name] = nil
    end
  end
  log('servidor mandou ' .. got .. ' sprite(s)' .. (none > 0 and (', ' .. none .. ' sem sprite') or ''))
end

local function onGameEnd()
  waiting, queue, queued = {}, {}, {}
end

function init()
  if not originalSet then
    originalSet = UIWidget.setImageSource
    UIWidget.setImageSource = hookedSet
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, onLooks)
  local count = 0
  for _ in pairs(CODEX_LOOKS_DATA or {}) do count = count + 1 end
  g_logger.info('[PokeLooks] ligado: ' .. count .. ' sprites na lista, hook ' .. (UIWidget.setImageSource == hookedSet and 'OK' or 'FALHOU'))
  connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
  if originalSet then
    UIWidget.setImageSource = originalSet
    originalSet = nil
  end
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
end
