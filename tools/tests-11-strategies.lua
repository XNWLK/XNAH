-- XNAH test scenes, part 11: strategies (Strategy.lua) and the Strategies tab (UIStrategies.lua). A 10-day market
-- (plus a few items with longer or finer history) where each strategy must find the item made for it and leave out
-- the look-alikes; marks; numbers saved across a reload; the tab and its buttons; a 2,000-item market in slices.

local IDS = {
	below = 80001, near = 80002, plain = 80003, dip = 80004, wild = 80005, gap = 80006, many = 80007, rise = 80008,
	flood = 80009, craft = 80010, reagent = 80011, vflip = 80012, fast = 80013, hours = 80014, flatHours = 80015,
	week = 80016, flatWeek = 80017, steady = 80018, fall = 80019, spike = 80020, slowFast = 80021,
}
local function key(name) return tostring(IDS[name]) end

local function addItems()
	local function item(name, title, sell, stack)
		W.items[IDS[name]] = {name = title, quality = 1, sell = sell, stack = stack or 20}
	end
	item("below", "Cheap Hide", 100) item("near", "Near Ore", 1000) item("plain", "Plain Bloom", 100)
	item("dip", "Steady Herb", 10) item("wild", "Wild Herb", 10) item("gap", "Gap Dust", 10) item("many", "Crowded Dust", 10)
	item("rise", "Rising Silk", 10) item("flood", "Flooded Leather", 10) item("craft", "Fine Potion", 10)
	item("reagent", "Potion Root", 10) item("vflip", "Vendor Spice", 10) item("fast", "Busy Thread", 10)
	item("hours", "Night Moss", 10) item("flatHours", "Even Moss", 10) item("week", "Raid Flask", 10)
	item("flatWeek", "Plain Flask", 10) item("steady", "Steady Bolt", 10) item("fall", "Falling Scale", 10)
	item("spike", "Spiking Gem", 10) item("slowFast", "Quiet Thread", 10)
end

-- local start of the day of `t` (the same reckoning as the strategies' time of day)
local function localDayStart(t)
	local tt = W.env.date("*t", t)
	local off = (tt.hour * 3600 + tt.min * 60 + tt.sec) - t % 86400
	return t - ((t + off) % 86400)
end

-- sales speed of an item: `perDay` units a day (one day watched)
local function setRate(X, k, perDay)
	X.Realm().speed = X.Realm().speed or {}
	X.Realm().speed[k] = X.b36(X.Day()) .. "," .. X.b36(perDay) .. "," .. X.b36(1440)
end

-- what you own (instead of bags, bank and mail)
local OWNED = {}
local function own(X)
	X.Owned = function(id)
		local n = OWNED[tostring(id)] or 0
		return n, {bags = n, bank = 0, mail = 0, auctions = 0, alts = 0, warbank = 0}
	end
end

-- the market: 9 days of history recorded, then today's listings read by a real full scan
local function market(X)
	addItems()
	W.addDEItems()
	local now = X.Now()
	local function hist(name, price, qty, days)
		for d = (days or 9), 1, -1 do
			local p = type(price) == "function" and price(d) or price
			local q = type(qty) == "function" and qty(d) or qty
			X.Record(key(name), now - d * 86400, p, p, q, 5, nil, 1)
		end
	end
	-- 28 days at noon, one weekday dear (the weekday cycle), or flat
	local wdDear = (X.Day(now) - 3) % 7
	for d = 28, 1, -1 do
		local day = X.Day(now - d * 86400)
		X.Record(key("week"), now - d * 86400, day % 7 == wdDear and 15000 or 10000, nil, 30, 5, nil, 1)
		X.Record(key("flatWeek"), now - d * 86400, 10000, nil, 30, 5, nil, 1)
	end
	-- six days of scans at night (cheap) and in the evening (dear); the other moss the same at both
	local start = localDayStart(now)
	for d = 6, 1, -1 do
		local night, evening = start - d * 86400 + 3 * 3600, start - d * 86400 + 20 * 3600
		X.Record(key("hours"), night, 10000, 10000, 30, 5, nil, 1)
		X.Record(key("hours"), evening, 15000, 15000, 30, 5, nil, 1)
		X.Record(key("flatHours"), night, 12000, 12000, 30, 5, nil, 1)
		X.Record(key("flatHours"), evening, 12000, 12000, 30, 5, nil, 1)
	end
	hist("below", 300, 20) hist("near", 3000, 20) hist("plain", 300, 20)
	hist("dip", function(d) return d % 2 == 0 and 10100 or 9900 end, 35)
	hist("wild", function(d) return d % 2 == 0 and 5000 or 15000 end, 35)
	hist("gap", 10000, 40) hist("many", 10000, 70)
	hist("rise", function(d) return math.floor(13000 / 1.03 ^ d) end, function(d) return d > 3 and 100 or 50 end)
	hist("flood", 5000, 20) hist("craft", 20000, 20) hist("reagent", 1000, 50) hist("vflip", 5000, 20)
	hist("fast", 1000, 50) hist("slowFast", 1000, 50) hist("steady", 2000, 30)
	hist("fall", function(d) return math.floor(6000 / 0.95 ^ d) end, 20)
	hist("spike", 10000, 20)
	-- today
	W.openAH()
	local L = W.list
	L(IDS.below, 50, 2, 1, "Hasty") L(IDS.below, 300, 20, 1)
	L(IDS.near, 1100, 3, 1, "Low") L(IDS.near, 3000, 20, 1)
	L(IDS.plain, 300, 20, 1)
	L(IDS.dip, 6000, 5, 1, "Hasty") L(IDS.dip, 10000, 30, 1)
	L(IDS.wild, 6000, 5, 1, "Hasty") L(IDS.wild, 10000, 30, 1)
	L(IDS.gap, 5000, 2, 1, "Typo") L(IDS.gap, 10000, 40, 1)
	L(IDS.many, 5000, 30, 1, "Dumper") L(IDS.many, 10000, 40, 1)
	L(IDS.rise, 13000, 30, 1)
	L(IDS.flood, 5000, 100, 1)
	L(IDS.craft, 20000, 20, 1) L(IDS.reagent, 1000, 50, 1) L(IDS.vflip, 5000, 20, 1)
	L(IDS.fast, 850, 3, 1, "Hasty") L(IDS.fast, 1000, 50, 1)
	L(IDS.slowFast, 850, 3, 1, "Hasty") L(IDS.slowFast, 1000, 50, 1)
	L(IDS.steady, 1800, 2, 1, "Low") L(IDS.steady, 2000, 30, 1)
	L(IDS.hours, 12000, 30, 1) L(IDS.flatHours, 12000, 30, 1)
	L(IDS.week, 10000, 30, 1) L(IDS.flatWeek, 10000, 30, 1)
	L(IDS.fall, 6000, 20, 1) L(IDS.spike, 15000, 20, 1)
	-- disenchanting: the materials and a blue under its value (5000)
	L(10940, 100, 50, 1) L(10998, 1000, 50, 1) L(10978, 2000, 50, 1) L(11139, 5000, 50, 1) L(20725, 30000, 10, 1)
	L(W.DE_GEAR.blue, 3000, 1, 1, "Gear")
	L(W.DE_GEAR.green, 2000, 1, 1, "Gear") -- value 800: over it
	T.ok("full scan", T.fullScan(X))
	W.advance(3) -- speed and shape jobs
	-- sales speed, a recipe you know (and one you do not), a vendor that sells something cheap
	setRate(X, key("fast"), 20)
	setRate(X, key("steady"), 5)
	X.db.recipes[900] = {name = "Brew Fine Potion", out = IDS.craft, n = 1, r = {{IDS.reagent, 2}}, prof = "Alchemy"}
	X.db.recipes[901] = {name = "Brew Steady Bolt", out = IDS.steady, n = 1, r = {{IDS.reagent, 1}}, prof = "Tailoring"}
	X.db.known = {[X.CharKey()] = {[900] = true}}
	W.merchant = {{itemID = IDS.vflip, price = 100, stackCount = 1, numAvailable = -1}}
	W.openMerchant("Spice Seller")
	W.advance(1)
	W.closeMerchant()
	OWNED = {[key("rise")] = 7, [key("flood")] = 4, [key("fall")] = 3, [key("spike")] = 2, [key("dip")] = 5, [key("plain")] = 9}
	own(X)
	X.StrategyForget()
end

local function find(rows, k)
	for _, r in ipairs(rows or {}) do if r.key == k then return r end end
end
local function keys(rows)
	local out = {}
	for _, r in ipairs(rows or {}) do out[#out + 1] = r.key end
	table.sort(out)
	return table.concat(out, ",")
end

T.scene("strategies: each one finds its item over a 10-day market", function()
	local X = W.start()
	market(X)
	T.check("20 strategies", #X.Strategies(), 20)
	for _, s in ipairs(X.Strategies()) do
		T.ok(s.key .. ": described", s.name and s.short and #s.how >= 3 and #s.how <= 6 and s.needs, s.key)
		T.ok(s.key .. ": side", s.side == "buy" or s.side == "sell" or s.side == "make", s.side)
	end
	local R = X.RunStrategy
	-- 1 vendor floor
	local r = find(R("vendorfloor"), key("below"))
	T.check("vendor floor: under vendor price -> buy and vendor", r and r.action, "Buy and vendor")
	T.check("vendor floor: the 2 cheap ones", r and r.qty, 2)
	T.near("vendor floor: profit each", r and r.profit, 50, 0.01)
	T.check("vendor floor: risk", r and r.risk, "Low")
	r = find(R("vendorfloor"), key("near"))
	T.check("vendor floor: 10% over vendor -> buy", r and r.action, "Buy")
	T.check("vendor floor: 3 near the floor", r and r.qty, 3)
	T.ok("vendor floor: upside to the usual price", r and r.profit > 1500, r and r.profit)
	T.check("vendor floor: far over vendor price -> no", find(R("vendorfloor"), key("plain")), nil)
	-- 2 buy the dip
	r = find(R("dip"), key("dip"))
	T.ok("dip: the steady herb", r ~= nil)
	T.check("dip: buy and relist", r and r.action, "Buy and relist")
	T.check("dip: 5 cheap", r and r.qty, 5)
	T.check("dip: now = lowest", r and r.now, 6000)
	T.check("dip: a wild price is left out", find(R("dip"), key("wild")), nil)
	T.check("dip: a falling price is left out", find(R("dip"), key("fall")), nil)
	-- 3 undercut gap
	r = find(R("gap"), key("gap"))
	T.check("gap: 2 cheap units", r and r.qty, 2)
	T.near("gap: target just under the market value", r and r.target, 9999, 0.5)
	T.check("gap: 30 cheap units is a new price, not a gap", find(R("gap"), key("many")), nil)
	-- 4 market reset
	r = find(R("reset"), key("dip"))
	T.check("reset: the 5 cheap herbs", r and r.qty, 5)
	T.check("reset: speed unknown -> medium risk", r and r.risk, "Medium")
	T.check("reset: too little profit in all -> no", find(R("reset"), key("gap")), nil)
	-- 5 momentum
	local rs = X.Stats(key("rise"))
	T.ok("rising silk: trend and supply", rs.trend and rs.trend >= 10 and rs.supply and rs.supply <= -10, T.show(rs))
	r = find(R("momentum"), key("rise"))
	T.ok("momentum: the rising silk", r ~= nil)
	T.check("momentum: high risk", r and r.risk, "High")
	T.ok("momentum: target over now", r and r.target > r.now, r and T.show(r))
	T.check("momentum: a flat item -> no", find(R("momentum"), key("steady")), nil)
	-- 6 scarcity
	r = find(R("scarcity"), key("rise"))
	T.check("scarcity: sell now", r and r.action, "Sell now")
	T.check("scarcity: the 7 you have", r and r.qty, 7)
	T.near("scarcity: profit = after the cut", r and r.profit, 13000 * 0.95, 1)
	OWNED[key("rise")] = 0
	X.StrategyForget()
	T.check("scarcity: not owned -> no", find(R("scarcity"), key("rise")), nil)
	OWNED[key("rise")] = 7
	X.StrategyForget()
	-- 7 flood
	r = find(R("flood"), key("flood"))
	T.check("flood: hold", r and r.action, "Hold")
	T.check("flood: qty", r and r.qty, 4)
	T.check("flood: only items you own", keys(R("flood")), key("flood"))
	-- 8 crafting
	r = find(R("craft"), key("craft"))
	T.check("craft: craft", r and r.action, "Craft")
	T.near("craft: cost", r and r.now, 2000, 1)
	T.near("craft: profit", r and r.profit, 20000 * 0.95 - 2000, 1)
	T.check("craft: a recipe nobody of yours knows -> no", find(R("craft"), key("steady")), nil)
	-- 9 disenchant
	r = find(R("de"), tostring(W.DE_GEAR.blue))
	T.check("disenchant: the blue", r and r.action, "Disenchant")
	T.near("disenchant: profit", r and r.profit, 5000 * 0.95 - 3000, 1)
	T.check("disenchant: a green over its value -> no", find(R("de"), tostring(W.DE_GEAR.green)), nil)
	-- 10 vendor to auction house
	r = find(R("vendorflip"), key("vflip"))
	T.check("vendor flip: now = vendor price", r and r.now, 100)
	T.ok("vendor flip: marked as a vendor buy", r and r.vendor == true)
	T.ok("vendor flip: says where", r and r.why:find("Spice Seller", 1, true) ~= nil, r and r.why)
	-- 11 volume
	r = find(R("volume"), key("fast"))
	T.check("volume: 3 cheap", r and r.qty, 3)
	T.near("volume: profit", r and r.profit, 1000 * 0.95 - 850, 0.5)
	T.check("volume: speed not known -> no", find(R("volume"), key("slowFast")), nil)
	-- 12 time of day
	r = find(R("hours"), key("hours"))
	T.ok("hours: night cheap, evening dear", r and r.why:find("night", 1, true) and r.why:find("evening", 1, true), r and r.why)
	T.near("hours: now = night average", r and r.now, 10000, 1)
	T.near("hours: target = evening average", r and r.target, 15000, 1)
	T.check("hours: the same at every hour -> no", find(R("hours"), key("flatHours")), nil)
	-- 13 weekday
	r = find(R("weekday"), key("week"))
	local names = {"Thursday", "Friday", "Saturday", "Sunday", "Monday", "Tuesday", "Wednesday"}
	T.ok("weekday: the dear day", r and r.why:find("sell " .. names[(X.Day() - 3) % 7 + 1], 1, true), r and r.why)
	T.check("weekday: the same every day -> no", find(R("weekday"), key("flatWeek")), nil)
	T.check("weekday: 10 days of data is too little", find(R("weekday"), key("dip")), nil)
	-- 14 steady
	r = find(R("steady"), key("steady"))
	T.check("steady: the bolt", r and r.action, "Buy and relist")
	T.check("steady: low risk", r and r.risk, "Low")
	T.check("steady: a wild price -> no", find(R("steady"), key("wild")), nil)
	-- 15 falling knife, 16 spike
	r = find(R("knife"), key("fall"))
	T.check("knife: sell now", r and r.action, "Sell now")
	T.check("knife: the 3 you have", r and r.qty, 3)
	T.check("knife: a steady item you own -> no", find(R("knife"), key("plain")), nil)
	r = find(R("spike"), key("spike"))
	T.check("spike: sell now", r and r.action, "Sell now")
	T.check("spike: only the spike", keys(R("spike")), key("spike"))
	-- every row is complete
	for _, s in ipairs(X.Strategies()) do
		for _, row in ipairs(R(s.key)) do
			local okRow = row.key and row.action and row.now and row.target and row.profit and row.why and
				(row.risk == "Low" or row.risk == "Medium" or row.risk == "High")
			if not okRow then T.ok(s.key .. ": complete row", false, T.show(row)) break end
		end
	end
	-- the ledger knows what you paid: the profit of a sale is less that
	X.LedgerItem = function(k) if k == key("spike") then return {avgBuy = 9000} end end
	X.StrategyForget()
	r = find(R("spike"), key("spike"))
	T.near("spike: profit minus what you paid", r and r.profit, 15000 * 0.95 - 9000, 1)
	-- old prices: nothing to buy
	W.advance(4 * 86400)
	X.StrategyForget()
	T.check("old prices: no dip", #R("dip"), 0)
	T.check("old prices: no vendor floor", #R("vendorfloor"), 0)
end)

T.scene("strategies: sliced runs, marks, numbers saved", function()
	local X = W.start()
	market(X)
	-- the job gives the same as running now
	local direct = {}
	for _, s in ipairs(X.Strategies()) do direct[s.key] = keys(s.run()) end
	local fired = 0
	X.On("XNAH_STRATEGY", function() fired = fired + 1 end)
	X.StrategyUpdate()
	T.ok("busy while running", X.StrategyBusy())
	W.advance(2)
	T.ok("done", not X.StrategyBusy())
	T.check("XNAH_STRATEGY fired once", fired, 1)
	for _, s in ipairs(X.Strategies()) do T.check(s.key .. ": job = direct", keys((X.StrategyRows(s.key))), direct[s.key]) end
	-- marks only for strategies switched on
	T.check("no marks while off", #X.StrategyMarks(key("dip")), 0)
	X.SetStrategyOn("dip", true)
	W.advance(1)
	local m = X.StrategyMarks(key("dip"))
	T.check("dip marked", m[1], "Buy the dip")
	T.check("an item no strategy lists", #X.StrategyMarks(key("plain")), 0)
	X.SetStrategyOn("reset", true)
	W.advance(1)
	T.check("two strategies mark the herb", #X.StrategyMarks(key("dip")), 2)
	local hits = X.StrategyHits(key("gap"))
	T.ok("hits: every strategy listing the gap dust", #hits >= 2, T.show(hits))
	-- new prices: worked out again after about 2 seconds (marks are on)
	fired = 0
	X.Fire("XNAH_PRICES")
	W.advance(1)
	T.check("not yet after 1 s", fired, 0)
	W.advance(3)
	T.check("worked out again after the pause", fired, 1)
	-- the numbers: saved, used, kept across a reload, reset
	X.SetStrategyParam("dip", "pct", 50)
	W.advance(2)
	T.check("dip at 50%: the herb at 60% is out", find((X.StrategyRows("dip")), key("dip")), nil)
	X.SetStrategyParam("craft", "mine", false)
	X.SetStrategyParam("craft", "minProfit", 100)
	W.advance(2)
	T.ok("craft: all recipes", find((X.StrategyRows("craft")), key("steady")) ~= nil)
	X = W.reload()
	own(X)
	T.check("after reload: dip %", X.StrategyParams("dip").pct, 50)
	T.check("after reload: craft mine", X.StrategyParams("craft").mine, false)
	T.check("after reload: dip still on", X.StrategyOn("dip"), true)
	T.check("after reload: defaults kept", X.StrategyParams("dip").spread, 25)
	X.ResetStrategy("dip")
	T.check("reset: back to 70", X.StrategyParams("dip").pct, 70)
	T.check("reset: still on", X.StrategyOn("dip"), true)
	-- nothing runs while the tab is closed and no strategy is on
	X.SetStrategyOn("dip", false)
	X.SetStrategyOn("reset", false)
	W.advance(2)
	fired = 0
	X.On("XNAH_STRATEGY", function() fired = fired + 1 end)
	X.Fire("XNAH_PRICES")
	W.advance(5)
	T.check("tab closed, no marks: nothing worked out", fired, 0)
end)

T.scene("strategies: the tab and its buttons", function()
	local X = W.start()
	market(X)
	W.env.SlashCmdList.XNAH("")
	X.UI.Open("strategies")
	W.advance(3)
	local p = X.UI.tabs.strategies.panel
	local text = W.screen(p)
	for _, s in ipairs({"Buy", "Sell", "Make", "Vendor floor", "Buy the dip", "Crafting margin", "Hold in a flood", "Mark on tooltips",
		"Reset numbers", "Search these on the AH", "Add to shopping list", "Snipe at this price", "Why", "Risk"}) do
		T.ok("shows " .. s, text:find(s, 1, true) ~= nil)
	end
	T.ok("vendor floor lists the cheap hide", text:find("Cheap Hide", 1, true) ~= nil, text)
	-- every strategy: click it, the right side follows
	for _, s in ipairs(X.Strategies()) do
		W.click(s.name, p)
		W.advance(0.3)
		T.check("selected " .. s.key, X.S().strategySel, s.key)
		T.ok(s.key .. ": its how text", W.screen(p):find(s.how[1]:sub(1, 30), 1, true) ~= nil)
	end
	-- the numbers of buy the dip
	W.click("Buy the dip", p)
	W.advance(0.3)
	local box
	W.walk(p, function(f) if not box and f.kind == "EditBox" and f:IsVisible() and f.text == "70" then box = f end end)
	T.ok("dip: a box with 70", box ~= nil)
	if box then
		W.type(box, "55")
		W.step(box.scripts.OnEditFocusLost, box)
		W.advance(3)
		T.check("typed 55", X.StrategyParams("dip").pct, 55)
		W.type(box, "nonsense")
		W.step(box.scripts.OnEditFocusLost, box)
		T.check("nonsense: kept 55", X.StrategyParams("dip").pct, 55)
	end
	W.click("Reset numbers", p)
	T.check("reset numbers", X.StrategyParams("dip").pct, 70)
	W.click("Mark on tooltips", p)
	W.advance(1)
	T.check("marked", X.StrategyOn("dip"), true)
	T.ok("star in the list", W.screen(p):find("* Buy the dip", 1, true) ~= nil)
	-- shopping list and sniper (buy rows only)
	W.advance(3)
	W.click("Add to shopping list", p)
	local list = X.ShopList and X.ShopList("Strategy: Buy the dip")
	T.ok("shopping list made", list ~= nil and #list.items > 0)
	local e = X.ShopEntry and X.ShopEntry("Strategy: Buy the dip", key("dip"))
	T.check("shopping: max = 5% over now", e and e.max, 6300)
	W.click("Snipe at this price", p)
	T.check("sniper: max price", X.WatchMax(key("dip")), 6000)
	-- sell strategies: no shopping list, no sniper
	W.click("Hold in a flood", p)
	W.advance(0.3)
	T.ok("flood: shopping off", W.findButton("Add to shopping list", p).disabled == true)
	-- searching what is shown
	W.click("Vendor floor", p)
	W.advance(0.3)
	W.click("Search these on the AH", p)
	T.ok("search started", X.scan.state ~= "idle")
	W.waitFor(function() return X.scan.state == "idle" end, 60)
	-- the money box of a strategy
	W.click("Buy the dip", p)
	W.advance(0.3)
	local money
	W.walk(p, function(f) if not money and f.kind == "EditBox" and f:IsVisible() and f.text == "10s" then money = f end end)
	T.ok("money box shows 10s", money ~= nil)
	if money then
		W.type(money, "1g 50s")
		W.step(money.scripts.OnEditFocusLost, money)
		T.check("typed money", X.StrategyParams("dip").minProfit, 15000)
	end
	W.click("Work out again", p)
	W.advance(3)
	-- an empty start: says what is needed
	X = W.start()
	W.env.SlashCmdList.XNAH("")
	X.UI.Open("strategies")
	W.advance(3)
	p = X.UI.tabs.strategies.panel
	T.ok("empty: says a scan is needed", W.screen(p):find("Full scan", 1, true) ~= nil, W.screen(p))
	W.click("Sell into scarcity", p)
	W.advance(3)
	T.ok("empty: every strategy says something", W.screen(p):find("No prices yet", 1, true) ~= nil)
end)

T.scene("strategies: scale - 2,000 items, 10 days, in slices", function()
	local X = W.start()
	W.makeMarket(77, 2000, {uncached = 0})
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	W.advance(3)
	local r = W.rng(11)
	-- 9 more days recorded directly; today a real full scan again
	local base = {}
	for k, it in pairs(X.Items()) do if it.cur and it.cur.mkt then base[k] = it.cur end end
	for day = 1, 9 do
		W.advance(86400)
		local t = X.Now()
		for k, c in pairs(base) do
			local f = 0.9 + r() * 0.2
			X.Record(k, t, c.min and c.min * f, c.mkt * f, math.max(1, math.floor((c.qty > 0 and c.qty or 10) * (0.8 + r() * 0.4))), c.auc)
		end
	end
	W.advance(3600)
	W.marketDay(10)
	T.ok("full scan today", T.fullScan(X))
	W.advance(3)
	local n = 0
	for k in pairs(X.Items()) do
		n = n + 1
		if n % 5 == 0 then setRate(X, k, r(1, 30)) end
	end
	OWNED = {}
	for k in pairs(X.Items()) do if r() < 0.1 then OWNED[k] = r(1, 20) end end
	own(X)
	X.StrategyForget()
	W.maxStepTime = 0
	local c0 = os.clock()
	X.StrategyUpdate()
	W.waitFor(function() return not X.StrategyBusy() end, 60)
	local found = 0
	for _, s in ipairs(X.Strategies()) do found = found + #((X.StrategyRows(s.key)) or {}) end
	T.ok("finished", not X.StrategyBusy())
	T.note(string.format("strategies scale: %d items, 20 strategies, %d rows found; %.1f s here, slowest step %.0f ms here (fengari)",
		n, found, os.clock() - c0, W.maxStepTime * 1000))
	T.ok("no step slower than 400 ms here", W.maxStepTime < 0.4, W.maxStepTime)
end)

T.scene("strategies: the gold list (learn, cooldown crafts, what to farm, stock up at a low)", function()
	local X = W.start()
	for _, k in ipairs({"learn", "cooldown", "farm", "seasonal"}) do T.ok("strategy " .. k, X.Strategy(k) ~= nil) end
	-- Transmute: Arcanite: Thorium Bar + Arcane Crystal -> Arcanite Bar
	X.Record("12359", X.Now(), 20000, 20000, 50, 3, "Thorium Bar", 1)
	X.Record("12363", X.Now(), 100000, 100000, 10, 3, "Arcane Crystal", 2)
	X.Record("12360", X.Now(), 300000, 300000, 10, 3, "Arcanite Bar", 2)
	X.StrategyUpdate("cooldown")
	W.waitFor(function() return not X.JobRunning("strategies") end, 60)
	local rows = X.RunStrategy("cooldown") or {}
	local arcanite
	for _, r in ipairs(rows) do if r.key == "12360" then arcanite = r end end
	T.ok("Arcanite found", arcanite ~= nil, #rows)
	T.check("profit: sells for 300g less the cut, minus 12g of reagents", arcanite and X.Round(arcanite.profit), X.Round(300000 * (1 - X.S().cut / 100) - 120000))
	T.ok("action says how often", arcanite and arcanite.action:find("every 2 days", 1, true) ~= nil, arcanite and arcanite.action)
	-- the others run without errors on an empty market
	for _, k in ipairs({"learn", "farm", "seasonal"}) do T.ok(k .. " runs", type(X.RunStrategy(k)) == "table") end
end)

T.scene("strategies: transmutes are never a way to get a reagent (Water -> Undeath -> Water)", function()
	local X = W.start()
	-- Xn's prices: Essence of Water 4g, Essence of Undeath 46s, Living Essence 26s, Essence of Earth 3.9g
	X.Record("7080", X.Now(), 40000, 40000, 50, 3, "Essence of Water", 2)
	X.Record("12808", X.Now(), 4600, 4623, 315, 3, "Essence of Undeath", 2)
	X.Record("12803", X.Now(), 2654, 2654, 80, 3, "Living Essence", 2)
	X.Record("7076", X.Now(), 39000, 39000, 40, 3, "Essence of Earth", 2)
	local cost, how = X.ReagentCost(7080)
	T.check("Essence of Water costs what the auction house asks", cost, 40000)
	T.check("bought, not transmuted", how, "ah")
	X.StrategyUpdate("cooldown")
	W.waitFor(function() return not X.JobRunning("strategies") end, 60)
	local byRecipe = {}
	for _, r in ipairs(X.RunStrategy("cooldown") or {}) do byRecipe[r.why:match("^([^;]+)")] = r end
	T.ok("Water to Undeath is not a profit (4g in, 46s out)", byRecipe["Transmute: Water to Undeath"] == nil)
	local u2w = byRecipe["Transmute: Undeath to Water"]
	T.ok("Undeath to Water is", u2w ~= nil)
	T.check("its cost is one Essence of Undeath (market value)", u2w and u2w.now, 4623)
	T.ok("Life to Earth is", byRecipe["Transmute: Life to Earth"] ~= nil)
end)
