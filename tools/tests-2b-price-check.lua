-- XNAH test scenes, part 2b: the automatic price check (is the full scan's buyout for the stack or for one?).
-- A search of a stackable item gives a sure price of one; X.CheckUnits compares it with the full scan read both ways.

local function stacks()
	W.list(2589, 50, 20, 3, "Ann")      -- 3 stacks of 20 Linen Cloth at 50c each
	W.list(2589, 60, 5, 2, "Bob")
	W.list(15210, 50000, 1, 1, "Cid", -19)
end

T.scene("price check: full scan gives the price of ONE - found and fixed", function()
	local X = W.start()
	stacks()
	W.replicateBuyoutIsTotal = false
	W.openAH()
	T.ok("first full scan finished", T.fullScan(X))
	T.check("before the check: Linen reads 20 times too low", X.Items()["2589"].cur.min, 2.5)
	T.check("mode not known yet", X.Realm().unitMode, nil)
	T.ok("search Linen", X.ScanItems({"2589"}, "check"))
	T.ok("search done", W.waitFor(function() return X.scan.state == "idle" end, 30))
	T.check("mode found: price of one", X.Realm().unitMode, "unit")
	T.ok("Xn is told", #W.said("price check:") > 0, W.chat[#W.chat])
	W.advance(16 * 60)
	T.ok("second full scan finished", T.fullScan(X))
	T.check("after the check: Linen right", X.Items()["2589"].cur.min, 50)
	T.check("single items stay right", X.Items()["15210:-19"].cur.min, 50000)
end)

T.scene("price check: full scan gives the price of the stack - stays", function()
	local X = W.start()
	stacks()
	W.openAH()
	T.ok("full scan finished", T.fullScan(X))
	T.check("Linen right", X.Items()["2589"].cur.min, 50)
	X.ScanItems({"2589"}, "check")
	T.ok("search done", W.waitFor(function() return X.scan.state == "idle" end, 30))
	T.check("mode: stack", X.Realm().unitMode, "stack")
	T.ok("Xn is told it passed", #W.said("price check passed") > 0, W.chat[#W.chat])
end)

T.scene("price check: no answer without a recent full scan or without stacks", function()
	local X = W.start()
	W.list(15210, 50000, 1, 1, "Cid", -19)
	W.list(2589, 50, 1, 4, "Ann") -- Linen only as single units: both readings are the same
	W.openAH()
	T.ok("full scan finished", T.fullScan(X))
	X.ScanItems({"2589"}, "check")
	T.ok("search done", W.waitFor(function() return X.scan.state == "idle" end, 30))
	T.check("no stacks: nothing decided", X.Realm().unitMode, nil)
end)
