-- XNAH test scenes, part 29: a stack of an item that is NOT a commodity (it stacks, but is sold one auction per stack,
-- like gear). The game's item search gives such a row's buyout as the price of ONE, also for a stack of 40 (its own
-- list shows it as it is, its Buyout button sends it unchanged). XNAH used to divide it by the quantity, so a stack of
-- 40 at 49s 99c each read as 1s 25c each - 40 times too cheap. Here: one auction of 40 at 49s 99c each and one single
-- at 1g.

local MAP = 50001
local KEY = tostring(MAP)
local ONE = 4999         -- 49s 99c each
local STACK = ONE * 40   -- 19g 99s 60c for all 40

local function history(X, key, usual, days)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5) end
end
local function searchNow(X, key)
	local got
	X.LiveSearch(key, function(live) got = live end)
	W.waitFor(function() return got ~= nil end, 10)
	return got
end
-- a click of ours (a hardware event)
local function press(fn)
	local was = W.hardware
	W.hardware = true
	local ok, e = pcall(fn)
	W.hardware = was
	if not ok then error(e, 0) end
	return e
end
local function addItem()
	W.items[MAP] = {name = "Lower Map Fragment", quality = 1, sell = 0, stack = 40, nocommodity = true}
end
local function waitBuy(X)
	W.waitFor(function() return X.buy.state ~= "searching" and X.buy.state ~= "idle" end, 10)
	return X.buy.state
end

T.scene("stack prices: an item search of a non-commodity stack gives the price of one", function()
	local X = W.start()
	addItem()
	history(X, KEY, 5000)
	W.list(MAP, ONE, 40, 1, "Ann")    -- one auction of 40 at 49s 99c each
	W.list(MAP, 10000, 1, 1, "Bob")   -- a single one at 1g
	W.openAH()
	local live = searchNow(X, KEY)
	T.ok("searched", live ~= nil)
	T.check("not a commodity", live and live.commodity, false)
	T.check("lowest: 49s 99c (not 1s 25c)", live and live.lowest, ONE)
	local o = live and live.offers[1]
	T.check("offer: price of one", o and o.unit, ONE)
	T.check("offer: 40 of it", o and o.qty, 40)
	T.check("offer: buyout as the game gives it", o and o.buyout, ONE)
	T.check("offer: the whole auction", o and o.total, STACK)
	-- the price recorded by the search
	local it = X.Items()[KEY]
	T.check("recorded lowest price: 49s 99c", it and it.cur and it.cur.min, ONE)
	T.check("recorded: 41 listed", it and it.cur and it.cur.qty, 41)
	-- the "% usual" column of the game's item list: the row's buyout as it is
	local row = W.itemResults[KEY] and W.itemResults[KEY][1]
	T.check("game row: buyout of one", row and row.buyoutAmount, ONE)
	local k, price = X.AHPanel.RowItem("item", row)
	T.check("% usual column: the item", k, KEY)
	T.check("% usual column: 49s 99c", price, ONE)
	T.check("% usual: about 100%", W.plain(X.AHPanel.PctText(price, X.Usual(KEY))), "100%")
	-- price alerts / sniper: a max of 10s finds nothing, a max of 60s finds the 40 at 49s 99c
	X.SetWatched(KEY, true)
	X.SetWatchMax(KEY, 1000)
	X.SnipeCheck(KEY, live)
	T.ok("sniper, max 10s: no hit", X.snipe.hits[KEY] == nil)
	X.SetWatchMax(KEY, 6000)
	X.SnipeCheck(KEY, live)
	local h = X.snipe.hits[KEY]
	T.check("sniper, max 60s: hit at 49s 99c", h and h.unit, ONE)
	T.check("sniper, max 60s: 40 of it", h and h.qty, 40)
	T.check("sniper, max 60s: the cost of all", h and h.total, STACK)
end)

T.scene("stack prices: buying a stack - max price, label, gold check, amount sent, cost", function()
	local X = W.start()
	addItem()
	W.list(MAP, ONE, 40, 1, "Ann")
	W.list(MAP, 10000, 1, 1, "Bob")
	W.openAH()
	-- at most 10s each: nothing (49s 99c each is over it)
	X.BuyStart(KEY, 40, 1000, "test", "cheap")
	T.check("max 10s: nothing to buy", waitBuy(X), "none")
	T.ok("max 10s: no plan", X.buy.plan == nil)
	-- the shopping list cost: the whole stack
	X.ShopAdd("Maps", KEY, 40, 6000)
	local cost, n = X.ShopCost(X.ShopEntry("Maps", KEY))
	T.check("shopping list: costs 19g 99s 60c", cost, STACK)
	T.check("shopping list: 40 can be had", n, 40)
	-- at most 60s each: the 40 for 19g 99s 60c
	X.BuyStart(KEY, 40, 6000, "test", "maps")
	T.check("max 60s: ready", waitBuy(X), "ready")
	local plan = X.buy.plan
	T.check("plan: 40", plan and plan.qty, 40)
	T.check("plan: the whole stack costs 19g 99s 60c", plan and plan.total, STACK)
	T.check("plan: the amount sent is the price of one", plan and plan.buyout, ONE)
	T.check("buy button label", (X.BuyButton()), "Buy 40 for " .. X.MoneyPlain(STACK))
	-- not enough gold for the whole stack (but enough for one)
	W.money = 100000
	local peek = X.NextBuyPeek()
	T.check("10g: not enough gold", peek.what, "poor")
	W.money = 300000
	peek = X.NextBuyPeek()
	T.check("30g: buy", peek.what, "buy")
	T.check("next buy label", peek.text, "Buy 40 Lower Map Fragment for " .. X.MoneyPlain(STACK))
	-- the click: PlaceBid gets 49s 99c (as the game's own Buyout button); the stand-in server takes it x 40
	local money = W.money
	T.check("the click buys", press(X.BuyClick), true)
	T.check("PlaceBid called once", #W.bids, 1)
	T.check("PlaceBid amount: 49s 99c", W.bids[1] and W.bids[1].amount, ONE)
	W.waitFor(function() return X.buy.state == "done" end, 10)
	T.check("bought all 40", X.buy.bought, 40)
	T.check("gold taken: 19g 99s 60c", money - W.money, STACK)
	T.check("spent: 19g 99s 60c", X.buy.spent, STACK)
	local line = W.said("bought 40 ")[1] or ""
	T.ok("chat: bought 40 for 19g 99s 60c", line:find("for " .. W.plain(X.Money(STACK)), 1, true) ~= nil, line)
	T.check("the 1g one is left", #W.ah, 1)
end)

T.scene("stack prices: a server that takes one buyout for the stack - the gold that went is recorded", function()
	local X = W.start()
	addItem()
	W.list(MAP, ONE, 40, 1, "Ann")
	W.openAH()
	-- the other possible rule (unverified in the game): the whole stack for the amount sent
	local AH = W.env.C_AuctionHouse
	local real = AH.PlaceBid
	AH.PlaceBid = function(id, amount)
		real(id, amount)
		W.money = W.money + STACK - amount
	end
	X.BuyStart(KEY, 40, 6000, "test", "maps")
	T.check("ready", waitBuy(X), "ready")
	local money = W.money
	press(X.BuyClick)
	W.waitFor(function() return X.buy.state == "done" end, 10)
	T.check("gold taken: 49s 99c", money - W.money, ONE)
	T.check("spent: what really went", X.buy.spent, ONE)
	AH.PlaceBid = real
end)

T.scene("stack prices: the cancel scan sees your own stack at its price of one", function()
	local X = W.start()
	addItem()
	local mine = W.mine(MAP, ONE, 40)   -- yours: 40 at 49s 99c each
	W.list(MAP, 4500, 40, 1, "Cid")     -- someone at 45s each
	W.openAH()
	W.waitFor(function() return X.cancel.state == "idle" or X.cancel.state == "done" end, 20)
	-- searched first: XNAH knows it is not a commodity (the old code then divided your buyout by 40)
	local live = searchNow(X, KEY)
	T.check("searched: not a commodity", live and live.commodity, false)
	X.CancelScan()
	W.waitFor(function() return X.cancel.state == "done" end, 20)
	T.check("one auction of yours", #X.cancel.all, 1)
	local a = X.cancel.all[1]
	T.check("yours: the auction", a and a.auctionID, mine.id)
	T.check("yours: price of one 49s 99c", a and a.unit, ONE)
	T.check("yours: 40 of it", a and a.qty, 40)
	T.check("lowest not yours: 45s", a and a.lowest, 4500)
	T.check("undercut", a and a.undercut, true)
end)
