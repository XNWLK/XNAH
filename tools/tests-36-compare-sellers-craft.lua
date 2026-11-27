-- XNAH test scenes, part 36: three item pages and their maths - Compare (several items on one graph, % change, the
-- compare list kept per item), Sellers (seller history numbers, how fast they undercut, the sellers of the last
-- search) and Crafting (crafting cost on a past day from the reagents' day prices, the margin over time, the recipes
-- that use an item). Every scene title starts with "36" (node tools/test.js 36).

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function items(X) return X.UI.tabs.items.panel end
local function pageOf(X, key) return items(X).pages.frames[key] end
local function openMenu()
	for _, f in ipairs(W.frames) do
		if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then return f end
	end
end
-- the start of a day (server seconds)
local function dayStart(X, day) return day * DAY end
-- one price a day for `days` days up to yesterday, oldest first: priceOf(daysAgo)
local function daily(X, key, days, priceOf, name, qty)
	local today = X.Day()
	for d = days, 1, -1 do
		local v = priceOf(d)
		X.Record(key, dayStart(X, today - d) + 3600, v, v, qty or 20, 4, name, 1)
	end
end
-- shows an item and one of its pages; returns the page frame
local function show(X, key, title, pageKey)
	X.UI.ShowItem(key)
	W.advance(0.3)
	W.click(title, items(X))
	W.advance(0.3)
	return pageOf(X, pageKey)
end

-- [[ Compare ]]
T.scene("36 compare: the list kept per item, % maths, price change", function()
	local X = W.start()
	T.check("nothing yet", #X.CompareList("2770"), 0)
	T.ok("add one", X.CompareAdd("2770", "2840"))
	local ok, why = X.CompareAdd("2770", "2770")
	T.check("the item itself: no", tostring(ok) .. " " .. tostring(why), "false same")
	ok, why = X.CompareAdd("2770", "2840")
	T.check("twice: no", tostring(ok) .. " " .. tostring(why), "false already")
	for _, k in ipairs({"2771", "3576", "2841"}) do X.CompareAdd("2770", k) end
	T.check("four more", table.concat(X.CompareList("2770"), ","), "2840,2771,3576,2841")
	ok, why = X.CompareAdd("2770", "2589")
	T.check("a fifth: full", tostring(ok) .. " " .. tostring(why), "false full")
	X.CompareRemove("2770", "2771")
	T.check("one taken off", table.concat(X.CompareList("2770"), ","), "2840,3576,2841")
	T.ok("room again", X.CompareAdd("2770", "2589"))
	T.check("a copy, not the setting itself", (function() local l = X.CompareList("2770") l[1] = "x" return X.CompareList("2770")[1] end)(), "2840")
	X.CompareAdd("2589", "2592")
	X.CompareRemove("2589", "2592")
	T.check("an empty list is dropped", X.S().compareLists["2589"], nil)
	-- capped: at most X.COMPARE_LISTS items keep a list, the one changed longest ago goes
	for i = 1, X.COMPARE_LISTS + 5 do
		W.advance(1)
		X.CompareAdd(tostring(500000 + i), "2589")
	end
	T.check("capped", T.count(X.S().compareLists), X.COMPARE_LISTS)
	T.check("the oldest went first", X.S().compareLists["2770"], nil)
	T.ok("the newest stays", X.S().compareLists[tostring(500000 + X.COMPARE_LISTS + 5)] ~= nil)
	-- % change: every line starts at 100
	local idx = X.CompareIndex({{1, nil}, {2, 200}, {3, 250}, {4, nil}, {5, 100}})
	T.check("before the first price: nothing", idx[1][2], nil)
	T.check("the first price = 100", idx[2][2], 100)
	T.check("25% dearer = 125", idx[3][2], 125)
	T.check("a gap stays a gap", idx[4][2], nil)
	T.check("half = 50", idx[5][2], 50)
	T.check("no prices: all gaps", #X.CompareIndex({{1, nil}}), 1)
	-- the change over 7 / 30 days: the price now against the day price then
	daily(X, "2770", 40, function(d) return d > 20 and 100 or 150 end, "Copper Ore")
	X.Record("2770", X.Now() + 60, 165, 165, 20, 4)
	T.near("7 days: 150 -> 165 = +10%", X.PriceChange("2770", 7), 10, 0.01)
	T.near("30 days: 100 -> 165 = +65%", X.PriceChange("2770", 30), 65, 0.01)
	T.check("no history that far: nil", X.PriceChange("2770", 90), nil)
	T.check("unknown item: nil", X.PriceChange("999999", 7), nil)
	-- the day price: a day without a scan takes the last one, up to 7 days back
	local it = X.Items()["2589"] or X.Item("2589", true)
	local today = X.Day()
	X.Record("2589", dayStart(X, today - 20) + 60, 40, 44, 5, 1, "Linen Cloth", 1)
	T.check("that day: the market value", X.DayPrice("2589", today - 20), 44)
	T.check("3 days later: carried", X.DayPrice("2589", today - 17), 44)
	T.check("8 days later: too old", X.DayPrice("2589", today - 12), nil)
	T.check("before it: nothing", X.DayPrice("2589", today - 21), nil)
	T.ok("(the record)", it ~= nil)
end)

T.scene("36 compare: the page with no data and with prices", function()
	local X = W.start()
	-- no data at all: the page builds and says so
	local page = show(X, "2770", "Compare", "compare")
	T.ok("the page is shown", page and page:IsVisible())
	T.check("the page key kept", X.S().itemPage, "compare")
	local info = page.graph.GetInfo()
	T.check("no lines", #info.series, 0)
	T.ok("says no prices yet", has(W.screen(page.graph), "No prices yet"), W.screen(page.graph))
	T.ok("one chip: the item picked", page.chips[1]:IsVisible() and not page.chips[2]:IsVisible())
	T.ok("a hint how to add", has(W.screen(page), "Type a name"), W.screen(page))
	T.check("the table: one row", #page.tbl.items, 1)
	T.ok("column titles have a hover line", page.tbl.columns[4].tip ~= nil)
	W.hover(page.tbl.headerButtons[4])
	T.ok("hover: what 7 days means", has(W.tipText(), "moved in the last 7 days"), W.tipText())
	W.unhover(page.tbl.headerButtons[4])
	-- prices: ore and bars
	daily(X, "2770", 40, function(d) return 100 + d end, "Copper Ore")
	daily(X, "2840", 40, function(d) return 300 - d end, "Copper Bar")
	daily(X, "3576", 40, function(d) return 500 end, "Tin Bar")
	X.UI.Refresh(true)
	W.advance(0.3)
	info = page.graph.GetInfo()
	T.check("one line (the item)", #info.series, 1)
	T.check("money labels", info.labels, "money")
	-- add with Enter (the best match), then from the menu
	W.type(page.add, "Copper Bar")
	W.advance(0.3)
	T.check("added with Enter", table.concat(X.CompareList("2770"), ","), "2840")
	W.type(page.add, "tin b", false)
	W.advance(0.5)
	local menu = openMenu()
	T.ok("matches in a menu", menu ~= nil)
	if menu then W.click("Tin Bar", menu) end
	W.advance(0.3)
	T.check("picked from the menu", table.concat(X.CompareList("2770"), ","), "2840,3576")
	info = page.graph.GetInfo()
	T.check("three lines", #info.series, 3)
	T.check("legend: three names", #info.legend, 3)
	T.check("legend: the item first", info.legend[1] and info.legend[1].label, "Copper Ore")
	T.ok("three chips", page.chips[3]:IsVisible() and has(W.plain(page.chips[3].label.text), "Tin Bar"))
	T.check("the table: three rows", #page.tbl.items, 3)
	local text = W.screen(page.tbl)
	T.ok("the table: price, change, listed", has(text, "Copper Bar") and has(text, "%") and has(text, "20"), text)
	-- % change: every line starts at 100, a flat line at 100
	W.click("% change", page)
	W.advance(0.3)
	info = page.graph.GetInfo()
	T.check("percent labels", info.labels, "percent")
	T.check("the flat line at 100", info.levels[1] and info.levels[1].v, 100)
	local first = info.series[1].pts[1]
	T.near("the item's line starts at 100", first and first[2], 100, 0.01)
	T.check("kept", X.S().compareMode, "pct")
	-- ranges
	W.click("7 days", page)
	W.advance(0.3)
	T.check("range kept", X.S().compareRange, 1)
	T.ok("7 days: fewer points", #page.graph.GetInfo().series[1].pts <= 8, #page.graph.GetInfo().series[1].pts)
	W.click("1 year", page)
	W.advance(0.3)
	T.ok("1 year: all points", #page.graph.GetInfo().series[1].pts >= 40, #page.graph.GetInfo().series[1].pts)
	-- take one off with its x
	page.chips[2].remove:Click("LeftButton")
	W.advance(0.3)
	T.check("taken off", table.concat(X.CompareList("2770"), ","), "3576")
	T.check("two lines", #page.graph.GetInfo().series, 2)
	-- full: a fifth is refused with a line saying why
	for _, k in ipairs({"2840", "2771", "2841"}) do X.CompareAdd("2770", k) end
	X.UI.Refresh(true)
	W.advance(0.3)
	T.ok("full: the box is off", page.add.enabled == false or not page.add:IsEnabled(), page.add.enabled)
	-- another item has its own list
	X.UI.ShowItem("2840")
	W.advance(0.3)
	T.check("another item: its own list (empty)", #page.graph.GetInfo().series, 1)
	-- kept after a reload
	X = W.reload()
	W.advance(1)
	T.check("after a reload", table.concat(X.CompareList("2770"), ","), "3576,2840,2771,2841")
	page = show(X, "2770", "Compare", "compare")
	T.check("after a reload: the three with prices drawn (tin ore and bronze have none)", #page.graph.GetInfo().series, 3)
	T.check("after a reload: five chips", page.chips[5]:IsVisible(), true)
	T.check("after a reload: still %", page.graph.GetInfo().labels, "percent")
end)

-- [[ Sellers ]]
T.scene("36 sellers: how fast they undercut, in plain words", function()
	local X = W.start()
	T.check("not scanned", X.UndercutSpeed(nil).word, "not known")
	T.check("too few scans", X.UndercutSpeed(0, 2, 0).word, "not seen yet")
	T.check("none in many scans", X.UndercutSpeed(0, 12, 0).word, "hardly ever")
	local s = X.UndercutSpeed(0.5, 10, 3)
	T.check("half a day: slow", s.word .. " / " .. s.sub, "slow / once in 2 days")
	s = X.UndercutSpeed(2, 20, 14)
	T.check("twice a day: steady", s.word .. " / " .. s.sub, "steady / every 12 h")
	s = X.UndercutSpeed(6, 60, 42)
	T.check("6 a day: fast", s.word .. " / " .. s.sub, "fast / every 4 h")
	s = X.UndercutSpeed(24, 200, 168)
	T.check("24 a day: very fast", s.word .. " / " .. s.sub, "very fast / every 60 min")
	T.ok("a whole sentence", has(s.text, "168 of your 200 scans"), s.text)
end)

T.scene("36 sellers: seller history numbers - sellers now, undercuts, the graph points", function()
	local X = W.start()
	local key = "2589"
	local today = X.Day()
	local st = X.SellerStats(key)
	T.check("unknown item: no sellers", st.hasSellers, false)
	T.check("unknown item: speed not known", st.speed.word, "not known")
	-- a quiet day (one scan), then 7 days with two scans each: the second is one copper cheaper (an undercut)
	X.Record(key, dayStart(X, today - 8) + 3600, 100, 110, 50, 5, "Linen Cloth", 1)
	-- (searches on three of the days: the sellers of a search, the latest wins; the history is written in time order)
	local searches = {[5] = {5, 0.6, "Bigseller Trader"}, [3] = {6, 0.5, "Bigseller Trader"}, [1] = {4, 0.75, "Other Seller"}}
	for d = 6, 0, -1 do
		X.Record(key, dayStart(X, today - d) + 3600, 100, 110, 50, 5)
		X.Record(key, dayStart(X, today - d) + 7200, 99, 110, 50, 5)
		if d == 6 then
			st = X.SellerStats(key)
			T.check("no sellers yet", st.hasSellers, false)
		end
		local s = searches[d]
		if s then X.RecordSellers(key, dayStart(X, today - d) + 7300, s[1], s[2], s[3]) end
	end
	st = X.SellerStats(key)
	T.check("seen on 7 days", st.days7, 7)
	T.check("14 scans", st.scans7, 14)
	T.check("7 undercuts", st.undercuts7, 7)
	T.check("one a day", st.perDay, 1)
	T.check("half the scans", st.share, 0.5)
	T.check("steady", st.speed.word, "steady")
	T.check("sellers known", st.hasSellers, true)
	T.check("sellers now", st.now.sellers, 4)
	T.check("biggest share", st.now.topShare, 75)
	T.check("biggest seller", st.now.topName, "Other Seller")
	T.check("from yesterday", st.now.day, today - 1)
	local sellers, share, cuts = X.SellerSeries(key, today - 29)
	T.check("graph: three seller points", #sellers, 3)
	T.check("graph: three share points", #share, 3)
	T.check("graph: share in %", share[3][2], 75)
	T.check("graph: undercuts on every day seen (8)", #cuts, 8)
	T.check("graph: the quiet day is 0", cuts[1][2], 0)
	T.check("graph: then one a day", cuts[2][2], 1)
	T.check("graph: at noon", cuts[1][1], (today - 8) * DAY + DAY / 2)
	local s2 = X.SellerSeries(key, today - 3)
	T.check("graph: a shorter range", #s2, 2)
	-- cached until something changes
	T.ok("cached", X.SellerStats(key) == st)
	X.Record(key, dayStart(X, today) + 9000, 90, 110, 50, 5)
	T.check("a new undercut: worked out again", X.SellerStats(key).undercuts7, 8)
end)

T.scene("36 sellers: the page with no data, with seller history and with a search", function()
	local X = W.start()
	-- nothing at all
	local page = show(X, "2589", "Sellers", "sellers")
	T.ok("the page is shown", page and page:IsVisible())
	local text = W.screen(page)
	T.ok("the plain line: no seller numbers and how to get them", has(text, "No seller numbers yet") and has(text, "Scan tracked"), text)
	T.ok("tiles: not known", has(W.plain(page.tiles[1].value.text), "not known"))
	T.ok("graphs empty", #page.gSellers.GetInfo().series == 0 and #page.gCuts.GetInfo().series == 0)
	T.ok("the table says how", has(page.tbl.empty.text, "Open the auction house"), page.tbl.empty.text)
	T.ok("hover on the line: the whole story", page.hot.text and has(page.hot.text, "searched by itself"))
	W.hover(page.tiles[4])
	T.ok("tile hover: what it means", has(W.tipText(), "slow"), W.tipText())
	W.unhover(page.tiles[4])
	W.hover(page.tbl.headerButtons[2])
	T.ok("column hover: what it means", has(W.tipText(), "everything listed"), W.tipText())
	W.unhover(page.tbl.headerButtons[2])
	-- prices only (full scans): undercuts but no sellers
	local today = X.Day()
	for d = 6, 0, -1 do
		X.Record("2589", dayStart(X, today - d) + 3600, 100, 110, 50, 5, "Linen Cloth", 1)
		X.Record("2589", dayStart(X, today - d) + 7200, 99, 110, 50, 5)
	end
	X.UI.Refresh(true)
	W.advance(0.3)
	T.ok("undercuts a day shown", W.plain(page.tiles[3].value.text) == "1", page.tiles[3].value.text)
	T.check("how fast: steady", W.plain(page.tiles[4].value.text), "steady")
	T.ok("undercut graph drawn", #page.gCuts.GetInfo().series == 1)
	T.ok("still the plain line about sellers", has(W.screen(page), "No seller numbers yet"))
	-- seller history (a search today)
	X.RecordSellers("2589", dayStart(X, today) + 7300, 5, 0.62, "Bea Smith")
	X.UI.Refresh(true)
	W.advance(0.3)
	T.check("sellers now", W.plain(page.tiles[1].value.text), "5")
	T.check("biggest share", W.plain(page.tiles[2].value.text), "62%")
	T.check("its name", W.plain(page.tiles[2].sub.text), "Bea Smith")
	T.ok("the line now says how fast", has(W.screen(page), "times a day"), W.screen(page))
	T.check("sellers graph", #page.gSellers.GetInfo().series, 1)
	T.check("share graph in %", page.gShare.GetInfo().labels, "percent")
	T.check("share graph: a line at half", page.gShare.GetInfo().levels[1].v, 50)
	-- a search of gear: the sellers by name in the table
	W.openAH()
	W.list(15210, 50000, 1, 3, "Bob")    -- Bob1 Smith, Bob2 Smith, Bob3 Smith
	W.list(15210, 52000, 1, 1, "Bob1")   -- Bob1 Smith again
	W.ah[#W.ah + 1] = {itemID = 15210, count = 1, buyout = 49000, bid = 40000, owner = W.me, timeLeft = 2} -- yours
	W.advance(1)
	X.ScanItems({"15210"})
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	local live = X.SellersNow("15210")
	T.ok("kept this session", live ~= nil)
	T.check("four sellers (you too)", live and #live.rows, 4)
	T.check("the biggest first", live and live.rows[1].name, "Bob1 Smith")
	T.check("its units", live and live.rows[1].units, 2)
	T.check("its share", live and live.rows[1].share, 0.4)
	T.check("its cheapest", live and live.rows[1].lowest, 50000)
	local mine
	for _, r in ipairs(live and live.rows or {}) do if r.mine then mine = r end end
	T.ok("yours marked", mine ~= nil and mine.lowest == 49000, mine and mine.name)
	X.UI.ShowItem("15210")
	W.advance(0.5)
	T.check("the table: four rows", #page.tbl.items, 4)
	text = W.screen(page.tbl)
	T.ok("the table: names and prices", has(text, "Bob1 Smith") and has(text, "5g") and has(text, "(you)"), text)
	T.ok("the title: last search", has(W.plain(page.tblTitle.text), "last search"), page.tblTitle.text)
	-- a commodity search: three sellers of 20 each
	W.list(2589, 120, 20, 3, "Cid")
	W.advance(1)
	X.ScanItems({"2589"})
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	live = X.SellersNow("2589")
	T.check("commodity: three sellers", live and #live.rows, 3)
	T.check("commodity: 20 each", live and live.rows[1].units, 20)
	-- sellers the game gives no name for: one row for all of them, last
	X.KeepSellersNow("2592", {
		{quantity = 30, unitPrice = 300, owners = {"Dan Smith"}, totalNumberOfOwners = 3},
		{quantity = 10, unitPrice = 310, owners = {}, totalNumberOfOwners = 1},
		{quantity = 5, unitPrice = 290, owners = {"player"}, totalNumberOfOwners = 1, containsOwnerItem = true},
	})
	live = X.SellersNow("2592")
	T.check("unnamed: three rows (Dan, you, the others)", #live.rows, 3)
	T.ok("unnamed: Dan's share of a row of three", live.rows[1].name == "Dan Smith" and live.rows[1].units == 10, live.rows[1].name)
	T.check("unnamed: the others last", live.rows[3].name, X.SELLERS_UNNAMED)
	T.check("unnamed: their units (20 + 10)", live.rows[3].units, 30)
	T.ok("unnamed: \"player\" is you", live.rows[2].mine == true and live.rows[2].name == X.CharKey(), live.rows[2].name)
	-- after a reload: the session list is gone, the history stays (the commodity search today counted 3 sellers)
	X = W.reload()
	W.advance(1)
	T.check("not saved", X.SellersNow("15210"), nil)
	page = show(X, "2589", "Sellers", "sellers")
	T.check("history kept", W.plain(page.tiles[1].value.text), tostring(X.SellerStats("2589").now.sellers))
	T.check("the last search of the day wins", X.SellerStats("2589").now.sellers, 3)
end)

-- [[ Crafting ]]
T.scene("36 craft: the crafting cost on a past day from the reagents' day prices", function()
	local X = W.start()
	local today = X.Day()
	local D1, D2 = today - 10, today - 9
	-- Copper Ore 100 then 120; Copper Bar listed at 300; Tin Bar at 250, Tin Ore 400
	X.Record("2770", dayStart(X, D1) + 3600, 100, 100, 20, 2, "Copper Ore", 1)
	X.Record("2840", dayStart(X, D1) + 3600, 300, 300, 20, 2, "Copper Bar", 1)
	X.Record("3576", dayStart(X, D1) + 3600, 250, 250, 20, 2, "Tin Bar", 1)
	X.Record("2771", dayStart(X, D1) + 3600, 400, 400, 20, 2, "Tin Ore", 1)
	X.Record("2770", dayStart(X, D2) + 3600, 120, 120, 20, 2)
	-- Smelt Copper (2657): one ore makes one bar
	T.check("smelt copper on day 1", X.CraftCostOn(2657, D1), 100)
	T.check("smelt copper on day 2", X.CraftCostOn(2657, D2), 120)
	T.check("3 days later: the last price carried", X.CraftCostOn(2657, D2 + 3), 120)
	local c, missing = X.CraftCostOn(2657, D1 - 1)
	T.check("before any price: no cost", c, nil)
	T.check("before any price: one reagent missing", missing, 1)
	-- Smelt Bronze (2659): copper bar + tin bar make two; the copper bar is cheaper smelted (100) than bought (300)
	local cost, how = X.ReagentCostOn(2840, D1)
	T.ok("copper bar on day 1: crafted", cost == 100 and how == "craft", tostring(cost) .. " " .. tostring(how))
	cost, how = X.ReagentCostOn(3576, D1)
	T.ok("tin bar on day 1: bought", cost == 250 and how == "ah", tostring(cost) .. " " .. tostring(how))
	T.check("bronze on day 1: (100 + 250) / 2", X.CraftCostOn(2659, D1), 175)
	T.check("bronze on day 2: the dearer ore", X.CraftCostOn(2659, D2), 185)
	-- vendor reagents: Minor Healing Potion = Empty Vial + Mild Spices (vendor) + Peacebloom (auction house)
	X.db.vbuy[3371] = {p = 4, at = X.Now(), from = "Test"}
	X.db.vbuy[2678] = {p = 10, at = X.Now(), from = "Test"}
	X.Record("2447", dayStart(X, D1) + 3600, 30, 30, 20, 2, "Peacebloom", 1)
	X.Record("2447", dayStart(X, D2) + 3600, 50, 50, 20, 2)
	X.Fire("XNAH_PRICES")
	T.check("potion on day 1: 4 + 10 + 30", X.CraftCostOn(1244431, D1), 44)
	T.check("potion on day 2: 4 + 10 + 50", X.CraftCostOn(1244431, D2), 64)
	cost, how = X.ReagentCostOn(3371, D1)
	T.ok("the vial: vendor", cost == 4 and how == "vendor", tostring(cost) .. " " .. tostring(how))
	-- a vial listed cheaper than the vendor: the cheaper one (as Craft.lua does)
	X.Record("3371", dayStart(X, D1) + 4000, 2, 2, 20, 2, "Empty Vial", 1)
	X.Fire("XNAH_PRICES")
	T.check("potion with a cheap vial: 2 + 10 + 30", X.CraftCostOn(1244431, D1), 42)
	-- the same rule as now: buying from vendors only when nothing is listed, setting off
	X.S().vendorBuyFirst = false
	X.Fire("XNAH_PRICES")
	T.check("vendor not first: the vial still the cheaper", X.CraftCostOn(1244431, D1), 42)
	X.S().vendorBuyFirst = true
	-- today: the same as Craft.lua (a price today; the day price of today is the market value so far today)
	X.Record("2770", dayStart(X, today) + 60, 130, 130, 20, 2)
	X.Fire("XNAH_PRICES")
	T.check("today: the same as the crafting cost now", X.CraftCostOn(2657, today), X.RecipeCost(2657))
	-- a crazy price is left out of the day prices
	for d = 8, 1, -1 do X.Record("2771", dayStart(X, today - d) + 3600, 400, 400, 20, 2) end
	X.Record("2771", dayStart(X, today) + 3600, 40000, 40000, 20, 2)
	X.Record("2771", dayStart(X, today) + 7200, 40000, 40000, 20, 2)
	X.Record("2771", dayStart(X, today) + 9000, 40000, 40000, 20, 2)
	X.Fire("XNAH_PRICES")
	T.ok("a crazy day price is not used", (X.DayPrice("2771", today) or 0) <= 400, X.DayPrice("2771", today))
end)

T.scene("36 craft: the margin over time - average, best day, trend; recipes that use an item", function()
	local X = W.start()
	local today = X.Day()
	X.db.vbuy[3371] = {p = 4, at = X.Now(), from = "Test"}
	X.db.vbuy[2678] = {p = 10, at = X.Now(), from = "Test"}
	-- Peacebloom gets dearer every day (3000 -> 4900), the potion stays at 1g: the margin shrinks 1s a day
	daily(X, "2447", 20, function(d) return 3000 + 100 * (20 - d) end, "Peacebloom")
	daily(X, "118", 20, function() return 10000 end, "Minor Healing Potion")
	local list = X.CraftSeries(1244431, today - 29, today)
	T.check("a point a day: 20 days + today (carried)", #list, 21)
	T.check("first day: the cost", list[1].cost, 3014)
	T.check("first day: sells for after the cut", list[1].sell, 9500)
	T.check("first day: the margin", list[1].margin, 6486)
	T.check("today: yesterday's prices", list[#list].margin, 4586)
	local m = X.CraftMargin(1244431)
	T.check("margin now", m.margin, 4586)
	T.check("cost now", m.cost, 4914)
	T.near("average margin, 30 days", m.avg30, (5536 * 20 + 4586) / 21, 0.01)
	T.check("from 21 days", m.days30, 21)
	T.check("best day", m.best.day, today - 20)
	T.check("best margin", m.best.margin, 6486)
	T.ok("trend: shrinking", m.trend < 0 and m.trendWord == "shrinking", tostring(m.trend) .. " " .. tostring(m.trendWord))
	-- a steady market: steady
	daily(X, "2770", 20, function() return 100 end, "Copper Ore")
	daily(X, "2840", 20, function() return 300 end, "Copper Bar")
	m = X.CraftMargin(2657)
	T.check("steady: the margin", m.margin, 300 * 0.95 - 100)
	T.check("steady: the word", m.trendWord, "steady")
	-- cached; new prices work it out again
	T.ok("cached", X.CraftMargin(2657) == m)
	X.Record("2840", X.Now() + 60, 400, 400, 20, 2)
	X.Fire("XNAH_PRICES")
	T.check("new prices: again", X.CraftMargin(2657).margin, 400 * 0.95 - 100)
	-- the recipes that use Peacebloom, with their margin now
	local uses = X.ReagentUses(2447)
	local row
	for _, r in ipairs(uses) do if r.rid == 1244431 then row = r end end
	T.ok("the potion is among them", row ~= nil, #uses)
	T.check("what it makes", row and row.key, "118")
	T.check("how many it uses", row and row.count, 1)
	T.check("its margin", row and row.margin, 4586)
	T.ok("best margin first", uses[1].margin ~= nil)
	T.check("an item no recipe uses", #X.ReagentUses(15210), 0)
	-- 10,000 items do not matter: a year of one recipe stays quick
	daily(X, "2771", 365, function(d) return 400 + d % 7 end, "Tin Ore")
	local started = os.clock()
	local year = X.CraftSeries(3304, today - 364, today)
	T.note(string.format("crafting history: a year of one recipe (%d days) in %.0f ms", #year, (os.clock() - started) * 1000))
	T.ok("a year of points (thinned to weeks after 60 days)", #year >= 300, #year)
end)

T.scene("36 craft: the page with no data, an item made by nothing, a reagent, full data", function()
	local X = W.start()
	-- made by nothing and used by nothing
	local page = show(X, "15210", "Crafting", "craft")
	T.ok("the page is shown", page and page:IsVisible())
	T.ok("a plain line: no recipe makes it", page.none:IsVisible() and has(W.plain(page.none.text), "No recipe makes"), page.none.text)
	T.ok("graphs hidden", not page.gPrice:IsVisible() and not page.gMargin:IsVisible())
	T.ok("no recipe uses it", has(page.tbl.empty.text, "No recipe uses"), page.tbl.empty.text)
	T.check("tiles empty", W.plain(page.tiles[1].value.text), "-")
	-- a reagent made by nothing: the recipes that use it
	X.UI.ShowItem("2770")
	W.advance(0.3)
	T.ok("ore: no recipe makes it", page.none:IsVisible())
	T.ok("ore: used by smelting", #page.tbl.items >= 1)
	T.ok("ore: the title counts them", has(W.plain(page.usedTitle.text), "Recipes that use it: " .. #page.tbl.items))
	-- made by a recipe, no prices
	X.UI.ShowItem("2840")
	W.advance(0.3)
	T.ok("bar: the graphs", page.gPrice:IsVisible() and page.gMargin:IsVisible() and not page.none:IsVisible())
	T.ok("bar: the recipe", has(W.plain(page.pick.label.text), "Smelt Copper"), page.pick.label.text)
	T.ok("bar: no prices yet", has(W.screen(page.gPrice), "No prices"), W.screen(page.gPrice))
	-- full data
	daily(X, "2770", 30, function(d) return 100 + 20 * d end, "Copper Ore") -- cheaper every day: the margin grows
	daily(X, "2840", 30, function() return 300 end, "Copper Bar")
	X.Fire("XNAH_PRICES") -- (a scan fires it)
	X.UI.Refresh(true)
	W.advance(0.3)
	local info = page.gPrice.GetInfo()
	T.check("bar: two lines", #info.series, 2)
	T.check("bar: legend", info.legend[1] and info.legend[1].label, "Crafting cost (one)")
	info = page.gMargin.GetInfo()
	T.check("bar: the margin line", #info.series, 1)
	T.check("bar: a break even line", info.levels[1] and info.levels[1].v, 0)
	T.ok("tile: margin now", has(W.plain(page.tiles[1].value.text), "+"), page.tiles[1].value.text)
	T.ok("tile: best day has a date", page.tiles[3].sub.text ~= "", page.tiles[3].sub.text)
	T.ok("tile: a trend word", has(W.plain(page.tiles[4].value.text), "growing"), page.tiles[4].value.text)
	-- ranges
	W.click("90 days", page)
	W.advance(0.3)
	T.check("range kept", X.S().craftRange, 2)
	-- the bar is used by many recipes: click one -> its item
	T.ok("bar: used by recipes", #page.tbl.items > 3, #page.tbl.items)
	local r1 = page.tbl.items[1]
	page.tbl.rows[1]:Click("LeftButton")
	W.advance(0.3)
	T.check("click a recipe: shows what it makes", X.UI.itemKey, r1.key)
	-- the hover lines of the tiles and columns
	T.ok("column hover lines", page.tbl.columns[6].tip ~= nil)
	W.hover(page.tiles[2])
	T.ok("tile hover: what it means", has(W.tipText(), "average day"), W.tipText())
	W.unhover(page.tiles[2])
	W.hover(page.pick)
	T.ok("recipe hover: the recipe", has(W.tipText(), "Makes"), W.tipText())
	W.unhover(page.pick)
	-- an empty database: every new page refreshes without an error
	X = W.reload()
	W.advance(1)
	for _, k in ipairs({"compare", "sellers", "craft"}) do
		X.S().itemPage = k
		X.UI.ShowItem("999999")
		W.advance(0.3)
		X.UI.Refresh(true)
		W.advance(0.3)
		T.ok("unknown item: page " .. k, pageOf(X, k):IsVisible())
	end
end)

T.scene("36 craft: the recipe picker when several recipes make an item", function()
	local X = W.start()
	-- find an item made by two or more recipes in the built-in list
	local id
	for _, rid in ipairs(X.AllRecipeIDs()) do
		local r = X.Recipe(rid)
		if r and r.out and #X.RecipesFor(r.out) >= 2 then id = r.out break end
	end
	T.ok("an item with two recipes exists", id ~= nil)
	if not id then return end
	local key = tostring(id)
	local page = show(X, key, "Crafting", "craft")
	T.ok("the picker says how many", has(W.plain(page.pick.label.text), "of " .. #X.RecipesFor(id)), page.pick.label.text)
	local before = page.pick.rid
	page.pick:Click("LeftButton")
	W.advance(0.2)
	local menu = openMenu()
	T.ok("a menu of recipes", menu ~= nil)
	local other
	for _, rid in ipairs(X.RecipesFor(id)) do if rid ~= before then other = rid break end end
	if menu and other then
		local r = X.Recipe(other)
		W.click(r.name or X.RecipeTitle(other), menu)
		W.advance(0.3)
		T.check("picked", page.pick.rid, other)
	end
end)
