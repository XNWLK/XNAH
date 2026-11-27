-- Small 7-day price lines ("sparklines"): one tiny line per row of a list, so you can see at a glance which way a price
-- went this week. Used by the tracked list of the Items view (UIItem.lua).
-- X.Spark(key) -> the line's numbers, or false when there are fewer than 2 days with a price in the last 7 days:
--   {pts = {{x 0..1, y 0..1}, ...} (one point per day with a price, oldest first), change (% from the first day to the
--   last), first, last, lo, hi (copper), days (days with a price), color = {r, g, b}}
-- Each day's point is the average of that day's prices (market value, else the lowest price), from X.History (the
-- crazy prices left out). Colour by direction, the same as everywhere in XNAH: green = the price rose 3% or more, red =
-- it fell 3% or more, grey = about flat.
-- Kept per item until that item gets new prices (its history changes) or the hour changes; never saved. Only the rows
-- on screen ask for their line, so only those are worked out, and X.Spark(key, true) works out at most a few
-- milliseconds of lines a frame (the rest the next frames: X.SparkBusy / X.SparkAgain).
-- K.Sparkline(parent, w, h) -> a small frame; spark:SetData(X.Spark(key)) draws the line of an item (false: empty).
-- It is made of at most 6 line pieces and a dot at the last day, made once and reused (rows are reused while scrolling).
local ADDON, X = ...
local K = X.K

local DAYS = 7
local DAY = 86400
X.SPARK_UP = {0.29, 0.87, 0.5}     -- rising (as X.Arrow's "+")
X.SPARK_DOWN = {0.97, 0.44, 0.44}  -- falling (as X.Arrow's "-")
X.SPARK_FLAT = {0.7, 0.7, 0.7}
X.SPARK_MOVE = 3                   -- % change from which a line counts as rising or falling

-- the line of each item record (weak: an item record that is gone takes its line with it)
local cache = setmetatable({}, {__mode = "k"})

X.sparkWorked = 0 -- how many lines were worked out (tests)
local function work(key, now)
	X.sparkWorked = X.sparkWorked + 1
	local from = now - DAYS * DAY
	local sums, cnt = {}, {}
	for _, p in ipairs(X.History(key, from)) do
		local v = p[3] or p[2]
		if v and v > 0 then
			local d = math.max(1, math.min(DAYS, math.floor((p[1] - from) / DAY) + 1))
			sums[d], cnt[d] = (sums[d] or 0) + v, (cnt[d] or 0) + 1
		end
	end
	local vals = {}
	for d = 1, DAYS do
		if cnt[d] then vals[#vals + 1] = {d, sums[d] / cnt[d]} end
	end
	if #vals < 2 then return false end
	local lo, hi = math.huge, 0
	for _, v in ipairs(vals) do lo, hi = math.min(lo, v[2]), math.max(hi, v[2]) end
	local flat = hi - lo < hi * 0.01 -- (moves under 1% are drawn as a flat line in the middle)
	local pts = {}
	for i, v in ipairs(vals) do
		pts[i] = {(v[1] - 1) / (DAYS - 1), flat and 0.5 or (v[2] - lo) / (hi - lo)}
	end
	local first, last = vals[1][2], vals[#vals][2]
	local change = (last - first) / first * 100
	local color = change >= X.SPARK_MOVE and X.SPARK_UP or (change <= -X.SPARK_MOVE and X.SPARK_DOWN or X.SPARK_FLAT)
	return {pts = pts, change = change, first = first, last = last, lo = lo, hi = hi, days = #vals, color = color}
end

-- X.Spark(key, wait): wait = true (lists on screen) keeps the work of one frame under BUDGET_MS milliseconds: once that
-- is used up, a line not worked out yet comes back as nil ("next frame"; X.SparkBusy() then says so) - the list asks
-- again a frame later (X.SparkAgain). Without wait the line is always worked out at once.
local BUDGET_MS = 6
local function clock() local f = debugprofilestop return f and f() or 0 end
local frameT, spent, busyT -- the frame (GetTime) of the time spent, the milliseconds spent in it, the frame a line waited
function X.Spark(key, wait)
	if not key then return false end
	local it = X.Items()[key]
	if not it then return false end
	local now = X.Now()
	local hour = math.floor(now / 3600)
	local cur = it.cur
	local curT = cur and cur.t or 0
	local e = cache[it]
	-- still right: the same history strings, the same price now, the same hour
	if e and e.h == it.h and e.d == it.d and e.curT == curT and e.hour == hour then return e.c end
	local t0
	if wait then
		local f = GetTime()
		if f ~= frameT then frameT, spent = f, 0 end
		if spent >= BUDGET_MS then
			busyT = f
			return nil
		end
		t0 = clock()
	end
	local c = work(key, now)
	if wait then spent = spent + (clock() - t0) end
	cache[it] = {h = it.h, d = it.d, curT = curT, hour = hour, c = c}
	return c
end
-- did a line have to wait for the next frame (in this frame)?
function X.SparkBusy()
	return busyT ~= nil and busyT == GetTime()
end
-- runs fn next frame (once per owner, however often asked in this frame): a list draws its waiting lines then
local again, againOn = {}, false
function X.SparkAgain(owner, fn)
	again[owner] = fn
	if againOn then return end
	againOn = true
	X.After(0, function()
		againOn = false
		frameT, busyT = nil, nil -- (a new frame: its own time to spend)
		local list = again
		again = {}
		for _, f in pairs(list) do
			local ok, err = pcall(f)
			if not ok then X.OnError(err) end
		end
	end)
end
-- forgets every line (tests; a realm change does this by itself: other item records)
function X.SparkReset()
	cache = setmetatable({}, {__mode = "k"})
end

-- the change of the line as text: "+12%" green, "-4%" red, "+1%" grey; nil without a line
function X.SparkText(c)
	if not c then return nil end
	local col = c.color == X.SPARK_UP and "|cff4ade80" or (c.color == X.SPARK_DOWN and "|cfff87171" or "|cffaaaaaa")
	return col .. string.format("%+.0f%%", c.change) .. "|r"
end

-- [[ the widget ]]
function K.Sparkline(parent, w, h)
	local s = CreateFrame("Frame", nil, parent)
	s:SetSize(w, h)
	s.w, s.h = w, h
	s.lines = {}
	s.dot = s:CreateTexture(nil, "OVERLAY")
	s.dot:SetSize(3, 3)
	s.dot:Hide()
	-- draws c (from X.Spark) or nothing
	function s:SetData(c)
		self.data = c or nil
		local n = 0
		if c then
			local col = c.color
			for i = 2, #c.pts do
				n = n + 1
				local l = self.lines[n]
				if not l then
					l = self:CreateLine(nil, "ARTWORK")
					l:SetThickness(1.5)
					self.lines[n] = l
				end
				local a, b = c.pts[i - 1], c.pts[i]
				l:SetColorTexture(col[1], col[2], col[3], 0.95)
				l:SetStartPoint("BOTTOMLEFT", self, a[1] * self.w, a[2] * self.h)
				l:SetEndPoint("BOTTOMLEFT", self, b[1] * self.w, b[2] * self.h)
				l:Show()
			end
			local p = c.pts[#c.pts]
			self.dot:SetColorTexture(col[1], col[2], col[3], 1)
			self.dot:ClearAllPoints()
			self.dot:SetPoint("CENTER", self, "BOTTOMLEFT", p[1] * self.w, p[2] * self.h)
			self.dot:Show()
		else
			self.dot:Hide()
		end
		for i = n + 1, #self.lines do self.lines[i]:Hide() end
		self.drawn = n
	end
	return s
end
