-- XNAH test scenes, part 31: the three read-only views of the big window - Market overview (UIMarket.lua), Your gold
-- (UILedger.lua + UIWealth.lua) and Opportunities (UIOpps.lua). Each builds with an empty database and with data,
-- filters and sorting work, clicking a row opens the item (UI.ShowItem), no button in them buys, posts or cancels, and
-- a big data set is worked out a little per frame.

-- a market of 10 days (one full scan a day; the last day has deals, short supply and floods) and a vendor's prices
local function tenDays(X)
	W.makeMarket(31, 70, {lastDay = 9, uncached = 0})
	W.openAH()
	for day = 0, 9 do
		W.marketDay(day, 9)
		local t0 = W.NOW
		T.fullScan(X)
		if day < 9 then W.advance(86400 - (W.NOW - t0)) end
	end
	W.advance(3)
	W.openMerchant("Supplies")
	W.advance(1)
	W.closeMerchant()
	W.advance(1)
end

-- opens a view and lets its sliced work finish
local function open(X, key)
	if not X.UI.Frame() or not X.UI.Frame():IsShown() then X.UI.Toggle() end
	X.UI.Open(key)
	W.advance(3)
	X.UI.Refresh(true)
	W.advance(1.5) -- the debounced refreshes
	return X.UI.tabs[key].panel
end

local function keySet(rows, kind)
	local set, n = {}, 0
	for _, r in ipairs(rows or {}) do
		if not kind or r.kind == kind then
			if not set[r.key] then n = n + 1 end
			set[r.key] = true
		end
	end
	return set, n
end
local function sameSet(title, a, b)
	local missing, extra = {}, {}
	for k in pairs(a) do if not b[k] then extra[#extra + 1] = k end end
	for k in pairs(b) do if not a[k] then missing[#missing + 1] = k end end
	T.ok(title, #missing == 0 and #extra == 0, "missing " .. table.concat(missing, ",") .. " extra " .. table.concat(extra, ","))
end
-- UI.ShowItem replaced by a recorder while fn runs
local function spyShow(X, fn)
	local got = {}
	local old = X.UI.ShowItem
	X.UI.ShowItem = function(key) got[#got + 1] = key end
	local ok, e = pcall(fn)
	X.UI.ShowItem = old
	if not ok then error(e, 0) end
	return got
end

T.scene("views: market, your gold and opportunities with an empty database", function()
	local X = W.start()
	T.check("market: view order", X.UI.tabs.market.n, 2)
	T.check("your gold: view order and title", X.UI.tabs.gold.n .. " " .. X.UI.tabs.gold.title, "3 Your gold")
	T.check("opportunities: view order and title", X.UI.tabs.opps.n .. " " .. X.UI.tabs.opps.title, "4 Opportunities")
	local p = open(X, "market")
	local text = W.screen(p)
	T.ok("market: tiles", text:find("Items known", 1, true) ~= nil and text:find("Short supply", 1, true) ~= nil, text)
	T.ok("market: says to scan", text:find("No prices yet", 1, true) ~= nil, text)
	for _, chip in ipairs({"Rising", "Falling", "Short supply", "Flooded", "Tracked"}) do
		W.click(chip, p)
		W.advance(0.4)
		T.ok("market: " .. chip .. " with nothing", W.screen(p) ~= "")
		W.click(chip, p)
	end
	p = open(X, "gold")
	text = W.screen(p)
	T.ok("gold: tiles", text:find("Gold today", 1, true) ~= nil and text:find("Net worth", 1, true) ~= nil, text)
	for _, part in ipairs({"Best sellers", "Recent", "Characters", "Overview"}) do
		W.click(part, p)
		W.advance(0.3)
		T.ok("gold: " .. part, W.screen(p) ~= "")
	end
	T.ok("gold: empty graph says why", W.screen(p):find("No sales or purchases", 1, true) ~= nil)
	p = open(X, "opps")
	text = W.screen(p)
	T.ok("opportunities: explains what fills it", text:find("Do a full scan at the auction house", 1, true) ~= nil, text)
	T.check("opportunities: no rows", #X.UI.OppsRows(), 0)
end)

local function marketPart(X)
	X.SetWatched(tostring(W.market.byKind.stack[1]), true)
	local p = open(X, "market")
	local tbl = p.tbl
	local total = T.count(X.Items())
	T.check("tiles: items known", W.plain(p.tiles[1].value:GetText()), X.Num(total))
	T.ok("tiles: scans today", tonumber(W.plain(p.tiles[3].value:GetText())) >= 1)
	-- each quick filter shows the same items as X.Movers
	local CHIPS = {{"Rising", "up", 4}, {"Falling", "down", 5}, {"Short supply", "short", 6}, {"Flooded", "flood", nil}}
	for _, c in ipairs(CHIPS) do
		W.click(c[1], p)
		W.advance(0.5)
		local want = keySet(X.Movers(c[2]))
		local got = {}
		for _, r in ipairs(tbl.items) do got[r.key] = true end
		sameSet(c[1] .. ": the items X.Movers finds", got, want)
		if c[3] then T.check(c[1] .. ": the tile counts them", W.plain(p.tiles[c[3]].value:GetText()), X.Num(T.count(want))) end
		T.check(c[1] .. ": kept", X.S().marketFilter.move, c[2])
		W.click(c[1], p) -- off again
		W.advance(0.5)
	end
	T.check("all back", #tbl.items, math.min(2000, total))
	T.ok("planted short supply found", #X.Movers("short") > 0 and #X.Movers("flood") > 0)
	-- Rising sorts by the trend, Flooded by "vs normal"
	W.click("Rising", p)
	W.advance(0.5)
	T.check("rising: sorted by Trend/wk", tbl.sortCol, 5)
	for i = 2, #tbl.items do T.ok("rising: fastest first", tbl.items[i - 1].trend >= tbl.items[i].trend) end
	W.click("Flooded", p)
	W.advance(0.5)
	T.check("flooded: sorted by vs normal", tbl.sortCol, 9)
	W.click("All", p)
	W.advance(0.5)
	-- tracked
	W.click("Tracked", p)
	W.advance(0.5)
	T.check("tracked: one item", #tbl.items, 1)
	W.click("Tracked", p)
	W.advance(0.5)
	-- search
	local name = X.Items()[tostring(W.market.byKind.stack[3])].n
	W.type(p.search, name, false)
	W.advance(0.6)
	T.ok("search: finds the item", #tbl.items >= 1 and tbl.items[1].name == name:lower(), #tbl.items)
	W.type(p.search, "", false)
	W.advance(0.6)
	-- sorting by a header: cheapest first, then most expensive first
	-- the header buttons: the table's own buttons that are not rows or the scroll bar, in column order
	local hdrs = {}
	for _, f in ipairs(tbl.children) do
		if f.kind == "Button" and not f.cols and f ~= tbl.track and f.scripts.OnClick then hdrs[#hdrs + 1] = f end
	end
	local hdr = hdrs[2]
	T.check("one header button per column", #hdrs, #tbl.columns)
	if hdr then
		hdr:Click("LeftButton")
		W.advance(0.2)
		local a, b = tbl.items[1].min, tbl.items[2].min
		local first = tbl.sortDesc
		T.ok("sort: by cheapest", tbl.sortCol == 2 and a and b and ((first and a >= b) or (not first and a <= b)))
		hdr:Click("LeftButton")
		T.ok("sort: the other way", tbl.sortDesc ~= first)
		T.ok("sort: remembered", X.S().sorts["market:1"] ~= nil and X.S().sorts["market:1"][1] == 2)
	else
		tbl.sortCol, tbl.sortDesc = 2, false
		tbl:Sort()
		T.ok("sort: cheapest first", (tbl.items[1].min or 0) <= (tbl.items[2].min or 0))
	end
	-- the 7-day line
	T.ok("7-day line", X.UI.MarketSpark(tbl.items[1].key) ~= nil)
	-- a click on a row opens the item, a right-click the menu
	local got = spyShow(X, function()
		tbl.rows[1]:Click("LeftButton")
		tbl.rows[2]:Click("RightButton")
	end)
	T.check("click: UI.ShowItem with the row's item", got[1], tbl.items[1].key)
	T.check("right-click: not opened", #got, 1)
	X.K.CloseMenu()
end

local function oppsPart(X)
	-- a reset chance and a few-sellers item (market shape data, as a full scan and a search leave them)
	local some = tostring(W.market.byKind.stack[2])
	X.Realm().shape = X.Realm().shape or {}
	X.Realm().shape[some] = {t = X.Now(), reset = {u = 10, c = 1000, p = 5000}, sellers = 2, top = 0.7, ts = X.Now()}
	local p = open(X, "opps")
	local rows = X.UI.OppsRows()
	T.ok("found some", #rows > 0, #rows)
	sameSet("far under usual = X.Deals", keySet(rows, "deal"), keySet(X.Deals()))
	sameSet("under vendor price = X.BelowVendor", keySet(rows, "below"), keySet(X.BelowVendor()))
	sameSet("vendor flips = X.VendorFlips", keySet(rows, "vflip"), keySet(X.VendorFlips()))
	sameSet("under disenchant = X.UnderDE", keySet(rows, "de"), keySet(X.UnderDE()))
	sameSet("resets = X.Resets", keySet(rows, "reset"), keySet(X.Resets()))
	T.ok("planted deals, vendor flips, under vendor", select(2, keySet(rows, "deal")) > 0 and select(2, keySet(rows, "vflip")) > 0 and
		select(2, keySet(rows, "below")) > 0)
	T.ok("reset row", keySet(rows, "reset")[some] == true)
	T.ok("few sellers row", keySet(rows, "few")[some] == true)
	local tbl = p.tbl
	-- best first: the most profit of one
	T.check("sorted by profit", tbl.sortCol, 5)
	for i = 2, #tbl.items do T.ok("most profit first", (tbl.items[i - 1].profit or -1e12) >= (tbl.items[i].profit or -1e12)) end
	local deal = keySet(rows, "deal")
	for _, r in ipairs(rows) do
		if r.kind == "deal" then
			T.ok("deal: profit = sells for - buy at", math.abs(r.profit - (r.sell - r.buy)) < 1)
			T.ok("deal: why", r.why:find("Far under usual", 1, true) ~= nil)
			T.ok("deal: price age", r.t ~= nil)
			break
		end
	end
	-- a kind chip shows only that kind; again = all
	W.click("Vendor flip", p)
	W.advance(0.3)
	local only = true
	for _, r in ipairs(tbl.items) do if r.kind ~= "vflip" then only = false end end
	T.ok("vendor flip chip: only vendor flips", only and #tbl.items > 0)
	T.check("chip kept", X.S().oppsFilter.kind, "vflip")
	W.click("Vendor flip", p)
	W.advance(0.3)
	T.check("again: all", #tbl.items, #rows)
	-- hide slow sellers: nothing known under 1 a day stays
	X.SaleRate = (function(old) return function(key) if deal[key] then return 0.2, 5 end return old(key) end end)(X.SaleRate)
	X.Fire("XNAH_PRICES")
	X.UI.Refresh(true)
	W.advance(3)
	X.UI.Refresh(true)
	W.click("Hide slow sellers", p)
	W.advance(0.3)
	local slow = 0
	for _, r in ipairs(tbl.items) do if r.rate and r.rate < 1 then slow = slow + 1 end end
	T.check("hide slow sellers: none slow", slow, 0)
	T.ok("hide slow sellers: fewer rows", #tbl.items < #X.UI.OppsRows())
	W.click("Hide slow sellers", p)
	W.advance(0.3)
	-- profit filter (set as the menu does) and search
	X.S().oppsFilter.minProfit = 10000
	X.S().oppsFilter.kind = nil
	X.UI.Select("market")
	X.UI.Select("opps")
	W.advance(0.3)
	local under = 0
	for _, r in ipairs(tbl.items) do if (r.profit or 0) < 10000 then under = under + 1 end end
	T.ok("profit filter: all 1g or more", under == 0 and W.screen(p):find("Profit at least: 1g", 1, true) ~= nil)
	X.S().oppsFilter.minProfit = nil
	X.UI.Refresh(true)
	W.type(p.search, "under vendor", false)
	W.advance(0.6)
	only = #tbl.items > 0
	for _, r in ipairs(tbl.items) do if r.kind ~= "below" then only = false end end
	T.ok("search: by the why text", only)
	W.type(p.search, "", false)
	W.advance(0.6)
	-- click = the item
	local got = spyShow(X, function() tbl.rows[1]:Click("LeftButton") end)
	T.check("click: UI.ShowItem", got[1], tbl.items[1].key)
	-- new prices while shown: worked out again (after a second)
	local fresh = "70301"
	for d = 5, 1, -1 do X.Record(fresh, X.Now() - d * 86400, 100000, 100000, 20, 5, "Shiny Test Gem", 2) end
	X.Record(fresh, X.Now(), 20000, 100000, 20, 5, "Shiny Test Gem", 2)
	X.Fire("XNAH_PRICES")
	W.advance(0.5)
	X.UI.Refresh(true)
	W.advance(4)
	T.ok("new prices: the new deal appears", keySet(X.UI.OppsRows(), "deal")[fresh] == true)
	-- a changed setting: worked out again with it
	X.S().dealPct = 10
	X.UI.Refresh(true)
	W.advance(4)
	sameSet("stricter setting: the deals X.Deals finds now", keySet(X.UI.OppsRows(), "deal"), keySet(X.Deals()))
	T.ok("stricter setting: fewer deals", select(2, keySet(X.UI.OppsRows(), "deal")) < select(2, keySet(rows, "deal")))
	X.S().dealPct = 60
end

local H = 3600
local function add(X, list, t, key, count, money, cut)
	table.insert(X.Ledger()[list], {t = t, key = key, name = X.ItemName(key) or key, count = count, money = money, cut = cut, char = "Xn Ascalon"})
end

T.scene("views: your gold - tiles, graphs, best sellers, recent, characters", function()
	local X = W.start()
	W.advance(5)
	local t0 = X.Now() - 5 * H
	add(X, "buys", t0, "2589", 10, 1000)
	add(X, "sales", t0 + H, "2589", 10, 3000, 150)
	add(X, "sales", t0 + 2 * H, "2592", 5, 9000, 450)
	add(X, "sales", X.Now() - 10 * 86400, "2592", 2, 4000, 200)
	add(X, "expired", t0, "2592", 3)
	W.setMoney(1234567 + 30000)
	W.advance(3)
	local p = open(X, "gold")
	W.click("Overview", p)
	W.advance(0.5)
	local text = W.screen(p)
	T.ok("tile: gold today +3g", W.plain(p.tiles[1].value:GetText()) == "+3g", p.tiles[1].value:GetText())
	local n = X.GoldNumbers()
	T.check("tile: profit this week", W.plain(p.tiles[3].value:GetText()), "+" .. W.plain(X.Money(n.profitWeek, true)))
	T.ok("overview: daily graph drawn", text:find("No sales or purchases in the last 30", 1, true) == nil, text)
	T.ok("overview: flips", text:find("Linen Cloth", 1, true) ~= nil)
	-- best sellers: income first
	W.click("Best sellers", p)
	W.advance(0.5)
	local best = p.views.items.tbl
	T.check("best sellers: most income first", best.items[1] and best.items[1].key, "2592")
	T.ok("best sellers: sell-through shown", W.screen(p):find("Sell-through", 1, true) ~= nil)
	local got = spyShow(X, function() best.rows[1]:Click("LeftButton") end)
	T.check("best sellers: click opens the item", got[1], "2592")
	W.click("Recent", p)
	W.advance(0.5)
	local recent = p.views.recent.tbl
	T.check("recent: newest first", recent.items[1] and recent.items[1].key, "2592")
	T.ok("recent: expired listed", W.screen(p):find("expired", 1, true) ~= nil)
	W.click("Characters", p)
	W.advance(0.5)
	T.ok("characters: this one", W.screen(p):find("Xn Ascalon", 1, true) ~= nil)
	T.ok("characters: no delete button", W.findButton("Delete a character", p) == nil)
	-- the old names open the right part
	X.UI.Select("ledger")
	W.advance(0.5)
	T.check("ledger: best sellers", X.S().goldView, "items")
end)

-- no button in the three views buys, posts, cancels or bids: every visible button is clicked (rows too)
local function noActionPart(X)
	add(X, "buys", X.Now() - 3 * H, "2589", 10, 1000)
	add(X, "sales", X.Now() - H, "2589", 10, 3000, 150)
	local before, bids = #W.restrictedCalls, #W.bids
	local words = {}
	local clicked = 0
	spyShow(X, function()
		for _, key in ipairs({"market", "gold", "opps"}) do
			local p = open(X, key)
			local parts = key == "gold" and {"Overview", "Best sellers", "Recent", "Characters"} or {false}
			for _, part in ipairs(parts) do
				if part then W.click(part, p) W.advance(0.3) end
				local list = {}
				W.walk(p, function(f)
					if (f.kind == "Button" or f.kind == "CheckButton") and f.scripts.OnClick and f:IsVisible() then list[#list + 1] = f end
				end)
				for _, f in ipairs(list) do
					if not f.cols then
						local t = W.plain(W.buttonText(f))
						for _, w in ipairs({"Buy", "Post", "Cancel", "Bid", "Sell ", "Purchase"}) do
							if t:find(w, 1, true) then words[#words + 1] = t end
						end
					end
					if f:IsVisible() then
						f:Click("LeftButton")
						clicked = clicked + 1
						X.K.CloseMenu()
					end
				end
				W.advance(0.5)
			end
		end
	end)
	T.ok("many buttons clicked", clicked > 40, clicked)
	T.check("no buy / post / cancel calls", #W.restrictedCalls, before)
	T.check("no bids", #W.bids, bids)
	T.check("no button named like an action", table.concat(words, ", "), "")
end

T.scene("views: market overview, opportunities and no action buttons with a 10-day market", function()
	local X = W.start()
	tenDays(X)
	marketPart(X)
	oppsPart(X)
	noActionPart(X)
end)

-- a big realm: the market rows and the opportunities are worked out a few hundred items per frame
T.scene("views: a big data set is worked out in slices", function()
	local X = W.start()
	local now = X.Now()
	local N = 6000
	for i = 1, N do
		local key = tostring(200000 + i)
		local p = 20000 + (i % 97) * 100
		for d = 4, 1, -1 do X.Record(key, now - d * 86400, p, p, 20, 3, "Bulk Thing " .. i, 1) end
		X.Record(key, now - 60, (i % 500 == 0) and math.floor(p * 0.3) or p, p, 20, 3, "Bulk Thing " .. i, 1)
	end
	X.Fire("XNAH_PRICES")
	X.UI.Toggle()
	X.UI.Open("market")
	T.ok("market: still working after the first frame", X.JobRunning("market rows"))
	W.advance(W.FRAME * 3)
	T.ok("market: still working after 3 frames", X.JobRunning("market rows"))
	T.ok("market: says it is reading", W.screen(X.UI.tabs.market.panel):find("Reading prices", 1, true) ~= nil)
	W.advance(10)
	X.UI.Refresh(true)
	T.ok("market: done", not X.JobRunning("market rows"))
	T.check("market: every item", W.plain(X.UI.tabs.market.panel.tiles[1].value:GetText()), X.Num(N))
	T.check("market: at most 2000 rows shown", #X.UI.tabs.market.panel.tbl.items, 2000)
	X.UI.Open("opps")
	T.ok("opportunities: still working after the first frame", X.JobRunning("opportunities"))
	W.advance(W.FRAME * 3)
	T.ok("opportunities: still working after 3 frames", X.JobRunning("opportunities"))
	W.advance(10)
	X.UI.Refresh(true)
	T.ok("opportunities: done", not X.JobRunning("opportunities"))
	T.check("opportunities: the 12 deals", select(2, keySet(X.UI.OppsRows(), "deal")), 12)
	sameSet("opportunities: = X.Deals", keySet(X.UI.OppsRows(), "deal"), keySet(X.Deals()))
end)
