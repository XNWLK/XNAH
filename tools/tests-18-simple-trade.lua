-- XNAH test scenes, part 18: the Buy and Sell pages of the simple window (SimpleTrade.lua): entries appear, the big
-- button's label follows the clicks, one buying / posting / cancelling call per click, nothing of that outside a click
-- (tools/world-auction.lua makes those calls throw outside one), the auction house closed handled.

local function history(X, key, usual, days)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5) end
end
local function myAuctions(id)
	local out = {}
	for _, a in ipairs(W.ah) do if a.owner == W.me and (not id or a.itemID == id) then out[#out + 1] = a end end
	return out
end
local function calls() return table.concat(W.restrictedCalls, ",") end
local function ids(S)
	local out = {}
	for _, e in ipairs(S.list.items or {}) do out[#out + 1] = e.id end
	return table.concat(out, ", ")
end
-- picks the entry with this id in the left list; returns true when found
local function pick(S, id)
	for i, e in ipairs(S.list.items or {}) do
		if e.id == id then
			S.list.rows[i - (S.list.offset or 0)]:Click()
			return true
		end
	end
	return false
end
local function label(S) return S.detail.button:IsShown() and S.detail.button:GetText() or "(no button)" end
local function press(S)
	S.detail.button:Click()
	W.advance(1.5)
end

T.scene("simple trade: the Buy page buys in clicks that say what they do", function()
	local X = W.start()
	local S = X.Simple
	-- a buy-side strategy row (stand-in for the strategies' last results): Linen usually 1g, listed at 40s now
	history(X, "2589", 10000)
	X.Record("2589", X.Now(), 4000, 4100, 20, 1)
	W.list(2589, 4000, 20, 1, "Ann")
	local realRows = X.StrategyRows
	X.StrategyRows = function(k)
		if k == "dip" then return {{key = "2589", action = "Buy and relist", now = 4000, target = 10000, profit = 5500, qty = 4, risk = "Low"}} end
		return nil
	end
	-- a deal: the sword usually about 3g 67s, listed at 2g
	history(X, "15210:-19", 40000)
	X.Record("15210:-19", X.Now(), 20000, 20000, 1, 1)
	W.list(15210, 20000, 1, 1, "Cid", -19)
	S.Open("buy")
	W.advance(3)
	T.check("entries: the strategy buy, then the deal", ids(S), "buy:2589, buy:15210:-19")
	local e = S.list.items[1]
	T.check("title", e.title, "Buy 4 Linen Cloth")
	T.check("sub", W.plain(e.sub), "you make +2g 20s")
	T.check("profit", e.profit, 22000)
	T.check("sentence", S.detail.sentence:GetText(), "Buy all 4 now and post them again at 1g each.")
	T.ok("why", (S.detail.why:GetText() or ""):find("usually sells for 1g", 1, true) ~= nil, S.detail.why:GetText())
	T.check("closed: the button says so", label(S), "Open the auction house first")
	T.ok("closed: the button is off", S.detail.button.disabled == true)
	press(S)
	T.check("closed: nothing happens", #W.searches, 0)
	-- open: search, buy, confirm, bought
	W.openAH()
	W.advance(1)
	T.check("open: first the price", label(S), "Check the price")
	press(S)
	T.check("searched", #W.searches >= 1, true)
	T.check("no restricted call for the search", #W.restrictedCalls, 0)
	T.check("then: buy", label(S), "Buy 4 for about 1g 60s")
	press(S)
	T.check("one call: start", calls(), "StartCommoditiesPurchase")
	T.check("then: confirm", label(S), "Confirm: buy 4 for 1g 60s")
	T.check("nothing bought by the first click", #W.won, 0)
	press(S)
	T.check("one call: confirm", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	T.check("bought 4", W.won[1] and W.won[1].count, 4)
	T.check("then: bought", label(S), "Bought 4 for 1g 60s")
	T.ok("bought: the button is off", S.detail.button.disabled == true)
	-- the sword: one click buys it
	T.ok("the deal is listed", pick(S, "buy:15210:-19"))
	T.check("deal: first the price", label(S), "Check the price")
	press(S)
	T.check("deal: buy it", label(S), "Buy it for 2g")
	press(S)
	T.check("one call: the bid", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase,PlaceBid")
	T.check("sword bought", W.won[2] and W.won[2].id, 15210)
	T.check("deal: bought", label(S), "Bought 1 for 2g")
	X.StrategyRows = realRows
end)

T.scene("simple trade: shopping list and watch list on the Buy page", function()
	local X = W.start()
	local S = X.Simple
	X.ShopAdd("Mats", "2592", 10, 70)
	X.SetWatchMax("4306", 9000)
	X.Record("2592", X.Now(), 60, 60, 20, 1)
	X.Record("4306", X.Now(), 8000, 8500, 20, 1)
	W.list(2592, 60, 20, 1, "Bob")
	W.list(4306, 8000, 5, 1, "Ann")
	W.list(4306, 9500, 20, 1, "Ann")
	W.openAH()
	S.Open("buy")
	W.advance(3)
	T.check("wishes first", ids(S), "shop:Mats:2592, watch:4306")
	T.check("shop title", S.list.items[1].title, "Buy 10 Wool Cloth")
	press(S)
	T.check("shop: buy", label(S), "Buy 10 for about 6s")
	press(S)
	press(S)
	T.check("counted on the list", X.ShopEntry("Mats", "2592").bought, 10)
	W.advance(1)
	T.ok("watch entry still there", pick(S, "watch:4306"))
	press(S)
	T.check("watch: only the ones under the max", label(S), "Buy 5 for about 4g")
	press(S)
	press(S)
	T.check("bought 5 silk", W.won[2] and W.won[2].count, 5)
	T.check("calls", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase,StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
end)

T.scene("simple trade: the Sell page cancels, posts, confirms a warning, and points to vendors", function()
	local X = W.start()
	local S = X.Simple
	W.items[3300] = {name = "Rabbit's Foot", quality = 0, sell = 37, stack = 20}
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "2770", 6)
	W.mine(2589, 95, 10)                 -- undercut by Ann at 90c
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.list(2770, 6, 20, 1, "Bob")
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.putBag(0, 3, 2770, 5)              -- a vendor pays 25c; posting would bring less after the deposit
	W.putBag(0, 4, 3300, 2)              -- junk
	S.Open("sell")
	W.advance(1)
	T.check("closed: posts shown, but the button says so", label(S), "Open the auction house first")
	W.openAH()
	W.advance(1)
	S.Refresh()
	W.waitFor(function() return X.cancel.state == "done" end, 20)
	W.advance(5)
	T.check("the list: cancel first, then posts, vendor, junk", ids(S), "cancel:" .. myAuctions(2589)[1].id .. ", post:2589, post:2592, vendor:2770, junk, check")
	T.check("no restricted call while it checked and searched", #W.restrictedCalls, 0)
	for _, e in ipairs(S.list.items) do T.ok("profit for " .. e.id, type(e.profit) == "number", e.profit) end
	-- cancel
	T.check("cancel title", S.list.items[1].title, "Cancel Linen Cloth x10")
	T.ok("pick the cancel", pick(S, S.list.items[1].id))
	T.check("cancel button", label(S), "Cancel this auction")
	S.detail.button:Click()
	T.check("one call: cancel", calls(), "CancelAuction")
	S.Refresh()
	T.check("then: cancelling", label(S), "Cancelling ...")
	S.detail.button:Click()
	T.check("a second click does nothing", calls(), "CancelAuction")
	W.advance(1.5)
	T.check("cancelled", #myAuctions(2589), 0)
	-- post Linen
	T.ok("Linen to post", pick(S, "post:2589"))
	T.check("post title", S.list.items[1].title, "Sell 20 Linen Cloth")
	T.check("post sentence", S.detail.sentence:GetText(), "Post all 20 at 89c each.")
	T.ok("post why", (S.detail.why:GetText() or ""):find("cheapest other seller asks 90c", 1, true) ~= nil, S.detail.why:GetText())
	T.check("post button", label(S), "Post 20 at 89c each")
	press(S)
	T.check("one call: post", calls(), "CancelAuction,PostCommodity")
	T.check("Linen posted", #myAuctions(2589), 1)
	-- Wool with a price warning: a second click
	T.ok("Wool to post", pick(S, "post:2592"))
	W.warnNextPost = true
	press(S)
	T.check("not posted yet", #myAuctions(2592), 0)
	T.check("then: confirm", label(S), "Confirm: post anyway")
	T.check("and Don't post", S.detail.button2:GetText(), "Don't post")
	press(S)
	T.check("calls", calls(), "CancelAuction,PostCommodity,PostCommodity,ConfirmPostCommodity")
	T.check("Wool posted", #myAuctions(2592), 1)
	-- the vendor entries have no button
	T.ok("vendor entry", pick(S, "vendor:2770"))
	T.ok("vendor: no button", not S.detail.button:IsShown())
	T.ok("vendor sentence", (S.detail.sentence:GetText() or ""):find("vendor", 1, true) ~= nil)
	T.ok("junk entry", pick(S, "junk"))
	T.check("junk value", S.detail.entry and S.detail.entry.profit, 74)
	-- Check your auctions: the cancel scan on a click
	T.ok("check entry", pick(S, "check"))
	T.check("check button", label(S), "Check your auctions")
	local before = #W.restrictedCalls
	S.detail.button:Click()
	T.ok("checking", X.cancel.state == "asking" or X.cancel.state == "checking", X.cancel.state)
	S.Refresh()
	T.check("check: busy", label(S), "Checking ...")
	W.waitFor(function() return X.cancel.state == "done" end, 20)
	T.check("checking is not restricted", #W.restrictedCalls, before)
	-- for the To do page
	local list = S.SellEntries(2)
	T.check("SellEntries(limit)", #list, 2)
end)

T.scene("simple trade: nothing restricted outside a click; Find shows Post or Buy", function()
	local X = W.start()
	local S = X.Simple
	history(X, "2589", 10000)
	history(X, "2592", 60)
	X.Record("2589", X.Now(), 4000, 4100, 20, 1)
	W.list(2589, 4000, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.mine(2592, 80, 10)
	W.putBag(0, 1, 2592, 10)
	X.ShopAdd("Mats", "2589", 5, 5000)
	W.openAH()
	W.advance(1)
	-- XNAH searches by itself only while you look at the To do or the Sell page
	S.SellEntries(10)
	W.advance(5)
	T.check("window closed: no check of your auctions", X.cancel.state, "idle")
	T.check("window closed: no search", #W.searches, 0)
	S.Open("buy")
	W.advance(2)
	S.SellEntries(10)
	W.advance(5)
	T.check("on the Buy page: no check of your auctions", X.cancel.state, "idle")
	T.check("on the Buy page: no search", #W.searches, 0)
	S.Select("sell")
	W.advance(0.2)
	T.ok("on the Sell page: your auctions are checked", X.cancel.state ~= "idle", X.cancel.state)
	W.advance(5)
	T.ok("and the bag items searched", #W.searches >= 1, #W.searches)
	S.Select("buy")
	for _ = 1, 4 do
		S.BuyEntries(10)
		S.SellEntries(10)
		W.advance(30)
	end
	T.check("two minutes of pages, timers and events: no restricted call", #W.restrictedCalls, 0)
	T.check("a buy outside a click is refused by the game", (pcall(function() X.BuyStart("2589", 5, 5000) W.advance(2) X.BuyClick() end)), false)
	T.check("nothing bought", #W.won, 0)
	X.BuyClear()
	local refused = #W.restrictedCalls -- the refused call above is counted
	-- Find: something in your bags -> Post; something on the auction house -> Buy
	X.ShowItem("2592")
	W.advance(1)
	T.check("Find: the item", S.detail.entry and S.detail.entry.id, "item:2592")
	T.ok("Find: a Post button", label(S):find("^Post 10 at"), label(S))
	X.ShowItem("2589")
	W.advance(1)
	T.check("Find: a Buy button", label(S), "Check the price")
	press(S)
	T.check("Find: buy a stack after the search", label(S), "Buy 20 for about 8g")
	T.check("Find: still nothing restricted", #W.restrictedCalls, refused)
	-- the auction house closes: every button says so
	W.closeAH()
	W.advance(1)
	S.Select("buy")
	W.advance(1)
	for _, e in ipairs(S.BuyEntries(10)) do T.check("closed: " .. e.id, e.button and e.button.label, "Open the auction house first") end
	for _, e in ipairs(S.SellEntries(10)) do
		if e.button then T.check("closed: " .. e.id, e.button.label, "Open the auction house first") end
	end
end)
