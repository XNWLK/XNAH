-- The Buy tab (since v0.8 also the old Deals tab's buy ideas and Adjust ideas). Its views:
--   Best buys: everything worth buying right now in one list - your shopping lists, the crafting queue's materials and
--     watched items under your max price first, then the best buys of the Next buy key (X.BuyIdeas in Buy.lua), then every other buy idea
--     (X.DealIdeas("buy") in UIDeals.lua: disenchanting, buying from a vendor, smaller or riskier buys) - each with a
--     Buy button. Above it the Next buy box: one key (or its big button) does the next step of the best buy.
--   Shopping lists and sniper: the shopping lists, the purchase panel and the sniper.
--   Adjust ideas (UIStrategies.lua): which ideas go into the lists, their numbers, how each one works.
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
local NEXT_H = 84           -- the Next buy box above the best buys
local BEST_TOP = 132        -- where the best buys list starts (its column titles sit just above)
local BUY_W = 130           -- the Buy button in each row (its label says the next step: "Confirm 5 for 2g 10s")
local MAX = 50              -- rows used by the buttons under the best buys

X.Default("buyView", "best")
-- "hide items that sell under N a day" (best buys)
X.Default("dealSpeedHide", false)
X.Default("dealSpeedMin", 1)

local GREY = "|cff999999"
local VIEWS = {
	{key = "best", title = "Best buys", w = 120},
	{key = "lists", title = "Shopping lists and sniper", w = 200},
	{key = "adjust", title = "Adjust ideas", w = 120},
}
local VIEW_OK = {best = true, lists = true, adjust = true}

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
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end
local function lowestOf(key)
	local live = X.LiveLowest(key)
	if live then return live, false end
	return X.Price(key, "min"), true
end

-- shopping list entries: "keep" ones keep that many in stock (Need = what is missing), the others buy that many once
local SHOP_COLUMNS = {
	{"Item", 166, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Need", 45, "RIGHT", text = function(e) return X.Num(X.ShopNeed(e)) end, sort = function(e) return X.ShopNeed(e) end},
	{"Bought", 64, "RIGHT", text = function(e)
		if e.keep then return "|cff9db4ffkeep " .. X.Num(e.qty) .. "|r" end
		return X.Num(e.bought or 0) .. "/" .. X.Num(e.qty)
	end, sort = field("bought")},
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

-- [[ the best buys ]] one row per item: {key, kind (list / queue / watch / deal / idea), idea, ideaName, more, action, now,
-- target, each, qty, total, rate, risk, why, vendor, max, source, tag}
local function pos(v) return (v and v > 0) and v or nil end
-- rows of things you asked for (not ideas): your shopping lists, the crafting queue, watched items
local MINE = {list = true, queue = true, watch = true}
local function rateOf(key) return X.SaleRate and X.Try(X.SaleRate, key) or nil end
local function bestRows()
	local out, seen, ideas = {}, {}, {}
	local all = X.DealIdeas and X.DealIdeas("buy") or {}
	for _, d in ipairs(all) do ideas[d.key] = ideas[d.key] or d end
	-- what the Next buy key buys, in its order (lists, the crafting queue and watched items first)
	for _, b in ipairs(X.BuyIdeas(40)) do
		if not seen[b.key] then
			seen[b.key] = true
			local d = ideas[b.key]
			local row = {key = b.key, kind = b.kind, action = b.action, now = b.price, target = b.target, each = pos(b.each),
				qty = b.qty, total = pos(b.profit), max = b.max, source = b.source, tag = b.tag}
			if b.kind == "list" then
				row.ideaName = "Shopping list"
				row.why = "on your list " .. tostring(b.tag) .. (b.max and (", at most " .. plain(b.max) .. " each") or "")
			elseif b.kind == "queue" then
				row.ideaName = "Crafting queue"
				row.why = "material for your crafting queue" .. (b.max and (", at most " .. plain(b.max) .. " each") or "")
			elseif b.kind == "watch" then
				row.ideaName = "Watched"
				row.why = "listed under your max price of " .. plain(b.max)
			else
				row.idea = d and d.idea or (b.kind == "deal" and "usual" or nil)
				row.ideaName = d and d.ideaName or (b.kind == "deal" and "Under usual price" or b.from)
				row.more = d and d.more
				row.why = d and d.why
				if not row.why and b.target and b.target > 0 and b.price then
					row.why = string.format("%.0f%% of what it sells for", b.price / b.target * 100)
				end
				row.risk = b.risk or (d and d.risk)
			end
			row.rate = (d and d.rate) or rateOf(b.key)
			if not row.risk and (b.kind == "deal" or b.kind == "idea") then
				local it = X.Items()[b.key]
				row.risk = UI.IdeaRisk(it and X.Stats(it), row.rate)
			end
			out[#out + 1] = row
		end
	end
	-- then every other buy idea (best first): disenchanting, buying from a vendor, smaller or riskier buys
	for _, d in ipairs(all) do
		if not seen[d.key] then
			seen[d.key] = true
			out[#out + 1] = {key = d.key, kind = "idea", idea = d.idea, ideaName = d.ideaName, more = d.more, action = d.action,
				now = d.now, target = d.target, each = pos(d.profit), qty = d.qty, total = pos(d.total), rate = d.rate,
				risk = d.risk, why = d.why, vendor = d.vendor,
				-- the most to pay for one: the price now plus half the profit (still half the profit left)
				max = (d.now and not d.vendor) and math.floor(d.now + math.max(0, d.profit or 0) / 2) or nil,
				-- source and tag as the Next buy key uses them: one purchase whichever starts it
				source = "idea", tag = "idea:" .. d.key}
		end
	end
	-- the speed filter (items known to sell slower than N a day are left out; unknown speed and what you asked for: shown)
	local S = X.S()
	if not S.dealSpeedHide then return out end
	local kept = {}
	for _, r in ipairs(out) do
		if MINE[r.kind] or not r.rate or r.rate >= (S.dealSpeedMin or 0) then kept[#kept + 1] = r end
	end
	return kept
end

-- the best buys list (widths add up to 920: what a 940 wide list has room for next to its scroll bar)
local IC = UI.IdeaCells
local BUY_COL = 11
local BEST_COLUMNS = {
	{"Item", 166, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Idea", 96, "LEFT", text = IC.idea, sort = field("ideaName"), desc = false},
	{"Price now", 66, "RIGHT", text = money("now"), sort = field("now"), desc = false},
	{"Sells for", 66, "RIGHT", text = money("target"), sort = field("target")},
	{"Profit each", 66, "RIGHT", text = money("each"), sort = field("each")},
	{"Qty", 34, "RIGHT", text = IC.qty, sort = field("qty")},
	{"Profit in all", 72, "RIGHT", text = money("total"), sort = field("total")},
	{"Sells a day", 56, "RIGHT", text = function(r) return UI.RateText(r.rate) end, sort = field("rate")},
	{"Risk", 44, "LEFT", text = IC.risk, sort = IC.riskSort, desc = false},
	{"Why", 120, "LEFT", text = IC.why},
	{"", BUY_W + 4, "LEFT", text = function(r) return r.vendor and (GREY .. " at a vendor|r") or "" end},
}

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
		p.keepCheck:SetChecked(e.keep and true or false)
		p.qtyLabel:SetText(e.keep and "Keep" or "Buy in all")
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
-- the rows in the order shown, at most MAX, bought on the auction house (ideas only: not your lists, queue or watched items)
local function shownBuys(p, any)
	local out = {}
	for _, r in ipairs(p.bestList.items or {}) do
		if #out >= MAX then break end
		if not r.vendor and (any or not MINE[r.kind]) then out[#out + 1] = r end
	end
	return out
end
local function refreshBest(p)
	if X.StrategyCheck then X.StrategyCheck() end -- works the ideas out again when prices changed or they are old
	local S = X.S()
	local rows = bestRows()
	p.bestList:SetRows(rows, (next(X.Items()) ~= nil and X.BuyIdeasBusy()) and "Looking for good buys ..." or UI.IdeasEmptyText("buy"))
	local count = #rows == 1 and "1 item" or (X.Num(#rows) .. " items")
	if X.BuyIdeasBusy() then count = count .. ", working ..." end
	p.bestStatus:SetText(X.ahOpen and ("Your shopping lists, crafting queue and watched items first, then every buy idea.  " .. GREY .. count .. "|r") or
		("|cffff8888The auction house is closed:|r prices are from the last scan. Open it to buy.  " .. GREY .. count .. "|r"))
	if not p.speedBox:HasFocus() then p.speedBox:SetText(tostring(S.dealSpeedMin)) end
	p.speedCheck:SetChecked(S.dealSpeedHide and true or false)
	local ideas = #shownBuys(p)
	p.search:SetEnabled(X.ahOpen == true and X.scan.state == "idle" and #shownBuys(p, true) > 0)
	p.shop:SetEnabled(X.ShopAdd ~= nil and ideas > 0)
	p.snipe:SetEnabled(ideas > 0)
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
		box.item:SetText(GREY .. "No purchase going on.|r")
		box.line1:SetText("")
	end
	box.state:SetText("|cffaaaaaa" .. (b.text or "") .. "|r")
	local s = b.state
	p.skipButton:SetEnabled(s ~= "buying" and (b.key ~= nil or peek.idea ~= nil))
	p.cancelBuy:SetEnabled(s == "quoting" or s == "confirm" or s == "toohigh")
	local idea = peek.idea
	box.why:SetText(idea and ("|cffffd100Next: " .. (X.ItemName(idea.key) or "") .. ":|r " .. (idea.why or "")) or "")
end

local function refresh(p)
	local view = X.S().buyView
	if not VIEW_OK[view] then view = "best" X.S().buyView = view end
	p.view = view
	for key, b in pairs(p.viewButtons) do b:SetSelected(key == view) end
	p.bestView:SetShown(view == "best")
	p.listsView:SetShown(view == "lists")
	p.adjustView:SetShown(view == "adjust")
	if view == "best" then refreshBest(p)
	elseif view == "lists" then refreshLists(p)
	else
		if X.StrategyCheck then X.StrategyCheck() end
		if p.adjustView.Refresh then p.adjustView:Refresh() end
	end
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

-- [[ the Buy button in each row of the best buys ]] set again only for another item (a purchase under way keeps its
-- step when the list is drawn again)
local function drawButtons(tbl)
	for i, rowFrame in ipairs(tbl.rows) do
		local r = tbl.items[i + tbl.offset]
		if r and not r.vendor and rowFrame.cols then
			local b = rowFrame.buyButton
			if not b then
				b = UI.BuyButton(rowFrame, BUY_W, 16)
				b:SetPoint("LEFT", rowFrame.cols[BUY_COL], "LEFT", 0, 0)
				rowFrame.buyButton = b
			end
			local id = r.key .. ":" .. tostring(r.qty) .. ":" .. tostring(r.max) .. ":" .. tostring(r.tag)
			if b.bestId ~= id then
				b.bestId = id
				b:SetItem(r.key, r.qty, r.max, r.source, r.tag)
			end
			b:Show()
		elseif rowFrame.buyButton then
			rowFrame.buyButton:Hide()
			rowFrame.buyButton.bestId = nil
		end
		-- the mouse over a row: the item, and why it is a good buy (the Why column is short)
		if r and r.key then
			rowFrame:SetScript("OnEnter", function(self)
				UI.ItemTooltip(self, r.key)
				if X.KeyID(r.key) then
					GameTooltip:AddLine(" ")
					GameTooltip:AddLine((r.ideaName or "Buy") .. ((r.more or 0) > 0 and (" (and " .. r.more .. " more)") or ""), 1, 0.82, 0)
					local why = IC.whyText(r)
					if why ~= "" then GameTooltip:AddLine(why, 1, 1, 1, true) end
					GameTooltip:Show()
				end
			end)
		end
	end
end

-- the best buys view: the Next buy box on top, the list with Buy buttons, the buttons under it
local function buildBest(p, c)
	-- [[ the Next buy box ]] left: what it is and your key; middle: the big button; right: the purchase going on
	local box = K.Panel(c, W, NEXT_H)
	box:SetPoint("TOPLEFT", 0, 0)
	p.nextBox = box
	local title = K.Label(box, "Next buy", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	box.keyText = K.Label(box, "")
	box.keyText:SetPoint("TOPLEFT", 10, -28)
	box.keyText:SetWidth(226)
	box.keyText:SetHeight(48)
	box.keyText:SetJustifyV("TOP")
	box.keyText:SetWordWrap(true)
	p.nextButton = K.Button(box, "Next buy", 300, 40, function()
		X.NextBuy("button")
		refresh(p)
	end)
	p.nextButton:SetPoint("TOPLEFT", 246, -8)
	local nfs = p.nextButton:GetFontString()
	if nfs then
		nfs:SetWidth(284)
		nfs:SetWordWrap(true)
	end
	K.Tooltip(p.nextButton, "Next buy", "Each press of your Next buy key (or of this button) does one step of the best buy: " ..
		"check its price, buy, confirm - then it moves on to the next one. Nothing is bought without a press. Stackable " ..
		"items take two presses: the first asks the server for the exact price, the second buys.")
	p.skipButton = K.Button(box, "Skip this buy", 110, 22, function() X.NextBuySkip() refresh(p) end)
	p.skipButton:SetPoint("TOPLEFT", 246, -54)
	K.Tooltip(p.skipButton, "Skip this buy", "Leaves this buy out for 10 minutes and goes on to the next one.")
	p.cancelBuy = K.Button(box, "Cancel", 80, 22, function() X.BuyCancel() refresh(p) end)
	p.cancelBuy:SetPoint("LEFT", p.skipButton, "RIGHT", 6, 0)
	K.Tooltip(p.cancelBuy, "Cancel", "Stops a purchase that asked for its price (nothing is bought).")
	local RXB, RWB = 560, W - 570
	box.item = K.Label(box, "", "GameFontNormal")
	box.item:SetPoint("TOPLEFT", RXB, -8)
	box.item:SetWidth(RWB)
	box.item:SetWordWrap(false)
	box.line1 = K.Label(box, "")
	box.line1:SetPoint("TOPLEFT", RXB, -28)
	box.line1:SetWidth(RWB)
	box.line1:SetWordWrap(false)
	box.state = K.Label(box, "")
	box.state:SetPoint("TOPLEFT", RXB, -44)
	box.state:SetWidth(RWB)
	box.state:SetWordWrap(false)
	box.why = K.Label(box, "")
	box.why:SetPoint("TOPLEFT", RXB, -60)
	box.why:SetWidth(RWB)
	box.why:SetHeight(22)
	box.why:SetJustifyV("TOP")
	box.why:SetWordWrap(true)

	-- [[ under the box: status, and hide slow sellers ]]
	p.bestStatus = K.Label(c, "", "GameFontHighlightSmall")
	p.bestStatus:SetPoint("TOPLEFT", 0, -(NEXT_H + 12))
	p.bestStatus:SetWidth(610)
	p.bestStatus:SetWordWrap(false)
	p.speedCheck = K.Check(c, "Hide items that sell under", function(on)
		X.S().dealSpeedHide = on
		refresh(p)
	end)
	p.speedCheck:SetPoint("TOPLEFT", 624, -(NEXT_H + 6))
	K.Tooltip(p.speedCheck, "Hide slow sellers",
		"Leaves out of this list items known to sell fewer than this many a day (your shopping lists, crafting queue " ..
		"and watched items stay). The sales speed is an estimate from two full scans up to 4 hours apart (cancelled auctions look like " ..
		"sales, so it can be high). Items whose speed is not known yet stay in the list.")
	p.speedBox = K.Edit(c, 36)
	p.speedBox:SetPoint("LEFT", p.speedCheck.label, "RIGHT", 8, 0)
	p.speedBox:SetScript("OnEditFocusLost", function(self)
		local v = tonumber(X.Trim(self:GetText()))
		if v and v >= 0 then X.S().dealSpeedMin = v end
		self:SetText(tostring(X.S().dealSpeedMin))
		refresh(p)
	end)
	local aDay = K.Label(c, "a day")
	aDay:SetPoint("LEFT", p.speedBox, "RIGHT", 4, 0)

	-- [[ the list ]] click: item page, right click: menu
	p.bestList = K.Table(c, W, CH - BEST_TOP - 28, BEST_COLUMNS, function(r, button, rowFrame)
		if not r.key then return end
		if button == "RightButton" then UI.ItemMenu(rowFrame, r.key) else UI.ShowItem(r.key) end
	end)
	p.bestList:SetPoint("TOPLEFT", 0, -BEST_TOP)
	local baseRefresh = p.bestList.Refresh
	function p.bestList:Refresh()
		baseRefresh(self)
		drawButtons(self)
	end

	-- [[ under the list: search, shopping list, sniper (the first rows shown, bought on the auction house) ]]
	p.search = K.Button(c, "Search these on the AH", 166, 22, function()
		local keys = {}
		for _, r in ipairs(shownBuys(p, true)) do keys[#keys + 1] = r.key end
		if #keys > 0 and X.ahOpen and X.scan.state == "idle" then X.ScanItems(keys, "best buys") end
	end)
	p.search:SetPoint("BOTTOMLEFT", 0, 0)
	K.Tooltip(p.search, "Search these on the auction house",
		"Searches the first " .. MAX .. " items of this list one by one, in the order shown, for their live prices " ..
		"(the list can be out of date: someone may have bought them already). Needs the auction house open.")
	p.shop = K.Button(c, "Add to shopping list", 150, 22, function()
		if not X.ShopAdd then return end
		local name, n = "Deals", 0
		for _, r in ipairs(shownBuys(p)) do
			if X.ShopAdd(name, r.key, r.qty or 1, r.max) then n = n + 1 end
		end
		X.Print(n .. " items put on the shopping list \"" .. name .. "\" (tab Buy), each with a top price of its price now " ..
			"plus half the profit.")
	end)
	p.shop:SetPoint("LEFT", p.search, "RIGHT", 6, 0)
	K.Tooltip(p.shop, "Add to shopping list", "Puts the first " .. MAX .. " ideas of this list on the shopping list \"Deals\", " ..
		"with the quantity shown and a top price of the price now plus half the profit (not your lists, queue or watched items).")
	p.snipe = K.Button(c, "Snipe at this price", 140, 22, function()
		local n = 0
		for _, r in ipairs(shownBuys(p)) do
			if r.now then
				X.SetWatchMax(r.key, X.Round(r.now))
				n = n + 1
			end
		end
		X.Print(n .. " items on the watch list with a top price (the sniper looks for them: Shopping lists and sniper).")
	end)
	p.snipe:SetPoint("LEFT", p.shop, "RIGHT", 6, 0)
	K.Tooltip(p.snipe, "Snipe at this price", "Puts the first " .. MAX .. " ideas of this list on the watch list with their " ..
		"price now as the most to pay: the sniper tells you when one is listed at or under it.")
	local hint = K.Label(c, GREY .. "Click: item page.  Mouse over: why.  Right-click: menu.  +1 = another idea found it too.|r", nil, "RIGHT")
	hint:SetPoint("BOTTOMRIGHT", 0, 4)
	hint:SetWidth(W - 480)
	hint:SetWordWrap(false)
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
	p.shopTable = K.Table(c, LEFT_W, CH - TOP - 54, SHOP_COLUMNS, function(e, button, rowFrame)
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
	-- the picked entry (two lines under the list): its name; keep in stock, how many, the max price
	local eb = CreateFrame("Frame", nil, c)
	eb:SetPoint("BOTTOMLEFT", 0, 0)
	eb:SetSize(LEFT_W, 48)
	p.entryBox = eb
	p.entryLabel = K.Label(eb, "")
	p.entryLabel:SetPoint("TOPLEFT", 0, -4)
	p.entryLabel:SetWidth(LEFT_W)
	p.entryLabel:SetWordWrap(false)
	p.keepCheck = K.Check(eb, "Keep in stock", function(on)
		if p.selKey then X.ShopSet(p.list, p.selKey, "keep", on) end
		refresh(p)
	end)
	p.keepCheck:SetPoint("TOPLEFT", 0, -24)
	K.Tooltip(p.keepCheck, "Keep in stock", "Ticked: XNAH keeps this many in stock. It counts what all your characters have " ..
		"(bags, bank, mail, the auction house) and buys only what is missing - again whenever you run low.\n" ..
		"Not ticked: buys this many in all, once.")
	p.qtyLabel = K.Label(eb, "Buy in all")
	p.qtyLabel:SetPoint("TOPLEFT", 116, -29)
	p.qtyBox = K.Edit(eb, 50, function(text)
		local n = tonumber(X.Trim(text))
		if n and n >= 1 and p.selKey then X.ShopSet(p.list, p.selKey, "qty", n) end
		refresh(p)
	end)
	p.qtyBox:SetPoint("TOPLEFT", 176, -25)
	local lm = K.Label(eb, "Max each")
	lm:SetPoint("TOPLEFT", 240, -29)
	p.emaxBox = K.Edit(eb, 100, function(text)
		if p.selKey then
			local v = X.ParseMoney(text)
			if X.Trim(text) == "" then X.ShopSet(p.list, p.selKey, "max", nil)
			elseif v and v > 0 then X.ShopSet(p.list, p.selKey, "max", v) end
		end
		refresh(p)
	end)
	p.emaxBox:SetPoint("TOPLEFT", 300, -25)
	local hint = K.Label(eb, GREY .. "then Enter|r")
	hint:SetPoint("TOPLEFT", 408, -29)

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

local function build(p)
	p.viewButtons = {}
	local x = 0
	for _, v in ipairs(VIEWS) do
		local b = K.Flat(p, v.w, 22)
		b:SetPoint("TOPLEFT", x, 0)
		b:SetLabel(v.title)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().buyView = v.key refresh(p) end)
		p.viewButtons[v.key] = b
		x = x + v.w + 4
	end
	K.Tooltip(p.viewButtons.adjust, "Adjust ideas", "Which ideas go into the lists (here, Sell ideas on tab Sell, Make " ..
		"ideas on tab Crafting), their numbers, and how each one works.")
	-- the views below the buttons (same place, one shown)
	local function area()
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", 0, -VIEW_H)
		f:SetSize(W, CH)
		f:Hide()
		return f
	end
	p.bestView = area()
	buildBest(p, p.bestView)
	p.listsView = area()
	buildLists(p, p.listsView)
	p.adjustView = area()
	if UI.BuildIdeasAdjust then
		local ok, err = pcall(UI.BuildIdeasAdjust, p.adjustView, W, CH, function() UI.Ideas.changed() end)
		if not ok then X.OnError(err) end
	end
end

UI.AddTab("buy", "Buy", build, refresh, 3)
