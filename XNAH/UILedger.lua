-- Your gold (a view of the XNAH window): read-only numbers about your own trading - from the auction house mails in
-- your mailbox (the sales ledger, Ledger.lua) and what your characters own (Inventory.lua). No buttons that do things.
-- On top, always: number tiles (gold today, gold this week, profit this week, profit of the last 4 weeks, gold per hour
-- at the auction house, net worth and its change this week). Under them small buttons pick the page shown (other files
-- add pages with UI.AddGoldPage, below):
--   Overview      income and spent per day (30 days, a graph), profit per week (12 weeks, bars), totals for 7 days /
--                 30 days / all, and your flips (items you bought and later sold: best first, worst last)
--   Best sellers  what you sold and bought of each item (sold, income, average price, sell-through)
--   Recent        every auction house mail read, newest first (sales, purchases, expired, cancelled)
--   Characters    gold and items of your characters, net worth over time, your bags (UIWealth.lua)
--   Gold over time  gold per character and in all, net worth, profit per week and its trend (UIGoldHistory.lua)
--   Your items    your results per item: profit, time to sell, sell-through (UIGoldItems.lua)
-- Layout (UI.W x UI.H, read when the view is built): tiles 46 high; page buttons at y -54; the page under them from
-- y -TOP (1080 x 520).
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREEN, RED, GREY = "|cff4ade80", "|cfff87171", "|cff999999"
local NONE = "|cff666666-|r"
local DAY = 86400
local TOP = 80                -- the parts start here (under the tiles and chips)
local PERIODS = {{"7 days", 7}, {"30 days", 30}, {"All", nil}}
local LINES = {
	{"Income", "income", "What your sales brought, after the auction house's cut."},
	{"Spent", "spent", "What you paid for auctions you won or bought."},
	{"Auction house cut", "cut", "What the auction house kept of your sales."},
	{"Profit", "profit", "Income minus spent."},
	{"Sales", "sales", "Sale mails."},
	{"Purchases", "buys", "Purchase mails."},
	{"Auction house time", "ahtime", "How long the auction house window was open (one visit counts at most 6 hours)."},
	{"Gold per hour", "perhour", "Profit (sales after the cut minus purchases) divided by the hours the auction house " ..
		"window was open. Only days since XNAH started counting the time are used."},
}
local SUMW, LABW, COLW = 340, 112, 74
local LINE_H = 21
local WEEKS, DAYS = 12, 30
local GH = 200                -- height of the graphs row of the overview
local VIEWS = {
	{"overview", "Overview", "Profit = your sales after the auction house cut, minus your purchases."},
	{"items", "Best sellers", "What you sold and bought of each item (from the auction house mails)."},
	{"recent", "Recent", "Every auction house mail XNAH read, newest first."},
}
local TILES = {
	{"Gold today", "How much the gold of all your characters here changed today (from the first time XNAH saw it " ..
		"today). Next to it: their gold now."},
	{"Gold this week", "How much the gold of all your characters here changed over the last 7 days."},
	{"Profit this week", "Your auction house sales of the last 7 days after the cut, minus what you bought there."},
	{"Profit, 4 weeks", "The same over the last 28 days."},
	{"Gold per AH hour", "Profit of the last 30 days divided by the hours the auction house window was open."},
	{"Net worth", "Gold and items of all your characters here (and the account bank), items at their auction house " ..
		"price after the cut. Next to it: the change this week."},
}

X.Default("goldView", "overview")

local function M(v) return X.Money(v, true) end
-- money without colours, short (no copper above 1g)
local function plain(v) return (X.Money(v, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function signed(v)
	if not v then return NONE end
	if v >= 0 then return GREEN .. "+" .. plain(X.Round(v)) .. "|r" end
	return RED .. "-" .. plain(X.Round(-v)) .. "|r"
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
-- the item column takes the room the others leave (the list keeps 20 for its edges and scroll bar)
local function fit(columns, w)
	local fixed = 0
	for i = 2, #columns do fixed = fixed + columns[i][2] end
	local out = {}
	for i, c in ipairs(columns) do out[i] = c end
	local first = columns[1]
	out[1] = {first[1], math.max(140, w - 20 - fixed), first[3], text = first.text, sort = first.sort, desc = first.desc,
		tip = first.tip}
	return out
end
-- the hover line of each column title: tips = {text, ...} in the order of the columns
local function addTips(columns, tips)
	for i, c in ipairs(columns) do c.tip = tips[i] end
	return columns
end

-- [[ the tables ]]
local FLIP_COLS = {
	{"Item", 200, "LEFT", text = itemCell, sort = itemSort, desc = false},
	{"Units", 44, "RIGHT", text = function(r) return X.Num(r.units) end, sort = function(r) return r.units end},
	{"Bought at", 74, "RIGHT", text = function(r) return M(X.Round(r.buyEach)) end, sort = function(r) return r.buyEach end},
	{"Sold at", 74, "RIGHT", text = function(r) return M(X.Round(r.sellEach)) end, sort = function(r) return r.sellEach end},
	{"Profit of one", 80, "RIGHT", text = function(r) return signed(r.each) end, sort = function(r) return r.each end},
	{"%", 46, "RIGHT", text = function(r)
		if not r.pct then return NONE end
		return (r.pct >= 0 and GREEN or RED) .. string.format("%+.0f%%", r.pct * 100) .. "|r"
	end, sort = function(r) return r.pct end},
	{"Total", 80, "RIGHT", text = function(r) return signed(r.profit) end, sort = function(r) return r.profit end},
}
addTips(FLIP_COLS, {
	"An item you bought on the auction house and later sold there again.",
	"How many you bought and then sold again (units you farmed or crafted are not counted here).",
	"What you paid for one, on average.",
	"What one sale brought, on average, after the auction house cut.",
	"Sold at minus bought at: what you made on each one. Green: a gain. Red: a loss.",
	"The profit as a share of what you paid: +50% = you got back what you paid and half of it again.",
	"The profit of all of them together.",
})
local function sellThrough(r)
	if not r.sellThrough then return NONE end
	local pct = r.sellThrough * 100
	local col = pct >= 60 and GREEN or (pct >= 30 and "|cffffd100" or RED)
	return col .. string.format("%.0f%%", pct) .. "|r"
end
local ITEM_COLS = {
	{"Item", 260, "LEFT", text = itemCell, sort = itemSort, desc = false},
	{"Sold", 56, "RIGHT", text = function(r) return num(r.sold) end, sort = function(r) return r.sold end},
	{"Income", 96, "RIGHT", text = function(r) return (r.soldValue or 0) > 0 and M(r.soldValue) or NONE end,
		sort = function(r) return r.soldValue end},
	{"Avg price", 86, "RIGHT", text = function(r) return UI.MoneyCell(r.avgSell and X.Round(r.avgSell)) end,
		sort = function(r) return r.avgSell end},
	{"Sold a day", 70, "RIGHT", text = function(r)
		if not r.soldPerDay or r.soldPerDay <= 0 then return NONE end
		return X.Rate(r.soldPerDay)
	end, sort = function(r) return r.soldPerDay end},
	{"Bought", 56, "RIGHT", text = function(r) return num(r.bought) end, sort = function(r) return r.bought end},
	{"Avg buy", 86, "RIGHT", text = function(r) return UI.MoneyCell(r.avgBuy and X.Round(r.avgBuy)) end,
		sort = function(r) return r.avgBuy end},
	{"Profit", 96, "RIGHT", text = function(r) return signed(r.profit) end, sort = function(r) return r.profit end},
	{"Expired", 60, "RIGHT", text = function(r) return num((r.expired or 0) + (r.cancelled or 0)) end,
		sort = function(r) return (r.expired or 0) + (r.cancelled or 0) end},
	{"Sell-through", 80, "RIGHT", text = sellThrough, sort = function(r) return r.sellThrough end},
	{"Last", 70, "RIGHT", text = function(r) return (r.last or 0) > 0 and (GREY .. X.Ago(r.last) .. "|r") or NONE end,
		sort = function(r) return r.last end},
}
addTips(ITEM_COLS, {
	"Every item you sold or bought on the auction house (from the mails XNAH read in your mailbox).",
	"How many you sold.",
	"What your sales of it brought, after the auction house cut.",
	"What one sold for, on average, after the auction house cut.",
	"How many you sold a day over the last 30 days.",
	"How many you bought.",
	"What you paid for one, on average.",
	"What your sales brought after the cut, minus what the ones you sold cost you (at your average buying price). " ..
		"Ones you farmed or crafted cost nothing here.",
	"How many came back to you unsold: ran out (expired) or taken down by you (cancelled).",
	"Of all you put up, the share that sold: sold / (sold + expired + cancelled). Green: 60% or more. Yellow: 30% or " ..
		"more. Red: under 30%.",
	"When the last mail about it came (a sale, a purchase or one that came back).",
})
local WHAT ={sold = GREEN .. "sold|r", bought = "|cff8aa4ffbought|r", expired = GREY .. "expired|r", cancelled = GREY .. "cancelled|r"}
local RECENT_COLS = {
	{"Item", 300, "LEFT", text = itemCell, sort = itemSort, desc = false},
	{"When", 120, "LEFT", text = function(r) return X.Date(r.t, "%b %d  %H:%M") end, sort = function(r) return r.t end},
	{"What", 160, "LEFT", text = function(r)
		if r.pending then return GREEN .. "sold|r " .. GREY .. "(money on the way)|r" end
		return WHAT[r.what] or r.what
	end, sort = function(r) return r.what end, desc = false},
	{"Count", 56, "RIGHT", text = function(r) return X.Num(r.count or 1) end, sort = function(r) return r.count end},
	{"Money", 120, "RIGHT", text = function(r)
		if not r.money then return NONE end
		if r.what == "bought" then return RED .. "-|r" .. M(r.money) end
		return M(r.money)
	end, sort = function(r) return r.money end},
	{"Each", 96, "RIGHT", text = function(r)
		if not r.money or (r.count or 1) < 2 then return NONE end
		return M(X.Round(r.money / r.count))
	end, sort = function(r) return r.money and r.money / math.max(1, r.count or 1) end},
	{"Character", 150, "LEFT", text = function(r) return r.char or "?" end, sort = function(r) return r.char or "" end, desc = false},
}
addTips(RECENT_COLS, {
	"The item the mail is about.",
	"When the mail came (your computer's clock).",
	"sold: one of your auctions sold (\"money on the way\": the money mail has not come yet). bought: you won or bought " ..
		"an auction. expired: it ran out unsold and came back. cancelled: you took it down.",
	"How many were in it.",
	"A sale: what it brought after the auction house cut. A purchase (minus): what you paid.",
	"The money of one, when there were 2 or more.",
	"The character whose mailbox got the mail.",
})

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

-- [[ the overview ]] graphs row (income and spent per day | profit per week), then totals (left) and flips (right)
local function buildOverview(v, W, h)
	local half = math.floor((W - 10) / 2)
	local dt = K.Label(v, "Income and spent per day " .. GREY .. "(last " .. DAYS .. " days; " .. GREEN .. "income|r" .. GREY ..
		" after the cut, " .. RED .. "spent|r" .. GREY .. ")|r", "GameFontNormalSmall")
	dt:SetPoint("TOPLEFT", 4, -2)
	dt:SetWidth(half - 8)
	dt:SetWordWrap(false)
	v.days = K.Graph(v, half, GH - 18)
	v.days:SetPoint("TOPLEFT", 0, -18)
	v.weeks = weekBars(v, W - half - 10, GH)
	v.weeks:SetPoint("TOPLEFT", half + 10, 0)

	local y = GH + 8
	local sumH = 26 + #LINES * LINE_H + 4
	local sum = K.Panel(v, SUMW, sumH, {0, 0, 0, 0.25})
	sum:SetPoint("TOPLEFT", 0, -y)
	for c, per in ipairs(PERIODS) do
		local h = K.Label(sum, per[1], "GameFontNormalSmall", "RIGHT")
		h:SetPoint("TOPLEFT", 8 + LABW + (c - 1) * COLW, -8)
		h:SetWidth(COLW - 4)
	end
	v.cells = {}
	for i, line in ipairs(LINES) do
		local ly = -26 - (i - 1) * LINE_H
		local l = K.Label(sum, line[1], "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, ly)
		l:SetWidth(LABW)
		l:SetWordWrap(false)
		local hot = CreateFrame("Frame", nil, sum)
		hot:SetPoint("TOPLEFT", 4, ly + 4)
		hot:SetSize(LABW, 18)
		hot:EnableMouse(true)
		K.Tooltip(hot, line[1], line[3])
		v.cells[i] = {}
		for c = 1, #PERIODS do
			local cell = K.Label(sum, "", "GameFontHighlightSmall", "RIGHT")
			cell:SetPoint("TOPLEFT", 8 + LABW + (c - 1) * COLW, ly)
			cell:SetWidth(COLW - 4)
			cell:SetWordWrap(false)
			v.cells[i][c] = cell
		end
	end

	local fx = SUMW + 10
	local fw = W - fx
	local ft = K.Label(v, "Your flips " .. GREY .. "(bought, then sold; profit of one = its sale after the cut minus what " ..
		"you paid; best first)|r", "GameFontNormalSmall")
	ft:SetPoint("TOPLEFT", fx, -y)
	ft:SetWidth(fw)
	ft:SetWordWrap(false)
	local ty = y + 34
	v.flips = K.Table(v, fw, math.max(60, h - ty), fit(FLIP_COLS, fw), onRow)
	v.flips:SetPoint("TOPLEFT", fx, -ty)
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
	-- the daily graph: a line for the income and one for the spending (nothing at all: the empty text)
	local inc, spent, any = {}, {}, false
	for _, d in ipairs(X.LedgerDays(DAYS)) do
		local t = d.day * DAY + 43200
		inc[#inc + 1] = {t, d.income}
		spent[#spent + 1] = {t, d.spent}
		if d.income ~= 0 or d.spent ~= 0 then any = true end
	end
	v.days:SetSeries(any and {
		{points = inc, color = {0.29, 0.87, 0.5}, width = 2, label = "Income"},
		{points = spent, color = {0.97, 0.44, 0.44}, width = 2, label = "Spent"},
	} or {}, {empty = "No sales or purchases in the last " .. DAYS .. " days - open your mailbox after selling or buying"})
	v.weeks:SetWeeks(X.LedgerWeeks(WEEKS))
	v.flips:SetRows(X.LedgerFlips(), "No flips yet: an item counts here once you bought it on the auction house and sold " ..
		"it there later (open your mailbox to read the mails).")
end

-- [[ the tiles ]]
local function refreshTiles(p)
	local t = p.tiles
	local n = X.GoldNumbers()
	UI.SetTile(t[1], n.goldToday and signed(n.goldToday) or nil, n.gold and plain(n.gold) or nil)
	UI.SetTile(t[2], n.goldWeek and signed(n.goldWeek) or nil, n.goldWeek and n.goldDays and (n.goldDays .. (n.goldDays == 1 and " day" or " days")) or nil)
	UI.SetTile(t[3], signed(n.profitWeek), X.Num(n.week and n.week.units or 0) .. " sold")
	local four = X.LedgerTotals(X.Now() - 28 * DAY)
	UI.SetTile(t[4], signed(four.profit), X.Num(four.sales) .. " sales")
	local gph = X.GoldPerHour(30)
	UI.SetTile(t[5], gph.perHour and signed(gph.perHour) or nil, gph.seconds >= 60 and (hours(gph.seconds) .. " at the AH") or "no time yet")
	local change = n.worthWeek and ((n.worthWeek >= 0 and "+" or "-") .. plain(math.abs(X.Round(n.worthWeek))) .. " this week")
	UI.SetTile(t[6], n.worth and M(n.worth) or nil, change)
end

-- [[ the pages ]] UI.AddGoldPage(key, title, build(page, w, h), refresh(page) -> text, order, help)
-- Adds a page to the Your gold view (call it when the file loads). The page is a frame of the area under the tiles and
-- the page buttons: w x h = 1080 x 520 (UI.W x UI.H - 80). build(page, w, h) runs once when the view is first opened;
-- refresh(page) runs whenever the view refreshes while the page is shown (picked, new mails, new prices ...) and may
-- return a short text for the top right ("12 items"). help = the grey line shown next to the buttons. Pages here:
-- overview 1, items 2 ("Best sellers"), recent 3, chars 4 ("Characters", UIWealth.lua), history 5 ("Gold over time",
-- UIGoldHistory.lua), results 6 ("Your items", UIGoldItems.lua); new ones from 7 on.
local PAGES = UI.PageSet()
function UI.AddGoldPage(key, title, build, refresh, order, help)
	UI.AddPageTo(PAGES, key, title, build, refresh, order, help)
end
UI.GOLD_PAGES = PAGES
-- the pages the view had before others could add theirs: their tables keep remembering their sorting as before
local OLD_PAGES = {overview = true, items = true, recent = true, chars = true}

local EMPTY = "Nothing yet. Open your mailbox: XNAH reads the auction house mails there (sold, bought, expired, cancelled)."
UI.AddGoldPage("overview", VIEWS[1][2], function(f, w, h) buildOverview(f, w, h) end, function(f)
	refreshOverview(f)
end, 1, VIEWS[1][3])
UI.AddGoldPage("items", VIEWS[2][2], function(f, w, h)
	-- the lists: the headers sit just above them
	f.tbl = K.Table(f, w, h - 20, fit(ITEM_COLS, w), onRow)
	f.tbl:SetPoint("TOPLEFT", 0, -20)
	f.tbl:SortBy(3, true) -- income, most first
end, function(f)
	local rows = X.LedgerByItem()
	f.tbl:SetRows(rows, EMPTY)
	return X.Num(#rows) .. (#rows == 1 and " item" or " items")
end, 2, VIEWS[2][3])
UI.AddGoldPage("recent", VIEWS[3][2], function(f, w, h)
	f.tbl = K.Table(f, w, h - 20, fit(RECENT_COLS, w), onRow)
	f.tbl:SetPoint("TOPLEFT", 0, -20)
	f.tbl:SortBy(2, true) -- newest first
end, function(f)
	local rows = X.LedgerRecent(500)
	f.tbl:SetRows(rows, EMPTY)
	return X.Num(#rows) .. (#rows == 1 and " entry" or " entries") .. (#rows >= 500 and " (latest)" or "")
end, 3, VIEWS[3][3])

-- [[ the view ]]
local function currentKey()
	local S = X.S()
	-- an older page asked for the list of recent mails (it set the old setting): open that once
	if S.ledgerView == "recent" then S.goldView = "recent" end
	S.ledgerView = nil
	for _, pg in ipairs(PAGES) do if pg.key == S.goldView then return pg.key end end
	S.goldView = PAGES[1] and PAGES[1].key or "overview"
	return S.goldView
end

local function refresh(p)
	local page = UI.ShowPage(p.bar, currentKey())
	p.help:SetText(page and page.help and (GREY .. page.help .. "|r") or "")
	p.count:SetText("")
	refreshTiles(p)
	local text = UI.RefreshPage(p.bar, page)
	p.count:SetText(type(text) == "string" and text or "")
end

local function build(p)
	local W, H = UI.W, UI.H
	p.tiles = UI.NumberTiles(p, W, TILES, 0)
	local cy = -54
	p.bar = UI.PageBar(p, PAGES, {x = 0, y = cy, px = 0, py = -TOP, pw = W, ph = H - TOP, name = "gold", shared = OLD_PAGES,
		pick = function(key) X.S().goldView = key refresh(p) end})
	-- p.views[key] = the frame of each page, p.viewButtons[key] = its button
	p.views, p.viewButtons = p.bar.frames, p.bar.buttons
	local x = p.bar.right
	p.help = K.Label(p, "", "GameFontDisableSmall")
	p.help:SetPoint("TOPLEFT", x + 6, cy - 4)
	p.help:SetWidth(math.max(40, W - x - 6 - 130))
	p.help:SetWordWrap(false)
	p.count = K.Label(p, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, cy - 4)
	p.count:SetWidth(124)
	p.count:SetWordWrap(false)
end

X.On("XNAH_LEDGER", function() UI.Refresh() end)
UI.AddTab("gold", "Your gold", build, refresh, 3)
