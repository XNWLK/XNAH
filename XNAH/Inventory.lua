-- Inventory and net worth of your characters (this realm, both factions): what each one has in its bags, bank, mailbox and
-- on the auction house, and its gold - saved when you log in, open the bank or the mailbox, or look at your auctions.
--   Characters of your OTHER WoW accounts come from tools/sync-accounts.js (run on the PC with the game closed): their
--   records carry acct = that account's name and are only read here; XNAHDB.sync = {at, label, accounts} tells when.
--   XNAHDB.chars[character] = {realm = "Realm-Faction", money, bags = {[item key] = count}, bank = {...}, mail = {...},
--     mailMoney, auctions = {...}, bound = {[item key] = true} (soulbound), at, bagsAt, bankAt, mailAt, aucAt,
--     aucEnds = {time, ...} (when each of your auctions runs out, as last seen), seen (logout time), awayTold}
--   XNAHDB.warbank = {items = {[item key] = count}, bound = {...}, at}  the account bank (shared by all characters)
--   XNAHDB.worth[character] = "day,copper;..."  net worth once a day (base 36, a year kept)
--   XNAHDB.worthTotal["Realm-Faction"] = "day,copper;..."  all characters of the realm and the account bank together
--   X.Realm().goldHist[character] = "day,copper;..."  each character's gold (base 36), a point only on a day it changed
--     (the gold stays the same until the next point); after 90 days one point a week, a year kept (X.GoldHistory)
-- Worth = gold + items at their auction house price after the cut (soulbound items: what a vendor pays; no price: the
-- vendor price; neither: nothing).
local ADDON, X = ...

local BAGS = {0, 1, 2, 3, 4, 5}                  -- backpack, 4 bags, reagent bag
local BANK = {6, 7, 8, 9, 10, 11, 12, 13, 14}    -- character bank tabs
local WARBANK = {15, 16, 17, 18, 19, 20, 21, 22, 23} -- account bank tabs
local ATTACH = 16
local KEEP_DAYS = 365
local SLICE = 200 -- slots read per frame

local bankOpen = false
local ownedCache = {}
-- the most seconds a time-left band can mean (0 short, 1 medium, 2 long, 3 very long), when the game gives no seconds
local BAND_SECS = {[0] = 1800, [1] = 7200, [2] = 43200, [3] = 172800}

local function db()
	local d = X.db
	d.chars = d.chars or {}
	d.worth = d.worth or {}
	d.worthTotal = d.worthTotal or {}
	return d
end
local function realmKey() return X.realmKey or X.RealmKey() end
-- this character's record
local function me()
	local d = db()
	local k = X.CharKey()
	local c = d.chars[k]
	if not c then
		c = {bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
		d.chars[k] = c
	end
	c.realm = realmKey()
	c.acct = nil -- written by this account (characters of your other accounts come with acct = their name, see below)
	c.bags, c.bank, c.mail, c.auctions, c.bound = c.bags or {}, c.bank or {}, c.mail or {}, c.auctions or {}, c.bound or {}
	return c, k
end
X.InventoryMe = me

local function changed()
	ownedCache = {}
	X.Fire("XNAH_INVENTORY")
	X.Debounce("xnah-worth", 3, function() X.RecordWorth() end)
end

-- [[ reading containers ]] in slices; done(items, bound, anySlots)
local function readBags(bags, name, done)
	if X.JobRunning(name) then
		X.Debounce(name, 1, function() readBags(bags, name, done) end)
		return
	end
	if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
	local items, bound = {}, {}
	local bi, any = 0, false
	X.Job(name, function()
		local slots = 0
		while bi < #bags and slots < SLICE do
			bi = bi + 1
			local bag = bags[bi]
			local n = X.Plain(X.Try(C_Container.GetContainerNumSlots, bag)) or 0
			if n > 0 then any = true end
			for s = 1, n do
				local info = X.Try(C_Container.GetContainerItemInfo, bag, s)
				local id = info and X.Plain(info.itemID)
				if id then
					local key = X.KeyFromLink(X.Plain(info.hyperlink)) or tostring(id)
					items[key] = (items[key] or 0) + (X.Plain(info.stackCount) or 1)
					if X.Plain(info.isBound) then bound[key] = true end
				end
			end
			slots = slots + n
		end
		return bi >= #bags
	end, function() done(items, bound, any) end)
end

-- soulbound marks: the new ones of one place, plus the old ones still held somewhere else
local function mergeBound(c, fresh, other1, other2)
	local out = {}
	for k in pairs(fresh) do out[k] = true end
	for k in pairs(c.bound) do
		if (other1 and other1[k]) or (other2 and other2[k]) then out[k] = true end
	end
	c.bound = out
end

local function scanBags()
	readBags(BAGS, "xnah-bags", function(items, bound)
		local c = me()
		c.bags = items
		mergeBound(c, bound, c.bank, nil)
		c.bagsAt = X.Now()
		c.at = c.bagsAt
		changed()
	end)
end
local function scanBank()
	if not bankOpen then return end
	readBags(BANK, "xnah-bank", function(items, bound)
		if not bankOpen then return end
		local c = me()
		c.bank = items
		mergeBound(c, bound, c.bags, nil)
		c.bankAt = X.Now()
		c.at = c.bankAt
		changed()
	end)
	readBags(WARBANK, "xnah-warbank", function(items, bound, any)
		if not bankOpen or not any then return end -- not readable here (no account bank, or another character has it)
		db().warbank = {items = items, bound = bound, at = X.Now()}
		changed()
	end)
end
local function scanMoney()
	local m = X.Plain(GetMoney and GetMoney())
	if not m then return end
	local c = me()
	if c.money ~= m then
		c.money = m
		c.at = X.Now()
		changed()
	end
end
-- the mailbox: everything attached (cash-on-delivery mails left out: not yours until paid) and the gold in it
local function scanMail()
	if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
	local n = X.Try(GetInboxNumItems) or 0
	local items, money = {}, 0
	for i = 1, n do
		local _, _, _, _, m, cod, _, itemCount = X.Try(GetInboxHeaderInfo, i)
		money = money + (X.Plain(m) or 0)
		if (X.Plain(cod) or 0) == 0 and (X.Plain(itemCount) or 0) > 0 then
			for a = 1, ATTACH do
				local link = GetInboxItemLink and X.Try(GetInboxItemLink, i, a)
				local id, count
				if GetInboxItem then
					local _
					_, id, _, count = X.Try(GetInboxItem, i, a)
				end
				local key = X.KeyFromLink(link) or (id and tostring(id))
				if key then items[key] = (items[key] or 0) + (count or 1) end
			end
		end
	end
	local c = me()
	c.mail, c.mailMoney = items, money
	c.mailAt = X.Now()
	c.at = c.mailAt
	changed()
end
-- your auctions (the game sends them when the auction house shows your auctions); sold ones are in the mail already
local function scanAuctions()
	if not (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctions) then return end
	local list = X.Try(C_AuctionHouse.GetOwnedAuctions)
	if type(list) ~= "table" then return end
	local items, ends = {}, {}
	local seen = {} -- for the ledger's postings (time to sell): {id, key, qty, secs (nil when the game gives none), price, active}
	local now = X.Now()
	for _, a in ipairs(list) do
		local status = X.Plain(a.status)
		if status == nil or status == 0 then
			-- when it runs out (for the line at login): the seconds left, else the longest its time band can mean
			local exact = X.Plain(a.timeLeftSeconds)
			local secs = exact
			if type(secs) ~= "number" then secs = BAND_SECS[X.Plain(a.timeLeft) or -1] end
			if secs then ends[#ends + 1] = now + math.floor(secs) end
			local key = X.KeyFromLink(X.Plain(a.itemLink))
			local ik = a.itemKey
			if not key and ik and ik.itemID then
				key = (ik.itemSuffix and ik.itemSuffix ~= 0) and (ik.itemID .. ":" .. ik.itemSuffix) or tostring(ik.itemID)
			end
			local qty = X.Plain(a.quantity) or 1
			if key then items[key] = (items[key] or 0) + qty end
			seen[#seen + 1] = {id = X.Plain(a.auctionID), key = key, qty = qty, secs = type(exact) == "number" and exact or nil,
				price = X.Plain(a.buyoutAmount), active = true}
		end
	end
	if X.LedgerSawAuctions then X.LedgerSawAuctions(seen, now) end
	local c = me()
	c.auctions = items
	table.sort(ends)
	c.aucEnds = ends
	c.aucAt = X.Now()
	c.at = c.aucAt
	changed()
end
X.InventoryScan = {bags = scanBags, bank = scanBank, mail = scanMail, auctions = scanAuctions, money = scanMoney}

-- [[ "Welcome back" ]] about 10 s after login (after the other login lines): how long you were away, how many of the
-- auctions you left up have run out of time since, the gold waiting in your mailboxes. Nothing after a short break or
-- when there is nothing to say. Setting awayLine (Ledger.lua).
local AWAY_MIN = 30 * 60 -- away at least this long
local function span(s)
	local d, h, m = math.floor(s / 86400), math.floor((s % 86400) / 3600), math.floor((s % 3600) / 60)
	local function u(n, w) return n .. " " .. w .. (n == 1 and "" or "s") end
	if d > 0 then return u(d, "day") .. (h > 0 and (" " .. u(h, "hour")) or "") end
	if h > 0 then return u(h, "hour") end
	return u(m, "minute")
end
-- the line for: seen (when you logged out), ends (end times of your auctions then), now; nil when nothing to say
function X.AwayLoginText(seen, ends, now)
	now = now or X.Now()
	if not seen or now - seen < AWAY_MIN then return nil end
	local up, ended = 0, 0
	for _, t in ipairs(ends or {}) do
		if t > seen then
			up = up + 1
			if t <= now then ended = ended + 1 end
		end
	end
	local mailMoney = 0
	local rk = realmKey()
	for _, c in pairs(db().chars) do
		if c.realm == rk then mailMoney = mailMoney + (c.mailMoney or 0) end
	end
	if ended == 0 and mailMoney == 0 then return nil end
	local parts = {"Welcome back - you were away " .. span(now - seen) .. "."}
	if up > 0 and ended == 0 then
		parts[#parts + 1] = "Your " .. X.Num(up) .. " auction" .. (up == 1 and " is" or "s are") .. " still running."
	elseif up == 1 then
		parts[#parts + 1] = "The auction you left up has run out of time by now."
	elseif ended == up then
		parts[#parts + 1] = "All " .. X.Num(up) .. " auctions you left up have run out of time by now."
	elseif up > 0 then
		parts[#parts + 1] = "Of the " .. X.Num(up) .. " auctions you left up, " .. X.Num(ended) ..
			(ended == 1 and " has" or " have") .. " run out of time by now."
	end
	if mailMoney > 0 then parts[#parts + 1] = X.Money(mailMoney, true) .. " waiting in your mailboxes." end
	parts[#parts + 1] = "Open the mailbox to see what sold."
	return table.concat(parts, " ")
end

X.On("PLAYER_LOGOUT", function()
	if not X.db then return end
	local c = me()
	c.seen = X.Now()
end)

X.On("XNAH_LOGIN", function()
	ownedCache = {}
	local c = me()
	-- read before anything of this login changes them
	local seen, ends = c.seen or c.at, c.aucEnds
	X.After(10, function()
		if not X.S().awayLine then return end
		local text = X.AwayLoginText(seen, ends)
		if text then X.Print(text) end
	end)
	X.After(3, function()
		scanMoney()
		scanBags()
	end)
	X.After(8, function() X.RecordWorth() end)
end)
X.On("BAG_UPDATE_DELAYED", function()
	X.Debounce("xnah-inv-bags", 1, function()
		scanBags()
		if bankOpen then scanBank() end
	end)
end)
X.On("PLAYER_MONEY", function() X.Debounce("xnah-inv-money", 1, scanMoney) end)
X.On("BANKFRAME_OPENED", function()
	bankOpen = true
	X.Debounce("xnah-inv-bank", 0.5, scanBank)
end)
X.On("BANKFRAME_CLOSED", function() bankOpen = false end)
X.On("PLAYERBANKSLOTS_CHANGED", function() X.Debounce("xnah-inv-bank", 1, scanBank) end)
X.On("PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", function() X.Debounce("xnah-inv-bank", 1, scanBank) end)
X.On("MAIL_INBOX_UPDATE", function() X.Debounce("xnah-inv-mail", 0.7, scanMail) end)
X.On("OWNED_AUCTIONS_UPDATED", function() X.Debounce("xnah-inv-auctions", 0.5, scanAuctions) end)

-- [[ values ]]
-- one of an item: soulbound = what a vendor pays; else the auction house price after the cut, else the vendor price
function X.UnitWorth(key, bound)
	local vendor = X.VendorSell(X.KeyID(key))
	if bound then return vendor or 0 end
	return X.AfterCut(X.Price(key)) or vendor or 0
end
local function placeValue(list, bound)
	local v = 0
	for key, n in pairs(list or {}) do v = v + X.UnitWorth(key, bound and bound[key]) * n end
	return v
end
-- worth of one character: total, {money, bags, bank, mail, auctions}
function X.CharWorth(c)
	local p = {gold = c.money or 0, bags = placeValue(c.bags, c.bound), bank = placeValue(c.bank, c.bound),
		mail = placeValue(c.mail, nil) + (c.mailMoney or 0), auctions = placeValue(c.auctions, nil)}
	return p.gold + p.bags + p.bank + p.mail + p.auctions, p
end
function X.WarbankWorth()
	local w = db().warbank
	if not w then return 0 end
	return placeValue(w.items, w.bound)
end

-- X.Chars() -> list of {name, money, worth, at, key, gold, bags, bank, mail, auctions (values), me = true for this one}
-- of this realm (both factions), richest first
function X.Chars()
	local d = db()
	local rk = realmKey()
	local mine = X.CharKey()
	local out = {}
	for k, c in pairs(d.chars) do
		if c.realm == rk then
			local total, p = X.CharWorth(c)
			out[#out + 1] = {name = k, key = k, money = c.money or 0, worth = total, at = c.at, gold = p.gold, bags = p.bags,
				bank = p.bank, mail = p.mail, auctions = p.auctions, me = k == mine, acct = c.acct}
		end
	end
	table.sort(out, function(a, b)
		if a.worth ~= b.worth then return a.worth > b.worth end
		return a.name < b.name
	end)
	return out
end

-- X.Owned(itemID) -> total, {bags, bank, mail, auctions (this character), alts (your other characters here), warbank}
-- an "id:suffix" key counts only that version; a number or plain id counts every version of the item
function X.Owned(id)
	local ck = tostring(id)
	if ownedCache[ck] then
		local r = ownedCache[ck]
		return r.total, r.parts
	end
	local exact = ck:find(":", 1, true) and ck or nil
	local num = X.KeyID(ck)
	local function count(list)
		local n = 0
		if not list then return 0 end
		if exact then return list[exact] or 0 end
		for k, v in pairs(list) do
			if k == ck or X.KeyID(k) == num then n = n + v end
		end
		return n
	end
	local d = db()
	local rk = realmKey()
	local mine = X.CharKey()
	local parts = {bags = 0, bank = 0, mail = 0, auctions = 0, alts = 0, warbank = 0}
	for k, c in pairs(d.chars) do
		if c.realm == rk then
			if k == mine then
				parts.bags, parts.bank, parts.mail, parts.auctions = count(c.bags), count(c.bank), count(c.mail), count(c.auctions)
			else
				parts.alts = parts.alts + count(c.bags) + count(c.bank) + count(c.mail) + count(c.auctions)
			end
		end
	end
	if d.warbank then parts.warbank = count(d.warbank.items) end
	local total = parts.bags + parts.bank + parts.mail + parts.auctions + parts.alts + parts.warbank
	ownedCache[ck] = {total = total, parts = parts}
	return total, parts
end

-- forget a character (its bags, bank, gold and net worth history)
function X.DeleteChar(k)
	local d = db()
	d.chars[k] = nil
	d.worth[k] = nil
	local gh = X.Realm().goldHist
	if gh then gh[k] = nil end
	changed()
end

-- [[ net worth history ]] "day,copper;..." - today's point is replaced, a year is kept
local function setPoint(s, day, value)
	s = s or ""
	local tail = s:match("[^;]*$") or ""
	local point = X.b36(day) .. "," .. X.b36(value)
	if tail ~= "" and X.n36(tail:match("^([^,]*)")) == day then
		s = s:sub(1, #s - #tail) .. point
	else
		s = (s ~= "" and (s .. ";") or "") .. point
	end
	-- drop points older than a year
	while true do
		local first = X.n36(s:match("^([^,;]*)"))
		if not first or first >= day - KEEP_DAYS then break end
		local cut = s:find(";", 1, true)
		if not cut then s = "" break end
		s = s:sub(cut + 1)
	end
	return s
end
function X.RecordWorth()
	if not X.db then return end
	local d = db()
	local c, k = me()
	local today = X.Day()
	d.worth[k] = setPoint(d.worth[k], today, X.CharWorth(c))
	local total = X.WarbankWorth()
	for _, row in ipairs(X.Chars()) do total = total + row.worth end
	local rk = realmKey()
	d.worthTotal[rk] = setPoint(d.worthTotal[rk], today, total)
	X.RecordGoldHistory()
end
-- points {{t, copper}, ...} for a graph, oldest first; charKey nil = all characters together
function X.WorthHistory(charKey, from)
	local d = db()
	local s = charKey and d.worth[charKey] or d.worthTotal[realmKey()]
	local out = {}
	for p in (s or ""):gmatch("[^;]+") do
		local day, v = p:match("^([^,]*),(.*)$")
		day, v = X.n36(day), X.n36(v)
		if day and v then
			local t = day * 86400 + 43200
			if t >= (from or 0) then out[#out + 1] = {t, v} end
		end
	end
	return out
end

-- [[ gold history ]] X.Realm().goldHist[character] = "day,copper;..." (see the top of this file). Written by
-- X.RecordGoldHistory (with the net worth, after the gold of a character changed) for every character of this realm
-- whose gold XNAH knows (your other accounts' characters too, with the gold of their last sync). A new character's
-- history starts with the gold of the day notes (X.Realm().homeGold, up to 15 days back).
local GOLD_DAILY = 90 -- days with every change kept; older ones keep one point a week
local function parsePoints(s)
	local out = {}
	for p in (s or ""):gmatch("[^;]+") do
		local day, v = p:match("^([^,]*),(.*)$")
		day, v = X.n36(day), X.n36(v)
		if day and v then out[#out + 1] = {day, v} end
	end
	return out
end
local function joinPoints(list)
	local parts = {}
	for i, p in ipairs(list) do parts[i] = X.b36(p[1]) .. "," .. X.b36(p[2]) end
	return table.concat(parts, ";")
end
-- the list thinned: points older than 90 days one a week (the last of each week), older than a year dropped except the
-- newest of those (moved to a year ago: it still tells the gold from then on)
local function thinPoints(list, today)
	local out, old = {}, nil
	local yearAgo, daily = today - KEEP_DAYS, today - GOLD_DAILY
	for i, p in ipairs(list) do
		if p[1] <= yearAgo then
			old = {yearAgo, p[2]}
		elseif p[1] < daily then
			local nx = list[i + 1]
			-- keep the last point of its week (weeks of 7 days counted from day 0)
			if not nx or math.floor(nx[1] / 7) ~= math.floor(p[1] / 7) or nx[1] >= daily then out[#out + 1] = p end
		else
			out[#out + 1] = p
		end
	end
	if old and (not out[1] or out[1][1] > yearAgo) then table.insert(out, 1, old) end
	return out
end
local lastGold = {} -- [character] = "day:copper" written last (this session): nothing to do while it stays the same
local function goldHist()
	local r = X.Realm()
	r.goldHist = r.goldHist or {}
	return r.goldHist
end
-- a character's gold `value` on `day`: today's point is replaced, a point equal to the one before is not added
local function addGold(s, day, value, today)
	local list = parsePoints(s)
	local last = list[#list]
	if last and last[1] == day then
		last[2] = value
		local before = list[#list - 1]
		if before and before[2] == value then list[#list] = nil end
	elseif last and last[1] > day then
		return s -- an older reading than what is kept: nothing
	elseif last and last[2] == value then
		return s
	else
		list[#list + 1] = {day, value}
	end
	return joinPoints(thinPoints(list, today))
end
X.GoldHistAdd = addGold
function X.RecordGoldHistory()
	if not X.db then return end
	local d = db()
	local rk = realmKey()
	local book = goldHist()
	local today = X.Day()
	for k, c in pairs(d.chars) do
		if c.realm == rk and type(c.money) == "number" then
			local day = math.min(today, X.Day(c.at or X.Now()))
			if k == X.CharKey() then day = today end
			local sig = day .. ":" .. c.money
			if lastGold[k] ~= sig then
				lastGold[k] = sig
				local s = book[k]
				if s == nil then
					-- a new history: the gold of the day notes first (local day numbers, close enough to the server's)
					s = ""
					local notes = X.Realm().homeGold or {}
					local days = {}
					for nd, chars in pairs(notes) do if type(chars) == "table" and chars[k] then days[#days + 1] = nd end end
					table.sort(days)
					for _, nd in ipairs(days) do
						if nd < day then s = addGold(s, nd, notes[nd][k], today) end
					end
				end
				book[k] = addGold(s, day, c.money, today)
			end
		end
	end
end
-- forget what was written this session (the tests, after a reload of the saved data)
function X.GoldHistForget() lastGold = {} end

-- the characters of this realm with a gold history or known gold: {{key, name, gold}, ...} richest first
function X.GoldChars()
	local d = db()
	local rk = realmKey()
	local out = {}
	for k, c in pairs(d.chars) do
		if c.realm == rk and (type(c.money) == "number" or goldHist()[k]) then
			out[#out + 1] = {key = k, name = k, gold = c.money or 0, me = k == X.CharKey()}
		end
	end
	table.sort(out, function(a, b)
		if a.gold ~= b.gold then return a.gold > b.gold end
		return a.key < b.key
	end)
	return out
end

-- X.GoldHistory(keys, fromDay) -> points {{t, copper}, ...}, one per day from fromDay (or the first day known) to
-- today, oldest first. keys = one character's key, a list of keys (added up), or nil = every character of this realm.
-- Between points the gold stays the same; today is the gold now. Before a character's first point its first known
-- gold counts (so a character XNAH learns about later does not make the total jump). Empty when nothing is known.
function X.GoldHistory(keys, fromDay)
	local d = db()
	local rk = realmKey()
	local book = goldHist()
	local today = X.Day()
	local list = {}
	if type(keys) == "string" then
		list[1] = keys
	elseif type(keys) == "table" then
		list = keys
	else
		for k, c in pairs(d.chars) do if c.realm == rk then list[#list + 1] = k end end
	end
	local series, first = {}, nil
	for _, k in ipairs(list) do
		local pts = parsePoints(book[k])
		local c = d.chars[k]
		if c and type(c.money) == "number" then
			local last = pts[#pts]
			if last and last[1] == today then last[2] = c.money
			elseif not last or last[2] ~= c.money then pts[#pts + 1] = {today, c.money} end
		end
		if #pts > 0 then
			series[#series + 1] = {pts = pts, i = 1}
			if not first or pts[1][1] < first then first = pts[1][1] end
		end
	end
	local out = {}
	if not first then return out end
	local start = math.max(first, fromDay or first)
	for day = start, today do
		local sum = 0
		for _, s in ipairs(series) do
			local pts = s.pts
			while pts[s.i + 1] and pts[s.i + 1][1] <= day do s.i = s.i + 1 end
			sum = sum + pts[s.i][2]
		end
		out[#out + 1] = {day * 86400 + 43200, sum}
	end
	return out
end

-- [[ your bags: sell or keep? ]]
-- "Auction house", "Vendor", "Keep (bound)" or nil (no price anywhere). An item that sells under 0.2 a day goes to the
-- vendor unless the auction house pays at least 3 times as much.
function X.BestPlace(key, bound)
	if bound then return "Keep (bound)" end
	local ah = X.AfterCut(X.Price(key))
	local vendor = X.VendorSell(X.KeyID(key))
	if not ah then return vendor and "Vendor" or nil end
	if vendor and vendor >= ah then return "Vendor" end
	if X.SaleRate and vendor then
		local rate = X.SaleRate(key)
		if rate and rate < 0.2 and ah < vendor * 3 then return "Vendor" end
	end
	return "Auction house"
end
-- rows {key, count, ah (all of them, after the cut), vendor (all of them), best, rate (sold per day), bound}
function X.BagRows()
	local c = me()
	local out = {}
	for key, n in pairs(c.bags) do
		local bound = c.bound[key] or false
		local ahUnit = (not bound) and X.AfterCut(X.Price(key)) or nil
		local vUnit = X.VendorSell(X.KeyID(key))
		local rate = X.SaleRate and X.SaleRate(key) or nil
		out[#out + 1] = {key = key, count = n, ah = ahUnit and ahUnit * n, vendor = vUnit and vUnit * n,
			best = X.BestPlace(key, bound), rate = rate, bound = bound}
	end
	table.sort(out, function(a, b)
		local va, vb = a.ah or a.vendor or 0, b.ah or b.vendor or 0
		if va ~= vb then return va > vb end
		return a.key < b.key
	end)
	return out
end
