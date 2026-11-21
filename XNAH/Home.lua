-- The home page (tab Home, UIHome.lua): the numbers of the day and a to-do list with one button per job.
--   X.HomeNumbers() -> {gold (all characters of this realm), goldToday, goldWeek (changes; nil before XNAH
--     has seen the gold), goldDays (days the 7-day change covers), chars, today = {income (sales after the cut), units,
--     sales (mails), spent, bought, expired, cancelled}, week = the same for the last 7 days (today included),
--     profitWeek (income - spent), top = {{key, name, income, units}, ...} (best sellers of the last 7 days, at most 5),
--     best = top[1], worth, worthWeek (net worth and its change over 7 days), lastFull, scanAge (seconds), scanLeft
--     (seconds until the server allows the next full scan), scanReady, scanning, ahOpen}
--   X.HomeTodo() -> the jobs, most urgent first: {{id, text, why, button, tab, view = function(panel) (after the tab
--     opened: picks a view there), action = function() (a safe action instead; never buys, posts or cancels), count}}
-- Gold of the day: XNAH notes each character's gold the first time it sees it on a day:
--   X.Realm().homeGold = {[day] = {[character] = copper}}  (15 days kept; day = your local calendar day)
-- "Today" = gold now minus that; "7 days" = gold now minus the oldest note of the last 7 days.
-- Kept cheap: the numbers are worked out again only after something changed (or a minute passed); the deals count is
-- one pass over all items in slices, at most once a minute and only while someone looks at the home page.
local ADDON, X = ...

X.Default("homeFirst", true)    -- the window opens on Home the first time each session
X.Default("homeScanHours", 24)  -- a full scan older than this many hours is a job

local DAY = 86400
local KEEP_DAYS = 15
local SLICE = 300      -- items looked at per frame for the deals count
local MAX_AGE = 60     -- seconds: numbers are worked out again at least this often; the deals pass at most this often
local TOP = 5
local RECENT = 3 * DAY -- expired auctions of the last 3 days are jobs

-- [[ days ]] the start of your local day (midnight where you are), and a number for it
local function dayStart(t)
	t = t or X.Now()
	local tt = date("*t", t)
	if type(tt) ~= "table" or not tt.hour then return t - t % DAY end
	return t - (tt.hour * 3600 + tt.min * 60 + tt.sec)
end
X.HomeDayStart = dayStart
local function dayOf(t) return math.floor((dayStart(t) + DAY / 2) / DAY) end

-- your characters of this realm (both factions): {[name] = record}
local function realmChars()
	local rk = X.realmKey or X.RealmKey()
	local out = {}
	for k, c in pairs((X.db and X.db.chars) or {}) do
		if c.realm == rk then out[k] = c end
	end
	return out
end
local function goldBook()
	local r = X.Realm()
	r.homeGold = r.homeGold or {}
	return r.homeGold
end
-- notes each character's gold once a day (the first time it is seen that day)
function X.HomeRecordGold()
	if not X.db then return end
	local book = goldBook()
	local today = dayOf()
	local g = book[today]
	if not g then
		g = {}
		book[today] = g
	end
	for k, c in pairs(realmChars()) do
		if c.money and g[k] == nil then g[k] = c.money end
	end
	for d in pairs(book) do
		if d <= today - KEEP_DAYS then book[d] = nil end
	end
end

-- [[ the numbers ]]
local function newSums() return {income = 0, units = 0, sales = 0, spent = 0, bought = 0, expired = 0, cancelled = 0} end

local function goldNumbers(n)
	local book = goldBook()
	local today = dayOf()
	if not book[today] then -- a new day while playing: it starts with the gold now
		X.HomeRecordGold()
		book = goldBook()
	end
	local total, chars, dToday, dWeek, any, oldest = 0, 0, 0, 0, false, today
	for k, c in pairs(realmChars()) do
		if c.money then
			total = total + c.money
			chars = chars + 1
			local base = book[today] and book[today][k]
			if base then
				dToday = dToday + c.money - base
				any = true
			end
			for d = today - 6, today do
				local v = book[d] and book[d][k]
				if v then
					dWeek = dWeek + c.money - v
					if d < oldest then oldest = d end
					break
				end
			end
		end
	end
	n.gold, n.chars = total, chars
	n.goldToday = any and dToday or nil
	n.goldWeek = any and dWeek or nil
	n.goldDays = today - oldest + 1
end

local function ledgerNumbers(n, now)
	local today, week = newSums(), newSums()
	n.today, n.week = today, week
	n.top = {}
	local L = X.Ledger and X.Ledger()
	if not L then return end
	local t0 = dayStart(now)
	local w0 = t0 - 6 * DAY
	local by = {}
	for _, e in ipairs(L.sales or {}) do
		local t = e.t or 0
		if t >= w0 then
			local inc, units = (e.money or 0) - (e.cut or 0), e.count or 1
			week.income, week.units, week.sales = week.income + inc, week.units + units, week.sales + 1
			if t >= t0 then today.income, today.units, today.sales = today.income + inc, today.units + units, today.sales + 1 end
			local id = e.key or ("n:" .. tostring(e.name))
			local b = by[id]
			if not b then
				b = {key = e.key, name = e.name, income = 0, units = 0}
				by[id] = b
			end
			b.income, b.units = b.income + inc, b.units + units
		end
	end
	for _, e in ipairs(L.buys or {}) do
		local t = e.t or 0
		if t >= w0 then
			week.spent, week.bought = week.spent + (e.money or 0), week.bought + (e.count or 1)
			if t >= t0 then today.spent, today.bought = today.spent + (e.money or 0), today.bought + (e.count or 1) end
		end
	end
	for _, what in ipairs({"expired", "cancelled"}) do
		for _, e in ipairs(L[what] or {}) do
			local t = e.t or 0
			if t >= w0 then
				week[what] = week[what] + (e.count or 1)
				if t >= t0 then today[what] = today[what] + (e.count or 1) end
			end
		end
	end
	local list = {}
	for _, b in pairs(by) do list[#list + 1] = b end
	table.sort(list, function(a, b)
		if a.income ~= b.income then return a.income > b.income end
		return tostring(a.key or a.name) < tostring(b.key or b.name)
	end)
	for i = 1, math.min(TOP, #list) do n.top[i] = list[i] end
	n.best = n.top[1]
end

local function worthNumbers(n, now)
	if not X.WorthHistory then return end
	local points = X.WorthHistory(nil, now - 8 * DAY)
	local last = points[#points]
	if not last then return end
	n.worth = last[2]
	for _, p in ipairs(points) do
		if p[1] >= now - 7.5 * DAY and p ~= last then
			n.worthWeek = last[2] - p[2]
			break
		end
	end
end

local numbers, numbersAt, numbersDirty = nil, 0, true
function X.HomeNumbers()
	local now = X.Now()
	if not numbers or numbersDirty or now - numbersAt >= MAX_AGE then
		local n = {}
		goldNumbers(n)
		ledgerNumbers(n, now)
		worthNumbers(n, now)
		n.profitWeek = n.week.income - n.week.spent
		numbers, numbersAt, numbersDirty = n, now, false
	end
	-- these change by the second: always now
	local n = numbers
	n.lastFull = X.Realm().lastFull
	n.scanAge = n.lastFull and math.max(0, now - n.lastFull) or nil
	n.scanLeft = X.FullScanLeft()
	n.scanReady = X.FullScanReady()
	n.scanning = X.scan.state ~= "idle"
	n.ahOpen = X.ahOpen == true
	return n
end

-- [[ the deals count ]] the same test as X.Deals (Market.lua), over all items in slices
local deals = {n = 0, best = nil, at = nil}
local dealsDirty, dealsRunning = true, false
local todoDirty = true
local function dealsPass()
	dealsRunning = true
	local items = X.Items()
	local S = X.S()
	local keys, k = nil, 0
	local found = {n = 0}
	X.Job("home deals", function()
		if not keys then
			keys = {}
			for key in pairs(items) do keys[#keys + 1] = key end
			return #keys == 0
		end
		local stop = math.min(#keys, k + SLICE)
		while k < stop do
			k = k + 1
			local key = keys[k]
			local it = items[key]
			local cur = it and it.cur
			if cur and cur.min and (cur.qty or 0) > 0 and X.Fresh(it) then
				local usual, st = X.Usual(key)
				if usual and st and st.days >= S.minSamples then
					local profit = X.AfterCut(usual) - cur.min
					if cur.min / usual * 100 <= S.dealPct and profit >= S.dealMinProfit then
						found.n = found.n + 1
						if not found.best or profit > found.best.profit then found.best = {key = key, profit = profit} end
					end
				end
			end
		end
		return k >= #keys
	end, function()
		found.at = GetTime()
		deals = found
		dealsRunning = false
		todoDirty = true
		X.Fire("XNAH_HOME")
	end)
end
local function dealsCheck()
	if dealsRunning then return end
	if deals.at and GetTime() - deals.at > 600 then dealsDirty = true end -- prices get old with time
	if not dealsDirty then return end
	local wait = deals.at and (deals.at + MAX_AGE - GetTime()) or 0
	if wait > 0 then
		X.Debounce("xnah-home-deals", wait + 0.1, dealsCheck)
		return
	end
	dealsDirty = false
	dealsPass()
end
-- for the tests: forget the deals count
function X.HomeForget()
	deals, dealsDirty, todoDirty, numbersDirty = {n = 0}, true, true, true
end

-- [[ the to-do list ]]
local function plural(n, one, many) return X.Num(n) .. " " .. (n == 1 and one or (many or one .. "s")) end
local function openView(setting, value)
	return function()
		X.S()[setting] = value
	end
end
local function clickButton(field)
	return function(panel)
		local b = panel and panel[field]
		if b and b.Click then b:Click() end
	end
end

-- the full scan as a job: urgent = no scan yet, or prices too old to use (first in the list); else only "getting old"
local function scanJob(n, urgent)
	if n.scanning then return nil end
	local S = X.S()
	local job = {id = "scan", tab = "scan", button = "Scan"}
	local stale = not n.lastFull or n.scanAge > S.staleHours * 3600
	if urgent ~= stale then return nil end
	if not n.lastFull then
		job.text = "No full scan yet"
		job.why = "XNAH needs prices first: one full scan reads every auction at once."
	elseif stale then
		job.text = "Prices are " .. (X.Ago(n.lastFull):gsub(" ago", "")) .. " old - too old for deals"
		job.why = "Prices older than " .. S.staleHours .. " hours are not used for deals and strategies."
	elseif n.scanAge > S.homeScanHours * 3600 then
		job.text = "Last full scan " .. X.Ago(n.lastFull)
		job.why = "A fresh scan finds today's deals and keeps the price history going."
	else
		return nil
	end
	if n.ahOpen and n.scanReady then
		job.button, job.tab = "Scan now", nil
		job.action = function() X.FullScan() end
		job.why = job.why .. " The server allows one now."
	elseif n.ahOpen then
		job.why = job.why .. " The server allows the next one in " .. X.Clock(n.scanLeft) .. "."
	else
		job.why = job.why .. " Open the auction house to scan."
	end
	return job
end

local function computeTodo()
	local jobs = {}
	local function add(job) if job then jobs[#jobs + 1] = job end end
	local n = X.HomeNumbers()
	local now = X.Now()
	local me = X.CharKey and X.db.chars and X.db.chars[X.CharKey()] or nil
	-- prices missing or too old: first
	add(scanJob(n, true))

	-- expired auctions of the last days: waiting in the mailbox, or back in your bags to post again
	local L = X.Ledger and X.Ledger()
	if L and me then
		local inMail, inBags, seen = 0, 0, {}
		local myName = X.CharKey()
		for _, e in ipairs(L.expired or {}) do
			if (e.t or 0) >= now - RECENT and e.key and (not e.char or e.char == myName) and not seen[e.key] then
				seen[e.key] = true
				if me.mail and (me.mail[e.key] or 0) > 0 then inMail = inMail + 1
				elseif me.bags and (me.bags[e.key] or 0) > 0 then inBags = inBags + 1 end
			end
		end
		if inMail > 0 then
			add({id = "expiredMail", count = inMail, text = plural(inMail, "expired auction") .. " waiting in your mailbox",
				why = "Take " .. (inMail == 1 and "it" or "them") .. " at a mailbox, then post again in tab Sell.",
				button = "Gold", tab = "gold", view = openView("goldView", "recent")})
		end
		if inBags > 0 then
			add({id = "expiredBags", count = inBags, text = plural(inBags, "expired item") .. " back in your bags",
				why = "Post " .. (inBags == 1 and "it" or "them") .. " again in tab Sell (at the auction house).",
				button = "Sell", tab = "sell"})
		end
	end

	-- gold waiting in mailboxes (as seen the last time each character opened one)
	local mailGold, mailChars = 0, 0
	for _, c in pairs(realmChars()) do
		if (c.mailMoney or 0) > 0 then
			mailGold = mailGold + c.mailMoney
			mailChars = mailChars + 1
		end
	end
	if mailGold > 0 then
		add({id = "mailGold", count = mailChars, text = X.Money(mailGold, true) .. " waiting in " ..
			(mailChars == 1 and "a mailbox" or (mailChars .. " mailboxes")),
			why = "Gold from sales you have not taken yet (as seen at the last visit). Tab Gold, view Characters, shows who has it.",
			button = "Gold", tab = "gold", view = openView("goldView", "chars")})
	end

	-- your auctions that someone undercut (known after a cancel scan), or a check when the auction house is open
	local c = X.cancel
	if c and c.state == "done" and #(c.rows or {}) > 0 then
		add({id = "undercut", count = #c.rows, text = plural(#c.rows, "of your auctions is undercut", "of your auctions are undercut"),
			why = "Someone sells cheaper. Cancel and post again, one click each, in tab Sell.",
			button = "Show", tab = "sell", view = clickButton("viewCancel")})
	elseif n.ahOpen and c and c.state == "idle" and X.CancelScan and me and next(me.auctions or {}) then
		local count = 0
		for _ in pairs(me.auctions) do count = count + 1 end
		add({id = "checkUndercut", count = count, text = "Check your auctions for undercuts",
			why = "You have " .. plural(count, "item") .. " on the auction house. The check searches each one (it buys and cancels nothing).",
			button = "Check", tab = "sell", action = function() X.CancelScan() end, view = clickButton("viewCancel")})
	end

	-- watched items listed at or under your max price (the sniper's hits, and the last scan)
	local under = {}
	if X.SnipeHits then
		for _, h in ipairs(X.SnipeHits()) do under[h.key] = true end
	end
	for key in pairs(X.db.watch or {}) do
		local max = X.WatchMax(key)
		local it = max and X.Items()[key]
		if it and it.cur and it.cur.min and (it.cur.qty or 0) > 0 and X.Fresh(it) and it.cur.min <= max then under[key] = true end
	end
	local nUnder = 0
	for _ in pairs(under) do nUnder = nUnder + 1 end
	if nUnder > 0 then
		add({id = "watch", count = nUnder, text = plural(nUnder, "watched item is", "watched items are") .. " under your max price",
			why = "Listed at or under the most you said you would pay. Buy in tab Buy (the auction house must be open).",
			button = "Buy", tab = "buy"})
	end

	-- deals now
	dealsCheck()
	if (deals.n or 0) > 0 then
		local best = deals.best
		add({id = "deals", count = deals.n, text = plural(deals.n, "deal") .. " listed now" ..
			(best and (" - the best makes " .. X.Money(best.profit, true)) or ""),
			why = "Listed far under their usual price" .. (best and (" (best: " .. X.ItemText(best.key) .. ")") or "") .. ".",
			button = "Deals", tab = "deals"})
	end

	-- the strategies you follow
	if X.Strategies and X.StrategyRows and X.StrategyOn then
		local total, parts = 0, {}
		for _, s in ipairs(X.Strategies()) do
			if X.StrategyOn(s.key) then
				local rows = X.StrategyRows(s.key)
				if rows and #rows > 0 then
					total = total + #rows
					parts[#parts + 1] = s.name .. " " .. #rows
				end
			end
		end
		if total > 0 then
			add({id = "strategies", count = total, text = "Your strategies found " .. plural(total, "item"),
				why = table.concat(parts, ", ", 1, math.min(3, #parts)) .. (#parts > 3 and ", ..." or ""),
				button = "Deals", tab = "deals"})
		end
	end

	-- the crafting queue
	if X.QueueRows then
		local rows = X.QueueRows()
		local crafts, recipes = 0, 0
		for _, r in ipairs(rows) do
			if (r.craft or 0) > 0 then crafts, recipes = crafts + r.craft, recipes + 1 end
		end
		if crafts > 0 then
			local toBuy = 0
			if X.QueueMaterials then
				for _, m in ipairs((X.QueueMaterials(rows))) do if (m.buy or 0) > 0 then toBuy = toBuy + 1 end end
			end
			local job = {id = "queue", count = crafts, button = "Queue", tab = "craft", view = openView("craftView", "queue")}
			if toBuy == 0 then
				job.text = plural(crafts, "craft") .. " ready in your queue"
				job.why = "You have every material. Open your profession window and press Craft next in tab Crafting."
			else
				job.text = plural(crafts, "craft") .. " in your queue, " .. plural(toBuy, "material") .. " to buy"
				job.why = "Tab Crafting, view Queue, puts the materials on a shopping list."
			end
			add(job)
		end
	end

	-- your shopping lists
	if X.ShopLists and X.ShopList and X.ShopNeed then
		local left = 0
		for _, name in ipairs(X.ShopLists()) do
			local l = X.ShopList(name)
			for _, e in ipairs((l and l.items) or {}) do if X.ShopNeed(e) > 0 then left = left + 1 end end
		end
		if left > 0 then
			add({id = "shop", count = left, text = plural(left, "item") .. " left on your shopping lists",
				why = "Buy them in tab Buy while the auction house is open.", button = "Buy", tab = "buy"})
		end
	end

	-- your bags: things worth more on the auction house
	if X.BagRows and me then
		local count, value = 0, 0
		for _, r in ipairs(X.BagRows()) do
			if r.best == "Auction house" and r.ah and r.ah > 0 then count, value = count + 1, value + r.ah end
		end
		if count > 0 and value >= 10000 then
			add({id = "bags", count = count, text = plural(count, "item") .. " in your bags worth " .. X.Money(value, true) ..
				" on the auction house", why = "After the cut, at today's prices. Tab Sell posts them, one click each.",
				button = "Sell", tab = "sell"})
		end
	end

	-- the last full scan is getting old (not urgent)
	add(scanJob(n, false))

	if #jobs == 0 then
		add({id = "nothing", text = "Nothing to do right now",
			why = "Come back after your next visit to the auction house or the mailbox.", button = "Market", tab = "market"})
	end
	return jobs
end

local todo, todoAt = nil, 0
function X.HomeTodo()
	-- worked out again after a change, but not more than once a second (the window asks often)
	if not todo or todoDirty or GetTime() - todoAt >= MAX_AGE then
		if todo and GetTime() - todoAt < 1 then
			X.Debounce("xnah-home-todo", 1, function() X.Fire("XNAH_HOME") end)
		else
			todoDirty = false
			todoAt = GetTime()
			todo = computeTodo()
		end
	end
	return todo
end

-- [[ when to work things out again ]]
local function changed()
	numbersDirty, todoDirty = true, true
end
for _, e in ipairs({"XNAH_LEDGER", "XNAH_INVENTORY", "XNAH_STRATEGY", "XNAH_SNIPE", "XNAH_QUEUE", "XNAH_SHOP",
	"XNAH_CANCEL", "XNAH_WATCH", "XNAH_AH", "XNAH_POSTED", "XNAH_RECIPES"}) do
	X.On(e, changed)
end
X.On("XNAH_PRICES", function()
	changed()
	dealsDirty = true
end)
X.On("XNAH_SCAN", function()
	-- a scan starting or ending changes the scan job; its progress does not
	local state = X.scan.state
	if state == "idle" or state == "waiting" then todoDirty = true end
end)
X.On("XNAH_INVENTORY", function() X.Debounce("xnah-home-gold", 2, X.HomeRecordGold) end)
X.On("XNAH_LOGIN", function()
	-- before this session changes any gold: the notes of the day start from what was saved last time
	X.HomeRecordGold()
	changed()
	if X.S().homeFirst then X.S().tab = "home" end
end)
