local QSOs = {}

----------------------------------------------------------------------------------
--
-- QSOs.lua
--
----------------------------------------------------------------------------------

print('QSOs:Loading!')

function QSOs:refresh(QSO)
	print('refresh:closing Scene')
	SceneManager:closeScene({animation = "popDown", },
			function ()
				print('refresh:QSOs:re-openingScene...')
				if QSO == nil then
						SceneManager:openScene("QSOs_scene", {animation="popIn"})
				else SceneManager:openScene("QSO_scene", { animation="popIn", QSO = QSO })
				end
			end)
	--performWithDelay(100,function()
--[[
							if QSO == nil then
									SceneManager:openScene("QSOs_scene")
							else SceneManager:openScene("QSO_scene", { QSO = QSO })
							end
]]
	--					end)
end

function QSOs:iterate()
	local t = QSOs
	local f = nil	-- Comparison function?
	local a = {}
	for n in pairs(t) do table.insert(a, n) end
	table.sort(a, f)
	local i = 0      -- iterator variable
	local iter = function ()   -- iterator function
		repeat i = i + 1
		until type(t[a[i]]) ~= 'function'	-- Skip functions in class
		if a[i] == nil then return nil
		else return a[i], t[a[i]]
		end
	end
	return iter
end

function QSOs:getCount()
	local c = 0
	for k,v in QSOs:iterate() do
		c = c + 1
	end
	return c
end

function QSOs:getQSO(from, to, additional)
	additional = additional or ''
	if #additional > 0 then additional = ':'..additional end
	if not QSOs then QSOs = {} end
	local fromTo = tostring(from)..'<>'..tostring(to)..additional
	if QSOs[fromTo] then return QSOs[fromTo], fromTo end
	local toFrom = tostring(to)..'<>'..tostring(from)..additional
	if QSOs[toFrom] then return QSOs[toFrom], toFrom end
	if QSOs[from..additional] then return QSOs[from..additional], from..additional end
	if QSOs[to..additional] then return QSOs[to..additional], to..additional end
	--if from == 'ME' then fromTo = to end
	-- if to == 'ME' then fromTo = from end
	if to == 'ME' then fromTo = toFrom end
	local QSO = {}
	QSOs[fromTo] = QSO
	QSO.id = fromTo
	if from == 'ME' then
		QSO.from, QSO.to = from, to
	elseif to == 'ME' then
		QSO.from, QSO.to = to, from
	else
		QSO.from, QSO.to = from, to
	end
	if #additional > 0 then
		QSOs[fromTo].additional = additional:sub(2)	-- remove the :
	end
	return QSOs[fromTo], fromTo
end

function QSOs:newQSO(to, additional)
	local QSO = QSOs:getQSO("ME", to, additional)
	performWithDelay(100,function() SceneManager:openScene("QSO_scene", { animation="popIn", QSO = QSO }) end)
end

function QSOs:getMessageCount(QSO)	-- Returns New and Total message counts for one or all (nil) QSOs
	local n, t = 0, 0, 0
	if not QSO then
		for k,v in QSOs:iterate() do
			local n1, t1 = QSOs:getMessageCount(v)
			n = n + n1
			t = t + t1
		end
	else
		for i,m in ipairs(QSO) do
			if type(i) == 'number' then	-- ignore the extra pairs
				t = t + 1
				if not m.read then n = n + 1 end
			end
		end
	end
	return n, t
end

function QSOs:newQSOMessage(QSO, from, to, text, when)
	when = when or os.time()
	if #text > 3 and #text <= 8 and text:sub(1,3) == 'ack' then	-- ack<1-5>
		local ack = text:sub(4)
		for i = #QSO, 1, -1 do
			local QSOi = QSO[i]
			if QSOi.ack==ack and QSOi.from==to and QSOi.to==from then	-- Reverse direction!
				print("Msg:GotAnAck:for "..text.." ack:"..ack)
				if not QSOi.acked then
					QSOi.acked = {}
					print("Msg:Have "..#QSOi.acked.." acks for "..QSOi.text)
				else print("Msg:Had "..#QSOi.acked.." acks for "..QSOi.text)
				end
				QSOi.acked[#QSOi.acked+1] = when
				print("Msg:Have "..#QSOi.acked.." acks for "..QSOi.text)
				return QSO, QSOi
			else print("Msg:Ack("..ack..") ~= Expected("..tostring(QSOi.ack)..") from:"..from.."v"..QSOi.from.." to:"..to.."v"..QSOi.to.." for "..QSOi.text)
			end
		end
	else print("Msg:NotAnAck:"..text)
	end
	local QSOi = {}
	QSO[#QSO+1] = QSOi
	QSOi.fromTo = from..'<>'..to
	if QSO.additional then QSOi.fromTo = QSOi.fromTo..':'..QSO.additional end
	QSOi.from = from
	QSOi.to = to
	QSOi.text = text
	QSOi.when = when
	return QSO, QSOi
end

function QSOs:newMessage(from, to, text, when)
	if to == 'ME' then
		local s, e, group = string.find(text, "^N:(.-)%s")
		if group then
			local newText = '('..from..') '..text:sub(#group+3)
			local QSO = QSOs:getQSO("ANSRVR", "ME", group)
			QSOs:newQSOMessage(QSO, from, to, newText)
		end
	end
	return QSOs:newQSOMessage(QSOs:getQSO(from, to), from, to, text, when)
end

function QSOs:replyAck(from, to, ack)
	if #ack == 5 and ack:sub(3,3) == '}' then	-- if this one contains a ReplyAck
		local replyAck = ack:sub(4)..'}'
		local QSO = QSOs:getQSO(from, to)
		for i = #QSO, 1, -1 do
			local QSOi = QSO[i]
			if QSOi.ack and QSOi.ack:sub(1,3)==replyAck and QSOi.from==from and QSOi.to==to then	-- Same direction!
				print("Msg:GotReplyAck:for "..QSOi.text.." ack:"..ack)
				if not QSOi.acked then
					QSOi.acked = {}
					print("Msg:Have "..#QSOi.acked.." (reply)acks for "..QSOi.text)
				else print("Msg:Had "..#QSOi.acked.." (reply)acks for "..QSOi.text)
				end
				QSOi.acked[#QSOi.acked+1] = os.time()
				print("Msg:Have "..#QSOi.acked.." (reply)acks for "..QSOi.text)
				return QSO, QSOi
			else print("Msg:ReplyAck("..ack..") ~= Expected("..tostring(QSOi.ack)..") from:"..from.."v"..QSOi.from.." to:"..to.."v"..QSOi.to.." for "..QSOi.text)
			end
		end
	end
end

return QSOs
