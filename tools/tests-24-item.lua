-- XNAH test scenes, part 24: the analysis of one item on the Items view - the fair prices to buy and to sell
-- (X.FairPrices), the twelve number tiles with plain-words tooltips, the header line, the graph (ranges, names under it,
-- the fair price lines), and the three boxes (the auction house now, the best time to sell, crafting and your trades)
-- with and without the auction house open.

local DAY, HOUR = 86400, 3600

local function itemPanel(X)
	local tab = X.UI.tabs.items
	return tab and tab.panel
end
-- one price a day at noon on the realm's clock, `days` days back up to yesterday; fn(n) -> min, mkt (n = 1 oldest)
local function daily(X, key, name, days, fn)
	local shift = X.ServerShift()
	local today = math.floor((X.Now() + shift) / DAY)
	local n = 0
	for d = today - days, today - 1 do
		n = n + 1
		local min, mkt, qty = fn(n)
		X.Record(key, d * DAY - shift + 12 * HOUR, min, mkt, qty or 100, 10, name, 1)
	end
end
local function has(text, part) return text:find(part, 1, true) ~= nil end
local function tipOf(f)
	W.hover(f)
	local text = W.tipText(W.env.GameTooltip.lines)
	W.unhover(f)
	return text
end

T.scene("item page: fair prices to buy and to sell", function()
	local X = W.start()
	-- twelve days: lowest 110, 120 ... 220, market value a fifth higher; one day with a silly low price (5c)
	daily(X, "2589", "Linen Cloth", 12, function(n)
		if n == 6 then return 5, 192 end
		return 100 + n * 10, math.floor((100 + n * 10) * 1.2)
	end)
	local buy, sell, note, days = X.FairPrices("2589")
	-- lowest prices (silly one left out): 110 120 130 140 150 170 ... 220 -> 1 in 4 = the 3rd of 11
	T.check("fair to buy: 1 in 4 of the lowest prices", buy, 130)
	-- market values: 132 144 156 168 180 192 204 216 228 240 252 264 -> the middle (6th of 12)
	T.check("fair to sell: the middle of the market value", sell, 192)
	T.check("days used", days, 12)
	T.ok("a plain note", note and has(note, "Fair to buy") and has(note, "12 days"), note)
	T.check("the same again (kept)", (X.FairPrices("2589")), 130)
	-- many scans on one day count as much as one day
	local shift = X.ServerShift()
	local today = math.floor((X.Now() + shift) / DAY)
	local base = (today - 1) * DAY - shift + 13 * HOUR
	for i = 1, 20 do X.Record("2589", base + i * 60, 300, 360, 100, 10, "Linen Cloth", 1) end
	X.Record("2589", X.Now() - 60, 140, 170, 100, 10, "Linen Cloth", 1)
	buy, sell = X.FairPrices("2589")
	T.ok("a busy day does not take over", buy and buy <= 150, buy)
	T.ok("sell stays near the usual", sell and sell < 260, sell)
	-- never over the 30-day high
	local st = X.Stats("2589")
	T.ok("not over the 30-day high", sell <= (st.high30 or math.huge), tostring(sell) .. " / " .. tostring(st.high30))
	-- too little history
	X.Record("2592", X.Now() - 60, 500, 600, 20, 2, "Wool Cloth", 1)
	local b2, s2, n2 = X.FairPrices("2592")
	T.check("one price: no fair buy", b2, nil)
	T.check("one price: no fair sell", s2, nil)
	T.ok("one price: says why", n2 and has(n2, "Not enough"), n2)
	local b3, _, n3 = X.FairPrices("424242")
	T.check("unknown item", b3, nil)
	T.ok("unknown item: says so", n3 and has(n3, "Never seen"), n3)
end)

T.scene("item page: twelve number tiles with plain tooltips, the header, the graph", function()
	local X = W.start()
	daily(X, "2589", "Linen Cloth", 12, function(n) return 100 + n * 10, math.floor((100 + n * 10) * 1.2) end)
	X.Record("2589", X.Now() - 60, 120, 170, 80, 8, "Linen Cloth", 1)
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	local screen = W.screen(panel)
	for _, label in ipairs({"Cheapest now", "Market value", "Usual price", "Now vs usual", "Trend a week", "Ups and downs",
		"Sells a day", "Listed vs normal", "Fair price to buy", "Fair price to sell", "Vendor pays", "Crafting cost"}) do
		T.ok("tile: " .. label, has(screen, label), screen)
	end
	T.check("twelve tiles", #panel.tiles, 12)
	-- every tile says in plain words what it means
	for i, t in ipairs(panel.tiles) do
		local tip = tipOf(t)
		T.ok("tile " .. i .. ": a tooltip with words", #tip > 40, tip)
	end
	T.ok("cheapest now: 1s 20c", has(W.plain(panel.tiles[1].value.text), "1s 20c"), panel.tiles[1].value.text)
	T.ok("market value: 1s 70c", has(W.plain(panel.tiles[2].value.text), "1s 70c"))
	local usual = X.Usual("2589")
	T.check("now vs usual", W.plain(panel.tiles[4].value.text), math.floor(120 / usual * 100 + 0.5) .. "%")
	T.ok("cheaper than usual: green", has(panel.tiles[4].value.text, "4ade80"))
	T.check("listed now", W.plain(panel.tiles[8].value.text), "80")
	local buy, sell = X.FairPrices("2589")
	T.ok("fair to buy", has(W.plain(panel.tiles[9].value.text), W.plain(X.Money(buy, true))))
	T.ok("fair to sell: what you keep", has(W.plain(panel.tiles[10].sub.text), "keep"))
	T.ok("vendor pays (13c)", has(W.plain(panel.tiles[11].value.text), "13c"), panel.tiles[11].value.text)
	T.ok("no recipe", has(W.plain(panel.tiles[12].value.text), "no recipe"))
	-- the header: how many listed, by whom, when
	T.ok("header: listed and auctions", has(W.plain(panel.sub.text), "80 listed in 8 auctions"), panel.sub.text)
	T.ok("header: updated", has(W.plain(panel.sub.text), "updated"), panel.sub.text)
	-- the graph: lines, the fair prices as two flat lines, the names under it hide them
	local info = panel.graph.GetInfo()
	T.check("two lines", #info.series, 2)
	T.check("two fair lines", #info.levels, 2)
	T.check("fair to buy line", info.levels[2] and info.levels[2].v, buy)
	W.click("Fair prices", panel)
	T.check("hidden", #panel.graph.GetInfo().levels, 0)
	W.click("Fair prices", panel)
	T.check("shown again", #panel.graph.GetInfo().levels, 2)
	W.click("Market value", panel)
	T.check("market value hidden", #panel.graph.GetInfo().series, 1)
	W.click("Market value", panel)
	-- the ranges
	for i, name in ipairs({"7 days", "30 days", "90 days", "1 year"}) do
		W.click(name, panel)
		T.check("range " .. name, X.S().itemRange, i)
	end
	W.click("7 days", panel)
	T.ok("7 days: fewer points than a year", #panel.graph.GetInfo().series[1].pts <= 8)
	W.click("30 days", panel)
	-- an item with little history: no fair lines, says so
	X.Record("2592", X.Now() - 60, 500, 600, 20, 2, "Wool Cloth", 1)
	X.UI.ShowItem("2592")
	W.advance(0.3)
	T.check("little history: no lines", #panel.graph.GetInfo().levels, 0)
	T.ok("little history: not known yet", has(W.screen(panel), "not known yet"))
	T.ok("little history: no Fair prices name", not has(W.screen(panel), "Fair prices"))
	T.ok("trend: too new", has(W.plain(panel.tiles[5].value.text), "too new"))
end)

T.scene("item page: the three boxes, away from and at the auction house", function()
	local X = W.start()
	daily(X, "2589", "Linen Cloth", 12, function(n) return 100 + n * 10, math.floor((100 + n * 10) * 1.2) end)
	X.Record("2589", X.Now() - 60, 120, 170, 80, 8, "Linen Cloth", 1)
	-- a recipe that uses linen, one that makes it, and your trades
	W.recipes = {
		[1] = {name = "Bolt of Linen Cloth", out = 2996, reagents = {{2589, 2}}, learned = true, prof = "Tailoring"},
		[2] = {name = "Linen from nothing", out = 2589, reagents = {{2320, 1}, {2592, 1}}, learned = true, prof = "Tailoring"},
	}
	W.openProfession("Tailoring") W.advance(2) W.closeProfession()
	local L = X.Ledger()
	L.sales[#L.sales + 1] = {t = X.Now() - 2 * DAY, key = "2589", name = "Linen Cloth", count = 20, money = 3000, cut = 150}
	L.buys[#L.buys + 1] = {t = X.Now() - 3 * DAY, key = "2589", name = "Linen Cloth", count = 10, money = 1000}
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	-- away from the auction house: the last scan, and how to see every listing
	local ladder = W.screen(panel.ladder)
	T.ok("away: last scan", has(ladder, "The last scan"), ladder)
	T.ok("away: cheapest", has(ladder, "Cheapest:") and has(ladder, "1s 20c"), ladder)
	T.ok("away: listed", has(ladder, "80 in 8 auctions"), ladder)
	T.ok("away: open the auction house", has(ladder, "Open the auction house to see every listing"), ladder)
	local best = W.screen(panel.bestBox)
	T.ok("best time: weekday chart", has(best, "Price by weekday"), best)
	T.ok("best time: the day line", has(best, "Best day to sell:"), best)
	T.ok("best time: the hour line", has(best, "Best hour:"), best)
	local tip = tipOf(panel.bestBox.hot)
	T.ok("hover the title: the whole story", has(tip, "Best day to sell") and has(tip, "Your sales"), tip)
	local craft = W.screen(panel.craftBox)
	T.ok("crafting: its cost", has(craft, "Crafting cost"), craft)
	T.ok("crafting: a reagent line", has(craft, "1x") and has(craft, "Wool Cloth"), craft)
	T.ok("crafting: profit", has(craft, "Profit (after cut)"), craft)
	T.ok("used in recipes", has(craft, "Used in") and has(craft, "recipe"), craft)
	T.ok("your trades", has(craft, "sold 20, bought 10"), craft)
	T.ok("average prices", has(craft, "Average price") and has(craft, "buy 1s"), craft)
	T.ok("you own", has(craft, "You own"), craft)
	tip = tipOf(panel.craftBox)
	T.ok("hover: the whole recipe", has(tip, "Linen from nothing") and has(tip, "Cost of one craft"), tip)
	-- at the auction house: the search fills the ladder
	W.list(2589, 100, 20, 2, "Ann")  -- 40 at 1s
	W.list(2589, 120, 30, 1, "Bob")  -- 30 at 1s 20c
	W.list(2589, 300, 5, 1, "Cid")   -- 5 at 3s
	W.mine(2589, 150, 10)             -- 10 of yours at 1s 50c (a price of its own: tools/world-analysis.lua gives no
	                                  -- count of yours in a row shared with others)
	W.openAH()
	W.waitFor(function() return X.live["2589"] ~= nil end, 10)
	W.advance(0.5)
	ladder = W.screen(panel.ladder)
	local rows = 0
	for _, r in ipairs(panel.ladder.rows) do if r:IsShown() then rows = rows + 1 end end
	T.check("four price steps", rows, 4)
	T.ok("step 1: 1s, 40 listed", has(W.plain(panel.ladder.rows[1].price.text), "1s") and W.plain(panel.ladder.rows[1].count.text) == "40")
	T.check("step 2: 30 at 1s 20c", W.plain(panel.ladder.rows[2].count.text), "30")
	T.check("step 3: yours marked", W.plain(panel.ladder.rows[3].count.text), "10 (10 yours)")
	T.ok("the bars: the biggest step is the longest", panel.ladder.rows[1].bar.w >= panel.ladder.rows[3].bar.w)
	T.ok("foot: how many listed", has(ladder, "85 listed, 10 of them yours"), ladder)
	tip = tipOf(panel.ladder.rows[3])
	T.ok("hover: everything up to this price (not yours)", has(tip, "70 for 76s"), tip)
	T.ok("hover: yours", has(tip, "10 of them are yours"), tip)
	-- many price steps: the ladder says how many more
	for i = 1, 15 do W.list(2589, 400 + i * 10, 1, 1, "Dan") end
	X.LiveSearch("2589")
	W.advance(2)
	T.ok("more prices than rows", has(W.screen(panel.ladder), "more prices, up to"), W.screen(panel.ladder))
	W.closeAH()
	W.advance(0.5)
	T.ok("closed again: the last scan", has(W.screen(panel.ladder), "Open the auction house"), W.screen(panel.ladder))
end)

T.scene("item page: an empty database and unknown items do no harm", function()
	local X = W.start()
	X.UI.Open("items")
	W.advance(0.3)
	local panel = itemPanel(X)
	T.ok("hint with nothing shown", panel.hint:IsShown() and not panel.ana:IsShown())
	T.ok("the list says how to add", has(W.screen(panel), "Nothing tracked yet"))
	X.UI.ShowItem("424242")
	W.advance(0.3)
	T.ok("unknown: not seen yet", has(W.screen(panel), "Not seen on the auction house yet"), W.screen(panel))
	for _, t in ipairs(panel.tiles) do W.hover(t) W.unhover(t) end
	W.click("1 year", panel)
	W.openAH()
	W.advance(2)
	T.ok("at the auction house: nothing listed", has(W.screen(panel.ladder), "Nothing listed") or has(W.screen(panel.ladder), "Searching"),
		W.screen(panel.ladder))
	T.ok("buy button: nothing to buy", has(W.plain(W.buttonText(panel.buy)), "Nothing to buy"), W.buttonText(panel.buy))
	W.closeAH()
	W.advance(0.5)
	T.check("buy button: closed", W.plain(W.buttonText(panel.buy)), "Open the auction house to buy")
	X.UI.ShowItem("2589:-19")
	W.advance(0.3)
end)

-- regression (dry run on real saved data, 2026-11-27): sale times worked out from a mail's days left had a fraction of a
-- second; the item graph's sale dots and the Recent page formatted them with date(), which newer Lua refuses
T.scene("item page: sale times with a fraction of a second (old saved data, mails)", function()
	local X = W.start()
	W.advance(5)
	daily(X, "2589", "Linen Cloth", 12, function(n) return 100 + n * 10, 120 + n * 10 end)
	X.Record("2589", X.Now() - 60, 120, 170, 80, 8, "Linen Cloth", 1)
	local Lg = X.Ledger()
	local t1, t2 = X.Now() - 3 * DAY + 0.9436, X.Now() - DAY - 0.0225
	table.insert(Lg.sales, {t = t1, key = "2589", name = "Linen Cloth", count = 2, money = 400, cut = 20, char = "Xn Ascalon"})
	table.insert(Lg.buys, {t = t2, key = "2589", name = "Linen Cloth", count = 1, money = 150, char = "Xn Ascalon"})
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	local info = panel.graph.GetInfo()
	local sale, buy
	for _, m in ipairs(info.trades) do
		if m.t == t1 then sale = m elseif m.t == t2 then buy = m end
	end
	T.ok("sale dot drawn", sale ~= nil and sale.text ~= nil)
	T.ok("sale dot: its date", sale and has(W.plain(sale.text), X.Date(math.floor(t1), "%b %d %H:%M")), sale and sale.text)
	T.ok("buy dot: its date", buy and has(W.plain(buy.text), X.Date(math.floor(t2), "%b %d %H:%M")), buy and buy.text)
	-- the mouse on the sale dot: the hover box with its time
	local mx
	for _, m in ipairs(info.marks) do if m.t == t1 then mx = m.x end end
	W.cursor = {mx, 10}
	W.hover(panel.graph.plot, mx, 10)
	W.advance(0.1)
	local tip = panel.graph.tip:IsShown() and W.plain(panel.graph.tip.text:GetText() or "") or ""
	W.unhover(panel.graph.plot)
	T.ok("hover: the time", has(tip, W.env.date("%H:%M", math.floor(t1))), tip)
	T.check("X.Date: a fraction is fine", X.Date(t1, "%Y-%m-%d %H:%M:%S"), W.env.date("%Y-%m-%d %H:%M:%S", math.floor(t1)))
	-- a sale mail with a fraction of a day left: saved in whole seconds
	local m = W.mailSold(2592, 900, 3, "Ann Lee", 45)
	m.daysLeft = 29.4567
	W.addMail(m)
	W.openMail()
	W.advance(1)
	local wool
	for _, e in ipairs(Lg.sales) do if e.key == "2592" then wool = e end end
	T.ok("mail sale: whole seconds", wool and wool.t == math.floor(wool.t), wool and wool.t)
	W.closeMail()
	-- the Recent page of Your gold: the When column shows the old sale's date (not "?")
	X.UI.Open("gold")
	W.advance(2)
	local gp = X.UI.tabs.gold.panel
	W.click("Recent", gp)
	W.advance(1)
	T.ok("recent: the date of the old sale", has(W.screen(gp), X.Date(t1, "%b %d  %H:%M")), W.screen(gp))
end)
