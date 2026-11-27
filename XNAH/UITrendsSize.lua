-- Trends view, Auction house size page (UI.AddTrendsPage, order 3): how full the auction house is over time, from
-- the full scans (X.Scans("full"), X.TrendsSize in Trends.lua): gold listed, auctions, different items and units.
-- Tiles: each one now and against about 7 days ago. A graph of the one picked (buttons above it) over 7 days to a
-- year. Under it two small bar charts: how full the auction house is on each weekday and at each hour of the day
-- (each scan against the scans within 3 days of it, so a growing auction house does not tip it). Scans saved by
-- older versions of XNAH have no gold or units: those points are left out.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local DAY = 86400

X.Default("trendsSizeShow", 1)  -- the measure on the graph (an index of MEASURES)
X.Default("trendsSizeRange", 2) -- the graph's period (an index of UI.TRENDS_RANGES)

local MEASURES = {
	{"gold", "Gold listed", 84, "Gold listed", "Every buyout on the auction house added up (price of one x how many), " ..
		"at each full scan."},
	{"auctions", "Auctions", 70, "Auctions", "How many auctions were up at each full scan."},
	{"items", "Different items", 100, "Different items", "How many different items were listed at each full scan."},
	{"units", "Units listed", 84, "Units listed", "How many items were listed in all (a stack of 20 counts 20), at each full scan."},
}
local TILES = {
	{"Gold listed", "Every buyout on the auction house added up, at the last full scan. Next to it: the change against " ..
		"a full scan about 7 days before."},
	{"Auctions", "How many auctions were up at the last full scan, and the change against about 7 days before."},
	{"Different items", "How many different items were listed at the last full scan, and the change against about 7 days before."},
	{"Units listed", "How many items were listed in all at the last full scan (a stack of 20 counts 20), and the change " ..
		"against about 7 days before."},
}
local WEEK = {1, 2, 3, 4, 5, 6, 0} -- Monday first
local SHORT = {[0] = "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}

local function pick(setting, list, default)
	local i = X.S()[setting]
	return list[i] and i or default
end

-- [[ a small bar chart ]] n slots, bars up (green, fuller than usual) or down (red, emptier)
local CH = 110
local function barChart(page, x, y, w, n, title, tip)
	local c = {slots = {}, n = n}
	c.title = K.Label(page, title, "GameFontNormalSmall")
	c.title:SetPoint("TOPLEFT", x, y)
	c.title:SetWidth(w)
	c.title:SetWordWrap(false)
	local hot = CreateFrame("Frame", nil, page)
	hot:SetAllPoints(c.title)
	hot:EnableMouse(true)
	K.Tooltip(hot, title, tip)
	local bg = page:CreateTexture(nil, "BACKGROUND")
	bg:SetColorTexture(0, 0, 0, 0.3)
	bg:SetSize(w, CH + 34)
	bg:SetPoint("TOPLEFT", x, y - 16)
	c.mid = y - 16 - CH / 2 - 4
	local mid = page:CreateTexture(nil, "BORDER")
	mid:SetColorTexture(1, 1, 1, 0.25)
	mid:SetSize(w, 1)
	mid:SetPoint("TOPLEFT", x, c.mid)
	c.none = K.Label(page, "", "GameFontDisableSmall", "CENTER")
	c.none:SetPoint("TOPLEFT", x, c.mid + 20)
	c.none:SetWidth(w)
	local sw = w / n
	for i = 1, n do
		local s = CreateFrame("Button", nil, page)
		s:SetSize(sw, CH)
		s:SetPoint("TOPLEFT", x + (i - 1) * sw, y - 20)
		s.bar = s:CreateTexture(nil, "ARTWORK")
		s.bar:SetWidth(math.max(3, sw * 0.7))
		s.hi = s:CreateTexture(nil, "HIGHLIGHT")
		s.hi:SetAllPoints()
		s.hi:SetColorTexture(1, 1, 1, 0.06)
		s.lab = K.Label(page, "", "GameFontDisableSmall", "CENTER")
		s.lab:SetPoint("TOP", page, "TOPLEFT", x + (i - 0.5) * sw, y - 20 - CH - 2)
		s.lab:SetWidth(math.max(18, sw + 4))
		s.cx = x + (i - 0.5) * sw
		s:SetScript("OnLeave", function() GameTooltip:Hide() end)
		c.slots[i] = s
	end
	return c
end

-- slots = {{label, s = {n, pct}, name}, ...}; ok = enough scans
local function drawChart(page, c, list, ok, noneText)
	local maxAbs = 5
	for _, e in ipairs(list) do if e.s.pct and math.abs(e.s.pct) > maxAbs then maxAbs = math.abs(e.s.pct) end end
	local scale = (CH / 2 - 6) / maxAbs
	local any = false
	for i, s in ipairs(c.slots) do
		local e = list[i]
		s.lab:SetText(e.label)
		local p = e.s.pct
		s.bar:ClearAllPoints()
		if p and ok then
			any = true
			local hgt = math.max(1, math.abs(p) * scale)
			s.bar:SetHeight(hgt)
			if p >= 0 then
				s.bar:SetPoint("BOTTOM", page, "TOPLEFT", s.cx, c.mid)
				s.bar:SetColorTexture(0.29, 0.87, 0.5, 0.85)
			else
				s.bar:SetPoint("TOP", page, "TOPLEFT", s.cx, c.mid)
				s.bar:SetColorTexture(0.97, 0.44, 0.44, 0.85)
			end
			s.bar:Show()
		else
			s.bar:Hide()
		end
		s:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(e.name)
			if e.s.n > 0 then
				GameTooltip:AddDoubleLine("Auctions", UI.TrendsPct(e.s.pct, 0) .. GREY .. " against the days around it|r",
					0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("Full scans then", X.Num(e.s.n), 0.6, 0.6, 0.6, 1, 1, 1)
				if not ok then GameTooltip:AddLine("Not enough scans yet - a guess so far.", 0.97, 0.44, 0.44, true) end
			else
				GameTooltip:AddLine("No full scan at that time yet.", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
	end
	c.none:SetText(any and "" or noneText)
end

local refresh
local function build(page, w, h)
	page.tiles = UI.NumberTiles(page, w, TILES, 0)
	local defs = {}
	for i, m in ipairs(MEASURES) do defs[i] = {m[2], m[3], m[4], m[5]} end
	page.measures = UI.TrendsButtons(page, 0, -54, defs, function(i) X.S().trendsSizeShow = i refresh(page) end)
	local rdefs = {}
	for i, r in ipairs(UI.TRENDS_RANGES) do rdefs[i] = {r[1], 56, "Period: " .. r[1], "The graph shows the last " .. r[1] .. "."} end
	page.ranges = UI.TrendsButtons(page, page.measures.right + 20, -54, rdefs, function(i) X.S().trendsSizeRange = i refresh(page) end)
	page.note = K.Label(page, GREY .. "One point per full scan. Hover the graph for the numbers.|r", "GameFontHighlightSmall", "RIGHT")
	page.note:SetPoint("TOPRIGHT", 0, -57)
	page.note:SetWidth(w - page.ranges.right - 10)
	page.note:SetWordWrap(false)
	page.graph = K.Graph(page, w, 296)
	page.graph:SetPoint("TOPLEFT", 0, -78)
	local cy = -384
	local dayW = 340
	page.days = barChart(page, 0, cy, dayW, 7, "How full by weekday",
		"How many auctions are up on each weekday, against the days around it (server time). Green = fuller than usual, " ..
		"red = emptier. Needs full scans on several different weekdays.")
	page.hours = barChart(page, dayW + 16, cy, w - dayW - 16, 24, "How full by hour of the day",
		"How many auctions are up at each hour of the day (server time), against the scans around it. Needs full scans " ..
		"at many different hours.")
	page.foot = K.Label(page, "", "GameFontDisableSmall")
	page.foot:SetPoint("BOTTOMLEFT", 2, 2)
	page.foot:SetWidth(w - 4)
	page.foot:SetWordWrap(false)
end

-- worked out again only when a full scan was added (the view refreshes often while a scan runs)
local cache = {}
local function sizeOf(scans)
	local last = scans[#scans]
	local stamp = #scans .. ":" .. tostring(last and last.t) .. ":" .. X.Day() .. ":" .. tostring(X.RealmKey())
	if cache.stamp ~= stamp then cache.stamp, cache.size = stamp, X.TrendsSize(scans) end
	return cache.size
end

refresh = function(page)
	local scans = X.Scans("full")
	local size = sizeOf(scans)
	local t = page.tiles
	local last = size.last
	for i, m in ipairs(MEASURES) do
		local v = last and last[m[1]]
		local text = type(v) == "number" and (m[1] == "gold" and X.Money(v, true) or X.Num(v)) or nil
		local ch = size.change[m[1]]
		UI.SetTile(t[i], text, ch and (UI.TrendsPct(ch, 0) .. GREY .. " in 7 days") or (last and "7 days ago: -" or nil))
	end
	local mi = pick("trendsSizeShow", MEASURES, 1)
	local ri = pick("trendsSizeRange", UI.TRENDS_RANGES, 2)
	page.measures.Select(mi)
	page.ranges.Select(ri)
	local m = MEASURES[mi]
	local from = X.Now() - UI.TRENDS_RANGES[ri][2] * DAY
	local pts = {}
	for _, p in ipairs(size[m[1]]) do if p[1] >= from then pts[#pts + 1] = p end end
	local empty
	if #scans == 0 then
		empty = "No full scans yet. Open the auction house and press Full scan."
	elseif #size[m[1]] == 0 then
		empty = "The full scans so far do not have this number (older versions of XNAH did not save it)."
	else
		empty = "No full scans in this time - pick a longer period."
	end
	page.graph:SetSeries(#pts > 0 and {{points = pts, label = m[2], color = {1, 0.82, 0}, width = 2}} or {},
		{labels = m[1] == "gold" and "money" or "number", empty = empty})
	-- the weekday and hour charts
	local pat = size.pattern
	local need = pat.need
	local days, hours = {}, {}
	for i, wd in ipairs(WEEK) do days[i] = {label = SHORT[wd], s = pat.days[wd], name = X.DAY_NAMES[wd]} end
	for hr = 0, 23 do hours[hr + 1] = {label = (hr % 3 == 0) and tostring(hr) or "", s = pat.hours[hr], name = hr .. ":00 - " .. hr .. ":59"} end
	drawChart(page, page.days, days, pat.daysOK, "Needs " .. need.scans .. " full scans on " .. need.weekdays ..
		" different weekdays (" .. pat.scans .. " so far).")
	drawChart(page, page.hours, hours, pat.hoursOK, "Needs " .. need.scans .. " full scans on " .. need.days ..
		" different days at " .. need.hours .. " different hours (" .. pat.scans .. " so far).")
	page.foot:SetText(last and ("Last full scan " .. X.Ago(last.t) .. (size.ago and (", compared with the one of " ..
		X.Date(size.ago.t, "%b %d %H:%M")) or ", none about 7 days before it to compare with") .. ".") or "")
	return X.Num(#scans) .. " full scans"
end

UI.AddTrendsPage("size", "Auction house size", build, refresh, 3,
	"How full the auction house is over time: gold, auctions, items and units listed at each full scan.")
