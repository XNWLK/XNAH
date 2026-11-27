-- Market shape: how the listings of an item are spread, and who sells it.
--   Wall: one price at which a big part of the cheap listings sits (someone listed many at one price). Selling under
--     it is easy; selling above it waits until the wall is bought.
--   Reset: everything listed far under the usual price (under 80%) costs this much to buy; listed again at the usual
--     price it brings this much more after the cut. Only when the item sells fast enough to sell them again (within
--     about 5 days, when its sales speed is known). A chance, not a sure thing: others may list cheap again.
--   Sellers: the full scan on Forever gives no seller names, so sellers are counted from searches of one item (when
--     you look at an item on the auction house, or a watch list scan): how many sellers, and the biggest one's share.
--
-- Saved: X.Realm().shape[key] = {t, wall = {p, u}, reset = {u, c, p}, sellers, top, ts} (only items where something is
-- set; t = last full scan that set it, ts = the search the sellers come from). Kept 3 days.
local ADDON, X = ...

local WINDOW = 1.5       -- the wall is looked for among listings up to 1.5 x the lowest price
local WALL_SHARE = 0.30  -- ... and must hold at least 30% of those units
local WALL_MIN = 3       -- ... and at least 3 units (a single listing of one is no wall)
local RESET_UNDER = 0.80 -- reset: listings under 80% of the usual price
local RESET_DAYS = 5     -- ... only when they sell again within 5 days (known sales speed)
local KEEP = 3 * 86400
local SLICE = 4000

local function store()
	local r = X.Realm()
	r.shape = r.shape or {}
	return r.shape
end

-- [[ from one item's listings ]] list = {{price of one, count, band}, ...}
local function wallOf(list)
	local low
	for _, l in ipairs(list) do if not low or l[1] < low then low = l[1] end end
	if not low then return nil end
	local levels, total = {}, 0
	for _, l in ipairs(list) do
		if l[1] <= low * WINDOW then
			local p = math.floor(l[1] + 0.5)
			levels[p] = (levels[p] or 0) + (l[2] or 1)
			total = total + (l[2] or 1)
		end
	end
	local bestP, bestU
	for p, u in pairs(levels) do
		if not bestU or u > bestU or (u == bestU and p < bestP) then bestP, bestU = p, u end
	end
	if bestU and bestU >= WALL_MIN and bestU >= total * WALL_SHARE then return {p = bestP, u = bestU} end
	return nil
end
local function resetOf(key, list)
	local usual = X.Usual(key)
	if not usual or usual <= 0 then return nil end
	local units, cost = 0, 0
	for _, l in ipairs(list) do
		if l[1] < usual * RESET_UNDER then
			units = units + (l[2] or 1)
			cost = cost + l[1] * (l[2] or 1)
		end
	end
	if units == 0 then return nil end
	local profit = X.AfterCut(usual) * units - cost
	if profit <= 0 then return nil end
	local rate = X.SaleRate and X.SaleRate(key)
	if rate and units > rate * RESET_DAYS then return nil end
	return {u = units, c = X.Round(cost), p = X.Round(profit)}
end
X.ShapeWall, X.ShapeReset = wallOf, resetOf -- for the tests

X.On("XNAH_FULLSCAN", function(rows, t, seen)
	if type(rows) ~= "table" or not t then return end
	local keys = seen or {}
	local sh = store()
	local k = 0
	local pruned = false
	X.Job("shape", function()
		if not pruned then
			-- old entries go first (and the cheap parts of every entry this scan does not set again)
			for key, e in pairs(sh) do
				if (e.ts or 0) < t - KEEP then e.sellers, e.top, e.ts = nil, nil, nil end
				if (e.t or 0) < t - KEEP then e.wall, e.reset = nil, nil end
				if not e.wall and not e.reset and not e.sellers then sh[key] = nil end
			end
			pruned = true
			return false
		end
		local budget = 0
		while k < #keys and budget < SLICE do
			k = k + 1
			local key = keys[k]
			local r = rows[key]
			local list = r and r.list or {}
			budget = budget + #list + 1
			local wall = #list > 0 and wallOf(list) or nil
			local reset = #list > 0 and resetOf(key, list) or nil
			local e = sh[key]
			if wall or reset then
				e = e or {}
				sh[key] = e
				e.t, e.wall, e.reset = t, wall, reset
			elseif e then
				e.wall, e.reset = nil, nil
				e.t = t
				if not e.sellers then sh[key] = nil end
			end
		end
		return k >= #keys
	end, function()
		X.Fire("XNAH_ANALYSIS")
	end)
end)

-- [[ sellers from searches ]] owners = names of the sellers of a result row (may be cut short),
-- totalNumberOfOwners = how many in all. Units of a row with several sellers are shared out evenly (a guess).
local function countSellers(rows)
	local units, names, unnamed = 0, {}, 0
	for _, r in ipairs(rows) do
		local q = r.quantity or 1
		units = units + q
		local owners = type(r.owners) == "table" and r.owners or {}
		local total = math.max(r.totalNumberOfOwners or #owners, #owners, 1)
		local each = q / total
		local named = 0
		for _, name in ipairs(owners) do
			if type(name) == "string" and name ~= "" then
				names[name] = (names[name] or 0) + each
				named = named + 1
			end
		end
		unnamed = unnamed + math.max(0, total - named)
	end
	if units == 0 then return nil end
	local n, top, topName = 0, 0, nil
	for name, u in pairs(names) do
		n = n + 1
		if u > top or (u == top and topName and name < topName) then top, topName = u, name end
	end
	-- unnamed sellers of different rows may be the same people: counted at most once per row, never fewer than named
	return n + unnamed, top / units, topName
end
X.CountSellers = countSellers -- for the tests
-- keeps the sellers of the latest search (and a point a day in the seller history, Data.lua X.RecordSellers)
local function setSellers(key, sellers, top, topName)
	local sh = store()
	local e = sh[key]
	if not sellers then
		if e then
			e.sellers, e.top, e.ts = nil, nil, nil
			if not e.wall and not e.reset then sh[key] = nil end
		end
		return
	end
	e = e or {}
	sh[key] = e
	e.sellers, e.top, e.ts = sellers, math.floor(top * 1000 + 0.5) / 1000, X.Now()
	X.RecordSellers(key, X.Now(), sellers, top, topName)
	if not e.t then e.t = X.Now() end
end

X.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	if type(itemKey) ~= "table" then return end
	if not X.Try(C_AuctionHouse.HasFullItemSearchResults, itemKey) then return end
	local n = X.Try(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0
	local byKey = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
		if r then
			local key = X.KeyFromLink(r.itemLink) or (X.KeyOfItemKey and X.KeyOfItemKey(r.itemKey or itemKey))
			if key then
				byKey[key] = byKey[key] or {}
				table.insert(byKey[key], r)
			end
		end
	end
	for key, list in pairs(byKey) do setSellers(key, countSellers(list)) end
	if n == 0 and X.KeyOfItemKey then setSellers(X.KeyOfItemKey(itemKey), nil) end
	X.Debounce("shape", 0.5, function() X.Fire("XNAH_ANALYSIS") end)
end)
X.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not itemID then return end
	if not X.Try(C_AuctionHouse.HasFullCommoditySearchResults, itemID) then return end
	local n = X.Try(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
	local list = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
		if r then list[#list + 1] = r end
	end
	setSellers(tostring(itemID), countSellers(list))
	X.Debounce("shape", 0.5, function() X.Fire("XNAH_ANALYSIS") end)
end)

-- [[ X.Shape(key) ]] -> {wall = {price, units} or nil, reset = {units, cost, profit} or nil, sellers = n or nil,
-- topShare = 0..1 or nil, t}. Sellers fall back to the full scan's count when the client ever gives seller names there.
function X.Shape(key)
	local e = X.Realm().shape and X.Realm().shape[key]
	local it = X.Items()[key]
	local fallback = it and it.cur and it.cur.sellers
	if not e and not fallback then return nil end
	e = e or {}
	return {
		wall = e.wall and {price = e.wall.p, units = e.wall.u} or nil,
		reset = e.reset and {units = e.reset.u, cost = e.reset.c, profit = e.reset.p} or nil,
		sellers = e.sellers or fallback,
		topShare = e.top,
		t = math.max(e.t or 0, e.ts or 0) > 0 and math.max(e.t or 0, e.ts or 0) or (it and it.cur and it.cur.t),
	}
end

-- [[ lists ]] (no view shows them since the Opportunities view was taken out; kept for later pages)
-- reset chances: rows {key, units, cost, usual, profit, rate (sells per day or nil)}, best profit first
function X.Resets()
	local out = {}
	for key, e in pairs(X.Realm().shape or {}) do
		if e.reset then
			out[#out + 1] = {key = key, units = e.reset.u, cost = e.reset.c, usual = X.Usual(key), profit = e.reset.p,
				rate = X.SaleRate and X.SaleRate(key) or nil, t = e.t}
		end
	end
	table.sort(out, function(a, b) return a.profit > b.profit end)
	return out
end
-- few sellers or a wall: rows {key, sellers, top (0..1), wallP, wallU, min}; items with at most 3 sellers, one seller
-- holding half or more, or a wall
function X.FewSellers()
	local out = {}
	local sh = X.Realm().shape or {}
	local done = {}
	local function add(key, e, fallback)
		local sellers = e and e.sellers or fallback
		local top = e and e.top
		local wall = e and e.wall
		if (sellers and sellers <= 3) or (top and top >= 0.5) or wall then
			local it = X.Items()[key]
			out[#out + 1] = {key = key, sellers = sellers, top = top, wallP = wall and wall.p, wallU = wall and wall.u,
				min = it and it.cur and it.cur.min}
		end
	end
	for key, e in pairs(sh) do done[key] = true add(key, e) end
	for key, it in pairs(X.Items()) do
		if not done[key] and it.cur and it.cur.sellers and (it.cur.qty or 0) > 0 and X.Fresh(it) then add(key, nil, it.cur.sellers) end
	end
	table.sort(out, function(a, b)
		local ta, tb = a.top or 0, b.top or 0
		if ta ~= tb then return ta > tb end
		return (a.wallU or 0) > (b.wallU or 0)
	end)
	return out
end
