-- Ledger tab: what you sold and bought on the auction house, learned from its mails when you open your mailbox.
-- Layout (940 x 550): one line of help; the totals (left, 340 wide) and a graph of income and spending per day (right);
-- two buttons switch the table below between "By item" and "Recent".
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local GREEN, RED, GREY = "|cff4ade80", "|cfff87171", "|cff999999"
local DAY = 86400
local PERIODS = {{"7 days", 7}, {"30 days", 30}, {"All", nil}}
local LINES = {
	{"Income", "income", "What your sales brought, after the auction house's cut."},
	{"Spent", "spent", "What you paid for auctions you won or bought."},
	{"Auction house cut", "cut", "What the auction house kept of your sales."},
	{"Profit", "profit", "Income minus spent."},
	{"Sales", "sales", "Sale mails."},
	{"Purchases", "buys", "Purchase mails."},
}
local SUMW, LABW, COLW = 340, 100, 78
local TOP = 230 -- where the table area starts

X.Default("ledgerView", "items")

local function M(v) return X.Money(v, true) end
local function signed(v)
	if not v then return "|cff666666-|r" end
	if v >= 0 then return GREEN .. "+" .. X.MoneyPlain(v) .. "|r" end
	return RED .. "-" .. X.MoneyPlain(-v) .. "|r"
end
local function itemCell(r)
	if r.key then return UI.ItemCell(r.key) end
	return GREY .. (r.name or "?") .. "|r"
end
local function num(n) return (n and n > 0) and X.Num(n) or "|cff666666-|r" end
local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

local ITEM_COLS = {
	{"Item", 320, "LEFT", text = itemCell, sort = function(r) return r.key and (X.ItemName(r.key)) or r.name or "" end, desc = false},
	{"Sold", 60, "RIGHT", text = function(r) return num(r.sold) end, sort = function(r) return r.sold end},
	{"Avg sale", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.avgSell) end, sort = function(r) return r.avgSell end},
	{"Bought", 60, "RIGHT", text = function(r) return num(r.bought) end, sort = function(r) return r.bought end},
	{"Avg buy", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.avgBuy) end, sort = function(r) return r.avgBuy end},
	{"Profit", 110, "RIGHT", text = function(r) return signed(r.profit) end, sort = function(r) return r.profit end},
	{"Expired", 70, "RIGHT", text = function(r) return num((r.expired or 0) + (r.cancelled or 0)) end,
		sort = function(r) return (r.expired or 0) + (r.cancelled or 0) end},
	{"Sell-through", 95, "RIGHT", text = function(r)
		if not r.sellThrough then return "|cff666666-|r" end
		local pct = r.sellThrough * 100
		local col = pct >= 60 and GREEN or (pct >= 30 and "|cffffd100" or RED)
		return col .. string.format("%.0f%%", pct) .. "|r"
	end, sort = function(r) return r.sellThrough end},
}
local WHAT = {sold = GREEN .. "sold|r", bought = "|cff8aa4ffbought|r", expired = GREY .. "expired|r", cancelled = GREY .. "cancelled|r"}
local RECENT_COLS = {
	{"When", 120, "LEFT", text = function(r) return X.Date(r.t, "%b %d  %H:%M") end, sort = function(r) return r.t end},
	{"What", 150, "LEFT", text = function(r)
		if r.pending then return GREEN .. "sold|r " .. GREY .. "(money on the way)|r" end
		return WHAT[r.what] or r.what
	end, sort = function(r) return r.what end, desc = false},
	{"Item", 300, "LEFT", text = itemCell, sort = function(r) return r.key and (X.ItemName(r.key)) or r.name or "" end, desc = false},
	{"Count", 60, "RIGHT", text = function(r) return X.Num(r.count or 1) end, sort = function(r) return r.count end},
	{"Money", 130, "RIGHT", text = function(r)
		if not r.money then return "|cff666666-|r" end
		if r.what == "bought" then return RED .. "-|r" .. M(r.money) end
		return M(r.money)
	end, sort = function(r) return r.money end},
	{"Character", 160, "LEFT", text = function(r) return r.char or "?" end, sort = function(r) return r.char or "" end, desc = false},
}

local function setView(p, view)
	X.S().ledgerView = view
	p.items:SetShown(view == "items")
	p.recent:SetShown(view == "recent")
	p.bItems:SetSelected(view == "items")
	p.bRecent:SetSelected(view == "recent")
end

local function refresh(p)
	local now = X.Now()
	-- totals
	for c, per in ipairs(PERIODS) do
		local tot = X.LedgerTotals(per[2] and (now - per[2] * DAY) or nil)
		for i, line in ipairs(LINES) do
			local v = tot[line[2]]
			local text
			if line[2] == "sales" or line[2] == "buys" then text = X.Num(v)
			elseif line[2] == "profit" then text = signed(v)
			else text = M(v) end
			p.cells[i][c]:SetText(text)
		end
	end
	-- graph
	local empty = X.LedgerEmpty()
	if empty then
		p.graph:SetSeries({}, {empty = "No sales or purchases yet - open your mailbox after selling or buying"})
	else
		local inc, spent = {}, {}
		for _, d in ipairs(X.LedgerDays(30)) do
			local t = d.day * DAY + 43200
			inc[#inc + 1] = {t, d.income}
			spent[#spent + 1] = {t, d.spent}
		end
		p.graph:SetSeries({
			{points = inc, color = {0.29, 0.87, 0.5}, width = 2, label = "Income"},
			{points = spent, color = {0.97, 0.44, 0.44}, width = 2, label = "Spent"},
		})
	end
	-- tables
	local emptyText = "Nothing yet. Open your mailbox: XNAH reads the auction house mails there (sold, bought, expired, cancelled)."
	local byItem = X.LedgerByItem()
	p.items:SetRows(byItem, emptyText)
	local recent = X.LedgerRecent(500)
	p.recent:SetRows(recent, emptyText)
	local view = X.S().ledgerView == "recent" and "recent" or "items"
	setView(p, view)
	p.count:SetText(view == "items" and (X.Num(#byItem) .. (#byItem == 1 and " item" or " items")) or
		(X.Num(#recent) .. (#recent == 1 and " entry" or " entries") .. (#recent >= 500 and " (latest)" or "")))
end

local function build(p)
	local help = K.Label(p, "Learns from the auction house mails when you open your mailbox: what you sold, bought, and what " ..
		"came back expired or cancelled.", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 0, 0)
	help:SetWidth(W)
	help:SetWordWrap(false)

	-- [[ totals ]]
	local sum = K.Panel(p, SUMW, 190, {0, 0, 0, 0.25})
	sum:SetPoint("TOPLEFT", 0, -20)
	for c, per in ipairs(PERIODS) do
		local h = K.Label(sum, per[1], "GameFontNormalSmall", "RIGHT")
		h:SetPoint("TOPLEFT", 8 + LABW + (c - 1) * COLW, -10)
		h:SetWidth(COLW - 4)
	end
	p.cells = {}
	for i, line in ipairs(LINES) do
		local y = -32 - (i - 1) * 24
		local l = K.Label(sum, line[1], "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, y)
		l:SetWidth(LABW)
		l:SetWordWrap(false)
		local hot = CreateFrame("Frame", nil, sum)
		hot:SetPoint("TOPLEFT", 4, y + 4)
		hot:SetSize(LABW, 18)
		hot:EnableMouse(true)
		K.Tooltip(hot, line[1], line[3])
		p.cells[i] = {}
		for c = 1, #PERIODS do
			local v = K.Label(sum, "", "GameFontHighlightSmall", "RIGHT")
			v:SetPoint("TOPLEFT", 8 + LABW + (c - 1) * COLW, y)
			v:SetWidth(COLW - 4)
			v:SetWordWrap(false)
			p.cells[i][c] = v
		end
	end

	-- [[ graph ]]
	local gx = SUMW + 10
	local legend = K.Label(p, "Per day, last 30 days:   " .. GREEN .. "Income|r   " .. RED .. "Spent|r", "GameFontHighlightSmall")
	legend:SetPoint("TOPLEFT", gx, -22)
	legend:SetWidth(W - gx)
	p.graph = K.Graph(p, W - gx, 172)
	p.graph:SetPoint("TOPLEFT", gx, -38)

	-- [[ the tables ]]
	p.bItems = K.Flat(p, 90, 20)
	p.bItems:SetPoint("TOPLEFT", 0, -TOP + 10)
	p.bItems:SetLabel("By item")
	p.bItems.label:SetJustifyH("CENTER")
	p.bItems:SetScript("OnClick", function() X.S().ledgerView = "items" refresh(p) end)
	p.bRecent = K.Flat(p, 90, 20)
	p.bRecent:SetPoint("LEFT", p.bItems, "RIGHT", 6, 0)
	p.bRecent:SetLabel("Recent")
	p.bRecent.label:SetJustifyH("CENTER")
	p.bRecent:SetScript("OnClick", function() X.S().ledgerView = "recent" refresh(p) end)
	p.count = K.Label(p, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, -TOP + 6)
	p.count:SetWidth(300)

	local ty = TOP + 32 -- the headers sit just above the list
	p.items = K.Table(p, W, H - ty, ITEM_COLS, onRow)
	p.items:SetPoint("TOPLEFT", 0, -ty)
	-- both lists: the latest first until a header is clicked
	p.recent = K.Table(p, W, H - ty, RECENT_COLS, onRow)
	p.recent:SetPoint("TOPLEFT", 0, -ty)
	p.recent:Hide()
end

X.On("XNAH_LEDGER", function() UI.Refresh() end)
UI.AddTab("ledger", "Ledger", build, refresh, 8)
