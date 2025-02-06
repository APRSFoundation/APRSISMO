module(..., package.seeall)

--local Component = require "hp/gui/Component"

local backAnim
local titleText
local values
local newValue

function backHandler()
	SceneManager:closeScene({animation = "popOut"})
end

function onCreate(params)
	backAnim = params.backAnimation
	titleText = params.titleText
	values = params.values
	newValue = params.newValue

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
        --hBounceEnabled = false,
		HScrollEnabled = false,
        layout = VBoxLayout {
            align = {"center", "center"},
			padding = {0,0,0,0},
			--gap = {0,0},
            --padding = {10, 10, 10, 10},
            --gap = {4, 4},
            gap = {1, 1},
        },
    }

	local titleGroup = Group {}

	local titleBackground = Graphics {width = width, height = 40*config.Screen.scale, left = 0, top = 0}
    titleBackground:setPenColor(0.25, 0.25, 0.25, 0.75):fillRect()	-- dark gray like Android
	titleGroup:addChild(titleBackground)

    titleLabel = TextLabel {
        text = titleText,
		textSize=28*config.Screen.scale,
        size = {guiView:getWidth(), 40*config.Screen.scale},
        color = {1, 1, 1},
        parent = titleGroup,
        align = {"center", "center"},
    }

	if Application:isDesktop() then
		local button = Button {
			text = "Back", textSize=20, --13*config.Screen.scale,
			alpha = 0.8,
			--size = {100*config.Screen.scale, 40*config.Screen.scale},
			size = {100, 40},
			parent = titleGroup,
			onClick = function() backHandler() end,
		}
		button:setScl(config.Screen.scale,config.Screen.scale,1)
		button:setRight(width)
	end
	
	titleGroup:resizeForChildren()
	titleGroup:setParent(scroller)

	local colorRow =  { default = { 192/255, 192/255, 192/255 },
							over = { 30/255, 144/255, 255/255 }, }
	local colorLine = { 220/255, 220/255, 220/255 }
	local heightValue = 60*config.Screen.scale
	local pad = 5*config.Screen.scale
	
	for i, v in ipairs(values) do
        local button
		button = Group {}

		local titleBackground = Graphics {width = width, height = heightValue, left = 0, top = 0}
		titleBackground:setPenColor(unpack(colorRow.default)):fillRect()
		button:addChild(titleBackground)

		local text = tostring(v)
		local rowValue = TextLabel{
			text=text,
			textSize = 36*config.Screen.scale,
			size = {guiView:getWidth()/2, heightValue},
			color = {0,0,0},
			parent=button,
			align = {"center", "center"},
			wordBreak = MOAITextBox.WORD_BREAK_CHAR,
		}
		if #text > 0 then
			rowValue:fitSize()
			
			local useWidth = guiView:getWidth()-pad*2
			local xs, ys = rowValue:getSize()
			if xs > useWidth then
				print(useID..' is '..tostring(xs)..'x'..tostring(ys)..' vs '..useWidth..'x'..heightValue)
				local scale = useWidth/xs*0.95
				rowValue:dispose()
				rowValue = TextLabel{
					text=text,
					textSize = 36*config.Screen.scale*scale,
					size = {guiView:getWidth()/2, heightValue},
					color = {0,0,0},
					parent=button,
					align = {"center", "center"},
					wordBreak = MOAITextBox.WORD_BREAK_CHAR,
				}
				rowValue:fitSize()
			end
			rowValue:setWidth(useWidth)
		end
		rowValue:setRight(guiView:getWidth()-pad)
		rowValue:setTop(0)
		button:resizeForChildren()
		button:setParent(scroller)

		rowValue:addEventListener("touchUp",
				function(e)
					if e.isTap then
						print(v..' tapped!')
						newValue(v)
						backHandler()
					end
				end)
	end
end

--[[
self.unconfigure = function (self)
	if childScene then
		print('removing childScene:'..tostring(childScene)..' with '..(actions and #actions or 0)..' pending actions')
		SceneManager:closeScene({animation = "popOut"})
		childScene = nil
		return true
	end
	return false
end
]]

--[[
self.configure = function (self, removeIt, yOffset)	-- true will only remove if visible
	if not self.unconfigure(self) and not removeIt then
		childScene = SceneManager:openScene("config_scene", {config=self, animation = "popIn", backAnimation = "popOut", })
	end
end
]]

function onStop()
    print("chooser_scene:onStop()")
end

