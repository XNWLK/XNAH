-- Crafting history: what crafting an item cost on each past day, from the day prices of its reagents, and what it
-- sold for. The same rules as the crafting cost now (Craft.lua), with each day's prices instead of today's:
--   each reagent at the cheapest of: a vendor (vendor prices do not change), its auction house price that day, or
--   crafting it that day (3 levels deep, never in a circle, never crafts with a waiting time - X.CRAFT_COOLDOWNS);
--   a day where a reagent has no price gives no cost (it would look too cheap).
-- The price of a day = that day's market value (else its lowest price), from the day points of the price history
-- (Data.lua); a day without a scan takes the last price before it, up to 7 days back. Crazy prices (far off the item's
-- typical price, X.CrazyPrice) are left out as everywhere else.
--   X.DayPrice(key, day) -> copper or nil             the price of one on that day (day = X.Day: days since 1970)
--   X.CraftCostOn(rid, day) -> cost of ONE item made, missing (reagents without a price that day; cost nil then)
--   X.ReagentCostOn(itemID, day) -> copper, how ("vendor" / "ah" / "craft"), recipe when crafted
--   X.CraftSeries(rid, fromDay, toDay) -> {{day, t, cost, sell, margin}, ...}  sell = the made item's price that day
--     after the auction house cut; margin = sell - cost (both per item); nil where unknown
--   X.CraftMargin(rid) -> {cost, sell, margin (now, from the prices now - the same as the Overview page), missing,
--     avg30 (average margin of the last 30 days), days30 (days it is worked out from), best = {day, margin},
--     trend (copper a week, the last 14 days), trendWord}
--   X.ReagentUses(itemID) -> rows (margins from the prices now) {rid, key (what it makes), name, cost, sell, margin, pct, missing, count} for every
--     recipe that uses the item, best margin first
-- Everything is cached until new prices or recipes arrive (or the day changes).
local ADDON, X = ...

local DAY = 86400
local CARRY = 7 -- a day without a price takes the last one up to this many days before it

-- [[ day prices ]] per item: {[day] = price}, made again when its day text changes
local maps = setmetatable({}, {__mode = "k"})
local function dayMap(it)
	local m = maps[it]
	if m and m.d == it.d then return m.map end
	local map = {}
	local st = X.Stats(it)
	local typical = st and st.typical
	for _, p in ipairs(X.UnpackPoints(it.d)) do
		local v = p[3] or p[2]
		if v and v > 0 and not X.CrazyPrice(v, typical) then map[p[1]] = v end
	end
	maps[it] = {d = it.d, map = map}
	return map
end
function X.DayPrice(key, day)
	local it = X.Items()[tostring(key)]
	if not it or not day then return nil end
	local map = dayMap(it)
	for k = 0, CARRY do
		local v = map[day - k]
		if v then return v end
	end
	return nil
end

-- [[ costs on a day ]]
local costs = {}   -- [day] = {[itemID] = {cost, how, via}}
local series = {}  -- ["rid:from:to"] = list
local margins = {} -- [rid] = X.CraftMargin result
local uses = {}    -- [itemID] = X.ReagentUses result
local cachedDay
local function clear()
	costs, series, margins, uses = {}, {}, {}, {}
end
X.On("XNAH_PRICES", clear)
X.On("XNAH_RECIPES", clear)
local cachedAt = -100
local function fresh()
	-- a new day, or a while since the last look (prices can arrive without a scan finishing): worked out again
	local today, now = X.Day(), GetTime()
	if cachedDay ~= today or now - cachedAt > 30 then cachedDay, cachedAt = today, now clear() end
end

local recipeCostOn -- below
local function reagentCostOn(id, day, depth, visiting)
	local perDay = costs[day]
	if not perDay then perDay = {} costs[day] = perDay end
	local hit = perDay[id]
	if hit then return hit[1], hit[2], hit[3] end
	local best, how, via
	local vb = X.VendorBuy(id)
	if vb and X.S().vendorBuyFirst then best, how = vb, "vendor" end
	local ah = X.DayPrice(tostring(id), day)
	if ah and (not best or ah < best) then best, how = ah, "ah" end
	if vb and not X.S().vendorBuyFirst and not best then best, how = vb, "vendor" end
	if depth < 3 and not visiting[id] then
		visiting[id] = true
		for _, rid in ipairs(X.RecipesFor(id)) do
			if not X.CRAFT_COOLDOWNS[rid] then
				local c, miss = recipeCostOn(rid, day, depth + 1, visiting)
				if c and miss == 0 and (not best or c < best) then best, how, via = c, "craft", rid end
			end
		end
		visiting[id] = nil
	end
	-- only a full answer is kept (one worked out inside another recipe may stop early)
	if depth == 0 and next(visiting) == nil then perDay[id] = {best, how, via} end
	return best, how, via
end
recipeCostOn = function(rid, day, depth, visiting)
	local r = X.Recipe(rid)
	if not r or not r.r or #r.r == 0 then return nil, 0 end
	local total, missing = 0, 0
	for _, re in ipairs(r.r) do
		local c = reagentCostOn(re[1], day, depth, visiting)
		if c then total = total + c * re[2] else missing = missing + 1 end
	end
	if missing > 0 then return nil, missing end
	return total / (r.n or 1), 0
end
function X.ReagentCostOn(id, day)
	fresh()
	return reagentCostOn(id, day, 0, {})
end
function X.CraftCostOn(rid, day)
	fresh()
	return recipeCostOn(rid, day, 0, {})
end

-- [[ a recipe over time ]]
function X.CraftSeries(rid, fromDay, toDay)
	fresh()
	toDay = toDay or X.Day()
	local ck = rid .. ":" .. fromDay .. ":" .. toDay
	if series[ck] then return series[ck] end
	local r = X.Recipe(rid)
	local out = {}
	if r and r.out then
		local key = tostring(r.out)
		for day = fromDay, toDay do
			local cost = X.CraftCostOn(rid, day)
			local price = X.DayPrice(key, day)
			local sell = price and X.AfterCut(price) or nil
			-- only days with something to show
			if cost or sell then
				out[#out + 1] = {day = day, t = day * DAY + DAY / 2, cost = cost, sell = sell,
					margin = (cost and sell) and (sell - cost) or nil}
			end
		end
	end
	series[ck] = out
	return out
end

-- a straight line through (x, y): its slope
local function slope(xs, ys)
	local n = #xs
	if n < 3 then return nil end
	local sx, sy, sxx, sxy = 0, 0, 0, 0
	for i = 1, n do
		sx, sy = sx + xs[i], sy + ys[i]
		sxx, sxy = sxx + xs[i] * xs[i], sxy + xs[i] * ys[i]
	end
	local den = n * sxx - sx * sx
	if den == 0 then return nil end
	return (n * sxy - sx * sy) / den
end
X.Slope = slope

-- the margin now (from the prices now, as on the Overview page)
local function marginNow(rid, r)
	local m = {}
	local cost, missing = X.RecipeCost(rid)
	m.cost, m.missing = cost, missing or 0
	m.sell = X.AfterCut(X.Price(tostring(r.out)))
	if cost and m.sell and m.missing == 0 then m.margin = m.sell - cost end
	return m
end
function X.CraftMargin(rid)
	fresh()
	if margins[rid] then return margins[rid] end
	local r = X.Recipe(rid)
	local m = {}
	if r and r.out then
		m = marginNow(rid, r)
		local today = X.Day()
		local sum, n = 0, 0
		local xs, ys = {}, {}
		for _, p in ipairs(X.CraftSeries(rid, today - 29, today)) do
			if p.margin then
				sum, n = sum + p.margin, n + 1
				if not m.best or p.margin > m.best.margin then m.best = {day = p.day, margin = p.margin} end
				if p.day > today - 14 then xs[#xs + 1] = p.day ys[#ys + 1] = p.margin end
			end
		end
		m.days30 = n
		if n > 0 then m.avg30 = sum / n end
		local s = slope(xs, ys)
		if s then
			m.trend = s * 7
			-- "steady" while the margin moves less than 5% of the crafting cost a week (or 1 silver)
			local calm = math.max(100, (m.cost or 0) * 0.05)
			m.trendWord = math.abs(m.trend) < calm and "steady" or (m.trend > 0 and "growing" or "shrinking")
		end
	end
	margins[rid] = m
	return m
end

-- [[ recipes that use an item ]]
function X.ReagentUses(itemID)
	fresh()
	if uses[itemID] then return uses[itemID] end
	local out = {}
	for _, rid in ipairs(X.RecipesUsing(itemID)) do
		local r = X.Recipe(rid)
		if r and r.out then
			local m = marginNow(rid, r) -- (no history needed for the list: quick also for a reagent of 100 recipes)
			local count = 0
			for _, re in ipairs(r.r or {}) do if re[1] == itemID then count = count + re[2] end end
			out[#out + 1] = {rid = rid, key = tostring(r.out), name = r.name or X.RecipeTitle(rid), cost = m.cost, sell = m.sell,
				margin = m.margin, pct = (m.margin and m.cost and m.cost > 0) and (m.margin / m.cost * 100) or nil,
				missing = m.missing or 0, count = count, prof = r.prof}
		end
	end
	table.sort(out, function(a, b)
		if (a.margin ~= nil) ~= (b.margin ~= nil) then return a.margin ~= nil end
		if a.margin and b.margin and a.margin ~= b.margin then return a.margin > b.margin end
		return (a.name or "") < (b.name or "")
	end)
	uses[itemID] = out
	return out
end
