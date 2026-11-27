-- Patterns of one item: when it is cheap or scarce (a weekday x time-of-day grid), how jumpy its price is, and how
-- much of it sells a day (the size of its market). The numbers only; the Patterns page (UIItemPatterns.lua) and the
-- small grid on the Overview (UIItem.lua) show them, drawn with K.Heatmap (Heatmap.lua).
--
-- [[ the weekday x time-of-day grid ]] scan points are kept only 7 days (keepScanDays), too short to tell weekdays apart,
-- so each item you track or look at keeps a small summary that lives on: 7 weekdays x 6 times of the day (blocks of 4
-- hours, the realm's clock) = 42 cells. Each cell remembers how often the item was seen then, its price then against
-- its usual price, and how many were listed then. Older weeks count less: an observation counts half after 21 days,
-- a quarter after 42 ... so the grid follows the market. The first time, it is filled from the scan points of the last 7
-- days, so it is not empty on day one.
--   "Its usual price" here = a running average that follows the price about 2 days behind (kept in the summary), so a
--   price that climbs over the weeks does not make the late days look dear: only the ups and downs within the week count.
--   Saved: item.pw = "e,t,b,v;cell;cell;..." (base 36): e = the day the weights start from, t = the last observation
--   counted (minutes), b = the running average price (x10), v = the day the item was last looked at; then 42 cells
--   (Sunday 0-4h, Sunday 4-8h, ... Saturday 20-24h), each "w,r,q[,p]" or empty: w = weight of the observations (x100),
--   r = price against the usual price (x1000), q = how many were listed (x10), p = weight of those with a price (x100,
--   only when it differs from w: sold-out moments have no price). Weights grow 2x every 21 days instead of the old ones
--   shrinking, so an observation only ever changes its own cell (the weights are made small again every 84 days).
--   Kept for items you track and items you looked at in the last 60 days (Overview or Patterns page); the others lose it.
--   Recording: X.Record (Data.lua) is wrapped when this file loads (below). Browse results (X.Observe: only a lowest
--   price, with an older market value) are not counted; full scans and searches of one item are. Observations closer
--   than 20 minutes to the last one counted are left out (a scan and a search right after it count once).
--
--   X.PatternGrid(key) -> {cells = {[weekday 0-6, 0 = Sunday] = {[block 0-5] = cell}}, filled (cells seen), priced
--     (cells with a price), n (observations, older ones counting less), enough (true: enough to go by), usual,
--     cheap, dear, scarce, plenty (each {wd, b, cell} or nil)};
--     cell = {n (observations), pn (with a price), r (price against usual, 1 = usual), q (average listed),
--     pct (% over the average of the cells; minus = cheaper), price (copper: usual price x that), qpct (% more listed
--     than the average of the cells; minus = scarcer)}
--   X.PatternTime(wd, b, short) -> "Tuesday 04:00 - 08:00" / "Tue 4-8"; X.PATTERN_BLOCKS = 6; X.PatternCell(t) -> wd, b
--   X.PatternsKeep(key, looked) -> the summary (made from the scan points the first time), nil when the item has none
--
-- [[ how jumpy ]] X.Jumpy(key) -> {days = {{t, value}, ...} (daily market value, last 30 days, oldest first), moves (how
--   many day-to-day moves), move (their average size, %), word ("Steady" / "Moves a bit" / "Jumpy" / "Wild" or nil),
--   low, high (the 30-day low and high), now (market value now), pct (0-100: share of the days that were cheaper than
--   now), place (plain words: "cheapest 10% of the month")}
--
-- [[ market size ]] X.MarketSize(key) -> {perDay (units sold a day, estimate), how ("scans": two full scans compared,
--   Speed.lua; "drops": the listed number going down from scan to scan), price (its usual price), gold (copper a
--   day), daily = {{t, units, gold}, ...} (per day, last 30 days)}. An ESTIMATE from listings disappearing: bought or
--   cancelled by the seller (the game does not tell the two apart).
local ADDON, X = ...

local DAY = 86400
local BLOCKS = 6                 -- times of the day
local BLOCK_HOURS = math.floor(24 / BLOCKS) -- 4 hours each
local NCELLS = 7 * BLOCKS
local HALF = 21                  -- days: an observation counts half after this long
local RESCALE = 4 * HALF         -- days: then the weights are made small again
local BASE_TAU = 2 * DAY         -- the running usual price follows the price about this far behind
local GAP = 20 * 60              -- observations closer than this to the last one counted are left out
local FORGET = 60                -- days: an item not tracked and not looked at loses its grid after this long
local SURE = 1.5                 -- a cell needs this many observations to be named the cheapest / dearest time
local ENOUGH_CELLS, ENOUGH_N = 10, 14 -- the grid is "enough to go by" with this many cells priced and observations
local PW, PR, PQ, PB = 100, 1000, 10, 10 -- saved x100 (weights), x1000 (ratios), x10 (listed), x10 (usual price)

X.PATTERN_BLOCKS = BLOCKS
X.PATTERN_HALF = HALF
X.Default("patternsMode", "price") -- the Patterns page's grid: "price" or "supply"

local b36, n36 = X.b36, X.n36

-- [[ the grid summary: reading and writing it.pw ]]
local function cellOf(p)
	if not p or p == "" then return nil end
	local w, r, q, pw = p:match("^([^,]*),([^,]*),([^,]*),?([^,]*)$")
	w = n36(w)
	if not w then return nil end
	local c = {w = w / PW, q = (n36(q) or 0) / PQ}
	r = n36(r)
	if r then c.r = r / PR end
	pw = n36(pw)
	if pw then c.p = pw / PW elseif c.r then c.p = c.w else c.p = 0 end
	return c
end
local function cellText(c)
	if not c then return "" end
	local w = X.Round(c.w * PW)
	if w <= 0 then return "" end
	local p = c.r and X.Round(c.p * PW) or 0
	local s = b36(w) .. "," .. (c.r and b36(c.r * PR) or "") .. "," .. b36(c.q * PQ)
	if p ~= w then s = s .. "," .. b36(p) end
	return s
end

local cache = setmetatable({}, {__mode = "k"}) -- [item] = {s = the text it was read from, agg = the summary}

local function blank()
	local agg = {parts = {}}
	for i = 1, NCELLS do agg.parts[i] = "" end
	return agg
end
local function decode(s)
	if type(s) ~= "string" or s == "" then return nil end
	local parts = {}
	for p in (s .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = p end
	if #parts ~= NCELLS + 1 then return nil end
	local e, t, b, v = parts[1]:match("^([^,]*),([^,]*),([^,]*),([^,]*)$")
	if not e then return nil end
	local agg = {e = n36(e), t = n36(t) and n36(t) * 60, b = n36(b) and n36(b) / PB, v = n36(v), parts = {}}
	for i = 1, NCELLS do agg.parts[i] = parts[i + 1] end
	return agg
end
local function encode(agg)
	return b36(agg.e) .. "," .. b36(agg.t and math.floor(agg.t / 60)) .. "," .. b36(agg.b and agg.b * PB) .. "," .. b36(agg.v) ..
		";" .. table.concat(agg.parts, ";")
end
local function loadAgg(it)
	local c = cache[it]
	if c and c.s == it.pw then return c.agg end
	local agg = decode(it.pw)
	cache[it] = {s = it.pw, agg = agg}
	return agg
end
local function save(it, agg)
	it.pw = encode(agg)
	cache[it] = {s = it.pw, agg = agg}
end

-- weekday (0 = Sunday) and time-of-day block (0-5) of a server time, on the realm's clock (Graph.lua)
function X.PatternCell(t)
	local wd, hr = X.ServerWeekday(t)
	return wd, math.floor(hr / BLOCK_HOURS)
end

-- one observation into the summary: t (seconds), v (price of one, nil when none listed), q (how many listed).
-- Returns true when it was counted.
local function add(agg, t, v, q)
	if agg.t and t < agg.t + GAP then return false end
	local days = t / DAY
	if not agg.e then agg.e = math.floor(days) end
	-- the weights grow 2x every HALF days; now and then they are made small again (tiny old cells go)
	if days - agg.e > RESCALE then
		local ne = math.floor(days)
		local f = 2 ^ (-(ne - agg.e) / HALF)
		for i = 1, NCELLS do
			local c = cellOf(agg.parts[i])
			if c then
				c.w, c.p = c.w * f, c.p * f
				agg.parts[i] = cellText(c)
			end
		end
		agg.e = ne
	end
	local w = 2 ^ ((days - agg.e) / HALF)
	-- the price against the running usual price (before this observation moves it)
	local ratio
	if v and v > 0 then
		local base = agg.b
		if not base or base <= 0 or not agg.t or t - agg.t > 7 * DAY then
			ratio, agg.b = 1, v
		else
			ratio = math.max(0.25, math.min(4, v / base))
			agg.b = base + (v - base) * (1 - math.exp(-(t - agg.t) / BASE_TAU))
		end
	end
	local wd, b = X.PatternCell(t)
	local i = wd * BLOCKS + b + 1
	local c = cellOf(agg.parts[i]) or {w = 0, q = 0, p = 0}
	local nw = c.w + w
	c.q = (c.q * c.w + (q or 0) * w) / nw
	if ratio then
		local np = c.p + w
		c.r = ((c.r or 0) * c.p + ratio * w) / np
		c.p = np
	end
	c.w = nw
	agg.parts[i] = cellText(c)
	agg.t = t
	return true
end
X.PatternAdd = add -- (tests)

-- a new summary from the scan points kept (the last 7 days); nil when there are none
local function build(it)
	local agg = blank()
	local any = false
	for _, p in ipairs(X.UnpackPoints(it.h)) do
		if p[1] then
			local v = p[3] or p[2]
			if ((v and v > 0) or p[4]) and add(agg, p[1] * 60, v, p[4]) then any = true end
		end
	end
	return any and agg or nil
end

function X.PatternsKeep(key, looked)
	local it = key and X.Items()[tostring(key)]
	if not it then return nil end
	local agg = loadAgg(it)
	local changed = false
	if not agg then
		agg = build(it)
		if not agg then return nil end
		changed = true
	end
	if looked and agg.v ~= X.Day() then
		agg.v = X.Day()
		changed = true
	end
	if changed then save(it, agg) end
	return agg
end

-- [[ recording ]] X.Record is wrapped: after the price is saved, the grid of a tracked item (or one that has a grid)
-- gets the observation too. Errors here never stop the recording itself.
local observing = false
local function afterRecord(it, key, t, min, mkt, qty)
	if not (it and it.cur and it.cur.t == t) or it.ox then return end -- older, or a crazy price left out
	local watched = X.db and X.db.watch and X.db.watch[key] ~= nil
	if not (it.pw or watched) then return end
	local agg = loadAgg(it)
	if not agg then
		X.PatternsKeep(key) -- made from the scan points, this one included
		return
	end
	if not watched and agg.v and agg.v < X.Day(t) - FORGET then
		it.pw = nil -- not tracked and not looked at for a long time
		cache[it] = nil
		return
	end
	if add(agg, t, mkt or min, qty) then save(it, agg) end
end
local record = X.Record
function X.Record(key, t, min, mkt, qty, auc, name, quality)
	local it = record(key, t, min, mkt, qty, auc, name, quality)
	if not observing and it and (it.pw or (X.db and X.db.watch and X.db.watch[key] ~= nil)) then
		local ok, err = pcall(afterRecord, it, key, t, min, mkt, qty)
		if not ok and X.OnError then X.OnError(err) end
	end
	return it
end
-- browse results (a lowest price only, with the older market value) are not counted
local observe = X.Observe
if observe then
	function X.Observe(...)
		observing = true
		local ok, err = pcall(observe, ...)
		observing = false
		if not ok then error(err, 0) end
	end
end

-- [[ reading the grid ]]
local DAYS = {[0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
function X.PatternTime(wd, b, short)
	local h1, h2 = b * BLOCK_HOURS, (b + 1) * BLOCK_HOURS
	if short then return DAYS[wd]:sub(1, 3) .. " " .. h1 .. "-" .. h2 end
	return DAYS[wd] .. " " .. string.format("%02d:00 - %02d:00", h1, h2 % 24 == 0 and 24 or h2)
end

function X.PatternGrid(key)
	key = key and tostring(key)
	local out = {cells = {}, filled = 0, priced = 0, n = 0}
	for wd = 0, 6 do out.cells[wd] = {} end
	local it = key and X.Items()[key]
	local agg = it and X.PatternsKeep(key, true)
	if not agg or not agg.e then return out end
	local now = math.max(X.Now(), agg.t or 0)
	local wNow = 2 ^ ((now / DAY - agg.e) / HALF)
	local sumR, nR, sumQ, nQ = 0, 0, 0, 0
	for wd = 0, 6 do
		for b = 0, BLOCKS - 1 do
			local c = cellOf(agg.parts[wd * BLOCKS + b + 1])
			if c and c.w > 0 then
				local cell = {n = c.w / wNow, pn = c.p / wNow, r = c.r, q = c.q}
				out.cells[wd][b] = cell
				out.filled, out.n = out.filled + 1, out.n + cell.n
				sumQ, nQ = sumQ + c.q, nQ + 1
				if c.r then
					out.priced = out.priced + 1
					sumR, nR = sumR + c.r, nR + 1
				end
			end
		end
	end
	local meanR = nR > 0 and sumR / nR or nil
	local meanQ = nQ > 0 and sumQ / nQ or nil
	local usual = X.Usual and X.Usual(key)
	if not usual and it.cur then usual = it.cur.mkt or it.cur.min end
	out.usual, out.meanQ = usual, meanQ
	for wd = 0, 6 do
		for b = 0, BLOCKS - 1 do
			local cell = out.cells[wd][b]
			if cell then
				if cell.r and meanR and meanR > 0 then
					cell.pct = (cell.r / meanR - 1) * 100
					if usual then cell.price = usual * cell.r / meanR end
				end
				if meanQ and meanQ > 0 then cell.qpct = (cell.q / meanQ - 1) * 100 end
			end
		end
	end
	-- the cheapest / dearest / scarcest / most plentiful time: among the cells seen often enough, else among all
	local function pick(field, want, better)
		for _, need in ipairs({SURE, 0}) do
			local best
			for wd = 0, 6 do
				for b = 0, BLOCKS - 1 do
					local cell = out.cells[wd][b]
					local v = cell and cell[field]
					if v and cell[want] >= need and (not best or better(v, best.cell[field])) then best = {wd = wd, b = b, cell = cell} end
				end
			end
			if best then return best end
		end
		return nil
	end
	local lower = function(a, b) return a < b end
	local higher = function(a, b) return a > b end
	out.cheap, out.dear = pick("pct", "pn", lower), pick("pct", "pn", higher)
	out.scarce, out.plenty = pick("qpct", "n", lower), pick("qpct", "n", higher)
	out.enough = out.priced >= ENOUGH_CELLS and out.n >= ENOUGH_N
	return out
end

-- [[ how jumpy ]]
local JUMPY = {{3, "Steady"}, {8, "Moves a bit"}, {20, "Jumpy"}, {math.huge, "Wild"}}
X.JUMPY_WORDS = JUMPY
local MIN_MOVES = 5
function X.JumpyWord(move)
	if not move then return nil end
	for _, e in ipairs(JUMPY) do if move < e[1] then return e[2] end end
	return JUMPY[#JUMPY][2]
end
-- plain words for where a price sits among the month's days (pct = share of the days that were cheaper)
function X.PlaceText(pct, now, low, high)
	if not (pct and now) then return nil end
	if low and now < low then return "cheaper than any day this month" end
	if high and now > high then return "dearer than any day this month" end
	if pct <= 10 then return "cheapest 10% of the month" end
	if pct <= 25 then return "cheaper than most days this month" end
	if pct < 75 then return "a normal price for the month" end
	if pct < 90 then return "dearer than most days this month" end
	return "dearest 10% of the month"
end

function X.Jumpy(key)
	key = key and tostring(key)
	local it = key and X.Items()[key]
	local out = {days = {}, moves = 0}
	if not it then return out end
	local today = X.Day()
	local pts, vals = {}, {}
	for _, p in ipairs(X.UnpackPoints(it.d)) do
		local v = p[3] or p[2]
		if p[1] and p[1] > today - 30 and v and v > 0 then
			pts[#pts + 1] = {p[1], v}
			vals[#vals + 1] = v
		end
	end
	local typical = X.Median(vals)
	local days = {}
	for _, p in ipairs(pts) do
		if not X.CrazyPrice(p[2], typical) then days[#days + 1] = p end
	end
	-- day-to-day moves (days up to 2 apart count as next to each other)
	local sum, n = 0, 0
	for i = 2, #days do
		local a, b = days[i - 1], days[i]
		if b[1] - a[1] <= 2 then
			sum, n = sum + math.abs(b[2] / a[2] - 1) * 100, n + 1
		end
	end
	out.moves = n
	if n >= MIN_MOVES then
		out.move = sum / n
		out.word = X.JumpyWord(out.move)
	end
	for _, p in ipairs(days) do
		out.days[#out.days + 1] = {p[1] * DAY + 43200, p[2]}
		if not out.low or p[2] < out.low then out.low = p[2] end
		if not out.high or p[2] > out.high then out.high = p[2] end
	end
	local cur = it.cur
	if cur and (cur.qty or 0) > 0 then out.now = cur.mkt or cur.min end
	if out.now and #days >= MIN_MOVES then
		local below, same = 0, 0
		for _, p in ipairs(days) do
			if p[2] < out.now then below = below + 1 elseif p[2] == out.now then same = same + 1 end
		end
		out.pct = (below + same / 2) / #days * 100
		out.place = X.PlaceText(out.pct, out.now, out.low, out.high)
	end
	return out
end

-- [[ market size ]]
local MAX_STEP = 12 * 3600 -- scans further apart than this are not compared for drops
local MIN_COVER = 6 * 3600 -- drops: at least this much time between scans compared
local MIN_WATCH = 60       -- Speed.lua: at least this many minutes watched on a day

-- the listed number going down from one scan to the next: units gone and seconds compared, per day ([day] = {u, s})
-- and in all; pts = {{t, min, mkt, qty}, ...} oldest first
local function drops(pts)
	local byDay, units, secs = {}, 0, 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local gap = b[1] - a[1]
		if a[4] and b[4] and gap > 0 and gap <= MAX_STEP then
			local gone = math.max(0, a[4] - b[4])
			local d = X.Day(b[1])
			local e = byDay[d]
			if not e then e = {u = 0, s = 0} byDay[d] = e end
			e.u, e.s = e.u + gone, e.s + gap
			units, secs = units + gone, secs + gap
		end
	end
	return byDay, units, secs
end
X.PatternDrops = drops -- (tests)

-- Speed.lua's saved numbers per day: [day] = {units seen sold, minutes watched} (read only)
local function speedDays(key)
	local out = {}
	local r = X.Realm()
	local s = r and r.speed and r.speed[key]
	if type(s) ~= "string" then return out end
	for p in s:gmatch("[^;]+") do
		local d, u, m = p:match("^([^,]*),([^,]*),([^,]*)$")
		d = n36(d)
		if d then out[d] = {n36(u) or 0, n36(m) or 0} end
	end
	return out
end

function X.MarketSize(key)
	key = key and tostring(key)
	local it = key and X.Items()[key]
	local out = {daily = {}}
	if not it then return out end
	local scans = {}
	for _, p in ipairs(X.UnpackPoints(it.h)) do
		if p[1] then scans[#scans + 1] = {p[1] * 60, p[2], p[3], p[4]} end
	end
	local byDay, units, secs = drops(scans)
	if secs >= MIN_COVER then out.dropsPerDay = units / secs * DAY end
	local rate = X.SaleRate and X.SaleRate(key)
	if rate then
		out.perDay, out.how = rate, "scans"
	elseif out.dropsPerDay then
		out.perDay, out.how = out.dropsPerDay, "drops"
	end
	local price = X.Usual and X.Usual(key)
	if not price and it.cur then price = it.cur.mkt or it.cur.min end
	out.price = price
	if out.perDay and price then out.gold = out.perDay * price end
	-- per day: Speed.lua's numbers where it watched long enough, else the drops of that day
	local dayPrice = {}
	for _, p in ipairs(X.UnpackPoints(it.d)) do
		local v = p[3] or p[2]
		if p[1] and v and v > 0 then dayPrice[p[1]] = v end
	end
	local sp = speedDays(key)
	local today = X.Day()
	for d = today - 29, today do
		local u
		local s = sp[d]
		if s and s[2] >= MIN_WATCH then
			u = s[1] / s[2] * 1440
		else
			local e = byDay[d]
			if e and e.s >= MIN_COVER then u = e.u / e.s * DAY end
		end
		if u then
			local v = dayPrice[d] or price
			out.daily[#out.daily + 1] = {d * DAY + 43200, u, v and u * v or nil}
		end
	end
	return out
end
