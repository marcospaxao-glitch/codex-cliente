-- ============================================================
-- ESPECIALIZACOES (cliente) - opcode 117
-- Abre pelo NPC Mestre das Especializacoes. Tudo e conferido no
-- servidor. So envia opcodes a partir de cliques do jogador.
-- ============================================================

local OPCODE = 117

local window = nil
local espButton = nil
local data = { current = 0, rank = 0, minLevel = 0, level = 0, changeCost = 0, maxRank = 6, bank = 0,
  specs = {}, ranks = {}, reqs = {}, remote = false }
local selected = nil
local armed = false

local function W(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function send(text)
  local protocol = g_game.getProtocolGame()
  if protocol then protocol:sendExtendedOpcode(OPCODE, text) end
end

local function splitFields(line)
  local fields = {}
  for field in (line .. '|'):gmatch('(.-)|') do fields[#fields + 1] = field end
  return fields
end

local function fmt(value)
  local text = tostring(math.floor(tonumber(value) or 0))
  return (text:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', ''))
end

local function status(text, ok)
  local label = W('statusLabel')
  if not label then return end
  label:setText(text or '')
  label:setColor(ok == nil and '#8fa7c4' or (ok and '#5fd35f' or '#e04848'))
end

local function specById(id)
  for _, s in ipairs(data.specs) do if s.id == id then return s end end
  return nil
end

-- ------------------------------------------------------------
-- tela
-- ------------------------------------------------------------
local renderDetail

local function renderList()
  local list = W('specList')
  list:destroyChildren()
  for _, s in ipairs(data.specs) do
    local row = g_ui.createWidget('EspSpecRow', list)
    row:getChildById('icon'):setImageSource('/images/especializacao/' .. s.id)
    row:getChildById('name'):setText(s.name .. (s.id == data.current and ('  (rank ' .. data.rank .. ')') or ''))
    row:getChildById('name'):setColor(s.id == data.current and '#5fd35f' or '#ffffff')
    row:getChildById('types'):setText(s.types)
    row:setOn(selected == s.id)
    row.onClick = function()
      selected = s.id
      armed = false
      renderList()
      renderDetail()
    end
  end
end

renderDetail = function()
  local s = specById(selected)
  if not s then return end
  W('specIcon'):setImageSource('/images/especializacao/' .. s.id .. '_grande')
  W('specName'):setText(s.name)
  W('specTypes'):setText('Tipos: ' .. s.types)
  W('specDesc'):setText(s.desc)
  local reqList = W('reqList')
  reqList:destroyChildren()
  local button = W('actionButton')
  local mine = s.id == data.current
  W('reqTitle'):setText('')
  W('rankInfo'):setText('')

  if mine then
    local r = data.ranks[data.rank] or {}
    W('rankInfo'):setText('Seu rank: ' .. data.rank .. ' - ' .. (r.name or '') .. '   (+' .. (r.atk or 0) .. '% dano, +' .. (r.def or 0) .. '% defesa)')
    if data.rank >= data.maxRank then
      W('reqTitle'):setText('Voce chegou ao rank maximo!')
      button:setText('Rank maximo')
      button:setEnabled(false)
    else
      local nextRank = data.ranks[data.rank + 1] or {}
      W('reqTitle'):setText('PARA O RANK ' .. (data.rank + 1) .. ' - ' .. (nextRank.name or '') .. ' (traga na mochila):')
      local ready = true
      for _, req in ipairs(data.reqs) do
        local row = g_ui.createWidget('EspReqRow', reqList)
        row:getChildById('item'):setItemId(req.clientId)
        row:getChildById('name'):setText(req.name)
        local ok = req.have >= req.need
        if not ok then ready = false end
        row:getChildById('count'):setText(fmt(req.have) .. ' / ' .. fmt(req.need))
        row:getChildById('count'):setColor(ok and '#5fd35f' or '#e04848')
      end
      local gold = nextRank.gold or 0
      if gold > 0 then
        local row = g_ui.createWidget('EspReqRow', reqList)
        row:getChildById('item'):setItemId(0)
        row:getChildById('name'):setText('gp no PokeBank')
        local ok = data.bank >= gold
        if not ok then ready = false end
        row:getChildById('count'):setText(fmt(data.bank) .. ' / ' .. fmt(gold))
        row:getChildById('count'):setColor(ok and '#5fd35f' or '#e04848')
      end
      button:setText(ready and ('Subir para o rank ' .. (data.rank + 1)) or 'Faltam itens')
      button:setEnabled(ready)
      button.onClick = function() send('RANKUP') end
    end
  elseif data.current == 0 then
    local first = data.ranks[1] or {}
    W('reqTitle'):setText('Comeca no rank 1: +' .. (first.atk or 0) .. '% de dano e +' .. (first.def or 0) .. '% de defesa nos tipos.')
    local canJoin = data.level >= data.minLevel
    button:setText(canJoin and ('Entrar para os ' .. s.name) or ('Precisa de level ' .. data.minLevel))
    button:setEnabled(canJoin)
    button.onClick = function()
      if armed then armed = false send('CHOOSE|' .. s.id) return end
      armed = true
      button:setText('Confirmar? (clique de novo)')
      scheduleEvent(function() if armed then armed = false renderDetail() end end, 3000)
    end
  elseif data.remote then
    W('reqTitle'):setText('Para trocar de especializacao, fale com o Mestre das Especializacoes.')
    button:setText('So no NPC')
    button:setEnabled(false)
    button.onClick = nil
  else
    local cur = specById(data.current)
    W('reqTitle'):setText('Trocar custa ' .. fmt(data.changeCost) .. ' gp e voce volta ao rank 1' ..
      (cur and (' (sai dos ' .. cur.name .. ').') or '.'))
    button:setText('Trocar para os ' .. s.name)
    button:setEnabled(data.bank >= data.changeCost)
    button.onClick = function()
      if armed then armed = false send('CHANGE|' .. s.id) return end
      armed = true
      button:setText('Confirmar troca? (perde o rank)')
      scheduleEvent(function() if armed then armed = false renderDetail() end end, 3000)
    end
  end

  local ranks = W('ranksList')
  ranks:destroyChildren()
  for i, r in ipairs(data.ranks) do
    local row = g_ui.createWidget('EspRankRow', ranks)
    row:getChildById('rank'):setText(i .. '. ' .. r.name)
    row:getChildById('bonus'):setText('+' .. r.atk .. '% dano  +' .. r.def .. '% defesa')
    row:getChildById('cost'):setText(r.gold > 0 and (fmt(r.gold) .. ' gp + loot') or 'gratis')
    if mine and i == data.rank then
      row:getChildById('rank'):setColor('#5fd35f')
    end
  end
end

-- ------------------------------------------------------------
-- botao no topo (aparece depois de escolher a especializacao)
-- ------------------------------------------------------------
local function updateButton(id, rank, name)
  if not espButton then return end
  id = tonumber(id) or 0
  if id <= 0 then
    espButton:hide()
    return
  end
  espButton:setIcon('/images/especializacao/' .. id)
  espButton:setTooltip((name and name ~= '' and name or 'Especializacao') .. ' - rank ' .. (tonumber(rank) or 1))
  espButton:show()
end

-- ------------------------------------------------------------
-- servidor
-- ------------------------------------------------------------
local function onEspOpcode(protocol, opcode, buffer)
  if not window then return end
  buffer = buffer or ''
  local head = buffer:match('^([^|\n]*)')
  if head == 'INFO' then
    local f = splitFields(buffer)
    updateButton(f[2], f[3], f[4])
    return
  elseif head == 'CLOSE' then
    window:hide()
    if espButton then espButton:setOn(false) end
    return
  elseif head == 'OK' then
    status(buffer:sub(4), true)
    return
  elseif head == 'ERR' then
    status(buffer:sub(5), false)
    return
  elseif head ~= 'ESP' then
    return
  end
  local fresh = { specs = {}, ranks = {}, reqs = {} }
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    local f = splitFields(line)
    if f[1] == 'ESP' then
      fresh.current, fresh.rank = tonumber(f[2]) or 0, tonumber(f[3]) or 0
      fresh.minLevel, fresh.level = tonumber(f[4]) or 0, tonumber(f[5]) or 0
      fresh.changeCost, fresh.maxRank, fresh.bank = tonumber(f[6]) or 0, tonumber(f[7]) or 6, tonumber(f[8]) or 0
      fresh.remote = f[9] == '1'
    elseif f[1] == 'S' then
      fresh.specs[#fresh.specs + 1] = { id = tonumber(f[2]) or 0, name = f[3] or '?', types = f[4] or '',
        icon = tonumber(f[5]) or 0, desc = f[6] or '' }
    elseif f[1] == 'B' then
      fresh.ranks[tonumber(f[2]) or (#fresh.ranks + 1)] = { name = f[3] or '', atk = tonumber(f[4]) or 0,
        def = tonumber(f[5]) or 0, gold = tonumber(f[6]) or 0 }
    elseif f[1] == 'R' then
      fresh.reqs[#fresh.reqs + 1] = { id = tonumber(f[2]) or 0, clientId = tonumber(f[3]) or 0, name = f[4] or '?',
        need = tonumber(f[5]) or 0, have = tonumber(f[6]) or 0 }
    end
  end
  data = fresh
  if not specById(selected) then
    selected = data.current ~= 0 and data.current or (data.specs[1] and data.specs[1].id)
  end
  local cur = specById(data.current)
  W('currentLabel'):setText(cur and ('Voce: ' .. cur.name .. ' - rank ' .. data.rank) or 'Sem especializacao')
  W('currentLabel'):setColor(cur and '#5fd35f' or '#8fa7c4')
  armed = false
  renderList()
  renderDetail()
  if not window:isVisible() then
    status(data.remote and 'Aberto pelo atalho: voce pode subir de rank daqui.' or 'Escolha uma especializacao para ver os detalhes.', nil)
    window:show()
  end
  if espButton then espButton:setOn(true) end
  window:raise()
  window:focus()
end

-- ------------------------------------------------------------
-- abrir / fechar
-- ------------------------------------------------------------
function hide()
  if window and window:isVisible() then
    window:hide()
    send('CLOSE')
  end
  if espButton then espButton:setOn(false) end
end

-- clique no botao do topo
function toggle()
  if window and window:isVisible() then
    hide()
  elseif g_game.isOnline() then
    send('OPEN')
  end
end

local function onGameEnd()
  if window then window:hide() end
  if espButton then
    espButton:setOn(false)
    espButton:hide()
  end
end

function init()
  window = g_ui.displayUI('especializacao')
  window:hide()
  ProtocolGame.registerExtendedOpcode(OPCODE, onEspOpcode)
  connect(g_game, { onGameEnd = onGameEnd })
  if modules.client_topmenu and modules.client_topmenu.addRightGameToggleButton then
    espButton = modules.client_topmenu.addRightGameToggleButton('especButton', tr('Especializacao'), '/images/especializacao/1', toggle, true)
    espButton:setOn(false)
    espButton:hide()
  end
end

function terminate()
  ProtocolGame.unregisterExtendedOpcode(OPCODE)
  disconnect(g_game, { onGameEnd = onGameEnd })
  if espButton then
    espButton:destroy()
    espButton = nil
  end
  if window then
    window:destroy()
    window = nil
  end
end
