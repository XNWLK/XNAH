-- The Gold tab: what you earn on the auction house (from its mails in your mailbox) and what your characters own.
-- Four views, picked with the buttons on top:
--   Overview    totals for 7 days / 30 days / all (with auction house time and gold per hour), profit per week as bars,
--               and your flips (items you bought and later sold: profit of one, best first, worst last)
--   By item     what you sold and bought of each item
--   Recent      every auction house mail read, newest first
--   Characters  gold and items of your characters, net worth over time, your bags (UIWealth.lua)
-- Layout (940 x 550): view buttons and a help line (20 high) on top; the view under it from y -28.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local GREEN, RED, GREY = "|cff4ade80", "|cfff87171", "|cff999999"
local NONE = "|cff666666-|r"
local DAY = 86400
local TOP = 28                -- the views start here
local PERIODS = {{"7 days", 7}, {"30 days", 30}, {"All", nil}}
local LINES = {
	{"Income", "income", "What your sales brought, after the auction house's cut."},
	{"Spent", "spent", "What you paid for auctions you won or bought."},
	{"Auction house cut", "cut", "What the auction house kept of your sales."},
	{"Profit", "profit", "Income minus spent."},
	{"Sales", "sales", "Sale mails."},
	{"Purchases", "buys", "Purchase mails."},
	{"Auction house time", "ahtime", "How long the auction house window was open (XNAH counts it from this version on; " ..
		"one visit counts at most 6 hours)."},
	{"Gold per hour", "perhour", "Profit (sales after the cut minus purchases) divided by the hours the auction house " ..
		"window was open. Only days since XNAH started counting the time are used."},
}
local SUMW, LABW, COLW = 340, 112, 74
local WEEKS = 12
local VIEWS = {
	{"overview", "Overview", "Profit = your sales after the auction house cut, minus your purchases."},
	{"items", "By item", "What you sold and bought of each item (from the auction house mails)."},
	{"recent", "Recent", "Every auction house mail XNAH read, newest first."},
	{"chars", "Characters", "Gold and items of your characters on this realm (both factions)."},
}

X.Default("goldView", "overview")

local function M(v) return X.Money(v, true) end
local function signed(v)
	if not v then return NONE end
	if v >= 0 then return GREEN .. "+" .. X.MoneyPlain(X.Round(v)) .. "|r" end
	return RED .. "-" .. X.MoneyPlain(X.Round(-v)) .. "|r"
end
local function hours(secs)
	secs = secs or 0
	if secs < 60 then return NONE end
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	if h == 0 then return m .. "m" end
	return h .. "h " .. string.format("%02d", m) .. "m"
end
local function itemCell(r)
	if r.key then return UI.ItemCell(r.key) end
	return GREY .. (r.name or "?") .. "|r"
end
local function itemSort(r) return r.key and (X.ItemName(r.key)) or r.name or "" end
local function num(n) return (n and n > 0) and X.Num(n) or NONE end
local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

-- [[ the tables ]]
local FLIP_COLS = {
	{"Item", 270, "LEFT", text = itemCell, sort = itemSort, desc = false},
	{"Units", 60, "RIGHT", text = function(r) return X.Num(r.units) end, sort = function(r) return r.units end},
	{"Bought at", 100, "RIGHT", text = function(r) return M(X.Round(r.buyEach)) end, sort = function(r) return r.buyEach end},
	{"Sold at", 100, "RIGHT", text = function(r) return M(X.Round(r.sellEach)) end, sort = function(r) return r.sellEach end},
	{"Profit of one", 110, "RIGHT", text = function(r) return signed(r.each) end, sort = function(r) return r.each end},
	{"Profit %", 70, "RIGHT", text = function(r)
		if not r.pct then return NONE end
		return (r.pct >= 0 and GREEN or RED) .. string.format("%+.0f%%", r.pct * 100) .. "|r"
	end, sort = function(r) return r.pct end},
	{"Total profit", 110, "RIGHT", text = function(r) return signed(r.profit) end, sort = function(r) return r.profit end},
	{"Last sold", 95, "RIGHT", text = function(r) return GREY .. X.Ago(r.last) .. "|r" end, sort = function(r) return r.last end},
}
local ITEM_COLS = {
	{"Item", 320, "LEFT", text = itemCell, sort = itemSort, desc = false},
	{"Sold", 60, "RIGHT", text = function(r) return num(r.sold) end, sort = function(r) return r.sold end},
	{"Avg sale", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.avgSell) end, sort = function(r) return r.avgSell end},
	{"Bought", 60, "RIGHT", text = function(r) return num(r.bought) end, sort = function(r) return r.bought end},
	{"Avg buy", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.avgBuy) end, sort = function(r) return r.avgBuy end},
	{"Profit", 110, "RIGHT", text = function(r) return signed(r.profit) end, sort = function(r) return r.profit end},
	{"Expired", 70, "RIGHT", text = function(r) return num((r.expired or 0) + (r.cancelled or 0)) end,
		sort = function(r) return (r.expired or 0) + (r.cancelled or 0) end},
	{"Sell-through", 95, "RIGHT", text = function(r)
		if not r.sellThrough then return NONE end
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
	{"Item", 300, "LEFT", text = itemCell, sort = itemSort, desc = false},
	{"Count", 60, "RIGHT", text = function(r) return X.Num(r.count or 1) end, sort = function(r) return r.count end},
	{"Money", 130, "RIGHT", text = function(r)
		if not r.money then return NONE end
		if r.what == "bought" then return RED .. "-|r" .. M(r.money) end
		return M(r.money)
	end, sort = function(r) return r.money end},
	{"Character", 160, "LEFT", text = function(r) return r.char or "?" end, sort = function(r) return r.char or "" end, desc = false},
}

-- [[ profit per week ]] a bar chart: green bars over the middle line (profit), red ones under it (loss); hovering a bar
-- tells the week's numbers
local function weekBars(parent, w, h)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(w, h)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.25)
	local title = K.Label(f, "Profit per week " .. GREY .. "(sales after the cut minus purchases; weeks start on Monday)|r",
		"GameFontNormalSmall")
	title:SetPoint("TOPLEFT", 8, -6)
	title:SetWidth(w - 16)
	title:SetWordWrap(false)
	local PT, PB, PX = 26, 20, 8 -- room above, under (week labels) and at the sides
	local ph = h - PT - PB
	local zero = f:CreateTexture(nil, "BORDER")
	zero:SetColorTexture(1, 1, 1, 0.25)
	zero:SetHeight(1)
	f.none = K.Label(f, "", "GameFontDisableSmall", "CENTER")
	f.none:SetPoint("CENTER", 0, -6)
	f.none:SetWidth(w - 20)
	f.slots = {}
	local sw = (w - 2 * PX) / WEEKS
	for i = 1, WEEKS do
		local slot = CreateFrame("Button", nil, f)
		slot:SetSize(sw, ph + PB)
		slot:SetPoint("TOPLEFT", PX + (i - 1) * sw, -PT)
		slot.bar = slot:CreateTexture(nil, "ARTWORK")
		slot.bar:SetWidth(math.max(3, sw * 0.7))
		slot.hi = slot:CreateTexture(nil, "HIGHLIGHT")
		slot.hi:SetAllPoints()
		slot.hi:SetColorTexture(1, 1, 1, 0.06)
		slot.lab = K.Label(slot, "", "GameFontDisableSmall", "CENTER")
		slot.lab:SetPoint("BOTTOM", 0, 3)
		slot.lab:SetWidth(sw + 4)
		slot.lab:SetWordWrap(false)
		slot.cx = PX + (i - 0.5) * sw
		slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
		f.slots[i] = slot
	end
	function f:SetWeeks(weeks)
		local hi, lo = 0, 0
		for _, wk in ipairs(weeks) do
			if wk.profit > hi then hi = wk.profit end
			if wk.profit < lo then lo = wk.profit end
		end
		local span = hi - lo
		local any = span > 0
		local scale = any and (ph - 4) / span or 0
		local zy = -PT - 2 - hi * scale -- y of the middle line
		zero:ClearAllPoints()
		zero:SetPoint("TOPLEFT", PX, zy)
		zero:SetPoint("TOPRIGHT", -PX, zy)
		f.none:SetText(any and "" or "No sales or purchases in the last " .. WEEKS .. " weeks - open your mailbox after selling or buying")
		f.none:SetShown(not any)
		for i, slot in ipairs(f.slots) do
			local wk = weeks[i]
			slot.bar:ClearAllPoints()
			if wk and any and wk.profit ~= 0 then
				local hgt = math.max(1, math.abs(wk.profit) * scale)
				if wk.profit > 0 then
					slot.bar:SetColorTexture(0.29, 0.87, 0.5, 0.9)
					slot.bar:SetPoint("BOTTOM", f, "TOPLEFT", slot.cx, zy)
				else
					slot.bar:SetColorTexture(0.97, 0.44, 0.44, 0.9)
					slot.bar:SetPoint("TOP", f, "TOPLEFT", slot.cx, zy)
				end
				slot.bar:SetHeight(hgt)
				slot.bar:Show()
			else
				slot.bar:Hide()
			end
			slot.lab:SetText(wk and X.Date(wk.start * DAY + 43200, "%b %d") or "")
			slot:SetScript("OnEnter", wk and function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine("Week of " .. X.Date(wk.start * DAY + 43200, "%b %d"))
				GameTooltip:AddDoubleLine("Income (after the cut)", X.Money(wk.income, true), 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("Spent", X.Money(wk.spent, true), 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("Profit", signed(wk.profit), 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("Sales / purchases", wk.sales .. " / " .. wk.buys, 0.6, 0.6, 0.6, 1, 1, 1)
				GameTooltip:AddDoubleLine("Auction house time", hours(wk.seconds), 0.6, 0.6, 0.6, 1, 1, 1)
				if wk.seconds >= 60 then
					GameTooltip:AddDoubleLine("Gold per hour", signed(wk.profit / (wk.seconds / 3600)), 0.6, 0.6, 0.6, 1, 1, 1)
				end
				GameTooltip:Show()
			end or nil)
		end
	end
	return f
end

-- [[ the overview ]]
local function buildOverview(v)
	local sum = K.Panel(v, SUMW, 222, {0, 0, 0, 0.25})
	sum:SetPoint("TOPLEFT", 0, 0)
	for c, per in ipairs(PERIODS) do
		local h = K.Label(sum, per[1], "GameFontNormalSmall", "RIGHT")
		h:SetPoint("TOPLEFT", 8 + LABW + (c - 1) * COLW, -10)
		h:SetWidth(COLW - 4)
	end
	v.cells = {}
	for i, line in ipairs(LINES) do
		local y = -32 - (i - 1) * 23
		local l = K.Label(sum, line[1], "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, y)
		l:SetWidth(LABW)
		l:SetWordWrap(false)
		local hot = CreateFrame("Frame", nil, sum)
		hot:SetPoint("TOPLEFT", 4, y + 4)
		hot:SetSize(LABW, 18)
		hot:EnableMouse(true)
		K.Tooltip(hot, line[1], line[3])
		v.cells[i] = {}
		for c = 1, #PERIODS do
			local cell = K.Label(sum, "", "GameFontHighlightSmall", "RIGHT")
			cell:SetPoint("TOPLEFT", 8 + LABW + (c - 1) * COLW, y)
			cell:SetWidth(COLW - 4)
			cell:SetWordWrap(false)
			v.cells[i][c] = cell
		end
	end
	v.weeks = weekBars(v, W - SUMW - 10, 222)
	v.weeks:SetPoint("TOPLEFT", SUMW + 10, 0)

	local ft = K.Label(v, "Your flips: items you bought and later sold", "GameFontNormal")
	ft:SetPoint("TOPLEFT", 0, -232)
	local fh = K.Label(v, "Profit of one = its sale after the cut minus what you paid (oldest purchase first). Best first, " ..
		"worst last.", "GameFontDisableSmall", "RIGHT")
	fh:SetPoint("TOPRIGHT", 0, -234)
	fh:SetWidth(W - 330)
	fh:SetWordWrap(false)
	local ty = 268
	v.flips = K.Table(v, W, H - TOP - ty, FLIP_COLS, onRow)
	v.flips:SetPoint("TOPLEFT", 0, -ty)
	v.flips:SortBy(5, true)
end

local function refreshOverview(v)
	local now = X.Now()
	for c, per in ipairs(PERIODS) do
		local tot = X.LedgerTotals(per[2] and (now - per[2] * DAY) or nil)
		local gph = X.GoldPerHour(per[2])
		for i, line in ipairs(LINES) do
			local key = line[2]
			local text
			if key == "sales" or key == "buys" then text = X.Num(tot[key])
			elseif key == "profit" then text = signed(tot.profit)
			elseif key == "ahtime" then text = hours(gph.seconds)
			elseif key == "perhour" then text = gph.perHour and signed(gph.perHour) or NONE
			else text = M(tot[key]) end
			v.cells[i][c]:SetText(text)
		end
	end
	v.weeks:SetWeeks(X.LedgerWeeks(WEEKS))
	v.flips:SetRows(X.LedgerFlips(), "No flips yet: an item counts here once you bought it on the auction house and sold " ..
		"it there later (open your mailbox to read the mails).")
end

-- [[ the tab ]]
local function currentView()
	local S = X.S()
	-- an older page asked for the list of recent mails (it set the old setting): open that once
	if S.ledgerView == "recent" then S.goldView = "recent" end
	S.ledgerView = nil
	for _, view in ipairs(VIEWS) do if view[1] == S.goldView then return view end end
	S.goldView = "overview"
	return VIEWS[1]
end

local function refresh(p)
	local view = currentView()
	for key, b in pairs(p.viewButtons) do b:SetSelected(key == view[1]) end
	for key, f in pairs(p.views) do f:SetShown(key == view[1]) end
	p.help:SetText(GREY .. view[3] .. "|r")
	p.count:SetText("")
	local emptyText = "Nothing yet. Open your mailbox: XNAH reads the auction house mails there (sold, bought, expired, cancelled)."
	if view[1] == "overview" then
		refreshOverview(p.views.overview)
	elseif view[1] == "items" then
		local rows = X.LedgerByItem()
		p.views.items.tbl:SetRows(rows, emptyText)
		p.count:SetText(X.Num(#rows) .. (#rows == 1 and " item" or " items"))
	elseif view[1] == "recent" then
		local rows = X.LedgerRecent(500)
		p.views.recent.tbl:SetRows(rows, emptyText)
		p.count:SetText(X.Num(#rows) .. (#rows == 1 and " entry" or " entries") .. (#rows >= 500 and " (latest)" or ""))
	elseif view[1] == "chars" and UI.GoldChars then
		UI.GoldChars.refresh(p.views.chars)
	end
end

local function build(p)
	p.viewButtons, p.views = {}, {}
	local x = 0
	for _, view in ipairs(VIEWS) do
		local key = view[1]
		local b = K.Flat(p, 92, 20)
		b:SetPoint("TOPLEFT", x, 0)
		b:SetLabel(view[2])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().goldView = key refresh(p) end)
		p.viewButtons[key] = b
		x = x + 96
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", 0, -TOP)
		f:SetSize(W, H - TOP)
		f:Hide()
		p.views[key] = f
	end
	p.help = K.Label(p, "", "GameFontDisableSmall")
	p.help:SetPoint("TOPLEFT", x + 6, -4)
	p.help:SetWidth(W - x - 6 - 130)
	p.help:SetWordWrap(false)
	p.count = K.Label(p, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, -4)
	p.count:SetWidth(124)
	p.count:SetWordWrap(false)

	buildOverview(p.views.overview)
	-- the lists: the headers sit just above them
	p.views.items.tbl = K.Table(p.views.items, W, H - TOP - 22, ITEM_COLS, onRow)
	p.views.items.tbl:SetPoint("TOPLEFT", 0, -22)
	p.views.recent.tbl = K.Table(p.views.recent, W, H - TOP - 22, RECENT_COLS, onRow)
	p.views.recent.tbl:SetPoint("TOPLEFT", 0, -22)
	if UI.GoldChars then UI.GoldChars.build(p.views.chars) end
end

X.On("XNAH_LEDGER", function() UI.Refresh() end)
UI.AddTab("gold", "Gold", build, refresh, 7)
