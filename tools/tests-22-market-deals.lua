-- XNAH test scenes, part 22: the Market page (Rising / Falling buttons, Sells a day, the 7-day line in each row) and the
-- numbers behind it: deals (X.Deals) and movers (X.Movers).

local IDS = {rise = 80101, fall = 80102, flat = 80103, hide = 80104, herb = 80105, flood = 80106, potion = 80107, root = 80108}
local function key(name) return tostring(IDS[name]) end

local function addItems()
	local function item(name, title, sell)
		W.items[IDS[name]] = {name = title, quality = 1, sell = sell, stack = 20}
	end
	item("rise", "Rising Silk", 10) item("fall", "Falling Scale", 10) item("flat", "Plain Bloom", 10)
	item("hide", "Cheap Hide", 100) item("herb", "Steady Herb", 10) item("flood", "Flooded Leather", 10)
	item("potion", "Fine Potion", 10) item("root", "Potion Root", 10)
end

-- 8 days of history, then today's listings read by a real full scan
local function market(X)
	addItems()
	local now = X.Now()
	local function hist(name, price, qty)
		for d = 8, 1, -1 do
			local p = type(price) == "function" and price(d) or price
			X.Record(key(name), now - d * 86400, p, p, qty or 20, 5, nil, 1)
		end
	end
	hist("rise", function(d) return math.floor(13000 / 1.04 ^ d) end)
	hist("fall", function(d) return math.floor(6000 / 0.94 ^ d) end)
	hist("flat", 300)
	hist("hide", 300)
	hist("herb", function(d) return d % 2 == 0 and 10100 or 9900 end, 35)
	hist("flood", 5000)
	hist("potion", 20000)
	hist("root", 1000, 50)
	W.openAH()
	local L = W.list
	L(IDS.rise, 13000, 30, 1) L(IDS.fall, 6000, 20, 1) L(IDS.flat, 300, 20, 1)
	L(IDS.hide, 50, 2, 1, "Hasty") L(IDS.hide, 300, 20, 1)
	L(IDS.herb, 5000, 5, 1, "Hasty") L(IDS.herb, 10000, 30, 1)
	L(IDS.flood, 5000, 100, 1)
	L(IDS.potion, 20000, 20, 1) L(IDS.root, 1000, 50, 1)
	T.ok("full scan", T.fullScan(X))
	W.advance(3)
	X.db.recipes[990] = {name = "Brew Fine Potion", out = IDS.potion, n = 1, r = {{IDS.root, 2}}, prof = "Alchemy"}
	X.db.known = {[X.CharKey()] = {[990] = true}}
	X.Owned = function(id)
		local n = (tostring(id) == key("flood") or tostring(id) == key("rise")) and 5 or 0
		return n, {bags = n, bank = 0, mail = 0, auctions = 0, alts = 0, warbank = 0}
	end
end

local function shownLines(root)
	local n = 0
	W.walk(root, function(f) if f.kind == "Line" and f.shown and f:IsVisible() then n = n + 1 end end)
	return n
end

T.scene("market and deals: Market - Rising / Falling, Sells a day, the 7-day line", function()
	local X = W.start()
	market(X)
	X.UI.Toggle()
	X.UI.Open("market")
	W.advance(3) -- the rows are worked out in slices
	X.UI.Refresh(true)
	local p = X.UI.tabs.market.panel
	local text = W.screen(p)
	for _, s in ipairs({"Rising", "Falling", "Sells a day", "7 days", "Trend"}) do
		T.ok("shows " .. s, text:find(s, 1, true) ~= nil)
	end
	T.ok("no Trends tab", X.UI.tabs.trends == nil)
	-- the 7-day line: worked out per item, green up, red down
	local up, down, flat = X.UI.MarketSpark(key("rise")), X.UI.MarketSpark(key("fall")), X.UI.MarketSpark(key("flat"))
	T.ok("line: rising goes up", up and up.change > 3, up and up.change)
	T.ok("line: falling goes down", down and down.change < -3, down and down.change)
	T.ok("line: flat stays", flat and math.abs(flat.change) < 3, flat and flat.change)
	T.ok("line: 7 points at most", up and #up.pts <= 7 and #up.pts >= 2, up and #up.pts)
	T.ok("line: drawn in the rows", shownLines(p) >= 6, shownLines(p))
	-- Rising
	local sortBefore = p.tbl.sortCol
	W.click("Rising", p)
	W.advance(0.5)
	text = W.screen(p)
	T.ok("rising: the silk", text:find("Rising Silk", 1, true) ~= nil, text)
	T.ok("rising: not the scale", text:find("Falling Scale", 1, true) == nil)
	T.ok("rising: not the flat one", text:find("Plain Bloom", 1, true) == nil)
	T.check("rising: sorted by the trend", p.tbl.sortCol, 5)
	T.check("rising: kept", X.S().marketFilter.move, "up")
	-- Falling
	W.click("Falling", p)
	W.advance(0.5)
	text = W.screen(p)
	T.ok("falling: the scale", text:find("Falling Scale", 1, true) ~= nil, text)
	T.ok("falling: not the silk", text:find("Rising Silk", 1, true) == nil)
	T.check("falling: lowest trend first", p.tbl.sortDesc, false)
	-- off again: the sorting picked before comes back
	W.click("Falling", p)
	W.advance(0.5)
	T.check("off: the sorting from before", p.tbl.sortCol, sortBefore)
	T.ok("off: all back", W.screen(p):find("Plain Bloom", 1, true) ~= nil)
	-- scrolling reuses the rows: lines follow the items
	p.tbl.offset = 1
	p.tbl:Refresh()
	T.ok("scrolled: lines still drawn", shownLines(p) >= 1)
	-- new prices: the lines are worked out again
	X.Fire("XNAH_PRICES")
	T.ok("new prices: line again", X.UI.MarketSpark(key("rise")) ~= nil)
	-- Rising kept after a reload
	W.click("Rising", p)
	X = W.reload()
	X.UI.Toggle()
	X.UI.Open("market")
	W.advance(3)
	X.UI.Refresh(true)
	p = X.UI.tabs.market.panel
	T.check("reload: Rising still on and sorted", p.tbl.sortCol, 5)
	W.click("All", p)
	W.advance(0.3)
	T.check("All: Rising off", X.S().marketFilter.move, nil)
	-- an empty start: Rising says what it needs
	X = W.start()
	X.UI.Toggle()
	X.UI.Open("market")
	W.advance(1)
	p = X.UI.tabs.market.panel
	W.click("Rising", p)
	W.advance(0.5)
	T.ok("empty: no error", W.screen(p) ~= "")
end)

local function find(rows, k) for _, r in ipairs(rows) do if r.key == k then return r end end end

T.scene("market and deals: X.Deals and X.Movers", function()
	local X = W.start()
	market(X)
	-- deals: listed at or under 60% of the usual price with at least 10s profit after the cut
	local deals = X.Deals()
	local herb = find(deals, key("herb"))
	T.ok("deal: the herb at 50s (usually about 1g)", herb ~= nil)
	T.check("deal: bought at the cheapest", herb and herb.buy, 5000)
	T.ok("deal: under 60%", herb and herb.pct <= 60, herb and herb.pct)
	T.near("deal: profit = usual after the cut - price", herb and herb.profit, herb and (X.AfterCut(herb.usual) - 5000), 1)
	T.check("not a deal: the hide (profit too small)", find(deals, key("hide")), nil)
	T.check("not a deal: the flat one", find(deals, key("flat")), nil)
	for i = 2, #deals do T.ok("most profit first", deals[i - 1].profit >= deals[i].profit) end
	T.check("a stricter %: no herb", find(X.Deals({pct = 40}), key("herb")), nil)
	T.ok("a smaller profit: the hide", find(X.Deals({pct = 60, minProfit = 100}), key("hide")) ~= nil)
	-- never suggest: left out
	X.SetIgnored(key("herb"), true)
	T.check("ignored: no herb", find(X.Deals(), key("herb")), nil)
	X.SetIgnored(key("herb"), false)
	T.ok("allowed again", find(X.Deals(), key("herb")) ~= nil)
	-- movers
	local up, down = X.Movers("up"), X.Movers("down")
	T.ok("rising: the silk", find(up, key("rise")) ~= nil)
	T.check("rising: not the scale", find(up, key("fall")), nil)
	T.ok("falling: the scale", find(down, key("fall")) ~= nil)
	T.check("falling: not the silk", find(down, key("rise")), nil)
	T.ok("rising: biggest first", #up < 2 or up[1].v >= up[2].v)
	T.ok("flood: the leather (100 listed, usually 20)", find(X.Movers("flood"), key("flood")) ~= nil)
	T.check("limit", #X.Movers("up", 1), math.min(1, #up))
end)
