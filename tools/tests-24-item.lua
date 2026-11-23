-- XNAH test scenes, part 24: the item page made calmer - ten plain rows (with "More numbers" for the rest), the fair
-- prices to buy and to sell (X.FairPrices), one Watch list button (no Buy button), honest ways to make gold.

local DAY, HOUR = 86400, 3600

local function itemPanel(X)
	local tab = X.UI.tabs.item
	return tab and tab.panel
end
local function openMenu()
	for _, f in ipairs(W.frames) do
		if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then return f end
	end
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

T.scene("item page: ten plain rows, More numbers, the fair price lines", function()
	local X = W.start()
	daily(X, "2589", "Linen Cloth", 12, function(n) return 100 + n * 10, math.floor((100 + n * 10) * 1.2) end)
	X.Record("2589", X.Now() - 60, 120, 170, 80, 8, "Linen Cloth", 1)
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	local screen = W.screen(panel)
	if os.getenv and os.getenv("SHOWITEM") then print(screen) print(W.screen(panel.profBox)) end
	for _, label in ipairs({"Lowest now", "Usually sells for", "Fair price to buy", "Fair price to sell", "Sells a day",
		"Listed now", "Price trend", "Vendor pays", "You own", "Seen"}) do
		T.ok("plain row: " .. label, has(screen, label), screen)
	end
	for _, label in ipairs({"Market shape", "3-day average", "Day-to-day spread", "Vendor sells at", "Disenchant value"}) do
		T.ok("not in the plain view: " .. label, not has(screen, label))
	end
	local shown = 0
	for i = 1, #panel.numL do if panel.numL[i]:IsShown() then shown = shown + 1 end end
	T.check("ten rows", shown, 10)
	T.ok("the fair price note", has(screen, "Fair to buy:"), screen)
	T.ok("cheap now: says so", has(screen, "a good price"), screen)
	local buy = X.FairPrices("2589")
	-- More numbers: the rest, and back
	W.click("More numbers", panel)
	screen = W.screen(panel)
	T.ok("more: 3-day average", has(screen, "3-day average"), screen)
	T.ok("more: spread", has(screen, "Day-to-day spread"))
	T.ok("more: no market shape", not has(screen, "Market shape"))
	T.ok("more: note hidden", not has(screen, "Fair to buy:"))
	T.check("remembered", X.S().itemMore, true)
	W.click("Fewer numbers", panel)
	T.ok("plain again", has(W.screen(panel), "Usually sells for"))
	T.check("remembered off", X.S().itemMore, false)
	-- the graph: two flat lines at the fair prices, a name under the graph hides them
	local info = panel.graph.GetInfo()
	T.check("two fair lines", #info.levels, 2)
	T.check("fair to buy line", info.levels[2] and info.levels[2].v, buy)
	T.ok("legend: Fair prices", has(W.screen(panel), "Fair prices"))
	T.check("lines stay out of the series", #info.series, 2)
	W.click("Fair prices", panel)
	T.check("hidden", #panel.graph.GetInfo().levels, 0)
	W.click("Fair prices", panel)
	T.check("shown again", #panel.graph.GetInfo().levels, 2)
	-- an item with little history: no lines, no name
	X.Record("2592", X.Now() - 60, 500, 600, 20, 2, "Wool Cloth", 1)
	X.UI.ShowItem("2592")
	W.advance(0.3)
	T.check("little history: no lines", #panel.graph.GetInfo().levels, 0)
	T.ok("little history: not known yet", has(W.screen(panel), "not known yet"))
	T.ok("little history: no Fair prices name", not has(W.screen(panel), "Fair prices"))
end)

T.scene("item page: Search and one Watch list button, no Buy button", function()
	local X = W.start()
	daily(X, "2589", "Linen Cloth", 12, function(n) return 100 + n * 10, math.floor((100 + n * 10) * 1.2) end)
	W.list(2589, 120, 20, 3)
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	local buy = X.FairPrices("2589")
	T.ok("no Buy button", panel.buy == nil and W.findButton("Buy", panel) == nil)
	T.ok("no price alert button", panel.alert == nil and W.findButton("Alert me", panel) == nil)
	T.ok("search hidden while the auction house is closed", not panel.ah:IsShown())
	W.openAH()
	W.advance(0.5)
	T.ok("search shown with the auction house open", panel.ah:IsShown())
	local old = {"Add to watch list", "Max price", "Shopping list", "Add to the shopping list"}
	for _, t in ipairs(old) do T.ok("one button instead of: " .. t, W.findButton(t, panel) == nil) end
	-- the Watch list menu
	W.click("Watch list", panel)
	local menu = openMenu()
	T.ok("a menu", menu ~= nil)
	T.ok("no shopping list in the menu", menu == nil or W.findButton("shopping list", menu) == nil)
	if menu then W.click("On the watch list", menu) end
	W.advance(0.6)
	T.check("watched", X.Watched("2589") and true or false, true)
	T.ok("button says so", W.findButton("Watched", panel) ~= nil)
	W.click("Watched", panel)
	menu = openMenu()
	if menu then W.click("fair price to buy", menu) end
	W.advance(0.6)
	T.check("highest price = the fair price to buy", X.WatchMax("2589"), buy)
	T.ok("button shows it", W.findButton("Watched, max", panel) ~= nil)
	W.click("Watched", panel)
	menu = openMenu()
	if menu then W.click("No highest price", menu) end
	W.advance(0.6)
	T.check("no highest price", X.WatchMax("2589"), nil)
	W.closeAH()
end)

T.scene("item page: ways to make gold stay honest", function()
	local X = W.start()
	-- stone at about 1s 75c with one silly scan at 1g: buying at 1s 70c is no real profit
	daily(X, "2836", "Coarse Stone", 12, function(n)
		if n == 4 then return 10000, 10000 end
		return 170 + (n % 3), 175 + (n % 3)
	end)
	X.Record("2836", X.Now() - 60, 172, 176, 200, 20, "Coarse Stone", 1)
	X.UI.Toggle()
	X.UI.ShowItem("2836")
	W.advance(0.5)
	local panel = itemPanel(X)
	local box = W.screen(panel.profBox)
	T.ok("no silly profit from one high scan", not has(box, "Buy it now"), box)
	T.ok("says nothing is worth doing", has(box, "Nothing worth doing"), box)
	-- linen listed cheap now (under the fair price to buy): buy it now, sell it later, with the real numbers
	daily(X, "2589", "Linen Cloth", 12, function(n) return 100 + n * 10, math.floor((100 + n * 10) * 1.2) end)
	X.Record("2589", X.Now() - 60, 105, 170, 80, 8, "Linen Cloth", 1)
	X.UI.ShowItem("2589")
	W.advance(0.3)
	box = W.screen(panel.profBox)
	local _, sell = X.FairPrices("2589")
	T.ok("cheap now: buy it now, sell it later", has(box, "Buy it now, sell it later"), box)
	T.ok("profit from the fair price to sell", has(box, W.plain(X.MoneyPlain(math.floor(X.AfterCut(sell) - 105)))) or
		has(box, W.plain(X.MoneyPlain(X.AfterCut(sell) - 105))), box)
	local heads = 0
	for _, slot in ipairs(panel.prof) do if slot.head:IsShown() then heads = heads + 1 end end
	T.ok("at most three ways", heads <= 3, heads)
	-- old prices: no buy-now idea
	X.Items()["2589"].cur.t = X.Now() - 10 * DAY
	X.UI.Refresh(true)
	W.advance(0.3)
	T.ok("old prices: no buy-now idea", not has(W.screen(panel.profBox), "Buy it now"))
end)
