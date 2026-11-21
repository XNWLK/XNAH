-- Saved data, price history and the numbers worked out from it.
--
-- XNAHDB = {
--   v = 1, settings = {...},
--   realms = {["Realm-Faction"] = {items = {[key] = item}, scans = {{t, kind, items, auctions, secs}}, lastFull = t}},
--   vsell = {[itemID] = copper}      what a vendor pays for one (the game's sell price, cached for every item seen)
--   vbuy  = {[itemID] = {p = copper per one, lim = true if limited stock, at = t, from = "NPC name"}}
--   recipes = {[recipeID] = see Craft.lua}
--   watch = {[key] = true}          the watch list (starred items)
-- }
-- An item key is the item ID as text ("2589"), or "id:suffix" for an item with a random bonus ("15210:-19", "of the
-- Bear"): those sell for very different prices.
-- item = {id = 2589, n = "Linen Cloth", q = 1, cur = {t, min, mkt, qty, auc}, h = "scan points", d = "day points"}
--   h: one point per scan, kept `keepScanDays` days:  "t,min,mkt,qty,auc;..."  (t in minutes, all numbers in base 36)
--   d: one point per day, kept `keepDays` days:       "day,min,mkt,qty,n;..." (lowest min, average mkt and qty, n scans)
local ADDON, X = ...

X.DEFAULTS = {
	cut = 5,            -- % the auction house keeps of a sale
	source = "mkt",     -- price used for costs and values: min, mkt, avg7, avg30
	keepScanDays = 7,   -- every scan point is kept this long, then only the day's summary
	keepDays = 365,     -- day summaries are kept this long (after 60 days one per week)
	staleHours = 72,    -- a price older than this is shown dimmed and not used for deals
	tooltip = true, tipVendor = true, tipCraft = true, tipHistory = true, tipStack = true,
	dealPct = 60,       -- deals: listed at or under this % of the 30-day average
	dealMinProfit = 1000, -- deals: at least this much profit (copper)
	minSamples = 3,     -- deals and trends need this many days of history
	vendorBuyFirst = true, -- crafting: buy a reagent from a vendor when that is cheaper than the auction house
	debug = false,
	minimap = {angle = 200, hide = false},
	ahBar = true,       -- the little XNAH bar on the auction house window
	scanOnOpen = false, -- start a full scan by itself when the auction house opens (and the server allows one)
}

-- a file of the addon adds its own settings: X.Default("key", value) at load time (before the saved data is read)
function X.Default(key, value)
	if X.DEFAULTS[key] == nil then X.DEFAULTS[key] = value end
	if X.db and X.db.settings[key] == nil then X.db.settings[key] = X.Copy(value) end
end

-- [[ saved data ]]
function X.InitDB()
	XNAHDB = XNAHDB or {}
	local db = XNAHDB
	db.v = db.v or 1
	db.settings = db.settings or {}
	for k, v in pairs(X.DEFAULTS) do
		if db.settings[k] == nil then db.settings[k] = X.Copy(v) end
	end
	db.realms = db.realms or {}
	db.vsell = db.vsell or {}
	db.vbuy = db.vbuy or {}
	db.recipes = db.recipes or {}
	db.watch = db.watch or {}
	-- names saved empty by v0.1.0 (items the game had not loaded): asked for again
	for _, r in pairs(db.realms) do
		for _, it in pairs(r.items or {}) do if it.n == "" then it.n = nil end end
	end
	X.db = db
end
function X.S()
	return X.db.settings
end
-- the auction house is per realm - one for both factions (Xn, 2026-11-21: "horde and alliance are the same auction
-- house. forever is based off of the retail client"). Up to v0.7.1 XNAH kept a set per faction ("Realm 6946-Alliance");
-- X.MigrateRealms joins those into one.
-- On Forever GetRealmName() gives the name of the server SHARD you landed on ("CAMWOW EU5 Realm 4 PvP"), which
-- changes from login to login; the realm itself is the number GetRealmID() gives. So the key is "Realm 6946" (the
-- realm name only where there is no ID).
-- Xn, 2026-11-22: "auction house data gets wiped when i update the addon". It was not wiped: right at login the game
-- sometimes does not know the realm yet (GetRealmID 0, GetRealmName ""), and XNAH filed new scans under a blank realm
-- name ("" / "-Alliance"), so the history looked empty. Now a realm the game does not give yet is never blank: the
-- realm of last time (XNAHDB.lastRealm), else the realm in the saved data with the newest scan; the game is asked again
-- a little later (Core.lua) and anything filed under a guess or a blank name is joined in (X.MigrateRealms).
local function realmID()
	local id = GetRealmID and X.Try(GetRealmID)
	if type(id) == "number" and id > 0 then return id end
	return nil
end
X.RealmID = realmID
-- the "Realm <id>" key in the saved data with the newest full scan (the most items when none has one)
function X.GuessRealmKey()
	local best, bestT, bestN
	for k, r in pairs(X.db and X.db.realms or {}) do
		local id = type(k) == "string" and k:match("^Realm (%d+)")
		if id and type(r) == "table" then
			local t = r.lastFull or 0
			local n = 0
			for _ in pairs(r.items or {}) do n = n + 1 if n > 50 then break end end
			if not best or t > bestT or (t == bestT and n > bestN) then best, bestT, bestN = "Realm " .. id, t, n end
		end
	end
	return best
end
function X.RealmKey()
	local id = realmID()
	if id then return "Realm " .. id, true end
	if X.db and type(X.db.lastRealm) == "string" and X.db.lastRealm ~= "" then return X.db.lastRealm, false end
	local guess = X.GuessRealmKey()
	if guess then return guess, false end
	local name = X.Plain(GetRealmName and GetRealmName())
	if name and name ~= "" then return name, false end
	return "Realm ?", false
end

-- one realm's saved data into another: newest price per item, ledgers and scan lists joined, the rest filled in
local function joinRealm(to, r)
	to.items = to.items or {}
	-- both histories of an item are kept (not just the copy with the newest price: that lost history - Xn, 2026-11-22)
	for k, it in pairs(r.items or {}) do to.items[k] = X.MergeItem(to.items[k], it) end
	to.scans = to.scans or {}
	for _, sc in ipairs(r.scans or {}) do to.scans[#to.scans + 1] = sc end
	table.sort(to.scans, function(x, y) return (x.t or 0) < (y.t or 0) end)
	while #to.scans > 200 do table.remove(to.scans, 1) end
	if r.lastFull and (not to.lastFull or r.lastFull > to.lastFull) then to.lastFull = r.lastFull end
	if r.ledger then
		to.ledger = to.ledger or {}
		for kind, list in pairs(r.ledger) do
			if type(list) == "table" then
				to.ledger[kind] = to.ledger[kind] or {}
				for k2, e in pairs(list) do
					if type(k2) == "number" then table.insert(to.ledger[kind], e) else to.ledger[kind][k2] = e end
				end
				if #to.ledger[kind] > 0 and type(to.ledger[kind][1]) == "table" then
					table.sort(to.ledger[kind], function(x, y) return (x.t or 0) < (y.t or 0) end)
				end
			end
		end
	end
	-- gold notes per day and character (Home), time at the auction house per day (Gold)
	if type(r.homeGold) == "table" then
		to.homeGold = to.homeGold or {}
		for day, chars in pairs(r.homeGold) do
			to.homeGold[day] = to.homeGold[day] or {}
			for c, v in pairs(chars) do if to.homeGold[day][c] == nil then to.homeGold[day][c] = v end end
		end
	end
	if type(r.ahTime) == "table" then
		to.ahTime = to.ahTime or {}
		for day, secs in pairs(r.ahTime) do to.ahTime[day] = (to.ahTime[day] or 0) + secs end
		if r.ahTimeFirst and (not to.ahTimeFirst or r.ahTimeFirst < to.ahTimeFirst) then to.ahTimeFirst = r.ahTimeFirst end
	end
	for field, v in pairs(r) do
		if to[field] == nil then to[field] = v end
	end
end

-- data saved under older keys moves into the realm key: server shard names (v0.3.0 and older) and the per-faction
-- keys "Realm <id>-Alliance" / "Realm <id>-Horde" (up to v0.7.1)
function X.MigrateRealms(key)
	local db = X.db
	local id = key:match("^Realm (%d+)$")
	if not id then return 0 end
	local function old(k)
		if not k or k == key then return false end
		if k:match("^Realm " .. id .. "%-") then return true end -- this realm, one faction
		if k == "Realm ?" or k:find("^Realm %?") then return true end -- filed before the game knew the realm
		return not k:find("^Realm %d") -- a server shard name, or a blank one ("" / "-Alliance": the game did not know)
	end
	local moved, factions = 0, 0
	local olds = {}
	for k in pairs(db.realms) do if old(k) then olds[#olds + 1] = k end end
	table.sort(olds)
	for _, k in ipairs(olds) do
		local r = db.realms[k]
		if db.realms[key] then joinRealm(db.realms[key], r) else db.realms[key] = r end
		db.realms[k] = nil
		if db.worthTotal and db.worthTotal[k] then
			-- net worth over time: the longer history stays (both factions' characters count from now on)
			local have = db.worthTotal[key]
			if not have or #db.worthTotal[k] > #have then db.worthTotal[key] = db.worthTotal[k] end
			db.worthTotal[k] = nil
		end
		moved = moved + 1
		if k:find("^Realm %d") then factions = factions + 1 end
	end
	-- characters (also those of other accounts after Sync accounts) follow
	for _, c in pairs(db.chars or {}) do
		if old(c.realm) then c.realm = key end
	end
	-- told a little after login, so the line is not lost among the login messages
	if moved > 0 then
		local text = factions > 0 and ("Alliance and Horde share one auction house: their prices, sales and characters are " ..
			"now joined under " .. key) or ("price data saved under " .. moved .. " other realm name" .. (moved > 1 and "s" or "") ..
			" (from logins where the game did not know the realm yet) joined under " .. key)
		if C_Timer then X.After(8, function() X.Print(text) end) else X.Print(text) end
	end
	return moved
end
function X.Realm(key)
	key = key or X.realmKey or X.RealmKey()
	local r = X.db.realms[key]
	if not r then
		r = {items = {}, scans = {}}
		X.db.realms[key] = r
	end
	return r
end
function X.Items()
	return X.Realm().items
end

-- [[ item keys ]]
-- key from an item link: "id" or "id:suffix"
function X.KeyFromLink(link)
	if type(link) ~= "string" then return nil end
	local body = link:match("item:([%-%d:]+)")
	if not body then return nil end
	local fields = {}
	for f in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
	local id = tonumber(fields[1])
	if not id then return nil end
	local suffix = tonumber(fields[7] or "")
	if suffix and suffix ~= 0 then return id .. ":" .. suffix end
	return tostring(id)
end
function X.KeyID(key)
	return tonumber((tostring(key):match("^(%-?%d+)")))
end
function X.Item(key, create)
	local items = X.Items()
	local it = items[key]
	if not it and create then
		it = {id = X.KeyID(key)}
		items[key] = it
		if tostring(key):find(":", 1, true) then X.suffixIndex = nil end -- a new random-bonus key
	end
	return it
end
-- quality (rarity) checked with the game this session, per item ID: the full scan gives a wrong quality for items the
-- game had not loaded yet, so the game is asked again once per session
X.qualityOK = {}
function X.CheckQuality(it)
	if not it or not it.id or it.qk or X.qualityOK[it.id] or not C_Item.GetItemQualityByID then return end
	local q = X.Try(C_Item.GetItemQualityByID, it.id)
	if q then it.q, it.qk = q, 1 X.qualityOK[it.id] = true end
end
-- the random-bonus keys of an item ("15210:-19", ...): built in one pass per session, cheap afterwards
function X.SuffixKeys(id)
	if not X.suffixIndex then
		local index = {}
		for key, it in pairs(X.Items()) do
			if it.id and key:find(":", 1, true) then
				index[it.id] = index[it.id] or {}
				table.insert(index[it.id], key)
			end
		end
		X.suffixIndex = index
	end
	return X.suffixIndex[id]
end
-- quality from the colour of an item link (nil if none)
function X.QualityFromLink(link)
	local hex = type(link) == "string" and link:match("|c%x%x(%x%x%x%x%x%x)")
	if not hex then return nil end
	hex = hex:lower()
	for q = 0, 7 do if X.QUALITY_HEX[q] == hex then return q end end
	return nil
end
-- the item's name and quality, from the record or the game
function X.ItemName(key)
	local it = X.Items()[key]
	if it and it.n and it.n ~= "" then
		X.CheckQuality(it)
		return it.n, it.q
	end
	local id = X.KeyID(key)
	local name, _, q = X.Try(C_Item.GetItemInfo, id)
	if name and name ~= "" then
		if it then it.n, it.q = name, q end
		return name, q
	end
	local known = X.RECIPE_ITEMS and id and X.RECIPE_ITEMS[id]
	if known then
		local lq, lname = known:match("^(%d+);(.+)$")
		if lname then return lname, tonumber(lq) or 1 end
	end
	return "item " .. tostring(id), 1
end
function X.ItemText(key)
	local name, q = X.ItemName(key)
	return "|cff" .. (X.QUALITY_HEX[q or 1] or "ffffff") .. name .. "|r"
end
-- the game's vendor sell price (cached, so it is known while the item is not loaded)
function X.VendorSell(id)
	if not id then return nil end
	local v = X.db.vsell[id]
	if v then return v > 0 and v or nil end
	local name, _, _, _, _, _, _, _, _, _, sell = X.Try(C_Item.GetItemInfo, id)
	if name then
		X.db.vsell[id] = sell or 0
		if sell and sell > 0 then return sell end
	end
	return nil
end
function X.VendorBuy(id)
	local v = id and X.db.vbuy[id]
	return v and v.p or nil, v
end

-- [[ number packing ]] base 36 keeps the saved file small
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
	if n == nil then return "" end
	n = math.floor(n + 0.5)
	if n == 0 then return "0" end
	local neg = n < 0
	if neg then n = -n end
	local out = ""
	while n > 0 do
		local r = n % 36
		out = DIGITS:sub(r + 1, r + 1) .. out
		n = (n - r) / 36
	end
	return (neg and "-" or "") .. out
end
local function n36(s)
	if s == nil or s == "" then return nil end
	return tonumber(s, 36)
end
X.b36, X.n36 = b36, n36

local function packPoint(a, b, c, d, e)
	return b36(a) .. "," .. b36(b) .. "," .. b36(c) .. "," .. b36(d) .. "," .. b36(e)
end
-- "a,b,c,d,e;..." -> {{a,b,c,d,e}, ...}
local function unpackPoints(s)
	local out = {}
	if not s or s == "" then return out end
	for p in s:gmatch("[^;]+") do
		local a, b, c, d, e = p:match("^([^,]*),([^,]*),([^,]*),([^,]*),?([^,]*)$")
		if a then out[#out + 1] = {n36(a), n36(b), n36(c), n36(d), n36(e)} end
	end
	return out
end
X.UnpackPoints = unpackPoints

-- first field of the first point (its time / day)
local function firstStamp(s)
	local a = s and s:match("^([^,;]*)")
	return n36(a)
end
-- drops points from the front of s while their first field is below `limit`
local function prune(s, limit)
	while s and s ~= "" do
		local t = firstStamp(s)
		if not t or t >= limit then break end
		local cut = s:find(";", 1, true)
		if not cut then return "" end
		s = s:sub(cut + 1)
	end
	return s
end

-- [[ crazy prices ]] (Xn, 2026-11-19: Solid Stone at 1s 75c had one scan at 1g, which made its usual price 11s 61c and
-- every normal listing look like a bargain.) A price more than outlierFactor (4) times above or below the item's typical
-- price - the middle value (median) of its recent prices - is left out of its history, its averages and its graph.
X.Default("outlierFactor", 4)
local function median(list)
	local n = #list
	if n == 0 then return nil end
	local c = {}
	for i = 1, n do c[i] = list[i] end
	table.sort(c)
	if n % 2 == 1 then return c[(n + 1) / 2] end
	return (c[n / 2] + c[n / 2 + 1]) / 2
end
X.Median = median
-- true when v is far off the typical price m
local function crazy(v, m)
	if not v or not m or m <= 0 or v <= 0 then return false end
	local f = X.S().outlierFactor or 4
	return v > m * f or v < m / f
end
X.CrazyPrice = crazy

-- [[ recording prices ]]
-- one observation of an item: min (lowest price of one), mkt (market value of one), qty (how many listed),
-- auc (number of auctions). full = the whole auction house was seen, so an item that is missing is sold out.
function X.Record(key, t, min, mkt, qty, auc, name, quality)
	local it = X.Item(key, true)
	if name and name ~= "" then it.n = name end
	if quality then it.q = quality end
	if it.cur and it.cur.t and it.cur.t > t then return it end -- an older observation never replaces a newer one
	it.cur = {t = t, min = min, mkt = mkt, qty = qty, auc = auc}
	local S = X.S()
	-- a crazy price (far off the middle of the last scans) stays out of the history - unless 3 scans in a row say so
	local v = mkt or min
	if v and it.h and it.h ~= "" then
		-- only the end of the text: the last scans (a full scan records thousands of items - no full unpacking)
		local tailText = it.h
		if #tailText > 400 then
			tailText = tailText:sub(-400)
			local cut = tailText:find(";", 1, true)
			tailText = cut and tailText:sub(cut + 1) or tailText
		end
		local recent = {}
		local pts = unpackPoints(tailText)
		for i = #pts, math.max(1, #pts - 8), -1 do
			local pv = pts[i][3] or pts[i][2]
			if pv then recent[#recent + 1] = pv end
		end
		if #recent >= 3 and crazy(v, median(recent)) then
			it.ox = (it.ox or 0) + 1
			if it.ox < 3 then
				X.statsCache[it] = nil
				return it
			end
		end
	end
	it.ox = nil
	-- scan point
	local point = packPoint(math.floor(t / 60), min, mkt, qty, auc)
	local h = it.h
	if h and h ~= "" then
		-- a second observation in the same minute replaces the first
		local tail = h:match("[^;]*$")
		if tail and n36(tail:match("^([^,]*)")) == math.floor(t / 60) then
			h = h:sub(1, #h - #tail) .. point
		else
			h = h .. ";" .. point
		end
	else
		h = point
	end
	it.h = prune(h, math.floor((t - S.keepScanDays * 86400) / 60))
	-- day point: lowest min, running average of mkt and qty
	local day = X.Day(t)
	local d = it.d or ""
	local tail = d:match("[^;]*$") or ""
	local last = tail ~= "" and unpackPoints(tail)[1]
	local newTail
	if last and last[1] == day then
		local n = last[5] or 1
		local dmin = (last[2] and min) and math.min(last[2], min) or (last[2] or min)
		local dmkt = (last[3] and mkt) and (last[3] * n + mkt) / (n + 1) or (last[3] or mkt)
		local dqty = (last[4] or 0) * n / (n + 1) + (qty or 0) / (n + 1)
		newTail = packPoint(day, dmin, dmkt, dqty, n + 1)
		d = d:sub(1, #d - #tail) .. newTail
	else
		newTail = packPoint(day, min, mkt, qty, 1)
		d = (d ~= "" and (d .. ";") or "") .. newTail
	end
	it.d = prune(d, day - S.keepDays)
	if (it.cd or 0) < day then X.Thin(it, day) end
	X.statsCache[it] = nil
	return it
end
-- day points older than THIN_AFTER days become one point per week (keeps a year of history small)
local THIN_AFTER = 60
function X.Thin(it, today)
	it.cd = today
	local d = it.d
	if not d or d == "" then return end
	local first = firstStamp(d)
	if not first or first >= today - THIN_AFTER then return end
	local pts = unpackPoints(d)
	local out, week = {}, nil
	for _, p in ipairs(pts) do
		if p[1] >= today - THIN_AFTER then
			out[#out + 1] = p
		else
			local wk = math.floor(p[1] / 7)
			local last = out[#out]
			if week == wk and last then
				local n1, n2 = last[5] or 1, p[5] or 1
				last[2] = (last[2] and p[2]) and math.min(last[2], p[2]) or (last[2] or p[2])
				last[3] = (last[3] and p[3]) and (last[3] * n1 + p[3] * n2) / (n1 + n2) or (last[3] or p[3])
				last[4] = ((last[4] or 0) * n1 + (p[4] or 0) * n2) / (n1 + n2)
				last[5] = n1 + n2
			else
				week = wk
				out[#out + 1] = {wk * 7 + 3, p[2], p[3], p[4], p[5] or 1}
			end
		end
	end
	if #out == #pts then return end
	local parts = {}
	for i, p in ipairs(out) do parts[i] = packPoint(p[1], p[2], p[3], p[4], p[5]) end
	it.d = table.concat(parts, ";")
end
-- two records of one item (two realm keys joined): the newer current price, every scan point (one per minute) and every
-- day point of both (a day in both: the two put together, weighted by how many scans each had). Returns the record.
function X.MergeItem(a, b)
	if not a then return b end
	if not b or a == b then return a end
	local newer = (b.cur and b.cur.t or 0) > (a.cur and a.cur.t or 0)
	if newer then
		a.cur = b.cur
		if b.n and b.n ~= "" then a.n = b.n end
		if b.q then a.q = b.q end
	end
	if not a.n or a.n == "" then a.n = b.n end
	a.q = a.q or b.q
	a.qk = a.qk or b.qk
	a.sfx = a.sfx or b.sfx
	-- scan points
	local byT, ts = {}, {}
	for _, p in ipairs(unpackPoints(a.h)) do if not byT[p[1]] then ts[#ts + 1] = p[1] end byT[p[1]] = p end
	for _, p in ipairs(unpackPoints(b.h)) do
		if not byT[p[1]] then ts[#ts + 1] = p[1] byT[p[1]] = p elseif newer then byT[p[1]] = p end
	end
	table.sort(ts)
	local parts = {}
	for i, t in ipairs(ts) do local p = byT[t] parts[i] = packPoint(p[1], p[2], p[3], p[4], p[5]) end
	a.h = #parts > 0 and table.concat(parts, ";") or nil
	-- day points
	local byD, ds = {}, {}
	for _, p in ipairs(unpackPoints(a.d)) do if not byD[p[1]] then ds[#ds + 1] = p[1] end byD[p[1]] = p end
	for _, p in ipairs(unpackPoints(b.d)) do
		local q = byD[p[1]]
		if not q then
			ds[#ds + 1] = p[1]
			byD[p[1]] = p
		elseif not (q[2] == p[2] and q[3] == p[3] and q[4] == p[4]) then -- the same day saved twice (synced copies) stays as it is
			local n1, n2 = q[5] or 1, p[5] or 1
			q[2] = (q[2] and p[2]) and math.min(q[2], p[2]) or (q[2] or p[2])
			q[3] = (q[3] and p[3]) and (q[3] * n1 + p[3] * n2) / (n1 + n2) or (q[3] or p[3])
			q[4] = ((q[4] or 0) * n1 + (p[4] or 0) * n2) / (n1 + n2)
			q[5] = n1 + n2
		end
	end
	table.sort(ds)
	parts = {}
	for i, d in ipairs(ds) do local p = byD[d] parts[i] = packPoint(p[1], p[2], p[3], p[4], p[5]) end
	a.d = #parts > 0 and table.concat(parts, ";") or nil
	a.cd, a.ox = nil, nil
	if X.statsCache then X.statsCache[a] = nil end
	return a
end

-- after a full scan: every known item that was not seen is sold out (quantity 0) - the history shows the gap
function X.RecordGone(key, t)
	local it = X.Items()[key]
	if not it or not it.cur or it.cur.t >= t then return end
	if (it.cur.qty or 0) == 0 then
		it.cur.t = t
		return
	end
	X.Record(key, t, nil, nil, 0, 0)
end

-- [[ market value ]] from the listings of one item: list = {{unit price, count}, ...} (buyouts only)
-- min = lowest price of one. Market value = the average of the cheapest part of the market: the cheapest 15% of all
-- units always count, more up to 30% while the price does not jump (over 20% above the one before); then units more
-- than 1.5 standard deviations off that average are dropped and the rest averaged again. One cheap or silly listing
-- moves it little, a wall of units at one price moves it a lot - like a buyer working through the cheapest offers.
function X.MarketValue(list)
	if not list or #list == 0 then return nil end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	local total = 0
	for i = 1, #list do total = total + list[i][2] end
	if total <= 0 then return nil end
	-- at least 3 units (when there are that many), so one odd listing alone never is the market
	local lo, hi = math.max(math.min(3, total), total * 0.15), math.max(math.min(3, total), total * 0.30)
	local taken, n, prev = {}, 0, nil
	for i = 1, #list do
		local price, count = list[i][1], list[i][2]
		if n >= lo and (n >= hi or (prev and price > prev * 1.2)) then break end
		-- never more than up to the 30% mark (a huge listing counts only in part)
		local take = math.min(count, math.max(1, math.ceil(hi - n)))
		taken[#taken + 1] = {price, take}
		n = n + take
		prev = price
	end
	-- units under half the middle price of those taken are dropped (a listing at a silly low price)
	local median, c = taken[#taken][1], 0
	for _, u in ipairs(taken) do
		c = c + u[2]
		if c >= n / 2 then median = u[1] break end
	end
	local used, sum = {}, 0
	n = 0
	for _, u in ipairs(taken) do
		if u[1] >= median * 0.5 then used[#used + 1] = u n = n + u[2] sum = sum + u[1] * u[2] end
	end
	local mean = sum / n
	local var = 0
	for _, u in ipairs(used) do var = var + (u[1] - mean) ^ 2 * u[2] end
	local sd = math.sqrt(var / n)
	local s2, n2 = 0, 0
	for _, u in ipairs(used) do
		if math.abs(u[1] - mean) <= 1.5 * sd + 0.5 then s2 = s2 + u[1] * u[2] n2 = n2 + u[2] end
	end
	local mkt = n2 > 0 and s2 / n2 or mean
	return list[1][1], X.Round(mkt), total, #list
end

-- [[ numbers from the history ]] cached per item until its next observation
-- stats = {avg3, avg7, avg14, avg30, low30, high30, trend (% per week), vol (% day to day spread), qty7 (average
-- listed), supply (% now vs qty7), days (days with data), first (oldest day)}
local function regression(xs, ys)
	local n = #xs
	if n < 2 then return nil end
	local sx, sy, sxx, sxy = 0, 0, 0, 0
	for i = 1, n do sx = sx + xs[i] sy = sy + ys[i] sxx = sxx + xs[i] * xs[i] sxy = sxy + xs[i] * ys[i] end
	local den = n * sxx - sx * sx
	if den == 0 then return nil end
	return (n * sxy - sx * sy) / den, sy / n
end
-- the numbers are kept outside the saved data (weak keys) and worked out again on a new day or a new observation
X.statsCache = setmetatable({}, {__mode = "k"})
function X.Stats(key)
	local it = type(key) == "table" and key or X.Items()[key]
	if not it then return nil end
	local today = X.Day()
	local cached = X.statsCache[it]
	if cached and cached.today == today then return cached end
	local days = unpackPoints(it.d)
	-- the typical price: the middle of the last 30 days and the price now; day prices far off it are left out
	local vals = {}
	for i = #days, 1, -1 do
		local p = days[i]
		if p[1] <= today - 30 then break end
		local v = p[3] or p[2]
		if v then vals[#vals + 1] = v end
	end
	if it.cur and (it.cur.mkt or it.cur.min) then vals[#vals + 1] = it.cur.mkt or it.cur.min end
	local typical = #vals >= 3 and median(vals) or nil
	local dropped = 0
	if typical then
		local kept = {}
		for _, p in ipairs(days) do
			if crazy(p[3] or p[2], typical) then dropped = dropped + 1 else kept[#kept + 1] = p end
		end
		days = kept
	end
	local s = {days = #days, first = days[1] and days[1][1], today = today, typical = typical, dropped = dropped}
	local function avg(n)
		local sum, c = 0, 0
		for i = #days, 1, -1 do
			local p = days[i]
			if p[1] <= today - n then break end
			local v = p[3] or p[2]
			if v then sum = sum + v c = c + 1 end
		end
		return c > 0 and sum / c or nil
	end
	s.avg3, s.avg7, s.avg14, s.avg30 = avg(3), avg(7), avg(14), avg(30)
	local xs, ys, qs, all = {}, {}, {}, {}
	for i = #days, 1, -1 do
		local p = days[i]
		if p[1] <= today - 30 then break end
		local v = p[3] or p[2]
		if v then
			all[#all + 1] = v
			if not s.low30 or v < s.low30 then s.low30 = v end
			if not s.high30 or v > s.high30 then s.high30 = v end
			if p[1] > today - 14 then xs[#xs + 1] = p[1] ys[#ys + 1] = v end
		end
		if p[1] > today - 7 and p[4] then qs[#qs + 1] = p[4] end
	end
	-- trend: straight line through the last 14 days, as % per week of the average
	if #xs >= 3 then
		local slope, mean = regression(xs, ys)
		if slope and mean and mean > 0 then s.trend = slope * 7 / mean * 100 end
	end
	-- spread: how much the price moves from day to day (standard deviation / average, %)
	if #ys >= 3 then
		local m = 0
		for i = 1, #ys do m = m + ys[i] end
		m = m / #ys
		local v = 0
		for i = 1, #ys do v = v + (ys[i] - m) ^ 2 end
		if m > 0 then s.vol = math.sqrt(v / #ys) / m * 100 end
	end
	if #qs > 0 then
		local q = 0
		for i = 1, #qs do q = q + qs[i] end
		s.qty7 = q / #qs
		if s.qty7 > 0 and it.cur and it.cur.qty then s.supply = (it.cur.qty / s.qty7 - 1) * 100 end
	end
	X.statsCache[it] = s
	return s
end
-- is the latest price fresh enough to act on?
function X.Fresh(it)
	return it and it.cur and it.cur.t and (X.Now() - it.cur.t) < X.S().staleHours * 3600
end

-- [[ prices ]] X.Price(key, source) - one item, copper; nil when unknown
-- sources: min, mkt, avg3, avg7, avg30, vsell (vendor pays), vbuy (vendor sells), craft (cost to make), best (mkt, else
-- avg7, else min)
X.SOURCES = {"mkt", "min", "avg3", "avg7", "avg30"}
X.SOURCE_NAMES = {min = "Lowest price", mkt = "Market value", avg3 = "3-day average", avg7 = "7-day average",
	avg30 = "30-day average", vsell = "Vendor sell", vbuy = "Vendor buy", craft = "Crafting cost"}
function X.Price(key, source)
	source = source or X.S().source
	local id = X.KeyID(key)
	if source == "vsell" then return X.VendorSell(id) end
	if source == "vbuy" then return (X.VendorBuy(id)) end
	if source == "craft" then return X.CraftCost and X.CraftCost(id) or nil end
	local it = X.Items()[tostring(key)]
	if not it then return nil end
	if source == "min" or source == "mkt" then
		local cur = it.cur
		if not cur then return nil end
		local v = cur[source]
		if v == nil and source == "mkt" then v = cur.min end
		if v == nil and cur.qty == 0 then -- sold out right now: the last known value
			local st = X.Stats(it)
			v = st.avg3 or st.avg7
		end
		return v
	end
	local st = X.Stats(it)
	if source == "best" then return (it.cur and (it.cur.mkt or it.cur.min)) or st.avg7 or st.avg30 end
	return st[source]
end
-- what selling one on the auction house brings after the cut
function X.AfterCut(copper)
	if not copper then return nil end
	return copper * (1 - X.S().cut / 100)
end

-- [[ history for graphs ]] points {t (seconds), min, mkt, qty} from `from` (seconds) on; scan points where they are
-- kept, day points (at noon) before that
function X.History(key, from, raw)
	local it = X.Items()[key]
	if not it then return {} end
	local out = X.HistoryRaw(it, from)
	if raw or #out < 3 then return out end
	-- crazy prices left out: the typical price is the middle of each day's middle price (a day with many scans counts
	-- once, like a day with one) and the price now
	local byDay, order = {}, {}
	for _, p in ipairs(out) do
		local v = p[3] or p[2]
		if v then
			local d = math.floor(p[1] / 86400)
			if not byDay[d] then byDay[d] = {} order[#order + 1] = d end
			table.insert(byDay[d], v)
		end
	end
	local vals = {}
	for _, d in ipairs(order) do vals[#vals + 1] = median(byDay[d]) end
	if it.cur and (it.cur.mkt or it.cur.min) then vals[#vals + 1] = it.cur.mkt or it.cur.min end
	local m = median(vals)
	local kept = {}
	for _, p in ipairs(out) do if not crazy(p[3] or p[2], m) then kept[#kept + 1] = p end end
	return kept
end
function X.HistoryRaw(it, from)
	local out = {}
	local scans = unpackPoints(it.h)
	local firstScan = scans[1] and scans[1][1] * 60 or math.huge
	for _, p in ipairs(unpackPoints(it.d)) do
		local t = p[1] * 86400 + 43200
		if t >= (from or 0) and t < firstScan - 43200 then out[#out + 1] = {t, p[2], p[3], p[4]} end
	end
	for _, p in ipairs(scans) do
		local t = p[1] * 60
		if t >= (from or 0) then out[#out + 1] = {t, p[2], p[3], p[4]} end
	end
	return out
end

-- [[ items never to suggest ]] XNAHDB.ignore[key] = true (right-click an item: Never suggest buying this). Xn: grey
-- junk gets listed at silly prices and then looks like a bargain. Buy ideas (strategies, deals, the Buy page) leave
-- these out, and grey items too (their only real value is what a vendor pays).
function X.Ignored(key)
	return X.db.ignore ~= nil and X.db.ignore[tostring(key)] == true
end
function X.SetIgnored(key, on)
	X.db.ignore = X.db.ignore or {}
	X.db.ignore[tostring(key)] = on and true or nil
	X.Fire("XNAH_IGNORE")
	if X.StrategyUpdate then X.StrategyUpdate() end
end
function X.IgnoredList()
	local out = {}
	for key in pairs(X.db.ignore or {}) do out[#out + 1] = key end
	table.sort(out, function(a, b) return X.ItemName(a) < X.ItemName(b) end)
	return out
end
-- may XNAH suggest buying this to sell again?
function X.BuyIdea(key, it)
	if X.Ignored(key) then return false end
	it = it or X.Items()[tostring(key)]
	if it and it.q == 0 then return false end
	return true
end

-- [[ watch list ]] XNAHDB.watch[key] = true, or {max = copper} with a highest price to buy at (sniper alerts)
function X.Watched(key)
	return X.db.watch[key] ~= nil
end
function X.SetWatched(key, on)
	if on then X.db.watch[key] = X.db.watch[key] or true else X.db.watch[key] = nil end
	X.Fire("XNAH_WATCH")
end
function X.WatchMax(key)
	local w = X.db.watch[key]
	return type(w) == "table" and w.max or nil
end
-- copper, or nil to remove the price (the item stays watched)
function X.SetWatchMax(key, copper)
	if copper and copper > 0 then X.db.watch[key] = {max = copper} else X.db.watch[key] = true end
	X.Fire("XNAH_WATCH")
end

-- [[ searching the known items ]] by name (any part, any case); returns keys
-- exact names first, then names that start with the text, then the rest (each group by name)
function X.Find(text, limit)
	text = X.Trim(text or ""):lower()
	local hits = {}
	for key, it in pairs(X.Items()) do
		local name = it.n and it.n:lower()
		if text == "" or (name and name:find(text, 1, true)) or key == text then
			local rank = (key == text or name == text) and 1 or (name and name:sub(1, #text) == text) and 2 or 3
			hits[#hits + 1] = {key, rank, name or ""}
		end
	end
	table.sort(hits, function(a, b)
		if a[2] ~= b[2] then return a[2] < b[2] end
		if a[3] ~= b[3] then return a[3] < b[3] end
		return a[1] < b[1]
	end)
	local out = {}
	for i = 1, math.min(#hits, limit or #hits) do out[i] = hits[i][1] end
	return out
end

-- [[ size of the saved data ]] rough, for the settings page
function X.DataSize()
	local items, bytes = 0, 0
	for _, r in pairs(X.db.realms) do
		for _, it in pairs(r.items) do
			items = items + 1
			bytes = bytes + #(it.h or "") + #(it.d or "") + 60
		end
	end
	return items, bytes
end
