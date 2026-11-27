-- Reading the auction house.
--   Full scan: C_AuctionHouse.ReplicateItems() hands over every auction at once (the server allows it about every
--     15 minutes). Read in slices so the game never stalls, then one market value per item, and every known item
--     that was not seen counts as sold out.
--   While you use the auction house normally, every list it shows is recorded too: browse results (lowest price and
--     quantity), and the full list of one item when you open it (lowest price and market value).
--   Watch list scan: searches each watched item (and crafting reagents) one by one - not limited to every 15 minutes.
local ADDON, X = ...

X.FULL_COOLDOWN = 15 * 60
X.scan = {state = "idle"} -- idle / waiting / reading / loading / saving / items
local READ_SLICE, SAVE_SLICE = 800, 400

-- price of one when a buyout is for the whole auction (all `count` of it).
-- NOT for the game's item search results (one row per auction, ITEM_SEARCH_RESULTS_UPDATED): their buyoutAmount is
-- already the price of ONE, even for a stack of 40 (the game's own list shows it as it is, and its Buyout button
-- sends it unchanged). Dividing those by the quantity makes a 40-stack look 40 times too cheap.
function X.UnitPrice(buyout, count)
	if not buyout or buyout <= 0 then return nil end
	return buyout / math.max(1, count or 1)
end
-- the full scan: whether its buyout is for the whole stack ("stack", the default) or for one ("unit") is not in
-- Blizzard's documents. XNAH finds out by itself: a search of a stackable item gives a sure price of one
-- (X.CheckUnits below), compared with the last full scan read both ways.
function X.FullUnitPrice(buyout, count)
	if not buyout or buyout <= 0 then return nil end
	if X.Realm().unitMode == "unit" then return buyout end
	return buyout / math.max(1, count or 1)
end
function X.CheckUnits(key, sureMin)
	local c = X.unitCheck
	if not c or not sureMin or sureMin <= 0 or X.Now() - c.t > 2 * 3600 then return end
	local e = c.keys[key]
	if not e or not e.a or not e.b then return end
	local la, lb = math.abs(math.log(e.a / sureMin)), math.abs(math.log(e.b / sureMin))
	-- clear answers only: one reading within 30% of the sure price, the other off by more than half
	local mode
	if la < 0.26 and lb > 0.4 then mode = "stack" elseif lb < 0.26 and la > 0.4 then mode = "unit" end
	if not mode then return end
	local r = X.Realm()
	local before = r.unitMode or "stack"
	r.unitMode = mode
	r.unitCheck = {t = X.Now(), key = key, sure = sureMin, stack = e.a, unit = e.b, mode = mode}
	c.keys[key] = nil
	if mode ~= before then
		X.Print("|cffffd100price check:|r the full scan gives the price of ONE item, not of the stack (checked with " ..
			X.ItemName(key) .. "). Fixed from now on - run a new full scan (it replaces the prices of stacks; /xnah forget starts this realm from scratch).")
	elseif not c.told then
		c.told = true
		X.Print("price check passed: full scan prices of stacks are right (checked with " .. X.ItemName(key) .. ")")
	end
	X.Fire("XNAH_SCAN")
end

local function keyOf(itemKey)
	if not itemKey or not itemKey.itemID then return nil end
	if itemKey.itemSuffix and itemKey.itemSuffix ~= 0 then return itemKey.itemID .. ":" .. itemKey.itemSuffix end
	return tostring(itemKey.itemID)
end
X.KeyOfItemKey = keyOf

-- [[ the auction house window ]]
X.On("AUCTION_HOUSE_SHOW", function()
	X.ahOpen = true
	if X.CheckRealm then X.CheckRealm() else X.realmKey = X.RealmKey() end
	X.Fire("XNAH_AH", true)
	if X.S().scanOnOpen and X.FullScanReady() then X.After(1, function() if X.ahOpen then X.FullScan() end end) end
end)
X.On("AUCTION_HOUSE_CLOSED", function()
	X.ahOpen = false
	local st = X.scan.state
	if st == "waiting" or st == "reading" or st == "loading" or st == "items" then
		X.ScanStop("the auction house was closed")
	end
	X.Fire("XNAH_AH", false)
end)

function X.FullScanLeft()
	local last = X.Realm().lastFull
	if not last then return 0 end
	return math.max(0, last + X.FULL_COOLDOWN - X.Now())
end
function X.FullScanReady()
	return X.FullScanLeft() == 0 and X.scan.state == "idle"
end

local function setState(state, text)
	X.scan.state = state
	X.scan.text = text
	X.Fire("XNAH_SCAN")
end
function X.ScanStop(why)
	X.scan.token = {}
	X.scan.rows = nil
	setState("idle", why and ("Stopped: " .. why) or nil)
	if why then X.Print("scan stopped: " .. why) end
end

-- [[ full scan ]]
function X.FullScan(force)
	if not X.ahOpen then X.Print("open the auction house first") return false end
	if X.scan.state ~= "idle" then X.Print("a scan is already running") return false end
	local left = X.FullScanLeft()
	if left > 0 and not force then
		X.Print("the server allows a full scan again in " .. X.Clock(left) .. " (searching your tracked items works any time)")
		return false
	end
	local token = {}
	X.scan = {state = "waiting", token = token, kind = "full", started = X.Now(), startedAt = GetTime()}
	setState("waiting", "Asking the server for every auction ...")
	C_AuctionHouse.ReplicateItems()
	-- the answer usually comes within seconds; nothing after 90 s = the server said no (too soon)
	X.After(90, function()
		if X.scan.token == token and X.scan.state == "waiting" then
			X.Realm().lastFull = X.Now() - X.FULL_COOLDOWN + 5 * 60 -- try again in 5 minutes
			X.ScanStop("no answer from the server (a full scan was probably made too recently)")
		end
	end)
	return true
end

-- reads auction i of the full scan into the rows table; returns false if the item's details are not loaded yet
-- (force: take it anyway, under its plain item ID - better than counting the item as sold out)
local function readRow(i, rows, seen, force)
	local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, ownerFull, _, itemID, hasAll =
		C_AuctionHouse.GetReplicateItemInfo(i)
	if not itemID then return true end
	if name == "" then name = nil end
	-- the link holds the random bonus ("of the Bear") and the name; asked for even when the item is not loaded
	local link = X.Try(C_AuctionHouse.GetReplicateItemLink, i)
	if type(link) ~= "string" then link = nil end
	if not name and link then name = link:match("|h%[(.-)%]|h") end
	-- the link's colour is the item's real quality (the row's own quality can be wrong while the item is not loaded)
	quality = X.QualityFromLink(link) or (hasAll ~= false and quality) or nil
	if name == "" then name = nil end
	if (hasAll == false or not name) and not force and not (link and name) then return false end
	local key = X.KeyFromLink(link) or tostring(itemID)
	local r = rows[key]
	if not r then
		r = {list = {}, name = name, q = quality, owners = {}, bidOnly = 0}
		rows[key] = r
		seen[#seen + 1] = key
	elseif name and not r.name then
		r.name, r.q = name, quality
	end
	if buyout and buyout > 0 then
		local a, b = buyout / math.max(1, count or 1), buyout -- the two readings, for the price check
		if not r.ma or a < r.ma then r.ma = a end
		if not r.mb or b < r.mb then r.mb = b end
		if (count or 1) > 1 then r.stacks = true end
	end
	local unit = X.FullUnitPrice(buyout, count)
	if unit then
		-- {price of one, count, time left band} (the band is for the sales speed estimate)
		r.list[#r.list + 1] = {unit, count or 1, X.Try(C_AuctionHouse.GetReplicateItemTimeLeft, i)}
	else
		r.bidOnly = r.bidOnly + (count or 1)
	end
	local who = ownerFull or owner
	-- units per seller (the game gives no names in the full scan on Forever; kept in case it ever does)
	if who and who ~= "" then r.owners[who] = (r.owners[who] or 0) + (count or 1) end
	return true
end

X.On("REPLICATE_ITEM_LIST_UPDATE", function()
	local s = X.scan
	if s.state ~= "waiting" then return end
	local token = s.token
	local n = C_AuctionHouse.GetNumReplicateItems() or 0
	s.total, s.done, s.rows, s.seen, s.missing, s.asked = n, 0, {}, {}, {}, {}
	X.Realm().lastFull = X.Now()
	setState("reading", "Reading " .. X.Num(n) .. " auctions ...")
	local i = 0
	X.Job("read", function()
		if X.scan.token ~= token then return true end
		-- the list is read from 0 to n: retail counts from 0, and an empty row at either end is skipped (Forever unverified)
		local stop = math.min(n + 1, i + READ_SLICE)
		while i < stop do
			if not readRow(i, s.rows, s.seen) then
				s.missing[#s.missing + 1] = i
				local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(i)
				if itemID and not s.asked[itemID] and C_Item.RequestLoadItemDataByID then
					s.asked[itemID] = true
					X.Try(C_Item.RequestLoadItemDataByID, itemID)
				end
			end
			i = i + 1
		end
		s.done = math.min(i, n)
		X.scan.text = "Reading auctions: " .. X.Num(math.min(i, n)) .. " / " .. X.Num(n)
		X.Fire("XNAH_SCAN")
		return i > n
	end, function()
		if X.scan.token ~= token then return end
		X.ScanLoadMissing(token, 1)
	end)
end)

-- auctions of items the game had not loaded yet: asked for, read again after a moment (up to 4 tries)
function X.ScanLoadMissing(token, try)
	local s = X.scan
	if #s.missing == 0 or try > 4 then
		if #s.missing > 0 then X.Debug(#s.missing .. " auctions read without their item details (never loaded)") end
		s.skipped = #s.missing
		local k = 0
		X.Job("forced", function()
			if X.scan.token ~= token then return true end
			local stop = math.min(#s.missing, k + SAVE_SLICE)
			while k < stop do k = k + 1 readRow(s.missing[k], s.rows, s.seen, true) end
			return k >= #s.missing
		end, function()
			if X.scan.token == token then X.ScanSave(token) end
		end)
		return
	end
	setState("loading", "Loading details of " .. X.Num(#s.missing) .. " auctions ...")
	X.After(try == 1 and 1 or 2, function()
		if X.scan.token ~= token then return end
		local still, k = {}, 0
		X.Job("retry", function()
			if X.scan.token ~= token then return true end
			local stop = math.min(#s.missing, k + SAVE_SLICE)
			while k < stop do
				k = k + 1
				local i = s.missing[k]
				if not readRow(i, s.rows, s.seen) then still[#still + 1] = i end
			end
			return k >= #s.missing
		end, function()
			if X.scan.token ~= token then return end
			s.missing = still
			X.ScanLoadMissing(token, try + 1)
		end)
	end)
end

-- one market value per item, then the sold-out ones
function X.ScanSave(token)
	local s = X.scan
	local t = s.started or X.Now()
	setState("saving", "Saving prices of " .. X.Num(#s.seen) .. " items ...")
	local k, seenSet = 0, {}
	local gone, g = nil, 0
	-- the whole auction house: copper of every buyout listed, items listed, different sellers (names, when given)
	local gold, units, everyone, nSellers = 0, 0, {}, 0
	X.Job("save", function()
		if X.scan.token ~= token then return true end
		if not gone then
			local stop = math.min(#s.seen, k + SAVE_SLICE)
			while k < stop do
				k = k + 1
				local key = s.seen[k]
				local r = s.rows[key]
				seenSet[key] = true
				local min, mkt, qty, auc = X.MarketValue(r.list)
				local it = X.Record(key, t, min, mkt, (qty or 0) + r.bidOnly, auc or 0, r.name, r.q)
				for _, l in ipairs(r.list) do gold = gold + l[1] * (l[2] or 1) end
				units = units + (qty or 0) + r.bidOnly
				-- sellers (r.owners = units per seller name; on Forever the full scan gives no names, so this stays empty)
				local sellers, top, topName = 0, 0, nil
				for who, u in pairs(r.owners) do
					sellers = sellers + 1
					if u > top then top, topName = u, who end
					if not everyone[who] then everyone[who] = true nSellers = nSellers + 1 end
				end
				it.cur.sellers = sellers > 0 and sellers or nil
				local all = (qty or 0) + r.bidOnly
				if sellers > 0 and all > 0 then X.RecordSellers(key, t, sellers, top / all, topName) end
			end
			if k >= #s.seen then
				gone = {}
				for key in pairs(X.Items()) do if not seenSet[key] then gone[#gone + 1] = key end end
			end
			return false
		end
		local stop = math.min(#gone, g + SAVE_SLICE)
		while g < stop do
			g = g + 1
			X.RecordGone(gone[g], t)
		end
		return g >= #gone
	end, function()
		if X.scan.token ~= token then return end
		-- for the price check: both readings of every item sold in stacks
		local check = {t = t, keys = {}}
		for key, row in pairs(s.rows) do
			if row.stacks then check.keys[key] = {a = row.ma, b = row.mb} end
		end
		X.unitCheck = check
		-- other parts (sales speed, market shape) look at every listing of this scan:
		-- rows[key] = {list = {{price of one, count, time left band}, ...}, bidOnly, name, q}; seen = keys in order
		X.Fire("XNAH_FULLSCAN", s.rows, t, s.seen)
		X.After(5, function() X.PackScanRows(s.rows, s.seen) end)
		X.FillNames()
		local r = X.Realm()
		table.insert(r.scans, {t = t, kind = "full", items = #s.seen, auctions = s.total, secs = X.Round(GetTime() - (s.startedAt or GetTime())),
			skipped = s.skipped, gold = X.Round(gold), units = units, sellers = nSellers > 0 and nSellers or nil})
		while #r.scans > X.MAX_SCANS do table.remove(r.scans, 1) end
		local msg = "full scan done: " .. X.Num(s.total) .. " auctions, " .. X.Num(#s.seen) .. " items"
		X.scan = {state = "idle", text = "Last full scan: " .. X.Num(s.total) .. " auctions, " .. X.Num(#s.seen) .. " items"}
		X.Print(msg)
		X.Fire("XNAH_SCAN")
		X.Fire("XNAH_PRICES")
	end)
end

-- [[ recording what the auction house shows while you use it ]]
-- a lowest price without a full list: the market value from the last full list is kept
function X.Observe(key, t, min, qty, name, quality)
	local it = X.Items()[key]
	local prev = it and it.cur
	if prev and prev.t and prev.t > t then return end
	-- the earlier market value goes into the history point too (a later point in the same minute replaces the earlier one)
	X.Record(key, t, min, prev and prev.mkt, qty, prev and prev.auc, name, quality)
	it = X.Items()[key]
	if prev and prev.mkt then
		it.cur.mkt = prev.mkt
		it.cur.mktT = prev.mktT or prev.t
	end
	it.cur.sellers = prev and prev.sellers
end

local function onBrowse()
	if X.scan.state ~= "idle" and X.scan.state ~= "items" then return end
	local results = X.Try(C_AuctionHouse.GetBrowseResults)
	if not results then return end
	local t = X.Now()
	for _, r in ipairs(results) do
		local key = keyOf(r.itemKey)
		if key and r.minPrice and r.minPrice > 0 then
			local info = X.Try(C_AuctionHouse.GetItemKeyInfo, r.itemKey)
			X.Observe(key, t, r.minPrice, r.totalQuantity, info and info.itemName, info and info.quality)
		end
	end
	X.Debounce("browse", 0.5, function() X.Fire("XNAH_PRICES") end)
end
X.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", onBrowse)
X.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", onBrowse)

-- the full list of one item: both kinds of list give the price of ONE directly (stackable "commodity" items as
-- unitPrice, other items one row per auction with buyoutAmount = the price of one of that auction)
-- the watch list scan goes on once the item it waits for has answered
local function answered(keys)
	local s = X.scan
	if s.state == "items" and s.waitFor and keys[s.waitFor] then X.ScanItemsNext() end
end
local function recordList(key, list, name, quality)
	if #list == 0 then return end
	local min, mkt, qty, auc = X.MarketValue(list)
	local it = X.Record(key, X.Now(), min, mkt, qty, auc, name, quality)
	X.Debounce("search", 0.3, function() X.Fire("XNAH_PRICES") end)
	return it
end
X.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	if type(itemKey) ~= "table" then return end
	if not X.Try(C_AuctionHouse.HasFullItemSearchResults, itemKey) then return end -- wait for the whole list
	local n = X.Try(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0
	local byKey = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
		if r and r.buyoutAmount and r.buyoutAmount > 0 then
			local key = X.KeyFromLink(r.itemLink) or keyOf(r.itemKey) or keyOf(itemKey)
			byKey[key] = byKey[key] or {}
			-- the buyout here is the price of ONE, also when the auction is a stack (never divide it by the quantity)
			table.insert(byKey[key], {r.buyoutAmount, r.quantity or 1})
		end
	end
	local info = X.Try(C_AuctionHouse.GetItemKeyInfo, itemKey)
	local main = keyOf(itemKey)
	for key, list in pairs(byKey) do recordList(key, list, info and info.itemName, info and info.quality) end
	if n == 0 and main then X.RecordGone(main, X.Now()) end
	if main then byKey[main] = byKey[main] or {} end
	answered(byKey)
end)
X.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not itemID then return end
	if not X.Try(C_AuctionHouse.HasFullCommoditySearchResults, itemID) then return end
	local n = X.Try(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
	local list = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
		if r and r.unitPrice and r.unitPrice > 0 then list[#list + 1] = {r.unitPrice, r.quantity or 1} end
	end
	local key = tostring(itemID)
	if #list == 0 then
		X.RecordGone(key, X.Now())
	else
		local name, q = X.ItemName(key)
		local it = recordList(key, list, name, q)
		X.CheckUnits(key, it and it.cur and it.cur.min)
	end
	answered({[key] = true})
end)

-- [[ watch list scan ]] searches the given items one at a time (default: the watch list)
function X.ScanItems(keys, label)
	if not X.ahOpen then X.Print("open the auction house first") return false end
	if X.scan.state ~= "idle" then X.Print("a scan is already running") return false end
	if not keys then
		keys = {}
		for key in pairs(X.db.watch) do keys[#keys + 1] = key end
		table.sort(keys)
	end
	if #keys == 0 then X.Print("nothing to scan: track items first (the Track button in the Items view)") return false end
	X.scan = {state = "items", token = {}, kind = label or "tracked items", queue = keys, pos = 0, total = #keys, done = 0,
		started = X.Now(), startedAt = GetTime()}
	X.ScanItemsNext()
	return true
end
function X.ScanItemsNext()
	local s = X.scan
	if s.state ~= "items" then return end
	s.pos = s.pos + 1
	s.done = s.pos - 1
	local key = s.queue[s.pos]
	if not key then
		local r = X.Realm()
		table.insert(r.scans, {t = s.started, kind = s.kind, items = s.total, secs = X.Round(GetTime() - s.startedAt)})
		while #r.scans > X.MAX_SCANS do table.remove(r.scans, 1) end
		X.scan = {state = "idle", text = "Scanned " .. s.total .. " items (" .. s.kind .. ")"}
		X.Print("scan done: " .. s.total .. " items (" .. s.kind .. ")")
		X.Fire("XNAH_SCAN")
		X.Fire("XNAH_PRICES")
		return
	end
	s.waitFor = key
	s.text = "Searching " .. s.pos .. " / " .. s.total .. ": " .. X.ItemName(key)
	X.Fire("XNAH_SCAN")
	local token = s.token
	local function send()
		if X.scan.token ~= token or s.waitFor ~= key then return end
		if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
			X.After(0.3, send)
			return
		end
		local id = X.KeyID(key)
		local suffix = tonumber((key:match(":(%-?%d+)$")))
		local itemKey = C_AuctionHouse.MakeItemKey(id, 0, suffix or 0)
		C_AuctionHouse.SendSearchQuery(itemKey, {{sortOrder = 0, reverseSort = false}}, false)
		-- no answer in 6 s: skip it
		X.After(6, function()
			if X.scan.token == token and s.waitFor == key and s.pos == X.Contains(s.queue, key) then
				X.Debug("no answer for " .. key)
				X.ScanItemsNext()
			end
		end)
	end
	send()
end

-- [[ the game's own auction house window ]] "Search on the auction house" also shows the item there: its listings
-- page when the game knows the item (else after a moment, else a search by its name). Only while that window is open.
function X.ShowOnAuctionHouse(key)
	local f = AuctionHouseFrame
	if not (X.ahOpen and f and f.IsShown and f:IsShown() and key) then return false end
	local id = X.KeyID(key)
	if not id then return false end
	local suffix = tonumber((tostring(key):match(":(%-?%d+)$")))
	local itemKey = X.Try(C_AuctionHouse.MakeItemKey, id, 0, suffix or 0)
	local name = X.ItemName(key)
	if name and name:find("^item %-?%d+$") then name = nil end -- not known yet (X.ItemName's stand-in)
	-- the Buy tab first (the posting and "your auctions" tabs take no search)
	local modes = AuctionHouseFrameDisplayMode
	if modes and modes.Buy and f.SetDisplayMode then X.Try(f.SetDisplayMode, f, modes.Buy) end
	if name and name ~= "" and f.SetSearchText then X.Try(f.SetSearchText, f, name) end
	local tries = 0
	local function open()
		if not (X.ahOpen and f:IsShown()) then return end
		local info = itemKey and X.Try(C_AuctionHouse.GetItemKeyInfo, itemKey)
		if info and f.SelectBrowseResult then
			local it = X.Item(key)
			X.Try(f.SelectBrowseResult, f, {itemKey = itemKey, minPrice = it and it.cur and it.cur.min or 0})
			return
		end
		tries = tries + 1
		if tries < 4 then X.After(0.3, open) return end -- the game is still loading the item
		if name and name ~= "" and type(f.SearchBar) == "table" and f.SearchBar.StartSearch then X.Try(f.SearchBar.StartSearch, f.SearchBar) end
	end
	open()
	return true
end

-- [[ checking the raw data in the game ]] /xnah raw: the first auctions of the last full scan as the game gives them
function X.RawDump(n)
	if not X.ahOpen then X.Print("open the auction house first (after a full scan)") return end
	local total = X.Try(C_AuctionHouse.GetNumReplicateItems) or 0
	X.Print("full scan rows the game holds: " .. total)
	for i = 0, math.min(total, n or 5) - 1 do
		local name, _, count, _, _, _, _, minBid, _, buyout, bid, _, _, owner, _, _, itemID, hasAll = C_AuctionHouse.GetReplicateItemInfo(i)
		X.Print(string.format("#%d %s (id %s) count %s, buyout %s, min bid %s, bid %s, seller %s, loaded %s", i,
			tostring(name), tostring(itemID), tostring(count), tostring(buyout), tostring(minBid), tostring(bid), tostring(owner), tostring(hasAll)))
	end
end

-- [[ item names ]] most items of a full scan are not loaded by the game yet (no name): asked for in the background,
-- 40 a second, and filled in when the game has them
local nameQueue, nameBusy = {}, false
local function nameStep()
	local n = 0
	while n < 25 and #nameQueue > 0 do
		local id = table.remove(nameQueue)
		n = n + 1
		local name = X.Try(C_Item.GetItemInfo, id)
		if name then X.NameLoaded(id, true) elseif C_Item.RequestLoadItemDataByID then X.Try(C_Item.RequestLoadItemDataByID, id) end
	end
	if #nameQueue > 0 then X.After(1, nameStep) else
		nameBusy = false
		X.Debounce("names", 1, function() X.Fire("XNAH_PRICES") end)
	end
end
function X.FillNames()
	local ids, set = {}, {}
	for _, it in pairs(X.Items()) do
		-- it.qk = the quality was checked with the game once (saved), so this is not done again at every login
		if (not it.n or it.n == "" or not (it.qk or X.qualityOK[it.id])) and it.id and not set[it.id] then set[it.id] = true ids[#ids + 1] = it.id end
	end
	nameQueue = ids
	if #ids > 0 and not nameBusy then nameBusy = true X.After(0.5, nameStep) end
	return #ids
end
-- the game has an item now: its name and quality go to every key of that item (random bonus items keep the base name
-- until a link with the full name is seen)
function X.NameLoaded(id, quiet)
	local name, link, q = X.Try(C_Item.GetItemInfo, id)
	if not name or name == "" then return end
	local items = X.Items()
	local base = items[tostring(id)]
	local changed = false
	if base and (not base.n or base.n == "") then base.n = name changed = true end
	-- the game's quality wins (also for the "id:suffix" keys of the same item)
	if q and not X.qualityOK[id] then
		X.qualityOK[id] = true
		if base then
			if base.q ~= q then base.q = q changed = true end
			base.qk = 1
		end
		-- the other keys of this item (random bonus)
		for _, key in ipairs(X.SuffixKeys(id) or {}) do
			local it = items[key]
			if it and it.q ~= q then it.q = q changed = true end
			if it then it.qk = 1 end
		end
	end
	-- while the background look-up runs, the window refreshes once at its end (not every 2 seconds)
	if (changed or not quiet) and not nameBusy then X.Debounce("names", 2, function() X.Fire("XNAH_PRICES") end) end
end
X.On("ITEM_DATA_LOAD_RESULT", function(id, ok) if ok and id then X.NameLoaded(id) end end)
X.On("GET_ITEM_INFO_RECEIVED", function(id, ok) if ok and id then X.NameLoaded(id) end end)
X.On("XNAH_LOGIN", function() X.After(5, X.FillNames) end)

-- [[ keeping the last full scan small ]] sales speed and Shape.lua keep every listing of the last full scan for the
-- session (about 300,000 of them). As small tables that is tens of megabytes the game has to sweep through - a cause of
-- stutter, more so with several game windows. So a few seconds after the scan each item's listings become one string
-- "price*100,count,band;..." (base 36); row.list unpacks it again whenever something reads it (a fresh table each time).
local function packList(list)
	local parts = {}
	for i = 1, #list do
		local l = list[i]
		parts[i] = X.b36(math.floor(l[1] * 100 + 0.5)) .. "," .. X.b36(l[2] or 1) .. "," .. (l[3] and X.b36(l[3]) or "")
	end
	return table.concat(parts, ";")
end
local function unpackList(s)
	local out = {}
	for u, c, b in s:gmatch("([^,;]*),([^,;]*),([^,;]*)") do
		out[#out + 1] = {(X.n36(u) or 0) / 100, X.n36(c) or 1, X.n36(b)}
	end
	return out
end
X.UnpackScanList = unpackList
local LAZY = {__index = function(t, k)
	if k == "list" then
		local p = rawget(t, "packed")
		return p and unpackList(p) or {}
	end
end}
function X.PackScanRows(rows, seen)
	if type(rows) ~= "table" then return end
	local keys = seen
	if not keys then keys = {} for key in pairs(rows) do keys[#keys + 1] = key end end
	local i = 0
	X.Job("pack", function()
		local stop = math.min(#keys, i + 300)
		while i < stop do
			i = i + 1
			local r = rows[keys[i]]
			if r and rawget(r, "list") then
				r.packed = packList(r.list)
				r.list, r.owners, r.ma, r.mb = nil, nil, nil, nil
				setmetatable(r, LAZY)
			end
		end
		return i >= #keys
	end, function() pcall(collectgarbage, "step", 1000) end)
end

-- [[ /xnah perf ]] what XNAH does right now and how much memory it uses
function X.Perf()
	if UpdateAddOnMemoryUsage then pcall(UpdateAddOnMemoryUsage) end
	local kb = GetAddOnMemoryUsage and X.Try(GetAddOnMemoryUsage, ADDON)
	X.Print(string.format("memory: %s (all addons' Lua: %.0f MB)", kb and string.format("%.1f MB", kb / 1024) or "?",
		(select(2, pcall(collectgarbage, "count")) or 0) / 1024))
	X.Print("busy: " .. (X.JobList and X.JobList() or "?") .. "; names to look up: " .. #nameQueue ..
		"; scan: " .. tostring(X.scan.state))
	local items, bytes = X.DataSize()
	X.Print("saved data: " .. X.Num(items) .. " items, about " .. string.format("%.1f MB", bytes / 1048576))
	X.Print("time spent in XNAH in the last 60 s: " .. string.format("%.0f ms", X.PerfTime and X.PerfTime() or 0) ..
		" (worst single step " .. string.format("%.1f ms", X.perfWorst or 0) .. ")")
end
