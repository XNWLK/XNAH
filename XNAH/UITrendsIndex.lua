-- Trends view, Market index page (UI.AddTrendsPage, order 1): one line that shows whether the whole auction house
-- gets cheaper or pricier, like a stock index (100 = prices at the start of the period; the math is in Trends.lua,
-- X.TrendsData). Extra lines for item groups (Cloth, Herb, Armor ...) can be switched on and off with the small
-- buttons above the graph. Tiles: the index now, its change over 7 and 30 days, how many items rise, how many are in
-- the basket. Worked out a little per frame, only while the page is shown, and kept until new prices arrive.
-- Also here (used by the other Trends pages, which load after this file):
--   UI.TrendsButtons(parent, x, y, defs, onPick) -> buttons: a row of small buttons, defs = {{label, width, tip title,
--     tip}, ...}; onPick(i) on a click; buttons.right = x just right of the last one; buttons.Select(i)
--   UI.TrendsPct(p, decimals) - "+3.2%" green / "-1.5%" red (nil: a grey dash)
--   UI.TRENDS_RANGES = {{"7 days", 7}, {"30 days", 30}, {"90 days", 90}, {"1 year", 365}}
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local NONE = "|cff666666-|r"

X.Default("trendsRange", 2)  -- the index page's period (an index of UI.TRENDS_RANGES): 30 days
X.Default("trendsLines", {}) -- group lines picked on or off: [group key] = true / false (others: the 3 biggest are on)

UI.TRENDS_RANGES = {{"7 days", 7}, {"30 days", 30}, {"90 days", 90}, {"1 year", 365}}

-- [[ shared bits ]]
function UI.TrendsButtons(parent, x, y, defs, onPick)
	local buttons = {}
	for i, d in ipairs(defs) do
		local b = K.Flat(parent, d[2] or 56, 18)
		b:SetPoint("TOPLEFT", x, y)
		b:SetLabel(d[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() onPick(i) end)
		if d[4] then K.Tooltip(b, d[3] or d[1], d[4]) end
		buttons[i] = b
		x = x + (d[2] or 56) + 4
	end
	buttons.right = x
	buttons.Select = function(sel) for i, b in ipairs(buttons) do b:SetSelected(i == sel) end end
	return buttons
end

function UI.TrendsPct(p, decimals)
	if p == nil then return NONE end
	local col = math.abs(p) < 0.5 and "aaaaaa" or (p >= 0 and "4ade80" or "f87171")
	return "|cff" .. col .. (p >= 0 and "+" or "") .. string.format("%." .. (decimals or 1) .. "f", p) .. "%|r"
end

local function hexOf(c)
	return string.format("%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- [[ the page ]]
local WHITE = {1, 1, 1}
local MAX_CHIPS = 14
local TILES = {
	{"Market index", "Where prices stand against the start of the period: 100 = the same, 105 = the typical item costs " ..
		"5% more, 95 = 5% less. The 10% most extreme price changes at each end are left out, so a few odd items cannot swing it."},
	{"Change, 7 days", "How much the typical item's price went up or down in the last 7 days."},
	{"Change, 30 days", "How much the typical item's price went up or down in the last 30 days."},
	{"Items rising", "The share of the items in the basket that cost more now than at the start of the period. Next to " ..
		"it: the share that cost less."},
	{"Items in the basket", "How many items the index is made of: items with a price near the start of the period and " ..
		"enough days of prices in it (setting: days of history needed). Next to it: every item XNAH knows."},
}

local function rangeIndex()
	local i = X.S().trendsRange
	return UI.TRENDS_RANGES[i] and i or 2
end

local function lineOn(gk, rank)
	local v = X.S().trendsLines[gk]
	if v == nil then return rank <= 3 end
	return v == true
end

local refresh
local function chip(page, i)
	local c = page.chips[i]
	if c then return c end
	c = K.Flat(page, 60, 18)
	c.label:SetJustifyH("CENTER")
	c:SetScript("OnClick", function(self)
		if not self.gk then return end
		X.S().trendsLines[self.gk] = not self.on
		refresh(page)
	end)
	c:SetScript("OnEnter", function(self)
		if not self.gk then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(X.TrendsGroupLabel(self.gk))
		GameTooltip:AddLine("Its own index line: " .. X.Num(self.count or 0) .. " items of this group are in the basket. " ..
			"Click to show or hide the line.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	c:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.chips[i] = c
	return c
end

local function build(page, w, h)
	page.w = w
	page.tiles = UI.NumberTiles(page, w, TILES, 0)
	local defs = {}
	for i, r in ipairs(UI.TRENDS_RANGES) do
		defs[i] = {r[1], 56, "Period: " .. r[1], "The index over the last " .. r[1] .. " (100 at its start)."}
	end
	page.ranges = UI.TrendsButtons(page, 0, -54, defs, function(i) X.S().trendsRange = i refresh(page) end)
	page.note = K.Label(page, GREY .. "100 = prices at the start of the period. Hover the graph for the numbers.|r",
		"GameFontHighlightSmall", "RIGHT")
	page.note:SetPoint("TOPRIGHT", 0, -57)
	page.note:SetWidth(w - page.ranges.right - 10)
	page.note:SetWordWrap(false)
	page.linesLabel = K.Label(page, GREY .. "Group lines:|r", "GameFontNormalSmall")
	page.linesLabel:SetPoint("TOPLEFT", 0, -81)
	page.chips = {}
	page.graph = K.Graph(page, w, h - 104 - 20)
	page.graph:SetPoint("TOPLEFT", 0, -104)
	page.foot = K.Label(page, "", "GameFontDisableSmall")
	page.foot:SetPoint("BOTTOMLEFT", 2, 4)
	page.foot:SetWidth(w - 4)
	page.foot:SetWordWrap(false)
end

refresh = function(page)
	local ri = rangeIndex()
	page.ranges.Select(ri)
	local P = UI.TRENDS_RANGES[ri][2]
	local res, busy, progress = X.TrendsData({P})
	local idx = res and res.index[P]
	local t = page.tiles
	if not idx then
		for i = 1, #t do UI.SetTile(t[i], busy and (GREY .. "...|r") or nil) end
		for _, c in ipairs(page.chips) do c:Hide() end
		page.graph:SetSeries({}, {empty = busy and ("Working it out ... " .. (progress or "")) or "No prices yet"})
		page.foot:SetText(progress or "")
		return busy and "working ..." or nil
	end
	-- tiles
	local known = res.groups and res.groups.all and res.groups.all.items or 0
	UI.SetTile(t[1], idx.now and string.format("%.1f", idx.now) or nil, UI.TRENDS_RANGES[ri][1])
	local i7, i30 = res.index[7], res.index[30]
	UI.SetTile(t[2], i7 and i7.now and UI.TrendsPct(i7.now - 100) or nil, i7 and (X.Num(i7.basket) .. " items") or nil)
	UI.SetTile(t[3], i30 and i30.now and UI.TrendsPct(i30.now - 100) or nil, i30 and (X.Num(i30.basket) .. " items") or nil)
	if idx.basket > 0 then
		UI.SetTile(t[4], math.floor(idx.rising / idx.basket * 100 + 0.5) .. "%",
			math.floor(idx.falling / idx.basket * 100 + 0.5) .. "% falling")
	else
		UI.SetTile(t[4], nil)
	end
	UI.SetTile(t[5], X.Num(idx.basket), "of " .. X.Num(known) .. " known")

	-- the group buttons: the groups with a line, biggest first
	local keys = {}
	for gk in pairs(idx.lines) do if gk ~= "all" then keys[#keys + 1] = gk end end
	table.sort(keys, function(a, b)
		local na, nb = idx.n[a] or 0, idx.n[b] or 0
		if na ~= nb then return na > nb end
		return a < b
	end)
	local series = {{points = idx.all, label = "All items", color = WHITE, width = 3}}
	local x = 74
	local shown = 0
	for i = 1, math.min(#keys, MAX_CHIPS) do
		local gk = keys[i]
		local label = X.TrendsGroupLabel(gk)
		local cw = math.max(44, #label * 6 + 14)
		if x + cw > page.w then break end
		local c = chip(page, i)
		c:ClearAllPoints()
		c:SetPoint("TOPLEFT", x, -78)
		c:SetSize(cw, 18)
		x = x + cw + 4
		local color = K.GRAPH_COLORS[(i - 1) % #K.GRAPH_COLORS + 1]
		c.gk, c.count, c.on = gk, idx.n[gk], lineOn(gk, i)
		c:SetLabel(c.on and ("|cff" .. hexOf(color) .. label .. "|r") or (GREY .. label .. "|r"))
		c:SetSelected(c.on)
		c:Show()
		shown = i
		if c.on then series[#series + 1] = {points = idx.lines[gk], label = label, color = color} end
	end
	for i = shown + 1, #page.chips do page.chips[i]:Hide() page.chips[i].gk = nil end
	page.linesLabel:SetShown(shown > 0)
	page.graph:SetSeries(idx.basket > 0 and series or {}, {labels = "number", legend = true,
		levels = {{v = 100, color = {0.6, 0.6, 0.6}, label = "start"}},
		empty = "Not enough price history yet. The index needs items with at least " .. X.S().minSamples ..
			" days of prices in this period - one full scan a day is enough."})
	local since = X.Date(idx.start * 86400 + 43200, "%b %d")
	page.foot:SetText("From " .. since .. (idx.start > X.Day() - idx.P and " (the oldest prices XNAH has)" or "") ..
		".  A group line needs at least 3 items of the group in the basket." .. (busy and ("   " .. (progress or "")) or ""))
	return X.Num(idx.basket) .. " items in the basket"
end

UI.AddTrendsPage("index", "Market index", build, refresh, 1,
	"Is the whole auction house getting cheaper or pricier? 100 = prices at the start of the period.")
