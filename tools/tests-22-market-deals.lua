-- XNAH test scenes, part 22: the Market page (Rising / Falling buttons, Sells a day, the 7-day line in each row) and the
-- ideas of the old Deals page (v0.8): Best buys on the Buy tab (every buy idea with a Buy button per row), Sell ideas on
-- the Sell tab, Make ideas on the Crafting tab, Adjust ideas on the Buy tab.

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
	X.StrategyForget()
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

local function rowsOf(tbl) return tbl.items or {} end
local function findRow(rows, k)
	for _, r in ipairs(rows or {}) do if r.key == k then return r end end
end

local function shown(p, text) return W.screen(p):find(text, 1, true) ~= nil end

T.scene("market and deals: Buy - best buys with every buy idea, Sell ideas, Make ideas, Adjust ideas", function()
	local X = W.start()
	market(X)
	-- the Buy button as a stand-in that only remembers what it was given
	local given = {}
	X.UI.BuyButton = function(parent, w, h)
		local b = X.K.Button(parent, "Buy", w, h)
		function b:SetItem(k, qty, maxEach, source, tag) given[#given + 1] = {k, qty, maxEach, source, tag} end
		b:SetScript("OnClick", function() end)
		return b
	end
	X.UI.Toggle()
	X.UI.Open("buy")
	W.advance(3) -- the ideas are worked out in slices
	X.UI.Refresh(true)
	T.ok("no Deals tab", X.UI.tabs.deals == nil)
	T.ok("no Strategies tab", X.UI.tabs.strategies == nil)
	local p = X.UI.tabs.buy.panel
	local text = W.screen(p)
	for _, s in ipairs({"Best buys", "Shopping lists and sniper", "Adjust ideas", "Next buy", "Idea", "Price now", "Sells for",
		"Profit each", "Profit in all", "Sells a day", "Risk", "Why", "Search these on the AH", "Add to shopping list",
		"Snipe at this price", "Hide items that sell under"}) do
		T.ok("best buys shows " .. s, text:find(s, 1, true) ~= nil)
	end
	local rows = rowsOf(p.bestList)
	local hide, herb = findRow(rows, key("hide")), findRow(rows, key("herb"))
	T.ok("best: the hide under vendor price", hide ~= nil and hide.idea == "vendorfloor", hide and hide.idea)
	T.ok("best: the herb under its usual price", herb ~= nil, text)
	T.ok("best: the herb found by two ideas", herb and herb.more and herb.more >= 1, herb and herb.more)
	T.ok("best: one row per item", #rows == (function() local s, n = {}, 0 for _, r in ipairs(rows) do if not s[r.key] then s[r.key] = true n = n + 1 end end return n end)())
	T.ok("best: the why says sell to a vendor", text:find("sell to a vendor", 1, true) ~= nil, text)
	T.ok("best: no sell or make rows", findRow(rows, key("flood")) == nil and findRow(rows, key("potion")) == nil)
	T.ok("best: the herb has a risk", herb and herb.risk ~= nil, herb and herb.risk)
	-- the Buy button: what it was given (item, how many, the most each, where from)
	local g
	for _, x in ipairs(given) do if x[1] == key("herb") then g = x end end
	T.ok("buy button: set for the herb", g ~= nil)
	if g and herb then
		T.check("buy button: source (shared with the Next buy key)", g[4], "idea")
		T.check("buy button: tag", g[5], "idea:" .. key("herb"))
		T.check("buy button: max each = price + half the profit", g[3], math.floor(herb.now + herb.each / 2))
		T.check("buy button: qty", g[2], herb.qty)
	end
	local n = #given
	X.UI.Refresh(true)
	T.check("buy button: drawn again, not set again", #given, n)
	-- the mouse over a row: why it is a good buy
	local rf = p.bestList.rows[1]
	if rf and rf:IsVisible() then
		W.hover(rf)
		T.ok("hover: the idea in the tooltip", W.tipText():find(p.bestList.items[1 + p.bestList.offset].ideaName or "?", 1, true) ~= nil, W.tipText())
		W.unhover(rf)
	end
	-- sorting by a column (every column but Why and the button)
	for i = 1, 9 do T.ok("column " .. i .. " sorts", p.bestList.columns[i].sort ~= nil) end
	p.bestList.sortCol, p.bestList.sortDesc = 7, true
	p.bestList:Sort()
	rows = rowsOf(p.bestList)
	T.ok("sorted: most profit first", #rows < 2 or (rows[1].total or 0) >= (rows[2].total or 0))
	local b1 = p.bestList.rows[1] and p.bestList.rows[1].buyButton
	T.ok("sorted: the buttons follow", rows[1] == nil or rows[1].vendor or (b1 and b1.bestId and b1.bestId:find(rows[1].key .. ":", 1, true) == 1))
	-- speed filter
	X.S().dealSpeedMin = 100000
	W.click("Hide items that sell under", p)
	T.check("speed filter on", X.S().dealSpeedHide, true)
	for _, r in ipairs(rowsOf(p.bestList)) do T.ok("filter: no known slow seller " .. r.key, r.rate == nil or r.kind == "list" or r.kind == "watch") end
	W.click("Hide items that sell under", p)
	T.check("speed filter off", X.S().dealSpeedHide, false)
	-- shopping list and sniper
	W.click("Add to shopping list", p)
	T.ok("shopping list made", X.ShopList == nil or X.ShopList("Deals") ~= nil)
	W.click("Snipe at this price", p)
	T.ok("sniper: max price", X.WatchMax(key("herb")) ~= nil)
	-- Sell ideas: a view of the Sell tab
	X.UI.Open("sell")
	W.advance(0.5)
	local sp = X.UI.tabs.sell.panel
	W.click("Sell ideas", sp)
	W.advance(0.3)
	text = W.screen(sp)
	T.ok("sell ideas: the flooded leather", text:find("Flooded Leather", 1, true) ~= nil, text)
	T.ok("sell ideas: says Hold", text:find("Hold", 1, true) ~= nil)
	T.ok("sell ideas: no buy rows", text:find("Cheap Hide", 1, true) == nil)
	T.ok("sell ideas: no shopping list button", W.findButton("Add to shopping list", sp) == nil)
	T.ok("sell ideas: the Worth posting list hidden", not sp.worthList:IsVisible())
	-- Make ideas: a view of the Crafting tab
	X.UI.Open("craft")
	W.advance(0.5)
	local cp = X.UI.tabs.craft.panel
	W.click("Make ideas", cp)
	W.advance(0.3)
	text = W.screen(cp)
	T.ok("make ideas: the potion", text:find("Fine Potion", 1, true) ~= nil, text)
	T.check("make ideas: remembered", X.S().craftView, "make")
	T.ok("make ideas: the recipe list hidden", not cp.list:IsVisible())
	-- its Adjust ideas button opens Adjust ideas on the Buy tab
	W.click("Adjust ideas", cp)
	W.advance(0.3)
	T.check("adjust: on the Buy tab", X.UI.current, "buy")
	T.check("adjust: the view", X.S().buyView, "adjust")
	text = W.screen(p)
	for _, s in ipairs({"Under usual price", "Vendor floor", "Buy the dip", "Hold in a flood", "Crafting margin", "Use in the lists",
		"Reset numbers", "Work out again"}) do
		T.ok("adjust shows " .. s, text:find(s, 1, true) ~= nil)
	end
	T.ok("adjust: the best buys hidden", W.findButton("Snipe at this price", p) == nil)
	-- Under usual price: its numbers are the deal settings
	W.click("Under usual price", p)
	W.advance(0.3)
	local box
	W.walk(p, function(f) if not box and f.kind == "EditBox" and f:IsVisible() and f.text == "60" then box = f end end)
	T.ok("usual: a box with 60", box ~= nil)
	if box then
		W.type(box, "40")
		W.step(box.scripts.OnEditFocusLost, box)
		T.check("usual: typed 40", X.S().dealPct, 40)
		W.click("Reset numbers", p)
		T.check("usual: reset to 60", X.S().dealPct, 60)
	end
	-- a strategy's numbers
	W.click("Buy the dip", p)
	W.advance(0.3)
	box = nil
	W.walk(p, function(f) if not box and f.kind == "EditBox" and f:IsVisible() and f.text == "70" then box = f end end)
	T.ok("dip: a box with 70", box ~= nil)
	if box then
		W.type(box, "55")
		W.step(box.scripts.OnEditFocusLost, box)
		W.advance(3)
		T.check("dip: typed 55", X.StrategyParams("dip").pct, 55)
	end
	W.click("Reset numbers", p)
	T.check("dip: reset", X.StrategyParams("dip").pct, 70)
	W.click("Mark on tooltips", p)
	W.advance(1)
	T.check("dip: marked", X.StrategyOn("dip"), true)
	-- leave Vendor floor out of the lists: the hide goes
	W.click("Vendor floor", p)
	W.advance(0.3)
	W.click("Use in the lists", p)
	T.check("vendor floor left out", X.S().dealsHidden.vendorfloor, true)
	W.click("Work out again", p)
	W.advance(3)
	W.click("Best buys", p)
	W.advance(0.3)
	X.UI.Refresh(true)
	rows = rowsOf(p.bestList)
	T.ok("left out: the hide gone", findRow(rows, key("hide")) == nil or findRow(rows, key("hide")).idea ~= "vendorfloor")
	T.ok("left out: the herb still there", findRow(rows, key("herb")) ~= nil)
	-- the right-click menu of a row
	local rowFrame = p.bestList.rows[1]
	if rowFrame and rowFrame:IsVisible() then
		rowFrame.scripts.OnClick(rowFrame, "RightButton")
		T.ok("menu: never suggest buying this", W.findButton("Never suggest buying this") ~= nil)
		X.K.CloseMenu()
	end
	-- the real Buy button: set for the row's item, shared with the Next buy key, keeps its step when redrawn
	X = W.start()
	market(X)
	X.UI.Toggle()
	X.UI.Open("buy")
	W.advance(3)
	X.UI.Refresh(true)
	p = X.UI.tabs.buy.panel
	local btn, herbRow
	for i, f in ipairs(p.bestList.rows) do
		local r = p.bestList.items[i + p.bestList.offset]
		if r and r.key == key("herb") then btn, herbRow = f.buyButton, r end
	end
	T.ok("real button: in the herb row", btn ~= nil)
	if btn and herbRow then
		T.check("real button: item", btn.key, key("herb"))
		T.check("real button: source", btn.source, "idea")
		T.check("real button: tag", btn.tag, "idea:" .. key("herb"))
		T.check("real button: max each", btn.max, math.floor(herbRow.now + herbRow.each / 2))
		T.check("real button: says Buy", W.plain(W.buttonText(btn)), "Buy")
		btn:Click()
		W.advance(3)
		local after = W.plain(W.buttonText(btn))
		T.ok("real button: the next step after a click", after ~= "Buy", after)
		X.UI.Refresh(true)
		T.check("real button: drawn again, same step", W.plain(W.buttonText(btn)), after)
		W.closeAH()
		W.advance(0.5)
		X.UI.Refresh(true)
		T.check("real button: auction house closed", W.plain(W.buttonText(btn)), "Open the auction house")
	end
	-- an empty start: every view says something
	X = W.start()
	X.UI.Toggle()
	X.UI.Open("buy")
	W.advance(1)
	p = X.UI.tabs.buy.panel
	T.ok("empty / Best buys: says something", shown(p, "No prices yet"), W.screen(p))
	W.click("Adjust ideas", p)
	W.advance(0.5)
	T.ok("empty / Adjust ideas: says something", shown(p, "No prices yet"), W.screen(p))
	X.UI.Open("sell")
	W.advance(0.5)
	W.click("Sell ideas", X.UI.tabs.sell.panel)
	W.advance(0.5)
	T.ok("empty / Sell ideas: says something", shown(X.UI.tabs.sell.panel, "No prices yet"), W.screen(X.UI.tabs.sell.panel))
	X.UI.Open("craft")
	W.advance(0.5)
	W.click("Make ideas", X.UI.tabs.craft.panel)
	W.advance(0.5)
	T.ok("empty / Make ideas: says something", shown(X.UI.tabs.craft.panel, "No prices yet"), W.screen(X.UI.tabs.craft.panel))
	-- old page names still open the right page
	X.UI.Open("strategies")
	T.check("strategies opens Buy", X.UI.current, "buy")
	T.check("strategies: on Adjust ideas", X.S().buyView, "adjust")
	X.UI.Open("deals")
	T.check("deals opens Buy", X.UI.current, "buy")
	T.check("deals: on Best buys", X.S().buyView, "best")
	X.UI.Open("trends")
	T.check("trends opens Market", X.UI.current, "market")
end)
