-- Trends: the numbers behind the Trends view - a market index (is the whole auction house getting cheaper or
-- pricier?), the same per item group, the sums of each group (items, units and gold listed, supply), how full the
-- auction house is over time (from the full scans), and what changed in a period (risers, fallers, sold out, flooded,
-- new, back). The pages are in UITrendsIndex.lua, UITrendsGroups.lua, UITrendsSize.lua and UITrendsChanges.lua.
--
-- [[ the market index ]] like a stock index, 100 at the start of the period:
--   The basket = every item with a price near the start of the period and at least `minSamples` days of prices in
--   it. Each item's price on a day is compared with its own price at the start (a ratio: 1.1 = 10% dearer). The index
--   of a day is the typical ratio of the basket: the 10% highest and the 10% lowest ratios are left out (so a few odd
--   items cannot swing it) and the rest averaged the way growth is averaged (a geometric mean: +100% and -50% cancel
--   out), times 100. 103 = the typical item costs 3% more than at the start.
--   Prices are the day's market value (else the lowest price) from the day history; a day with no price keeps the
--   price before it. Before an item's first price in the period its ratio counts as 1 (no change). A day price far off
--   the item's typical price (X.CrazyPrice) is skipped; ratios are held between 0.2 and 5.
--   When the history is younger than the period, the period starts at the oldest day XNAH has.
--   Lines per item group (X.ItemGroup): the same, only for the items of that group (at least 3 items).
-- Group keys: "Trade Goods" = a whole group; "Trade Goods/Cloth" = a subgroup; "Armor/" = the items of a group that
-- have no subgroup (only used inside).
--
-- Functions:
--   X.TrendsGroupKeys(key) -> group key, leaf key of an item ("Trade Goods", "Trade Goods/Cloth")
--   X.TrendsGroupName(gk) -> name, parent group name (nil for a whole group); X.TrendsGroupLabel(gk) -> a short label
--   X.TrendsTypical(ratios) -> the index value (100 x the typical ratio) of a list of ratios
--   X.TrendsBuilder(opts) -> builder: B.pre(key, it), B.setup(), B.add(key, it), B.finishStep() -> true when done,
--     B.result = {index = {[days] = period result}, groups = {[gk] = sums}, today, first}
--     opts = {periods = {7, 30, ...}, groups = true, today = day number, now = seconds, minSamples}
--     period result = {P, start, days, step, all = {{t, v}}, lines = {[gk] = {{t, v}}}, n = {[gk] = items}, basket,
--       rising, falling, now (index today), last = {[gk] = value today}, items = {{key, g, leaf, r, base, now}}}
--     group sums = {items, units, gold (units x market value), now7, then7 (units now / 7 days ago of the items known then),
--       supply (% change of those units), listed (items listed now)}
--   X.TrendsRun(opts, items) -> the same result at once (small data and the tests)
--   X.TrendsData(periods) -> result, busy, progress: the index and group sums of this realm, worked out a little per
--     frame (X.Job) and kept until new prices or a new day. result may be the older one while busy; nil at first.
--   X.TrendsChangesBuilder(from, now) / X.TrendsChangesRun(from, now, items) / X.TrendsChanges(kind, from) -> lists
--     {risers, fallers, soldOut, flooded, new, back, from, first (oldest time seen), seen (items seen since from)}
--   X.TrendsSize(scans) -> the size of the auction house over time (from full scans) and a weekday / hour pattern
local ADDON, X = ...

local DAY = 86400
local LOG_MIN, LOG_MAX = math.log(0.2), math.log(5)
local TRIM = 0.1        -- this share of the ratios is left out at each end
local MIN_GROUP = 3     -- a group line needs this many items
local LIST_CAP = 200    -- the longest list of What changed
local CHANGE_MIN = 0.10 -- a riser / faller moved at least 10%
local FLOOD_UNITS = 10  -- flooded: at least twice as many listed and this many more

X.TRENDS_PERIODS = {7, 30, 90, 365}

-- [[ groups ]]
function X.TrendsGroupKeys(key)
	local _, _, g, s = X.ItemGroup(key)
	g = g or "Other"
	return g, g .. "/" .. (s or "")
end
-- "Trade Goods" -> "Trade Goods", nil; "Trade Goods/Cloth" -> "Cloth", "Trade Goods"
function X.TrendsGroupName(gk)
	local g, s = tostring(gk):match("^(.-)/(.*)$")
	if not g then return gk, nil end
	if s == "" then return g, nil end
	return s, g
end
-- a short label for a legend: the group, a trade goods subgroup by its own name ("Cloth"), else "Armor: Cloth"
function X.TrendsGroupLabel(gk)
	if gk == "all" then return "All items" end
	local name, parent = X.TrendsGroupName(gk)
	if not parent or parent == "Trade Goods" then return name end
	return parent .. ": " .. name
end

-- [[ the typical ratio ]] list = log ratios (sorted here, in place); the middle 80% averaged
local function trimmed(list)
	local n = #list
	if n == 0 then return nil end
	table.sort(list)
	local cut = math.floor(n * TRIM)
	local sum, c = 0, 0
	for i = cut + 1, n - cut do sum, c = sum + list[i], c + 1 end
	return 100 * math.exp(sum / c)
end
function X.TrendsTypical(ratios)
	local logs = {}
	for i, r in ipairs(ratios) do logs[i] = math.max(LOG_MIN, math.min(LOG_MAX, math.log(r))) end
	return trimmed(logs)
end

-- the first number of a packed history (its oldest day, or minute for scan points)
local function firstStamp(s)
	local a = s and s:match("^([^,;]*)")
	return X.n36(a)
end

-- the priced day points of an item: {{day, price, qty}, ...} oldest first, prices far off the typical one skipped
local function pricedDays(pts, from)
	local out, vals = {}, {}
	for _, p in ipairs(pts) do
		local v = p[3] or p[2]
		if v and v > 0 and p[1] >= from then out[#out + 1] = {p[1], v} vals[#vals + 1] = v end
	end
	if #vals >= 3 then
		local m = X.Median(vals)
		local kept = {}
		for _, p in ipairs(out) do if not X.CrazyPrice(p[2], m) then kept[#kept + 1] = p end end
		out = kept
	end
	return out
end

-- [[ the builder ]] one pass over the items for all periods and the group sums
function X.TrendsBuilder(opts)
	opts = opts or {}
	local today = opts.today or X.Day()
	local now = opts.now or X.Now()
	local minS = opts.minSamples or (X.S().minSamples or 3)
	local B = {today = today, periods = {}, sums = opts.groups and {} or nil}
	local longest = 0
	for _, P in ipairs(opts.periods or {}) do
		B.periods[#B.periods + 1] = {P = P, step = P <= 30 and 1 or (P <= 90 and 2 or 7)}
		if P > longest then longest = P end
	end
	-- phase 1: the oldest day of history (when the history is younger than a period, the period starts there)
	function B.pre(_, it)
		local d = it and firstStamp(it.d)
		if d and (not B.first or d < B.first) then B.first = d end
	end
	function B.setup()
		for _, pr in ipairs(B.periods) do
			pr.start = math.max(today - pr.P, math.min(B.first or today, today))
			pr.win = math.max(1, math.floor((today - pr.start) / 4))
			pr.days = {}
			for d = pr.start, today, pr.step do pr.days[#pr.days + 1] = d end
			if pr.days[#pr.days] ~= today then pr.days[#pr.days + 1] = today end
			pr.lists = {}
			for i = 1, #pr.days do pr.lists[i] = {} end
			pr.leafGroup, pr.n, pr.items = {}, {}, {}
			pr.basket, pr.rising, pr.falling = 0, 0, 0
		end
		B.di, B.pi = 1, 1
	end

	local function addSums(gk, it, thenQty)
		local s = B.sums[gk]
		if not s then
			s = {items = 0, units = 0, gold = 0, now7 = 0, then7 = 0, listed = 0, seen7 = 0}
			B.sums[gk] = s
		end
		local cur = it.cur or {}
		local qty = cur.qty or 0
		s.items = s.items + 1
		s.units = s.units + qty
		if qty > 0 then
			s.listed = s.listed + 1
			s.gold = s.gold + qty * (cur.mkt or cur.min or 0)
		end
		if thenQty then
			s.now7, s.then7, s.seen7 = s.now7 + qty, s.then7 + thenQty, s.seen7 + 1
		end
	end

	local function addPeriod(pr, key, g, leaf, priced)
		local n = #priced
		if n == 0 then return end
		local s = pr.start
		-- the price at the start: the last one on or before the start day (up to 7 days before), else the first one
		-- in the first quarter of the period
		local bi, bday
		for i = n, 1, -1 do
			local d = priced[i][1]
			if d <= s then
				if d >= s - 7 then bi, bday = i, s end
				break
			end
		end
		if not bi then
			for i = 1, n do
				local d = priced[i][1]
				if d > s then
					if d <= s + pr.win then bi, bday = i, d end
					break
				end
			end
		end
		if not bi or n - bi + 1 < minS then return end
		local base = priced[bi][2]
		local j, lr = bi, 0
		local days, lists = pr.days, pr.lists
		for di = 1, #days do
			local d = days[di]
			if d >= bday then
				while j < n and priced[j + 1][1] <= d do j = j + 1 end
				lr = math.max(LOG_MIN, math.min(LOG_MAX, math.log(priced[j][2] / base)))
			else
				lr = 0
			end
			local L = lists[di]
			local l = L[leaf]
			if not l then l = {} L[leaf] = l end
			l[#l + 1] = lr
		end
		pr.leafGroup[leaf] = g
		pr.n[leaf] = (pr.n[leaf] or 0) + 1
		if leaf ~= g .. "/" then pr.n[g] = (pr.n[g] or 0) + 1 end
		pr.basket = pr.basket + 1
		local r = math.exp(lr)
		if r > 1.01 then pr.rising = pr.rising + 1 elseif r < 0.99 then pr.falling = pr.falling + 1 end
		pr.items[#pr.items + 1] = {key = key, g = g, leaf = leaf, r = r, base = base, now = priced[j][2]}
	end

	-- phase 2: one item
	function B.add(key, it)
		if not it then return end
		local g, leaf = X.TrendsGroupKeys(key)
		local pts
		if B.sums then
			pts = X.UnpackPoints(it.d)
			-- units listed 7 days ago (the last day point 7 to 10 days back)
			local thenQty
			for i = #pts, 1, -1 do
				local d = pts[i][1]
				if d <= today - 7 then
					if d >= today - 10 then thenQty = pts[i][4] or 0 end
					break
				end
			end
			addSums("all", it, thenQty)
			addSums(g, it, thenQty)
			if leaf ~= g .. "/" then addSums(leaf, it, thenQty) end
		end
		if #B.periods == 0 or not it.d then return end
		pts = pts or X.UnpackPoints(it.d)
		local priced = pricedDays(pts, today - longest - 7)
		for _, pr in ipairs(B.periods) do addPeriod(pr, key, g, leaf, priced) end
	end

	-- phase 3: the index of one day of one period per call; true when all are done
	local function point(pr, gk, t, v)
		if not v then return end
		pr.lines[gk] = pr.lines[gk] or {}
		local l = pr.lines[gk]
		l[#l + 1] = {t, v}
		pr.last[gk] = v
	end
	function B.finishStep()
		local pr = B.periods[B.pi]
		if not pr then
			B.finish()
			return true
		end
		if B.di == 1 then pr.all, pr.lines, pr.last = {}, {}, {} end
		local di = B.di
		local L = pr.lists[di]
		local d = pr.days[di]
		local t = math.min(d * DAY + 43200, now)
		if pr.basket > 0 then
			-- the lists of each group's subgroups: byG[g] = {{leaf, list}, ...}, count[g] = items in them
			local all, byG, count = {}, {}, {}
			for leaf, l in pairs(L) do
				local g = pr.leafGroup[leaf]
				byG[g] = byG[g] or {}
				table.insert(byG[g], {leaf, l})
				count[g] = (count[g] or 0) + #l
				for i = 1, #l do all[#all + 1] = l[i] end
			end
			local v = trimmed(all)
			for g, leaves in pairs(byG) do
				-- a group with every item of the basket has the basket's value, a group of one subgroup that
				-- subgroup's value: sorted only once
				local gv
				if count[g] == #all then
					gv = v
				elseif count[g] >= MIN_GROUP then
					if #leaves == 1 then
						gv = trimmed(leaves[1][2])
					else
						local gl = {}
						for _, e in ipairs(leaves) do for i = 1, #e[2] do gl[#gl + 1] = e[2][i] end end
						gv = trimmed(gl)
					end
				end
				point(pr, g, t, gv)
				for _, e in ipairs(leaves) do
					local leaf, l = e[1], e[2]
					if #l >= MIN_GROUP and leaf ~= g .. "/" then point(pr, leaf, t, #l == count[g] and gv or trimmed(l)) end
				end
			end
			if v then pr.all[#pr.all + 1] = {t, v} pr.now = v end
		end
		pr.lists[di] = nil
		B.di = di + 1
		if B.di > #pr.days then B.pi, B.di = B.pi + 1, 1 end
		return false
	end
	function B.finish()
		local index = {}
		for _, pr in ipairs(B.periods) do
			pr.lists = nil
			pr.lines.all = pr.all
			pr.last.all = pr.now
			pr.n.all = pr.basket
			index[pr.P] = pr
		end
		if B.sums then
			for _, s in pairs(B.sums) do
				if s.seen7 > 0 and s.then7 > 0 then s.supply = (s.now7 / s.then7 - 1) * 100 end
			end
		end
		B.result = {index = index, groups = B.sums, today = today, first = B.first}
	end
	return B
end

-- all at once
function X.TrendsRun(opts, items)
	items = items or X.Items()
	local B = X.TrendsBuilder(opts)
	for key, it in pairs(items) do B.pre(key, it) end
	B.setup()
	for key, it in pairs(items) do B.add(key, it) end
	while not B.finishStep() do end
	return B.result
end

-- [[ worked out a little per frame, kept until new prices or a new day ]]
local version = 0
-- (item names coming in from the game change no number here: kind "names")
X.On("XNAH_PRICES", function(kind) if kind ~= "names" then version = version + 1 end end)
-- items per frame: at most PRE_SLICE in the first quick pass, at most `slice` (ADD_SLICE unless the job says) in the
-- main one, and the main one also stops for the frame once BUDGET_MS milliseconds went by (a big auction house on a
-- slower PC: the game keeps running smoothly, the work just takes a few more frames)
local PRE_SLICE, ADD_SLICE, BUDGET_MS = 2000, 80, 12
local clock = debugprofilestop or function() return 0 end
-- a cached job: state = {res, ver, day, items, key, running, progress}
local function cachedJob(state, name, makeKeys, builder, label, valid, done, slice)
	slice = slice or ADD_SLICE
	local items = X.Items()
	local day = X.Day()
	if state.res and state.items == items and state.ver == version and state.day == day and valid(state) then
		return state.res, false, nil
	end
	if state.running then return state.items == items and state.res or nil, true, state.progress end
	state.running = true
	local ver = version
	local keys = makeKeys(items)
	local B = builder()
	local phase, i = 1, 0
	state.progress = label .. ": 0 / " .. X.Num(#keys)
	X.Job(name, function()
		if X.Items() ~= items then return true end -- the realm changed: stop
		if phase == 1 then
			if not B.pre then phase = 2 else
				local stop = math.min(#keys, i + PRE_SLICE)
				while i < stop do i = i + 1 B.pre(keys[i], items[keys[i]]) end
				if i >= #keys then phase, i = 2, 0 if B.setup then B.setup() end end
				return false
			end
		end
		if phase == 2 then
			local stop = math.min(#keys, i + slice)
			local t0 = clock()
			while i < stop do
				i = i + 1
				B.add(keys[i], items[keys[i]])
				if clock() - t0 > BUDGET_MS then break end
			end
			state.progress = label .. ": " .. X.Num(i) .. " / " .. X.Num(#keys)
			if i >= #keys then phase = 3 end
			return false
		end
		-- one day of the index per frame (each sorts the basket's price changes)
		return B.finishStep()
	end, function()
		state.running = false
		if B.result then
			state.res, state.ver, state.day, state.items = B.result, ver, day, items
			if done then done(state) end
		end
		if X.UI and X.UI.current == "trends" and X.UI.Refresh then X.UI.Refresh(true) end
	end)
	return state.items == items and state.res or nil, true, state.progress
end
local function allKeys(items)
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	return keys
end

local main = {}
-- the index of the periods asked for (7 and 30 days always: the tiles and the Groups page) and the group sums
function X.TrendsData(periods)
	local want = {[7] = true, [30] = true}
	for _, P in ipairs(periods or {}) do want[P] = true end
	local list = {}
	for _, P in ipairs(X.TRENDS_PERIODS) do if want[P] then list[#list + 1] = P end end
	local function valid(st)
		for _, P in ipairs(list) do if not st.res.index[P] then return false end end
		return true
	end
	return cachedJob(main, "trends index", allKeys, function()
		return X.TrendsBuilder({periods = list, groups = true})
	end, "Working out the index", valid)
end
-- forget what was worked out (tests)
function X.TrendsForget()
	for k in pairs(main) do main[k] = nil end
	X.TrendsChangesForget()
end

-- the last history point at or before `from` and not before `oldest` (seconds): {t, min, mkt, qty} or nil - the same
-- point as the last of X.HistoryRaw(it, oldest) at or before `from`, but only the time of each point is read (an item
-- has up to a few hundred scan points; unpacking them all for every item was slow on a big auction house)
local function pointBefore(it, from, oldest)
	local hs = it.h
	local firstScan = hs and firstStamp(hs)
	firstScan = firstScan and firstScan * 60 or math.huge
	local pick, pickDay
	if hs and firstScan <= from then
		for part in hs:gmatch("[^;]+") do
			local t = X.n36(part:match("^([^,]*)"))
			if t then
				t = t * 60
				if t > from then break end
				if t >= oldest then pick = part end
			end
		end
	end
	if not pick and it.d then
		-- day points (noon of the day) from before the scan points start
		for part in it.d:gmatch("[^;]+") do
			local d = X.n36(part:match("^([^,]*)"))
			if d then
				local t = d * DAY + 43200
				if t > from or t >= firstScan - 43200 then break end
				if t >= oldest then pick, pickDay = part, t end
			end
		end
	end
	if not pick then return nil end
	local p = X.UnpackPoints(pick)[1]
	if not p then return nil end
	return {pickDay or p[1] * 60, p[2], p[3], p[4]}
end
X.TrendsPointBefore = pointBefore -- (tests)

-- [[ what changed ]] from = the start of the period (seconds)
function X.TrendsChangesBuilder(from, now)
	now = now or X.Now()
	local C = {from = from, now = now, risers = {}, fallers = {}, soldOut = {}, flooded = {}, new = {}, back = {}, seen = 0}
	function C.add(key, it)
		local cur = it and it.cur
		if not cur or not cur.t then return end
		-- first seen: the first scan point when it is from the item's first day, else the start of its first day
		local fd = firstStamp(it.d)
		local fsMin = firstStamp(it.h)
		local firstSeen
		if fsMin and (not fd or X.Day(fsMin * 60) <= fd) then firstSeen = fsMin * 60 elseif fd then firstSeen = fd * DAY end
		if firstSeen and (not C.first or firstSeen < C.first) then C.first = firstSeen end
		if cur.t >= from then C.seen = C.seen + 1 end
		local qty = cur.qty or 0
		local price = cur.mkt or cur.min
		if firstSeen and firstSeen > from then
			if qty > 0 or cur.t >= from then
				C.new[#C.new + 1] = {key = key, first = firstSeen, qty = qty, price = price}
			end
			return
		end
		if cur.t < from then return end -- not seen since: nothing to tell
		-- the last point at or before the start of the period (up to 8 days before)
		local before = pointBefore(it, from, from - 8 * DAY)
		local qty0 = before and (before[4] or 0) or 0
		local price0 = before and (before[3] or before[2])
		if qty0 >= 0.5 and qty == 0 then
			C.soldOut[#C.soldOut + 1] = {key = key, qty0 = qty0, price0 = price0, t = cur.t}
			return
		end
		if qty0 < 0.5 then
			if qty > 0 then C.back[#C.back + 1] = {key = key, qty = qty, price = price} end
			return
		end
		if qty >= qty0 * 2 and qty - qty0 >= FLOOD_UNITS then
			C.flooded[#C.flooded + 1] = {key = key, qty0 = qty0, qty = qty, change = (qty / qty0 - 1) * 100}
		end
		if price0 and price0 > 0 and price and price > 0 and qty > 0 and not X.CrazyPrice(price, price0) then
			local ch = price / price0 - 1
			local row = {key = key, price0 = price0, price = price, change = ch * 100}
			if ch >= CHANGE_MIN then C.risers[#C.risers + 1] = row elseif ch <= -CHANGE_MIN then C.fallers[#C.fallers + 1] = row end
		end
	end
	-- a list sorted best first and cut to LIST_CAP rows; each row's number is worked out once (not in every comparison:
	-- a list can have thousands of rows on a real auction house)
	local function cap(list, better)
		local v = {}
		for _, r in ipairs(list) do v[r] = better(r) or 0 end
		table.sort(list, function(a, b)
			local x, y = v[a], v[b]
			if x ~= y then return x > y end
			return a.key < b.key
		end)
		for i = #list, LIST_CAP + 1, -1 do list[i] = nil end
	end
	-- one list per call (the job runs one call a frame); true when all six are done
	local CAPS = {
		{"risers", function(r) return r.change end},
		{"fallers", function(r) return -r.change end},
		{"soldOut", function(r) return (r.price0 or 0) * r.qty0 end},
		{"flooded", function(r) return r.change end},
		{"new", function(r) return r.first end},
		{"back", function(r) return (r.price or 0) * r.qty end},
	}
	local capped = 0
	function C.finishStep()
		capped = capped + 1
		local c = CAPS[capped]
		if c then
			cap(C[c[1]], c[2])
			return false
		end
		-- the history starts after the start of the period: every item looks new
		C.tooYoung = C.first == nil or C.first > from
		C.result = C
		return true
	end
	return C
end
function X.TrendsChangesRun(from, now, items)
	local C = X.TrendsChangesBuilder(from, now)
	for key, it in pairs(items or X.Items()) do C.add(key, it) end
	while not C.finishStep() do end
	return C
end
-- kind = "visit" / "day" / "week" (each kept apart); from = the start of the period. A start that moved less than
-- 10 minutes keeps the list worked out before.
local changeStates = {}
function X.TrendsChanges(kind, from)
	local st = changeStates[kind]
	if not st then st = {} changeStates[kind] = st end
	if not st.running and (not st.from or math.abs(st.from - from) >= 600) then st.from, st.res = from, nil end
	local f = st.from
	-- (each item's scan points of the last days are read: fewer items per frame than for the index)
	return cachedJob(st, "trends changes", allKeys, function() return X.TrendsChangesBuilder(f) end,
		"Looking through the items", function() return true end, nil, 40)
end
function X.TrendsChangesForget() for k in pairs(changeStates) do changeStates[k] = nil end end

-- [[ the size of the auction house ]] scans = X.Scans("full"), oldest first.
-- -> {gold = {{t, v}}, auctions, items, units (each only the scans that have it), last = scan, ago = the scan nearest to
--   7 days before it (1 to 13 days before), change = {gold = %, ...}, pattern = {days = {[0..6] = {n, pct}}, hours =
--   {[0..23] = {n, pct}}, scans, dayCount (different days), daysOK, hoursOK}}
X.TRENDS_SIZE = {"gold", "auctions", "items", "units"}
local PAT_MIN_SCANS, PAT_MIN_DAYS, PAT_MIN_WEEKDAYS, PAT_MIN_HOURS = 10, 3, 4, 6
function X.TrendsSize(scans)
	scans = scans or X.Scans("full")
	local out = {scans = #scans}
	for _, f in ipairs(X.TRENDS_SIZE) do out[f] = {} end
	for _, sc in ipairs(scans) do
		if sc.t then
			for _, f in ipairs(X.TRENDS_SIZE) do
				local v = sc[f]
				if type(v) == "number" then table.insert(out[f], {sc.t, v}) end
			end
		end
	end
	local last = scans[#scans]
	out.last, out.change = last, {}
	if last and last.t then
		local best, bestD
		for i = #scans - 1, 1, -1 do
			local sc = scans[i]
			local age = last.t - (sc.t or 0)
			if age >= DAY and age <= 13 * DAY then
				local d = math.abs(age - 7 * DAY)
				if not bestD or d < bestD then best, bestD = sc, d end
			end
		end
		out.ago = best
		if best then
			for _, f in ipairs(X.TRENDS_SIZE) do
				local a, b = last[f], best[f]
				if type(a) == "number" and type(b) == "number" and b > 0 then out.change[f] = (a / b - 1) * 100 end
			end
		end
	end
	-- how full by weekday and hour: each scan's auctions against the average of the scans within 3 days of it
	local days, hours = {}, {}
	for d = 0, 6 do days[d] = {n = 0, r = 0} end
	for h = 0, 23 do hours[h] = {n = 0, r = 0} end
	local used, dayset = 0, {}
	for i, sc in ipairs(scans) do
		if sc.t and type(sc.auctions) == "number" and sc.auctions > 0 then
			local sum, c = 0, 0
			for j = i, 1, -1 do
				local o = scans[j]
				if (sc.t - (o.t or 0)) > 3 * DAY then break end
				if type(o.auctions) == "number" and o.auctions > 0 then sum, c = sum + o.auctions, c + 1 end
			end
			for j = i + 1, #scans do
				local o = scans[j]
				if ((o.t or 0) - sc.t) > 3 * DAY then break end
				if type(o.auctions) == "number" and o.auctions > 0 then sum, c = sum + o.auctions, c + 1 end
			end
			if c >= 2 then
				local r = sc.auctions / (sum / c)
				local wd, hr = X.ServerWeekday(sc.t)
				days[wd].n, days[wd].r = days[wd].n + 1, days[wd].r + r
				hours[hr].n, hours[hr].r = hours[hr].n + 1, hours[hr].r + r
				used = used + 1
				dayset[X.Day(sc.t)] = true
			end
		end
	end
	local nDays, nWeekdays, nHours = 0, 0, 0
	for _ in pairs(dayset) do nDays = nDays + 1 end
	for d = 0, 6 do
		local s = days[d]
		if s.n > 0 then s.pct = (s.r / s.n - 1) * 100 nWeekdays = nWeekdays + 1 end
	end
	for h = 0, 23 do
		local s = hours[h]
		if s.n > 0 then s.pct = (s.r / s.n - 1) * 100 nHours = nHours + 1 end
	end
	out.pattern = {days = days, hours = hours, scans = used, dayCount = nDays,
		daysOK = used >= PAT_MIN_SCANS and nWeekdays >= PAT_MIN_WEEKDAYS,
		hoursOK = used >= PAT_MIN_SCANS and nDays >= PAT_MIN_DAYS and nHours >= PAT_MIN_HOURS}
	out.pattern.need = {scans = PAT_MIN_SCANS, days = PAT_MIN_DAYS, weekdays = PAT_MIN_WEEKDAYS, hours = PAT_MIN_HOURS}
	return out
end
