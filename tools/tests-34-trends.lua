-- XNAH test scenes, part 34: the Trends view's pages and their math (Trends.lua, UITrendsIndex.lua, UITrendsGroups.lua,
-- UITrendsSize.lua, UITrendsChanges.lua) - the market index with known prices (exact values, trimming, the basket,
-- group lines), group sums, what changed (risers, fallers, sold out, flooded, new, back), the size of the auction house
-- from the full scans (and its weekday / hour pattern), each page with an empty database and with a 10-day market,
-- and a big data set worked out a little per frame, only while the page is shown.

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end

-- trade goods and armor with their subgroups (the item class the stand-in client gives)
local function groupItems()
	local list = {
		[91001] = {"Test Linen", 7, "Cloth"}, [91002] = {"Test Wool", 7, "Cloth"}, [91003] = {"Test Silk", 7, "Cloth"},
		[91004] = {"Test Bloom", 7, "Herb"}, [91005] = {"Test Leaf", 7, "Herb"}, [91006] = {"Test Root", 7, "Herb"},
		[91007] = {"Test Helm", 4, "Plate"}, [91008] = {"Test Boots", 4, "Plate"},
	}
	for id, e in pairs(list) do
		W.items[id] = {name = e[1], quality = 1, sell = 10, stack = e[2] == 7 and 20 or 1, class = e[2], subType = e[3]}
	end
end
-- one price a day for days k = n .. 0 (0 = today): prices[k] or the price before it
local function daily(X, key, prices, n, qtys)
	local p, q = nil, 20
	for k = n, 0, -1 do
		p = prices[k] or p
		q = (qtys and qtys[k]) or q
		X.Record(key, X.Now() - k * DAY - 60, p, p, q, 2, nil, 1)
	end
end
local function spyShow(X, fn)
	local got = {}
	local old = X.UI.ShowItem
	X.UI.ShowItem = function(key) got[#got + 1] = key end
	local ok, e = pcall(fn)
	X.UI.ShowItem = old
	if not ok then error(e, 0) end
	return got
end
local function lastV(points) return points and points[#points] and points[#points][2] end
local function inList(list, key)
	for _, r in ipairs(list or {}) do if r.key == key then return true end end
	return false
end

T.scene("trends 34: the typical ratio (trimmed geometric mean)", function()
	local X = W.start()
	T.near("three items: 1, 1.1 and 0.5", X.TrendsTypical({1, 1.1, 0.5}), 100 * (0.55 ^ (1 / 3)), 1e-6)
	T.near("ten items, one tripled: left out", X.TrendsTypical({1, 1, 1, 1, 1, 1, 1, 1, 1, 3}), 100, 1e-6)
	T.near("ten items, one halved and one doubled: both left out", X.TrendsTypical({1, 1, 1, 1, 1, 1, 1, 1, 0.5, 2}), 100, 1e-6)
	T.near("ratios held between 0.2 and 5", X.TrendsTypical({10}), 500, 1e-6)
	T.near("+100% and -50% cancel out", X.TrendsTypical({2, 0.5}), 100, 1e-6)
	T.check("nothing: no value", X.TrendsTypical({}), nil)
	T.check("group label: trade goods subgroup", X.TrendsGroupLabel("Trade Goods/Cloth"), "Cloth")
	T.check("group label: other subgroup", X.TrendsGroupLabel("Armor/Plate"), "Armor: Plate")
	T.check("group label: a whole group", X.TrendsGroupLabel("Armor"), "Armor")
	local n, p = X.TrendsGroupName("Trade Goods/Herb")
	T.check("group name and parent", n .. "|" .. p, "Herb|Trade Goods")
end)

T.scene("trends 34: the market index with known prices", function()
	local X = W.start()
	groupItems()
	-- cloth: one steady, one +10% today, one -20% three days ago and -50% today
	daily(X, "91001", {[7] = 100}, 7, {[0] = 40})
	daily(X, "91002", {[7] = 100, [0] = 110}, 7)
	daily(X, "91003", {[7] = 100, [3] = 80, [0] = 50}, 7)
	-- herbs: two steady, one +50% today
	daily(X, "91004", {[7] = 200}, 7)
	daily(X, "91005", {[7] = 200}, 7)
	daily(X, "91006", {[7] = 200, [0] = 300}, 7)
	-- armor: two steady (too few for a line of their own)
	daily(X, "91007", {[7] = 5000}, 7)
	daily(X, "91008", {[7] = 7000}, 7)
	-- one with only two days of prices: not in the basket (3 needed)
	daily(X, "2589", {[1] = 120}, 1)
	local res = X.TrendsRun({periods = {7, 30}, groups = true})
	local idx = res.index[7]
	T.check("7 days: the basket", idx.basket, 8)
	T.check("7 days: starts 7 days ago", idx.start, X.Day() - 7)
	T.check("7 days: 8 days", #idx.all, 8)
	T.near("starts at 100", idx.all[1][2], 100, 1e-9)
	T.near("3 days ago: one item at 0.8", idx.all[5][2], 100 * (0.8 ^ (1 / 8)), 1e-6)
	local want = 100 * ((1.1 * 0.5 * 1.5) ^ (1 / 8))
	T.near("today: all items", idx.now, want, 1e-6)
	T.near("today: the last point", lastV(idx.all), want, 1e-6)
	T.near("cloth line", lastV(idx.lines["Trade Goods/Cloth"]), 100 * (0.55 ^ (1 / 3)), 1e-6)
	T.near("herb line", lastV(idx.lines["Trade Goods/Herb"]), 100 * (1.5 ^ (1 / 3)), 1e-6)
	T.near("trade goods line (6 items)", lastV(idx.lines["Trade Goods"]), 100 * ((1.1 * 0.5 * 1.5) ^ (1 / 6)), 1e-6)
	T.check("armor: too few for a line", idx.lines["Armor"], nil)
	T.check("armor: counted", idx.n["Armor"], 2)
	T.check("rising", idx.rising, 2)
	T.check("falling", idx.falling, 1)
	local r3
	for _, e in ipairs(idx.items) do if e.key == "91003" then r3 = e end end
	T.ok("an item's change, then and now", r3 and math.abs(r3.r - 0.5) < 1e-9 and r3.base == 100 and r3.now == 50)
	-- the history is younger than 30 days: the 30-day index starts at the oldest day
	local i30 = res.index[30]
	T.check("30 days on 8 days of history: starts at the oldest day", i30.start, X.Day() - 7)
	T.near("30 days: the same value today", i30.now, want, 1e-6)
	-- group sums: items, units and gold listed now, supply against 7 days ago
	local g = res.groups
	T.check("cloth: items", g["Trade Goods/Cloth"].items, 3)
	T.check("cloth: units now", g["Trade Goods/Cloth"].units, 40 + 20 + 20)
	T.check("cloth: gold listed", g["Trade Goods/Cloth"].gold, 40 * 100 + 20 * 110 + 20 * 50)
	T.near("cloth: supply 7 days", g["Trade Goods/Cloth"].supply, (80 / 60 - 1) * 100, 1e-6)
	T.check("trade goods: units (Linen Cloth has no subgroup)", g["Trade Goods"].units, 80 + 60 + 20)
	T.check("all items: units", g.all.units, 80 + 60 + 40 + 20)
	T.check("all items: items (the young one too)", g.all.items, 9)
	T.check("armor: gold", g["Armor"].gold, 20 * 5000 + 20 * 7000)
	-- the same through the sliced job
	X.UI.Toggle()
	local r2, busy = X.TrendsData({7})
	T.ok("the job: busy at first", busy == true and r2 == nil)
	W.advance(3)
	r2, busy = X.TrendsData({7})
	T.ok("the job: done", busy == false and r2 ~= nil)
	T.near("the job: the same index", r2 and r2.index[7].now, want, 1e-6)
	-- new prices: worked out again, the old numbers shown meanwhile
	X.Fire("XNAH_PRICES")
	local r3b, busy3 = X.TrendsData({7})
	T.ok("new prices: working again, the old result still there", busy3 == true and r3b == r2)
	W.advance(3)
	-- a crazy day price is skipped
	daily(X, "91004", {[7] = 200}, 7)
	X.Record("91005", X.Now() - 30, 200, 200, 20, 2) -- (same day)
	local res2 = X.TrendsRun({periods = {7}})
	T.near("same prices again: the same", res2.index[7].now, want, 1e-6)
end)

T.scene("trends 34: what changed - risers, fallers, sold out, flooded, new, back", function()
	local X = W.start()
	local now = X.Now()
	local H = 3600
	local function rec(key, ago, price, qty) X.Record(key, now - ago, price, price, qty, 1, "Item " .. key, 1) end
	-- riser +50%, faller -50%, steady
	rec("2589", 50 * H, 100, 10) rec("2589", 25 * H, 100, 10) rec("2589", 60, 150, 10)
	rec("2592", 50 * H, 200, 10) rec("2592", 25 * H, 200, 10) rec("2592", 60, 100, 10)
	rec("2996", 50 * H, 300, 10) rec("2996", 25 * H, 300, 10) rec("2996", 60, 305, 10)
	-- sold out: listed, then gone at the last full scan
	rec("2770", 50 * H, 50, 5) rec("2770", 25 * H, 50, 5)
	X.RecordGone("2770", now - 60)
	-- flooded: 10 -> 40
	rec("2840", 50 * H, 80, 10) rec("2840", 25 * H, 80, 10) rec("2840", 60, 80, 40)
	-- new: first seen 2 hours ago
	rec("2771", 2 * H, 70, 3)
	-- back: gone 30 hours ago, listed again
	rec("3576", 50 * H, 90, 4)
	X.RecordGone("3576", now - 30 * H)
	rec("3576", 60, 95, 6)
	local C = X.TrendsChangesRun(now - DAY, now)
	T.ok("riser", inList(C.risers, "2589") and not inList(C.risers, "2996"))
	T.near("riser: +50%", C.risers[1] and C.risers[1].change, 50, 1e-6)
	T.ok("faller", inList(C.fallers, "2592") and #C.fallers == 1)
	T.ok("steady: in no list", not inList(C.risers, "2996") and not inList(C.fallers, "2996") and not inList(C.flooded, "2996"))
	T.ok("sold out", inList(C.soldOut, "2770") and #C.soldOut == 1)
	T.ok("flooded", inList(C.flooded, "2840") and #C.flooded == 1)
	T.near("flooded: +300%", C.flooded[1] and C.flooded[1].change, 300, 1e-6)
	T.ok("new", inList(C.new, "2771") and #C.new == 1)
	T.ok("back", inList(C.back, "3576") and #C.back == 1)
	T.ok("the new one is not back", not inList(C.back, "2771"))
	T.check("not too young", C.tooYoung, false)
	T.check("items seen since then", C.seen, 7)
	-- 7 days back: the history starts later
	local C7 = X.TrendsChangesRun(now - 7 * DAY, now)
	T.check("7 days: history too young", C7.tooYoung, true)
	-- the sliced version gives the same
	local res, busy = X.TrendsChanges("day", now - DAY)
	T.ok("sliced: busy at first", busy == true and res == nil)
	W.advance(2)
	res, busy = X.TrendsChanges("day", now - DAY)
	T.ok("sliced: done", busy == false and res and inList(res.risers, "2589") and inList(res.back, "3576"))
end)

T.scene("trends 34: the size of the auction house from the full scans", function()
	local X = W.start()
	local now = X.Now()
	local scans = X.Realm().scans
	-- old scans without gold and units, then full scans every 3 hours for 8 days (fuller at 18:00 UTC), and searches
	for d = 20, 12, -1 do scans[#scans + 1] = {t = now - d * DAY, kind = "full", items = 500, auctions = 900} end
	local start = (X.Day() - 8) * DAY
	local t = start
	while t <= now do
		local hour = math.floor((t % DAY) / 3600)
		local auctions = hour == 18 and 1200 or 1000
		scans[#scans + 1] = {t = t, kind = "full", items = 600, auctions = auctions, gold = auctions * 100, units = auctions * 3}
		scans[#scans + 1] = {t = t + 60, kind = "tracked", items = 3, auctions = 5}
		t = t + 3 * 3600
	end
	local full = X.Scans("full")
	local size = X.TrendsSize(full)
	local withGold = 0
	for _, sc in ipairs(full) do if sc.gold then withGold = withGold + 1 end end
	T.check("gold: only scans that have it", #size.gold, withGold)
	T.check("auctions: every full scan", #size.auctions, #full)
	T.ok("the last scan", size.last == full[#full])
	T.ok("about 7 days before it", size.ago and math.abs((size.last.t - size.ago.t) - 7 * DAY) <= 3 * 3600)
	local a, b = size.last.gold, size.ago.gold
	T.near("gold: change", size.change.gold, (a / b - 1) * 100, 1e-9)
	local pat = size.pattern
	T.ok("hours: enough", pat.hoursOK == true, pat.scans)
	T.ok("weekdays: enough", pat.daysOK == true)
	local _, hr18 = X.ServerWeekday(start + 18 * 3600)
	local _, hr6 = X.ServerWeekday(start + 6 * 3600)
	T.ok("hours: fuller at 18:00 UTC", (pat.hours[hr18].pct or 0) > 10, pat.hours[hr18].pct)
	T.ok("hours: emptier at 06:00 UTC", (pat.hours[hr6].pct or 0) < 0, pat.hours[hr6].pct)
	-- nothing at all
	local none = X.TrendsSize({})
	T.ok("no scans: nothing", #none.gold == 0 and none.last == nil and not none.pattern.daysOK)
end)

-- opens the Trends view on a page and lets its sliced work finish
local function page(X, key, title)
	if not X.UI.Frame() or not X.UI.Frame():IsShown() then X.UI.Toggle() end
	X.UI.Open("trends")
	W.advance(0.3)
	local p = X.UI.tabs.trends.panel
	W.click(title, p)
	W.advance(4)
	X.UI.Refresh(true)
	W.advance(0.5)
	return p.pages[key], p
end
-- every column title of every table on a page has a hover line
local function columnTips(pg)
	local tables, missing = 0, 0
	W.walk(pg, function(f)
		if f.headers and f.columns then
			tables = tables + 1
			-- (K.Table's column tip: the button over each title shows it on hover)
			for i = 1, #f.headers do
				local b = f.headerButtons and f.headerButtons[i]
				local text = ''
				if b and b.scripts.OnEnter then W.hover(b) text = W.tipText() W.unhover(b) end
				if #text < 12 then missing = missing + 1 end
			end
		end
	end)
	return tables, missing
end

T.scene("trends 34: the four pages with an empty database", function()
	local X = W.start()
	local keys = {}
	for _, pg in ipairs(X.UI.TRENDS_PAGES) do keys[#keys + 1] = pg.key end
	T.ok("the four pages first, in order", table.concat(keys, ","):find("^index,groups,size,changes") ~= nil, table.concat(keys, ","))
	local p = page(X, "index", "Market index")
	T.ok("index: tiles", has(W.screen(p), "Market index") and has(W.screen(p), "Items in the basket"), W.screen(p))
	T.ok("index: says why there is no line", has(W.screen(p), "Not enough price history"), W.screen(p))
	local tables, missing = columnTips(p)
	T.check("index: no tables", tables, 0)
	p = page(X, "groups", "Item groups")
	T.ok("groups: shows something", W.screen(p) ~= "")
	tables, missing = columnTips(p)
	T.check("groups: three tables", tables, 3)
	T.check("groups: every column has a hover line", missing, 0)
	p = page(X, "size", "Auction house size")
	T.ok("size: says to scan", has(W.screen(p), "No full scans yet"), W.screen(p))
	T.ok("size: the weekday chart says what it needs", has(W.screen(p), "different weekdays"))
	p = page(X, "changes", "What changed")
	T.ok("changes: the six lists", has(W.screen(p), "Rising most") and has(W.screen(p), "Back on the auction house"), W.screen(p))
	tables, missing = columnTips(p)
	T.check("changes: six tables", tables, 6)
	T.check("changes: every column has a hover line", missing, 0)
	T.ok("changes: the first visit", has(W.screen(p), "first visit"), W.screen(p))
	T.ok("changes: the visit time kept", math.abs(X.S().trendsLastVisit - X.Now()) < 5)
	for _, title in ipairs({"1 day", "7 days", "Since your last visit"}) do
		W.click(title, p)
		W.advance(2)
		T.ok("changes: " .. title, W.screen(p) ~= "")
	end
	-- the tiles have hover lines
	local ip = X.UI.tabs.trends.panel.pages.index
	for i, tile in ipairs(ip.tiles) do T.ok("index tile " .. i .. " has a hover line", tile.scripts.OnEnter ~= nil) end
end)

-- a market of 10 days (one full scan a day) with groups
local function tenDays(X)
	W.makeMarket(34, 90, {lastDay = 9, uncached = 0})
	for i, e in ipairs(W.market.items) do
		local it = W.items[e.id]
		if e.kind == "stack" then it.class, it.subType = 7, ({"Cloth", "Herb", "Metal & Stone"})[i % 3 + 1]
		else it.class, it.subType = 4, (i % 2 == 0) and "Plate" or "Mail" end
	end
	W.openAH()
	for day = 0, 9 do
		W.marketDay(day, 9)
		local t0 = W.NOW
		T.fullScan(X)
		if day < 9 then W.advance(86400 - (W.NOW - t0)) end
	end
	W.advance(3)
end

T.scene("trends 34: the four pages with a 10-day market", function()
	local X = W.start()
	tenDays(X)
	local shown = spyShow(X, function()
		-- Market index
		local p = page(X, "index", "Market index")
		local basket = tonumber((W.plain(p.tiles[5].value:GetText()):gsub(",", "")))
		T.ok("index: a basket", basket and basket > 20, p.tiles[5].value:GetText())
		local info = p.graph.GetInfo()
		T.ok("index: all items and 3 group lines", #info.series == 4, #info.series)
		T.check("index: number labels", info.labels, "number")
		T.ok("index: a legend", #info.legend == 4)
		T.ok("index: the flat line at 100", info.levels[1] and info.levels[1].v == 100)
		T.ok("index: tiles filled", has(p.tiles[1].value:GetText(), ".") and has(p.tiles[4].value:GetText(), "%"))
		-- a group line switched off and on
		local chip = p.chips[1]
		local gk = chip.gk
		chip:Click("LeftButton")
		W.advance(0.3)
		T.check("index: line off", X.S().trendsLines[gk], false)
		T.check("index: one line less", #p.graph.GetInfo().series, 3)
		p.chips[4]:Click("LeftButton")
		W.advance(0.3)
		T.check("index: another line on", #p.graph.GetInfo().series, 4)
		W.click("1 year", p)
		W.advance(4)
		X.UI.Refresh(true)
		W.advance(0.3)
		T.check("index: period kept", X.S().trendsRange, 4)
		T.ok("index: 1 year drawn", #p.graph.GetInfo().series >= 1)
		W.click("7 days", p)
		W.advance(1)

		-- Item groups
		p = page(X, "groups", "Item groups")
		local items = p.tbl.items
		T.check("groups: All items first", items[1] and items[1].gk, "all")
		local ok, parentOf = true, nil
		for i = 2, #items do
			local r = items[i]
			if r.parent then
				if r.parent ~= parentOf then ok = false end
			else
				parentOf = r.name
			end
		end
		T.ok("groups: each subgroup under its group", ok)
		local sumTop, sumItems = 0, 0
		for _, r in ipairs(items) do if not r.parent and not r.top then sumTop = sumTop + r.units end end
		for _, it in pairs(X.Items()) do sumItems = sumItems + ((it.cur and it.cur.qty) or 0) end
		T.check("groups: units of the groups add up", sumTop, items[1].units)
		T.check("groups: units = every item's", items[1].units, sumItems)
		-- sorted by another column: the order still keeps the subgroups
		p.tbl.sortCol, p.tbl.sortDesc = 2, true
		p.tbl:Sort()
		local cloth
		for i, r in ipairs(p.tbl.items) do if r.gk == "Trade Goods/Cloth" then cloth = i end end
		T.ok("groups: cloth there", cloth ~= nil)
		p.tbl.rows[cloth - p.tbl.offset]:Click("LeftButton")
		W.advance(0.3)
		T.check("groups: picked", X.S().trendsGroup, "Trade Goods/Cloth")
		T.ok("groups: its title", has(p.title:GetText(), "Cloth"))
		T.ok("groups: its line", #p.graph.GetInfo().series == 1)
		local movers = #p.risers.items + #p.fallers.items
		T.ok("groups: its movers", movers > 0, movers)
		local tbl = #p.risers.items > 0 and p.risers or p.fallers
		local key = tbl.items[1].key
		T.ok("groups: a mover is of the group", select(2, X.TrendsGroupKeys(key)) == "Trade Goods/Cloth")
		tbl.rows[1]:Click("LeftButton")
		local tables, missing = columnTips(p)
		T.check("groups: every column has a hover line", missing, 0)
		return key
	end)
	T.ok("groups: a mover clicked opens it", #shown == 1)

	-- Auction house size
	local p = page(X, "size", "Auction house size")
	T.ok("size: gold tile", has(W.plain(p.tiles[1].value:GetText()), "g"), p.tiles[1].value:GetText())
	T.ok("size: change in 7 days", has(W.plain(p.tiles[2].sub:GetText()), "in 7 days"), p.tiles[2].sub:GetText())
	local fulls = 0
	for _, sc in ipairs(X.Scans("full")) do if sc.gold then fulls = fulls + 1 end end
	T.ok("size: ten days of full scans", fulls >= 9, fulls)
	T.check("size: one point per full scan", #p.graph.GetInfo().series[1].pts, fulls)
	T.check("size: money labels for gold", p.graph.GetInfo().labels, "money")
	W.click("Auctions", p)
	W.advance(0.3)
	T.check("size: auctions picked", X.S().trendsSizeShow, 2)
	T.check("size: number labels", p.graph.GetInfo().labels, "number")

	-- What changed
	shown = spyShow(X, function()
		p = page(X, "changes", "What changed")
		W.click("7 days", p)
		W.advance(3)
		X.UI.Refresh(true)
		W.advance(0.3)
		local risers = p.lists[1].tbl.items
		local anyRise = false
		for _, id in ipairs(W.market.byKind.rise) do if inList(risers, tostring(id)) then anyRise = true end end
		T.ok("changes: a rising item among the risers", anyRise, #risers)
		local fl = p.lists[4].tbl.items
		local anyFlood = false
		for _, id in ipairs(W.market.byKind.flood) do if inList(fl, tostring(id)) then anyFlood = true end end
		T.ok("changes: a flooded item", anyFlood, #fl)
		T.ok("changes: rows clickable", #risers > 0)
		p.lists[1].tbl.rows[1]:Click("LeftButton")
	end)
	T.check("changes: a row opens the item", #shown, 1)
end)

T.scene("trends 34: a big data set is worked out in slices, only while the page is shown", function()
	local X = W.start()
	local now = X.Now()
	local N = 6000
	for i = 1, N do
		local key = tostring(300000 + i)
		local p = 20000 + (i % 97) * 100
		for d = 4, 0, -1 do X.Record(key, now - d * DAY - 60, p + (4 - d) * (i % 3), p, 20, 3, "Bulk Thing " .. i, 1) end
	end
	X.Fire("XNAH_PRICES")
	X.UI.Toggle()
	X.UI.Open("market")
	W.advance(15)
	T.ok("another view open: no index work", not X.JobRunning("trends index"))
	W.maxStepTime = 0
	X.UI.Open("trends")
	T.ok("index: still working after the first frame", X.JobRunning("trends index"))
	W.advance(W.FRAME * 3)
	T.ok("index: still working after 3 frames", X.JobRunning("trends index"))
	T.ok("index: says it is working", has(W.screen(X.UI.tabs.trends.panel), "Working"), W.screen(X.UI.tabs.trends.panel))
	W.advance(30)
	X.UI.Refresh(true)
	T.ok("index: done", not X.JobRunning("trends index"))
	T.note(string.format("trends: index longest step %.0f ms", W.maxStepTime * 1000))
	local p = X.UI.tabs.trends.panel.pages.index
	T.check("index: every item in the basket", W.plain(p.tiles[5].value:GetText()), X.Num(N))
	-- the size page needs no slicing; on it new prices start no index work
	W.click("Auction house size", X.UI.tabs.trends.panel)
	W.advance(0.3)
	X.Fire("XNAH_PRICES")
	W.advance(2)
	T.ok("size page: no index work", not X.JobRunning("trends index"))
	-- What changed is sliced too
	W.maxStepTime = 0
	W.click("What changed", X.UI.tabs.trends.panel)
	T.ok("changes: working", X.JobRunning("trends changes"))
	W.advance(30)
	T.ok("changes: done", not X.JobRunning("trends changes"))
	T.note(string.format("trends: changes longest step %.0f ms", W.maxStepTime * 1000))
	T.note(string.format("trends: longest step %.0f ms at %s", W.maxStepTime * 1000, tostring(W.maxStepWhere)))
end)
