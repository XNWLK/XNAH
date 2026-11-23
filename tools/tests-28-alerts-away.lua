-- XNAH test scenes, part 28 (v0.8, helper C): the "while you were away" lines (mailbox and login) and the best day to
-- sell.

local function has(text, part) return text:find(part, 1, true) ~= nil end
local function said(part) return #W.said(part) end
local function itemPanel(X) return X.UI.tabs.item and X.UI.tabs.item.panel end

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
