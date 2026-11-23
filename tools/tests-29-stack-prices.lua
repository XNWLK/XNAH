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
	-- at most 60s each: the 40 for 19g 99s 60c
	X.BuyStart(KEY, 40, 6000, "test", "maps")
	T.check("max 60s: ready", waitBuy(X), "ready")
	local plan = X.buy.plan
	T.check("plan: 40", plan and plan.qty, 40)
	T.check("plan: the whole stack costs 19g 99s 60c", plan and plan.total, STACK)
	T.check("plan: the amount sent is the price of one", plan and plan.buyout, ONE)
	T.check("buy button label", (X.BuyButton()), "Buy 40 for " .. X.MoneyPlain(STACK))
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

-- [[ the purchase engine ]] (moved here from the removed Buy / Sell tab scenes): X.BuyStart, then ONE step per click of
-- ours (X.BuyClick): commodities search, ask the exact price, confirm; other items one auction per click
local function calls() return table.concat(W.restrictedCalls, ",") end

T.scene("stack prices: the purchase engine - commodities, an auction, all under a max, one call per click", function()
	local X = W.start()
	history(X, "2589", 100)
	W.list(2589, 50, 10, 2, "Ann")       -- 20 at 50c
	W.list(2589, 90, 10, 1, "Bob")       -- over the max
	W.list(15210, 50000, 1, 1, "Cid", -19)
	X.BuyStart("2589", 4, 60, "test", "a")
	T.check("closed: nothing to buy", X.buy.state, "none")
	T.check("closed: a buy step does nothing", X.BuyClick(), false)
	W.openAH()
	W.advance(0.5)
	X.BuyStart("2589", 4, 60, "test", "a")
	T.check("searching first (nothing restricted)", #W.restrictedCalls, 0)
	T.check("found", waitBuy(X), "ready")
	T.check("label: buy 4", (X.BuyButton()), "Buy 4 for about " .. X.MoneyPlain(200))
	T.check("first click: asks the exact price", press(X.BuyClick), true)
	T.check("one call", calls(), "StartCommoditiesPurchase")
	W.advance(1)
	T.check("exact price known", X.buy.state, "confirm")
	T.check("label: confirm", (X.BuyButton()), "Confirm 4 for " .. X.MoneyPlain(200))
	T.check("nothing bought yet", #W.won, 0)
	press(X.BuyClick)
	W.waitFor(function() return X.buy.state == "done" end, 10)
	T.check("got 4", W.won[1] and W.won[1].count, 4)
	T.check("bought 4", X.buy.bought, 4)
	T.check("one call per click", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	-- an item that is not a commodity: one click buys one auction
	X.BuyStart("15210:-19", 1, 60000, "test", "sword")
	T.check("sword: ready", waitBuy(X), "ready")
	T.check("sword: label", (X.BuyButton()), "Buy for " .. X.MoneyPlain(50000))
	press(X.BuyClick)
	W.waitFor(function() return X.buy.state == "done" end, 10)
	T.check("sword bought", X.buy.bought, 1)
	T.check("calls", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase,PlaceBid")
	-- need nil: everything at or under the max (the 16 left at 50c, not the 90c ones)
	X.BuyStart("2589", nil, 60, "test", "all")
	T.check("all: ready", waitBuy(X), "ready")
	T.check("all under the max", X.buy.plan and X.buy.plan.qty, 16)
	press(X.BuyClick)
	W.advance(1)
	press(X.BuyClick)
	W.waitFor(function() return X.buy.state == "done" or X.buy.state == "none" end, 10)
	T.check("bought all 16", X.buy.bought, 16)
	T.check("the 90c ones left alone", W.ah[#W.ah] and W.ah[#W.ah].count, 10)
	-- nothing at the max any more
	X.BuyStart("2589", 5, 60, "test", "none")
	T.check("none at the max", waitBuy(X), "none")
	-- the most to pay when you did not say: a little over the usual price
	T.check("limit: 110% of the usual price", X.BuyLimit("2589"), math.floor(X.Usual("2589") * 1.1))
	T.check("cheapest now (not yours): 90c", (X.PriceNow("2589")), 90)
	-- a purchase that was started can be stopped (not restricted)
	X.BuyStart("2589", 2, 100, "test", "stop")
	waitBuy(X)
	press(X.BuyClick)
	W.advance(1)
	T.check("asked", X.buy.state, "confirm")
	local n = #W.restrictedCalls
	X.BuyCancel()
	T.check("cancel: not restricted", #W.restrictedCalls, n)
	waitBuy(X)
	T.check("cancel: searched again", X.buy.state, "ready")
	X.BuyClear()
	T.check("cleared", X.buy.state, "idle")
	W.closeAH()
	W.advance(0.5)
	T.check("closed again: a buy step does nothing", X.BuyClick(), false)
end)

T.scene("stack prices: nothing restricted is called outside a click", function()
	local X = W.start()
	history(X, "2589", 100)
	W.list(2589, 50, 20, 3, "Ann")
	W.openAH()
	X.BuyStart("2589", 10, 70, "test", "wait")
	W.advance(60)
	T.check("the purchase is ready but waits for a click", X.buy.state, "ready")
	T.check("no restricted call in a minute of timers and events", #W.restrictedCalls, 0)
	-- the test world refuses those calls outside a click (so the other scenes prove XNAH made them in clicks)
	T.check("buying outside a click is refused", (pcall(X.BuyClick)), false)
	T.check("nothing was bought", #W.won, 0)
	W.closeAH()
	W.advance(5)
end)
