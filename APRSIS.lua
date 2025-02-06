local APRSIS = { VERSION = "0.0.1" }

local debugging = true

local toast = require("toast");
local APRS = require("APRS")
local colors = require("colors");
local LatLon = require("latlon")
local QSOs = require("QSOs")

--	Forward references for callbacks
local getConnection
local closeConnection

packetCount = 0

local packetCallback

local config = nil	-- set by APRSIS:start(config) below
local appName, appVersion = "APRSIS", "*unknown*"

local osmTiles = nil	-- Wrong way to access, I know...
osmTiles = require("osmTiles")	-- pick it up now for later use

local gpsUpdate, lwdUpdate, whyUpdate

local function updateUI()
	if gpsUpdate and gpstext then
		local x,y = gpstext:getLoc()
		gpstext:setString ( gpsUpdate )
		gpstext:fitSize()
		gpstext:setLoc(x,y)
		gpsUpdate = nil
	end
	if lwdUpdate and lwdtext then
		local x,y = lwdtext:getLoc()
		lwdtext:setString ( lwdUpdate );
		lwdtext:fitSize()
		lwdtext:setLoc(x,y)
		--lwdtext:setLoc(Application.viewWidth/2, 75*config.Screen.scale)
		lwdUpdate = nil
	end
	if whyUpdate and whytext then
		local x,y = whytext:getLoc()
		whytext:setString(whyUpdate)
		whytext:fitSize()
		whytext:setLoc(x,y)
		--whytext:setLoc(Application.viewWidth/2, Application.viewHeight-20*config.Screen.scale)
		whyUpdate = nil
	end
end

local function showTrack(track, dots, why)
	if osmTiles then
		performWithDelay(1,function()
--print("APRSIS:showTrack:Actually showing "..#track.." because "..why)
						osmTiles:showTrack(track, dots, why)
					end)
	else print('APRSIS:removeTrack:osmTiles='..tostring(osmTiles))
	end
end

local function removeTrack(track)
	if osmTiles then
		performWithDelay(1,function()
						osmTiles:removeTrack(track)
					end)
	else print('APRSIS:removeTrack:osmTiles='..tostring(osmTiles))
	end
end

local timer = MOAITimer.new()
timer:setSpan(1/60)
timer:setMode(MOAITimer.LOOP)
timer:setListener(MOAITimer.CONTINUE, updateUI)
timer:start()

function APRSIS:setAppName(name, version)
	appName = name or appName
	appVersion = version or appVersion
end

function APRSIS:setPacketCallback(callback)	-- is passed a single received APRS packet + server info string + self
	if type(callback) == 'function' then
		packetCallback = callback
		
		performWithDelay(15000, function() packetCallback("CRPTOR>APRS,qAO,AE5PL-WX:;CRPTORKlA*212145z2755.80N\\09713.80Wt112/005 TORNADO }a0IE;IFDIEPHQHWWY^4\\9X8R=Q<Q6W4O3E;{LKlAA", nil, APRSIS) end)
		
	end
end

local connectedCallback

function APRSIS:setConnectedCallback(callback)
	if type(callback) == 'function' then	-- gets server:port or nil on disconnect
		connectedCallback = callback
	end
end

local serviceTimers = {}

local function serviceWithDelay (name, delay, func, repeats, ...)
	delay = delay * 0.001	-- convert to seconds
	local s = serviceTimers
	if s[name] then
		print ('Redefining serviceTimer['..name..']')
	--else print ('Defining serviceTimer['..name..']')
	end
	s[name] = {}
	s[name].delay = delay
	s[name].func = func
	s[name].arg = arg
	s[name].repeats = repeats or 1
	s[name].expires = MOAISim.getDeviceTime() + delay
	return s[name]
end

local sendFilter, sendStatus, pcallSendPosit, sendPosit	-- forward references

function APRSIS:triggerFilter(delay)
	serviceWithDelay('sendFilter', tonumber(delay) or 0, sendFilter)
end

function APRSIS:triggerStatus(delay)
	serviceWithDelay('sendStatus', tonumber(delay) or 0, sendStatus)
end

function APRSIS:triggerReconnect(why, delay)
	serviceWithDelay('Reconnect', tonumber(delay) or 0, function() closeConnection(why or "Reconnect") end)
end

local sendPositTimer = nil

function APRSIS:triggerPosit(why,delay)
	delay = tonumber(delay) or 0
	serviceWithDelay('posit('..why..')', delay, function() sendPosit(nil, why) end)
	if not sendPositTimer then
		sendPositTimer = serviceWithDelay('pcallSendPosit', 1000, pcallSendPosit, 0)	-- ,0 to keep running
	end
end

local function runServiceTimers()
	local which = ''
	local now = MOAISim.getDeviceTime()
	local expired = {}
	local ready = {}
	for k,v in pairs(serviceTimers) do
		if v.expires <= now then
--print('runServiceTimer['..k..'] ready')
			ready[k] = v
			v.expires = now + v.delay	-- Reset for forever (0) repeats
			if v.repeats >= 1 then
--print('runServiceTimer['..k..'] rescheduled')
				v.repeats = v.repeats - 1
				if v.repeats == 0 then
--print('runServiceTimer['..k..'] expiring')
					expired[#expired+1] = k
				end
			end
		end
	end
	for k,v in ipairs(expired) do
--print('runServiceTimer['..v..'] EXPIRED!')
		serviceTimers[v] = nil
	end

	local elapsed = (MOAISim.getDeviceTime()-now)*1000
	which = 'prep:'..math.floor(elapsed)..'ms'

	for k,v in pairs(ready) do
--print('runServiceTimer['..k..'] dispatching')
		local start = MOAISim.getDeviceTime()
		if debugging then
			v.func(unpack(v.arg))
		else
			local status, text = pcall(v.func, unpack(v.arg))
			if not status then
				scheduleNotification(0,{ alert='runServiceTimer['..k..']:'..tostring(text)})
			end
		end
		local elapsed = (MOAISim.getDeviceTime()-start)*1000
		which = which..' '..k..':'..math.floor(elapsed)..'ms'
	end
	return which
end

--
local client, clientServer
local initialized = false

local locationCounter = 0	-- Diagnosing location callbacks

local gpxDir = (MOAIEnvironment.externalFilesDirectory or '/sdcard/'..MOAIEnvironment.appDisplayName)..'/GPX/'

local function makeSDcardDirectory(file)
print('makeSDcardDirectory('..file..')')
	if file == '' then return nil end
	local path = string.match(file, "(.+)/.+")
	if not path then return nil end
	local fullpath = path
	print('affirmPath('..fullpath..')')
	MOAIFileSystem.affirmPath(fullpath)
	return fullpath
end

local function GetGPXFileName(StationID, StartTime, suffix)
	suffix = suffix or ''
	return StationID..'-'..os.date("!%Y%m%d-%H%M", StartTime)..suffix..'.gpx'
end

local function SaveTrackToGPX(StationID, track, suffix)

	if type(track) ~= 'table' or #track < 2 then return nil end

	local shortname = GetGPXFileName(StationID, track[1].when, suffix)
	local filename = gpxDir..shortname

	if not makeSDcardDirectory(filename) then toast.new('makeSDcardDirectory('..filename..') FAILED!', 5000) return nil end
	local file, err = io.open(filename,'w')
	if not file then toast.new('io.open('..filename..') failed with '..tostring(err), 5000) return nil end

	file:write(string.format("<gpx version=\"1.1\" creator=\"%s %s\">\n", appName, config.About.Version))
	file:write("<metadata>\n");
	file:write(string.format("<name>%s</name>\n", filename));
	file:write(string.format("<desc>APRS Track For %s</desc>\n", StationID));
	file:write(string.format("<author><name>%s</name></author>\n", StationID));
	file:write(string.format("<link href=\"http://aprs.fi/%s\"><text>%s at APRS.FI</text></link>\n", StationID, StationID));
	file:write(os.date("!<time>%Y-%m-%dT%H:%M:%SZ</time>\n",track[1].when));
	file:write("</metadata>\n");

	local function writeTrack(file, track)
		file:write("<trk>\n");
		file:write("<trkseg>\n");

		for t=1, #track do
			if type(track[t].when) == 'number' then
			--if (Station->Tracks[t].Invalid == TRACK_OK)	/* Only the good ones */
				file:write(string.format("<trkpt lat=\"%.6f\" lon=\"%.6f\">",
										track[t].lat, track[t].lon))
				if type(track[t].alt) == 'number' and track[t].alt > 0 then
					file:write(string.format("<ele>%d</ele>", track[t].alt))
				end
				if not track[t].label then track[t].label = "" end
				file:write(os.date("!<time>%Y-%m-%dT%H:%M:%SZ</time><name>%H:%M:%S ", track[t].when))
				file:write(tostring(track[t].label).."</name></trkpt>\n")
			end	-- if when
		end	-- do
		file:write("</trkseg>\n");
		file:write("</trk>\n");
	end
	writeTrack(file, track)
	file:write("</gpx>\n");
	file:close()
	return shortname
end

local socket = require("socket")

local client
local lastReceive, lastPackets, lastIdle

local clientConnecting
local function timedConnection()
--print('timedConnection:client='..tostring(client)..' connecting='..tostring(clientConnecting)..' server='..tostring(clientServer))
	if config.APRSIS.Enabled then
		if not client then
			local status, text = pcall(getConnection)
			if not status then
				scheduleNotification(0,{alert = 'getConnection:'..tostring(text)})
			end
		else
			local text = os.date("%H:%M:%S:")..tostring(clientServer)..' '..tostring(clientConnecting)
			print(text)
		end
	else
		local text = os.date("%H:%M:%S:APRS-IS Disabled!")
		print(text)
	end
	serviceWithDelay('timedConnection', 60*1000, timedConnection)
end

closeConnection = function (why)
	print('closeConnection('..why..')')
	if client then
		client:close()	-- Close it down
		client = nil	-- and clean it up so getConnection will recover
		clientServer = nil
		if connectedCallback then
			local status, text = pcall(connectedCallback,nil)
			if not status then
				scheduleNotification(0,{alert = 'connectedCallback:'..tostring(text)})
			end
		end
		local alert = "APRS-IS Lost("..tostring(why)..")"
		toast.new(alert, 2000)
	end
	serviceWithDelay('getConnection', 5*1000, getConnection)
end

local lastPosit
local MOVING_SPEED = 1.0 * 0.868976	-- compared to knots (location's speed), but want 1.0 mph

local function CalculateGenius(lastPosit, thisPosit)	-- returns Genius table
	local Genius = { coordinatesMoved = false, deltaDistance = 0, deltaBearing = 0, deltaHeading = -1,
						forecastDistance = 0, projDistance = 0, projBearing = 0 }
--	NOTE: final ,0 should be Beacon's Accuracy for additional digits
--lwdText.text = 'genius:1'
	Genius.coordinatesMoved = not AreCoordinatesEquivalent(lastPosit.lat, lastPosit.lon,
															thisPosit.lat, thisPosit.lon, 2)

--lwdText.text = 'genius:2'
	local fromPoint = LatLon.new(lastPosit.lat, lastPosit.lon)
	local toPoint = LatLon.new(thisPosit.lat, thisPosit.lon)
--lwdText.text = 'genius:3'
	Genius.deltaDistance = kmToMiles(fromPoint.distanceTo(toPoint))
	Genius.deltaBearing = fromPoint.bearingTo(toPoint)
--lwdText.text = 'genius:4'

	--print("CalculateGenius:Moved:", Genius.deltaDistance, Genius.deltaHeading)
	
	local deltaMS = thisPosit.when - lastPosit.when
	if deltaMS > 0 then
		if lastPosit.moving and lastPosit.speed and lastPosit.course then	-- enough info to forecast
--lwdText.text = 'genius:5'
			Genius.forecastDistance = deltaMS * knotsToMph(lastPosit.speed) / 60 / 60 / 1000	-- Miles
			local projPoint = fromPoint.destinationPoint(lastPosit.course, milesToKm(Genius.forecastDistance))
			Genius.projDistance = kmToMiles(toPoint.distanceTo(projPoint))
			Genius.projBearing = toPoint.bearingTo(projPoint)
		elseif Genius.coordinatesMoved and thisPosit.moving and not lastPosit.moving then	-- but no longer stationary (don't use stopped!)
			Genius.projDistance = Genius.deltaDistance
			Genius.projBearing = toPoint.bearingTo(fromPoint)	-- Bearing from current loc back to stopped point
		end
	end

--lwdText.text = 'genius:6'
	if lastPosit.course and thisPosit.course then
		if lastPosit.moving and thisPosit.moving then	-- don't trust course if not moving, it drifts
--lwdText.text = 'genius:7'
			Genius.deltaHeading = math.abs(thisPosit.course - lastPosit.course)
			if Genius.deltaHeading > 180 then Genius.deltaHeading = 360 - Genius.deltaHeading end
		end
	end
--lwdText.text = 'genius:8'

	return Genius
end

--function osmTiles:getQueueStats()	-- returns count, maxcount, pushcount, popcount

local redDot, rangeGroup, debugGenius, geniusText

function APRSIS:mapResized(width, height)
	if osmTiles then
		local tileGroup = osmTiles:getTileGroup()
		if rangeGroup then
			tileGroup:removeChild(rangeGroup)
			rangeGroup = nil
		end
		if redDot then
			tileGroup:removeChild(redDot)
			redDot = nil
		end
	end
end

local function CalcTransmitPressure(lastPosit, thisPosit, force)	-- Returns Pressure, Why

	if config.Screen.RangeCircle and osmTiles then
		local tileGroup = osmTiles:getTileGroup()
		local w, h = osmTiles:getSize()
		local r = math.min(w, h)/2
		local dpi = MOAIEnvironment.screenDpi
		local bs = dpi/16	-- Bar size = 1/16"
		if not rangeGroup then
			rangeGroup = Group()
			rangeCircle = Graphics {width = r*2-2, height = r*2-2, left = w/2-r, top = h/2-r}
			--rangeCircle:setPenColor(64/255, 64/255, 64/255, 128/255):setPenWidth(3):drawCircle(w/2-r,h/2-r,r,32)
			rangeCircle:setPenWidth(3):drawCircle()
			rangeCircle:setColor(64/255, 64/255, 64/255, 128/255)
			rangeCircle:setPriority(2000000019)
			rangeGroup:addChild(rangeCircle)
			
			tileGroup:addChild(rangeGroup)
			
--rangeCircle:addEventListener( "touchUp", function() print(os.date("%H:%M:%S:")..'rangeCircle touchUp!') end )
		end
		if rangeGroup
		and tileGroup.offsetVersion
		and (not rangeGroup.offsetVersion
			or tileGroup.offsetVersion ~= rangeGroup.offsetVersion)	then -- map changed offsets!
			rangeGroup.offsetVersion = tileGroup.offsetVersion
			local horzDistance, vertDistance = osmTiles:rangeLatLon(r)

			if horzDistance < 1 then
				horzDistance = string.format("%.3fmi", horzDistance)
			elseif horzDistance < 10 then
				horzDistance = string.format("%.2fmi", horzDistance)
			elseif horzDistance < 100 then
				horzDistance = string.format("%.1fmi", horzDistance)
			else horzDistance = string.format("%imi", horzDistance)
			end
			if vertDistance < 1 then
				vertDistance = string.format("%.3f", vertDistance)
			elseif vertDistance < 10 then
				vertDistance = string.format("%.2f", vertDistance)
			elseif vertDistance < 100 then
				vertDistance = string.format("%.1f", vertDistance)
			else vertDistance = string.format("%i", vertDistance)
			end

			local wb, hb = r, bs
			local lb, tb = w/2-wb/2, h-hb
			if rangeGroup.horzScale then rangeGroup:removeChild(rangeGroup.horzScale) end
			local horzScale = Graphics { width=wb, height=hb, left=lb, top=tb }
			horzScale:setPenColor(0,0,0,1):drawRect(0, 0, wb, hb)
			horzScale:setPenColor(0,0,0,1):fillRect(0, 0, wb/4, hb)
			horzScale:setPenColor(0,0,0,1):fillRect(wb/2, 0, wb*3/4, hb)
			horzScale:setPriority(2000000019)
			rangeGroup:addChild(horzScale)
			rangeGroup.horzScale = horzScale

			if not rangeGroup.horzLabel then
				rangeGroup.horzLabel = TextLabel { text=horzDistance, textSize=bs*2, width=r/2, height=bs*4, left=w/2+r/2, top=h-bs*2-2 }
				rangeGroup.horzLabel:setRGBA(0, 0, 0, 1)
				--rangeGroup.horzLabel:setAlignment ( MOAITextBox.LEFT_JUSTIFY )
				rangeGroup.horzLabel:setPriority(2000000019)
				rangeGroup:addChild(rangeGroup.horzLabel)
			else rangeGroup.horzLabel:setString(horzDistance)
			end
			--rangeGroup.horzLabel:fitSize()
			rangeGroup.horzLabel:setLeft(w/2+r/2+bs/2)
			rangeGroup.horzLabel:setTop(h-bs*2.5)

			if vertDistance ~= horzDistance:sub(1,#vertDistance) then	-- If horizontal and vertical scales are different
				if rangeGroup.vertScale then rangeGroup:removeChild(rangeGroup.vertScale) end
				local wb, hb = bs, r
				local lb, tb = w-wb, h/2-hb/2
				local vertScale = Graphics { width=wb, height=hb, left=lb, top=tb }
				vertScale:setPenColor(0,0,0,1):drawRect(0, 0, wb, hb)
				vertScale:setPenColor(0,0,0,1):fillRect(0, 0, wb, hb/4)
				vertScale:setPenColor(0,0,0,1):fillRect(0, hb/2, wb, hb*3/4)
				vertScale:setPriority(2000000019)
				rangeGroup:addChild(vertScale)
				rangeGroup.vertScale = vertScale
			
				if not rangeGroup.vertLabel then
					rangeGroup.vertLabel = TextLabel { text=vertDistance, textSize=bs*1.5, width=r/2, height=bs*4, left=w/2, top=h-bs*2-2 }
					--rangeGroup.vertLabel:setRot(0,0,270)
					rangeGroup.vertLabel:setRGBA(0, 0, 0, 1)
					rangeGroup.vertLabel:setAlignment ( MOAITextBox.RIGHT_JUSTIFY )
					rangeGroup.vertLabel:setPriority(2000000019)
					rangeGroup:addChild(rangeGroup.vertLabel)
				else
					rangeGroup.vertLabel:setString(vertDistance)
					rangeGroup:addChild(rangeGroup.vertLabel)	-- ensure that it's visible
				end
				--rangeGroup.vertLabel:fitSize()
				--rangeGroup.vertLabel:setTop(h/2+r/2+bs*2.75)
				--rangeGroup.vertLabel:setTop(h/2+bs*2.75)
				--rangeGroup.vertLabel:setLeft(w-bs*4.5)
				rangeGroup.vertLabel:setRight(w-bs/4)
				rangeGroup.vertLabel:setTop(h/2+r/2)
			else	-- Make the vertical stuff disappear as the scales are equal
				if rangeGroup.vertScale then rangeGroup:removeChild(rangeGroup.vertScale) rangeGroup.vertScale = nil end
				if rangeGroup.vertLabel then rangeGroup:removeChild(rangeGroup.vertLabel) rangeGroup.vertLabel = nil end
			end
		end
	elseif rangeGroup then
		local tileGroup = osmTiles:getTileGroup()
		tileGroup:removeChild(rangeGroup)
		rangeGroup = nil
	end
	if config.Screen.RedDot and simRunning then
		if not redDot and osmTiles and getSymbolImage then
			redDot = Group()
			local w, h = osmTiles:getSize()
			redDot.dot = getSymbolImage('//', '0@0')
			--redDot:addEventListener("tap", function (event) Vibrate(true); debugGenius = not debugGenius return true end)
			redDot.dot:setScl(1.5,1.5,1.5)
			redDot:addChild(redDot.dot)
			local tSize = math.min(redDot.dot:getWidth(),redDot.dot:getHeight())*0.7
			tSize = 20
			redDot.text = TextLabel { text="100%@999", textSize=tSize }
			redDot.text:setAlignment ( MOAITextBox.RIGHT_JUSTIFY )
			redDot.text:fitSize()
			redDot.text:setLoc(0,0)
			redDot.text:setRight(-tSize/2)
			redDot.text:setColor(1.0,0,0,1.0)
			redDot.text:setPriority(2000000020)
			redDot:addChild(redDot.text)
			local tileGroup = osmTiles:getTileGroup()
			redDot:setPriority(2000000020)
			tileGroup:addChild(redDot)
			redDot:setLoc(w/2, h/2)
			redDot:setLoc(w*2,h*2)	-- Put it off-screen until needed
redDot:addEventListener( "touchUp", function() print(os.date("%H:%M:%S:")..'redDot touchUp!') end )
		end
	elseif redDot then
		local tileGroup = osmTiles:getTileGroup()
		tileGroup:removeChild(redDot)
		redDot = nil
	end

	local newPressure
	local Pressure, Why = 0, ''
--lwdText.text = 'calc:1'
	thisPosit.moving = (thisPosit.speed and (thisPosit.speed > MOVING_SPEED))
	thisPosit.stopped = (thisPosit.speed and (thisPosit.speed == 0))
--lwdText.text = 'calc:2'
	if config.Beacon.AfterTransmit and not thisPosit.gotLocation then
		Pressure = 0; Why = 'Need Loc'
	elseif not lastPosit or lastPosit.when > thisPosit.when then 
--lwdText.text = 'calc:3'
		Pressure = 100.0; Why = 'FIRST'
		--if accText and accText.text then accText.text = 'FIRST' end
	elseif force then
		Pressure = 100; Why = force
	else
--lwdText.text = 'calc:4'
		local Genius = CalculateGenius(lastPosit, thisPosit)
--lwdText.text = 'calc:5'
		if debugGenius then
			if not geniusText then
				geniusText = display.newText("", 0, 0, native.systemFont, 18)
				geniusText:setTextColor(0)
				geniusText:setReferencePoint(display.CenterLeftReferencePoint)
				geniusText.x = 0
				geniusText.y = display.contentHeight/2
			end
			local last = ''
			if lastPosit.why then last = last..tostring(lastPosit.why)..'\r\n' end
			if lastPosit.startWhen or lastPosit.stopWhen then
				if lastPosit.startWhen then
					last = last..string.format('Starting+%is:\r\n', (lastPosit.startWhen-thisPosit.when)/1000)
				end
				if lastPosit.stopWhen then
					last = last..string.format('Stopping+%is:\r\n', (lastPosit.stopWhen-thisPosit.when)/1000)
				end
			else last = last..'Not Stop/Starting...\r\n'
			end
			last = last..'Last:'
			if lastPosit.moving then
				last = last..'Moving:'
			end
			if lastPosit.stopped then
				last = last..'Stopped:'
			end
			if lastPosit.speed and lastPosit.course then
				last = last..string.format("%.2fkn@%i", lastPosit.speed, lastPosit.course)
			end
			last = last..string.format("*%is\r\n", (thisPosit.when-lastPosit.when)/1000)
			if thisPosit.moving or thisPosit.stopped
			or (thisPosit.speed and thisPosit.course) then
				last = last..'This:'
				if thisPosit.moving then
					last = last..'Moving:'
				end
				if thisPosit.stopped then
					last = last..'Stopped:'
				end
				if thisPosit.speed and thisPosit.course then
					last = last..string.format("%.2fkn@%i", thisPosit.speed, thisPosit.course)
				end
				last = last..'\r\n'
			end
			geniusText.text = last..printableTable('Genius', Genius, '\r\n')
			geniusText.x = geniusText.contentWidth / 2
			geniusText.y = display.contentHeight/2
			geniusText.alpha = 1.0
		elseif geniusText then
			geniusText.alpha = 0
		end
		--print(printableTable('Genius', Genius))

		if redDot then
			local w, h = osmTiles:getSize()
			if tonumber(config.Genius.ForecastError) <= 0 or Genius.projDistance <= 0 then
				redDot:setLoc(w*2,h*2)	-- Put it offscreen until needed
			else
				--osmTiles:insertOverMap(redDot)
--lwdText.text = 'calc:8'
				if config.Enables.GPS then
					local radius = math.min(w, h)/2
					local bearing = (Genius.projBearing) / 180 * math.pi
					local range = math.min(Genius.projDistance, config.Genius.ForecastError)
					--range = config.Genius.ForecastError*0.95
					local scale = config.Genius.ForecastError
					if scale ~= 0 then
						local x = math.sin(bearing) * range / scale * radius + 0.5 + w/2
						local y = -math.cos(bearing) * range / scale * radius + 0.5 + h/2
						redDot:setLoc(x,y)
					end
					redDot.text:setString(string.format('%i%%@%i', range/scale*100, Genius.projBearing))
				else
					redDot:setLoc(w*2,h*2)	-- Put it off-screen until needed
				end
			end
		end
		
--lwdText.text = 'calc:6'
--[[
		local w,h = getDisplayWH()	-- with Corona SDK fix
		w,h = display.contentWidth, display.contentHeight
		if config.Screen.RedDot then
			if not redDot then
				redDot = getSymbolImage('//', '0@0')
				redDot.x = w / 2
				redDot.y = h / 2
				redDot:addEventListener("tap", function (event) Vibrate(true); debugGenius = not debugGenius return true end)
				redDot[1]:setTextColor(0)
				redDot[1].alpha = 1.0
				redDot[1]:scale(1.5,1.5)
				--redDot[1].x = redDot[2].contentWidth / 2
			end
		elseif redDot then
			redDot:removeSelf()
			redDot = nil
		end
--lwdText.text = 'calc:7'
		if config.Screen.RangeCircle then
			if not rangeCircle then
				local radius = math.min(w, h)/2 - titleYOffset/2
				rangeCircle = display.newCircle(0,0,radius)
				rangeCircle:setFillColor(255,255,255,0)
				rangeCircle.strokeWidth = 2
				rangeCircle:setStrokeColor(192,192,192,192)
				rangeCircle.x = w/2
				rangeCircle.y = h/2 + titleYOffset/2
				osmTiles:insertOverMap(rangeCircle)
			end
		elseif rangeCircle then
			rangeCircle:removeSelf()
			rangeCircle = nil
		end
		if redDot then
			--if tonumber(config.Genius.ForecastError) <= 0 or Genius.projDistance <= 0 then
				--redDot.alpha = 0
			--else
				osmTiles:insertOverMap(redDot)
--lwdText.text = 'calc:8'
				if config.Enables.GPS then
			local w, h = osmTiles:getSize()
			redDot = getSymbolImage('//', '0@0')
			redDot:setLoc(w/2, h/2)
					redDot.alpha = 1.0
					--Genius.projBearing = 90
					local bearing = (Genius.projBearing) / 180 * math.pi
					local range = math.min(Genius.projDistance, config.Genius.ForecastError)
					--range = config.Genius.ForecastError*0.95
					local scale = config.Genius.ForecastError
					local radius = math.min(w, h)/2 - titleYOffset/2
					local x = math.sin(bearing) * range / scale * radius + 0.5 + w/2
					local y = -math.cos(bearing) * range / scale * radius + 0.5 + h/2
					redDot.x, redDot.y = x,y
					setSymbolLabel(redDot, string.format('%i%%@%i', range/scale*100, Genius.projBearing))
				else
					redDot.alpha = 0.0
				end
			--end
		end
]]
--lwdText.text = 'calc:9'
		if not Genius.TimeOnly then
		-- and GPSEnabled?
			if config.Genius.StartStop
			-- and GPSEnabled?
			and Genius.coordinatesMoved then
				if thisPosit.moving then
					if (lastPosit.stopped or lastPosit.startWhen) then
						if not lastPosit.startWhen then
							lastPosit.startWhen = thisPosit.when + config.Genius.MinTime*1000
							lastPosit.startingCount = locationCounter
						end
--lwdText.text = 'calc:10'
						Pressure = 100-(lastPosit.startWhen-thisPosit.when)/1000/(config.Genius.MinTime or 1)*100
						Why = string.format('START %i%%(%i)', Pressure, locationCounter-lastPosit.startingCount)
						thisPosit.startingCount = lastPosit.startingCount
					else lastPosit.startWhen = nil	-- no longer qualifies, reset timer
					end
					lastPosit.stopWhen = nil	-- Moving kills the stop timer
				else lastPosit.startWhen = nil	-- No longer moving, not starting!
				end
				if thisPosit.stopped then
					if (lastPosit.moving or lastPosit.stopWhen) then
						if not lastPosit.stopWhen then
							lastPosit.stopWhen = thisPosit.when + config.Genius.MinTime*1000
							lastPosit.stoppingCount = locationCounter
						end
--lwdText.text = 'calc:11'
						Pressure = 100-(lastPosit.stopWhen-thisPosit.when)/1000/(config.Genius.MinTime or 1)*100
						Why = string.format('STOP %i%%(%i)', Pressure, locationCounter-lastPosit.stoppingCount)
						thisPosit.stoppingCount = lastPosit.stoppingCount
					else lastPosit.stopWhen = nil	-- no longer qualifies, reset timer
					end
					lastPosit.startWhen = nil	-- Stopped kills the start timer
				else lastPosit.stopWhen = nil	-- no longer stopped, not stopping!
				end
			end
--lwdText.text = 'calc:dD'
			newPressure = Genius.deltaDistance / config.Genius.MaxDistance * 100
			if newPressure > Pressure then Why = string.format('Dist %i%%', newPressure); Pressure = newPressure; end

--lwdText.text = 'calc:fD'
			newPressure = Genius.forecastDistance / config.Genius.MaxDistance * 100
			if newPressure > Pressure then Why = string.format('Fore %i%%', newPressure); Pressure = newPressure; end

--lwdText.text = 'calc:pD'
			newPressure = Genius.projDistance / config.Genius.ForecastError * 100
			if newPressure > Pressure then Why = string.format('Proj %i%%', newPressure); Pressure = newPressure; end

			if Genius.coordinatesMoved then
			if Genius.deltaHeading > 0 then
			if tonumber(config.Genius.HeadingChange) > 0 and tonumber(config.Genius.HeadingChange) < 180 then
--lwdText.text = 'calc:Hd'
				newPressure = Genius.deltaHeading / config.Genius.HeadingChange * 100
				if newPressure > Pressure then Why = string.format('Head %i%%', newPressure); Pressure = newPressure; end
			end
			end
			end
		end

		local deltaSec = (thisPosit.when-lastPosit.when)/1000
		newPressure = deltaSec/60 / config.Genius.MaxTime * 100
		if newPressure > Pressure then
			local sec = math.floor(math.max(0, config.Genius.MaxTime*60 - deltaSec))
			local Seconds = sec % 60
			local Minutes = (sec / 60) % 60
			local Hours = math.floor(sec / 3600)
--lwdText.text = 'calc:T'
			Why = string.format('Time %i:%02i:%02i', Hours, Minutes, Seconds);
			Pressure = newPressure;
		end
	end

	return Pressure, Why
end

pcallSendPosit = function (event)
	if debugging then
		local text = sendPosit()
		if text then print('sendPosit returned '..tostring(text)) end
	else
		local status, text = pcall(sendPosit)
		if not status then
			scheduleNotification(0,{alert = 'sendPosit:'..tostring(text)})
		elseif text and config.Beacon.Enabled then
			print('sendPosit returned '..tostring(text))
		end
	end
end

local lastGPXWrite = nil
local lastGPSWrite = nil

function addCrumb(lat, lon, alt, tWhy)
--print("addCrumb:"..tWhy)
	if not myStation.crumbsLong then
		myStation.crumbsLong = {}
		myStation.crumbsLong.color = colors:getColorArray('pink')
	end
	if not myStation.crumbShort then
		myStation.crumbShort = {}
		myStation.crumbShort.color = myStation.crumbsLong.color
	end
	if #myStation.crumbShort == 0
	or lat ~= myStation.crumbShort[#myStation.crumbShort].lat
	or lon ~= myStation.crumbShort[#myStation.crumbShort].lon
	or tWhy ~= myStation.crumbShort[#myStation.crumbShort].label then
		myStation.crumbShort[#myStation.crumbShort+1] = { lat=lat, lon=lon, alt=alt, label=tWhy}
		myStation.crumbShort[#myStation.crumbShort].when = os.time()
--print("addCrumb:showTrack:"..#myStation.crumbShort.." points")
		showTrack(myStation.crumbShort, false, "crumbShort")
	end
end

sendPosit = function (event, force)
if force then
	print(os.date("%H:%M:%S sendPosit(")..force..')')
end
if simRunning and not osmTiles then
	osmTiles = require("osmTiles")	-- pick it up now for later use
end

	local status = nil
	--if myStation.lat ~= 0.0 or myStation.lon ~= 0.0 then
--lwdText.text = 'send:1'
		local thisPosit = {}
		thisPosit.gotLocation = myStation.gotLocation
		thisPosit.lat, thisPosit.lon = myStation.lat, myStation.lon
		thisPosit.course, thisPosit.speed = myStation.course, myStation.speed
		thisPosit.when = MOAISim.getDeviceTime()*1000
--lwdText.text = 'send:2'
		local tPressure, tWhy = CalcTransmitPressure(lastPosit, thisPosit, force)
--		lwdText.text = tWhy
--lwdText.text = '1:'..tWhy
--print(tWhy)
whyUpdate = tWhy
--whytext:setString ( tWhy )
--whytext:fitSize()
--whytext:setLoc(Application.viewWidth/2, Application.viewHeight-20*config.Screen.scale)

		if not myStation.crumbShort or #myStation.crumbShort == 0
		or myStation.lat ~= myStation.crumbShort[#myStation.crumbShort].lat
		or myStation.lon ~= myStation.crumbShort[#myStation.crumbShort].lon
		or tPressure >= 100 then
			addCrumb(myStation.lat, myStation.lon, myStation.alt, tWhy)
		end

		if tPressure >= 100 then
			if lastPosit and lastPosit.when
			and thisPosit.when-lastPosit.when < tonumber(config.Genius.MinTime)*1000 then
local tempWhy = '2Soon:'..tWhy
whyUpdate = tempWhy
--whytext:setString(tempWhy)
--whytext:fitSize()
--whytext:setLoc(Application.viewWidth/2, Application.viewHeight-20*config.Screen.scale)
				status = 'Too Soon ('..tostring(math.floor((thisPosit.when-lastPosit.when)/1000))..'/'..tostring(config.Genius.MinTime)..'s)'
			else
				local components = { lat=myStation.lat, lon = myStation.lon,
										symbol = myStation.symbol }
				components.comment = config.Beacon.Comment
--lwdText.text = '2:'..tWhy
				if config.Beacon.Altitude and myStation.alt then components.alt = myStation.alt end
				if config.Beacon.Speed and myStation.course and myStation.speed then components.course = myStation.course; components.speed = myStation.speed end
				if config.Beacon.AutoAmbiguity and myStation.acc then
					if myStation.acc >= 18520 then	-- 10nm in meters
						components.ambiguity = 3
					elseif myStation.acc >= 1852 then	-- 1nm in meters
						components.ambiguity = 2
					elseif myStation.acc >= 185 then	-- 0.1nm in meters
						components.ambiguity = 1
					end
				end
--lwdText.text = '3:'..tWhy
				if config.Beacon.Why then
					if lastPosit then
						components.comment = string.format("(%i/%i) %s",
												locationCounter-lastPosit.locationCounter,
												(thisPosit.when-lastPosit.when)/1000,
												components.comment)
					end
					if tWhy and #tWhy then components.comment = tWhy..' '..components.comment end
				end
--lwdText.text = '4:'..tWhy

				if not config.Beacon.Enabled then
					status = 'Beacon Disabled'
--lwdText.text = '5:'..tWhy
				elseif not client then
					status = 'No APRS-IS Connection'
--lwdText.text = '6:'..tWhy
				else
					local prefix = ''
					if config.Beacon.TimestampHH then	-- @Messaging+Time /noMessaging+Time
						prefix = os.date('!@%H%M%Sh')
					elseif config.Beacon.TimestampDD then
						prefix = os.date('!@%d%H%Mz')
					else	prefix = '='	-- =Messaging+noTime !noMessaging+noTime
					end
					--local posit = config.StationID..'>APWA00,TCPIP*:!'..APRS:Posit(components) -- !no messaging, no timestamp
					local posit = config.StationID..'>APWA00,TCPIP*:'..prefix..APRS:Posit(components) -- =messaging, no timestamp
--lwdText.text = '7a:'..tWhy
					local n, err = client:send(posit..'\r\n')
--lwdText.text = '7b:'..tWhy
					print ('sendPosit['..tostring(n)..']:'..posit)
--lwdText.text = '8:'..tWhy
					if type(n) ~= 'number' or n == 0 then
						closeConnection('sendPosit Error:'..tostring(err))
					else
						if not myStation.tracks then
							myStation.tracks = {}
							myStation.tracks.color = colors:getColorArray('red')
						end
						local trackSize = #myStation.tracks
						if trackSize == 0
						or type(myStation.tracks[trackSize].original) == 'nil'
						or myStation.lat ~= myStation.tracks[trackSize].lat
						or myStation.lon ~= myStation.tracks[trackSize].lon then
							if trackSize == 0 
							or type(myStation.tracks[trackSize].original) ~= 'nil' then
								trackSize = trackSize + 1
								if myStation.trkseg then	-- If we have a lurking segment, get rid of it!
									removeTrack(myStation.trkseg)
									myStation.trkseg = nil
								end
							end
							myStation.tracks[trackSize] = { lat=myStation.lat, lon=myStation.lon, label=tWhy, original=posit }
							myStation.tracks[trackSize].when = os.time()
							showTrack(myStation.tracks, true, "ME-Tracks")	-- No longer showing it above!
	if config.Enables.SaveMyTrack then
		local status, GPXname = pcall(SaveTrackToGPX, config.StationID, myStation.tracks)
		if not status then
			scheduleNotification(0,{alert='SaveTrackToGPX(track):'..tostring(GPXname)})
		elseif GPXname then
			--if lastGPXWrite then cancelNotification(lastGPXWrite) end
			--lastGPXWrite = scheduleNotification(0,{alert=tostring(#myStation.tracks)..' written to '..GPXname})
			toast.new(tostring(#myStation.tracks)..' written to '..GPXname, 1000)
		end
	end
--print('APRSIS:sendPosit:Adding '..#myStation.crumbShort..' crumbs to '..#myStation.crumbsLong..' track')
	local lc = #myStation.crumbsLong
	for k,v in ipairs(myStation.crumbShort) do
		if lc == 0
		or myStation.crumbsLong[lc] ~= v then
			lc = lc + 1
			myStation.crumbsLong[lc] = v
		end
	end
--print("APRSIS:sendPosit:Resetting crumbShort and showing crumbsLong")
	if osmTiles then removeTrack(myStation.crumbShort) end
	myStation.crumbShort = {}	-- Empty the short track
	myStation.crumbShort.color = myStation.crumbsLong.color
	myStation.crumbShort[1] = myStation.crumbsLong[lc]	-- and restart at last point
	showTrack(myStation.crumbsLong, false, "crumbsLong")
	--if osmTiles then osmTiles:showTrack(myStation.crumbShort, false, "crumbShort") end
	if config.Enables.SaveMyCrumbs then
		local status, GPXname = pcall(SaveTrackToGPX, config.StationID, myStation.crumbsLong, '-GPS')
		if not status then
			scheduleNotification(0,{alert='SaveTrackToGPX(crumbs):'..tostring(GPXname)})
		elseif GPXname then
			--if lastGPSWrite then cancelNotification(lastGPSWrite) end
			--lastGPSWrite = scheduleNotification(0,{alert=tostring(#myStation.crumbsLong)..' written to '..GPXname..'-GPS'})
			toast.new(tostring(#myStation.crumbsLong)..' written to '..GPXname, 2000)
		end
	end
							--print(string.format('%s Has %i Packets %i Done!', myStation.stationID, #myStation.tracks, (myStation.tracks.donePoint or 0)))
							--if #myStation.tracks > 2 then
								--if centerStation ~= myStation then
									--toast.new(string.format('%s Has %i Packets', myStation.stationID, #myStation.tracks), 3000, makeCenterTapCallback(myStation))
								--end
							--end
						end


					end
					myStation.packetsHeard = (myStation.packetsHeard or 0) + 1
					lastPosit = thisPosit
					lastPosit.why = tWhy
					lastPosit.locationCounter = locationCounter
					lastPosit.startWhen, lastPosit.stopWhen = nil, nil	-- don't need these after beaconing
--lwdText.text = '9:'..tWhy

					if config.Screen.PositPop and osmTiles and simRunning then
						local tileGroup = osmTiles:getTileGroup()
						local x, y = osmTiles:whereIS(myStation.lat, myStation.lon)
						x, y = osmTiles:translateXY(x,y)
						local w, h = osmTiles:getSize()
print("positPop - Creating positGroup for "..tostring(tWhy)..", currently "..tostring(positGroup))
						local positGroup = Group()
						if tWhy and #tWhy > 0 then
							local positText  = TextLabel { text=tWhy, textSize=48 }
							positText:setColor(0,0,0,1.0)
							positText:fitSize()
							if x > w*0.75 then
								positText:setAlignment ( MOAITextBox.RIGHT_JUSTIFY )
								positText:setLoc(0,0)
								positText:setRight(-40)
							else
								positText:setAlignment ( MOAITextBox.LEFT_JUSTIFY )
								positText:setLoc(0,0)
								positText:setLeft(40)
							end
							positText:setPriority(2000000040)
							positGroup:addChild(positText)
						end
						local dot = getSymbolImage('//', 'posit')
						dot:setScl(10,10,10)
						dot:setPriority(2000000039)
						positGroup:addChild(dot)

						if x < 20 or x > w-120 or y < 20 or y > h-20 then	-- if (nearly) off screen
							x = math.max(20,math.min(w-120,x))	-- move to edge of screen
							y = math.max(20,math.min(h-20,y))	-- move to edge of screen
							positGroup:setLoc(x, y)
							tileGroup:addChild(positGroup)
							local anim = Animation():sequence(
								Animation({positGroup},3,MOAIEaseType.EASE_OUT):seekScl(0.1, 0.1, 1.0),
								Animation({positGroup},0):callFunc(function() tileGroup:removeChild(positGroup) positGroup = nil print("removed positGroup - offscreen") end))
							anim:play()
						else	-- otherwise track it at lat/lon like a station symbol
							local positSymLab = {symbol=positGroup}
							osmTiles:showSymbol(myStation.lat, myStation.lon, positSymLab, "ME")
							local anim = Animation():sequence(
								Animation({positGroup},3,MOAIEaseType.EASE_OUT):seekScl(0.1, 0.1, 1.0),
								Animation({positGroup},0):callFunc(function() osmTiles:removeSymbol(positSymLab) positGroup = nil print("removed positGroup Symbol") end))
							anim:play()
						end
					end
--[[
					if config.Screen.PositPop then
						positGroup = display.newGroup()
						if tWhy and #tWhy then
							local positText  = display.newText( tWhy, 0, 0, native.systemFontBold, 48)
							positText:setTextColor(0)
							positText.x, positText.y = 0,50+positText.contentHeight/2
							positGroup:insert(positText)
						end
						local positCircle = display.newCircle(0,0,50)
						positGroup:insert(positCircle)
						positCircle:setFillColor(255,0,0, 192)
						local x, y = osmTiles:whereIS(myStation.lat, myStation.lon)
						if x and y then x, y = osmTiles:translateXY(x,y)
						else x, y = display.contentWidth / 2, 0
						end
						positGroup.x, positGroup.y = x, y
						transition.to( positCircle, { alpha = 0, time=5000, onComplete = positDone } )
						timer.performWithDelay(100, positShrink, 0)
					end
]]
--lwdText.text = 'D:'..tWhy
				end
			end
		end
	--end
	return status
end

sendStatus = function()
	if client then
		local environment = tostring(MOAIEnvironment.devPlatform or '')
		local model = tostring(MOAIEnvironment.devManufacturer or MOAIEnvironment.devBrand or '')
		local name = tostring(MOAIEnvironment.devModel or MOAIEnvironment.devName or '')
		local platformName = tostring(MOAIEnvironment.osBrand or '')
		local platformVersion = tostring(MOAIEnvironment.osVersion or '')
		if #environment > 0 then environment = ' '..environment end
		if #model > 0 then model = ' '..model end
		if #name > 0 then if name == 'unknown' then name = '' else name = ' '..name end end
		if #platformName > 0 then platformName = ' '..platformName end
		if #platformVersion > 0 then platformVersion = ' '..platformVersion end

		local myVersion = appVersion
		if not myVersion or myVersion == "" then myVersion = "" end
		if myVersion ~= "" then myVersion="("..myVersion..")" end

		local platformSize = ''
		if type(Application.viewWidth)=='number' and type(Application.viewHeight)=='number' then
			platformSize=platformSize..' '..tostring(Application.viewWidth)..'x'..tostring(Application.viewHeight)
		end
		if type(MOAIEnvironment.screenDpi)=='number' then
			platformSize=platformSize..'@'..tostring(MOAIEnvironment.screenDpi)..'dpi'
		end

		local report = appName..myVersion.." de KJ4ERJ"..environment..model..name..platformName..platformVersion..platformSize
		local pkt = config.StationID..'>APWA00,TCPIP*:>'..report
		local n, err = client:send(pkt..'\r\n')
		print ('sendStatus:'..pkt)
		if type(n) ~= 'number' or n == 0 then closeConnection('sendStatus Error:'..tostring(err)) end
		myStation.packetsHeard = (myStation.packetsHeard or 0) + 1
--[[
		if config.Screen.PositPop then
			statusCircle = display.newCircle(0,0,20)
			statusCircle:setFillColor(128,0,128,127)
			local x, y = osmTiles:whereIS(myStation.lat, myStation.lon)
			if x and y then x, y = osmTiles:translateXY(x,y)
			else x, y = display.contentWidth / 2, 0
			end
			statusCircle.x, statusCircle.y = x, y
			transition.to( statusCircle, { alpha = 0, time=5000, onComplete = statusDone } )
			timer.performWithDelay(100, statusShrink, 0)
			-- transition.to( statusCircle, { scale = 0.1, time=4000 } )
		end
]]
	end
end

local function flushClient()
	local packetInfo = nil
	if client then
		local rcvTime, callTime = 0, 0
		local count = 0
		local startTime = MOAISim.getDeviceTime()
		local gotoStation
		repeat
			local rcvStart = MOAISim.getDeviceTime()
			local line, err = client:receive('*l')
			if line then
				count = count + 1
				packetCount = packetCount + 1
				if packetCallback then
					local callStart = MOAISim.getDeviceTime()
					rcvTime = rcvTime + (callStart-rcvStart)
					if debugging then
						packetCallback(line, clientServer, APRSIS)
					else
						local status, text = pcall(packetCallback, line, clientServer, APRSIS)
						if not status then
							scheduleNotification(0,{alert='APRSIS:packetCallback:'..tostring(text)})
						end
					end
					callTime = callTime + (MOAISim.getDeviceTime()-callStart)
				end
			else
				if err ~= 'timeout' then
					closeConnection('Receive Error:'..err)
				end
			end
		until not line
		if client then
			local thisTime = MOAISim.getDeviceTime()
			local text = string.format('%i Packets in %.2fms(%.2f+%.2f)',
										count, (thisTime-startTime)*1000,
										rcvTime*1000, callTime*1000)
			local idle = ""
			if lastReceive then idle = ' Idle '..(math.floor((thisTime-lastReceive)*1)/1)..'s' end
			if count > 0 then
				lastPackets = text
				lwdUpdate = lastPackets..idle
				lastIdle = idle
			elseif idle ~= lastIdle then
				lwdUpdate = (lastPackets or "")..idle
				lastIdle = idle
			end

			--lwdtext:setString ( text );
			--lwdtext:fitSize()
			--lwdtext:setLoc(Application.viewWidth/2, 75*config.Screen.scale)

			if lwdtext then
				if not lwdtext.touchup then
					lwdtext.touchup = true
					lwdtext:addEventListener("touchUp",
								function()
									print("lwdtext touched!")
									local text = tostring(clientServer)..' '..tostring(clientConnecting)
									toast.new(text)
								end)
				end
			end

			if count > 0 then
				lastReceive = thisTime
			elseif lastReceive
			--and config.APRSIS.QuietTime > 0
			and (thisTime-lastReceive) > 60 then
				text = string.format('No Data in %i/%is',
												math.floor((thisTime-lastReceive)),
												60)
				closeConnection(text)
				lastReceive = nil
			end
		else
			lwdUpdate = "APRS-IS Lost"
			--flushStatus.text = "APRS-IS Connection Lost"
			lastReceive = nil
		end
		serviceWithDelay('flushClient', 50, flushClient)
		--coroutine.yield()
	else
		print ('No Client Connection')
	end
end

function APRSIS:sendPacket(packet)
	print ('APRSIS:sendPacket:'..packet)
	if client then
		local n, err = client:send(packet..'\r\n')
		if type(n) ~= 'number' or n == 0 then
			closeConnection('sendPacket Error:'..tostring(err))
			return 'Send Error'
		end
		return nil
	end
	return 'No Client Connection'
end

function WordWrap(aMsg, MaxWidth, PreLen)	-- returns table of wrapped lines

	local len = #aMsg
	
	if not MaxWidth then MaxWidth = len + 16 end	-- for good measure
	if not PreLen then PreLen = 0 end
	if len <= PreLen then PreLen = 0 end
	
	local p = 1
	local n = len/(MaxWidth/2-PreLen) + 1
	local r = {}
	
	local Next, Last

	Next = PreLen+1	-- Index to first checkable character
	while p <= n and Next <= len do

		while Next < len and aMsg:sub(Next,Next) == ' ' do Next = Next + 1 end	-- Remove leading spaces

		if PreLen > 0 then r[p] = aMsg:sub(1,PreLen) else r[p] = '' end	-- Initialize new line

		if len-Next > MaxWidth-PreLen then
			Last = Next + MaxWidth-PreLen-1;
-- Need to watch for next line starting with ? tripping up remote queries
-- Lines should also not start with ack, no matter how long they are
			while aMsg:sub(Last,Last) ~= ' ' and Last > Next+MaxWidth/2 do Last = Last - 1 end	-- Find previous white
			if aMsg:sub(Last,Last) == ' ' then
				while Last>Next and aMsg:sub(Last-1,Last-1) == ' ' do Last = Last - 1 end	-- Skip back over all spaces
			else Last = Next + MaxWidth-PreLen-1	-- No spaces, just chop the word
			end
		else Last = len+1;
		end

		r[p] = r[p]..aMsg:sub(Next,Last-1)

		local Check4More = Last
		while Check4More <= len and aMsg:sub(Check4More,Check4More) == ' ' do Check4More = Check4More + 1 end
		if Check4More <= len then r[p] = r[p]..'+' end	-- flag more to follow

		if #r[p] > PreLen then p = p + 1 end	-- Go to next line if data after prefix

		Next = Last
	end
	return r;
end

local msgAck
function sendAPRSMessage(to, text, additional)	-- nil return = success
	if client then
		local lines = WordWrap(text,67)
		for l = 1, #lines do
			msgAck = (msgAck or 0) + 1
			local actualAck = string.format("%02X",msgAck) .. "}" .. (stationInfo and stationInfo[to] and stationInfo[to].replyAck or "")
			local msg = string.format('%s>APWA00,TCPIP*::%-9s:%s{%s',
										config.StationID, to, lines[l], actualAck)
			local n, err = client:send(msg..'\r\n')
			local QSO, QSOi
			if additional then
				QSO, QSOi = QSOs:newQSOMessage(QSOs:getQSO("ME", to, additional), "ME", to, lines[l])
			else QSO, QSOi = QSOs:newMessage("ME", to, lines[l])
			end
			print("Msg:Setting Expected ack on "..tostring(QSOi).." to "..tostring(actualAck))
			QSOi.ack = actualAck	-- Attach the expected ack sequence to the message
			if n == 0 then
				closeConnection('APRSMsg Error:'..err);
				return 'Send Error'
			end
		end
		return nil
	else
		return "No APRS-IS Connection"
	end
end

local function formatFilter()
	local range = tonumber(config.Range) or 50
	local filter = config.Filter or "u/APWA*/APWM*/APWW*"
	if range >= 1 then
		return string.format('r/%.2f/%.2f/%i m/%i %s', myStation.lat, myStation.lon, range, range, filter)
	elseif #filter > 0 then
		return filter
	else return 'p/KJ4ERJ'	-- hopefully not too many people get this!
	end
end

local lastFilter, ackFilter

sendFilter = function (ifChanged)
	if client then
		if myStation.lat ~= 0.0 or myStation.lon ~= 0.0 then
			local filter = formatFilter()
			if filter ~= lastFilter or not ifChanged then
				ackFilter = ackFilter or 1
				--filter = filter..' g/BLT p/K/N/W'	-- Temporary hack!
				local msg = string.format('%s>APWA00,TCPIP*::SERVER   :filter %s{%s', config.StationID, filter, ackFilter)
				msg = '#filter '..filter	-- send to SERVER doesn't work on non-verified connections :(
				local n, err = client:send(msg..'\r\n')
				if type(n) ~= 'number' or n == 0 then closeConnection('sendFilter Error:'..tostring(err)) end
				ackFilter = ackFilter + 1
				if ackFilter > 9999 then ackFilter = 1 end
				print ('sendFilter:'..msg)
				filtered = true
				lastFilter = filter
			else
				--print('sendFilter:Suppressed Redundant Filter:'..filter)
			end
		end
	end
end

local function clientConnected()
	if client then
		--Get IP and Port from client
		local ip, port = client:getsockname()
		--Print the ip address and port to the terminal
		print("APRS-IS@"..ip..":"..port.." Remote: "..tostring(client:getpeername()))
		if connectedCallback then
			if debugging then
				connectedCallback(clientServer)
			else
				local status, text = pcall(connectedCallback,clientServer)
				if not status then
					scheduleNotification(0,{alert="connectedCallback:"..tostring(text)})
				end
			end
		end
	
		client:settimeout(0)	-- no timeouts for instant complete
		client:setoption('keepalive',true)
		client:setoption('tcp-nodelay',true)
		local myVersion = appVersion:gsub("(%s)", "-")

		local n, err
		local filter = formatFilter()
		local logon = string.format('user %s pass %s vers %s %s filter %s',
									config.StationID, config.PassCode,
									appName, myVersion, filter)
print(logon)
		n, err = client:send(logon..'\r\n')
print("logon sent:"..type(n)..' '..tostring(n))
		if type(n) ~= 'number' or n == 0 then
			closeConnection('sendLogon Error:'..tostring(err))
		else
			serviceWithDelay('flushClient', 10, flushClient)
			--local flushThread = MOAICoroutine.new()
			--flushThread:run(flushClient)
		end
	else
		print ('Failed to connect to the APRS-IS')
	end
end

local chkCount = 0

local function checkClientConnect(master, startTime)
	local elapsed = (MOAISim.getDeviceTime() - startTime)*1000
	print('checkClientConnect('..tostring(master)..') elapsed '..tostring(elapsed)..'ms')
	chkCount = chkCount + 1
	local text = 'Chk'..tostring(chkCount)..'@'..tostring(clientConnecting)..' '..tostring(math.floor(elapsed))..'ms'
	print(text)
	local readable, writeable, err = socket.select(nil, { master }, 0)
	if err then print('master.select('..tostring(master)..' returned '..tostring(err)) end
	if writeable and #writeable > 0 then
		print(tostring(#writeable)..' writeable sockets!  is '..tostring(master)..'=='..tostring(writeable[1])..'?')
		if writeable[1] == master then
			client = master
			text = 'good@'..tostring(clientConnecting)..' '..tostring(math.floor(elapsed))..'ms'
			clientServer = clientConnecting..' ('..tostring(client:getpeername())..')'
			clientConnecting = nil
			clientConnected()
		else
			master:close()
			clientConnecting = nil
			lwdUpdate = "Master Socket not Writeable"
			text = 'Fail1@'..tostring(ip)..':'..tostring(port)..' '..tostring(math.floor(elapsed))..'ms'
			--flushStatus.text = "APRS-IS Connect Failed in "..tostring(elapsed)..'ms'
		end
	elseif elapsed > 30*1000 then
		print('Giving up and closing '..tostring(master)..' after '..tostring(math.floor(elapsed))..'ms')
		clientConnecting = nil
		master:close()
		text = 'Fail2@'..tostring(ip)..':'..tostring(port)..' '..tostring(math.floor(elapsed/1000))..'s'
		lwdUpdate = "APRS-IS Connect Timeout"
		--flushStatus.text = "APRS-IS Connect Failed in "..tostring(elapsed)..'ms'
	else
		local delay = math.min(elapsed/10, 1000)
		serviceWithDelay('checkConnect', delay, function() checkClientConnect(master, startTime) end)
		lwdUpdate = "APRS-IS Connecting..."
	end
end

local getCount = 0
getConnection = function ()
	if config.APRSIS.Enabled then

print('getConnection:client='..tostring(client)..' connecting='..tostring(clientConnecting))

	getCount = getCount + 1
	text = 'get'..tostring(getCount)..':'..tostring(client)..' '..tostring(clientConnecting)..' '..tostring(clientServer)
	print(text)

--Connect to the client
	if not client and not clientConnecting then
		getCount = 0
		chkCount = 0
		print ('Connecting to the APRS-IS')
		if config.APRSIS.Server and config.APRSIS.Port then
			clientConnecting = config.APRSIS.Server..':'..config.APRSIS.Port
			--lastStation.text = config.StationID
			text = 'Connecting@'..tostring(clientConnecting)
			print(text)
			serviceWithDelay('connectMaster', 1, function()
				local startTime = MOAISim.getDeviceTime()
				local master = socket.tcp()	-- Get a master socket
					--client = socket.connect(config.APRSIS.Server, config.APRSIS.Port)
					master:settimeout(0)	-- No timeouts on this socket
					print ('REALLY Connecting to the APRS-IS')
				local i, err = master:connect(config.APRSIS.Server, config.APRSIS.Port)
				if i then	-- Must have accepted it
					print('connect('..tostring(master)..') initiated with '..tostring(i)..':'..tostring(err))
					serviceWithDelay('checkConnect', 10, function() checkClientConnect(master, startTime) end)
				else
					print('connect('..tostring(master)..') failed with '..tostring(err))
					if err == 'timeout' then
						serviceWithDelay('checkConnect', 10, function() checkClientConnect(master, startTime) end)
					else
						master:close()
						text = 'Fail3@'..tostring(clientConnecting)..' '..tostring(err)
						print(text)
						lwdUpdate = err
						clientConnecting = nil
					end
				end
			end	) -- timer.performWithDelay closure
			print ('Connect initiated')
		end	-- if Server and Port
	end	-- if not client

	end	-- If Enabled
end
local lastPackets = 0
local lastPrint = MOAISim.getDeviceTime()
local nextPrint = MOAISim.getDeviceTime() + 5	-- First comes 5 seconds after startup
local totalElapsed = 0
local maxElapsed, maxRecentElapsed = 0,0

local lastLat, lastLon

APRSIS.locationListener = function( lng, lat, ha, alt, va, speed, heading, fromGPS )
	function dump( lat, lon, alt, speed, heading, acc )
		alt = alt or -9997
		speed = speed or -3
		heading = heading or -3
		print ( string.format("lat:%.7f lon:%.7f alt:%.2f spd:%.1f@%.1f acc:%i", lat, lon, alt, speed, heading, acc) )
	end
	--dump( lat, lng, alt, speed, heading, ha )
	if type(speed) == 'number' and speed > 0 then
		speed = kphToKnots(speed * 3.6)	-- convert meters per second to kilometers per hour to knots
	end
	if gpstext then
		local text = string.format('%s%s',
									fromGPS and "GPS " or "",
									FormatLatLon(lat, lng, 1, 0))
		if alt and tonumber(alt) and alt ~= -9999 then
			text = text..string.format(' %im', alt)
		end
		if speed and tonumber(speed) and speed >= 0 then
			text = text..string.format(' %.1f', speed)
		end
		if heading and tonumber(heading) and heading >= 0 then
			text = text..string.format('@%i', heading)
		end
		if ha and tonumber(ha) and ha >= 0 then
			text = text..string.format(' %i', ha)
		end
		gpsUpdate = text
	end
	locationCounter = locationCounter + 1
	if config.Enables.GPS then
	
		local tWhy = (fromGPS and "gps" or "network")..'~'..math.floor(ha)
		addCrumb(lat, lng, alt, tWhy)

		if fromGPS or config.Enables.AllowNetworkFix then
			moveME(lat, lng, alt, heading, speed, ha)
		else
			if lastLat and lastLon then
				local fromPoint = LatLon.new(lastLat, lastLon)
				local toPoint = LatLon.new(lat, lng)
				local deltaDistance = kmToMiles(fromPoint.distanceTo(toPoint))
				local deltaBearing = fromPoint.bearingTo(toPoint)
				local text = string.format('Moved %ift@%i', deltaDistance*5280, deltaBearing)
				local timeout = nil
				if deltaDistance < 15 then timeout = 1000 end
				toast.new("Ignoring Network Acc:"..tostring(ha)..'\r\n'..text, timeout)
			end
		end
		lastLat, lastLon = lat, lng
	end
end

local function runAPRSIS()
		local start = MOAISim.getDeviceTime()
		local which = runServiceTimers()
		local elapsed = (MOAISim.getDeviceTime() - start) * 1000
		totalElapsed = totalElapsed + elapsed
		if elapsed > maxElapsed then maxElapsed = elapsed end
		if elapsed > maxRecentElapsed then maxRecentElapsed = elapsed end
		if elapsed > 10 and false then
			print(string.format('runServiceTimers took %.2fms busy %.2f%% doing %s',
							elapsed,
							totalElapsed * 100 / ((MOAISim.getDeviceTime()-lastPrint)*1000),
							tostring(which)))
		end
		if start > nextPrint then
			local timers = ''
			for k,v in pairs(serviceTimers) do timers=timers..k..' ' end
			local percentBusy = totalElapsed * 100 / ((MOAISim.getDeviceTime()-lastPrint)*1000)
			local text = string.format('%s:Serviced %i Packets\r\n%.1f%% busy max %.1fms\r\nmax ever %.1fms',
							os.date("%H:%M:%S"),
							packetCount-lastPackets,
							percentBusy, maxRecentElapsed, maxElapsed)
			print(text)
if simRunning and ((packetCount-lastPackets) < 2 or percentBusy > 2) then toast.new(text, 2000) end
			maxRecentElapsed = 0
			totalElapsed = 0
			if client then print(string.format('client:%s to:%s', tostring(client), tostring(clientServer))) end
			if clientConnecting then print(string.format('connectingTo:%s',tostring(clientConnecting))) end
			if timers == '' then timers = '*NONE*' end
			print(string.format('ServiceTimers:%s', timers))
			lastPackets = packetCount
			lastPrint = MOAISim.getDeviceTime()
			nextPrint = lastPrint + 30	-- Repeat every 30 seconds
		end
end


function APRSIS:start(configuration)
	if type(configuration) == 'table' and type(configuration.APRSIS) == 'table' then
		config = configuration

if type(MOAISim.setServiceCallback) == 'function' then
	MOAISim:setServiceCallback(runAPRSIS)
else
  local timer = MOAITimer.new()
  timer:setSpan(1/60)
  timer:setMode(MOAITimer.LOOP)
  timer:setListener(MOAITimer.CONTINUE, runAPRSIS)
  timer:start()
end

serviceWithDelay('bootstrap', 1000, timedConnection)	--jump start the whole thing!

else
	print('APRSIS:start() requires table configuration with .APRSIS table inside!, got '..type(configuration)..' and '..type(configuration.APRSIS))
end

end

--[[
local function printableTable(w, t, s)
	s = s or ' '
	local r = 'Table['..w..'] ='
	if t then
		for k,v in pairs(t) do
			if type(v) == 'number' then v = string.format('%.3f', v) end
			r = r..s..tostring(k)..'='..tostring(v)
		end
	else	r = r..' NIL!'
	end
	return r
end

ip, resolved = socket.dns.toip('noam.aprs2.net')
print(printableTable(ip, resolved, '\r\n'))
print(printableTable('alias', resolved.alias, '\r\n'))
print(printableTable('ip', resolved.ip, '\r\n'))
]]

return APRSIS
