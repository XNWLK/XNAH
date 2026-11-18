-- The Trends tab: four short lists of items whose price or supply is moving - when to sell, when to wait.
-- Trends need a few days of history per item (setting minSamples) and a fresh price.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local GAP = 10
local QW, QH = (W - GAP) / 2, (H - GAP) / 2 -- one quarter: 465 x 270
local LIMIT = 50

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
X.On("XNAH_PRICES", function() dirty = true end)

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

local function refresh(p)
	if dirty or (GetTime() - madeAt) > 60 then
		for _, b in ipairs(BOXES) do data[b.kind] = X.Movers(b.kind, LIMIT) end
		dirty, madeAt = false, GetTime()
	end
	local n = X.S().minSamples
	local empty
	if next(X.Items()) == nil then
		empty = "No prices yet. Open the auction house and press Full scan (tab Scan & settings)."
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

local function build(p)
	p.tables, p.counts = {}, {}
	for i, b in ipairs(BOXES) do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local box = CreateFrame("Frame", nil, p)
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

UI.AddTab("trends", "Trends", build, refresh, 5)
