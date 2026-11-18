-- The Buy tab: shopping lists on the left (what to buy, how many, the most to pay for one), the purchase panel and
-- the sniper on the right. Buying is always a click on our button: stackable items take two clicks (the first asks the
-- server for the exact price, the second buys), other items one click per auction.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 70
local LEFT_W = 560
local RX, RW = 572, 368

for _, e in ipairs({"XNAH_BUY", "XNAH_SHOP", "XNAH_SNIPE", "XNAH_LIVE"}) do
	X.On(e, function() UI.Refresh() end)
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

local function currentList(p)
	local names = X.ShopLists()
	if not p.list or not X.ShopList(p.list) then p.list = X.S().shopList end
	if not p.list or not X.ShopList(p.list) then p.list = names[1] end
	return p.list
end

-- [[ the purchase panel ]]
local function refreshBuy(p)
	local b = X.buy
	local box = p.buyBox
	if not b.key then
		box.title:SetText("|cff999999Pick an item of a list, or a sniper hit.|r")
		box.line1:SetText("")
		box.line2:SetText("")
	else
		box.title:SetText(UI.ItemCell(b.key, 16) .. (b.source == "snipe" and "  |cffffd100(sniper hit)|r" or
			(b.tag and ("  |cff999999(list " .. b.tag .. ")|r") or "")))
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

local function refresh(p)
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
	K.Ask2("Add to the list " .. list, {"Item (name or link)", "", "Shift-click an item to put its link in. Max price: set it on the right after adding."},
		{"How many", "1"}, function(text, count)
			local key = X.KeyFromLink(text) or X.Find(text, 1)[1]
			if not key then X.Print("no item found for \"" .. X.Trim(text) .. "\"") return end
			X.ShopAdd(list, key, tonumber(count) or 1)
			p.list, p.selKey = list, key
			X.S().shopList = list
			refresh(p)
		end, "Add")
end

local function build(p)
	-- [[ left: the shopping list ]]
	p.listButton = K.Flat(p, 250, 22)
	p.listButton:SetPoint("TOPLEFT", 0, 0)
	p.listButton:SetScript("OnClick", function(self) listMenu(p, self) end)
	local new = K.Button(p, "New list", 80, 22, function()
		K.Ask("Name of the new shopping list", "", false, function(name)
			if X.ShopNew(name) then p.list = X.Trim(name) X.S().shopList = p.list refresh(p) end
		end, "Make")
	end)
	new:SetPoint("TOPLEFT", 256, 0)
	local add = K.Button(p, "Add item", 80, 22, function() addItem(p) end)
	add:SetPoint("TOPLEFT", 340, 0)
	local searchAll = K.Button(p, "Search list", 90, 22, function()
		local l = X.ShopList(p.list)
		for _, e in ipairs(l and l.items or {}) do if X.ShopNeed(e) > 0 then X.LiveSearch(e.key) end end
	end)
	searchAll:SetPoint("TOPLEFT", 424, 0)
	K.Tooltip(searchAll, "Search list", "Searches every item still needed, one a second, for live prices and the cost to buy the rest.")
	p.status = K.Label(p, "", "GameFontHighlightSmall")
	p.status:SetPoint("TOPLEFT", 0, -30)
	p.status:SetWidth(LEFT_W)
	p.status:SetWordWrap(false)
	p.shopTable = K.Table(p, LEFT_W, H - TOP - 50, SHOP_COLUMNS, function(e, button, rowFrame)
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
	local eb = CreateFrame("Frame", nil, p)
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
	local box = K.Panel(p, RW, 196)
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
	local sn = K.Panel(p, RW, H - 206)
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
	p.watchTable = K.Table(sn, RW - 16, 112, WATCH_COLUMNS, function(r, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, r.key) return end
		p.watchKey = r.key
		refresh(p)
	end)
	p.watchTable:SetPoint("TOPLEFT", 8, -66)
	p.maxLabel = K.Label(sn, "")
	p.maxLabel:SetPoint("TOPLEFT", 10, -186)
	p.maxLabel:SetWidth(220)
	p.maxLabel:SetWordWrap(false)
	p.maxBox = K.Edit(sn, 100, function(text)
		if p.watchKey then
			local v = X.ParseMoney(text)
			if X.Trim(text) == "" then X.SetWatchMax(p.watchKey, nil) elseif v and v > 0 then X.SetWatchMax(p.watchKey, v) end
		end
		refresh(p)
	end)
	p.maxBox:SetPoint("TOPLEFT", 240, -182)
	p.hitTable = K.Table(sn, RW - 16, 94, HIT_COLUMNS, function(h, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, h.key) return end
		X.SnipeBuy(h.key)
		refresh(p)
	end)
	p.hitTable:SetPoint("TOPLEFT", 8, -232)
end

UI.AddTab("buy", "Buy", build, refresh, 7)
