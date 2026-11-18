-- The Deals tab: five lists of ways to make gold from what is listed right now.
--   Under usual price: listings far under their usual price - buy them, sell them again later at the usual price.
--   Under vendor price: listings cheaper than what a vendor pays - buy them and sell them to any vendor, no risk.
--   Vendor to auction house: things a vendor sells that go for more on the auction house.
--   Under disenchant value: gear listed for less than its disenchanting materials bring (needs a disenchanter).
--   Reset chances: everything listed far under the usual price of an item, bought up and listed again at the usual price.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 96 -- where the tables start (their column titles sit just above)
local MAX_SEARCH = 50

-- "hide items that sell under N a day" (Under usual price)
X.Default("dealSpeedHide", false)
X.Default("dealSpeedMin", 1)

local VIEWS = {
	{key = "deals", title = "Under usual price", w = 128,
		help = "Listed far under their usual price (the 30-day average): buy them now and sell them again at the usual price."},
	{key = "vendor", title = "Under vendor price", w = 128,
		help = "Listed for less than a vendor pays for them: buy them and sell them to any vendor. No risk."},
	{key = "flips", title = "Vendor to auction house", w = 160,
		help = "Things a vendor sells that go for more on the auction house: buy them from the vendor and list them."},
	{key = "de", title = "Under disenchant value", w = 158,
		help = "Gear listed for less than its disenchanting materials bring. Worth it if you or a friend can disenchant."},
	{key = "resets", title = "Reset chances", w = 110,
		help = "Buy every unit listed under 80% of the usual price and list them again at the usual price. Others may undercut."},
}

-- [[ the lists, worked out again only when prices changed (or a minute passed: prices get old) ]]
local data, dirty, madeAt = {}, {}, {}
local function markDirty() for _, v in ipairs(VIEWS) do dirty[v.key] = true end end
markDirty()
X.On("XNAH_PRICES", markDirty)
X.On("XNAH_ANALYSIS", function()
	markDirty()
	UI.Refresh()
end)

local function rowsFor(view)
	if dirty[view] or not data[view] or (GetTime() - (madeAt[view] or 0)) > 60 then
		if view == "deals" then
			data[view] = X.Deals()
			for _, r in ipairs(data[view]) do r.rate = X.SaleRate and X.SaleRate(r.key) or nil end
		elseif view == "vendor" then data[view] = X.BelowVendor()
		elseif view == "flips" then data[view] = X.VendorFlips()
		elseif view == "de" then data[view] = X.UnderDE and X.UnderDE() or {}
		else data[view] = X.Resets and X.Resets() or {} end
		dirty[view], madeAt[view] = false, GetTime()
	end
	local rows = data[view]
	-- the speed filter: items known to sell slower than N a day are left out (unknown speed: shown)
	local S = X.S()
	if view == "deals" and S.dealSpeedHide then
		local out = {}
		for _, r in ipairs(rows) do
			if not r.rate or r.rate >= (S.dealSpeedMin or 0) then out[#out + 1] = r end
		end
		rows = out
	end
	return rows
end

-- [[ cells ]]
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end
local function count(r) return r.qty and X.Num(r.qty) or "-" end
-- sells per day (an estimate): "-" when not known yet
function UI.RateText(rate)
	if not rate then return "|cff666666-|r" end
	if rate >= 10 then return X.Num(rate) end
	if rate >= 0.1 then return string.format("%.1f", rate) end
	return "|cff999999<0.1|r"
end
local function rate(r) return UI.RateText(r.rate) end
local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

local COLUMNS = {
	deals = {
		{"Item", 290, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Listed at", 100, "RIGHT", text = money("buy"), sort = field("buy"), desc = false},
		{"Usual price", 100, "RIGHT", text = money("usual"), sort = field("usual")},
		{"% of usual", 75, "RIGHT", text = function(r) return string.format("%.0f%%", r.pct) end, sort = field("pct"), desc = false},
		{"Profit after cut", 110, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Listed", 60, "RIGHT", text = count, sort = field("qty")},
		{"Sells/day", 75, "RIGHT", text = rate, sort = field("rate")},
		{"Days of data", 80, "RIGHT", text = function(r) return tostring(r.days or "-") end, sort = field("days")},
	},
	vendor = {
		{"Item", 380, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Listed at", 130, "RIGHT", text = money("buy"), sort = field("buy"), desc = false},
		{"Vendor pays", 130, "RIGHT", text = money("sell"), sort = field("sell")},
		{"Profit each", 130, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Listed", 90, "RIGHT", text = count, sort = field("qty")},
	},
	flips = {
		{"Item", 330, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Vendor price", 110, "RIGHT", text = money("buy"), sort = field("buy"), desc = false},
		{"Sells for (after cut)", 140, "RIGHT", text = money("sell"), sort = field("sell")},
		{"Profit each", 110, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Margin %", 80, "RIGHT", text = function(r) return X.Pct(r.pct) end, sort = field("pct")},
		{"Limited stock", 100, "RIGHT", text = function(r) return r.lim and "|cffffd100yes|r" or "|cff999999no|r" end,
			sort = function(r) return r.lim and 1 or 0 end},
	},
	de = {
		{"Item", 330, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Listed at", 110, "RIGHT", text = money("buy"), sort = field("buy"), desc = false},
		{"Disenchant value", 120, "RIGHT",
			text = function(r) return UI.MoneyCell(r.de) .. ((r.missing or 0) > 0 and " |cffff9933?|r" or "") end, sort = field("de")},
		{"Profit after cut", 120, "RIGHT", text = money("profit"), sort = field("profit")},
		{"% of value", 90, "RIGHT", text = function(r) return string.format("%.0f%%", r.pct) end, sort = field("pct"), desc = false},
		{"Listed", 80, "RIGHT", text = count, sort = field("qty")},
	},
	resets = {
		{"Item", 300, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Units to buy", 95, "RIGHT", text = function(r) return X.Num(r.units) end, sort = field("units")},
		{"Cost", 120, "RIGHT", text = money("cost"), sort = field("cost")},
		{"Usual", 115, "RIGHT", text = money("usual"), sort = field("usual")},
		{"Profit after cut", 120, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Sells per day", 100, "RIGHT", text = rate, sort = field("rate")},
	},
}

-- [[ what to say when a list is empty ]]
local NO_PRICES = "No prices yet. Open the auction house and press Full scan (tab Scan)."
local function emptyText(view)
	local S = X.S()
	if next(X.Items()) == nil and view ~= "flips" then return NO_PRICES end
	if view == "deals" then
		return "No deals with these limits right now. A deal needs a price from the last " .. S.staleHours ..
			" hours (a full scan) and at least " .. S.minSamples .. " days of price history for the item (scan once a day). " ..
			"Try a higher % or a lower minimum profit."
	elseif view == "vendor" then
		return "Nothing is listed under what a vendor pays right now. Every full scan checks again " ..
			"(prices older than " .. S.staleHours .. " hours are not used)."
	elseif view == "de" then
		return "No gear is listed under its disenchanting value right now. Needs fresh prices of the gear and of the " ..
			"materials (dusts, essences, shards): a full scan."
	elseif view == "resets" then
		return "No reset chances right now. Each full scan looks for items with units listed under 80% of their usual " ..
			"price (needs " .. S.minSamples .. "+ days of history) that sell again within about 5 days."
	end
	if next(X.db.vbuy) == nil then
		return "XNAH does not know any vendor items yet. Open a vendor's window (any merchant) and XNAH remembers what " ..
			"it sells and for how much. Then scan the auction house."
	end
	return "None of the vendor items XNAH knows sells for more on the auction house right now. Needs fresh auction " ..
		"prices (a full scan); visit more vendors to add their items."
end

-- [[ the tab ]]
local function refresh(p)
	local S = X.S()
	local view = p.view
	for _, v in ipairs(VIEWS) do
		p.viewButtons[v.key]:SetSelected(v.key == view)
		p.tables[v.key]:SetShown(v.key == view)
	end
	p.help:SetText(p.helpText[view])
	p.controls:SetShown(view == "deals")
	p.note:SetShown(view == "de" or view == "resets")
	if view == "de" then
		p.note:SetText("|cff999999Classic disenchanting chances (Forever may differ). Each material at its price; " ..
			"|cffff9933?|r|cff999999 = a material has no price yet (counted as 0).|r")
	elseif view == "resets" then
		p.note:SetText("|cff999999Sales speed is an estimate from two full scans (cancelled auctions look like sales). " ..
			"Profit = units x usual price after the cut - cost.|r")
	end
	if not p.pctBox:HasFocus() then p.pctBox:SetText(tostring(S.dealPct)) end
	if not p.profitBox:HasFocus() then p.profitBox:SetText(X.MoneyPlain(S.dealMinProfit)) end
	if not p.speedBox:HasFocus() then p.speedBox:SetText(tostring(S.dealSpeedMin)) end
	p.speedCheck:SetChecked(S.dealSpeedHide and true or false)
	local rows = rowsFor(view)
	local tbl = p.tables[view]
	tbl:SetRows(rows, emptyText(view))
	p.count:SetText(#rows == 1 and "1 item" or (X.Num(#rows) .. " items"))
	p.search:SetShown(X.ahOpen == true)
	p.search:SetEnabled(#rows > 0 and X.scan.state == "idle")
end

local function build(p)
	p.view = "deals"
	p.helpText = {}
	p.viewButtons = {}
	p.tables = {}

	-- the five views
	local x = 0
	for _, v in ipairs(VIEWS) do
		p.helpText[v.key] = v.help
		local b = K.Flat(p, v.w, 22)
		b:SetPoint("TOPLEFT", x, 0)
		b:SetLabel(v.title)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() p.view = v.key refresh(p) end)
		p.viewButtons[v.key] = b
		x = x + v.w + 4
	end

	-- live prices for what is shown
	p.search = K.Button(p, "Search these on the AH", 216, 22, function()
		local tbl = p.tables[p.view]
		local keys = {}
		for i = 1, math.min(MAX_SEARCH, #(tbl.items or {})) do keys[#keys + 1] = tbl.items[i].key end
		if #keys > 0 then X.ScanItems(keys, "deals") end
	end)
	p.search:SetPoint("TOPRIGHT", 0, 0)
	K.Tooltip(p.search, "Search these on the auction house",
		"Searches the first " .. MAX_SEARCH .. " items of this list one by one, in the order shown, to get their live prices " ..
		"(a list can be out of date: someone may have bought them already).")

	-- one plain line about the list
	p.help = K.Label(p, "", "GameFontHighlight")
	p.help:SetPoint("TOPLEFT", 0, -30)
	p.help:SetWidth(W - 120)
	p.help:SetWordWrap(false)
	p.count = K.Label(p, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, -32)
	p.count:SetWidth(110)
	-- a second line for the disenchant and reset views
	p.note = K.Label(p, "", "GameFontHighlightSmall")
	p.note:SetPoint("TOPLEFT", 0, -56)
	p.note:SetWidth(W)
	p.note:SetWordWrap(false)

	-- limits for "Under usual price"
	local c = CreateFrame("Frame", nil, p)
	c:SetPoint("TOPLEFT", 0, -52)
	c:SetSize(W, 24)
	p.controls = c
	local l1 = K.Label(c, "Listed at or under")
	l1:SetPoint("LEFT", 0, 0)
	p.pctBox = K.Edit(c, 36)
	p.pctBox:SetPoint("LEFT", l1, "RIGHT", 8, 0)
	p.pctBox:SetScript("OnEditFocusLost", function(self)
		local v = tonumber((X.Trim(self:GetText()):gsub("%%", "")))
		if v and v > 0 then
			X.S().dealPct = math.min(100, X.Round(v))
			dirty.deals = true
		end
		self:SetText(tostring(X.S().dealPct))
		refresh(p)
	end)
	local l2 = K.Label(c, "% of usual, profit at least")
	l2:SetPoint("LEFT", p.pctBox, "RIGHT", 4, 0)
	p.profitBox = K.Edit(c, 80)
	p.profitBox:SetPoint("LEFT", l2, "RIGHT", 8, 0)
	p.profitBox:SetScript("OnEditFocusLost", function(self)
		local v = X.ParseMoney(self:GetText())
		if v and v >= 0 then
			X.S().dealMinProfit = v
			dirty.deals = true
		end
		self:SetText(X.MoneyPlain(X.S().dealMinProfit))
		refresh(p)
	end)
	K.Tooltip(p.profitBox, "Smallest profit", "Type e.g. 50g or 1g 50s, then Enter. The profit is after the auction house cut.")
	local l3 = K.Label(c, "after the cut.")
	l3:SetPoint("LEFT", p.profitBox, "RIGHT", 4, 0)
	-- hide slow sellers
	p.speedCheck = K.Check(c, "Hide items that sell under", function(on)
		X.S().dealSpeedHide = on
		refresh(p)
	end)
	p.speedCheck:SetPoint("LEFT", l3, "RIGHT", 24, 0)
	K.Tooltip(p.speedCheck, "Hide slow sellers",
		"Leaves out items known to sell fewer than this many a day. The sales speed is an estimate from two full scans " ..
		"up to 4 hours apart (cancelled auctions look like sales, so it can be high). Items whose speed is not known yet stay in the list.")
	p.speedBox = K.Edit(c, 36)
	p.speedBox:SetPoint("LEFT", p.speedCheck.label, "RIGHT", 8, 0)
	p.speedBox:SetScript("OnEditFocusLost", function(self)
		local v = tonumber(X.Trim(self:GetText()))
		if v and v >= 0 then X.S().dealSpeedMin = v end
		self:SetText(tostring(X.S().dealSpeedMin))
		refresh(p)
	end)
	local l4 = K.Label(c, "a day")
	l4:SetPoint("LEFT", p.speedBox, "RIGHT", 4, 0)

	-- one table per view (same place, one shown)
	for _, v in ipairs(VIEWS) do
		local tbl = K.Table(p, W, H - TOP - 20, COLUMNS[v.key], onRow)
		tbl:SetPoint("TOPLEFT", 0, -TOP)
		p.tables[v.key] = tbl
	end

	local hint = K.Label(p, "|cff999999Left click a row: item page.  Right click: menu (watch list, search).  " ..
		"Click a column title to sort.|r")
	hint:SetPoint("BOTTOMLEFT", 0, 2)
end

UI.AddTab("deals", "Deals", build, refresh, 3)
