-- Items view, Moves with page: the items whose prices went up and down on the same days as the item picked (ore and
-- its bars, a herb and its potion), and the ones that moved the opposite way (Related.lua does the maths).
-- Layout (810 x 532): range buttons (30 / 90 days) and a line saying what was compared (or "Working..."); a plain line
-- that moving together does not prove one causes the other; the table "Moves together" (up to 15 rows); the table
-- "Moves the opposite way" (up to 5 rows); a hint line. Click a row to show that item; "+ Compare" on a row puts it
-- on the Compare page's graph next to the item picked (X.CompareAdd in UIItemCompare.lua).
-- The range is a setting (relatedRange: 30 or 90). Nothing else is saved: the results are kept in memory per item and
-- range until new prices arrive.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GOLD, GREEN, RED = "|cff999999", "|cffffd100", "|cff4ade80", "|cfff87171"
local NONE = "|cff666666-|r"
local ROW_H = 18
local FEW_DAYS = 21 -- with fewer days of prices of the item, the line at the top warns that a match can be chance
X.Default("relatedRange", 30) -- days: 30 or 90

local function rangeOf()
	local d = X.S().relatedRange
	for _, r in ipairs(X.RELATED_RANGES) do if r == d then return d end end
	return 30
end

-- "How closely" in colour: green together, red opposite
local function wordText(r)
	if not r then return NONE end
	local w = X.RelatedWord(r)
	if r < 0 then return RED .. w .. "|r" end
	if r >= 0.8 then return GREEN .. w .. "|r" end
	if r >= 0.6 then return "|cffa3e635" .. w .. "|r" end
	return "|cffd9d9d9" .. w .. "|r"
end

local COLUMNS = {
	{"Item", 250, "LEFT", text = function(r) return UI.ItemCell(r.key, 12) end, sort = function(r) return r.name end, desc = false},
	{"How closely", 100, "LEFT", text = function(r) return wordText(r.r) end, sort = function(r) return r.low end},
	{"Shared days", 80, "RIGHT", text = function(r) return X.Num(r.shared) end, sort = function(r) return r.shared end},
	{"Price now", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.price, r.stale) end, sort = function(r) return r.price end},
	{"7 days", 65, "RIGHT", text = function(r) return X.Pct(r.c7) end, sort = function(r) return r.c7 end},
	{"30 days", 65, "RIGHT", text = function(r) return X.Pct(r.c30) end, sort = function(r) return r.c30 end},
	{"Compare", 85, "CENTER", text = function() return "" end},
}
local COLUMN_TIPS = {
	"The other item. Click it to show it; right-click for more.",
	"How closely its price moved with this item's price from day to day: Very closely, Closely or A bit - or " ..
		"Opposite: it went down when this one went up. The ups and downs of the whole auction house are taken out " ..
		"first. Hover a row for the number. The best match comes first: a link seen on many days counts for more than " ..
		"one seen on a few. Items with only a few listed are left out (their price jumps with every sale).",
	"On how many days both items had a price. Only those days are compared.",
	"What one goes for right now (its market value at the last scan or search). Grey when the price is old.",
	"How much its price moved in the last 7 days. Plus (green): it rose. Minus (red): it fell.",
	"How much its price moved in the last 30 days.",
	"Puts the item on the Compare page's graph next to this item (up to " .. (X.COMPARE_MAX or 4) .. " more items).",
}
local COMPARE_X = 4 -- where the Compare column starts in a row
for i = 1, #COLUMNS - 1 do COMPARE_X = COMPARE_X + COLUMNS[i][2] end

local fill -- below

-- [[ + Compare ]]
local function addToCompare(page, other)
	local key = UI.itemKey
	if not (key and other and X.CompareAdd) then return end
	local ok, why = X.CompareAdd(key, other)
	if ok then
		page.msg = GREEN .. X.ItemName(other) .. " is on the Compare page now, next to this item.|r"
	elseif why == "full" then
		page.msg = GOLD .. "The Compare page is full (" .. (X.COMPARE_MAX or 4) .. " more items): take one off there first.|r"
	elseif why == "already" then
		page.msg = GOLD .. "That item is on the Compare page already.|r"
	end
	fill(page, key)
end
-- the state of the Compare button of a row
local function compareLabel(other)
	local key = UI.itemKey
	local list = key and X.CompareList and X.CompareList(key) or {}
	if X.Contains(list, other) then return GREY .. "on Compare|r", "on" end
	if #list >= (X.COMPARE_MAX or 4) then return GREY .. "Compare full|r", "full" end
	return "+ Compare", nil
end

-- the hover of a row: the item, then the numbers of the match
local function rowTip(rowFrame, row)
	UI.ItemTooltip(rowFrame, row.key)
	if not X.KeyID(row.key) then return end
	local name = X.ItemName(UI.itemKey) or "this item"
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Moves with " .. name .. ": " .. X.RelatedWord(row.r), 1, 0.82, 0)
	GameTooltip:AddLine(string.format("Match: %.2f", row.r) .. "  (1 = always up and down on the same days, 0 = no link, " ..
		"-1 = always the opposite way)", 1, 1, 1, true)
	GameTooltip:AddLine("From " .. row.changes .. " day-to-day changes on the " .. row.shared .. " days both had a price " ..
		"(the last " .. rangeOf() .. " days).", 0.6, 0.6, 0.6, true)
	GameTooltip:AddLine("Moving together does not prove one causes the other.", 0.6, 0.6, 0.6, true)
	GameTooltip:Show()
end

-- a table with a "+ Compare" button on every row and the match numbers in the row hover
local function makeTable(page, w, h)
	local tbl = K.Table(page, w, h, COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	for i, rf in ipairs(tbl.rows) do
		local b = K.Flat(rf, COLUMNS[#COLUMNS][2] - 8, ROW_H - 4)
		b:SetPoint("LEFT", rf, "LEFT", COMPARE_X, 0)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function()
			local row = tbl.items[tbl.offset + i]
			if row then addToCompare(page, row.key) end
		end)
		b:SetScript("OnEnter", function(self)
			local row = tbl.items[tbl.offset + i]
			local _, state = compareLabel(row and row.key)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:AddLine("Compare")
			GameTooltip:AddLine((state == "on" and "This item is on the Compare page already (take it off there with its x)." or
				state == "full" and ("The Compare page has " .. (X.COMPARE_MAX or 4) .. " more items already: take one off there first.") or
				"Puts this item on the Compare page's graph next to the item picked."), 1, 1, 1, true)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rf.compare = b
	end
	-- after every draw (sorting, scrolling, new rows): the button labels and the row hovers
	local draw = tbl.Refresh
	function tbl:Refresh()
		draw(self)
		for i, rf in ipairs(self.rows) do
			local row = self.items[self.offset + i]
			if row then
				rf.compare:SetLabel((compareLabel(row.key)))
				rf:SetScript("OnEnter", function(f) rowTip(f, row) end)
			end
		end
	end
	return tbl
end

local function build(page, w, h)
	page.ranges = {}
	for i, d in ipairs(X.RELATED_RANGES) do
		local b = K.Flat(page, 60, 18)
		b:SetPoint("TOPLEFT", (i - 1) * 64, 0)
		b:SetLabel(d .. " days")
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().relatedRange = d fill(page, UI.itemKey) end)
		K.Tooltip(b, d .. " days", "Compares the price changes of the last " .. d .. " days." .. (d > 60 and
			" (Older than 60 days XNAH keeps one price a week, so those days count as weekly changes.)" or ""))
		page.ranges[d] = b
	end
	page.note = K.Label(page, "", "GameFontHighlightSmall", "RIGHT")
	page.note:SetPoint("TOPRIGHT", 0, -3)
	page.note:SetWidth(w - 140)
	page.note:SetWordWrap(false)
	page.about = K.Label(page, GREY .. "Items whose price went up and down on the same days as this one, from one day to " ..
		"the next (only days both had a price). Moving together does not prove that one causes the other: both may " ..
		"just follow the same thing, like a new patch, a busy weekend or the same farmers.|r", "GameFontHighlightSmall")
	page.about:SetPoint("TOPLEFT", 0, -24)
	page.about:SetWidth(w)
	page.title1 = K.Label(page, "Moves together", "GameFontNormal")
	page.title1:SetPoint("TOPLEFT", 0, -58)
	for i, c in ipairs(COLUMNS) do c.tip = COLUMN_TIPS[i] end -- the hover line of each column title
	page.together = makeTable(page, w, X.RELATED_TOGETHER * ROW_H + 4)
	page.together:SetPoint("TOPLEFT", 0, -92)
	page.together:SortBy(2, true)
	local y2 = -92 - (X.RELATED_TOGETHER * ROW_H + 4) - 10
	page.title2 = K.Label(page, "Moves the opposite way", "GameFontNormal")
	page.title2:SetPoint("TOPLEFT", 0, y2)
	page.opposite = makeTable(page, w, X.RELATED_OPPOSITE * ROW_H + 4)
	page.opposite:SetPoint("TOPLEFT", 0, y2 - 34)
	page.opposite:SortBy(2, true)
	page.hint = K.Label(page, GREY .. "Click an item to show it, right-click for more. + Compare puts it on the Compare " ..
		"page's graph next to this item.|r", "GameFontHighlightSmall")
	page.hint:SetPoint("TOPLEFT", 0, y2 - 34 - (X.RELATED_OPPOSITE * ROW_H + 4) - 8)
	page.hint:SetWidth(w)
	page.hint:SetWordWrap(false)
end

local function rowsOf(list)
	local rows = {}
	for _, m in ipairs(list or {}) do
		local it = X.Items()[m.key]
		rows[#rows + 1] = {key = m.key, r = m.r, low = m.low, shared = m.shared, changes = m.changes,
			name = (X.ItemName(m.key) or m.key):lower(), price = X.Price(m.key, "mkt"), stale = it and not X.Fresh(it),
			c7 = X.PriceChange and X.PriceChange(m.key, 7), c30 = X.PriceChange and X.PriceChange(m.key, 30)}
	end
	return rows
end

fill = function(page, key)
	if not key then return end
	local days = rangeOf()
	for d, b in pairs(page.ranges) do b:SetSelected(d == days) end
	local res, busy, progress = X.Related(key, days, function(done, text)
		if not (page:IsVisible() and UI.itemKey == key and rangeOf() == days) then return end
		if done then fill(page, key) elseif text then page.note:SetText(GREY .. text .. "|r") end
	end)
	-- the line at the top right
	local note
	if page.msg then
		note, page.msg = page.msg, nil
	elseif busy then
		note = GREY .. (progress or "Working...") .. (res and " (showing the last result)" or "") .. "|r"
	elseif res and res.tooFew then
		note = GREY .. "Not enough prices of this item yet.|r"
	elseif res and (res.flat or res.fewListed) then
		note = ""
	elseif res and (res.have or 0) < FEW_DAYS then
		note = GOLD .. "Only " .. (res.have or 0) .. " days of prices so far: a match can still be chance. It gets " ..
			"surer with every week.|r"
	elseif res then
		note = GREY .. "Compared with " .. X.Num(res.compared or 0) .. " items that had a price on at least " ..
			X.RELATED_MIN_SHARED .. " of the same days.|r"
	end
	page.note:SetText(note or "")
	-- the tables
	local e1, e2 = "", ""
	if not res then
		e1, e2 = "Working it out...", ""
	elseif res.tooFew then
		e1 = "Not enough prices of this item yet: it needs a price on at least " .. X.RELATED_MIN_SHARED .. " days of the " ..
			"last " .. days .. " (it has " .. (res.have or 0) .. "). Scans on more days bring them."
	elseif res.flat then
		e1 = "This item's price hardly moved in the last " .. days .. " days, so no other item can be matched with it."
	elseif res.fewListed then
		e1 = "Only about " .. X.Num(res.fewListed) .. " of this item are listed on a typical day: its price jumps whenever " ..
			"one sells or one is put up, so it cannot be matched with other items."
	else
		e1 = "No item moved together with this one clearly enough. More days of prices help" ..
			(days < 90 and " - or try 90 days." or ".")
		e2 = "No item moved clearly the opposite way."
	end
	page.together:SetRows(res and rowsOf(res.together) or {}, e1)
	page.opposite:SetRows(res and rowsOf(res.opposite) or {}, e2)
end

UI.AddItemPage("related", "Moves with", build, function(page, key) fill(page, key) end, 6,
	"Other items whose prices rise and fall on the same days as this one (ore and its bars, a herb and its potion), " ..
	"and ones that move the opposite way. Moving together does not prove one causes the other.")
