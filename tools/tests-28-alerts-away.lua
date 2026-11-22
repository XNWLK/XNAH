-- XNAH test scenes, part 28 (v0.8, helper C): shopping list "keep N in stock", price alerts from any price data,
-- the "while you were away" lines (mailbox and login) and the best day to sell.

local function has(text, part) return text:find(part, 1, true) ~= nil end
local function said(part) return #W.said(part) end
local function itemPanel(X) return X.UI.tabs.item and X.UI.tabs.item.panel end
local function dialog() return W.env.XNAHDialog end

T.scene("alerts-away: keep in stock - need from what you own, old lists unchanged", function()
	local X = W.start()
	W.putBag(0, 1, 2589, 5)
	W.bagsChanged()
	W.advance(3)
	T.check("own 5 linen", X.QueueOwned(2589), 5)
	local e = X.ShopAdd("Stock", "2589", 20, 70, true)
	T.check("keep set", e.keep, true)
	T.check("keep: need = 20 - 5 owned", X.ShopNeed(e), 15)
	-- adding it again in keep mode sets the number to keep (not added)
	X.ShopAdd("Stock", "2589", 30, nil, true)
	T.check("keep: new number to keep", e.qty, 30)
	T.check("keep: need 25", X.ShopNeed(e), 25)
	T.check("max kept", e.max, 70)
	-- more in the bags: less needed; the bought counter does not change the need
	W.putBag(0, 2, 2589, 10)
	W.bagsChanged()
	W.advance(3)
	T.check("keep: need follows the bags", X.ShopNeed(e), 15)
	-- bought for it: it goes to the mailbox, counted as owned until the mailbox is read
	W.advance(2)
	X.Fire("XNAH_BOUGHT", "2589", 10, 500, "shop", "Stock")
	T.check("bought counted", e.bought, 10)
	T.check("keep: bought units waiting in the mail count", X.ShopNeed(e), 5)
	W.advance(2)
	W.addMail(W.mailWon(2589, 500, 10, "Ann Lee"))
	W.openMail()
	W.advance(2)
	T.check("keep: read from the mail now (not twice)", X.ShopNeed(e), 5)
	T.check("nothing on its way any more", X.QueueOnWay and X.QueueOnWay(2589) or 0, 0)
	W.closeMail()
	-- the cost of the rest still works
	X.Record("2589", X.Now(), 60, 65, 100, 5, "Linen Cloth", 1)
	T.check("cost of the rest", (X.ShopCost(e)), 5 * 60)
	-- switched off: back to qty - bought
	X.ShopSet("Stock", "2589", "keep", false)
	T.check("keep off", e.keep, nil)
	T.check("plain: need = 30 - 10 bought", X.ShopNeed(e), 20)
	X.ShopSet("Stock", "2589", "keep", true)
	T.check("keep on again", X.ShopNeed(e), 5)
	-- a plain entry as before
	local p = X.ShopAdd("Plain", "2592", 10)
	X.ShopAdd("Plain", "2592", 5)
	T.check("plain entry: added up", p.qty, 15)
	T.check("plain entry: no keep", p.keep, nil)
	T.check("plain entry: need", X.ShopNeed(p), 15)
	-- a list saved by an older version (no keep field)
	X.db.shop["Old"] = {items = {{key = "2770", qty = 8, bought = 3}}}
	local o = X.ShopEntry("Old", "2770")
	T.check("old list: need = qty - bought", X.ShopNeed(o), 5)
	X.ShopAdd("Old", "2770", 2)
	T.check("old list: add works", o.qty, 10)
	-- saved over a reload
	X = W.reload()
	W.advance(5)
	local k = X.ShopEntry("Stock", "2589")
	T.check("keep saved", k and k.keep, true)
	T.check("old list still there", X.ShopEntry("Old", "2770") and X.ShopEntry("Old", "2770").qty, 10)
end)

T.scene("alerts-away: price alert from a full scan (sniper off), not twice, a lower price again", function()
	local X = W.start()
	X.SetWatched("2589", true)
	X.SetWatchMax("2589", 60)
	X.SetWatchMax("2592", 600)
	W.list(2589, 50, 20, 1, "Ann")
	W.list(2589, 80, 20, 1, "Bob")
	W.list(2592, 700, 10, 1, "Cid") -- over its max
	W.openAH()
	T.check("sniper off", X.snipe.on, false)
	local sounds = #W.sounds
	T.ok("full scan", T.fullScan(X, true))
	W.advance(1)
	T.check("one alert", said("price alert:"), 1)
	T.ok("the line", has(W.said("price alert:")[1] or "", "price alert: Linen Cloth listed at 50c (your max 60c) - tab Buy"),
		W.said("price alert:")[1])
	T.ok("a sound", #W.sounds > sounds)
	T.check("no alert for the item over its max", said("Wool Cloth listed"), 0)
	local hits = X.SnipeHits()
	T.check("in the hits list", hits[1] and hits[1].key, "2589")
	-- the item is searched once: the hit gets the real offers (only the 20 at or under the max), no second line
	W.advance(5)
	hits = X.SnipeHits()
	T.check("hit: only the units at or under the max", hits[1] and hits[1].qty, 20)
	T.check("hit: from the search now", hits[1] and hits[1].est, nil)
	T.check("still one alert", said("listed at"), 1)
	-- the same price again in the next scan (15 minutes later): not told again
	W.advance(901)
	T.ok("second scan", T.fullScan(X))
	W.advance(5)
	T.check("same price within 30 minutes: quiet", said("listed at"), 1)
	-- a lower price: told again
	W.list(2589, 40, 5, 1, "Dan")
	W.advance(901)
	T.ok("third scan", T.fullScan(X))
	W.advance(5)
	T.check("lower price: told", said("listed at"), 2)
	T.ok("at 40c", has(W.said("listed at")[2] or "", "listed at 40c"), W.said("listed at")[2])
	-- more than 30 minutes later, the same price: told again
	W.advance(1900)
	T.ok("fourth scan", T.fullScan(X))
	W.advance(5)
	T.check("after 30 minutes: told again", said("listed at"), 3)
	-- all gone: the hit goes with the next reading
	W.ah = {}
	W.advance(901)
	T.ok("fifth scan", T.fullScan(X))
	W.advance(2)
	T.check("hit gone when none are listed", #X.SnipeHits(), 0)
	T.check("nothing was bought", #W.won, 0)
	T.check("no restricted call", #W.restrictedCalls, 0)
	W.closeAH()
end)

T.scene("alerts-away: price alert from a browse and from another search; the sniper on as before", function()
	local X = W.start()
	X.SetWatchMax("2589", 60)
	X.SetWatchMax("2592", 600)
	W.list(2589, 55, 10, 1, "Ann")
	W.list(2592, 500, 4, 1, "Bob")
	W.openAH()
	W.env.C_AuctionHouse.SendBrowseQuery({searchString = "Linen"})
	W.advance(3)
	T.check("browse: one alert", said("price alert: Linen Cloth listed at 55c"), 1)
	-- a search that is not the sniper's (the Buy or Sell tab)
	X.LiveSearch("2592")
	W.advance(3)
	T.check("search: alert", said("price alert: Wool Cloth listed at 5s"), 1)
	T.ok("search: says how many", has(W.said("Wool Cloth listed")[1] or "", "4 available"), W.said("Wool Cloth listed")[1])
	T.check("two hits", #X.SnipeHits(), 2)
	-- searched again, same price: quiet
	X.LiveSearch("2592")
	W.advance(3)
	T.check("search again: quiet", said("Wool Cloth listed"), 1)
	-- the sniper itself still says "sniper:" for its own new hits
	X.SetWatchMax("2770", 3000)
	W.list(2770, 2500, 2, 1, "Cid")
	X.SnipeStart()
	W.advance(20)
	T.ok("the sniper's own line", said("sniper:") >= 1, table.concat(W.chat, "\n"))
	T.check("sniper hit not told twice as a price alert", said("Copper Ore listed"), 1)
	X.SnipeStop()
	T.check("nothing was bought", #W.won, 0)
	W.closeAH()
end)

T.scene("alerts-away: AskAlert sets the watch max; the item page button", function()
	local X = W.start()
	X.Record("2589", X.Now() - 60, 100, 110, 50, 5, "Linen Cloth", 1)
	X.AskAlert("2589")
	local d = dialog()
	T.ok("asks", d and d:IsShown())
	T.ok("the question", d and has(W.plain(d.title:GetText() or ""), "Alert me when Linen Cloth is listed at or under:"))
	W.type(d.line, "1g 20s", true)
	T.check("watched", X.Watched("2589"), true)
	T.check("max set", X.WatchMax("2589"), 12000)
	T.ok("told", said("price alert: Linen Cloth at or under 1g 20s") == 1, table.concat(W.chat, "\n"))
	-- the item page shows it and changes it
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = itemPanel(X)
	T.ok("button shows the alert price", W.findButton("Alert under 1g 20s", panel) ~= nil, W.screen(panel))
	W.click("Alert under 1g 20s", panel)
	T.ok("asks again", d:IsShown())
	T.check("box shows the price", W.plain(d.line:GetText() or ""), "1g 20s")
	W.type(d.line, "", true)
	W.advance(0.5)
	T.check("removed", X.WatchMax("2589"), nil)
	T.check("still watched", X.Watched("2589"), true)
	T.ok("button: no alert", W.findButton("Alert me under", panel) ~= nil)
	T.ok("told off", said("price alert off for Linen Cloth") == 1)
end)

T.scene("alerts-away: mailbox line - what is new since the last line", function()
	local X = W.start()
	W.advance(5)
	W.addMail(W.mailSold(2589, 1000, 20, "Ann Lee", 50))
	W.addMail(W.mailSold(2592, 400, 5, "Bob Stone", 20))
	W.addMail(W.mailExpired(2770, 4))
	W.addMail(W.mailWon(3576, 300, 3, "Cid Moss"))
	W.addMail(W.mailCancelled(3576, 2)) -- cancelled by you: not told
	W.openMail()
	W.advance(3)
	local lines = W.said("Since you were last here")
	T.check("one line", #lines, 1)
	T.ok("the line", has(lines[1] or "", "Since you were last here: sold 25 items for 13s 30c, 4 came back unsold, bought 3"), lines[1])
	-- read again (the mailbox changes, opens again): nothing new, no line
	W.fire("MAIL_INBOX_UPDATE")
	W.advance(3)
	W.closeMail()
	W.openMail()
	W.advance(3)
	T.check("nothing new: no line", said("Since you were last here"), 1)
	W.closeMail()
	-- one more sale later: only that
	W.advance(3600)
	W.addMail(W.mailSold(2589, 5000, 1, "Dan Ray", 250))
	W.openMail()
	W.advance(3)
	lines = W.said("Since you were last here")
	T.check("a second line", #lines, 2)
	T.ok("only what happened", lines[2] == "XNAH Since you were last here: sold 1 item for 47s 50c" or has(lines[2] or "", "Since you were last here: sold 1 item for 47s 50c") and not has(lines[2], "unsold"), lines[2])
	T.ok("last told kept per character", (X.db.chars["Xn Ascalon"].awayTold or 0) > 0)
	-- switched off
	W.closeMail()
	X.S().awayLine = false
	W.addMail(W.mailExpired(2589, 1))
	W.openMail()
	W.advance(3)
	T.check("off: no line", said("Since you were last here"), 2)
	W.closeMail()
end)

T.scene("alerts-away: login line - away time, auctions run out, gold in the mailboxes", function()
	local X = W.start()
	W.advance(5)
	W.openAH()
	W.mine(2589, 100, 5)                -- 24 hours left
	local short = W.mine(2592, 100, 5)  -- 1 hour left
	short.seconds = 3600
	W.ownedChanged()
	local me = X.db.chars["Xn Ascalon"]
	T.check("end times kept", me.aucEnds and #me.aucEnds, 2)
	W.closeAH()
	W.addMail({sender = "Ann Lee", subject = "for you", money = 50000})
	W.openMail()
	W.closeMail()
	T.check("gold in the mailbox seen", me.mailMoney, 50000)
	-- a quick reload: nothing
	W.fire("PLAYER_LOGOUT")
	W.advance(60)
	X = W.reload()
	W.advance(12)
	T.check("short break: no line", said("Welcome back"), 0)
	-- away two hours: the 1-hour auction has run out
	W.fire("PLAYER_LOGOUT")
	W.advance(7200)
	X = W.reload()
	W.advance(8)
	T.check("not before 10 s", said("Welcome back"), 0)
	W.advance(4)
	local lines = W.said("Welcome back")
	T.check("one line", #lines, 1)
	T.ok("the line", has(lines[1] or "", "Welcome back - you were away 2 hours. Of the 2 auctions you left up, 1 has run out of " ..
		"time by now. 5g waiting in your mailboxes. Open the mailbox to see what sold."), lines[1])
	-- after a day: both have run out
	W.fire("PLAYER_LOGOUT")
	W.advance(86400 + 3600)
	X = W.reload()
	W.advance(12)
	lines = W.said("Welcome back")
	T.ok("the one left up has run out", has(lines[2] or "", "you were away 1 day 1 hour. The auction you left up has run out of time by now."), lines[2])
	-- nothing to say (no auctions left up, no gold in the mail): no line
	me = X.db.chars["Xn Ascalon"]
	me.aucEnds, me.mailMoney = {}, 0
	W.fire("PLAYER_LOGOUT")
	W.advance(7200)
	X = W.reload()
	W.advance(12)
	T.check("nothing to say: no line", said("Welcome back"), 2)
	-- the text alone: auctions still running
	local now = X.Now()
	X.db.chars["Xn Ascalon"].mailMoney = 10000
	local text = W.plain(X.AwayLoginText(now - 7200, {now + 600, now + 900}, now) or "")
	T.ok("still running", text and has(text, "Your 2 auctions are still running.") and has(text, "1g waiting"), text)
	text = W.plain(X.AwayLoginText(now - 7200, {now - 9000, now - 600, now - 300}, now) or "")
	T.ok("all run out (one that ended before you left not counted)", has(text, "All 2 auctions you left up have run out of time by now."), text)
	-- switched off
	X.S().awayLine = false
	W.fire("PLAYER_LOGOUT")
	W.advance(7200)
	X = W.reload()
	W.advance(12)
	T.check("off: no line", said("Welcome back"), 2)
end)

-- day prices: fn(i, wday) -> price of the day i days ago (i = n-1 .. 0), recorded at noon in time order
local function days(X, key, name, n, fn)
	local today = X.Day()
	for i = n - 1, 0, -1 do
		local d = today - i
		local t = d * 86400 + 43200
		if t > X.Now() then t = X.Now() - 60 end
		local w = os.date("*t", d * 86400 + 43200).wday
		local v = math.floor(fn(i, w) + 0.5)
		X.Record(key, t, v, v, 50, 5, name, 1)
	end
end

T.scene("alerts-away: best day to sell - little data, a Tuesday bump, a steady trend", function()
	local X = W.start()
	T.check("unknown item", X.BestDay("2589"), nil)
	-- ten days: not enough
	days(X, "2589", "Linen Cloth", 10, function(i, w) return w == 3 and 1100 or 1000 end)
	T.check("ten days: nil", X.BestDay("2589"), nil)
	-- under three weeks: still nil
	days(X, "2592", "Wool Cloth", 19, function(i, w) return w == 3 and 1100 or 1000 end)
	T.check("19 days: nil", X.BestDay("2592"), nil)
	-- six weeks with Tuesdays 10% higher
	days(X, "2770", "Copper Ore", 42, function(i, w) return w == 3 and 1100 or 1000 end)
	local bd = X.BestDay("2770")
	T.check("Tuesday found", bd and bd.day, 3)
	T.check("name", bd and bd.name, "Tuesday")
	T.check("short", bd and bd.short, "Tue")
	T.near("about +10%", bd and bd.pct, 10, 2.5)
	T.ok("weeks", bd and bd.weeks >= 5, bd and bd.weeks)
	T.ok("cached (same table)", X.BestDay("2770") == bd)
	-- a price rising every day (and one falling): no weekday is better
	days(X, "3576", "Tin Bar", 42, function(i) return 1000 + (42 - i) * 25 end)
	T.check("rising price: nil", X.BestDay("3576"), nil)
	days(X, "2771", "Tin Ore", 42, function(i) return 3000 - (42 - i) * 30 end)
	T.check("falling price: nil", X.BestDay("2771"), nil)
	-- a rising price with a Saturday bump: Saturday, not fooled by the trend
	days(X, "2840", "Copper Bar", 42, function(i, w) return (1000 + (42 - i) * 20) * (w == 7 and 1.08 or 1) end)
	bd = X.BestDay("2840")
	T.check("trend + Saturday bump: Saturday", bd and bd.name, "Saturday")
	-- a 1% bump is not "clearly higher"
	days(X, "4306", "Silk Cloth", 42, function(i, w) return w == 3 and 1010 or 1000 end)
	T.check("1% is too little", X.BestDay("4306"), nil)
	-- the tooltip line and the item page row, only when known
	local function tipHas(key, text)
		for _, l in ipairs(X.TooltipLines(key)) do if has(W.plain(l[1] .. " " .. l[2]), text) then return true end end
		return false
	end
	T.ok("tooltip: best day", tipHas("2770", "Best day to sell Tuesday (+10%)") or tipHas("2770", "Best day to sell Tuesday (+9%)") or
		tipHas("2770", "Best day to sell Tuesday (+11%)"))
	T.ok("tooltip: none when unknown", not tipHas("3576", "Best day"))
	X.UI.Toggle()
	X.UI.ShowItem("2770")
	W.advance(0.5)
	local panel = itemPanel(X)
	local screen = W.screen(panel)
	T.ok("item page: the row", has(screen, "Best day to sell") and has(screen, "Tuesday ("), screen)
	X.UI.ShowItem("3576")
	W.advance(0.5)
	T.ok("item page: no row when unknown", not has(W.screen(panel), "Best day to sell"))
end)

T.scene("alerts-away: one mail take per call (for the next-step key)", function()
	local X = W.start()
	W.advance(5)
	local ok, text = X.MailTakeOne()
	T.check("closed: no", ok, false)
	T.check("closed: why", text, "Open your mailbox first.")
	local sold = W.addMail(W.mailSold(2589, 1000, 20, "Ann Lee", 50))
	local won = W.addMail(W.mailWon(2592, 400, 10, "Bob Stone"))
	local friend = W.addMail({sender = "Ann Lee", subject = "for you", money = 500})
	W.openMail()
	local takes = #W.mailTakes
	ok, text = X.MailTakeOne()
	T.check("first: taken", ok, true)
	T.check("one take", #W.mailTakes - takes, 1)
	T.check("gold first", W.mailTakes[#W.mailTakes] and W.mailTakes[#W.mailTakes].what, "money")
	T.ok("says what", text and text:find("took 9s 50c from an auction house mail", 1, true), text)
	T.check("the ledger read it first", #X.Ledger().sales, 1)
	ok, text = X.MailTakeOne()
	T.check("server busy: no take", ok, false)
	T.ok("busy: why", text and text:find("busy", 1, true), text)
	T.check("still one take", #W.mailTakes - takes, 1)
	W.advance(0.5)
	ok, text = X.MailTakeOne()
	T.check("second: the item", ok, true)
	T.ok("says the item", text and text:find("took 10 x Wool Cloth", 1, true), text)
	W.advance(0.5)
	ok, text = X.MailTakeOne()
	T.check("nothing left", ok, false)
	T.check("nothing left: why", text, "No auction house mail with gold or items left.")
	T.check("mail from a player untouched", friend.money, 500)
	T.check("two takes in all", #W.mailTakes - takes, 2)
	-- full bags: items wait
	W.addMail(W.mailExpired(2770, 4))
	W.bagRoom = 0
	W.advance(0.5)
	ok, text = X.MailTakeOne()
	T.check("bags full: no", ok, false)
	T.ok("bags full: why", text and text:find("bags are full", 1, true), text)
	-- Open all still works as before
	W.bagRoom = 100
	W.click("Open all auction mail")
	W.advance(5)
	T.ok("Open all took the rest", #W.mailTakes - takes >= 3, #W.mailTakes - takes)
	W.closeMail()
end)
