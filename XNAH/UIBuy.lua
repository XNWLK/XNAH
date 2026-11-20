-- The Buy tab. It opens on "Best buys": the best buys right now (X.BuyIdeas in Buy.lua: your shopping lists and
-- watched items under your max price first, then the strategies' ideas and the deals), each with a Buy button, and the
-- "Next buy" box: one key (or its big button) does the next step of the best buy. The second view keeps the shopping
-- lists, the purchase panel and the sniper.
-- Buying is always a click on our button (or a key press): stackable items take two (the first asks the server for the
-- exact price, the second buys), other items one per auction.
--
-- UI.BuyButton(parent, w, h) -> a button for any page (deal rows, the item page): btn:SetItem(key, qty, maxEach,
-- source, tag) (qty nil = as many as are listed at or under maxEach; maxEach nil = XNAH's limit, X.BuyLimit). It walks
-- the steps itself: "Buy" (checks the price) -> "Buy 4 for 2g 10s" -> "Confirm 4 for 2g 10s" (stackable items) ->
-- "Bought 4". Each click does at most ONE buying call, and only what its label says.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local VIEW_H = 28           -- the row of view buttons
local CH = H - VIEW_H       -- height of a view (522)
local TOP = 70
local LEFT_W = 560
local RX, RW = 572, 368
local BEST_W = 620          -- the best buys list
local BX, BW = 628, 312     -- the Next buy box

for _, e in ipairs({"XNAH_BUY", "XNAH_SHOP", "XNAH_SNIPE", "XNAH_LIVE", "XNAH_BUYIDEAS", "XNAH_STRATEGY"}) do
	X.On(e, function() UI.Refresh() end)
end

local function gold() return GetMoney and GetMoney() or 0 end
local function plain(c) return X.MoneyPlain(math.floor((c or 0) + 0.5)) end

-- [[ the Buy button for any page ]]
local buyButtons = setmetatable({}, {__mode = "k"})
-- what the button says and does now: text, enabled, run (function), tooltip text
local function buyState(btn)
	local key = btn.key
	if not key then return "Buy", false end
	if not X.ahOpen then return "Open the auction house", false, nil, "Buying works only while the auction house window is open." end
	local b = X.buy
	local s = b.state
	local mine = b.key == key and b.source == btn.source and b.tag == btn.tag
	if not mine then
		if s == "quoting" or s == "confirm" or s == "buying" then
			return "Wait: another purchase", false, nil, "Finish or cancel the purchase going on first (tab Buy)."
		end
		if X.scan.state ~= "idle" then return "Wait for the scan", false, nil, "Buying waits until the scan is done." end
		return "Buy", true, function() X.BuyStart(key, btn.qty, btn.max, btn.source, btn.tag) end,
			"Checks the live price first - this click buys nothing. " ..
			(btn.qty and ("Up to " .. X.Num(btn.qty)) or "As many as are listed") ..
			(btn.max and (" at most " .. plain(btn.max) .. " each.") or " at any price.")
	end
	if s == "ready" and b.plan then
		local p = b.plan
		if p.total > gold() then return "Not enough gold", false end
		return "Buy " .. X.Num(p.qty) .. " for " .. plain(p.total), true, X.BuyClick,
			p.commodity and "Asks the server for the exact price; the next click buys." or "This click buys this auction."
	elseif s == "confirm" and b.quote then
		if (b.quote.total or 0) > gold() then return "Not enough gold", false end
		return "Confirm " .. X.Num(b.quote.qty) .. " for " .. plain(b.quote.total), true, X.BuyClick,
			"The exact price from the server. This click buys."
	elseif s == "quoting" then return "Asking the price ...", false
	elseif s == "buying" then return "Buying ...", false
	elseif s == "toohigh" then return "Price went up: check again", true, X.BuyCancel, b.text
	elseif s == "none" then
		return "None at your price", true, X.BuyResearch, (b.text or "") .. " Click to check again."
	elseif s == "done" then return "Bought " .. X.Num(b.bought or 0), false, nil, "Bought " .. X.Num(b.bought or 0) .. " for " .. plain(b.spent) .. "."
	end
	return "Checking the price ...", false
end
local function updateBuy(btn)
	local text, on, run, tip = buyState(btn)
	btn.shownText, btn.tip = text, tip
	btn:SetText(text)
	btn:SetEnabled(on and run ~= nil)
end
function UI.UpdateBuyButtons()
	for btn in pairs(buyButtons) do
		if btn:IsVisible() then updateBuy(btn) end
	end
end
for _, e in ipairs({"XNAH_BUY", "XNAH_AH", "XNAH_SCAN", "PLAYER_MONEY"}) do X.On(e, function() UI.UpdateBuyButtons() end) end

function UI.BuyButton(parent, w, h)
	local btn = K.Button(parent, "Buy", w or 140, h or 22)
	buyButtons[btn] = true
	btn:SetScript("OnClick", function(self)
		local text, on, run = buyState(self)
		-- only what the label says: when things changed since it was drawn, the click only shows the new label
		if text == self.shownText and on and run then run() end
		UI.UpdateBuyButtons()
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.key and X.ItemText(self.key) or "Buy")
		if self.tip then GameTooltip:AddLine(self.tip, 1, 1, 1, true) end
		GameTooltip:AddLine("One click = one step. Stackable items: the first click asks the exact price, the second buys.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
	function btn:SetItem(key, qty, maxEach, source, tag)
		self.key = key
		self.source = source or "button"
		if maxEach == nil and key then maxEach = X.BuyLimit(key) end
		if qty == nil and maxEach == nil then qty = 1 end -- no price known at all: never "everything at any price"
		self.qty, self.max = qty, maxEach
		self.tag = tag or (self.source .. ":" .. tostring(key))
		updateBuy(self)
	end
	updateBuy(btn)
	return btn
end

local function field(name) return function(r) return r[name] end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end
local function lowestOf(key)
	local live = X.LiveLowest(key)
	if live then return live, false end
	return X.Price(key, "min"), true
end

local SHOP_COLUMNS = {
	{"Item", 180, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Need", 45, "RIGHT", text = function(e) return X.Num(X.ShopNeed(e)) end, sort = function(e) return X.ShopNeed(e) end},
	{"Bought", 50, "RIGHT", text = function(e) return X.Num(e.bought or 0) .. "/" .. X.Num(e.qty) end, sort = field("bought")},
	{"Max", 80, "RIGHT", text = function(e) return e.max and UI.MoneyCell(e.max) or "|cff999999any|r" end, sort = field("max")},
	{"Lowest now", 80, "RIGHT", text = function(e) local v, old = lowestOf(e.key) return UI.MoneyCell(v, old) end,
		sort = function(e) return (lowestOf(e.key)) end, desc = false},
	{"Cost to buy rest", 105, "RIGHT", text = function(e)
		local cost, n = X.ShopCost(e)
		if cost == nil then return "|cff999999-|r" end
		local short = n and n < X.ShopNeed(e)
		return UI.MoneyCell(cost, n == nil) .. (short and (" |cffff8888(" .. n .. ")|r") or "")
	end, sort = function(e) return (X.ShopCost(e)) end},
}
local WATCH_COLUMNS = {
	{"Watched item", 220, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Max price", 120, "RIGHT", text = function(r) return r.max and UI.MoneyCell(r.max) or "|cff999999none|r" end, sort = field("max")},
}
local HIT_COLUMNS = {
	{"Hit", 165, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Price", 85, "RIGHT", text = function(h) return UI.MoneyCell(h.unit) end, sort = field("unit"), desc = false},
	{"Qty", 40, "RIGHT", text = function(h) return X.Num(h.qty) end, sort = field("qty")},
	{"Seen", 50, "RIGHT", text = function(h) return X.Ago(h.t) end, sort = field("t")},
}
-- the best buys list (its own rows: each has a Buy button)
local BEST_COLUMNS = {{"Item", 166, "LEFT"}, {"Why", 110, "LEFT"}, {"Qty", 40, "RIGHT"}, {"Price now", 72, "RIGHT"},
	{"You make", 72, "RIGHT"}, {"", 140, "LEFT"}}
local RISK = {Low = "", Medium = "", High = " |cfff87171(risky)|r"}

local function currentList(p)
	local names = X.ShopLists()
	if not p.list or not X.ShopList(p.list) then p.list = X.S().shopList end
	if not p.list or not X.ShopList(p.list) then p.list = names[1] end
	return p.list
end

-- [[ the purchase panel ]] (the lists view)
local function refreshBuy(p)
	local b = X.buy
	local box = p.buyBox
	if not b.key then
		box.title:SetText("|cff999999Pick an item of a list, or a sniper hit.|r")
		box.line1:SetText("")
		box.line2:SetText("")
	else
		box.title:SetText(UI.ItemCell(b.key, 16) .. (b.source == "snipe" and "  |cffffd100(sniper hit)|r" or
			((b.source == "shop" and b.tag) and ("  |cff999999(list " .. b.tag .. ")|r") or "")))
		box.line1:SetText("Still to buy: " .. X.Num(b.need or 0) .. "   at most " .. (b.max and X.Money(b.max) or "any price") ..
			" each" .. ((b.bought or 0) > 0 and ("   |cff4ade80bought " .. X.Num(b.bought) .. " for " .. X.MoneyPlain(b.spent) .. "|r") or ""))
		local plan = b.plan
		if plan and b.state == "ready" then
			local cheapest = plan.offers[1] and plan.offers[1].unit
			box.line2:SetText("Can buy now: " .. X.Num(plan.qty) .. " for " .. X.Money(plan.total) .. "  (from " .. X.Money(cheapest) .. " each)")
		elseif b.quote and (b.state == "confirm" or b.state == "toohigh") then
			box.line2:SetText("Exact price: " .. X.Money(b.quote.unit) .. " each, " .. X.Money(b.quote.total) .. " in all")
		else
			box.line2:SetText("")
		end
	end
	box.state:SetText("|cffaaaaaa" .. (b.text or (X.ahOpen and "" or "Open the auction house to buy.")) .. "|r")
	local text, on = X.BuyButton()
	p.buyButton:SetText(text)
	p.buyButton:SetEnabled(on)
	local s = b.state
	p.stopButton:SetEnabled(s == "quoting" or s == "confirm" or s == "toohigh")
	p.againButton:SetEnabled(b.key ~= nil and X.ahOpen == true and s ~= "quoting" and s ~= "confirm" and s ~= "buying")
end

-- [[ the sniper ]]
local function refreshSnipe(p)
	local s = X.snipe
	p.snipeButton:SetText(s.on and "Sniper: ON" or "Sniper: off")
	local pause = X.SnipePause()
	local text
	if not s.on then text = "Off. Watched items with a max price are searched over and over while it is on."
	elseif pause then text = "Waiting: " .. pause .. "."
	elseif s.current then text = "Searching " .. X.ItemName(s.current) .. " (round " .. (s.round + 1) .. ")"
	elseif (s.waitUntil or 0) > GetTime() then text = "Round " .. s.round .. " done; next in " .. math.ceil(s.waitUntil - GetTime()) .. " s."
	else text = "Searching ..." end
	p.snipeStatus:SetText("|cffaaaaaa" .. text .. "|r")
	if not p.waitBox:HasFocus() then p.waitBox:SetText(tostring(X.S().snipeWait)) end
	local rows = {}
	for key in pairs(X.db.watch) do rows[#rows + 1] = {key = key, max = X.WatchMax(key)} end
	p.watchTable:SetRows(rows, "No watched items. Star items (right click: Add to watch list) to watch them.")
	if p.watchKey and not X.Watched(p.watchKey) then p.watchKey = nil end
	p.maxLabel:SetText(p.watchKey and ("Max price for " .. X.ItemText(p.watchKey) .. ":") or "|cff999999Pick a watched item to set its max price.|r")
	p.maxBox:SetShown(p.watchKey ~= nil)
	if p.watchKey and not p.maxBox:HasFocus() then
		local m = X.WatchMax(p.watchKey)
		p.maxBox:SetText(m and X.MoneyPlain(m) or "")
	end
	p.hitTable:SetRows(X.SnipeHits(), "No hits yet.")
end

local function refreshLists(p)
	local list = currentList(p)
	p.listButton:SetLabel(list and ("List: |cffffd100" .. list .. "|r  v") or "|cff999999No lists yet - press New list|r  v")
	local l = X.ShopList(list)
	p.shopTable:SetRows(l and l.items or {}, list and "This list is empty. Press Add item." or
		"Make a shopping list: New list, then Add item. Each item: how many to buy and the most to pay for one.")
	local e = list and p.selKey and X.ShopEntry(list, p.selKey)
	if not e then p.selKey = nil end
	p.entryBox:SetShown(e ~= nil)
	if e then
		p.entryLabel:SetText(X.ItemText(e.key) .. ":")
		if not p.qtyBox:HasFocus() then p.qtyBox:SetText(tostring(e.qty)) end
		if not p.emaxBox:HasFocus() then p.emaxBox:SetText(e.max and X.MoneyPlain(e.max) or "") end
	end
	p.status:SetText(X.ahOpen and "Click an item of the list: it is searched, then the purchase panel shows what one click buys." or
		"|cffff8888The auction house is closed:|r lowest prices are from the last scan (grey).")
	refreshBuy(p)
	refreshSnipe(p)
end

-- [[ best buys + the Next buy box ]]
local NEXT_ON = {check = true, buy = true, confirm = true, poor = true}
local function selectedIdea(p)
	for _, r in ipairs(p.ideas or {}) do if r.id == p.selIdea then return r end end
	return nil
end
local function refreshBest(p)
	local rows = X.BuyIdeas(40)
	p.ideas = rows
	local empty
	if X.Realm().lastFull == nil and #rows == 0 then empty = "Nothing to buy yet: XNAH needs prices. Do a full scan at the auction house."
	elseif X.BuyIdeasBusy() then empty = "Looking for good buys ..."
	else empty = "Nothing worth buying right now. XNAH looks again when prices change." end
	p.bestList:SetItems(rows, empty)
	p.bestStatus:SetText(X.ahOpen and "Best first: your shopping lists and watched items under your max price, then the best ideas and deals." or
		"|cffff8888The auction house is closed:|r prices are from the last scan. Open it to buy.")
	-- the Next buy box
	local box = p.nextBox
	local peek = X.NextBuyPeek()
	p.nextButton:SetText(peek.text or "Next buy")
	p.nextButton:SetEnabled(NEXT_ON[peek.what] == true)
	local key = GetBindingKey and GetBindingKey("XNAH_NEXTBUY")
	box.keyText:SetText(key and ("Your key: |cffffd100" .. key .. "|r") or
		"|cffff8888No key set yet:|r set one in the game's key bindings, under AddOns > XNAH (Next buy).")
	local b = X.buy
	if b.key then
		box.item:SetText(UI.ItemCell(b.key, 16))
		box.line1:SetText("To buy: " .. X.Num(b.need or 0) .. "   at most " .. (b.max and X.Money(b.max) or "any price") .. " each" ..
			((b.bought or 0) > 0 and ("   |cff4ade80bought " .. X.Num(b.bought) .. " for " .. X.MoneyPlain(b.spent) .. "|r") or ""))
	else
		box.item:SetText("|cff999999No purchase going on.|r")
		box.line1:SetText("")
	end
	box.state:SetText("|cffaaaaaa" .. (b.text or "") .. "|r")
	local s = b.state
	p.skipButton:SetEnabled(s ~= "buying" and (b.key ~= nil or peek.idea ~= nil))
	p.cancelBuy:SetEnabled(s == "quoting" or s == "confirm" or s == "toohigh")
	local idea = selectedIdea(p) or peek.idea
	box.why:SetText(idea and ("|cffffd100" .. (X.ItemName(idea.key) or "") .. ":|r " .. (idea.why or "")) or "")
end

local function refresh(p)
	local view = p.view
	p.viewBest:SetSelected(view == "best")
	p.viewLists:SetSelected(view == "lists")
	p.bestView:SetShown(view == "best")
	p.listsView:SetShown(view == "lists")
	if view == "best" then refreshBest(p) else refreshLists(p) end
end

local function listMenu(p, anchor)
	local items = {{text = "Shopping lists", isTitle = true}}
	for _, name in ipairs(X.ShopLists()) do
		items[#items + 1] = {text = name, checked = name == p.list, func = function()
			p.list, p.selKey = name, nil
			X.S().shopList = name
			refresh(p)
		end}
	end
	items[#items + 1] = {text = "New list ...", func = function()
		K.Ask("Name of the new shopping list", "", false, function(name)
			if X.ShopNew(name) then p.list = X.Trim(name) X.S().shopList = p.list refresh(p) end
		end, "Make")
	end}
	if p.list then
		local name = p.list
		items[#items + 1] = {text = "Rename this list ...", func = function()
			K.Ask("New name for " .. name, name, false, function(new)
				if X.ShopRename(name, new) then p.list = X.Trim(new) X.S().shopList = p.list end
				refresh(p)
			end, "Rename")
		end}
		items[#items + 1] = {text = "Set 'bought' back to 0", func = function() X.ShopClear(name, true) end}
		items[#items + 1] = {text = "Empty this list", func = function()
			X.Confirm("Remove every item from the list " .. name .. "?", function() X.ShopClear(name) end)
		end}
		items[#items + 1] = {text = "Delete this list", func = function()
			X.Confirm("Delete the shopping list " .. name .. "?", function() X.ShopDelete(name) p.list = nil refresh(p) end)
		end}
	end
	K.Menu(anchor, items)
end

local function addItem(p)
	local list = currentList(p) or "Shopping"
	K.Ask2("Add to the list " .. list, {"Item (name or link)", "", "Shift-click an item to put its link in. Max price: set it below after adding."},
		{"How many", "1"}, function(text, count)
			local key = X.KeyFromLink(text) or X.Find(text, 1)[1]
			if not key then X.Print("no item found for \"" .. X.Trim(text) .. "\"") return end
			X.ShopAdd(list, key, tonumber(count) or 1)
			p.list, p.selKey = list, key
			X.S().shopList = list
			refresh(p)
		end, "Add")
end

-- the best buys view: the list with Buy buttons, and the Next buy box
local function buildBest(p, c)
	p.bestStatus = K.Label(c, "", "GameFontHighlightSmall")
	p.bestStatus:SetPoint("TOPLEFT", 0, -2)
	p.bestStatus:SetWidth(BEST_W)
	p.bestStatus:SetWordWrap(false)
	p.bestList = K.List(c, BEST_W, CH - 64, 22, function(row, r)
		row:SetCols(UI.ItemCell(r.key), "|cffaaaaaa" .. (r.from or "") .. "|r" .. (RISK[r.risk or "Low"] or ""), X.Num(r.qty or 1),
			UI.MoneyCell(r.price), (r.profit and r.profit > 0) and ("|cff4ade80" .. X.MoneyPlain(math.floor(r.profit)) .. "|r") or "|cff999999-|r", "")
		row:SetSelected(r.id == p.selIdea)
		if not row.buy then
			row.buy = UI.BuyButton(row, 136, 19)
			row.buy:SetPoint("RIGHT", -2, 0)
		end
		row.buy:SetItem(r.key, r.qty, r.max, r.source, r.tag)
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" then UI.ItemMenu(self, r.key) return end
			p.selIdea = r.id
			refresh(p)
		end)
		row:SetScript("OnEnter", function(self) UI.ItemTooltip(self, r.key) end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end, BEST_COLUMNS)
	p.bestList:SetPoint("TOPLEFT", 0, -40)
	local hint = K.Label(c, "|cff999999Click a row for why it is a good buy.  Right click: menu (Never suggest buying this).|r")
	hint:SetPoint("BOTTOMLEFT", 0, 2)

	local box = K.Panel(c, BW, CH)
	box:SetPoint("TOPLEFT", BX, 0)
	p.nextBox = box
	local title = K.Label(box, "Next buy", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -10)
	local intro = K.Label(box, "Each press of your Next buy key (or of the big button) does one step of the best buy: check " ..
		"its price, buy, confirm. Then it moves on to the next one. Nothing is bought without a press.")
	intro:SetPoint("TOPLEFT", 10, -30)
	intro:SetWidth(BW - 20)
	intro:SetHeight(56)
	intro:SetJustifyV("TOP")
	intro:SetWordWrap(true)
	box.keyText = K.Label(box, "")
	box.keyText:SetPoint("TOPLEFT", 10, -90)
	box.keyText:SetWidth(BW - 20)
	box.keyText:SetHeight(28)
	box.keyText:SetJustifyV("TOP")
	box.keyText:SetWordWrap(true)
	p.nextButton = K.Button(box, "Next buy", BW - 20, 48, function()
		X.NextBuy("button")
		refresh(p)
	end)
	p.nextButton:SetPoint("TOPLEFT", 10, -122)
	local nfs = p.nextButton:GetFontString()
	if nfs then
		nfs:SetWidth(BW - 36)
		nfs:SetWordWrap(true)
	end
	K.Tooltip(p.nextButton, "Next buy", "Does what the button says: one step per press. Your Next buy key does the same " ..
		"while the auction house is open.")
	box.item = K.Label(box, "", "GameFontNormal")
	box.item:SetPoint("TOPLEFT", 10, -182)
	box.item:SetWidth(BW - 20)
	box.item:SetWordWrap(false)
	box.line1 = K.Label(box, "")
	box.line1:SetPoint("TOPLEFT", 10, -202)
	box.line1:SetWidth(BW - 20)
	box.line1:SetWordWrap(false)
	box.state = K.Label(box, "")
	box.state:SetPoint("TOPLEFT", 10, -220)
	box.state:SetWidth(BW - 20)
	box.state:SetHeight(30)
	box.state:SetJustifyV("TOP")
	box.state:SetWordWrap(true)
	p.skipButton = K.Button(box, "Skip this buy", 110, 22, function() X.NextBuySkip() refresh(p) end)
	p.skipButton:SetPoint("TOPLEFT", 10, -256)
	K.Tooltip(p.skipButton, "Skip this buy", "Leaves this buy out for 10 minutes and goes on to the next one.")
	p.cancelBuy = K.Button(box, "Cancel", 80, 22, function() X.BuyCancel() refresh(p) end)
	p.cancelBuy:SetPoint("LEFT", p.skipButton, "RIGHT", 6, 0)
	K.Tooltip(p.cancelBuy, "Cancel", "Stops a purchase that asked for its price (nothing is bought).")
	box.why = K.Label(box, "")
	box.why:SetPoint("TOPLEFT", 10, -292)
	box.why:SetWidth(BW - 20)
	box.why:SetHeight(84)
	box.why:SetJustifyV("TOP")
	box.why:SetWordWrap(true)
	local note = K.Label(box, "|cff999999Stackable items take two presses: the first asks the server for the exact price, the " ..
		"second buys. Buys you skip come back after 10 minutes.|r")
	note:SetPoint("BOTTOMLEFT", 10, 10)
	note:SetWidth(BW - 20)
	note:SetHeight(42)
	note:SetJustifyV("BOTTOM")
	note:SetWordWrap(true)
end

-- the lists view: shopping lists on the left, the purchase panel and the sniper on the right
local function buildLists(p, c)
	p.listButton = K.Flat(c, 250, 22)
	p.listButton:SetPoint("TOPLEFT", 0, 0)
	p.listButton:SetScript("OnClick", function(self) listMenu(p, self) end)
	local new = K.Button(c, "New list", 80, 22, function()
		K.Ask("Name of the new shopping list", "", false, function(name)
			if X.ShopNew(name) then p.list = X.Trim(name) X.S().shopList = p.list refresh(p) end
		end, "Make")
	end)
	new:SetPoint("TOPLEFT", 256, 0)
	local add = K.Button(c, "Add item", 80, 22, function() addItem(p) end)
	add:SetPoint("TOPLEFT", 340, 0)
	local searchAll = K.Button(c, "Search list", 90, 22, function()
		local l = X.ShopList(p.list)
		for _, e in ipairs(l and l.items or {}) do if X.ShopNeed(e) > 0 then X.LiveSearch(e.key) end end
	end)
	searchAll:SetPoint("TOPLEFT", 424, 0)
	K.Tooltip(searchAll, "Search list", "Searches every item still needed, one a second, for live prices and the cost to buy the rest.")
	p.status = K.Label(c, "", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", 0, -30)
	p.status:SetWidth(LEFT_W)
	p.status:SetWordWrap(false)
	p.shopTable = K.Table(c, LEFT_W, CH - TOP - 50, SHOP_COLUMNS, function(e, button, rowFrame)
		if button == "RightButton" then
			K.Menu(rowFrame, {
				{text = X.ItemText(e.key), isTitle = true},
				{text = "Open item page", func = function() UI.ShowItem(e.key) end},
				{text = "Remove from this list", func = function() X.ShopRemove(p.list, e.key) end},
			})
			return
		end
		p.selKey = e.key
		if X.ahOpen and X.ShopNeed(e) > 0 then X.ShopBuy(p.list, e.key) end
		refresh(p)
	end)
	p.shopTable:SetPoint("TOPLEFT", 0, -TOP)
	-- the picked entry: how many and the max price
	local eb = CreateFrame("Frame", nil, c)
	eb:SetPoint("BOTTOMLEFT", 0, 0)
	eb:SetSize(LEFT_W, 24)
	p.entryBox = eb
	p.entryLabel = K.Label(eb, "")
	p.entryLabel:SetPoint("LEFT", 0, 0)
	p.entryLabel:SetWidth(200)
	p.entryLabel:SetWordWrap(false)
	local lq = K.Label(eb, "Buy in all")
	lq:SetPoint("LEFT", 206, 0)
	p.qtyBox = K.Edit(eb, 50, function(text)
		local n = tonumber(X.Trim(text))
		if n and n >= 1 and p.selKey then X.ShopSet(p.list, p.selKey, "qty", n) end
		refresh(p)
	end)
	p.qtyBox:SetPoint("LEFT", 266, 0)
	local lm = K.Label(eb, "Max each")
	lm:SetPoint("LEFT", 330, 0)
	p.emaxBox = K.Edit(eb, 100, function(text)
		if p.selKey then
			local v = X.ParseMoney(text)
			if X.Trim(text) == "" then X.ShopSet(p.list, p.selKey, "max", nil)
			elseif v and v > 0 then X.ShopSet(p.list, p.selKey, "max", v) end
		end
		refresh(p)
	end)
	p.emaxBox:SetPoint("LEFT", 390, 0)
	local hint = K.Label(eb, "|cff999999then Enter|r")
	hint:SetPoint("LEFT", 496, 0)

	-- [[ right, top: the purchase panel ]]
	local box = K.Panel(c, RW, 196)
	box:SetPoint("TOPLEFT", RX, 0)
	p.buyBox = box
	box.title = K.Label(box, "", "GameFontNormal")
	box.title:SetPoint("TOPLEFT", 10, -10)
	box.title:SetWidth(RW - 20)
	box.title:SetWordWrap(false)
	box.line1 = K.Label(box, "")
	box.line1:SetPoint("TOPLEFT", 10, -32)
	box.line1:SetWidth(RW - 20)
	box.line2 = K.Label(box, "")
	box.line2:SetPoint("TOPLEFT", 10, -50)
	box.line2:SetWidth(RW - 20)
	box.state = K.Label(box, "")
	box.state:SetPoint("TOPLEFT", 10, -70)
	box.state:SetWidth(RW - 20)
	box.state:SetHeight(30)
	p.buyButton = K.Button(box, "Buy", RW - 20, 32, function() X.BuyClick() refresh(p) end)
	p.buyButton:SetPoint("TOPLEFT", 10, -110)
	p.stopButton = K.Button(box, "Cancel", 100, 22, function() X.BuyCancel() refresh(p) end)
	p.stopButton:SetPoint("TOPLEFT", 10, -154)
	p.againButton = K.Button(box, "Search again", 110, 22, function() X.BuyResearch() end)
	p.againButton:SetPoint("TOPLEFT", 116, -154)
	local clear = K.Button(box, "Clear", 70, 22, function() X.BuyClear() refresh(p) end)
	clear:SetPoint("TOPLEFT", 232, -154)
	K.Tooltip(p.buyButton, "Buy", "One click = one step. Stackable items: the first click asks the server for the exact " ..
		"price, the second click buys them. Other items: one click buys one auction.")

	-- [[ right, below: the sniper ]]
	local sn = K.Panel(c, RW, CH - 206)
	sn:SetPoint("TOPLEFT", RX, -206)
	local st = K.Label(sn, "Sniper", "GameFontNormal")
	st:SetPoint("TOPLEFT", 10, -10)
	p.snipeButton = K.Button(sn, "Sniper: off", 100, 22, function() X.SnipeToggle() refresh(p) end)
	p.snipeButton:SetPoint("TOPLEFT", 70, -6)
	local wl = K.Label(sn, "Wait between rounds (s)")
	wl:SetPoint("TOPLEFT", 186, -10)
	p.waitBox = K.Edit(sn, 36, function(text)
		local n = tonumber(X.Trim(text))
		if n and n >= 1 then X.S().snipeWait = math.floor(n) end
		refresh(p)
	end)
	p.waitBox:SetPoint("TOPLEFT", 322, -6)
	p.snipeStatus = K.Label(sn, "")
	p.snipeStatus:SetPoint("TOPLEFT", 10, -34)
	p.snipeStatus:SetWidth(RW - 20)
	p.snipeStatus:SetWordWrap(false)
	p.watchTable = K.Table(sn, RW - 16, 96, WATCH_COLUMNS, function(r, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, r.key) return end
		p.watchKey = r.key
		refresh(p)
	end)
	p.watchTable:SetPoint("TOPLEFT", 8, -66)
	p.maxLabel = K.Label(sn, "")
	p.maxLabel:SetPoint("TOPLEFT", 10, -172)
	p.maxLabel:SetWidth(220)
	p.maxLabel:SetWordWrap(false)
	p.maxBox = K.Edit(sn, 100, function(text)
		if p.watchKey then
			local v = X.ParseMoney(text)
			if X.Trim(text) == "" then X.SetWatchMax(p.watchKey, nil) elseif v and v > 0 then X.SetWatchMax(p.watchKey, v) end
		end
		refresh(p)
	end)
	p.maxBox:SetPoint("TOPLEFT", 240, -168)
	p.hitTable = K.Table(sn, RW - 16, 90, HIT_COLUMNS, function(h, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, h.key) return end
		X.SnipeBuy(h.key)
		refresh(p)
	end)
	p.hitTable:SetPoint("TOPLEFT", 8, -212)
end

local function viewButton(p, text, x, view)
	local b = K.Flat(p, 190, 22)
	b:SetPoint("TOPLEFT", x, 0)
	b:SetLabel(text)
	b.label:SetJustifyH("CENTER")
	b:SetScript("OnClick", function() p.view = view refresh(p) end)
	return b
end

local function build(p)
	p.view = "best"
	p.viewBest = viewButton(p, "Best buys", 0, "best")
	p.viewLists = viewButton(p, "Shopping lists and sniper", 194, "lists")
	p.bestView = CreateFrame("Frame", nil, p)
	p.bestView:SetPoint("TOPLEFT", 0, -VIEW_H)
	p.bestView:SetSize(W, CH)
	buildBest(p, p.bestView)
	p.listsView = CreateFrame("Frame", nil, p)
	p.listsView:SetPoint("TOPLEFT", 0, -VIEW_H)
	p.listsView:SetSize(W, CH)
	buildLists(p, p.listsView)
	p.listsView:Hide()
end

UI.AddTab("buy", "Buy", build, refresh, 4)
