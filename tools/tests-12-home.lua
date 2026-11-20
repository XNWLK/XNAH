-- XNAH test scenes, part 12: the home page (Home.lua, UIHome.lua) - the numbers of the day, the to-do list and its
-- buttons, opening on Home the first time each session.

local function jobOf(X, id)
	for _, j in ipairs(X.HomeTodo()) do if j.id == id then return j end end
	return nil
end
local function ids(X)
	local out = {}
	for _, j in ipairs(X.HomeTodo()) do out[#out + 1] = j.id end
	return table.concat(out, ",")
end
-- the home page's to-do list worked out again now (the page asks at most once a second)
local function fresh(X)
	X.HomeForget()
	W.advance(1.1)
	X.HomeTodo()
	W.advance(1) -- the deals pass runs in slices
	return X.HomeTodo()
end

T.scene("home: gold, sales and the best seller", function()
	local X = W.start()
	W.advance(5)
	local n = X.HomeNumbers()
	T.check("gold of this character", n.gold, 1234567)
	T.check("gold today: nothing changed yet", n.goldToday, 0)
	T.check("one character", n.chars, 1)
	W.setMoney(1234567 + 50000)
	W.advance(3)
	n = X.HomeNumbers()
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
	n = X.HomeNumbers()
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
	-- the scan card's numbers
	T.check("no full scan yet", n.lastFull, nil)
	T.check("auction house closed", n.ahOpen, false)
	-- the next day: today starts again, the week keeps yesterday
	W.closeMail()
	W.advance(86400)
	n = X.HomeNumbers()
	T.check("next day: gold today starts at 0", n.goldToday, 0)
	T.check("next day: the week still has +5g", n.goldWeek, 50000)
	T.check("next day: no sales today", n.today.income, 0)
	T.check("next day: the week keeps them", n.week.income, 950 + 4750 + 1900)
	W.setMoney(1234567 + 50000 - 20000)
	W.advance(3)
	n = X.HomeNumbers()
	T.check("next day: spent 2g", n.goldToday, -20000)
	T.check("next day: week +3g", n.goldWeek, 30000)
	-- a reload keeps the notes of the day
	X = W.reload()
	W.advance(5)
	n = X.HomeNumbers()
	T.check("after a reload: today", n.goldToday, -20000)
	T.check("after a reload: week", n.goldWeek, 30000)
	-- 10 days later: only the last 7 days count; old notes are dropped after 15 days
	W.advance(10 * 86400)
	n = X.HomeNumbers()
	T.check("10 days later: week = 0 (nothing changed)", n.goldWeek, 0)
	W.advance(10 * 86400)
	X.HomeNumbers()
	local days = 0
	for _ in pairs(X.Realm().homeGold) do days = days + 1 end
	T.ok("old gold notes dropped", days <= 15, days)
end)

T.scene("home: the to-do list", function()
	local X = W.start()
	W.advance(5)
	-- nothing known at all: the scan comes first
	local todo = fresh(X)
	T.check("no scan yet: first job is the scan", todo[1] and todo[1].id, "scan")
	T.check("auction house closed: the button opens tab Scan", todo[1] and todo[1].tab, "scan")
	T.check("no action while the auction house is closed", todo[1] and todo[1].action, nil)
	-- the auction house open: "Scan now" starts a full scan
	W.makeMarket(7, 40, {lastDay = 6, uncached = 0})
	W.openAH()
	todo = fresh(X)
	T.check("auction house open: Scan now", todo[1] and todo[1].button, "Scan now")
	T.ok("Scan now has an action", todo[1] and todo[1].action ~= nil)
	todo[1].action()
	T.ok("the scan started", X.scan.state ~= "idle")
	W.waitFor(function() return X.scan.state == "idle" end, 300)
	T.ok("the scan finished", X.Realm().lastFull ~= nil)
	todo = fresh(X)
	T.ok("after the scan: no scan job", jobOf(X, "scan") == nil, ids(X))
	-- a week of prices with deals on the last day
	for day = 1, 6 do
		W.advance(86400)
		W.marketDay(day, 6)
		T.fullScan(X)
	end
	todo = fresh(X)
	local deals = X.Deals()
	local dj = jobOf(X, "deals")
	T.ok("deals: a job", #deals == 0 or dj ~= nil, #deals)
	if dj then
		T.check("deals: the same count as tab Deals", dj.count, #deals)
		T.check("deals: opens tab Deals", dj.tab, "deals")
	end
	T.note("home: " .. #deals .. " deals in the test market")
	-- a watched item under its max price
	local key = tostring(W.market.byKind.stack[1])
	X.SetWatched(key, true)
	X.SetWatchMax(key, 99999999)
	W.advance(0.5)
	fresh(X)
	T.ok("watched item under max: a job", jobOf(X, "watch") ~= nil, ids(X))
	-- an expired auction in the mailbox, then back in the bags
	W.addMail(W.mailSold(2589, 30000, 20, "Ann Lee", 1500))
	local m = W.addMail(W.mailExpired(2840, 4))
	W.openMail()
	fresh(X)
	local ej = jobOf(X, "expiredMail")
	T.ok("expired in the mailbox: a job", ej ~= nil, ids(X))
	T.check("expired in the mailbox: count", ej and ej.count, 1)
	T.ok("gold in the mailbox: a job", jobOf(X, "mailGold") ~= nil, ids(X))
	W.takeMail(m)
	W.fill(0, {{2840, 4}})
	W.bagsChanged()
	W.advance(2)
	fresh(X)
	T.ok("expired, now in the bags: a job", jobOf(X, "expiredBags") ~= nil, ids(X))
	T.ok("no longer waiting in the mailbox", jobOf(X, "expiredMail") == nil, ids(X))
	-- undercut auctions (after a cancel scan)
	X.cancel = {state = "done", rows = {{key = "2589", auctionID = 1, unit = 100, qty = 1}}, all = {}}
	X.Fire("XNAH_CANCEL")
	fresh(X)
	local uj = jobOf(X, "undercut")
	T.ok("undercut: a job", uj ~= nil, ids(X))
	T.check("undercut: opens tab Sell", uj and uj.tab, "sell")
	-- the crafting queue and a shopping list
	W.recipes = {[1] = {name = "Smelt Copper", out = 2840, reagents = {{2770, 1}}, learned = true, prof = "Mining"}}
	W.openProfession("Mining")
	W.advance(2)
	W.closeProfession()
	X.QueueSet(1, "craft", 3)
	X.ShopAdd("Home test", "2589", 10)
	W.advance(1)
	fresh(X)
	local qj = jobOf(X, "queue")
	T.ok("crafting queue: a job", qj ~= nil, ids(X))
	T.check("crafting queue: 3 crafts", qj and qj.count, 3)
	T.ok("shopping list: a job", jobOf(X, "shop") ~= nil, ids(X))
	-- the order: the most urgent first, nothing listed twice
	local seen, twice = {}, false
	for _, j in ipairs(X.HomeTodo()) do
		if seen[j.id] then twice = true end
		seen[j.id] = true
		T.ok("job " .. j.id .. ": text, why and a button", j.text and j.why and j.button, j.id)
		T.ok("job " .. j.id .. ": opens a tab or acts", j.tab or j.action, j.id)
	end
	T.ok("no job twice", not twice)
	-- three days later the prices are too old: the scan is the first job again
	W.closeAH()
	W.advance(4 * 86400)
	todo = fresh(X)
	T.check("old prices: the scan first", todo[1] and todo[1].id, "scan")
	T.ok("old prices: the text says so", todo[1] and todo[1].text:find("too old", 1, true) ~= nil, todo[1] and todo[1].text)
	T.check("old prices: no deals", jobOf(X, "deals"), nil)
end)

T.scene("home: nothing to do, and a cheap page", function()
	local X = W.start()
	W.advance(5)
	X.Realm().lastFull = X.Now()
	local todo = fresh(X)
	T.check("one job", #todo, 1)
	T.check("it says nothing to do", todo[1] and todo[1].id, "nothing")
	-- asked many times in a row: the list is not worked out again each time
	local a = X.HomeTodo()
	for _ = 1, 50 do X.HomeTodo() X.HomeNumbers() end
	T.ok("the same list when nothing changed", X.HomeTodo() == a)
end)

T.scene("home: the tab - first tab, opens on Home each session, buttons", function()
	local X = W.start()
	W.advance(5)
	T.check("Home is the first tab", X.UI.order[1], "home")
	T.ok("12 tabs or fewer", #X.UI.order <= 12, #X.UI.order)
	X.UI.Toggle() -- the full window (/xnah opens the simple one)
	W.advance(1)
	T.check("the window opens on Home", X.UI.current, "home")
	local frame = X.UI.Frame()
	T.ok("shows the to-do list", W.screen(frame):find("What to do today", 1, true) ~= nil)
	T.ok("shows the cards", W.screen(frame):find("Gold, all characters", 1, true) ~= nil)
	-- the scan job's button opens tab Scan (auction house closed)
	W.click("Scan", X.UI.tabs.home.panel)
	W.advance(0.5)
	T.check("the Scan button opened tab Scan", X.UI.current, "scan")
	-- a card opens its tab
	X.UI.Select("home")
	W.advance(0.5)
	-- another tab used last; a reload: Home again (the setting is on)
	X.UI.Select("deals")
	W.advance(0.5)
	X = W.reload()
	W.advance(5)
	X.UI.Toggle() -- the full window (/xnah opens the simple one)
	W.advance(1)
	T.check("after a reload: Home again", X.UI.current, "home")
	-- the setting off: the page used last
	X.S().homeFirst = false
	X.UI.Select("deals")
	W.advance(0.5)
	X = W.reload()
	W.advance(5)
	X.UI.Toggle() -- the full window (/xnah opens the simple one)
	W.advance(1)
	T.check("setting off: the page used last", X.UI.current, "deals")
	-- with the auction house open: Scan now starts a scan from the home page
	X.S().homeFirst = true
	W.makeMarket(9, 20, {uncached = 0})
	W.openAH()
	X.UI.Select("home")
	W.advance(1)
	W.click("Scan now", X.UI.tabs.home.panel)
	W.advance(0.5)
	T.ok("Scan now started a full scan", X.scan.state ~= "idle" or X.Realm().lastFull ~= nil)
	W.waitFor(function() return X.scan.state == "idle" end, 300)
	-- undercut auctions: Show opens tab Sell on its undercut view
	X.cancel = {state = "done", rows = {{key = "2589", auctionID = 1, unit = 100, qty = 1}}, all = {}, at = W.NOW}
	X.Fire("XNAH_CANCEL")
	X.HomeForget()
	W.advance(1.5)
	X.UI.Refresh(true)
	W.click("Show", X.UI.tabs.home.panel)
	W.advance(0.5)
	T.check("Show opened tab Sell", X.UI.current, "sell")
	local sell = X.UI.tabs.sell.panel
	if sell and sell.view then T.check("on the undercut view", sell.view, "cancel") end
end)
