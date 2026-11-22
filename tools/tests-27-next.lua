-- XNAH test scenes, part 27 (v0.8): the Next step key (Next.lua) - one key for everything: at the profession window it
-- crafts the queue, at a mailbox it takes the next auction house mail (only on a press), at the auction house it
-- finishes a purchase going on, then cancels and posts (the routine), then buys: shopping lists and the crafting queue's
-- materials first. One restricted call per press at most, never from a timer; a button whose label is old only shows the
-- new one. And Home's checklist of the day (Home.lua X.HomeToday, UIHome.lua).

local function history(X, key, usual, days)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5) end
end
local function calls() return table.concat(W.pressCalls(), ",") end
local function bagCount(id)
	local n = 0
	for b = 0, 5 do for _, s in pairs(W.bags[b] or {}) do if s.id == id then n = n + s.count end end end
	return n
end
local function myAuctions(id)
	local out = {}
	for _, a in ipairs(W.ah) do if a.owner == W.me and (not id or a.itemID == id) then out[#out + 1] = a end end
	return out
end
local function peek(X) return X.DoNextPeek() end
local function routineReady(X)
	return W.waitFor(function() return X.routine.phase == "ready" and X.routine.cur == nil and X.routine.waiting <= 0 end, 60)
end
-- the bronze recipe (one craft: 1 Copper Bar + 1 Tin Bar -> 2 Bronze Bars), read at the profession window
local function bronze(X)
	W.recipes = {[2] = {name = "Smelt Bronze", out = 2841, qMin = 2, qMax = 2, reagents = {{2840, 1}, {3576, 1}}, learned = true, prof = "Mining"}}
	W.openProfession("Mining")
	W.advance(3)
	W.closeProfession()
end
local function stepOf(X, id)
	for _, s in ipairs(X.HomeToday()) do if s.id == id then return s end end
end
local function fresh(X)
	X.HomeForget()
	W.advance(1.1)
	X.HomeTodo()
	W.advance(1)
	return X.HomeToday()
end

T.scene("next: at the auction house - cancel, post, then your list and the queue's materials", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "2996", 150)
	history(X, "4306", 200)
	history(X, "2840", 30)
	history(X, "3576", 40)
	history(X, "2841", 100)
	bronze(X)
	W.mine(2589, 95, 10)                   -- undercut by Ann at 90c
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.list(4306, 150, 10, 1, "Cid")        -- Silk: on the shopping list, max 2s
	W.list(3576, 40, 10, 1, "Dee")         -- Tin Bar: the queue needs 3
	W.list(2840, 30, 10, 1, "Dee")
	W.list(2841, 100, 10, 1, "Dee")
	W.list(2996, 140, 20, 1, "Bob")
	X.Record("4306", X.Now(), 150, 150, 10, 1)
	X.Record("3576", X.Now(), 40, 40, 10, 1)
	X.Record("2840", X.Now(), 30, 30, 10, 1)
	X.Record("2841", X.Now(), 100, 100, 10, 1)
	W.putBag(0, 1, 2592, 10)               -- Wool: worth posting
	W.putBag(0, 2, 2840, 3)                -- Copper Bars: the queue uses them - kept
	W.bagsChanged()
	X.ShopAdd("Mats", "4306", 5, 200)
	X.QueueSet(2, "craft", 3)              -- 3 bronze crafts: 3 Copper Bars (in the bags), 3 Tin Bars (to buy)
	T.check("the queue keeps its Copper Bars", X.QueueKeep("2840"), 3)
	local qb = X.QueueBuys()
	T.check("queue: one material to buy", #qb, 1)
	T.check("queue: 3 Tin Bars", qb[1] and (qb[1].key .. " x" .. qb[1].buy), "3576 x3")
	-- one craft makes 2 bars worth 95c after the cut, its materials cost 70c: 120c profit a craft, half of it may go to
	-- the Tin Bar on top of the 40c XNAH counted
	T.check("queue: max price keeps half the profit", qb[1] and qb[1].max, 100)
	T.check("away from everything", peek(X).what, "away")
	W.openAH()
	W.advance(3)
	local p = peek(X)
	T.check("first: check auctions and bags", p.what, "start")
	T.check("its part", p.area, "cancel")
	W.pressKey()
	T.check("press 1: nothing restricted", calls(), "")
	T.ok("prepared", routineReady(X))
	T.check("press 2 will cancel", peek(X).text, "Cancel Linen Cloth x10 (undercut by 5c)")
	W.pressKey()
	T.check("press 2: one cancel", calls(), "CancelAuction")
	W.pressKey()
	T.check("a press before the answer does nothing", calls(), "CancelAuction")
	W.advance(1)
	T.check("cancelled", #myAuctions(2589), 0)
	p = peek(X)
	T.check("press 3 will post", p.text, "Post 10 Wool Cloth at 59c each")
	T.check("its part", p.area, "post")
	W.pressKey()
	W.advance(1)
	T.check("press 3: one post", calls(), "CancelAuction,PostCommodity")
	T.check("Copper Bars kept for the queue (no step)", (function()
		for _, s in ipairs(X.routine.steps) do if s.key == "2840" then return false end end
		return true
	end)(), true)
	T.check("still in the bags", bagCount(2840), 3)
	-- then buying: the shopping list first
	W.advance(1)
	local ideas = X.BuyIdeas(10)
	local order = {}
	for _, r in ipairs(ideas) do order[#order + 1] = r.kind .. " " .. r.key end
	T.ok("buy ideas: the list, then the queue", table.concat(order, ", "):find("^list 4306, queue 3576") ~= nil, table.concat(order, ", "))
	p = peek(X)
	T.check("press 4 checks the list item", p.text, "Check the price: 5 Silk Cloth (list Mats)")
	T.check("its part", p.area, "buy")
	W.pressKey()
	T.check("press 4: a search only", calls(), "CancelAuction,PostCommodity")
	W.advance(2)
	T.check("press 5 buys", peek(X).text, "Buy 5 Silk Cloth for about 7s 50c")
	W.pressKey()
	T.check("press 5: one call", calls(), "CancelAuction,PostCommodity,StartCommoditiesPurchase")
	W.advance(1)
	T.check("press 6 confirms", peek(X).text, "Confirm: buy 5 Silk Cloth for 7s 50c")
	-- something new to post comes in now: the purchase going on is finished first
	W.putBag(0, 3, 2996, 5)
	W.fire("BAG_UPDATE_DELAYED")
	W.advance(3)
	T.check("the purchase first", peek(X).text, "Confirm: buy 5 Silk Cloth for 7s 50c")
	W.pressKey()
	W.advance(1)
	T.check("bought", W.won[1] and (W.won[1].id .. " x" .. W.won[1].count), "4306 x5")
	T.check("counted on the list", X.ShopEntry("Mats", "4306").bought, 5)
	T.ok("then the new post", peek(X).text:find("^Post 5 Bolt of Linen Cloth at ") ~= nil, peek(X).text)
	W.pressKey()
	W.advance(1)
	T.check("posted", #myAuctions(2996), 1)
	-- the queue's material
	W.advance(3)
	T.check("press: check the queue's Tin Bars", peek(X).text, "Check the price: 3 Tin Bar (craft queue)")
	W.pressKey()
	W.advance(2)
	T.check("buy them", peek(X).text, "Buy 3 Tin Bar for about 1s 20c")
	W.pressKey()
	W.advance(1)
	W.pressKey()
	W.advance(1)
	T.check("bought for the queue", W.won[2] and (W.won[2].id .. " x" .. W.won[2].count), "3576 x3")
	T.check("on their way in the mail: counted as owned", X.QueueOnWay(3576), 3)
	T.check("nothing more to buy for the queue", #X.QueueBuys(), 0)
	T.check("one call per press", calls(), "CancelAuction,PostCommodity,StartCommoditiesPurchase,ConfirmCommoditiesPurchase," ..
		"PostCommodity,StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	W.advance(3)
	p = peek(X)
	T.check("all done: a press checks your auctions again", p.what, "recheck")
	W.pressKey()
	T.check("that press: nothing restricted", #W.pressCalls(), 7)
	T.ok("a new round (done at once: nothing new)", X.routine.state ~= "off" and #W.searches > 0, X.routine.state)
	-- the mailbox read after the purchase: the Tin Bars count from the mail now, not twice
	W.closeAH()
	W.addMail(W.mailWon(3576, 120, 3, "Dee Smith"))
	W.openMail()
	W.advance(2)
	T.check("read from the mailbox: no longer on the way", X.QueueOnWay(3576), 0)
	T.check("still nothing to buy", #X.QueueBuys(), 0)
	-- the old key for buying only still works
	T.check("Next buy key still there", type(W.env.XNAH_NextBuy), "function")
end)

T.scene("next: profession window, then the mailbox - mail only on a press", function()
	local X = W.start()
	history(X, "2840", 30)
	history(X, "3576", 40)
	history(X, "2841", 100)
	bronze(X)
	X.QueueSet(2, "craft", 3)
	W.give(2840, 2)
	W.give(3576, 2)
	W.openProfession("Mining")
	W.advance(2)
	local p = peek(X)
	T.check("profession window: craft", p.text, "Craft Bronze Bar x2")
	T.check("its part", p.area, "craft")
	W.pressKey()
	T.check("one press: one craft", calls(), "CraftRecipe")
	T.check("bronze x2", W.crafted[1] and (W.crafted[1].rid .. "x" .. W.crafted[1].count), "2x2")
	T.ok("chat says it", #W.said("crafting Smelt Bronze x2") == 1, W.lastSaid())
	-- the mailbox (the profession window still open, nothing left to craft from the bags)
	W.take(2840, 2)
	W.take(3576, 2)
	W.mailNeedsPress = true
	W.addMail(W.mailSold(2589, 30000, 20, "Ann Lee", 1500))
	W.addMail(W.mailExpired(2592, 4))
	W.addMail({sender = "Bob Stone", subject = "hello", money = 5000})   -- from a player: never taken
	W.openMail()
	W.advance(30)
	T.check("the mailbox open 30 s: nothing taken by itself", #W.mailTakes, 0)
	p = peek(X)
	T.ok("mailbox: take the next one", p.text:find("^Take the next auction mail %(2 left") ~= nil, p.text)
	T.check("its part", p.area, "mail")
	W.pressKey()
	T.check("press 1: one take (the gold)", calls(), "CraftRecipe,TakeInboxMoney")
	W.pressKey()
	T.check("a press while the mailbox is busy: nothing", #W.mailTakes, 1)
	W.advance(1)
	W.pressKey()
	T.check("press 2: one take (the items)", calls(), "CraftRecipe,TakeInboxMoney,TakeInboxItem")
	W.advance(1)
	T.check("the expired Wool is in the bags", bagCount(2592), 4)
	T.check("nothing left", peek(X).text, "No auction house mail waiting")
	W.pressKey()
	T.check("press 3: nothing", #W.mailTakes, 2)
	T.check("the player's mail stays", #W.mail, 1)
	T.ok("the sale is in the ledger", #(X.Ledger().sales or {}) == 1, #(X.Ledger().sales or {}))
	-- outside a press the game refuses
	W.addMail(W.mailSold(2589, 1000, 1, "Cid Moss", 50))
	W.advance(1)
	T.check("outside a press: refused", (pcall(X.DoNext)), false)
	-- crafting comes first when both are open and there is something to craft
	W.give(2840, 1)
	W.give(3576, 1)
	W.advance(1)
	T.check("profession window first", peek(X).what, "craft")
	W.closeProfession()
	W.advance(1)
	T.check("then the mail again", peek(X).what, "mail")
	W.closeMail()
	T.check("closed: away", peek(X).what, "away")
end)

T.scene("next: the button - its label, only what it said, nothing from a timer", function()
	local X = W.start()
	history(X, "2592", 60)
	history(X, "2996", 150)
	W.list(2592, 60, 20, 1, "Bob")
	W.list(2996, 140, 20, 1, "Bob")
	W.putBag(0, 1, 2592, 10)
	W.putBag(0, 2, 2996, 5)
	X.S().routineCancel = false
	W.openAH()
	W.advance(3)
	X.UI.Open("home")
	W.advance(1)
	local panel = X.UI.tabs.home.panel
	local btn = panel.next
	T.ok("the big button is there", btn and btn:IsVisible())
	T.check("its label: the next step", W.plain(W.buttonText(btn)), "Check your auctions and bags (to cancel and post)")
	btn:Click()
	T.ok("prepared", routineReady(X))
	W.advance(1)
	local label = W.plain(W.buttonText(btn))
	T.ok("label: the first post", label:find("^Post 5 Bolt of Linen Cloth") ~= nil, label)
	-- two minutes of timers and events: nothing restricted happens
	W.advance(120)
	T.check("nothing restricted from timers", calls(), "")
	-- the step changes after the label was drawn (you untick Bolt): the click only shows the new step
	local bolt
	for _, r in ipairs(X.SellItems()) do if r.key == "2996" then bolt = r end end
	X.SetSellTick("2996", false, bolt)
	btn:Click()
	T.check("old label: the click did nothing restricted", calls(), "")
	label = W.plain(W.buttonText(btn))
	T.check("it shows the new step", label, "Post 10 Wool Cloth at 59c each")
	btn:Click()
	W.advance(1)
	T.check("now it posts", calls(), "PostCommodity")
	T.check("Bolt stays in the bags", bagCount(2996), 5)
	-- the Next step key outside a key press: refused by the game
	X.SetSellTick("2996", true, bolt)
	W.advance(3)
	T.check("outside a press: refused", (pcall(X.DoNext)), false)
	T.check("the refused call posted nothing", bagCount(2996), 5)
end)

T.scene("next: Home's checklist of the day", function()
	local X = W.start()
	W.advance(5)
	local steps = fresh(X)
	local ids = {}
	for _, s in ipairs(steps) do ids[#ids + 1] = s.id end
	T.check("the steps, in order", table.concat(ids, ","), "scan,mail,cancel,post,buy,craft,ideas")
	T.check("no scan yet: open", stepOf(X, "scan").done, false)
	T.check("nothing in the mail: ticked", stepOf(X, "mail").done, true)
	T.check("no auctions: ticked", stepOf(X, "cancel").done, true)
	T.check("nothing to buy: ticked", stepOf(X, "buy").done, true)
	T.check("no queue: ticked", stepOf(X, "craft").done, true)
	T.check("the optional line is never ticked", stepOf(X, "ideas").optional, true)
	T.check("first open: the scan", (X.HomeTodayNext()) and X.HomeTodayNext().id, "scan")
	T.ok("the scan step has a button", stepOf(X, "scan").job ~= nil)
	-- a scan of yesterday is not today's
	X.Realm().lastFull = X.HomeDayStart() - 3600
	fresh(X)
	T.check("yesterday's scan: open", stepOf(X, "scan").done, false)
	X.Realm().lastFull = X.Now()
	fresh(X)
	T.check("today's scan: ticked", stepOf(X, "scan").done, true)
	T.check("all done", X.HomeTodayNext(), nil)
	-- the shopping list, the queue and gold in the mailbox
	bronze(X)
	X.QueueSet(2, "craft", 2)
	X.ShopAdd("Mats", "2589", 10)
	X.db.chars[X.CharKey()].mailMoney = 50000
	W.advance(1)
	fresh(X)
	T.check("gold waiting: the mail step is open", stepOf(X, "mail").done, false)
	T.check("list items: the buy step is open", stepOf(X, "buy").done, false)
	T.ok("the buy step names the queue's materials", (stepOf(X, "buy").detail or ""):find("for your crafting queue", 1, true) ~= nil,
		stepOf(X, "buy").detail)
	T.check("the queue: the craft step is open", stepOf(X, "craft").done, false)
	T.check("first open: the mail", X.HomeTodayNext().id, "mail")
	-- the page
	X.UI.Toggle()
	W.advance(1)
	X.UI.Select("home")
	W.advance(1)
	local panel = X.UI.tabs.home.panel
	local text = W.screen(panel)
	T.ok("shows the steps", text:find("Scan prices", 1, true) and text:find("Craft your queue", 1, true), text)
	T.ok("shows how many are done", text:find("of 6 done", 1, true) ~= nil, text)
	T.ok("a done step has a tick", panel.steps[1].mark.text and panel.steps[1].mark.text:find("ReadyCheck-Ready", 1, true) ~= nil, panel.steps[1].mark.text)
	T.ok("the first open step is lit", panel.steps[2].bar:IsShown() and not panel.steps[1].bar:IsShown())
	T.check("the big button: where to go", W.plain(W.buttonText(panel.next)), "Go to the auction house, a mailbox or your profession window")
	T.ok("the big button does nothing here", panel.next.disabled == true)
	-- the Gold button of the mail step still opens tab Gold
	W.click("Gold", panel)
	W.advance(0.5)
	T.check("the mail step's button opens tab Gold", X.UI.current, "gold")
end)
