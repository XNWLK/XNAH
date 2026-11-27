-- XNAH test scenes, part 37: the two new pages of the Your gold view - "Gold over time" (UIGoldHistory.lua, the gold
-- history per character in Inventory.lua) and "Your items" (UIGoldItems.lua, time to sell and sell-through from
-- Ledger.lua: your postings seen in your auctions list, matched with the sale / expired / cancelled mails).
-- Run alone: node tools/test.js 37

local DAY, H = 86400, 3600
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function L(X) return X.Ledger() end

-- the mail functions that take, return, delete or open a mail: counted (XNAH must never call them)
local MAIL_ACTIONS = {"TakeInboxMoney", "TakeInboxItem", "AutoLootMailItem", "DeleteInboxItem", "ReturnInboxItem",
	"GetInboxText", "InboxItemCanDelete", "CheckInbox"}
local function spyMail()
	local calls = {}
	for _, name in ipairs(MAIL_ACTIONS) do
		W.env[name] = function() calls[#calls + 1] = name end
	end
	return calls
end

-- opens a view (and a page of the Your gold view by its button)
local function openGold(X, page)
	if not X.UI.Frame() or not X.UI.Frame():IsShown() then X.UI.Toggle() end
	X.UI.Open("gold")
	W.advance(1)
	local p = X.UI.tabs.gold.panel
	if page then
		W.click(page, p)
		W.advance(0.5)
	end
	return p
end

-- an auction of yours put up now (the game tells it was created), then your auctions list arrives
local function post(X, id, unit, count)
	local a = W.mine(id, unit, count)
	W.fire("AUCTION_HOUSE_AUCTION_CREATED", a.id)
	W.advance(4) -- XNAH asks for your auctions a moment later
	return a
end

T.scene("37 gold pages: expired and cancelled mails counted once, never taken, never opened", function()
	local X = W.start()
	W.advance(5)
	local calls = spyMail()
	W.addMail(W.mailExpired(2770, 5))
	W.addMail(W.mailExpired(2770, 5))
	W.addMail(W.mailCancelled(3576, 2))
	W.addMail(W.mailSold(2589, 1000, 10, "Ann Lee", 50))
	for _ = 1, 3 do
		W.openMail()
		W.fire("MAIL_INBOX_UPDATE")
		W.advance(2)
		W.closeMail()
		W.advance(600)
	end
	T.check("two expired (two equal mails at once both count)", #L(X).expired, 2)
	T.check("one cancelled", #L(X).cancelled, 1)
	T.check("one sale", #L(X).sales, 1)
	X = W.reload()
	W.advance(5)
	calls = spyMail()
	W.openMail()
	W.advance(2)
	T.check("after a reload: still two expired", #L(X).expired, 2)
	T.check("after a reload: still one cancelled", #L(X).cancelled, 1)
	T.check("every mail still in the mailbox", #W.mail, 4)
	local read = 0
	for _, m in ipairs(W.mail) do if m.read then read = read + 1 end end
	T.check("no mail marked as read", read, 0)
	T.check("no mail taken, returned, deleted or opened", table.concat(calls, ","), "")
	local li = X.LedgerItem("2770")
	T.check("expired units", li and li.expired, 10)
	T.check("sell-through of an item that only expired", li and li.sellThrough, 0)
end)

T.scene("37 gold pages: posting times and price matching", function()
	local X = W.start()
	W.advance(5)
	local now = 1800000000
	local t, late = X.LedgerPostTime(now, 86400)
	T.check("24 hours left: put up now", t, now)
	T.check("24 hours left: exact", late, nil)
	t, late = X.LedgerPostTime(now, 50000)
	T.check("over 8 hours left: a 24 hour auction", t, now - 36400)
	T.check("over 8 hours left: exact", late, nil)
	t, late = X.LedgerPostTime(now, 20000)
	T.check("5.5 hours left: at the latest 8800 s ago", t, now - 8800)
	T.check("5.5 hours left: a guess", late, true)
	t, late = X.LedgerPostTime(now, 3000)
	T.check("50 minutes left: at the latest 70 minutes ago", t, now - 4200)
	T.check("50 minutes left: a guess", late, true)
	t, late = X.LedgerPostTime(now, nil)
	T.check("no seconds: now", t, now)
	T.check("no seconds: a guess", late, true)
	-- the same item posted twice at two prices: a sale at the second price takes the second posting
	local Lg = L(X)
	Lg.posts = {
		{t = now - 5 * H, k = "2589", q = 10, n = 10, c = "Xn Ascalon", id = 901, p = 100},
		{t = now - 2 * H, k = "2589", q = 10, n = 10, c = "Xn Ascalon", id = 902, p = 150},
		{t = now - 6 * H, k = "2589", q = 10, n = 10, c = "Someone Else", id = 903, p = 150},
	}
	local e = {t = now, key = "2589", count = 4, money = 600, char = "Xn Ascalon"}
	X.LedgerMatchPosts("sale", e)
	T.check("price match: second posting", Lg.posts[2].n, 6)
	T.check("price match: first posting untouched", Lg.posts[1].n, 10)
	T.check("another character's posting untouched", Lg.posts[3].n, 10)
	T.check("time to sell of the sale", e.tts, 2 * H)
	T.check("units matched", e.ttsN, 4)
	-- a sale at no posting's price: the oldest first, spilling over to the next one
	e = {t = now, key = "2589", count = 12, money = 12 * 120, char = "Xn Ascalon"}
	X.LedgerMatchPosts("sale", e)
	T.check("oldest first: first posting used up", Lg.posts[1].n, 0)
	T.check("then the second", Lg.posts[2].n, 4)
	T.check("time: 10 units of 5 hours and 2 of 2 hours", e.tts, X.Round((10 * 5 * H + 2 * 2 * H) / 12))
	-- an expired mail takes units but gets no time to sell
	e = {t = now, key = "2589", count = 4, char = "Xn Ascalon"}
	X.LedgerMatchPosts("expired", e)
	T.check("expired takes the rest", Lg.posts[2].n, 0)
	T.check("expired: no time to sell", e.tts, nil)
	-- nothing left: a sale stays without a time
	e = {t = now, key = "2589", count = 1, money = 100, char = "Xn Ascalon"}
	X.LedgerMatchPosts("sale", e)
	T.check("nothing left to match", e.tts, nil)
	-- a posting made after the mail came does not count
	Lg.posts = {{t = now + 2 * H, k = "2589", q = 5, n = 5, c = "Xn Ascalon", id = 904, p = 100}}
	e = {t = now, key = "2589", count = 1, money = 100, char = "Xn Ascalon"}
	X.LedgerMatchPosts("sale", e)
	T.check("a later posting is not used", Lg.posts[1].n, 5)
end)

T.scene("37 gold pages: time to sell and sell-through from postings and mails", function()
	local X = W.start()
	W.advance(5)
	W.openAH()
	-- put up now (the game tells it): exact
	local linen = post(X, 2589, 100, 20)
	local Lg = L(X)
	T.check("one posting noted", Lg.posts and #Lg.posts, 1)
	local p1 = Lg.posts and Lg.posts[1] or {}
	T.check("posting: item", p1.k, "2589")
	T.check("posting: count", p1.q, 20)
	T.check("posting: exact time", p1.late, nil)
	T.near("posting: when", p1.t, X.Now() - 3, 1)
	T.ok("counting started", Lg.postsSince ~= nil)
	-- an auction XNAH sees only an hour after it went up, 23 hours left: a 24 hour one, exact
	local wool = W.mine(2592, 300, 5)
	wool.posted = W.NOW - H
	-- one with 2 hours, put up 30 minutes ago: only "at the latest"
	local copper = W.mine(2770, 50, 5)
	copper.seconds, copper.posted = 7200, W.NOW - 1800
	local tin = W.mine(3576, 80, 4)
	W.ownedChanged()
	W.advance(1)
	T.check("four postings", #Lg.posts, 4)
	local byKey = {}
	for _, p in ipairs(Lg.posts) do byKey[p.k] = p end
	T.near("wool: put up an hour ago", byKey["2592"] and byKey["2592"].t, X.Now() - 1 - H, 2)
	T.check("wool: exact (over 8 hours left)", byKey["2592"] and byKey["2592"].late, nil)
	T.check("copper: a guess", byKey["2770"] and byKey["2770"].late, true)
	-- the list again and again: nothing doubled
	for _ = 1, 3 do W.ownedChanged() end
	W.env.C_AuctionHouse.QueryOwnedAuctions({})
	W.advance(1)
	T.check("seen again: still four", #Lg.posts, 4)
	-- two hours later half the Linen sells, an hour after that the rest
	W.advance(2 * H)
	W.closeAH()
	W.addMail(W.mailSold(2589, 1000, 10, "Ann Lee", 50))
	W.openMail()
	W.advance(H)
	W.addMail(W.mailSold(2589, 1000, 10, "Bob Stone", 50))
	W.addMail(W.mailSold(2592, 1500, 5, "Cid Moss", 75))
	W.addMail(W.mailSold(2770, 250, 5, "Dee Fox", 12))
	W.addMail(W.mailExpired(3576, 4))
	W.advance(2)
	W.addMail(W.mailSold(3576, 160, 2, "Eve Oak", 8)) -- put up again while XNAH did not see it: no time
	W.advance(2)
	local li = X.LedgerItem("2589")
	T.near("linen: average time to sell (2 and 3 hours)", li and li.timeToSell, 2.5 * H, 30)
	T.check("linen: units with a time", li and li.ttsUnits, 20)
	T.check("linen: not a guess", li and li.ttsAtLeast, nil)
	T.near("linen: sell-through 100%", li and li.sellThrough, 1, 0.001)
	T.near("linen: profit each (nothing bought)", li and li.profitEach, 95, 0.01)
	li = X.LedgerItem("2592")
	T.near("wool: 4 hours (seen an hour after it went up)", li and li.timeToSell, 4 * H, 30)
	li = X.LedgerItem("2770")
	T.ok("copper: a time", li and li.timeToSell ~= nil)
	T.check("copper: at least (seen only later)", li and li.ttsAtLeast, true)
	li = X.LedgerItem("3576")
	T.check("tin: expired took the posting, the later sale has no time", li and li.timeToSell, nil)
	T.near("tin: sell-through 2 of 6", li and li.sellThrough, 2 / 6, 0.001)
	T.check("tin: posted", li and li.posted, 6)
	-- read again, reloaded: no double counting
	local sales = #L(X).sales
	X = W.reload()
	W.advance(5)
	W.openMail()
	W.advance(2)
	T.check("after a reload: same sales", #L(X).sales, sales)
	li = X.LedgerItem("2589")
	T.near("after a reload: same time to sell", li and li.timeToSell, 2.5 * H, 30)
	-- matched postings go after 2 days
	W.advance(3 * DAY)
	X = W.reload()
	W.advance(5)
	local left = 0
	for _, p in ipairs(L(X).posts or {}) do left = left + 1 end
	T.check("postings used up and older than 2 days are gone", left, 0)
	T.near("the times stay with the sales", X.LedgerItem("2589") and X.LedgerItem("2589").timeToSell, 2.5 * H, 30)
	local _ = linen
end)

T.scene("37 gold pages: gold history per character", function()
	local X = W.start()
	W.setMoney(100000)
	W.advance(10)
	local r = X.Realm()
	T.ok("history started", r.goldHist and r.goldHist["Xn Ascalon"] ~= nil)
	local pts = X.GoldHistory("Xn Ascalon")
	T.check("one day", #pts, 1)
	T.check("today's gold", pts[1] and pts[1][2], 100000)
	-- same day, more gold: today's point replaced
	W.setMoney(120000)
	W.advance(5)
	T.check("same day: still one point saved", select(2, r.goldHist["Xn Ascalon"]:gsub(";", "")), 0)
	-- next days: unchanged gold adds nothing saved, the graph still has one point a day
	W.advance(DAY)
	W.bagsChanged()
	W.advance(5)
	W.advance(DAY)
	W.setMoney(90000)
	W.advance(5)
	T.check("two points saved (no point for the unchanged day)", select(2, r.goldHist["Xn Ascalon"]:gsub(";", "")), 1)
	pts = X.GoldHistory("Xn Ascalon")
	T.check("three days on the graph", #pts, 3)
	T.check("the unchanged day keeps the gold", pts[2] and pts[2][2], 120000)
	T.check("today", pts[3] and pts[3][2], 90000)
	-- another character (synced from another account): its gold counts from then on, and before its first point too
	local d = W.env.XNAHDB
	d.chars["Alt Ascalon"] = {realm = X.RealmKey(), money = 50000, at = X.Now(), bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
	X.RecordGoldHistory()
	local all = X.GoldHistory(nil)
	T.check("all characters: three days", #all, 3)
	T.check("all characters today", all[3] and all[3][2], 140000)
	T.check("all characters on day one (the alt's first gold counts back)", all[1] and all[1][2], 170000)
	T.check("two characters", #X.GoldChars(), 2)
	-- a new character with gold notes of earlier days: its history starts with them
	local today = X.Day()
	r.homeGold = r.homeGold or {}
	r.homeGold[today - 2] = r.homeGold[today - 2] or {}
	r.homeGold[today - 2]["New Ascalon"] = 7000
	d.chars["New Ascalon"] = {realm = X.RealmKey(), money = 9000, at = X.Now(), bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
	X.RecordGoldHistory()
	pts = X.GoldHistory("New Ascalon")
	T.check("from the day notes: three days", #pts, 3)
	T.check("from the day notes: first day", pts[1] and pts[1][2], 7000)
	T.check("from the day notes: today", pts[3] and pts[3][2], 9000)
	-- forgetting a character forgets its history
	X.DeleteChar("New Ascalon")
	T.check("forgotten", r.goldHist["New Ascalon"], nil)
	-- after a reload: kept
	X = W.reload()
	W.advance(10)
	T.check("after a reload: three days", #X.GoldHistory("Xn Ascalon"), 3)
	-- a year of changes every day: thinned (90 days daily, then a week each), small
	local s = ""
	local start = today - 400
	for day = start, today do s = X.GoldHistAdd(s, day, 100000 + (day - start) * 137, today) end
	local n = select(2, s:gsub(";", "")) + 1
	T.ok("a year of daily changes: thinned to about 90 + 40 points", n >= 120 and n <= 140, n)
	T.ok("a year of daily changes: under 2 KB", #s < 2048, #s)
	T.note("gold history: " .. #s .. " bytes per character after a year of daily changes (" .. n .. " points)")
	-- the oldest point kept is a year ago (it still tells the gold from then on)
	local first = X.n36(s:match("^([^,]*)"))
	T.check("the oldest point: a year ago", first, today - 365)
end)

T.scene("37 gold pages: both pages with no data, then with data", function()
	local X = W.start()
	W.advance(5)
	local p = openGold(X, "Gold over time")
	local f = p.views.history
	T.ok("gold over time: shown", f and f:IsVisible())
	T.check("remembered", X.S().goldView, "history")
	T.ok("gold over time: tiles", has(W.screen(f), "Gold now") and has(W.screen(f), "Best week"), W.screen(f))
	local n = X.GoldHistoryNumbers()
	T.check("no profit weeks yet", n.nWeeks, 0)
	T.ok("profit graph: nothing yet", has(W.screen(f), "No sales or purchases yet"))
	for _, b in ipairs({"7 days", "30 days", "90 days", "1 year", "All characters", "Net worth"}) do
		T.ok("button " .. b, W.findButton(b, f) ~= nil)
	end
	p = openGold(X, "Your items")
	local g = p.views.results
	T.ok("your items: shown", g and g:IsVisible())
	T.ok("your items: empty text", has(W.screen(g), "Nothing yet. Open your mailbox"), W.screen(g))
	T.ok("your items: time to sell column", has(W.screen(g), "Time to sell"))
	-- every column header tells what it means
	local ncol = #g.tbl.columns
	local tipsOk = 0
	for i = 1, ncol do
		local b = g.tbl.headerButtons[i]
		if b then
			W.hover(b)
			local text = W.tipText()
			if #text > 30 then tipsOk = tipsOk + 1 end
			W.unhover(b)
		end
	end
	T.check("a hover line on every column", tipsOk, ncol)
	-- data: a month of gold, sales, purchases, postings
	W.setMoney(200000)
	W.advance(5)
	W.openAH()
	post(X, 2589, 100, 20)
	W.closeAH()
	W.advance(H)
	local Lg = L(X)
	local t0 = X.Now()
	for i = 1, 20 do
		table.insert(Lg.sales, {t = t0 - i * DAY, key = "2592", name = "Wool Cloth", count = 5, money = 1500, cut = 75, char = "Xn Ascalon"})
		table.insert(Lg.buys, {t = t0 - i * DAY - H, key = "2592", name = "Wool Cloth", count = 5, money = 500, char = "Xn Ascalon"})
	end
	table.insert(Lg.expired, {t = t0 - 3 * DAY, key = "2592", name = "Wool Cloth", count = 5, char = "Xn Ascalon"})
	X.LedgerForget()
	W.addMail(W.mailSold(2589, 1000, 10, "Ann Lee", 50))
	W.openMail()
	W.advance(2)
	X.Fire("XNAH_LEDGER")
	W.advance(1)
	p = openGold(X, "Your items")
	g = p.views.results
	T.check("two items", #g.tbl.items, 2)
	T.ok("count top right", has(W.screen(p), "2 items"), W.screen(p))
	local wool, linen
	for _, r in ipairs(g.tbl.items) do
		if r.key == "2592" then wool = r elseif r.key == "2589" then linen = r end
	end
	T.check("wool sold", wool and wool.sold, 100)
	T.check("wool bought", wool and wool.bought, 100)
	T.near("wool profit each", wool and wool.profitEach, (1425 * 20 - 100 * 100) / 100, 0.01)
	T.near("wool sell-through 100 of 105", wool and wool.sellThrough, 100 / 105, 0.001)
	T.check("wool: no time (never seen put up)", wool and wool.timeToSell, nil)
	T.near("linen: an hour to sell", linen and linen.timeToSell, H, 30)
	T.ok("summary line", has(W.screen(g), "average time to sell"), W.screen(g))
	-- a click opens the item
	local got
	local old = X.UI.ShowItem
	X.UI.ShowItem = function(key) got = key end
	g.tbl.rows[1]:Click("LeftButton")
	X.UI.ShowItem = old
	T.ok("click opens the item", got == "2592" or got == "2589", got)
	-- gold over time with data: lines, weeks, tiles; every range
	p = openGold(X, "Gold over time")
	f = p.views.history
	n = X.GoldHistoryNumbers()
	T.ok("weeks counted", n.nWeeks >= 3, n.nWeeks)
	T.ok("best week", n.best ~= nil and n.best.profit > 0)
	T.ok("average a week", n.avgWeek ~= nil and n.avgWeek > 0)
	local info = f.gold.GetInfo()
	T.ok("gold graph: lines", #info.series >= 2, #info.series)
	T.ok("gold graph: legend", #info.legend >= 2)
	T.ok("profit graph: two lines", #f.profit.GetInfo().series == 2)
	T.ok("tile: gold now", has(W.plain(f.tiles[1].value:GetText()), "20g"), f.tiles[1].value:GetText())
	for _, b in ipairs({"7 days", "90 days", "1 year", "30 days"}) do
		W.click(b, f)
		W.advance(0.3)
		T.ok("range " .. b .. ": drawn", f.gold:IsVisible())
	end
	T.check("range kept", X.S().goldHistRange, 2)
	-- hide the account line and net worth: only the character
	W.click("All characters", f)
	W.click("Net worth", f)
	W.advance(0.3)
	T.check("only the character's line", #f.gold.GetInfo().series, 1)
	-- the characters menu
	W.click("Characters (1 of 1)", f)
	W.advance(0.3)
	T.ok("characters menu opened", W.findButton("Hide every character") ~= nil)
	W.click("Hide every character")
	W.advance(0.3)
	T.check("no lines: the empty text", #f.gold.GetInfo().series, 0)
	W.click("All characters", f)
	W.advance(0.3)
	T.check("account line back", #f.gold.GetInfo().series, 1)
	-- refresh without changes: nothing worked out again
	local before = X.GoldHistoryNumbers
	local count = 0
	X.GoldHistoryNumbers = function(...) count = count + 1 return before(...) end
	X.UI.Refresh(true)
	W.advance(1)
	X.GoldHistoryNumbers = before
	T.check("a refresh without changes works nothing out", count, 0)
	-- after a reload: the page and its range are kept
	X = W.reload()
	W.advance(5)
	p = openGold(X)
	T.ok("after a reload: gold over time shown", p.views.history:IsVisible())
end)
