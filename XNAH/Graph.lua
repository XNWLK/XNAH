-- A price graph: lines over time (market value, lowest price ...), faint bars for how many were listed, money on the
-- left, dates below, and a small box with the numbers where the mouse is.
--   local g = X.K.Graph(parent, w, h)
--   g:SetSeries({{points = {{t, value}, ...}, color = {r, g, b}, width = 2, label = "Market value"}, ...},
--     {bars = {{t, value}, ...}, barsLabel = "Listed", empty = "text when there is nothing", format = fn(value)})
-- Times are server seconds, oldest first. A nil value breaks a line (sold out at that time).
-- Everything is drawn with pooled lines and textures: a new SetSeries reuses what the last one made.
local ADDON, X = ...
local K = X.K

local MAXPTS = 300 -- at most this many points per line (more are averaged together)
local LEFT, RIGHT, TOP, BOTTOM = 66, 8, 8, 18 -- room for the money labels (left) and the dates (below)
local GRIDS = 6

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

	-- grid lines with their money labels, date labels
	local grid, ylab, xlab = {}, {}, {}
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
	end
	for i = 1, 5 do
		local fs = K.Label(g, "", "GameFontDisableSmall", "CENTER")
		fs:SetWidth(90)
		fs:SetWordWrap(false)
		fs:Hide()
		xlab[i] = fs
	end
	g.empty = K.Label(plot, "", "GameFontDisableSmall", "CENTER")
	g.empty:SetPoint("CENTER")
	g.empty:SetWidth(pw - 20)

	-- pools: lines, dots (single points), bars
	local lines, nLines = {}, 0
	local dots, nDots = {}, 0
	local bars, nBars = {}, 0
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

	local data = {series = {}, marks = {}} -- what is drawn, for the mouse-over box
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
			text = text .. "\n" .. string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) .. (s.label or "") ..
				"|r  " .. (v and fmt(v) or "|cff666666-|r")
			local d = hoverDots[i]
			if not d then
				d = plot:CreateTexture(nil, "OVERLAY", nil, 2)
				d:SetSize(6, 6)
				hoverDots[i] = d
			end
			if v then
				d:SetColorTexture(c[1], c[2], c[3], 1)
				d:ClearAllPoints()
				d:SetPoint("CENTER", plot, "BOTTOMLEFT", m.x, data.y(v))
				d:Show()
			else
				d:Hide()
			end
		end
		for i = #data.series + 1, #hoverDots do hoverDots[i]:Hide() end
		if data.bars then
			local v = valueAt(data.bars, m.t)
			text = text .. "\n|cff8aa4ff" .. (data.barsLabel or "Listed") .. "|r  " .. (v and X.Num(v) or "-")
		end
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

	g:SetScript("OnUpdate", function(self)
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
	end)
	g:SetScript("OnHide", hideHover)

	function g:SetSeries(series, opts)
		opts = opts or {}
		series = series or {}
		hideHover()
		for i = 1, nLines do lines[i]:Hide() end
		for i = 1, nDots do dots[i]:Hide() end
		for i = 1, nBars do bars[i]:Hide() end
		for i = 1, GRIDS do grid[i]:Hide() ylab[i]:Hide() end
		for i = 1, 5 do xlab[i]:Hide() end
		nLines, nDots, nBars = 0, 0, 0
		data = {series = {}, marks = {}, format = opts.format or function(v) return X.Money(v, true) end,
			barsLabel = opts.barsLabel, span = 0}

		-- thin out, find the time and value ranges
		local t0, t1, lo, hi
		for _, s in ipairs(series) do
			local pts = thin(sorted(s.points or {}), MAXPTS)
			if #pts > 0 then
				data.series[#data.series + 1] = {pts = pts, color = s.color or {1, 1, 1}, width = s.width or 2, label = s.label}
				for _, p in ipairs(pts) do
					if not t0 or p[1] < t0 then t0 = p[1] end
					if not t1 or p[1] > t1 then t1 = p[1] end
					local v = p[2]
					if v ~= nil then
						if not lo or v < lo then lo = v end
						if not hi or v > hi then hi = v end
					end
				end
			end
		end
		local barPts = opts.bars and thin(sorted(opts.bars), MAXPTS) or {}
		local barMax = 0
		for _, p in ipairs(barPts) do
			if p[2] and p[2] > barMax then barMax = p[2] end
			if not t0 or p[1] < t0 then t0 = p[1] end
			if not t1 or p[1] > t1 then t1 = p[1] end
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
		local pad = (hi - lo) * 0.08
		if pad <= 0 then pad = math.max(math.abs(hi) * 0.1, 1) end
		local vlo, vhi = lo - pad, hi + pad
		if lo >= 0 and vlo < 0 then vlo = 0 end
		local function xOf(t) return (t - t0) / (t1 - t0) * pw end
		local function yOf(v) return (v - vlo) / (vhi - vlo) * ph end
		data.y = yOf

		-- grid and money labels on round steps
		local step = niceStep(vlo, vhi, 4)
		local v = math.ceil(vlo / step) * step
		local i = 0
		while v <= vhi and i < GRIDS do
			i = i + 1
			local y = yOf(v)
			grid[i]:ClearAllPoints()
			grid[i]:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
			grid[i]:SetWidth(pw)
			grid[i]:Show()
			ylab[i]:SetText(data.format(v))
			ylab[i]:ClearAllPoints()
			ylab[i]:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, y)
			ylab[i]:Show()
			v = v + step
		end

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
			local pts = s.pts
			for k = 1, #pts do
				local p = pts[k]
				local t = p[1]
				if not seen[t] then
					seen[t] = true
					data.marks[#data.marks + 1] = {t = t, x = xOf(t)}
				end
				if p[2] ~= nil then
					local x, y = xOf(t), yOf(p[2])
					local nxt = pts[k + 1]
					if nxt and nxt[2] ~= nil then
						local l = line(s.color, s.width)
						l:SetStartPoint("BOTTOMLEFT", plot, x, y)
						l:SetEndPoint("BOTTOMLEFT", plot, xOf(nxt[1]), yOf(nxt[2]))
					end
					local prev = pts[k - 1]
					if not (prev and prev[2] ~= nil) and not (nxt and nxt[2] ~= nil) then
						dot(s.color, s.width + 3, x, y)
						if #pts == 1 then -- just one point: a short flat line through it
							local l = line(s.color, s.width)
							l:SetStartPoint("BOTTOMLEFT", plot, math.max(0, x - 8), y)
							l:SetEndPoint("BOTTOMLEFT", plot, math.min(pw, x + 8), y)
						end
					end
				end
			end
		end
		table.sort(data.marks, function(a, b) return a.t < b.t end)
	end

	return g
end
