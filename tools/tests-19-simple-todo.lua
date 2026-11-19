-- XNAH test scenes, part 19: the To do page of the simple window (SimpleTodo.lua) - ranking, every kind of job, the
-- buttons, the empty page. The Buy and Sell pages' entries (SimpleTrade.lua, another helper's) are stood in for here,
-- and used as they are when that file provides them.

local function todo(X)
	local S = X.Simple
	S.Open("todo")
	W.advance(0.5)
	S.Refresh()
	return S.list.items, S
end
local function ids(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.id end
	return table.concat(out, ",")
end
local function find(list, id)
	for i, e in ipairs(list) do if e.id == id then return e, i end end
	return nil
end
local function pick(S, id)
	for i, e in ipairs(S.list.items) do
		if e.id == id then
			local row = S.list.rows[i - S.list.offset]
			if row then row:Click() end
			return e
		end
	end
end
-- stand-in Buy / Sell entries: n entries with profits from `base` down
local function stubTrade(prefix, n, base)
	return function(limit)
		local out = {}
		for i = 1, math.min(n, limit or n) do
			out[i] = {id = prefix .. i, key = "2589", title = prefix .. " " .. i, sub = "+" .. (base - i), profit = (base - i) * 10000,
				sentence = "Do " .. prefix .. i, why = "test", button = {label = prefix .. " now", run = function() end}}
		end
		return out
	end
end
-- the Transmute: Undeath to Water recipe known, its reagent and result priced (cost 1g, sells for 5g)
local function transmute(X)
	X.db.known = X.db.known or {}
	X.db.known[X.CharKey()] = {[17563] = true}
	X.Record("12808", X.Now(), 10000, 10000, 30, 3, "Essence of Undeath", 1)
	X.Record("7080", X.Now(), 50000, 50000, 10, 2, "Essence of Water", 1)
end

T.scene("simple todo: the empty page, then Scan now", function()
	local X = W.start()
	W.advance(5)
	local list, S = todo(X)
	T.check("To do is the first page", S.order[1], "todo")
	T.check("nothing listed with no prices and the auction house closed", #list, 0)
	T.ok("the empty line says what XNAH needs", (S.list.empty:GetText() or ""):find("Do a full scan at the auction house", 1, true) ~= nil,
		S.list.empty:GetText())
	-- the auction house open: a Scan now entry
	W.makeMarket(5, 20, {uncached = 0})
	W.openAH()
	list = todo(X)
	local e = find(list, "todo:scan")
	T.ok("auction house open: the scan entry", e ~= nil, ids(list))
	T.check("its button", e and e.button and e.button.label, "Scan now")
	T.check("no graph for it", e and e.graph, false)
	T.ok("it has an icon", e and e.icon ~= nil)
	T.check("it is picked first", S.detail.entry and S.detail.entry.id, "todo:scan")
	S.detail.button:Click()
	T.ok("the big button started the scan", X.scan.state ~= "idle")
	W.waitFor(function() return X.scan.state == "idle" end, 300)
	-- the server's waiting time: a button that cannot be pressed yet... and fresh prices: no scan entry at all
	list = todo(X)
	T.check("fresh prices: no scan entry", find(list, "todo:scan"), nil)
	W.closeAH()
	list = todo(X)
	T.check("nothing to do", #list, 0)
	T.ok("a friendly line", (S.list.empty:GetText() or ""):find("Nothing to do right now", 1, true) ~= nil, S.list.empty:GetText())
	-- old prices (4 days) with the auction house open but the scan not allowed yet: a disabled button
	X.Realm().lastFull = X.Now() - 4 * 86400
	list = todo(X)
	T.check("prices too old, auction house closed: the empty line", #list, 0)
	T.ok("it says the prices are too old", (S.list.empty:GetText() or ""):find("too old", 1, true) ~= nil, S.list.empty:GetText())
	W.openAH()
	X.Realm().lastFull = X.Now() - 4 * 86400
	list = todo(X)
	e = find(list, "todo:scan")
	T.check("old prices, auction house open: Scan now", e and e.button and e.button.label, "Scan now")
	X.Realm().lastFull = X.Now() - 60
	X.S().staleHours = 0 -- stale at once, but the server waits
	list = todo(X)
	e = find(list, "todo:scan")
	T.ok("server waits: a disabled button", e and e.button and e.button.disabled == true, e and e.button and e.button.label)
	X.S().staleHours = 72
end)

T.scene("simple todo: ranking - buys, sells and jobs by the gold they bring", function()
	local X = W.start()
	W.advance(5)
	X.Realm().lastFull = X.Now()
	X.Record("2589", X.Now(), 50, 50, 60, 3, "Linen Cloth", 1)
	local S = X.Simple
	S.BuyEntries = stubTrade("buy", 6, 50) -- 49g, 48g, ... 44g
	S.SellEntries = stubTrade("sell", 6, 30) -- 29g ... 24g
	-- 45g waiting in the mailbox
	W.addMail({sender = "Auction House", subject = "Auction successful: Linen Cloth", money = 450000})
	W.openMail()
	W.closeMail()
	local list = todo(X)
	local buys, sells = 0, 0
	for _, e in ipairs(list) do
		if e.id:find("^buy") then buys = buys + 1 end
		if e.id:find("^sell") then sells = sells + 1 end
	end
	T.check("the best 4 buys", buys, 4)
	T.check("the best 4 sells", sells, 4)
	T.check("first: the best buy (49g)", list[1] and list[1].id, "buy1")
	local _, mailAt = find(list, "todo:mail")
	local _, buy4 = find(list, "buy4")
	local _, sell1 = find(list, "sell1")
	T.ok("the mail (45g) comes after the 4th buy (46g)", mailAt and buy4 and mailAt > buy4, ids(list))
	T.ok("the mail (45g) comes before the best sell (29g)", mailAt and sell1 and mailAt < sell1, ids(list))
	T.ok("at most 12", #list <= 12, #list)
	T.check("the buy entries are not changed", S.BuyEntries(1)[1].value, nil)
	-- the scan is urgent: first, before every buy
	X.Realm().lastFull = nil
	list = todo(X)
	T.check("no prices: the scan first", list[1] and list[1].id, "todo:scan")
	-- an old scan (30 hours, not too old): last
	X.Realm().lastFull = X.Now() - 30 * 3600
	list = todo(X)
	T.check("old scan: last", list[#list] and list[#list].id, "todo:scan")
	-- the big button of a buy entry runs R's flow
	local ran = 0
	S.BuyEntries = function()
		return {{id = "buyX", key = "2589", title = "Buy Linen", profit = 999999999, button = {label = "Buy 5", run = function() ran = ran + 1 end}}}
	end
	list = todo(X)
	T.check("a buy entry on top", S.detail.entry and S.detail.entry.id, "buyX")
	S.detail.button:Click()
	T.check("its button runs", ran, 1)
	-- the Buy and Sell pages missing: the home page's trade jobs open the full window instead
	S.BuyEntries, S.SellEntries = nil, nil
	local deals = 0
	list = todo(X)
	for _, e in ipairs(list) do if e.id:find("^todo:home:") then deals = deals + 1 end end
	T.ok("without the Buy and Sell pages: still a list", #list >= 1, ids(list))
end)

T.scene("simple todo: mail, expired auctions, cooldown crafts, the queue, checking auctions", function()
	local X = W.start()
	W.advance(5)
	X.Realm().lastFull = X.Now()
	-- mail: gold and an expired auction
	W.addMail(W.mailSold(2589, 30000, 20, "Ann Lee", 1500))
	local m = W.addMail(W.mailExpired(2840, 4))
	W.openMail()
	local list, S = todo(X)
	local e = find(list, "todo:mail")
	T.ok("mail: an entry", e ~= nil, ids(list))
	T.ok("mail: title starts with a verb", e and e.title:find("^Collect") ~= nil, e and e.title)
	T.ok("mail: says the gold", e and W.plain(e.sub):find("2g 85s", 1, true) ~= nil, e and W.plain(e.sub))
	T.ok("mail: says an expired auction is in it", e and e.why:find("expired", 1, true) ~= nil, e and e.why)
	T.check("mail: no graph", e and e.graph, false)
	T.ok("mail: the letter icon", e and e.icon and e.icon:find("INV_Letter", 1, true) ~= nil)
	-- the mail taken: the expired item back in the bags
	W.takeMail(m)
	for i = #W.mail, 1, -1 do W.takeMail(W.mail[i]) end
	W.fill(0, {{2840, 4}})
	W.bagsChanged()
	W.advance(2)
	W.closeMail()
	X.Record("2840", X.Now(), 300, 300, 40, 4, "Copper Bar", 1)
	list = todo(X)
	T.check("mail taken: no mail entry", find(list, "todo:mail"), nil)
	-- the Sell page lists the expired Copper Bar as a Post entry (post:2840); without it, a To do entry of its own
	e = find(list, "todo:expired") or find(list, "post:2840")
	T.ok("expired in the bags: an entry", e ~= nil, ids(list))
	T.ok("expired: title starts with a verb", e and (e.title:find("^Post") or e.title:find("^Sell")) ~= nil, e and e.title)
	if e and e.id == "todo:expired" then
		pick(S, "todo:expired")
		S.detail.button:Click()
		W.advance(0.5)
		T.ok("expired: its button opens the Sell page (or the full window)", (S.views.sell and S.Frame():IsShown()) or
			(X.UI.Frame() and X.UI.Frame():IsShown()))
	end
	if X.UI.Frame() then X.UI.Frame():Hide() end
	-- a cooldown craft worth doing
	transmute(X)
	list = todo(X)
	local cid = "todo:cd:" .. X.CharKey() .. "|17563"
	e = find(list, cid)
	T.ok("cooldown craft: an entry", e ~= nil, ids(list))
	T.check("cooldown craft: its title", e and e.title, "Transmute: Undeath to Water")
	T.ok("cooldown craft: its profit in the sub line", e and W.plain(e.sub):find("+3g 75s", 1, true) ~= nil, e and W.plain(e.sub))
	T.ok("cooldown craft: why says XNAH cannot always see the waiting time", e and e.why:find("cannot always see", 1, true) ~= nil)
	T.check("cooldown craft: the button", e and e.button and e.button.label, "Done")
	pick(S, cid)
	S.detail.button:Click()
	W.advance(0.5)
	list = todo(X)
	T.check("Done: gone", find(list, cid), nil)
	W.advance(22 * 3600)
	list = todo(X)
	T.check("22 hours later: still gone", find(list, cid), nil)
	W.advance(2 * 3600)
	X.Record("12808", X.Now(), 10000, 10000, 30, 3, "Essence of Undeath", 1)
	X.Record("7080", X.Now(), 50000, 50000, 10, 2, "Essence of Water", 1)
	X.Realm().lastFull = X.Now()
	list = todo(X)
	T.ok("23 hours: back", find(list, cid) ~= nil, ids(list))
	-- a craft seen in the game marks it done too
	W.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 17563)
	list = todo(X)
	T.check("crafted: gone", find(list, cid), nil)
	-- an alt that knows it: its own entry
	X.db.known["Alt Twink"] = {[17563] = true}
	list = todo(X)
	e = find(list, "todo:cd:Alt Twink|17563")
	T.ok("an alt's cooldown craft", e and e.sentence:find("Log in on Alt Twink", 1, true) ~= nil, e and e.sentence)
	-- not worth it (reagent dearer than the result): not listed
	X.Record("12808", X.Now(), 90000, 90000, 30, 3, "Essence of Undeath", 1)
	X.Fire("XNAH_PRICES") -- as after a scan (crafting costs are worked out again)
	list = todo(X)
	T.check("no profit: not listed", find(list, "todo:cd:Alt Twink|17563"), nil)
	-- the crafting queue with materials to buy
	W.recipes = {[1] = {name = "Smelt Copper", out = 2840, reagents = {{2770, 1}}, learned = true, prof = "Mining"}}
	W.openProfession("Mining")
	W.advance(2)
	W.closeProfession()
	X.Record("2770", X.Now(), 50, 50, 40, 4, "Copper Ore", 1)
	X.QueueSet(1, "craft", 3)
	list = todo(X)
	e = find(list, "todo:queue")
	T.ok("queue: an entry", e ~= nil, ids(list))
	T.ok("queue: 3 crafts", e and W.plain(e.sub):find("3 crafts", 1, true) ~= nil, e and W.plain(e.sub))
	T.check("queue: materials to buy - the button", e and e.button and e.button.label, "Put materials on a list")
	pick(S, "todo:queue")
	S.detail.button:Click()
	W.advance(0.5)
	local shop = X.ShopList and X.ShopList(X.QUEUE_LIST or "Crafting queue")
	T.ok("queue: the materials are on a shopping list", shop and #shop.items >= 1)
	-- your auctions, the auction house open: Check
	W.openAH()
	X.InventoryMe().auctions = {["2589"] = 5}
	local checks = 0
	X.CancelScan = function() checks = checks + 1 return true end
	list = todo(X)
	e = find(list, "todo:check")
	T.ok("auctions: a Check entry", e ~= nil, ids(list))
	pick(S, "todo:check")
	local before = checks -- the Sell page may already have checked by itself (the window is open on To do)
	S.detail.button:Click()
	T.check("Check runs the cancel scan", checks, before + 1)
	-- every entry: a title, a sentence, an icon or an item
	for _, x in ipairs(todo(X)) do
		T.ok(x.id .. ": title", x.title and x.title ~= "")
		T.ok(x.id .. ": short title", #W.plain(x.title) <= 34, x.title)
		T.ok(x.id .. ": a sentence", x.sentence and x.sentence ~= "")
		T.ok(x.id .. ": an icon or an item", x.icon or x.key)
	end
end)

T.scene("simple todo: with the real Buy and Sell pages", function()
	local X = W.start()
	W.advance(5)
	local S = X.Simple
	if not (S.BuyEntries or S.SellEntries) then
		T.note("simple todo: SimpleTrade.lua gives no S.BuyEntries / S.SellEntries yet - stand-ins only")
		return
	end
	W.makeMarket(11, 40, {lastDay = 6, uncached = 0})
	W.openAH()
	for day = 0, 6 do
		if day > 0 then W.advance(86400) end
		W.marketDay(day, 6)
		T.fullScan(X)
	end
	W.fill(0, {{2589, 20}, {2592, 20}})
	W.bagsChanged()
	local list = todo(X)
	local top = {}
	for _, fn in ipairs({S.BuyEntries, S.SellEntries}) do
		if fn then
			local l = fn(4)
			if l[1] then top[#top + 1] = l[1].id end
		end
	end
	for _, id in ipairs(top) do T.ok("the best of a page is on To do: " .. id, find(list, id) ~= nil, ids(list)) end
	T.ok("at most 12", #list <= 12)
	T.note("simple todo: " .. #list .. " entries with the real pages (" .. ids(list) .. ")")
end)
