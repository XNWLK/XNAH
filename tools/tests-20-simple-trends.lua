-- XNAH test scenes, part 20: the simple window's Trends page (prices going up and down) and Wealth page (all your
-- gold, each character, your best sellers this week).

local DAY = 86400

-- a price a day at noon for `days` days up to today; fn(i) -> market value (i = 0 the oldest)
local function daily(X, key, name, days, fn, qty)
	local now = X.Now()
	for i = 0, days - 1 do
		local t = now - (days - 1 - i) * DAY
		local v = math.floor(fn(i))
		X.Record(key, t, math.floor(v * 0.95), v, qty or 100, 10, name, 1)
	end
end
local function entryById(X, id)
	for _, e in ipairs(X.Simple.list.items or {}) do if e.id == id then return e end end
end
local function pick(X, id)
	local S = X.Simple
	for i, e in ipairs(S.list.items or {}) do
		if e.id == id then
			S.list.offset = 0
			S.list:Refresh()
			local row = S.list.rows[i]
			if row then row:Click() end
			return e
		end
	end
end

T.scene("simple trends: rising and falling items, watch, sell", function()
	local X = W.start()
	-- you carry 40 Linen
	W.fill(0, {{2589, 40}})
	W.bagsChanged()
	daily(X, "2589", "Linen Cloth", 14, function(i) return 10000 * (1 + 0.03 * i) end)       -- up about 20% a week
	daily(X, "2592", "Wool Cloth", 14, function(i) return 20000 * (1 - 0.025 * i) end)       -- down
	daily(X, "2770", "Copper Ore", 14, function(i) return 300 * (1 + 0.05 * i) end)          -- rising, but too cheap
	daily(X, "4306", "Silk Cloth", 14, function(i) return 5000 * (i % 2 == 0 and 1.3 or 0.7) end) -- jumps about, no trend
	daily(X, "14047", "Runecloth", 14, function() return 8000 end)                           -- flat
	daily(X, "2996", "Bolt of Linen Cloth", 14, function(i) return 6000 * (1 + 0.04 * i) end, 2) -- rising, hardly listed
	local S = X.Simple
	S.Open("trends")
	T.ok("first: working it out", (S.list.items and #S.list.items == 0), #(S.list.items or {}))
	W.advance(2)
	local keys = {}
	for _, e in ipairs(S.list.items or {}) do keys[#keys + 1] = e.key end
	table.sort(keys)
	T.check("two items move (cheap, jumpy, flat and rarely listed ones left out)", table.concat(keys, ","), "2589,2592")
	local up = entryById(X, "trend:2589")
	T.check("title: going up", up and up.title, "Linen Cloth going up")
	T.ok("sub: this week, you have 40", up and W.plain(up.sub):find("this week, you have 40", 1, true) ~= nil, up and W.plain(up.sub))
	T.ok("sub: a rise", up and W.plain(up.sub):find("^%+%d+%% this week") ~= nil, up and W.plain(up.sub))
	T.ok("sentence: rising, sell now", up and up.sentence:find("rising for 2 weeks", 1, true) and up.sentence:find("good time to sell", 1, true),
		up and up.sentence)
	T.ok("why: a week ago", up and up.why:find("A week ago it sold for about", 1, true) ~= nil, up and up.why)
	T.check("button: watch it", up and up.button.label, "Watch it")
	T.check("button2: sell it (you own some)", up and up.button2 and up.button2.label, "Sell it")
	local down = entryById(X, "trend:2592")
	T.check("title: going down", down and down.title, "Wool Cloth going down")
	T.ok("sentence: falling, wait", down and down.sentence:find("falling", 1, true) and down.sentence:find("Wait before you buy", 1, true),
		down and down.sentence)
	-- the page: pick it, watch it
	pick(X, "trend:2589")
	T.check("picked", S.detail.entry and S.detail.entry.id, "trend:2589")
	T.ok("its graph", S.detail.graph:IsShown())
	S.detail.button:Click()
	T.ok("now watched", X.Watched("2589"))
	W.advance(0.6)
	T.check("the button says what the next click does", S.detail.button:GetText(), "Stop watching")
	S.detail.button:Click()
	T.ok("watched no more", not X.Watched("2589"))
	-- new prices: worked out again, but not more than once a minute
	X.Fire("XNAH_PRICES")
	W.advance(1)
	T.ok("not again within the minute", not X.JobRunning("simple trends"))
	W.advance(65)
	T.ok("still listed after the minute", #S.list.items == 2, #S.list.items)
	-- Sell it opens the Sell page (when there is one) or the item
	S.Select("trends")
	W.advance(0.5)
	pick(X, "trend:2589")
	if S.detail.button2:IsShown() then S.detail.button2:Click() end
	W.advance(0.5)
	T.ok("Sell it went somewhere", S.views.sell ~= nil or (S.detail.entry and S.detail.entry.id == "item:2589"))
end)

T.scene("simple trends: nothing moves", function()
	local X = W.start()
	daily(X, "14047", "Runecloth", 10, function() return 8000 end)
	local S = X.Simple
	S.Open("trends")
	W.advance(2)
	T.check("no entries", #(S.list.items or {}), 0)
	T.ok("says why", W.screen(S.Frame()):find("No price is moving much", 1, true) ~= nil)
end)

T.scene("simple wealth: all your gold, characters, best sellers", function()
	local X = W.start()
	W.fill(0, {{2589, 100}})
	W.setMoney(10000000) -- 1,000g
	W.bagsChanged()
	daily(X, "2589", "Linen Cloth", 3, function() return 1000 end)
	local rk = X.RealmKey()
	X.db.chars["Ann Lee"] = {realm = rk, money = 5000000, bags = {["2589"] = 20}, bank = {}, mail = {}, auctions = {}, bound = {}, at = X.Now() - DAY}
	-- the gold a week ago, and the worth line of 10 days
	local today = math.floor((X.HomeDayStart() + DAY / 2) / DAY)
	X.Realm().homeGold = {[today - 6] = {["Xn Ascalon"] = 9000000, ["Ann Lee"] = 5000000}}
	local pts = {}
	for d = 10, 1, -1 do pts[#pts + 1] = X.b36(X.Day() - d) .. "," .. X.b36(14000000 + (10 - d) * 50000) end
	X.db.worthTotal[rk] = table.concat(pts, ";")
	-- sales this week
	local L = X.Ledger()
	L.sales[#L.sales + 1] = {t = X.Now() - DAY, key = "2589", name = "Linen Cloth", count = 200, money = 2000000, cut = 100000}
	L.sales[#L.sales + 1] = {t = X.Now() - 2 * DAY, key = "2592", name = "Wool Cloth", count = 20, money = 400000, cut = 20000}
	X.Fire("XNAH_LEDGER")
	W.advance(1)

	local S = X.Simple
	S.Open("wealth")
	W.advance(0.5)
	local items = S.list.items or {}
	T.check("first: all your gold", items[1] and items[1].title, "All your gold")
	T.check("then the characters (richest first)", items[2] and items[2].title, "Xn Ascalon")
	T.check("second character", items[3] and items[3].title, "Ann Lee")
	T.check("last: best sellers", items[4] and items[4].title, "Your best sellers this week")
	local all = items[1]
	T.ok("sentence: gold, characters, this week", all and W.plain(all.sentence):find("You have 1,500g on 2 characters; +7.1% this week.", 1, true) ~= nil,
		all and W.plain(all.sentence))
	T.ok("why: worth", all and all.why:find("you own about", 1, true) ~= nil, all and all.why)
	-- its graph: what you own and your gold over time
	pick(X, "wealth:all")
	local info = S.detail.graph.GetInfo()
	T.check("two lines", #info.series, 2)
	T.ok("the worth line has the days", info.series[1] and #info.series[1].pts >= 10, info.series[1] and #info.series[1].pts)
	T.check("the gold line", info.series[2] and info.series[2].label, "Gold")
	T.check("All details", S.detail.button2:GetText(), "All details")
	-- a character
	local ann = entryById(X, "wealth:char:Ann Lee")
	T.ok("Ann: gold and items", ann and W.plain(ann.sentence):find("Ann Lee has 500g and things worth", 1, true) ~= nil, ann and ann.sentence)
	T.ok("Ann: last seen", ann and ann.why:find("Last seen 24h ago", 1, true) ~= nil, ann and ann.why)
	pick(X, "wealth:char:Ann Lee")
	T.ok("Ann: a graph (empty: no history yet)", S.detail.graph:IsShown())
	-- best sellers
	local best = entryById(X, "wealth:top")
	T.ok("best: Linen", best and best.sentence:find("Best this week: Linen Cloth brought 190g (200 sold)", 1, true) ~= nil, best and best.sentence)
	T.ok("best: the next one", best and best.why:find("Wool Cloth 38g", 1, true) ~= nil, best and best.why)
	pick(X, "wealth:top")
	T.check("best: sales a day", S.detail.graph.GetInfo().series[1] and S.detail.graph.GetInfo().series[1].label, "Sales that day")
	-- All details opens the full window's Wealth page
	pick(X, "wealth:all")
	S.detail.button2:Click()
	W.advance(0.5)
	T.ok("full window open", X.UI.Frame() and X.UI.Frame():IsShown())
	T.ok("simple window closed", not S.Frame():IsShown())
	T.check("on the Wealth page", X.UI.current, "wealth")
end)

T.scene("simple wealth: a first start (no history, no sales)", function()
	local X = W.start()
	W.setMoney(123456)
	W.advance(1)
	local S = X.Simple
	S.Open("wealth")
	W.advance(0.5)
	local items = S.list.items or {}
	T.check("all and one character", #items, 2)
	T.ok("sentence", items[1] and W.plain(items[1].sentence):find("You have 12g 34s 56c on 1 character", 1, true) ~= nil, items[1] and W.plain(items[1].sentence))
	pick(X, "wealth:all")
	T.ok("graph shown", S.detail.graph:IsShown())
end)
