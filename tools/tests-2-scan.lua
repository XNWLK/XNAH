-- XNAH test scenes, part 2: reading the auction house - full scans, the watch list scan, browsing.

-- a few hand-made auctions on top of a market: Linen Cloth in stacks, a sword with random suffixes
local function handMade()
	W.list(2589, 50, 20, 3, "Ann")      -- 3 stacks of 20 Linen Cloth at 50c each
	W.list(2589, 60, 5, 2, "Bob")       -- 2 stacks of 5 at 60c each
	W.list(15210, 50000, 1, 1, "Cid", -19) -- Raider Shortsword of the Bear, 5g
	W.list(15210, 60000, 1, 1, "Dan", -19)
	W.list(15210, 30000, 1, 1, "Eve", -5)  -- of the Monkey, 3g
	W.items[2770].uncached = true       -- Copper Ore: the game has not loaded it yet
	W.list(2770, 12, 20, 4, "Fay")
end

T.scene("scan: full scan of 5,000+ auctions, read in slices", function()
	local X = W.start()
	W.makeMarket(11, 400)
	handMade()
	T.ok("more than 5,000 auctions", #W.ah > 5000, #W.ah)
	W.openAH()
	T.check("the addon saw the auction house open", X.ahOpen, true)
	T.check("scan starts", X.FullScan(), true)
	T.check("waiting for the server", X.scan.state, "waiting")
	W.advance(1)
	T.check("still waiting after 1 s", X.scan.state, "waiting")
	W.advance(1.2)
	T.ok("reading after the server answered", X.scan.state == "reading" or X.scan.state == "loading", X.scan.state)
	T.check("total auctions known", X.scan.total, #W.ah)
	W.maxStepRows = 0
	T.ok("scan finished", W.waitFor(function() return X.scan.state == "idle" end, 120), X.scan.state)
	T.ok("no step read more than 1,000 rows", W.maxStepRows <= 1000, W.maxStepRows)
	-- every listed item recorded
	local keys = T.ahKeys()
	local missing = 0
	for k in pairs(keys) do if not (X.Items()[k] and X.Items()[k].cur) then missing = missing + 1 end end
	T.check("every item on the auction house recorded", missing, 0)
	T.check("no extra items", T.count(X.Items()), T.count(keys))
	-- prices of one for stacks
	local lin = X.Items()["2589"]
	T.check("Linen: lowest price of one", lin.cur.min, 50)
	T.check("Linen: market value of one", lin.cur.mkt, 50)
	T.check("Linen: quantity", lin.cur.qty, 70)
	T.check("Linen: auctions", lin.cur.auc, 5)
	T.check("Linen: sellers", lin.cur.sellers, 5)
	local wrong, checked = 0, 0
	for _, id in ipairs(W.market.byKind.stack) do
		local it = X.Items()[tostring(id)]
		local expect = T.ahMin(id)
		checked = checked + 1
		if not it or not it.cur.min or math.abs(it.cur.min - expect) > 0.01 then wrong = wrong + 1 end
	end
	T.check("lowest price of one right for all " .. checked .. " stackable items", wrong, 0)
	-- random suffixes are told apart
	T.check("sword of the Bear: lowest", X.Items()["15210:-19"].cur.min, 50000)
	T.check("sword of the Monkey: lowest", X.Items()["15210:-5"].cur.min, 30000)
	T.check("sword of the Bear: name", X.Items()["15210:-19"].n, "Raider Shortsword of the Bear")
	-- not loaded at first: loaded on the retry
	T.ok("Copper Ore (not loaded at first) recorded", X.Items()["2770"] ~= nil)
	T.check("Copper Ore: price", X.Items()["2770"] and X.Items()["2770"].cur.min, 12)
	T.check("Copper Ore: name", X.Items()["2770"] and X.Items()["2770"].n, "Copper Ore")
	-- the scans log
	local log = X.Realm().scans
	T.check("one scan logged", #log, 1)
	T.check("log: kind", log[1] and log[1].kind, "full")
	T.check("log: auctions", log[1] and log[1].auctions, #W.ah)
	T.check("log: items", log[1] and log[1].items, T.count(keys))
	T.check("log: none skipped", log[1] and log[1].skipped, 0)
	T.ok("chat says done", #W.said("full scan done") == 1, W.lastSaid())
	T.near("next full scan in 15 minutes", X.FullScanLeft(), 900, 30)
	T.check("a second scan is refused by XNAH itself", X.FullScan(), false)
	-- 16 minutes later Linen Cloth sold out: the next full scan marks it
	W.advance(16 * 60)
	local keep = {}
	for _, a in ipairs(W.ah) do if a.itemID ~= 2589 then keep[#keep + 1] = a end end
	W.ah = keep
	T.ok("second full scan", T.fullScan(X))
	T.check("Linen sold out: quantity 0", X.Items()["2589"].cur.qty, 0)
	T.check("Linen sold out: price falls back to the earlier value", X.Price("2589"), 50)
	T.check("two scans logged", #X.Realm().scans, 2)
end)

T.scene("scan: items that never load are read without their details", function()
	local X = W.start()
	handMade()
	W.items[2592].uncached, W.items[2592].never = true, true
	W.list(2592, 80, 10, 3)
	W.openAH()
	T.ok("scan finished", T.fullScan(X))
	local wool = X.Items()["2592"]
	T.check("item that never loaded: recorded under its plain item ID", wool and wool.cur.min, 80)
	T.check("item that never loaded: quantity", wool and wool.cur.qty, 30)
	T.check("log: 3 auctions read without details", X.Realm().scans[1].skipped, 3)
	T.check("others recorded", X.Items()["2589"].cur.min, 50)
end)

T.scene("scan: if the full scan gave prices of ONE (switch)", function()
	-- XNAH divides the full scan's buyout by the count (the old auction house gave the whole stack's price). If Forever
	-- turns out to give the price of one, every stack price comes out `count` times too low - /xnah raw checks this.
	local X = W.start()
	handMade()
	W.replicateBuyoutIsTotal = false
	W.openAH()
	T.ok("scan finished", T.fullScan(X))
	local lin = X.Items()["2589"].cur
	T.check("per-unit buyouts: Linen comes out 20 times too low (50c / 20)", lin.min, 2.5)
	T.check("single items are not affected", X.Items()["15210:-19"].cur.min, 50000)
	T.note("full scan buyout per unit (if Forever does that): Linen Cloth would read " .. lin.min .. "c instead of 50c")
end)

T.scene("scan: server refuses a full scan within 15 minutes", function()
	local X = W.start()
	handMade()
	W.openAH()
	T.ok("first scan", T.fullScan(X))
	W.advance(60)
	-- another character (or a reload that lost the time) asks again: XNAH thinks it may, the server stays silent
	X.Realm().lastFull = nil
	T.check("scan asked for", X.FullScan(), true)
	W.advance(80)
	T.check("still waiting after 80 s", X.scan.state, "waiting")
	T.check("the server got the call and kept quiet", W.refused, 1)
	W.advance(11)
	T.check("stopped after 90 s", X.scan.state, "idle")
	T.ok("a message says why", #W.said("no answer from the server") == 1, W.lastSaid())
	T.near("may try again in 5 minutes", X.FullScanLeft(), 300, 2)
	T.check("only one scan logged", #X.Realm().scans, 1)
	T.ok("text on the scan state", (X.scan.text or ""):find("Stopped", 1, true) ~= nil, X.scan.text)
end)

T.scene("scan: closing the auction house mid-scan", function()
	local X = W.start()
	W.makeMarket(5, 300)
	W.openAH()
	T.check("scan starts", X.FullScan(), true)
	W.advance(2.0)
	T.check("reading", X.scan.state, "reading")
	W.advance(0.05) -- one frame: one slice read
	T.ok("part read", (X.scan.done or 0) > 0 and X.scan.done < X.scan.total, tostring(X.scan.done) .. " / " .. tostring(X.scan.total))
	W.closeAH()
	T.check("stopped", X.scan.state, "idle")
	T.ok("text says the auction house was closed", (X.scan.text or ""):find("closed", 1, true) ~= nil, X.scan.text)
	W.advance(10)
	T.check("nothing half-saved", T.count(X.Items()), 0)
	T.check("no scan logged", #X.Realm().scans, 0)
	T.check("the addon knows it is closed", X.ahOpen, false)
	T.check("no scan without the auction house", X.FullScan(), false)
	-- open again later: a new scan works
	W.advance(16 * 60)
	W.openAH()
	T.ok("a new scan after reopening", T.fullScan(X))
	T.ok("items recorded", T.count(X.Items()) > 100, T.count(X.Items()))
	-- closing while waiting for the server
	W.advance(16 * 60)
	T.check("scan asked", X.FullScan(), true)
	W.closeAH()
	T.check("waiting scan stopped", X.scan.state, "idle")
	W.advance(100)
	T.check("still idle", X.scan.state, "idle")
end)

T.scene("scan: watch list - commodities, gear, a random suffix, a search with no answer", function()
	local X = W.start()
	handMade()
	W.list(2589, 45, 2, 1, "Gil") -- a cheaper few
	X.SetWatched("2589", true)
	X.SetWatched("15210:-19", true)
	X.SetWatched("2592", true)      -- Wool Cloth: the server never answers
	X.SetWatched("15248", true)     -- Gleaming Claymore: none listed
	W.searchDrop[2592] = true
	T.check("no watch scan without the auction house", X.ScanItems(), false)
	W.openAH()
	local t0 = W.NOW
	T.check("watch scan starts", X.ScanItems(), true)
	T.ok("finished", W.waitFor(function() return X.scan.state == "idle" end, 60), X.scan.state)
	T.ok("the one with no answer was skipped after about 6 s", W.NOW - t0 >= 6 and W.NOW - t0 < 15, W.NOW - t0)
	T.check("4 searches sent", #W.searches, 4)
	local lin = X.Items()["2589"]
	T.check("Linen: lowest (commodity search, price of one)", lin and lin.cur.min, 45)
	T.check("Linen: quantity", lin and lin.cur.qty, 72)
	T.check("Linen: market value", lin and lin.cur.mkt, 50)
	local bear = X.Items()["15210:-19"]
	T.check("sword of the Bear: lowest", bear and bear.cur.min, 50000)
	T.check("sword of the Bear: 2 auctions", bear and bear.cur.auc, 2)
	T.check("sword of the Monkey not searched", X.Items()["15210:-5"], nil)
	T.check("Wool Cloth: nothing recorded", X.Items()["2592"], nil)
	T.check("Claymore: nothing recorded (never seen)", X.Items()["15248"], nil)
	local log = X.Realm().scans
	T.check("scan logged", log[#log] and log[#log].kind, "watch list")
	T.check("scan logged: 4 items", log[#log] and log[#log].items, 4)
	T.ok("chat says done", #W.said("scan done: 4 items") == 1, W.lastSaid())
	-- the base key of a sword finds every suffix and records each apart
	T.check("one item search", X.ScanItems({"15210"}, "one item"), true)
	W.waitFor(function() return X.scan.state == "idle" end, 20)
	T.check("base key: Monkey recorded too", X.Items()["15210:-5"] and X.Items()["15210:-5"].cur.min, 30000)
	-- the Claymore sold out after being seen: an empty answer marks it
	X.Record("15248", X.Now() - 600, 90000, 90000, 1, 1)
	X.ScanItems({"15248"})
	W.waitFor(function() return X.scan.state == "idle" end, 20)
	T.check("empty answer: sold out", X.Items()["15248"].cur.qty, 0)
	-- a stack item that sold out: commodity search with no rows
	local keep = {}
	for _, a in ipairs(W.ah) do if a.itemID ~= 2589 then keep[#keep + 1] = a end end
	W.ah = keep
	X.ScanItems({"2589"})
	W.waitFor(function() return X.scan.state == "idle" end, 20)
	T.check("commodity empty answer: sold out", X.Items()["2589"].cur.qty, 0)
	-- closing the auction house stops a watch scan
	X.ScanItems({"2589", "15210:-19", "15248"})
	W.closeAH()
	T.check("watch scan stopped on close", X.scan.state, "idle")
end)

T.scene("scan: browsing keeps the earlier market value", function()
	local X = W.start()
	handMade()
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	W.advance(30)
	W.list(2589, 30, 1, 1, "Cheap")
	W.list(2592, 70, 10, 2, "Wool")
	W.env.C_AuctionHouse.SendBrowseQuery({searchString = "cloth", sorts = {}})
	W.advance(1.5)
	local lin = X.Items()["2589"].cur
	T.check("browse: new lowest price", lin.min, 30)
	T.check("browse: quantity", lin.qty, 71)
	T.check("browse: market value of the full scan kept", lin.mkt, 50)
	T.ok("browse: market value time kept", lin.mktT ~= nil and lin.mktT < lin.t, tostring(lin.mktT) .. " vs " .. tostring(lin.t))
	T.check("browse: sellers kept", lin.sellers, 5)
	local wool = X.Items()["2592"]
	T.check("browse: a new item recorded", wool and wool.cur.min, 70)
	T.check("browse: its price falls back to the lowest", X.Price("2592"), 70)
	T.check("browse: name from the item key", wool and wool.n, "Wool Cloth")
	-- the history keeps the full scan's market value for that minute (browsing seconds later must not wipe it)
	local h = X.History("2589")
	local withMkt = 0
	for _, p in ipairs(h) do if p[3] then withMkt = withMkt + 1 end end
	T.check("history: the full scan's point still has its market value", withMkt >= 1, true)
	-- browsing a minute later: the full scan's point and the browse point
	W.advance(120)
	W.env.C_AuctionHouse.SendBrowseQuery({searchString = "linen", sorts = {}})
	W.advance(1.5)
	T.check("browse again: market value still kept", X.Items()["2589"].cur.mkt, 50)
	-- browsing during a full scan is ignored
	W.advance(16 * 60)
	X.FullScan()
	W.advance(2.2)
	W.env.C_AuctionHouse.SendBrowseQuery({searchString = "linen", sorts = {}})
	T.ok("scan finishes", W.waitFor(function() return X.scan.state == "idle" end, 60))
end)

T.scene("scan: /xnah raw prints rows as the game gives them", function()
	local X = W.start()
	handMade()
	W.openAH()
	T.fullScan(X)
	W.chat = {}
	W.env.SlashCmdList.XNAH("raw 3")
	T.check("count line + 3 rows", #W.chat, 4)
	T.ok("a row shows count and buyout", W.plain(W.chat[2] or ""):find("buyout", 1, true) ~= nil, W.chat[2])
end)
