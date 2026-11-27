-- XNAH test scenes, part 33: the ground for the new pages - the page registration of the Trends view, the Items view
-- (the item on the right) and Your gold (UI.AddTrendsPage, UI.AddItemPage, UI.AddGoldPage), the Trends view with no
-- pages, the Opportunities view taken out (and its saved settings cleaned up), several lines on one graph with a
-- legend and number / percent labels, the seller history (X.SellerHistory), item groups (X.ItemGroup) and the gold
-- listed at each full scan.

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end

-- a test page that remembers how it was built and refreshed
local function probe()
	local pr = {builds = 0, refreshes = 0}
	pr.build = function(page, w, h)
		pr.builds, pr.page, pr.w, pr.h = pr.builds + 1, page, w, h
		page.label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		page.label:SetPoint("TOPLEFT", 0, 0)
	end
	pr.refresh = function(page, key)
		pr.refreshes, pr.lastPage, pr.key = pr.refreshes + 1, page, key
		page.label:SetText("probe page " .. tostring(key))
		return "3 things"
	end
	return pr
end

local function history(X, key, price, days, name)
	for d = days, 1, -1 do X.Record(key, X.Now() - d * DAY, price, price, 20, 4, name, 1) end
end

T.scene("pages: the three page functions (Trends, Items, Your gold)", function()
	local X = W.start()
	local UI = X.UI
	T.ok("the functions exist", type(UI.AddTrendsPage) == "function" and type(UI.AddItemPage) == "function" and
		type(UI.AddGoldPage) == "function")
	-- added before the window is first opened (as files do when they load)
	local tp, tp0, ip, gp = probe(), probe(), probe(), probe()
	UI.AddTrendsPage("test", "Test Trend", tp.build, tp.refresh, 5, "A page of the tests.")
	UI.AddTrendsPage("first", "First Trend", tp0.build, tp0.refresh, 1)
	UI.AddTrendsPage("test", "Test Trend", tp.build, tp.refresh, 5, "A page of the tests.") -- again: replaced, not twice
	UI.AddItemPage("test", "Test Item", ip.build, ip.refresh, 9)
	UI.AddGoldPage("test", "Test Gold", gp.build, gp.refresh, 9, "Gold of the tests.")
	T.check("trends: two pages, lowest order first", UI.TRENDS_PAGES[1].key .. "," .. UI.TRENDS_PAGES[2].key .. "," .. #UI.TRENDS_PAGES,
		"first,test,2")
	local keys = {}
	for _, pg in ipairs(UI.GOLD_PAGES) do keys[#keys + 1] = pg.key end
	T.check("gold: the old pages keep their order, the new one after", table.concat(keys, ","), "overview,items,recent,chars,test")
	keys = {}
	for _, pg in ipairs(UI.ITEM_PAGES) do keys[#keys + 1] = pg.key end
	T.check("items: Overview first", table.concat(keys, ","), "overview,test")
	T.check("nothing built before the window opens", tp.builds + ip.builds + gp.builds, 0)

	-- Trends
	history(X, "2589", 120, 5, "Linen Cloth")
	history(X, "2592", 300, 5, "Wool Cloth")
	X.UI.Open("trends")
	W.advance(0.5)
	local p = X.UI.tabs.trends.panel
	T.check("trends: built once", tp.builds, 1)
	T.check("trends: page size", tp.w .. " x " .. tp.h, "1080 x 574")
	T.ok("trends: the first page shown at first", tp0.refreshes > 0 and tp.refreshes == 0, tp0.refreshes .. "/" .. tp.refreshes)
	W.click("Test Trend", p)
	W.advance(0.3)
	T.ok("trends: picked page refreshed", tp.refreshes > 0 and tp.lastPage == tp.page)
	T.ok("trends: its page shown, the other hidden", tp.page:IsVisible() and not tp0.page:IsVisible())
	T.check("trends: kept", X.S().trendsPage, "test")
	T.ok("trends: the count text", has(W.screen(p), "3 things"), W.screen(p))
	T.ok("trends: the help line", has(W.screen(p), "A page of the tests."), W.screen(p))
	T.ok("trends: no Nothing here yet", not has(W.screen(p), "Nothing here yet"))

	-- Items: the header and Buy cheapest now stay on every page
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = X.UI.tabs.items.panel
	T.check("items: page size", ip.w .. " x " .. ip.h, "810 x 532")
	T.ok("items: Overview at first", panel.tiles[1]:IsVisible() and panel.graph:IsVisible() and not ip.page:IsVisible())
	W.click("Test Item", panel)
	W.advance(0.3)
	T.check("items: refreshed with the item", ip.key, "2589")
	T.ok("items: the page shown, Overview hidden", ip.page:IsVisible() and not panel.tiles[1]:IsVisible() and
		not panel.ladder:IsVisible())
	T.ok("items: the header on the page", panel.name:IsVisible() and has(panel.name.text, "Linen Cloth") and panel.star:IsVisible())
	T.ok("items: Buy cheapest now on the page", panel.buy:IsVisible())
	local n = ip.refreshes
	X.UI.ShowItem("2592")
	W.advance(0.3)
	T.check("items: another item, the page refreshed with it", ip.key, "2592")
	T.ok("items: refreshed again", ip.refreshes > n)
	T.check("items: the page stays", X.S().itemPage, "test")
	W.click("Overview", panel)
	W.advance(0.3)
	T.ok("items: back on Overview", panel.tiles[1]:IsVisible() and not ip.page:IsVisible())
	T.ok("items: Overview filled for the item", has(W.plain(panel.tiles[1].value.text), "3s"), panel.tiles[1].value.text)

	-- Your gold
	X.UI.Open("gold")
	W.advance(0.3)
	local g = X.UI.tabs.gold.panel
	T.check("gold: page size", gp.w .. " x " .. gp.h, "1080 x 520")
	for _, title in ipairs({"Overview", "Best sellers", "Recent", "Characters", "Test Gold"}) do
		T.ok("gold: button " .. title, W.findButton(title, g) ~= nil)
	end
	W.click("Test Gold", g)
	W.advance(0.3)
	T.ok("gold: picked page refreshed", gp.refreshes > 0 and gp.page:IsVisible())
	T.check("gold: kept", X.S().goldView, "test")
	T.ok("gold: tiles still on top", g.tiles[1]:IsVisible())
	T.ok("gold: count and help", has(W.screen(g), "3 things") and has(W.screen(g), "Gold of the tests."), W.screen(g))
	W.click("Best sellers", g)
	W.advance(0.3)
	T.ok("gold: the old pages work", g.views.items.tbl:IsVisible() and not gp.page:IsVisible())
	-- the sorting the old pages remember keeps its old name ("gold:2" = Best sellers)
	T.check("gold: Best sellers sorting name", g.views.items.tbl.saveKey, "gold:2")
	T.check("gold: Recent sorting name", g.views.recent.tbl.saveKey, "gold:3")
	T.check("gold: flips sorting name", g.views.overview.flips.saveKey, "gold:1")
	-- after a reload: the page picked last is shown again; a page that is not there any more: the first one
	X.UI.Open("trends")
	W.advance(0.3)
	X = W.reload()
	W.advance(1)
	X.UI.Open("gold")
	W.advance(0.3)
	T.check("after a reload: the gold page kept", X.S().goldView, "items")
	T.ok("after a reload: Best sellers shown", X.UI.tabs.gold.panel.views.items:IsVisible())
	X.UI.Open("trends")
	W.advance(0.3)
	T.ok("after a reload: the test trend page is gone, Nothing here yet", has(W.screen(X.UI.tabs.trends.panel), "Nothing here yet"))
	X.UI.ShowItem("2589")
	W.advance(0.3)
	T.ok("after a reload: the item page that is gone falls back to Overview", X.UI.tabs.items.panel.tiles[1]:IsVisible())
end)

T.scene("pages: the Trends view with no pages", function()
	local X = W.start()
	T.check("view order and title", X.UI.tabs.trends.n .. " " .. X.UI.tabs.trends.title, "4 Trends")
	X.UI.Open()
	local f = X.UI.Frame()
	W.click("Trends", f)
	W.advance(0.3)
	T.check("the Trends button opens it", X.UI.current, "trends")
	local p = X.UI.tabs.trends.panel
	T.ok("says Nothing here yet", has(W.screen(p), "Nothing here yet"), W.screen(p))
	T.check("no page buttons", next(p.pageButtons), nil)
	X.UI.Refresh(true)
	W.advance(0.3)
	T.ok("still fine after a refresh", has(W.screen(p), "Nothing here yet"))
	-- the views in the header, in order
	local keys = {}
	for _, k in ipairs(X.UI.order) do keys[#keys + 1] = k end
	T.check("the views", table.concat(keys, ","), "items,market,gold,trends,scan")
end)

T.scene("pages: the Opportunities view is gone", function()
	local X = W.start()
	T.check("no opps view", X.UI.tabs.opps, nil)
	T.check("no X.Deals", X.Deals, nil)
	T.check("no list of its rows", X.UI.OppsRows, nil)
	T.check("no deal settings", X.S().dealPct, nil)
	X.UI.Open()
	local f = X.UI.Frame()
	T.ok("no Opportunities button", W.findButton("Opportunities", f) == nil)
	X.UI.Open("opps")
	T.check("an old link to it opens Items", X.UI.current, "items")
	X.UI.Open("deals")
	T.check("an older one too", X.UI.current, "items")
	X.UI.Open("scan")
	T.ok("Settings: no Opportunities box", not has(W.screen(X.UI.tabs.scan.panel), "Opportunities") and
		not has(W.screen(X.UI.tabs.scan.panel), "Far under usual"), W.screen(X.UI.tabs.scan.panel))
	-- the functions the other views and the tooltip use are still there
	for _, name in ipairs({"Usual", "Movers", "Summary", "VendorFlips", "BelowVendor", "UnderDE", "Resets", "FewSellers"}) do
		T.ok("kept: X." .. name, type(X[name]) == "function")
	end
	-- the window saved on Opportunities opens on Items
	X.S().tab = "opps"
	X = W.reload()
	W.advance(1)
	X.UI.Open()
	T.check("saved on opps: opens Items", X.UI.current, "items")
end)

T.scene("pages: the saved settings of Opportunities are cleaned up once", function()
	local X = W.start()
	local S = X.S()
	S.dealPct, S.dealMinProfit, S.oppsFilter = 45, 2500, {kind = "vflip", minProfit = 100}
	S.tab = "opps"
	S.sorts = {["opps:1"] = {5, true}, ["market:1"] = {3, false}, ["gold:2"] = {3, true}}
	S.cut, S.staleHours, S.minSamples = 6, 48, 4
	X.SetWatched("2589", true)
	X.Record("2589", X.Now() - 3600, 100, 110, 50, 5, "Linen Cloth", 1)
	X.db.cleanup = 2 -- saved by v0.9.0
	X = W.reload()
	W.advance(1)
	S = X.S()
	T.check("cleanup number", X.db.cleanup, 3)
	for _, k in ipairs({"dealPct", "dealMinProfit", "oppsFilter"}) do T.check("setting deleted: " .. k, S[k], nil) end
	T.ok("the tab forgotten", S.tab ~= "opps", S.tab)
	T.check("its sorting deleted", S.sorts["opps:1"], nil)
	T.ok("other sorting kept", S.sorts["market:1"] ~= nil and S.sorts["gold:2"] ~= nil)
	T.check("settings in use kept: cut", S.cut, 6)
	T.check("settings in use kept: old after", S.staleHours, 48)
	T.check("settings in use kept: days needed", S.minSamples, 4)
	T.ok("watch list and prices kept", X.Watched("2589") and X.Items()["2589"] and X.Items()["2589"].cur ~= nil)
	-- once only
	X.S().dealPct = 30
	X = W.reload()
	W.advance(1)
	T.check("not cleaned twice", X.S().dealPct, 30)
end)

T.scene("pages: several lines on one graph, a legend, number and percent labels", function()
	local X = W.start()
	local K = X.K
	local now = X.Now()
	local g = K.Graph(W.env.UIParent, 600, 200)
	local function pts(base, step)
		local out = {}
		for i = 0, 9 do out[#out + 1] = {now - (9 - i) * DAY, base + i * step} end
		return out
	end
	-- an index around 100: three lines, the last one without a colour, a flat line at 100
	g:SetSeries({
		{points = pts(100, 1), color = {1, 0, 0}, label = "All items"},
		{points = pts(95, 1.5), color = {0, 1, 0}, label = "Cloth"},
		{points = pts(104, -0.5), label = "Herbs"},
		{points = pts(98, 0.2)}, -- no label: not in the legend
	}, {legend = true, labels = "percent", levels = {{v = 100, color = {0.6, 0.6, 0.6}, label = "start"}}})
	local info = g.GetInfo()
	T.check("four lines", #info.series, 4)
	T.check("legend: the three named lines", #info.legend, 3)
	T.check("legend: names in order", info.legend[1].label .. "," .. info.legend[2].label .. "," .. info.legend[3].label,
		"All items,Cloth,Herbs")
	T.check("own colours kept", info.series[1].color[1] .. info.series[2].color[2], "11")
	local c3, p3 = info.series[3].color, K.GRAPH_COLORS[3]
	T.ok("no colour: the third colour of the list", c3[1] == p3[1] and c3[2] == p3[2] and c3[3] == p3[3])
	local text = W.screen(g)
	T.ok("legend shown", has(text, "All items") and has(text, "Cloth") and has(text, "Herbs"), text)
	T.ok("percent labels on the scale", has(text, "100%"), text)
	T.ok("no money on the scale", not has(text, "1c") and not has(text, "|cff"), text)
	T.check("percent: hover format", info.format(102.5), "102.5%")
	T.check("percent: whole", info.format(100), "100%")
	T.check("flat line kept", #info.levels, 1)
	-- a count: plain numbers, steps under 1 for small values
	g:SetSeries({{points = pts(1, 0.2), label = "Sellers"}}, {labels = "number"})
	info = g.GetInfo()
	T.check("number: no legend unless asked", #info.legend, 0)
	T.check("number: thousands", info.format(1234), "1,234")
	T.check("number: a fraction", info.format(2.5), "2.5")
	text = W.screen(g)
	T.ok("number: a scale step under 1", has(text, ".5") or has(text, ".2") or has(text, ".25"), text)
	-- the legend in the top right corner works too
	g:SetSeries({{points = pts(5, 1), label = "A"}, {points = pts(6, 1), label = "B"}}, {legend = "TOPRIGHT", labels = "number"})
	T.check("top right legend", #g.GetInfo().legend, 2)
	-- an old call: money, no legend, colours as given
	g:SetSeries({{points = pts(10000, 100), color = {1, 1, 1}, label = "Market value"}})
	info = g.GetInfo()
	T.check("old call: no legend", #info.legend, 0)
	T.check("old call: money labels", info.format(12345), X.Money(12345, true))
	T.check("old call: labels", info.labels, "money")
	T.ok("old call: legend hidden again", not has(W.screen(g), "Herbs"), W.screen(g))
end)

T.scene("pages: seller history - sellers, the biggest seller, undercuts", function()
	local X = W.start()
	local now = X.Now()
	local today = X.Day()
	T.check("nothing known: empty", #X.SellerHistory("2589"), 0)
	-- undercuts: the lowest price went down from one scan to the next while listed
	local key = "2589"
	local t = now - 5 * 3600
	X.Record(key, t, 100, 110, 50, 5, "Linen Cloth", 1)
	X.Record(key, t + 600, 95, 110, 50, 5)    -- undercut 1
	X.Record(key, t + 1200, 99, 110, 50, 5)   -- up: no
	X.Record(key, t + 1800, 90, 108, 50, 5)   -- undercut 2
	X.Record(key, t + 2400, nil, nil, 0, 0)   -- sold out: no
	X.Record(key, t + 3000, 80, 100, 10, 1)   -- listed again after none: no
	X.Record(key, t + 3600, 79, 100, 10, 1)   -- undercut 3
	X.Record(key, t + 3000, 10, 100, 10, 1)   -- an older observation: ignored
	local sh = X.SellerHistory(key)
	T.check("one day", #sh, 1)
	T.check("the day", sh[1] and sh[1].day, today)
	T.check("three undercuts today", sh[1] and sh[1].undercuts, 3)
	T.check("no seller numbers yet", sh[1] and sh[1].sellers, nil)
	-- the sellers of a search (the last of the day is kept)
	X.RecordSellers(key, now, 6, 0.42, "Bigseller")
	X.RecordSellers(key, now + 1, 5, 0.555, "Other,Name;x")
	sh = X.SellerHistory(key)
	T.check("sellers", sh[1].sellers, 5)
	T.check("top share 0-100", sh[1].topShare, 56)
	T.check("name without , or ;", sh[1].topName, "OtherNamex")
	T.check("undercuts kept", sh[1].undercuts, 3)
	-- a real search of a gear item at the auction house: its sellers by name
	W.openAH()
	W.list(15210, 50000, 1, 3, "Bob")    -- Bob1 Smith, Bob2 Smith, Bob3 Smith
	W.list(15210, 52000, 1, 1, "Bob1")   -- Bob1 Smith again: 2 of 4
	W.advance(1)
	X.ScanItems({"15210"})
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	sh = X.SellerHistory("15210")
	T.check("search: 3 sellers", sh[#sh] and sh[#sh].sellers, 3)
	T.check("search: the biggest has half", sh[#sh] and sh[#sh].topShare, 50)
	T.check("search: its name", sh[#sh] and sh[#sh].topName, "Bob1 Smith")
	-- the next days, then 90 days: older than 60 days one point a week
	local it = X.Items()[key]
	it.sh = nil
	for d = 90, 0, -1 do
		local dt = now - d * DAY
		X.RecordSellers(key, dt, 10 + (d % 2), 0.3, d % 7 == 0 and "Weekly" or nil)
		X.CountUndercut(it, dt)
		X.CountUndercut(it, dt + 60)
	end
	local before = #X.SellerHistory(key)
	T.check("91 days, one point each", before, 91)
	X.Thin(it, today)
	sh = X.SellerHistory(key)
	T.ok("thinned: fewer points", #sh < before and #sh >= 61 + 4, #sh)
	local old = sh[1]
	T.ok("a week point: sellers averaged", old.sellers == 10 or old.sellers == 11, old.sellers)
	T.check("a week point: undercuts a day", old.undercuts, 2)
	T.check("a week point: top share", old.topShare, 30)
	T.check("the last 60 days kept as they are", sh[#sh].day, today)
	-- kept keepDays days
	X.S().keepDays = 30
	X.RecordSellers(key, now + 60, 3, 0.5, "Late")
	T.ok("older than keepDays dropped", X.SellerHistory(key)[1].day >= today - 30, X.SellerHistory(key)[1].day)
	X.S().keepDays = 365
	-- a reload keeps it, two records are joined (Sync accounts, realm keys)
	local n = #X.SellerHistory(key)
	X = W.reload()
	W.advance(1)
	T.check("after a reload", #X.SellerHistory(key), n)
	local a = {id = 2592, sh = X.b36(today - 2) .. ",3,14,1,Ann;" .. X.b36(today - 1) .. ",4,,2,"}
	local b = {id = 2592, sh = X.b36(today - 1) .. ",5,1e,5,Bea;" .. X.b36(today) .. ",6,1e,,Cid", cur = {t = X.Now()}}
	local m = X.MergeItem(a, b)
	local list = X.UnpackSellers(m.sh)
	T.check("joined: three days", #list, 3)
	T.check("joined: the same day takes the newer sellers", list[2][2], 5)
	T.check("joined: and the most undercuts", list[2][4], 5)
	T.check("joined: a day only in one", list[1][5], "Ann")
end)

T.scene("pages: seller history - size on a test scene", function()
	local X = W.start()
	local now = X.Now()
	local N = 40
	-- every day: the sellers of a search (when withSellers) and 0-3 undercuts; thinned once a week (in the game X.Record
	-- does it once a day)
	local function fill(days, withSellers)
		for i = 1, N do
			local key = tostring(300000 + i)
			local it = X.Item(key, true)
			it.sh = nil
			for d = days - 1, 0, -1 do
				local t = now - d * DAY
				if withSellers then X.RecordSellers(key, t, 5 + i % 40, 0.2 + (i % 50) / 100, "Seller" .. (i % 97) .. " Trader") end
				for _ = 1, (i + d) % 4 do X.CountUndercut(it, t) end
				if d % 7 == 0 then X.Thin(it, X.Day(t)) end
			end
			X.Thin(it, X.Day())
		end
		local bytes = 0
		for i = 1, N do bytes = bytes + #(X.Items()[tostring(300000 + i)].sh or "") end
		return bytes / N
	end
	local s30, u30 = fill(30, true), fill(30, false)
	local s365, u365 = fill(365, true), fill(365, false)
	T.note(string.format("seller history: %.0f bytes / item after 30 days (searched every day: sellers + name + undercuts), " ..
		"%.0f with undercuts only (items never searched); after a year (thinned): %.0f and %.0f", s30, u30, s365, u365))
	T.ok("30 days with sellers: under 1 KB an item", s30 < 1024, s30)
	T.ok("a year with sellers: under 2 KB an item", s365 < 2048, s365)
end)

T.scene("pages: item groups", function()
	local X = W.start()
	W.items[2589].subType = "Cloth"
	W.items[118].class, W.items[118].subClass, W.items[118].subType = 0, 1, "Potion"
	local c, s, name, sub = X.ItemGroup("2589")
	T.check("cloth: trade goods", tostring(c) .. "/" .. tostring(s) .. " " .. name .. " " .. tostring(sub), "7/0 Trade Goods Cloth")
	c, s, name = X.ItemGroup("15210:-19")
	T.check("a sword with a suffix: armor (the world's guess for gear)", tostring(c) .. " " .. name, "4 Armor")
	c, s, name, sub = X.ItemGroup("118")
	T.check("a potion: consumables", tostring(c) .. "/" .. tostring(s) .. " " .. name .. " " .. tostring(sub), "0/1 Consumables Potion")
	c, s, name = X.ItemGroup("999999")
	T.check("unknown item", tostring(c) .. " " .. tostring(s) .. " " .. name, "nil nil Other")
	c, s, name = X.ItemGroup(nil)
	T.check("no key", name, "Other")
	T.check("group names: a plain list", X.ITEM_GROUPS[7], "Trade Goods")
	-- nothing saved for it
	T.ok("not in the saved data", not W.saveText(W.env.XNAHDB):find("Trade Goods", 1, true))
end)

T.scene("pages: gold listed and sellers at each full scan", function()
	local X = W.start()
	W.openAH()
	W.list(2589, 120, 20, 3, "Ann")       -- 3 auctions of 20 at 1s 20c each
	W.list(2592, 300, 10, 2, "Bea")       -- 2 of 10 at 3s
	W.list(15210, 50000, 1, 1, "Ann1")    -- one sword at 5g (Ann1 Smith sells cloth too)
	W.ah[#W.ah + 1] = {itemID = 2770, count = 5, buyout = 0, bid = 100, owner = "Cid Smith", timeLeft = 2} -- bid only
	local gold, units, owners = 0, 0, {}
	for _, a in ipairs(W.ah) do
		gold = gold + (a.buyout or 0)
		units = units + (a.count or 1)
		owners[a.owner] = true
	end
	W.advance(1)
	T.ok("full scan", T.fullScan(X))
	W.advance(2)
	local scans = X.Scans("full")
	local sc = scans[#scans]
	T.check("one full scan", #scans, 1)
	T.check("gold listed", sc and sc.gold, gold)
	T.check("items listed", sc and sc.units, units)
	T.check("different sellers", sc and sc.sellers, T.count(owners))
	T.check("auctions", sc and sc.auctions, #W.ah)
	-- the full scan's seller names also fill the seller history (the game on Forever gives none there)
	local sh = X.SellerHistory("2589")
	T.check("history: sellers of the cloth", sh[1] and sh[1].sellers, 3)
	-- a search of the tracked items: no gold numbers
	X.SetWatched("2589", true)
	X.ScanItems()
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	local all = X.Scans()
	T.check("all scans: two", #all, 2)
	T.check("the search has no gold", all[2].gold, nil)
	T.check("full scans only: still one", #X.Scans("full"), 1)
	-- a full scan without seller names (as on Forever): no sellers number
	W.ah = {}
	W.list(2589, 100, 20, 2)
	for _, a in ipairs(W.ah) do a.owner = nil end
	W.advance(16 * 60)
	T.ok("second full scan", T.fullScan(X))
	W.advance(2)
	scans = X.Scans("full")
	T.check("second: gold", scans[2].gold, 4000)
	T.check("second: no seller names, no sellers number", scans[2].sellers, nil)
	-- kept after a reload, at most X.MAX_SCANS
	X = W.reload()
	W.advance(1)
	T.check("after a reload", X.Scans("full")[2].gold, 4000)
	T.ok("a limit on the list", X.MAX_SCANS >= 200, X.MAX_SCANS)
end)
