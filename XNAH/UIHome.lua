-- The Home tab (the first tab): what to do today. Numbers and the checklist come from Home.lua.
-- Layout (940 x 550): five number cards on top (gold of all characters, sales today, sales of the last 7 days, net
-- worth, the last full scan) - a click opens the tab with the details. Below on the left "Today": one big Next step
-- button (the same as the Next step key, Next.lua) and the checklist of the day - scan, mail, cancel, post, buy,
-- craft - each with a green tick when done, the first open one lit up, and its own button (it opens the right tab, or
-- does a safe thing like starting a scan; only the big button buys, posts, cancels, crafts or takes mail). On the right
-- the best sellers of the last 7 days and today's trading; at the bottom a check box: open the window on this page the
-- first time each session.
--   UI.DoNextButton(parent, w, h) -> the big Next step button for any page: its label is what the next press does
--     (X.DoNextPeek); a click does that ONE step, and only that: when the next step changed since the label was drawn,
--     the click only shows the new one.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local CARD_W, CARD_H, GAP = 180, 76, 10
local TOP = CARD_H + 12        -- where the lower half starts
local JOB_W = 600              -- the checklist
local NEXT_H = 40              -- the big Next step button
local LIST_TOP = TOP + 22 + NEXT_H + 26 -- where the checklist starts
local STEP_H = 46              -- one step of the checklist
local MAX_STEPS = 7
local RX = JOB_W + 20          -- the right column
local RW = W - RX              -- 320
local WHITE = "Interface\\Buttons\\WHITE8x8"
local TICK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:18:18|t"

-- refresh when Home.lua or parts the window does not watch changed
for _, e in ipairs({"XNAH_HOME", "XNAH_STRATEGY", "XNAH_CANCEL", "XNAH_SNIPE", "XNAH_POSTED", "XNAH_QUEUE", "XNAH_SHOP", "XNAH_MAIL"}) do
	X.On(e, function() if UI.current == "home" then UI.Refresh() end end)
end

-- [[ the Next step button for any page ]]
local nextButtons = setmetatable({}, {__mode = "k"})
local function updateNext(btn)
	local p = X.DoNextPeek()
	btn.shownText = p.text
	btn:SetText(p.text or "Next step")
	btn:SetEnabled(p.act == true)
end
function UI.UpdateNextButtons()
	for btn in pairs(nextButtons) do
		if btn:IsVisible() then
			local ok, err = pcall(updateNext, btn)
			if not ok then X.OnError(err) end
		end
	end
end
for _, e in ipairs({"XNAH_NEXT", "XNAH_BUY", "XNAH_ROUTINE", "XNAH_POST", "XNAH_CANCEL", "XNAH_SCAN", "XNAH_QUEUE", "XNAH_BUYIDEAS",
	"XNAH_LIVE", "XNAH_AH", "PLAYER_MONEY"}) do
	X.On(e, function() if next(nextButtons) then X.Debounce("xnah-next-buttons", 0.15, UI.UpdateNextButtons) end end)
end
-- the key set for the Next step key, as text (nil = none)
function UI.NextKeyText()
	local key = GetBindingKey and GetBindingKey("XNAH_NEXT")
	return key and tostring(key) or nil
end

function UI.DoNextButton(parent, w, h)
	local btn = K.Button(parent, "Next step", w or 300, h or NEXT_H)
	nextButtons[btn] = true
	local fs = btn:GetFontString()
	if fs then
		fs:SetWidth((w or 300) - 16)
		fs:SetWordWrap(true)
	end
	btn:SetScript("OnClick", function(self)
		X.DoNext("button", self.shownText) -- the game allows buying, posting, crafting only from a click: this is it
		updateNext(self)
		UI.Refresh()
	end)
	btn:SetScript("OnShow", function(self) updateNext(self) end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Next step")
		GameTooltip:AddLine("Does what the button says: one step per click. At your profession window it crafts your queue, " ..
			"at a mailbox it takes the next auction house mail, at the auction house it finishes a purchase, cancels your " ..
			"undercut auctions, posts what is worth posting, then buys your lists and the queue's materials.", 1, 1, 1, true)
		local key = UI.NextKeyText()
		GameTooltip:AddLine(key and ("Your Next step key: " .. key) or
			"Set a key for it: the game's key bindings, AddOns, XNAH, Next step.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	updateNext(btn)
	return btn
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

-- [[ one step of the checklist ]] its button does what the to-do job did: open a tab, or a safe action
local function doJob(job)
	if not job then return end
	if job.action then
		local ok, err = pcall(job.action)
		if not ok then X.OnError(err) end
	end
	if job.tab then
		UI.Open(job.tab)
		local tab = UI.tabs[UI.TabKey and UI.TabKey(job.tab) or job.tab]
		if job.view then
			local ok, err = pcall(job.view, tab and tab.panel)
			if not ok then X.OnError(err) end
			UI.Refresh(true)
		end
	else
		UI.Refresh()
	end
end
local function stepRow(p, i)
	local r = K.Panel(p, JOB_W, STEP_H - 4, {1, 1, 1, 0.04})
	r:SetPoint("TOPLEFT", 0, -(LIST_TOP + (i - 1) * STEP_H))
	K.Backdrop(r, {1, 1, 1, 0.04}, {0, 0, 0, 0})
	local bar = r:CreateTexture(nil, "ARTWORK")
	bar:SetTexture(WHITE)
	bar:SetPoint("TOPLEFT", 0, 0)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetWidth(3)
	bar:SetVertexColor(K.colors.accent[1], K.colors.accent[2], K.colors.accent[3], 0.9)
	r.bar = bar
	r.mark = K.Label(r, "", "GameFontNormal", "CENTER")
	r.mark:SetPoint("LEFT", 8, 0)
	r.mark:SetWidth(22)
	r.text = K.Label(r, "", "GameFontHighlight")
	r.text:SetPoint("TOPLEFT", 36, -5)
	r.why = K.Label(r, "", "GameFontDisableSmall")
	r.why:SetPoint("TOPLEFT", 36, -23)
	for _, fs in ipairs({r.text, r.why}) do
		fs:SetWidth(JOB_W - 170)
		fs:SetWordWrap(false)
	end
	r.button = K.Button(r, "", 110, 22, function(self) doJob(self:GetParent().step and self:GetParent().step.job) end)
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

local function refreshToday(p)
	local steps = X.HomeToday()
	local _, first = X.HomeTodayNext()
	local done, all = 0, 0
	for _, s in ipairs(steps) do
		if not s.optional then
			all = all + 1
			if s.done then done = done + 1 end
		end
	end
	p.todayTitle:SetText("Today" .. GREY .. "  (" .. done .. " of " .. all .. " done)|r")
	for i, r in ipairs(p.steps) do
		local s = steps[i]
		r.step = s
		r:SetShown(s ~= nil)
		if s then
			local lit = i == first
			if s.done then
				r.mark:SetText(TICK)
				r.text:SetText(GREY .. s.text .. "|r")
				r.why:SetText(GREY .. (s.detail or "") .. "|r")
			elseif s.optional then
				r.mark:SetText(GREY .. "-|r")
				r.text:SetText(s.text)
				r.why:SetText(s.detail or "")
			else
				r.mark:SetText((lit and "|cffffd100" or GREY) .. i .. ".|r")
				r.text:SetText(lit and ("|cffffd100" .. s.text .. "|r") or s.text)
				r.why:SetText(s.detail or "")
			end
			r.bar:SetShown(lit)
			K.Backdrop(r, lit and {K.colors.accent[1], K.colors.accent[2], K.colors.accent[3], 0.12} or {1, 1, 1, 0.04}, {0, 0, 0, 0})
			local job = s.job
			r.button:SetShown(job ~= nil and job.button ~= nil and not s.done)
			if job then r.button:SetText(job.button or "Open") end
		end
	end
	if not first then
		p.allDone:SetText("|cff4ade80All done for today.|r" .. GREY .. " Come back after your next visit to the auction house or the mailbox.|r")
	else
		p.allDone:SetText("")
	end
	local key = UI.NextKeyText()
	p.keyText:SetText(key and (GREY .. "Your Next step key:|r |cffffd100" .. key .. "|r" .. GREY .. " - one press, one step (the same as the button).|r") or
		(GREY .. "Tip: set a key for Next step in the game's key bindings (AddOns, XNAH) - then one key does it all.|r"))
	updateNext(p.next)
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

	-- today's checklist and the Next step button
	refreshToday(p)

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
		card(p, 1, "Gold, all characters", "Gold of all your characters of this realm (both factions), and how it changed today " ..
			"and over the last 7 days (as far as XNAH has seen it: a character counts from the first time XNAH saw it). Click for tab Gold.", "gold"),
		card(p, 2, "Sales today", "What your auctions brought today after the auction house cut, and what you spent on " ..
			"auctions. Read from the auction house mails in your mailbox. Click for tab Gold.", "gold"),
		card(p, 3, "Sales, last 7 days", "What your auctions brought over the last 7 days after the cut. Profit = sales " ..
			"minus what you bought on the auction house in that time. Click for tab Gold.", "gold"),
		card(p, 4, "Net worth", "Gold plus the items of all your characters at auction house prices, and the change over " ..
			"the last 7 days. Click for tab Gold.", "gold"),
		card(p, 5, "Last full scan", "When XNAH last read every auction, and when the server allows the next full scan. " ..
			"Click for Settings.", "scan"),
	}
	p.todayTitle = K.Label(p, "Today", "GameFontNormal")
	p.todayTitle:SetPoint("TOPLEFT", 2, -(TOP + 2))
	p.next = UI.DoNextButton(p, JOB_W, NEXT_H)
	p.next:SetPoint("TOPLEFT", 0, -(TOP + 20))
	p.keyText = K.Label(p, "", "GameFontHighlightSmall")
	p.keyText:SetPoint("TOPLEFT", 2, -(TOP + 20 + NEXT_H + 6))
	p.keyText:SetWidth(JOB_W - 4)
	p.keyText:SetWordWrap(false)
	p.steps = {}
	for i = 1, MAX_STEPS do p.steps[i] = stepRow(p, i) end
	p.allDone = K.Label(p, "", "GameFontHighlightSmall")
	p.allDone:SetPoint("TOPLEFT", 2, -(LIST_TOP + MAX_STEPS * STEP_H + 4))
	p.allDone:SetWidth(JOB_W - 4)
	p.allDone:SetWordWrap(false)

	local title = K.Label(p, "Best sellers, last 7 days", "GameFontNormal")
	title:SetPoint("TOPLEFT", RX, -(TOP + 2))
	p.top = K.Table(p, RW, 5 * 18 + 6, TOP_COLS, onTopRow)
	p.top:SetPoint("TOPLEFT", RX, -(TOP + 38))
	p.top:SortBy(3, true)
	local tTitle = K.Label(p, "Today's trading", "GameFontNormal")
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
