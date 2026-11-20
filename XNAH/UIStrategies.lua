-- Adjust ideas (on the Deals page): the ideas behind the Deals lists (Strategy.lua, plus "Under usual price"), each
-- with how it works, its numbers and what it finds right now.
--   Left: the ideas, grouped Buy / Sell / Make, with how many items each finds (* = marked on tooltips, grey = left
--   out of the lists).
--   Right: how the selected one works, "Use in the lists", "Mark on tooltips", its numbers, what it finds.
-- UI.BuildIdeasAdjust(area, w, h, onChange) builds it inside the Deals page; area:Refresh() draws it again.
local ADDON, X = ...
local K, UI = X.K, X.UI

local LW = 250              -- the list on the left
local X0 = LW + 12          -- where the right side starts
local TOP = 192             -- where the results start (their column titles sit just above)
local CELL = 186            -- one number box with its label

X.Default("strategySel", "usual")

local GROUPS = {{side = "buy", title = "Buy"}, {side = "sell", title = "Sell"}, {side = "make", title = "Make"}}
local SIDE_TEXT = {buy = "buying", sell = "selling what you have", make = "crafting"}
local RISK_COLOR = {Low = "4ade80", Medium = "facc15", High = "f87171"}

local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end

-- the numbers of the selected idea
local function showValue(prm, v)
	if prm.kind == "money" then return X.MoneyPlain(v or 0) end
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

function UI.BuildIdeasAdjust(p, W, H, onChange)
	local I = UI.Ideas
	local RW = W - X0
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
		{"Why", RW - 160 - 86 - 66 * 3 - 40 - 50 - 24, "LEFT", text = function(r) return "|cffbbbbbb" .. (r.why or "") .. "|r" end},
	}

	local function emptyText(s)
		if X.StrategyBusy() and s.key ~= "usual" and not X.StrategyRows(s.key) then return "Working it out ..." end
		if next(X.Items()) == nil and s.key ~= "vendorflip" and s.key ~= "craft" then
			return "No prices yet. Open the auction house and press Full scan (Settings)."
		end
		local text = "Nothing found with these numbers right now. This idea needs " .. s.needs .. "."
		if s.side == "sell" and not X.Owned then text = text .. " (XNAH does not know your items in this version.)" end
		return text .. " Prices older than " .. X.S().staleHours .. " hours are not used."
	end

	local function refresh()
		local sel = I.get(X.S().strategySel) or I.list()[1]
		p.sel = sel
		-- the list
		local items = {}
		for _, g in ipairs(GROUPS) do
			items[#items + 1] = {header = g.title}
			for _, s in ipairs(I.list()) do if s.side == g.side then items[#items + 1] = {s = s} end end
		end
		p.list:SetItems(items)
		-- the right side
		local strategy = sel.key ~= "usual"
		p.title:SetText(sel.name)
		p.side:SetText("|cff999999for " .. (SIDE_TEXT[sel.side] or sel.side) .. " - " .. sel.short .. "|r")
		p.how:SetText(table.concat(sel.how or {}, "  "))
		p.use:SetChecked(I.shown(sel.key))
		p.mark:SetShown(strategy)
		p.mark:SetChecked(strategy and X.StrategyOn(sel.key))
		local P = I.params(sel)
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
		local rows, c = I.rows(sel)
		rows = rows or {}
		p.tbl:SetRows(rows, emptyText(sel))
		local status = (#rows == 1 and "1 found" or (X.Num(#rows) .. " found"))
		if X.StrategyBusy() then status = status .. ", working ..." elseif c and c.t then status = status .. ", " .. X.Ago(c.t) end
		p.status:SetText("|cff999999" .. status .. "|r")
	end
	p.Refresh = refresh
	local function changed()
		refresh()
		if onChange then onChange() end
	end

	-- [[ left: the ideas ]]
	p.list = K.List(p, LW, H - 64, 18, function(row, item)
		if item.header then
			row:SetCols("|cffe6b422" .. item.header .. "|r", "")
			row:SetScript("OnClick", nil)
			return
		end
		local s = item.s
		local rows = (s.key == "usual") and true or X.StrategyRows(s.key)
		local mark = (s.key ~= "usual" and X.StrategyOn(s.key)) and "|cffffd100*|r " or "   "
		local name = I.shown(s.key) and s.name or ("|cff777777" .. s.name .. "|r")
		local found = rows == true and "" or (rows and X.Num(#rows) or "|cff666666...|r")
		row:SetCols(mark .. name, found)
		row:SetSelected(p.sel == s)
		row:SetScript("OnClick", function()
			X.S().strategySel = s.key
			p.tbl.offset = 0
			refresh()
		end)
	end, {{"Idea", 180, "LEFT"}, {"Found", 50, "RIGHT"}})
	p.list:SetPoint("TOPLEFT", 0, -16)
	local note = K.Label(p, "|cff999999* = marks tooltips, grey = not in the lists|r")
	note:SetPoint("BOTTOMLEFT", 0, 28)
	note:SetWidth(LW)
	local again = K.Button(p, "Work out again", 120, 20, function() X.StrategyUpdate() changed() end)
	again:SetPoint("BOTTOMLEFT", 0, 2)
	K.Tooltip(again, "Work out again", "Runs every idea again now (it also happens by itself a few seconds after new prices).")

	-- [[ right: the selected idea ]]
	p.title = K.Label(p, "", "GameFontNormalLarge")
	p.title:SetPoint("TOPLEFT", X0, 0)
	p.side = K.Label(p, "", "GameFontHighlightSmall")
	p.side:SetPoint("LEFT", p.title, "RIGHT", 10, -1)
	p.side:SetWidth(RW - 480)
	p.side:SetWordWrap(false)
	p.use = K.Check(p, "Use in the lists", function(on)
		if p.sel then I.setShown(p.sel.key, on) end
		changed()
	end)
	p.use:SetPoint("TOPLEFT", X0 + RW - 260, 2)
	K.Tooltip(p.use, "Use in the lists", "What this idea finds goes into the Buy, Sell or Make list of the Deals page. " ..
		"Switch it off to leave it out.")
	p.mark = K.Check(p, "Mark on tooltips", function(on)
		if p.sel then X.SetStrategyOn(p.sel.key, on) end
		changed()
	end)
	p.mark:SetPoint("TOPLEFT", X0 + RW - 128, 2)
	K.Tooltip(p.mark, "Mark on tooltips", "Items this idea finds get a line on their tooltip and their item page. " ..
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
			if v ~= nil and v ~= I.params(s)[prm.key] then I.setParam(s, prm.key, v) end
			self:SetText(showValue(prm, I.params(s)[prm.key]))
			changed()
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
			if prm and s then I.setParam(s, prm.key, on) end
			changed()
		end)
		cell.check:SetPoint("LEFT", 0, 0)
		cell:Hide()
		p.cells[i] = cell
	end
	local reset = K.Button(p, "Reset numbers", 104, 22, function()
		if p.sel then I.reset(p.sel) end
		changed()
	end)
	reset:SetPoint("TOPLEFT", X0 + RW - 104, -130)
	K.Tooltip(reset, "Reset numbers", "Puts this idea's numbers back to how they came.")

	-- what it finds
	p.tbl = K.Table(p, RW, H - TOP - 28, COLUMNS, onRow)
	p.tbl:SetPoint("TOPLEFT", X0, -TOP)
	p.tbl:SortBy(5, true)
	p.status = K.Label(p, "", "GameFontHighlightSmall", "RIGHT")
	p.status:SetPoint("BOTTOMRIGHT", 0, 6)
	p.status:SetWidth(200)
	p.status:SetWordWrap(false)
	local hint = K.Label(p, "|cff999999What this idea finds now (also when it is not used in the lists).|r")
	hint:SetPoint("BOTTOMLEFT", X0, 6)
	hint:SetWidth(RW - 210)
	hint:SetWordWrap(false)
	return p
end
