-- XNAH test scenes, part 25 (round 12, helper G): the Gold tab's numbers (profit per week, flips, auction house time
-- and gold per hour), your gold of the day and week (X.GoldNumbers), and the saved data of removed features cleaned.

local H = 3600

-- a ledger entry put straight into the lists (the mails themselves are tested in tests-6-ledger.lua)
local function add(X, list, t, key, count, money, cut)
	local L = X.Ledger()
	table.insert(L[list], {t = t, key = key, name = X.ItemName(key) or key, count = count, money = money, cut = cut, char = "Xn Ascalon"})
end
local function flipOf(rows, key) for _, r in ipairs(rows) do if r.key == key then return r end end end

T.scene("gold: flips match sales with earlier purchases, oldest first", function()
	local X = W.start()
	W.advance(5)
	local t0 = X.Now() - 10 * H
	-- Linen: 10 bought at 1s, 10 more at 2s, then 15 sold at 2s each (cut 5%): 10 of the 1s ones and 5 of the 2s ones
	add(X, "buys", t0, "2589", 10, 1000)
	add(X, "buys", t0 + H, "2589", 10, 2000)
	add(X, "sales", t0 + 2 * H, "2589", 15, 3000, 150)
	-- Wool: bought 5 at 2s, sold them at 1s: a loss
	add(X, "buys", t0, "2592", 5, 1000)
	add(X, "sales", t0 + 30 * 60, "2592", 5, 500, 25)
	-- Copper Ore: sold before it was ever bought (farmed), and the later purchase is not sold yet: no flip
	add(X, "sales", t0 - H, "2770", 5, 500, 25)
	add(X, "buys", t0, "2770", 5, 400)
	-- Tin Bar: a sale on the same second as the purchase counts (bought first)
	add(X, "buys", t0 + 3 * H, "3576", 2, 200)
	add(X, "sales", t0 + 3 * H, "3576", 2, 400, 20)
	local rows = X.LedgerFlips()
	T.check("three flips", #rows, 3)
	local linen = flipOf(rows, "2589")
	T.check("linen: units", linen and linen.units, 15)
	T.check("linen: cost (10 at 1s, 5 at 2s)", linen and linen.cost, 2000)
	T.check("linen: income after the cut", linen and linen.income, 2850)
	T.check("linen: profit", linen and linen.profit, 850)
	T.near("linen: profit of one", linen and linen.each, 850 / 15, 0.01)
	T.near("linen: bought at", linen and linen.buyEach, 2000 / 15, 0.01)
	T.check("linen: sold at", linen and linen.sellEach, 190)
	T.near("linen: profit %", linen and linen.pct, 0.425, 0.001)
	T.check("linen: last sale", linen and linen.last, t0 + 2 * H)
	local wool = flipOf(rows, "2592")
	T.check("wool: a loss of 1s 5c each", wool and wool.each, -105)
	T.ok("no flip for the farmed ore", flipOf(rows, "2770") == nil)
	T.check("tin: bought and sold at once", flipOf(rows, "3576") and flipOf(rows, "3576").profit, 180)
	T.check("best first: tin (90c each)", rows[1].key, "3576")
	T.check("worst last: wool", rows[#rows].key, "2592")
	-- only sales from a moment on
	local later = X.LedgerFlips(t0 + 90 * 60)
	T.ok("from: linen still counts", flipOf(later, "2589") ~= nil)
	T.ok("from: the earlier wool sale does not", flipOf(later, "2592") == nil)
	-- an item saved by name only (not known when the mail was read) still pairs up
	local L = X.Ledger()
	table.insert(L.buys, {t = t0, name = "Odd Thing", count = 1, money = 100})
	table.insert(L.sales, {t = t0 + H, name = "Odd Thing", count = 1, money = 300, cut = 15})
	local odd
	for _, r in ipairs(X.LedgerFlips()) do if r.name == "Odd Thing" then odd = r end end
	T.check("by name: profit", odd and odd.profit, 185)
end)

T.scene("gold: profit per week", function()
	local X = W.start()
	W.advance(5)
	local now = X.Now()
	add(X, "sales", now - 60, "2589", 10, 5000, 250)      -- this week
	add(X, "buys", now - 120, "2592", 5, 1000)
	add(X, "sales", now - 14 * 86400, "2589", 1, 800, 40) -- two weeks ago
	add(X, "buys", now - 14 * 86400, "2592", 1, 2000)
	add(X, "sales", now - 200 * 86400, "2589", 1, 999, 0) -- too old for 12 weeks
	local weeks = X.LedgerWeeks(12)
	T.check("12 weeks", #weeks, 12)
	local last, before = weeks[12], weeks[10]
	T.check("this week is the last", last.week, X.LedgerWeekOf(X.Day(now - 60)))
	T.check("weeks start on Monday (day 4 = Mon 5 Jan 1970)", (last.start - 4) % 7, 0)
	T.check("this week: income", last.income, 4750)
	T.check("this week: spent", last.spent, 1000)
	T.check("this week: profit", last.profit, 3750)
	T.check("this week: sales and purchases", last.sales .. "/" .. last.buys, "1/1")
	T.check("two weeks ago: a loss", before.profit, 760 - 2000)
	local sum = 0
	for _, w in ipairs(weeks) do sum = sum + w.income end
	T.check("the old sale is not in the 12 weeks", sum, 4750 + 760)
end)

T.scene("gold: auction house time and gold per hour", function()
	local X = W.start()
	W.advance(5)
	T.check("nothing counted yet", X.AHSeconds(), 0)
	T.check("no gold per hour yet", X.GoldPerHour().perHour, nil)
	W.openAH()
	W.advance(600)
	T.near("counted while open", X.AHSeconds(), 600, 2)
	W.advance(1200)
	W.closeAH()
	W.advance(5)
	T.near("half an hour", X.AHSeconds(), 1800, 2)
	T.check("first day noted", X.Realm().ahTimeFirst, X.Day(X.Now() - 1805))
	-- money made: 2g sold (after the cut) and 50s spent today; an old sale from before the counting is left out
	add(X, "sales", X.Now() - 60, "2589", 10, 21000, 1000)
	add(X, "buys", X.Now() - 60, "2592", 5, 5000)
	add(X, "sales", X.Now() - 40 * 86400, "2589", 10, 99999, 0)
	local g = X.GoldPerHour()
	T.check("profit since the counting started", g.profit, 15000)
	T.near("gold per hour: 1g 50s in half an hour = 3g an hour", g.perHour, 30000, 50)
	T.check("7 days: the same", X.GoldPerHour(7).profit, 15000)
	local week = X.LedgerWeeks(1)[1]
	T.near("the week knows the time too", week.seconds, 1800, 2)
	-- a reload while the window is open: the time so far is kept
	W.openAH()
	W.advance(300)
	W.fire("PLAYER_LOGOUT")
	X = W.reload()
	W.advance(5)
	T.near("kept over a reload", X.AHSeconds(), 2100, 4)
	-- a window left open for hours counts at most 6 hours
	W.openAH()
	W.advance(7 * H)
	W.closeAH()
	W.advance(1)
	T.near("one visit: at most 6 hours", X.AHSeconds(), 2100 + 6 * H, 4)
	T.ok("saved", W.saveText(W.env.XNAHDB):find("ahTime", 1, true) ~= nil)
end)

T.scene("gold: the overview shows totals, weeks and flips", function()
	local X = W.start()
	W.advance(5)
	local t0 = X.Now() - 5 * H
	add(X, "buys", t0, "2589", 10, 1000)
	add(X, "sales", t0 + H, "2589", 10, 3000, 150)
	add(X, "buys", t0, "2592", 5, 1000)
	add(X, "sales", t0 + H, "2592", 5, 500, 25)
	W.openAH()
	W.advance(3600)
	W.closeAH()
	X.UI.Toggle()
	local frame = X.UI.Frame()
	X.S().goldView = "overview"
	X.UI.Select("gold")
	W.advance(1)
	local text = W.screen(frame)
	T.ok("totals", text:find("Auction house time", 1, true) ~= nil, text)
	T.ok("an hour counted", text:find("1h 00m", 1, true) ~= nil, text)
	T.ok("flips: linen", text:find("Linen Cloth", 1, true) ~= nil)
	T.ok("flips: wool", text:find("Wool Cloth", 1, true) ~= nil)
	local v = X.UI.tabs.gold.panel.views.overview
	local rows = v.flips.items
	T.check("best flip first", rows[1] and rows[1].key, "2589")
	T.check("worst last", rows[#rows] and rows[#rows].key, "2592")
	local slot = v.weeks.slots[12]
	W.hover(slot)
	local tip = W.tipText()
	T.ok("week tooltip: profit", tip:find("Profit", 1, true) ~= nil, tip)
	T.ok("week tooltip: gold per hour", tip:find("Gold per hour", 1, true) ~= nil, tip)
	W.unhover(slot)
	T.ok("this week has a bar", slot.bar:IsShown())
end)

T.scene("settings: a hidden page, no guild sharing or export, old sharing data cleaned", function()
	local X = W.start()
	-- saved data of the old guild sharing
	X.db.share = {id = "abc123", lastSent = 5, got = 10}
	X.S().share = true
	X.Realm().sharedFull = 12345
	X = W.reload()
	W.advance(2)
	T.check("sharing data gone", X.db.share, nil)
	T.check("sharing setting gone", X.S().share, nil)
	T.check("received scan time gone", X.Realm().sharedFull, nil)
	T.ok("no sharing functions", X.ShareState == nil and X.CommSend == nil and X.ExportPrices == nil)
	local tab = X.UI.tabs.scan
	T.check("title", tab.title, "Settings")
	T.ok("no tab button", tab.hidden == true)
	X.UI.Toggle()
	X.UI.Open("settings")
	W.advance(0.5)
	T.check("the old name opens it", X.UI.current, "scan")
	local text = W.screen(tab.panel)
	T.ok("scan box", text:find("Full scan", 1, true) ~= nil, text)
	T.ok("settings", text:find("Auction house cut", 1, true) ~= nil)
	T.ok("no mailbox box", text:find("Open all auction mail", 1, true) == nil)
	T.ok("no sharing box", text:find("Guild", 1, true) == nil)
	T.ok("no export", text:find("Export", 1, true) == nil)
end)

T.scene("gold: gold of the day and week, sales and the best seller (X.GoldNumbers)", function()
	local X = W.start()
	W.advance(5)
	local n = X.GoldNumbers()
	T.check("gold of this character", n.gold, 1234567)
	T.check("gold today: nothing changed yet", n.goldToday, 0)
	T.check("one character", n.chars, 1)
	W.setMoney(1234567 + 50000)
	W.advance(3)
	n = X.GoldNumbers()
	T.check("gold today: +5g", n.goldToday, 50000)
	T.check("gold this week: +5g", n.goldWeek, 50000)
	-- sales and a purchase today, a sale 3 days ago, an old sale 10 days ago
	W.addMail(W.mailSold(2589, 1000, 20, "Ann Lee", 50))
	W.addMail(W.mailSold(2592, 5000, 5, "Bob Stone", 250))
	W.addMail(W.mailWon(2770, 400, 10, "Cid Moss"))
	W.addMail(W.mailAgo(W.mailSold(2592, 2000, 2, "Dee Fox", 100), 3))
	W.addMail(W.mailAgo(W.mailSold(4306, 99999, 1, "Old Buyer", 0), 10))
	W.addMail(W.mailExpired(2840, 4))
	W.openMail()
	n = X.GoldNumbers()
	T.check("today: income after the cut", n.today.income, 950 + 4750)
	T.check("today: units sold", n.today.units, 25)
	T.check("today: spent", n.today.spent, 400)
	T.check("today: bought", n.today.bought, 10)
	T.check("today: expired", n.today.expired, 4)
	T.check("week: income (3 days ago counts, 10 days ago does not)", n.week.income, 950 + 4750 + 1900)
	T.check("week: units", n.week.units, 27)
	T.check("week: profit = income - spent", n.profitWeek, 950 + 4750 + 1900 - 400)
	T.check("best seller this week: Wool Cloth", n.best and n.best.key, "2592")
	T.check("best seller: what it brought", n.best and n.best.income, 4750 + 1900)
	T.check("best seller: units", n.best and n.best.units, 7)
	T.check("two items in the top list", #n.top, 2)
	T.check("the old sale is not in the top list", n.top[3], nil)
	-- the scan numbers
	T.check("no full scan yet", n.lastFull, nil)
	T.check("auction house closed", n.ahOpen, false)
	-- the next day: today starts again, the week keeps yesterday
	W.closeMail()
	W.advance(86400)
	n = X.GoldNumbers()
	T.check("next day: gold today starts at 0", n.goldToday, 0)
	T.check("next day: the week still has +5g", n.goldWeek, 50000)
	T.check("next day: no sales today", n.today.income, 0)
	T.check("next day: the week keeps them", n.week.income, 950 + 4750 + 1900)
	W.setMoney(1234567 + 50000 - 20000)
	W.advance(3)
	n = X.GoldNumbers()
	T.check("next day: spent 2g", n.goldToday, -20000)
	T.check("next day: week +3g", n.goldWeek, 30000)
	-- a reload keeps the notes of the day
	X = W.reload()
	W.advance(5)
	n = X.GoldNumbers()
	T.check("after a reload: today", n.goldToday, -20000)
	T.check("after a reload: week", n.goldWeek, 30000)
	-- 10 days later: only the last 7 days count; old notes are dropped after 15 days
	W.advance(10 * 86400)
	n = X.GoldNumbers()
	T.check("10 days later: week = 0 (nothing changed)", n.goldWeek, 0)
	W.advance(10 * 86400)
	X.GoldNumbers()
	local days = 0
	for _ in pairs(X.Realm().homeGold) do days = days + 1 end
	T.ok("old gold notes dropped", days <= 15, days)
end)

T.scene("gold: the saved data of removed features is deleted once, the rest is kept", function()
	local X = W.start()
	local db = X.db
	-- saved by the removed features (shopping lists, crafting queue, posting, sniper, strategies, guide, Home, mail)
	db.shop = {Mats = {items = {{key = "2589", qty = 5}}}}
	db.queue = {[123] = {mode = "craft", n = 2}}
	db.onWay = {[2589] = {{5, 1, "Me"}}}
	db.strategies = {usual = {on = true}}
	db.postRules = {["2589"] = {floor = 50}}
	db.sellTick = {["2589"] = true}
	db.sellList = {}
	db.mailLast = {t = 1, text = "x"}
	db.guideSeen = "0.8.1"
	local S = X.S()
	S.homeFirst, S.snipeWait, S.alertSound, S.postFloor, S.buyView, S.craftView = true, 10, true, 80, "best", "recipes"
	S.dealsHidden, S.strategySel, S.mailButton, S.routineCancel, S.guideAtLogin = {}, "usual", true, true, true
	S.ahBar = true
	S.tab = "buy"
	S.sorts = {["buy:1"] = {2, true}, ["market:1"] = {3, false}, ["craft:2"] = {1, false}}
	-- kept: the watch list with a highest price, prices, ledger, settings in use
	X.SetWatched("2589", true)
	X.SetWatchMax("2589", 77)
	X.Record("2589", X.Now() - 3600, 100, 110, 50, 5)
	X.Ledger().sales[1] = {t = X.Now(), key = "2589", count = 1, money = 100}
	S.cut = 7
	db.cleanup = nil
	X = W.reload()
	W.advance(2)
	db, S = X.db, X.S()
	for _, k in ipairs({"shop", "queue", "onWay", "strategies", "postRules", "sellTick", "sellList", "mailLast", "guideSeen"}) do
		T.check("deleted: " .. k, db[k], nil)
	end
	for _, k in ipairs({"homeFirst", "snipeWait", "alertSound", "postFloor", "buyView", "craftView", "dealsHidden",
		"strategySel", "mailButton", "routineCancel", "guideAtLogin", "ahBar"}) do
		T.check("setting deleted: " .. k, S[k], nil)
	end
	T.ok("the tab of a removed page is forgotten", S.tab ~= "buy", S.tab)
	T.check("sorting of a removed page deleted", S.sorts["buy:1"], nil)
	T.check("sorting of a removed page deleted (2)", S.sorts["craft:2"], nil)
	T.ok("sorting of Market kept", S.sorts["market:1"] ~= nil)
	T.check("done once", db.cleanup, 2)
	T.ok("watch list kept", X.Watched("2589"))
	T.check("its highest price kept", X.WatchMax("2589"), 77)
	T.ok("prices kept", X.Items()["2589"] ~= nil and X.Items()["2589"].cur ~= nil)
	T.check("ledger kept", #X.Ledger().sales, 1)
	T.check("setting in use kept", S.cut, 7)
	T.ok("settings still filled in", S.staleHours ~= nil and S.uiScale ~= nil)
	-- once only: a field of the same name set later stays
	db.shop = {kept = true}
	X = W.reload()
	W.advance(1)
	T.ok("not cleaned twice", X.db.shop ~= nil and X.db.shop.kept == true)
	-- saved data cleaned by the first round only (cleanup = 1): runs once more, harmless, and takes the auction house bar
	X.db.cleanup = 1
	X.S().ahBar = true
	X.S().cut = 6
	X = W.reload()
	W.advance(1)
	T.check("second round: auction house bar setting deleted", X.S().ahBar, nil)
	T.check("second round: now 2", X.db.cleanup, 2)
	T.check("second round: setting in use kept", X.S().cut, 6)
	T.check("second round: ledger kept", #X.Ledger().sales, 1)
	T.ok("second round: watch list kept", X.Watched("2589"))
end)
