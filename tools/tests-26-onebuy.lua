-- XNAH test scenes, part 26: one Buy tab (v0.8). The Deals tab is gone: its buy ideas are in Best buys (tab Buy), its
-- sell ideas on tab Sell, its make ideas on tab Crafting, Adjust ideas on tab Buy; old names still open the right place.
-- And the small pieces other files build on: "Price alert ..." in the item menu, the "Keep in stock" tick of a shopping
-- list entry, the "Best day" column of Worth posting, the Next step line of the crafting queue.

local function history(X, key, usual, days)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5) end
end
local function shownTabs(X)
	local out = {}
	for _, k in ipairs(X.UI.order) do if not X.UI.tabs[k].hidden then out[#out + 1] = k end end
	return table.concat(out, ",")
end
local function has(root, text) return W.screen(root):find(text, 1, true) ~= nil end

T.scene("onebuy: the Deals tab is gone, its views moved, old names still work", function()
	local X = W.start()
	X.UI.Toggle()
	T.ok("no Deals tab", X.UI.tabs.deals == nil)
	T.check("seven tabs, in order", shownTabs(X), "home,market,item,buy,sell,craft,gold")
	-- the tab buttons: no "Deals"
	local frame = X.UI.Frame()
	T.ok("no Deals button", W.findButton("Deals", frame) == nil)
	-- Buy: Best buys, Shopping lists and sniper, Adjust ideas
	X.UI.Open("buy")
	W.advance(0.5)
	local p = X.UI.tabs.buy.panel
	for _, v in ipairs({"Best buys", "Shopping lists and sniper", "Adjust ideas"}) do T.ok("Buy view " .. v, W.findButton(v, p) ~= nil) end
	T.check("opens on Best buys", X.S().buyView, "best")
	T.ok("best buys shown", p.bestView:IsVisible() and not p.listsView:IsVisible() and not p.adjustView:IsVisible())
	W.click("Adjust ideas", p)
	W.advance(0.3)
	T.ok("adjust shown", p.adjustView:IsVisible() and not p.bestView:IsVisible())
	T.ok("adjust: the ideas", has(p, "Under usual price") and has(p, "Use in the lists"), W.screen(p))
	W.click("Shopping lists and sniper", p)
	W.advance(0.3)
	T.ok("lists shown", p.listsView:IsVisible() and has(p, "Sniper"))
	-- the view is remembered
	X = W.reload()
	X.UI.Toggle()
	X.UI.Open("buy")
	W.advance(0.5)
	T.ok("after a reload: the lists again", X.UI.tabs.buy.panel.listsView:IsVisible())
	-- Sell ideas on Sell, Make ideas on Crafting
	X.UI.Open("sell")
	W.advance(0.5)
	local sp = X.UI.tabs.sell.panel
	W.click("Sell ideas", sp)
	W.advance(0.3)
	T.ok("Sell ideas view", sp.ideasView:IsVisible() and not sp.worthList:IsVisible())
	T.ok("Sell ideas: its columns", has(sp, "Action") and has(sp, "Target"), W.screen(sp))
	W.click("Worth posting", sp)
	W.advance(0.3)
	T.ok("back to Worth posting", sp.worthList:IsVisible() and not sp.ideasView:IsVisible())
	X.UI.Open("craft")
	W.advance(0.5)
	local cp = X.UI.tabs.craft.panel
	W.click("Make ideas", cp)
	W.advance(0.3)
	T.ok("Make ideas view", cp.make:IsVisible() and not cp.list:IsVisible() and not cp.queue:IsVisible())
	W.click("Queue", cp)
	W.advance(0.3)
	T.ok("Queue view", cp.queue:IsVisible() and not cp.make:IsVisible())
	W.click("Recipes", cp)
	W.advance(0.3)
	T.ok("Recipes view", cp.list:IsVisible() and not cp.make:IsVisible())
	-- old names: deals -> Best buys, strategies -> Adjust ideas (Home and the guide still say "deals")
	X.S().buyView = "lists"
	X.UI.Open("deals")
	T.check("deals opens Buy", X.UI.current, "buy")
	T.ok("deals: on Best buys", X.UI.tabs.buy.panel.bestView:IsVisible())
	X.UI.Open("strategies")
	T.check("strategies opens Buy", X.UI.current, "buy")
	T.ok("strategies: on Adjust ideas", X.UI.tabs.buy.panel.adjustView:IsVisible())
	X.UI.Select("deals")
	T.check("Select deals: Buy", X.UI.current, "buy")
	-- toggling with an old name: the window closes when that page is shown
	X.UI.Toggle("deals")
	T.ok("toggle deals on Buy: closed", not X.UI.Frame():IsShown())
	X.UI.Toggle("deals")
	T.ok("toggle again: open on Buy", X.UI.Frame():IsShown() and X.UI.current == "buy")
	-- an old saved page name opens Buy
	X.S().tab = "deals"
	X.UI.Frame():Hide()
	X.UI.current = nil
	X.UI.Open()
	T.check("saved page deals: Buy", X.UI.current, "buy")
	-- the guide's and Home's jobs point at tab "deals": they land on Buy
	if X.ShowGuide then
		X.UI.Open("market")
		X.UI.Open("deals")
		T.check("a link to deals lands on Buy", X.UI.current, "buy")
	end
	-- an unknown view setting falls back to Best buys
	X.S().buyView = "nonsense"
	X.UI.Refresh(true)
	T.ok("unknown view: Best buys", X.UI.tabs.buy.panel.bestView:IsVisible())
	T.check("unknown view: put right", X.S().buyView, "best")
end)

T.scene("onebuy: Price alert in the item menu, Keep in stock tick", function()
	local X = W.start()
	history(X, "2589", 100)
	X.UI.Toggle()
	X.UI.Open("market")
	W.advance(0.5)
	local anchor = X.UI.Frame()
	-- without X.AskAlert: no entry
	local saved = X.AskAlert
	X.AskAlert = nil
	X.UI.ItemMenu(anchor, "2589")
	T.ok("no AskAlert: no Price alert entry", W.findButton("Price alert") == nil)
	X.K.CloseMenu()
	-- with it: the entry asks for the item
	local asked
	X.AskAlert = function(k) asked = k end
	X.UI.ItemMenu(anchor, "2589")
	local entry = W.findButton("Price alert ...")
	T.ok("Price alert entry", entry ~= nil)
	if entry then entry:Click() end
	T.check("Price alert asks for the item", asked, "2589")
	X.AskAlert = saved
	-- the shopping list entry: Keep in stock
	X.ShopAdd("Mats", "2589", 20, 70)
	local calls = {}
	local set = X.ShopSet
	X.ShopSet = function(list, k, fieldName, value)
		calls[#calls + 1] = table.concat({tostring(list), tostring(k), tostring(fieldName), tostring(value)}, " ")
		return set(list, k, fieldName, value)
	end
	X.S().shopList = "Mats"
	X.S().buyView = "lists"
	X.UI.Open("buy")
	W.advance(0.5)
	local p = X.UI.tabs.buy.panel
	T.ok("lists view", p.listsView:IsVisible())
	local row = p.shopTable.rows[1]
	T.ok("the entry row", row and row:IsVisible())
	row:Click()
	W.advance(0.3)
	T.ok("entry box shown", p.entryBox:IsVisible())
	T.ok("Keep in stock tick", p.keepCheck:IsVisible() and not p.keepCheck:GetChecked())
	T.check("not ticked: Buy in all", W.plain(p.qtyLabel.text), "Buy in all")
	T.ok("not ticked: bought / wanted", has(p.shopTable, "0/20"), W.screen(p.shopTable))
	p.keepCheck:Click() -- a click ticks it
	T.check("tick: ShopSet keep on", calls[#calls], "Mats 2589 keep true")
	-- what the list shows once the entry keeps stock (the Shop.lua side sets e.keep)
	local e = X.ShopEntry("Mats", "2589")
	e.keep = true
	X.UI.Refresh(true)
	T.check("ticked: Keep", W.plain(p.qtyLabel.text), "Keep")
	T.ok("ticked: the box ticked", p.keepCheck:GetChecked() == true)
	T.ok("ticked: the list says keep 20", has(p.shopTable, "keep 20"), W.screen(p.shopTable))
	T.ok("Need: what ShopNeed says", has(p.shopTable, X.Num(X.ShopNeed(e))))
	p.keepCheck:Click()
	T.check("untick: ShopSet keep off", calls[#calls], "Mats 2589 keep false")
	e.keep = nil
	X.UI.Refresh(true)
	T.check("unticked: Buy in all again", W.plain(p.qtyLabel.text), "Buy in all")
	-- the quantity box still sets the number
	W.type(p.qtyBox, "30")
	T.check("qty box: ShopSet qty", calls[#calls], "Mats 2589 qty 30")
	X.ShopSet = set
end)

T.scene("onebuy: the Best day column copes with X.BestDay missing, nil or broken", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	W.list(2589, 100, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.openAH()
	local saved = X.BestDay
	X.BestDay = nil
	X.UI.Toggle()
	X.UI.Open("sell")
	W.advance(1)
	local p = X.UI.tabs.sell.panel
	T.ok("the column", has(p, "Best day"), W.screen(p))
	local function rowOf(key)
		for _, row in ipairs(p.worthList.rows) do
			if row:IsVisible() and row.item and row.item.key == key then return row end
		end
	end
	local function cell(key)
		local row = rowOf(key)
		return row and W.plain(row.cols[7].text)
	end
	T.check("no X.BestDay: -", cell("2589"), "-")
	-- not enough history: nil
	X.BestDay = function() return nil end
	X.UI.Refresh(true)
	T.check("nil: -", cell("2589"), "-")
	-- broken: still a dash, no error
	X.BestDay = function() error("broken") end
	X.UI.Refresh(true)
	T.check("an error: -", cell("2589"), "-")
	-- known: the short day, and the tooltip says how much more
	X.BestDay = function(k)
		if k == "2589" then return {day = 3, name = "Tuesday", short = "Tue", pct = 8, weeks = 6} end
		return nil
	end
	X.UI.Refresh(true)
	T.check("known: Tue", cell("2589"), "Tue")
	T.check("the other: -", cell("2592"), "-")
	local row = rowOf("2589")
	W.hover(row)
	local tip = W.tipText()
	T.ok("tooltip: the best day and how much more", tip:find("Best day to sell: Tuesday (+8% over the average day) - 6 weeks of prices", 1, true) ~= nil, tip)
	W.unhover(row)
	row = rowOf("2592")
	W.hover(row)
	T.ok("tooltip: nothing when not known", W.tipText():find("Best day", 1, true) == nil)
	W.unhover(row)
	X.BestDay = saved
end)

T.scene("onebuy: the crafting queue says the Next step key does it too", function()
	local X = W.start()
	local saved = X.DoNext
	X.DoNext = nil
	X.UI.Toggle()
	X.S().craftView = "queue"
	X.UI.Open("craft")
	W.advance(0.5)
	local q = X.UI.tabs.craft.panel.queue
	T.ok("queue shown", q:IsVisible())
	T.check("no X.DoNext: no line", q.nextLine.text or "", "")
	X.DoNext = function() end
	W.bindings.XNAH_NEXT = "F"
	X.UI.Refresh(true)
	local line = W.plain(q.nextLine.text)
	T.ok("the line", line:find("Next step key (F) does this queue too", 1, true) ~= nil, line)
	T.ok("says it buys and crafts", line:find("buys the materials", 1, true) ~= nil and line:find("then crafts", 1, true) ~= nil, line)
	W.bindings.XNAH_NEXT = nil
	X.UI.Refresh(true)
	T.ok("no key: still the line", W.plain(q.nextLine.text):find("Next step key does", 1, true) ~= nil, q.nextLine.text)
	X.DoNext = saved
end)

T.scene("onebuy: Best buys - your own rows (list, crafting queue, watched) stay, ideas only for the buttons", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "14047", 20000)
	-- the best buys of the Next buy key (Buy.lua) as a stand-in: one of each of your own kinds and one idea
	local saved = X.BuyIdeas
	X.BuyIdeas = function()
		return {
			{id = "shop:Mats:2589", key = "2589", kind = "list", from = "list Mats", action = "Buy", qty = 10, max = 70, price = 50,
				profit = 0, source = "shop", tag = "Mats"},
			{id = "queue:2592", key = "2592", kind = "queue", from = "craft queue", action = "Buy", qty = 4, max = 40, price = 30,
				profit = 0, source = "queue", tag = "queue:2592"},
			{id = "idea:14047", key = "14047", kind = "deal", from = "deal", action = "Buy and relist", qty = 1, price = 8000,
				each = 10000, profit = 10000, target = 19000, max = 13000, source = "idea", tag = "idea:14047"},
		}
	end
	X.S().dealSpeedHide, X.S().dealSpeedMin = true, 100000
	X.UI.Toggle()
	X.UI.Open("buy")
	W.advance(0.5)
	local p = X.UI.tabs.buy.panel
	local rows = p.bestList.items
	local kinds = {}
	for _, r in ipairs(rows) do kinds[#kinds + 1] = r.kind .. " " .. r.key .. " " .. (r.ideaName or "?") end
	T.check("your rows first, then the deal", table.concat(kinds, ", "),
		"list 2589 Shopping list, queue 2592 Crafting queue, deal 14047 Under usual price")
	T.ok("the queue row says so", W.screen(p.bestList):find("material for your crafting queue", 1, true) ~= nil, W.screen(p.bestList))
	T.check("the queue row: its Buy button source", p.bestList.rows[2].buyButton and p.bestList.rows[2].buyButton.source, "queue")
	-- Add to shopping list / Snipe at this price: only the idea
	W.click("Add to shopping list", p)
	local l = X.ShopList("Deals")
	T.check("shopping list: only the idea", l and #l.items, 1)
	T.check("shopping list: the deal, at its max", l and l.items[1] and (l.items[1].key .. " " .. l.items[1].max), "14047 13000")
	X.S().dealSpeedHide = false
	X.BuyIdeas = saved
end)
