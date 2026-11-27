-- Moves with: which other items' prices go up and down on the same days as one item (ore and its bars, a herb and
-- its potion), and which move the opposite way. The page is in UIItemRelated.lua.
--
-- How it is worked out:
--   The day prices of the history (Data.lua: the day's market value, else its lowest price; one point a day for 60
--   days, then one a week) of the last 30 or 90 days. Prices far off an item's typical price (X.CrazyPrice against
--   the middle of its prices in the range) are left out.
--   The whole market first: on each day, the typical change of every item that had a price that day and the day
--   before (the middle one of them; at least MARKET_MIN items). That part is taken out of every item's changes, so
--   two items are not shown as linked only because the whole auction house got dearer or cheaper on the same days.
--   Two items are only compared on the days BOTH have a price ("shared days"). From one shared day to the next (at
--   most MAX_GAP days apart) each item's price change is taken as a growth rate (the log of new / old, so +100% and
--   -50% weigh the same; held between 1/5 and 5 times), less the market's change. The two lists of changes are then
--   compared by their order (a rank correlation: each day's change is replaced by its place from the biggest fall to
--   the biggest rise, so one wild day cannot make two items look linked): +1 = on the days one rose most the other
--   rose most too, and the same for the falls; 0 = no link; -1 = always the opposite way.
--   With only a few days, two unrelated items can look linked by chance, and XNAH compares one item with thousands.
--   So an item is only listed when the link is bigger than two unrelated items reach by chance in 2 of 10,000 tries
--   (about one chance link among 5,000 items compared; X.RelatedNeed, the numbers come from a simulation of unrelated
--   lists): with 10 days that needs about 0.95, with 30 days about 0.65, with 60 days about 0.47. The list is sorted by
--   the weakest the link is likely to be (the low end of a 95% range), so a long history counts for more than a lucky
--   week. (On Xn's real data with 10 days, a looser rule listed dozens of items per item, mostly gear that cannot be
--   linked to ore or herbs - chance links.)
--   Items need at least MIN_SHARED shared days and MIN_CHANGES changes, and the price of each must have changed (by
--   more than MOVE) on at least half of them: a price that stays put (one gear item listed at the same price all week)
--   cannot be matched with anything. Items with fewer than MIN_QTY listed on a typical day are left out too: their
--   price jumps whenever one auction sells or one is put up.
--
-- Functions:
--   X.RelatedSeries(it, fromDay, toDay, level) -> {days = {...}, logs = {...} (log prices less the market level),
--     raw = {...} (log prices)} the priced days of an item (oldest first)
--   X.RelatedMarket(days, items) -> level = {[day] = the market's log level} at once (the tests; the page does it sliced)
--   X.RelatedPair(a, b, days, level) -> stats of two items (keys) over the last `days` days (level: optional, from
--     X.RelatedMarket), or nil when too few shared days or one of them hardly moved:
--     {r (-1 to 1), shared (days both have a price), changes (changes compared), z, low (the low end of the 95% range of
--     the size of r, 0 to 1)}
--   X.RelatedWord(r) -> "Very closely" / "Closely" / "A bit" / "Opposite"
--   X.RelatedNeed(changes) -> the smallest link (size of r) listed for that many changes
--   X.RelatedBuilder(key, days, opts {items, today, level}) -> B: B.ready (false = too few prices of the item itself,
--     or it hardly moved: B.result is set at once), B.add(otherKey, it), B.finish() -> result
--     result = {key, days, together = {rows, best first, at most TOGETHER}, opposite = {rows, at most OPPOSITE}, have
--     (priced days of the item in the range), tooFew (true: fewer than MIN_SHARED), flat (true: the item's price hardly
--     moved), fewListed (the number listed on a typical day, when under MIN_QTY), checked (items looked at), compared
--     (items with enough shared days), found (items linked)}
--     row = {key, r, shared, changes, z, low, word}
--   X.RelatedRun(key, days, items) -> the same result at once (the tests)
--   X.Related(key, days, notify) -> result, busy, progress: worked out a little per frame (X.Job: at most SLICE items or
--     BUDGET_MS milliseconds a frame) and kept per item and range until new prices arrive or the day changes (in
--     memory only, nothing is saved; the market part is kept per range and shared by every item). While busy the
--     result of an earlier run (or nil) comes back with a progress text; notify(done, progress) is called now and then
--     while it works (done = false) and once at the end (done = true).
--   X.RelatedForget() forgets every result (tests)
local ADDON, X = ...

X.RELATED_RANGES = {30, 90}
X.RELATED_MIN_SHARED = 10
local MIN_SHARED = X.RELATED_MIN_SHARED -- days both items need a price on
local MIN_CHANGES = 8                   -- day-to-day changes compared
local MAX_GAP = 7                       -- two shared days further apart than this are not compared
local MOVE, MIN_MOVES = 0.002, 4        -- a change of more than 0.2% is a move; each item needs this many ...
local MOVE_SHARE = 0.5                  -- ... and moves on at least half of the changes compared
-- the smallest link (rank correlation, either way) listed, by changes compared: two unrelated lists of that length
-- reach it in only 2 of 10,000 tries (simulated, 500,000 tries each); in between straight lines, after 90 shrinking
-- like 1 / square root of the changes
local NEED = {{8, 0.976}, {9, 0.950}, {10, 0.939}, {11, 0.918}, {12, 0.888}, {14, 0.855}, {16, 0.824}, {18, 0.787},
	{20, 0.752}, {25, 0.688}, {30, 0.644}, {40, 0.561}, {50, 0.508}, {60, 0.470}, {75, 0.418}, {90, 0.382}}
function X.RelatedNeed(changes)
	if changes <= NEED[1][1] then return NEED[1][2] end
	for i = 2, #NEED do
		local a, b = NEED[i - 1], NEED[i]
		if changes <= b[1] then return a[2] + (b[2] - a[2]) * (changes - a[1]) / (b[1] - a[1]) end
	end
	local last = NEED[#NEED]
	return last[2] * math.sqrt((last[1] - 1) / (changes - 1))
end
local Z95 = 1.96
local RANK_SE = 1.06                    -- a rank correlation is a little less sure than a plain one of the same days
local TOGETHER, OPPOSITE = 15, 5        -- rows of each list
local LOG_CAP = math.log(5)
local MIN_QTY = 5                       -- items with fewer listed on a typical day are left out (see above)
local MARKET_MIN = 20                   -- a day's market change needs this many items (else it counts as none)
local BIN, BINS = 0.002, 500            -- the market's changes are counted in steps of 0.2% (-50% to +50%)
local SLICE, BUDGET_MS = 100, 12   -- items a frame at most (the game stops sooner when 12 ms went by)
X.RELATED_TOGETHER, X.RELATED_OPPOSITE = TOGETHER, OPPOSITE

local n36 = function(s) if s == nil or s == "" then return nil end return tonumber(s, 36) end
local log, sqrt, abs, floor = math.log, math.sqrt, math.abs, math.floor
local NO_LEVEL = {}
local function capLog(x)
	if x > LOG_CAP then return LOG_CAP end
	if x < -LOG_CAP then return -LOG_CAP end
	return x
end
local function atanh(r)
	if r > 0.9999 then r = 0.9999 elseif r < -0.9999 then r = -0.9999 end
	return 0.5 * log((1 + r) / (1 - r))
end
local function tanh(x)
	local e = math.exp(2 * x)
	return (e - 1) / (e + 1)
end

-- [[ the priced days of an item ]] "day,min,mkt,..." points, oldest first; `want` (optional) = {[day] = true}: only
-- those days are kept (the others are not even read as prices)
-- -> days, prices, the average number listed on those days
local function priced(d, fromDay, toDay, want)
	local days, vals = {}, {}
	if not d or d == "" then return days, vals, 0 end
	local units = 0
	for a, b, c, q in d:gmatch("([^,;]*),([^,;]*),([^,;]*),?([^,;]*)[^;]*") do
		local day = n36(a)
		if day and day >= fromDay and day <= toDay and (not want or want[day]) then
			local v = n36(c) or n36(b)
			if v and v > 0 then
				days[#days + 1] = day
				vals[#vals + 1] = v
				units = units + (n36(q) or 0)
			end
		end
	end
	local avgQty = #vals > 0 and units / #vals or 0
	-- prices far off the middle of them are left out
	if #vals >= 3 then
		local m = X.Median(vals)
		local kd, kv = {}, {}
		for i = 1, #vals do
			if not X.CrazyPrice(vals[i], m) then kd[#kd + 1] = days[i] kv[#kv + 1] = vals[i] end
		end
		days, vals = kd, kv
	end
	return days, vals, avgQty
end
function X.RelatedSeries(it, fromDay, toDay, level)
	level = level or NO_LEVEL
	local days, vals, avgQty = priced(it and it.d, fromDay, toDay or X.Day())
	local logs, raw = {}, {}
	for i = 1, #vals do
		raw[i] = log(vals[i])
		logs[i] = raw[i] - (level[days[i]] or 0)
	end
	return {days = days, logs = logs, raw = raw, qty = avgQty}
end

-- [[ the whole market ]] each day's middle change of every item priced that day and the day before
local function marketBuilder(fromDay, toDay)
	local M = {count = {}, bins = {}}
	function M.add(it)
		local d = it and it.d
		if not d or #d < 14 then return end
		local days, vals = priced(d, fromDay, toDay)
		for i = 2, #days do
			local day = days[i]
			if day - days[i - 1] == 1 then
				local x = capLog(log(vals[i] / vals[i - 1]))
				-- (step b holds the changes nearest to (b - 1 - BINS / 2) x BIN; no change at all = the middle step)
				local b = floor(x / BIN + 0.5) + BINS / 2 + 1
				if b < 1 then b = 1 elseif b > BINS + 1 then b = BINS + 1 end
				local h = M.bins[day]
				if not h then h = {} M.bins[day] = h end
				h[b] = (h[b] or 0) + 1
				M.count[day] = (M.count[day] or 0) + 1
			end
		end
	end
	function M.finish()
		local level, sum = {}, 0
		for day = fromDay, toDay do
			local n, h = M.count[day] or 0, M.bins[day]
			if n >= MARKET_MIN and h then
				local half, seen = n / 2, 0
				for b = 1, BINS + 1 do
					seen = seen + (h[b] or 0)
					if seen >= half then
						sum = sum + (b - 1 - BINS / 2) * BIN
						break
					end
				end
			end
			level[day] = sum
		end
		M.bins, M.count = nil, nil
		return level
	end
	return M
end
function X.RelatedMarket(days, items)
	local today = X.Day()
	local M = marketBuilder(today - (days or 30) - 1, today)
	for _, it in pairs(items or X.Items()) do M.add(it) end
	return M.finish()
end

-- the places of the values of v[1..n] from the smallest (1) to the biggest (n); equal values share the average place
local function ranks(v, n)
	local idx, out = {}, {}
	for i = 1, n do idx[i] = i end
	table.sort(idx, function(a, b) return v[a] < v[b] end)
	local i = 1
	while i <= n do
		local j = i
		while j < n and v[idx[j + 1]] == v[idx[i]] do j = j + 1 end
		local place = (i + j) / 2
		for k = i, j do out[idx[k]] = place end
		i = j + 1
	end
	return out
end
-- how alike two lists of the same length are (Pearson), -1 to 1; nil when one of them does not vary
local function pearson(xs, ys, n)
	local sx, sy, sxx, syy, sxy = 0, 0, 0, 0, 0
	for i = 1, n do
		local x, y = xs[i], ys[i]
		sx, sy = sx + x, sy + y
		sxx, syy, sxy = sxx + x * x, syy + y * y, sxy + x * y
	end
	local vx, vy = sxx / n - (sx / n) ^ 2, syy / n - (sy / n) ^ 2
	if vx <= 1e-12 or vy <= 1e-12 then return nil end
	local r = (sxy / n - (sx / n) * (sy / n)) / sqrt(vx * vy)
	if r > 1 then r = 1 elseif r < -1 then r = -1 end
	return r
end

-- [[ two items ]] target = {at = {[day] = log price less the market}, rawAt = {[day] = log price}, level}; the other's
-- priced days (only the shared ones)
local function pairStats(target, days, vals, qty)
	local n = #days
	if n < MIN_SHARED or (qty or 0) < MIN_QTY then return nil, n end
	local at, rawAt, level = target.at, target.rawAt, target.level
	local xs, ys, c, mx, my = {}, {}, 0, 0, 0
	local pd, pt, po, prt, pro
	for i = 1, n do
		local day = days[i]
		local ro = log(vals[i])
		local t, o, rt = at[day], ro - (level[day] or 0), rawAt[day]
		if pd and day - pd <= MAX_GAP then
			c = c + 1
			xs[c], ys[c] = capLog(t - pt), capLog(o - po)
			-- (moves are counted on the plain prices: did the price change at all?)
			if abs(rt - prt) > MOVE then mx = mx + 1 end
			if abs(ro - pro) > MOVE then my = my + 1 end
		end
		pd, pt, po, prt, pro = day, t, o, rt, ro
	end
	-- (an item that hardly moved cannot be matched: its few changes would decide everything)
	local need = math.max(MIN_MOVES, c * MOVE_SHARE)
	if c < MIN_CHANGES or mx < need or my < need then return nil, n end
	local r = pearson(ranks(xs, c), ranks(ys, c), c)
	if not r then return nil, n end
	local se = sqrt(RANK_SE / math.max(1, c - 3))
	local z = atanh(r) / se
	local low = math.max(0, tanh(abs(atanh(r)) - Z95 * se))
	return {r = r, shared = n, changes = c, z = z, low = low}, n
end

function X.RelatedWord(r)
	if not r then return "" end
	if r < 0 then return "Opposite" end
	if r >= 0.8 then return "Very closely" end
	if r >= 0.6 then return "Closely" end
	return "A bit"
end

-- the item picked: its priced days and how often its price changes
local function targetOf(it, fromDay, toDay, level)
	level = level or NO_LEVEL
	local s = X.RelatedSeries(it, fromDay, toDay, level)
	s.at, s.rawAt, s.want, s.level = {}, {}, {}, level
	for i, day in ipairs(s.days) do s.at[day], s.rawAt[day], s.want[day] = s.logs[i], s.raw[i], true end
	local c, moves = 0, 0
	for i = 2, #s.days do
		if s.days[i] - s.days[i - 1] <= MAX_GAP then
			c = c + 1
			if abs(s.raw[i] - s.raw[i - 1]) > MOVE then moves = moves + 1 end
		end
	end
	s.flat = c >= MIN_CHANGES and moves < math.max(MIN_MOVES, c * MOVE_SHARE)
	return s
end

function X.RelatedPair(a, b, days, level)
	local items = X.Items()
	local ia, ib = items[tostring(a)], items[tostring(b)]
	if not (ia and ib) then return nil end
	local today = X.Day()
	local from = today - (days or 30)
	local t = targetOf(ia, from, today, level)
	local dd, vv, qq = priced(ib.d, from, today, t.want)
	return (pairStats(t, dd, vv, qq))
end

-- [[ the builder ]] one item against the others
function X.RelatedBuilder(key, days, opts)
	opts = opts or {}
	key = tostring(key)
	days = days or 30
	local today = opts.today or X.Day()
	local from = today - days
	local items = opts.items or X.Items()
	local B = {key = key, days = days}
	local res = {key = key, days = days, together = {}, opposite = {}, checked = 0, compared = 0}
	local target = targetOf(items[key], from, today, opts.level)
	res.have = #target.days
	local pos, neg = {}, {}
	if #target.days < MIN_SHARED then
		res.tooFew = true
	elseif target.flat then
		res.flat = true
	elseif target.qty < MIN_QTY then
		res.fewListed = target.qty
	end
	B.ready = not (res.tooFew or res.flat or res.fewListed)
	if not B.ready then B.result = res end
	-- a quick look: too short a history to have enough priced days (each point is at least 7 characters)
	local minLen = MIN_SHARED * 7
	function B.add(k, it)
		if k == key or not it then return end
		local d = it.d
		if not d or #d < minLen then return end
		res.checked = res.checked + 1
		local dd, vv, qq = priced(d, from, today, target.want)
		local st = pairStats(target, dd, vv, qq)
		if not st then return end
		res.compared = res.compared + 1
		if abs(st.r) < X.RelatedNeed(st.changes) then return end
		st.key, st.word = k, X.RelatedWord(st.r)
		if st.r > 0 then pos[#pos + 1] = st else neg[#neg + 1] = st end
	end
	local function best(list, n)
		table.sort(list, function(x, y)
			if x.low ~= y.low then return x.low > y.low end
			if x.changes ~= y.changes then return x.changes > y.changes end
			return x.key < y.key
		end)
		local out = {}
		for i = 1, math.min(n, #list) do out[i] = list[i] end
		return out
	end
	function B.finish()
		if B.ready then
			res.together = best(pos, TOGETHER)
			res.opposite = best(neg, OPPOSITE)
			res.found = #pos + #neg
		end
		B.result = res
		return res
	end
	return B
end
function X.RelatedRun(key, days, items)
	items = items or X.Items()
	local B = X.RelatedBuilder(key, days, {items = items, level = X.RelatedMarket(days, items)})
	if not B.ready then return B.result end
	for k, it in pairs(items) do B.add(k, it) end
	return B.finish()
end

-- [[ a little per frame, kept until new prices ]]
local version = 0
X.On("XNAH_PRICES", function(kind) if kind ~= "names" then version = version + 1 end end)
local cache = {}     -- ["key|days"] = {res, ver, day, items, used}
local markets = {}   -- [days] = {level, ver, day, items}
local CACHE_MAX = 20 -- results kept (the ones looked at longest ago go first)
local running        -- {ck, cancelled, progress, notify}
local clock = debugprofilestop or function() return 0 end
local uses = 0

local function keep(ck, entry)
	cache[ck] = entry
	local n = 0
	for _ in pairs(cache) do n = n + 1 end
	while n > CACHE_MAX do
		local oldK, oldU
		for k, e in pairs(cache) do
			if k ~= ck and (not oldU or e.used < oldU) then oldK, oldU = k, e.used end
		end
		if not oldK then break end
		cache[oldK] = nil
		n = n - 1
	end
end
local function current(e, items, today) return e and e.items == items and e.ver == version and e.day == today end

function X.Related(key, days, notify)
	if not key then return nil, false end
	key = tostring(key)
	days = days or 30
	local ck = key .. "|" .. days
	local items, today = X.Items(), X.Day()
	local entry = cache[ck]
	uses = uses + 1
	if entry then entry.used = uses end
	local old = entry and entry.items == items and entry.res or nil
	if current(entry, items, today) then return entry.res, false, nil end
	if running and running.ck == ck and not running.cancelled then
		running.notify = notify
		return old, true, running.progress
	end
	-- another item or range was being worked out: it stops (only one at a time)
	if running then running.cancelled = true running = nil end
	local ver = version
	-- too few prices of the item itself: said at once (no need for the market)
	local B = X.RelatedBuilder(key, days, {items = items, today = today})
	if not B.ready then
		keep(ck, {res = B.result, ver = ver, day = today, items = items, used = uses})
		return B.result, false, nil
	end
	local mk = markets[days]
	local level = current(mk, items, today) and mk.level or nil
	local M = not level and marketBuilder(today - days - 1, today) or nil
	if level then B = X.RelatedBuilder(key, days, {items = items, today = today, level = level}) end
	local keys = {}
	for k in pairs(items) do keys[#keys + 1] = k end
	local total = #keys * (M and 2 or 1)
	local job = {ck = ck, notify = notify, progress = "Working... 0%"}
	running = job
	local i, done, frames = 0, 0, 0
	X.Job("moves with", function()
		if job.cancelled or X.Items() ~= items then return true end
		local stop = math.min(#keys, i + SLICE)
		local t0 = clock()
		while i < stop do
			i = i + 1
			local k = keys[i]
			if M then M.add(items[k]) else B.add(k, items[k]) end
			if clock() - t0 > BUDGET_MS then break end
		end
		job.progress = "Working... " .. floor((done + i) / math.max(1, total) * 100) .. "%"
		frames = frames + 1
		if frames % 6 == 0 and job.notify then
			local ok, err = pcall(job.notify, false, job.progress)
			if not ok then X.OnError(err) end
		end
		if i >= #keys and M then
			-- the market is known: now the item against every other one
			level = M.finish()
			markets[days] = {level = level, ver = ver, day = today, items = items}
			M, done, i = nil, #keys, 0
			B = X.RelatedBuilder(key, days, {items = items, today = today, level = level})
			return false
		end
		return i >= #keys
	end, function()
		if job.cancelled or X.Items() ~= items or M then return end
		if running == job then running = nil end
		keep(ck, {res = B.finish(), ver = ver, day = today, items = items, used = uses})
		if job.notify then job.notify(true) end
	end)
	return old, true, job.progress
end
function X.RelatedForget()
	cache, markets = {}, {}
	if running then running.cancelled = true running = nil end
end
