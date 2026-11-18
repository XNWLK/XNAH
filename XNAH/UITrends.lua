-- The Trends tab, three views:
--   Price and supply: four short lists of items whose price or supply is moving - when to sell, when to wait
--     (needs a few days of history per item, setting minSamples, and a fresh price).
--   Best time to post: at which hours of the day the auction house sells most (estimate from full scans).
--   Few sellers / walls: items with one or few sellers, or a big block of units at one price.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local GAP = 10
local VIEW_H = 30 -- the view buttons on top
local QW, QH = (W - GAP) / 2, (H - VIEW_H - GAP) / 2 -- one quarter of the price and supply view: 465 x 255
local LIMIT = 50

local VIEWS = {
	{key = "moves", title = "Price and supply", w = 150},
	{key = "hours", title = "Best time to post", w = 150},
	{key = "sellers", title = "Few sellers / walls", w = 150},
}

local BOXES = {
	{kind = "up", title = "Rising prices",
		help = "The price went up over the last two weeks (change = % per week). A good time to sell what you hold."},
	{kind = "down", title = "Falling prices",
		help = "The price went down over the last two weeks (% per week). Sell soon, or wait and buy cheap later."},
	{kind = "short", title = "Supply dropped (chance to sell)",
		help = "Far fewer listed than usual this week while the price holds: list yours now, the buyers have little choice."},
	{kind = "flood", title = "Flooded (wait before selling)",
		help = "Far more listed than usual this week: prices are under pressure. Wait a few days before selling."},
}

-- the lists, worked out again only when prices changed (or a minute passed: prices get old)
local data, dirty, madeAt = {}, true, 0
local sellersData, sellersDirty = nil, true
X.On("XNAH_PRICES", function() dirty = true sellersDirty = true end)
X.On("XNAH_ANALYSIS", function()
	sellersDirty = true
	UI.Refresh()
end)

local function field(name) return function(r) return r[name] end end
local function onRow(row, button, rowFrame)
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

local function columns(kind)
	local supply = kind == "short" or kind == "flood"
	return {
		{"Item", supply and 185 or 215, "LEFT", text = function(r) return UI.ItemCell(r.key) end,
			sort = function(r) return (X.ItemName(r.key)) end, desc = false},
		{"Price", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.price) end, sort = field("price")},
		{supply and "Supply" or "Change", 70, "RIGHT",
			text = function(r)
				if supply then return X.Pct(r.supply, true) end -- fewer listed = green (good for a seller)
				return X.Pct(r.trend)
			end,
			sort = function(r) return supply and r.supply or r.trend end, desc = kind ~= "down" and kind ~= "short"},
		{supply and "Listed / usual" or "Listed", supply and 95 or 65, "RIGHT",
			text = function(r)
				local now = r.qty and X.Num(r.qty) or "-"
				if supply then return now .. " |cff999999/ " .. (r.qty7 and X.Num(r.qty7) or "-") .. "|r" end
				return now
			end,
			sort = field("qty")},
	}
end

local SELLER_COLUMNS = {
	{"Item", 320, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return (X.ItemName(r.key)) end, desc = false},
	{"Sellers", 80, "RIGHT", text = function(r) return r.sellers and X.Num(r.sellers) or "|cff666666-|r" end, sort = field("sellers"), desc = false},
	{"Top seller share", 120, "RIGHT", text = function(r) return r.top and string.format("%.0f%%", r.top * 100) or "|cff666666-|r" end, sort = field("top")},
	{"Wall at", 120, "RIGHT", text = function(r) return UI.MoneyCell(r.wallP) end, sort = field("wallP")},
	{"Wall units", 90, "RIGHT", text = function(r) return r.wallU and X.Num(r.wallU) or "|cff666666-|r" end, sort = field("wallU")},
	{"Lowest price", 120, "RIGHT", text = function(r) return UI.MoneyCell(r.min) end, sort = field("min")},
}

-- [[ the views ]]
local function refreshMoves(p)
	if dirty or (GetTime() - madeAt) > 60 then
		for _, b in ipairs(BOXES) do data[b.kind] = X.Movers(b.kind, LIMIT) end
		dirty, madeAt = false, GetTime()
	end
	local n = X.S().minSamples
	local empty
	if next(X.Items()) == nil then
		empty = "No prices yet. Open the auction house and press Full scan (tab Scan)."
	else
		empty = "Nothing here yet. Needs at least " .. n .. " days of scans per item (one full scan a day is enough) " ..
			"and a fresh price."
	end
	for _, b in ipairs(BOXES) do
		local rows = data[b.kind] or {}
		p.tables[b.kind]:SetRows(rows, empty)
		p.counts[b.kind]:SetText(#rows >= LIMIT and ("top " .. LIMIT) or (X.Num(#rows) .. (#rows == 1 and " item" or " items")))
	end
end

local BAR_H = 300
local function refreshHours(p)
	local share, minutes = {}, {}
	if X.BestHours then share, minutes = X.BestHours() end
	local best, watched = 0, 0
	for h = 0, 23 do
		if (share[h] or 0) > best then best = share[h] end
		if (minutes[h] or 0) > 0 then watched = watched + 1 end
	end
	-- the three best hours, in words
	local order = {}
	for h = 0, 23 do if (share[h] or 0) > 0 then order[#order + 1] = h end end
	table.sort(order, function(a, b) return share[a] > share[b] end)
	for h = 0, 23 do
		local bar = p.bars[h]
		local s = share[h] or 0
		local hgt = best > 0 and math.max(1, BAR_H * s / best) or 1
		bar.fill:SetHeight(hgt)
		local top3 = order[1] == h or order[2] == h or order[3] == h
		if top3 then bar.fill:SetColorTexture(0.29, 0.87, 0.5, 0.9)
		elseif (minutes[h] or 0) > 0 then bar.fill:SetColorTexture(0.9, 0.71, 0.13, 0.75)
		else bar.fill:SetColorTexture(0.4, 0.4, 0.4, 0.4) end
		bar.value:SetText((minutes[h] or 0) > 0 and string.format("%.0f%%", s * 100) or "|cff666666-|r")
	end
	local info = X.speedInfo or X.Realm().speedLast
	local lines = {}
	if #order == 0 then
		lines[1] = "|cffffd100Not known yet.|r This needs two full scans an hour or more apart (up to 4 hours) in one session, " ..
			"better many on different days and hours."
	else
		local names = {}
		for i = 1, math.min(3, #order) do names[i] = string.format("%02d:00", order[i]) end
		lines[1] = "Most sales: |cff4ade80" .. table.concat(names, ", ") .. "|r (your clock). Post an hour or two before."
	end
	lines[2] = "|cff999999Hours watched: " .. watched .. " of 24 (grey bars: never watched). Share of all sales seen per hour watched. " ..
		"An estimate: auctions gone before their time count as sold, so cancelled ones count too.|r"
	if info and info.t then
		lines[3] = "|cff999999Last measured: " .. X.Date(info.from, "%H:%M") .. " to " .. X.Date(info.t, "%H:%M") .. ", " ..
			X.Num(info.units or 0) .. " units seen sold over " .. X.Num(info.items or 0) .. " items.|r"
	end
	p.hoursText:SetText(table.concat(lines, "\n"))
end

local function refreshSellers(p)
	if sellersDirty or not sellersData then
		sellersData = X.FewSellers and X.FewSellers() or {}
		sellersDirty = false
	end
	p.sellerTable:SetRows(sellersData, "Nothing yet. Walls come from full scans; sellers from looking at an item on the " ..
		"auction house (the full scan has no seller names on Forever) - a watch list scan does that for many items.")
	p.sellerCount:SetText(X.Num(#sellersData) .. (#sellersData == 1 and " item" or " items"))
end

local function refresh(p)
	for _, v in ipairs(VIEWS) do
		p.viewButtons[v.key]:SetSelected(v.key == p.view)
		p.views[v.key]:SetShown(v.key == p.view)
	end
	if p.view == "moves" then refreshMoves(p)
	elseif p.view == "hours" then refreshHours(p)
	else refreshSellers(p) end
end

-- [[ building ]]
local function buildMoves(p, area)
	p.tables, p.counts = {}, {}
	for i, b in ipairs(BOXES) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local box = CreateFrame("Frame", nil, area)
		box:SetSize(QW, QH)
		box:SetPoint("TOPLEFT", col * (QW + GAP), -row * (QH + GAP))
		local title = K.Label(box, b.title, "GameFontNormal")
		title:SetPoint("TOPLEFT", 0, 0)
		local count = K.Label(box, "", "GameFontDisableSmall", "RIGHT")
		count:SetPoint("TOPRIGHT", 0, -1)
		count:SetWidth(100)
		p.counts[b.kind] = count
		local help = K.Label(box, b.help)
		help:SetPoint("TOPLEFT", 0, -17)
		help:SetWidth(QW - 4)
		help:SetWordWrap(true)
		local tbl = K.Table(box, QW, QH - 56, columns(b.kind), onRow)
		tbl:SetPoint("TOPLEFT", 0, -56)
		p.tables[b.kind] = tbl
	end
end

local function buildHours(p, area)
	local title = K.Label(area, "Best time to post: share of the sales in each hour of the day", "GameFontNormal")
	title:SetPoint("TOPLEFT", 0, 0)
	local chart = K.Panel(area, W, BAR_H + 50, {0, 0, 0, 0.35})
	chart:SetPoint("TOPLEFT", 0, -22)
	local bw = math.floor((W - 20) / 24)
	p.bars = {}
	for h = 0, 23 do
		local bar = CreateFrame("Frame", nil, chart)
		bar:SetSize(bw - 6, BAR_H + 40)
		bar:SetPoint("BOTTOMLEFT", 10 + h * bw, 4)
		bar.fill = bar:CreateTexture(nil, "ARTWORK")
		bar.fill:SetPoint("BOTTOMLEFT", 0, 16)
		bar.fill:SetWidth(bw - 6)
		bar.fill:SetHeight(1)
		bar.fill:SetColorTexture(0.4, 0.4, 0.4, 0.4)
		bar.label = K.Label(bar, string.format("%02d", h), "GameFontHighlightSmall", "CENTER")
		bar.label:SetPoint("BOTTOM", 0, 2)
		bar.label:SetWidth(bw)
		bar.value = K.Label(bar, "", "GameFontDisableSmall", "CENTER")
		bar.value:SetPoint("BOTTOM", bar.fill, "TOP", 0, 2)
		bar.value:SetWidth(bw)
		p.bars[h] = bar
	end
	p.hoursText = K.Label(area, "", "GameFontHighlightSmall")
	p.hoursText:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -10)
	p.hoursText:SetWidth(W)
	p.hoursText:SetWordWrap(true)
end

local function buildSellers(p, area)
	local title = K.Label(area, "Few sellers / walls", "GameFontNormal")
	title:SetPoint("TOPLEFT", 0, 0)
	p.sellerCount = K.Label(area, "", "GameFontDisableSmall", "RIGHT")
	p.sellerCount:SetPoint("TOPRIGHT", 0, -1)
	p.sellerCount:SetWidth(120)
	local help = K.Label(area, "One seller holding most of an item can set its price; a wall (many units at one price) " ..
		"is what you must undercut. Sellers counted from item searches; the share of units is a guess when several sell at one price.")
	help:SetPoint("TOPLEFT", 0, -18)
	help:SetWidth(W)
	help:SetWordWrap(true)
	p.sellerTable = K.Table(area, W, H - VIEW_H - 80, SELLER_COLUMNS, onRow)
	p.sellerTable:SetPoint("TOPLEFT", 0, -58)
	p.sellerTable:SortBy(3, true)
end

local function build(p)
	p.view = "moves"
	p.viewButtons, p.views = {}, {}
	local x = 0
	for _, v in ipairs(VIEWS) do
		local b = K.Flat(p, v.w, 22)
		b:SetPoint("TOPLEFT", x, 0)
		b:SetLabel(v.title)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() p.view = v.key refresh(p) end)
		p.viewButtons[v.key] = b
		x = x + v.w + 4
		local area = CreateFrame("Frame", nil, p)
		area:SetPoint("TOPLEFT", 0, -VIEW_H)
		area:SetSize(W, H - VIEW_H)
		p.views[v.key] = area
	end
	buildMoves(p, p.views.moves)
	buildHours(p, p.views.hours)
	buildSellers(p, p.views.sellers)
end

UI.AddTab("trends", "Trends", build, refresh, 5)
