-- ============================================================
-- PokeBank Digital v2 - Modulo Cliente OTC (Opcode 88)
-- Servidor: data/lib/core/pokebank.lua
-- ============================================================

PokeBank = {}
PokeBank.opcode = 88
PokeBank.window = nil
PokeBank.opcodeRegistered = false
PokeBank.refreshEvent = nil
PokeBank.notifyEvent = nil
PokeBank.confirmEvent = nil

PokeBank.ICONS = '/modules/game_pokemonmanager/images/'
PokeBank.data = {bank = 0, money = 0, tokens = 0, pokecoins = 0, donate = 0,
  account = 0, sentToday = 0, dailyLimit = 0, feePermil = 0, name = '',
  pocket = {GOLD = 0, POKECOINS = 0, DONATE = 0, TOKENS = 0}, tokenPhysical = false}
PokeBank.history = {}
PokeBank.historyFilter = 'ALL'
PokeBank.currency = 'GOLD'
PokeBank.pendingTransfer = nil
PokeBank.currentTab = 'panelDeposit'
PokeBank.lookup = {query = '', status = 'idle'}  -- destinatario da transferencia
PokeBank.lookupEvent = nil

local TYPE_INFO = {
  DEPOSIT      = {label = 'Deposito',         sign = 1,  color = '#5fd35f'},
  WITHDRAW     = {label = 'Saque',            sign = -1, color = '#e07a5f'},
  TRANSFER_IN  = {label = 'Recebido de',      sign = 1,  color = '#5fd35f'},
  TRANSFER_OUT = {label = 'Enviado para',     sign = -1, color = '#e07a5f'},
  FEE          = {label = 'Taxa de transferencia', sign = -1, color = '#c9a227'},
}
local CURRENCY_UNIT = {GOLD = 'gp', POKECOINS = 'PokeCoins', DONATE = 'Donate', TOKENS = 'Tokens'}
local CURRENCY_COLOR = {GOLD = '#f2c400', POKECOINS = '#45a8ff', DONATE = '#c46be0', TOKENS = '#72e6a0'}
local CURRENCY_NAME = {GOLD = 'GOLD', POKECOINS = 'POKECOINS', DONATE = 'DONATE', TOKENS = 'TOKENS'}
local CURRENCY_ICON = {GOLD = 'gold', POKECOINS = 'pokecoins', DONATE = 'donate', TOKENS = 'tokens'}
local CURRENCIES = {'GOLD', 'POKECOINS', 'DONATE', 'TOKENS'}
-- atalhos: ids fixos no otui, valores por moeda
local SHORTCUT_IDS = {'1k', '10k', '100k', '1kk'}
local SHORTCUTS = {
  GOLD = {{'1k', 1000}, {'10k', 10000}, {'100k', 100000}, {'1kk', 1000000}},
  OTHER = {{'1', 1}, {'10', 10}, {'100', 100}, {'1k', 1000}}
}

function PokeBank.balanceOf(currency)
  local d = PokeBank.data
  if currency == 'GOLD' then return d.bank end
  if currency == 'POKECOINS' then return d.pokecoins end
  if currency == 'DONATE' then return d.donate end
  if currency == 'TOKENS' then return d.tokens end
  return 0
end

function PokeBank.pocketOf(currency)
  return PokeBank.data.pocket[currency] or 0
end

function PokeBank.hasPhysical(currency)
  return currency ~= 'TOKENS' or PokeBank.data.tokenPhysical
end

-- ============================================
-- UTIL
-- ============================================
function PokeBank.formatNumber(num)
  local s = tostring(math.floor(tonumber(num) or 0))
  local neg = s:sub(1, 1) == '-'
  if neg then s = s:sub(2) end
  s = s:reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
  return (neg and '-' or '') .. s
end

-- aceita "50000", "50.000", "10k", "1,5kk", "2kk"
function PokeBank.parseAmount(text)
  text = tostring(text or ''):lower():gsub('%s', '')
  if text == '' then return 0 end
  local mult = 1
  if text:sub(-2) == 'kk' then mult = 1000000; text = text:sub(1, -3)
  elseif text:sub(-1) == 'k' then mult = 1000; text = text:sub(1, -2) end
  if mult > 1 then
    text = text:gsub(',', '.')
  else
    text = text:gsub('[%.,]', '')
  end
  local value = tonumber(text)
  if not value or value <= 0 then return 0 end
  return math.floor(value * mult)
end

function PokeBank.split(str, delimiter)
  local result, from = {}, 1
  local a, b = string.find(str, delimiter, from, true)
  while a do
    result[#result + 1] = string.sub(str, from, a - 1)
    from = b + 1
    a, b = string.find(str, delimiter, from, true)
  end
  result[#result + 1] = string.sub(str, from)
  return result
end

local function W(id)
  if not PokeBank.window or PokeBank.window:isDestroyed() then return nil end
  return PokeBank.window:recursiveGetChildById(id)
end

local function setText(id, text)
  local widget = W(id)
  if widget then widget:setText(text) end
  return widget
end

local function send(text)
  if not PokeBank.opcodeRegistered then
    PokeBank.tryRegisterOpcode()
  end
  if not g_game.isOnline() then
    PokeBank.showNotification('Voce esta offline.', false)
    return false
  end
  local proto = g_game.getProtocolGame()
  if not proto then return false end
  proto:sendExtendedOpcode(PokeBank.opcode, text)
  return true
end

local function formatDate(ts, withYear)
  ts = tonumber(ts) or 0
  if ts <= 0 then return '' end
  local ok, text = pcall(os.date, withYear and '%d/%m/%y %H:%M' or '%d/%m %H:%M', ts)
  return ok and text or ''
end

-- ============================================
-- INIT / LIFECYCLE
-- ============================================
function init()
  connect(g_game, {
    onGameStart = PokeBank.onGameStart,
    onGameEnd = PokeBank.onGameEnd
  })

  PokeBank.tryRegisterOpcode()
  if not PokeBank.opcodeRegistered then
    PokeBank.retryEvent = scheduleEvent(PokeBank.tryRegisterOpcode, 2000)
  end

  modules.game_pokebank = PokeBank
end

function terminate()
  for _, key in ipairs({'retryEvent', 'refreshEvent', 'notifyEvent', 'confirmEvent'}) do
    if PokeBank[key] then
      removeEvent(PokeBank[key])
      PokeBank[key] = nil
    end
  end
  disconnect(g_game, {
    onGameStart = PokeBank.onGameStart,
    onGameEnd = PokeBank.onGameEnd
  })
  PokeBank.destroy()
  pcall(function() ProtocolGame.unregisterExtendedOpcode(PokeBank.opcode) end)
  PokeBank.opcodeRegistered = false
  modules.game_pokebank = nil
end

function PokeBank.tryRegisterOpcode()
  if PokeBank.opcodeRegistered then return true end
  local ok = pcall(function()
    ProtocolGame.registerExtendedOpcode(PokeBank.opcode, PokeBank.onExtendedOpcode)
  end)
  if ok then
    PokeBank.opcodeRegistered = true
    if PokeBank.retryEvent then
      removeEvent(PokeBank.retryEvent)
      PokeBank.retryEvent = nil
    end
  end
  return ok
end

function PokeBank.onGameStart()
  PokeBank.destroy()
  PokeBank.tryRegisterOpcode()
end

function PokeBank.onGameEnd()
  PokeBank.destroy()
end

-- O PokeBank so abre pelo terminal (item 39405) ou pelo notebook: quem
-- abre e o servidor (mensagem OPEN). Botoes antigos so fecham/avisam.
function PokeBank.toggle()
  if PokeBank.window and not PokeBank.window:isDestroyed() and PokeBank.window:isVisible() then
    PokeBank.destroy()
  elseif modules.game_textmessage then
    modules.game_textmessage.displayFailureMessage('[PokeBank] Use um terminal PokeBank ou o notebook.')
  end
end

-- ============================================
-- OPCODE HANDLER
-- ============================================
function PokeBank.onExtendedOpcode(protocol, opcode, buffer)
  if opcode ~= PokeBank.opcode then return end
  buffer = buffer or ''

  if buffer:sub(1, 7) == 'HISTORY' then
    PokeBank.parseHistory(buffer)
    return
  end

  local parts = PokeBank.split(buffer, '|')
  local cmd = parts[1]

  if cmd == 'OPEN' then
    -- o servidor ja manda saldo e extrato logo depois
    PokeBank.show(true)
    return
  elseif cmd == 'CLOSE' then
    PokeBank.destroy()
    return
  end

  if cmd == 'BALANCE' then
    local d = PokeBank.data
    d.bank = tonumber(parts[2]) or 0
    d.money = tonumber(parts[3]) or 0
    d.tokens = tonumber(parts[4]) or 0
    d.pokecoins = tonumber(parts[5]) or 0
    d.donate = tonumber(parts[6]) or 0
    d.account = tonumber(parts[7]) or 0
    d.sentToday = tonumber(parts[8]) or 0
    d.dailyLimit = tonumber(parts[9]) or 0
    d.feePermil = tonumber(parts[10]) or 0
    d.name = parts[11] or ''
    d.pocket = {
      GOLD = d.money,
      POKECOINS = tonumber(parts[12]) or 0,
      DONATE = tonumber(parts[13]) or 0,
      TOKENS = tonumber(parts[14]) or 0
    }
    d.tokenPhysical = parts[15] == '1'
    PokeBank.refreshBalance()

  elseif cmd == 'LOOKUP' then
    PokeBank.onLookup(parts)

  elseif cmd == 'RESULT' then
    local ok = parts[2] == 'OK'
    PokeBank.showNotification(parts[3] or '', ok)
    if ok then
      PokeBank.clearInputs()
    end
  end
end

function PokeBank.parseHistory(buffer)
  local list = {}
  local first = true
  for line in (buffer .. '\n'):gmatch('(.-)\n') do
    if first then
      first = false
    elseif line ~= '' then
      local f = PokeBank.split(line, '|')
      list[#list + 1] = {
        type = f[1] or '',
        currency = (f[2] ~= nil and f[2] ~= '') and f[2] or 'GOLD',
        amount = tonumber(f[3]) or 0,
        after = tonumber(f[4]) or 0,
        target = f[5] or '',
        time = tonumber(f[6]) or 0
      }
    end
  end
  PokeBank.history = list
  PokeBank.refreshHistory()
end

-- ============================================
-- RENDER
-- ============================================
local function setupWallet(id, name, icon)
  local card = W(id)
  if not card then return end
  card:getChildById('name'):setText(name)
  card:getChildById('icon'):setImageSource(PokeBank.ICONS .. icon .. '.png')
end

function PokeBank.refreshBalance()
  if not PokeBank.window or PokeBank.window:isDestroyed() then return end
  local d = PokeBank.data
  local fmt = PokeBank.formatNumber

  setText('balanceLabel', fmt(d.bank) .. ' gp')
  setText('moneyLabel', 'Na mochila: ' .. fmt(d.money) .. ' gp')
  setText('totalLabel', 'Patrimonio: ' .. fmt(d.bank + d.money) .. ' gp')
  if d.account > 0 then
    setText('accountLabel', string.format('CONTA %06d', d.account))
  end
  setText('holderLabel', d.name ~= '' and d.name:upper() or (g_game.getCharacterName() or ''):upper())

  local function wallet(id, currency)
    local card = W(id)
    if not card then return end
    local text = fmt(PokeBank.balanceOf(currency))
    local pocket = PokeBank.pocketOf(currency)
    if pocket > 0 then text = text .. '  (+' .. fmt(pocket) .. ')' end
    card:getChildById('value'):setText(text)
    card:setTooltip(CURRENCY_UNIT[currency] .. ': ' .. fmt(PokeBank.balanceOf(currency)) .. ' em conta, ' .. fmt(pocket) .. ' na mochila')
  end
  wallet('walletPokecoins', 'POKECOINS')
  wallet('walletDonate', 'DONATE')
  wallet('walletTokens', 'TOKENS')

  PokeBank.applyCurrency()
end

-- aplica a moeda escolhida em titulos, atalhos e saldos
function PokeBank.applyCurrency()
  if not PokeBank.window or PokeBank.window:isDestroyed() then return end
  local cur = PokeBank.currency
  local fmt = PokeBank.formatNumber
  local unit = CURRENCY_UNIT[cur]

  for _, c in ipairs(CURRENCIES) do
    local chip = W('cur' .. c)
    if chip then
      chip:setOn(c == cur)
      local text = chip:getChildById('label')
      if text then text:setColor(c == cur and '#ffffff' or '#8fa7c4') end
    end
  end
  setText('depTitle', 'DEPOSITAR ' .. CURRENCY_NAME[cur])
  setText('witTitle', 'SACAR ' .. CURRENCY_NAME[cur])
  setText('traTitle', 'TRANSFERIR ' .. CURRENCY_NAME[cur])
  setText('depAvailable', 'Mochila: ' .. fmt(PokeBank.pocketOf(cur)) .. ' ' .. unit)
  setText('witAvailable', 'Em conta: ' .. fmt(PokeBank.balanceOf(cur)) .. ' ' .. unit)

  local list = cur == 'GOLD' and SHORTCUTS.GOLD or SHORTCUTS.OTHER
  for i, suffix in ipairs(SHORTCUT_IDS) do
    for _, prefix in ipairs({'btnDeposit', 'btnWithdraw'}) do
      local chip = W(prefix .. suffix)
      if chip then
        chip:setText(list[i][1])
        chip.shortcutValue = list[i][2]
      end
    end
  end

  local physical = PokeBank.hasPhysical(cur)
  local depNote = W('depNote')
  if depNote then
    if not physical then
      depNote:setText('Tokens so existem no banco. Use Transferir.')
      depNote:setColor('#e07a5f')
    elseif cur == 'GOLD' then
      depNote:setText('Moedas gold, platinum e crystal da mochila.')
      depNote:setColor('#4a5f7a')
    else
      depNote:setText('Itens ' .. unit .. ' da mochila viram saldo em conta.')
      depNote:setColor('#4a5f7a')
    end
  end
  local witNote = W('witNote')
  if witNote then
    if physical then
      witNote:setText('O saque precisa de capacidade e espaco livre na mochila.')
      witNote:setColor('#4a5f7a')
    else
      witNote:setText('Tokens so existem no banco. Use Transferir.')
      witNote:setColor('#e07a5f')
    end
  end
  PokeBank.updatePreviews()
end

function PokeBank.setCurrency(currency)
  PokeBank.currency = currency
  PokeBank.cancelTransfer(true)
  PokeBank.applyCurrency()
end

function PokeBank.updatePreviews()
  if not PokeBank.window or PokeBank.window:isDestroyed() then return end
  local cur = PokeBank.currency
  local fmt = PokeBank.formatNumber
  local unit = CURRENCY_UNIT[cur]
  local bank, pocket = PokeBank.balanceOf(cur), PokeBank.pocketOf(cur)
  local physical = PokeBank.hasPhysical(cur)
  local hint = cur == 'GOLD' and 'Digite um valor (aceita 10k, 1kk).' or 'Digite a quantidade.'

  local dep = W('depositAmount')
  local depValue = dep and PokeBank.parseAmount(dep:getText()) or 0
  local depLabel = W('depPreview')
  if depLabel then
    if depValue <= 0 then
      depLabel:setText(hint)
      depLabel:setColor('#6f86a8')
    elseif depValue > pocket then
      depLabel:setText('Voce so tem ' .. fmt(pocket) .. ' ' .. unit .. ' na mochila.')
      depLabel:setColor('#e07a5f')
    else
      depLabel:setText('Saldo apos o deposito: ' .. fmt(bank + depValue) .. ' ' .. unit)
      depLabel:setColor('#5fd35f')
    end
  end
  local depBtn = W('btnDeposit')
  if depBtn then
    depBtn:setEnabled(physical and depValue > 0 and depValue <= pocket)
    depBtn:setText(depValue > 0 and ('DEPOSITAR ' .. fmt(depValue) .. ' ' .. unit:upper()) or 'DEPOSITAR')
  end

  local wit = W('withdrawAmount')
  local witValue = wit and PokeBank.parseAmount(wit:getText()) or 0
  local witLabel = W('witPreview')
  if witLabel then
    if witValue <= 0 then
      witLabel:setText(hint)
      witLabel:setColor('#6f86a8')
    elseif witValue > bank then
      witLabel:setText('Saldo insuficiente: ' .. fmt(bank) .. ' ' .. unit .. ' em conta.')
      witLabel:setColor('#e07a5f')
    else
      witLabel:setText('Saldo apos o saque: ' .. fmt(bank - witValue) .. ' ' .. unit)
      witLabel:setColor('#5fd35f')
    end
  end
  local witBtn = W('btnWithdraw')
  if witBtn then
    witBtn:setEnabled(physical and witValue > 0 and witValue <= bank)
    witBtn:setText(witValue > 0 and ('SACAR ' .. fmt(witValue) .. ' ' .. unit:upper()) or 'SACAR')
  end

  PokeBank.updateTransferInfo()
end

function PokeBank.transferFee(amount)
  local d = PokeBank.data
  if PokeBank.currency ~= 'GOLD' or d.feePermil <= 0 or amount <= 0 then return 0 end
  return math.max(1, math.floor(amount * d.feePermil / 1000))
end

function PokeBank.updateTransferInfo()
  local info = W('transferInfo')
  if not info then return end
  local d = PokeBank.data
  local fmt = PokeBank.formatNumber
  local gold = PokeBank.currency == 'GOLD'
  local amountWidget = W('transferAmount')
  local amount = amountWidget and PokeBank.parseAmount(amountWidget:getText()) or 0
  local fee = PokeBank.transferFee(amount)
  local unit = CURRENCY_UNIT[PokeBank.currency]


  if PokeBank.pendingTransfer then
    local p = PokeBank.pendingTransfer
    local text = 'Confirme: enviar ' .. fmt(p.amount) .. ' ' .. CURRENCY_UNIT[p.currency] .. ' para ' .. p.target .. '.'
    if p.fee > 0 then text = text .. ' Taxa: ' .. fmt(p.fee) .. ' gp (total ' .. fmt(p.amount + p.fee) .. ').' end
    info:setText(text)
    info:setColor('#f2c400')
    return
  end

  local lines = {}
  if gold then
    lines[#lines + 1] = 'Em conta: ' .. fmt(d.bank) .. ' gp'
    if d.feePermil > 0 then
      lines[#lines] = lines[#lines] .. '  |  Taxa: ' .. string.format('%.1f', d.feePermil / 10) .. '%'
        .. (fee > 0 and (' (' .. fmt(fee) .. ' gp)') or '')
    end
    if d.dailyLimit > 0 then
      lines[#lines + 1] = 'Limite diario restante: ' .. fmt(math.max(0, d.dailyLimit - d.sentToday)) .. ' gp'
    end
  else
    lines[#lines + 1] = 'Em conta: ' .. fmt(PokeBank.balanceOf(PokeBank.currency)) .. ' ' .. unit .. '  |  Sem taxa'
  end
  info:setText(table.concat(lines, '\n'))
  local have = PokeBank.balanceOf(PokeBank.currency)
  info:setColor((amount + fee) > have and '#e07a5f' or '#8fa7c4')

  local btn = W('btnTransfer')
  if btn then
    btn:setText(amount > 0 and ('TRANSFERIR ' .. fmt(amount) .. ' ' .. unit:upper()) or 'TRANSFERIR')
  end
end

function PokeBank.refreshHistory()
  local panel = W('historyPanel')
  if not panel then return end
  panel:destroyChildren()

  for _, pair in ipairs({{'filterAll', 'ALL'}, {'filterGold', 'GOLD'}, {'filterPokecoins', 'POKECOINS'}, {'filterDonate', 'DONATE'}}) do
    local chip = W(pair[1])
    if chip then chip:setOn(PokeBank.historyFilter == pair[2]) end
  end

  local fmt = PokeBank.formatNumber
  local shown = 0
  for _, entry in ipairs(PokeBank.history) do
    if PokeBank.historyFilter == 'ALL' or PokeBank.historyFilter == entry.currency then
      local info = TYPE_INFO[entry.type] or {label = entry.type, sign = 0, color = '#dce8f5'}
      local unit = CURRENCY_UNIT[entry.currency] or entry.currency
      local row = g_ui.createWidget('PBHistoryRow', panel)
      local title = info.label
      if entry.target ~= '' then title = title .. ' ' .. entry.target end
      row:getChildById('title'):setText(title)
      row:getChildById('accent'):setBackgroundColor(CURRENCY_COLOR[entry.currency] or '#4a5f7a')
      local sign = info.sign > 0 and '+' or (info.sign < 0 and '-' or '')
      local amount = row:getChildById('amount')
      amount:setText(sign .. fmt(entry.amount) .. ' ' .. unit)
      amount:setColor(info.color)
      row:getChildById('detail'):setText(formatDate(entry.time))
      local oldRecord = entry.after == 0 and (entry.type == 'DEPOSIT' or entry.type == 'TRANSFER_IN')
      row:getChildById('after'):setText(oldRecord and '' or ('Saldo: ' .. fmt(entry.after) .. ' ' .. unit))
      shown = shown + 1
    end
  end

  if shown == 0 then
    local empty = g_ui.createWidget('PBCaption', panel)
    empty:setText('Nenhuma transacao encontrada.')
    empty:setTextAlign(AlignCenter)
    empty:setHeight(40)
  end
end

-- ============================================
-- UI
-- ============================================
function PokeBank.show(fromServer)
  if not fromServer then
    -- abrir so pelo terminal ou notebook
    return PokeBank.toggle()
  end
  if not g_game.isOnline() then
    modules.game_textmessage.displayFailureMessage('[PokeBank] Voce precisa estar online!')
    return
  end

  if PokeBank.window and not PokeBank.window:isDestroyed() then
    PokeBank.window:show()
    PokeBank.window:raise()
    PokeBank.window:focus()
    return
  end

  PokeBank.tryRegisterOpcode()

  local window
  for _, path in ipairs({'pokebank', '/game_pokebank/pokebank', '/modules/game_pokebank/pokebank'}) do
    local ok, res = pcall(function() return g_ui.displayUI(path) end)
    if ok and res then
      window = res
      break
    end
  end
  if not window then
    modules.game_textmessage.displayFailureMessage('[PokeBank] pokebank.otui nao encontrado!')
    return
  end
  PokeBank.window = window

  setupWallet('walletPokecoins', 'PokeCoins', 'pokecoins')
  setupWallet('walletDonate', 'Donate', 'donate')
  setupWallet('walletTokens', 'Tokens', 'tokens')

  local tabs = {tabDeposit = 'panelDeposit', tabWithdraw = 'panelWithdraw', tabTransfer = 'panelTransfer', tabHistory = 'panelHistory'}
  for tabId, panelId in pairs(tabs) do
    local btn = W(tabId)
    if btn then btn.onClick = function() PokeBank.switchTab(panelId) end end
  end

  local function bind(id, fn)
    local widget = W(id)
    if widget then widget.onClick = fn end
  end
  bind('btnClose', function()
    send('CLOSE')
    PokeBank.destroy()
  end)
  bind('btnDeposit', PokeBank.doDeposit)
  bind('btnWithdraw', PokeBank.doWithdraw)
  bind('btnTransfer', PokeBank.doTransfer)
  bind('btnTransferCancel', PokeBank.cancelTransfer)
  bind('btnDepositAll', function()
    PokeBank.setAmount('depositAmount', PokeBank.pocketOf(PokeBank.currency))
  end)
  bind('btnWithdrawAll', function()
    PokeBank.setAmount('withdrawAmount', PokeBank.balanceOf(PokeBank.currency))
  end)

  for _, suffix in ipairs(SHORTCUT_IDS) do
    local dep, wit = W('btnDeposit' .. suffix), W('btnWithdraw' .. suffix)
    if dep then dep.onClick = function(self) PokeBank.addAmount('depositAmount', self.shortcutValue or 0) end end
    if wit then wit.onClick = function(self) PokeBank.addAmount('withdrawAmount', self.shortcutValue or 0) end end
  end

  for _, cur in ipairs(CURRENCIES) do
    local chip = W('cur' .. cur)
    if chip then
      chip:getChildById('label'):setText(cur == 'GOLD' and 'Gold' or CURRENCY_UNIT[cur])
      chip:getChildById('icon'):setImageSource(PokeBank.ICONS .. CURRENCY_ICON[cur] .. '.png')
      chip.onClick = function() PokeBank.setCurrency(cur) end
    end
  end
  bind('filterAll', function() PokeBank.historyFilter = 'ALL'; PokeBank.refreshHistory() end)
  bind('filterGold', function() PokeBank.historyFilter = 'GOLD'; PokeBank.refreshHistory() end)
  bind('filterPokecoins', function() PokeBank.historyFilter = 'POKECOINS'; PokeBank.refreshHistory() end)
  bind('filterDonate', function() PokeBank.historyFilter = 'DONATE'; PokeBank.refreshHistory() end)
  bind('exportPdf', PokeBank.exportPdf)
  bind('exportBrowse', PokeBank.chooseExportDir)
  local exportInput = W('exportDir')
  if exportInput then
    local okSaved, saved = pcall(function() return g_settings.getString('pokebankExportDir') end)
    exportInput:setText((okSaved and saved and saved ~= '') and saved or PokeBank.defaultExportDir())
    if not (io and io.open) then
      exportInput:setEnabled(false)
      exportInput:setTooltip('Este cliente nao permite escolher a pasta; o PDF vai para a pasta do cliente.')
    end
  end

  for _, id in ipairs({'depositAmount', 'withdrawAmount', 'transferAmount', 'transferTarget'}) do
    local input = W(id)
    if input then
      input.onTextChange = function()
        if id == 'transferAmount' or id == 'transferTarget' then
          PokeBank.cancelTransfer(true)
        end
        if id == 'transferTarget' then
          PokeBank.scheduleLookup()
        end
        PokeBank.updatePreviews()
      end
    end
  end

  PokeBank.switchTab(PokeBank.currentTab, true)
  PokeBank.refreshBalance()
  PokeBank.refreshHistory()
end

-- O cliente tem protecao anti-bot: pacotes enviados de dentro de um
-- scheduleEvent sao cancelados. Por isso nada aqui envia por timer; o
-- servidor ja manda o saldo novo depois de cada operacao/recebimento.
function PokeBank.startRefreshTimer()
end

function PokeBank.destroy()
  PokeBank.pendingTransfer = nil
  PokeBank.lookup = {query = '', status = 'idle'}
  for _, key in ipairs({'refreshEvent', 'notifyEvent', 'confirmEvent', 'lookupEvent', 'lookupTimeout'}) do
    if PokeBank[key] then
      removeEvent(PokeBank[key])
      PokeBank[key] = nil
    end
  end
  if PokeBank.window and not PokeBank.window:isDestroyed() then
    PokeBank.window:destroy()
  end
  PokeBank.window = nil
end

function PokeBank.switchTab(panelId, silent)
  if not PokeBank.window or PokeBank.window:isDestroyed() then return end
  PokeBank.currentTab = panelId
  local map = {panelDeposit = 'tabDeposit', panelWithdraw = 'tabWithdraw', panelTransfer = 'tabTransfer', panelHistory = 'tabHistory'}
  for pid, tabId in pairs(map) do
    local panel = W(pid)
    if panel then panel:setVisible(pid == panelId) end
    local tab = W(tabId)
    if tab then tab:setOn(pid == panelId) end
  end
  PokeBank.cancelTransfer(true)
  if panelId == 'panelHistory' and not silent then PokeBank.requestData() end
end

function PokeBank.setAmount(inputId, value)
  local input = W(inputId)
  if input then
    input:setText(PokeBank.formatNumber(value))
    PokeBank.updatePreviews()
  end
end

function PokeBank.addAmount(inputId, value)
  local input = W(inputId)
  if not input then return end
  PokeBank.setAmount(inputId, PokeBank.parseAmount(input:getText()) + value)
end

function PokeBank.clearInputs()
  for _, id in ipairs({'depositAmount', 'withdrawAmount', 'transferAmount', 'transferTarget'}) do
    local input = W(id)
    if input then input:setText('') end
  end
  PokeBank.cancelTransfer(true)
  PokeBank.updatePreviews()
end


-- ============================================
-- ACOES
-- ============================================
function PokeBank.doDeposit()
  local input = W('depositAmount')
  local amount = input and PokeBank.parseAmount(input:getText()) or 0
  if amount <= 0 then
    return PokeBank.showNotification('Informe um valor valido.', false)
  end
  local cur = PokeBank.currency
  local pocket = PokeBank.pocketOf(cur)
  if amount >= pocket and pocket > 0 then
    send('DEPOSIT_ALL|' .. cur)
  else
    send('DEPOSIT|' .. cur .. '|' .. amount)
  end
  PokeBank.showNotification('Processando deposito...', true)
end

function PokeBank.doWithdraw()
  local input = W('withdrawAmount')
  local amount = input and PokeBank.parseAmount(input:getText()) or 0
  if amount <= 0 then
    return PokeBank.showNotification('Informe um valor valido.', false)
  end
  send('WITHDRAW|' .. PokeBank.currency .. '|' .. amount)
  PokeBank.showNotification('Processando saque...', true)
end

function PokeBank.cancelTransfer(silent)
  local hadPending = PokeBank.pendingTransfer ~= nil
  PokeBank.pendingTransfer = nil
  if PokeBank.confirmEvent then
    removeEvent(PokeBank.confirmEvent)
    PokeBank.confirmEvent = nil
  end
  local btn, cancel = W('btnTransfer'), W('btnTransferCancel')
  if cancel then cancel:setVisible(false) end
  if btn then
    btn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    btn:setMarginLeft(12)
  end
  if hadPending and not silent then
    PokeBank.showNotification('Transferencia cancelada.', false)
  end
  PokeBank.updateTransferInfo()
end

function PokeBank.doTransfer()
  -- segundo clique: confirma
  if PokeBank.pendingTransfer then
    local p = PokeBank.pendingTransfer
    send('TRANSFER|' .. p.currency .. '|#' .. p.guid .. '|' .. p.amount)
    PokeBank.showNotification('Processando transferencia...', true)
    PokeBank.cancelTransfer(true)
    return
  end

  local targetInput, amountInput = W('transferTarget'), W('transferAmount')
  if not targetInput or not amountInput then return end
  local query = PokeBank.cleanQuery(targetInput:getText())
  local amount = PokeBank.parseAmount(amountInput:getText())
  if query == '' or amount <= 0 then
    return PokeBank.showNotification('Preencha o ID do jogador e o valor.', false)
  end
  local look = PokeBank.lookup
  if look.query ~= query or look.status ~= 'ok' then
    PokeBank.requestLookup()
    return PokeBank.showNotification('Aguarde a confirmacao do destinatario.', false)
  end
  if look.guid == PokeBank.data.account then
    return PokeBank.showNotification('Voce nao pode transferir para si mesmo.', false)
  end
  local fee = PokeBank.transferFee(amount)
  local have = PokeBank.balanceOf(PokeBank.currency)
  if amount + fee > have then
    return PokeBank.showNotification('Saldo insuficiente para essa transferencia.', false)
  end

  PokeBank.pendingTransfer = {currency = PokeBank.currency, guid = look.guid,
    target = look.name .. ' (ID ' .. look.guid .. ')', amount = amount, fee = fee}
  local btn, cancel = W('btnTransfer'), W('btnTransferCancel')
  if cancel then cancel:setVisible(true) end
  if btn then
    btn:addAnchor(AnchorLeft, 'btnTransferCancel', AnchorRight)
    btn:setMarginLeft(6)
    btn:setText('CONFIRMAR ENVIO')
  end
  PokeBank.updateTransferInfo()
  PokeBank.confirmEvent = scheduleEvent(function()
    PokeBank.confirmEvent = nil
    PokeBank.cancelTransfer(false)
  end, 10000)
end

-- ============================================
-- DESTINATARIO (busca por ID ou nome)
-- ============================================
function PokeBank.cleanQuery(text)
  return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[|#]', ''))
end

function PokeBank.setTargetText(text, color)
  local label = W('targetName')
  if label then
    label:setText(text)
    label:setColor(color)
  end
end

function PokeBank.requestLookup()
  local input = W('transferTarget')
  local query = input and PokeBank.cleanQuery(input:getText()) or ''
  PokeBank.lookup = {query = query, status = query == '' and 'idle' or 'loading'}
  if query == '' then
    PokeBank.setTargetText('Digite o ID que aparece em CONTA no PokeBank do jogador.', '#6f86a8')
    return
  end
  PokeBank.setTargetText('Procurando jogador...', '#6f86a8')
  g_logger.info('[PokeBank] LOOKUP enviado: ' .. query)
  send('LOOKUP|' .. query)
  -- sem resposta: o servidor ainda esta com a lib antiga do PokeBank
  if PokeBank.lookupTimeout then removeEvent(PokeBank.lookupTimeout) end
  PokeBank.lookupTimeout = scheduleEvent(function()
    PokeBank.lookupTimeout = nil
    local look = PokeBank.lookup
    if look.status == 'loading' and look.query == query then
      look.status = 'timeout'
      PokeBank.setTargetText('Servidor nao respondeu. Reinicie o servidor com a lib nova.', '#e07a5f')
    end
  end, 3000)
end

-- envia direto na digitacao (evento do teclado e permitido pela protecao anti-bot)
function PokeBank.scheduleLookup()
  PokeBank.requestLookup()
end

-- LOOKUP|consulta|guid|nome|level|online   (guid 0 = nao encontrado)
function PokeBank.onLookup(parts)
  g_logger.info('[PokeBank] LOOKUP recebido: ' .. table.concat(parts, '|'))
  local input = W('transferTarget')
  local current = input and PokeBank.cleanQuery(input:getText()) or ''
  local query = parts[2] or ''
  if query ~= current then return end -- resposta antiga
  local guid = tonumber(parts[3]) or 0
  if guid <= 0 then
    PokeBank.lookup = {query = query, status = 'notfound'}
    PokeBank.setTargetText('Nenhum jogador com esse ID ou nome.', '#e07a5f')
    return
  end
  local name, level, online = parts[4] or '?', tonumber(parts[5]) or 0, parts[6] == '1'
  PokeBank.lookup = {query = query, status = 'ok', guid = guid, name = name}
  if guid == PokeBank.data.account then
    PokeBank.setTargetText('Esta e a sua propria conta.', '#e07a5f')
    return
  end
  PokeBank.setTargetText('Destinatario: ' .. name .. '  |  Nivel ' .. level .. (online and '  |  online' or '  |  offline'), '#5fd35f')
end

-- ============================================
-- EXTRATO EM PDF (gerado no proprio cliente)
-- ============================================
local function pdfEscape(text)
  return (tostring(text or ''):gsub('[^\32-\126]', '?'):gsub('([\\%(%)])', '\\%1'))
end

-- largura aproximada de texto (Helvetica ~0.52em, Courier 0.6em exatos)
local function textWidth(text, size, mono)
  return #tostring(text or '') * size * (mono and 0.6 or 0.52)
end

local function fitText(text, size, maxWidth, mono)
  text = tostring(text or '')
  while #text > 1 and textWidth(text, size, mono) > maxWidth do
    text = text:sub(1, -2)
  end
  return text
end

-- Monta um PDF A4 com cabecalho, resumo de saldos e tabela.
-- columns = {{title, x, width, align ('left'/'right'), mono}}
-- rows    = {{cells = {...}, colors = {[colIndex] = {r,g,b}}}}
function PokeBank.buildPdf(info, columns, rows)
  local W, H = 595, 842
  local left, right = 36, 559
  local rowH, fontSize = 17, 8.5
  local pages, ops = {}, nil
  local y

  local function add(op) ops[#ops + 1] = op end
  local function rect(x, yy, w, h, r, g, b)
    add(string.format('%.3f %.3f %.3f rg %.1f %.1f %.1f %.1f re f', r, g, b, x, yy, w, h))
  end
  local function text(x, yy, str, font, size, color, align, width, mono)
    str = fitText(str, size, width or 500, mono)
    if align == 'right' then x = x + (width or 0) - textWidth(str, size, mono) end
    local c = color or {0.12, 0.14, 0.18}
    add(string.format('BT %.3f %.3f %.3f rg /%s %.1f Tf %.1f %.1f Td (%s) Tj ET', c[1], c[2], c[3], font, size, x, yy, pdfEscape(str)))
  end

  local function tableHeader()
    rect(left, y - 6, right - left, 20, 0.043, 0.086, 0.149)
    for _, col in ipairs(columns) do
      text(col.x, y, col.title, 'F2', 8, {1, 1, 1}, col.align, col.width, true)
    end
    y = y - 22
  end

  local function newPage(first)
    ops = {}
    pages[#pages + 1] = ops
    -- faixa do topo
    rect(0, H - 70, W, 70, 0.043, 0.086, 0.149)
    rect(0, H - 73, W, 3, 0.949, 0.769, 0)
    text(left, H - 38, 'POKEBANK', 'F2', 20, {0.949, 0.769, 0}, 'left', 200)
    text(left, H - 56, 'Extrato de conta', 'F1', 10, {0.85, 0.9, 0.96}, 'left', 200)
    text(300, H - 34, info.holder, 'F2', 11, {1, 1, 1}, 'right', right - 300)
    text(300, H - 50, 'Conta ' .. info.account .. '   |   ' .. info.filter, 'F1', 9, {0.8, 0.86, 0.94}, 'right', right - 300)
    y = H - 100
    if first then
      -- resumo de saldos
      text(left, y, 'SALDOS EM CONTA', 'F2', 9, {0.35, 0.4, 0.5}, 'left', 200)
      text(300, y, 'Emitido em ' .. info.issued, 'F1', 8.5, {0.45, 0.5, 0.58}, 'right', right - 300)
      y = y - 12
      local boxW = (right - left - 18) / 4
      for i, item in ipairs(info.balances) do
        local x = left + (i - 1) * (boxW + 6)
        rect(x, y - 34, boxW, 34, 0.953, 0.961, 0.973)
        rect(x, y - 34, 3, 34, item.color[1], item.color[2], item.color[3])
        text(x + 10, y - 13, item.label, 'F1', 8, {0.4, 0.45, 0.53}, 'left', boxW - 14)
        text(x + 10, y - 27, item.value, 'F2', 11, {0.1, 0.12, 0.16}, 'left', boxW - 14)
      end
      y = y - 56
    end
    tableHeader()
  end

  newPage(true)
  for index, row in ipairs(rows) do
    if y < 60 then newPage(false) end
    if index % 2 == 0 then rect(left, y - 5, right - left, rowH, 0.965, 0.972, 0.982) end
    for c, col in ipairs(columns) do
      local color = row.colors and row.colors[c] or nil
      text(col.x, y, row.cells[c] or '', col.mono and 'F3' or 'F1', fontSize, color, col.align, col.width, col.mono)
    end
    y = y - rowH
  end

  -- rodape com numero da pagina
  for page, pageOps in ipairs(pages) do
    ops = pageOps
    add('0.8 0.83 0.88 RG 0.5 w ' .. left .. ' 40 m ' .. right .. ' 40 l S')
    text(left, 28, 'PokeBank Digital  -  documento gerado pelo cliente do jogo', 'F1', 7.5, {0.55, 0.6, 0.66}, 'left', 300)
    text(400, 28, 'Pagina ' .. page .. ' de ' .. #pages, 'F1', 7.5, {0.55, 0.6, 0.66}, 'right', right - 400)
  end

  -- objetos: 1 catalogo, 2 paginas, 3-5 fontes, depois pagina/conteudo
  local objects, kids = {}, {}
  objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
  objects[4] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>'
  objects[5] = '<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>'
  for page, pageOps in ipairs(pages) do
    local content = table.concat(pageOps, '\n')
    local pageId, contentId = 4 + page * 2, 5 + page * 2
    kids[#kids + 1] = pageId .. ' 0 R'
    objects[pageId] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ' .. W .. ' ' .. H ..
      '] /Resources << /Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >> >> /Contents ' .. contentId .. ' 0 R >>'
    objects[contentId] = '<< /Length ' .. #content .. ' >>\nstream\n' .. content .. '\nendstream'
  end
  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>'
  objects[2] = '<< /Type /Pages /Kids [' .. table.concat(kids, ' ') .. '] /Count ' .. #kids .. ' >>'

  local out = {'%PDF-1.4\n'}
  local length = #out[1]
  local offsets = {}
  for id = 1, #objects do
    offsets[id] = length
    local chunk = id .. ' 0 obj\n' .. objects[id] .. '\nendobj\n'
    out[#out + 1] = chunk
    length = length + #chunk
  end
  local xref = {'xref\n0 ' .. (#objects + 1) .. '\n0000000000 65535 f \n'}
  for id = 1, #objects do
    xref[#xref + 1] = string.format('%010d 00000 n \n', offsets[id])
  end
  out[#out + 1] = table.concat(xref)
  out[#out + 1] = 'trailer\n<< /Size ' .. (#objects + 1) .. ' /Root 1 0 R >>\nstartxref\n' .. length .. '\n%%EOF\n'
  return table.concat(out)
end

function PokeBank.exportPdf()
  local fmt = PokeBank.formatNumber
  local green, red, gray = {0.11, 0.52, 0.25}, {0.75, 0.2, 0.2}, {0.55, 0.6, 0.66}
  local rows = {}
  for _, entry in ipairs(PokeBank.history) do
    if PokeBank.historyFilter == 'ALL' or PokeBank.historyFilter == entry.currency then
      local info = TYPE_INFO[entry.type] or {label = entry.type, sign = 0}
      local sign = info.sign > 0 and '+' or (info.sign < 0 and '-' or '')
      local unit = CURRENCY_UNIT[entry.currency] or entry.currency
      local label = info.label:gsub(' de$', ''):gsub(' para$', '')
      -- registros antigos (antes da v2) nao tinham saldo gravado
      local after = fmt(entry.after)
      if entry.after == 0 and (entry.type == 'DEPOSIT' or entry.type == 'TRANSFER_IN') then after = '-' end
      local date = formatDate(entry.time, true)
      rows[#rows + 1] = {
        cells = {date ~= '' and date or '-', label, entry.currency == 'GOLD' and 'Gold' or unit, sign .. fmt(entry.amount), after,
          entry.target ~= '' and entry.target or '-'},
        colors = {[1] = (date == '') and gray or nil, [4] = info.sign > 0 and green or (info.sign < 0 and red or nil),
          [5] = after == '-' and gray or nil, [6] = entry.target == '' and gray or nil}
      }
    end
  end
  if #rows == 0 then
    return PokeBank.showNotification('Nao ha transacoes para exportar.', false)
  end

  local d = PokeBank.data
  local okDate, now = pcall(os.date, '%d/%m/%Y %H:%M')
  local info = {
    holder = (d.name ~= '' and d.name or (g_game.getCharacterName() or '')):upper(),
    account = string.format('%06d', d.account),
    filter = PokeBank.historyFilter == 'ALL' and 'Todas as moedas' or (CURRENCY_UNIT[PokeBank.historyFilter] or ''),
    issued = okDate and now or '',
    balances = {
      {label = 'Gold', value = fmt(d.bank) .. ' gp', color = {0.949, 0.769, 0}},
      {label = 'PokeCoins', value = fmt(d.pokecoins), color = {0.27, 0.66, 1}},
      {label = 'Donate', value = fmt(d.donate), color = {0.77, 0.42, 0.88}},
      {label = 'Tokens', value = fmt(d.tokens), color = {0.45, 0.9, 0.63}},
    }
  }
  local columns = {
    {title = 'DATA', x = 42, width = 72, align = 'left', mono = true},
    {title = 'OPERACAO', x = 120, width = 80, align = 'left'},
    {title = 'MOEDA', x = 204, width = 60, align = 'left'},
    {title = 'VALOR', x = 262, width = 84, align = 'right', mono = true},
    {title = 'SALDO APOS', x = 356, width = 92, align = 'right', mono = true},
    {title = 'JOGADOR', x = 466, width = 88, align = 'left'},
  }
  local pdf = PokeBank.buildPdf(info, columns, rows)

  local okName, stamp = pcall(os.date, '%Y%m%d_%H%M%S')
  local fileName = 'pokebank_extrato_' .. (okName and stamp or tostring(os.time())) .. '.pdf'
  local savedPath = PokeBank.savePdf(fileName, pdf)
  if not savedPath then
    return PokeBank.showNotification('Nao foi possivel salvar. Confira a pasta escolhida.', false)
  end
  g_logger.info('[PokeBank] Extrato salvo em: ' .. savedPath)
  PokeBank.showNotification('PDF salvo: ' .. savedPath, true)
  if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
    pcall(modules.game_textmessage.displayGameMessage, '[PokeBank] Extrato salvo em: ' .. savedPath)
  end
end

-- pasta padrao: Area de Trabalho do Windows (ou Documentos / home)
function PokeBank.defaultExportDir()
  local okEnv, home = pcall(os.getenv, 'USERPROFILE')
  if not okEnv or not home or home == '' then
    okEnv, home = pcall(os.getenv, 'HOME')
  end
  if okEnv and home and home ~= '' then
    return (home:gsub('\\', '/')) .. '/Desktop'
  end
  return ''
end

function PokeBank.getExportDir()
  local input = W('exportDir')
  local dir = input and input:getText() or ''
  dir = dir:gsub('^%s+', ''):gsub('%s+$', ''):gsub('\\', '/'):gsub('/+$', '')
  return dir
end

-- So guarda a pasta nas configuracoes se for texto simples (ASCII):
-- caminhos com acento vindos do Windows podem corromper o config.otml.
function PokeBank.rememberDir(dir)
  dir = tostring(dir or '')
  if dir == '' or dir:find('[^\32-\126]') then return end
  pcall(function() g_settings.set('pokebankExportDir', dir) end)
end

-- Abre a janela "Procurar pasta" do Windows (via PowerShell).
-- Enquanto a janela estiver aberta o cliente fica parado.
function PokeBank.chooseExportDir()
  local isWindows = package and package.config and package.config:sub(1, 1) == '\\'
  if not isWindows or not io or not io.popen then
    return PokeBank.showNotification('Seu cliente nao permite abrir a janela de pastas. Digite o caminho.', false)
  end
  local current = PokeBank.getExportDir():gsub('/', '\\'):gsub("['\"]", '')
  local script = "Add-Type -AssemblyName System.Windows.Forms;" ..
    "$o = New-Object System.Windows.Forms.Form -Property @{TopMost=$true};" ..
    "$d = New-Object System.Windows.Forms.FolderBrowserDialog;" ..
    "$d.Description = 'Escolha a pasta para salvar o extrato do PokeBank';" ..
    "$d.SelectedPath = '" .. current .. "';" ..
    "if ($d.ShowDialog($o) -eq 'OK') { $d.SelectedPath }"
  local command = 'powershell -NoProfile -STA -WindowStyle Hidden -Command "' .. script .. '"'
  local ok, chosen = pcall(function()
    local pipe = io.popen(command)
    if not pipe then return nil end
    local out = pipe:read('*a')
    pipe:close()
    return out
  end)
  chosen = ok and tostring(chosen or ''):gsub('[\r\n]+', ''):gsub('^%s+', ''):gsub('%s+$', '') or ''
  if chosen == '' then
    if not ok then PokeBank.showNotification('Nao foi possivel abrir a janela de pastas.', false) end
    return
  end
  chosen = chosen:gsub('\\', '/')
  local input = W('exportDir')
  if input then input:setText(chosen) end
  PokeBank.rememberDir(chosen)
  PokeBank.showNotification('Pasta escolhida: ' .. chosen, true)
end

-- grava na pasta escolhida (io); se o cliente bloquear io, grava na
-- pasta de dados do cliente (g_resources) e devolve o caminho real
function PokeBank.savePdf(fileName, data)
  local dir = PokeBank.getExportDir()
  if dir ~= '' and io and io.open then
    local path = dir .. '/' .. fileName
    local ok, saved = pcall(function()
      local file = io.open(path, 'wb')
      if not file then return false end
      file:write(data)
      file:close()
      return true
    end)
    if ok and saved then
      PokeBank.rememberDir(dir)
      return path
    end
  end
  local ok = pcall(function() g_resources.writeFileContents('/' .. fileName, data) end)
  if not ok then return nil end
  local okDir, writeDir = pcall(function() return g_resources.getWriteDir() end)
  return ((okDir and writeDir or '') .. fileName):gsub('\\', '/')
end

function PokeBank.requestData()
  send('REQUEST')
end

function PokeBank.showNotification(text, isSuccess)
  local lbl = W('notificationLabel')
  if not lbl then return end
  lbl:setText(text)
  lbl:setColor(isSuccess and '#5fd35f' or '#e07a5f')
  local bar = W('notificationBar')
  if bar then bar:setBorderColor(isSuccess and '#2f6b3a' or '#7a2f2f') end
  if PokeBank.notifyEvent then removeEvent(PokeBank.notifyEvent) end
  PokeBank.notifyEvent = scheduleEvent(function()
    PokeBank.notifyEvent = nil
    local label, b = W('notificationLabel'), W('notificationBar')
    if label then
      label:setText('PokeBank Digital')
      label:setColor('#6f86a8')
    end
    if b then b:setBorderColor('#1d3557') end
  end, 4000)
end
