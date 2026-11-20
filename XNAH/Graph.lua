-- A price graph: lines over time (market value, lowest price ...), faint bars for how many were listed, money on the
-- left, dates below, and a small box with the numbers where the mouse is.
--   local g = X.K.Graph(parent, w, h)
--   g:SetSeries({{points = {{t, value}, ...}, color = {r, g, b}, width = 2, label = "Market value", right = true}, ...},
--     {bars = {{t, value}, ...}, barsLabel = "Listed", empty = "text when there is nothing", format = fn(value),
--      marks = {{t = time, v = value, color = {r, g, b}, text = "line for the mouse-over box"}, ...},
--      levels = {{v = value, color = {r, g, b}, label = "Fair to buy"}, ...}})
-- Times are server seconds, oldest first. A nil value breaks a line (sold out at that time).
-- right = true (optional): the line gets its own scale, its numbers on the right side inside the graph (for a second
-- item whose price is far from the first one's). marks (optional): single dots (your own sales and buys), drawn over
-- the lines; the mouse-over box lists the dots near the mouse. levels (optional): thin flat lines right across the
-- graph with a small name on the left (the fair prices to buy and to sell), also listed in the mouse-over box.
-- Everything is drawn with pooled lines and textures: a new SetSeries reuses what the last one made.
--
-- Also here: X.BestTimes(key) (price by weekday and by hour of the day) and K.TimeBars (its little bar charts).
local ADDON, X = ...
local K = X.K

local MAXPTS = 300 -- at most this many points per line (more are averaged together)
local LEFT, RIGHT, TOP, BOTTOM = 66, 8, 8, 18 -- room for the money labels (left) and the dates (below)
local GRIDS = 6
local MAXNEAR = 4 -- the mouse-over box lists at most this many dots

-- points sorted by time (a copy only when they are not)
local function sorted(points)
	for i = 2, #points do
		if points[i][1] < points[i - 1][1] then
			local copy = {}
			for j = 1, #points do copy[j] = points[j] end
			table.sort(copy, function(a, b) return a[1] < b[1] end)
			return copy
		end
	end
	return points
end

-- at most `max` points: the time range is cut into `max` slices and the points of each slice averaged (time and value);
-- a slice whose points have no value stays a gap
local function thin(points, max)
	local n = #points
	if n <= max then return points end
	local t0, t1 = points[1][1], points[n][1]
	if t1 <= t0 then return {points[n]} end
	local size = (t1 - t0) / max
	local out = {}
	local bucket, st, sv, ct, cv = nil, 0, 0, 0, 0
	for i = 1, n do
		local p = points[i]
		local b = math.min(max - 1, math.floor((p[1] - t0) / size))
		if b ~= bucket then
			if ct > 0 then out[#out + 1] = {st / ct, cv > 0 and sv / cv or nil} end
			bucket, st, sv, ct, cv = b, 0, 0, 0, 0
		end
		st, ct = st + p[1], ct + 1
		if p[2] ~= nil then sv, cv = sv + p[2], cv + 1 end
	end
	if ct > 0 then out[#out + 1] = {st / ct, cv > 0 and sv / cv or nil} end
	return out
end

-- a round step (1, 2, 2.5 or 5 times a power of ten) that puts about `want` labels between lo and hi
local function niceStep(lo, hi, want)
	local raw = (hi - lo) / want
	if raw <= 1 then return 1 end
	local mag = 10 ^ math.floor(math.log(raw) / math.log(10) + 1e-9)
	local best, bestDiff
	for _, m in ipairs({0.5, 1, 2, 2.5, 5, 10}) do
		local step = math.max(1, m * mag)
		local n = math.floor(hi / step) - math.ceil(lo / step) + 1
		local diff = math.abs(n - want)
		if n >= 2 and (not bestDiff or diff < bestDiff) then best, bestDiff = step, diff end
	end
	return best or math.max(1, raw)
end

local function dayText(t)
	return (date("%b %d", t):gsub(" 0", " "))
end

local function hex(c)
	return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end
K.ColorCode = hex

-- the value range of a scale with a little room above and below
local function padded(lo, hi)
	local pad = (hi - lo) * 0.08
	if pad <= 0 then pad = math.max(math.abs(hi) * 0.1, 1) end
	local vlo, vhi = lo - pad, hi + pad
	if lo >= 0 and vlo < 0 then vlo = 0 end
	return vlo, vhi
end

function K.Graph(parent, w, h)
	local g = CreateFrame("Frame", nil, parent)
	g:SetSize(w, h)
	local pw, ph = w - LEFT - RIGHT, h - TOP - BOTTOM
	local plot = CreateFrame("Frame", nil, g)
	plot:SetPoint("TOPLEFT", LEFT, -TOP)
	plot:SetSize(pw, ph)
	g.plot = plot
	local bg = plot:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.3)

	-- grid lines with their money labels, date labels, the labels of a second scale (right, inside the graph)
	local grid, ylab, xlab, rlab = {}, {}, {}, {}
	for i = 1, GRIDS do
		local t = plot:CreateTexture(nil, "BORDER")
		t:SetColorTexture(1, 1, 1, 0.07)
		t:SetHeight(1)
		t:Hide()
		grid[i] = t
		local fs = K.Label(g, "", "GameFontDisableSmall", "RIGHT")
		fs:SetWidth(LEFT - 6)
		fs:SetWordWrap(false)
		fs:Hide()
		ylab[i] = fs
		local rs = K.Label(plot, "", "GameFontDisableSmall", "RIGHT")
		rs:SetWidth(90)
		rs:SetWordWrap(false)
		rs:Hide()
		rlab[i] = rs
	end
	for i = 1, 5 do
		local fs = K.Label(g, "", "GameFontDisableSmall", "CENTER")
		fs:SetWidth(90)
		fs:SetWordWrap(false)
		fs:Hide()
		xlab[i] = fs
	end
	local levlab = {} -- names of the flat lines (made when needed)
	g.empty = K.Label(plot, "", "GameFontDisableSmall", "CENTER")
	g.empty:SetPoint("CENTER")
	g.empty:SetWidth(pw - 20)

	-- pools: lines, dots (single points), bars, trade dots (a dark edge and a coloured middle)
	local lines, nLines = {}, 0
	local dots, nDots = {}, 0
	local bars, nBars = {}, 0
	local spots, nSpots = {}, 0
	local function line(color, width)
		nLines = nLines + 1
		local l = lines[nLines]
		if not l then
			l = plot:CreateLine(nil, "ARTWORK")
			lines[nLines] = l
		end
		l:SetThickness(width)
		l:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		l:Show()
		return l
	end
	local function dot(color, size, x, y)
		nDots = nDots + 1
		local d = dots[nDots]
		if not d then
			d = plot:CreateTexture(nil, "OVERLAY")
			dots[nDots] = d
		end
		d:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		d:SetSize(size, size)
		d:ClearAllPoints()
		d:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
		d:Show()
		return d
	end
	local function bar(x, bw, bh)
		nBars = nBars + 1
		local b = bars[nBars]
		if not b then
			b = plot:CreateTexture(nil, "BORDER", nil, 1)
			b:SetColorTexture(0.45, 0.6, 1, 0.22)
			bars[nBars] = b
		end
		b:SetSize(bw, bh)
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x - bw / 2, 0)
		b:Show()
	end
	local function spot(color, x, y)
		nSpots = nSpots + 1
		local s = spots[nSpots]
		if not s then
			s = {edge = plot:CreateTexture(nil, "OVERLAY", nil, 3), fill = plot:CreateTexture(nil, "OVERLAY", nil, 4)}
			s.edge:SetColorTexture(0, 0, 0, 0.9)
			s.edge:SetSize(9, 9)
			s.fill:SetSize(7, 7)
			spots[nSpots] = s
		end
		s.fill:SetColorTexture(color[1], color[2], color[3], 1)
		for _, tex in ipairs({s.edge, s.fill}) do
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", plot, "BOTTOMLEFT", x, y)
			tex:Show()
		end
	end

	-- the mouse-over marker and box
	local marker = plot:CreateTexture(nil, "OVERLAY")
	marker:SetColorTexture(1, 1, 1, 0.35)
	marker:SetWidth(1)
	marker:SetPoint("TOP", plot, "TOPLEFT", 0, 0)
	marker:SetPoint("BOTTOM", plot, "BOTTOMLEFT", 0, 0)
	marker:Hide()
	local hoverDots = {}
	local tip = K.Panel(g, 150, 40, {0.03, 0.03, 0.05, 0.92})
	tip:SetFrameLevel(g:GetFrameLevel() + 10)
	tip.text = K.Label(tip, "", "GameFontHighlightSmall")
	tip.text:SetPoint("TOPLEFT", 6, -5)
	tip.text:SetJustifyV("TOP")
	tip:Hide()

	local data = {series = {}, marks = {}, trades = {}} -- what is drawn, for the mouse-over box
	local function hideHover()
		marker:Hide()
		tip:Hide()
		for _, d in ipairs(hoverDots) do d:Hide() end
		g.hoverIdx, g.lastCx = nil, nil
	end

	-- the value of series `s` at time t: the point at t, else the nearest one
	local function valueAt(s, t)
		local best, bd
		for _, p in ipairs(s.pts) do
			local d = math.abs(p[1] - t)
			if not bd or d < bd then best, bd = p, d end
			if d == 0 then break end
		end
		return best and best[2]
	end

	local function showHover(idx)
		g.hoverIdx = idx
		local m = data.marks[idx]
		marker:ClearAllPoints()
		marker:SetPoint("TOP", plot, "TOPLEFT", m.x, 0)
		marker:SetPoint("BOTTOM", plot, "BOTTOMLEFT", m.x, 0)
		marker:Show()
		local fmt = data.format
		local text = "|cffffd100" .. (data.span < 2 * 86400 and date("%H:%M", m.t) .. "  " .. dayText(m.t) or
			dayText(m.t) .. "  " .. date("%H:%M", m.t)) .. "|r"
		for i, s in ipairs(data.series) do
			local v = valueAt(s, m.t)
			local c = s.color
			text = text .. "\n" .. hex(c) .. (s.label or "") .. "|r  " .. (v and fmt(v) or "|cff666666-|r")
			local d = hoverDots[i]
			if not d then
				d = plot:CreateTexture(nil, "OVERLAY", nil, 2)
				d:SetSize(6, 6)
				hoverDots[i] = d
			end
			if v then
				d:SetColorTexture(c[1], c[2], c[3], 1)
				d:ClearAllPoints()
				d:SetPoint("CENTER", plot, "BOTTOMLEFT", m.x, s.y(v))
				d:Show()
			else
				d:Hide()
			end
		end
		for i = #data.series + 1, #hoverDots do hoverDots[i]:Hide() end
		for _, lv in ipairs(data.levels or {}) do
			text = text .. "\n" .. hex(lv.color) .. (lv.label or "") .. "|r  " .. fmt(lv.v)
		end
		if data.bars then
			local v = valueAt(data.bars, m.t)
			text = text .. "\n|cff8aa4ff" .. (data.barsLabel or "Listed") .. "|r  " .. (v and X.Num(v) or "-")
		end
		-- dots (your trades) within a few pixels of the mouse
		local near = 0
		for _, tr in ipairs(data.trades) do
			if math.abs(tr.x - m.x) <= 4 then
				near = near + 1
				if near <= MAXNEAR then text = text .. "\n" .. hex(tr.color) .. "o|r " .. (tr.text or fmt(tr.v)) end
			end
		end
		if near > MAXNEAR then text = text .. "\n|cff999999and " .. (near - MAXNEAR) .. " more|r" end
		tip.text:SetText(text)
		local tw = math.max(80, (tip.text:GetStringWidth() or 100) + 12)
		local th = (tip.text:GetStringHeight() or 40) + 10
		tip:SetSize(tw, th)
		tip:ClearAllPoints()
		if m.x + tw + 12 > pw then
			tip:SetPoint("TOPRIGHT", plot, "TOPLEFT", m.x - 8, -4)
		else
			tip:SetPoint("TOPLEFT", plot, "TOPLEFT", m.x + 8, -4)
		end
		tip:Show()
	end

	-- follows the mouse only while it is over the graph (no work at all otherwise)
	local function follow(self)
		if #data.marks == 0 or not plot:IsMouseOver() then
			if self.hoverIdx then hideHover() end
			return
		end
		local left = plot:GetLeft()
		if not left then return end
		local cx = GetCursorPosition() / plot:GetEffectiveScale() - left
		if cx == self.lastCx then return end
		self.lastCx = cx
		local best, bd = nil, nil
		for i, m in ipairs(data.marks) do
			local d = math.abs(m.x - cx)
			if not bd or d < bd then best, bd = i, d end
		end
		if best and best ~= self.hoverIdx then showHover(best) end
	end
	plot:EnableMouse(true)
	plot:SetScript("OnEnter", function() g:SetScript("OnUpdate", follow) end)
	plot:SetScript("OnLeave", function()
		g:SetScript("OnUpdate", nil)
		hideHover()
	end)
	g:SetScript("OnHide", function()
		g:SetScript("OnUpdate", nil)
		hideHover()
	end)
	g.tip = tip
	g.GetInfo = function() return data end -- what is drawn (for the tests)

	-- the money labels of the left scale (with grid lines) or of the right one (inside the graph, in the line's colour)
	local function scaleLabels(vlo, vhi, yOf, right, color)
		local step = niceStep(vlo, vhi, 4)
		local v = math.ceil(vlo / step) * step
		local i = 0
		while v <= vhi and i < GRIDS do
			i = i + 1
			local y = yOf(v)
			if right then
				rlab[i]:SetText(hex(color) .. data.format(v) .. "|r")
				rlab[i]:ClearAllPoints()
				rlab[i]:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -3, y + 1)
				rlab[i]:Show()
			else
				grid[i]:ClearAllPoints()
				grid[i]:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
				grid[i]:SetWidth(pw)
				grid[i]:Show()
				ylab[i]:SetText(data.format(v))
				ylab[i]:ClearAllPoints()
				ylab[i]:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, y)
				ylab[i]:Show()
			end
			v = v + step
		end
	end

	function g:SetSeries(series, opts)
		opts = opts or {}
		series = series or {}
		hideHover()
		for i = 1, nLines do lines[i]:Hide() end
		for i = 1, nDots do dots[i]:Hide() end
		for i = 1, nBars do bars[i]:Hide() end
		for i = 1, nSpots do spots[i].edge:Hide() spots[i].fill:Hide() end
		for i = 1, GRIDS do grid[i]:Hide() ylab[i]:Hide() rlab[i]:Hide() end
		for i = 1, 5 do xlab[i]:Hide() end
		for _, fs in ipairs(levlab) do fs:Hide() end
		nLines, nDots, nBars, nSpots = 0, 0, 0, 0
		data = {series = {}, marks = {}, trades = {}, format = opts.format or function(v) return X.Money(v, true) end,
			barsLabel = opts.barsLabel, span = 0}

		-- thin out, find the time and value ranges (lo / hi: left scale, rlo / rhi: right scale)
		local t0, t1, lo, hi, rlo, rhi
		local function time(t)
			if not t0 or t < t0 then t0 = t end
			if not t1 or t > t1 then t1 = t end
		end
		for _, s in ipairs(series) do
			local pts = thin(sorted(s.points or {}), MAXPTS)
			if #pts > 0 then
				local right = s.right and true or false
				data.series[#data.series + 1] = {pts = pts, color = s.color or {1, 1, 1}, width = s.width or 2, label = s.label, right = right}
				for _, p in ipairs(pts) do
					time(p[1])
					local v = p[2]
					if v ~= nil then
						if right then
							if not rlo or v < rlo then rlo = v end
							if not rhi or v > rhi then rhi = v end
						else
							if not lo or v < lo then lo = v end
							if not hi or v > hi then hi = v end
						end
					end
				end
			end
		end
		for _, m in ipairs(opts.marks or {}) do
			if m.t and m.v then
				time(m.t)
				if not lo or m.v < lo then lo = m.v end
				if not hi or m.v > hi then hi = m.v end
			end
		end
		-- only lines with their own scale: they take the left one
		if not lo and rlo then
			lo, hi, rlo, rhi = rlo, rhi, nil, nil
			for _, s in ipairs(data.series) do s.right = false end
		end
		-- flat lines: only next to something else, and they count for the scale
		data.levels = {}
		if lo then
			for _, lv in ipairs(opts.levels or {}) do
				if lv.v then
					data.levels[#data.levels + 1] = {v = lv.v, color = lv.color or {1, 1, 1}, label = lv.label}
					if lv.v < lo then lo = lv.v end
					if lv.v > hi then hi = lv.v end
				end
			end
		end
		local barPts = opts.bars and thin(sorted(opts.bars), MAXPTS) or {}
		local barMax = 0
		for _, p in ipairs(barPts) do
			if p[2] and p[2] > barMax then barMax = p[2] end
			time(p[1])
		end
		if barMax > 0 then data.bars = {pts = barPts} end
		if not lo then
			g.empty:SetText(opts.empty or "No price history yet - scan the auction house")
			g.empty:Show()
			return
		end
		g.empty:Hide()
		if t1 - t0 < 60 then t0, t1 = t0 - 1800, t1 + 1800 end -- one moment in time: an hour around it
		data.span = t1 - t0
		local vlo, vhi = padded(lo, hi)
		local function xOf(t) return (t - t0) / (t1 - t0) * pw end
		local function yOf(v) return (v - vlo) / (vhi - vlo) * ph end
		local yRight = yOf
		data.y = yOf
		scaleLabels(vlo, vhi, yOf, false)
		if rlo then
			local rvlo, rvhi = padded(rlo, rhi)
			yRight = function(v) return (v - rvlo) / (rvhi - rvlo) * ph end
			for _, s in ipairs(data.series) do
				if s.right then scaleLabels(rvlo, rvhi, yRight, true, s.color) break end
			end
		end
		for _, s in ipairs(data.series) do s.y = s.right and yRight or yOf end

		-- dates below: hours for less than two days, else days
		local n = pw >= 500 and 5 or (pw >= 300 and 4 or 3)
		for k = 1, n do
			local t = t0 + (t1 - t0) * (k - 1) / (n - 1)
			local fs = xlab[k]
			fs:SetText(data.span < 2 * 86400 and date("%H:%M", t) or dayText(t))
			fs:ClearAllPoints()
			if k == 1 then
				fs:SetJustifyH("LEFT")
				fs:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -3)
			elseif k == n then
				fs:SetJustifyH("RIGHT")
				fs:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -3)
			else
				fs:SetJustifyH("CENTER")
				fs:SetPoint("TOP", plot, "BOTTOMLEFT", xOf(t), -3)
			end
			fs:Show()
		end

		-- quantity bars (bottom quarter, their own scale)
		if data.bars then
			local bw = math.max(1, math.min(10, pw / math.max(1, #barPts) * 0.8))
			for _, p in ipairs(barPts) do
				if p[2] and p[2] > 0 then bar(xOf(p[1]), bw, math.max(1, p[2] / barMax * ph * 0.25)) end
			end
		end

		-- lines; a point with no neighbour gets a dot (a lone price between gaps)
		local seen = {}
		for _, s in ipairs(data.series) do
			local pts, y = s.pts, s.y
			for k = 1, #pts do
				local p = pts[k]
				local t = p[1]
				if not seen[t] then
					seen[t] = true
					data.marks[#data.marks + 1] = {t = t, x = xOf(t)}
				end
				if p[2] ~= nil then
					local x, yy = xOf(t), y(p[2])
					local nxt = pts[k + 1]
					if nxt and nxt[2] ~= nil then
						local l = line(s.color, s.width)
						l:SetStartPoint("BOTTOMLEFT", plot, x, yy)
						l:SetEndPoint("BOTTOMLEFT", plot, xOf(nxt[1]), y(nxt[2]))
					end
					local prev = pts[k - 1]
					if not (prev and prev[2] ~= nil) and not (nxt and nxt[2] ~= nil) then
						dot(s.color, s.width + 3, x, yy)
						if #pts == 1 then -- just one point: a short flat line through it
							local l = line(s.color, s.width)
							l:SetStartPoint("BOTTOMLEFT", plot, math.max(0, x - 8), yy)
							l:SetEndPoint("BOTTOMLEFT", plot, math.min(pw, x + 8), yy)
						end
					end
				end
			end
		end

		-- flat lines with their names (left, just above the line)
		for i, lv in ipairs(data.levels) do
			local c = lv.color
			local yy = yOf(lv.v)
			local l = line({c[1], c[2], c[3], 0.6}, 1)
			l:SetStartPoint("BOTTOMLEFT", plot, 0, yy)
			l:SetEndPoint("BOTTOMLEFT", plot, pw, yy)
			local fs = levlab[i]
			if not fs then
				fs = K.Label(plot, "", "GameFontDisableSmall", "LEFT")
				fs:SetWordWrap(false)
				levlab[i] = fs
			end
			fs:SetText(hex(c) .. (lv.label or "") .. "|r")
			fs:ClearAllPoints()
			fs:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 4, yy + 1)
			fs:Show()
		end

		-- your trades: a dot each at its price; the mouse can stop on them too
		for _, m in ipairs(opts.marks or {}) do
			if m.t and m.v then
				local x = xOf(m.t)
				local c = m.color or {1, 1, 1}
				spot(c, x, yOf(m.v))
				data.trades[#data.trades + 1] = {t = m.t, x = x, v = m.v, color = c, text = m.text}
				if not seen[m.t] then
					seen[m.t] = true
					data.marks[#data.marks + 1] = {t = m.t, x = x}
				end
			end
		end
		table.sort(data.marks, function(a, b) return a.t < b.t end)
	end

	return g
end

-- [[ best time to sell ]]
-- Price by weekday and by hour of the day, worked out from the price history (market value) and from your own sales.
-- Each day is compared with the days around it (3 before, 3 after) and each scan with the scans within 12 hours of it,
-- so a price that climbs or falls over the weeks does not make the late days look better: only the up and down within
-- a week (or a day) counts. Times are the realm's clock (server time).
local DAY = 86400
local DAY_SPAN = 56          -- weekdays: the last 8 weeks (older history is one point a week)
local SCAN_SPAN = 7 * DAY    -- hours: scan points are kept 7 days
local MIN_DAYS = 14          -- weekdays need prices on this many days ...
local MIN_WEEKDAYS = 6       -- ... covering this many different weekdays
local MIN_SCANS = 12         -- hours need this many scans ...
local MIN_SCAN_DAYS = 2      -- ... on this many different days ...
local MIN_HOURS = 6          -- ... at this many different hours
local MIN_SALES = 5          -- your sales: this many ...
local MIN_SALE_DAYS = 3      -- ... on this many different weekdays
X.DAY_NAMES = {[0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"}
X.BEST_MIN = {days = MIN_DAYS, weekdays = MIN_WEEKDAYS, scans = MIN_SCANS, scanDays = MIN_SCAN_DAYS, hours = MIN_HOURS,
	sales = MIN_SALES, saleDays = MIN_SALE_DAYS}

-- seconds to add to a server time to get the realm's clock (worked out once from the game's clock, to 15 minutes);
-- second value true when the game told its clock (else the computer's clock is used)
local zoneShift, zoneKnown
function X.ServerShift()
	if zoneShift then return zoneShift, zoneKnown end
	local now = X.Now()
	local u = date("!*t", now)
	local h, m
	if GetGameTime then h, m = X.Try(GetGameTime) end
	local known = type(h) == "number" and type(m) == "number"
	if not known then
		local l = date("*t", now)
		h, m = l.hour, l.min
	end
	local diff = (h * 60 + m) - (u.hour * 60 + u.min)
	if diff >= 720 then diff = diff - 1440 elseif diff < -720 then diff = diff + 1440 end
	zoneShift, zoneKnown = math.floor(diff / 15 + 0.5) * 15 * 60, known
	return zoneShift, zoneKnown
end
-- forget the clock difference (tests; a new day on a realm that changes its clock)
function X.ServerShiftReset() zoneShift, zoneKnown = nil, nil end

-- weekday (0 = Sunday) and hour (0-23) of a server time on the realm's clock
function X.ServerWeekday(t)
	local st = t + X.ServerShift()
	return (math.floor(st / DAY) + 4) % 7, math.floor((st % DAY) / 3600)
end

-- per slot: avg = the average of its ratios, pct = % over the average of all slots seen; returns slots seen, the best one
-- (highest pct among slots seen at least twice, else among those seen once)
local function finishSlots(slots, a, b)
	local sum, n = 0, 0
	for i = a, b do
		local s = slots[i]
		if s.n > 0 then
			s.avg = s.r / s.n
			sum, n = sum + s.avg, n + 1
		end
	end
	if n == 0 then return 0, nil end
	local mean = sum / n
	for i = a, b do
		local s = slots[i]
		if s.n > 0 then s.pct = (s.avg / mean - 1) * 100 end
	end
	local best
	for need = 2, 1, -1 do
		for i = a, b do
			local s = slots[i]
			if s.n >= need and (not best or s.pct > slots[best].pct) then best = i end
		end
		if best then break end
	end
	return n, best
end

-- X.GraphTrades(key, which) -> your sales ("sales", the default) or buys ("buys") of the item from the ledger, entries
-- as Ledger.lua keeps them {t, count, money (the whole sale or purchase), cut, ...}; by key, or by name when the item
-- was not known then
local function salesOf(key, which)
	local out = {}
	if not X.Ledger then return out end
	local L = X.Ledger()
	local name = X.ItemName(key)
	local lname = name and name:lower()
	for _, e in ipairs(L[which or "sales"] or {}) do
		if e.t and (e.money or 0) > 0 and (e.key == key or (not e.key and lname and e.name and e.name:lower() == lname)) then
			out[#out + 1] = e
		end
	end
	return out
end
X.GraphTrades = salesOf

local cache, cacheN = {}, 0
-- X.BestTimes(key) -> {
--   days  = {[0..6]  = {n (days seen), pct (% over the week's average) or nil, sales, units, each (your average price
--             of one) or nil, salePct (% over your average price) or nil}},  0 = Sunday
--   hours = {[0..23] = same, n = scans seen},
--   dayCount, weekdays, bestDay, dayEnough;  scanCount, scanDays, hourCount, bestHour, hourEnough;
--   sales, units, eachAvg, saleDays, saleBestDay (best price), saleMostDay (most units), saleEnough;
--   serverClock (true: the realm's clock; false: the computer's clock) }
function X.BestTimes(key)
	key = tostring(key)
	local it = X.Items()[key]
	local sales = salesOf(key)
	local now = X.Now()
	local shift, known = X.ServerShift()
	local stamp = tostring(it and it.cur and it.cur.t or 0) .. "/" .. #sales .. "/" .. math.floor(now / 3600) .. "/" .. shift ..
		(known and "" or "?")
	local hit = cache[key]
	if hit and hit.stamp == stamp then return hit.out end

	local out = {days = {}, hours = {}, serverClock = known}
	for d = 0, 6 do out.days[d] = {n = 0, r = 0, sales = 0, units = 0, money = 0} end
	for h = 0, 23 do out.hours[h] = {n = 0, r = 0, sales = 0, units = 0, money = 0} end

	-- market value per day (realm's days) and the scan points of the last 7 days
	local hist = X.History(key, now - DAY_SPAN * DAY)
	local byDay, order, scans = {}, {}, {}
	for _, p in ipairs(hist) do
		local v = p[3]
		if v and v > 0 then
			local st = p[1] + shift
			local d = math.floor(st / DAY)
			local e = byDay[d]
			if not e then
				e = {sum = 0, n = 0}
				byDay[d] = e
				order[#order + 1] = d
			end
			e.sum, e.n = e.sum + v, e.n + 1
			-- day points sit at noon (UTC); scan points are on whole minutes
			if p[1] % DAY ~= 43200 and p[1] >= now - SCAN_SPAN then scans[#scans + 1] = {p[1], v, st} end
		end
	end
	-- each day against the days around it
	local rated = 0
	for _, d in ipairs(order) do
		local e = byDay[d]
		local sum, n = 0, 0
		for k = d - 3, d + 3 do
			local f = byDay[k]
			if f then sum, n = sum + f.sum / f.n, n + 1 end
		end
		if n >= 4 and sum > 0 then
			local slot = out.days[(d + 4) % 7]
			slot.r, slot.n = slot.r + (e.sum / e.n) / (sum / n), slot.n + 1
			rated = rated + 1
		end
	end
	out.dayCount = rated
	out.weekdays, out.bestDay = finishSlots(out.days, 0, 6)
	out.dayEnough = rated >= MIN_DAYS and out.weekdays >= MIN_WEEKDAYS

	-- each scan against the scans within 12 hours of it
	local hrated, days = 0, {}
	local HALF = 12 * 3600
	for i, p in ipairs(scans) do
		local sum, n = 0, 0
		for k = i, 1, -1 do
			if p[1] - scans[k][1] > HALF then break end
			sum, n = sum + scans[k][2], n + 1
		end
		for k = i + 1, #scans do
			if scans[k][1] - p[1] > HALF then break end
			sum, n = sum + scans[k][2], n + 1
		end
		if n >= 3 then
			local slot = out.hours[math.floor((p[3] % DAY) / 3600)]
			slot.r, slot.n = slot.r + p[2] / (sum / n), slot.n + 1
			hrated = hrated + 1
			days[math.floor(p[3] / DAY)] = true
		end
	end
	local nd = 0
	for _ in pairs(days) do nd = nd + 1 end
	out.scanCount, out.scanDays = hrated, nd
	out.hourCount, out.bestHour = finishSlots(out.hours, 0, 23)
	out.hourEnough = hrated >= MIN_SCANS and nd >= MIN_SCAN_DAYS and out.hourCount >= MIN_HOURS

	-- your sales: units and average price of one per weekday and hour
	local units, money = 0, 0
	for _, e in ipairs(sales) do
		local c = math.max(1, e.count or 1)
		local st = e.t + shift
		for _, slot in ipairs({out.days[(math.floor(st / DAY) + 4) % 7], out.hours[math.floor((st % DAY) / 3600)]}) do
			slot.sales, slot.units, slot.money = slot.sales + 1, slot.units + c, slot.money + e.money
		end
		units, money = units + c, money + e.money
	end
	out.sales, out.units = #sales, units
	out.eachAvg = units > 0 and money / units or nil
	local saleDays = 0
	for _, list in ipairs({out.days, out.hours}) do
		for i = 0, #list do
			local s = list[i]
			if s.units > 0 then
				s.each = s.money / s.units
				s.salePct = out.eachAvg and (s.each / out.eachAvg - 1) * 100 or nil
				if list == out.days then saleDays = saleDays + 1 end
			end
		end
	end
	out.saleDays = saleDays
	for d = 0, 6 do
		local s = out.days[d]
		if s.units > 0 then
			if not out.saleBestDay or s.salePct > out.days[out.saleBestDay].salePct then out.saleBestDay = d end
			if not out.saleMostDay or s.units > out.days[out.saleMostDay].units then out.saleMostDay = d end
		end
	end
	out.saleEnough = #sales >= MIN_SALES and saleDays >= MIN_SALE_DAYS

	if cacheN > 40 then cache, cacheN = {}, 0 end
	if not cache[key] then cacheN = cacheN + 1 end
	cache[key] = {stamp = stamp, out = out}
	return out
end

local GREEN, RED, GREY = "|cff4ade80", "|cfff87171", "|cff999999"
local function pctText(p)
	if not p then return "-" end
	return (p >= 0 and GREEN .. "+" or RED .. "-") .. string.format("%.0f%%", math.abs(p)) .. "|r"
end
X.BestPctText = pctText

-- X.BestTimesText(bt) -> lines (plain sentences) for the best-time view
function X.BestTimesText(bt)
	local lines = {}
	if bt.dayEnough and bt.bestDay then
		local p = bt.days[bt.bestDay].pct
		lines[#lines + 1] = "Best day: |cffffd100" .. X.DAY_NAMES[bt.bestDay] .. "|r (" .. pctText(p) .. " over the week's average)" ..
			(p < 1 and (GREY .. " - the weekdays hardly differ|r") or "")
	else
		lines[#lines + 1] = "Best day: " .. GREY .. "not enough data yet (needs prices on " .. MIN_DAYS .. " days; " ..
			(bt.dayCount or 0) .. " so far)|r"
	end
	if bt.hourEnough and bt.bestHour then
		local p = bt.hours[bt.bestHour].pct
		lines[#lines + 1] = "Best hour: |cffffd100" .. string.format("%02d:00 - %02d:00", bt.bestHour, (bt.bestHour + 1) % 24) ..
			"|r (" .. pctText(p) .. " over the day's average)" .. (p < 1 and (GREY .. " - the hours hardly differ|r") or "")
	else
		lines[#lines + 1] = "Best hour: " .. GREY .. "not enough data yet (needs " .. MIN_SCANS .. " scans at " .. MIN_HOURS ..
			" different hours on " .. MIN_SCAN_DAYS .. " days; " .. (bt.scanCount or 0) .. " so far)|r"
	end
	if (bt.sales or 0) == 0 then
		lines[#lines + 1] = "Your sales: " .. GREY .. "none in the ledger yet (it reads your auction house mails)|r"
	elseif not bt.saleEnough then
		lines[#lines + 1] = "Your sales: " .. bt.sales .. GREY .. " - not enough to tell yet (needs " .. MIN_SALES ..
			" sales on " .. MIN_SALE_DAYS .. " different weekdays)|r"
	else
		lines[#lines + 1] = "Your sales: " .. bt.sales .. GREY .. ", most sold on |r" .. X.DAY_NAMES[bt.saleMostDay] ..
			GREY .. "; best price on |r" .. X.DAY_NAMES[bt.saleBestDay] .. " (" .. pctText(bt.days[bt.saleBestDay].salePct) ..
			" over your average of " .. X.Money(bt.eachAvg, true) .. ")"
	end
	lines[#lines + 1] = GREY .. (bt.serverClock and "Server time" or "Your computer's clock (the server's was not known)") ..
		". Days: the last 8 weeks, each against the days around it. Hours: the last 7 days of scans. Market value, not what sold.|r"
	return lines
end

-- [[ K.TimeBars(parent, w, h) ]] two small bar charts (weekday left, hour of the day right) and the sentences under
-- them; tb:SetData(X.BestTimes(key)). Bars go up (green) when the price is over the average, down (red) when under;
-- a small orange dot under a bar: you sold some then. Hovering a bar tells its numbers.
local ORANGE = {1, 0.55, 0.2}
local WEEK = {1, 2, 3, 4, 5, 6, 0} -- Monday first
local SHORT = {[0] = "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
function K.TimeBars(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	local bgt = f:CreateTexture(nil, "BACKGROUND")
	bgt:SetAllPoints()
	bgt:SetColorTexture(0, 0, 0, 0.3)
	local CH, MID = 120, -80 -- chart height, y of the middle line
	local dayW = math.floor(w * 0.36)
	local charts = {
		{x = 8, w = dayW - 16, n = 7, title = "Price by weekday"},
		{x = dayW + 8, w = w - dayW - 16, n = 24, title = "Price by hour of the day"},
	}
	for ci, c in ipairs(charts) do
		c.titleFs = K.Label(f, c.title, "GameFontNormalSmall")
		c.titleFs:SetPoint("TOPLEFT", c.x, -5)
		c.titleFs:SetWidth(c.w)
		c.titleFs:SetWordWrap(false)
		local mid = f:CreateTexture(nil, "BORDER")
		mid:SetColorTexture(1, 1, 1, 0.25)
		mid:SetSize(c.w, 1)
		mid:SetPoint("TOPLEFT", c.x, MID)
		c.none = K.Label(f, "", "GameFontDisableSmall", "CENTER")
		c.none:SetPoint("TOPLEFT", c.x, MID + 22)
		c.none:SetWidth(c.w)
		c.slots = {}
		local sw = c.w / c.n
		for i = 1, c.n do
			local slot = CreateFrame("Button", nil, f)
			slot:SetSize(sw, CH + 30)
			slot:SetPoint("TOPLEFT", c.x + (i - 1) * sw, MID + CH / 2 + 4)
			slot.bar = slot:CreateTexture(nil, "ARTWORK")
			slot.bar:SetWidth(math.max(3, sw * 0.7))
			slot.hi = slot:CreateTexture(nil, "HIGHLIGHT")
			slot.hi:SetAllPoints()
			slot.hi:SetColorTexture(1, 1, 1, 0.06)
			slot.lab = K.Label(slot, "", "GameFontDisableSmall", "CENTER")
			slot.lab:SetPoint("TOP", f, "TOPLEFT", c.x + (i - 0.5) * sw, MID - CH / 2 - 6)
			slot.lab:SetWidth(math.max(20, sw + 6))
			slot.val = ci == 1 and K.Label(slot, "", "GameFontHighlightSmall", "CENTER") or nil
			slot.sold = slot:CreateTexture(nil, "OVERLAY")
			slot.sold:SetColorTexture(ORANGE[1], ORANGE[2], ORANGE[3], 1)
			slot.sold:SetSize(5, 5)
			slot.sold:SetPoint("TOP", f, "TOPLEFT", c.x + (i - 0.5) * sw, MID - CH / 2 - 20)
			slot.cx = c.x + (i - 0.5) * sw
			slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
			c.slots[i] = slot
		end
	end
	f.charts = charts
	f.text = K.Label(f, "", "GameFontHighlightSmall")
	f.text:SetPoint("TOPLEFT", 8, MID - CH / 2 - 32)
	f.text:SetWidth(w - 16)
	f.text:SetJustifyV("TOP")

	local function tipFor(slot, title, s, enough, what)
		slot:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(title)
			if s.n > 0 then
				GameTooltip:AddDoubleLine("Market value", pctText(s.pct) .. GREY .. " over the " .. what .. "'s average|r", 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("Seen", s.n .. (what == "week" and " day" or " scan") .. (s.n == 1 and "" or "s"), 0.6, 0.6, 0.6, 1, 1, 1)
				if not enough then GameTooltip:AddLine("Not enough data yet - a guess so far.", 0.97, 0.44, 0.44, true) end
			else
				GameTooltip:AddLine("No prices seen then yet.", 0.6, 0.6, 0.6)
			end
			if s.units > 0 then
				GameTooltip:AddDoubleLine("You sold", X.Num(s.units) .. GREY .. " in " .. s.sales .. " sale" .. (s.sales == 1 and "" or "s") .. "|r", 1, 0.55, 0.2, 1, 1, 1)
				GameTooltip:AddDoubleLine("Your price of one", X.Money(s.each, true) .. " " .. (s.salePct and pctText(s.salePct) or ""), 1, 0.55, 0.2, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
	end

	local function draw(c, list, keys, enough, label, title, what)
		local maxAbs = 5
		for _, k in ipairs(keys) do
			local s = list[k]
			if s.pct and math.abs(s.pct) > maxAbs then maxAbs = math.abs(s.pct) end
		end
		local scale = (CH / 2 - 16) / maxAbs -- room for the % labels over the weekday bars
		local any = false
		for i, k in ipairs(keys) do
			local slot, s = c.slots[i], list[k]
			slot.bar:ClearAllPoints()
			if s.pct then
				any = true
				local hgt = math.max(1, math.abs(s.pct) * scale)
				local a = enough and 0.9 or 0.45
				if s.pct >= 0 then
					slot.bar:SetColorTexture(0.29, 0.87, 0.5, a)
					slot.bar:SetPoint("BOTTOM", f, "TOPLEFT", slot.cx, MID)
				else
					slot.bar:SetColorTexture(0.97, 0.44, 0.44, a)
					slot.bar:SetPoint("TOP", f, "TOPLEFT", slot.cx, MID)
				end
				slot.bar:SetHeight(hgt)
				slot.bar:Show()
				if slot.val then
					slot.val:SetText(pctText(s.pct))
					slot.val:ClearAllPoints()
					if s.pct >= 0 then
						slot.val:SetPoint("BOTTOM", f, "TOPLEFT", slot.cx, MID + hgt + 2)
					else
						slot.val:SetPoint("TOP", f, "TOPLEFT", slot.cx, MID - hgt - 2)
					end
					slot.val:Show()
				end
			else
				slot.bar:Hide()
				if slot.val then slot.val:Hide() end
			end
			slot.lab:SetText(label(k, i))
			slot.sold:SetShown(s.units > 0)
			tipFor(slot, title(k), s, enough, what)
		end
		c.none:SetText(any and "" or "No prices yet")
		c.none:SetShown(not any)
	end

	function f:SetData(bt)
		local hours = {}
		for hr = 0, 23 do hours[#hours + 1] = hr end
		draw(charts[1], bt.days, WEEK, bt.dayEnough, function(k) return SHORT[k] end,
			function(k) return X.DAY_NAMES[k] end, "week")
		draw(charts[2], bt.hours, hours, bt.hourEnough, function(k) return k % 3 == 0 and tostring(k) or "" end,
			function(k) return string.format("%02d:00 - %02d:59", k, k) end, "day")
		charts[2].titleFs:SetText("Price by hour of the day " .. GREY .. (bt.serverClock and "(server time)" or "(your clock)") .. "|r")
		self.text:SetText(table.concat(X.BestTimesText(bt), "\n"))
	end
	return f
end

-- [[ fair prices ]] X.FairPrices(key) -> buy, sell, note, days (nil, nil, note when there is too little history)
-- From the last 14 days of the item's history (silly prices already left out by X.History):
--   buy  = a price it is often listed at or under: 1 in 4 of the lowest prices seen was this cheap or cheaper.
--   sell = what it usually sells around: the middle (median) of its market value, never over the 30-day high.
-- Every day counts the same, however many scans it had. Kept until the item gets a new price or the hour changes.
local FAIR_DAYS = 14
local FAIR_BUY_PART = 0.25
local fairCache = setmetatable({}, {__mode = "k"})

-- the value below which `part` of the weight lies; list = {{value, weight}, ...}
local function weightedPart(list, part)
	if #list == 0 then return nil end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	local total = 0
	for _, e in ipairs(list) do total = total + e[2] end
	local want, sum = total * part, 0
	for _, e in ipairs(list) do
		sum = sum + e[2]
		if sum >= want - 1e-9 then return e[1] end
	end
	return list[#list][1]
end

function X.FairPrices(key)
	key = key and tostring(key)
	local it = key and X.Items()[key]
	if not it then return nil, nil, "Never seen on the auction house yet.", 0 end
	local hour = math.floor(X.Now() / 3600)
	local c = fairCache[it]
	if c and c.t == (it.cur and it.cur.t) and c.hour == hour then return c.buy, c.sell, c.note, c.days end
	local hist = X.History(key, X.Now() - FAIR_DAYS * 86400)
	-- how many points each day has (each day counts the same)
	local perDay, days = {}, 0
	for _, p in ipairs(hist) do
		local d = math.floor(p[1] / 86400)
		if not perDay[d] then days = days + 1 end
		perDay[d] = (perDay[d] or 0) + 1
	end
	-- lowest prices: the sold-out moments do not count, and a silly low one is left out too
	local mins = {}
	for _, p in ipairs(hist) do
		if p[2] and p[2] > 0 and (p[4] or 1) > 0 then mins[#mins + 1] = p[2] end
	end
	local midMin = X.Median(mins)
	local lows, mkts = {}, {}
	for _, p in ipairs(hist) do
		local w = 1 / perDay[math.floor(p[1] / 86400)]
		if p[2] and p[2] > 0 and (p[4] or 1) > 0 and not X.CrazyPrice(p[2], midMin) then lows[#lows + 1] = {p[2], w} end
		local m = p[3] or p[2]
		if m and m > 0 then mkts[#mkts + 1] = {m, w} end
	end
	local buy, sell, note
	if #lows < 3 or #mkts < 3 then
		note = "Not enough price history yet: a few more scans on different days fill these in."
	else
		buy = weightedPart(lows, FAIR_BUY_PART)
		sell = weightedPart(mkts, 0.5)
		local st = X.Stats(it)
		if st and st.high30 and sell > st.high30 then sell = st.high30 end
		if buy > sell then buy = sell end
		buy, sell = X.Round(buy), X.Round(sell)
		note = "Fair to buy: it was listed this cheap or cheaper about 1 time in 4. Fair to sell: its usual market " ..
			"value. Both from the last " .. (days < FAIR_DAYS and (days .. " day" .. (days == 1 and "" or "s")) or (FAIR_DAYS .. " days")) ..
			(days < 4 and " - only a rough guide so far." or ".")
	end
	fairCache[it] = {t = it.cur and it.cur.t, hour = hour, buy = buy, sell = sell, note = note, days = days}
	return buy, sell, note, days
end
