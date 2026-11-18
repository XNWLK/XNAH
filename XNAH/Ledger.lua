-- Sales and purchase ledger: learned from the auction house mails when you open your mailbox.
--   X.Realm().ledger = {sales = {...}, buys = {...}, expired = {...}, cancelled = {...}, seen = {[fingerprint] = t}}
--   an entry = {t (when it happened), key (item key, nil when the item is not known yet), name, count, money (the whole
--     sale or purchase price), cut (what the auction house kept), deposit, who (buyer or seller), char (your character),
--     pending = true (sold, the money is not in the mailbox yet)}
-- Sold auctions bring an invoice ("seller"); a sale whose money is still on its way first brings a "sale pending" one
-- ("seller_temp_invoice") - recorded once, and the real one an hour later only finishes it. Won auctions bring a
-- "buyer" invoice. Expired and cancelled auctions bring no invoice: their subject tells.
-- A mail is never counted twice: each one gets a fingerprint (kind, item, player, money, count, arrival time to 10
-- minutes; the arrival is worked out from the days the mail has left, 30 for auction mails) kept 35 days.
local ADDON, X = ...

local DAY = 86400
local KEEP_DAYS = 365      -- entries are kept this long
local SEEN_DAYS = 35       -- fingerprints are kept this long (auction mails last 30 days)
local MAIL_DAYS = 30       -- an auction house mail has this many days left when it arrives
local BUCKET = 600         -- arrival times are rounded to 10 minutes
local LISTS = {"sales", "buys", "expired", "cancelled"}

local function ledger()
	local r = X.Realm()
	local L = r.ledger
	if not L then
		L = {}
		r.ledger = L
	end
	for _, name in ipairs(LISTS) do L[name] = L[name] or {} end
	L.seen = L.seen or {}
	return L
end
X.Ledger = ledger

-- [[ subjects of mails without an invoice ]] the game's text with %s turned into a capture
local function subjectPattern(fmt)
	if type(fmt) ~= "string" or fmt == "" then return nil end
	local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	p = p:gsub("%%%%s", "(.+)")
	return "^" .. p .. "$"
end
local patterns
local function subjectKind(subject)
	if not patterns then
		patterns = {}
		local function add(kind, fmt)
			local p = subjectPattern(fmt)
			if p then patterns[#patterns + 1] = {kind, p} end
		end
		add("expired", AUCTION_EXPIRED_MAIL_SUBJECT)
		add("expired", "Auction expired: %s")
		add("cancelled", AUCTION_REMOVED_MAIL_SUBJECT)
		add("cancelled", "Auction canceled: %s")
		add("cancelled", "Auction cancelled: %s")
	end
	if type(subject) ~= "string" then return nil end
	for _, p in ipairs(patterns) do
		local name = subject:match(p[2])
		if name then return p[1], (name:gsub("%s*%(%d+%)$", "")) end
	end
	return nil
end
X.LedgerSubject = subjectKind

-- [[ item keys from names ]] a link when there is one; else a known item with exactly that name; else the game's cache
local nameCache = {}
local byName -- [lower case name] = key of the known items; made once per mailbox read when needed
local function keyFor(link, name)
	local key = link and X.KeyFromLink(link)
	if key then return key end
	if not name or name == "" then return nil end
	if nameCache[name] then return nameCache[name] end
	if not byName then
		byName = {}
		for k, it in pairs(X.Items()) do
			if it.n and it.n ~= "" then
				local ln = it.n:lower()
				if not byName[ln] or #k < #byName[ln] then byName[ln] = k end
			end
		end
	end
	key = byName[name:lower()]
	if not key and C_Item and C_Item.GetItemInfo then
		local _, glink = X.Try(C_Item.GetItemInfo, name)
		key = glink and X.KeyFromLink(glink) or nil
	end
	if key then nameCache[name] = key end
	return key
end
X.LedgerKeyFor = function(link, name) byName = nil local k = keyFor(link, name) byName = nil return k end

-- [[ the summary per item ]] worked out again only when the ledger changed
local index, indexDay, covered
local SPEED_DAYS = 30 -- soldPerDay looks at this many days
local function invalidate() index = nil end
local function buildIndex()
	index = {}
	local L = ledger()
	local now = X.Now()
	indexDay = X.Day(now)
	local since = now - SPEED_DAYS * DAY
	-- the days the ledger covers out of the last 30 (from its oldest entry of any kind; at least one day)
	local first = now
	for _, name in ipairs(LISTS) do
		for _, e in ipairs(L[name]) do if e.t and e.t < first then first = e.t end end
	end
	covered = math.max(1, math.min(SPEED_DAYS, (now - first) / DAY))
	local function slot(e)
		local id = e.key or ("n:" .. (e.name or "?"):lower())
		local s = index[id]
		if not s then
			s = {key = e.key, name = e.name, sold = 0, soldValue = 0, bought = 0, boughtValue = 0, expired = 0, cancelled = 0,
				nSold = 0, nBought = 0, last = 0, sold30 = 0}
			index[id] = s
		end
		if e.t and e.t > s.last then s.last = e.t end
		return s
	end
	for _, e in ipairs(L.sales) do
		local s = slot(e)
		s.sold = s.sold + (e.count or 1)
		s.soldValue = s.soldValue + (e.money or 0) - (e.cut or 0)
		s.nSold = s.nSold + 1
		if (e.t or 0) >= since then s.sold30 = s.sold30 + (e.count or 1) end
	end
	for _, e in ipairs(L.buys) do
		local s = slot(e)
		s.bought = s.bought + (e.count or 1)
		s.boughtValue = s.boughtValue + (e.money or 0)
		s.nBought = s.nBought + 1
	end
	for _, e in ipairs(L.expired) do local s = slot(e) s.expired = s.expired + (e.count or 1) end
	for _, e in ipairs(L.cancelled) do local s = slot(e) s.cancelled = s.cancelled + (e.count or 1) end
	return index
end

-- the numbers worked out from the sums: averages, sell-through and profit
-- profit = what the sales brought (after the cut) minus what the sold units cost you, at your average buying price
-- (units you never bought - farmed or crafted - cost nothing here)
local function finish(s)
	local out = {sold = s.sold, soldValue = s.soldValue, bought = s.bought, boughtValue = s.boughtValue,
		expired = s.expired, cancelled = s.cancelled, key = s.key, name = s.name, last = s.last}
	local posted = s.sold + s.expired + s.cancelled
	out.sellThrough = posted > 0 and s.sold / posted or nil
	out.avgSell = s.sold > 0 and s.soldValue / s.sold or nil
	out.avgBuy = s.bought > 0 and s.boughtValue / s.bought or nil
	out.profit = s.soldValue - (out.avgBuy or 0) * math.min(s.sold, s.bought)
	-- units you sold a day over the last 30 days (or over the days since the ledger's first entry, when fewer)
	out.soldPerDay = (s.sold30 or 0) / (covered or SPEED_DAYS)
	return out
end

-- X.LedgerItem(key) -> {sold (units), soldValue (copper after the cut), bought, boughtValue, expired, cancelled,
-- sellThrough (0..1 or nil), avgSell, avgBuy, profit, soldPerDay (units you sold a day over the last 30 days, or over
-- the days since the ledger's first entry when it is younger; 0 when none sold lately)} or nil when never traded
function X.LedgerItem(key)
	if not key then return nil end
	key = tostring(key)
	local idx = (index and indexDay == X.Day()) and index or buildIndex()
	local a = idx[key]
	-- entries saved by name only (the item was not known then)
	local name = X.ItemName(key)
	local b = name and idx["n:" .. name:lower()]
	if not a and not b then return nil end
	local s = {key = key, name = name, sold = 0, soldValue = 0, bought = 0, boughtValue = 0, expired = 0, cancelled = 0, last = 0, sold30 = 0}
	for _, part in ipairs({a or false, b or false}) do
		if part then
			for _, f in ipairs({"sold", "soldValue", "bought", "boughtValue", "expired", "cancelled", "sold30"}) do s[f] = s[f] + part[f] end
			if part.last > s.last then s.last = part.last end
		end
	end
	return finish(s)
end

-- every item traded: rows {key or nil, name, sold, soldValue, bought, boughtValue, expired, cancelled, sellThrough,
-- avgSell, avgBuy, profit, soldPerDay, last}
function X.LedgerByItem()
	local idx = (index and indexDay == X.Day()) and index or buildIndex()
	local out = {}
	for _, s in pairs(idx) do out[#out + 1] = finish(s) end
	table.sort(out, function(a, b) return a.last > b.last end)
	return out
end

-- the latest entries, newest first: rows {t, what ("sold" / "bought" / "expired" / "cancelled"), key, name, count,
-- money (after the cut for a sale), char, pending}
function X.LedgerRecent(limit)
	local L = ledger()
	local out = {}
	local function add(list, what)
		for _, e in ipairs(list) do
			local money = e.money
			if what == "sold" and money then money = money - (e.cut or 0) end
			out[#out + 1] = {t = e.t, what = what, key = e.key, name = e.name, count = e.count, money = money,
				who = e.who, char = e.char, pending = e.pending}
		end
	end
	add(L.sales, "sold")
	add(L.buys, "bought")
	add(L.expired, "expired")
	add(L.cancelled, "cancelled")
	table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
	if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
	return out
end

-- X.LedgerTotals(fromTime) -> {income (sales after the cut), spent, cut, profit (income - spent), sales, buys (numbers
-- of mails)}; fromTime nil = everything kept
function X.LedgerTotals(from)
	local L = ledger()
	from = from or 0
	local r = {income = 0, spent = 0, cut = 0, profit = 0, sales = 0, buys = 0}
	for _, e in ipairs(L.sales) do
		if (e.t or 0) >= from then
			r.income = r.income + (e.money or 0) - (e.cut or 0)
			r.cut = r.cut + (e.cut or 0)
			r.sales = r.sales + 1
		end
	end
	for _, e in ipairs(L.buys) do
		if (e.t or 0) >= from then
			r.spent = r.spent + (e.money or 0)
			r.buys = r.buys + 1
		end
	end
	r.profit = r.income - r.spent
	return r
end

-- X.LedgerDays(days) -> {{day, income, spent}, ...} one per day, oldest first, the last `days` days (today included)
function X.LedgerDays(days)
	days = days or 30
	local today = X.Day()
	local first = today - days + 1
	local out, byDay = {}, {}
	for d = first, today do
		local row = {day = d, income = 0, spent = 0}
		out[#out + 1] = row
		byDay[d] = row
	end
	local L = ledger()
	for _, e in ipairs(L.sales) do
		local row = byDay[X.Day(e.t or 0)]
		if row then row.income = row.income + (e.money or 0) - (e.cut or 0) end
	end
	for _, e in ipairs(L.buys) do
		local row = byDay[X.Day(e.t or 0)]
		if row then row.spent = row.spent + (e.money or 0) end
	end
	return out
end

-- is there anything in the ledger at all?
function X.LedgerEmpty()
	local L = ledger()
	return #L.sales == 0 and #L.buys == 0 and #L.expired == 0 and #L.cancelled == 0
end

-- [[ keeping it small ]] entries older than a year and fingerprints older than 35 days go
local function prune(now)
	local L = ledger()
	local limit = now - KEEP_DAYS * DAY
	for _, name in ipairs(LISTS) do
		local list, keep = L[name], {}
		for _, e in ipairs(list) do if (e.t or 0) >= limit then keep[#keep + 1] = e end end
		if #keep ~= #list then L[name] = keep end
	end
	local seenLimit = now - SEEN_DAYS * DAY
	for fp, t in pairs(L.seen) do if t < seenLimit then L.seen[fp] = nil end end
end

-- entries saved by name only get their item key once the item is known (a few per mailbox visit)
local function resolveNames()
	local L = ledger()
	local tries = 0
	for _, name in ipairs(LISTS) do
		for _, e in ipairs(L[name]) do
			if not e.key and e.name and tries < 20 then
				tries = tries + 1
				e.key = keyFor(nil, e.name)
			end
		end
	end
end

-- [[ reading the mailbox ]]
-- a pending sale that this real invoice finishes: same item, count, price and buyer, from up to 3 hours before
local function findSale(L, name, count, money, who, from, to, pending)
	for i = #L.sales, 1, -1 do
		local e = L.sales[i]
		if (e.pending == true) == pending and e.name == name and e.count == count and e.money == money
			and (e.who == who or not e.who or not who) and (e.t or 0) >= from and (e.t or 0) <= to then
			return e
		end
	end
	return nil
end

local function readMail()
	if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
	local n = X.Try(GetInboxNumItems) or 0
	local L = ledger()
	local now = X.Now()
	local char = X.CharKey and X.CharKey() or "?"
	local occurrences, added = {}, 0
	byName = nil
	for i = 1, n do
		local _, _, _, subject, _, _, daysLeft = X.Try(GetInboxHeaderInfo, i)
		local kind, name, who, money, count, cut, deposit, link
		local itype, iname, iplayer, bid, _, ideposit, consignment, _, _, _, icount
		if GetInboxInvoiceInfo then
			itype, iname, iplayer, bid, _, ideposit, consignment, _, _, _, icount = X.Try(GetInboxInvoiceInfo, i)
		end
		if itype == "seller" or itype == "seller_temp_invoice" then
			kind = itype == "seller" and "sale" or "pend"
			name, who, money, count, cut, deposit = iname, iplayer, bid, icount, consignment, ideposit
		elseif itype == "buyer" then
			kind = "buy"
			name, who, money, count = iname, iplayer, bid, icount
			link = GetInboxItemLink and X.Try(GetInboxItemLink, i, 1)
		else
			local sk, sname = subjectKind(X.Plain(subject))
			if sk then
				kind, name = sk, sname
				link = GetInboxItemLink and X.Try(GetInboxItemLink, i, 1)
				if GetInboxItem then
					local iname2, _, _, c = X.Try(GetInboxItem, i, 1)
					if iname2 and iname2 ~= "" then name = iname2 end
					count = c
				end
			end
		end
		if kind and name and name ~= "" then
			count = (count and count > 0) and count or 1
			local arrival = now - (MAIL_DAYS - (tonumber(daysLeft) or MAIL_DAYS)) * DAY
			if arrival > now then arrival = now end
			local b = math.floor(arrival / BUCKET + 0.5)
			local base = kind .. "|" .. name .. "|" .. tostring(who or "") .. "|" .. tostring(money or 0) .. "|" .. count
			-- the n-th mail exactly like this one in this mailbox (two equal sales at the same moment are two sales)
			local nth = (occurrences[base .. "|" .. b] or 0) + 1
			occurrences[base .. "|" .. b] = nth
			local seen = false
			for d = -1, 1 do
				if L.seen[base .. "|" .. (b + d) .. "#" .. nth] then seen = true break end
			end
			if not seen then
				L.seen[base .. "|" .. b .. "#" .. nth] = arrival
				local key = keyFor(link, name)
				local e = {t = arrival, key = key, name = name, count = count, money = money, who = who, char = char}
				if kind == "sale" then
					-- the real invoice of a sale recorded while its money was on the way: that one is finished
					local p = findSale(L, name, count, money, who, arrival - 3 * 3600, arrival + BUCKET * 2, true)
					if p then
						p.pending, p.cut, p.deposit = nil, cut, deposit
					else
						e.cut, e.deposit = cut, deposit
						table.insert(L.sales, e)
					end
					added = added + 1
				elseif kind == "pend" then
					-- the real invoice was read first (both in the mailbox): nothing new
					if not findSale(L, name, count, money, who, arrival - BUCKET * 2, arrival + 3 * 3600, false) then
						e.cut, e.deposit, e.pending = cut, deposit, true
						table.insert(L.sales, e)
						added = added + 1
					end
				elseif kind == "buy" then
					table.insert(L.buys, e)
					added = added + 1
				elseif kind == "expired" or kind == "cancelled" then
					e.money = nil
					table.insert(L[kind], e)
					added = added + 1
				end
			end
		end
	end
	prune(now)
	resolveNames()
	byName = nil
	invalidate()
	if added > 0 then
		X.Debug("ledger: " .. added .. " new auction house mail" .. (added == 1 and "" or "s"))
		X.Fire("XNAH_LEDGER")
	end
end
X.LedgerReadMail = readMail

X.On("MAIL_SHOW", function() X.Debounce("xnah-ledger-mail", 0.5, readMail) end)
X.On("MAIL_INBOX_UPDATE", function() X.Debounce("xnah-ledger-mail", 0.5, readMail) end)
X.On("XNAH_LOGIN", function()
	invalidate()
	nameCache = {}
	prune(X.Now())
end)
