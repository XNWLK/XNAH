-- XNAH test scenes, part 23: easier buying and selling (round 12) - the Buy button for any page (UI.BuyButton), the best
-- buys (X.BuyIdeas) and the Next buy key, the Sell tab's "Worth posting" view with its ticks and the Post next button,
-- and the undercut check that starts by itself. Every buying / posting / cancelling call must come from a click or a key
-- press, one per press (tools/world-auction.lua + world-routine.lua make those calls throw outside one).

local function history(X, key, usual, days)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5) end
end
local function calls() return table.concat(W.restrictedCalls, ",") end
local function label(btn) return W.plain(W.buttonText(btn) or "") end
local function myAuctions(id)
	local out = {}
	for _, a in ipairs(W.ah) do if a.owner == W.me and (not id or a.itemID == id) then out[#out + 1] = a end end
	return out
end
local function bagCount(id)
	local n = 0
	for _, bag in pairs(W.bags) do for _, s in pairs(bag) do if s.id == id then n = n + s.count end end end
	return n
end
local function tab(X, key)
	X.UI.Open(key)
	W.advance(0.5)
	return X.UI.tabs[key].panel
end

T.scene("buy-sell: the Buy button walks check price, buy, confirm, bought", function()
	local X = W.start()
	history(X, "2589", 100)
	W.list(2589, 50, 10, 2, "Ann")       -- 20 at 50c
	W.list(2589, 90, 10, 1, "Bob")       -- over the max
	W.list(15210, 50000, 1, 1, "Cid", -19)
	local p = tab(X, "buy")
	local btn = X.UI.BuyButton(p, 140, 22)
	btn:SetItem("2589", 4, 60, "test")
	T.check("closed: says so", label(btn), "Open the auction house")
	T.ok("closed: off", btn.disabled == true)
	W.openAH()
	W.advance(0.5)
	T.check("open: Buy", label(btn), "Buy")
	btn:Click()
	T.check("first click: only a search", #W.restrictedCalls, 0)
	T.check("checking", label(btn), "Checking the price ...")
	W.advance(2)
	T.check("price known", label(btn), "Buy 4 for 2s")
	btn:Click()
	T.check("second click: asks the exact price", calls(), "StartCommoditiesPurchase")
	W.advance(1)
	T.check("confirm", label(btn), "Confirm 4 for 2s")
	T.check("nothing bought yet", #W.won, 0)
	btn:Click()
	W.advance(1)
	T.check("bought", label(btn), "Bought 4")
	T.check("got 4", W.won[1] and W.won[1].count, 4)
	T.check("one call per click", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	-- the sword: one click buys one auction
	local sword = X.UI.BuyButton(p, 140, 22)
	sword:SetItem("15210:-19", 1, 60000, "test")
	T.check("another item: Buy", label(sword), "Buy")
	T.check("the first button keeps its result", label(btn), "Bought 4")
	sword:Click()
	W.advance(2)
	T.check("sword price", label(sword), "Buy 1 for 5g")
	T.check("the first button: Buy again (another purchase is only searched)", label(btn), "Buy")
	sword:Click()
	W.advance(1)
	T.check("sword bought", label(sword), "Bought 1")
	T.check("calls", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase,PlaceBid")
	-- qty nil: everything at or under the max (the 16 left at 50c, not the 90c ones)
	local all = X.UI.BuyButton(p, 140, 22)
	all:SetItem("2589", nil, 60, "test")
	all:Click()
	W.advance(2)
	T.check("all under the max", label(all), "Buy 16 for 8s")
	-- a purchase going on elsewhere: the other buttons wait
	all:Click()
	W.advance(1)
	T.check("asking", label(all), "Confirm 16 for 8s")
	btn:SetItem("2589", 4, 60, "other")
	T.check("another button waits", label(btn), "Wait: another purchase")
	T.ok("and is off", btn.disabled == true)
	all:Click()
	W.advance(1)
	T.check("bought all", label(all), "Bought 16")
	T.check("the 90c ones left alone", W.ah[#W.ah] and W.ah[#W.ah].count, 10)
	-- nothing at the max any more: says so, a click checks again (a search, nothing restricted)
	local none = X.UI.BuyButton(p, 140, 22)
	none:SetItem("2589", 5, 60, "test2")
	none:Click()
	W.advance(2)
	T.check("none at the max", label(none), "None at your price")
	local n = #W.restrictedCalls
	none:Click()
	W.advance(2)
	T.check("checking again is not restricted", #W.restrictedCalls, n)
	-- no max given: XNAH's limit (a little over the usual price)
	local auto = X.UI.BuyButton(p, 140, 22)
	auto:SetItem("2589")
	T.check("limit: 110% of the usual price", auto.max, math.floor(X.Usual("2589") * 1.1))
	T.check("no quantity: as many as are at or under it", auto.qty, nil)
	-- what you see is what you click: a label drawn before the state changed does nothing
	local stale = X.UI.BuyButton(p, 140, 22)
	stale:SetItem("15210:-19", 1, 60000, "stale")
	stale.shownText = "Buy 1 for 1c"
	stale:Click()
	T.check("a stale label only redraws", label(stale), "Buy")
	T.check("and started nothing", X.buy.tag == "stale", false)
	-- closed again: all say so
	W.closeAH()
	W.advance(0.5)
	X.UI.UpdateBuyButtons()
	T.check("closed again", label(none), "Open the auction house")
	T.check("closed: a buy step does nothing", X.BuyClick(), false)
end)

T.scene("buy-sell: best buys and the Next buy key", function()
	local X = W.start()
	-- a shopping list item under its max, a watched item under its max, and a deal (far under its usual price)
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "14047", 20000)
	X.ShopAdd("Mats", "2589", 10, 70)
	X.SetWatched("2592", true)
	X.SetWatchMax("2592", 40)
	W.list(2589, 50, 10, 2, "Ann")
	W.list(2592, 30, 5, 1, "Bob")
	W.list(14047, 8000, 1, 1, "Cid")
	X.Record("2589", X.Now(), 50, 50, 20, 2)
	X.Record("2592", X.Now(), 30, 30, 5, 1)
	X.Record("14047", X.Now(), 8000, 8000, 1, 1)
	X.SetIgnored("4306", true)
	W.bindings.XNAH_NEXTBUY = "B"
	X.BuyIdeas(10)
	W.advance(3) -- the deals pass runs in slices
	local ideas = X.BuyIdeas(10)
	local order = {}
	for _, r in ipairs(ideas) do order[#order + 1] = r.kind .. " " .. r.key end
	T.check("best first: list, watched, then the deal", table.concat(order, ", "), "list 2589, watch 2592, deal 14047")
	T.check("list: 10 to buy at most 70c", ideas[1] and (ideas[1].qty .. " " .. ideas[1].max), "10 70")
	T.check("deal: profit after the cut from today's price", ideas[3] and ideas[3].each, X.AfterCut(ideas[3].target) - 8000)
	T.ok("deal: max keeps half the profit", ideas[3] and ideas[3].max == math.floor(8000 + ideas[3].each / 2))
	-- grey items and items you never want suggested are left out
	W.items[6266] = {name = "Grey Vest", quality = 0, sell = 90, stack = 1}
	history(X, "6266", 20000)
	X.Record("6266", X.Now(), 5000, 5000, 1, 1)
	X.Items()["6266"].q = 0
	history(X, "4306", 20000)
	X.Record("4306", X.Now(), 5000, 5000, 1, 1)
	X.Fire("XNAH_PRICES")
	W.advance(65)
	for _, r in ipairs(X.BuyIdeas(10)) do
		T.ok("not grey, not ignored: " .. r.key, r.key ~= "6266" and r.key ~= "4306")
	end
	-- the key with the auction house closed: a line in chat, nothing else
	W.pressKey("XNAH_NextBuy")
	T.ok("closed: says so", #W.said("Open the auction house first") == 1, W.lastSaid())
	W.openAH()
	W.advance(0.5)
	local p = tab(X, "buy")
	T.ok("the Buy tab opens on the best buys", p.bestView:IsVisible())
	T.ok("shows the key", W.screen(p):find("Your key: B", 1, true) ~= nil, W.screen(p))
	T.check("next press: check the list item", X.NextBuyPeek().text, "Check the price: 10 Linen Cloth (list Mats)")
	T.ok("the big button says it", W.findButton("Check the price: 10 Linen Cloth", p) ~= nil, W.screen(p))
	-- press 1: a search only
	W.pressKey("XNAH_NextBuy")
	T.check("press 1: nothing restricted", #W.restrictedCalls, 0)
	W.advance(2)
	T.check("next press: buy", X.NextBuyPeek().text, "Buy 10 Linen Cloth for about 5s")
	W.pressKey("XNAH_NextBuy")
	T.check("press 2: one call", calls(), "StartCommoditiesPurchase")
	W.pressKey("XNAH_NextBuy")
	T.check("a press while it waits does nothing", calls(), "StartCommoditiesPurchase")
	W.advance(1)
	T.check("next press: confirm", X.NextBuyPeek().text, "Confirm: buy 10 Linen Cloth for 5s")
	W.pressKey("XNAH_NextBuy")
	W.advance(1)
	T.check("press 3: bought", W.won[1] and W.won[1].count, 10)
	T.check("counted on the list", X.ShopEntry("Mats", "2589").bought, 10)
	T.check("calls", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	-- then the next one: the watched Wool
	W.advance(3)
	T.check("next: the watched item", X.NextBuyPeek().text, "Check the price: 20 Wool Cloth (watched)")
	-- skip it with the button
	W.click("Skip this buy", p)
	T.check("skipped: the deal is next", X.NextBuyPeek().idea and X.NextBuyPeek().idea.key, "14047")
	-- the big button does the same as the key
	W.click("Check the price: 1 Runecloth", p)
	W.advance(2)
	T.ok("button: buy the deal", W.findButton("Buy 1 Runecloth for about 80s", p) ~= nil, W.screen(p))
	-- the row's own Buy button shows the same purchase
	T.ok("the row button follows", W.findButton("Buy 1 for 80s", p.bestList) ~= nil, W.screen(p.bestList))
	W.click("Buy 1 Runecloth for about 80s", p)
	W.advance(1)
	W.click("Confirm: buy 1 Runecloth for 80s", p)
	W.advance(1)
	T.check("deal bought", W.won[2] and W.won[2].id, 14047)
	T.check("calls", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase,StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	W.advance(3)
	T.check("nothing left (the skipped one waits 10 minutes)", X.NextBuyPeek().what, "none")
	-- a minute of timers and events: nothing restricted
	W.advance(60)
	T.check("nothing restricted outside presses", #W.restrictedCalls, 4)
	X.BuyStart("2592", 5, 40, "test", "outside")
	W.advance(2)
	T.check("ready", X.buy.state, "ready")
	T.check("the key function outside a press is refused by the game", (pcall(W.env.XNAH_NextBuy)), false)
end)

-- the Worth posting row of an item (its frame in the list)
local function worthRow(p, key)
	for _, row in ipairs(p.worthList.rows) do
		if row:IsVisible() and row.item and row.item.kind == "post" and row.item.key == key then return row end
	end
end

T.scene("buy-sell: Worth posting - ticked by default, undercut first, Post next", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "4306", 100)               -- Silk: a vendor pays 150c each - more than the auction house
	W.mine(2589, 95, 10)                  -- undercut by Ann at 90c
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.list(4306, 100, 20, 1, "Bob")
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.putBag(0, 3, 4306, 5)
	W.putBag(0, 4, 2841, 3)               -- Bronze: no price known
	W.bindings.XNAH_NEXT = "F"
	W.openAH()
	local p = tab(X, "sell")
	T.check("opens on Worth posting", p.view, "worth")
	T.check("a round starts by itself (asking and searching only)", X.routine.state, "on")
	W.waitFor(function() return X.routine.phase == "ready" end, 60)
	W.advance(1)
	local rows = p.worthRows
	T.check("first row: the undercut auction", rows[1] and (rows[1].kind .. " " .. rows[1].key), "cancel 2589")
	local function ticked(key) for _, r in ipairs(rows) do if r.kind == "post" and r.key == key then return r.ticked end end end
	T.check("Linen ticked", ticked("2589"), true)
	T.check("Wool ticked", ticked("2592"), true)
	T.check("Silk not ticked", ticked("4306"), false)
	T.check("Bronze not ticked", ticked("2841"), false)
	local screen = W.screen(p)
	T.ok("says why Silk is not", screen:find("a vendor pays more", 1, true) ~= nil, screen)
	T.ok("says why Bronze is not", screen:find("no price known yet", 1, true) ~= nil, screen)
	T.ok("shows the key", screen:find("Your key: F", 1, true) ~= nil)
	T.ok("the big button: the cancel first", W.findButton("Next: cancel Linen Cloth x10 (undercut by 5c)", p) ~= nil, screen)
	T.check("nothing restricted yet", #W.restrictedCalls, 0)
	-- untick Wool: kept, remembered
	local wool = worthRow(p, "2592")
	T.ok("Wool has a tick box", wool and wool.check and wool.check:GetChecked())
	wool.check:Click()
	W.advance(1)
	T.check("unticked: remembered", X.db.sellTick["2592"], false)
	T.ok("shows kept", W.screen(p.worthList):find("kept", 1, true) ~= nil, W.screen(p.worthList))
	T.check("no restricted call from a tick", #W.restrictedCalls, 0)
	-- Post next: the cancel, then Linen; Wool, Silk and Bronze stay
	W.click("Next: cancel Linen Cloth", p)
	W.advance(1)
	T.check("press 1: cancelled", calls(), "CancelAuction")
	W.advance(1)
	T.ok("the big button: post Linen", W.findButton("Next: post 20 x Linen Cloth at 89c each", p) ~= nil, W.screen(p))
	W.click("Next: post 20 x Linen Cloth", p)
	W.advance(2)
	T.check("press 2: posted", calls(), "CancelAuction,PostCommodity")
	T.check("Linen on the auction house", #myAuctions(2589), 1)
	T.ok("the big button: done", W.findButton("Done: 1 cancelled, 1 posted", p) ~= nil, W.screen(p))
	T.check("Wool kept", bagCount(2592), 10)
	T.check("Silk kept", bagCount(4306), 5)
	T.check("Bronze kept", bagCount(2841), 3)
	-- tick Silk anyway: it is posted on the next press
	local silk = worthRow(p, "4306")
	silk.check:Click()
	W.advance(2)
	T.check("ticked by you: remembered", X.db.sellTick["4306"], true)
	T.ok("the big button: post Silk", W.findButton("Next: post 5 x Silk Cloth", p) ~= nil, W.screen(p))
	-- a row: its price and why; Price rules opens Post by hand with it
	worthRow(p, "4306"):Click() -- (the rows moved: Silk is ticked now)
	W.advance(0.5)
	T.ok("why it was not ticked", W.screen(p):find("Not worth posting: a vendor pays more", 1, true) ~= nil, W.screen(p))
	W.click("Price rules for this item", p)
	W.advance(1)
	T.check("Post by hand", p.view, "sell")
	T.check("with Silk", p.selKey, "4306")
	T.check("still only two restricted calls", #W.restrictedCalls, 2)
end)

T.scene("buy-sell: the undercut check starts by itself when the auction house opens", function()
	local X = W.start()
	W.mine(2589, 95, 10)
	W.list(2589, 90, 20, 1, "Ann")
	W.openAH()
	W.advance(1)
	T.check("not at once", X.cancel.state, "idle")
	W.advance(1.5)
	T.ok("then by itself", X.cancel.state == "asking" or X.cancel.state == "checking", X.cancel.state)
	W.waitFor(function() return X.cancel.state == "done" end, 20)
	T.check("found the undercut auction", #X.cancel.rows, 1)
	T.check("nothing restricted", #W.restrictedCalls, 0)
	local at = X.cancel.at
	-- closed and opened again within 5 minutes: not again
	W.closeAH()
	W.advance(60)
	W.openAH()
	W.advance(5)
	T.check("not again within 5 minutes", X.cancel.at, at)
	-- later: again
	W.closeAH()
	W.advance(300)
	W.openAH()
	W.advance(3)
	W.waitFor(function() return X.cancel.state == "done" end, 20)
	T.ok("again after 5 minutes", X.cancel.at ~= at)
	-- a full scan running: the check waits for it
	at = X.cancel.at
	W.closeAH()
	W.advance(400)
	W.replicaDelay = 10 -- the server takes its time with the full scan
	W.openAH()
	T.ok("full scan started", X.FullScan(true))
	W.advance(5)
	T.check("no check while the scan runs", X.cancel.at, at)
	T.ok("the scan still runs", X.scan.state ~= "idle", X.scan.state)
	W.waitFor(function() return X.scan.state == "idle" end, 300)
	W.advance(2)
	W.waitFor(function() return X.cancel.state == "done" end, 20)
	T.ok("checked right after the scan", X.cancel.at ~= at)
	T.check("never anything restricted", #W.restrictedCalls, 0)
end)
