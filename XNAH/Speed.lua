-- Sales speed: how many of an item sell in a day, and at which hours of the day the auction house sells most.
--
-- How it is worked out (an ESTIMATE): two full scans of this session, up to 4 hours apart, are compared. Every listing
-- of the earlier scan that is gone in the later one, although it still had too much time left to have run out
-- ("very long" = over 12 hours left, or "long" = 2 to 12 hours when the scans are under 2 hours apart), was bought -
-- or cancelled by its seller: the game does not tell the two apart, so cancelled auctions count as sales and the
-- numbers come out somewhat high for items people re-list often. Listings that were close to running out are never
-- counted (they may simply have expired). Only part of what is listed can be watched this way, so the time watched
-- counts in that part only: if half of the units had a long time left, an hour between scans counts as half an hour.
--
-- Saved: X.Realm().speed[key] = "day,units,minutes;..." (base 36, kept 30 days): units seen sold and minutes watched
-- per day. X.Realm().hours[0..23] = units seen sold in that hour of the day (your clock), X.Realm().hoursSeen[0..23] =
-- minutes watched in that hour; both fade slowly (half after two weeks) so the picture follows the server.
-- The previous full scan itself is kept in memory only (never saved).
local ADDON, X = ...

local MAX_GAP = 4 * 3600     -- scans further apart than this are not compared
local LONG_GAP = 2 * 3600    -- "long" listings (2 to 12 hours left) only count when the scans are closer than this
local KEEP_DAYS = 30
local SLICE = 3000           -- listings compared per frame
local FADE_DAYS = 14         -- the hours of the day: older sales count half after this many days

local prev                   -- {rows, t, seen} of the last full scan of this session
X.speedInfo = nil            -- the last comparison: {t, from, gap (seconds), units, items}

-- could a listing with this time-left band have run out between two scans `gap` seconds apart?
local function couldNotExpire(band, gap)
	if band == 3 then return true end
	if band == 2 and gap < LONG_GAP then return true end
	return false
end

-- one listing's "same auction" mark: its whole buyout (rounded) and its count
local function mark(price, count)
	count = count or 1
	return math.floor(price * count + 0.5) .. "x" .. count
end

-- [[ saving per item ]]
local function addDay(key, day, units, minutes)
	local r = X.Realm()
	r.speed = r.speed or {}
	local s = r.speed[key] or ""
	local pts = {}
	for p in s:gmatch("[^;]+") do
		local d, u, m = p:match("^([^,]*),([^,]*),([^,]*)$")
		d = X.n36(d)
		if d and d > day - KEEP_DAYS then pts[#pts + 1] = {d, X.n36(u) or 0, X.n36(m) or 0} end
	end
	local last = pts[#pts]
	if last and last[1] == day then
		last[2], last[3] = last[2] + units, last[3] + minutes
	else
		pts[#pts + 1] = {day, units, minutes}
	end
	local out = {}
	for i, p in ipairs(pts) do out[i] = X.b36(p[1]) .. "," .. X.b36(p[2]) .. "," .. X.b36(p[3]) end
	r.speed[key] = table.concat(out, ";")
end

-- units seen sold and minutes watched over the last 30 days
local function totals(key)
	local s = X.Realm().speed and X.Realm().speed[key]
	if not s then return nil end
	local today = X.Day()
	local units, minutes = 0, 0
	for p in s:gmatch("[^;]+") do
		local d, u, m = p:match("^([^,]*),([^,]*),([^,]*)$")
		d = X.n36(d)
		if d and d > today - KEEP_DAYS then
			units = units + (X.n36(u) or 0)
			minutes = minutes + (X.n36(m) or 0)
		end
	end
	return units, minutes
end

-- what you sold yourself, per day (from the sales ledger, when it knows): a sure lower limit
local function ownPerDay(key)
	if not X.LedgerItem then return nil end
	local li = X.Try(X.LedgerItem, key)
	if type(li) ~= "table" then return nil end
	if li.soldPerDay then return li.soldPerDay end
	if li.sold and li.days and li.days > 0 then return li.sold / li.days end
	return nil
end

-- [[ X.SaleRate(key) ]] -> units sold per day (estimate), hours watched; nil when nothing is known yet
function X.SaleRate(key)
	local units, minutes = totals(key)
	local rate, hours
	if units and minutes and minutes > 0 then
		rate = units / minutes * 1440
		hours = minutes / 60
	end
	local own = ownPerDay(key)
	if own and own > 0 and (not rate or own > rate) then rate = own end
	if not rate then return nil end
	return rate, hours or 0
end

-- [[ X.BestHours() ]] -> {[0..23] = share of the sales (0..1)}, {[0..23] = minutes watched}. Sales per minute watched
-- in each hour, as a share of all hours; an hour never watched has share 0 (see the minutes).
function X.BestHours()
	local r = X.Realm()
	local units, seen = r.hours or {}, r.hoursSeen or {}
	local rate, sum = {}, 0
	for h = 0, 23 do
		local m = seen[h] or 0
		rate[h] = m > 0 and (units[h] or 0) / m or 0
		sum = sum + rate[h]
	end
	local out, minutes = {}, {}
	for h = 0, 23 do
		out[h] = sum > 0 and rate[h] / sum or 0
		minutes[h] = seen[h] or 0
	end
	return out, minutes
end

-- spreads sold units and watched minutes over the hours of the day between t1 and t2 (local clock)
local function addHours(t1, t2, units, minutes)
	local r = X.Realm()
	r.hours = r.hours or {}
	r.hoursSeen = r.hoursSeen or {}
	local gap = t2 - t1
	if gap <= 0 then return end
	-- older numbers fade (half after FADE_DAYS days)
	local last = r.hoursT or t2
	local fade = 0.5 ^ (math.max(0, t2 - last) / (FADE_DAYS * 86400))
	r.hoursT = t2
	for h = 0, 23 do
		if r.hours[h] then r.hours[h] = r.hours[h] * fade end
		if r.hoursSeen[h] then r.hoursSeen[h] = r.hoursSeen[h] * fade end
	end
	local t = t1
	while t < t2 do
		local h = tonumber(date("%H", t)) or 0
		local m = tonumber(date("%M", t)) or 0
		local s = tonumber(date("%S", t)) or 0
		local stop = math.min(t2, t + 3600 - m * 60 - s)
		if stop <= t then stop = t + 1 end
		local part = (stop - t) / gap
		r.hours[h] = (r.hours[h] or 0) + units * part
		r.hoursSeen[h] = (r.hoursSeen[h] or 0) + minutes * part
		t = stop
	end
end

-- [[ comparing two full scans ]]
local function compare(old, rows, t)
	local gap = t - old.t
	local keys = old.seen
	local day = X.Day(t)
	local k = 0
	local soldAll, items, weightAll = 0, 0, 0
	X.Job("speed", function()
		local budget = 0
		while k < #keys and budget < SLICE do
			k = k + 1
			local key = keys[k]
			local before = old.rows[key]
			local list = before and before.list or {}
			budget = budget + #list + 1
			if #list > 0 then
				-- the listings still there now (same buyout, same count)
				local now = {}
				local cur = rows[key]
				for _, l in ipairs(cur and cur.list or {}) do
					local m = mark(l[1], l[2])
					now[m] = (now[m] or 0) + 1
				end
				-- the earlier listings, longest time left first: when two look the same and one is gone, the gone one
				-- is taken to be the one closer to running out (never counted)
				local order = {}
				for i = 1, #list do order[i] = list[i] end
				table.sort(order, function(a, b) return (a[3] or -1) > (b[3] or -1) end)
				local sold, units, watched = 0, 0, 0
				for _, l in ipairs(order) do
					local count = l[2] or 1
					units = units + count
					local ok = couldNotExpire(l[3], gap)
					if ok then watched = watched + count end
					local m = mark(l[1], count)
					if (now[m] or 0) > 0 then
						now[m] = now[m] - 1
					elseif ok then
						sold = sold + count
					end
				end
				if watched > 0 then
					local minutes = gap / 60 * watched / units
					addDay(key, day, sold, X.Round(minutes))
					soldAll = soldAll + sold
					weightAll = weightAll + minutes
					items = items + 1
				end
			end
		end
		return k >= #keys
	end, function()
		-- the hours of the day: all units seen sold, against the time watched (the average share watched)
		if items > 0 then addHours(old.t, t, soldAll, weightAll / items) end
		X.speedInfo = {t = t, from = old.t, gap = gap, units = soldAll, items = items}
		X.Realm().speedLast = X.speedInfo
		X.Fire("XNAH_ANALYSIS")
	end)
end

X.On("XNAH_FULLSCAN", function(rows, t, seen)
	if type(rows) ~= "table" or not t then return end
	local old = prev
	prev = {rows = rows, t = t, seen = seen or {}}
	if old and t > old.t and t - old.t <= MAX_GAP then
		compare(old, rows, t)
	end
	-- items not seen for 30 days: their speed goes
	local sp = X.Realm().speed
	if sp then
		local limit = X.Day(t) - KEEP_DAYS
		local list = {}
		for key in pairs(sp) do list[#list + 1] = key end
		local i = 0
		X.Job("speed-prune", function()
			local stop = math.min(#list, i + 2000)
			while i < stop do
				i = i + 1
				local key = list[i]
				local s = sp[key]
				local tail = s and s:match("([^;]*)$")
				local lastDay = tail and X.n36(tail:match("^([^,]*)"))
				if not lastDay or lastDay <= limit then sp[key] = nil end
			end
			return i >= #list
		end)
	end
end)

-- for the tests and /dump: forget the previous scan of this session
function X.SpeedForget() prev = nil end
