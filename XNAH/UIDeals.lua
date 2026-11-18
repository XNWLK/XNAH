-- The Deals tab: three lists of ways to make gold from what is listed right now.
--   Under usual price: listings far under their usual price - buy them, sell them again later at the usual price.
--   Under vendor price: listings cheaper than what a vendor pays - buy them and sell them to any vendor, no risk.
--   Vendor to auction house: things a vendor sells that go for more on the auction house.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 96 -- where the tables start (their column titles sit just above)
local MAX_SEARCH = 50

local VIEWS = {
	{key = "deals", title = "Under usual price", w = 150,
		help = "Listed far under their usual price (the 30-day average): buy them now and sell them again at the usual price."},
	{key = "vendor", title = "Under vendor price", w = 150,
		help = "Listed for less than a vendor pays for them: buy them and sell them to any vendor. No risk."},
	{key = "flips", title = "Vendor to auction house", w = 170,
		help = "Things a vendor sells that go for more on the auction house: buy them from the vendor and list them."},
}

-- [[ the lists, worked out again only when prices changed (or a minute passed: prices get old) ]]
local data, dirty, madeAt = {}, {}, {}
local function markDirty() dirty.deals, dirty.vendor, dirty.flips = true, true, true end
markDirty()
X.On("XNAH_PRICES", markDirty)

local function rowsFor(view)
	if dirty[view] or not data[view] or (GetTime() - (madeAt[view] or 0)) > 60 then
		if view == "deals" then data[view] = X.Deals()
		elseif view == "vendor" then data[view] = X.BelowVendor()
		else data[view] = X.VendorFlips() end
		dirty[view], madeAt[view] = false, GetTime()
	end
	return data[view]
end

-- [[ cells ]]
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end
local function count(r) return r.qty and X.Num(r.qty) or "-" end
local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

local COLUMNS = {
	deals = {
		{"Item", 350, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Listed at", 105, "RIGHT", text = money("buy"), sort = field("buy"), desc = false},
		{"Usual price", 105, "RIGHT", text = money("usual"), sort = field("usual")},
		{"% of usual", 80, "RIGHT", text = function(r) return string.format("%.0f%%", r.pct) end, sort = field("pct"), desc = false},
		{"Profit after cut", 115, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Listed", 70, "RIGHT", text = count, sort = field("qty")},
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
}

-- [[ what to say when a list is empty ]]
local NO_PRICES = "No prices yet. Open the auction house and press Full scan (tab Scan & settings)."
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
	if not p.pctBox:HasFocus() then p.pctBox:SetText(tostring(S.dealPct)) end
	if not p.profitBox:HasFocus() then p.profitBox:SetText(X.MoneyPlain(S.dealMinProfit)) end
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

	-- the three views
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
	p.search = K.Button(p, "Search these on the auction house", 240, 22, function()
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

	-- limits for "Under usual price"
	local c = CreateFrame("Frame", nil, p)
	c:SetPoint("TOPLEFT", 0, -52)
	c:SetSize(W, 24)
	p.controls = c
	local l1 = K.Label(c, "Show listings at or under")
	l1:SetPoint("LEFT", 0, 0)
	p.pctBox = K.Edit(c, 40)
	p.pctBox:SetPoint("LEFT", l1, "RIGHT", 10, 0)
	p.pctBox:SetScript("OnEditFocusLost", function(self)
		local v = tonumber((X.Trim(self:GetText()):gsub("%%", "")))
		if v and v > 0 then
			X.S().dealPct = math.min(100, X.Round(v))
			dirty.deals = true
		end
		self:SetText(tostring(X.S().dealPct))
		refresh(p)
	end)
	local l2 = K.Label(c, "% of the usual price and a profit of at least")
	l2:SetPoint("LEFT", p.pctBox, "RIGHT", 4, 0)
	p.profitBox = K.Edit(c, 90)
	p.profitBox:SetPoint("LEFT", l2, "RIGHT", 10, 0)
	p.profitBox:SetScript("OnEditFocusLost", function(self)
		local v = X.ParseMoney(self:GetText())
		if v and v >= 0 then
			X.S().dealMinProfit = v
			dirty.deals = true
		end
		self:SetText(X.MoneyPlain(X.S().dealMinProfit))
		refresh(p)
	end)
	local l3 = K.Label(c, "after the cut.  |cff999999(type e.g. 50g or 1g 50s, then Enter)|r")
	l3:SetPoint("LEFT", p.profitBox, "RIGHT", 4, 0)

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
