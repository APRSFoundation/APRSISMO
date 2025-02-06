module(..., package.seeall)

local QSOs = require('QSOs')

-- Forward reference for our tableView
--local tableView = nil

local QSOCount

local freezeRefresh

local function refresh(event)
	if not freezeRefresh then
		if not event or event.isTap then
			QSOs:refresh()
		end
	end
end

local function closeScene()
	SceneManager:closeScene({animation="popOut"})
end

-- Called when the scene's view does not exist:
function onCreate( params )

print('QSOs:onCreate')

QSOCount = QSOs:getCount()

scene.backHandler = closeScene

--print('QSOs:createScene:DONE')

end

function onResume(  )
print('QSOs:onResume:QSOs='..QSOs:getCount()..' was '..QSOCount)
if QSOCount ~= QSOs:getCount() then performWithDelay(100,function() refresh() end) end
end

-- Called immediately after scene has moved onscreen:
function onStart(  )
print('QSOs:onStart')

if QSOCount ~= QSOs:getCount()  then
	refresh()
else

--[[
local QSO = event.params
if QSO then
	performWithDelay(100,function() SceneManager:openScene("QSO_scene", { QSO = QSO }) end)
else
]]
-----------------------------------------------------------------------------

-- INSERT code here (e.g. start timers, load audio, start listeners, etc.)

-----------------------------------------------------------------------------
--print('QSOs:enterScene')

	-- Listen for tableView events
	local function tableViewListener( event )
		local phase = event.phase
		
		--print( "Event.phase is:", event.phase )
	end

	-- Handle row rendering
	local function onRowRender( event )
		local phase = event.phase
		local row = event.row
		local id = row.id or '*Missing ID'
		local rowTitle = display.newText( row, tostring(id), 0, 0, nil, 14 )
		rowTitle:setReferencePoint( display.CenterLeftReferencePoint )
		--rowTitle.x = row.x - ( row.contentWidth * 0.5 ) + ( rowTitle.contentWidth * 0.5 )
		rowTitle.x = 10
		rowTitle.y = row.contentHeight * 0.5
		rowTitle:setTextColor( 0, 0, 0 )
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
			if id == 'New QSO...' then
				if not row.entryField then
if system.getInfo( "environment") == 'simulator' then
	QSOs:newQSO('KJ4ERJ-AP')
else
					row.promptField = display.newText("To Station:", row.x, row.y, nil, 14)
					row.promptField:setTextColor( 0, 0, 0 )
					local promptX = 10
					local xOffset = promptX+row.promptField.contentWidth+4
					row.entryField = native.newTextField( row.x+xOffset, row.y, row.contentWidth-xOffset-4, row.contentHeight*1.2 )
					row.entryField.font = native.newFont( native.systemFontBold, 14 )
					row.entryField.text = ''
					row.entryField:addEventListener( "userInput", function (event)
local eventPhase = event.phase	-- began, ended, editing, submitted
if eventPhase == 'ended' or eventPhase == 'submitted' then	-- Elvis has left the building!
	if row.entryField then
		local to = string.upper(trim(row.entryField.text))
		if to ~= '' then
			QSOs:newQSO(to)
		end
		row.entryField:removeSelf()
		row.promptField:removeSelf()
		row.entryField = nil
		row.promptField = nil
		if eventPhase == 'submitted' then
			native.setKeyboardFocus( nil )	-- Remove keyboard!
		end
	end
end
						end)
					row.promptField:setReferencePoint( display.CenterLeftReferencePoint )
					row.entryField:setReferencePoint( display.CenterLeftReferencePoint )
					row:insert(row.promptField)
					row.promptField.x, row.promptField.y = promptX, row.promptField.contentHeight/2
					row:insert(row.entryField)
					row.entryField.x, row.entryField.y = xOffset, row.entryField.contentHeight/2
					native.setKeyboardFocus( row.entryField )
					if row.index and type(row.index)=='number' and row.index > 1 then
						tableView:scrollToIndex( row.index-1, 500 )
					end
end
				end
			elseif id == 'New Group...' then
				if not row.entryField then
if system.getInfo( "environment") == 'simulator' then
	QSOs:newQSO('ANSRVR', 'TEST')
else
					row.promptField = display.newText("Group Name:", row.x, row.y, nil, 14)
					row.promptField:setTextColor( 0, 0, 0 )
					local promptX = 10
					local xOffset = promptX+row.promptField.contentWidth+4
					row.entryField = native.newTextField( row.x+xOffset, row.y, row.contentWidth-xOffset-4, row.contentHeight*1.2 )
					row.entryField.font = native.newFont( native.systemFontBold, 14 )
					row.entryField.text = ''
					row.entryField:addEventListener( "userInput", function (event)
local eventPhase = event.phase	-- began, ended, editing, submitted
if eventPhase == 'ended' or eventPhase == 'submitted' then	-- Elvis has left the building!
	if row.entryField then
		local to = string.upper(trim(row.entryField.text))
		if to ~= '' then
			QSOs:newQSO("ANSRVR", to)
		end
		row.entryField:removeSelf()
		row.promptField:removeSelf()
		row.entryField = nil
		row.promptField = nil
		if eventPhase == 'submitted' then
			native.setKeyboardFocus( nil )	-- Remove keyboard!
		end
	end
end
						end)
					row.promptField:setReferencePoint( display.CenterLeftReferencePoint )
					row.entryField:setReferencePoint( display.CenterLeftReferencePoint )
					row:insert(row.promptField)
					row.promptField.x, row.promptField.y = promptX, row.promptField.contentHeight/2
					row:insert(row.entryField)
					row.entryField.x, row.entryField.y = xOffset, row.entryField.contentHeight/2
					native.setKeyboardFocus( row.entryField )
					if row.index and type(row.index)=='number' and row.index > 1 then
						tableView:scrollToIndex( row.index-1, 500 )
					end
end
				end
			else
				local s, e, from = string.find(id, "^(.-)%s")
				--print("Selected ("..tostring(from)..')'..type(QSOs[from])..' '..type(QSOs[from].id)..' '..tostring(QSOs[from].id))
				if from and QSOs and QSOs[from] and QSOs[from].id and QSOs[from].id == from then
					performWithDelay(100,function() SceneManager:openScene("QSO_scene", { animation="popIn", QSO = QSOs[from] }) end)
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
        text = "APRS QSOs", textSize = 28*config.Screen.scale,
        size = {guiView:getWidth(), 50*config.Screen.scale},
        --size = {width, 50},
        color = {1, 1, 1},
        parent = titleGroup,
        align = {"center", "center"},
    }

	--if Application:isDesktop() then
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
	--end
	
	titleGroup:resizeForChildren()
	titleGroup:setParent(scroller)
	titleGroup:addEventListener("touchUp", function(e) print("QSOs_scene:titleGroup:touchUp!") end)

	local lineColor = { 220/255, 220/255, 220/255 }
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
			textSize = 29*config.Screen.scale,
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
			text=text:gsub("\<","\<\<"),
			textSize = 22*config.Screen.scale,
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
	--button = newButton("Refresh", 38*config.Screen.scale, newColor.default)
	--button:addEventListener("touchUp", refresh)
--[[
	button = newButton("New QSO...", qsoHeight, newColor.default)
	button:addEventListener("touchUp",
			function (e)
				if e.isTap then
					freezeRefresh = true
					SceneManager:openScene("textentry_scene",
					{
						animation = "popIn", backAnimation = "popOut",
						size = { Application.viewWidth * 0.95, 180},
						type = DialogBox.TYPE_WARNING,
						title = "New QSO",
						text = "Enter StationID (Callsign-SSID)",
						value = "",
						buttons = {"OK", "Cancel"},
						onResult = function(e)
							if e.result == 'OK' or e.result == 'Enter' then
								if type(e.value) == 'string' and #e.value > 0 then
									e.value = string.upper(trim(e.value))
									print("Dialog result is: '" .. e.result .. "', index " .. tostring(e.resultIndex)..", value "..tostring(e.value))
									QSOs:newQSO(e.value)
								end
							end
							freezeRefresh = false
						end,
					})
				end
			end)
]]
	
	local Qtitle = newTitle("Active QSOs", titleHeight, titleColor.default)
	local newQButton = Button {
		text = "New",
		textSize = 20,
		alpha = 0.8,
		size = {100, 50},
		parent = Qtitle,
		onClick = function ()
				freezeRefresh = true
				SceneManager:openScene("textentry_scene",
				{
					animation = "popIn", backAnimation = "popOut",
					size = { Application.viewWidth * 0.95, 180},
					type = DialogBox.TYPE_WARNING,
					title = "New QSO",
					text = "Enter StationID (Callsign-SSID)",
					value = "",
					buttons = {"OK", "Cancel"},
					onResult = function(e)
						if e.result == 'OK' or e.result == 'Enter' then
							if type(e.value) == 'string' and #e.value > 0 then
								e.value = string.upper(trim(e.value))
								print("Dialog result is: '" .. e.result .. "', index " .. tostring(e.resultIndex)..", value "..tostring(e.value))
								QSOs:newQSO(e.value)
							end
						end
						freezeRefresh = false
					end,
				})
			end
	}
	newQButton:setScl(config.Screen.scale,config.Screen.scale,1)
	newQButton:setRight(width)
	--print('QSOs='..type(QSOs)..'('..tostring(QSOs)..')')
	if QSOs then
		for q,a in QSOs:iterate() do
			if not a.additional or #a.additional == 0 then	-- ANSRVR's go below
				local n, t = QSOs:getMessageCount(a)
				if n > 0 then
					newButton(q..' ('..tostring(t)..' msgs '..tostring(n)..' NEW!)', qsoHeight, qsoColor.new)
				else newButton(q..' ('..tostring(t)..' msgs)', qsoHeight, qsoColor.default)
				end
				button:addEventListener("touchUp",
						function(e) if e.isTap then SceneManager:openScene("QSO_scene", { animation="popIn", QSO = a }) end end)
			end
		end
	else
		newButton("*None*", qsoHeight, newColor.default)
	end
	
	local Atitle = newTitle("ANSRVR (Announcements)", titleHeight, titleColor.default)
--[[
	newButton("New Group...", qsoHeight, newColor.default)
	button:addEventListener("touchUp",
			function (e)
				if e.isTap then
					freezeRefresh = true
					SceneManager:openScene("textentry_scene",
					{
						animation = "popIn", backAnimation = "popOut",
						size = { Application.viewWidth * 0.95, 180},
						type = DialogBox.TYPE_WARNING,
						title = "New ANSRVR Group",
						text = "Enter Group Name",
						value = "",
						buttons = {"OK", "Cancel"},
						onResult = function(e)
							if e.result == 'OK' or e.result == 'Enter' then
								if type(e.value) == 'string' and #e.value > 0 then
									e.value = string.upper(trim(e.value))
									print("Dialog result is: '" .. e.result .. "', index " .. tostring(e.resultIndex)..", value "..tostring(e.value))
									QSOs:newQSO('ANSRVR', e.value)
								end
							end
							freezeRefresh = false
						end,
					})
				end
			end)
]]
	local newAButton = Button {
		text = "New",
		textSize = 20,
		alpha = 0.8,
		size = {100, 50},
		parent = Atitle,
		onClick = function ()
					freezeRefresh = true
					SceneManager:openScene("textentry_scene",
					{
						animation = "popIn", backAnimation = "popOut",
						size = { Application.viewWidth * 0.95, 180},
						type = DialogBox.TYPE_WARNING,
						title = "New ANSRVR Group",
						text = "Enter Group Name",
						value = "",
						buttons = {"OK", "Cancel"},
						onResult = function(e)
							if e.result == 'OK' or e.result == 'Enter' then
								if type(e.value) == 'string' and #e.value > 0 then
									e.value = string.upper(trim(e.value))
									print("Dialog result is: '" .. e.result .. "', index " .. tostring(e.resultIndex)..", value "..tostring(e.value))
									QSOs:newQSO('ANSRVR', e.value)
								end
							end
							freezeRefresh = false
						end,
					})
				end
	}
	newAButton:setScl(config.Screen.scale,config.Screen.scale,1)
	newAButton:setRight(width)
	if QSOs then
		for q,a in QSOs:iterate() do
			if a.additional and #a.additional > 0 then	-- ANSRVR's go here
				local n, t = QSOs:getMessageCount(a)
				local n, t = QSOs:getMessageCount(a)
				if n > 0 then
					newButton(q..' ('..tostring(t)..' msgs '..tostring(n)..' NEW!)', qsoHeight, qsoColor.new)
				else newButton(q..' ('..tostring(t)..' msgs)', qsoHeight, qsoColor.default)
				end
				button:addEventListener("touchUp",
						function(e) if e.isTap then SceneManager:openScene("QSO_scene", { animation="popIn", QSO = a }) end end)
			end
		end
	else
		newButton("*None*", qsoHeight, newColor.default)
	end
	newTitle("Saved QSOs (Future)", titleHeight, titleColor.default)
	
--	if Application:isDesktop() then
		--button = newButton("Refresh", 40*config.Screen.scale, newColor.default)
		button = newButton("-", titleHeight, newColor.default)
		--button:addEventListener("touchUp", refresh )
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
		local backButton = Button {
			text = "Back",
			textSize = 20,
			alpha = 0.8,
			size = {100, 50},
			parent = button,
			onClick = closeScene
		}
		backButton:setScl(config.Screen.scale,config.Screen.scale,1)
		backButton:setLeft(0)
		--backButton:setRight(width)
--	else
--		button = newButton("Refresh", qsoHeight, newColor.default)
--		button:addEventListener("touchUp", refresh )
--	end
--[[	
	if Application:isDesktop() then
		button = newButton("Back", qsoHeight, newColor.default, true)
		button:addEventListener("touchUp", function(e) if e.isTap then SceneManager:closeScene() end end)
	end
]]

--print('QSOs:enterScene:Done')
--end
end
end

-- Called when scene is about to move offscreen:
function onStop( )

-----------------------------------------------------------------------------

-- INSERT code here (e.g. stop timers, remove listeners, unload sounds, etc.)

-----------------------------------------------------------------------------
--print('QSOs:exitScene')

--print('QSOs:exitScene:Done')
end


-- Called prior to the removal of scene's "view" (display group)
function onDestroy( )

-----------------------------------------------------------------------------

-- INSERT code here (e.g. remove listeners, widgets, save state, etc.)

-----------------------------------------------------------------------------
--print('QSOs:destroyScene')

end

---------------------------------------------------------------------------------
-- END OF YOUR IMPLEMENTATION
---------------------------------------------------------------------------------
