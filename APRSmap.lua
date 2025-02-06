local debugging = false

module(..., package.seeall)

local toast = require("toast");
local colors = require("colors");
local stations = require('stationList')
local QSOs = require('QSOs')
--local QSO = require('QSO')

print("APRSmap:Loading APRSIS")
APRSIS = require("APRSIS")

print("APRSmap:Loading osmTiles")
osmTiles = require("osmTiles")	-- This currently sets the Z order of the map

local myWidth, myHeight

local RenderPassCount, totalDrawCount, totalRenderCount, totalRenderTime = 0, 0, 0, 0
local lastRenderWhen = 0

if MOAIRenderMgr and type(MOAIRenderMgr.setRenderCallback) == 'function' then
	MOAIRenderMgr:setRenderCallback(
				function(lastDrawCount, lastRenderCount, lastRenderTime)
					RenderPassCount = RenderPassCount + 1
					totalDrawCount = totalDrawCount + lastDrawCount
					totalRenderCount = totalRenderCount + lastRenderCount
					totalRenderTime = totalRenderTime + lastRenderTime
--local now = MOAISim.getDeviceTime()
--print("APRSmap:renderCallback["..RenderPassCount.."]:Draw:"..lastDrawCount.." Render:"..lastRenderCount.." in:"..math.floor(lastRenderTime*1000).."ms dt:"..math.floor((now-lastRenderWhen)*1000))
--lastRenderWhen = now
				end)
end

local memoryText, messageButton
local lastFrameCount = MOAISim.getElapsedFrames()
local lastMemoryTime = MOAISim.getDeviceTime()
local entryCount = 0

local hasProcStatm

local function getVirtualResident()
	if hasProcStatm == nil or hasProcStatm then
		local hFile, err = io.open("/proc/self/statm","r")
		if hFile and not err then
			local xmlText=hFile:read("*a"); -- read file content
			io.close(hFile);
			local s, e, virtual, resident = string.find(xmlText, "(%d+)%s(%d+)")
			if virtual and resident then
				hasProcStatm = true
				return tonumber(virtual)*4096, tonumber(resident)*4096
			else
				hasProcStam = false
			end
		else
			hasProcStatm = false
			print( err )
		end
	end
	return nil
end

local function updateMemoryUsage()
	local newCount = MOAISim.getElapsedFrames()
	local localCount = newCount - lastFrameCount
	lastFrameCount = newCount
	local now = MOAISim.getDeviceTime()
	local elapsed = now-lastMemoryTime
	local fps = 0
	if elapsed > 0 then
		fps = localCount / (now-lastMemoryTime)
	end
	lastMemoryTime = now
	local memuse = MOAISim:getMemoryUsage()
	if not (type(memuse._sys_vs) == 'number' and type(memuse._sys_rss) == 'number') then
		memuse._sys_vs, memuse._sys_rss = getVirtualResident()
	end

	local avgDraws, avgRenders, avgRenderTime, renderPercent = 0,0,0,0
	
	if RenderPassCount > 0 then
		avgDraws = totalDrawCount / RenderPassCount
		avgRenders = totalRenderCount / RenderPassCount
		avgRenderTime = totalRenderTime / RenderPassCount
	end
	if elapsed > 0 then
		renderPercent = totalRenderTime / elapsed * 100
	end
	local mbMult = 1/1024/1024
	local text
	if Application.viewWidth > Application.viewHeight then	-- wider screens get more info
		text = string.format('%.1f+%.1f=%.1fMB%s fps:%.1f/%.1f/%i %i(%i)@%.1fms=%.1f%%',
								memuse.lua*mbMult,
								memuse.texture*mbMult,
								memuse.total*mbMult,
	((type(memuse._sys_vs) == 'number' and type(memuse._sys_rss) == 'number')
		and ("("..math.floor(memuse._sys_rss*mbMult).."/"..math.floor(memuse._sys_vs*mbMult).."MB)")
		or ""),
								fps, MOAISim.getPerformance(), RenderPassCount,
								avgRenders, avgDraws, avgRenderTime*1000, renderPercent)
	else text = string.format('%.0f+%.0f=%.0fMB%s %ifps %i(%i)=%.0f%%',
								memuse.lua*mbMult,
								memuse.texture*mbMult,
								memuse.total*mbMult,
	((type(memuse._sys_vs) == 'number' and type(memuse._sys_rss) == 'number')
		and ("("..math.floor(memuse._sys_rss*mbMult).."/"..math.floor(memuse._sys_vs*mbMult).."MB)")
		or ""),
								RenderPassCount,
								avgRenders, avgDraws, renderPercent)
	end
	RenderPassCount, totalDrawCount, totalRenderCount, totalRenderTime = 0, 0, 0, 0

	if memoryText then
		if debugging then print(os.date("%H:%M:%S ")..text) end
		memoryText:setString(text)
		memoryText:fitSize()
		memoryText:setLoc(Application.viewWidth/2, 55*config.Screen.scale)
		--memoryText:fitSize(#text)
	else print(text)
	end
end
performWithDelay( 1000, updateMemoryUsage, 0)

local function positionMessageButton(width, height)
    if messageButton then messageButton:setRight(width-10) messageButton:setTop(50*config.Screen.scale) end
end

local function runQSOsButton(layer, myWidth, myHeight)
	local function checkQSOsButton()
		local current = SceneManager:getCurrentScene()
		local new = QSOs:getMessageCount()	-- Get all new message count
		if current.name == 'APRSmap' then	-- Only if I'm current
			if new > 0 then
				if not messageButton then
					local alpha = 0.75
					messageButton = Button {
						text = "QSOs",
						red=0*alpha, green=240/255*alpha, blue=0*alpha, alpha=alpha,
						size = {100, 66},
						layer=layer, priority=2000000000,
						onClick = function()
										SceneManager:openScene("QSOs_scene", {animation = "popIn", backAnimation = "popOut", })
									end,
					}
					messageButton:setScl(config.Screen.scale,config.Screen.scale,1)
					positionMessageButton(Application.viewWidth, Application.viewHeight)
					--messageButton:setRight(myWidth-10) messageButton:setTop(50*config.Screen.scale)
				end
			elseif messageButton then
				--layer:getPartition():removeProp(messageButton)
				messageButton:dispose()
				messageButton = nil
			end
			performWithDelay(5000,checkQSOsButton)
		elseif messageButton then
			--layer:getPartition():removeProp(messageButton)
			messageButton:dispose()
			messageButton = nil
		end
	end
	performWithDelay(1000,checkQSOsButton)
end

local function resizeHandler ( width, height )
	myWidth, myHeight = width, height
	--print('APRSmap:onResize:'..tostring(width)..'x'..tostring(height))
	APRSmap.backLayer:setSize(width,height)
	if APRSIS then APRSIS:mapResized(width,height) end
	tileLayer:setSize(width,height)
	layer:setSize(width,height)
	positionMessageButton(width, height)
	whytext:setLoc ( width/2, height-32*config.Screen.scale )
	gpstext:setLoc ( width/2, height-65*config.Screen.scale )
	memoryText:setLoc ( width/2, 55*config.Screen.scale)
	lwdtext:setLoc ( width/2, 75*config.Screen.scale )
--	if titleBackground then
--		titleGroup:removeChild(titleBackground)
--		titleBackground:dispose()
--	end
	titleBackground:setSize(width,40*config.Screen.scale)
--	titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
--    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
--	titleBackground:setPriority(2000000000)
--	titleGroup:addChild(titleBackground)
	local x,y = titleText:getSize()
	titleText:setLoc(width/2, 25*config.Screen.scale)
	if osmTiles then osmTiles:setSize(width, height) end
end

function onStart()
    print("APRSmap:onStart()")

	local iniLat, iniLon, iniZoom, iniAlpha = 27.996683, -80.659083, 12, 0.5
	if tonumber(config.lastMapLat) then iniLat = tonumber(config.lastMapLat) end
	if tonumber(config.lastMapLon) then iniLon = tonumber(config.lastMapLon) end
	if tonumber(config.lastMapZoom) then iniZoom = tonumber(config.lastMapZoom) end
	if tonumber(config.lastMapAlpha) then iniAlpha = tonumber(config.lastMapAlpha) end
	print("APRSmap:Starting osmTiles")
	osmTiles:start()
	print('APRSmap:moveTo:'..iniLat..' '..iniLon..' zoom:'..iniZoom)
	if debugging then
		osmTiles:moveTo(iniLat, iniLon, iniZoom)
	else
		local s, text = pcall(osmTiles.moveTo, osmTiles, iniLat, iniLon, iniZoom)
		if not s then print("APRSmap:onStart:moveTo Failed with "..tostring(text)) end
	end
	print('APRSmap:setTileAlpha:'..iniAlpha)
	osmTiles:setTileAlpha(iniAlpha)
	osmTiles:showLabels(not config.lastLabels)	-- lastLabels flags suppression

	print("APRSmap:setupME w/osmTiles")
	stations:setupME(osmTiles)	-- Have to tell the station list about the map module

	print("APRSmap:starting APRSIS w/config")
	APRSIS:start(config)

end

function onResume()
    print("APRSmap:onResume()")
	if Application.viewWidth ~= myWidth or Application.viewHeight ~= myHeight then
		print("APRSmap:onResume():Resizing...")
		resizeHandler(Application.viewWidth, Application.viewHeight)
	end
	runQSOsButton(layer, Application.viewWidth, Application.viewHeight)
end

function onPause()
    print("APRSmap:onPause()")
end

function onStop()
    print("APRSmap:onStop()")
end

function onDestroy()
    print("APRSmap:onDestroy()")
end

function onEnterFrame()
    --print("onEnterFrame()")
end

function onKeyDown(event)
    print("APRSmap:onKeyDown(event)")
end

function onKeyUp(event)
    print("APRSmap:onKeyUp(event)")
end

local touchDowns = {}

function onTouchDown(event)
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
--    print("APRSmap:onTouchDown(event)@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchDown', event))
	touchDowns[event.idx] = {x=event.x, y=event.y}
end

function onTouchUp(event)
	local wx, wy = layer:wndToWorld(event.x, event.y, 0)
--    print("APRSmap:onTouchUp(event)@"..tostring(wx)..','..tostring(wy)..printableTable(' onTouchUp', event))
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
--[[
		local props = {layer:getPartition():propListForPoint(wx, wy, 0, sortMode)}
		for i = #props, 1, -1 do
			local prop = props[i]
			if prop:getAttr(MOAIProp.ATTR_VISIBLE) > 0 then
				print('APRSmap:Found prop..'..tostring(prop)..' with '..tostring(type(prop.onTap)))
			end
		end
]]
--    SceneManager:closeScene({animation = "popOut"})
end

function onTouchMove(event)
    --print("APRSmap:onTouchMove(event)")
	if touchDowns[event.idx] then
		local dx = event.x - touchDowns[event.idx].x
		local dy = event.y - touchDowns[event.idx].y
		--print(string.format('APRSmap:onTouchMove:dx=%i dy=%i moveX=%i moveY=%i',
		--					dx, dy, event.moveX, event.moveY))
		osmTiles:deltaMove(event.moveX, event.moveY)
	end
end

local objectCounts

function onCreate(e)
	print('APRSmap:onCreate')
--[[
do
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?()&/-"
	local index = 1
	local sprite, temptext, sizetext
	local paused = false
	performWithDelay(1000, function()
	if not paused then
	local c = chars:sub(index,index)
	index = index + 1
	if index > #chars then index = 1 end
	if sprite then sprite:dispose() end
	if sizetext then sizetext:dispose() end
	if temptext then temptext:dispose() end
	print("Doing:"..c)
	local font = FontManager:getRecentFont()
	local fontImage, xBearing, yBearing = font:getGlyphImage(c, 18*.7)
	if fontImage then
		local width, height = fontImage:getSize()
		fontImage:drawLine(0,yBearing,width-1,yBearing,0,0,0,1.0)
		fontImage:drawLine(0,yBearing+1,width-1,yBearing+1,0,0,0,1.0)
		fontImage:drawLine(0,height-1,width-1,height-1,0,0,0,1.0)
		fontImage:drawLine(xBearing,0,xBearing,height-1,0,0,0,1.0)
		sprite = Sprite{texture=fontImage, layer=layer}
		print("getGlyphImage("..c..") returned "..tostring(fontImage).." size "..sprite:getWidth().." x "..sprite:getHeight().." Bearing:"..xBearing.." "..yBearing)
		--sprite:setColor(1,0,0,0.5)
		sprite:setLeft(0) sprite:setTop(titleBackground:getBottom())
		sprite:addEventListener( "touchUp", function() paused = not paused end )
	sizetext = TextLabel { text=tostring(width)..'x'..tostring(height)..' '..tostring(xBearing)..' '..tostring(yBearing), layer=layer }
	sizetext:setColor(0,0,0, 1.0)
	sizetext:fitSize()
	sizetext:setLeft(sprite:getRight()) sizetext:setTop(sprite:getTop()+sprite:getHeight()/2)

	end
	temptext = TextLabel { text=c..".", layer=layer, textSize=18*.7 }
	temptext:setColor(0,0,0, 1.0)
	temptext:fitSize()
	temptext:setLeft(0) temptext:setTop(sprite:getBottom())
	end
	end, 0)
end
]]
	print("APRSmap:setting APRSIS callbacks")
	APRSIS:setAppName(MOAIEnvironment.appDisplayName,MOAIEnvironment.appVersion)
	APRSIS:setPacketCallback(stations.packetReceived)	-- Tie the two together!
	APRSIS:setConnectedCallback(function(clientServer) print("APRSmap:connected:"..tostring(clientServer)) end)

	local width, height = Application.viewWidth, Application.viewHeight
	myWidth, myHeight = width, height

	scene.resizeHandler = resizeHandler
	scene.menuHandler = function()
							SceneManager:openScene("buttons_scene", {animation="overlay"})
						end

	APRSmap.backLayer = Layer {scene = scene }
	if type(APRSmap.backLayer.setClearColor) == 'function' then 
	if config.lastDim then	-- Dim
		APRSmap.backLayer:setClearColor ( 0,0,0,1 )	-- Black background
	else	-- Bright
		APRSmap.backLayer:setClearColor ( 1,1,1,1 )	-- White background
	end
	else print('setClearColor='..type(APRSmap.backLayer.setClearColor))
	end

	tileLayer = Layer { scene = scene, touchEnabled = true }
	--tileLayer:setAlpha(0.9)
	local alpha = 0.75
	tileLayer:setColor(alpha,alpha,alpha,alpha)
	osmTiles:getTileGroup():setLayer(tileLayer)

    layer = Layer {scene = scene, touchEnabled = true }

	lwdtext = TextLabel { text="lwdText", layer=layer, textSize=20*config.Screen.scale }
_G["lwdtext"] = lwdtext
	lwdtext:setColor(0.25, 0.25, 0.25, 1.0)
	lwdtext:fitSize()
	--lwdtext:setWidth(width)
	lwdtext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	lwdtext:setLoc(width/2, 75*config.Screen.scale)
local x,y = lwdtext:getSize()
	lwdtext:setPriority(2000000000)

	whytext = TextLabel { text="whyText", layer=layer, textSize=32*config.Screen.scale }
_G["whytext"] = whytext
	whytext:setColor(0.5, 0.5, 0.5, 1.0)
	whytext:fitSize()
	--whytext:setWidth(width)
	whytext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	whytext:setLoc(width/2, height-32*config.Screen.scale)
local x,y = whytext:getSize()
	whytext:setPriority(2000000000)

	gpstext = TextLabel { text="gpsText", layer=layer, textSize=22*config.Screen.scale }
_G["gpstext"] = gpstext
	gpstext:setColor(0.5, 0.5, 0.5, 1.0)
	gpstext:fitSize()
	gpstext:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	gpstext:setLoc(width/2, height-65*config.Screen.scale)
	gpstext:setPriority(2000000000)

	memoryText = TextLabel { text="memoryText", layer=layer, textSize=20*config.Screen.scale }
	memoryText:setColor(0.25, 0.25, 0.25, 1.0)
	memoryText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	memoryText:setLoc(width/2, 55*config.Screen.scale)
--	memoryText:setPriority(2000000000)
	memoryText:setPriority(1999999999)
	memoryText:addEventListener("touchUp",
			function()
				print("Collecting Garbage")
if Application:isDesktop() then
				stations:clearStations()
end
				MOAISim:forceGarbageCollection()	-- This does it iteratively!
if Application:isDesktop() then
	print ( "REPORTING HISTOGRAM" )
	MOAISim.reportHistogram ()
	MOAISim.reportLeaks(true)	-- report leaks and reset the bar for next time
	print ()
	
	if not objectCounts then objectCounts = {} end
	local didOne = false
	local histogram = MOAISim.getHistogram ()
	for k, v in pairs ( histogram ) do
		if objectCounts[k] and objectCounts[k] ~= v then
			print('memoryText:Delta('..tostring(v-objectCounts[k])..') '..k..' objects')
			didOne = true
		end
		objectCounts[k] = v
	end
	if didOne then print() end
end
				updateMemoryUsage()
			end)

			
    titleGroup = Group { layer=layer }
	titleGroup:setLayer(layer)

	titleGradientColors = { "#BDCBDC", "#BDCBDC", "#897498", "#897498" }
--	local colors = { "#DCCBBD", "#DCCBBD", "#987489", "#987489" }
 --	{ 189, 203, 220, 255 }, 
--	{ 89, 116, 152, 255 }, "down" )

    -- Parameters: left, top, width, height, colors
    --titleBackground = Mesh.newRect(0, 0, width, 40, titleGradientColors )
	titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
    --titleBackground:setPenColor(0.707, 0.8125, 0.8125, 0.75):fillRect()	-- 181,208,208 from OSM zoom 0 map
    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
	titleBackground:setPriority(2000000000)
	titleGroup:addChild(titleBackground)

	titleText = TextLabel { text="APRSISMO", textSize=28*config.Screen.scale }
	titleText:fitSize()
	titleText:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
	titleText:setLoc(width/2, 20*config.Screen.scale)
	titleText:setPriority(2000000001)
	titleGroup:addChild(titleText)
	--titleGroup:setRGBA(1,1,1,0.75)
_G["titleText"] = titleText

    --titleGroup:resizeForChildren()
	--titleGroup:setLoc(0,0)
	titleGroup:addEventListener("touchUp",
			function()
				print("Tapped TitleGroup")
				scene.menuHandler()
--[[
				local text = tostring(MOAIEnvironment.appDisplayName)..' '..tostring(MOAIEnvironment.appVersion)
				text = text..' @ '..tostring(MOAIEnvironment.screenDpi)..'dpi'
				text = text..'\r\ncache:'..tostring(MOAIEnvironment.cacheDirectory)
				text = text..'\r\ndocument:'..tostring(MOAIEnvironment.documentDirectory)
				text = text..'\r\nextCache:'..tostring(MOAIEnvironment.externalCacheDirectory)
				text = text..'\r\nextFiles:'..tostring(MOAIEnvironment.externalFilesDirectory)
				text = text..'\r\nresource:'..tostring(MOAIEnvironment.resourceDirectory)
				toast.new(text)
				print(text)
]]
			end)
			
	updateGPSEnabled()	-- get the colors right
	updateKeepAwake()	-- get the colors right
	
--[[
	testWedge = Graphics { layer=layer, left=0, top=0, width=100, height=100 }
	testWedge:setPenColor(0,0,0,0.25):setPenWidth(1):fillFan({0,0,100,90,90,100,75,200,0,0})
	--testWedge:setScl(2,2,2)
	testWedge:setPriority(3000000)
]]
end
