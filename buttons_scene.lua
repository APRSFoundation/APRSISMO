module(..., package.seeall)

local toast = require("toast");
local colors = require("colors");
local stations = require('stationList')
local QSOs = require('QSOs')
--local QSO = require('QSO')

APRSIS = require("APRSIS")

osmTiles = require("osmTiles")	-- This currently sets the Z order of the map

local buttonAlpha = 0.8

local myWidth, myHeight

local function closeScene()
	SceneManager:closeScene({animation="popOut"})
end

local closeTimer
local function cancelTimer()
	if closeTimer then
		closeTimer:stop()
		closeTimer = nil
	end
end

local function resetTimer()
	cancelTimer()
	closeTimer = performWithDelay(5000, function() closeScene() end)
end

local squares	-- centering squares
local r, g, b	-- boundary squares
local o, ot, ot2, ob	-- DPI square and label

local function reCreateSquares(width, height)
	local partition = layer:getPartition()
--[[
	if r then partition:removeProp(r) r:dispose() end
	r = Graphics {width = width+2, height = height+2, left = -1, top = -1, layer = layer}
    r:setPenColor(1, 0, 0, 1):drawRect()
	if g then partition:removeProp(g) g:dispose() end
	g = Graphics {width = width+0, height = height+0, left = 0, top = 0, layer = layer}
    g:setPenColor(0, 1, 0, 1):drawRect()
	if b then partition:removeProp(b) b:dispose() end
	b = Graphics {width = width-2, height = height-2, left = 1, top = 1, layer = layer}
    b:setPenColor(0, 0, 1, 1):drawRect()
]]
--[[
	if MOAIEnvironment.screenDpi and MOAIEnvironment.screenDpi > 0 then
		local l = MOAIEnvironment.screenDpi
		if o then partition:removeProp(o) o:dispose() end
		o = Graphics {width = l, height = l, left = l/4, top = l/4, layer = layer}
		o:setPenColor(0, 0, 0, 1):setPenWidth(3):drawRect()
		if ot then partition:removeProp(ot) ot:dispose() end
		ot = TextLabel { text=tostring(MOAIEnvironment.screenDpi), textSize=l/4, layer=layer }
		ot:fitSize()
		ot:setColor(0,0,0,1)
		ot:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		ot:setLoc(l/2+l/4, l/2+l/4)
		if ot2 then partition:removeProp(ot2) ot2:dispose() end
		ot2 = TextLabel { text=tostring(width)..'x'..tostring(height), textSize=l/8, layer=layer }
		ot2:fitSize()
		ot2:setColor(0,0,0,1)
		ot2:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
		ot2:setLoc(l/2+l/4, l-l/8+l/4)
		local obSize = l*3/8
		if ob then partition:removeProp(ob) ob:dispose() end
		ob = Graphics {width = obSize, height = obSize, left = 5, top = height-5-obSize, layer = layer}
		ob:setPenColor(0, 0, 0, 1):setPenWidth(3):drawRect()
	end
]]
--[[
	if squares then
		for k,v in pairs(squares) do
			partition:removeProp(v)
			v:dispose()
		end
	end
	squares = {}
	for i=50,1000,50 do
		squares[i] = Graphics { width=i*2, height=i*2, left=width/2-i, top = height/2-i, layer=layer }
		squares[i]:setPenColor(1,1,0,0.75):drawRect()
	end
]]
end
local function fixButtonColors()
	local zoom, zoomMax = osmTiles:getZoom()
	if zoom == 0 then
		inButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		in3Button:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		outButton:setColor(buttonAlpha/2, buttonAlpha/2, buttonAlpha/2, buttonAlpha/2)
		out3Button:setColor(buttonAlpha/2, buttonAlpha/2, buttonAlpha/2, buttonAlpha/2)
	elseif zoom == zoomMax then
		inButton:setColor(buttonAlpha/2, buttonAlpha/2, buttonAlpha/2, buttonAlpha/2)
		in3Button:setColor(buttonAlpha/2, buttonAlpha/2, buttonAlpha/2, buttonAlpha/2)
		outButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		out3Button:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
	else
		inButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		in3Button:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		outButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		out3Button:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
	end
	if config.lastDim then
		--brightButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
		dimButton:setColor(1.0, buttonAlpha, buttonAlpha, buttonAlpha)
		dimButton:setText("Dim")
	else
		dimButton:setColor(buttonAlpha, 1.0, buttonAlpha, buttonAlpha)
		dimButton:setText("Bright")
		--dimButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
	end
	if config.lastRadar then
		radarButton:setColor(buttonAlpha, 1.0, buttonAlpha, buttonAlpha)
	else
		radarButton:setColor(1.0, buttonAlpha, buttonAlpha, buttonAlpha)
	end
	if config.lastLabels then	-- lastLabels flags SUPPRESSION!
		labelButton:setColor(1.0, buttonAlpha, buttonAlpha, buttonAlpha)
	else
		labelButton:setColor(buttonAlpha, 1.0, buttonAlpha, buttonAlpha)
	end
	local onDivisor = 2
	if MOAIInputMgr.device.location then
		onDivisor = 1
	end
	if config.Enables.GPS then
		gpsButton:setColor(buttonAlpha/onDivisor, 1.0/onDivisor, buttonAlpha/onDivisor, buttonAlpha/onDivisor)
		--offButton:setColor(buttonAlpha, buttonAlpha, buttonAlpha, buttonAlpha)
	else
		--gpsButton:setColor(buttonAlpha/onDivisor, buttonAlpha/onDivisor, buttonAlpha/onDivisor, buttonAlpha/onDivisor)
		gpsButton:setColor(1.0, buttonAlpha, buttonAlpha, buttonAlpha)
	end
end

local function reCreateButtons(width,height)
	if buttonView then buttonView:setScene(nil) buttonView:setLayer(nil) buttonView:dispose() end
	
    buttonView = View {
        scene = scene,
		priority = 2000000000,
    }
--	buttonView = layer

    configureButton = Button {
        text = "Config",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						config:configure()
					end,

    }
	configureButton:setScl(config.Screen.scale,config.Screen.scale,1)

    debugButton = Button {
        text = "Debug",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						toggleDebugLines()
						resetTimer()
					end,
    }
	debugButton:setScl(config.Screen.scale,config.Screen.scale,1)

    messageButton = Button {
        text = "QSOs",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						SceneManager:openNextScene("QSOs_scene", {animation = "popIn", backAnimation = "popOut", })
					end,
    }
	messageButton:setScl(config.Screen.scale,config.Screen.scale,1)
    inButton = Button {
        text = "+", textSize = 32,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(1) fixButtonColors() resetTimer() end,
    }
	inButton:setScl(config.Screen.scale,config.Screen.scale,1)
    in3Button = Button {
        text = "+++", textSize = 16,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(3) fixButtonColors() resetTimer() end,
    }
	in3Button:setScl(config.Screen.scale,config.Screen.scale,1)
    outButton = Button {
        text = "-", textSize = 32,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(-1) fixButtonColors() resetTimer() end,
    }
	outButton:setScl(config.Screen.scale,config.Screen.scale,1)
    out3Button = Button {
        text = "- - -", textSize = 20,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {50, 66},
        parent = buttonView, priority=2000000000,
        onClick = function() osmTiles:deltaZoom(-3) fixButtonColors() resetTimer() end,
    }
	out3Button:setScl(config.Screen.scale,config.Screen.scale,1)
    oneButton = Button {
        text = "One",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
					local zoom, zoomMax = osmTiles:getZoom()
						osmTiles:zoomTo(zoomMax)
						stations:updateCenterStation()	-- re-center on current center
						fixButtonColors()
						resetTimer()
					end,
    }
	oneButton:setScl(config.Screen.scale,config.Screen.scale,1)
    allButton = Button {
        text = "All",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
--[[
						local xs = myWidth / 256
						local ys = myHeight / 256
						osmTiles:zoomTo(math.min(xs,ys))
]]
						osmTiles:showAll()
						fixButtonColors()
						resetTimer()
					end,
    }
	allButton:setScl(config.Screen.scale,config.Screen.scale,1)
--[[
    brightButton = Button {
        text = "Bright",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						config.lastDim = false
						if type(APRSmap.backLayer.setClearColor) == 'function' then
							APRSmap.backLayer:setClearColor ( 1,1,1,1 )	-- White background
						end
						fixButtonColors()
						resetTimer()
					end,
    }
	brightButton:setScl(config.Screen.scale,config.Screen.scale,1)
]]
    radarButton = Button {
        text = "Radar",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						config.lastRadar = not config.lastRadar
						radar = require("radar")
						if radar then radar:setEnable(config.lastRadar) end
						fixButtonColors()
						resetTimer()
					end,
    }
	radarButton:setScl(config.Screen.scale,config.Screen.scale,1)
    dimButton = Button {
        text = "Dim",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
						config.lastDim = not config.lastDim
						if type(APRSmap.backLayer.setClearColor) == 'function' then
							if config.lastDim then
								APRSmap.backLayer:setClearColor ( 0,0,0,1 )	-- Black background
							else APRSmap.backLayer:setClearColor ( 1,1,1,1 )	-- White background
							end
						end
						fixButtonColors()
						resetTimer()
					end,
    }
	dimButton:setScl(config.Screen.scale,config.Screen.scale,1)
    gpsButton = Button {
        text = "GPS",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						config.Enables.GPS = not config.Enables.GPS
						updateGPSEnabled()
						fixButtonColors()
						resetTimer()
					end,
    }
	gpsButton:setScl(config.Screen.scale,config.Screen.scale,1)
--[[
    offButton = Button {
        text = "Off",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
						config.Enables.GPS = false
						updateGPSEnabled()
						fixButtonColors()
						resetTimer()
					end,
    }
	offButton:setScl(config.Screen.scale,config.Screen.scale,1)
]]

    labelButton = Button {
        text = "Labels",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66},
        parent = buttonView, priority=2000000000,
        onClick = function()
						config.lastLabels = not config.lastLabels
						osmTiles:showLabels(not config.lastLabels)	-- lastLables flags suppression
						fixButtonColors()
						resetTimer()
					end,
    }
	labelButton:setScl(config.Screen.scale,config.Screen.scale,1)
--[[
    off2Button = Button {
        text = "Off",
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
						osmTiles:showLabels(false)
						resetTimer()
					end,
    }
	off2Button:setScl(config.Screen.scale,config.Screen.scale,1)
]]
	
--        textSize = 24,

    meButton = Button {
        text = "ME", textSize = 24,	-- default is 24
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
						--osmTiles:removeTapGroup()
						local tileGroup = osmTiles:getTileGroup()
						local lat, lon = tileGroup.lat, tileGroup.lon
						local center = stations:getCenterStation()

						myStation.gotLocation = true
						print(center.stationID..' vs '..myStation.stationID..' delta '..lat-myStation.lat..' '..lon-myStation.lon)
						--if center == myStation or (lat == myStation.lat and lon == myStation.lon) then
							stations:updateCenterStation(myStation)	-- move and track
						--else								-- otherwise just move and require a center tap
						--	osmTiles:moveTo(myStation.lat, myStation.lon)
						--end
						resetTimer()	-- Only if not closing scene
						-- closeScene()	-- Don't close scene as I'm normally zooming too
						return true
					end,
    }
	meButton:fitSize()
	meButton:setScl(config.Screen.scale,config.Screen.scale,1)

	--local tempWidth = display.newText("WWWWWW-WW", 0, 0, native.systemFont, 14)	-- 14 is the default for buttons
	local whoStation = stations:getCenterStation()
	local whoButton
	if whoStation ~= myStation then
		local whoLabel
		if not whoStation or not whoStation.stationID then whoLabel = "WWWWWW-WW" else whoLabel = whoStation.stationID end
		whoButton = Button {
			text = whoLabel, --textSize = 12,	-- default is 24
			red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
			size = {100, 66}, priority=2000000000,
			parent = buttonView, priority=2000000000,
			onClick = function()
							--osmTiles:removeTapGroup()
							print('whoButton:click:centerStation='..tostring(stations:getCenterStation()))
							stations:updateCenterStation(whoStation)
							resetTimer()	-- Only if not closing scene
							--closeScene()
							return true
						end,
		}
		whoButton:fitSize()
		whoButton:setScl(config.Screen.scale,config.Screen.scale,1)
	end
	--tempWidth:removeSelf()

    xmitButton = Button {
        text = "Xmit", textSize = 24,
		--styles = { textSize = 12, },	-- default is 24
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
--[[
local tileGroup = osmTiles:getTileGroup()
if not config.Enables.GPS
and MOAIDialog and type(MOAIDialog.showDialog) == 'function'
and not AreCoordinatesEquivalent(tileGroup.lat, tileGroup.lon,
							myStation.lat, myStation.lon, 2) then
	MOAIDialog.showDialog('Move ME', "Move ME To Center?", 'Yes', nil, 'No', true, 
				function(result)
print("MoveME:result="..tostring(result))
					if result == MOAIDialogAndroid.DIALOG_RESULT_POSITIVE then
						moveME(tileGroup.lat, tileGroup.lon)
						local status = APRSIS:triggerPosit('Moved')
						toast.new(status or 'Posit Sent', 2000)
					elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEUTRAL then
					elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEGATIVE then
						myStation.gotLocation = true
						local status = APRSIS:triggerPosit('FORCE')
						toast.new(status or 'Posit Sent', 2000)
					elseif result == MOAIDialogAndroid.DIALOG_RESULT_CANCEL then
					end
				end)
else]]
	myStation.gotLocation = true
	local status = APRSIS:triggerPosit('FORCE')
	toast.new(status or 'Posit Sent', 2000)
--end
					closeScene()
					return true
				end
    }
	xmitButton:fitSize()
	xmitButton:setScl(config.Screen.scale,config.Screen.scale,1)
	if not config.Enables.GPS
	and osmTiles and osmTiles:getZoom() > 15 then
    moveButton = Button {
        text = "Move", textSize = 24,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
local tileGroup = osmTiles:getTileGroup()
if not config.Enables.GPS
and not AreCoordinatesEquivalent(tileGroup.lat, tileGroup.lon,
							myStation.lat, myStation.lon, 2) then
if MOAIDialog and type(MOAIDialog.showDialog) == 'function' then
	MOAIDialog.showDialog('Move ME', "Move ME To Center?", 'Yes', nil, 'No', true, 
				function(result)
print("MoveME:result="..tostring(result))
					if result == MOAIDialogAndroid.DIALOG_RESULT_POSITIVE then
						addCrumb(tileGroup.lat, tileGroup.lon, nil, "MoveME")
						moveME(tileGroup.lat, tileGroup.lon)
						local status = APRSIS:triggerPosit('Moved')
						toast.new(status or 'ME Moved', 2000)
					elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEUTRAL then
					elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEGATIVE then
					elseif result == MOAIDialogAndroid.DIALOG_RESULT_CANCEL then
					end
				end)
else
	addCrumb(tileGroup.lat, tileGroup.lon, nil, "MoveME")
	moveME(tileGroup.lat, tileGroup.lon)
	local status = APRSIS:triggerPosit('Moved')
	toast.new(status or 'ME Moved', 2000)
end
					closeScene()
end
					return true
					end,
    }
	moveButton:fitSize()
	moveButton:setScl(config.Screen.scale,config.Screen.scale,1)
	else moveButton = nil
	end

	local issAck
    issButton = Button {
        text = "ISS", textSize = 24,
		red=buttonAlpha, green=buttonAlpha, blue=buttonAlpha, alpha=buttonAlpha,
        size = {100, 66}, priority=2000000000,
        parent = buttonView, priority=2000000000,
        onClick = function()
					performWithDelay(500,function()
							issAck = (issAck or 0) + 1
							local whoFor = "ME"
							local centerStation = stations:getCenterStation()
							if centerStation ~= myStation then whoFor = centerStation.stationID end
							local msg = string.format('%s>APWA00,TCPIP*::%-9s:%s{%i', config.StationID, 'ISS', whoFor, issAck)
							local status = APRSIS:sendPacket(msg)
							print ('msgISS:'..msg)
							QSOs:newMessage("ME", "ISS", whoFor)
							toast.new(status or "Next Pass Requested", 3000)
						end
					)
					closeScene()
					return true
				end
    }
	print('issButton:'..issButton:getWidth()..'x'..issButton:getHeight())
	issButton:fitSize()
	print('issButton:'..issButton:getWidth()..'x'..issButton:getHeight())
	issButton:setScl(config.Screen.scale,config.Screen.scale,1)
	print('issButton:'..issButton:getWidth()..'x'..issButton:getHeight())

    configureButton:setLeft(10) configureButton:setTop(50*config.Screen.scale)
    debugButton:setLeft(configureButton:getRight()) debugButton:setTop(50*config.Screen.scale)
    if messageButton then messageButton:setRight(width-10) messageButton:setTop(50*config.Screen.scale) end
    in3Button:setRight(width-10) in3Button:setBottom(height-10)
    inButton:setRight(in3Button:getLeft()) inButton:setBottom(height-10)
    outButton:setRight(inButton:getLeft()) outButton:setBottom(height-10)
    out3Button:setRight(outButton:getLeft()) out3Button:setBottom(height-10)
    oneButton:setRight(width-10) oneButton:setBottom(inButton:getTop()-10)
    allButton:setRight(oneButton:getLeft()) allButton:setBottom(outButton:getTop()-10)
    dimButton:setLeft(10) dimButton:setBottom(height-10)
    --brightButton:setLeft(dimButton:getRight()) brightButton:setBottom(height-10)
    radarButton:setLeft(dimButton:getRight()) radarButton:setBottom(height-10)
	gpsButton:setLeft(10) gpsButton:setBottom(dimButton:getTop()-10)
	--gpsButton:setLeft(offButton:getRight()) gpsButton:setBottom(dimButton:getTop()-10)
	labelButton:setLeft(10) labelButton:setBottom(gpsButton:getTop()-10)
	--labelButton:setLeft(off2Button:getRight()) labelButton:setBottom(gpsButton:getTop()-10)
    meButton:setLeft((width-meButton:getWidth())/2) meButton:setTop(height/2+meButton:getHeight()*0.5)
    if moveButton then moveButton:setRight(width/2-meButton:getWidth()/2) moveButton:setTop(meButton:getTop()) end
    if whoButton then whoButton:setLeft((width-whoButton:getWidth())/2) whoButton:setBottom(height/2-whoButton:getHeight()*0.5) end
    if xmitButton then xmitButton:setRight(width/2-meButton:getWidth()/2) xmitButton:setBottom((height+xmitButton:getHeight())/2) end
    if issButton then issButton:setLeft(width/2+meButton:getWidth()/2) issButton:setBottom((height+issButton:getHeight())/2) end

	fixButtonColors()
end

local function resizeHandler ( width, height )
	myWidth, myHeight = width, height
	local mapScene = SceneManager:findSceneByName("APRSmap")
	if mapScene and type(mapScene.resizeHandler) == 'function' then
		mapScene.resizeHandler(width, height)
	end
	layer:setSize(width,height)
	reCreateSquares(width, height)
	reCreateButtons(width,height)
	titleBackground:setSize(width, 40*config.Screen.scale)
	local x,y = titleText:getSize()
	titleText:setLoc(width/2, 25*config.Screen.scale)
	resetTimer()
end

function onStart()
    print("Buttons:onStart()")
	resetTimer()
end

function onResume()
    print("Buttons:onResume()")
	if Application.viewWidth ~= myWidth or Application.viewHeight ~= myHeight then
		print("Buttons:onResume():Resizing...")
		resizeHandler(Application.viewWidth, Application.viewHeight)
	end
	resetTimer()
end

function onPause()
    print("Buttons:onPause()")
	cancelTimer()
end

function onStop()
    print("Buttons:onStop()")
	cancelTimer()
end

function onDestroy()
    print("Buttons:onDestroy()")
	cancelTimer()
end

function onEnterFrame()
    --print("onEnterFrame()")
end

function onKeyDown(event)
    print("Buttons:onKeyDown(event)")
end

function onKeyUp(event)
    print("Buttons:onKeyUp(event)")
end

local touchDowns = {}

function onTouchDown(event)
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
--    print("Buttons:onTouchDown(event)@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchDown', event))
	touchDowns[event.idx] = {x=event.x, y=event.y}
	cancelTimer()
end

function onTouchUp(event)
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
--    print("Buttons:onTouchUp(event)@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchUp', event))
	if touchDowns[event.idx] then
		local dy = event.y - touchDowns[event.idx].y
		if math.abs(dy) > Application.viewHeight * 0.10 then
			local dz = 1
			if dy > 0 then dz = -1 end
--[[			osmTiles:deltaZoom(dz)
		else
			config.lastDim = not config.lastDim
			if config.lastDim then	-- Dim
				backLayer:setClearColor ( 0,0,0,1 )	-- Black background
			else	-- Bright
				backLayer:setClearColor ( 1,1,1,1 )	-- White background
			end
]]		end
	end
--    SceneManager:closeScene({animation = "popOut"})
	resetTimer()
end

function onTouchMove(event)
    --print("Buttons:onTouchMove(event)")
	if touchDowns[event.idx] then
		local dx = event.x - touchDowns[event.idx].x
		local dy = event.y - touchDowns[event.idx].y
		--print(string.format('Buttons:onTouchMove:dx=%i dy=%i moveX=%i moveY=%i',
		--					dx, dy, event.moveX, event.moveY))
		osmTiles:deltaMove(event.moveX, event.moveY)
	end
end

function onCreate(e)
	print('buttons:onCreate')
	local width, height = Application.viewWidth, Application.viewHeight
	myWidth, myHeight = width, height

	scene.resizeHandler = resizeHandler
	scene.backHandler = closeScene
	scene.menuHandler = closeScene

    layer = Layer {scene = scene, touchEnabled = true }
	
	reCreateSquares(width,height)
	reCreateButtons(width,height)

    titleGroup = Group { layer=layer }
	titleGroup:setLayer(layer)

	titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
	titleBackground:setPriority(2000000000)
	titleGroup:addChild(titleBackground)
	
--[[
	fontImage = FontManager:getRecentImage()
	if fontImage then
		print("FontImage is "..tostring(fontImage))
		local sprite = Sprite{texture=fontImage, layer=layer}
		sprite:setPos((width-sprite:getWidth())/2, (height-sprite:getHeight())/2)
	end
]]

	titleText = TextLabel { text=tostring(MOAIEnvironment.appDisplayName)..' '..tostring(MOAIEnvironment.appVersion), textSize=28*config.Screen.scale }
	titleText:fitSize()
	titleText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	titleText:setLoc(width/2, 20*config.Screen.scale)
	titleText:setPriority(2000000001)
	titleGroup:addChild(titleText)

	titleGroup:addEventListener("touchUp",
			function()
				print("Tapped Button:TitleGroup")
				closeScene()
			end)
end
