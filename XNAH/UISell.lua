-- The Sell tab. It opens on "Worth posting": your undercut auctions first (with their Cancel step), then everything in
-- your bags that can go on the auction house, with XNAH's price. What is worth posting is ticked; untick what you want
-- to keep (XNAH remembers it per item). One big "Post next" button (or your key for it) does the next step of the
-- one-key routine (Routine.lua): cancel an undercut auction, or post the next ticked item - one per press, as the game
-- allows. Your auctions are checked by themselves when the auction house opens (Post.lua).
-- The other views: "Undercut auctions" (your auctions someone sells cheaper, one Cancel click each) and "Post by hand"
-- (one item: your own price, amount, duration, and its price rules - floor, ceiling, undercut, normal price).
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 70         -- where the table starts (its column titles sit just above)
local LEFT_W = 600     -- table width
local RX, RW = 612, 328 -- the panel on the right

for _, e in ipairs({"XNAH_LIVE", "XNAH_POST", "XNAH_CANCEL", "XNAH_ROUTINE", "XNAH_SELLTICK", "BAG_UPDATE_DELAYED"}) do
	X.On(e, function() UI.Refresh() end)
end

local GREY, GREEN, RED, GOLD = "|cff999999", "|cff33ff33", "|cfff87171", "|cffffd100"
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end

-- [[ rows of the "Post by hand" view ]] (worked out on every refresh: a bag holds few items)
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
	{"Item", 190, "LEFT", text = itemCell, sort = itemName, desc = false},
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
-- the Worth posting list (its own rows: each has a tick box)
local WORTH_COLUMNS = {{"", 24, "LEFT"}, {"Item", 176, "LEFT"}, {"Have", 44, "RIGHT"}, {"Lowest now", 78, "RIGHT"},
	{"XNAH price", 78, "RIGHT"}, {"Brings", 74, "RIGHT"}, {"Step", 104, "LEFT"}}

-- [[ the Worth posting rows ]] undercut auctions first, then the ticked bag items (most valuable first), then the rest
local function worthRows()
	local out = {}
	for _, a in ipairs(X.cancel.rows or {}) do
		out[#out + 1] = {kind = "cancel", key = a.key, a = a, id = "a" .. tostring(a.auctionID)}
	end
	for _, row in ipairs(X.SellItems()) do
		local worth, w = X.SellWorth(row)
		local choice = X.SellChoice(row.key)
		local ticked
		if choice == nil then ticked = worth else ticked = choice end
		out[#out + 1] = {kind = "post", key = row.key, row = row, worth = worth, w = w, ticked = ticked, choice = choice,
			id = "p" .. row.key}
	end
	table.sort(out, function(a, b)
		if a.kind ~= b.kind then return a.kind == "cancel" end
		if a.kind == "post" then
			if a.ticked ~= b.ticked then return a.ticked end
			local va, vb = a.w.net or -1, b.w.net or -1
			if va ~= vb then return va > vb end
		end
		return a.id < b.id
	end)
	return out
end

-- the routine's word for a row: next, posted, skipped ...
local function stepOf(r, peek)
	local R = X.routine
	local first, done, skipped, why
	for _, s in ipairs(R.steps) do
		local mine
		if r.kind == "cancel" then mine = s.kind == "cancel" and s.auctionID == r.a.auctionID
		else mine = s.kind == "post" and s.key == r.key end
		if mine then
			if s == peek.step then return GOLD .. "next|r" end
			if s.status == "sent" then return "waiting ..." end
			if s.status == "todo" or s.status == "wait" then first = first or s.status end
			if s.status == "done" then done = true end
			if s.status == "skipped" then skipped, why = true, s.why end
		end
	end
	if first == "todo" then return "to do" end
	if first == "wait" then return GREY .. "checking price|r" end
	if r.kind == "cancel" then
		if done then return GREEN .. "cancelled|r" end
		local by = (r.a.unit and r.a.lowest) and (r.a.unit - r.a.lowest) or nil
		return RED .. "undercut" .. (by and (" by " .. X.MoneyPlain(by)) or "") .. "|r"
	end
	if done then return GREEN .. "posted|r" end
	if skipped then return RED .. "skipped|r" .. (why and (GREY .. ": " .. why .. "|r") or "") end
	if r.choice == false then return GREY .. "kept|r" end
	if not r.ticked then return GREY .. (r.w.why or "not ticked") .. "|r" end
	return ""
end

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

-- [[ the right panel: posting one item by hand ]]
local function refreshSell(p)
	local b = p.sellBox
	local row = selected(p)
	local key = row and row.key
	if not row then
		b.title:SetText(GREY .. "Pick an item on the left.|r")
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
	b.lines[1]:SetText("Lowest now (not yours): " .. UI.MoneyCell(info.lowest) .. "  " .. GREY ..
		(info.from == "search" and searched or "from the last scan") .. "|r")
	b.lines[2]:SetText("Usual price: " .. UI.MoneyCell(info.usual) .. "   Market: " .. UI.MoneyCell(row.market) ..
		(info.craft and ("   Craft: " .. UI.MoneyCell(info.craft)) or ""))
	b.lines[3]:SetText("Suggested: " .. UI.MoneyCell(row.price) .. "  " .. GREY .. "(floor " .. X.MoneyPlain(info.floor) ..
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
	b.ruleNote:SetText(next(rule.own) and (GOLD .. "this item has its own rules|r") or (GREY .. "the general rules|r"))
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
	p.postStatus:SetText(warn and (GOLD .. (X.post.text or "") .. "|r") or (blocked and ("|cffff8888" .. blocked .. "|r") or
		(GREY .. (X.post.text or "One click = one auction.") .. "|r")))
end

-- [[ the right panel: one undercut auction ]]
local function refreshCancel(p)
	local b = p.cancelBox
	local r = selectedAuction(p)
	if not r then
		b.title:SetText(GREY .. (#X.cancel.rows > 0 and "Pick an auction on the left." or "Press Check auctions to check your auctions.") .. "|r")
		for _, fs in ipairs(b.lines) do fs:SetText("") end
		p.cancelButton:SetEnabled(false)
		return
	end
	b.title:SetText(UI.ItemCell(r.key, 16))
	b.lines[1]:SetText("Your auction: " .. X.Num(r.qty) .. " at " .. UI.MoneyCell(r.unit) .. " each")
	b.lines[2]:SetText("Lowest now (not yours): " .. UI.MoneyCell(r.lowest))
	b.lines[3]:SetText("Time left: " .. X.TimeLeftText(r.timeLeftSeconds, r.timeLeft))
	b.lines[4]:SetText("Cancelling costs: " .. (r.cost and UI.MoneyCell(r.cost) or (GREY .. "unknown|r")) ..
		"  " .. GREY .. "(the deposit is not paid back)|r")
	p.cancelButton:SetEnabled(X.ahOpen == true and not r.cancelling)
	p.cancelButton:SetText(r.cancelling and "Cancelling ..." or "Cancel this auction")
end

-- [[ the Worth posting view and its Post next panel ]]
local NEXT_ON = {start = true, done = true, cancel = true, post = true, confirm = true, finish = true}
local function pickedWorth(p)
	for _, r in ipairs(p.worthRows or {}) do if r.id == p.selWorth then return r end end
	return nil
end
local function refreshWorth(p)
	X.RoutineAuto() -- a round starts by itself while you look at this view (it only asks and searches)
	local R = X.routine
	local peek = X.RoutinePeek()
	p.peek = peek
	local rows = worthRows()
	p.worthRows = rows
	p.worthList:SetItems(rows, X.ahOpen and "Nothing in your bags can go on the auction house, and none of your auctions is undercut." or
		"Nothing to sell in your bags (open the auction house to see exactly what it takes).")
	local rb = p.routineBox
	p.nextButton:SetText(peek.text or "Post next")
	p.nextButton:SetEnabled(NEXT_ON[peek.what] == true)
	rb.nextText:SetText((peek.what == "done" and (GREY .. "Press again to look for more.|r")) or
		(peek.what == "closed" and "|cffff8888Posting works only while the auction house is open.|r") or
		(peek.what == "confirm" and (GOLD .. "The auction house warns that this price is far from usual. Press again to post anyway, or Skip.|r")) or
		(peek.what == "wait" and (GREY .. "Prices are searched about one a second.|r")) or "")
	local finished, all = X.RoutineProgress()
	local c = R.counts
	rb.progress:SetText(all > 0 and ("Step " .. math.min(finished + 1, all) .. " of " .. all .. "   " .. GREY .. "(" .. c.cancelled ..
		" cancelled, " .. c.posted .. " posted, " .. c.skipped .. " skipped)|r") or "")
	rb.note:SetText(GREY .. (R.note or (R.state == "off" and R.text) or "") .. "|r")
	local key = GetBindingKey and GetBindingKey("XNAH_NEXT")
	rb.keyText:SetText(key and ("Your key: " .. GOLD .. key .. "|r") or
		"|cffff8888No key set yet:|r set one in the game's key bindings, under AddOns > XNAH (One-key routine).")
	p.skipButton:SetEnabled(peek.step ~= nil or (R.cur ~= nil and X.post.state == "warning"))
	p.stopButton:SetEnabled(R.state == "on")
	p.restartButton:SetEnabled(X.ahOpen == true and R.cur == nil)
	p.cancelFirst:SetChecked(X.S().routineCancel == true)
	-- the picked row
	local r = pickedWorth(p)
	if not r then
		rb.pickTitle:SetText(GREY .. "Click a row for its price and why.|r")
		rb.pickWhy:SetText("")
		p.rulesButton:Hide()
	elseif r.kind == "cancel" then
		rb.pickTitle:SetText(UI.ItemCell(r.key, 16))
		rb.pickWhy:SetText("You ask " .. X.MoneyPlain(r.a.unit) .. " each, someone else " .. X.MoneyPlain(r.a.lowest) ..
			": yours will not sell. Post next cancels it first; it comes back by mail, then post it again.")
		p.rulesButton:Hide()
	else
		rb.pickTitle:SetText(UI.ItemCell(r.key, 16))
		local w = r.w
		rb.pickWhy:SetText("XNAH price: " .. UI.MoneyCell(w.price) .. "  " .. GREY .. (w.reason or "") .. "|r" ..
			(w.why and ("\n" .. RED .. "Not worth posting: " .. w.why .. "|r") or ""))
		p.rulesButton:Show()
	end
end

local function refresh(p)
	local view = p.view
	p.viewWorth:SetSelected(view == "worth")
	p.viewCancel:SetSelected(view == "cancel")
	p.viewSell:SetSelected(view == "sell")
	p.worthList:SetShown(view == "worth")
	p.sellTable:SetShown(view == "sell")
	p.cancelTable:SetShown(view == "cancel")
	p.routineBox:SetShown(view == "worth")
	p.sellBox:SetShown(view == "sell")
	p.cancelBox:SetShown(view == "cancel")
	local blocked = X.SearchBlocked()
	local cs = X.cancel.state
	local checking = cs == "asking" or cs == "checking"
	p.cancelScan:SetEnabled(blocked == nil and not checking)
	p.cancelScan:SetText(checking and "Checking ..." or "Check auctions")
	if view == "worth" then
		p.status:SetText(not X.ahOpen and ("|cffff8888The auction house is closed:|r prices from the last scan. Open it to post.") or
			(checking and (X.cancel.text or "Checking your auctions ...")) or
			"Ticked items are posted by Post next (or your key), most valuable first. Untick what you want to keep.")
		refreshWorth(p)
	elseif view == "sell" then
		p.rows = sellRows()
		p.sellTable:SetRows(p.rows, X.ahOpen and "Nothing in your bags can be sold on the auction house." or
			"Nothing to sell in your bags (open the auction house to see exactly what it takes).")
		p.status:SetText(blocked and ("|cffff8888" .. blocked .. ":|r prices from the last scan; posting needs the auction house.") or
			"Click an item: it is searched for the live lowest price. Prices in grey are from the last scan.")
		refreshSell(p)
	else
		p.cancelTable:SetRows(X.cancel.rows, cs == "done" and "None of your auctions is undercut." or
			"XNAH checks your auctions by itself when the auction house opens (or press Check auctions).")
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
local function viewButton(p, text, x, view)
	local b = K.Flat(p, 150, 22)
	b:SetPoint("TOPLEFT", x, 0)
	b:SetLabel(text)
	b.label:SetJustifyH("CENTER")
	b:SetScript("OnClick", function() p.view = view refresh(p) end)
	return b
end
local function wrapLabel(parent, y, h, font)
	local fs = K.Label(parent, "", font)
	fs:SetPoint("TOPLEFT", 10, y)
	fs:SetWidth(RW - 20)
	if h then
		fs:SetHeight(h)
		fs:SetJustifyV("TOP")
		fs:SetWordWrap(true)
	else
		fs:SetWordWrap(false)
	end
	return fs
end

-- the Worth posting list and the Post next panel
local function buildWorth(p)
	p.worthList = K.List(p, LEFT_W, H - TOP - 20, 22, function(row, r)
		local priceText, lowText, haveText, bringText
		if r.kind == "cancel" then
			haveText = X.Num(r.a.qty or 1)
			lowText = UI.MoneyCell(r.a.lowest)
			priceText = RED .. X.MoneyPlain(r.a.unit) .. "|r"
			bringText = GREY .. "-|r"
		else
			local w = r.w
			local info = w.info or {}
			haveText = X.Num(r.row.have)
			lowText = UI.MoneyCell(info.lowest, info.from == "scan")
			priceText = UI.MoneyCell(w.price)
			bringText = w.net and ((r.ticked and "" or GREY) .. X.MoneyPlain(math.floor(w.net)) .. (r.ticked and "" or "|r")) or (GREY .. "-|r")
		end
		row:SetCols("", UI.ItemCell(r.key), haveText, lowText, priceText, bringText, stepOf(r, p.peek or {}))
		row:SetSelected(r.id == p.selWorth)
		if not row.check then
			row.check = K.Check(row, "", function(on)
				local item = row.item
				if item and item.kind == "post" then X.SetSellTick(item.key, on, item.row) end
				refresh(p)
			end)
			row.check:SetPoint("LEFT", 1, 0)
			row.check:SetSize(20, 20)
			K.Tooltip(row.check, "Post it?", "Ticked: Post next (and your key) posts it. Untick to keep it - XNAH remembers.")
		end
		row.item = r
		row.check:SetShown(r.kind == "post")
		row.check:SetChecked(r.kind == "post" and r.ticked == true)
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then UI.ItemMenu(self, r.key) return end
			p.selWorth = r.id
			refresh(p)
		end)
		row:SetScript("OnEnter", function(self) UI.ItemTooltip(self, r.key) end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end, WORTH_COLUMNS)
	p.worthList:SetPoint("TOPLEFT", 0, -TOP)

	local rb = K.Panel(p, RW, H - 52)
	rb:SetPoint("TOPLEFT", RX, -52)
	p.routineBox = rb
	local rt = K.Label(rb, "Post next", "GameFontNormal")
	rt:SetPoint("TOPLEFT", 10, -10)
	local intro = wrapLabel(rb, -30, 56)
	intro:SetText("Each press does the next step: cancel an auction someone undercut, or post the next ticked item at " ..
		"XNAH's price. One press = one auction - the game allows no more. It never buys anything.")
	rb.keyText = wrapLabel(rb, -90, 28)
	p.nextButton = K.Button(rb, "Post next", RW - 20, 48, function()
		X.RoutineNext("button")
		refresh(p)
	end)
	p.nextButton:SetPoint("TOPLEFT", 10, -122)
	local nfs = p.nextButton:GetFontString()
	if nfs then
		nfs:SetWidth(RW - 36)
		nfs:SetWordWrap(true)
	end
	K.Tooltip(p.nextButton, "Post next", "Does what the button says: one cancel or one post per press. Your key for the " ..
		"one-key routine does the same while the auction house is open.")
	rb.nextText = wrapLabel(rb, -176, 30)
	rb.progress = wrapLabel(rb, -210, nil, "GameFontHighlight")
	rb.note = wrapLabel(rb, -230)
	p.skipButton = K.Button(rb, "Skip this step", 110, 22, function() X.RoutineSkip() refresh(p) end)
	p.skipButton:SetPoint("TOPLEFT", 10, -250)
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
	p.cancelFirst:SetPoint("TOPLEFT", 8, -280)
	K.Tooltip(p.cancelFirst, "Cancel undercut auctions first", "Off: Post next only posts. Cancelled items come back by mail, " ..
		"so they are posted again once they are in your bags.")
	rb.pickTitle = wrapLabel(rb, -316, nil, "GameFontNormal")
	rb.pickWhy = wrapLabel(rb, -338, 70)
	p.rulesButton = K.Button(rb, "Price rules for this item", 170, 22, function()
		local r = pickedWorth(p)
		if r then p.selKey = r.key end
		p.view = "sell"
		if r and X.ahOpen then X.LiveSearch(r.key) end
		refresh(p)
	end)
	p.rulesButton:SetPoint("TOPLEFT", 10, -414)
	K.Tooltip(p.rulesButton, "Price rules", "Opens Post by hand with this item: its floor, ceiling, undercut and normal price.")
	local foot = wrapLabel(rb, -446, 40)
	foot:SetText(GREY .. "Ticked = worth posting (it brings more than a vendor pays). Untick to keep an item; tick anything " ..
		"to post it anyway.|r")
end

local function build(p)
	p.view = "worth"
	p.duration = X.S().postDuration
	p.viewWorth = viewButton(p, "Worth posting", 0, "worth")
	p.viewCancel = viewButton(p, "Undercut auctions", 154, "cancel")
	p.viewSell = viewButton(p, "Post by hand", 308, "sell")
	p.cancelScan = K.Button(p, "Check auctions", 120, 22, function()
		p.selAuction = nil
		X.CancelScan()
		refresh(p)
	end)
	p.cancelScan:SetPoint("TOPRIGHT", 0, 0)
	K.Tooltip(p.cancelScan, "Check auctions", "Asks the auction house for your auctions, searches each item (one a second) " ..
		"and lists the ones where someone sells for less than you. XNAH also does this by itself when the auction house " ..
		"opens (at most every 5 minutes). Cancelling is one click each.")
	local again = K.Button(p, "Search again", 110, 22, function()
		local key = p.view == "worth" and (pickedWorth(p) or {}).key or p.selKey
		if key then X.LiveSearch(key) end
	end)
	again:SetPoint("RIGHT", p.cancelScan, "LEFT", -6, 0)
	K.Tooltip(again, "Search again", "Searches the picked item again for its live lowest price.")
	p.status = K.Label(p, "", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", 0, -30)
	p.status:SetWidth(W)
	p.status:SetWordWrap(false)

	buildWorth(p)
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
	local hint = K.Label(p, GREY .. "Click a row to pick it.  Right click: menu.|r")
	hint:SetPoint("BOTTOMLEFT", 0, 2)

	-- [[ right: posting by hand ]]
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
	local ruleHint = K.Label(c, GREY .. "Post next (view Worth posting) uses these rules too.|r")
	ruleHint:SetPoint("TOPLEFT", 10, -214)
	ruleHint:SetWidth(RW - 20)
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
	b:Hide()

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
	local note = K.Label(cb, GREY .. "One click = one auction cancelled. The items come back by mail.|r")
	note:SetPoint("BOTTOMLEFT", 10, 10)
	note:SetWidth(RW - 20)
	cb:Hide()
end

UI.AddTab("sell", "Sell", build, refresh, 5)
