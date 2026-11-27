-- Trends view, What changed page (UI.AddTrendsPage, order 4): a short report of what moved on the auction house in a
-- period - since your last visit to this page, the last day or the last 7 days. Six lists: biggest risers, biggest
-- fallers, sold out (listed at the start, none now), flooded (far more listed), new (first seen in the period) and
-- back (none listed at the start, listed now). Click a row to see the item; right-click for the item menu.
-- The lists come from X.TrendsChanges (Trends.lua), worked out a little per frame while the page is shown.
-- "Your last visit" = the last time this page was shown in an earlier session (setting trendsLastVisit); on the very
-- first visit the last day is used.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local DAY = 86400

X.Default("trendsChangesRange", 1) -- 1 = since your last visit, 2 = 1 day, 3 = 7 days
X.Default("trendsLastVisit", 0)    -- when this page was last shown (server seconds)

local RANGES = {
	{"Since your last visit", 130, "Since your last visit", "What changed since you last looked at this page (in an " ..
		"earlier session). The first time: the last 24 hours."},
	{"1 day", 56, "1 day", "What changed in the last 24 hours."},
	{"7 days", 56, "7 days", "What changed in the last 7 days."},
}
local KINDS = {"visit", "day", "week"}

-- when this page was shown before this session (false: never)
local visitFrom

local function money(v) return UI.MoneyCell(v) end
local function units(v) return v and X.Num(v) or NONE end
local function itemCol(w)
	return {"Item", w, "LEFT", text = function(r) return UI.ItemCell(r.key) end,
		sort = function(r) return (X.ItemName(r.key) or ""):lower() end, desc = false}
end
local function usual(r)
	if r.usual == nil then r.usual = X.Usual(r.key) or false end
	return r.usual or nil
end
local ITEM_TIP = "The item. Click to see it on the Items view; right-click for its menu."

-- the six lists: field of the result, title, help, columns, column tips, first sort {column, descending}, empty text
local LISTS = {
	{"risers", "Rising most", "Items whose price went up at least 10% since the start of the period (market value then and now).",
		{itemCol(161),
		{"Before", 62, "RIGHT", text = function(r) return money(r.price0) end, sort = function(r) return r.price0 end},
		{"Now", 62, "RIGHT", text = function(r) return money(r.price) end, sort = function(r) return r.price end},
		{"Change", 48, "RIGHT", text = function(r) return UI.TrendsPct(r.change, 0) end, sort = function(r) return r.change end}},
		{ITEM_TIP, "Its market value at the start of the period.", "Its market value now.", "How much its price went up."},
		{4, true}, "No price went up 10% or more."},
	{"fallers", "Falling most", "Items whose price went down at least 10% since the start of the period.",
		{itemCol(161),
		{"Before", 62, "RIGHT", text = function(r) return money(r.price0) end, sort = function(r) return r.price0 end},
		{"Now", 62, "RIGHT", text = function(r) return money(r.price) end, sort = function(r) return r.price end},
		{"Change", 48, "RIGHT", text = function(r) return UI.TrendsPct(r.change, 0) end, sort = function(r) return r.change end}},
		{ITEM_TIP, "Its market value at the start of the period.", "Its market value now.", "How much its price went down."},
		{4, false}, "No price went down 10% or more."},
	{"soldOut", "Sold out", "Items that were listed at the start of the period and have none listed now: a chance to " ..
		"sell at your own price.",
		{itemCol(197),
		{"Had", 56, "RIGHT", text = function(r) return units(r.qty0) end, sort = function(r) return r.qty0 end},
		{"Price then", 80, "RIGHT", text = function(r) return money(r.price0) end, sort = function(r) return r.price0 end}},
		{ITEM_TIP, "How many were listed at the start of the period.", "Its market value at the start of the period."},
		{3, true}, "Nothing sold out."},
	{"flooded", "Flooded", "Items with at least twice as many listed as at the start of the period (and 10 or more " ..
		"extra): prices may drop, better wait before selling.",
		{itemCol(173),
		{"Before", 52, "RIGHT", text = function(r) return units(r.qty0) end, sort = function(r) return r.qty0 end},
		{"Now", 52, "RIGHT", text = function(r) return units(r.qty) end, sort = function(r) return r.qty end},
		{"Change", 56, "RIGHT", text = function(r) return UI.TrendsPct(r.change, 0) end, sort = function(r) return r.change end}},
		{ITEM_TIP, "How many were listed at the start of the period.", "How many are listed now.",
			"How much the number listed went up."},
		{4, true}, "Nothing flooded."},
	{"new", "New on the auction house", "Items XNAH saw for the first time in this period.",
		{itemCol(151),
		{"First seen", 62, "RIGHT", text = function(r) return X.Ago(r.first) end, sort = function(r) return r.first end},
		{"Listed", 50, "RIGHT", text = function(r) return units(r.qty) end, sort = function(r) return r.qty end},
		{"Price", 70, "RIGHT", text = function(r) return money(r.price) end, sort = function(r) return r.price end}},
		{ITEM_TIP, "When XNAH first saw it on the auction house.", "How many are listed now.", "Its market value now."},
		{2, true}, "Nothing new."},
	{"back", "Back on the auction house", "Items that had none listed at the start of the period and are listed again now.",
		{itemCol(143),
		{"Listed", 50, "RIGHT", text = function(r) return units(r.qty) end, sort = function(r) return r.qty end},
		{"Price", 70, "RIGHT", text = function(r) return money(r.price) end, sort = function(r) return r.price end},
		{"Usual", 70, "RIGHT", text = function(r) return money(usual(r)) end, sort = usual}},
		{ITEM_TIP, "How many are listed now.", "Its market value now.",
			"Its usual price (the 30-day average, else 7 or 3 days): is it back cheap or dear?"},
		{3, true}, "Nothing came back."},
}

local refresh
local function build(page, w, h)
	page.ranges = UI.TrendsButtons(page, 0, 0, RANGES, function(i) X.S().trendsChangesRange = i refresh(page) end)
	page.since = K.Label(page, "", "GameFontHighlightSmall")
	page.since:SetPoint("TOPLEFT", page.ranges.right + 8, -3)
	page.since:SetWidth(w - page.ranges.right - 8)
	page.since:SetWordWrap(false)
	local gap = 10
	local cw = math.floor((w - 2 * gap) / 3)
	local rowH = math.floor((h - 26) / 2)
	page.lists = {}
	for i, def in ipairs(LISTS) do
		local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
		local x, y = col * (cw + gap), -26 - row * rowH
		local title = K.Label(page, def[2], "GameFontNormalSmall")
		title:SetPoint("TOPLEFT", x, y)
		title:SetWidth(cw - 60)
		title:SetWordWrap(false)
		local hot = CreateFrame("Frame", nil, page)
		hot:SetAllPoints(title)
		hot:EnableMouse(true)
		K.Tooltip(hot, def[2], def[3])
		local count = K.Label(page, "", "GameFontDisableSmall", "RIGHT")
		count:SetPoint("TOPRIGHT", page, "TOPLEFT", x + cw, y)
		count:SetWidth(60)
		for j, c in ipairs(def[4]) do c.tip = def[5][j] end -- the hover line of each column title
		local tbl = K.Table(page, cw, rowH - 34 - 6, def[4], function(r, button, rowFrame)
			if button == "RightButton" then UI.ItemMenu(rowFrame, r.key) else UI.ShowItem(r.key) end
		end)
		tbl:SetPoint("TOPLEFT", x, y - 34)
		tbl:SortBy(def[6][1], def[6][2])
		page.lists[i] = {tbl = tbl, count = count, def = def}
	end
end

refresh = function(page)
	local S = X.S()
	local now = X.Now()
	if visitFrom == nil then visitFrom = (S.trendsLastVisit or 0) > 0 and S.trendsLastVisit or false end
	S.trendsLastVisit = now
	local ri = RANGES[S.trendsChangesRange] and S.trendsChangesRange or 1
	page.ranges.Select(ri)
	local from
	if ri == 1 then from = visitFrom or (now - DAY) elseif ri == 2 then from = now - DAY else from = now - 7 * DAY end
	local res, busy, progress = X.TrendsChanges(KINDS[ri], from)
	if not res then
		for _, l in ipairs(page.lists) do
			l.tbl:SetRows({}, busy and "Working it out ..." or "No prices yet.")
			l.count:SetText("")
		end
		page.since:SetText(GREY .. (progress or "") .. "|r")
		return busy and "working ..." or nil
	end
	local total = 0
	for _, l in ipairs(page.lists) do
		local rows = res[l.def[1]] or {}
		local empty = l.def[7]
		if l.def[1] == "new" and res.tooYoung then
			rows, empty = {}, "XNAH's prices start after this time, so it cannot tell what is new."
		end
		l.tbl:SetRows(rows, empty)
		l.count:SetText(#rows > 0 and X.Num(#rows) or "")
		total = total + #rows
	end
	local text = "Since " .. X.Date(res.from, "%b %d %H:%M") .. " (" .. X.Ago(res.from) .. ")"
	if ri == 1 and not visitFrom then text = text .. GREY .. " - your first visit: the last 24 hours|r" end
	text = text .. GREY .. "   " .. X.Num(res.seen) .. " items seen since then|r"
	if res.tooYoung then text = text .. GREY .. "  (XNAH's prices start later than that)|r" end
	if busy then text = text .. GREY .. "   " .. (progress or "") .. "|r" end
	page.since:SetText(text)
	return X.Num(total) .. " changes"
end

-- (tests) forget the visit time read this session
function UI.TrendsChangesReset() visitFrom = nil end

UI.AddTrendsPage("changes", "What changed", build, refresh, 4,
	"What moved since your last visit, in a day or in 7 days. Click an item to see it.")
