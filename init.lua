--==============================================================
-- Copyright (c) 2010-2011 Zipline Games, Inc. 
-- All Rights Reserved. 
-- http://getmoai.com
--==============================================================
	package.path = "?;?.lua"
	print ( "load:" .. "\t" .. "running assets\lua\init.lua" )
	
	----------------------------------------------------------------
	-- this function supports all the ways a user could call print
	----------------------------------------------------------------
	print = function ( ... )
		
		local argCount = #arg
		
		if argCount == 0 then
			MOAILogMgr.log ( "" )
			return
		end
		
		local output = tostring ( arg [ 1 ])
		
		for i = 2, argCount do
			output = output .. "\t" .. tostring ( arg [ i ])
		end
		
		MOAILogMgr.log ( os.date("%H:%M:%S ")..output..'\n' )
	end
	----------------------------------------------------------------
	-- error function that actually prints the error
	----------------------------------------------------------------
	local superError = error
	
	error = function ( message, level )
	
		print ( "error: " .. message )
		print ( debug.traceback ( "", 2 ))
		superError ( message, level or 1 )
	end