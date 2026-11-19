-- XNAH test scenes, part 14: more on the graph - your own sales and buys as dots on the price line, a second item to
-- compare, and the best weekday and hour to sell.

local DAY, HOUR = 86400, 3600

-- the item page's panel and its graph
local function itemPanel(X)
	local tab = X.UI.tabs.item
	return tab and tab.panel
end
-- the visible pop-up menu, if any
local function openMenu()
	for _, f in ipairs(W.frames) do
		if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then return f end
	end
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

	W.env.SlashCmdList.XNAH("")
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
	-- the whole history: the old sale too
	W.click("All", panel)
	T.check("all: three sales and a buy", #g.GetInfo().trades, 4)
	W.click("30 days", panel)
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

T.scene("graph: a second item to compare, its own scale when far apart", function()
	local X = W.start()
	dailyHistory(X, "2589", "Linen Cloth", 10, function() return 1000 end)
	dailyHistory(X, "2592", "Wool Cloth", 10, function() return 1300 end)
	dailyHistory(X, "15210", "Raider Shortsword", 10, function() return 60000 end)
	W.env.SlashCmdList.XNAH("")
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	local g = panel.graph
	W.click("Compare", panel)
	T.ok("the search box opens", panel.cmpEdit:IsShown())
	W.type(panel.cmpEdit, "wool", false)
	W.advance(0.5)
	local menu = openMenu()
	T.ok("matches in a menu", menu ~= nil)
	if menu then W.click("Wool Cloth", menu) end
	W.advance(0.2)
	T.ok("the box closes", not panel.cmpEdit:IsShown())
	local s = g.GetInfo().series
	T.check("three lines", #s, 3)
	T.check("the second item's line", s[3] and s[3].label, "Wool Cloth")
	T.check("same scale (prices close)", s[3] and s[3].right, false)
	local text = hoverAt(g, g.GetInfo().marks[3].x)
	T.ok("hover: both items", text:find("Market value", 1, true) ~= nil and text:find("Wool Cloth", 1, true) ~= nil, text)
	T.ok("hover: the second item's price", text:find("13s", 1, true) ~= nil, text)
	T.ok("legend: vs Wool Cloth", W.screen(panel):find("vs Wool Cloth", 1, true) ~= nil)
	-- kept while looking at another item; Enter takes the best match
	X.UI.ShowItem("2592")
	W.advance(0.2)
	T.check("on the compared item's own page: not drawn twice", #g.GetInfo().series, 2)
	X.UI.ShowItem("2589")
	W.advance(0.2)
	T.check("back: still compared", g.GetInfo().series[3] and g.GetInfo().series[3].label, "Wool Cloth")
	W.click("Compare", panel)
	W.type(panel.cmpEdit, "raider", true)
	W.advance(0.3)
	s = g.GetInfo().series
	T.check("Enter picks the match", s[3] and s[3].label, "Raider Shortsword")
	T.check("far apart: its own scale", s[3] and s[3].right, true)
	T.ok("legend: scale on the right", W.screen(panel):find("scale on the right", 1, true) ~= nil)
	-- a click on its name takes it off
	W.click("vs Raider", panel)
	T.check("cleared", #g.GetInfo().series, 2)
	T.ok("legend: gone", W.screen(panel):find("vs Raider", 1, true) == nil)
	-- Escape closes the search box
	W.click("Compare", panel)
	W.type(panel.cmpEdit, "wo", false)
	panel.cmpEdit.scripts.OnEscapePressed(panel.cmpEdit)
	T.ok("Escape closes the box", not panel.cmpEdit:IsShown())
	-- the graph widget's old way of use still works (no marks, no right scale)
	local g2 = X.K.Graph(W.env.UIParent, 400, 150)
	g2:SetSeries({{points = {{X.Now() - DAY, 100}, {X.Now(), 120}}, color = {1, 1, 1}, label = "Old"}}, {bars = {{X.Now(), 5}}})
	T.check("old use: one line", #g2.GetInfo().series, 1)
	T.check("old use: no dots", #g2.GetInfo().trades, 0)
	g2:SetSeries({}, {empty = "Nothing"})
	T.check("old use: empty text", g2.empty:GetText(), "Nothing")
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
	T.ok("sentence: best day", W.plain(lines):find("Best day: Tuesday (+", 1, true) ~= nil, W.plain(lines))
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
	T.ok("sentence: days not enough", lines:find("Best day: not enough data yet", 1, true) ~= nil, lines)

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

	-- the item page: "Best time" shows the charts, "Price" the graph again
	W.env.SlashCmdList.XNAH("")
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	W.click("Best time", panel)
	T.ok("charts shown", panel.best:IsShown() and not panel.graph:IsShown())
	local screen = W.screen(panel)
	T.ok("charts: the sentence", screen:find("Best day: Tuesday", 1, true) ~= nil, screen)
	T.ok("charts: weekday labels", screen:find("Tue", 1, true) ~= nil and screen:find("Price by weekday", 1, true) ~= nil)
	T.ok("charts: server time", screen:find("(server time)", 1, true) ~= nil)
	T.ok("range buttons hidden", W.findButton("30 days", panel) == nil)
	-- hovering the bars tells their numbers
	for _, c in ipairs(panel.best.charts) do
		for _, slot in ipairs(c.slots) do W.hover(slot) W.unhover(slot) end
	end
	local tue = panel.best.charts[1].slots[2]
	W.hover(tue)
	local tip = W.plain(W.tipText(W.env.GameTooltip.lines))
	W.unhover(tue)
	T.ok("hover: Tuesday", tip:find("Tuesday", 1, true) ~= nil and tip:find("over the week's average", 1, true) ~= nil, tip)
	-- another item keeps the view
	X.UI.ShowItem("4306")
	W.advance(0.2)
	T.ok("other item: not enough", W.screen(panel):find("not enough data yet", 1, true) ~= nil)
	W.click("Price", panel)
	T.ok("graph again", panel.graph:IsShown() and not panel.best:IsShown())

	-- without the game's clock: the computer's clock, said so
	W.gameShift = nil
	X.ServerShiftReset()
	local _, known2 = X.ServerShift()
	T.check("no game clock: not known", known2, false)
	T.ok("no game clock: said so", W.plain(table.concat(X.BestTimesText(X.BestTimes("4306")), "\n")):find("computer's clock", 1, true) ~= nil)
end)
