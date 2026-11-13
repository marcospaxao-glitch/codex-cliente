local evs = {}
local ev = {"EV HP: ", "EV ATK: ", "EV DEF: ", "EV SP.ATK: ", "EV SP.DEF: ", "EV SPEED: ", "EV PTS: "}

function parse(protocol, opcode, buffer)
	for match in string.gmatch(buffer, "([^,]+),%s*") do
		evs[#evs + 1] = match
	end
	evsystem:show()
	showEvs(evs)
end

function init()
	evsystem = g_ui.displayUI('evsystem')
	connect(g_game, 'onTextMessage', getParams)
	connect(g_game, { onGameEnd = hide } )
	evsystem:hide()
	ProtocolGame.registerExtendedOpcode(65, parse)
end

function hide()
	evs = {}
	if evsystem:isVisible() then
	  evsystem:hide()
	end
end

function show()
  evsystem:show()
  evsystem:raise()
  evsystem:focus()
end

function destroyApps()
	for i = 1, 7 do
		if evsystem:recursiveGetChildById('ev'..i) ~= nil then evsystem:recursiveGetChildById('ev'..i):destroy() end
		if evsystem:recursiveGetChildById('text'..i) ~= nil then evsystem:recursiveGetChildById('text'..i):destroy() end
		if evsystem:recursiveGetChildById('plusbutton'..i) ~= nil then evsystem:recursiveGetChildById('plusbutton'..i):destroy() end
		if evsystem:recursiveGetChildById('minusbutton'..i) ~= nil then evsystem:recursiveGetChildById('minusbutton'..i):destroy() end
		if evsystem:recursiveGetChildById('buybutton'..i) ~= nil then evsystem:recursiveGetChildById('buybutton'..i):destroy() end
	end
end

function showEvs(evs)
	destroyApps()
	local startY = 32
	for i = 1, 6 do
		icon = g_ui.createWidget('TextUI',evsystem)
		icon:setId('ev'..i)
		icon:setText(ev[i])
		icon:setMarginLeft(10)
		icon:setMarginTop(startY + ((i-1) * 22))
		icon:setWidth(75)
		icon:setPhantom(true)
		text = g_ui.createWidget('TextUI',evsystem)
		text:setId('text'..i)
		text:setText(evs[i])
		text:setWidth(35)
		text:setMarginLeft(85)
		text:setMarginTop(startY + ((i-1) * 22))
		text:setPhantom(true)
		plusbutton = g_ui.createWidget('TMButton',evsystem)
		minusbutton = g_ui.createWidget('TMButton',evsystem)
		plusbutton:setId('plusbutton'..i)
		minusbutton:setId('minusbutton'..i)
		plusbutton:rotate(180)
		plusbutton:setWidth(16)
		minusbutton:setWidth(16)
		plusbutton:setHeight(16)
		minusbutton:setHeight(16)
		plusbutton:setSize(plusbutton:getSize())
		minusbutton:setSize(minusbutton:getSize())
		local path2 = "interface/returnbutton.png"
		plusbutton:setImageSource(path2)
		minusbutton:setImageSource(path2)
		plusbutton:setImageSize(plusbutton:getSize())
		minusbutton:setImageSize(minusbutton:getSize())
		plusbutton:addAnchor(AnchorRight, evsystem:recursiveGetChildById('text'..i), AnchorLeft)
		minusbutton:addAnchor(AnchorRight, evsystem:recursiveGetChildById('text'..i), AnchorLeft)
		plusbutton:addAnchor(AnchorBottom, evsystem:recursiveGetChildById('text'..i), AnchorTop)
		minusbutton:addAnchor(AnchorBottom, evsystem:recursiveGetChildById('text'..i), AnchorTop)
		plusbutton:setMarginLeft(130)
		minusbutton:setMarginLeft(110)
		plusbutton:setMarginTop(startY + ((i-1) * 22))
		minusbutton:setMarginTop(startY - 2 + ((i-1) * 22))
		plusbutton.onClick = function() if tonumber(evsystem:recursiveGetChildById('text7'):getText()) >= 1 and tonumber(evsystem:recursiveGetChildById('text'..i):getText()) < 150 then evsystem:recursiveGetChildById('text'..i):setText(tonumber(evsystem:recursiveGetChildById('text'..i):getText())+1)		evsystem:recursiveGetChildById('text7'):setText(tonumber(evsystem:recursiveGetChildById('text7'):getText())-1) end end
		minusbutton.onClick = function() if tonumber(evsystem:recursiveGetChildById('text'..i):getText()) > tonumber(evs[i]) then evsystem:recursiveGetChildById('text'..i):setText(tonumber(evsystem:recursiveGetChildById('text'..i):getText())-1) evsystem:recursiveGetChildById('text7'):setText(tonumber(evsystem:recursiveGetChildById('text7'):getText())+1) end end
	end
	icon = g_ui.createWidget('TextUI',evsystem)
	icon:setId('ev7')
	icon:setText(ev[7])
	icon:setWidth(75)
	icon:setMarginLeft(10)
	icon:setMarginTop(startY + (6 * 22) + 10)
	icon:setPhantom(true)
	text = g_ui.createWidget('TextUI',evsystem)
	text:setId('text7')
	text:setText(evs[7])
	text:setMarginLeft(85)
	text:setMarginTop(startY + (6 * 22) + 10)
	text:setPhantom(true)
	buy = g_ui.createWidget('TMButton',evsystem)
	buy:setId('buybutton7')
	local path = "interface/button.png"
	buy:setImageSource(path)
	buy:setMarginTop(startY + (6 * 22) + 42)
	buy:setMarginLeft(50)
	buy:setWidth(68)
	buy:setHeight(22)
	buy:setSize(buy:getSize())
	buy:setImageSize(buy:getSize())
	buy:setText('CONFIRM')
	buy:setVisible(true)
	buy.onClick = function() sendEvs(tonumber(evsystem:recursiveGetChildById('text1'):getText()), tonumber(evsystem:recursiveGetChildById('text2'):getText()), tonumber(evsystem:recursiveGetChildById('text3'):getText()), tonumber(evsystem:recursiveGetChildById('text4'):getText()), tonumber(evsystem:recursiveGetChildById('text5'):getText()), tonumber(evsystem:recursiveGetChildById('text6'):getText()), tonumber(evsystem:recursiveGetChildById('text7'):getText()), evs[8]) end
	evsystem:recursiveGetChildById('returnbutton'):hide()
	evsystem:setHeight(235)
	evsystem:setWidth(175)
end

function sendEvs(evhp, evatk, evdef, evspatk, evspdef, evspeed, evpts, name)
  if acceptWindow then
    return true
  end

  local acceptFunc = function()
    g_game.talk("#evsystem "..evhp.."|"..evatk.."|"..evdef.."|"..evspatk.."|"..evspdef.."|"..evspeed.."|"..evpts.."|"..name)
	hide()
	destroyApps()
	acceptWindow:destroy()
	acceptWindow = nil
  end

  local cancelFunc = function() acceptWindow:destroy() acceptWindow = nil end

  local msg = "Voce deseja adicionar ao seu "..name..":\n"..
    (evhp - evs[1]).." pontos em HP\n"..
    (evatk - evs[2]).." pontos em ATK\n"..
    (evdef - evs[3]).." pontos em DEF\n"..
    (evspatk - evs[4]).." pontos em SP.ATK\n"..
    (evspdef - evs[5]).." pontos em SP.DEF\n"..
    (evspeed - evs[6]).." pontos em SPEED\n"..
    "Voce vai gastar: "..(evs[7] - evpts).." pontos."

  acceptWindow = displayGeneralBox(tr('Atribuir EVs'), tr(msg),
  { { text=tr('Yes'), callback=acceptFunc },
    { text=tr('No'), callback=cancelFunc },
    anchor=AnchorHorizontalCenter }, acceptFunc, cancelFunc)
  return true
end