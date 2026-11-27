-- XNAH test scenes, part 14: more on the graph - your own sales and buys as dots on the price line, the graph widget's
-- plain use, and the best weekday and hour to sell (the box under the graph in the Items view).

local DAY, HOUR = 86400, 3600

-- the Items view's panel and its graph
local function itemPanel(X)
	local tab = X.UI.tabs.items
	return tab and tab.panel
end
-- a price point a day at noon on the realm's clock, `days` days back up to yesterday; fn(day number, weekday) -> mkt
local function dailyHistory(X, key, name, days, fn)
	local shift = X.ServerShift()
	local today = math.floor((X.Now() + shift) / DAY)
	for d = today - days, today - 1 do
		local v = fn(d, (d + 4) % 7)
		X.Record(key, d * DAY - shift + 12 * HOUR, math.floor(v * 0.9), v, 100, 10, name, 1)
	end
end
-- the mouse at x over the graph (a frame passes, the box follows)
local function hoverAt(g, x)
	W.cursor = {x, 10}
	W.hover(g.plot, x, 10)
	W.advance(0.1)
	local text = g.tip:IsShown() and W.plain(g.tip.text:GetText() or "") or ""
	W.unhover(g.plot)
	return text
end

T.scene("graph: your sales and buys as dots, hover, hide", function()
	local X = W.start()
	dailyHistory(X, "2589", "Linen Cloth", 10, function(d) return 1000 + (d % 3) * 20 end)
	dailyHistory(X, "2592", "Wool Cloth", 10, function() return 1100 end)
	dailyHistory(X, "15210", "Raider Shortsword", 10, function() return 60000 end)
	local L = X.Ledger()
	local now = X.Now()
	L.sales[#L.sales + 1] = {t = now - 2 * DAY, key = "2589", name = "Linen Cloth", count = 20, money = 22000, cut = 1100}
	L.sales[#L.sales + 1] = {t = now - 40 * DAY, key = "2589", name = "Linen Cloth", count = 5, money = 5000, cut = 250} -- outside 30 days
	L.sales[#L.sales + 1] = {t = now - 3 * DAY, name = "Linen Cloth", count = 2, money = 2100, cut = 105} -- saved by name only
	L.buys[#L.buys + 1] = {t = now - 4 * DAY, key = "2589", name = "Linen Cloth", count = 10, money = 9000}
	L.sales[#L.sales + 1] = {t = now - 1 * DAY, key = "2592", name = "Wool Cloth", count = 1, money = 1000, cut = 50} -- another item
	T.check("trades of Linen: sales", #X.GraphTrades("2589", "sales"), 3)
	T.check("trades of Linen: buys", #X.GraphTrades("2589", "buys"), 1)

	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	local g = panel.graph
	local info = g.GetInfo()
	T.check("30 days: two sales and a buy as dots", #info.trades, 3)
	local sold
	for _, tr in ipairs(info.trades) do if (tr.text or ""):find("You sold 20", 1, true) then sold = tr end end
	T.ok("a sale: count and price of one", sold and W.plain(sold.text):find("You sold 20 at 11s each", 1, true) ~= nil, sold and W.plain(sold.text))
	T.check("a sale: at the price of one", sold and sold.v, 1100)
	local screen = W.screen(panel)
	T.ok("legend: your sales (in the range)", screen:find("Your sales (2)", 1, true) ~= nil, screen)
	T.ok("legend: your buys", screen:find("Your buys (1)", 1, true) ~= nil)
	-- the mouse over the sale's dot: the box tells the sale
	local text = hoverAt(g, sold.x)
	T.ok("hover: the sale with date", text:find("You sold 20 at 11s each", 1, true) ~= nil and text:find(X.Date(sold.t, "%b %d"), 1, true) ~= nil, text)
	T.ok("hover: market value too", text:find("Market value", 1, true) ~= nil, text)
	-- a longer range: the old sale too; a shorter one: only the last week's
	W.click("1 year", panel)
	T.check("1 year: three sales and a buy", #g.GetInfo().trades, 4)
	T.check("1 year: kept in the settings", X.S().itemRange, 4)
	W.click("7 days", panel)
	T.check("7 days: two sales and a buy", #g.GetInfo().trades, 3)
	W.click("30 days", panel)
	T.check("30 days again", X.S().itemRange, 2)
	-- a click on "Your sales" hides them (kept in the settings), a second click shows them again
	W.click("Your sales", panel)
	T.check("sales hidden: the buy is left", #g.GetInfo().trades, 1)
	T.check("hidden in the settings", X.S().graphHide.sales, true)
	W.click("Your sales", panel)
	T.check("sales shown again", #g.GetInfo().trades, 3)
	T.check("not hidden any more", X.S().graphHide.sales, nil)
	W.click("Market value", panel)
	T.check("market value line hidden", #g.GetInfo().series, 1)
	W.click("Market value", panel)
	T.check("market value line back", #g.GetInfo().series, 2)
	-- an item never traded: no names for trades under its graph
	X.UI.ShowItem("15210")
	W.advance(0.2)
	T.ok("no trades: no 'Your sales'", W.screen(panel):find("Your sales", 1, true) == nil)
	T.check("no trades: no dots", #g.GetInfo().trades, 0)
end)

T.scene("graph: the widget's plain use (no dots, no right scale)", function()
	local X = W.start()
	local g2 = X.K.Graph(W.env.UIParent, 400, 150)
	g2:SetSeries({{points = {{X.Now() - DAY, 100}, {X.Now(), 120}}, color = {1, 1, 1}, label = "Old"}}, {bars = {{X.Now(), 5}}})
	T.check("plain use: one line", #g2.GetInfo().series, 1)
	T.check("plain use: no dots", #g2.GetInfo().trades, 0)
	g2:SetSeries({}, {empty = "Nothing"})
	T.check("plain use: empty text", g2.empty:GetText(), "Nothing")
end)

T.scene("graph: best day and hour to sell", function()
	local X = W.start()
	local shift, known = X.ServerShift()
	T.check("the realm's clock: one hour ahead of UTC", shift, 3600)
	T.check("the realm's clock is known", known, true)
	local wd, hr = X.ServerWeekday(W.START) -- 2026-11-18 12:00 UTC: a Wednesday, 13:00 on the realm
	T.check("weekday on the realm's clock", wd, 3)
	T.check("hour on the realm's clock", hr, 13)

	-- Linen: Tuesdays 10% dearer, on a price that climbs 1% a day (the climb must not count)
	dailyHistory(X, "2589", "Linen Cloth", 35, function(d, w) return math.floor(1000 * (1 + (d % 1000) * 0.01) * (w == 2 and 1.1 or 1)) end)
	local bt = X.BestTimes("2589")
	T.ok("enough days", bt.dayEnough, bt.dayCount)
	T.check("best day: Tuesday", bt.bestDay, 2)
	T.ok("Tuesday about +8%", bt.days[2].pct and bt.days[2].pct > 6 and bt.days[2].pct < 11, bt.days[2].pct)
	T.ok("other days a little under", bt.days[4].pct and bt.days[4].pct < 0 and bt.days[4].pct > -4, bt.days[4].pct)
	local lines = table.concat(X.BestTimesText(bt), "\n")
	T.ok("sentence: best day", W.plain(lines):find("Best day to sell: Tuesday (+", 1, true) ~= nil, W.plain(lines))
	T.ok("sentence: server time", W.plain(lines):find("Server time", 1, true) ~= nil)
	T.ok("hours: not enough (one scan a day)", not bt.hourEnough)
	T.ok("sentence: hours not enough", W.plain(lines):find("Best hour: not enough data yet", 1, true) ~= nil, W.plain(lines))

	-- Wool: a scan every hour for 4 days, dearer at 20:00 on the realm's clock
	local now = X.Now()
	local t = now - 4 * DAY
	t = t - t % HOUR
	while t < now do
		local _, h = X.ServerWeekday(t)
		local v = h == 20 and 1200 or 1000
		X.Record("2592", t, v - 50, v, 100, 10, "Wool Cloth", 1)
		t = t + HOUR
	end
	bt = X.BestTimes("2592")
	T.ok("enough scans", bt.hourEnough, {bt.scanCount, bt.scanDays, bt.hourCount})
	T.check("best hour: 20:00", bt.bestHour, 20)
	T.ok("20:00 well over the day", bt.hours[20].pct and bt.hours[20].pct > 10, bt.hours[20].pct)
	T.ok("days: not enough (4 days)", not bt.dayEnough)
	lines = W.plain(table.concat(X.BestTimesText(bt), "\n"))
	T.ok("sentence: best hour", lines:find("Best hour: 20:00 - 21:00 (+", 1, true) ~= nil, lines)
	T.ok("sentence: days not enough", lines:find("Best day to sell: no day clearly better yet", 1, true) ~= nil, lines)

	-- your sales: 6 on 4 weekdays, the Saturday ones at a better price
	local L = X.Ledger()
	local today = math.floor((now + shift) / DAY)
	local function saleOn(daysBack, each, count)
		local d = today - daysBack
		L.sales[#L.sales + 1] = {t = d * DAY - shift + 15 * HOUR, key = "2589", name = "Linen Cloth", count = count, money = each * count, cut = 0}
		return (d + 4) % 7
	end
	local sat
	for back = 1, 14 do
		local d = today - back
		if (d + 4) % 7 == 6 then sat = back break end
	end
	saleOn(sat, 1500, 10)
	saleOn(sat + 7, 1500, 10)
	saleOn(sat + 1, 1000, 20)
	saleOn(sat + 2, 1000, 20)
	saleOn(sat + 3, 1000, 5)
	saleOn(sat + 8, 1000, 20)
	bt = X.BestTimes("2589")
	T.check("sales counted", bt.sales, 6)
	T.check("units", bt.units, 85)
	T.ok("enough sales", bt.saleEnough)
	T.check("best price: Saturday", bt.saleBestDay, 6)
	T.check("most units: Friday", bt.saleMostDay, 5)
	T.check("sold at 15:00", bt.hours[15].units, 85)
	lines = W.plain(table.concat(X.BestTimesText(bt), "\n"))
	T.ok("sentence: your sales", lines:find("most sold on Friday; best price on Saturday (+", 1, true) ~= nil, lines)

	-- too little: an item with three days of prices and no sales
	dailyHistory(X, "4306", "Silk Cloth", 3, function() return 500 end)
	bt = X.BestTimes("4306")
	T.ok("3 days: not enough", not bt.dayEnough and not bt.hourEnough and not bt.saleEnough)
	lines = W.plain(table.concat(X.BestTimesText(bt), "\n"))
	T.ok("sentence: no sales yet", lines:find("Your sales: none in the ledger yet", 1, true) ~= nil, lines)

	-- the Items view: the best-time box is always there, under the graph (which stays shown)
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	T.ok("grid and graph both shown", panel.best:IsShown() and panel.graph:IsShown())
	T.ok("range buttons shown too", W.findButton("30 days", panel) ~= nil)
	local screen = W.screen(panel)
	T.ok("box: its title", screen:find("Best time to sell", 1, true) ~= nil, screen)
	T.ok("box: the best day", screen:find("Best day to sell: Tuesday", 1, true) ~= nil, screen)
	T.ok("box: weekday labels", screen:find("Tue", 1, true) ~= nil and screen:find("Price by weekday", 1, true) ~= nil)
	T.ok("box: server time", screen:find("(server time)", 1, true) ~= nil)
	T.ok("box: hours not enough (one scan a day)", screen:find("Best hour: not enough scans yet", 1, true) ~= nil, screen)
	-- hovering the title tells the whole story in sentences
	W.hover(panel.bestBox.hot)
	local story = W.plain(W.tipText(W.env.GameTooltip.lines))
	W.unhover(panel.bestBox.hot)
	T.ok("title hover: the sentences", story:find("Best day to sell: Tuesday (+", 1, true) ~= nil and
		story:find("Server time", 1, true) ~= nil, story)
	-- the small weekday x time-of-day grid (rows Monday first, 6 times of the day): every square can be hovered
	for _, row in ipairs(panel.best.cells) do
		for _, sq in ipairs(row) do W.hover(sq) W.unhover(sq) end
	end
	T.check("no errors from hovering the squares", #W.errors, 0)
	-- the Tuesday square with a price (one scan a day, always at the same time of day): its weekday and its price then
	local tip
	for _, sq in ipairs(panel.best.cells[2]) do
		W.hover(sq)
		local text = W.plain(W.tipText(W.env.GameTooltip.lines))
		W.unhover(sq)
		if text:find("Price then", 1, true) then tip = text end
	end
	T.ok("hover: Tuesday and its price then", tip and tip:find("Tuesday", 1, true) ~= nil, tip)
	T.ok("hover: Tuesday is dearer", tip and tip:find("dearer than usual", 1, true) ~= nil, tip)
	-- Wool: the best hour in the box
	X.UI.ShowItem("2592")
	W.advance(0.2)
	screen = W.screen(panel)
	T.ok("box: best hour 20:00", screen:find("Best hour: 20:00 - 21:00 (+", 1, true) ~= nil, screen)
	T.ok("box: no day yet (4 days)", screen:find("Best day to sell: no day clearly better yet", 1, true) ~= nil, screen)
	-- an item with too little: said so, the graph stays
	X.UI.ShowItem("4306")
	W.advance(0.2)
	screen = W.screen(panel)
	T.ok("other item: no day", screen:find("no day clearly better yet", 1, true) ~= nil, screen)
	T.ok("other item: no hour", screen:find("not enough scans yet", 1, true) ~= nil, screen)
	T.ok("other item: graph and box shown", panel.graph:IsShown() and panel.best:IsShown())

	-- without the game's clock: the computer's clock, said so
	W.gameShift = nil
	X.ServerShiftReset()
	local _, known2 = X.ServerShift()
	T.check("no game clock: not known", known2, false)
	T.ok("no game clock: said so", W.plain(table.concat(X.BestTimesText(X.BestTimes("4306")), "\n")):find("computer's clock", 1, true) ~= nil)
end)
