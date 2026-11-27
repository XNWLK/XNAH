-- Items view, the Patterns page of the item picked (UI.AddItemPage, order 2, 810 x 532): six number tiles on top, then
-- three boxes - when it is cheap or scarce (the weekday x time-of-day grid, K.Heatmap, with a Price / Supply switch),
-- how jumpy the price is (the 30-day low and high around the daily market value, today's price as a dot), and the
-- market size (about how many sell a day and how much gold that is, two graphs over 30 days). The numbers come from
-- Patterns.lua. Also here, for the Overview's small grid: UI.PatternGridData(key, mode, small) -> the data for
-- hm:SetData and the grid; UI.PatternSummary(grid, mode) -> one short line; UI.PATTERN_ROWS / UI.PATTERN_COLS.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED, GOLD = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"
local ORANGE, BLUE = "|cffff9933", "|cff66a0ff"
local NONE = "|cff666666-|r"
local DAY = 86400

local WEEK = {1, 2, 3, 4, 5, 6, 0} -- Monday first
local SHORT = {[0] = "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
UI.PATTERN_ROWS = {}
for i, wd in ipairs(WEEK) do UI.PATTERN_ROWS[i] = SHORT[wd] end
UI.PATTERN_COLS = {}
for b = 0, X.PATTERN_BLOCKS - 1 do
	local h = math.floor(24 / X.PATTERN_BLOCKS)
	UI.PATTERN_COLS[b + 1] = (b * h) .. "-" .. ((b + 1) * h)
end
UI.PATTERN_WEEK = WEEK

local function M(v) return X.Money(v, true) end
local function pctText(p, invert)
	if not p then return NONE end
	local good = p < 0
	if invert then good = not good end
	return (good and GREEN or RED) .. (p >= 0 and "+" or "-") .. string.format("%.0f%%", math.abs(p)) .. "|r"
end
local function timesText(n)
	if not n or n <= 0 then return "never" end
	if n < 0.75 then return "less than once lately" end
	local r = math.floor(n + 0.5)
	return "about " .. r .. " time" .. (r == 1 and "" or "s")
end

-- [[ the grid's data ]] mode "price" or "supply"; small = no text inside the squares (the Overview)
local function cellLines(cell, mode, usual)
	local lines = {}
	if cell.pct then
		local word = math.abs(cell.pct) < 0.5 and "as usual" or
			(string.format("%.0f%%", math.abs(cell.pct)) .. (cell.pct < 0 and " cheaper" or " dearer") .. " than usual")
		lines[#lines + 1] = {"Price then", (cell.price and (M(cell.price) .. "  ") or "") .. pctText(cell.pct)}
		lines[#lines + 1] = "On average " .. word .. " at this time (market value, against its usual price)."
	else
		lines[#lines + 1] = {"Price then", GREY .. "none listed when seen|r"}
	end
	lines[#lines + 1] = {"Listed then", X.Num(cell.q) .. (cell.qpct and ("  " .. pctText(cell.qpct, true) ..
		GREY .. " vs the other times|r") or "")}
	lines[#lines + 1] = {"Seen", timesText(cell.n)}
	lines[#lines + 1] = GREY .. "Recent weeks count most: a time seen 3 weeks ago counts half." .. "|r"
	if cell.n < 1.5 then lines[#lines + 1] = "|cfff87171Seen only once or twice - a guess so far.|r" end
	return lines
end

function UI.PatternGridData(key, mode, small)
	local grid = X.PatternGrid(key)
	mode = mode == "supply" and "supply" or "price"
	local field = mode == "price" and "pct" or "qpct"
	-- the colour scale: the biggest difference seen (at least 5% for prices, 15% for supply) is the full colour
	local maxAbs = mode == "price" and 5 or 15
	for wd = 0, 6 do
		for b = 0, X.PATTERN_BLOCKS - 1 do
			local c = grid.cells[wd][b]
			if c and c[field] and math.abs(c[field]) > maxAbs then maxAbs = math.abs(c[field]) end
		end
	end
	local cells = {}
	for r, wd in ipairs(WEEK) do
		cells[r] = {}
		for b = 0, X.PATTERN_BLOCKS - 1 do
			local c = grid.cells[wd][b]
			if c then
				local v = c[field] and c[field] / maxAbs or nil
				local text
				if not small then
					if mode == "price" then
						text = c.pct and ((c.pct >= 0 and "+" or "-") .. string.format("%.0f%%", math.abs(c.pct))) or "-"
					else
						text = X.Num(c.q)
					end
				end
				cells[r][b + 1] = {v = v, text = text, faint = c.n < 1.5, title = X.PatternTime(wd, b) .. GREY .. "  (server time)|r",
					lines = cellLines(c, mode, grid.usual)}
			end
		end
	end
	local empty
	if grid.filled == 0 then
		empty = small and "No prices yet" or "No prices yet - scans at the auction house fill this in"
	end
	return {cells = cells, scheme = mode, empty = empty}, grid
end

-- one short line: the cheapest and dearest time (price), or the scarcest and the most listed (supply)
function UI.PatternSummary(grid, mode)
	if not grid or grid.filled == 0 then return GREY .. "Nothing seen yet.|r" end
	local function at(p, field, invert)
		if not p then return NONE end
		return GOLD .. X.PatternTime(p.wd, p.b, true) .. "|r (" .. pctText(p.cell[field], invert) .. ")"
	end
	if mode == "supply" then
		return "Scarcest: " .. at(grid.scarce, "qpct", true) .. GREY .. "   Most listed: |r" .. at(grid.plenty, "qpct", true)
	end
	return "Cheapest: " .. at(grid.cheap, "pct") .. GREY .. "   Dearest: |r" .. at(grid.dear, "pct")
end

-- [[ the page ]]
local TILES = {
	{"Steady or jumpy", "How much the market value moves from one day to the next, on average over the last 30 days. " ..
		"Steady: under 3% a day. Moves a bit: 3 to 8%. Jumpy: 8 to 20%. Wild: more than 20%. Jumpy items are risky - " ..
		"or a chance to buy on a low day and sell on a high one."},
	{"30-day low", "The lowest daily market value in the last 30 days (silly prices left out)."},
	{"30-day high", "The highest daily market value in the last 30 days (silly prices left out)."},
	{"Today in the month", "Where the market value now sits among the daily market values of the last 30 days. " ..
		"\"Cheapest 10%\": it was dearer on 9 days out of 10 - a good time to buy. \"Dearest 10%\": a good time to sell."},
	{"Sells a day", "About how many are sold each day. An ESTIMATE from listings disappearing between scans: bought - or " ..
		"cancelled by the seller (the game does not tell the two apart), so it can come out somewhat high."},
	{"Gold a day", "About how much gold this item moves each day: sells a day x its usual price. The size of its " ..
		"market - an estimate from listings disappearing (bought or cancelled)."},
}
local TILE_H = 46
local ROW_Y = -54
local ROW_H = 262
local HEAT_W = 400
local MKT_Y = -324
local JUMP_COLOR, LOW_COLOR, HIGH_COLOR, NOW_COLOR = {1, 0.82, 0}, {0.29, 0.87, 0.5}, {0.97, 0.44, 0.44}, {0.4, 0.8, 1}
local UNITS_COLOR, GOLD_COLOR = {0.54, 0.64, 1}, {1, 0.82, 0}

local function titled(box, text, help, w)
	local t = K.Label(box, text, "GameFontNormalSmall")
	t:SetPoint("TOPLEFT", 8, -6)
	local hot = CreateFrame("Frame", nil, box)
	hot:SetPoint("TOPLEFT", 4, -2)
	hot:SetSize(w, 16)
	hot:EnableMouse(true)
	K.Tooltip(hot, text, help)
	return t, hot
end
local function line(box, y, w, font)
	local l = K.Label(box, "", font or "GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", 8, y)
	l:SetWidth(w)
	l:SetWordWrap(false)
	return l
end

local function build(page, w, h)
	page.tiles = UI.NumberTiles(page, w, TILES, 0)

	-- box 1: when is it cheap (or scarce)
	local heat = K.Panel(page, HEAT_W, ROW_H, {0, 0, 0, 0.25})
	heat:SetPoint("TOPLEFT", 0, ROW_Y)
	heat.title, heat.hot = titled(heat, "When is it cheap?", "Each square is a weekday and a time of the day (4 hours, " ..
		"server time). Price: green = cheaper than its usual price then, red = dearer. Supply: orange = fewer listed " ..
		"then, blue = more. Hover a square for its numbers. Kept for items you track or look at; recent weeks count most.", 220)
	page.modes = {}
	for i, m in ipairs({{"price", "Price"}, {"supply", "Supply"}}) do
		local b = K.Flat(heat, 58, 18)
		b:SetPoint("TOPRIGHT", -6 - (2 - i) * 62, -4)
		b:SetLabel(m[2])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function()
			X.S().patternsMode = m[1]
			if page.key then UI.PatternsRefresh(page, page.key) end
		end)
		K.Tooltip(b, m[2], m[1] == "price" and "Colour the squares by the price then: green cheaper, red dearer than usual." or
			"Colour the squares by how many were listed then: orange fewer (scarce), blue more than at the other times.")
		page.modes[m[1]] = b
	end
	page.heat = K.Heatmap(heat, HEAT_W - 16, 168, {rows = UI.PATTERN_ROWS, cols = UI.PATTERN_COLS, labelW = 34})
	page.heat:SetPoint("TOPLEFT", 6, -26)
	page.heatKey = line(heat, -200, HEAT_W - 16)
	page.heatSum = line(heat, -216, HEAT_W - 16)
	page.heatNote = line(heat, -232, HEAT_W - 16, "GameFontDisableSmall")
	page.heatEnough = line(heat, -246, HEAT_W - 16, "GameFontDisableSmall")
	page.heatBox = heat

	-- box 2: how jumpy
	local jw = w - HEAT_W - 8
	local jump = K.Panel(page, jw, ROW_H, {0, 0, 0, 0.25})
	jump:SetPoint("TOPLEFT", HEAT_W + 8, ROW_Y)
	jump.title, jump.hot = titled(jump, "How jumpy is the price?", "The daily market value of the last 30 days (yellow), " ..
		"the 30-day low (green line) and high (red line), and the market value now (blue dot). Hover the graph for the " ..
		"numbers.", jw - 8)
	page.jumpLine = line(jump, -22, jw - 16)
	page.jumpGraph = K.Graph(jump, jw - 12, 210)
	page.jumpGraph:SetPoint("TOPLEFT", 6, -42)
	page.jumpBox = jump

	-- box 3: market size
	local mkt = K.Panel(page, w, h + MKT_Y, {0, 0, 0, 0.25})
	mkt:SetPoint("TOPLEFT", 0, MKT_Y)
	mkt.title, mkt.hot = titled(mkt, "Market size", "About how many sell a day and how much gold that is. An ESTIMATE " ..
		"from listings disappearing between scans: bought - or cancelled by the seller (the game does not tell the two " ..
		"apart). Left: sold a day, right: gold a day (sold x the market value that day).", 300)
	page.mktLine = line(mkt, -22, w - 16)
	page.mktNote = line(mkt, -37, w - 16, "GameFontDisableSmall")
	page.mktNote:SetText("An estimate from listings disappearing between scans (bought, or cancelled by the seller - the " ..
		"game does not tell the two apart). Hover the graphs for each day.")
	local gw = math.floor((w - 24) / 2)
	page.unitsGraph = K.Graph(mkt, gw, h + MKT_Y - 60)
	page.unitsGraph:SetPoint("TOPLEFT", 6, -54)
	page.goldGraph = K.Graph(mkt, gw, h + MKT_Y - 60)
	page.goldGraph:SetPoint("TOPLEFT", 18 + gw, -54)
	page.mktBox = mkt
end

local function fillTiles(page, j, ms)
	local t = page.tiles
	UI.SetTile(t[1], j.word and (GOLD .. j.word .. "|r") or (GREY .. "too new|r"), j.move and string.format("%.0f%% a day", j.move) or
		(j.moves > 0 and (j.moves .. " of 5 days") or nil))
	UI.SetTile(t[2], j.low and M(j.low) or nil)
	UI.SetTile(t[3], j.high and M(j.high) or nil)
	local place
	if j.pct then
		place = j.pct <= 10 and (GREEN .. "cheapest 10%|r") or j.pct <= 25 and (GREEN .. "cheap|r") or
			j.pct < 75 and "normal" or j.pct < 90 and (RED .. "dear|r") or (RED .. "dearest 10%|r")
		if j.low and j.now < j.low then place = GREEN .. "lowest yet|r" end
		if j.high and j.now > j.high then place = RED .. "highest yet|r" end
	end
	UI.SetTile(t[4], place or (GREY .. (j.now and "too new" or "none listed") .. "|r"), j.pct and string.format("%.0f%% cheaper", j.pct) or nil)
	UI.SetTile(t[5], ms.perDay and X.Rate(ms.perDay) or (GREY .. "not known|r"), ms.how == "drops" and "rough" or (ms.perDay and "estimate" or nil))
	UI.SetTile(t[6], ms.gold and M(ms.gold) or (GREY .. "not known|r"), ms.gold and "estimate" or nil)
end

local function fillHeat(page, key)
	local mode = X.S().patternsMode == "supply" and "supply" or "price"
	for m, b in pairs(page.modes) do b:SetSelected(m == mode) end
	local data, grid = UI.PatternGridData(key, mode, false)
	page.heat:SetData(data)
	page.grid = grid
	if mode == "price" then
		page.heatKey:SetText(GREEN .. "Green|r: cheaper than usual then   " .. RED .. "Red|r: dearer   " .. GREY .. "Dark: not seen then|r")
		page.heatTitle = "When is it cheap?"
	else
		page.heatKey:SetText(ORANGE .. "Orange|r: fewer listed then (scarce)   " .. BLUE .. "Blue|r: more   " .. GREY .. "Dark: not seen|r")
		page.heatTitle = "When is it scarce?"
	end
	page.heatBox.title:SetText(page.heatTitle)
	page.heatSum:SetText(UI.PatternSummary(grid, mode))
	page.heatNote:SetText("Server time. Recent weeks count most. Kept for items you track or look at.")
	if grid.filled == 0 then
		page.heatEnough:SetText("")
	elseif not grid.enough then
		page.heatEnough:SetText("|cfff87171Only " .. X.Num(grid.n) .. " observations at " .. grid.priced ..
			" times so far - a rough guide. Each scan adds one.|r")
	else
		page.heatEnough:SetText(X.Num(grid.n) .. " observations at " .. grid.filled .. " of 42 times.")
	end
end

local function fillJumpy(page, key, j)
	local parts = {}
	if j.word then
		parts[#parts + 1] = GOLD .. j.word .. "|r: it moves about " .. string.format("%.0f%%", j.move) .. " a day."
	else
		parts[#parts + 1] = GREY .. "Not enough days yet to say how jumpy (needs 5 day-to-day moves, " .. j.moves .. " so far).|r"
	end
	if j.place then
		parts[#parts + 1] = "Now: " .. j.place .. "."
	elseif j.now and j.low then
		parts[#parts + 1] = GREY .. "Now: needs 5 days to compare.|r"
	end
	page.jumpLine:SetText(table.concat(parts, " "))
	local levels, marks = {}, {}
	if j.high then levels[#levels + 1] = {v = j.high, color = HIGH_COLOR, label = "30-day high"} end
	if j.low then levels[#levels + 1] = {v = j.low, color = LOW_COLOR, label = "30-day low"} end
	if j.now and #j.days > 0 then
		-- at today's noon, like the day points (whole days keep the graph's dates on whole seconds)
		marks[1] = {t = X.Day() * DAY + 43200, v = j.now, color = NOW_COLOR, text = "Market value now " .. M(j.now) ..
			(j.place and (GREY .. " - " .. j.place .. "|r") or "")}
	end
	page.jumpGraph:SetSeries({{points = j.days, color = JUMP_COLOR, width = 2, label = "Market value (day)"}},
		{levels = levels, marks = marks, empty = "No daily prices yet - scans on a few days fill this in"})
end

local function fillMarket(page, key, ms)
	if ms.perDay and ms.gold then
		page.mktLine:SetText("This item moves about " .. GOLD .. X.MoneyPlain(X.Round(ms.gold)) .. "|r a day: about " ..
			X.Rate(ms.perDay) .. " sold a day at " .. M(ms.price) .. GREY .. (ms.how == "drops" and
			"  (rough: from the number listed going down between scans)|r" or "  (from full scans compared)|r"))
	elseif ms.perDay then
		page.mktLine:SetText("About " .. X.Rate(ms.perDay) .. " sold a day" .. GREY .. " (no price to tell the gold)|r")
	else
		page.mktLine:SetText(GREY .. "Not known yet: needs two full scans up to 4 hours apart, or a few scans in a row of this item.|r")
	end
	local units, gold = {}, {}
	for i, d in ipairs(ms.daily) do
		units[i] = {d[1], d[2]}
		gold[i] = {d[1], d[3]}
	end
	page.unitsGraph:SetSeries({{points = units, color = UNITS_COLOR, width = 2, label = "Sold a day"}},
		{labels = "number", empty = "No sales seen yet"})
	page.goldGraph:SetSeries({{points = gold, color = GOLD_COLOR, width = 2, label = "Gold a day"}},
		{empty = "No sales seen yet"})
end

function UI.PatternsRefresh(page, key)
	page.key = key
	local j = X.Jumpy(key)
	local ms = X.MarketSize(key)
	fillTiles(page, j, ms)
	fillHeat(page, key)
	fillJumpy(page, key, j)
	fillMarket(page, key, ms)
end

UI.AddItemPage("patterns", "Patterns", build, function(page, key) UI.PatternsRefresh(page, key) end, 2,
	"When the item is cheap or scarce (weekday and time of day), how jumpy its price is, and about how much of it sells a day.")
