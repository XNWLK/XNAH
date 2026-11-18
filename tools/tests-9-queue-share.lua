-- XNAH test scenes, part 9 (helper D): the crafting queue (targets, materials, "Craft next" only on a click) and guild
-- price sharing (messages, chunks, the queue's pace, a whole share between two players, bad messages) and the export.

-- [[ shared bits ]]
local function craftWorld(X)
	W.recipes = {
		[1] = {name = "Smelt Copper", out = 2840, reagents = {{2770, 1}}, learned = true, prof = "Mining"},
		[2] = {name = "Smelt Bronze", out = 2841, qMin = 2, qMax = 2, reagents = {{2840, 1}, {3576, 1}}, learned = true, prof = "Mining"},
		[3] = {name = "Minor Healing Potion", out = 118, reagents = {{2447, 1}, {765, 1}, {3371, 1}}, learned = true, prof = "Alchemy"},
	}
	W.list(2770, 10, 20, 5)    -- Copper Ore 10c
	W.list(2840, 30, 20, 5)    -- Copper Bar 30c (smelting it costs 10c)
	W.list(3576, 40, 20, 5)    -- Tin Bar 40c
	W.list(2841, 50, 20, 5)    -- Bronze Bar 50c
	W.list(2447, 20, 20, 5)    -- Peacebloom
	W.list(765, 15, 20, 5)     -- Silverleaf
	W.list(3371, 50, 20, 5)    -- Empty Vial 50c (a vendor sells it for 4c)
	W.list(118, 10000, 5, 5)   -- Minor Healing Potion 1g
	W.merchant = {{itemID = 3371, price = 4, stackCount = 1, numAvailable = -1}}
	W.openProfession("Mining") W.advance(3) W.closeProfession()
	W.openProfession("Alchemy") W.advance(3) W.closeProfession()
	W.openMerchant("Alchemy Supplies") W.advance(1) W.closeMerchant()
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	W.closeAH()
end
local function rowOf(rows, rid) for _, r in ipairs(rows) do if r.rid == rid then return r end end end
local function matOf(mats, id) for _, m in ipairs(mats) do if m.id == id then return m end end end

-- a sent addon message read back (single-chunk messages)
local function decode(X, m)
	local body = m.text:match("^S[0-9a-z]+:(.*)$")
	if not body then return nil end
	return X.Deser(X.CommUnescape(body))
end
local function sentOf(X, kind, from)
	local out = {}
	for i = from or 1, #W.sent do
		local d = decode(X, W.sent[i])
		if d and d.k == kind then out[#out + 1] = {m = W.copy(W.sent[i]), d = d} end
	end
	return out
end
-- a message as if another player sent it
local function inject(X, msg, sender, channel, prefix)
	W.fire("CHAT_MSG_ADDON", prefix or "XNAH", "S1:" .. X.CommEscape(X.Ser(msg)), channel or "GUILD", sender or "Evil Guy")
end

T.scene("queue: restock vs craft, makes-per-craft, owned counts, profit", function()
	local X = W.start()
	craftWorld(X)
	local owned = X.Owned
	X.Owned = nil -- this character's bags and bank only
	W.bags[0] = {[1] = {id = 2841, count = 2}}
	W.bags[6] = {[1] = {id = 2841, count = 1}} -- in the bank
	T.check("owned: bags + bank", X.QueueOwned(2841), 3)
	X.QueueSet(2, "restock", 7) -- Bronze: one craft makes 2
	X.QueueSet(1, "craft", 4)   -- Copper Bar: craft 4 times
	X.QueueSet(3, "restock", 2) -- potion, none owned
	X.QueueSet(999, "craft", 3) -- not a recipe: refused
	T.check("queue count", X.QueueCount(), 3)
	local rows = X.QueueRows()
	local bronze, copper, potion = rowOf(rows, 2), rowOf(rows, 1), rowOf(rows, 3)
	T.check("bronze: have", bronze and bronze.have, 3)
	T.check("bronze: makes 2 a craft", bronze and bronze.makes, 2)
	T.check("bronze: (7 - 3) / 2 = 2 crafts", bronze and bronze.craft, 2)
	T.near("bronze: profit = 2 crafts x 2 x (47.5 - 25)", bronze and bronze.profit, 90, 0.01)
	T.check("copper: craft mode = the number", copper and copper.craft, 4)
	T.near("copper: profit = 4 x (28.5 - 10)", copper and copper.profit, 74, 0.01)
	T.check("potion: 2 crafts", potion and potion.craft, 2)
	X.QueueSet(2, "restock", 5)
	T.check("bronze target 5: ceil(2 / 2) = 1 craft", rowOf(X.QueueRows(), 2).craft, 1)
	X.QueueSet(2, "restock", 3)
	T.check("bronze target reached: 0 crafts", rowOf(X.QueueRows(), 2).craft, 0)
	T.check("bronze target reached: profit 0", rowOf(X.QueueRows(), 2).profit, 0)
	-- with the inventory part: every character's count
	X.Owned = function(id) if id == 2841 then return 10, {} end return 0, {} end
	X.QueueSet(2, "restock", 7)
	T.check("X.Owned used when it exists", rowOf(X.QueueRows(), 2).have, 10)
	T.check("X.Owned: target reached", rowOf(X.QueueRows(), 2).craft, 0)
	X.Owned = owned
	-- taking out
	X.QueueSet(3, "restock", 0)
	T.check("number 0 takes it out", X.QueueGet(3), nil)
	-- survives a reload
	X = W.reload()
	T.check("after reload: the queue is kept", X.QueueCount(), 2)
	T.check("after reload: mode kept", X.QueueGet(1) and X.QueueGet(1).mode, "craft")
end)

T.scene("queue: materials minus what you own, vendor reagents, shopping list", function()
	local X = W.start()
	craftWorld(X)
	local owned, shopAdd = X.Owned, X.ShopAdd
	X.Owned = nil
	X.QueueSet(2, "restock", 4)  -- bronze: 2 crafts
	X.QueueSet(1, "craft", 4)    -- copper bar: 4 crafts
	X.QueueSet(3, "restock", 2)  -- potion: 2 crafts
	W.bags[0] = {[1] = {id = 2840, count = 1}, [2] = {id = 765, count = 5}} -- 1 Copper Bar, 5 Silverleaf
	local mats, totals = X.QueueMaterials()
	local bar, tin, ore, vial, leaf = matOf(mats, 2840), matOf(mats, 3576), matOf(mats, 2770), matOf(mats, 3371), matOf(mats, 765)
	T.check("copper bar: need 2, own 1, buy 1", bar and (bar.need .. "/" .. bar.have .. "/" .. bar.buy), "2/1/1")
	T.check("copper bar: cheapest is crafting it", bar and bar.how, "craft")
	T.check("tin bar: buy 2 at 40c", tin and (tin.buy .. "/" .. tin.unit .. "/" .. tin.total), "2/40/80")
	T.check("copper ore: 4 for the 4 copper crafts", ore and ore.buy, 4)
	T.check("silverleaf: owned, nothing to buy", leaf and leaf.buy, 0)
	T.check("vial: from the vendor", vial and vial.how, "vendor")
	T.check("vial: the vendor's name", vial and vial.vendor, "Alchemy Supplies")
	local list = totals.vendor["Alchemy Supplies"]
	T.check("vendor list: the vial", list and #list == 1 and list[1].id, 3371)
	T.near("total to buy: 10 + 80 + 40 + 2 x 20 + 2 x 4", totals.cost, 10 + 80 + 40 + 40 + 8, 0.01)
	-- the shopping list (the shopping part may not be there: a stand-in records the calls)
	local calls = {}
	X.ShopAdd = function(list, key, qty, max) calls[#calls + 1] = {list = list, key = key, qty = qty, max = max} end
	T.check("send to shopping list: every reagent to buy but the vendor's", X.QueueToShop(), 4)
	local tinCall
	for _, c in ipairs(calls) do if c.key == "3576" then tinCall = c end end
	T.check("shopping list name", calls[1] and calls[1].list, "Crafting queue")
	T.check("tin: 2 at most 120% of 40c", tinCall and (tinCall.qty .. "/" .. tinCall.max), "2/48")
	for _, c in ipairs(calls) do T.ok("no vendor reagent on the list", c.key ~= "3371") end
	X.ShopAdd = nil
	T.check("no shopping part: nothing sent", X.QueueToShop(), nil)
	X.ShopAdd, X.Owned = shopAdd, owned
	-- the Queue view of the Crafting tab
	X.UI.Open("craft")
	W.advance(0.5)
	local tab = X.UI.tabs.craft.panel
	W.click("Queue (", tab)
	W.advance(0.5)
	local text = W.screen(tab)
	T.ok("queue view: summary", text:find("3 recipes in the queue", 1, true) ~= nil, text)
	T.ok("queue view: vendor line", text:find("Alchemy Supplies:", 1, true) ~= nil, text)
	T.ok("queue view: shopping button hidden without the shopping part", W.findButton("Send to shopping list", tab) == nil or X.ShopAdd ~= nil)
	-- + and - on a row, x takes it out
	local before = X.QueueGet(1).n
	W.click("+", tab)
	W.advance(0.5)
	T.check("+ adds one", X.QueueGet(1).n, before + 1)
	W.click("-", tab)
	W.advance(0.5)
	T.check("- takes one off", X.QueueGet(1).n, before)
	W.click("Recipes", tab)
	W.advance(0.5)
	T.check("back to the recipes view", X.S().craftView, "recipes")
end)

T.scene("queue: craft next only on a click, counts down", function()
	local X = W.start()
	craftWorld(X)
	X.QueueSet(2, "craft", 3)    -- bronze 3 times
	X.QueueSet(3, "restock", 2)  -- potions (alchemy)
	local row, why = X.CraftNextTarget()
	T.ok("no profession window: nothing", row == nil and why:find("Open your profession", 1, true) ~= nil, why)
	W.openProfession("Mining")
	W.advance(2)
	W.give(2840, 2) W.give(3576, 5)
	row, why = X.CraftNextTarget()
	T.check("mining window: bronze next", row and row.rid, 2)
	T.check("as many as the bags allow (2 of 3)", why, 2)
	-- not from a click: the game refuses (the stand-in errors, XNAH says so)
	X.CraftNext()
	T.check("outside a click: nothing crafted", #W.crafted, 0)
	T.ok("outside a click: XNAH says it could not", #W.said("could not start crafting") == 1, W.lastSaid())
	-- the button
	X.UI.Open("craft")
	W.advance(0.5)
	local tab = X.UI.tabs.craft.panel
	W.click("Queue (", tab)
	W.advance(0.5)
	W.craftCasts = true
	W.click("Craft next", tab)
	T.check("one click: one CraftRecipe", #W.crafted, 1)
	T.check("CraftRecipe: bronze x2", W.crafted[1] and (W.crafted[1].rid .. "x" .. W.crafted[1].count), "2x2")
	W.advance(5)
	T.check("two casts done: 1 left", X.QueueGet(2) and X.QueueGet(2).n, 1)
	T.check("the bars made arrived", W.bagCount(2841), 4)
	row, why = X.CraftNextTarget()
	T.ok("no bars left: told so", row == nil and why:find("Not enough reagents", 1, true) ~= nil, why)
	W.give(2840, 1) W.give(3576, 1)
	W.advance(1)
	W.click("Craft next", tab)
	T.check("second click: one more call", #W.crafted, 2)
	W.advance(3)
	T.check("all 3 crafted: out of the queue", X.QueueGet(2), nil)
	T.check("restock row still there", X.QueueGet(3) ~= nil, true)
	-- a linked (someone else's) window: never
	W.closeProfession()
	W.openProfession("Alchemy", true)
	W.advance(2)
	row, why = X.CraftNextTarget()
	T.ok("linked window: not crafted from", row == nil and why:find("someone else", 1, true) ~= nil, why)
end)

T.scene("share: serialize round trip, odd characters, chunks, pace, held, throttled", function()
	local X = W.start()
	local bytes = {}
	for i = 0, 255 do bytes[#bytes + 1] = string.char(i) end
	local odd = table.concat(bytes)
	local t = {a = "x\0y\1z:s5:|n;e", b = 2.5, c = -3, d = true, e = false, [1] = "one", nested = {k = {1, 2, 3}}, big = 1795003200, odd = odd}
	local r = X.Deser(X.Ser(t))
	T.check("round trip: odd string", r and r.a, t.a)
	T.check("round trip: every byte", r and r.odd, odd)
	T.check("round trip: fraction", r and r.b, 2.5)
	T.check("round trip: negative", r and r.c, -3)
	T.check("round trip: true / false", r and (tostring(r.d) .. tostring(r.e)), "truefalse")
	T.check("round trip: number key", r and r[1], "one")
	T.check("round trip: nested", r and r.nested and r.nested.k[3], 3)
	T.check("round trip: big number", r and r.big, 1795003200)
	for _, bad in ipairs({"s99:abc", "t", "n;", "x", "tn1;", "s-1:", "n1;n2;", "", "tn1;s1:", "nabc;"}) do
		T.check("bad text read as nothing: " .. bad, (X.Deser(bad)), nil)
	end
	T.check("escape round trip", X.CommUnescape(X.CommEscape(odd)), odd)
	-- a long message in chunks
	W.inGuild = true
	W.echoGuild = false
	W.advance(1)
	local got, from
	X.commHandlers.T = function(msg, sender) got, from = msg, sender end
	local long = string.rep(odd, 12) -- 3072 bytes
	T.ok("sent", X.CommSend({k = "T", s = long}))
	W.advance(30)
	local n = #W.sent
	T.ok("in many chunks", n >= 13, n)
	local maxLen, zero = 0, false
	for _, m in ipairs(W.sent) do
		if #m.text > maxLen then maxLen = #m.text end
		if m.text:find("\0", 1, true) then zero = true end
	end
	T.ok("no chunk over 255 bytes", maxLen <= 255, maxLen)
	T.ok("no zero byte sent", not zero)
	T.ok("guild channel", W.sent[1] and W.sent[1].channel == "GUILD")
	T.ok("at most 2 a second", n > 1 and (W.sent[n].t - W.sent[1].t) >= (n - 1) * 0.5 - 0.01, W.sent[n].t - W.sent[1].t)
	W.deliver(W.sent, "Ann Smith")
	T.check("put back together", got and got.s, long)
	T.check("sender", from, "Ann Smith")
	-- the game blocks addon messages: held, sent later
	W.addonRestricted = true
	local n0 = #W.sent
	X.CommSend({k = "T", s = "hi"})
	W.advance(10)
	T.check("held while blocked", #W.sent, n0)
	T.ok("blocked is known", X.CommBlocked())
	W.addonRestricted = false
	W.advance(5)
	T.check("sent when allowed", #W.sent, n0 + 1)
	-- too fast: tried again, slower
	W.throttleNext = 2
	X.CommSend({k = "T", s = "again"})
	W.advance(10)
	T.check("sent after the throttle", #W.sent, n0 + 2)
	T.ok("throttle counted", X.commStats.throttled >= 2)
	-- other channels and prefixes are not read
	got = nil
	W.fire("CHAT_MSG_ADDON", "XNAH", "S1:" .. X.Ser({k = "T", s = "raid"}), "RAID", "Bob Stone")
	W.fire("CHAT_MSG_ADDON", "OTHER", "S1:" .. X.Ser({k = "T", s = "other"}), "GUILD", "Bob Stone")
	T.check("raid channel and other prefixes ignored", got, nil)
	W.inGuild = false
	T.check("not in a guild: nothing sent", X.CommSend({k = "T", s = "x"}), false)
end)

T.scene("share: a full share between two guild members", function()
	-- Tor scanned an hour before Ann. Ann's HELLO reaches Tor, Tor asks Ann, Ann answers, Tor takes the newer prices.
	-- One client at a time runs: each step's messages are kept and handed to the next one.
	W.reset()
	W.inGuild = true
	W.player, W.surname = "Tor", "Jones"
	local X = W.login()
	W.list(2589, 50, 20, 5) W.list(2592, 80, 20, 3)
	W.openAH() T.ok("Tor: full scan", T.fullScan(X)) W.closeAH()
	W.advance(40)
	local torScan = X.MyFullScan()
	T.ok("Tor: HELLO sent", #sentOf(X, "H") >= 1)
	T.check("Tor: own echo is not a peer", X.ShareState().peers, 0)
	local savedTor = W.saveText(W.env.XNAHDB)

	-- Ann, an hour later
	local t1 = W.NOW
	W.reset()
	W.NOW = t1 + 3600
	W.inGuild = true
	W.player, W.surname = "Ann", "Smith"
	X = W.login()
	W.list(2589, 60, 20, 5) W.list(2592, 90, 20, 3) W.list(15210, 50000, 1, 2, "Cid", -19) W.list(2996, 150, 20, 3)
	W.openAH() T.ok("Ann: full scan", T.fullScan(X)) W.closeAH()
	W.advance(40)
	local hellos = sentOf(X, "H")
	local hello = hellos[#hellos]
	T.ok("Ann: HELLO with her scan", hello and hello.d.f == X.MyFullScan(), hello and hello.d)
	local annId = X.shareId
	local savedAnn = W.saveText(W.env.XNAHDB)

	-- Tor hears Ann
	local t2 = W.NOW
	W.reset()
	W.NOW = t2 + 10
	W.inGuild = true
	W.player, W.surname = "Tor", "Jones"
	X = W.login(savedTor)
	W.deliver({hello.m}, "Ann Smith")
	W.advance(5)
	local st = X.ShareState()
	T.check("Tor: one guild member seen", st.peers, 1)
	T.check("Tor: her name", st.names[1], "Ann Smith")
	local wants = sentOf(X, "W")
	T.check("Tor: asks once", #wants, 1)
	T.check("Tor: asks Ann", wants[1] and wants[1].d.to, annId)
	T.check("Tor: for prices newer than his scan", wants[1] and wants[1].d.s, torScan)
	local savedTor2 = W.saveText(W.env.XNAHDB)

	-- Ann answers
	local t3 = W.NOW
	W.reset()
	W.NOW = t3 + 1
	W.inGuild = true
	W.player, W.surname = "Ann", "Smith"
	X = W.login(savedAnn)
	W.deliver({wants[1].m}, "Tor Jones")
	W.advance(20)
	local rowsMsgs, ends = sentOf(X, "R"), sentOf(X, "E")
	T.check("Ann: one END", #ends, 1)
	T.check("Ann: 4 prices", ends[1] and ends[1].d.n, 4)
	local rowCount = 0
	for _, m in ipairs(rowsMsgs) do for _ in m.d.d:gmatch("[^;]+") do rowCount = rowCount + 1 end end
	T.check("Ann: 4 rows in the messages", rowCount, 4)
	T.ok("Ann: last sent noted", X.ShareState().lastSent ~= nil)
	local answer = {}
	for _, m in ipairs(rowsMsgs) do answer[#answer + 1] = m.m end
	answer[#answer + 1] = ends[1].m
	-- a second WANT while nothing is newer: still one answer each, no doubling
	W.deliver({wants[1].m}, "Tor Jones")
	W.advance(20)
	T.check("Ann: answers a second WANT once", #sentOf(X, "E"), 2)

	-- Tor gets the answer
	local t4 = W.NOW
	W.reset()
	W.NOW = t4 + 1
	W.inGuild = true
	W.player, W.surname = "Tor", "Jones"
	X = W.login(savedTor2)
	W.deliver({hello.m}, "Ann Smith")
	W.advance(5)
	T.check("Tor: asks again after his reload", #sentOf(X, "W"), 1)
	W.deliver(answer, "Ann Smith")
	W.advance(3)
	local items = X.Items()
	T.check("Tor: Linen at Ann's price", items["2589"] and items["2589"].cur.min, 60)
	T.check("Tor: Wool at Ann's price", items["2592"] and items["2592"].cur.min, 90)
	T.check("Tor: the Bear sword (suffix key)", items["15210:-19"] and items["15210:-19"].cur.min, 50000)
	T.check("Tor: Bolt of Linen, new to him", items["2996"] and items["2996"].cur.qty, 60)
	T.check("Tor: 2 Linen prices in the history", #X.History("2589"), 2)
	st = X.ShareState()
	T.check("Tor: 4 prices received", st.got, 4)
	T.ok("Tor: last received noted", st.lastGot ~= nil)
	T.ok("Tor: told in chat", #W.said("received 4 guild prices (from Ann Smith)") == 1, W.lastSaid())
	T.check("Tor: now as new as Ann", X.Realm().sharedFull, hello.d.f)
	-- the same again: nothing newer, nothing taken
	W.deliver(answer, "Ann Smith")
	W.advance(3)
	T.check("Tor: the same prices again are not taken", X.ShareState().got, 4)
	-- Ann's HELLO again: Tor is up to date, does not ask
	local before = #sentOf(X, "W")
	W.deliver({hello.m}, "Ann Smith")
	W.advance(5)
	T.check("Tor: up to date, no new WANT", #sentOf(X, "W"), before)
	-- the Scan tab shows it
	X.UI.Open("scan")
	W.advance(0.5)
	local text = W.screen(X.UI.tabs.scan.panel)
	T.ok("scan tab: prices received", text:find("Prices received: 4", 1, true) ~= nil, text)
	T.ok("scan tab: Ann listed", text:find("Ann Smith", 1, true) ~= nil, text)
end)

T.scene("share: the newest scan answers, ties by name, a silent one is skipped", function()
	local X = W.start()
	W.inGuild = true
	W.advance(31)
	local now = X.Now()
	local realm = X.realmKey
	inject(X, {k = "H", r = realm, c = "zzzzzz", f = now - 600, v = "1"}, "Zed Last")
	inject(X, {k = "H", r = realm, c = "bbbbbb", f = now - 600, v = "1"}, "Bea First")
	W.advance(4)
	local wants = sentOf(X, "W")
	T.check("one WANT", #wants, 1)
	T.check("same scan time: the first name is asked", wants[1] and wants[1].d.to, "bbbbbb")
	inject(X, {k = "H", r = realm, c = "cccccc", f = now - 60, v = "1"}, "Cal Newer")
	W.advance(4)
	T.check("while waiting for an answer: no second WANT", #sentOf(X, "W"), 1)
	W.advance(45)
	wants = sentOf(X, "W")
	T.check("no answer in time: the next one is asked", #wants, 2)
	T.check("... the newest scan", wants[2] and wants[2].d.to, "cccccc")
	T.ok("guild members counted", X.ShareState().peers == 3, X.ShareState().peers)
end)

T.scene("share: bad messages are ignored", function()
	local X = W.start()
	W.inGuild = true
	W.advance(31)
	local now = X.Now()
	local realm = X.realmKey
	X.Record("2589", now - 3600, 50, 50, 10, 1, "Linen Cloth", 1)
	local b36 = X.b36
	local function R(d, extra)
		local m = {k = "R", r = realm, c = "eeeeee", b = now - 100, d = d}
		for k, v in pairs(extra or {}) do m[k] = v end
		inject(X, m)
	end
	R("2589,0,1,1,5", {r = "Other-Alliance"})
	T.check("other realm: not taken", X.Items()["2589"].cur.min, 50)
	R("abc,0,1,1,5;12:3:4,0,1,1,5;-5,0,1,1,5;" .. string.rep("9", 30) .. ",0,1,1,5")
	T.check("bad keys: nothing new", T.count(X.Items()), 1)
	R("2589,a," .. b36(1e12) .. ",1,5")
	T.check("a price out of range: not taken", X.Items()["2589"].cur.min, 50)
	R("2589,a,1,1,5", {b = now + 86400})
	T.check("a time in the future: not taken", X.Items()["2589"].cur.min, 50)
	R("2589,a,1,1,5", {c = X.shareId})
	T.check("my own message: not taken", X.Items()["2589"].cur.min, 50)
	R("2589,a,1,1,5", {c = "EVIL!"})
	T.check("a bad client id: not taken", X.Items()["2589"].cur.min, 50)
	R("2589,a,1,1,5,6,7;2589,A,1,1,5;2589,a,1.5,1,5")
	T.check("bad rows: not taken", X.Items()["2589"].cur.min, 50)
	R({"not text"})
	R(string.rep("2589,a,1,1,5;", 400))
	T.check("rows not text / too long: not taken", X.Items()["2589"].cur.min, 50)
	W.fire("CHAT_MSG_ADDON", "XNAH", "S1:n5;", "GUILD", "Evil Guy")
	W.fire("CHAT_MSG_ADDON", "XNAH", "S1:t s3", "GUILD", "Evil Guy")
	W.fire("CHAT_MSG_ADDON", "XNAH", "hello", "GUILD", "Evil Guy")
	W.fire("CHAT_MSG_ADDON", "XNAH", "S1:" .. X.Ser({k = "R", r = realm, c = "eeeeee", b = now - 100, d = "2589,a,1,1,5"}), "WHISPER", "Evil Guy")
	W.fire("CHAT_MSG_ADDON", "XNAH", "Sabcdefgh:" .. X.Ser({k = "R", r = realm, c = "eeeeee", b = now - 100, d = "2589,a,1,1,5"}), "GUILD", "Evil Guy")
	inject(X, {k = "X", r = realm, c = "eeeeee"})
	T.check("garbage, whispers, odd ids, unknown kinds: nothing", X.Items()["2589"].cur.min, 50)
	-- a HELLO from the future, a WANT for someone else
	inject(X, {k = "H", r = realm, c = "ffffff", f = now + 86400})
	T.check("a HELLO from the future: not a peer", X.ShareState().peers, 0)
	local n0 = #W.sent
	inject(X, {k = "W", r = realm, c = "aaaaaa", to = "zzzzzz", s = 0})
	W.advance(10)
	T.check("a WANT for someone else: no answer", #sentOf(X, "R", n0 + 1) + #sentOf(X, "E", n0 + 1), 0)
	-- a good row is taken; an older one is not
	R("2589," .. b36(100) .. ",7,8,9")
	T.check("a good row: taken", X.Items()["2589"].cur.min, 7)
	T.check("a good row: quantity", X.Items()["2589"].cur.qty, 9)
	R("2589,0,3,3,3", {b = now - 7200})
	T.check("an older row: not taken", X.Items()["2589"].cur.min, 7)
	R("2592,0,,,0")
	T.check("a sold-out row (no price): taken", X.Items()["2592"] and X.Items()["2592"].cur.qty, 0)
	-- sharing off: nothing taken
	X.SetShare(false)
	R("2589," .. b36(200) .. ",5,5,5")
	T.check("sharing off: not taken", X.Items()["2589"].cur.min, 7)
	n0 = #W.sent
	inject(X, {k = "W", r = realm, c = "aaaaaa", to = X.shareId, s = 0})
	W.advance(10)
	T.check("sharing off: nothing sent", #W.sent, n0)
end)

T.scene("share: export prices as text", function()
	local X = W.start()
	W.items[900099] = {name = 'Odd, "Quoted" Thing', quality = 1, sell = 1, stack = 20}
	W.list(2589, 50, 20, 5)
	W.list(15210, 50000, 1, 2, "Cid", -19)
	W.list(900099, 100, 20, 1)
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	X.Record("2592", X.Now() - 5 * 86400, 80, 80, 10, 1, "Wool Cloth", 1) -- seen 5 days ago: left out
	local text, shown, total
	X.ExportPrices(function(a, b, c) text, shown, total = a, b, c end)
	W.advance(1)
	T.ok("export ready", text ~= nil)
	text = text or ""
	local lines = {}
	for l in text:gmatch("[^\n]+") do lines[#lines + 1] = l end
	T.check("header", lines[1], "itemID,suffix,name,lowest,market,listed,avg7,avg30,seen")
	T.check("3 items + the header", #lines, 4)
	T.check("counts", tostring(shown) .. "/" .. tostring(total), "3/3")
	T.ok("Linen line", text:find("\n2589,,Linen Cloth,50,50,100,50,50,2026-", 1, true) ~= nil, text)
	T.ok("suffix line", text:find("\n15210,-19,Raider Shortsword of the Bear,50000,50000,2,", 1, true) ~= nil, text)
	T.ok("a name with a comma and quotes is quoted", text:find('900099,,"Odd, ""Quoted"" Thing",100,100,20,', 1, true) ~= nil, text)
	T.ok("old item left out", text:find("2592", 1, true) == nil)
	-- the cap
	X.EXPORT_CAP = 2
	X.ExportPrices(function(a, b, c) text, shown, total = a, b, c end)
	W.advance(1)
	X.EXPORT_CAP = 5000
	T.check("capped: shown / total", tostring(shown) .. "/" .. tostring(total), "2/3")
	local n = 0
	for _ in text:gmatch("[^\n]+") do n = n + 1 end
	T.check("capped: 2 lines + the header", n, 3)
	-- the button on the Scan tab
	X.UI.Open("scan")
	W.advance(0.5)
	W.click("Export prices", X.UI.tabs.scan.panel)
	W.advance(1)
	local d = W.env.XNAHDialog
	T.ok("export dialog shown", d and d.shown)
	T.ok("export dialog title", d and W.plain(d.title.text):find("Prices: 3 items", 1, true) ~= nil, d and d.title.text)
end)
