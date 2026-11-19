-- XNAH test scenes, part 15: the one-key routine (Routine.lua) - each press of its key does ONE thing: cancels first,
-- then posts at XNAH's price; a price warning needs a second press; failed steps are skipped; nothing that posts or
-- cancels ever runs outside a press (tools/world-auction.lua + world-routine.lua make those calls throw outside one).

local function history(X, key, usual, days)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5) end
end
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
local function calls() return table.concat(W.restrictedCalls, ",") end
local function ready(X)
	return W.waitFor(function() return X.routine.phase == "ready" and X.routine.cur == nil end, 60)
end
local function kinds(X)
	local out = {}
	for _, s in ipairs(X.routine.steps) do out[#out + 1] = s.kind .. " " .. s.key end
	return table.concat(out, ", ")
end

T.scene("routine: cancels first, then posts, one action per press", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	W.mine(2589, 95, 10)                 -- undercut by Ann at 90c
	W.mine(2592, 50, 10)                 -- not undercut (others at 60c)
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.list(15210, 50000, 1, 1, "Cid", -19)
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.putBag(1, 1, 15210, 1, -19)
	W.putBag(1, 2, 15210, 1, -19)
	W.putBag(1, 3, 4306, 5)              -- not on the sell list: never posted
	W.openAH()
	X.SetSellList("2589", true)
	X.SetSellList("2592", true)
	X.SetSellList("15210:-19", true)
	T.check("off before the first press", X.routine.state, "off")
	T.check("peek: start", X.RoutinePeek().what, "start")
	-- the first press only starts (asks for your auctions, searches prices in the background)
	W.pressKey()
	T.check("first press: started", X.routine.state, "on")
	T.check("first press: nothing restricted", #W.restrictedCalls, 0)
	T.ok("chat says it is checking", #W.said("checking your auctions") == 1, W.lastSaid())
	T.check("a press while it prepares does nothing restricted", (function() W.pressKey() return #W.restrictedCalls end)(), 0)
	T.ok("prepared", ready(X))
	T.check("no restricted call while preparing", #W.restrictedCalls, 0)
	T.check("the steps: cancels first, then posts", kinds(X), "cancel 2589, post 2589, post 2592, post 15210:-19, post 15210:-19")
	T.check("peek: the cancel", X.RoutinePeek().text, "Next: cancel Linen Cloth x10 (undercut by 5c)")
	-- 1: the cancel
	W.pressKey()
	T.check("press 1: one cancel", calls(), "CancelAuction")
	W.pressKey()
	T.check("a press before the answer does nothing", calls(), "CancelAuction")
	W.advance(1)
	T.check("cancelled", #myAuctions(2589), 0)
	T.check("count: cancelled", X.routine.counts.cancelled, 1)
	T.check("the other auction stays", #myAuctions(2592), 1)
	-- 2: Linen, all 20 in one auction, undercut by 1c
	T.check("peek: post Linen", X.RoutinePeek().text, "Next: post 20 x Linen Cloth at 89c each")
	W.pressKey()
	T.check("press 2: one post", calls(), "CancelAuction,PostCommodity")
	W.advance(1)
	local mine = myAuctions(2589)
	T.check("Linen posted", #mine, 1)
	T.check("Linen: 20 in it", mine[1] and mine[1].count, 20)
	T.check("Linen: at 89c", mine[1] and W.unitOf(mine[1]), 89)
	T.check("Linen bags empty", bagCount(2589), 0)
	-- 3: Wool
	T.check("peek: post Wool", X.RoutinePeek().text, "Next: post 10 x Wool Cloth at 59c each")
	W.pressKey()
	W.advance(1)
	T.check("Wool posted", #myAuctions(2592), 2)
	-- 4 + 5: the swords, one auction each
	T.check("peek: a sword", X.RoutinePeek().text, "Next: post 1 x Raider Shortsword of the Bear at 4g 99s 99c")
	W.pressKey()
	W.advance(1)
	W.pressKey()
	W.advance(1)
	T.check("both swords posted", #myAuctions(15210), 2)
	T.check("restricted calls, one per press", calls(), "CancelAuction,PostCommodity,PostCommodity,PostItem,PostItem")
	T.check("done", X.routine.state, "done")
	T.check("done text", X.RoutinePeek().text, "Done: 1 cancelled, 4 posted")
	T.check("progress", select(1, X.RoutineProgress()) .. "/" .. select(2, X.RoutineProgress()), "5/5")
	T.check("silk (not on the list) stays in the bags", bagCount(4306), 5)
	T.check("nothing bought", #W.won, 0)
	-- after done, a press starts a new round (nothing restricted on that press)
	W.pressKey()
	T.check("new round", X.routine.state, "on")
	T.ok("new round prepared", ready(X))
	T.check("new round: nothing undercut, nothing in the bags", X.routine.state, "done")
	T.check("new round: no more calls", #W.restrictedCalls, 5)
end)

T.scene("routine: a price warning needs a second press; failed steps are skipped", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "2996", 150)
	W.mine(2770, 20, 5)                  -- undercut, but the auction house refuses the cancel
	W.list(2770, 10, 20, 1, "Ann")
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.list(2996, 140, 20, 1, "Bob")
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.putBag(0, 3, 2996, 5)
	W.putBag(0, 4, 2841, 3)              -- no price known at all
	W.openAH()
	for _, k in ipairs({"2589", "2592", "2996", "2841"}) do X.SetSellList(k, true) end
	W.pressKey()
	T.ok("prepared", ready(X))
	T.check("steps", kinds(X), "cancel 2770, post 2589, post 2592, post 2996, post 2841")
	-- the cancel is refused: skipped with a reason
	W.cancelRefuse = true
	W.pressKey()
	W.advance(1)
	T.check("cancel tried once", calls(), "CancelAuction")
	T.check("cancel skipped", X.routine.steps[1].status, "skipped")
	T.ok("reason", (X.routine.steps[1].why or ""):find("did not cancel", 1, true), X.routine.steps[1].why)
	T.check("auction still up", #myAuctions(2770), 1)
	-- Linen: the auction house warns -> a second press confirms
	W.warnNextPost = true
	W.pressKey()
	W.advance(1)
	T.check("not posted yet", #myAuctions(2589), 0)
	local peek = X.RoutinePeek()
	T.check("peek: confirm", peek.what, "confirm")
	T.ok("confirm text", peek.text:find("Next: confirm the post of 20 x Linen Cloth", 1, true), peek.text)
	W.advance(30)
	T.check("the warning waits for you (no time-out)", X.RoutinePeek().what, "confirm")
	W.pressKey()
	W.advance(1)
	T.check("posted after the second press", #myAuctions(2589), 1)
	T.check("calls", calls(), "CancelAuction,PostCommodity,ConfirmPostCommodity")
	-- Wool: the auction house says no -> skipped, on to the next
	W.postErrorNext = true
	W.pressKey()
	W.advance(1)
	T.check("wool tried once", calls(), "CancelAuction,PostCommodity,ConfirmPostCommodity,PostCommodity")
	T.check("wool skipped", X.routine.steps[3].status, "skipped")
	T.check("wool still in the bags", bagCount(2592), 10)
	-- Bolt: gone from the bags before its press -> skipped; Bronze Bar has no price -> skipped; nothing restricted
	W.bags[0][3] = nil
	W.pressKey()
	T.check("bolt skipped", X.routine.steps[4].status, "skipped")
	T.ok("bolt reason", (X.routine.steps[4].why or ""):find("not in your bags", 1, true), X.routine.steps[4].why)
	T.check("bronze skipped", X.routine.steps[5].status, "skipped")
	T.check("no call for skipped steps", #W.restrictedCalls, 4)
	T.check("done", X.routine.state, "done")
	T.check("done text", X.routine.text, "Done: 0 cancelled, 1 posted, 4 skipped")
	T.ok("chat says why each was skipped", #W.said("skipped") >= 4, #W.said("skipped"))
	-- Skip: a price warning answered with Skip this step
	W.putBag(0, 1, 2592, 10)
	X.S().routineCancel = false
	W.pressKey()
	T.ok("prepared again", ready(X))
	T.check("steps of the new round", kinds(X), "post 2592, post 2841")
	W.warnNextPost = true
	W.pressKey()
	W.advance(1)
	T.check("warning", X.RoutinePeek().what, "confirm")
	X.RoutineSkip()
	T.check("skipped by you", X.routine.steps[1].status, "skipped")
	T.check("the reason", X.routine.steps[1].why, "you said no to the price warning")
	T.check("post state back to idle", X.post.state, "idle")
	T.check("nothing posted", #myAuctions(2592), 0)
end)

T.scene("routine: nothing restricted happens outside a press", function()
	local X = W.start()
	history(X, "2589", 100)
	W.mine(2589, 95, 10)
	W.list(2589, 90, 20, 3, "Ann")
	W.putBag(0, 1, 2589, 20)
	X.SetSellList("2589", true)
	-- the key with the auction house closed: a chat line, nothing else
	W.pressKey()
	T.ok("closed: says so", #W.said("only while the auction house is open") == 1, W.lastSaid())
	T.check("closed: not started", X.routine.state, "off")
	W.openAH()
	-- a full scan is running: the routine waits for it before it asks or searches anything
	T.ok("full scan started", X.FullScan())
	local searches = #W.searches
	X.RoutineStart()
	T.check("waits for the scan", X.RoutinePeek().text, "Waiting for the scan to finish")
	T.check("no search while the scan runs", #W.searches, searches)
	W.waitFor(function() return X.scan.state == "idle" end, 300)
	T.ok("prepared after the scan", ready(X))
	T.ok("searched after the scan", #W.searches > searches)
	W.advance(120)
	T.check("two minutes of timers and events: no restricted call", #W.restrictedCalls, 0)
	T.check("the steps wait for presses", X.routine.steps[1].status, "todo")
	T.check("a call outside a press is refused by the game", (pcall(X.RoutineNext)), false)
	T.check("nothing cancelled", #myAuctions(2589), 1)
	T.check("nothing posted", bagCount(2589), 20)
	-- the auction house closes: the round stops
	W.closeAH()
	W.advance(1)
	T.check("stopped when closed", X.routine.state, "off")
	T.check("peek when closed", X.RoutinePeek().what, "closed")
end)

T.scene("routine: the Sell tab's routine view and the sell list", function()
	local X = W.start()
	history(X, "2589", 100)
	W.mine(2589, 95, 10)
	W.list(2589, 90, 20, 1, "Ann")
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.bindings.XNAH_NEXT = "F"
	W.openAH()
	X.UI.Open("sell")
	W.advance(0.5)
	local p = X.UI.tabs.sell.panel
	-- the sell list: ticked on the bag view
	W.click("Linen Cloth", p.sellTable)
	W.advance(2)
	W.click("On the sell list", p)
	T.check("ticked: on the list", X.OnSellList("2589"), true)
	T.check("saved", X.db.sellList["2589"], true)
	-- the routine view
	W.click("One-key routine", p)
	W.advance(0.5)
	T.ok("shows the key", W.screen(p):find("Your key: F", 1, true) ~= nil, W.screen(p))
	T.ok("sell list count", W.screen(p):find("Sell list: 1 items, 1 of them in your bags", 1, true) ~= nil, W.screen(p))
	W.click("Start: check your auctions", p)
	T.check("the button started it", X.routine.state, "on")
	T.ok("prepared", ready(X))
	W.advance(1)
	T.ok("button shows the next step", W.findButton("Next: cancel Linen Cloth x10 (undercut by 5c)", p) ~= nil, W.screen(p))
	T.ok("progress", W.screen(p):find("Step 1 of 2", 1, true) ~= nil, W.screen(p))
	T.ok("steps listed", W.screen(p.routineTable):find("next", 1, true) ~= nil, W.screen(p.routineTable))
	W.click("Next: cancel Linen Cloth", p)
	W.advance(1)
	T.check("the button cancelled", calls(), "CancelAuction")
	W.advance(1)
	T.ok("button: the post", W.findButton("Next: post 20 x Linen Cloth at 89c each", p) ~= nil, W.screen(p))
	W.click("Skip this step", p)
	T.check("skipped with the button", X.routine.state, "done")
	T.ok("button: done", W.findButton("Done: 1 cancelled, 0 posted, 1 skipped", p) ~= nil, W.screen(p))
	-- without cancelling, with Start over
	W.click("Cancel undercut auctions first", p)
	T.check("setting off", X.S().routineCancel, false)
	W.click("Start over", p)
	T.ok("prepared", ready(X))
	T.check("only the post now", kinds(X), "post 2589")
	W.click("Stop", p)
	T.check("stopped", X.routine.state, "off")
	-- untick
	W.click("Sell from your bags", p)
	W.click("Linen Cloth", p.sellTable)
	W.advance(1)
	W.click("On the sell list", p)
	T.check("unticked", X.OnSellList("2589"), false)
	T.check("only the cancel was restricted", calls(), "CancelAuction")
end)
