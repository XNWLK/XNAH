-- Items view, Compare page: the item picked plus up to 4 more on one graph (ore against bars, a herb against its
-- potion). Pick them with the box at the top (it finds items the same way as "Add an item"); the x on an item takes it
-- off. "Price" shows the prices of one; "% change" starts every line at 100% at the start of the range, so items of very
-- different prices can be compared. Under the graph: each item's price now, its change over 7 and 30 days, how many
-- are listed.
-- The items compared are remembered per item picked (setting compareLists; at most MAX_LISTS items keep a list, the
-- one changed longest ago goes first).
--   X.CompareList(key) -> {other keys}; X.CompareAdd(key, other) -> true, or false and why ("same" / "already" /
--     "full"); X.CompareRemove(key, other)
--   X.CompareIndex(points) -> the points as % of the first price (100 = the first price)
--   X.PriceChange(key, days) -> % the price moved in that many days (the price now against the day price then), or nil
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, RED = "|cff999999", "|cfff87171"
local NONE = "|cff666666-|r"
local DAY = 86400
local MAX_OTHERS = 4 -- items besides the one picked
local MAX_LISTS = 50 -- items that remember a compare list
local RANGES = {{"7 days", 7}, {"30 days", 30}, {"90 days", 90}, {"1 year", 365}}
X.Default("compareLists", {}) -- [picked item] = {t = last change, k = {other item keys}}
X.Default("compareMode", "price") -- "price" or "pct"
X.Default("compareRange", 2)      -- an index of RANGES

-- [[ the list of each item ]]
local function lists() return X.S().compareLists end
function X.CompareList(key)
	local e = key and lists()[tostring(key)]
	local out = {}
	if e and type(e.k) == "table" then
		for i = 1, math.min(MAX_OTHERS, #e.k) do out[i] = e.k[i] end
	end
	return out
end
function X.CompareAdd(key, other)
	if not (key and other) then return false, "none" end
	key, other = tostring(key), tostring(other)
	if key == other then return false, "same" end
	local all = lists()
	local e = all[key]
	if not e then
		e = {k = {}}
		all[key] = e
	end
	if X.Contains(e.k, other) then return false, "already" end
	if #e.k >= MAX_OTHERS then return false, "full" end
	e.k[#e.k + 1] = other
	e.t = X.Now()
	-- not too many lists: the one changed longest ago goes
	local n = 0
	for _ in pairs(all) do n = n + 1 end
	while n > MAX_LISTS do
		local oldKey, oldT
		for k, v in pairs(all) do
			if k ~= key and (not oldT or (v.t or 0) < oldT) then oldKey, oldT = k, v.t or 0 end
		end
		if not oldKey then break end
		all[oldKey] = nil
		n = n - 1
	end
	return true
end
function X.CompareRemove(key, other)
	local all = lists()
	local e = key and all[tostring(key)]
	if not e then return end
	local i = X.Contains(e.k, tostring(other))
	if i then table.remove(e.k, i) end
	e.t = X.Now()
	if #e.k == 0 then all[tostring(key)] = nil end
end
X.COMPARE_MAX, X.COMPARE_LISTS = MAX_OTHERS, MAX_LISTS

-- [[ the maths ]]
function X.CompareIndex(points)
	local base
	for _, p in ipairs(points) do
		if p[2] and p[2] > 0 then base = p[2] break end
	end
	local out = {}
	for i, p in ipairs(points) do
		out[i] = {p[1], (base and p[2]) and (p[2] / base * 100) or nil}
	end
	return out
end
function X.PriceChange(key, days)
	local now = X.Price(key, "mkt")
	local past = X.DayPrice and X.DayPrice(key, X.Day() - days)
	if not (now and past and past > 0) then return nil end
	return (now / past - 1) * 100
end
-- the points of an item for the graph: {t, price of one} (market value, else the lowest price)
local function pricePoints(key, from)
	local out = {}
	for _, p in ipairs(X.History(key, from)) do out[#out + 1] = {p[1], p[3] or p[2]} end
	return out
end

-- [[ the page ]]
local function colorOf(i) return K.GRAPH_COLORS[(i - 1) % #K.GRAPH_COLORS + 1] end
local function swatch(c)
	return string.format("|TInterface\\Buttons\\WHITE8x8:9:9:0:0:8:8:0:8:0:8:%d:%d:%d|t", math.floor(c[1] * 255),
		math.floor(c[2] * 255), math.floor(c[3] * 255))
end

local COLUMNS = {
	{"Item", 250, "LEFT", text = function(r) return swatch(r.color) .. " " .. UI.ItemCell(r.key, 12) end,
		sort = function(r) return r.n end, desc = false},
	{"Price now", 110, "RIGHT", text = function(r) return UI.MoneyCell(r.price, r.stale) end, sort = function(r) return r.price end},
	{"Usual price", 110, "RIGHT", text = function(r) return X.Money(r.usual, true) end, sort = function(r) return r.usual end},
	{"7 days", 80, "RIGHT", text = function(r) return X.Pct(r.c7) end, sort = function(r) return r.c7 end},
	{"30 days", 80, "RIGHT", text = function(r) return X.Pct(r.c30) end, sort = function(r) return r.c30 end},
	{"Listed", 90, "RIGHT", text = function(r)
		if r.qty == nil then return NONE end
		return r.qty == 0 and (GREY .. "none|r") or X.Num(r.qty)
	end, sort = function(r) return r.qty end},
}
local COLUMN_TIPS = {
	"The items on the graph, in the colour of their line. Click one to show it; right-click for more.",
	"What one goes for right now (its market value at the last scan or search). Grey when the price is old.",
	"Its average market value over the last 30 days (7 or 3 days while there is less history).",
	"How much the price moved in the last 7 days. Plus (green): it rose. Minus (red): it fell.",
	"How much the price moved in the last 30 days.",
	"How many are listed on the auction house at the last scan or search.",
}

local fill -- below

local function addPicked(page, other)
	page.add:SetText("")
	page.add:ClearFocus()
	K.CloseMenu()
	local key = UI.itemKey
	if not (key and other) then return end
	local ok, why = X.CompareAdd(key, other)
	if not ok then
		page.msg = (why == "full" and ("At most " .. MAX_OTHERS .. " more items - take one off first (its x).")) or
			(why == "same" and "That is the item picked - it is always on the graph.") or
			(why == "already" and "That item is on the graph already.") or nil
	end
	fill(page, key)
end

local function buildPicker(page, w)
	local label = K.Label(page, "Compare with", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 0, -5)
	local add = K.Edit(page, 220, function(text)
		local hits = X.QuickFind and X.QuickFind(text, 1) or {}
		K.CloseMenu()
		if hits[1] and hits[1].key then addPicked(page, hits[1].key) end
	end)
	add:SetPoint("TOPLEFT", 94, 0)
	add:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-compare-add", 0.25, function()
			local text = self:GetText() or ""
			if not self:HasFocus() or #X.Trim(text) < 2 or not X.QuickFind then K.CloseMenu() return end
			local entries = {}
			for _, h in ipairs(X.QuickFind(text, 15)) do
				entries[#entries + 1] = {text = h.text, disabled = h.key == nil, func = function() addPicked(page, h.key) end}
			end
			if #entries == 0 then entries[1] = {text = "Nothing found", disabled = true} end
			K.Menu(self, entries)
		end)
	end)
	K.Tooltip(add, "Compare with", "Type an item's name and pick it: it goes on the graph next to the item picked " ..
		"(up to " .. MAX_OTHERS .. " more). Remembered for this item.")
	page.add = add
	page.note = K.Label(page, "", "GameFontHighlightSmall", "RIGHT")
	page.note:SetPoint("TOPRIGHT", 0, -5)
	page.note:SetWidth(w - 330)
	page.note:SetWordWrap(false)
	-- the items: a chip each (colour, name, x to take it off)
	page.chips = {}
	local cw = math.floor((w - 4 * 6) / (MAX_OTHERS + 1))
	for i = 1, MAX_OTHERS + 1 do
		local c = K.Flat(page, cw, 20)
		c:SetPoint("TOPLEFT", (i - 1) * (cw + 6), -26)
		c.label:ClearAllPoints()
		c.label:SetPoint("LEFT", 4, 0)
		c.label:SetPoint("RIGHT", i == 1 and -4 or -22, 0)
		c:SetScript("OnEnter", function(self) if self.key then UI.ItemTooltip(self, self.key) end end)
		c:SetScript("OnLeave", function() GameTooltip:Hide() end)
		c:SetScript("OnClick", function(self, button)
			if self.key and button == "RightButton" then UI.ItemMenu(self, self.key) end
		end)
		if i > 1 then
			local x = K.Flat(c, 18, 18)
			x:SetPoint("RIGHT", -1, 0)
			x:SetLabel(RED .. "x|r")
			x.label:SetJustifyH("CENTER")
			x:SetScript("OnClick", function()
				local key = UI.itemKey
				if key and c.key then X.CompareRemove(key, c.key) end
				fill(page, key)
			end)
			K.Tooltip(x, "Take it off", "Takes this item off the graph and the list below.")
			c.remove = x
		end
		c:Hide()
		page.chips[i] = c
	end
end

local function buildControls(page, w)
	page.modes = {}
	local defs = {
		{"price", "Price", "The price of one of each item (its market value at each scan, or each day further back)."},
		{"pct", "% change", "Every line starts at 100% at the start of the range: 120% = 20% dearer than then. Good for items " ..
			"of very different prices."},
	}
	for i, d in ipairs(defs) do
		local b = K.Flat(page, 74, 18)
		b:SetPoint("TOPLEFT", (i - 1) * 78, -54)
		b:SetLabel(d[2])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().compareMode = d[1] fill(page, UI.itemKey) end)
		K.Tooltip(b, d[2], d[3])
		page.modes[d[1]] = b
	end
	-- the usual range of the item picked (price only; the same setting as on the Overview)
	page.bandBtn = K.Flat(page, 84, 18)
	page.bandBtn:SetPoint("TOPLEFT", #defs * 78 + 4, -54)
	page.bandBtn:SetLabel("Usual range")
	page.bandBtn.label:SetJustifyH("CENTER")
	page.bandBtn:SetScript("OnClick", function() X.S().usualBand = not X.S().usualBand fill(page, UI.itemKey) end)
	K.Tooltip(page.bandBtn, "Usual range", "Shows or hides the soft band behind the line of the item picked: where its " ..
		"market value usually sat in the 30 days up to each day. A red dot: well over it; a green dot: well under it.")
	page.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(page, 56, 18)
		b:SetPoint("TOPRIGHT", -(#RANGES - i) * 60, -54)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().compareRange = i fill(page, UI.itemKey) end)
		K.Tooltip(b, r[1], "Shows the last " .. r[1] .. " on the graph.")
		page.ranges[i] = b
	end
	page.hint = K.Label(page, GREY .. "Hover the graph for the numbers.|r", "GameFontHighlightSmall", "CENTER")
	page.hint:SetPoint("TOP", page, "TOPLEFT", w / 2, -57)
	page.hint:SetWidth(w - 480)
	page.hint:SetWordWrap(false)
end

local function build(page, w, h)
	buildPicker(page, w)
	buildControls(page, w)
	page.graph = K.Graph(page, w, 300)
	page.graph:SetPoint("TOPLEFT", 0, -78)
	local ty = -400
	for i, c in ipairs(COLUMNS) do c.tip = COLUMN_TIPS[i] end -- the hover line of each column title
	page.tbl = K.Table(page, w, h + ty, COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	page.tbl:SetPoint("TOPLEFT", 0, ty)
	page.tbl:SortBy(1, false) -- the order of the graph (the item picked first)
end

fill = function(page, key)
	if not key then return end
	local S = X.S()
	local mode = S.compareMode == "pct" and "pct" or "price"
	local ri = RANGES[S.compareRange] and S.compareRange or 2
	for k, b in pairs(page.modes) do b:SetSelected(k == mode) end
	for i, b in ipairs(page.ranges) do b:SetSelected(i == ri) end
	local keys = {key}
	for _, k in ipairs(X.CompareList(key)) do keys[#keys + 1] = k end
	-- the chips
	for i, c in ipairs(page.chips) do
		local k = keys[i]
		c.key = k
		if k then
			c:SetLabel(swatch(colorOf(i)) .. " " .. X.ItemText(k))
			c:SetSelected(i == 1)
			c:Show()
		else
			c:Hide()
		end
	end
	page.add:SetEnabled(#keys <= MAX_OTHERS)
	if page.msg then
		page.note:SetText("|cffffd100" .. page.msg .. "|r")
		page.msg = nil
	elseif #keys == 1 then
		page.note:SetText(GREY .. "Type a name on the left to put another item on the graph.|r")
	elseif #keys > MAX_OTHERS then
		page.note:SetText(GREY .. "Full: take an item off (its x) to add another.|r")
	else
		page.note:SetText(GREY .. (#keys - 1) .. " of " .. MAX_OTHERS .. " more items. Remembered for this item.|r")
	end
	-- the graph
	local from = X.Now() - RANGES[ri][2] * DAY
	local series, any, ever = {}, false, false
	for i, k in ipairs(keys) do
		local pts = pricePoints(k, from)
		if #pts > 0 then any = true end
		if not ever and #pts == 0 and #X.History(k, 0, true) > 0 then ever = true end
		if mode == "pct" then pts = X.CompareIndex(pts) end
		series[#series + 1] = {points = pts, label = X.ItemName(k) or k, color = colorOf(i), width = i == 1 and 2 or 1.5}
	end
	local empty
	if not any then
		empty = ever and "No prices in this time - pick a longer range" or
			"No prices yet - a scan or a search at the auction house brings the first"
	end
	page.bandBtn:SetShown(mode == "price")
	page.bandBtn:SetSelected(S.usualBand and true or false)
	local band = mode == "price" and S.usualBand and X.UsualBand and X.UsualBand(key, from) or nil
	page.graph:SetSeries(series, {legend = true, labels = mode == "pct" and "percent" or "money", empty = empty,
		levels = mode == "pct" and {{v = 100, color = {0.6, 0.6, 0.6}, label = "start"}} or nil,
		band = band and #band > 0 and {points = band, check = 1} or nil})
	-- the table
	local rows = {}
	for i, k in ipairs(keys) do
		local it = X.Items()[k]
		rows[#rows + 1] = {key = k, n = i, color = colorOf(i), price = X.Price(k, "mkt"), stale = it and not X.Fresh(it),
			usual = X.Usual and X.Usual(k), c7 = X.PriceChange(k, 7), c30 = X.PriceChange(k, 30),
			qty = it and it.cur and it.cur.qty}
	end
	page.tbl:SetRows(rows, "")
end

UI.AddItemPage("compare", "Compare", build, function(page, key) fill(page, key) end, 3,
	"The item and up to " .. MAX_OTHERS .. " more on one graph (ore against bars, a herb against its potion): their prices, " ..
	"or how much each moved in %. Under it: each one's price now and its change over 7 and 30 days.")
