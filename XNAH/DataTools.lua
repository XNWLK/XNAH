-- Your data (the window is UIData.lua): how big and how old XNAH's saved data is, slimming it down, and plain text
-- exports that paste straight into a spreadsheet.
--
-- Data health (X.DataHealth): one walk over everything saved, a little per frame (at most ITEM_SLICE items or about
-- 12 ms a frame): the size of each part as the game writes it into the saved file (rough: the game's own text format
-- is counted, not the memory), the items with the most data, how many items were not seen for 30 / 60 / 90 / 180 days
-- and what "Slim down" would remove for each choice. Kept until asked again (or after a slim down).
--
-- Seen = the last time the item was LISTED (a price seen): its current price when it is listed now, else the last day
-- of its history with a price. (A full scan marks every unseen known item as sold out and touches its record, so the
-- record's own time is not "seen".) An item never seen with a price counts as never seen.
--
-- Slim down (X.DataSlim): removes the items of this realm not seen for N days, a little per frame. Never removed:
-- tracked items, items in Compare lists (the picked item and the items compared with it), items in your ledger
-- (sales, buys, expired, cancelled, your postings; also entries saved by name only), items your characters on this realm
-- or the account bank have, and the item shown on the Items view right now. With an item go its sales speed and market
-- shape lines; the caches made from it are forgotten (Trends starts over, the random-bonus index is made again).
-- The game writes the saved file only at /reload or logout, so the file gets smaller then.
--
-- Exports (X.Export): text with columns split by tabs and a header row; prices as plain gold numbers ("12.3456").
-- Built a little per frame; at most X.EXPORT_MAX characters (a text box with megabytes of text freezes the game): when
-- there is more, the NEWEST rows are kept and res.cut is set.
local ADDON, X = ...

local DAY = 86400
local BUDGET_MS = 12
local ITEM_SLICE = 500   -- items per frame at most (health and slim down)
local WALK_SLICE = 4000  -- other saved values per frame at most
local LINE_SLICE = 800   -- export lines per frame at most
local clock = debugprofilestop or function() return 0 end

X.SLIM_DAYS = {30, 60, 90, 180, 365}
X.UNSEEN_DAYS = {30, 60, 90, 180}
X.EXPORT_MAX = 100000
X.Default("dataSlimDays", 90)
X.Default("dataExport", "history")
X.Default("dataRange", 90) -- days (0 = all)

-- [[ sizes ]] as the game writes the saved file: ["key"] = value,\n  (strings in quotes, tables in { })
local function sizeOf(v)
	local t = type(v)
	if t == "string" then return #v + 2 end
	if t == "number" then return #tostring(v) end
	if t == "boolean" then return v and 4 or 5 end
	if t == "table" then
		local n = 3
		for k, x in pairs(v) do n = n + sizeOf(k) + sizeOf(x) + 7 end
		return n
	end
	return 0
end
X.DataSizeOf = sizeOf
-- one item in the items list: its whole size, and the parts (price history, patterns, seller history)
local function itemBytes(key, it)
	return sizeOf(key) + 7 + sizeOf(it)
end
local function strPart(s) return s and (#s + 12) or 0 end -- ["h"] = "...",\n

-- "123 bytes", "45 KB", "6.1 MB"
function X.SizeText(bytes)
	bytes = bytes or 0
	if bytes < 1024 then return X.Num(bytes) .. " bytes" end
	if bytes < 1024 * 1024 then return X.Num(bytes / 1024) .. " KB" end
	return string.format("%.1f MB", bytes / (1024 * 1024))
end

-- [[ when an item was last seen listed ]] seconds, or nil when never seen with a price
local function lastListed(it)
	local cur = it.cur
	if cur and cur.t and (cur.min or cur.mkt) and (cur.qty == nil or cur.qty > 0) then return cur.t end
	local s = it.d
	while s and s ~= "" do
		local tail = s:match("[^;]*$") or ""
		local day, mn, mk = tail:match("^([^,]*),([^,]*),([^,]*)")
		if (mn and mn ~= "") or (mk and mk ~= "") then
			local d = X.n36(day)
			if d then return d * DAY + DAY / 2 end
		end
		if #tail >= #s then break end
		s = s:sub(1, #s - #tail - 1)
	end
	if cur and cur.t and (cur.min or cur.mkt) then return cur.t end
	return nil
end
X.DataLastSeen = lastListed

-- [[ items never removed ]] -> {keys = {[key] = why}, names = {[lower-case name] = true}}
function X.DataKeep()
	local keys, names = {}, {}
	for key in pairs(X.db.watch or {}) do keys[tostring(key)] = "tracked" end
	local lists = X.S().compareLists
	if type(lists) == "table" then
		for key, e in pairs(lists) do
			keys[tostring(key)] = keys[tostring(key)] or "compared"
			if type(e) == "table" and type(e.k) == "table" then
				for _, k in ipairs(e.k) do keys[tostring(k)] = keys[tostring(k)] or "compared" end
			end
		end
	end
	local L = X.Realm().ledger
	if type(L) == "table" then
		for _, kind in ipairs({"sales", "buys", "expired", "cancelled"}) do
			for _, e in ipairs(L[kind] or {}) do
				if e.key then keys[tostring(e.key)] = keys[tostring(e.key)] or "traded"
				elseif type(e.name) == "string" then names[e.name:lower()] = true end
			end
		end
		for _, p in ipairs(L.posts or {}) do
			if p.k then keys[tostring(p.k)] = keys[tostring(p.k)] or "traded" end
		end
	end
	-- what your characters on this realm (and the account bank) have
	local rk = X.realmKey or X.RealmKey()
	local function own(list)
		if type(list) ~= "table" then return end
		for key in pairs(list) do keys[tostring(key)] = keys[tostring(key)] or "owned" end
	end
	for _, c in pairs(X.db.chars or {}) do
		if type(c) == "table" and c.realm == rk then own(c.bags) own(c.bank) own(c.mail) own(c.auctions) end
	end
	if type(X.db.warbank) == "table" then own(X.db.warbank.items) end
	if X.UI and X.UI.itemKey then keys[tostring(X.UI.itemKey)] = keys[tostring(X.UI.itemKey)] or "shown" end
	return {keys = keys, names = names}
end
local function kept(keep, key, it)
	if keep.keys[key] then return true end
	return type(it.n) == "string" and keep.names[it.n:lower()] == true
end

-- [[ the parts of the saved data ]] (order = the order in the window)
X.DATA_PARTS = {
	{"prices", "Prices now (one record per item)"},
	{"history", "Price history"},
	{"patterns", "Weekday and time-of-day patterns"},
	{"sellers", "Seller history"},
	{"ledger", "Your sales and buys"},
	{"gold", "Gold history and net worth"},
	{"speed", "Sales speed and market shape"},
	{"scans", "List of scans"},
	{"recipes", "Recipes"},
	{"vendor", "Vendor prices"},
	{"chars", "Your characters' bags, bank and mail"},
	{"otherRealms", "Other realms"},
	{"other", "Settings, lists and the rest"},
}
local REALM_PART = {scans = "scans", ledger = "ledger", goldHist = "gold", homeGold = "gold", speed = "speed",
	hours = "speed", hoursSeen = "speed", speedLast = "speed", shape = "speed"}
local DB_PART = {vsell = "vendor", vbuy = "vendor", recipes = "recipes", known = "recipes", chars = "chars",
	warbank = "chars", worth = "gold", worthTotal = "gold"}

-- a walk over saved tables, a few values per call (the tables' keys are listed once, so a change between frames
-- never breaks it)
local function walker(add)
	local w = {stack = {}, seen = {}}
	function w.push(t, part)
		if w.seen[t] then return end
		w.seen[t] = true
		local keys = {}
		for k in pairs(t) do keys[#keys + 1] = k end
		w.stack[#w.stack + 1] = {t = t, keys = keys, i = 0, part = part}
	end
	-- true when nothing is left
	function w.step(n)
		while n > 0 do
			local top = w.stack[#w.stack]
			if not top then return true end
			top.i = top.i + 1
			local k = top.keys[top.i]
			if k == nil then
				w.stack[#w.stack] = nil
				add(top.part, 3)
			else
				local v = top.t[k]
				if v ~= nil then
					add(top.part, sizeOf(k) + 7)
					if type(v) == "table" then w.push(v, top.part) else add(top.part, sizeOf(v)) end
				end
			end
			n = n - 1
		end
		return #w.stack == 0
	end
	return w
end

local function countDays(d)
	if not d or d == "" then return 0 end
	return select(2, d:gsub(";", "")) + 1
end

-- [[ data health ]] X.DataHealthBuilder() -> B: B.step() true when done, B.result, B.progress
--   result = {t, realm, items, scans, fullScans, lastFull, lastTracked, sales, buys, total (bytes of the whole saved
--   file, about), parts = {{key, name, bytes}}, top = {{key, bytes, days}} (biggest first, 10), unseen = {[days] = n},
--   never (items never seen with a price), slim = {[days] = {n, bytes, kept}}, keptAll (items kept by the rules)}
function X.DataHealthBuilder()
	local db, r = X.db, X.Realm()
	local items = r.items
	local now = X.Now()
	local keep = X.DataKeep()
	local bytes = {}
	local function add(part, n) bytes[part] = (bytes[part] or 0) + n end
	local res = {t = now, realm = X.realmKey or X.RealmKey(), items = 0, top = {}, unseen = {}, slim = {}, never = 0, keptAll = 0}
	for _, d in ipairs(X.UNSEEN_DAYS) do res.unseen[d] = 0 end
	for _, d in ipairs(X.SLIM_DAYS) do res.slim[d] = {n = 0, bytes = 0, kept = 0} end
	-- scans and the ledger: counted at once (short lists)
	local scans = r.scans or {}
	res.scans, res.fullScans = #scans, 0
	for i = #scans, 1, -1 do
		local sc = scans[i]
		if sc.kind == "full" then
			res.fullScans = res.fullScans + 1
			if not res.lastFullScan then res.lastFullScan = sc end
		elseif sc.kind == "tracked items" and not res.lastTracked then
			res.lastTracked = sc.t
		end
	end
	res.lastFull = r.lastFull or (res.lastFullScan and res.lastFullScan.t)
	local L = r.ledger or {}
	res.sales, res.buys = #(L.sales or {}), #(L.buys or {})
	local keys = {}
	for k in pairs(items) do keys[#keys + 1] = k end
	local B = {i = 0, phase = 1, progress = "Looking through the items: 0 / " .. X.Num(#keys)}
	local w = walker(add)
	local function top(key, n)
		local list = res.top
		if #list >= 10 and n <= list[#list].bytes then return end
		local pos = #list + 1
		while pos > 1 and list[pos - 1].bytes < n do pos = pos - 1 end
		table.insert(list, pos, {key = key, bytes = n})
		if #list > 10 then list[#list] = nil end
	end
	local function oneItem(key, it)
		local all = itemBytes(key, it)
		local hist, pat, sel = strPart(it.h) + strPart(it.d), strPart(it.pw), strPart(it.sh)
		add("history", hist)
		add("patterns", pat)
		add("sellers", sel)
		add("prices", all - hist - pat - sel)
		res.items = res.items + 1
		top(key, all)
		local seen = lastListed(it)
		local age = seen and (now - seen) or math.huge
		if not seen then res.never = res.never + 1 end
		for _, d in ipairs(X.UNSEEN_DAYS) do if age >= d * DAY then res.unseen[d] = res.unseen[d] + 1 end end
		local isKept = kept(keep, key, it)
		if isKept then res.keptAll = res.keptAll + 1 end
		for _, d in ipairs(X.SLIM_DAYS) do
			if age >= d * DAY then
				local s = res.slim[d]
				if isKept then s.kept = s.kept + 1 else s.n, s.bytes = s.n + 1, s.bytes + all end
			end
		end
	end
	-- the other parts of this realm, the rest of the saved data, the other realms
	local function queueRest()
		for field, v in pairs(r) do
			if field ~= "items" then
				local part = REALM_PART[field] or "other"
				add(part, sizeOf(field) + 7)
				if type(v) == "table" then w.push(v, part) else add(part, sizeOf(v)) end
			end
		end
		add("other", 20) -- the realm's key and braces
		for field, v in pairs(db) do
			if field == "realms" then
				for rk, other in pairs(v) do
					if other ~= r then
						add("otherRealms", sizeOf(rk) + 7)
						if type(other) == "table" then w.push(other, "otherRealms") end
					end
				end
			else
				local part = DB_PART[field] or "other"
				add(part, sizeOf(field) + 7)
				if type(v) == "table" then w.push(v, part) else add(part, sizeOf(v)) end
			end
		end
		add("other", 14) -- "XNAHDB = {", "}"
	end
	function B.step()
		if X.Items() ~= items then B.stopped = true return true end
		local t0 = clock()
		if B.phase == 1 then
			local stop = math.min(#keys, B.i + ITEM_SLICE)
			while B.i < stop do
				B.i = B.i + 1
				local key = keys[B.i]
				local it = items[key]
				if type(it) == "table" then oneItem(key, it) end
				if clock() - t0 > BUDGET_MS then break end
			end
			B.progress = "Looking through the items: " .. X.Num(B.i) .. " / " .. X.Num(#keys)
			if B.i >= #keys then
				B.phase = 2
				queueRest()
				B.progress = "Measuring the rest of the saved data"
			end
			return false
		end
		if not w.step(WALK_SLICE) then return false end
		-- done
		local total = 0
		res.parts = {}
		for _, p in ipairs(X.DATA_PARTS) do
			local n = bytes[p[1]] or 0
			total = total + n
			res.parts[#res.parts + 1] = {key = p[1], name = p[2], bytes = n}
		end
		res.total = total
		for _, e in ipairs(res.top) do
			local it = items[e.key]
			e.days = it and countDays(it.d) or 0
		end
		B.result = res
		return true
	end
	return B
end
-- all at once (tests)
function X.DataHealthRun()
	local B = X.DataHealthBuilder()
	while not B.step() do end
	return B.result
end

-- X.DataHealth(again) -> result (or the last one), busy, progress text. Works it out a little per frame; fires
-- XNAH_DATA when done. again = true: start over (a result older than the realm's items is never shown).
local health = {}
function X.DataHealth(again)
	if health.running then return health.items == X.Items() and health.res or nil, true, health.B and health.B.progress end
	if health.res and health.items == X.Items() and not again then return health.res, false, nil end
	health.running = true
	local B = X.DataHealthBuilder()
	health.B = B
	local items = X.Items()
	X.Job("data health", function() return B.step() end, function()
		health.running = false
		if B.result then health.res, health.items = B.result, items end
		X.Fire("XNAH_DATA")
	end)
	return health.items == items and health.res or nil, true, B.progress
end
function X.DataHealthForget() health.res = nil end
function X.DataHealthBusy() return health.running == true end

-- [[ slim down ]] one item and everything saved under its key go
function X.DataForget(r, key)
	r = r or X.Realm()
	r.items[key] = nil
	if type(r.speed) == "table" then r.speed[key] = nil end
	if type(r.shape) == "table" then r.shape[key] = nil end
end
-- the caches made from the items (after items were removed)
local function forgetCaches()
	X.suffixIndex = nil
	if X.TrendsForget then X.TrendsForget() end
	if X.LedgerForget then X.LedgerForget() end
	health.res = nil
end
-- X.DataSlimBuilder(days) -> B: B.step() true when done; B.removed, B.bytes (about), B.stopped (the realm changed)
function X.DataSlimBuilder(days)
	local r = X.Realm()
	local items = r.items
	local keep = X.DataKeep()
	local limit = X.Now() - days * DAY
	local keys = {}
	for k in pairs(items) do keys[#keys + 1] = k end
	local B = {i = 0, removed = 0, bytes = 0, total = #keys, days = days}
	function B.step()
		if X.Items() ~= items then
			B.stopped = true
			if B.removed > 0 then forgetCaches() end
			return true
		end
		local t0 = clock()
		local stop = math.min(#keys, B.i + ITEM_SLICE)
		while B.i < stop do
			B.i = B.i + 1
			local key = keys[B.i]
			local it = items[key]
			if type(it) == "table" and not kept(keep, key, it) and (lastListed(it) or 0) <= limit then
				B.bytes = B.bytes + itemBytes(key, it)
				X.DataForget(r, key)
				B.removed = B.removed + 1
			end
			if clock() - t0 > BUDGET_MS then break end
		end
		if B.i < #keys then return false end
		if B.removed > 0 then forgetCaches() end
		return true
	end
	return B
end
-- all at once (tests): removed, bytes
function X.DataSlimRun(days)
	local B = X.DataSlimBuilder(days)
	while not B.step() do end
	if B.removed > 0 then X.Fire("XNAH_PRICES") end
	return B.removed, B.bytes
end
-- sliced; done(B) when finished. Refused (false, why) while a scan runs or a slim down is running.
local slimming
function X.DataSlim(days, done)
	if slimming then return false, "busy" end
	if X.scan and X.scan.state and X.scan.state ~= "idle" then return false, "scan" end
	local B = X.DataSlimBuilder(days)
	slimming = B
	X.Job("slim down", function() return B.step() end, function()
		slimming = nil
		if B.removed > 0 then X.Fire("XNAH_PRICES") end
		X.Fire("XNAH_DATA")
		if done then done(B) end
	end)
	return true, B
end
function X.DataSlimming() return slimming end

-- [[ exports ]]
X.EXPORTS = {
	{key = "history", title = "Price history of one item", item = true, range = true},
	{key = "ledger", title = "Your sales and buys", range = true},
	{key = "gold", title = "Gold of each character", range = true},
	{key = "tracked", title = "Tracked items now"},
}
X.EXPORT_RANGES = {{"Last 30 days", 30}, {"Last 90 days", 90}, {"All", 0}}
function X.ExportSpec(kind)
	for _, e in ipairs(X.EXPORTS) do if e.key == kind then return e end end
	return nil
end

-- copper -> "12.3456" (gold, plain number); nil -> ""
local function gold(c)
	if type(c) ~= "number" then return "" end
	return string.format("%.4f", c / 10000)
end
X.ExportGold = gold
local function clean(s)
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[\t\r\n]", " "))
end
local function day(d) return date("%Y-%m-%d", d * DAY + DAY / 2) end
local function num(n) return type(n) == "number" and tostring(X.Round(n)) or "" end

-- each maker: opts -> {header, list (newest first unless keepOrder), format(entry) -> line, note}
local makers = {}
-- the day points of one item: date, lowest price, usual price (the day's market value), quantity listed, scans; after
-- 60 days the history keeps one point per week ("Week")
function makers.history(opts)
	local spec = {header = "Date\tLowest price (gold)\tUsual price (gold)\tQuantity listed\tScans\tCovers", list = {}}
	local key = opts.key and tostring(opts.key)
	local it = key and X.Items()[key]
	if not it then spec.note = key and "noitem" or "pick" return spec end
	local today = X.Day()
	local from = (opts.days or 0) > 0 and (today - opts.days + 1) or nil
	local weekBefore = (it.cd or today) - 60
	local pts = X.UnpackPoints(it.d)
	for i = #pts, 1, -1 do
		local p = pts[i]
		if from and p[1] < from then break end
		spec.list[#spec.list + 1] = p
	end
	spec.format = function(p)
		return day(p[1]) .. "\t" .. gold(p[2]) .. "\t" .. gold(p[3]) .. "\t" .. num(p[4]) .. "\t" .. num(p[5]) .. "\t" ..
			(p[1] < weekBefore and "Week" or "Day")
	end
	spec.name = X.ItemName(key)
	return spec
end
-- sales and buys: profit of a sale = what it brought after the cut minus the units at your average buying price of the
-- item (units you never bought, farmed or crafted, cost nothing - as on the Your gold pages)
function makers.ledger(opts)
	local spec = {header = "Date\tWhat\tItem\tQuantity\tPrice each (gold)\tTotal (gold)\tAuction house cut (gold)\t" ..
		"Profit (gold)\tCharacter", list = {}}
	local L = X.Ledger()
	local from = (opts.days or 0) > 0 and (X.Now() - opts.days * DAY) or nil
	for _, kind in ipairs({"sales", "buys"}) do
		for _, e in ipairs(L[kind] or {}) do
			if not from or (e.t or 0) >= from then spec.list[#spec.list + 1] = {e = e, sold = kind == "sales"} end
		end
	end
	table.sort(spec.list, function(a, b)
		local ta, tb = a.e.t or 0, b.e.t or 0
		if ta ~= tb then return ta > tb end
		return a.sold and not b.sold
	end)
	local buyEach = {}
	spec.format = function(x)
		local e = x.e
		local count = e.count or 1
		local money = e.money or 0
		local name = e.key and X.ItemName(e.key) or e.name or "?"
		local each = count > 0 and money / count or nil
		local cut, profit = "", ""
		if x.sold then
			cut = gold(e.cut or 0)
			local avg = 0
			if e.key then
				if buyEach[e.key] == nil then
					local li = X.LedgerItem(e.key)
					buyEach[e.key] = li and li.avgBuy or false
				end
				avg = buyEach[e.key] or 0
			end
			profit = gold(money - (e.cut or 0) - count * avg)
		end
		return X.Date(e.t and math.floor(e.t), "%Y-%m-%d %H:%M") .. "\t" .. (x.sold and "Sold" or "Bought") .. "\t" .. clean(name) .. "\t" ..
			count .. "\t" .. gold(each) .. "\t" .. gold(money) .. "\t" .. cut .. "\t" .. profit .. "\t" .. clean(e.char or "")
	end
	return spec
end
-- the gold of each character of this realm per day (a day without a change keeps the gold of the day before), and all
-- of them together (as on the Gold over time page)
function makers.gold(opts)
	local chars = X.GoldChars()
	local today = X.Day()
	local from = (opts.days or 0) > 0 and (today - opts.days + 1) or nil
	local head, cols, keys = {"Date"}, {}, {}
	for i, c in ipairs(chars) do
		head[#head + 1] = clean(c.name or c.key)
		keys[i] = c.key
		local byDay = {}
		for _, p in ipairs(X.GoldHistory(c.key, from)) do byDay[math.floor(p[1] / DAY)] = p[2] end
		cols[i] = byDay
	end
	head[#head + 1] = "All characters"
	local spec = {header = table.concat(head, "\t"), list = {}}
	local all = #keys > 0 and X.GoldHistory(keys, from) or {}
	for i = #all, 1, -1 do spec.list[#spec.list + 1] = all[i] end
	spec.format = function(p)
		local d = math.floor(p[1] / DAY)
		local parts = {day(d)}
		for i = 1, #cols do parts[#parts + 1] = gold(cols[i][d]) end
		parts[#parts + 1] = gold(p[2])
		return table.concat(parts, "\t")
	end
	return spec
end
-- the tracked list with its numbers now (no time span)
function makers.tracked()
	local spec = {header = "Item\tItem ID\tLowest price now (gold)\tMarket value now (gold)\tUsual price (gold)\t" ..
		"7-day average (gold)\t30-day average (gold)\tListed now\tTrend (% a week)\tLast seen listed\tDays of history",
		list = {}, keepOrder = true}
	for key in pairs(X.db.watch or {}) do spec.list[#spec.list + 1] = {key = tostring(key), name = X.ItemName(tostring(key))} end
	table.sort(spec.list, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.key < b.key
	end)
	spec.format = function(x)
		local key = x.key
		local it = X.Items()[key]
		local cur = it and it.cur or {}
		local st = it and X.Stats(it) or {}
		local usual = it and X.Usual(key) or nil
		local seen = it and lastListed(it)
		return clean(x.name) .. "\t" .. key .. "\t" .. gold(cur.min) .. "\t" .. gold(cur.mkt) .. "\t" .. gold(usual) .. "\t" ..
			gold(st.avg7) .. "\t" .. gold(st.avg30) .. "\t" .. num(cur.qty) .. "\t" ..
			(st.trend and string.format("%.1f", st.trend) or "") .. "\t" .. (seen and X.Date(math.floor(seen), "%Y-%m-%d") or "") .. "\t" ..
			num(st.days)
	end
	return spec
end

-- X.ExportBuilder(kind, opts) -> B: B.step() true when done, then B.result = {text, rows, total, cut, bytes, note,
-- name}; opts = {key (the item, for "history"), days (0 or nil = all), max (characters, default X.EXPORT_MAX)}
function X.ExportBuilder(kind, opts)
	opts = opts or {}
	local make = makers[kind]
	local spec = make and make(opts) or {header = "", list = {}, note = "unknown"}
	local max = opts.max or X.EXPORT_MAX
	local list = spec.list
	local B = {i = 0, lines = {}, size = #spec.header + 1, total = #list, kind = kind}
	B.progress = "Making the text: 0 / " .. X.Num(#list) .. " rows"
	function B.step()
		local t0 = clock()
		local n = 0
		while B.i < #list and not B.cut do
			local line = spec.format(list[B.i + 1])
			if B.size + #line + 1 > max then
				B.cut = true
			else
				B.i = B.i + 1
				B.lines[B.i] = line
				B.size = B.size + #line + 1
				n = n + 1
				if n >= LINE_SLICE or clock() - t0 > BUDGET_MS then
					B.progress = "Making the text: " .. X.Num(B.i) .. " / " .. X.Num(#list) .. " rows"
					return false
				end
			end
		end
		local lines = B.lines
		if not spec.keepOrder then
			-- newest first was built (so a cut keeps the newest); the text goes oldest first
			local m = #lines
			for j = 1, math.floor(m / 2) do lines[j], lines[m - j + 1] = lines[m - j + 1], lines[j] end
		end
		local text = spec.header .. (#lines > 0 and ("\n" .. table.concat(lines, "\n")) or "")
		B.result = {text = text, rows = #lines, total = #list, cut = B.cut == true, bytes = #text, note = spec.note,
			name = spec.name}
		return true
	end
	return B
end
-- all at once (tests)
function X.ExportRun(kind, opts)
	local B = X.ExportBuilder(kind, opts)
	while not B.step() do end
	return B.result
end
-- sliced: done(result) when finished; a newer call replaces one still running (the older never calls done)
local exportToken
function X.Export(kind, opts, done)
	local token = {}
	exportToken = token
	local B = X.ExportBuilder(kind, opts)
	X.Job("export", function()
		if exportToken ~= token then return true end
		return B.step()
	end, function()
		if exportToken ~= token then return end
		exportToken = nil
		if done and B.result then done(B.result) end
	end)
	return B
end
