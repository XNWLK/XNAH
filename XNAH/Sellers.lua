-- Sellers: the numbers of an item's seller history (X.SellerHistory, Data.lua) for the Sellers page of the Items view.
--   X.SellerStats(key) -> {
--     hasSellers = true when any day has a seller count (only items searched by themselves: the full scan on Forever
--       gives no seller names),
--     now = the latest day with sellers {day, sellers, topShare (0-100), topName} or nil,
--     days7 = days in the last 7 the item was seen at all (a scan or a search), scans7 = scans and searches in them,
--     undercuts7 = undercuts counted in the last 7 days, perDay = undercuts7 / days7 (nil when not seen),
--     share = undercuts7 / scans7 (0..1: how many of your scans saw a lower price than the one before),
--     speed = {word, sub, text} "how fast they undercut" in plain words}
--   X.SellerSeries(key, fromDay) -> sellers, topShare, undercuts: points {{t, v}} for graphs (t = noon of the day);
--     undercuts get a 0 on every day the item was seen without one, so the line does not skip quiet days.
--   X.UndercutSpeed(perDay, scans, undercuts) -> {word, sub, text} (the plain words alone, for the tests)
--   X.SellersNow(key) -> {t, units, rows = {{name, units, auctions, lowest, share (0..1), mine, unnamed}, ...}} the sellers
--     of the last search of the item THIS SESSION (biggest first; one row "unnamed" for the sellers the game gives no
--     name for), or nil. Not saved: names and stacks change by the hour.
-- Undercuts are counted only between your own scans and searches (Data.lua X.Record): an item scanned once a day can
-- show at most one a day. The page says so.
local ADDON, X = ...

local DAY = 86400
local MAX_LIVE = 100 -- the sellers of at most this many items are kept this session (the oldest go first)

-- [[ the numbers ]] cached per item until its seller text, day text or the day changes
local cache = setmetatable({}, {__mode = "k"})

-- day points of the item's price history: {[day] = scans that day}
local function seenDays(it)
	local out = {}
	for _, p in ipairs(X.UnpackPoints(it.d)) do out[p[1]] = p[5] or 1 end
	return out
end

-- plain words for how often the lowest price is cut
function X.UndercutSpeed(perDay, scans, undercuts)
	if perDay == nil then
		return {word = "not known", sub = nil, text = "Not known yet: the item was not scanned or searched in the last 7 days."}
	end
	if (undercuts or 0) == 0 then
		if (scans or 0) < 3 then
			return {word = "not seen yet", sub = nil, text = "No lower price seen yet, but only " .. (scans or 0) ..
				" scan" .. (scans == 1 and "" or "s") .. " in 7 days. Scan more often to know."}
		end
		return {word = "hardly ever", sub = "none in 7 days", text = "Hardly ever: none of your " .. scans ..
			" scans in the last 7 days saw a lower price than the scan before. Prices here stay put."}
	end
	local word, sub
	if perDay < 1 then
		local every = math.max(2, X.Round(1 / perDay))
		word, sub = "slow", "once in " .. every .. " days"
	else
		local hours = 24 / perDay
		if perDay >= 12 then
			word = "very fast"
			sub = "every " .. math.max(1, X.Round(hours * 60)) .. " min"
		else
			word = perDay >= 4 and "fast" or "steady"
			local hh = hours >= 10 and X.Round(hours) or (math.floor(hours * 2 + 0.5) / 2)
			sub = "every " .. (hh == math.floor(hh) and string.format("%d", hh) or string.format("%.1f", hh)) .. " h"
		end
	end
	local text = "About " .. (perDay < 1 and ("once every " .. math.max(2, X.Round(1 / perDay)) .. " days") or
		(string.format("%.1f", perDay):gsub("%.0$", "") .. " times a day")) .. ": " .. undercuts .. " of your " .. (scans or 0) ..
		" scans in the last 7 days saw a lower price than the scan before."
	return {word = word, sub = sub, text = text}
end

function X.SellerStats(key)
	local it = X.Items()[tostring(key)]
	if not it then return {hasSellers = false, speed = X.UndercutSpeed(nil)} end
	local today = X.Day()
	local c = cache[it]
	if c and c.sh == it.sh and c.d == it.d and c.today == today then return c.s end
	local s = {hasSellers = false}
	local hist = X.SellerHistory(key)
	for i = #hist, 1, -1 do
		local p = hist[i]
		if p.sellers then
			s.hasSellers = true
			s.now = s.now or {day = p.day, sellers = p.sellers, topShare = p.topShare, topName = p.topName}
		end
	end
	local seen = seenDays(it)
	local days, scans, cuts = 0, 0, 0
	for d = today - 6, today do
		if seen[d] then days, scans = days + 1, scans + seen[d] end
	end
	for _, p in ipairs(hist) do
		if p.day > today - 7 and p.day <= today then cuts = cuts + (p.undercuts or 0) end
	end
	s.days7, s.scans7, s.undercuts7 = days, scans, cuts
	if days > 0 then s.perDay = cuts / days end
	if scans > 0 then s.share = math.min(1, cuts / scans) end
	s.speed = X.UndercutSpeed(s.perDay, scans, cuts)
	cache[it] = {sh = it.sh, d = it.d, today = today, s = s}
	return s
end

function X.SellerSeries(key, fromDay)
	local sellers, share, cuts = {}, {}, {}
	local it = X.Items()[tostring(key)]
	if not it then return sellers, share, cuts end
	fromDay = fromDay or 0
	local byDay = {}
	for _, p in ipairs(X.SellerHistory(key)) do
		if p.day >= fromDay then
			local t = p.day * DAY + DAY / 2
			if p.sellers then sellers[#sellers + 1] = {t, p.sellers} end
			if p.topShare then share[#share + 1] = {t, p.topShare} end
			byDay[p.day] = p.undercuts or 0
		end
	end
	-- every day the item was seen: its undercuts (0 when none)
	local days = {}
	for d in pairs(seenDays(it)) do if d >= fromDay then days[#days + 1] = d end end
	for d in pairs(byDay) do if not X.Contains(days, d) then days[#days + 1] = d end end
	table.sort(days)
	for _, d in ipairs(days) do cuts[#cuts + 1] = {d * DAY + DAY / 2, byDay[d] or 0} end
	return sellers, share, cuts
end

-- [[ the sellers of the last search, this session ]] the same search results Shape.lua counts (two more listeners on
-- the same events): who sells how many, in how many auctions, and their cheapest price of one.
local live, liveCount = {}, 0
local OTHERS = "(sellers the game does not name)"
X.SELLERS_UNNAMED = OTHERS
local function me()
	-- your name as the game shows it to others ("First Last" on Forever)
	local name = X.CharKey and X.CharKey()
	if name == "?" then return nil end
	return name
end
local function keep(key, list)
	if not key then return end
	local mine = me() or "You"
	local by, total = {}, 0
	local function add(name, units, unit, own, unnamed)
		local e = by[name]
		if not e then e = {name = name, units = 0, auctions = 0, mine = own, unnamed = unnamed} by[name] = e end
		e.units = e.units + units
		e.auctions = e.auctions + 1
		if unit and unit > 0 and (not e.lowest or unit < e.lowest) then e.lowest = unit end
	end
	for _, r in ipairs(list) do
		local q = r.quantity or 1
		local unit = r.unitPrice or r.buyoutAmount
		local owners = type(r.owners) == "table" and r.owners or {}
		local names = {}
		-- the game names your own auctions "player"
		for _, n in ipairs(owners) do
			if type(n) == "string" and n ~= "" then names[#names + 1] = (n == "player") and mine or n end
		end
		if #names == 0 and r.containsOwnerItem then names[1] = mine end
		local others = math.max(0, (r.totalNumberOfOwners or #names) - #names)
		local each = q / math.max(1, #names + others)
		total = total + q
		for _, n in ipairs(names) do add(n, each, unit, n == mine) end
		-- sellers the game does not name: one row for all of them
		if others > 0 then add(OTHERS, each * others, unit, false, true) end
	end
	local rows = {}
	for _, e in pairs(by) do
		e.share = total > 0 and e.units / total or nil
		rows[#rows + 1] = e
	end
	table.sort(rows, function(a, b)
		if (a.unnamed == true) ~= (b.unnamed == true) then return not a.unnamed end
		if a.units ~= b.units then return a.units > b.units end
		return a.name < b.name
	end)
	if not live[key] then liveCount = liveCount + 1 end
	live[key] = {t = X.Now(), rows = rows, units = total}
	-- too many items this session: the oldest go
	if liveCount > MAX_LIVE then
		local oldKey, oldT
		for k, e in pairs(live) do if not oldT or e.t < oldT then oldKey, oldT = k, e.t end end
		if oldKey then live[oldKey] = nil liveCount = liveCount - 1 end
	end
end
X.KeepSellersNow = keep -- for the tests

X.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	if type(itemKey) ~= "table" then return end
	if not X.Try(C_AuctionHouse.HasFullItemSearchResults, itemKey) then return end
	local n = X.Try(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0
	local byKey = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
		if r then
			local key = X.KeyFromLink(r.itemLink) or (X.KeyOfItemKey and X.KeyOfItemKey(r.itemKey or itemKey))
			if key then
				byKey[key] = byKey[key] or {}
				table.insert(byKey[key], r)
			end
		end
	end
	for key, list in pairs(byKey) do keep(key, list) end
	if n == 0 and X.KeyOfItemKey then keep(X.KeyOfItemKey(itemKey), {}) end
end)
X.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not itemID then return end
	if not X.Try(C_AuctionHouse.HasFullCommoditySearchResults, itemID) then return end
	local n = X.Try(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
	local list = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
		if r then list[#list + 1] = r end
	end
	keep(tostring(itemID), list)
end)

function X.SellersNow(key)
	return live[tostring(key)]
end
