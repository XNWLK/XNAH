-- The Deals page: every idea for making gold in one place (the old Strategies page lives on here).
--   Buy ideas: one list of everything worth buying right now - listings far under their usual price, and what every
--     buy idea (Strategy.lua) finds - one row per item, best first, with the idea that found it, a short "why" and a
--     Buy button in each row.
--   Sell ideas: what to do with things you have (sell now, hold) - from the sell ideas.
--   Make ideas: crafting, recipes worth learning, cooldowns, what to farm - from the make ideas.
--   Adjust ideas (UIStrategies.lua): which ideas are in the lists, their numbers, how each works.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 96      -- where the tables start (their column titles sit just above)
local MAX = 50      -- rows used by the buttons under the buy list
local BUY_W = 128   -- the Buy button in each row (its label says the next step: "Confirm 5 for 2g 10s")

-- "hide items that sell under N a day" (buy ideas)
X.Default("dealSpeedHide", false)
X.Default("dealSpeedMin", 1)
-- ideas left out of the lists: [idea key] = true
X.Default("dealsHidden", {})

local VIEWS = {
	{key = "buy", title = "Buy ideas", w = 110,
		help = "Worth buying now: listed under what it usually sells for, or under what a vendor pays. Best first."},
	{key = "sell", title = "Sell ideas", w = 100,
		help = "What to do with things you have: sell now while the price is good, or hold while it is low."},
	{key = "make", title = "Make ideas", w = 100,
		help = "Crafting for profit, recipes worth learning, cooldown crafts and what to gather."},
}

-- [[ the ideas ]] the strategies (Strategy.lua) plus "Under usual price" (the deals test, Market.lua: X.Deals), which
-- has its numbers in the settings (dealPct, dealMinProfit)
local USUAL = {key = "usual", name = "Under usual price", side = "buy",
	short = "Listed far under its usual price (the 30-day average).",
	how = {
		"Lists items whose lowest price is at or under a share of their usual price (the 30-day average, else the 7-day one), with enough profit after the auction house cut.",
		"Buy them now and sell them again at the usual price.",
		"When it fails: when the price has really moved (a patch, a new source) - the usual price is then old news.",
	},
	needs = "fresh prices (a full scan) and a few days of price history per item (one full scan a day)",
	params = {
		{key = "pct", label = "Share of usual price at most", kind = "pct",
			tip = "The lowest price must be at or under this % of the usual price."},
		{key = "minProfit", label = "Profit each at least", kind = "money",
			tip = "Leave out items that bring less than this each (after the auction house cut)."},
	},
}
local IDEAS = {}
-- every idea, in the order shown (Under usual price first)
function IDEAS.list()
	local out = {USUAL}
	for _, s in ipairs(X.Strategies and X.Strategies() or {}) do out[#out + 1] = s end
	return out
end
function IDEAS.get(key)
	if key == USUAL.key then return USUAL end
	return X.Strategy and X.Strategy(key) or nil
end
function IDEAS.params(idea)
	if idea == USUAL then
		local S = X.S()
		return {pct = S.dealPct, minProfit = S.dealMinProfit}
	end
	return X.StrategyParams(idea.key)
end
local dirty -- forward: the lists must be worked out again
function IDEAS.setParam(idea, pkey, value)
	if idea == USUAL then
		if pkey == "pct" then X.S().dealPct = math.max(1, math.min(100, X.Round(value))) end
		if pkey == "minProfit" then X.S().dealMinProfit = value end
		dirty()
		return
	end
	X.SetStrategyParam(idea.key, pkey, value)
end
function IDEAS.reset(idea)
	if idea == USUAL then
		X.S().dealPct, X.S().dealMinProfit = X.DEFAULTS.dealPct, X.DEFAULTS.dealMinProfit
		dirty()
		return
	end
	X.ResetStrategy(idea.key)
end
-- is the idea used in the Deals lists?
function IDEAS.shown(key) return not (X.S().dealsHidden or {})[key] end
function IDEAS.setShown(key, on)
	X.S().dealsHidden = X.S().dealsHidden or {}
	X.S().dealsHidden[key] = (not on) and true or nil
	dirty()
end
UI.Ideas = IDEAS

-- [[ the rows ]]
local function riskOf(st, rate)
	local score = 0
	local vol = st and st.vol
	if not vol then score = score + 1 elseif vol > 25 then score = score + 2 elseif vol > 12 then score = score + 1 end
	local days = st and st.days or 0
	if days < 7 then score = score + 1 end
	if not rate then score = score + 1 elseif rate < 0.5 then score = score + 2 elseif rate < 2 then score = score + 1 end
	if score <= 1 then return "Low" end
	if score <= 3 then return "Medium" end
	return "High"
end
-- the deals of "Under usual price" as idea rows (how many: about 3 days of sales when the speed is known); kept
-- until prices or the numbers change (a minute at most: prices get old)
local usualCache, usualAt, usualDirty
local function usualRows()
	if usualCache and not usualDirty and GetTime() - usualAt <= 60 then return usualCache end
	local out = {}
	for _, d in ipairs(X.Deals()) do
		local rate = X.SaleRate and X.Try(X.SaleRate, d.key) or nil
		local qty
		if rate and rate > 0 then qty = math.max(1, math.min(d.qty or 1, math.floor(rate * 3 + 0.5))) end
		local it = X.Items()[d.key]
		out[#out + 1] = {key = d.key, action = "Buy and relist", now = d.buy, target = d.usual, profit = d.profit, qty = qty,
			risk = riskOf(it and X.Stats(it), rate), rate = rate, total = d.profit * (qty or 1),
			why = string.format("%.0f%% of its usual price", d.pct)}
	end
	usualCache, usualAt, usualDirty = out, GetTime(), false
	return out
end
-- the rows one idea finds right now (nil: not worked out yet)
function IDEAS.rows(idea)
	if idea == USUAL then return usualRows() end
	return X.StrategyRows(idea.key)
end

-- all ideas of one side, one row per item (the one bringing the most in all), best first
local cache, cacheAt, cacheDirty = {}, {}, {}
local function markDirty()
	cacheDirty.buy, cacheDirty.sell, cacheDirty.make = true, true, true
	usualDirty = true
end
dirty = function()
	markDirty()
	UI.Refresh()
end
for _, e in ipairs({"XNAH_PRICES", "XNAH_STRATEGY", "XNAH_IGNORE", "XNAH_ANALYSIS", "XNAH_INVENTORY"}) do X.On(e, markDirty) end
local function merge(side)
	local best, others = {}, {}
	local function take(idea, r)
		local row = {}
		for k, v in pairs(r) do row[k] = v end
		row.idea, row.ideaName = idea.key, idea.name
		row.total = row.total or (row.profit or 0) * (row.qty or 1)
		local old = best[row.key]
		others[row.key] = (others[row.key] or 0) + 1
		if not old or row.total > old.total then best[row.key] = row end
	end
	for _, idea in ipairs(IDEAS.list()) do
		if idea.side == side and IDEAS.shown(idea.key) then
			local rows = (idea == USUAL) and usualRows() or (X.StrategyRows(idea.key) or {})
			for _, r in ipairs(rows) do if r.key then take(idea, r) end end
		end
	end
	local out = {}
	for key, row in pairs(best) do
		row.more = others[key] - 1
		if row.rate == nil then row.rate = X.SaleRate and X.Try(X.SaleRate, key) or nil end
		out[#out + 1] = row
	end
	table.sort(out, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.key < b.key
	end)
	return out
end
-- every buy idea (one row per item, best first): {key, idea, ideaName, action, now, target, profit, qty, total, risk,
-- why, rate, more (other ideas that found it too), vendor (bought from a vendor)}
function X.DealIdeas(side)
	side = side or "buy"
	if cacheDirty[side] ~= false or not cache[side] or GetTime() - (cacheAt[side] or 0) > 60 then
		cache[side] = merge(side)
		cacheAt[side], cacheDirty[side] = GetTime(), false
	end
	return cache[side]
end

-- the buy rows after the speed filter (items known to sell slower than N a day are left out; unknown speed: shown)
local function buyRows()
	local rows = X.DealIdeas("buy")
	local S = X.S()
	if not S.dealSpeedHide then return rows end
	local out = {}
	for _, r in ipairs(rows) do
		if not r.rate or r.rate >= (S.dealSpeedMin or 0) then out[#out + 1] = r end
	end
	return out
end

-- [[ cells ]]
local RISK_COLOR = {Low = "4ade80", Medium = "facc15", High = "f87171"}
local GREY = "|cff999999"
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end
-- sells per day (an estimate): "-" when not known yet
function UI.RateText(rate)
	if not rate then return "|cff666666-|r" end
	if rate >= 10 then return X.Num(rate) end
	if rate >= 0.1 then return string.format("%.1f", rate) end
	return "|cff999999<0.1|r"
end
local function ideaCell(r)
	return (r.ideaName or "") .. ((r.more or 0) > 0 and (GREY .. " +" .. r.more .. "|r") or "")
end
local function riskCell(r) return "|cff" .. (RISK_COLOR[r.risk] or "ffffff") .. (r.risk or "-") .. "|r" end
local function riskSort(r) return r.risk == "Low" and 1 or r.risk == "Medium" and 2 or 3 end
-- what to do with it after buying, in front of the why
local THEN = {["Buy and vendor"] = "sell to a vendor: ", ["Disenchant"] = "disenchant: ", ["Buy and hold"] = "keep a while: "}
local function whyCell(r)
	local pre = r.vendor and "buy from a vendor: " or THEN[r.action] or ""
	return "|cffbbbbbb" .. pre .. (r.why or "") .. "|r"
end
local function qtyCell(r) return r.qty and X.Num(r.qty) or "|cff666666-|r" end
local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

local BUY_COL = 11
local COLUMNS = {
	buy = {
		{"Item", 170, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Idea", 100, "LEFT", text = ideaCell, sort = field("ideaName"), desc = false},
		{"Price now", 66, "RIGHT", text = money("now"), sort = field("now"), desc = false},
		{"Sells for", 66, "RIGHT", text = money("target"), sort = field("target")},
		{"Profit each", 66, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Qty", 34, "RIGHT", text = qtyCell, sort = field("qty")},
		{"Profit in all", 72, "RIGHT", text = money("total"), sort = field("total")},
		{"Sells a day", 56, "RIGHT", text = function(r) return UI.RateText(r.rate) end, sort = field("rate")},
		{"Risk", 42, "LEFT", text = riskCell, sort = riskSort, desc = false},
		{"Why", 108, "LEFT", text = whyCell},
		{"", BUY_W + 2, "LEFT", text = function(r) return r.vendor and (GREY .. " at a vendor|r") or "" end},
	},
	other = {
		{"Item", 200, "LEFT", text = itemCell, sort = itemName, desc = false},
		{"Idea", 130, "LEFT", text = ideaCell, sort = field("ideaName"), desc = false},
		{"Action", 100, "LEFT", text = function(r)
			local a = r.action or ""
			if a == "Hold" then return "|cff9db4ff" .. a .. "|r" end
			if a == "Sell now" then return "|cffffd100" .. a .. "|r" end
			return a
		end, sort = field("action"), desc = false},
		{"Now", 80, "RIGHT", text = money("now"), sort = field("now"), desc = false},
		{"Target", 80, "RIGHT", text = money("target"), sort = field("target")},
		{"Profit each", 80, "RIGHT", text = money("profit"), sort = field("profit")},
		{"Qty", 44, "RIGHT", text = qtyCell, sort = field("qty")},
		{"Risk", 50, "LEFT", text = riskCell, sort = riskSort, desc = false},
		{"Why", 150, "LEFT", text = whyCell},
	},
}

-- [[ the Buy button in each row ]] the purchase button of the Buy page (UI.BuyButton: check the price, buy, confirm,
-- each one click); a stand-in that shows the item on the auction house when that button is missing
local function standIn(parent)
	local b = K.Button(parent, "Find", BUY_W, 16)
	b.standIn = true
	function b:SetItem(key)
		self.key = key
		self:SetEnabled(X.ahOpen == true)
	end
	b:SetScript("OnClick", function(self)
		if not self.key or not X.ahOpen then return end
		if X.ShowOnAuctionHouse then X.ShowOnAuctionHouse(self.key) end
		if X.scan.state == "idle" then X.ScanItems({self.key}, "one item") end
	end)
	K.Tooltip(b, "Find on the auction house", "Shows this item on the auction house (it must be open) to buy it there.")
	return b
end
local function rowButton(rowFrame)
	local b = rowFrame.buyButton
	if b then return b end
	if UI.BuyButton then
		local ok, made = pcall(UI.BuyButton, rowFrame, BUY_W, 16)
		if ok and made then b = made end
	end
	b = b or standIn(rowFrame)
	b:SetPoint("LEFT", rowFrame.cols[BUY_COL], "LEFT", 0, 0)
	rowFrame.buyButton = b
	return b
end
-- the most to pay for one: the price now plus half the profit (still half the profit left)
local function maxEach(r)
	if not r.now then return nil end
	return math.floor(r.now + math.max(0, r.profit or 0) / 2)
end
local function drawButtons(tbl)
	for i, rowFrame in ipairs(tbl.rows) do
		local r = tbl.items[i + tbl.offset]
		if r and not r.vendor and rowFrame.cols then
			local b = rowButton(rowFrame)
			local max = maxEach(r)
			local id = r.key .. ":" .. tostring(r.qty) .. ":" .. tostring(max)
			-- set again only for another item (a purchase under way keeps its step when the list is drawn again)
			if b.dealsId ~= id or b.standIn then
				b.dealsId = id
				-- source and tag as the Next buy key uses them: one purchase whichever starts it
				local ok, err = pcall(b.SetItem, b, r.key, r.qty, max, "idea", "idea:" .. r.key)
				if not ok then X.Debug("deals buy button: " .. tostring(err)) end
			end
			b:Show()
		elseif rowFrame.buyButton then
			rowFrame.buyButton:Hide()
			rowFrame.buyButton.dealsId = nil
		end
	end
end

-- [[ what to say when a list is empty ]]
local NO_PRICES = "No prices yet. Open the auction house and press Full scan (Settings)."
local function emptyText(view)
	local S = X.S()
	if next(X.Items()) == nil then return NO_PRICES end
	if X.StrategyBusy and X.StrategyBusy() then return "Working out the ideas ..." end
	if view == "buy" then
		return "No buy ideas right now. They need fresh prices (a full scan; prices older than " .. S.staleHours ..
			" hours are not used), a few days of price history per item, and for some the sales speed or vendors visited. " ..
			"Adjust ideas changes their numbers."
	elseif view == "sell" then
		return "No sell ideas right now. They look at what you have (log in your characters, open the bank and the " ..
			"mailbox) and need a few days of price history."
	end
	return "No make ideas right now. They need recipes (open your profession windows) and fresh prices of what goes in " ..
		"and what comes out. The Crafting page lists every recipe."
end

-- the hour of the day with the most sales (estimate), for the sell ideas
local function bestHour()
	if not X.BestHours then return nil end
	local share = X.Try(X.BestHours)
	if type(share) ~= "table" then return nil end
	local best, h = 0, nil
	for i = 0, 23 do if (share[i] or 0) > best then best, h = share[i], i end end
	return h
end

-- the buy rows in the order shown, at most MAX, bought on the auction house
local function shownBuys(p)
	local out = {}
	for _, r in ipairs(p.tables.buy.items or {}) do
		if #out >= MAX then break end
		if not r.vendor then out[#out + 1] = r end
	end
	return out
end

-- [[ the page ]]
local function refresh(p)
	if X.StrategyCheck then X.StrategyCheck() end -- works the ideas out again when prices changed or they are old
	local S = X.S()
	local view = p.view
	local adjust = view == "adjust"
	for _, v in ipairs(VIEWS) do
		p.viewButtons[v.key]:SetSelected(v.key == view)
		p.tables[v.key]:SetShown(v.key == view)
	end
	p.adjustButton:SetSelected(adjust)
	p.adjust:SetShown(adjust)
	p.listBits:SetShown(not adjust)
	if adjust then
		if p.adjust.Refresh then p.adjust:Refresh() end
		return
	end
	local rows
	if view == "buy" then rows = buyRows() else rows = X.DealIdeas(view) end
	p.help:SetText(p.helpText[view])
	p.controls:SetShown(view == "buy")
	p.buyBar:SetShown(view == "buy")
	p.note:SetShown(view ~= "buy")
	p.hint2:SetShown(view ~= "buy")
	if view == "sell" then
		local h = bestHour()
		p.note:SetText(GREY .. (h and ("Most sales happen about " .. string.format("%02d:00", h) .. " (your clock): post an hour or two before. ")
			or "") .. "Sell ideas look at what you have on all your characters.|r")
	elseif view == "make" then
		p.note:SetText(GREY .. "Profit = what it sells for after the cut, minus what goes in at today's prices. " ..
			"The Crafting page has every recipe.|r")
	end
	if not p.speedBox:HasFocus() then p.speedBox:SetText(tostring(S.dealSpeedMin)) end
	p.speedCheck:SetChecked(S.dealSpeedHide and true or false)
	local tbl = p.tables[view]
	tbl:SetRows(rows, emptyText(view))
	local status = #rows == 1 and "1 item" or (X.Num(#rows) .. " items")
	if X.StrategyBusy and X.StrategyBusy() then status = status .. ", working ..." end
	p.count:SetText(status)
	if view == "buy" then
		local buys = #shownBuys(p)
		p.search:SetEnabled(X.ahOpen == true and X.scan.state == "idle" and buys > 0)
		p.shop:SetEnabled(X.ShopAdd ~= nil and buys > 0)
		p.snipe:SetEnabled(buys > 0)
	end
end

local function build(p)
	p.view = "buy"
	p.helpText = {}
	p.viewButtons = {}
	p.tables = {}

	-- the views
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
	local adjustButton = K.Flat(p, 120, 22)
	adjustButton:SetPoint("TOPRIGHT", 0, 0)
	adjustButton:SetLabel("Adjust ideas")
	adjustButton.label:SetJustifyH("CENTER")
	adjustButton:SetScript("OnClick", function()
		if p.view == "adjust" then p.view = p.lastList or "buy" else p.lastList, p.view = p.view, "adjust" end
		refresh(p)
	end)
	K.Tooltip(adjustButton, "Adjust ideas", "Which ideas go into these lists, their numbers, and how each one works.")
	p.adjustButton = adjustButton

	-- everything of the three lists (hidden while adjusting)
	local bits = CreateFrame("Frame", nil, p)
	bits:SetAllPoints(p)
	p.listBits = bits
	p.help = K.Label(bits, "", "GameFontHighlight")
	p.help:SetPoint("TOPLEFT", 0, -30)
	p.help:SetWidth(W - 130)
	p.help:SetWordWrap(false)
	p.count = K.Label(bits, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, -32)
	p.count:SetWidth(120)
	p.note = K.Label(bits, "", "GameFontHighlightSmall")
	p.note:SetPoint("TOPLEFT", 0, -56)
	p.note:SetWidth(W)
	p.note:SetWordWrap(false)

	-- hide slow sellers (buy ideas)
	local c = CreateFrame("Frame", nil, bits)
	c:SetPoint("TOPLEFT", 0, -52)
	c:SetSize(W, 24)
	p.controls = c
	p.speedCheck = K.Check(c, "Hide items that sell under", function(on)
		X.S().dealSpeedHide = on
		refresh(p)
	end)
	p.speedCheck:SetPoint("LEFT", 0, 0)
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

	-- the tables (same place, one shown)
	for _, v in ipairs(VIEWS) do
		local tbl = K.Table(bits, W, H - TOP - 28, v.key == "buy" and COLUMNS.buy or COLUMNS.other, onRow)
		tbl:SetPoint("TOPLEFT", 0, -TOP)
		tbl:SortBy(v.key == "buy" and 7 or 6, true) -- the most profit first
		p.tables[v.key] = tbl
	end
	-- a Buy button in each row of the buy list
	local buyTbl = p.tables.buy
	local baseRefresh = buyTbl.Refresh
	function buyTbl:Refresh()
		baseRefresh(self)
		drawButtons(self)
	end

	-- under the buy list: search, shopping list, sniper (the first rows shown, bought on the auction house)
	local bar = CreateFrame("Frame", nil, bits)
	bar:SetPoint("BOTTOMLEFT", 0, 0)
	bar:SetSize(W, 22)
	p.buyBar = bar
	p.search = K.Button(bar, "Search these on the AH", 166, 22, function()
		local keys = {}
		for _, r in ipairs(shownBuys(p)) do keys[#keys + 1] = r.key end
		if #keys > 0 and X.ahOpen and X.scan.state == "idle" then X.ScanItems(keys, "deals") end
	end)
	p.search:SetPoint("BOTTOMLEFT", 0, 0)
	K.Tooltip(p.search, "Search these on the auction house",
		"Searches the first " .. MAX .. " items of this list one by one, in the order shown, for their live prices " ..
		"(the list can be out of date: someone may have bought them already). Needs the auction house open.")
	p.shop = K.Button(bar, "Add to shopping list", 150, 22, function()
		if not X.ShopAdd then return end
		local name, n = "Deals", 0
		for _, r in ipairs(shownBuys(p)) do
			if X.ShopAdd(name, r.key, r.qty or 1, maxEach(r)) then n = n + 1 end
		end
		X.Print(n .. " items put on the shopping list \"" .. name .. "\" (Buy page), each with a top price of its price now " ..
			"plus half the profit.")
	end)
	p.shop:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
	K.Tooltip(p.shop, "Add to shopping list", "Puts the first " .. MAX .. " items to buy on the shopping list \"Deals\", " ..
		"with the quantity shown and a top price of the price now plus half the profit.")
	p.snipe = K.Button(bar, "Snipe at this price", 140, 22, function()
		local n = 0
		for _, r in ipairs(shownBuys(p)) do
			X.SetWatchMax(r.key, X.Round(r.now))
			n = n + 1
		end
		X.Print(n .. " items on the watch list with a top price (the sniper on the Buy page looks for them).")
	end)
	p.snipe:SetPoint("LEFT", p.shop, "RIGHT", 6, 0)
	K.Tooltip(p.snipe, "Snipe at this price", "Puts the first " .. MAX .. " items to buy on the watch list with their " ..
		"price now as the most to pay: the sniper tells you when one is listed at or under it.")
	local hint = K.Label(bar, GREY .. "Click: item page.  Right-click: menu.  +1 = another idea found it too.|r", nil, "RIGHT")
	hint:SetPoint("BOTTOMRIGHT", 0, 4)
	hint:SetWidth(W - 480)
	hint:SetWordWrap(false)
	p.hint2 = K.Label(bits, GREY .. "Click a row: item page.  Right-click: menu.  +1 = another idea found it too.  " ..
		"Click a column title to sort.|r")
	p.hint2:SetPoint("BOTTOMLEFT", 0, 4)

	-- Adjust ideas (UIStrategies.lua)
	local area = CreateFrame("Frame", nil, p)
	area:SetPoint("TOPLEFT", 0, -30)
	area:SetSize(W, H - 30)
	if UI.BuildIdeasAdjust then
		local ok, err = pcall(UI.BuildIdeasAdjust, area, W, H - 30, function() dirty() end)
		if not ok then X.OnError(err) end
	end
	area:Hide()
	p.adjust = area
end

X.On("XNAH_STRATEGY", function() UI.Refresh() end)

UI.AddTab("deals", "Deals", build, refresh, 3)
