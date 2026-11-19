-- The Home tab (the first tab): what to do today. Numbers and jobs come from Home.lua.
-- Layout (940 x 550): five number cards on top (gold of all characters, sales today, sales of the last 7 days, net
-- worth, the last full scan) - a click opens the tab with the details. Below on the left the to-do list, most urgent
-- first, one button per job (it opens the right tab, or does a safe thing like starting a scan; it never buys, posts
-- or cancels). On the right the best sellers of the last 7 days and today's trading; at the bottom a check box: open
-- the window on this page the first time each session.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local CARD_W, CARD_H, GAP = 180, 76, 10
local TOP = CARD_H + 12        -- where the lower half starts
local JOB_W = 600              -- the to-do list
local JOB_H = 40               -- one job
local MAX_JOBS = 10
local RX = JOB_W + 20          -- the right column
local RW = W - RX              -- 320
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- refresh when Home.lua or parts the window does not watch changed
for _, e in ipairs({"XNAH_HOME", "XNAH_STRATEGY", "XNAH_CANCEL", "XNAH_SNIPE", "XNAH_POSTED"}) do
	X.On(e, function() if UI.current == "home" then UI.Refresh() end end)
end

-- "+12g" green, "-3g" red, "0" grey
local function signed(v)
	if v == nil then return NONE end
	if v == 0 then return GREY .. "0|r" end
	if v > 0 then return "|cff4ade80+|r" .. X.Money(v, true) end
	return X.Money(v, true)
end
local function units(n, one, many) return X.Num(n) .. " " .. (n == 1 and one or many) end

-- [[ a number card ]]
local function card(p, i, title, tip, tab)
	local c = CreateFrame("Button", nil, p, "BackdropTemplate")
	c:SetSize(CARD_W, CARD_H)
	c:SetPoint("TOPLEFT", (i - 1) * (CARD_W + GAP), 0)
	K.Backdrop(c, K.colors.panel)
	local hi = c:CreateTexture(nil, "HIGHLIGHT")
	hi:SetAllPoints()
	hi:SetColorTexture(K.colors.rowHi[1], K.colors.rowHi[2], K.colors.rowHi[3], 0.12)
	c.title = K.Label(c, GREY .. title .. "|r", "GameFontHighlightSmall")
	c.title:SetPoint("TOPLEFT", 10, -8)
	c.value = K.Label(c, "", "GameFontNormalLarge")
	c.value:SetPoint("TOPLEFT", 10, -24)
	c.value:SetWidth(CARD_W - 20)
	c.value:SetWordWrap(false)
	c.sub1 = K.Label(c, "", "GameFontHighlightSmall")
	c.sub1:SetPoint("TOPLEFT", 10, -46)
	c.sub2 = K.Label(c, "", "GameFontHighlightSmall")
	c.sub2:SetPoint("TOPLEFT", 10, -59)
	for _, fs in ipairs({c.sub1, c.sub2}) do
		fs:SetWidth(CARD_W - 20)
		fs:SetWordWrap(false)
	end
	c:SetScript("OnClick", function() UI.Open(tab) end)
	K.Tooltip(c, title, tip)
	return c
end

-- [[ one job of the to-do list ]]
local function doJob(job)
	if not job then return end
	if job.action then
		local ok, err = pcall(job.action)
		if not ok then X.OnError(err) end
	end
	if job.tab then
		UI.Open(job.tab)
		local tab = UI.tabs[job.tab]
		if job.view then
			local ok, err = pcall(job.view, tab and tab.panel)
			if not ok then X.OnError(err) end
			UI.Refresh(true)
		end
	else
		UI.Refresh()
	end
end
local function jobRow(p, i)
	local r = K.Panel(p, JOB_W, JOB_H - 4, {1, 1, 1, 0.04})
	r:SetPoint("TOPLEFT", 0, -(TOP + 22 + (i - 1) * JOB_H))
	K.Backdrop(r, {1, 1, 1, 0.04}, {0, 0, 0, 0})
	local bar = r:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(WHITE)
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetWidth(3)
	bar:SetVertexColor(K.colors.accent[1], K.colors.accent[2], K.colors.accent[3], 0.9)
	r.bar = bar
	r.text = K.Label(r, "", "GameFontHighlight")
	r.text:SetPoint("TOPLEFT", 12, -4)
	r.why = K.Label(r, "", "GameFontDisableSmall")
	r.why:SetPoint("TOPLEFT", 12, -21)
	for _, fs in ipairs({r.text, r.why}) do
		fs:SetWidth(JOB_W - 150)
		fs:SetWordWrap(false)
	end
	r.button = K.Button(r, "", 110, 22, function(self) doJob(self:GetParent().job) end)
	r.button:SetPoint("RIGHT", -8, 0)
	r:Hide()
	return r
end

local TOP_COLS = {
	{"Item", 160, "LEFT", text = function(r) return r.key and UI.ItemCell(r.key) or ("|cffffffff" .. tostring(r.name or "?") .. "|r") end,
		sort = function(r) return r.key and (X.ItemName(r.key)) or tostring(r.name) end, desc = false},
	{"Sold", 50, "RIGHT", text = function(r) return X.Num(r.units) end, sort = function(r) return r.units end},
	{"Earned", 90, "RIGHT", text = function(r) return X.Money(r.income, true) end, sort = function(r) return r.income end},
}
local function onTopRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

local function refresh(p)
	local n = X.HomeNumbers()
	-- the cards
	local c = p.cards
	c[1].value:SetText(X.Money(n.gold or 0, true))
	c[1].sub1:SetText(GREY .. "Today|r " .. signed(n.goldToday))
	if (n.goldDays or 1) <= 1 then
		c[1].sub2:SetText(GREY .. "Counting from today|r")
	else
		c[1].sub2:SetText(GREY .. ((n.goldDays or 7) >= 7 and "Last 7 days" or ("Last " .. n.goldDays .. " days")) .. "|r " .. signed(n.goldWeek))
	end
	local td, wk = n.today, n.week
	c[2].value:SetText(X.Money(td.income, true))
	c[2].sub1:SetText(GREY .. units(td.units, "item", "items") .. " sold|r")
	c[2].sub2:SetText(GREY .. "Spent|r " .. (td.spent > 0 and X.Money(td.spent, true) or NONE))
	c[3].value:SetText(X.Money(wk.income, true))
	c[3].sub1:SetText(GREY .. units(wk.units, "item", "items") .. " sold|r")
	c[3].sub2:SetText(GREY .. "Profit|r " .. signed(n.profitWeek))
	c[4].value:SetText(n.worth and X.Money(n.worth, true) or NONE)
	c[4].sub1:SetText(GREY .. "Last 7 days|r " .. signed(n.worthWeek))
	c[4].sub2:SetText(GREY .. "Gold and items, all characters|r")
	if n.scanning then
		c[5].value:SetText("|cffffd100Scanning ...|r")
		c[5].sub1:SetText(GREY .. (X.scan.text or "") .. "|r")
	else
		c[5].value:SetText(n.lastFull and X.Ago(n.lastFull) or "|cffff8080never|r")
		c[5].sub1:SetText(GREY .. "Next full scan|r " .. (n.scanLeft > 0 and X.Clock(n.scanLeft) or "|cff4ade80now|r"))
	end
	c[5].sub2:SetText(n.ahOpen and "|cff4ade80Auction house open|r" or (GREY .. "Auction house closed|r"))

	-- the to-do list
	local jobs = X.HomeTodo()
	p.jobTitle:SetText("What to do today" .. GREY .. "  (" .. units(#jobs == 1 and jobs[1].id == "nothing" and 0 or #jobs, "job", "jobs") .. ")|r")
	for i, r in ipairs(p.jobs) do
		local job = jobs[i]
		r.job = job
		r:SetShown(job ~= nil)
		if job then
			r.text:SetText(job.text or "")
			r.why:SetText(job.why or "")
			r.button:SetText(job.button or "Open")
			r.button:SetShown(job.button ~= nil)
			if job.id == "nothing" then r.bar:SetVertexColor(0.3, 0.8, 0.4, 0.9)
			else r.bar:SetVertexColor(K.colors.accent[1], K.colors.accent[2], K.colors.accent[3], 0.9) end
		end
	end

	-- best sellers and today
	p.top:SetRows(n.top or {}, "No sales in the last 7 days. XNAH reads sales from your mailbox.")
	local lines = {}
	lines[#lines + 1] = GREY .. "Sold|r  " .. units(td.units, "item", "items") .. (td.units > 0 and (" for " .. X.Money(td.income, true)) or "")
	lines[#lines + 1] = GREY .. "Bought|r  " .. units(td.bought, "item", "items") .. (td.bought > 0 and (" for " .. X.Money(td.spent, true)) or "")
	lines[#lines + 1] = GREY .. "Expired|r  " .. X.Num(td.expired) .. GREY .. "    Cancelled|r  " .. X.Num(td.cancelled)
	lines[#lines + 1] = GREY .. "Gold, all characters|r  " .. signed(n.goldToday)
	if n.best then
		lines[#lines + 1] = " "
		lines[#lines + 1] = GREY .. "Best seller this week|r"
		lines[#lines + 1] = (n.best.key and UI.ItemCell(n.best.key) or tostring(n.best.name)) .. GREY .. "  -  |r" ..
			X.Money(n.best.income, true) .. GREY .. " (" .. X.Num(n.best.units) .. " sold)|r"
	end
	p.today:SetText(table.concat(lines, "\n"))
	p.first:SetChecked(X.S().homeFirst and true or false)
end

local function build(p)
	p.cards = {
		card(p, 1, "Gold, all characters", "Gold of all your characters of this realm and faction, and how it changed today " ..
			"and over the last 7 days (as far as XNAH has seen it: a character counts from the first time XNAH saw it). Click for tab Wealth.", "wealth"),
		card(p, 2, "Sales today", "What your auctions brought today after the auction house cut, and what you spent on " ..
			"auctions. Read from the auction house mails in your mailbox. Click for tab Ledger.", "ledger"),
		card(p, 3, "Sales, last 7 days", "What your auctions brought over the last 7 days after the cut. Profit = sales " ..
			"minus what you bought on the auction house in that time. Click for tab Ledger.", "ledger"),
		card(p, 4, "Net worth", "Gold plus the items of all your characters at auction house prices, and the change over " ..
			"the last 7 days. Click for tab Wealth.", "wealth"),
		card(p, 5, "Last full scan", "When XNAH last read every auction, and when the server allows the next full scan. " ..
			"Click for tab Scan.", "scan"),
	}
	p.jobTitle = K.Label(p, "", "GameFontNormal")
	p.jobTitle:SetPoint("TOPLEFT", 2, -(TOP + 2))
	p.jobs = {}
	for i = 1, MAX_JOBS do p.jobs[i] = jobRow(p, i) end

	local title = K.Label(p, "Best sellers, last 7 days", "GameFontNormal")
	title:SetPoint("TOPLEFT", RX, -(TOP + 2))
	p.top = K.Table(p, RW, 5 * 18 + 6, TOP_COLS, onTopRow)
	p.top:SetPoint("TOPLEFT", RX, -(TOP + 38))
	p.top:SortBy(3, true)
	local tTitle = K.Label(p, "Today", "GameFontNormal")
	tTitle:SetPoint("TOPLEFT", RX, -(TOP + 150))
	p.today = K.Label(p, "", "GameFontHighlightSmall")
	p.today:SetPoint("TOPLEFT", RX + 2, -(TOP + 170))
	p.today:SetWidth(RW - 4)
	p.today:SetSpacing(4)

	p.first = K.Check(p, "Open XNAH on this page first each session", function(on) X.S().homeFirst = on end)
	p.first:SetPoint("BOTTOMLEFT", RX - 2, 0)
	K.Tooltip(p.first, "Start on Home", "When on, the first time you open XNAH after logging in it shows this page. " ..
		"Later it opens on the page you used last.")
end

UI.AddTab("home", "Home", build, refresh, 0.5)
