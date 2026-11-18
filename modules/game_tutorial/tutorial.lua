-- ============================================================
-- GUIA CODEX - todos os sistemas do servidor, dentro do cliente
--   Botao "Guia" no topo ou Ctrl+Shift+H.
--   Conteudo: guia_conteudo.lua (GUIA_CODEX).
--   Imagens opcionais: coloque imgs/paginas/<id da pagina>.png
--   (ex.: imgs/paginas/tera.png) e ela aparece na pagina sozinha.
-- ============================================================
local HOTKEY = 'Ctrl+Shift+H'
local OPEN_ON_FIRST_LOGIN = false    -- (a Jornada do Treinador abre no 1o login no lugar do Guia)
local SETTINGS_KEY = 'codexGuia'
local IMG_DIR = '/modules/game_tutorial/imgs/paginas/'
local IMG_HEIGHT = 150

local window, button
local list, searchEdit
local flat = {}        -- paginas visiveis na ordem da lista
local current = nil    -- indice em flat
local rowsById = {}

-- ---------------- utilidades ----------------
local function lower(s) return tostring(s or ''):lower() end

local function lookOf(name)
  local n = lower(name)
  local mod = modules.game_pokelooks
  local data = mod and mod.CODEX_LOOKS_DATA
  local d = data and data[n]
  if d then return {type = d[1], head = d[2], body = d[3], legs = d[4], feet = d[5]} end
  local bar = modules.game_pokemonbar
  if bar and bar.getLook then
    local ok, o = pcall(bar.getLook, n)
    if ok and type(o) == 'table' then return o end
  end
  return nil
end

local function fileExists(path)
  local ok, r = pcall(function() return g_resources.fileExists(path) end)
  return ok and r
end

-- ---------------- pagina ----------------
local function fillVisuals(page)
  local box = window:getChildById('visuals')
  box:destroyChildren()
  local count = 0
  for _, cid in ipairs(page.items or {}) do
    local w = g_ui.createWidget('UIItem', box)
    w:setSize({width = 48, height = 48})
    w:setVirtual(true)
    pcall(function() w:setItemId(cid) end)
    if page.itemNames and page.itemNames[_] then w:setTooltip(page.itemNames[_]) end
    count = count + 1
  end
  for _, name in ipairs(page.pokes or {}) do
    local o = lookOf(name)
    if o then
      local w = g_ui.createWidget('UICreature', box)
      w:setSize({width = 64, height = 64})
      pcall(function() w:setOutfit(o) end)
      w:setTooltip((name:gsub('^%l', string.upper)))
      count = count + 1
    end
  end
  box:setHeight(count > 0 and 76 or 0)
  box:setVisible(count > 0)
  box:setMarginTop(count > 0 and 6 or 0)
end

local function fillImage(page)
  local img = window:getChildById('pageImage')
  local path = IMG_DIR .. tostring(page.id)
  if fileExists(path .. '.png') then
    img:setImageSource(path)
    img:setHeight(IMG_HEIGHT)
    img:setMarginTop(6)
    img:setVisible(true)
  else
    img:setHeight(0)
    img:setMarginTop(0)
    img:setVisible(false)
  end
end

local function showPage(index)
  local page = flat[index]
  if not page then return end
  current = index
  window:getChildById('pageTitle'):setText(page.title)
  window:getChildById('pageCat'):setText(page.cat)
  window:recursiveGetChildById('pageText'):setText(page.text)
  fillVisuals(page)
  fillImage(page)
  local scroll = window:getChildById('textScroll')
  if scroll then scroll:setValue(0) end
  window:getChildById('pageCount'):setText(index .. ' / ' .. #flat)
  window:getChildById('prevButton'):setEnabled(index > 1)
  window:getChildById('nextButton'):setEnabled(index < #flat)
  local row = rowsById[page.id]
  if row and list:getFocusedChild() ~= row then
    list:focusChild(row)
    pcall(function() list:ensureChildVisible(row) end)
  end
  g_settings.set(SETTINGS_KEY .. 'Last', page.id)
end

local function matches(page, words)
  if #words == 0 then return true end
  local hay = lower(page.title .. ' ' .. page.cat .. ' ' .. page.text)
  for _, w in ipairs(words) do
    if not hay:find(w, 1, true) then return false end
  end
  return true
end

local function buildList()
  list:destroyChildren()
  flat, rowsById = {}, {}
  local words = {}
  for w in lower(searchEdit:getText()):gmatch('%S+') do words[#words + 1] = w end
  for _, cat in ipairs(GUIA_CODEX or {}) do
    local header = nil
    for _, page in ipairs(cat.pages) do
      page.cat = cat.name
      if matches(page, words) then
        if not header then
          header = g_ui.createWidget('GuiaCat', list)
          header:setText(cat.name)
        end
        local row = g_ui.createWidget('GuiaRow', list)
        row:setText(page.title)
        row.guiaIndex = #flat + 1
        flat[#flat + 1] = page
        rowsById[page.id] = row
      end
    end
  end
  if #flat == 0 then
    local none = g_ui.createWidget('GuiaCat', list)
    none:setText('Nada encontrado')
  end
end

local function onFocus(widget, focused)
  if focused and focused.guiaIndex and focused.guiaIndex ~= current then
    showPage(focused.guiaIndex)
  end
end

-- ---------------- publico ----------------
function step(delta)
  if not current then return end
  local n = current + delta
  if n >= 1 and n <= #flat then showPage(n) end
end

function openPage(id)
  if not window then return end
  for i, p in ipairs(flat) do
    if p.id == id then showPage(i) return true end
  end
  return false
end

function show(pageId)
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  if pageId and openPage(pageId) then return end
  if not current then
    local last = g_settings.getString(SETTINGS_KEY .. 'Last')
    if not (last ~= '' and openPage(last)) then showPage(1) end
  end
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

local function onSearch()
  current = nil
  buildList()
  if #flat > 0 then showPage(1) end
end

local function onGameStart()
  if not OPEN_ON_FIRST_LOGIN then return end
  local char = g_game.getCharacterName and g_game.getCharacterName() or ''
  local key = SETTINGS_KEY .. 'Visto_' .. tostring(char)
  if not g_settings.getBoolean(key) then
    g_settings.set(key, true)
    scheduleEvent(function() if g_game.isOnline() then show('bemvindo') end end, 1500)
  end
end

function init()
  window = g_ui.displayUI('tutorial')
  window:hide()
  list = window:getChildById('pageList')
  searchEdit = window:getChildById('searchEdit')
  searchEdit.onTextChange = onSearch
  connect(list, {onChildFocusChange = onFocus})
  g_keyboard.bindKeyPress('Up', function() step(-1) end, window)
  g_keyboard.bindKeyPress('Down', function() step(1) end, window)
  buildList()

  if modules.client_topmenu and modules.client_topmenu.addRightGameButton then
    button = modules.client_topmenu.addRightGameButton('codexGuideButton', 'Guia do servidor (' .. HOTKEY .. ')', 'imgs/guia', toggle)
  end
  g_keyboard.bindKeyDown(HOTKEY, toggle)
  connect(g_game, {onGameStart = onGameStart, onGameEnd = hide})
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, {onGameStart = onGameStart, onGameEnd = hide})
  g_keyboard.unbindKeyDown(HOTKEY)
  if list then disconnect(list, {onChildFocusChange = onFocus}) end
  if button then button:destroy() button = nil end
  if window then window:destroy() window = nil end
end
