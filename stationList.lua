local debugging = false

local M = { VERSION = "0.0.1" }

local toast = require("toast");
local APRS = require("APRS")
local colors = require("colors");
local symbols = require("symbols");
local LatLon = require("latlon")
local QSOs = require("QSOs")

local times
local function initTime()
	times = {}
end

local function addTime(what, elapsed)
	if times then
		times[#times+1] = what
		times[what] = elapsed
	else print("addTime:times = NIL!")
	end
end

local function sayTime(src)
	if times then
		local report = ''
		for i, k in ipairs(times) do
			if report ~= '' then
				if i == #times then
					report=report..' = '
				else report=report..' '
				end
			end
			report = report..string.format('%s:%.2f', k, times[k]*1000)
		end
		print(src..':'..report)
		times = nil
	end
end

local osmTiles	-- Will populate itself after simRunning

--	Forward references for callbacks
--local getSymbolImage	-- Needs to be global for redDot
local addCenterTapCallback

-- Symbol was /. for red x /$ for phone /F for tractor
myStation = { stationID="ME", lat=27.996683, lon=-80.659083,
					symbol='/$', packetsHeard=0, firstHeard='', lastHeard=''}

local centerStation, wasCenter = myStation, nil

stationInfo = {}
stationCount = 0
packetCount = 0

UniqueSymbols = {}
UniqueSymbolCount = 0

local function showTrack(track, dots, why)
	if osmTiles then
		performWithDelay(1,function()
						osmTiles:showTrack(track, dots, why)
					end)
	else print('stationList:showTrack:osmTiles='..tostring(osmTiles))
	end
end

local function removeTrack(track)
	if osmTiles then
		performWithDelay(1,function()
						osmTiles:removeTrack(track)
					end)
	else print('stationList:removeTrack:osmTiles='..tostring(osmTiles))
	end
end

function M:setupME(mapTiles)
	mapTiles = mapTiles or osmTiles	-- For re-starting ME
	osmTiles = mapTiles	-- This gets the whole map thing going!
	print("stationList:setupME("..tostring(mapTiles)..")")
	if myStation.symbolLabel then osmTiles:removeSymbol(myStation.symbolLabel) end
	print("stationList:setupME:getSymbolLabel")
	myStation.symbolLabel = getSymbolLabel(myStation.symbol, myStation.stationID)
	print("stationList:setupME:showSymbol:"..tostring(myStation.symbolLabel))
	osmTiles:showSymbol(myStation.lat, myStation.lon, myStation.symbolLabel, myStation.stationID)
	addCenterTapCallback(myStation)
	print("stationList:setupME:Done")
end

if Application:isDesktop() then
	local delay = 5*60*1000	-- 5 minutes as milliseconds (performWithDelay use)
	local retain = 15*60	-- 15 minutes as seconds (for os.time()/station.tracks[].when use)
	local lastAfter = nil	-- for delta _sys_* calculations
	performWithDelay(delay, function()
							if stationCount > 1000 then	-- Don't bother for low station counts
								local oldest = os.time() - retain
								print("stationList:Purging...")
								local start = MOAISim.getDeviceTime()
								print("stationList:Purging tracks before "..os.date("%H:%M:%S", oldest))
								local removed, from = 0, 0
								for c,station in pairs(stationInfo) do
									if station ~= centerStation then
										if station.tracks and #station.tracks > 2 then
											from = from + 1
											local points = 0
											while #station.tracks > 2 and station.tracks[1].when < oldest do
												points = points + 1
												table.remove(station.tracks, 1)
											end
											if points > 0 then
												removed = removed + points
												osmTiles:showTrack(station.tracks, (centerStation == station), station.stationID)
											end
											--if removed > 0 then
												--print("stationList:"..station.stationID.." purged "..removed.." tracks leaving "..#station.tracks)
											--end
										end
									end
								end
								local before = MOAISim:getMemoryUsage()
								local start2 = MOAISim.getDeviceTime()
								MOAISim:forceGarbageCollection()	-- This does it iteratively!
								local now = MOAISim.getDeviceTime()
								local after = MOAISim:getMemoryUsage()
								text = os.date("%H:%M:%S")..":Purging tracks for "..stationCount.." stations took "..math.floor((now-start)*1000).."ms "..removed.." from "..from.." stations"
								text = text.."\r\nGarbageCollection:"..math.floor((now-start2)*1000).."ms"
								text = text.." Reduced:"..math.floor((before.total-after.total)/1024/1024).."MB"
								if type(after._sys_vs) == 'number' and type(after._sys_rss) == 'number' then
									text = text.."\r\nWork/Page:"..math.floor(after._sys_rss/1024/1024).."/"..math.floor(after._sys_vs/1024/1024).."MB"
									if lastAfter then
										text = text.." Delta:"..math.floor((after._sys_rss-lastAfter._sys_rss)/1024/1024).."/"..math.floor((after._sys_vs-lastAfter._sys_vs)/1024/1024).."MB"
									end
									lastAfter = after
								end
								print("stationList:"..text)
								toast.new(text, removed>0 and math.floor(delay*0.95) or 10000)
							end
						end, 0)	-- Do it forever
end

function M:clearStation(station, retain)
	if station.polygon then osmTiles:removePolygon(station.polygon) end
	if station.tracks then osmTiles:removeTrack(station.tracks) end
	if station.symbolLabel then osmTiles:removeSymbol(station.symbolLabel)
	else print("clearing symbol-less station:"..station.stationID.." last packet:"..station.lastPacket.original)
	end
	if not retain then stationInfo[station.stationID] = nil end
end

function M:clearStations()
	for c,station in pairs(stationInfo) do
		M:clearStation(station, true)		-- Retain in stationInfo[] and clear all at once
	end
	toast.new(stationCount..' Stations Cleared', 1000)
	stationInfo = {}
	stationCount = 0
	packetCount = 0
	if myStation.tracks then osmTiles:removeTrack(myStation.tracks) end
	myStation.tracks = nil
	if myStation.crumbsLong then osmTiles:removeTrack(myStation.crumbsLong) end
	myStation.crumbsLong = nil
	-- if myStation.symbolLabel then osmTiles:removeSymbol(myStation.symbolLabel) end
	--myStation.symbolLabel = nil
	UniqueSymbols = {}
	UniqueSymbolCount = 0
end

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

	local appName = MOAIEnvironment.appDisplayName
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
				file:write(os.date("!<time>%Y-%m-%dT%H:%M:%SZ</time><name>%H:%M:%S "..tostring(track[t].label).."</name></trkpt>\n", track[t].when))
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

function FormatCoordinate(Coord, degDigits, addDigits, daoDigits, NSEW)
	local dir = NSEW:sub(1,1)
	if Coord < 0 then Coord = -Coord; dir = NSEW:sub(2,2) end
	local fCoord, pCoord = math.modf(Coord)
	local formatString = string.format('%%0%ii %%%i.%if%%s', degDigits, 5+addDigits+daoDigits, 2+addDigits+daoDigits)
	return string.format(formatString, fCoord, pCoord*60.0, dir)
end

function FormatLatLon(Lat, Lon, addDigits, daoDigits)
	return FormatCoordinate(Lat, 2, addDigits, daoDigits, 'NS')..' '..FormatCoordinate(Lon, 3, addDigits, daoDigits, 'EW')
end

function AreCoordinatesEquivalent(Lat1, Lon1, Lat2, Lon2, daoDigits)
	if Lat1 == Lat2 and Lon1 == Lon2 then return true end	-- Cheap check!
	local One = FormatLatLon(Lat1, Lon1, 0, daoDigits)
	local Two = FormatLatLon(Lat2, Lon2, 0, daoDigits)
	--print('AreCoordinatesEquivalent', One, Two)
	return One == Two
end

function M:getCenterStation()
	return centerStation or myStation
end

function M:updateCenterStation(station)
	if station and station ~= centerStation then
		centerStation = station
		print('updateCenterStation:whoButton='..tostring(whoButton))
		if whoButton then whoButton:setText(station.stationID) end
	end

--print('updateCenterStation('..centerStation.stationID..') moveTo '..centerStation.lat..' '..centerStation.lon)

	if osmTiles then
		if debugging then
			osmTiles:moveTo(centerStation.lat, centerStation.lon)
		else
			local status, text = pcall(osmTiles.moveTo, osmTiles, centerStation.lat, centerStation.lon)
			if not status then print ('osmTiles:moveTo failed with '..text) end
		end
		--centerStation.symbolLabel.xScale, centerStation.symbolLabel.yScale = 1.0, 1.0
		--centerStation.symbolLabel.alpha = 1.0
		osmTiles:showSymbol(centerStation.lat, centerStation.lon, centerStation.symbolLabel, centerStation.stationID)
		if centerStation ~= myStation then	-- my station shows tracks (true) in sendPosit
			osmTiles:showTrack(centerStation.tracks, true, centerStation.stationID)
		end
		if wasCenter and wasCenter ~= centerStation and wasCenter ~= myStation then
			--print(wasCenter.stationID..' dots removed')
			osmTiles:showTrack(wasCenter.tracks, false, wasCenter.stationID)
		end
		wasCenter = centerStation
	end

--[[
	if centerStation.owner then
		stationGroup.stationID.text = centerStation.stationID..' de '..centerStation.owner
		stationGroup.stationID:setTextColor( 255,64,64 )
	else
		stationGroup.stationID.text = centerStation.stationID..' '..centerStation.symbol
		stationGroup.stationID:setTextColor( 128,128,128 )
	end
	stationGroup.packetCount.text = string.format("Pkts: %i", centerStation.packetsHeard)
	if centerStation.moveCount then 
		stationGroup.packetCount.text = stationGroup.packetCount.text..' M:'..tostring(centerStation.moveCount)
	end
	if centerStation.speed and centerStation.course then
		stationGroup.packetCount.text = stationGroup.packetCount.text..string.format(' %.2fmph@%i', knotsToMph(centerStation.speed), centerStation.course)
	end
	if centerStation.lastPacket then
		if centerStation.lastPacket.platform then
			stationGroup.packetCount.text = stationGroup.packetCount.text..' ('..centerStation.lastPacket.platform..')'
		else
			stationGroup.packetCount.text = stationGroup.packetCount.text..' ('..centerStation.lastPacket.dst..')'
		end
	end
	--stationGroup.firstHeard.text = centerStation.firstHeard
	--stationGroup.lastHeard.text = centerStation.lastHeard
	stationGroup.firstHeard.text = APRS:Coordinate(centerStation.lat, centerStation.lon)
	stationGroup.lastHeard.text = (centerStation.lastPacket and centerStation.lastPacket.comment) or '' --centerStation.lastHeard
	if centerStation.statusReport then
		if stationGroup.lastHeard.text ~= '' then
			stationGroup.lastHeard.text = stationGroup.lastHeard.text..'\r\n'
		end
		stationGroup.lastHeard.text = stationGroup.lastHeard.text..centerStation.statusReport
	end
	stationGroup.alpha = 1
	if stationTransition then transition.cancel(stationTransition) end
	stationTransition = transition.to( stationGroup, { alpha = 0, time=5000, transition=easing.inQuad, onComplete = function() stationTransition = nil end } )
]]
	if centerStation ~= myStation and config.Enables.SaveCenterTrack then
		SaveTrackToGPX(centerStation.stationID, centerStation.tracks)
	end
end

local function makeCenterTapCallback(station)
	return function (e)
			if e.isTap and e.y > 40 then	-- 40 avoids the title bar taps
				print('CenterTap:'..e.type..' isTap:'..tostring(e.isTap)..' on '..station.stationID)
				--Vibrate(config.Vibrate.onTapStation)
				if centerStation == myStation then
					myStation.gotLocation = true
				end
				M:updateCenterStation(station)
				e.stoped = true	-- Don't pass this one on
				return true
			else print('CenterTap Ignoring:'..e.type..' isTap:'..tostring(e.isTap)..' on '..station.stationID..' e.y:'..tostring(e.y))
			end
		end
end

addCenterTapCallback = function (station)
	station.symbolLabel.symbol:addEventListener( "touchUp", makeCenterTapCallback(station) )
end

function moveME--[[Really]](newLat, newLon, newAlt, newCourse, newSpeed, newAcc)
	myStation.gotLocation = true
	myStation.acc = newAcc
	if newAlt then
		if newAlt > 0 then
			myStation.alt = newAlt
		else
			myStation.alt = nil
		end
	end
	if newCourse then
		if newCourse >= 0 then
			myStation.course = newCourse
		else
			myStation.course = nil
		end
	end
	if newSpeed then
		if newSpeed >= 0 then
			myStation.speed = newSpeed
		else
			myStation.speed = nil
		end
	end
	if newLat ~= myStation.lat or newLon ~= myStation.lon then
if not AreCoordinatesEquivalent(myStation.lat, myStation.lon, newLat, newLon, 0) then
	local fromText = FormatLatLon(myStation.lat, myStation.lon, 0, 2)
	local toText = FormatLatLon(newLat, newLon, 0, 2)
	local fromPoint = LatLon.new(myStation.lat, myStation.lon)
	local toPoint = LatLon.new(newLat, newLon)
	local deltaDistance = kmToMiles(fromPoint.distanceTo(toPoint))
	local deltaBearing = fromPoint.bearingTo(toPoint)
	print(string.format('moveME from(%s) to(%s) or %ift@%i minutes(%.5f %.5f) Acc:%s',
						fromText, toText, deltaDistance*5280, deltaBearing,
						(newLat-myStation.lat)*60, (newLon-myStation.lon)*60,
						tostring(myStation.acc)))
end
		myStation.lat, myStation.lon = newLat, newLon
		config.lastLat, config.lastLon = newLat, newLon
		--sendFilter(true)

		if myStation.tracks and #myStation.tracks > 0 then
			local tp = myStation.tracks[#myStation.tracks]	-- last track point
			if myStation.lat ~= tp.lat or myStation.lon ~= tp.lon then	-- We've moved
				if not myStation.trkseg then
					myStation.trkseg = {}
					myStation.trkseg.color = myStation.tracks.color
					myStation.trkseg[1] = { lat=tp.lat, lon=tp.lon, when = os.time() }
				end
				myStation.trkseg[2] = { lat=myStation.lat, lon=myStation.lon, when = os.time() }
				showTrack(myStation.trkseg, true, "ME-trkseg")
			elseif myStation.trkseg then	-- If we have a lurking segment, get rid of it!
				removeTrack(myStation.trkseg)
				myStation.trkseg = nil
			end
		end
	end
	if centerStation == myStation then
		M:updateCenterStation()
	end
end


--function M:setTiledSheets(tileWidth, tileHeight, tileX, tileY, spacing, margin)
--local imageSheet = SpriteSheet { texture="APRS1.png" }
--imageSheeet:setTiledSheets(19, 19, 16, 6, 0, 1)	-- 0 spacing may need tweaking!
--local imageSheet2 = SpriteSheet { "APRS2.png" }
--imageSheeet2:setTiledSheets(19, 19, 16, 6, 0, 1)	-- 0 spacing may need tweaking!
--local imageSheet3 = graphics.newImageSheet( "GPXSym3.png", sheetOptions )
--local imageSheet4 = graphics.newImageSheet( "GPXSym4.png", sheetOptions )

local imageSheet1 = MOAIImage.new()
imageSheet1:load("APRS1.png", MOAIImage.PREMULTIPLY_ALPHA)
local imageSheet2 = MOAIImage.new()
imageSheet2:load("APRS2.png", MOAIImage.PREMULTIPLY_ALPHA)

local hasDrawLine = nil


getSymbolImage = function(symbol, stationID)
--print('getSymbolImage('..symbol..') for:'..stationID..' name:'..symbols:getSymbolName(symbol))
	local start = MOAISim.getDeviceTime()
	local image
	
	if not UniqueSymbols[symbol] then
	
	local shriek = '!'
	local sym, tab = APRS:SymTab(symbol)
	local symIndex = sym:byte(1)-shriek:byte(1)	-- zero relative
	if symIndex < 0 or symIndex >= 96 then
		--print(string.format("Invalid Symbol Index %i (ascii:%i - %i) from (%s) from %s, using ?",
		--					symIndex, sym:byte(1), shriek:byte(1), symbol, stationID))
		sym, tab = APRS:SymTab("\\?")
		symIndex = sym:byte(1)-shriek:byte(1)
	end

	local scale = 1
	--if Application:isMobile() then scale = 1.5 end

	local sheet = imageSheet1
	if tab ~= '/' then sheet = imageSheet2 end	-- Must be alternate or overlayed
	image = MOAIImage.new()
	local targetSize = math.floor(MOAIEnvironment.screenDpi / 4 / scale)	-- 1/4" touch target
	if (targetSize % 2) == 1 then targetSize = targetSize + 1 end	-- Round up to an even number
	if targetSize < 18 then targetSize = 18 end
	targetSize = 36	-- 2*18 to avoid scaling on the /2 below
	targetSize = 32	-- Make it a power of 2
	image:init(targetSize,targetSize,sheet:getFormat())
--[[
	if hasDrawLine == nil then
		hasDrawLine = (type(image.drawLine) == "function")
	end
	if hasDrawLine then
		image:drawLine(0,0,targetSize-1,0, 0.5,0,0,0.5)	-- top
		--image:drawLine(targetSize-1,0,targetSize-1,targetSize-1, 0,0,0,1)	-- right
		image:drawLine(targetSize-1,targetSize-1,0,targetSize-1, 0,0,0.5,0.5)	-- bottom
		image:drawLine(0,targetSize-1,0,0, 0,0.5,0,0.5)	-- left
	end
]]
	local r,c = math.floor(symIndex/16), symIndex % 16	-- 16 symbols per row
	--image:copyBits(sheet, 2+c*(18+3), 2+r*(18+3), 0,0, 18,18)
	local symbolSize = math.floor(MOAIEnvironment.screenDpi / 8 / scale)	-- 1/8" symbols
	if (symbolSize % 2) == 1 then symbolSize = symbolSize + 1 end	-- Round up to an even number
	if symbolSize < 18 then symbolSize = 18 end
	symbolSize = targetSize/2	-- copyRect doesn't scale nicely
	symbolSize = 18	-- This is the original bitmap size
	local dest = (targetSize-symbolSize) / 2
	image:copyRect(sheet, 2+c*(18+3), 2+r*(18+3), 2+c*(18+3)+17, 2+r*(18+3)+17,
					dest,dest, dest+symbolSize-1,dest+symbolSize-1)

	if tab ~= '/' and tab ~= '\\' then
		local start = MOAISim.getDeviceTime()
		if symbols:IsValidOverlay(tab) then	-- do an overlay!
			if type(FontManager.getRecentFont) == 'function' then
				local font = FontManager:getRecentFont()
				local fontImage, xBearing, yBearing = font:getGlyphImage(tab, math.floor(symbolSize*0.45))
				local w, h = fontImage:getSize()
				local xMax, yMax = 0, 0
				for y=0, h-1 do
					for x=0, w-1 do
						local c = fontImage:getColor32(x,y)
						if c ~= 0 then
							if x > xMax then xMax = x end
							if y > yMax then yMax = y end
						end
					end
				end
				local xoff, yoff = (symbolSize-xMax)/2, (symbolSize-yMax)/2
				image:fillRect(dest+xoff-1, dest+yoff-1, dest+xoff+xMax+2, dest+yoff+yMax+2, 1, 1, 1, 1)
				for y=0, yMax do
					for x=0, xMax do
						local r,g,b,a = fontImage:getRGBA(x,y)
						if a ~= 0 then
							local c = 1.0 - a	-- 1.0 is BLACK
							image:setRGBA(dest+xoff+x, dest+yoff+y, c, c, c, 1.0)
						end
					end
				end
			else
				print(stationID.." has overlay("..tab..") NOT displaying (no FontManger:getRecentFont)")
			end
		else
			local text = stationID..' has invalid overlay('..tab..') ASCII:'..tab:byte(1,-1)
			print(text)
			--toast.new(text)
		end
		addTime("Overlay", MOAISim.getDeviceTime()-start)
	end
		UniqueSymbolCount = UniqueSymbolCount + 1
--print("getSymbolImage:newUnique["..UniqueSymbolCount.."]("..symbol..")")
		UniqueSymbols[symbol] = image
		image.symbolSize = symbolSize
		image.targetSize = targetSize
	else
		image = UniqueSymbols[symbol]
	end
					
	local symbolImage = Sprite{texture=image}
	symbolImage.width, symbolImage.height = image.symbolSize, image.symbolSize	-- Use these for sizing
--print('symbol is '..image.symbolSize..' within target '..image.targetSize)

	scale = MOAIEnvironment.screenDpi / 4 / image.targetSize
	symbolImage.scale = scale

	if scale ~= 1 then symbolImage:setScl(scale,scale,scale) end
	symbolImage:setLoc(0,0)
	symbolImage:setPriority(2000000)
--print(stationID..' symbol('..symbol..') scale('..scale..') is '..symbolImage:getWidth()..'x'..symbolImage:getHeight())
	
	local symbolGroup = symbolImage	-- Keep it simpler for now

	--symbolGroup = Group()
	--symbolGroup:addChild(symbolImage)	--  Overlays need a group (turns out, they all do to stay same size)
	symbolGroup.width, symbolGroup.height, symbolGroup.scale = symbolImage.width, symbolImage.height, symbolImage.scale

	addTime("Image", MOAISim.getDeviceTime()-start)
--[[
	if tab ~= '/' and tab ~= '\\' then
		local start = MOAISim.getDeviceTime()
		if symbols:IsValidOverlay(tab) then	-- do an overlay!
		
			for x=-1,1,2 do
			for y=-1,1,2 do
			local overlay3 = TextLabel { text=tab }
			overlay3:setTextSize(math.min(symbolImage.width,symbolImage.height)*0.7*scale)
			overlay3:fitSize()
			overlay3:setPriority(2000002)
			overlay3:setColor(1,1,1,1)	-- black out the background
			overlay3:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
			--overlay3:setLeft(-overlay3:getWidth()/2+x)
			--overlay3:setTop(-overlay3:getHeight() / 2+y)
			overlay3:setLoc(x,y)
			symbolGroup:addChild(overlay3)
			end
			end

			local overlay3 = TextLabel { text=tab }
			overlay3:setTextSize(math.min(symbolImage.width,symbolImage.height)*0.7*scale)
			overlay3:fitSize()
			overlay3:setPriority(2000003)
			overlay3:setColor(0,0,0,1)	-- with a white letter inside
			overlay3:setAlignment ( MOAITextBox.CENTER_JUSTIFY )
			--overlay3:setLeft(-overlay3:getWidth()/2)
			--overlay3:setTop(-overlay3:getHeight() / 2)
			overlay3:setLoc(0,0)
			--overlay3:setHighlight(1,1,1,1,1)
			symbolGroup:addChild(overlay3)
		else
			local text = stationID..' has invalid overlay('..tab..') ASCII:'..tab:byte(1,-1)
			print(text)
			--toast.new(text)
		end
		addTime("Overlay", MOAISim.getDeviceTime()-start)
	end
]]
	
--	stationGroup:resizeForChildren()
--	if shouldIShowIt(stationID) then print("stationList:getSymbolImage:"..stationID.." Symbol("..symbol..") size "..symbolGroup:getWidth().."x"..symbolGroup:getHeight()) end
--print("getSymbolImage:returning "..tostring(symbolGroup))
	return symbolGroup
end

getSymbolLabel = function(symbol, stationID)
--print('getSymbolLabel('..symbol..') for:'..stationID..' name:'..symbols:getSymbolName(symbol))
	local start = MOAISim.getDeviceTime()
	
	local symbolLabel = {}
	
	symbolLabel.symbol = getSymbolImage(symbol, stationID)
	
	if stationID and #stationID then	-- Some symbols aren't labeled
	--if shouldIShowIt(stationID) then
		local start = MOAISim.getDeviceTime()
		local label = TextLabel { text=stationID, align = {"left", "center"}, }
--print("getSymbolLabel("..symbol..") for "..stationID.." labelling3...size:"..tostring(symbolLabel.symbol.width)..'x'..tostring(symbolLabel.symbol.height).." scale:"..tostring(symbolLabel.symbol.scale))
		label.orgTextSize = math.ceil(math.min(symbolLabel.symbol.width,symbolLabel.symbol.height)*0.7*symbolLabel.symbol.scale)
		label:setTextSize(label.orgTextSize)
		label:fitSize()
		label:setPriority(1999999)
		label:setColor(0,0,0,1.0)
		--label:setLeft(symbolLabel.symbol:getWidth() / 2 * symbolLabel.symbol.scale)
		--label:setTop(-symbolLabel.symbol:getHeight() / 2 * symbolLabel.symbol.scale)
		label.xOffset = label:getWidth()/2 + symbolLabel.symbol.width / 2 * symbolLabel.symbol.scale
--		local xMin, yMin, xMax, yMax = label:getStringBounds(1,#stationID)
--print(stationID..' '..label.orgTextSize..'pts height '..label:getHeight()..' xoffset '..label.xOffset..' bounds:'..xMin..','..yMin..'->'..xMax..','..yMax..' or '..(xMax-xMin)..'x'..(yMax-yMin))
		symbolLabel.label = label	-- showSymbol handles this!
		addTime("Label", MOAISim.getDeviceTime()-start)
	--end
	end
--	stationGroup:resizeForChildren()
--	if shouldIShowIt(stationID) then print("stationList:getSymbolImage:"..stationID.." Symbol("..symbol..") size "..symbolGroup:getWidth().."x"..symbolGroup:getHeight()) end
--print("getSymbolLabel:returning "..tostring(symbolLabel))
	return symbolLabel
end

--[[local function rotateSymbol()
	stationGroup.rotateSymbol.rotation = stationGroup.rotateSymbol.rotation + 5
end]]

local centerActive, centerToast

local parsed, located = 0, 0
local msgCount = os.time()	-- Counter for messages received and sent to Android

local lastTitleText = nil
local function refreshTitleText()
	if titleText then
		local start = MOAISim.getDeviceTime()
		local x,y = titleText:getLoc()
		local text = config.StationID..'('..stationCount..')('..UniqueSymbolCount..')'
		if osmTiles and Application.viewWidth > Application.viewHeight then	-- Wider screens get more info
			local sc, lc, tc, pc = osmTiles:getGroupCounts()
			text = text.." Grp:S:"..tostring(sc).." L:"..tostring(lc).." T:"..tostring(tc).." P:"..tostring(pc)
		end
		if text ~= lastTitleText then
			--print('Changing titleText from '..tostring(lastTitleText)..' to '..tostring(text))
			lastTitleText = text
			titleText:setString ( text )
			titleText:fitSize()
			titleText:setLoc(x,25*config.Screen.scale)
			addTime("titleText", MOAISim.getDeviceTime()-start)
		--else print('NOT changing titleText from '..tostring(lastTitleText))
		end
	--else	print('titleText:'..tostring(titleText)..' for stationCount:'..stationCount)
	end
end

local lastZoom = -1
performWithDelay(1000, function()
	if osmTiles then
		local zoom = osmTiles:getZoom()
		if zoom ~= lastZoom then
			--print("Refreshing titleText:zoom from "..tostring(lastZoom).." to "..tostring(zoom))
			refreshTitleText()
			lastZoom = zoom
		end
	else print("Not refreshing titleText, osmTiles="..tostring(osmTiles))
	end
end, 0)
performWithDelay(10000, function () --[[print("Refreshing titleText:timer")]] refreshTitleText() end, 0)

function M.packetReceived(line, clientServer, APRSIS)
	local start = MOAISim.getDeviceTime()
	initTime()
--print('Received:'..tostring(line))
	if type(line) ~= 'string' then print('packetReceived() must be string, not '..type(line)) return end
	local packetInfo = APRS:Parse(line)
	addTime("Parse["..(packetInfo and packetInfo.packetType or "?").."]", MOAISim.getDeviceTime()-start)
	if packetInfo then
		local newStation = false
		local newOwner = false
		local stationID = packetInfo.src
		if packetInfo.obj then stationID = packetInfo.obj end
		parsed = parsed + 1
		packetInfo.when = os.time()
		if packetInfo.error then
			--print('Parse('..packetInfo.src..') Error('..packetInfo.error..') Packet:'..packetInfo.payload)
		end
		if not stationInfo[stationID] then
			local start = MOAISim.getDeviceTime()
			newStation = true
			stationCount = stationCount + 1
	--print ("New station: "..packetInfo.src.." count:"..stationCount)
			stationInfo[stationID] = {}
			stationInfo[stationID].stationID = stationID
			stationInfo[stationID].firstHeard = os.date()
			refreshTitleText()
			addTime("newStation", MOAISim.getDeviceTime()-start)
		end
		local station = stationInfo[stationID]
		if packetInfo.obj then
			if station.owner then
				if station.owner ~= packetInfo.src then
					--print('Object('..stationID..') formerly owned by '..station.owner..' is now owned by '..packetInfo.src)
					newOwner = "from "..station.owner.." to "..packetInfo.src
					station.owner = packetInfo.src
				end
			else
				if not newStation then
					--print('Former Station('..stationID..') is now Object owned by '..packetInfo.src)
					newOwner = "from station to "..packetInfo.src
				end
				if packetInfo.src ~= packetInfo.obj then	-- Objects that own themselves are called stations!
					station.owner = packetInfo.src
				end
			end
		elseif station.owner then
			if packetInfo.lat and packetInfo.lon then	-- Only redefine as station for posits
				--print('Object('..stationID..') formerly owned by '..station.owner..' is now a REAL station!')
				newOwner = "from "..station.owner.." to station"
				station.owner = nil
			else	print("NOT Redefining "..station.owner..":"..stationID.." for non-posit["..packetInfo.packetType.."]")
			end
		end
		if packetInfo.statusReport then station.statusReport = packetInfo.statusReport end
		if packetInfo.lat and packetInfo.lon and packetInfo.symbol then
		if packetInfo.lat == 0 and packetInfo.lon == 0 then
			print("stationList:packetReceived:"..stationID..":ZERO lat/lon="..packetInfo.lat.."/"..packetInfo.lon.." from "..line)
		else
		if not osmTiles:validLatLon(packetInfo.lat, packetInfo.lon) then
			print("stationList:packetReceived:"..stationID..":INVALID lat/lon="..packetInfo.lat.."/"..packetInfo.lon.." from "..line)
		else
			local start = MOAISim.getDeviceTime()
			local duplicate = false
			local newsymbol = false
			local badMove = "Huh?"
			local moved = false
			located = located + 1
	local DidWhat = "Did NOTHING!"
			if not station.firstPosit then
				badMove = nil
				moved = true
				station.firstPosit = packetInfo
	DidWhat = "firstPosit"
			elseif station.lat and station.lon and (station.lat ~= packetInfo.lat or station.lon ~= packetInfo.lon) then
				badMove = nil
				moved = true
				local start = MOAISim.getDeviceTime()
				local checked = 0
				local now = os.time()
				local oldest = now - (5*60)	-- only look back 5 minutes
				if not station.tracks then
					station.tracks = {}
					station.tracks[1] = station.firstPosit
				end
				if packetInfo.dst and packetInfo.payload then
					local myTracks = station.tracks
					for t = #myTracks, 1, -1 do
						if myTracks[t].when < oldest then
							--print(station.stationID..' dupe check exit at '..(now-myTracks[t].when)..'ms')
							break
						end
						checked = checked + 1
						if myTracks[t].dst == packetInfo.dst
						and myTracks[t].payload == packetInfo.payload then
							print(station.stationID..' DUPLICATE '..packetInfo.packetType..' from '..(now-myTracks[t].when)..'sec ago')
							print(station.stationID..' DUPLICATE via '..packetInfo.path..' was '..myTracks[t].path)
							print(station.stationID..' DUPLICATE >'..myTracks[t].dst..':'..myTracks[t].payload)
							duplicate = true
	badMove = string.format("Duplicate[%i]:%isec",#myTracks-t, (os.time()-myTracks[t].when))
	DidWhat = badMove
							break
						end
					end
				end
				if duplicate then
					addTime("Duplicate["..checked.."/"..#station.tracks.."]", MOAISim.getDeviceTime()-start)
				else addTime("DupeCheck["..checked.."]", MOAISim.getDeviceTime()-start)
				end

				if not duplicate then
					local trackp = station.tracks[#station.tracks]
					local deltaSec = packetInfo.when - trackp.when
					if deltaSec < 5 then
						badMove = string.format("Too Quick:%isec", deltaSec)
						DidWhat = "delta:"..deltaSec.."sec"
						print("stationList:packetReceived:"..stationID.." too quick in "..deltaSec.."sec")
					else
						local fromPoint = LatLon.new(trackp.lat, trackp.lon)
						local toPoint = LatLon.new(packetInfo.lat, packetInfo.lon)
						local deltaDistance = kmToMiles(fromPoint.distanceTo(toPoint))
						local bearing = fromPoint.bearingTo(toPoint)
						if deltaDistance > 0.1 then	-- Ignore small motions, they can be FAST!
							local speed = deltaDistance / (deltaSec/60.0/60.0);
-- print("stationList:packetReceived:"..stationID.." moved "..deltaDistance.."mi in "..deltaSec.."sec or "..speed.."mph")
							if speed > 500
							and packetInfo.symbol ~= "\\S"	-- Satellites can exceed speed limit
							and (not station.speedAverage or speed > station.speedAverage*2) then
								badMove = string.format("Too Fast:Moved %.2fmi in %isec or %.0fmph", deltaDistance, deltaSec, speed)
								DidWhat = "speed:"..speed.."mph"
-- toast.new("stationList:packetReceived:"..stationID.." moved "..deltaDistance.."mi in "..deltaSec.."sec or "..speed.."mph (Avg:"..tostring(station.speedAverage)..")")
							end
							if (speed > 20000) then speed = 20000 end	-- Cap the speed we're accumulating (Satellites are about 15,000)
							if not station.speedAverage then station.speedAverage = 0
							else station.speedAverage = station.speedAverage - station.speedAverage / 4; end
							station.speedAverage = station.speedAverage + speed / 4;	-- Ramp it up slowly
							station.speedCalculated = speed;
							station.courseCalculated = bearing;
						end
					end
					if badMove then
						if station.tracks and (#station.tracks==1 or newOwner) then
--toast.new("Cleared "..#station.tracks..(#station.tracks==1 and " track for " or " tracks for ")..stationID.." "..tostring(newOwner and "("..newOwner..")" or "").."\r\n"..tostring(badMove), (#station.tracks==1 and 5000 or nil))
							removeTrack(station.tracks)	-- use the time-delay version
							station.tracks = nil
							station.firstPosit = packetInfo	-- Reset this as new to start over next posit
						end
						if newOwner then station.speedAverage = nil end	-- Start the average over
					end
--[[
			{	double distance, bearing;
				__int64 msDelta = msNow - Station->Last.msec;

				AprsHaversineLatLon(Station->Last.lat, Station->Last.lon,
									lat, lon, &distance, &bearing);

				if (Station->Last.lat == 0 && Station->Last.lon == 0) speed = 0;
				else if (msDelta) speed = distance / (msDelta/1000.0/60.0/60.0);
				else speed = 500 + 1;	/* Trip this one out */

				if (msDelta < 10000)	/* Ignore anything less than 10 second */
				{
#ifndef UNDER_CE
					TraceLog("Invalids", FALSE, hwnd, "%s Moved TOO SOON %.3lfmi @ %ld in %.4lf sec or %.2lfmph (last %.2lf Avg %.2lf) from %.5lf %.5lf to %.5lf %.5lf  IGNORED!\n",
						   Station->Station,
						   (double) distance, (long) bearing,
						   (double) msDelta/1000.0, (double) speed,
						   (double) Station->Last.speed,
						   (double) Station->speedAverage,
						   (double) Station->Last.lat,
						   (double) Station->Last.lon,
						   (double) lat, (double) lon);
#endif
					Station->Tracks[t].Invalid = TRACK_QUICK;
					Station->TrackInvalids++;
					ThisOK = FALSE;
				} else if (distance > 0.1	/* Little wiggle can be FAST */
				&& speed > 500)	/* Arbitrary upper "normal" speed limit */
				{
					if (speed > 20000	/* I don't care, NOTHING moves THAT fast!  (Satellites do about 15,000) */
					|| speed > Station->speedAverage * 2)	/* And MUCH more than before */
					{
#ifndef UNDER_CE
						TraceLog("Invalids", FALSE, hwnd, "%s Moved TOO FAST %.3lfmi @ %ld in %.2lf sec or %.2lfmph (last %.2lf Avg %.2lf) from %.5lf %.5lf to %.5lf %.5lf\n",
								   Station->Station,
								   (double) distance, (long) bearing,
								   (double) msDelta/1000.0, (double) speed,
								   (double) Station->Last.speed,
								   (double) Station->speedAverage,
								   (double) Station->Last.lat,
								   (double) Station->Last.lon,
								   (double) lat, (double) lon);
						//if (distance>1000)
						{	if (Station->sLastPositPacket && Station->pLastPositPacket)
								TraceLog("Invalids", FALSE, hwnd, "Frm:%.*s\n", Station->sLastPositPacket, Station->pLastPositPacket);
							if (pkt) TraceLog("Invalids", FALSE, hwnd, "New:%s\n", pkt);
						}
#endif
						Station->Tracks[t].Invalid = TRACK_FAST;	/* Default this one bad */
						Station->TrackInvalids++;
						ThisOK = FALSE;

						if (Station->Bad.msec	/* If we have a previously bad one, see if this is ok by that */
						&& msNow > Station->Bad.msec+1000)	/* And long enough ago to calculate */
						{	msDelta = msNow - Station->Bad.msec;
							AprsHaversineLatLon(Station->Bad.lat, Station->Bad.lon,
												lat, lon, &distance, &bearing);
							speed = distance / (msDelta/1000.0/60.0/60.0);
							if (distance < 0.1 || speed < 500)	/* This looks good! */
							{
#ifndef UNDER_CE
								TraceLog("Invalids", TRUE, hwnd, "%s BAD Move(%ld) MADE GOOD %.3lfmi @ %ld in %.2lf sec or %.2lfmph (last %.2lf Avg %.2lf) from %.5lf %.5lf to %.5lf %.5lf\n",
										   Station->Station, (long) Station->TrackCount,
										   (double) distance, (long) bearing,
										   (double) msDelta/1000.0, (double) speed,
										   (double) Station->Bad.speed,
										   (double) Station->speedAverage,
										   (double) Station->Bad.lat,
										   (double) Station->Bad.lon,
										   (double) lat, (double) lon);
#endif

								FreeTracks(Station, FALSE);

								t = 3;
								Station->TrackCount = 4;
								if (Station->TrackCount >= Station->TrackSize)
								{	Station->TrackSize += 32;	/* This code assumes this is at least 2 or 4 */
									Station->Tracks = (TRACK_INFO_S *) realloc(Station->Tracks, sizeof(*Station->Tracks)*Station->TrackSize);
									InvalidateStatUsage(FALSE);
								}

								Station->Tracks[0].pCoord = GetCoordIndex(Station->Bad.lat, Station->Bad.lon, "StationTrack0", Station->Station, NULL);
								Station->Tracks[0].alt = (long) (alt*FeetPerMeter);
								Station->Tracks[0].msec = Station->Bad.msec;
								Station->Tracks[0].st = *stWhen;
								Station->Tracks[0].Invalid = TRACK_RESTART;
#ifndef UNDER_CE
								strncpy(Station->Tracks[0].IGate, IGate, sizeof(Station->Tracks[0].IGate));
#endif

								Station->Tracks[1].pCoord = GetCoordIndex(lat, lon, "StationTrackOK", Station->Station, NULL);
								Station->Tracks[1].alt = (long) (alt*FeetPerMeter);
								Station->Tracks[1].msec = msNow;
								Station->Tracks[1].st = *stWhen;
								Station->Tracks[1].Invalid = TRACK_RESTART;
#ifndef UNDER_CE
								strncpy(Station->Tracks[1].IGate, IGate, sizeof(Station->Tracks[1].IGate));
#endif
								Station->TrackInvalids = 2;
								Station->TrackDupes = 0;
								Station->Tracks[2] = Station->Tracks[0];
								Station->Tracks[3] = Station->Tracks[1];
								Station->Tracks[2].Invalid = TRACK_OK;
								Station->Tracks[3].Invalid = TRACK_OK;
								Station->Tracks[2].pCoord = GetCoordIndex(Station->Bad.lat, Station->Bad.lon, "StationTrack0", Station->Station, NULL);
								Station->Tracks[3].pCoord = GetCoordIndex(lat, lon, "StationTrackOK", Station->Station, NULL);
								Station->speedAverage = 0;
								ThisOK = TRUE;
							}
						}
					} else
					{
#ifndef UNDER_CE
#ifdef TRACK_BEARING
						Station->Tracks[t].bearing = bearing;
#endif
						TraceLog("Invalids", FALSE, hwnd, "%s Moved %.3lfmi @ %ld in %.2lf sec or %.2lfmph (last %.2lf Avg %.2lf) from %.5lf %.5lf to %.5lf %.5lf\n",
								   Station->Station,
								   (double) distance, (long) bearing,
								   (double) msDelta/1000.0, (double) speed,
								   (double) Station->Last.speed,
								   (double) Station->speedAverage,
								   (double) Station->Last.lat,
								   (double) Station->Last.lon,
								   (double) lat, (double) lon);
#endif
					}
				}
				if (speed > 20000) speed = 20000;	/* Cap the speed we're accumulating (Satellites are about 15,000) */
				Station->speedAverage -= Station->speedAverage / 4;
				Station->speedAverage += speed / 4;
				Station->speedCalculated = speed;
				Station->courseCalculated = bearing;

#ifdef TRACK_SPEED
				if (Station->CSEParsed)
					Station->Tracks[t].speed = Station->speed;
				else Station->Tracks[t].speed = Station->speedAverage;
#endif
]]
				end

				if not badMove and moved then
					station.tracks[#station.tracks+1] = packetInfo
					station.moveCount = (station.moveCount or 0) + 1
					--print(string.format('%s Has %i Tracks %i Done!', station.stationID, #station.tracks, (station.tracks.donePoint or 0)))
					if #station.tracks > 1 then
						if osmTiles then
							if shouldIShowIt(station.stationID) then
							local start = MOAISim.getDeviceTime()
							osmTiles:showTrack(station.tracks, (centerStation == station), station.stationID)
							addTime("showTrack["..#station.tracks.."]", MOAISim.getDeviceTime()-start)
							end
						end
	DidWhat = osmTiles and "showTrack" or "osmTiles=nil"
	--[[
						if centerStation ~= station then
							if osmTiles then
	toast.new(string.format('%s Has %i Tracks', station.stationID, #station.tracks), 2000,
	function ()
	if centerStation == myStation then
	M:updateCenterStation(station)	-- move and track
	else								-- otherwise just move and require a center tap
	osmTiles:moveTo(station.lat, station.lon)
	end
	end)
							end
						end
	]]
						--centerStation = station
						--updateCenterStation()
					else
	DidWhat = "singleTrack"
					end
				else
	--DidWhat = "Duplicate"
				end
			elseif station.tracks and station.lat and station.lon and (station.lat ~= station.tracks[#station.tracks].lat or station.lon ~= station.tracks[#station.tracks].lon) then
	DidWhat = "station~=tracks"
	print(DidWhat..' '..printableTable(station.stationID..":didWhats", station.didWhats))
			else
	DidWhat = "noMove"
			end
	--print(DidWhat..' vs '..printableTable(station.stationID..":didWhats",station.didWhats))
			if not duplicate then
				if not badMove and moved then
	DidWhat = DidWhat..':Moved'
					station.lat, station.lon = packetInfo.lat, packetInfo.lon
				end
				if packetInfo.symbol ~= station.symbol then
					local start = MOAISim.getDeviceTime()
					if station.symbolLabel then
	--print('Station('..station.stationID..') Changed Symbols from '..station.symbol..' to '..packetInfo.symbol)
						osmTiles:removeSymbol(station.symbolLabel)
						station.symbolLabel = nil
					end
					station.symbol = packetInfo.symbol
					station.symbolLabel = getSymbolLabel(station.symbol, station.stationID)
					addCenterTapCallback(station)
					addTime("getSymbol["..station.symbol.."]", MOAISim.getDeviceTime()-start)
					newsymbol = true
				end
			end
	if not station.didWhats then station.didWhats = {} end
	if #station.didWhats > 1 and station.didWhats[#station.didWhats]:sub(-(#DidWhat+1),-1) == ":"..DidWhat then
		local s,e,v=station.didWhats[#station.didWhats]:find("%d%d%:%d%d%:%d%d%:%((%d+)%)%:")
		if v then
			if tonumber(v) then
				v = tonumber(v) + 1
			else print(v.." is NOT a number from "..station.didWhats[#station.didWhats])
				v = 999
			end
		else v = 2
		end
--print('Station('..station.stationID..') updating DidWhats['..#station.didWhats..']:'..station.didWhats[#station.didWhats]..' for '..DidWhat..' v='..v)
		station.didWhats[#station.didWhats] = os.date("%H:%M:%S:").."("..v.."):"..DidWhat
	else
--		if #station.didWhats > 1 then
--			print("Station("..station.stationID..") adding "..DidWhat.." after "..station.didWhats[#station.didWhats]:sub(-(#DidWhat+1),-1))
--		end
		station.didWhats[#station.didWhats+1] = os.date("%H:%M:%S:")..DidWhat
	end
	
			if type(packetInfo.comment) == 'string' then
				local s, e, lt, ot, sc, t, id  = string.find(packetInfo.comment, " }(.)(.)(.)(%S-){(.....)")
				if s then
					osmTiles:removePolygon(station.polygon)
					print(station.stationID.." MultiLine:Line:"..tostring(lt).." Object:"..tostring(ot).." Scale:"..tostring(sc).." id:"..tostring(id).." pairs:"..tostring(t))
-- ISS MultiLine:Line:k Object:1 Scale:m id:!w9E! pairs:mNhb[rJz8q/N8+J"[*h:mN
					sc = 10^((sc:byte(1,1)-33)/20.0)*0.0001;	-- Scale in degrees
					local points = {}
--					local minLat, minLon, maxLat, maxLon
					for i=1,#t,2 do
						local lat = station.lat + (t:byte(i,i)-78)*sc
						local lon = station.lon - (t:byte(i+1,i+1)-78)*sc
						if (lon <= -180) then lon = -179.99999999999 end
						if (lon >= 180) then lon = 179.99999999999 end
						if (lat <= -90) then lat = -89.99999 end
						if (lat >= 90) then lat = 89.99999 end
						points[#points+1] = lat
						points[#points+1] = lon
--[[
						if i == 1 then
							minLat, minLon = lat, lon
							maxLat, maxLon = lat, lon
						else
							if lat < minLat then minLat = lat end
							if lon < minLon then minLon = lon end
							if lat > maxLat then maxLat = lat end
							if lon > maxLon then maxLon = lon end
						end
]]
					end
					local filled = (ot == '0')
					if filled
					and (points[1] ~= points[#points-1] or points[2] ~= points[#points]) then
						points[#points+1] = points[1]
						points[#points+1] = points[2]
					end
--[[
					if filled then	-- Start/end at the center (average) point
						local lat, lon = (minLat+maxLat)/2, (minLon+maxLon)/2
						table.insert(points, 1, lat)
						table.insert(points, 2, lon)
						points[#points+1] = lat
						points[#points+1] = lon
					end
]]
					print(printableTable(station.stationID.."MLP", points, " "))
					local color
					if lt == 'a' or lt == 'b' or lt == 'c' then color = {192,0,0}
					elseif  lt == 'd' or lt == 'e' or lt == 'f' then color = {192,192,0}
					elseif  lt == 'g' or lt == 'h' or lt == 'i' then color = {0,0,192}
					elseif  lt == 'j' or lt == 'k' or lt == 'l' then color = {0,192,0}
					else print(station.stationID.." Invalid MultiLine Line:"..tostring(lt))
					end
--[[
					if lt == 'a' or lt == 'd' or lt == 'g' or lt == 'j' then line = solid
					elseif lt == 'b' or lt == 'e' or lt == 'h' or lt == 'k' then line = dashed
					elseif lt == 'c' or lt == 'f' or lt == 'i' or lt == 'l' then line = dashed
					else print(station.stationID.." Invalid MultiLine Line:"..tostring(lt))
					end
]]
					station.polygon = points
					station.polygon.color = color
					if filled then
						station.polygon.alpha = "Screen.NWSOpacity"
					else station.polygon.alpha = 1.0
					end
					station.polygon.filled = filled
					osmTiles:showPolygon(station.polygon, station.stationID)
				end
			end

			if packetInfo.BRGNRQ then
				station.BRGNRQ = packetInfo.BRGNRQ
			end
	
			if station.symbol == '/\\'	-- DF Triangle?
			and station.BRGNRQ
			and station.BRGNRQ.number > 0	-- 0 number is meaningless
			and station.BRGNRQ.quality > 0	-- 0 quality is useless
			and station.BRGNRQ.range > 0	-- 0 range is a point
			then
				osmTiles:removePolygon(station.polygon)
				local point = LatLon.new(station.lat, station.lon)	-- center
				local bearing = station.BRGNRQ.bearing	-- +(Station->CSEParsed?Station->course:0.0);
				local as = bearing - station.BRGNRQ.quality/2;
				local ae = bearing + station.BRGNRQ.quality/2;
				local range = milesToKm(station.BRGNRQ.range);
				local points = {station.lat, station.lon}	-- starting point for lat/lon array
				for a=as,ae+12,12 do
					if a > ae then a = ae end	-- end condition
					local proj = point.destinationPoint(a, range)
					points[#points+1] = proj.getlat()
					points[#points+1] = proj.getlon()
					if a == ae then break end	-- get outa dodge to avoid infinite looping
				end
				points[#points+1] = points[1]	-- close the wedge
				points[#points+1] = points[2]
				station.polygon = points
				station.polygon.color = {255,204,0}	-- orange ({192,192,192} if killed)
				station.polygon.alpha = "Screen.DFOpacity"
				station.polygon.filled = true
				osmTiles:showPolygon(station.polygon, station.stationID)
			end

			if station == centerStation then
				local start = MOAISim.getDeviceTime()
				M:updateCenterStation()	-- This handles showSymbol
				addTime("updateCenter", MOAISim.getDeviceTime()-start)
			else
				if (not badMove and moved) or newsymbol then
					local start = MOAISim.getDeviceTime()
					if station.lat < -85.0511 or station.lat > 85.0511 or station.lon < -180 or station.lon > 180 then
print(string.format('%s invalid lat=%.5f lon=%.5f', station.stationID, station.lat, station.lon))
	--scheduleNotification(0,{alert=string.format('%s invalid lat=%.5f lon=%.5f', station.stationID, station.lat, station.lon)})
					end
					osmTiles:showSymbol(station.lat, station.lon, station.symbolLabel, station.stationID)
					addTime("showSymbol", MOAISim.getDeviceTime()-start)
				end
				local start = MOAISim.getDeviceTime()
if false then
if not duplicate and station.tracks
and (station.tracks[#station.tracks].lat ~= station.lat or station.tracks[#station.tracks].lon ~= station.lon) then
print(string.format('%s lat/lon station:%.5f %.5f Tracks[%i]:%.5f %.5f %s',
		station.stationID, station.lat, station.lon,
		#station.tracks, station.tracks[#station.tracks].lat,
		station.tracks[#station.tracks].lon, DidWhat))
end
if not duplicate and station.tracks
and (station.tracks[#station.tracks].x20 ~= station.symbolLabel.x20 or station.tracks[#station.tracks].y20 ~= station.symbolLabel.y20) then
print(string.format('%s x/y20 station:%.5f %.5f Tracks[%i]:%.5f %.5f %s',
		station.stationID, station.symbolLabel.x20, station.symbolLabel.y20,
		#station.tracks, station.tracks[#station.tracks].x20,
		station.tracks[#station.tracks].y20, DidWhat))
end
if not duplicate and station.tracks
and (station.tracks[#station.tracks].x ~= station.symbolLabel.x or station.tracks[#station.tracks].y ~= station.symbolLabel.y) then
print(string.format('%s x/y station:%.5f %.5f Tracks[%i]:%.5f %.5f Age:%isec %s',
		station.stationID, station.symbolLabel.x, station.symbolLabel.y,
		#station.tracks, station.tracks[#station.tracks].x,
		station.tracks[#station.tracks].y,
		(os.time()-station.tracks[#station.tracks].when), DidWhat))
print(printableTable(station.stationID..":didWhats", station.didWhats))
end
end
				addTime("Checks", MOAISim.getDeviceTime()-start)
			end
			addTime("LatLon", MOAISim.getDeviceTime()-start)
		end
		end
		end
		if packetInfo.msg then
			local start = MOAISim.getDeviceTime()
			local msg = packetInfo.msg
	--print('msg:to('..tostring(msg.addressee)..') ack('..tostring(msg.ack)..') '..tostring(msg.text))
			if msg.addressee == config.StationID then
				local QSO, QSOi = QSOs:newMessage(packetInfo.src, "ME", msg.text)
				print("Msg:newMessage returned "..tostring(QSO).." and "..tostring(QSOi))
				if msg.text:sub(1,3) == 'ack' and #msg.text <= 8 then
					toast.new(packetInfo.src..':'..msg.text, 2000)
				else
					QSOi.ack = msg.ack	-- Attach the expected ack sequence to the message
					local alert = tostring(packetInfo.src)..':'..tostring(msg.text)
	--								local options = { alert = alert, --badge = #notificationIDs+1, --sound = "???.caf",
	--												custom = { name="message", msg=msg, QSO=QSO } }
	--								scheduleNotification(0,options)
if MOAINotifications and not simRunning then
MOAINotifications.setListener(MOAINotifications.LOCAL_NOTIFICATION_MESSAGE_RECEIVED,
				function(event)
					print(printableTable('QSO:Notification',event))
					if event and event.message and event.from and event.to then
						local alert = tostring(event.from)..':'..tostring(event.message)
						local QSO = QSOs:getQSO(event.from, event.to)
						toast.new(alert, nil, function()
									if QSO then
										local n = QSOs:getMessageCount(QSO)
										if n > 0 then	-- Only open if there are new ones
											print(':onTap:opening QSO:'..QSO.id)
											SceneManager:openScene("QSO_scene", { animation="popIn", QSO = QSO })
										end
									end
								end)
					end
				end)
MOAINotifications.localNotificationInSeconds(0.1, alert,
			{title=MOAIEnvironment.appDisplayName..':'..tostring(packetInfo.src),
				id=tostring(msgCount), message=tostring(msg.text), from=packetInfo.src, to="ME" })
msgCount = msgCount + 1	-- Make it different for next time
else toast.new(alert, nil,
				function()
					local n = QSOs:getMessageCount(QSO)
					if n > 0 then	-- Only open if there are new ones
						print(':onTap:opening QSO:'..QSO.id)
						SceneManager:openScene("QSO_scene", { animation="popIn", QSO = QSO })
					end
				end)
end
				end
				if APRSIS and msg.ack and #msg.ack then
					local ack = string.format('%s>APWA00,TCPIP*::%-9s:ack%s', config.StationID, packetInfo.src, msg.ack)
					APRSIS:sendPacket(ack)
					QSOs:newMessage("ME", packetInfo.src, 'ack'..tostring(msg.ack))
					print ('Msg:msgAck:'..ack)
					if msg.ack:sub(3,3) == '}' then	-- the other end does ReplyAck!
						print ('Msg:replyAck:'..ack)
						station.replyAck = msg.ack:sub(1,2)
						QSOs:replyAck("ME", packetInfo.src, msg.ack)
					end
	--[[	if (Stat && acklen>=4 && ack[3] == '}')	/* Remember the ReplyAck if any */
	{	Stat->ReplyAck[0] = ack[1];
	Stat->ReplyAck[1] = ack[2];
	if (acklen == 6)
	{
	TraceLogThread("Messages", TRUE, "Scanning For My ReplyAck[%s] from %s\n", ack, from);
	CheckAndHandlePendingAck(from, "ack", &ack[4]);
	}
	}
	]]
				end
			end
			addTime("Message", MOAISim.getDeviceTime()-start)
		end
--[[
					if packetInfo.miceTrailing then
						local s, e, IGate = packetInfo.path:find('.+%,(.+)$')
						if IGate then
							-- print('Mic-e Type('..packetInfo.src..') '..packetInfo.platform..' '..packetInfo.miceTrailing..' by '..IGate..' via '..packetInfo.path)
							if stationInfo[IGate] then
								if not stationInfo[IGate].miceTrailing then stationInfo[IGate].miceTrailing = {} end
								if not stationInfo[IGate].miceTrailing[packetInfo.miceTrailing] then stationInfo[IGate].miceTrailing[packetInfo.miceTrailing] = 0 end
								stationInfo[IGate].miceTrailing[packetInfo.miceTrailing] = stationInfo[IGate].miceTrailing[packetInfo.miceTrailing] + 1
								print('IGate('..IGate..'>'..tostring(stationInfo[IGate].lastPacket.dst)..') '..packetInfo.miceTrailing..' '..stationInfo[IGate].miceTrailing[packetInfo.miceTrailing]..' packets')
							else
								print('Unknown IGate('..IGate..') for Mic-E '..packetInfo.miceTrailing..' from '..packetInfo.src..' path '..packetInfo.path)
							end
						else
							print('Unable to find Mic-E '..packetInfo.miceTrailing..' IGate in '..packetInfo.path..' from '..packetInfo.src)
						end
					end
]]
					station.packetsHeard = (station.packetsHeard or 0) + 1
					station.lastHeard = os.date()
					station.lastPacket = packetInfo
					--lastStation.text = string.format("%s to %s (%i)", packetInfo.src, packetInfo.dst, station.packetsHeard)
					--lastPath.text = packetInfo.path
					--lastPayload.text = packetInfo.comment

		elseif string.sub(line,1,1) == '#' then
			local start = MOAISim.getDeviceTime()
			if line:sub(1,9) == '# logresp' then
				local Verified = "not sure"
				if line:find('.+unverified.+') then
					Verified = "UNverified"
					if titleText then
						titleText:setRGBA(192, 192, 0, 1)	-- Yellow(ish) for unverified
					end
					--titleTextColor = { 192,192,0 }
					--titleText:setTextColor( unpack(titleTextColor) )	-- Yellow(ish) for unverified
				elseif line:find('.+verified.+') then
					Verified = "Verified"
					if titleText then
						titleText:setRGBA(96, 255, 96, 1)	-- Green for VERIFIED!
					end
					--titleTextColor = { 255,0,0 }
					--titleText:setTextColor( unpack(titleTextColor) )	-- Red for VERIFIED!
				else
					print('Unrecognized logresp:'..line)
				end
				local alert = "APRS-IS "..tostring(clientServer).." "..Verified
				if not config.APRSIS.Notify then
					toast.new(alert, 2000)
				else
					local options = { alert = alert, --badge = #notificationIDs+1, --sound = "???.caf",
										custom = { name="flushClient", Verified=Verified } }
					scheduleNotification(0,options)
				end
				APRSIS:triggerFilter(500)
				APRSIS:triggerStatus(750)
				APRSIS:triggerPosit("APRS-IS", 1000)
			end
			addTime("Comment", MOAISim.getDeviceTime()-start)
		else
			print ('Parse Fail:'..line)
			--lastStation.text = "Parse Fail"
			--lastPath.text = ''
			--lastPayload.text = line
		end
--print('Done w/'..line)
		addTime("Total", MOAISim.getDeviceTime()-start)
		--sayTime('packetReceived:'..(packetInfo and (packetInfo.src..':') or ''))
	end

return M
