module(..., package.seeall)

local Event             = require "hp/event/Event"

local dlg
local result
local onResult

function onCreate(e)
    local width = 480
    local height = 320

    if e.size and type(e.size) == "table" and #e.size >= 2 then
        width = e.size[1]
        height = e.size[2]
    end

    view = View {
        scene = scene
    }
	onResult = 	e.onResult
    dlg = TextEntry {
        parent = view,
        type = e.type or TextEntry.TYPE_INFO,
        title = e.title or "Message title",
        text = e.text or "Message text",
        value = e.value or "Value",
        pos = {(Application.viewWidth - width) * 0.5, (Application.viewHeight - height) * 0.10},
        size = {width, height},
        buttons = e.buttons or {"OK"},
        onMessageResult = onDialogResult,
        onMessageHide = onDialogHide,
    }
    dlg:show()
end

local function dismiss(result)
	dlg:hide()
	local e = Event(TextEntry.EVENT_MESSAGE_RESULT)
	e.result = result
	e.resultIndex = 0
	e.value = dlg:getValue()
	dlg:dispatchEvent(e)
end

function onResume()
    print("textentry_scene:onResume()")

	if MOAIKeyboardAndroid then
		local function onInput ( start, length, text )
			print ( 'on input:type(start)='..type(start) )
			print ( 'start:'..start..' length:'..length..' text:'..text )
			if length > 0 then print('Bytes:',text:byte(1,length)) end
			print ( MOAIKeyboardAndroid.getText ())
			if length > 0 and text:byte(length,length) == 10 then
				length = length - 1
				text = text:sub(1,length)
				print('Shrunk:', text:byte(1,#text))
				--performWithDelay(1000,function() MOAIKeyboardAndroid.hideKeyboard() end)
				MOAIKeyboardAndroid.setText(text)
				MOAIKeyboardAndroid.hideKeyboard()
				dismiss('Enter')
			else
				dlg:setValue(text)
			end
		end

		local function onReturn ()
			print ( 'on return' )
			print ( MOAIKeyboardAndroid.getText ())
			--dlg:setValue(MOAIKeyboardAndroid.getText ())
			dismiss('Enter')
		end

		MOAIKeyboardAndroid.setListener ( MOAIKeyboardAndroid.EVENT_INPUT, onInput )
		MOAIKeyboardAndroid.setListener ( MOAIKeyboardAndroid.EVENT_RETURN, onReturn )
		MOAIKeyboardAndroid.setText(dlg:getValue())
		MOAIKeyboardAndroid.showKeyboard ()
	end

	if MOAIInputMgr.device.keyboard then
		MOAIInputMgr.device.keyboard:setCallback ( function(key,down)
				--print('main:onKeyboard:key('..tostring(key)..') down('..tostring(down)..')')
				if down then
					local value = dlg:getValue()
					if key == 8 then	-- Backspace
						value = value:sub(1,-2)
					elseif key == 127 then	-- Delete
						value = value:sub(2)
					elseif key == 13 then	-- <CR>
						print('textentry_scene:<CR>')
						dismiss('Enter')
					elseif key == 27 then	-- <ESC>
						print('textentry_scene:<ESC>')
						dismiss('Escape')
					elseif key == 256 then	-- Newly shifted?
					else
						print('textentry_scene:key='..tostring(key))
						value = value..string.char(key)
					end
					dlg:setValue(value)
				end
			end )
	end
	
end

function dropKeyboard()
	if MOAIKeyboardAndroid then
		MOAIKeyboardAndroid.hideKeyboard()
		MOAIKeyboardAndroid.setListener ( MOAIKeyboardAndroid.EVENT_INPUT, nil )
		MOAIKeyboardAndroid.setListener ( MOAIKeyboardAndroid.EVENT_RETURN, nil )
	end
	if MOAIInputMgr.device.keyboard then
		MOAIInputMgr.device.keyboard:setCallback ( nil )
	end
end

function onPause()
    print("textentry_scene:onPause()")
	dropKeyboard()
end

function onStop()
    print("textentry_scene:onStop()")
	dropKeyboard()
end

function onDestroy()
    print("textentry_scene:onDestroy()")
end

function onDialogResult(e)
	print(printableTable('textentry_scene:onDialogResult',e))
	result = e
end

function onDialogHide(e)
	print(printableTable('textentry_scene:onDialogHide',e))
	if MOAIKeyboardAndroid then
		MOAIKeyboardAndroid.hideKeyboard()
	end
	print('textentry_scene:closingScene')
    SceneManager:closeScene({animation = "popDown"})	-- popOut has delays
	print('textentry_scene:dispatching result:'..tostring(result)..' to '..tostring(onResult))
	if onResult and result then	-- do this AFTER the scene closes!
		onResult(result)
	end
	print('textentry_scene:onDialogHide:complete')
end
