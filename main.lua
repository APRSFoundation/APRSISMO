local debugLines = false

-- ----------------------------------------------------------------
-- Copyright (c) 2010-2011 Zipline Games, Inc. 
-- All Rights Reserved. 
-- http://getmoai.com
----------------------------------------------------------------

require "init"

local showIDs = { }
showIDs["ME"]=true
showIDs["crumbShort"]=true
showIDs["crumbsLong"]=true
showIDs["ME-trkseg"]=true
showIDs["ME-Tracks"]=true
showIDs["ISS"]=true
showIDs["KJ4ERJ-1"]=true
showIDs["KJ4ERJ-7"]=true
showIDs["KJ4ERJ-12"]=true
showIDs["KJ4ERJ-SM"]=true
showIDs["G6UIM"]=true 

function shouldIShowIt(ID)
	if Application:isMobile() then return true end
	return showIDs[ID]
end

if not MOAIEnvironment.appDisplayName or type(MOAIEnvironment.appDisplayName) ~= 'string' or #MOAIEnvironment.appDisplayName < 1 then
	print('main:MOAIEnvironment.appDisplayName is '..type(MOAIEnvironment.appDisplayName)..'('..tostring(MOAIEnvironment.appDisplayName)..')')
	MOAIEnvironment.appDisplayName = 'APRSISMO'
	print('main:Defining MOAIEnvironment.appDisplayName to '..tostring(MOAIEnvironment.appDisplayName))
end

if not MOAIEnvironment.appVersion then
	local recent = 0
	for file in lfs.dir(".") do
		local modified = lfs.attributes(file,"modification")
		--print(file..' modified '..os.date("%Y-%m-%d %H:%M", modified))
		if modified > recent then recent = modified end
	end
	if recent > 0 then
		MOAIEnvironment.appVersion = os.date("!%Y-%m-%d %H:%M", recent)
	else MOAIEnvironment.appVersion = '*Simulator*'
	end
end

local toast = require("toast");
local APRS = require("APRS")
local colors = require("colors");
local LatLon = require("latlon")
local APRSIS	-- required below as it auto-starts
local osmTiles	-- required at the end

local hp_modules = require "hp-modules"
local hp_config = require "hp-config"

if Application:isDesktop() then
	MOAISim.setHistogramEnabled ( true )
end

--local QSOs = require('QSOs')
--local QSO = require('QSO')

--local flower = require("flower")

function performWithDelay (delay, func, repeats, ...)
 local t = MOAITimer.new()
 if not func then func(unpack(arg)) end	-- Should not happen, but need to track it down!
 t:setSpan( delay/1000 )
 t:setListener( MOAITimer.EVENT_TIMER_END_SPAN,
   function ()
     t:stop()
     t = nil
     local result = func( unpack( arg ) )
		if result ~= 'cancel' and repeats then
			if repeats > 1 then
				performWithDelay( delay, func, repeats - 1, unpack( arg ) )
			elseif repeats == 0 then
			   performWithDelay( delay, func, 0, unpack( arg ) )
			end
		end
   end
 )
 t:start()
 return t
 end

function printableTable(w, t, s)
	s = s or ' '
	local r = 'Table['..w..'] ='
	if type(t) == 'table' then
function addValue(k,v)
	if type(v) == 'number' then v = string.format('%.3f', v) end
	r = r..s..tostring(k)..'='..tostring(v)
end
		local did = {}
		for k, v in ipairs(t) do	-- put the contiguous numerics in first
			did[k] = true
			addValue(k,v)
		end
		local f = nil	-- Comparison function?
		local a = {}
		for n in pairs(t) do	-- and now the non-numeric
			if not did[n] then
				table.insert(a, tostring(n))
			end
		end
		table.sort(a, f)
		for i, k in ipairs(a) do
			addValue(k,t[k])
		end
	else	r = r..' '..type(t)..'('..tostring(t)..')'
	end
	return r
end

local G_Count
local OldGs = {}
_ = true	-- make it a global first!
local function monitorGlobals(where)
	local now = MOAISim.getDeviceTime()*1000
	where = where or ""
	if #where then where = where..': ' end
	local nowCount = 0
	local newOnes = 0
	for k,v in pairs( _G ) do
		nowCount = nowCount + 1
		if G_Count and not OldGs[k] then
			print("*** New global("..tostring(k)..'):'..tostring(v))
			if type(v) == 'table' then print(printableTable(tostring(k),v)) end
			newOnes = newOnes + 1
		end
		OldGs[k] = now
	end
	for k,v in pairs( OldGs ) do
		if OldGs[k] ~= now then
			print("*** Removed global("..tostring(k)..')')
			OldGs[k] = nil
		end
	end
	if G_Count ~= nowCount then
		if G_Count then
			print(where..tostring(nowCount)..' Globals now defined ('..tostring(newOnes)..' new)')
		else print(where..tostring(nowCount)..' Globals initially defined')
		end
		G_Count = nowCount
	end
	return (newOnes > 0)
end
monitorGlobals('Initial')
performWithDelay(1000,function() monitorGlobals('timer') end,0)

local stations = require('stationList')

local notificationIDs = {}

cancelNotification = function(id)
	toast.destroy(id)
end

scheduleNotification = function(when, options)
	if type(options) == 'table' and type(options.alert) == 'string' then
		print('scheduleNotification('..tostring(options.alert)..')')
		local onTap = nil
		print(printableTable('scheduleNotification:options',options))
		if type(options.custom) == 'table' then print(printableTable('scheduleNotification:custom',options.custom)) end
		if type(options.custom) == 'table' and options.custom.name == 'message' and options.custom.QSO then
--custom = { name="message", msg=msg, QSO=QSO } }
			print('scheduleNotification:setting onTap')
			onTap = function()
					print('scheduleNotification:onTap:opening QSO:'..options.custom.QSO.id)
					SceneManager:openScene("QSO_scene", { animation="popIn", QSO = options.custom.QSO })
				end
		end
		return toast.new(options.alert, nil, onTap)--,5000)
	end
	return nil
end

--local myConfig = require("myconfig")
config = require("myconfig").new(MOAIEnvironment.appDisplayName..".xml", MOAIEnvironment.documentDirectory or "." )

local function validateStationID(value)
	print('validateStationID:'..tostring(value))
	value = string.upper(trim(value))
	if #value <= 0 then return nil end
	return value
end

local function updateStationID()
	print('updateStationID to '..tostring(config.StationID))
	local newValue = validateStationID(config.StationID)
	if newValue then
		config.StationID = newValue
		myStation.stationID = config.StationID
	end
end

--
local client, clientServer
--local GPSSwitch
local gpsSwitch -- Actually a segmented control...
local sleepSwitch
local initialized = false

local function updateMySymbol()
	myStation.symbol = config.Beacon.Symbol
	stations:setupME()
end

local function updateISServer()
	if APRSIS then
print('updateISServer:disconnecting APRS-IS...')
		APRSIS:triggerReconnect("Configuration Change restart")
else print('updateISServer:APRSIS Not Yet Initialized!')
	end
end

local function updateFilter()
	if APRSIS then
		APRSIS:triggerFilter()
else print('updateFilter:APRSIS Not Yet Initialized!')
	end
end

local locationListening

local GPSd
if Application:isDesktop() then
	GPSd = require('GPSd')
print('GPSd loaded as '..tostring(GPSd))
else print('NOT loading GPSd on non-desktop()')
end

function updateGPSEnabled()
	print("updateGPSEnabled("..tostring(config.Enables.GPS)..")")
	--GPSSwitch:setState( { isOn=config.Enables.GPS, isAnimated=false } )
	if config.Enables.GPS then
		if gpstext then gpstext:setColor(0.5, 0.5, 0.5, 1.0) end
		if gpstext then gpstext:setString ( "GPS On" ) end
		if not locationListening then
			locationListening = true
			-- Turn it ON here
			if GPSd and (config.gpsd.Server ~= '') and tonumber(config.gpsd.Port) then GPSd:start(config) else print('not starting GPSd') end
			if APRSIS then
				if MOAIInputMgr.device.location then
					MOAIInputMgr.device.location:setCallback(APRSIS.locationListener)
				else
					if gpstext then gpstext:setString ( "No GPS" ) end
				end
				APRSIS:triggerPosit('GPS:on',5000)
else print('updateGPSEnabled:APRSIS Not Yet Initialized!')
			end
		end
	else
		if gpstext then gpstext:setRGBA(192, 192, 0, 1) end	-- Yellow(ish) for disabled
		if gpstext then gpstext:setString ( "GPS Off" ) end
		if locationListening then
			locationListening = false
			-- Turn it OFF here
			if GPSd then GPSd:close() else print('not stopping GPSd') end
			if APRSIS then
				if MOAIInputMgr.device.location then
					MOAIInputMgr.device.location:setCallback(nil)
					if gpstext then gpstext:setString ( "GPS Off" ) end
				else
					if gpstext then gpstext:setString ( "No GPS" ) end
				end
				APRSIS:triggerPosit('GPS:off',0)
else print('updateGPSEnabled:APRSIS Not Yet Initialized!')
			end
		end
	end
end

local function updateGPSdServer()
	if GPSd then
		GPSd:stop()	-- It'll reconnect within 60 seconds if it was ever started
		GPSd:start(config)	-- Restart it
	end
end

function updateKeepAwake()
	if config.Enables.KeepAwake then
		if initialized and not config.Warning.KeepAwake then
			--native.showAlert( "Keep Awake?", "Staying awake may adversely impact battery life.  Just thought you might like to know.", {"OK"} )
			config.Warning.KeepAwake = true
		end
	end
	-- system.setIdleTimer(not config.Enables.KeepAwake)
end

config:addGroup("General", "Basic configuration settings")
config:addString("General", "StationID", "Your callsign-SSID (MYCALL)", 9, "APRSIS-DR", nil, validateStationID, updateStationID)

config:addGroup("Enables", "A vast collection of feature enablers")
config:addBoolean("Enables", "Enables.GPS", "Enable Location awareness", true, updateGPSEnabled)
config:addBoolean("Enables", "Enables.AllowNetworkFix", "Allow network-provided location updates (not recommended) ", false)
config:addBoolean("Enables", "Enables.KeepAwake", "Keep device Awake while running", false, updateKeepAwake)
config:addBoolean(nil, "Warning.KeepAwake", "Awake Warning Issued", false)
config:addBoolean("Enables", "Enables.SaveMyTrack", "Auto-Save (ME) Transmitted Posits", false)
config:addBoolean("Enables", "Enables.SaveMyCrumbs", "Auto-Save (ME) GPS BreadCrumbs", false)
config:addBoolean("Enables", "Enables.SaveCenterTrack", "Auto-Save Center Station Track", false)

config:addGroup("APRSIS", "APRS-IS settings")
config:addBoolean("APRSIS", "APRSIS.Enabled", "Keep connection to APRS-IS ", true, updateISServer)
config:addNumber("APRSIS", "Range", "Default m/ Range", 50, 1, 999, updateFilter)
config:addString("APRSIS", "APRSIS.Server", "APRS-IS Server to use", 128, "rotate.aprs2.net", nil, nil, updateISServer)
config:addNumber("APRSIS", "APRSIS.Port", "Server port (typically 14580)", 14580, 1, 65535, updateISServer)
config:addNumber("APRSIS", "APRSIS.QuietTime", "Max Idle seconds before Disconnect", 60, 0, 5*60)
config:addBoolean("APRSIS", "APRSIS.Notify", "Connection Status Notifications", true)
config:addNumber("APRSIS", "PassCode", "APRS-IS PassCode", -1, -1, 99999, updateISServer)
config:addString("APRSIS", "Filter", "Additional APRS-IS Filter", 256, "u/APWA*/APWM*", nil, nil, updateFilter)

config:addGroup("Beacon", "APRS Beacon settings")
config:addBoolean("Beacon", "Beacon.Enabled", "Allowed to beacon to APRS", true)
config:addBoolean("Beacon", "Beacon.AfterTransmit", "Suppress beacons until Location acquired", false)
config:addBoolean("Beacon", "Beacon.AutoAmbiguity", "Location accuracy implies ambiguity", true)
config:addString("Beacon", "Beacon.Symbol", "APRS Symbol Table + Identifier", 2, Application:isMobile() and "/$" or "/l", '^..$', velidateSymbol, updateMySymbol)
config:addString("Beacon", "Beacon.Comment", "Beacon Comment text", 43, MOAIEnvironment.appDisplayName.." de KJ4ERJ")
config:addBoolean("Beacon", "Beacon.Altitude", "Include Altitude if known", true)
config:addBoolean("Beacon", "Beacon.Speed", "Include Course and Speed if known (allows Dead Reckoning)", true)
config:addBoolean("Beacon", "Beacon.TimestampDD", "Include DDHHMMz Timestamp", false)
config:addBoolean("Beacon", "Beacon.TimestampHH", "Include HHMMSSh Timestamp (trumps DD)", true)
config:addBoolean("Beacon", "Beacon.Speed", "Include Course and Speed if known (allows Dead Reckoning)", true)
config:addBoolean("Beacon", "Beacon.Why", "Include Transmit Pressure (useful for debuggin)", true)

config:addGroup("Genius", "GeniusBeaconing™ settings")
config:addBoolean("Genius", "Genius.TimeOnly", "Beacon at MaxTime rate only", false)
config:addNumber("Genius", "Genius.MinTime", "Minimum (Seconds) between beacons", 15, 10, 5*60)
config:addNumber("Genius", "Genius.MaxTime", "Maximum (Minutes) between beacons", 30, 1, 60)
config:addBoolean("Genius", "Genius.StartStop", "Include Start/Stop detection", true)
config:addNumber("Genius", "Genius.HeadingChange", "Degrees of turn to trigger (180=none)", 80, 5, 180)
config:addNumberF("Genius", "Genius.ForecastError", "Allowed DeadReckon error before trigger (miles)", 0.1, 0.1, 2)
config:addNumber("Genius", "Genius.MaxDistance", "Maximum distance between beacons (miles)", 1.0, 0.5, 20)

config:addGroup("Screen", "On-Screen Controls and Indicators")
config:addNumber("Screen", "Screen.DFOpacity", "DF Highlight Opacity %", 10, 0, 100, function () osmTiles:refreshMap() end)
config:addNumber("Screen", "Screen.NWSOpacity", "NWS Area Opacity %", 10, 0, 100, function () osmTiles:refreshMap() end)
config:addBoolean("Screen", "Screen.PositPop", "Pop-and-Shrink Beacon Indicator", true)
config:addBoolean("Screen", "Screen.RedDot", "GeniusBeaconing™ Debug Aid (aka MeatBall)", true)
config:addBoolean("Screen", "Screen.RangeCircle", "Zoom/Range Indicator", true)
config:addNumberF("Screen", "Screen.SymbolSizeAdjust", "Symbol Size Scale Adjustment", 0, -10, 10)

if not (MOAIEnvironment.screenDpi and MOAIEnvironment.screenDpi > 0) or Application:isDesktop() then
	config:addNumber("Screen", "Screen.DPI", "DPI (sqrt(x^2+y^2)/diagonal)", 129, "*Unknown*")
end

if Application:isDesktop() then
	config:addGroup("gpsd", "gpsd Location Source")
	config:addString("gpsd", "gpsd.Server", "Server IP or Name", 128, "", nil, nil, updateGPSdServer)
	config:addNumber("gpsd", "gpsd.Port", "Server port (typically 2947)", 2947, 1, 65535, updateGPSdServer)
end

config:addGroup("Vibrate", "Vibrator usage controls")
config:addBoolean("Vibrate", "Vibrate.Enabled", "Enable vibrator use", true)
config:addBoolean("Vibrate", "Vibrate.onTapStation", "Vibrate when station is tapped", true)

config:addGroup("About", "Program Version Information")
config:addString("About", "About.Version", "Build Date/Time", -1, "*Unknown*")
config.About.Version = MOAIEnvironment.appVersion or ''

if type(config.APRSIS) == 'nil' then
	config.APRSIS = {}
end

if not (MOAIEnvironment.screenDpi and MOAIEnvironment.screenDpi > 0) or Application:isDesktop() then
	MOAIEnvironment.screenDpi = config.Screen.DPI	-- sqrt(px^2+py^2)/inches diagonal sqrt(1920*1920+1080*1080)/17" = 129
end

local dpi = MOAIEnvironment.screenDpi or 240
config.Screen.scale = dpi/240

--[[
if config.StationID == 'N0CALL-DR' then config.StationID = 'KJ4ERJ-MO' end
if config.StationID == 'KJ4ERJ-MO' then
	config.PassCode = 24231
	config.Genius.MaxTime = 2
	config.Enables.SaveMyTrack = true
	config.Enables.SaveMyCrumbs = true
end
]]

if configChanged or true then config:save('InitialDefaults') end

if tonumber(config.lastLat) and tonumber(config.lastLon) then
	myStation.lat = tonumber(config.lastLat)
	myStation.lon = tonumber(config.lastLon)
	print(string.format('ME is at %.5f %.5f', myStation.lat, myStation.lon))
else print(string.format('lastLat=%s(%s) lastLon=%s(%s)', type(config.lastLat), tostring(config.lastLat), type(config.lastLon), tostring(config.lastLon)))
end
if type(config.Beacon.Symbol) == 'string' and #config.Beacon.Symbol == 2 then
	myStation.symbol = config.Beacon.Symbol
end

local function Vibrate(yes)
	if yes and config.Vibrate.Enabled then
		--system.vibrate()
	end
end

simStarting = true
-- start and open
Application:start(hp_config)
SceneManager:openScene(hp_config.mainScene)	-- splash!

local function showDebugLines()
	--MOAIDebugLines.showStyle(MOAIDebugLines.PARTITION_CELLS)
	--MOAIDebugLines.showStyle(MOAIDebugLines.PARTITION_PADDED_CELLS)

	--MOAIDebugLines.setStyle(MOAIDebugLines.PROP_MODEL_BOUNDS,1,1,0,1,.75)	-- Purple
	--MOAIDebugLines.showStyle(MOAIDebugLines.PROP_MODEL_BOUNDS)

	MOAIDebugLines.setStyle(MOAIDebugLines.PROP_WORLD_BOUNDS,1,1,1,0,.75)	-- Yellow?
	MOAIDebugLines.showStyle(MOAIDebugLines.PROP_WORLD_BOUNDS, debugLines)

	MOAIDebugLines.setStyle(MOAIDebugLines.TEXT_BOX,1,1,0,0,.75)	-- Red
	MOAIDebugLines.setStyle(MOAIDebugLines.TEXT_BOX_BASELINES,1,0,1,0,.75)	-- Green
	MOAIDebugLines.setStyle(MOAIDebugLines.TEXT_BOX_LAYOUT,1,0,0,1,.75)	-- Blue

	MOAIDebugLines.showStyle(MOAIDebugLines.TEXT_BOX, debugLines)
	MOAIDebugLines.showStyle(MOAIDebugLines.TEXT_BOX_BASELINES, debugLines)
	MOAIDebugLines.showStyle(MOAIDebugLines.TEXT_BOX_LAYOUT, debugLines)
end

showDebugLines()	-- prime the pump

function toggleDebugLines()
	debugLines = not debugLines
	showDebugLines()
end

local function setConfigScreenSize()
local platformSize = ''
if type(Application.viewWidth)=='number' and type(Application.viewHeight)=='number' then
	platformSize=platformSize..' '..tostring(Application.viewWidth)..'x'..tostring(Application.viewHeight)
else print('viewWidth:'..type(Application.viewWidth)..' viewHeight:'..type(Application.viewHeight))
end
if type(MOAIEnvironment.screenDpi)=='number' then
	platformSize=platformSize..' at '..tostring(MOAIEnvironment.screenDpi)..' dpi'	-- trailing . for font sizing issues
else print('screenDPI:'..type(MOAIEnvironment.screenDpi))
end
config.Screen.Size = platformSize
print('platformSize:'..platformSize)
return platformSize
end
if #setConfigScreenSize() > 0 then
	config:addString("About", "Screen.Size", "Startup Screen Stats (static snapshot)", -1, "*Unknown*")
end
config:addString("About", "Screen.scale", "Calculated Scale (relative 240dpi)", -1, "*Unknown*")

--MOAISim.openWindow("MultiTrack", 64, 64)	-- Maybe? Nope, just one window :(

--[[
function onResize ( e )
	local width, height = e.width, e.height
	print('main:onResize:'..tostring(width)..'x'..tostring(height))
end
flower.Runtime:addEventListener(flower.Event.RESIZE, onResize)
]]

function onResize(width, height)
	local current = SceneManager:getCurrentScene()
	local name = current:getName()
	print('onResize:'..tostring(width)..'x'..tostring(height)..' scene:'..tostring(name))
	--SceneManager:closeScene(current)
	Application:setScreenSize(width,height)
	if type(current.resizeHandler) == 'function' then
		current.resizeHandler(width, height)
	end
	--SceneManager:openScene(name)
	setConfigScreenSize()
end

MOAIGfxDevice.setListener ( MOAIGfxDevice.EVENT_RESIZE, onResize )

function getScaledRGColor(Current, RedValue, GreenValue)
	local Percent = (Current - RedValue) / (GreenValue - RedValue) * 100.0;

	if (Percent <= 50.0) then
		if (Percent < 0.0) then Percent = 0.0 end
		return 255,255*Percent/50,0,255
	else
		if (Percent > 100.0) then Percent = 100.0 end
		return 255*(100.0-Percent)/50,255,0,255
	end
end

local mouseX = 0
local mouseY = 0
local lastX = 0
local lastY = 0

local points = { 0, 0 }
function onDraw ( index, xOff, yOff, xFlip, yFlip )
	if #points > 2048 then points = {}; lastX, lastY = 0,0 end
	local r, g, b = getScaledRGColor(#points, 2048, 0)
	MOAIGfxDevice.setPenColor(r/255,g/255,b/255,1)
    MOAIDraw.drawLine ( unpack ( points ) )
	--print('onDraw:'..tostring(#points)..' points')
end

local tapX = 0
local tapY = 0
function startTap ( downX, downY)
	tapX, tapY = downX, downY
end
function checkTap ( upX, upY)
	print(string.format('checkTap: dx=%i dy=%i', upX-tapX, upY-tapY))
	if toastLayer then
		local x,y = toastLayer:wndToWorld(upX, upY)
		local partition = toastLayer:getPartition()
		local list = { partition:propListForPoint(x,y,nil,MOAILayer.SORT_PRIORITY_DESCENDING) }
		if list then
			for k,v in ipairs(list) do
				print(string.format('toastProp%s %s @%i,%i has %s %s(%s)', tostring(toastLayer), tostring(partition), x,y, tostring(k), tostring(v), tostring(v.name)))
				if type(v.onTap) == 'function' then
					if v.onTap() then break end
				end
			end
		end
	end
	if layer then
		local x,y = layer:wndToWorld(upX, upY)
		local partition = layer:getPartition()
		local list = { partition:propListForPoint(x,y,nil,MOAILayer.SORT_PRIORITY_DESCENDING) }
		if list then
			for k,v in ipairs(list) do
				print(string.format('Prop%s %s @%i,%i has %s %s(%s)', tostring(toastLayer), tostring(partition), x,y, tostring(k), tostring(v), tostring(v.name)))
				if type(v.onTap) == 'function' then
					if v.onTap() then break end
				end
			end
		end
	end
end

function onTouch ( eventType, idx, x, y, tapCount  )
	mouseX, mouseY = layer:wndToWorld ( x, y )
	--print ( string.format('onTouch:%s[%s]:%i,%i %i or %i,%i', tostring(eventType), tostring(idx), x, y, tapCount, mouseX, mouseY ))
	if eventType == MOAITouchSensor.TOUCH_DOWN then
		startTap(x,y)
	elseif eventType == MOAITouchSensor.TOUCH_UP then
		checkTap(x,y)
	end
	if mouseX ~= lastX or mouseY ~= LastY or eventType == MOAITouchSensor.TOUCH_DOWN then
		lastX, lastY = mouseX, mouseY
        table.insert ( points, mouseX )
		table.insert ( points, mouseY )
	end
end

if MOAIInputMgr.device.touch then
	--MOAIInputMgr.device.touch:setCallback ( onTouch )
end

local leftIsDown
function onPointerEvent ( x, y )
--[[
	mouseX, mouseY = layer:wndToWorld ( x, y )
	if leftIsDown then
		--print ( string.format('onPointerEvent:%i,%i or %i,%i', x, y, mouseX, mouseY ))
		if mouseX ~= lastX or mouseY ~= LastY then
			lastX, lastY = mouseX, mouseY
			table.insert ( points, mouseX )
			table.insert ( points, mouseY )
			--print("onPointerEvent:up:mouseX:", mouseX, " mouseY:", mouseY)
		end
	end
]]
end

if MOAIInputMgr.device.pointer then
	--MOAIInputMgr.device.pointer:setCallback ( onPointerEvent )
end

function clickCallback( down )
	leftIsDown = down
	local x, y = MOAIInputMgr.device.pointer:getLoc()
	local xW, yW = layer:wndToWorld ( x, y )
	print(string.format('click at %i,%i or %i,%i vs %i,%i', x, y, xW, yW, mouseX, mouseY))
	if down then
		startTap(x,y)
	else
		checkTap(x,y)
	end
end

if MOAIInputMgr.device.mouseLeft then
	--MOAIInputMgr.device.mouseLeft:setCallback ( clickCallback )
end

--[[
local scriptDeck = MOAIScriptDeck.new ()
scriptDeck:setRect ( -64, -64, 64, 64 )
scriptDeck:setDrawCallback ( onDraw )

local prop2 = MOAIProp2D.new ()
prop2.name = "scribbles"
prop2:setDeck ( scriptDeck )
layer:insertProp ( prop2 )
]]

--[[
  print ("               Display Name : ", tostring(MOAIEnvironment.appDisplayName))
  print ("                     App ID : ", tostring(MOAIEnvironment.appID))
  print ("                App Version :  ", tostring(MOAIEnvironment.appVersion))
  print ("            Cache Directory : ", tostring(MOAIEnvironment.cacheDirectory))
  print ("   Carrier ISO Country Code : ", tostring(MOAIEnvironment.carrierISOCountryCode))
  print ("Carrier Mobile Country Code : ", tostring(MOAIEnvironment.carrierMobileCountryCode))
  print ("Carrier Mobile Network Code : ", tostring(MOAIEnvironment.carrierMobileNetworkCode))
  print ("               Carrier Name : ", tostring(MOAIEnvironment.carrierName))
  print ("            Connection Type : ", tostring(MOAIEnvironment.connectionType))
  print ("               Country Code : ", tostring(MOAIEnvironment.countryCode))
  print ("                    CPU ABI : ", tostring(MOAIEnvironment.cpuabi))
  print ("               Device Brand : ", tostring(MOAIEnvironment.devBrand))
  print ("                Device Name : ", tostring(MOAIEnvironment.devName))
  print ("        Device Manufacturer : ", tostring(MOAIEnvironment.devManufacturer))
  print ("               Device Model : ", tostring(MOAIEnvironment.devModel))
  print ("            Device Platform : ", tostring(MOAIEnvironment.devPlatform))
  print ("             Device Product : ", tostring(MOAIEnvironment.devProduct))
  print ("         Document Directory : ", tostring(MOAIEnvironment.documentDirectory))
  print ("         iOS Retina Display : ", tostring(MOAIEnvironment.iosRetinaDisplay))
  print ("              Language Code : ", tostring(MOAIEnvironment.languageCode))
  print ("                   OS Brand : ", tostring(MOAIEnvironment.osBrand))
  print ("                 OS Version : ", tostring(MOAIEnvironment.osVersion))
  print ("         Resource Directory : ", tostring(MOAIEnvironment.resourceDirectory))
  print ("                 Screen DPI : ", tostring(MOAIEnvironment.screenDpi))
  print ("              Screen Height : ", tostring(MOAIEnvironment.screenHeight))
  print ("               Screen Width : ", tostring(MOAIEnvironment.screenWidth))
  print ("                       UDID : ", tostring(MOAIEnvironment.udid))
]] 

APRSIS = require("APRSIS")	-- This auto-starts the APRS-IS connection
osmTiles = require("osmTiles")	-- This currently sets the Z order of the map

--performWithDelay( 1000, updateMemoryUsage, 0)

	print('cacheDirectory:'..tostring(MOAIEnvironment.cacheDirectory))
	print('documentDirectory:'..tostring(MOAIEnvironment.documentDirectory))
	print('resourceDirectory:'..tostring(MOAIEnvironment.resourceDirectory))

simRunning = true

MOAISim.setListener(MOAISim.EVENT_PAUSE,
	function()
		print('pause')
		config:save('Paused')
		simRunning = false
end)

MOAISim.setListener(MOAISim.EVENT_RESUME,
	function()
		print('resume')
		simRunning = true
end)

MOAISim.setListener(MOAISim.EVENT_FINALIZE,
	function()
		print('finalize')
		config:save('Finalized')
end)

local backTiming = false
local backValid = nil	-- Ignore more backs until this time

local function onMenuButtonPressed ()
	local scene = SceneManager:getCurrentScene()
	print('main:onMenuButtonPressed:scene:'..tostring(scene.name))
	if type(scene.menuHandler) == 'function' then
		scene.menuHandler()
	end
end

local function onBackButtonPressed ()
	local scene = SceneManager:getCurrentScene()

	print('main:onBackButtonPressed:scene:'..tostring(scene.name))

	if backValid and backValid > MOAISim.getDeviceTime() then
		print('suppressing redundant Back')
		return true
	elseif config:unconfigure() then
		print('Backed out of config')
	elseif type(scene.backHandler) == 'function' then
		scene.backHandler()
	elseif SceneManager:getCurrentScene().name == 'config_scene' then
		print('Force closing config!')
		SceneManager:closeScene({animation = "popOut"})
	elseif SceneManager:getCurrentScene().name == 'buttons_scene' then
		print('Backing out of Buttons')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'QSO_scene' then
		print('Backing out of QSO')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'QSOs_scene' then
		print('Backing out of QSOs')
		SceneManager:closeScene({animation="popOut"})
	elseif SceneManager:getCurrentScene().name == 'APRSmap' then	-- Only allowed to back out from here!
		if backTiming then return false end
		backTiming = true
		toast.new('Press Back again to exit', 2000, function() backTiming = false end)
		performWithDelay(2000, function() backTiming = false end)
		-- Return true if you want to override the back button press and prevent the system from handling it.
		print('First Back Button Suppressed!')
		return true --true to cancel back
	end
	print('main:onBackButtonPressed:Suppressing back for 1 second more')
	backValid = MOAISim.getDeviceTime() + 1	-- Ignore more backs for 1 second
	return true	-- This one HAS been proceesed!
end

print('MOAIApp:'..tostring(MOAIApp)..' MOAIAppAndroid:'..tostring(MOAIAppAndroid)..' MOAIAppIOS:'..tostring(MOAIAppIOS))

if MOAIApp then
if type(MOAIApp.setListener) == 'function' then
	print("Registering MOAIApp's Back Button!")
	print('Back:'..tostring(MOAIApp.BACK_BUTTON_PRESSED)..' Start:'..tostring(MOAIApp.SESSION_START)..' End:'..tostring(MOAIApp.SESSION_END))
	MOAIApp.setListener ( MOAIApp.BACK_BUTTON_PRESSED, onBackButtonPressed )
	MOAIApp.setListener ( MOAIApp.MENU_BUTTON_PRESSED, onMenuButtonPressed )
	MOAIApp.setListener ( MOAIApp.SESSION_START, function() print('MOAIApp:onSessionStart') end )
	MOAIApp.setListener ( MOAIApp.SESSION_END, function() print('MOAIApp:onSessionEnd') end )
else	print('MOAIApp.setListener='..type(MOAIApp.setListener))
end
else print('MOAIApp='..type(MOAIApp))
end

--[[
local function getLuaValue(v)
	if type(v) ~= 'string' then return 'nil' end
	--if type(v) == 'nil' then return 'nil' end
	local f, err = loadstring('return '..v)
	if f == nil then return 'nil' end
	local s, r = pcall(f)
	if s == false then
		print('pcall('..v..') gave '..tostring(r))
		return 'nil'
	end
	if r == nil then return 'nil' end
	return tostring(r)
end
local function testLuaValue(v)
	local r = getLuaValue(v)
	print('getLuaValue('..tostring(v)..'):'..tostring(r))
	return r
end
testLuaValue('foo.fil.this.should.be.nil')
testLuaValue('toast.bogus.field')
testLuaValue('config.Enables.GPS')
testLuaValue('config.Enables.KeepAwake')
testLuaValue('config.Filter')
testLuaValue('config.bogus.field')
]]

print('main.lua done processing!')

local versionDialogActive

local function checkNewVersion()
local URL = "http://ldeffenb.dnsalias.net/APRSISDR/*"	-- where new versions come from

	local function versionListener( task, responseCode )
		if responseCode ~= 200 then
			print ( "versionListener:Network error:"..responseCode)
		else
--[[HTTP/1.0 200 OK
X-Thread: *UNKNOWN*
Connection: close
Content-Type: application/vnd.android.package-archive
Date: Monday, 12 Aug 2013 19:51:32 GMT
Content-Length: 2853035]]
			local filename = nil
			if Application:isMobile() then
				filename = "APRSISMO%.apk"
			elseif Application:isDesktop() then
				filename = "APRSISMO%.7z"
			else	print('checkNewVersion:Unrecognized platform!')
			end
			if filename then
				local s,e,timestamp = task:getString():find(filename..".-%<%/A%>%s([%d%s]%d%s%w%w%w%s%d%d%d%d%s%d%d:%d%d:%d%d)")
				if timestamp then
					print (filename..' verison is '..timestamp)
					print('last:'..tostring(config.LastAPKTimestamp)..' now:'..timestamp)
					if not config.LastAPKTimestamp then	-- virgin birth?
						config.LastAPKTimestamp = timestamp
						config:save('APK Timestamp')
					elseif config.LastAPKTimestamp ~= timestamp then
						local text = "Possible new Version:\r\n"..timestamp..'\r\nYours:'..MOAIEnvironment.appVersion..'\r\nThey will not match exactly'
						if MOAIDialog and type(MOAIDialog.showDialog) == 'function' then
							versionDialogActive = true
							MOAIDialog.showDialog('New Version', text, 'Go There', 'Not Now', 'Never', true, 
										function(result)
											versionDialogActive = false
											if result == MOAIDialogAndroid.DIALOG_RESULT_POSITIVE then
												if MOAIApp and type(MOAIApp.openURL) == 'function' then
													MOAIApp.openURL(URL)
												else toast.new("Oops, Missing MOAIApp.openURL("..type(MOAIApp.openURL)..")!")
												end
											elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEUTRAL then
											elseif result == MOAIDialogAndroid.DIALOG_RESULT_NEGATIVE then
												config.LastAPKTimestamp = timestamp
												config:save('APK Timestamp')
											elseif result == MOAIDialogAndroid.DIALOG_RESULT_CANCEL then
											end
										end)
						else
							scheduleNotification(0,{alert=text})
							config.LastAPKTimestamp = timestamp
							config:save('APK Timestamp')
						end
					end
				else print ('Failed to match .APK date')
				end
			end
		end
		performWithDelay( 60*60*1000, checkNewVersion)
	end

	if versionDialogActive then
		performWithDelay( 60*60*1000, checkNewVersion)
	else
		task = MOAIHttpTask.new ()
		task:setVerb ( MOAIHttpTask.HTTP_GET )
		task:setUrl ( URL )
		task:setTimeout ( 15 )
		task:setCallback ( versionListener )
		task:setUserAgent ( string.format('%s from %s %s',
													tostring(config.StationID),
													MOAIEnvironment.appDisplayName,
													tostring(config.About.Version)) )
		task:setVerbose ( true )
		task:performAsync ()
	end
end
performWithDelay( 30000, checkNewVersion)

local function printEvent(event)
	print(printableTable('Notification',event))
end

print('MOAINotifications:'..tostring(MOAINotifications)..' MOAINotificationsAndroid:'..tostring(MOAINotificationsAndroid)..' MOAINotificationsIOS:'..tostring(MOAINotificationsIOS))
if MOAINotifications then
	print('HAVE MOAINotifications!')
--[[
	--MOAINotifications.setListener ( MOAINotifications.REMOTE_NOTIFICATION_REGISTRATION_COMPLETE, onRemoteRegistrationComplete )
	--MOAINotifications.setListener ( MOAINotifications.REMOTE_NOTIFICATION_MESSAGE_RECEIVED, onRemoteMessageReceived )
	MOAINotifications.setListener(MOAINotifications.LOCAL_NOTIFICATION_MESSAGE_RECEIVED, printEvent)
	MOAINotifications.localNotificationInSeconds(30, MOAIEnvironment.appDisplayName..' running!',
						{title=MOAIEnvironment.appDisplayName, message="Test Message...", QSO="KJ4ERJ-AP" })
]]
else print('No MOAINotifications')
end
print('MOAIApp:'..tostring(MOAIApp)..' MOAIAppAndroid:'..tostring(MOAIAppAndroid)..' MOAINotificationsIOS:'..tostring(MOAIAppIOS))
if MOAIApp then
	print('HAVE MOAIApp!')
	--MOAIApp.share('ThisPrompt:', 'This is the subject', 'This is the text')
	--MOAIApp.openURL('http://ldeffenb.dnsalias.net/APRSISDR/*')
else print('No MOAIApp')
end

print('MOAIDialog:'..tostring(MOAIDialog)..' MOAIAppAndroid:'..tostring(MOAIDialogAndroid)..' MOAINotificationsIOS:'..tostring(MOAIDialogIOS))
if MOAIDialog then
--[[
	MOAIDialog.showDialog('Title here', 'This is the message to the user', 'Positive', 'Neutral', 'Negative', true, 
				function(e,m)
					print('e='..tostring(e)..' m='..tostring(m))  print(printableTable('MOAIDialog:e',e))
					print(string.format('Positive=%i Neutral=%i Negative=%i Cancel=%i',
						MOAIDialogAndroid.DIALOG_RESULT_POSITIVE,
						MOAIDialogAndroid.DIALOG_RESULT_NEUTRAL,
						MOAIDialogAndroid.DIALOG_RESULT_NEGATIVE,
						MOAIDialogAndroid.DIALOG_RESULT_CANCEL))
				end)
]]
end

	print("Printing /proc/self")
	for file in lfs.dir("/proc/self") do
		print( "Found file:/proc/self/" .. file )
	end
	print("Done printing /proc/self/*")
	local hFile, err = io.open("/proc/self/statm","r")
	if hFile and not err then
			local xmlText=hFile:read("*a"); -- read file content
			io.close(hFile);
			print(xmlText)	-- virtual, working, share, text, lib, data, dt
			local s, e, virtual, resident = string.find(xmlText, "(%d+)%s(%d+)")
			if virtual and resident then print ("virt:"..tostring(virtual).." res:"..tostring(resident)) end
	else
			print( err )
	end

--local habitat = require('habitat')
--if habitat and type(habitat.start) == 'function' then habitat:start(config) end

local radar = require('radar')
if radar and type(radar.start) == 'function' then radar:start(config) radar:setEnable(config.lastRadar) end
