-- XNAH test scenes, part 15: the one-key routine (Routine.lua) - each press of its key does ONE thing: cancels first,
-- then posts the ticked items (everything worth posting, unless you unticked it) at XNAH's price; a price warning needs a
-- second press; failed steps are skipped; nothing that posts or cancels ever runs outside a press
-- (tools/world-auction.lua + world-routine.lua make those calls throw outside one).

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
local function bagRow(X, key)
	for _, r in ipairs(X.SellItems()) do if r.key == key then return r end end
end

T.scene("routine: cancels first, then posts, one action per press", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	history(X, "15210:-19", 50000)
	W.mine(2589, 95, 10)                 -- undercut by Ann at 90c
	W.mine(2592, 50, 10)                 -- not undercut (others at 60c)
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.list(15210, 50000, 1, 1, "Cid", -19)
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.putBag(1, 1, 15210, 1, -19)
	W.putBag(1, 2, 15210, 1, -19)
	W.putBag(1, 3, 4306, 5)              -- no price known: not worth posting, stays
	W.openAH()
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
	T.check("the steps: cancels first, then the most valuable posts", kinds(X),
		"cancel 2589, post 15210:-19, post 15210:-19, post 2589, post 2592")
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
	-- 2 + 3: the swords, one auction each
	T.check("peek: a sword", X.RoutinePeek().text, "Next: post 1 x Raider Shortsword of the Bear at 4g 99s 99c")
	W.pressKey()
	W.advance(1)
	W.pressKey()
	W.advance(1)
	T.check("both swords posted", #myAuctions(15210), 2)
	-- 4: Linen, all 20 in one auction, undercut by 1c
	T.check("peek: post Linen", X.RoutinePeek().text, "Next: post 20 x Linen Cloth at 89c each")
	W.pressKey()
	W.advance(1)
	local mine = myAuctions(2589)
	T.check("Linen posted", #mine, 1)
	T.check("Linen: 20 in it", mine[1] and mine[1].count, 20)
	T.check("Linen: at 89c", mine[1] and W.unitOf(mine[1]), 89)
	T.check("Linen bags empty", bagCount(2589), 0)
	-- 5: Wool
	T.check("peek: post Wool", X.RoutinePeek().text, "Next: post 10 x Wool Cloth at 59c each")
	W.pressKey()
	W.advance(1)
	T.check("Wool posted", #myAuctions(2592), 2)
	T.check("restricted calls, one per press", calls(), "CancelAuction,PostItem,PostItem,PostCommodity,PostCommodity")
	T.check("done", X.routine.state, "done")
	T.check("done text", X.RoutinePeek().text, "Done: 1 cancelled, 4 posted")
	T.check("progress", select(1, X.RoutineProgress()) .. "/" .. select(2, X.RoutineProgress()), "5/5")
	T.check("silk (no price: not worth posting) stays in the bags", bagCount(4306), 5)
	T.check("nothing bought", #W.won, 0)
	-- after done, a press starts a new round (nothing restricted on that press)
	W.pressKey()
	T.check("new round", X.routine.state, "on")
	T.ok("new round prepared", ready(X))
	T.check("new round: nothing undercut, nothing worth posting", X.routine.state, "done")
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
	W.putBag(0, 4, 2841, 3)              -- no price known at all: left out (not a step)
	W.openAH()
	W.pressKey()
	T.ok("prepared", ready(X))
	T.check("steps (most valuable first)", kinds(X), "cancel 2770, post 2589, post 2996, post 2592")
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
	-- Bolt: the auction house says no -> skipped, on to the next
	W.postErrorNext = true
	W.pressKey()
	W.advance(1)
	T.check("bolt tried once", calls(), "CancelAuction,PostCommodity,ConfirmPostCommodity,PostCommodity")
	T.check("bolt skipped", X.routine.steps[3].status, "skipped")
	T.check("bolt still in the bags", bagCount(2996), 5)
	-- Wool: gone from the bags before its press -> skipped (nothing restricted)
	W.bags[0][2] = nil
	W.pressKey()
	T.check("wool skipped", X.routine.steps[4] and X.routine.steps[4].status, "skipped")
	T.ok("wool reason", (X.routine.steps[4] and X.routine.steps[4].why or ""):find("not in your bags", 1, true))
	T.check("no call for skipped steps", #W.restrictedCalls, 4)
	T.check("done", X.routine.state, "done")
	T.check("done text", X.routine.text, "Done: 0 cancelled, 1 posted, 3 skipped")
	T.ok("chat says why each was skipped", #W.said("skipped") >= 3, #W.said("skipped"))
	T.check("bronze (no price) stays in the bags", bagCount(2841), 3)
	W.bags[0][3] = nil
	-- Skip: a price warning answered with Skip this step
	W.putBag(0, 1, 2592, 10)
	X.S().routineCancel = false
	W.pressKey()
	T.ok("prepared again", ready(X))
	T.check("steps of the new round", kinds(X), "post 2592")
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

T.scene("routine: ticks change the steps while a round is on", function()
	local X = W.start()
	history(X, "2589", 100)
	history(X, "2592", 60)
	W.list(2589, 90, 20, 1, "Ann")
	W.list(2592, 60, 20, 1, "Bob")
	W.putBag(0, 1, 2589, 20)
	W.putBag(0, 2, 2592, 10)
	W.openAH()
	X.S().routineCancel = false
	W.pressKey()
	T.ok("prepared", ready(X))
	T.check("both worth posting", kinds(X), "post 2589, post 2592")
	-- untick Linen: its step goes, remembered
	X.SetSellTick("2589", false, bagRow(X, "2589"))
	T.check("unticked: gone", kinds(X), "post 2592")
	T.check("remembered", X.db.sellTick["2589"], false)
	-- something new in the bags: a step for it (ticked by default)
	history(X, "2996", 150)
	W.list(2996, 140, 20, 1, "Bob")
	W.putBag(0, 3, 2996, 5)
	W.fire("BAG_UPDATE_DELAYED")
	W.advance(3)
	T.check("new in the bags: added", kinds(X), "post 2592, post 2996")
	W.pressKey()
	W.advance(1)
	W.pressKey()
	W.advance(1)
	T.check("done", X.routine.state, "done")
	-- tick Linen again: the round goes on with it
	X.SetSellTick("2589", true, bagRow(X, "2589"))
	W.advance(2)
	T.check("ticked again: back on", X.routine.state, "on")
	T.check("its step", kinds(X), "post 2592, post 2996, post 2589")
	T.check("the choice is not kept (worth posting = ticked anyway)", X.db.sellTick["2589"], nil)
	W.pressKey()
	W.advance(1)
	T.check("posted", #myAuctions(2589), 1)
	T.check("calls", calls(), "PostCommodity,PostCommodity,PostCommodity")
	-- a reload keeps an untick
	X.SetSellTick("2592", false, bagRow(X, "2592"))
	X = W.reload()
	T.check("untick kept after a reload", X.SellChoice("2592"), false)
	T.check("the old sell list is not used", X.OnSellList, nil)
end)
