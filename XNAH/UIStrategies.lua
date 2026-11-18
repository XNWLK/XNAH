-- The Strategies tab: ways to make gold (Strategy.lua), each with its own numbers and what it finds right now.
--   Left: the strategies, grouped Buy / Sell / Make, with how many items each finds (* = marked on tooltips).
--   Right: how the selected one works, its numbers, and what it finds - click an item for its page, right click for
--   the menu; search them on the auction house, put them on a shopping list or on the sniper.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local LW = 250              -- the list on the left
local X0 = LW + 12          -- where the right side starts
local RW = W - X0           -- its width (678)
local TOP = 192             -- where the results start (their column titles sit just above)
local MAX = 50              -- rows used by the buttons
local CELL = 186            -- one number box with its label

X.Default("strategySel", "vendorfloor")

local GROUPS = {{side = "buy", title = "Buy"}, {side = "sell", title = "Sell"}, {side = "make", title = "Make"}}
local SIDE_TEXT = {buy = "buying", sell = "selling what you have", make = "crafting"}
local RISK_COLOR = {Low = "4ade80", Medium = "facc15", High = "f87171"}
local BUY_ACTIONS = {["Buy"] = true, ["Buy and vendor"] = true, ["Buy and relist"] = true, ["Disenchant"] = true}

-- a row bought on the auction house (for the shopping list and the sniper)
local function ahBuy(r) return BUY_ACTIONS[r.action] and not r.vendor end

local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local COLUMNS = {
	{"Item", 160, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return (X.ItemName(r.key)) end, desc = false},
	{"Action", 86, "LEFT", text = function(r)
		local a = r.action or ""
		if a == "Hold" then return "|cff9db4ff" .. a .. "|r" end
		if a == "Sell now" then return "|cffffd100" .. a .. "|r" end
		return a
	end, sort = field("action"), desc = false},
	{"Now", 66, "RIGHT", text = money("now"), sort = field("now"), desc = false},
	{"Target", 66, "RIGHT", text = money("target"), sort = field("target")},
	{"Profit", 66, "RIGHT", text = money("profit"), sort = field("profit")},
	{"Qty", 40, "RIGHT", text = function(r) return r.qty and X.Num(r.qty) or "|cff666666-|r" end, sort = field("qty")},
	{"Risk", 50, "LEFT", text = function(r) return "|cff" .. (RISK_COLOR[r.risk] or "ffffff") .. (r.risk or "-") .. "|r" end,
		sort = function(r) return r.risk == "Low" and 1 or r.risk == "Medium" and 2 or 3 end, desc = false},
	{"Why", 128, "LEFT", text = function(r) return "|cffbbbbbb" .. (r.why or "") .. "|r" end},
}

-- [[ what to say when a strategy finds nothing ]]
local function emptyText(s)
	if X.StrategyBusy() and not X.StrategyRows(s.key) then return "Working it out ..." end
	if next(X.Items()) == nil and s.key ~= "vendorflip" and s.key ~= "craft" then
		return "No prices yet. Open the auction house and press Full scan (tab Scan)."
	end
	local text = "Nothing found with these numbers right now. This strategy needs " .. s.needs .. "."
	if s.side == "sell" and not X.Owned then text = text .. " (XNAH does not know your items in this version.)" end
	return text .. " Prices older than " .. X.S().staleHours .. " hours are not used."
end

-- the hour of the day with the most sales (estimate), for the sell strategies
local function bestHour()
	if not X.BestHours then return nil end
	local share = X.Try(X.BestHours)
	if type(share) ~= "table" then return nil end
	local best, h = 0, nil
	for i = 0, 23 do if (share[i] or 0) > best then best, h = share[i], i end end
	return h
end

-- [[ the numbers of the selected strategy ]]
local function showValue(prm, v)
	if prm.kind == "money" then return X.MoneyPlain(v) end
	if prm.kind == "pct" then return tostring(v) end
	return tostring(v)
end
local function readValue(prm, text)
	text = X.Trim(text or "")
	if prm.kind == "money" then
		local v = X.ParseMoney(text)
		return (v and v >= 0) and v or nil
	end
	local v = tonumber((text:gsub("%%", "")))
	if not v or v < 0 then return nil end
	if prm.kind == "pct" then return X.Round(v) end
	return v
end

local function refresh(p)
	X.StrategyCheck()
	local sel = X.Strategy(X.S().strategySel) or X.Strategies()[1]
	p.sel = sel
	-- the list
	local items = {}
	for _, g in ipairs(GROUPS) do
		items[#items + 1] = {header = g.title}
		for _, s in ipairs(X.Strategies()) do if s.side == g.side then items[#items + 1] = {s = s} end end
	end
	p.list:SetItems(items)
	-- the right side
	p.title:SetText(sel.name)
	p.side:SetText("|cff999999for " .. (SIDE_TEXT[sel.side] or sel.side) .. " - " .. sel.short .. "|r")
	p.how:SetText(table.concat(sel.how or {}, "  "))
	p.mark:SetChecked(X.StrategyOn(sel.key))
	local P = X.StrategyParams(sel.key)
	for i, cell in ipairs(p.cells) do
		local prm = sel.params and sel.params[i]
		cell.prm = prm
		cell:SetShown(prm ~= nil)
		if prm then
			local isCheck = prm.kind == "check"
			cell.box:SetShown(not isCheck)
			cell.label:SetShown(not isCheck)
			cell.check:SetShown(isCheck)
			if isCheck then
				cell.check.label:SetText(prm.label)
				cell.check:SetChecked(P[prm.key] and true or false)
			else
				cell.label:SetText(prm.label .. (prm.kind == "pct" and " (%)" or ""))
				if not cell.box:HasFocus() then cell.box:SetText(showValue(prm, P[prm.key])) end
			end
		end
	end
	local rows, c = X.StrategyRows(sel.key)
	rows = rows or {}
	p.tbl:SetRows(rows, emptyText(sel))
	local status = (#rows == 1 and "1 found" or (X.Num(#rows) .. " found"))
	if X.StrategyBusy() then status = status .. ", working ..." elseif c and c.t then status = status .. ", " .. X.Ago(c.t) end
	if sel.side == "sell" then
		local h = bestHour()
		if h then status = status .. ". Most sales about " .. string.format("%02d:00", h) end
	end
	p.status:SetText("|cff999999" .. status .. "|r")
	local buys = 0
	for _, r in ipairs(rows) do if ahBuy(r) then buys = buys + 1 end end
	p.search:SetEnabled(X.ahOpen == true and X.scan.state == "idle" and #rows > 0)
	p.shop:SetEnabled(X.ShopAdd ~= nil and buys > 0)
	p.snipe:SetEnabled(buys > 0)
end

-- the rows in the order shown, at most MAX (only those test(row) accepts)
local function shownRows(p, test)
	local out = {}
	for _, r in ipairs(p.tbl.items or {}) do
		if #out >= MAX then break end
		if not test or test(r) then out[#out + 1] = r end
	end
	return out
end

local function build(p)
	-- [[ left: the strategies ]]
	p.list = K.List(p, LW, H - 46, 18, function(row, item)
		if item.header then
			row:SetCols("|cffe6b422" .. item.header .. "|r", "")
			row:SetScript("OnClick", nil)
			return
		end
		local s = item.s
		local rows = X.StrategyRows(s.key)
		local mark = X.StrategyOn(s.key) and "|cffffd100*|r " or "   "
		row:SetCols(mark .. s.name, rows and X.Num(#rows) or "|cff666666...|r")
		row:SetSelected(p.sel == s)
		row:SetScript("OnClick", function()
			X.S().strategySel = s.key
			p.tbl.offset = 0
			refresh(p)
		end)
	end, {{"Strategy", 180, "LEFT"}, {"Found", 50, "RIGHT"}})
	p.list:SetPoint("TOPLEFT", 0, -16)
	local note = K.Label(p, "|cff999999* = marks tooltips|r")
	note:SetPoint("BOTTOMLEFT", 0, 6)
	note:SetWidth(LW - 110)
	local again = K.Button(p, "Work out again", 104, 20, function() X.StrategyUpdate() refresh(p) end)
	again:SetPoint("BOTTOMLEFT", LW - 104, 2)
	K.Tooltip(again, "Work out again", "Runs every strategy again now (it also happens by itself a few seconds after new prices).")

	-- [[ right: the selected strategy ]]
	p.title = K.Label(p, "", "GameFontNormalLarge")
	p.title:SetPoint("TOPLEFT", X0, 0)
	p.side = K.Label(p, "", "GameFontHighlightSmall")
	p.side:SetPoint("LEFT", p.title, "RIGHT", 10, -1)
	p.side:SetWidth(RW - 330)
	p.side:SetWordWrap(false)
	p.mark = K.Check(p, "Mark on tooltips", function(on)
		if p.sel then X.SetStrategyOn(p.sel.key, on) end
		refresh(p)
	end)
	p.mark:SetPoint("TOPLEFT", X0 + RW - 128, 2)
	K.Tooltip(p.mark, "Mark on tooltips", "Items this strategy finds get a line on their tooltip and their item page. " ..
		"Results are then kept up to date even while this window is closed.")
	p.how = K.Label(p, "", "GameFontHighlightSmall")
	p.how:SetPoint("TOPLEFT", X0, -26)
	p.how:SetWidth(RW)
	p.how:SetSpacing(2)
	p.how:SetMaxLines(6) -- the numbers start under 6 lines

	-- the numbers: up to 6 boxes, three to a line
	p.cells = {}
	for i = 1, 6 do
		local cell = CreateFrame("Frame", nil, p)
		cell:SetSize(CELL - 6, 22)
		cell:SetPoint("TOPLEFT", X0 + ((i - 1) % 3) * CELL, -130 - math.floor((i - 1) / 3) * 26)
		cell.label = K.Label(cell, "", "GameFontHighlightSmall", "RIGHT")
		cell.label:SetPoint("LEFT", 0, 0)
		cell.label:SetWidth(CELL - 76)
		cell.label:SetWordWrap(false)
		cell.box = K.Edit(cell, 58)
		cell.box:SetPoint("LEFT", CELL - 68, 0)
		local function save(self)
			local prm, s = cell.prm, p.sel
			if not prm or not s then return end
			local v = readValue(prm, self:GetText())
			if v ~= nil and v ~= X.StrategyParams(s.key)[prm.key] then X.SetStrategyParam(s.key, prm.key, v) end
			self:SetText(showValue(prm, X.StrategyParams(s.key)[prm.key]))
			refresh(p)
		end
		cell.box:SetScript("OnEditFocusLost", save)
		cell.box:SetScript("OnEnter", function(self)
			local prm = cell.prm
			if not prm then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(prm.label)
			if prm.tip then GameTooltip:AddLine(prm.tip, 1, 1, 1, true) end
			if prm.kind == "money" then GameTooltip:AddLine("Type e.g. 50g or 1g 50s, then Enter.", 0.7, 0.7, 0.7, true) end
			GameTooltip:Show()
		end)
		cell.box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		cell.check = K.Check(cell, "", function(on)
			local prm, s = cell.prm, p.sel
			if prm and s then X.SetStrategyParam(s.key, prm.key, on) end
			refresh(p)
		end)
		cell.check:SetPoint("LEFT", 0, 0)
		cell:Hide()
		p.cells[i] = cell
	end
	local reset = K.Button(p, "Reset numbers", 104, 22, function()
		if p.sel then X.ResetStrategy(p.sel.key) end
		refresh(p)
	end)
	reset:SetPoint("TOPLEFT", X0 + RW - 104, -130)
	K.Tooltip(reset, "Reset numbers", "Puts this strategy's numbers back to how they came.")

	-- the results
	p.tbl = K.Table(p, RW, H - TOP - 28, COLUMNS, onRow)
	p.tbl:SetPoint("TOPLEFT", X0, -TOP)

	-- [[ buttons ]]
	p.search = K.Button(p, "Search these on the AH", 166, 22, function()
		local keys = {}
		for _, r in ipairs(shownRows(p)) do keys[#keys + 1] = r.key end
		if #keys > 0 and X.ahOpen and X.scan.state == "idle" then X.ScanItems(keys, "strategy") end
	end)
	p.search:SetPoint("BOTTOMLEFT", X0, 0)
	K.Tooltip(p.search, "Search these on the auction house",
		"Searches the first " .. MAX .. " items of this list one by one, in the order shown, for their live prices " ..
		"(the list can be out of date). Needs the auction house open.")
	p.shop = K.Button(p, "Add to shopping list", 150, 22, function()
		local s = p.sel
		if not s or not X.ShopAdd then return end
		local name, n = "Strategy: " .. s.name, 0
		for _, r in ipairs(shownRows(p, ahBuy)) do
			if X.ShopAdd(name, r.key, r.qty or 1, X.Round(r.now * 1.05)) then n = n + 1 end
		end
		X.Print(n .. " items put on the shopping list \"" .. name .. "\" (tab Buy), each with a top price of 5% over its price now.")
	end)
	p.shop:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
	K.Tooltip(p.shop, "Add to shopping list", "Puts the items to buy (first " .. MAX .. ") on a shopping list named after " ..
		"this strategy, with the quantity shown and a top price of 5% over the price now.")
	p.snipe = K.Button(p, "Snipe at this price", 140, 22, function()
		local n = 0
		for _, r in ipairs(shownRows(p, ahBuy)) do
			X.SetWatchMax(r.key, X.Round(r.now))
			n = n + 1
		end
		X.Print(n .. " items on the watch list with a top price (the sniper on the Buy tab looks for them).")
	end)
	p.snipe:SetPoint("LEFT", p.shop, "RIGHT", 6, 0)
	K.Tooltip(p.snipe, "Snipe at this price", "Puts the items to buy (first " .. MAX .. ") on the watch list with their " ..
		"price now as the most to pay: the sniper tells you when one is listed at or under it.")
	p.status = K.Label(p, "", "GameFontHighlightSmall", "RIGHT")
	p.status:SetPoint("BOTTOMRIGHT", 0, 6)
	p.status:SetWidth(RW - 166 - 150 - 140 - 24)
	p.status:SetWordWrap(false)
end

X.On("XNAH_STRATEGY", function() UI.Refresh() end)

UI.AddTab("strategies", "Strategies", build, refresh, 3.5)
