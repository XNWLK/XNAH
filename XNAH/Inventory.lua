-- Inventory and net worth of your characters (this realm and faction): what each one has in its bags, bank, mailbox and
-- on the auction house, and its gold - saved when you log in, open the bank or the mailbox, or look at your auctions.
--   Characters of your OTHER WoW accounts come from tools/sync-accounts.js (run on the PC with the game closed): their
--   records carry acct = that account's name and are only read here; XNAHDB.sync = {at, label, accounts} tells when.
--   XNAHDB.chars[character] = {realm = "Realm-Faction", money, bags = {[item key] = count}, bank = {...}, mail = {...},
--     mailMoney, auctions = {...}, bound = {[item key] = true} (soulbound), at, bagsAt, bankAt, mailAt, aucAt}
--   XNAHDB.warbank = {items = {[item key] = count}, bound = {...}, at}  the account bank (shared by all characters)
--   XNAHDB.worth[character] = "day,copper;..."  net worth once a day (base 36, a year kept)
--   XNAHDB.worthTotal["Realm-Faction"] = "day,copper;..."  all characters of the realm and the account bank together
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
	local items = {}
	for _, a in ipairs(list) do
		local status = X.Plain(a.status)
		if status == nil or status == 0 then
			local key = X.KeyFromLink(X.Plain(a.itemLink))
			local ik = a.itemKey
			if not key and ik and ik.itemID then
				key = (ik.itemSuffix and ik.itemSuffix ~= 0) and (ik.itemID .. ":" .. ik.itemSuffix) or tostring(ik.itemID)
			end
			if key then items[key] = (items[key] or 0) + (X.Plain(a.quantity) or 1) end
		end
	end
	local c = me()
	c.auctions = items
	c.aucAt = X.Now()
	c.at = c.aucAt
	changed()
end
X.InventoryScan = {bags = scanBags, bank = scanBank, mail = scanMail, auctions = scanAuctions, money = scanMoney}

X.On("XNAH_LOGIN", function()
	ownedCache = {}
	me()
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
-- of this realm and faction, richest first
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
