-- XNAH test scenes, part 25 (round 12, helper G): the Gold tab's numbers (profit per week, flips, auction house time
-- and gold per hour) and the mailbox's "Open all auction mail".

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
	T.ok("mailbox box", text:find("Open all auction mail", 1, true) ~= nil)
	T.ok("no sharing box", text:find("Guild", 1, true) == nil)
	T.ok("no export", text:find("Export", 1, true) == nil)
	-- the mailbox check box turns the button off and on
	W.click("Open all auction mail", tab.panel)
	T.check("mail button off", X.S().mailButton, false)
	W.click("Open all auction mail", tab.panel)
	T.check("mail button on", X.S().mailButton, true)
end)

-- [[ the mailbox ]]
local function bagCount(id)
	local n = 0
	for _, bag in pairs(W.bags) do for _, s in pairs(bag) do if s.id == id then n = n + s.count end end end
	return n
end
local function mailBar() return W.env.XNAHMailBar end

T.scene("mail: open all auction mail takes gold and items, logs them, leaves other mail", function()
	local X = W.start()
	W.advance(5)
	W.money = 100000
	W.addMail(W.mailSold(2589, 1000, 20, "Ann Lee", 50))
	W.addMail(W.mailWon(2592, 400, 10, "Bob Stone"))
	W.addMail(W.mailExpired(2770, 5))
	W.addMail(W.mailCancelled(3576, 2))
	W.addMail(W.mailPending(2589, 2000, 20, "Cid Moss", 100))
	local friend = W.addMail({sender = "Ann Lee", subject = "for you", money = 500, items = {{id = 2589, count = 3}}})
	local cod = W.addMail(W.mailExpired(2589, 1))
	cod.cod = 100 -- cash on delivery: never taken
	W.openMail()
	W.advance(1)
	local text = W.screen(mailBar())
	T.ok("the bar shows what waits", text:find("4 auction house mails", 1, true) ~= nil, text)
	-- Xn: never automatic - opening the mailbox and waiting takes nothing; only the button does
	W.advance(30)
	T.check("opening the mailbox takes nothing", #W.mailTakes, 0)
	W.click("Open all auction mail")
	T.check("the first take straight from the click", #W.mailTakes, 1)
	T.ok("running: the button stops", W.findButton("Stop", mailBar()) ~= nil)
	W.advance(10)
	T.check("gold taken", W.money, 100000 + 950)
	T.check("wool in the bags", bagCount(2592), 10)
	T.check("ore in the bags", bagCount(2770), 5)
	T.check("tin in the bags", bagCount(3576), 2)
	T.check("four takes", #W.mailTakes, 4)
	local gap = 99
	for i = 2, #W.mailTakes do gap = math.min(gap, W.mailTakes[i].t - W.mailTakes[i - 1].t) end
	T.ok("a pause between takes", gap >= 0.2, gap)
	T.check("the friend's mail is untouched", friend.money, 500)
	T.ok("the friend's item is untouched", friend.items[1] ~= nil)
	T.ok("cash on delivery untouched", cod.items[1] ~= nil)
	T.check("left: friend, cash on delivery, sale pending", #W.mail, 3)
	local L = X.Ledger()
	T.check("ledger: sale (and the pending one)", #L.sales, 2)
	T.check("ledger: purchase", #L.buys, 1)
	T.check("ledger: expired (and the cash on delivery one)", #L.expired, 2)
	T.check("ledger: cancelled", #L.cancelled, 1)
	local said = W.said("took 9s 50c and 17 items from 4 auction house mails")
	T.check("told in chat", #said, 1)
	T.ok("saved for the Settings page", X.MailLast() and X.MailLast().text:find("17 items", 1, true) ~= nil)
	text = W.screen(mailBar())
	T.ok("the bar says what it took", text:find("took 9s 50c", 1, true) ~= nil, text)
	local again = W.findButton("Open all auction mail", mailBar())
	T.ok("nothing more to open", again == nil or again.disabled)
	-- the ledger did not count anything twice
	W.closeMail()
	W.openMail()
	T.check("ledger: still 2 sales", #X.Ledger().sales, 2)
end)

T.scene("mail: bags full - gold is still taken, items wait", function()
	local X = W.start()
	W.advance(5)
	W.money = 0
	W.bagRoom = 1
	W.addMail(W.mailWon(2592, 400, 10, "Bob Stone"))
	W.addMail(W.mailExpired(2770, 5))
	W.addMail(W.mailSold(2589, 1000, 20, "Ann Lee", 50))
	W.openMail()
	W.advance(1)
	W.click("Open all auction mail")
	W.advance(10)
	T.check("gold taken", W.money, 950)
	T.check("one item taken", W.bagRoom, 0)
	T.check("one item mail left", #W.mail, 1)
	T.check("told: bags full", #W.said("bags are full"), 1)
	T.ok("not running", not X.MailRunning())
end)

T.scene("mail: a mail that just came is in the ledger before it is taken", function()
	local X = W.start()
	W.advance(5)
	W.openMail()
	W.advance(1)
	W.addMail(W.mailSold(2589, 1000, 20, "Ann Lee", 50)) -- the ledger reads it 0.5 s later ...
	W.advance(0.35)                                      -- (the button shows it after 0.3 s)
	W.click("Open all auction mail")                     -- ... but the click comes first
	W.advance(5)
	T.check("taken", #W.mail, 0)
	T.check("in the ledger", #X.Ledger().sales, 1)
end)

T.scene("mail: closing the mailbox stops; the button can be switched off", function()
	local X = W.start()
	W.advance(5)
	for i = 1, 5 do W.addMail(W.mailExpired(2770, i)) end
	W.openMail()
	W.advance(1)
	W.click("Open all auction mail")
	W.advance(0.1)
	W.closeMail()
	W.advance(3)
	T.ok("stopped after the first", #W.mailTakes <= 2, #W.mailTakes)
	T.check("told: closed", #W.said("mailbox was closed"), 1)
	T.ok("not running", not X.MailRunning())
	-- clicking Stop
	W.openMail()
	W.advance(1)
	W.click("Open all auction mail")
	W.click("Stop", mailBar())
	W.advance(3)
	T.check("told: stopped", #W.said("(stopped)"), 1)
	W.closeMail()
	X.S().mailButton = false
	W.openMail()
	W.advance(1)
	T.ok("switched off: no button", W.findButton("Open all auction mail") == nil)
end)

T.scene("mail: when the game blocks timed takes, one mail per click", function()
	local X = W.start()
	W.advance(5)
	W.mailBlocked = true
	for i = 1, 3 do W.addMail(W.mailExpired(2770, i)) end
	W.openMail()
	W.advance(1)
	W.click("Open all auction mail")
	W.advance(3)
	T.check("the click's take worked", bagCount(2770) > 0, true)
	T.check("told: a click per mail", #W.said("click per mail"), 1)
	for _ = 1, 6 do
		local b = W.findButton("Take next auction mail", mailBar())
		if not b then break end
		b:Click()
		W.advance(1)
	end
	T.check("all taken by clicks", #W.mail, 0)
	T.check("all ore", bagCount(2770), 6)
	T.ok("no Lua error", true)
end)
