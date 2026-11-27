-- XNAH test scenes, part 43: the Market view on a big auction house. Every sort column (both ways) gives the same order
-- as a plain sort of the rows (equal values by item key, rows without a value last), also with filters and a search;
-- sorting, filtering, the "Can be crafted" list and the 7-day lines are worked out a little per frame; every column
-- title and filter button has a hover line.

local N = 1200 -- more than the 400 rows sorted at once: the sorting goes over several frames

-- the plain sort the Market view used before (one table.sort with a compare function) - the order to match
local function plainOrder(list, f, desc)
	local vals, out = {}, {}
	for i, r in ipairs(list) do
		vals[r] = f(r)
		out[i] = r
	end
	table.sort(out, function(a, b)
		local va, vb = vals[a], vals[b]
		if va == vb then return a.key < b.key end
		if va == nil then return false end
		if vb == nil then return true end
		if desc then return va > vb end
		return va < vb
	end)
	return out
end
local function keysOf(list)
	local k = {}
	for i, r in ipairs(list) do k[i] = r.key end
	return table.concat(k, ",")
end
-- the first place two lists differ (nil = the same)
local function firstDiff(a, b)
	for i = 1, math.max(#a, #b) do
		if (a[i] and a[i].key) ~= (b[i] and b[i].key) then
			return i .. ": " .. tostring(a[i] and a[i].key) .. " / " .. tostring(b[i] and b[i].key)
		end
	end
	return nil
end

-- N items with many equal values: 5 prices, 3 kinds of trend, repeated names, some never named, some sold out, some old,
-- some with one price only (no trend), sales speed for a quarter in 3 sizes; plain and random-suffix item keys
local function bulk(X)
	local now = X.Now()
	local r = X.Realm()
	r.speed = r.speed or {}
	local day = X.Day()
	local NAMES = {"Same Thing", "Other Thing", "Alpha Bar", ""}
	local PRICES = {100, 250, 250, 999, 5000}
	for i = 1, N do
		local key = i <= 400 and tostring(300000 + i) or (tostring(300000 + (i % 400) + 1) .. ":" .. (i % 2 == 0 and -i or i))
		local name = NAMES[i % 4 + 1]
		local q = i % 5
		local base = PRICES[i % 5 + 1]
		local slope = ((i % 3) - 1) * 0.05
		if i % 6 ~= 0 then
			for d = 4, 1, -1 do
				local p = math.floor(base * (1 + slope * (5 - d)))
				X.Record(key, now - d * 86400, p, p, 10 + (i % 4) * 5, 2, name, q)
			end
		end
		local t = (i % 11 == 0) and (now - 5 * 86400) or (now - 60)
		local qty = (i % 7 == 0) and 0 or (10 + (i % 4) * 5)
		X.Record(key, t, base, base + (i % 2), qty, qty > 0 and 2 or 0, name, q)
		if i % 4 == 0 then r.speed[key] = X.b36(day) .. "," .. X.b36(i % 3 + 1) .. "," .. X.b36(60) end
	end
	X.Fire("XNAH_PRICES")
end

local function idle(X)
	return W.waitFor(function()
		return not (X.JobRunning("market rows") or X.JobRunning("market sort") or X.JobRunning("market filter") or
			X.JobRunning("market recipes"))
	end, 120)
end

local function open(X)
	X.UI.Toggle()
	X.UI.Open("market")
	idle(X)
	X.UI.Refresh(true)
	idle(X)
	return X.UI.tabs.market.panel
end

-- clicks column i's title until it sorts the asked way, waits until the order is shown
local function sortBy(X, tbl, i, desc)
	for _ = 1, 2 do
		if tbl.sortCol == i and tbl.sortDesc == desc then break end
		tbl.headerButtons[i]:Click("LeftButton")
	end
	return idle(X)
end

local function shownLines(root)
	local n = 0
	W.walk(root, function(f) if f.kind == "Line" and f.shown and f:IsVisible() then n = n + 1 end end)
	return n
end

T.scene("market speed: every sort column gives the same order as a plain sort (both ways, ties by item key)", function()
	local X = W.start()
	bulk(X)
	local p = open(X)
	local tbl = p.tbl
	T.check("every row shown", #tbl.items, N)
	local all = {}
	for i, r in ipairs(tbl.items) do all[i] = r end
	local sortable = 0
	for i, c in ipairs(tbl.columns) do
		if c.sort then
			sortable = sortable + 1
			for _, desc in ipairs({true, false}) do
				T.ok("sorted by " .. c[1] .. (desc and " (down)" or " (up)") .. " in time", sortBy(X, tbl, i, desc))
				local want = plainOrder(all, c.sort, desc)
				T.check("all rows still there: " .. c[1], #tbl.items, N)
				T.ok("same order: " .. c[1] .. (desc and " (down)" or " (up)"), keysOf(tbl.items) == keysOf(want),
					firstDiff(tbl.items, want))
			end
		end
	end
	T.check("ten sortable columns", sortable, 10)
	-- the test data really has ties and empty values
	local ties, empty = 0, 0
	for _, r in ipairs(all) do
		if r.trend == nil then empty = empty + 1 end
		if r.mkt == 250 then ties = ties + 1 end
	end
	T.ok("many equal values", ties >= 100, ties)
	T.ok("rows without a trend", empty >= 100, empty)
	-- with filters and a search: the rows that pass, in the same order
	W.click("Listed now", p)
	idle(X)
	local listed = {}
	for _, r in ipairs(all) do if (r.qty or 0) > 0 then listed[#listed + 1] = r end end
	for _, i in ipairs({2, 5, 7, 11}) do
		local c = tbl.columns[i]
		sortBy(X, tbl, i, false)
		local want = plainOrder(listed, c.sort, false)
		T.ok("listed now, by " .. c[1] .. ": same rows and order", keysOf(tbl.items) == keysOf(want), firstDiff(tbl.items, want))
	end
	W.click("Listed now", p)
	idle(X)
	W.type(p.search, "thing")
	W.advance(0.5)
	idle(X)
	local things = {}
	for _, r in ipairs(all) do if r.name:find("thing", 1, true) then things[#things + 1] = r end end
	local want = plainOrder(things, tbl.columns[tbl.sortCol].sort, tbl.sortDesc)
	T.ok("search: same rows and order", keysOf(tbl.items) == keysOf(want), firstDiff(tbl.items, want))
	T.check("search: the matches", #tbl.items, #things)
	W.type(p.search, "")
	W.advance(0.5)
	idle(X)
	-- Rising: the trend kind of the rows, same rule as X.Movers
	W.click("Rising", p)
	idle(X)
	local up = {}
	for _, r in ipairs(X.Movers("up")) do up[r.key] = true end
	local n, wrong = 0, 0
	for _, r in ipairs(tbl.items) do
		n = n + 1
		if not up[r.key] then wrong = wrong + 1 end
	end
	T.ok("rising: some rows", n > 0, n)
	T.check("rising: only items X.Movers calls rising", wrong, 0)
	local count = 0
	for _ in pairs(up) do count = count + 1 end
	T.check("rising: all of them", n, count)
	W.click("Rising", p)
	idle(X)
end)

T.scene("market speed: sorting, filtering and the 7-day lines go over several frames", function()
	local X = W.start()
	bulk(X)
	local p = open(X)
	local tbl = p.tbl
	-- a column not sorted before: worked out over the next frames, the list waits meanwhile
	local before = keysOf(tbl.items)
	tbl.headerButtons[6]:Click("LeftButton")
	T.ok("sorting goes on in the next frames", X.JobRunning("market sort"))
	T.ok("the title shows the new sorting at once", W.plain(tbl.headers[6]:GetText()):find(" v", 1, true) ~= nil,
		tbl.headers[6]:GetText())
	T.check("the list waits for it", keysOf(tbl.items), before)
	T.ok("the footer says it is sorting", W.screen(p):find("Sorting...", 1, true) ~= nil)
	W.advance(W.FRAME)
	T.ok("still sorting after one frame", X.JobRunning("market sort"))
	T.ok("done in time", idle(X))
	T.ok("the new order is shown", keysOf(tbl.items) ~= before)
	T.ok("the footer no longer says sorting", W.screen(p):find("Sorting...", 1, true) == nil)
	-- sorted the other way: kept, so at once
	tbl.headerButtons[6]:Click("LeftButton")
	T.ok("the other way: at once", not X.JobRunning("market sort") and tbl.sortDesc == false)
	-- back to a column sorted before: kept, at once
	tbl.headerButtons[3]:Click("LeftButton")
	T.ok("a column sorted before: at once", not X.JobRunning("market sort"))
	-- a search over many rows: a part at once, the rest in the next frames
	W.type(p.search, "alpha")
	W.advance(0.31)
	idle(X)
	local alpha = 0
	for _, r in ipairs(tbl.items) do if r.name:find("alpha", 1, true) then alpha = alpha + 1 end end
	T.check("search: only matches", alpha, #tbl.items)
	T.ok("search: found some", alpha > 0, alpha)
	W.type(p.search, "")
	W.advance(0.31)
	idle(X)
	-- the 7-day lines of the rows on screen: worked out in the next frames, then drawn
	X.Fire("XNAH_PRICES")
	X.UI.Refresh(true)
	idle(X)
	X.UI.Refresh(true)
	W.waitFor(function() return not X.JobRunning("market lines") end, 10)
	T.ok("lines drawn", shownLines(p) >= 3, shownLines(p))
	local r1 = tbl.items[1]
	T.ok("the first row's line is worked out", r1 and X.UI.MarketSpark(r1.key) ~= nil)
	-- new prices while a sort is being worked out: the old sort stops, the new rows are sorted
	tbl.headerButtons[9]:Click("LeftButton")
	X.Fire("XNAH_PRICES")
	X.UI.Refresh(true)
	T.ok("done after new prices", idle(X))
	X.UI.Refresh(true)
	idle(X)
	local all = {}
	for i, r in ipairs(tbl.items) do all[i] = r end
	local want = plainOrder(all, tbl.columns[9].sort, tbl.sortDesc)
	T.ok("after new prices: same order as a plain sort", keysOf(tbl.items) == keysOf(want), firstDiff(tbl.items, want))
	T.check("after new prices: every row", #tbl.items, N)
end)

-- the game has a millisecond clock (the stand-in has none): then each frame works until its time is up
T.scene("market speed: with the game's clock the work is cut by time, same order", function()
	local function addClock(env) env.debugprofilestop = function() return os.clock() * 1000 end end
	table.insert(W.onEnv, addClock)
	local ok, e = pcall(function()
		local X = W.start()
		T.ok("the clock is there", type(W.env.debugprofilestop) == "function")
		bulk(X)
		local p = open(X)
		local tbl = p.tbl
		T.check("every row shown", #tbl.items, N)
		local all = {}
		for i, r in ipairs(tbl.items) do all[i] = r end
		for _, i in ipairs({1, 4, 7, 11}) do
			local c = tbl.columns[i]
			for _, desc in ipairs({true, false}) do
				T.ok("clock: sorted by " .. c[1] .. " in time", sortBy(X, tbl, i, desc))
				local want = plainOrder(all, c.sort, desc)
				T.ok("clock: same order by " .. c[1] .. (desc and " (down)" or " (up)"), keysOf(tbl.items) == keysOf(want),
					firstDiff(tbl.items, want))
			end
		end
		W.type(p.search, "other")
		W.advance(0.31)
		idle(X)
		local n = 0
		for _, r in ipairs(all) do if r.name:find("other", 1, true) then n = n + 1 end end
		T.check("clock: search", #tbl.items, n)
	end)
	for i = #W.onEnv, 1, -1 do if W.onEnv[i] == addClock then table.remove(W.onEnv, i) end end
	if not ok then error(e, 0) end
end)

T.scene("market speed: Can be crafted lists the same items as the recipe list", function()
	local X = W.start()
	local now = X.Now()
	-- items some recipe of the game makes, and ones none makes
	local ids = {2302, 2303, 2304, 2307, 2308, 2318, 2320, 2589, 2770, 2840, 2841, 300900}
	for _, id in ipairs(ids) do X.Record(tostring(id), now - 60, 100, 100, 5, 1, "Thing " .. id, 1) end
	X.Fire("XNAH_PRICES")
	local p = open(X)
	W.click("Can be crafted", p)
	idle(X)
	local got, want = {}, {}
	for _, r in ipairs(p.tbl.items) do got[#got + 1] = r.key end
	for _, id in ipairs(ids) do if #X.RecipesFor(id) > 0 then want[#want + 1] = tostring(id) end end
	table.sort(got)
	table.sort(want)
	T.ok("some can be crafted", #want >= 3, #want)
	T.check("the same items as X.RecipesFor", table.concat(got, ","), table.concat(want, ","))
	-- a recipe read in the game: the list follows
	X.db.recipes[990001] = {name = "Make the Thing", out = 300900, n = 1, r = {{2589, 2}}, prof = "Tailoring"}
	X.Fire("XNAH_RECIPES")
	X.UI.Refresh(true)
	idle(X)
	local found = false
	for _, r in ipairs(p.tbl.items) do if r.key == "300900" then found = true end end
	T.ok("a new recipe: its item is in the list", found)
	W.click("Can be crafted", p)
	idle(X)
	T.check("off: every item", #p.tbl.items, #ids)
end)

T.scene("market speed: every column title and filter button has a hover line", function()
	local X = W.start()
	X.Record("2589", X.Now() - 60, 50, 50, 10, 1, "Linen Cloth", 1)
	X.Fire("XNAH_PRICES")
	local p = open(X)
	local tbl = p.tbl
	local missing = {}
	for i = 1, #tbl.headers do
		local b = tbl.headerButtons[i]
		local text = ""
		if b and b.scripts.OnEnter then
			W.hover(b)
			text = W.tipText()
			W.unhover(b)
		end
		if #text < 40 then missing[#missing + 1] = tbl.columns[i][1] end
	end
	T.check("every column title explains itself", table.concat(missing, ", "), "")
	W.hover(tbl.headerButtons[4])
	T.ok("vs usual: what it compares", W.tipText():find("usual price", 1, true) ~= nil, W.tipText())
	W.unhover(tbl.headerButtons[4])
	W.hover(tbl.headerButtons[10])
	T.ok("7 days: cannot be sorted (no sorting line)", W.tipText():find("Click to sort", 1, true) == nil, W.tipText())
	W.unhover(tbl.headerButtons[10])
	missing = {}
	for id, b in pairs(p.buttons) do
		local text = ""
		if b.scripts.OnEnter then
			W.hover(b)
			text = W.tipText()
			W.unhover(b)
		end
		if #text < 20 then missing[#missing + 1] = id end
	end
	table.sort(missing)
	T.check("every filter button explains itself", table.concat(missing, ", "), "")
	W.hover(p.search)
	T.ok("the search box explains itself", W.tipText():find("item number", 1, true) ~= nil, W.tipText())
	W.unhover(p.search)
end)
