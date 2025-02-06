module(..., package.seeall)

----------------------------------------------------------------------------------
--
-- QSO.lua
--
----------------------------------------------------------------------------------
local QSOs = require("QSOs")	-- for sending messages and reloading conversation

----------------------------------------------------------------------------------
-- 
-- NOTE:
-- 
-- Code outside of listener functions (below) will only be executed once,
-- unless storyboard.removeScene() is called.
-- 
---------------------------------------------------------------------------------

---------------------------------------------------------------------------------
-- BEGINNING OF YOUR IMPLEMENTATION
---------------------------------------------------------------------------------

local tableView = nil

local QSO

local freezeRefresh

local function refresh(event)
	if not freezeRefresh then
		if not event or event.isTap then
			QSOs:refresh(QSO)
		end
	end
end

local function closeScene()
	SceneManager:closeScene({animation="popOut"})
end

-- Called when the scene's view does not exist:
function onCreate( params )
QSO = params.QSO

	scene.backHandler = closeScene

print(printableTable('onCreate:QSO',QSO))

	if QSO.to == 'ANSRVR' and QSO.additional then
		local now = MOAISim.getDeviceTime()
		if not QSO.refreshed or (now-QSO.refreshed) > 30*60 then	-- only every 30 seconds
			local text = 'J '..QSO.additional
			sendStatus = sendAPRSMessage(QSO.to, text, QSO.additional)
			if not sendStatus then QSO.refreshed = now else print('QSO:onCreate:sendStatus(J):'..sendStatus) end
		end
	end
end

-- Called immediately after scene has moved onscreen:
function onStart( )
print(printableTable('onStart:QSO',QSO))
-----------------------------------------------------------------------------

-- INSERT code here (e.g. start timers, load audio, start listeners, etc.)

-----------------------------------------------------------------------------
--print('QSO:enterScene')

	-- Listen for tableView events
	local function tableViewListener( event )
		local phase = event.phase
		
		--print( "Event.phase is:", event.phase )
	end

	-- Handle row rendering
	local function onRowRender( event )
		local phase = event.phase
		local row = event.row
		local id = row.id or '*Missing ID*'
		local w,h,ulX,ulY = getDisplayWH()
		if type(id) == 'table' then
			local rowTitle = display.newText( row, tostring(id.msg.text), 0, 0, nil, 14 )
			rowTitle:setReferencePoint( display.CenterLeftReferencePoint )
			rowTitle.x = 10
			--fillTextSquare(row, rowTitle, 8, 14, rowTitle.x+rowTitle.contentWidth)
			if id.isLeft then
			rowTitle.x = 10
			else --rowTitle:setReferencePoint( display.CenterRightReferencePoint )
			rowTitle.x = w-rowTitle.contentWidth-10
			end
			--rowTitle.x = row.x - ( row.contentWidth * 0.5 ) + ( rowTitle.contentWidth * 0.5 )
			rowTitle.y = row.contentHeight * 0.5
			rowTitle:setTextColor( 0, 0, 0 )

			local timestamp = nil
			if id.doDate then
				timestamp = os.date('%Y-%m-%d %H:%M:%S',id.msg.when)
			elseif id.doTime then
				timestamp = os.date('%H:%M:%S',id.msg.when)
			end
			if timestamp then
				local timeText = display.newText(row, tostring(timestamp), 0, 0, nil, 10)
				timeText.x = w/2
				timeText.y = timeText.contentHeight/2
				timeText:setTextColor( 64, 64, 64 )
			end
		else
			local rowTitle = display.newText( row, tostring(id), 0, 0, nil, 14 )
			rowTitle:setReferencePoint( display.CenterLeftReferencePoint )
			--rowTitle.x = row.x - ( row.contentWidth * 0.5 ) + ( rowTitle.contentWidth * 0.5 )
			rowTitle.x = 10
			rowTitle.y = row.contentHeight * 0.5
			rowTitle:setTextColor( 0, 0, 0 )
		end
	end
	
	-- Handle row updates
	local function onRowUpdate( event )
		local phase = event.phase
		local row = event.row
		
		--print( row.index, ": is now onscreen" )
	end
	
	-- Handle touches on the row
	local function onRowTouch( event )
		local phase = event.phase
		local row = event.target
		local id = row.id or '*Missing ID'

		if "release" == phase or "tap" == phase then
			if id == "Go Back" then
				performWithDelay(100,function() SceneManager:openScene("QSOs") end)
			elseif id == "Refresh" then
				performWithDelay(100,function() SceneManager:openScene("QSOs", { params = QSO }) end)
			elseif id == "Send Message..." then
				if not row.entryField then
if system.getInfo( "environment") == 'simulator' then
	local sendStatus
	if QSO.to == 'ANSRVR' and QSO.additional then
		local text = 'CQ '..QSO.additional..' '..'Test from simulator'
		sendStatus = sendAPRSMessage(QSO.to, text, QSO.additional)
	else
		sendStatus = sendAPRSMessage(QSO.to, "Test Message from Simulator")
	end
	toast.new(sendStatus or "Message Sent", 5000)
	performWithDelay(100,function() SceneManager:openScene("QSOs", { params = QSO }) end)
else
					row.entryField = native.newTextField( row.x, row.y, row.contentWidth-4, row.contentHeight*1.2 )
					row.entryField.font = native.newFont( native.systemFontBold, 14 )
					row.entryField.text = ''
					row.entryField:addEventListener( "userInput", function (event)
local eventPhase = event.phase	-- began, ended, editing, submitted
if eventPhase == 'ended' or eventPhase == 'submitted' then	-- Elvis has left the building!
	if row.entryField then
		if row.entryField.text ~= '' then
			local sendStatus
			if QSO.to == 'ANSRVR' and QSO.additional then
				local text = 'CQ '..QSO.additional..' '..row.entryField.text
				sendStatus = sendAPRSMessage(QSO.to, text, QSO.additional)
			else sendStatus = sendAPRSMessage(QSO.to, row.entryField.text)
			end
			toast.new(sendStatus or "Message Sent", 5000)
			performWithDelay(100,function() SceneManager:openScene("QSOs", { params = QSO }) end)
		end
		row.entryField:removeSelf()
		row.entryField = nil
		if eventPhase == 'submitted' then
			native.setKeyboardFocus( nil )	-- Remove keyboard!
		end
	end
end
						end)
					row:insert(row.entryField)
					row.entryField.x, row.entryField.y = row.entryField.contentWidth/2, row.entryField.contentHeight/2
					native.setKeyboardFocus( row.entryField )
					if row.index and type(row.index)=='number' and row.index > 1 then
						tableView:scrollToIndex( row.index-1, 500 )
					end
end
				end
			end
		end
	end

	-- Create a Scroller
	local width = Application.viewWidth
	if Application.viewWidth > Application.viewHeight then --	landscape, shrink the width
		width = width * 0.75
	end
	local left = (Application.viewWidth-width)/2

    guiView = View {
		left = left,
		width = width,
        scene = scene,
    }
    
    scroller = Scroller {
        parent = guiView,
		HScrollEnabled = false,
        layout = VBoxLayout {
            align = {"center", "center"},
			padding = {0,0,0,0},
			--gap = {0,0},
            --padding = {10, 10, 10, 10},
            gap = {1, 1},
        },
    }

	local titleGroup = Group {}

	local titleBackground = Graphics {width = width, height = 50*config.Screen.scale, left = 0, top = 0}
    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
	titleGroup:addChild(titleBackground)

    titleLabel = TextLabel {
        text = QSO.id:gsub("\<","\<\<"), textSize = 28*config.Screen.scale,
        size = {guiView:getWidth(), 50*config.Screen.scale},
        color = {1, 1, 1},
        parent = titleGroup,
        align = {"center", "center"},
    }

--	if Application:isDesktop() then
		local button = Button {
			text = "Back", textSize = 20,
			alpha = 0.8,
			size = {100, 50},
			parent = titleGroup,
			onClick = closeScene,
		}
		button:setScl(config.Screen.scale,config.Screen.scale,1)
		button:setLeft(0)
		--button:setRight(width)
		local refreshButton = Button {
			text = "Refresh",
			textSize = 20,
			alpha = 0.8,
			size = {100, 50},
			parent = titleGroup,
			onClick = function() refresh(nil) end
		}
		refreshButton:setScl(config.Screen.scale,config.Screen.scale,1)
		refreshButton:setRight(width)
--	end
	
	titleGroup:resizeForChildren()
	titleGroup:setParent(scroller)

	local lineColor = { 220/255, 220/255, 220/255 }
	local msgHeight = 36*config.Screen.scale -- 36
	local timeHeight = 14*config.Screen.scale	-- Added to msgHeight if timestamp included
	local titleHeight = 50*config.Screen.scale
	local titleColor = { default = { 150/255, 160/255, 180/255, 200/255 }, }
	local qsoHeight = 60*config.Screen.scale
	local qsoColor = { default = { 181/255, 208/255, 208/255 },
						new = { 30/255, 144/255, 255/255 },
						over = { 30/255, 144/255, 255/255 },
					}
	local newColor = { default = { 189/255, 203/255, 220/255 },
						over = { 30/255, 144/255, 255/255 },
					}
	local pad = 5*config.Screen.scale

	local function newTitle(text, height, color)
		button = Group {}
		local titleBackground = Graphics {width = width, height = height, left = 0, top = 0}
		titleBackground:setPenColor(unpack(color)):fillRect()
		button:addChild(titleBackground)
		local text = TextLabel{
			text=text,
			textSize = 28*config.Screen.scale,
			size = {width, height},
			color = {0,0,0},
			parent=button,
			align = {"center", "center"},
		}
		text:fitSize()
		text:setLeft(pad) text:setTop((height-text:getHeight())/2)
		button:resizeForChildren()
		button:setParent(scroller)
		return button
	end
	local function newButton(text, height, color, onRight)
		button = Group {}
		local titleBackground = Graphics {width = width, height = height, left = 0, top = 0}
		titleBackground:setPenColor(unpack(color)):fillRect()
		button:addChild(titleBackground)
		local text = TextLabel{
			text=text,
			textSize = 29*config.Screen.scale,
			size = {width, height},
			color = {0,0,0},
			parent=button,
			align = {"left", "center"},
		}
		text:fitSize()
		if onRight then text:setRight(width-pad)
		else text:setLeft(pad) end
		text:setTop((height-text:getHeight())/2)
		button:resizeForChildren()
		button:setParent(scroller)
		return button
	end

	local lastDate = ''
	local lastTime = 0

	local function newMessage(msg, height, color)
		local isRight = (msg.fromTo == QSO.id)
		local doDate, doTime = false, false
		local test
--print('QSO['..tostring(i)..']:'..type(m.when)..'('..tostring(m.when)..')')
		test = os.date('%Y-%m-%d',msg.when)
		if lastDate ~= test then
			lastDate = test
			doDate = true
		end
		test = os.date('%H:%M:%S:',msg.when)
		if test ~= lastTime then
			lastTime = test
			doTime = true
		end
		local timestamp = nil
		if doDate then
			timestamp = os.date('%Y-%m-%d %H:%M:%S',msg.when)
		elseif doTime then
			timestamp = os.date('%H:%M:%S',msg.when)
		end
		if timestamp or msg.ack or msg.acked then
			height = height + timeHeight	-- Make this cell a bit taller for timestamp
		end
		
		local button = Group {}

		local titleBackground = Graphics {width = width, height = height+1, left = 0, top = 0}
		titleBackground:setPenColor(unpack(color)):fillRect()
		button:addChild(titleBackground)
		
		local text = TextLabel{
			text=msg.text:gsub("\<","\<\<"),
			textSize = 29*config.Screen.scale,
			size = {width, height},
			color = {0,0,0},
			parent=button,
			align = {"left", "bottom"},
			wordBreak = MOAITextBox.WORD_BREAK_CHAR,
		}
		if #msg.text > 0 then
			text:fitSize()
			local useWidth = guiView:getWidth()-pad*2
			local xs, ys = text:getSize()
			if xs > useWidth then
				local scale = useWidth/xs*0.95
				text:dispose()
				text = TextLabel{
					text=msg.text:gsub("\<","\<\<"),
					textSize = 29*config.Screen.scale*scale,
					size = {guiView:getWidth()/2, heightValue},
					color = {0,0,0},
					parent=button,
					align = {"left", "bottom"},
					wordBreak = MOAITextBox.WORD_BREAK_CHAR,
				}
				text:fitSize()
			end
			--text:setWidth(useWidth)
		end
		
		if isRight then text:setLeft(pad)
		else text:setRight(guiView:getWidth()-pad) end
		--text:setTop((height-text:getHeight())/2)
		
		if type(text.getBaseline) == 'function' then
			local baseline = text:getBaseline()
			print("Height == "..text:getHeight().." Baseline:"..baseline)
			text:setTop(height-baseline-pad)
		else text:setBottom(height)
		end

		if timestamp then
			local timeText = TextLabel{
				text=timestamp,
				textSize = 14*config.Screen.scale,
				size = {width, height},
				color = {64/255,64/255,64/255},
				parent=button,
				align = {"center", "top"},
			}
			timeText:fitSize()
			timeText:setPos(0,0)
			if isRight then timeText:setLeft(pad)
			else timeText:setRight(width-pad) end
			--timeText:setPos(0, 0)	-- Maybe setLoc?
				--timeText.x = w/2
				--timeText.y = timeText.contentHeight/2
		end
		
		local ackText = msg.ack or ""
		if msg.acked then
			ackText = ackText.."="..os.date("%H:%M:%S", msg.acked[1])
			if #msg.acked > 1 then
				ackText = ackText.."+"..os.date("%H:%M:%S", msg.acked[#msg.acked])
				if #msg.acked > 2 then
					ackText = ackText.."("..tostring(#msg.acked)..")"
				end
			end
		end
		if #ackText > 0 then
			local timeText = TextLabel{
				text=ackText,
				textSize = 14*config.Screen.scale,
				size = {width, height},
				color = {64/255,64/255,64/255},
				parent=button,
				align = {"center", "top"},
			}
			timeText:fitSize()
			timeText:setPos(0,0)
			if isRight then timeText:setRight(width-pad)
			else timeText:setLeft(pad) end
		end
		button:resizeForChildren()
		button:setParent(scroller)
		return button
	end

--	button = newButton("Refresh", qsoHeight, newColor.default)
--	button:addEventListener("touchUp", refresh)

	--newTitle(QSO.id, titleHeight, titleColor.default)

	for i,m in ipairs(QSO) do
		if type(i) == 'number' then	-- ignore the extra pairs
			print('m.fromTo:'..tostring(m.fromTo)..' QSO.id:'..tostring(QSO.id)..' text:'..tostring(m.text))
			button = newMessage(m, msgHeight, m.read and qsoColor.default or qsoColor.new)
			m.read = os.time()
		end
	end
--[[
	if type(QSO.to) == 'string' then
		button = newButton("Send Message...", qsoHeight, newColor.default)
		button:addEventListener("touchUp",
			function(e)
				if e.isTap then
					freezeRefresh = true
					SceneManager:openScene("textentry_scene",
					{
						animation = "popIn", backAnimation = "popOut",
						size = { Application.viewWidth * 0.95, 180},
						type = DialogBox.TYPE_WARNING,
						title = QSO.id,
						text = "Enter Text to send",
						value = "",
						buttons = {"Send", "Cancel"},
						onResult = function(e)
							if e.result == 'Send' or e.result == 'Enter' then
								if type(e.value) == 'string' and #e.value > 0 then
									local sendStatus
									if QSO.to == 'ANSRVR' and QSO.additional then
										local text = 'CQ '..QSO.additional..' '..e.value
										sendStatus = sendAPRSMessage(QSO.to, text, QSO.additional)
									else
										sendStatus = sendAPRSMessage(QSO.to, e.value)
									end
									toast.new(sendStatus or "Message Sent", 5000)
									performWithDelay(100, refresh)
								end
							end
							freezeRefresh = false
						end,
					})
				end
			end)
	end
]]
--	if Application:isDesktop() then
		button = newButton("-", titleHeight, newColor.default)
		--button:addEventListener("touchUp", refresh )
		local backButton = Button {
			text = "Back", textSize = 20,
			alpha = 0.8,
			size = {100, 50},
			parent = button,
			onClick = closeScene,
		}
		backButton:setScl(config.Screen.scale,config.Screen.scale,1)
		backButton:setLeft(0)
		--backButton:setRight(width)
		local refreshButton = Button {
			text = "Refresh",
			textSize = 20,
			alpha = 0.8,
			size = {100, 50},
			parent = button,
			onClick = function() refresh(nil) end
		}
		refreshButton:setScl(config.Screen.scale,config.Screen.scale,1)
		refreshButton:setRight(width)

	if type(QSO.to) == 'string' then
		local newButton = Button {
			text = "Send",
			textSize = 20,
			alpha = 0.8,
			size = {100, 50},
			parent = button,
			onClick = function()
					freezeRefresh = true
					SceneManager:openScene("textentry_scene",
					{
						animation = "popIn", backAnimation = "popOut",
						size = { Application.viewWidth * 0.95, 180},
						type = DialogBox.TYPE_WARNING,
						title = QSO.id,
						text = "Enter Text to send",
						value = "",
						buttons = {"Send", "Cancel"},
						onResult = function(e)
							if e.result == 'Send' or e.result == 'Enter' then
								if type(e.value) == 'string' and #e.value > 0 then
									local sendStatus
									if QSO.to == 'ANSRVR' and QSO.additional then
										local text = 'CQ '..QSO.additional..' '..e.value
										sendStatus = sendAPRSMessage(QSO.to, text, QSO.additional)
									else
										sendStatus = sendAPRSMessage(QSO.to, e.value)
									end
									toast.new(sendStatus or "Message Sent", 5000)
									performWithDelay(100, refresh)
								end
							end
							freezeRefresh = false
						end,
					})
				end}
		newButton:setScl(config.Screen.scale,config.Screen.scale,1)
		newButton:setLeft((width-newButton:getWidth())/2)
	end
		
		
		
--	else
--		button = newButton("Refresh", qsoHeight, newColor.default)
--		button:addEventListener("touchUp", refresh )
--	end
	
	local minx, miny, maxx, maxy = scroller:scrollBoundaries()
	print('Scroller '..minx..','..miny..' -> '..maxx..','..maxy)
	scroller:ajustScrollSize()
	minx, miny, maxx, maxy = scroller:scrollBoundaries()
	print('Scroller '..minx..','..miny..' -> '..maxx..','..maxy)
	--scroller:scrollTo(0, -2000, 0.25, MOAIEaseType.SOFT_EASE_IN, function() print('Scrolled to bottom') end )	-- scroll to the bottom
	local xsize, ysize = scroller:getSize()
	local px, py = scroller:getParent():getSize()
	print('Scroller is '..xsize..'x'..ysize..' parent is '..px..'x'..py)
	performWithDelay(20,function() scroller:setPos(0,-2000000) end)
--[[
	local maxlines = ((h - ulY) - qsoHeight - titleHeight - qsoHeight - qsoHeight) / (msgHeight+2)
	--print('maxLines='..maxlines)
	if #QSO > maxlines then
	tableView:insertRow
	{	id = "Dummy Bottom Row(s)",
		isCategory = true,
		rowHeight = qsoHeight,
		rowColor = titleColor,
		lineColor = lineColor,
	}
	tableView:insertRow
	{	id = "Dummy Bottom Row(s)",
		isCategory = true,
		rowHeight = qsoHeight,
		rowColor = titleColor,
		lineColor = lineColor,
	}
		tableView:scrollToIndex( #QSO-math.floor(maxlines), 500 )
	end
]]

--print('QSO:enterScene:Done')

end


-- Called when scene is about to move offscreen:
function onStop( )

-----------------------------------------------------------------------------

-- INSERT code here (e.g. stop timers, remove listeners, unload sounds, etc.)

-----------------------------------------------------------------------------
--print('QSO:exitScene')
	if tableView then
		tableView:removeSelf()
		tableView = nil
	end
--print('QSOsexitScene:Done')
end


-- Called prior to the removal of scene's "view" (display group)
function onDestroy( )

-----------------------------------------------------------------------------

-- INSERT code here (e.g. remove listeners, widgets, save state, etc.)

-----------------------------------------------------------------------------
--print('QSO:destroyScene')

end

---------------------------------------------------------------------------------
-- END OF YOUR IMPLEMENTATION
---------------------------------------------------------------------------------

--print('QSO initialized!')
