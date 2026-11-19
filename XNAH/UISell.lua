-- The Sell tab: what is in your bags that can be sold, a suggested price for each (undercut the cheapest seller that is
-- not you, within your floor and ceiling), and posting - one click on Post = one auction (the game allows posting only
-- on a click). The second view lists your auctions that someone undercut, to cancel them (one click each). The third
-- view is the one-key routine (Routine.lua): each press of one key or of its big button does the next step.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 70         -- where the table starts (its column titles sit just above)
local LEFT_W = 600     -- table width
local RX, RW = 612, 328 -- the panel on the right

for _, e in ipairs({"XNAH_LIVE", "XNAH_POST", "XNAH_CANCEL", "XNAH_ROUTINE", "BAG_UPDATE_DELAYED"}) do
	X.On(e, function() UI.Refresh() end)
end

local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end

-- [[ rows of the bag view ]] (worked out on every refresh: a bag holds few items)
local function sellRows()
	local rows = X.SellItems()
	for _, r in ipairs(rows) do
		local price, reason, info = X.PostPrice(r.key)
		local rule = X.PostRule(r.key)
		local qty = r.commodity and r.have or 1
		r.price, r.reason, r.info = price, reason, info
		r.lowest = info and info.lowest
		r.market = X.Price(r.key, "mkt")
		r.deposit = X.PostDeposit(r, rule.duration, qty)
		r.afterCut = price and X.AfterCut(price * qty) or nil
	end
	return rows
end

local SELL_COLUMNS = {
	{"Item", 160, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"List", 30, "CENTER", text = function(r) return X.OnSellList(r.key) and "|cff33ff33yes|r" or "" end,
		sort = function(r) return X.OnSellList(r.key) and 1 or 0 end},
	{"Have", 45, "RIGHT", text = function(r) return X.Num(r.have) end, sort = field("have")},
	{"Lowest now", 80, "RIGHT", text = function(r)
		return UI.MoneyCell(r.lowest, r.info and r.info.from == "scan")
	end, sort = field("lowest")},
	{"Market", 75, "RIGHT", text = money("market"), sort = field("market")},
	{"Suggested", 80, "RIGHT", text = money("price"), sort = field("price")},
	{"Deposit", 60, "RIGHT", text = money("deposit"), sort = field("deposit")},
	{"After cut", 70, "RIGHT", text = money("afterCut"), sort = field("afterCut")},
}
local CANCEL_COLUMNS = {
	{"Item", 200, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Qty", 45, "RIGHT", text = function(r) return X.Num(r.qty) end, sort = field("qty")},
	{"Your price", 90, "RIGHT", text = money("unit"), sort = field("unit")},
	{"Lowest now", 90, "RIGHT", text = money("lowest"), sort = field("lowest")},
	{"Time left", 85, "RIGHT", text = function(r) return X.TimeLeftText(r.timeLeftSeconds, r.timeLeft) end,
		sort = function(r) return r.timeLeftSeconds or r.timeLeft end, desc = false},
	{"Cancel cost", 80, "RIGHT", text = function(r) return r.cost and UI.MoneyCell(r.cost) or "-" end, sort = field("cost")},
}

-- the one-key routine's steps
local STEP_DONE = {cancel = "cancelled", post = "posted"}
local function stepStatus(s)
	if s.status == "wait" then return "|cff999999waiting for its price|r" end
	if s.status == "todo" then return s.isNext and "|cffffd100next|r" or "to do" end
	if s.status == "sent" then
		if s.kind == "post" and X.post.state == "warning" and X.post.key == s.key then return "|cffffd100price warning: press again to post|r" end
		return "waiting for the auction house"
	end
	if s.status == "done" then return "|cff33ff33" .. STEP_DONE[s.kind] .. "|r" end
	return "|cffff8888skipped: " .. (s.why or "?") .. "|r"
end
local ROUTINE_COLUMNS = {
	{"#", 28, "RIGHT", text = function(r) return tostring(r.n or "") end, sort = field("n"), desc = false},
	{"Step", 62, "LEFT", text = function(r) return r.kind == "cancel" and "Cancel" or "Post" end, sort = field("kind")},
	{"Item", 190, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Qty", 45, "RIGHT", text = function(r) return X.Num(r.qty or 1) end, sort = field("qty")},
	{"Price", 85, "RIGHT", text = function(r) return UI.MoneyCell(r.price) end, sort = field("price")},
	{"Status", 190, "LEFT", text = stepStatus, sort = field("status")},
}

local function selected(p)
	for _, r in ipairs(p.rows or {}) do if r.key == p.selKey then return r end end
	return nil
end
local function selectedAuction(p)
	for _, r in ipairs(X.cancel.rows) do if r.auctionID == p.selAuction then return r end end
	return nil
end
local function boxPrice(p)
	return X.ParseMoney(p.priceBox:GetText())
end
local function boxQty(p)
	local n = tonumber(X.Trim(p.qtyBox:GetText()))
	return n and math.floor(n) or nil
end

-- [[ the right panel: posting one item ]]
local function refreshSell(p)
	local b = p.sellBox
	local row = selected(p)
	local key = row and row.key
	if not row then
		b.title:SetText("|cff999999Pick an item on the left.|r")
		for _, fs in ipairs(b.lines) do fs:SetText("") end
		b.controls:Hide()
		p.post:SetEnabled(false)
		p.post:SetText("Post")
		p.confirm:Hide()
		p.noConfirm:Hide()
		p.post:Show()
		p.postStatus:SetText(X.PostBlocked(nil) or "")
		return
	end
	b.controls:Show()
	local info = row.info or {}
	local live = X.live[key]
	b.title:SetText(UI.ItemCell(key, 16))
	local searched = live and ("searched " .. X.Ago(live.t)) or (X.ahOpen and "searching ..." or "from the last scan")
	b.lines[1]:SetText("Lowest now (not yours): " .. UI.MoneyCell(info.lowest) .. "  |cff999999" ..
		(info.from == "search" and searched or "from the last scan") .. "|r")
	b.lines[2]:SetText("Usual price: " .. UI.MoneyCell(info.usual) .. "   Market: " .. UI.MoneyCell(row.market) ..
		(info.craft and ("   Craft: " .. UI.MoneyCell(info.craft)) or ""))
	b.lines[3]:SetText("Suggested: " .. UI.MoneyCell(row.price) .. "  |cff999999(floor " .. X.MoneyPlain(info.floor) ..
		", ceiling " .. X.MoneyPlain(info.ceiling) .. ")|r")
	b.lines[4]:SetText("|cffaaaaaa" .. (row.reason or "") .. "|r")
	-- the boxes: filled with the suggestion until you type your own
	if p.boxKey ~= key then
		p.boxKey, p.edited, p.qtyEdited = key, false, false
		p.duration = X.PostRule(key).duration
	end
	if not p.edited and not p.priceBox:HasFocus() then p.priceBox:SetText(row.price and X.MoneyPlain(row.price) or "") end
	if not p.qtyEdited and not p.qtyBox:HasFocus() then p.qtyBox:SetText(tostring(row.commodity and row.have or 1)) end
	b.ofText:SetText("of " .. X.Num(row.have) .. (row.commodity and "  (one auction, price of one)" or "  (one auction each)"))
	for d = 1, 3 do p.durButtons[d]:SetSelected(d == p.duration) end
	local unit, qty = boxPrice(p), boxQty(p)
	local deposit = (qty and qty >= 1 and qty <= row.have) and X.PostDeposit(row, p.duration, qty) or nil
	b.deposit:SetText("Deposit: " .. UI.MoneyCell(deposit) .. "     After the cut: " ..
		UI.MoneyCell(unit and qty and X.AfterCut(unit * qty) or nil))
	-- the rule boxes (the item's own value, or the setting)
	local rule = X.PostRule(key)
	local function fill(box, text) if not box:HasFocus() then box:SetText(text) end end
	fill(p.floorBox, tostring(rule.floor))
	fill(p.ceilBox, tostring(rule.ceiling))
	fill(p.underBox, rule.undercut and rule.undercut > 0 and X.MoneyPlain(rule.undercut) or "")
	fill(p.normalBox, rule.normal and X.MoneyPlain(rule.normal) or "")
	b.ruleNote:SetText(next(rule.own) and "|cffffd100this item has its own rules|r" or "|cff999999the general rules|r")
	p.listCheck:SetChecked(X.OnSellList(key))
	-- Post / Confirm
	local state = X.post.state
	local warn = state == "warning" and X.post.key == key
	p.confirm:SetShown(warn)
	p.noConfirm:SetShown(warn)
	p.post:SetShown(not warn)
	local blocked = X.PostBlocked(row, unit, qty)
	if not blocked and deposit and GetMoney and GetMoney() < deposit then blocked = "Not enough money for the deposit." end
	if not blocked and state == "sent" then blocked = X.post.text end
	p.post:SetText(unit and qty and ("Post " .. X.Num(qty) .. " at " .. X.MoneyPlain(unit) .. (qty > 1 and " each" or "")) or "Post")
	p.post:SetEnabled(blocked == nil and not warn)
	p.postStatus:SetText(warn and ("|cffffd100" .. (X.post.text or "") .. "|r") or (blocked and ("|cffff8888" .. blocked .. "|r") or
		("|cff999999" .. (X.post.text or "One click = one auction.") .. "|r")))
end

-- [[ the right panel: one undercut auction ]]
local function refreshCancel(p)
	local b = p.cancelBox
	local r = selectedAuction(p)
	if not r then
		b.title:SetText("|cff999999" .. (#X.cancel.rows > 0 and "Pick an auction on the left." or "Press Cancel scan to check your auctions.") .. "|r")
		for _, fs in ipairs(b.lines) do fs:SetText("") end
		p.cancelButton:SetEnabled(false)
		return
	end
	b.title:SetText(UI.ItemCell(r.key, 16))
	b.lines[1]:SetText("Your auction: " .. X.Num(r.qty) .. " at " .. UI.MoneyCell(r.unit) .. " each")
	b.lines[2]:SetText("Lowest now (not yours): " .. UI.MoneyCell(r.lowest))
	b.lines[3]:SetText("Time left: " .. X.TimeLeftText(r.timeLeftSeconds, r.timeLeft))
	b.lines[4]:SetText("Cancelling costs: " .. (r.cost and UI.MoneyCell(r.cost) or "|cff999999unknown|r") ..
		"  |cff999999(the deposit is not paid back)|r")
	p.cancelButton:SetEnabled(X.ahOpen == true and not r.cancelling)
	p.cancelButton:SetText(r.cancelling and "Cancelling ..." or "Cancel this auction")
end

-- [[ the one-key routine ]]
local function refreshRoutine(p)
	local R = X.routine
	local peek = X.RoutinePeek()
	for i, s in ipairs(R.steps) do
		s.n = i
		s.isNext = peek.step == s
		if s.kind == "cancel" then s.price = s.unit
		elseif s.status == "todo" or s.status == "wait" then s.price = (X.PostPrice(s.key))
		else s.price = s.unit end
	end
	p.routineTable:SetRows(R.steps, R.state == "off" and
		"Press Next step (or your key) to start: XNAH checks your auctions and searches the prices of your sell list." or
		"Nothing to do: no undercut auctions, and nothing of your sell list is in your bags.")
	local b = p.routineBox
	p.nextButton:SetText(peek.text or "Next step")
	local can = peek.what == "start" or peek.what == "done" or peek.what == "cancel" or peek.what == "post" or
		peek.what == "confirm" or peek.what == "finish"
	p.nextButton:SetEnabled(can)
	b.nextText:SetText((peek.what == "done" and "|cff999999Press again to start a new round.|r") or
		(peek.what == "closed" and "|cffff8888The routine works only while the auction house is open.|r") or
		(peek.what == "confirm" and "|cffffd100The auction house warns that this price is far from usual. Press again to post anyway, or Skip.|r") or
		(peek.what == "wait" and "|cff999999Prices are searched about one a second.|r") or "")
	local finished, all = X.RoutineProgress()
	local c = R.counts
	b.progress:SetText(all > 0 and ("Step " .. math.min(finished + 1, all) .. " of " .. all .. "   |cff999999(" .. c.cancelled ..
		" cancelled, " .. c.posted .. " posted, " .. c.skipped .. " skipped)|r") or "")
	b.note:SetText("|cff999999" .. (R.note or (R.state == "off" and R.text) or "") .. "|r")
	local key = GetBindingKey and GetBindingKey("XNAH_NEXT")
	b.keyText:SetText(key and ("Your key: |cffffd100" .. key .. "|r") or
		"|cffff8888No key set yet:|r set one in the game's key bindings, under AddOns > XNAH.")
	p.skipButton:SetEnabled(peek.step ~= nil)
	p.stopButton:SetEnabled(R.state == "on")
	p.restartButton:SetEnabled(X.ahOpen == true and R.cur == nil)
	p.cancelFirst:SetChecked(X.S().routineCancel == true)
	local inBags = 0
	for _, r in ipairs(X.SellItems()) do if X.OnSellList(r.key) then inBags = inBags + 1 end end
	b.listText:SetText("Sell list: " .. #X.SellListKeys() .. " items, " .. inBags .. " of them in your bags.")
end

local function refresh(p)
	local view = p.view
	p.viewSell:SetSelected(view == "sell")
	p.viewCancel:SetSelected(view == "cancel")
	p.viewRoutine:SetSelected(view == "routine")
	p.sellTable:SetShown(view == "sell")
	p.cancelTable:SetShown(view == "cancel")
	p.routineTable:SetShown(view == "routine")
	p.sellBox:SetShown(view == "sell")
	p.cancelBox:SetShown(view == "cancel")
	p.routineBox:SetShown(view == "routine")
	local blocked = X.SearchBlocked()
	p.cancelScan:SetEnabled(blocked == nil and X.cancel.state ~= "asking" and X.cancel.state ~= "checking")
	if view == "routine" then
		p.status:SetText(X.routine.state == "on" and "One press = one step. Cancels first, then posts." or
			"Each press of your key (or of Next step) does the next step: cancel an undercut auction, or post the next item.")
		refreshRoutine(p)
	elseif view == "sell" then
		p.rows = sellRows()
		p.sellTable:SetRows(p.rows, X.ahOpen and "Nothing in your bags can be sold on the auction house." or
			"Nothing to sell in your bags (open the auction house to see exactly what it takes).")
		p.status:SetText(blocked and ("|cffff8888" .. blocked .. ":|r prices from the last scan; posting needs the auction house.") or
			"Click an item: it is searched for the live lowest price. Prices in grey are from the last scan.")
		refreshSell(p)
	else
		p.cancelTable:SetRows(X.cancel.rows, X.cancel.state == "done" and "None of your auctions is undercut." or
			"Press Cancel scan: XNAH asks for your auctions and searches each item for the cheapest price that is not yours.")
		p.status:SetText(X.cancel.text or (blocked and ("|cffff8888" .. blocked .. "|r") or "Your auctions that someone undercut."))
		refreshCancel(p)
	end
end

-- a labelled box for a rule
local function ruleBox(parent, text, x, y, w, onSet)
	local l = K.Label(parent, text)
	l:SetPoint("TOPLEFT", x, y - 4)
	local e = K.Edit(parent, w)
	e:SetPoint("TOPLEFT", x + l:GetStringWidth() + 8, y)
	e:SetScript("OnEditFocusLost", function(self) onSet(X.Trim(self:GetText())) end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	return e
end

local function build(p)
	p.view = "sell"
	p.duration = X.S().postDuration
	p.viewSell = K.Flat(p, 150, 22)
	p.viewSell:SetPoint("TOPLEFT", 0, 0)
	p.viewSell:SetLabel("Sell from your bags")
	p.viewSell.label:SetJustifyH("CENTER")
	p.viewSell:SetScript("OnClick", function() p.view = "sell" refresh(p) end)
	p.viewCancel = K.Flat(p, 150, 22)
	p.viewCancel:SetPoint("TOPLEFT", 154, 0)
	p.viewCancel:SetLabel("Undercut auctions")
	p.viewCancel.label:SetJustifyH("CENTER")
	p.viewCancel:SetScript("OnClick", function() p.view = "cancel" refresh(p) end)
	p.viewRoutine = K.Flat(p, 150, 22)
	p.viewRoutine:SetPoint("TOPLEFT", 308, 0)
	p.viewRoutine:SetLabel("One-key routine")
	p.viewRoutine.label:SetJustifyH("CENTER")
	p.viewRoutine:SetScript("OnClick", function() p.view = "routine" refresh(p) end)
	p.cancelScan = K.Button(p, "Cancel scan", 120, 22, function()
		p.view = "cancel"
		p.selAuction = nil
		X.CancelScan()
		refresh(p)
	end)
	p.cancelScan:SetPoint("TOPRIGHT", 0, 0)
	K.Tooltip(p.cancelScan, "Cancel scan", "Asks the auction house for your auctions, searches each item (one a second) " ..
		"and lists the ones where someone sells for less than you. Cancelling is one click each.")
	local again = K.Button(p, "Search again", 110, 22, function()
		local row = selected(p)
		if row then X.LiveSearch(row.key) end
	end)
	again:SetPoint("RIGHT", p.cancelScan, "LEFT", -6, 0)
	K.Tooltip(again, "Search again", "Searches the picked item again for its live lowest price.")
	p.status = K.Label(p, "", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", 0, -30)
	p.status:SetWidth(W)
	p.status:SetWordWrap(false)

	p.sellTable = K.Table(p, LEFT_W, H - TOP - 20, SELL_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) return end
		p.selKey = row.key
		if X.ahOpen then X.LiveSearch(row.key) end
		refresh(p)
	end)
	p.sellTable:SetPoint("TOPLEFT", 0, -TOP)
	p.cancelTable = K.Table(p, LEFT_W, H - TOP - 20, CANCEL_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) return end
		p.selAuction = row.auctionID
		refresh(p)
	end)
	p.cancelTable:SetPoint("TOPLEFT", 0, -TOP)
	p.routineTable = K.Table(p, LEFT_W, H - TOP - 20, ROUTINE_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) end
	end)
	p.routineTable:SetPoint("TOPLEFT", 0, -TOP)
	local hint = K.Label(p, "|cff999999Click a row to pick it.  Right click: menu.  Click a column title to sort.|r")
	hint:SetPoint("BOTTOMLEFT", 0, 2)

	-- [[ right: posting ]]
	local b = K.Panel(p, RW, H - 52)
	b:SetPoint("TOPLEFT", RX, -52)
	p.sellBox = b
	b.title = K.Label(b, "", "GameFontNormal")
	b.title:SetPoint("TOPLEFT", 10, -10)
	b.title:SetWidth(RW - 20)
	b.title:SetWordWrap(false)
	b.lines = {}
	for i = 1, 4 do
		local fs = K.Label(b, "")
		fs:SetPoint("TOPLEFT", 10, -32 - (i - 1) * 16)
		fs:SetWidth(RW - 20)
		if i == 4 then fs:SetHeight(28) fs:SetWordWrap(true) else fs:SetWordWrap(false) end
		b.lines[i] = fs
	end
	local c = CreateFrame("Frame", nil, b)
	c:SetPoint("TOPLEFT", 0, -112)
	c:SetSize(RW, 260)
	b.controls = c
	local l1 = K.Label(c, "Price each")
	l1:SetPoint("TOPLEFT", 10, -4)
	p.priceBox = K.Edit(c, 110)
	p.priceBox:SetPoint("TOPLEFT", 90, 0)
	p.priceBox:SetScript("OnTextChanged", function(_, user) if user then p.edited = true end end)
	p.priceBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() refresh(p) end)
	p.priceBox:SetScript("OnEditFocusLost", function() refresh(p) end)
	local sugg = K.Button(c, "Suggested", 90, 20, function() p.edited = false refresh(p) end)
	sugg:SetPoint("TOPLEFT", 210, 0)
	local l2 = K.Label(c, "Quantity")
	l2:SetPoint("TOPLEFT", 10, -30)
	p.qtyBox = K.Edit(c, 50)
	p.qtyBox:SetPoint("TOPLEFT", 90, -26)
	p.qtyBox:SetScript("OnTextChanged", function(_, user) if user then p.qtyEdited = true end end)
	p.qtyBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() refresh(p) end)
	p.qtyBox:SetScript("OnEditFocusLost", function() refresh(p) end)
	b.ofText = K.Label(c, "")
	b.ofText:SetPoint("TOPLEFT", 146, -30)
	b.ofText:SetWidth(RW - 150)
	b.ofText:SetWordWrap(false)
	local l3 = K.Label(c, "Duration")
	l3:SetPoint("TOPLEFT", 10, -56)
	p.durButtons = {}
	for d = 1, 3 do
		local db = K.Flat(c, 56, 20)
		db:SetPoint("TOPLEFT", 90 + (d - 1) * 60, -52)
		db:SetLabel(X.DURATION_SHORT[d])
		db.label:SetJustifyH("CENTER")
		db:SetScript("OnClick", function()
			p.duration = d
			if p.selKey then X.SetPostRule(p.selKey, "duration", d ~= X.S().postDuration and d or nil) end
			refresh(p)
		end)
		p.durButtons[d] = db
	end
	b.deposit = K.Label(c, "")
	b.deposit:SetPoint("TOPLEFT", 10, -82)
	b.deposit:SetWidth(RW - 20)
	local rt = K.Label(c, "Price rules", "GameFontNormal")
	rt:SetPoint("TOPLEFT", 10, -108)
	b.ruleNote = K.Label(c, "")
	b.ruleNote:SetPoint("TOPLEFT", 110, -110)
	local function setNum(fieldName, setting)
		return function(text)
			local key = p.selKey
			if not key then return end
			local v = tonumber((text:gsub("%%", "")))
			if text == "" then X.SetPostRule(key, fieldName, nil)
			elseif v and v > 0 then
				v = math.floor(v + 0.5)
				X.SetPostRule(key, fieldName, v ~= X.S()[setting] and v or nil)
			end
			refresh(p)
		end
	end
	local function setMoney(fieldName)
		return function(text)
			local key = p.selKey
			if not key then return end
			local v = X.ParseMoney(text)
			if text == "" then X.SetPostRule(key, fieldName, nil)
			elseif v and v > 0 then X.SetPostRule(key, fieldName, v) end
			refresh(p)
		end
	end
	p.floorBox = ruleBox(c, "Floor %", 10, -130, 40, setNum("floor", "postFloor"))
	p.ceilBox = ruleBox(c, "Ceiling %", 170, -130, 40, setNum("ceiling", "postCeiling"))
	p.underBox = ruleBox(c, "Undercut by", 10, -156, 70, setMoney("undercut"))
	p.normalBox = ruleBox(c, "Normal", 170, -156, 80, setMoney("normal"))
	K.Tooltip(p.floorBox, "Floor", "Never post under this % of the usual price (or under the crafting cost, when known). " ..
		"When the cheapest is under the floor, the normal price is used - no chasing the price down.")
	K.Tooltip(p.ceilBox, "Ceiling", "Never post over this % of the usual price.")
	K.Tooltip(p.underBox, "Undercut by", "How much under the cheapest other seller. Empty = the smallest step (1c, or 1s).")
	K.Tooltip(p.normalBox, "Normal price", "The price when nobody else sells it or the cheapest is under the floor. Empty = the usual price.")
	local reset = K.Button(c, "Back to the general rules", 180, 20, function()
		if p.selKey then X.ResetPostRule(p.selKey) p.duration = X.S().postDuration end
		p.edited = false
		refresh(p)
	end)
	reset:SetPoint("TOPLEFT", 10, -184)
	p.listCheck = K.Check(c, "On the sell list (the one-key routine posts it)", function(on)
		if p.selKey then X.SetSellList(p.selKey, on) end
		refresh(p)
	end)
	p.listCheck:SetPoint("TOPLEFT", 8, -212)
	K.Tooltip(p.listCheck, "Sell list", "The one-key routine (third view of this tab) posts the items of this list that are in " ..
		"your bags, at the suggested price, one press each.")
	p.post = K.Button(b, "Post", RW - 20, 32, function()
		local row = selected(p)
		if row and X.PostClick(row, boxPrice(p), boxQty(p), p.duration) then p.edited, p.qtyEdited = false, false end
		refresh(p)
	end)
	p.post:SetPoint("BOTTOM", 0, 34)
	p.confirm = K.Button(b, "Confirm: post it", RW - 120, 32, function() X.PostConfirmClick() refresh(p) end)
	p.confirm:SetPoint("BOTTOMLEFT", 10, 34)
	p.noConfirm = K.Button(b, "Don't post", 90, 32, function() X.PostCancelWarning() refresh(p) end)
	p.noConfirm:SetPoint("BOTTOMRIGHT", -10, 34)
	p.postStatus = K.Label(b, "", "GameFontHighlightSmall")
	p.postStatus:SetPoint("BOTTOMLEFT", 10, 6)
	p.postStatus:SetWidth(RW - 20)
	p.postStatus:SetHeight(26)

	-- [[ right: cancelling ]]
	local cb = K.Panel(p, RW, H - 52)
	cb:SetPoint("TOPLEFT", RX, -52)
	p.cancelBox = cb
	cb.title = K.Label(cb, "", "GameFontNormal")
	cb.title:SetPoint("TOPLEFT", 10, -10)
	cb.title:SetWidth(RW - 20)
	cb.lines = {}
	for i = 1, 4 do
		local fs = K.Label(cb, "")
		fs:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 18)
		fs:SetWidth(RW - 20)
		cb.lines[i] = fs
	end
	p.cancelButton = K.Button(cb, "Cancel this auction", RW - 20, 32, function()
		X.CancelClick(selectedAuction(p))
		refresh(p)
	end)
	p.cancelButton:SetPoint("BOTTOM", 0, 34)
	local note = K.Label(cb, "|cff999999One click = one auction cancelled. The items come back by mail.|r")
	note:SetPoint("BOTTOMLEFT", 10, 10)
	note:SetWidth(RW - 20)
	cb:Hide()

	-- [[ right: the one-key routine ]]
	local rb = K.Panel(p, RW, H - 52)
	rb:SetPoint("TOPLEFT", RX, -52)
	p.routineBox = rb
	local rt = K.Label(rb, "One-key routine", "GameFontNormal")
	rt:SetPoint("TOPLEFT", 10, -10)
	local intro = K.Label(rb, "Each press does the next step: first it cancels your auctions that someone undercut, then it " ..
		"posts the items of your sell list that are in your bags, at XNAH's suggested price. The game allows one action per " ..
		"click or key press, so press once for each step. It never buys anything.")
	intro:SetPoint("TOPLEFT", 10, -32)
	intro:SetWidth(RW - 20)
	intro:SetHeight(70)
	intro:SetJustifyV("TOP")
	intro:SetWordWrap(true)
	rb.keyText = K.Label(rb, "")
	rb.keyText:SetPoint("TOPLEFT", 10, -108)
	rb.keyText:SetWidth(RW - 20)
	rb.keyText:SetHeight(28)
	rb.keyText:SetJustifyV("TOP")
	rb.keyText:SetWordWrap(true)
	p.nextButton = K.Button(rb, "Next step", RW - 20, 48, function()
		X.RoutineNext("button")
		refresh(p)
	end)
	p.nextButton:SetPoint("TOPLEFT", 10, -140)
	local nfs = p.nextButton:GetFontString()
	if nfs then
		nfs:SetWidth(RW - 36)
		nfs:SetWordWrap(true)
	end
	K.Tooltip(p.nextButton, "Next step", "Does what the button says: one cancel or one post per press. Your key for the " ..
		"one-key routine does the same while the auction house is open.")
	rb.nextText = K.Label(rb, "")
	rb.nextText:SetPoint("TOPLEFT", 10, -196)
	rb.nextText:SetWidth(RW - 20)
	rb.nextText:SetHeight(30)
	rb.nextText:SetJustifyV("TOP")
	rb.nextText:SetWordWrap(true)
	rb.progress = K.Label(rb, "", "GameFontHighlight")
	rb.progress:SetPoint("TOPLEFT", 10, -232)
	rb.progress:SetWidth(RW - 20)
	rb.progress:SetWordWrap(false)
	rb.note = K.Label(rb, "")
	rb.note:SetPoint("TOPLEFT", 10, -254)
	rb.note:SetWidth(RW - 20)
	rb.note:SetWordWrap(false)
	p.skipButton = K.Button(rb, "Skip this step", 110, 22, function() X.RoutineSkip() refresh(p) end)
	p.skipButton:SetPoint("TOPLEFT", 10, -278)
	K.Tooltip(p.skipButton, "Skip this step", "Leaves the next step out (or says no to a price warning).")
	p.restartButton = K.Button(rb, "Start over", 100, 22, function() X.RoutineStart() refresh(p) end)
	p.restartButton:SetPoint("LEFT", p.skipButton, "RIGHT", 6, 0)
	K.Tooltip(p.restartButton, "Start over", "Checks your auctions and your bags again and makes a new list of steps.")
	p.stopButton = K.Button(rb, "Stop", 80, 22, function() X.RoutineStop() refresh(p) end)
	p.stopButton:SetPoint("LEFT", p.restartButton, "RIGHT", 6, 0)
	p.cancelFirst = K.Check(rb, "Cancel undercut auctions first", function(on)
		X.S().routineCancel = on
		refresh(p)
	end)
	p.cancelFirst:SetPoint("TOPLEFT", 8, -312)
	K.Tooltip(p.cancelFirst, "Cancel undercut auctions first", "Off: the routine only posts. Cancelled items come back by mail, " ..
		"so they are posted again on a later round, once they are in your bags.")
	rb.listText = K.Label(rb, "")
	rb.listText:SetPoint("TOPLEFT", 10, -344)
	rb.listText:SetWidth(RW - 20)
	local how = K.Label(rb, "|cff999999To put an item on the sell list: view \"Sell from your bags\", pick the item, tick \"On the " ..
		"sell list\". Its price follows that item's price rules.|r")
	how:SetPoint("TOPLEFT", 10, -362)
	how:SetWidth(RW - 20)
	how:SetHeight(42)
	how:SetJustifyV("TOP")
	how:SetWordWrap(true)
	rb:Hide()
end

UI.AddTab("sell", "Sell", build, refresh, 6)
