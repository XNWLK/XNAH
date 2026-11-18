-- Addon messages between XNAH users of the same guild (price sharing): chunks of at most 255 bytes, a send queue at a
-- safe rate (2 messages a second, slower when the game says "too fast"), everything held while the game blocks addon
-- messages (boss fights and the like). Only the GUILD channel is used - never whispers, groups or public channels.
-- Received text is only ever read as data (Serialize.lua); a message type nobody handles is dropped.
local ADDON, X = ...

local PREFIX = "XNAH"
local MAX = 255
local HEADER = 8          -- "S" / "F" / "M" / "L" + up to 6 id characters + ":"
local BASE = 0.5          -- seconds between messages (2 a second)
local SLOWEST = 3         -- never slower than this
local MAX_PARTS = 200     -- a message longer than this many chunks is not put together (about 50 KB)
X.COMM_PREFIX = PREFIX

local queue = {}          -- {prio, text}
local sendId = 0
local nextSendAt = 0
local interval = BASE
local held = false
local ticking = false
X.commStats = {sent = 0, received = 0, held = 0, throttled = 0, dropped = 0}
X.commHandlers = {}       -- [kind] = function(msg, sender)

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
	local s = ""
	repeat
		local d = n % 36
		s = DIGITS:sub(d + 1, d + 1) .. s
		n = math.floor(n / 36)
	until n == 0
	return s
end

function X.InGuild()
	return IsInGuild ~= nil and X.Try(IsInGuild) == true
end

local function restricted()
	if C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted then
		local ok, r = pcall(C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
		if ok and r == true then return true end
	end
	return false
end

-- a zero byte cannot travel in a chat message: "\1" is the escape character ("\1\1" = "\1", "\1\2" = a zero byte)
local function replacePlain(s, from, to)
	local out, i = {}, 1
	while true do
		local j = s:find(from, i, true)
		if not j then out[#out + 1] = s:sub(i) break end
		out[#out + 1] = s:sub(i, j - 1)
		out[#out + 1] = to
		i = j + #from
	end
	return table.concat(out)
end
local function escape(s)
	return replacePlain(replacePlain(s, "\1", "\1\1"), "\0", "\1\2")
end
local function unescape(s)
	if not s:find("\1", 1, true) then return s end
	local out, i = {}, 1
	while true do
		local j = s:find("\1", i, true)
		if not j then out[#out + 1] = s:sub(i) break end
		out[#out + 1] = s:sub(i, j - 1)
		local c = s:sub(j + 1, j + 1)
		if c == "\2" then out[#out + 1] = "\0" elseif c == "\1" then out[#out + 1] = "\1" else return nil end
		i = j + 2
	end
	return table.concat(out)
end
X.CommEscape, X.CommUnescape = escape, unescape

local pump
local function schedule(delay)
	if ticking then return end
	ticking = true
	X.After(math.max(0, delay), function() ticking = false pump() end)
end

pump = function()
	if #queue == 0 then return end
	if not X.InGuild() then
		X.commStats.dropped = X.commStats.dropped + #queue
		queue = {}
		return
	end
	if restricted() then
		if not held then
			held = true
			X.commStats.held = X.commStats.held + 1
			X.Debug("guild messages held: the game blocks addon messages right now")
			X.Fire("XNAH_SHARE")
		end
		schedule(2)
		return
	end
	if held then held = false X.Fire("XNAH_SHARE") end
	local now = GetTime()
	if now < nextSendAt then schedule(nextSendAt - now) return end
	local item = table.remove(queue, 1)
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.text, "GUILD")
	if not ok then
		X.Debug("guild message failed: " .. tostring(result))
		X.commStats.dropped = X.commStats.dropped + 1
		nextSendAt = now + interval
	elseif result == 3 or result == 8 or result == false then -- AddonMessageThrottle / ChannelThrottle (false: an older client)
		X.commStats.throttled = X.commStats.throttled + 1
		table.insert(queue, 1, item)
		interval = math.min(SLOWEST, interval * 1.5)
		nextSendAt = now + 2
	elseif result == 11 then -- AddOnMessageLockdown
		table.insert(queue, 1, item)
		held = true
		X.commStats.held = X.commStats.held + 1
		X.Fire("XNAH_SHARE")
		schedule(2)
		return
	elseif result == 10 then -- NotInGuild
		X.commStats.dropped = X.commStats.dropped + #queue + 1
		queue = {}
		return
	elseif result == nil or result == true or result == 0 then
		X.commStats.sent = X.commStats.sent + 1
		interval = math.max(BASE, interval * 0.95)
		nextSendAt = now + interval
	else
		X.Debug("guild message refused (" .. tostring(result) .. ")")
		X.commStats.dropped = X.commStats.dropped + 1
		nextSendAt = now + interval
	end
	if #queue > 0 then schedule(math.max(0, nextSendAt - GetTime())) end
end

-- sends a table to the guild; prio 1 = first, 3 = last (price rows go last, short notes first). False when not in a guild.
function X.CommSend(msg, prio)
	if not X.InGuild() then return false end
	local text = escape(X.Ser(msg))
	sendId = (sendId + 1) % 2000000000
	local id = b36(sendId)
	local room = MAX - HEADER
	local parts = {}
	local i = 1
	while i <= #text do
		parts[#parts + 1] = text:sub(i, i + room - 1)
		i = i + room
	end
	if #parts == 0 then parts[1] = "" end
	if #parts > MAX_PARTS then X.Debug("message too long, not sent") return false end
	prio = prio or 2
	local pos = #queue + 1
	for q = 1, #queue do
		if queue[q].prio > prio then pos = q break end
	end
	for p = 1, #parts do
		local flag = (#parts == 1 and "S") or (p == 1 and "F") or (p == #parts and "L") or "M"
		table.insert(queue, pos, {prio = prio, text = flag .. id .. ":" .. parts[p]})
		pos = pos + 1
	end
	pump()
	return true
end

-- messages waiting to go out
function X.CommQueued()
	return #queue
end
-- the game refuses addon messages right now
function X.CommBlocked()
	return held or restricted()
end
-- forget everything waiting (sharing switched off)
function X.CommClear()
	queue = {}
end

-- [[ receiving ]] chunks are put back together per sender and message id
local partial = {} -- [sender .. "/" .. id] = {parts..., t = time}

-- half-received messages are forgotten after a minute (the check runs only while some are waiting)
local sweeping = false
local function sweep()
	local now = GetTime()
	for key, p in pairs(partial) do
		if now - p.t > 60 then partial[key] = nil end
	end
	if next(partial) then X.After(30, sweep) else sweeping = false end
end
local function startSweep()
	if sweeping then return end
	sweeping = true
	X.After(30, sweep)
end

local function deliver(text, sender)
	text = unescape(text)
	if not text then return end
	local msg = X.Deser(text)
	if type(msg) ~= "table" or type(msg.k) ~= "string" then return end
	X.commStats.received = X.commStats.received + 1
	local fn = X.commHandlers[msg.k]
	if fn then
		local ok, err = pcall(fn, msg, sender)
		if not ok then X.OnError(err) end
	end
end

X.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
	if prefix ~= PREFIX or channel ~= "GUILD" then return end
	if X.IsSecret(text) or X.IsSecret(sender) then return end
	if type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
	local flag, id, body = text:match("^([SFML])([0-9a-z]+):(.*)$")
	if not flag or #id > 6 then return end
	local key = sender .. "/" .. id
	if flag == "S" then
		deliver(body, sender)
	elseif flag == "F" then
		partial[key] = {body, t = GetTime()}
		startSweep()
	else
		local p = partial[key]
		if not p then return end
		p[#p + 1] = body
		p.t = GetTime()
		if #p > MAX_PARTS then partial[key] = nil return end
		if flag == "L" then
			partial[key] = nil
			deliver(table.concat(p), sender)
		end
	end
end)

X.On("ADDON_RESTRICTION_STATE_CHANGED", function() schedule(1) end)
X.On("PLAYER_REGEN_ENABLED", function() schedule(1) end)
X.On("PLAYER_LOGIN", function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then X.Try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end)
