-- Guild price sharing: XNAH users of one guild (same realm and faction) hand each other the prices of their newest full
-- scan, so one scan helps everyone. Plus the price export (CSV text to copy).
--
-- How it works (all over the GUILD addon channel, Comm.lua):
--   HELLO  {k "H", r realm, c client id, f time of my last full scan, v version} - 30 s after login and after every
--          full scan; also as an answer to a HELLO from someone whose scan is older than mine.
--   WANT   {k "W", r, c, to = the client asked, s = prices newer than this} - sent by a client whose scan is older (by
--          more than 20 minutes) to the ONE client with the newest scan (ties: the first name).
--   ROWS   {k "R", r, c, b = base time, d = "key,t,min,mkt,qty;..." (base 36, t counted from b)} - many prices a message.
--   END    {k "E", r, c, f, s, n} - the answer is complete.
-- Every field is checked; a price is only taken when it is newer than the one we have. Nothing else in a message is
-- ever acted on, and no message can make XNAH do anything but store a price.
local ADDON, X = ...

X.Default("share", true)

local GAP = 20 * 60          -- a scan this much newer is worth asking for
local MAX_AGE = 72 * 3600    -- prices older than this are never asked for nor sent
local ROW_ROOM = 160         -- bytes of price rows in one message (with the other fields it fits one 255-byte chunk)
local ANSWER_WAIT = 40       -- seconds to wait for the first prices before asking the next client
local SLICE = 400            -- items packed per frame

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function makeId()
	local s = ""
	for _ = 1, 6 do
		local d = math.random(1, 36)
		s = s .. DIGITS:sub(d, d)
	end
	return s
end

local peers = {}            -- [client id] = {name, f, v, seen}
local asking                -- {c, since, at, tries, excluded = {}}
local answering = false
local pendingSince          -- a WANT that came while answering: answered after
local lastHello = 0
local rowsFrom = {}         -- [client id] = time the last prices came

local function S() return X.S() end
local function on() return X.db ~= nil and S().share == true end
local function realm() return X.realmKey or X.RealmKey() end
local function saved()
	X.db.share = X.db.share or {}
	return X.db.share
end
-- this client's id (kept in the saved data, so it stays the same after a /reload)
local clientId
local function myId()
	if not clientId then
		local sv = saved()
		if type(sv.id) ~= "string" or not sv.id:find("^[0-9a-z]+$") or #sv.id > 8 then sv.id = makeId() end
		clientId = sv.id
		X.shareId = clientId
	end
	return clientId
end
local function changed() X.Debounce("share", 0.3, function() X.Fire("XNAH_SHARE") end) end

-- time of the last full scan made here (a refused scan's waiting time is not counted)
function X.MyFullScan()
	local scans = X.Realm().scans or {}
	for i = #scans, 1, -1 do
		if scans[i].kind == "full" then return scans[i].t end
	end
	return nil
end
-- how new the prices here are: my own scan, or one received from the guild
local function effective()
	return math.max(X.MyFullScan() or 0, X.Realm().sharedFull or 0)
end

-- [[ checks of received fields ]]
local function isId(v) return type(v) == "string" and #v >= 1 and #v <= 8 and v:find("^[0-9a-z]+$") ~= nil end
local function isTime(v, now) return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= now + 600 end
local function n36(s)
	if s == "" then return nil, true end
	if #s > 9 then return nil, false end
	local n = tonumber(s, 36)
	if not n then return nil, false end
	return n, true
end
local function validKey(key)
	return type(key) == "string" and #key <= 24 and (key:find("^%d+$") ~= nil or key:find("^%d+:%-?%d+$") ~= nil)
end
X.ShareValidKey = validKey

-- [[ sending ]]
local function hello(force)
	if not on() or not X.InGuild() then return end
	local now = X.Now()
	if not force and now - lastHello < 60 then return end
	lastHello = now
	X.CommSend({k = "H", r = realm(), c = myId(), f = X.MyFullScan() or 0, v = tostring(X.VERSION or "")}, 1)
end
X.ShareHello = hello

-- asks the client with the newest scan (ties: the first name) for its prices
local function ask()
	if not on() or not X.InGuild() then return end
	local now = X.Now()
	local mine = effective()
	asking = asking or {tries = 0, excluded = {}}
	local best
	for c, p in pairs(peers) do
		if p.f > mine + GAP and not asking.excluded[c] and now - p.seen < 2 * 3600 then
			if not best or p.f > best.f or (p.f == best.f and (p.name < best.name or (p.name == best.name and c < best.c))) then
				best = {c = c, f = p.f, name = p.name}
			end
		end
	end
	if not best then asking = nil changed() return end
	local since = math.max(mine, now - MAX_AGE)
	asking.c, asking.since, asking.at, asking.name, asking.f = best.c, since, now, best.name, best.f
	asking.tries = asking.tries + 1
	X.CommSend({k = "W", r = realm(), c = myId(), to = best.c, s = since}, 1)
	X.Debug("asking " .. best.name .. " for guild prices")
	changed()
	local ask0 = asking
	X.After(ANSWER_WAIT, function()
		if asking ~= ask0 or asking.c ~= best.c then return end
		if (rowsFrom[best.c] or 0) >= ask0.at then return end -- prices are coming
		asking.excluded[best.c] = true
		if asking.tries < 3 then ask() else asking = nil changed() end
	end)
end

-- answers a WANT: every price newer than `since`, many to a message, at the send queue's pace
local function answer(since)
	if answering then
		pendingSince = math.min(pendingSince or since, since)
		return
	end
	answering = true
	local r = realm()
	local items = X.Items()
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local i, n, buf = 0, 0, {}
	local size = 0
	local b36 = X.b36
	local function flush()
		if #buf == 0 then return end
		X.CommSend({k = "R", r = r, c = myId(), b = since, d = table.concat(buf, ";")}, 3)
		buf, size = {}, 0
	end
	X.Job("share", function()
		if not on() then return true end
		local stop = math.min(#keys, i + SLICE)
		while i < stop do
			i = i + 1
			local key = keys[i]
			local cur = items[key] and items[key].cur
			if cur and cur.t and cur.t > since and validKey(key) then
				local row = key .. "," .. b36(cur.t - since) .. "," .. b36(cur.min) .. "," .. b36(cur.mkt) .. "," .. b36(cur.qty or 0)
				if size + #row + 1 > ROW_ROOM then flush() end
				buf[#buf + 1] = row
				size = size + #row + 1
				n = n + 1
			end
		end
		return i >= #keys
	end, function()
		answering = false
		if not on() then return end
		flush()
		X.CommSend({k = "E", r = r, c = myId(), f = X.MyFullScan() or 0, s = since, n = n}, 3)
		local sv = saved()
		sv.lastSent = X.Now()
		sv.sent = (sv.sent or 0) + n
		X.Debug("sending " .. n .. " prices to the guild")
		changed()
		if pendingSince then
			local p = pendingSince
			pendingSince = nil
			if p < since then answer(p) end
		end
	end)
end

-- [[ receiving ]]
local function fromPeer(msg)
	if not on() then return false end
	if type(msg.r) ~= "string" or msg.r ~= realm() then return false end -- another realm or faction
	if not isId(msg.c) or msg.c == myId() then return false end
	return true
end

X.commHandlers.H = function(msg, sender)
	if not fromPeer(msg) then return end
	local now = X.Now()
	if not isTime(msg.f, now) then return end
	local v = type(msg.v) == "string" and msg.v:sub(1, 20) or "?"
	local isNew = peers[msg.c] == nil
	peers[msg.c] = {name = tostring(sender):sub(1, 60), f = msg.f, v = v, seen = now}
	changed()
	local mine = X.MyFullScan() or 0
	if msg.f > effective() + GAP then
		-- someone has newer prices: ask (after a moment, so every HELLO of the moment is heard and the newest is picked)
		if not asking or not asking.c then X.Debounce("shareask", 3, ask) end
	elseif mine > msg.f + GAP and (isNew or now - lastHello >= 60) then
		-- mine are newer: say so, so they can ask (a random moment later, so not every client answers at once)
		X.Debounce("sharehello", 2 + math.random() * 4, function() hello(true) end)
	end
end

X.commHandlers.W = function(msg)
	if not fromPeer(msg) or msg.to ~= myId() then return end
	local now = X.Now()
	if not isTime(msg.s, now) then return end
	answer(math.max(msg.s, now - MAX_AGE))
end

X.commHandlers.R = function(msg)
	if not fromPeer(msg) then return end
	local now = X.Now()
	if not isTime(msg.b, now) or msg.b < now - 30 * 86400 then return end
	if type(msg.d) ~= "string" or #msg.d > 4000 then return end
	local items = X.Items()
	local got = 0
	for row in msg.d:gmatch("[^;]+") do
		local key, ts, smin, smkt, sqty = row:match("^([%d:%-]+),([0-9a-z]+),([0-9a-z]*),([0-9a-z]*),([0-9a-z]*)$")
		if key and validKey(key) then
			local dt, ok1 = n36(ts)
			local min, ok2 = n36(smin)
			local mkt, ok3 = n36(smkt)
			local qty, ok4 = n36(sqty)
			local t = dt and msg.b + dt
			if ok1 and ok2 and ok3 and ok4 and t and t <= now + 600 and t > now - MAX_AGE - 86400
				and (not min or (min >= 1 and min <= 1e11)) and (not mkt or (mkt >= 1 and mkt <= 1e11))
				and (qty or 0) <= 1e8 then
				local it = items[key]
				if not it or not it.cur or not it.cur.t or it.cur.t < t then
					X.Record(key, t, min, mkt, qty or 0, nil)
					got = got + 1
				end
			end
		end
	end
	rowsFrom[msg.c] = now
	if peers[msg.c] then peers[msg.c].seen = now end
	if got > 0 then
		local sv = saved()
		sv.lastGot = now
		sv.got = (sv.got or 0) + got
		X.shareSession = (X.shareSession or 0) + got
		X.Debounce("shareprices", 2, function() X.Fire("XNAH_PRICES") end)
	end
	changed()
end

X.commHandlers.E = function(msg, sender)
	if not fromPeer(msg) then return end
	local now = X.Now()
	if not isTime(msg.f, now) or not isTime(msg.s, now) then return end
	if asking and asking.c == msg.c then
		if msg.s <= asking.since + 1 then
			local r = X.Realm()
			r.sharedFull = math.max(r.sharedFull or 0, msg.f)
			local n = X.shareSession or 0
			if n > 0 then X.Print("received " .. X.Num(n) .. " guild prices (from " .. (asking.name or "?") .. ")") end
			X.shareSession = 0
			asking = nil
		end
		changed()
	end
end

-- [[ start ]]
X.On("XNAH_LOGIN", function()
	X.After(30, function() hello(true) end)
end)
X.On("XNAH_FULLSCAN", function()
	X.After(2, function() hello(true) end)
end)

-- switches sharing on or off (from the Scan tab)
function X.SetShare(v)
	S().share = v and true or false
	if v then hello(true) else
		X.CommClear()
		asking = nil
	end
	changed()
end

-- [[ state for the Scan tab ]] {on, peers (guild members with XNAH seen), lastSent, lastGot, got (prices received),
-- names, inGuild, held, queued, asking (name), answering}
function X.ShareState()
	local sv = X.db and saved() or {}
	local names = {}
	local now = X.Now()
	for _, p in pairs(peers) do
		if now - p.seen < 12 * 3600 then names[#names + 1] = p.name end
	end
	table.sort(names)
	return {on = on(), peers = #names, lastSent = sv.lastSent, lastGot = sv.lastGot, got = sv.got or 0, sent = sv.sent or 0,
		names = names, inGuild = X.InGuild(), held = X.CommBlocked and X.CommBlocked() or false,
		queued = X.CommQueued and X.CommQueued() or 0, asking = asking and asking.name or nil, answering = answering}
end

-- [[ export ]] CSV lines "itemID,suffix,name,lowest,market,listed,avg7,avg30,seen" of every item seen in the last 3
-- days (at most 5,000 lines). Built a slice per frame; done(text, lines, total) when ready.
X.EXPORT_CAP = 5000
local function csv(s)
	s = tostring(s or "")
	if s:find("[,\"\n]") then return "\"" .. s:gsub("\"", "\"\"") .. "\"" end
	return s
end
local function num(v) return v and tostring(X.Round(v)) or "" end
function X.ExportPrices(done)
	local items = X.Items()
	local since = X.Now() - 3 * 86400
	local list = {}
	for key, it in pairs(items) do
		if it.cur and it.cur.t and it.cur.t >= since then list[#list + 1] = {key, (it.n or ""):lower(), it} end
	end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then return a[2] < b[2] end
		return a[1] < b[1]
	end)
	local total = #list
	local count = math.min(total, X.EXPORT_CAP)
	local lines = {"itemID,suffix,name,lowest,market,listed,avg7,avg30,seen"}
	local i = 0
	X.Job("export", function()
		local stop = math.min(count, i + 300)
		while i < stop do
			i = i + 1
			local key, it = list[i][1], list[i][3]
			local cur = it.cur
			local st = X.Stats(it) or {}
			local suffix = key:match(":(%-?%d+)$") or ""
			lines[#lines + 1] = table.concat({X.KeyID(key), suffix, csv(it.n or ""), num(cur.min), num(cur.mkt), num(cur.qty),
				num(st.avg7), num(st.avg30), X.Date(cur.t, "%Y-%m-%d %H:%M")}, ",")
		end
		return i >= count
	end, function()
		if done then done(table.concat(lines, "\n"), count, total) end
	end)
end
