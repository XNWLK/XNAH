-- Item tab: everything about one item - prices now and over time (graph), fair prices to buy and sell at, ways to make
-- gold with it, its recipe and what it is used in. UI.ShowItem(key) opens it; "Back" goes to the item before.
-- Layout (940 x 550): header 48 high (Buy, Search, Watch list); below it the numbers (left, 300 wide: ten plain rows,
-- or all the numbers with "More numbers") and the graph area (right, 630 wide: a row of buttons, the graph 238 high, a
-- row of names under it - or the best-time charts); under those the profit box (left) and the crafting box (right).
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED, YELLOW = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"
local NONE = "|cff666666-|r"
local RANGES = {{"1 day", 86400}, {"7 days", 7 * 86400}, {"30 days", 30 * 86400}, {"90 days", 90 * 86400}, {"All", nil}}
local rangeIdx = 3
local HOW = {vendor = "Vendor", ah = "Auction", craft = "Craft"}
local NUMBERS = 16  -- rows in the number box (ten in the plain view, up to sixteen with "More numbers")
local PROFITS = 3   -- slots in the profit box (the best three ways)
local PARTS = 8     -- reagent rows
X.Default("itemMore", false) -- true: the number box shows all the numbers

local function M(v) return X.Money(v, true) end
local function signed(v)
	if v >= 0 then return GREEN .. "+" .. X.MoneyPlain(v) .. "|r" end
	return RED .. "-" .. X.MoneyPlain(-v) .. "|r"
end
local function count(n)
	if n == math.floor(n) then return tostring(n) end
	return string.format("%.1f", n)
end

-- [[ search box: the best matches first ]]
local function findItems(text, limit)
	text = X.Trim(text):lower()
	if #text < 2 then return {} end
	local hits = X.Find(text, 400)
	local items = X.Items()
	local function rank(key)
		local name = ((items[key] and items[key].n) or ""):lower()
		if name == text then return 0, name end
		if name:sub(1, #text) == text then return 1, name end
		return 2, name
	end
	local ranks, names = {}, {}
	for _, key in ipairs(hits) do ranks[key], names[key] = rank(key) end
	table.sort(hits, function(a, b)
		if ranks[a] ~= ranks[b] then return ranks[a] < ranks[b] end
		if #names[a] ~= #names[b] then return #names[a] < #names[b] end
		return names[a] < names[b]
	end)
	local out = {}
	for i = 1, math.min(limit, #hits) do out[i] = hits[i] end
	return out
end

local refresh -- below

-- [[ the graph area ]] top row: range buttons, Compare, "Price | Best time"; below it the graph (630 x 238) with a row of
-- names under it (click one to hide / show its line, dots or bars), or the best-time charts (630 x 258) instead
local GX, GW = 310, 630 -- where the graph area starts, its width
local SALE, BUY, CMP = {1, 0.55, 0.2}, {0.75, 0.5, 1}, {0.3, 0.85, 0.95}
local FAIRBUY, FAIRSELL = {0.55, 0.95, 0.7}, {1, 0.9, 0.55}
local LEGEND = {
	{"mkt", "Market value", {1, 0.82, 0}, "The market value at each scan: the average of the cheaper listings (price of one)."},
	{"low", "Lowest price", {0.29, 0.87, 0.5}, "The cheapest listing at each scan (price of one)."},
	{"bars", "Listed", {0.54, 0.64, 1}, "The faint bars: how many were listed at each scan."},
	{"fair", "Fair prices", {0.85, 0.85, 0.85}, "Two thin flat lines: the fair price to buy (lower) and the fair price " ..
		"to sell (upper), worked out from the last 14 days."},
	{"sales", "Your sales", SALE, "Your own sales of this item (from the ledger): a dot at the price of one. Hover it for the details."},
	{"buys", "Your buys", BUY, "Your own purchases of this item (from the ledger): a dot at the price of one. Hover it for the details."},
	{"cmp", "", CMP, nil},
}
local compareKey -- the second item on the graph (kept while you look at other items, until you clear it)
local showBest   -- true: the best-time charts instead of the graph
X.Default("graphHide", {}) -- names under the graph clicked off: {mkt, low, bars, sales, buys = true}

local function setCompare(panel, key)
	K.CloseMenu()
	panel.cmpEdit:SetText("")
	panel.cmpEdit:ClearFocus()
	panel.cmpEdit:Hide()
	if key and key ~= UI.itemKey then compareKey = key end
	refresh(panel)
end

local function buildGraph(panel, body)
	panel.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(body, 50, 20)
		b:SetPoint("TOPLEFT", GX + (i - 1) * 54, 0)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() rangeIdx = i refresh(panel) end)
		panel.ranges[i] = b
	end
	-- Price | Best time
	local best = K.Flat(body, 72, 20)
	best:SetPoint("TOPRIGHT", 0, 0)
	best:SetLabel("Best time")
	best.label:SetJustifyH("CENTER")
	best:SetScript("OnClick", function() showBest = true refresh(panel) end)
	K.Tooltip(best, "Best time to sell", "The price by weekday and by hour of the day (server time), from the price " ..
		"history and your own sales. Green bars: higher than usual, red: lower.")
	panel.viewBest = best
	local price = K.Flat(body, 50, 20)
	price:SetPoint("RIGHT", best, "LEFT", -4, 0)
	price:SetLabel("Price")
	price.label:SetJustifyH("CENTER")
	price:SetScript("OnClick", function() showBest = false refresh(panel) end)
	K.Tooltip(price, "Price graph", "The price over time, with your own sales and buys as dots.")
	panel.viewPrice = price
	-- Compare: a search box with the matches in a menu
	local cmp = K.Flat(body, 66, 20)
	cmp:SetPoint("RIGHT", price, "LEFT", -12, 0)
	cmp:SetLabel("Compare")
	cmp.label:SetJustifyH("CENTER")
	K.Tooltip(cmp, "Compare", "Draws a second item's market value on the same graph. Type its name in the box, pick it. " ..
		"Click its name under the graph to take it off again.")
	panel.cmpBtn = cmp
	local edit = K.Edit(body, 130, function(text)
		local hits = findItems(text, 1)
		if hits[1] then setCompare(panel, hits[1]) else K.CloseMenu() end
	end)
	edit:SetPoint("RIGHT", cmp, "LEFT", -8, 0)
	edit:SetScript("OnEscapePressed", function(self) K.CloseMenu() self:SetText("") self:ClearFocus() self:Hide() end)
	edit:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-item-compare", 0.25, function()
			local text = self:GetText() or ""
			if not self:HasFocus() or #X.Trim(text) < 2 then K.CloseMenu() return end
			local items = {}
			for _, key in ipairs(findItems(text, 15)) do
				if key ~= UI.itemKey then
					items[#items + 1] = {text = UI.ItemCell(key), func = function() setCompare(panel, key) end}
				end
			end
			if #items == 0 then items[1] = {text = "No item found", disabled = true} end
			K.Menu(self, items)
		end)
	end)
	edit:Hide()
	panel.cmpEdit = edit
	cmp:SetScript("OnClick", function()
		if edit:IsShown() then
			K.CloseMenu()
			edit:ClearFocus()
			edit:Hide()
		else
			edit:SetText("")
			edit:Show()
			edit:SetFocus()
		end
	end)

	panel.graph = K.Graph(body, GW, 238)
	panel.graph:SetPoint("TOPLEFT", GX, -24)
	panel.best = K.TimeBars(body, GW, 258)
	panel.best:SetPoint("TOPLEFT", GX, -24)
	panel.best:Hide()

	-- the names under the graph
	panel.legend = {}
	for i, e in ipairs(LEGEND) do
		local b = CreateFrame("Button", nil, body)
		b:SetSize(80, 16)
		b.sw = b:CreateTexture(nil, "ARTWORK")
		b.sw:SetSize(8, 8)
		b.sw:SetPoint("LEFT", 0, 0)
		b.sw:SetColorTexture(e[3][1], e[3][2], e[3][3], 1)
		b.label = K.Label(b, e[2], "GameFontHighlightSmall")
		b.label:SetPoint("LEFT", 12, 0)
		b.label:SetWordWrap(false)
		b.key, b.base = e[1], e[2]
		b:SetScript("OnClick", function()
			if e[1] == "cmp" then
				compareKey = nil
			else
				local hide = X.S().graphHide
				hide[e[1]] = (not hide[e[1]]) or nil
			end
			refresh(panel)
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if e[1] == "cmp" then
				GameTooltip:AddLine(compareKey and X.ItemName(compareKey) or "Compare")
				GameTooltip:AddLine("The market value of a second item, to compare. Click to take it off the graph.", 1, 1, 1, true)
			else
				GameTooltip:AddLine(e[2])
				GameTooltip:AddLine(e[4], 1, 1, 1, true)
				GameTooltip:AddLine(X.S().graphHide[e[1]] and "Hidden - click to show it." or "Click to hide it.", 0.6, 0.6, 0.6)
			end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:Hide()
		panel.legend[i] = b
	end
end

-- [[ Watch list button ]] one menu for the watch list, the highest price to pay and the shopping list
local function askMax(key)
	local cur = X.WatchMax(key)
	K.Ask("Highest price to buy " .. X.ItemName(key) .. " at (each; empty = none)", cur and X.MoneyPlain(cur) or "", false, function(text)
		local c = X.ParseMoney(text)
		if not X.Watched(key) then X.SetWatched(key, true) end
		X.SetWatchMax(key, c)
	end, "Set")
end
local function askShop(key)
	local fair = X.FairPrices(key)
	local price = fair or X.Price(key)
	local list = (X.ShopLists and X.ShopLists()[1]) or "Shopping"
	K.Ask2("Add " .. X.ItemName(key) .. " to a shopping list", {"How many", "20"},
		{"Max price each", price and X.MoneyPlain(price) or "", "List: " .. list},
		function(qty, max)
			X.ShopAdd(list, key, tonumber(qty) or 1, X.ParseMoney(max))
			X.Print("added to the shopping list \"" .. list .. "\"")
		end, "Add")
end
local function listsMenu(anchor, key)
	local watched = X.Watched(key) and true or false
	local wmax = X.WatchMax(key)
	local fair = X.FairPrices(key)
	local items = {
		{text = "On the watch list", checked = watched, func = function() X.SetWatched(key, not X.Watched(key)) end},
		{text = "Highest price to pay" .. (wmax and (": " .. X.MoneyPlain(wmax)) or "") .. " ...", func = function() askMax(key) end},
	}
	if fair and fair ~= wmax then
		items[#items + 1] = {text = "Highest price = the fair price to buy (" .. X.MoneyPlain(fair) .. ")", func = function()
			if not X.Watched(key) then X.SetWatched(key, true) end
			X.SetWatchMax(key, fair)
		end}
	end
	if wmax then items[#items + 1] = {text = "No highest price", func = function() X.SetWatchMax(key, nil) end} end
	if X.ShopAdd then items[#items + 1] = {text = "Add to the shopping list ...", func = function() askShop(key) end} end
	K.Menu(anchor, items)
end

-- [[ Buy button stand-in ]] until the Buy tab's button exists: shows the item's listings in the game's auction house
-- window (buy them there). Same use as the real one: btn:SetItem(key, qty, maxEach, source).
local function standInBuy(parent, w, h)
	local b = K.Button(parent, "Buy", w, h, function(self)
		if self.key and X.ahOpen then X.ShowOnAuctionHouse(self.key) end
	end)
	function b:SetItem(key, qty, maxEach)
		self.key = key
		if X.ahOpen then
			self:SetText(maxEach and ("Buy at or under " .. X.MoneyPlain(maxEach)) or "Buy")
			self:SetEnabled(true)
		else
			self:SetText("Open the auction house")
			self:SetEnabled(false)
		end
	end
	return b
end

local function build(panel)
	local W = UI.W

	-- [[ header ]]
	local icon = CreateFrame("Button", nil, panel)
	icon:SetSize(40, 40)
	icon:SetPoint("TOPLEFT", 0, 0)
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	icon.tex:SetAllPoints()
	icon:SetScript("OnEnter", function(self) if UI.itemKey then UI.ItemTooltip(self, UI.itemKey) end end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.icon = icon
	panel.name = K.Label(panel, "", "GameFontNormalLarge")
	panel.name:SetPoint("TOPLEFT", 48, -3)
	panel.name:SetWidth(540)
	panel.name:SetWordWrap(false)
	panel.sub = K.Label(panel, "", "GameFontDisableSmall")
	panel.sub:SetPoint("TOPLEFT", 48, -27)
	panel.sub:SetWidth(300)
	panel.sub:SetWordWrap(false)

	local back = K.Button(panel, "Back", 60, 22, function()
		local h = UI.history or {}
		if #h >= 2 then
			table.remove(h)
			UI.itemKey = h[#h]
			UI.Refresh(true)
		else
			UI.Open("market")
		end
	end)
	back:SetPoint("TOPRIGHT", 0, 0)
	local find = K.Edit(panel, 170, function(text)
		local hits = findItems(text, 1)
		K.CloseMenu()
		if hits[1] then
			panel.find:SetText("")
			UI.ShowItem(hits[1])
		end
	end)
	find:SetPoint("RIGHT", back, "LEFT", -10, 0)
	panel.find = find
	local findLabel = K.Label(panel, "Find item", "GameFontNormalSmall", "RIGHT")
	findLabel:SetPoint("RIGHT", find, "LEFT", -8, 0)
	find:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-item-find", 0.25, function()
			local text = self:GetText() or ""
			if not self:HasFocus() or #X.Trim(text) < 2 then K.CloseMenu() return end
			local hits = findItems(text, 15)
			local items = {}
			for _, key in ipairs(hits) do
				items[#items + 1] = {text = UI.ItemCell(key), func = function()
					self:SetText("")
					self:ClearFocus()
					UI.ShowItem(key)
				end}
			end
			if #items == 0 then items[1] = {text = "No item found", disabled = true} end
			K.Menu(self, items)
		end)
	end)

	-- [[ the buttons: Watch list (a menu), Search, Buy ]]
	panel.lists = K.Button(panel, "Watch list", 150, 22, function(self)
		if UI.itemKey then listsMenu(self, UI.itemKey) end
	end)
	panel.lists:SetPoint("TOPRIGHT", 0, -25)
	K.Tooltip(panel.lists, "Watch list and shopping list", "Put the item on the watch list (watch list scans and the " ..
		"sniper on the Buy tab look for it), set the highest price you would pay for one, or add it to your shopping list.")
	panel.ah = K.Button(panel, "Search on the auction house", 190, 22, function()
		if UI.itemKey then
			X.ShowOnAuctionHouse(UI.itemKey)
			X.ScanItems({UI.itemKey}, "one item")
		end
	end)
	panel.ah:SetPoint("RIGHT", panel.lists, "LEFT", -6, 0)
	K.Tooltip(panel.ah, "Search on the auction house", "Looks this item up now and records its prices. " ..
		"The game's auction house window shows its listings too.")
	-- Buy: buys what is listed at or under the fair price to buy (check, buy, confirm - one click each)
	panel.buy = UI.BuyButton and UI.BuyButton(panel, 190, 22) or standInBuy(panel, 190, 22)
	if not panel.buy:GetScript("OnEnter") then
		K.Tooltip(panel.buy, "Buy", "Buys this item from the auction house at or under the fair price to buy (see " ..
			"the numbers on the left). Click to look up the listings, click again to buy; stackable items ask once " ..
			"more to confirm the total.")
	end

	panel.hint = K.Label(panel, "Pick an item on the Market tab or type a name above.", "GameFontDisable", "CENTER")
	panel.hint:SetPoint("CENTER", 0, 20)
	panel.hint:SetWidth(600)

	-- everything below the header
	local body = CreateFrame("Frame", nil, panel)
	body:SetPoint("TOPLEFT", 0, -52)
	body:SetSize(W, UI.H - 52)
	panel.body = body

	-- [[ numbers ]]
	local nums = K.Panel(body, 300, 280, {0, 0, 0, 0.25})
	nums:SetPoint("TOPLEFT", 0, 0)
	nums:EnableMouse(true)
	nums:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("The numbers")
		if X.S().itemMore then
			GameTooltip:AddLine("Averages use one value per day. Trend: how fast the price moved over the last 14 days. " ..
				"Day-to-day spread: how much it jumps from day to day (big = risky, or good to buy on a low day). Supply: " ..
				"how many are listed now against the last 7 days.", 1, 1, 1, true)
		else
			GameTooltip:AddLine("Lowest now: the cheapest listing at the last scan (grey when old). Usually sells for: " ..
				"its average price over the last 30 days. Fair prices: see the line under the numbers. Sells a day: an " ..
				"estimate from the scans and your own sales. You own: on all your characters here (bags, bank, mail, " ..
				"auctions).", 1, 1, 1, true)
			GameTooltip:AddLine("More numbers: averages, highs and lows, spread, disenchant value and more.", 0.6, 0.6, 0.6, true)
		end
		GameTooltip:Show()
	end)
	nums:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.numL, panel.numR = {}, {}
	for i = 1, NUMBERS do
		local l = K.Label(nums, "", "GameFontHighlightSmall")
		l:SetWidth(118)
		l:SetWordWrap(false)
		local r = K.Label(nums, "", "GameFontHighlightSmall")
		r:SetWidth(166)
		r:SetWordWrap(false)
		panel.numL[i], panel.numR[i] = l, r
	end
	-- the line that explains the fair prices (plain view only)
	panel.fairNote = K.Label(nums, "", "GameFontDisableSmall")
	panel.fairNote:SetWidth(284)
	panel.fairNote:SetJustifyV("TOP")
	-- More numbers / Fewer numbers
	panel.more = K.Flat(nums, 120, 18)
	panel.more:SetPoint("BOTTOMLEFT", 8, 6)
	panel.more.label:SetJustifyH("CENTER")
	panel.more:SetScript("OnClick", function()
		X.S().itemMore = not X.S().itemMore
		refresh(panel)
	end)
	-- price alert: a chat line and a sound when any scan or search finds it at or under this price
	panel.alert = K.Flat(nums, 156, 18)
	panel.alert:SetPoint("BOTTOMRIGHT", -8, 6)
	panel.alert.label:SetJustifyH("CENTER")
	panel.alert:SetScript("OnClick", function()
		if UI.itemKey and X.AskAlert then X.AskAlert(UI.itemKey) end
	end)
	K.Tooltip(panel.alert, "Price alert", "Click to set the price: when any scan or search finds this item listed at or " ..
		"under it, XNAH says so in chat with a sound, and it shows in the Hits list on the Buy tab (buy it there). " ..
		"Nothing is bought by itself. Leave the box empty to remove the alert. Same price as the watch list's highest " ..
		"price to pay.")

	buildGraph(panel, body)

	-- [[ ways to make gold ]]
	local prof = K.Panel(body, 300, 208, {0, 0, 0, 0.25})
	prof:SetPoint("TOPLEFT", 0, -290)
	local pt = K.Label(prof, "Ways to make gold with this item", "GameFontNormalSmall")
	pt:SetPoint("TOPLEFT", 8, -7)
	panel.profTitle = pt
	panel.prof = {}
	for i = 1, PROFITS do
		local head = K.Label(prof, "", "GameFontHighlightSmall")
		head:SetWidth(284)
		head:SetWordWrap(false)
		local text = K.Label(prof, "", "GameFontDisableSmall")
		text:SetWidth(284)
		text:SetJustifyV("TOP")
		panel.prof[i] = {head = head, text = text}
	end
	panel.profBox = prof

	-- [[ crafting ]] its recipe (left) and recipes that use it (right)
	local craft = K.Panel(body, W - 310, 208, {0, 0, 0, 0.25})
	craft:SetPoint("TOPLEFT", 310, -290)
	panel.cTitle = K.Label(craft, "", "GameFontNormalSmall")
	panel.cTitle:SetPoint("TOPLEFT", 8, -7)
	panel.cTitle:SetWidth(390)
	panel.cTitle:SetWordWrap(false)
	panel.cKnown = K.Label(craft, "", "GameFontDisableSmall")
	panel.cKnown:SetPoint("TOPLEFT", 8, -23)
	panel.cKnown:SetWidth(390)
	panel.cKnown:SetWordWrap(false)
	-- reagent columns: name, count, each, from, cost
	local PC = {{4, 150, "LEFT"}, {156, 28, "RIGHT"}, {188, 66, "RIGHT"}, {262, 50, "LEFT"}, {314, 74, "RIGHT"}}
	local hdrNames = {"Reagent", "Count", "Each", "From", "Cost"}
	panel.cHead = {}
	for c, col in ipairs(PC) do
		local fs = K.Label(craft, GREY .. hdrNames[c] .. "|r", "GameFontHighlightSmall", col[3])
		fs:SetPoint("TOPLEFT", 8 + col[1], -39)
		fs:SetWidth(col[2])
		panel.cHead[c] = fs
	end
	panel.parts = {}
	for i = 1, PARTS do
		local b = K.Flat(craft, 392, 15)
		b:SetPoint("TOPLEFT", 8, -53 - (i - 1) * 15)
		b.label:Hide()
		b.cols = {}
		for c, col in ipairs(PC) do
			local fs = K.Label(b, "", "GameFontHighlightSmall", col[3])
			fs:SetPoint("LEFT", col[1], 0)
			fs:SetWidth(col[2])
			fs:SetWordWrap(false)
			b.cols[c] = fs
		end
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:Hide()
		panel.parts[i] = b
	end
	panel.cFoot = K.Label(craft, "", "GameFontHighlightSmall")
	panel.cFoot:SetPoint("TOPLEFT", 8, -53 - PARTS * 15 - 5)
	panel.cFoot:SetWidth(390)
	panel.cFoot:SetJustifyV("TOP")
	panel.uTitle = K.Label(craft, "", "GameFontNormalSmall")
	panel.uTitle:SetPoint("TOPLEFT", 410, -7)
	panel.uTitle:SetWidth(210)
	-- every recipe the item goes into (scrolls); hovering one shows the whole recipe, a click opens what it makes
	panel.used = K.List(craft, 214, 180, 17, function(row, e)
		local okey = e.key
		row:SetLabel(okey and UI.ItemCell(okey, 12) or ("|cffffd100" .. X.RecipeTitle(e.rid) .. "|r"))
		row:SetScript("OnClick", function(self, button)
			if not okey then return end
			if button == "RightButton" then UI.ItemMenu(self, okey) else UI.ShowItem(okey) end
		end)
		row:SetScript("OnEnter", function(self) UI.RecipeTooltip(self, e.rid, panel.usedFor) end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end)
	panel.used:SetPoint("TOPLEFT", 410, -22)
end

-- [[ a recipe as a tooltip ]] profession and skill, who knows it, what it makes, every reagent with its price, the cost,
-- the price it sells for and the profit. mark = an item ID shown in green (the item whose page this is).
local SKILL_COLORS = {"ff8040", "ffff00", "40c040", "808080"}
function UI.RecipeTooltip(owner, rid, mark)
	local r = X.Recipe(rid)
	if not r then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(r.name or "?", 1, 0.82, 0)
	local sub = (r.prof or "Recipe") .. (r.la and (" " .. r.la) or "")
	if r.colors then
		local c = {}
		for i = 1, 4 do
			if (r.colors[i] or 0) > 0 then c[#c + 1] = "|cff" .. SKILL_COLORS[i] .. r.colors[i] .. "|r" end
		end
		sub = sub .. GREY .. "   skill-ups: |r" .. table.concat(c, " ")
	end
	GameTooltip:AddLine(sub, 0.8, 0.8, 0.8)
	local who = X.KnownBy(rid)
	if #who > 0 then
		GameTooltip:AddLine("Known by: " .. table.concat(who, ", "), 0.29, 0.87, 0.5)
	else
		GameTooltip:AddLine("None of your characters knows it (that XNAH has seen in a profession window).", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(" ")
	if r.out then
		GameTooltip:AddDoubleLine("Makes", ((r.n or 1) ~= 1 and (count(r.n) .. " x ") or "") .. X.ItemText(tostring(r.out)), 0.6, 0.6, 0.6, 1, 1, 1)
	end
	local parts, total, missing = X.RecipeParts(rid), 0, 0
	for _, p in ipairs(parts) do
		local name = X.ItemText(tostring(p.id))
		if p.id == mark then name = "|cff4ade80> |r" .. name end
		local cost = p.unit and (M(p.unit * p.count) .. GREY .. " " .. (HOW[p.how] or "") .. "|r") or (RED .. "no price|r")
		GameTooltip:AddDoubleLine(count(p.count) .. " x " .. name, cost, 1, 1, 1, 1, 1, 1)
		if p.unit then total = total + p.unit * p.count else missing = missing + 1 end
	end
	GameTooltip:AddLine(" ")
	local each = r.out and (r.n or 1) ~= 1 and (GREY .. " (" .. M(total / (r.n or 1)) .. GREY .. " each)|r") or ""
	GameTooltip:AddDoubleLine("Cost of one craft", M(total) .. each, 0.6, 0.6, 0.6, 1, 1, 1)
	if missing > 0 then
		GameTooltip:AddLine(missing .. " reagent" .. (missing > 1 and "s have" or " has") .. " no price yet: the cost is too low.", 0.97, 0.44, 0.44, true)
	end
	if r.out then
		local sell = X.AfterCut(X.Price(tostring(r.out)))
		GameTooltip:AddDoubleLine("Sells for (after the cut)", sell and M(sell * (r.n or 1)) or NONE, 0.6, 0.6, 0.6, 1, 1, 1)
		if sell and missing == 0 then GameTooltip:AddDoubleLine("Profit per craft", signed(sell * (r.n or 1) - total), 0.6, 0.6, 0.6, 1, 1, 1) end
		GameTooltip:AddLine("Click: open " .. X.ItemName(tostring(r.out)) .. "   Right-click: menu", 0.6, 0.6, 0.6)
	end
	GameTooltip:Show()
end

-- [[ filling it in ]]
-- "rising 6% a week" / "steady"
local function trendText(p)
	if not p then return NONE end
	if math.abs(p) < 4 then return GREY .. "steady|r" end
	return (p > 0 and GREEN .. "rising " or RED .. "falling ") .. string.format("%.0f%%", math.abs(p)) ..
		"|r" .. GREY .. " a week|r"
end

-- the ten plain rows
local function plainRows(s)
	local cur, st = s.cur, s.st or {}
	local stale = not s.fresh
	local low = NONE
	if cur then
		if (cur.qty or 0) == 0 then
			low = GREY .. "none listed|r"
		else
			low = UI.MoneyCell(cur.min, stale)
			if s.fresh and s.fairBuy and cur.min and cur.min <= s.fairBuy then low = low .. GREEN .. "  a good price|r" end
		end
	end
	local listed = NONE
	if cur and cur.qty then
		listed = X.Num(cur.qty)
		if st.supply and cur.qty > 0 then
			if st.supply <= -25 then listed = listed .. GREY .. "  fewer than usual|r"
			elseif st.supply >= 25 then listed = listed .. GREY .. "  more than usual|r"
			else listed = listed .. GREY .. "  about as usual|r" end
		end
	end
	local own = NONE
	if s.owned then
		own = s.owned > 0 and (X.Num(s.owned) .. (s.ownedBags and s.ownedBags > 0 and s.ownedBags < s.owned and
			(GREY .. "  (" .. X.Num(s.ownedBags) .. " in your bags)|r") or "")) or (GREY .. "none|r")
	end
	local rows = {
		{"Lowest now", low},
		{"Usually sells for", M(s.usual)},
		{"Fair price to buy", s.fairBuy and (M(s.fairBuy) .. GREY .. "  or less|r") or (GREY .. "not known yet|r")},
		{"Fair price to sell", s.fairSell and (M(s.fairSell) .. GREY .. "  (you keep |r" .. M(X.AfterCut(s.fairSell)) .. GREY .. ")|r") or
			(GREY .. "not known yet|r")},
		{"Sells a day", s.rate and (GREY .. "about |r" .. X.Rate(s.rate)) or NONE},
		{"Listed now", listed},
		{"Price trend", trendText(st.trend)},
		{"Vendor pays", M(s.vsell)},
		{"You own", own},
		{"Seen", cur and cur.t and (X.Ago(cur.t) .. (stale and (GREY .. "  (old - search again)|r") or "")) or (GREY .. "never|r")},
	}
	-- only when the history shows a weekday clearly higher than the rest (X.BestDay)
	if s.bestDay then
		table.insert(rows, 6, {"Best day to sell", s.bestDay.name .. GREY .. " (|r" .. X.Pct(s.bestDay.pct) .. GREY .. ")|r"})
	end
	return rows
end

-- every number ("More numbers")
local function moreRows(s)
	local cur, st = s.cur, s.st or {}
	local stale = not s.fresh
	local info = s.vbuyInfo
	return {
		{"Market value", cur and UI.MoneyCell(cur.mkt, stale) or NONE},
		{"Listed", cur and cur.qty and (X.Num(cur.qty) .. GREY .. " (" .. X.Num(cur.auc or 0) .. " auctions)|r") or NONE},
		{"3-day average", M(st.avg3)},
		{"7-day average", M(st.avg7)},
		{"30-day average", M(st.avg30)},
		{"30-day low / high", st.low30 and (M(st.low30) .. GREY .. " / |r" .. M(st.high30)) or NONE},
		{"Trend", st.trend and (X.Arrow(st.trend) .. " " .. X.Pct(st.trend) .. GREY .. " a week|r") or NONE},
		{"Day-to-day spread", st.vol and string.format("%.0f%%", st.vol) or NONE},
		{"Supply vs 7 days", st.supply and (X.Pct(st.supply, true) .. GREY .. " (usually " .. X.Num(st.qty7) .. ")|r") or NONE},
		{"Sells per day", s.rate and (GREY .. "about |r" .. X.Rate(s.rate) .. (s.rateHours and (GREY .. "  (" .. X.Num(s.rateHours) .. " h seen)|r") or "")) or NONE},
		{"Vendor sells at", s.vbuy and (M(s.vbuy) .. (info and info.lim and (GREY .. " limited|r") or "") ..
			(info and info.from and (GREY .. "  " .. info.from .. "|r") or "")) or NONE},
		{"Disenchant value", s.de and M(s.de) or NONE},
		{"After the " .. X.S().cut .. "% cut", M(s.sell)},
		{"Your trades", s.ledger and (((s.ledger.sold or 0) > 0 or (s.ledger.bought or 0) > 0) and
			(GREY .. "sold |r" .. X.Num(s.ledger.sold or 0) .. GREY .. ", bought |r" .. X.Num(s.ledger.bought or 0) ..
			(s.ledger.sellThrough and (GREY .. ", " .. string.format("%.0f%%", s.ledger.sellThrough * 100) .. " sell|r") or "")) or NONE) or NONE},
		{"Strategies", s.marks and #s.marks > 0 and (YELLOW .. table.concat(s.marks, ", ") .. "|r") or NONE},
		{"First seen", st.first and X.Date(st.first * 86400 + 43200, "%b %d") or NONE},
	}
end

local function fillNumbers(panel, key, s)
	local more = X.S().itemMore and true or false
	local rows = more and moreRows(s) or plainRows(s)
	local step = more and 14.6 or 18
	for i = 1, NUMBERS do
		local r = rows[i]
		local l, v = panel.numL[i], panel.numR[i]
		l:ClearAllPoints()
		l:SetPoint("TOPLEFT", 8, -7 - (i - 1) * step)
		v:ClearAllPoints()
		v:SetPoint("TOPLEFT", 128, -7 - (i - 1) * step)
		l:SetText(r and (GREY .. r[1] .. "|r") or "")
		v:SetText(r and r[2] or "")
		l:SetShown(r ~= nil)
		v:SetShown(r ~= nil)
	end
	panel.fairNote:ClearAllPoints()
	panel.fairNote:SetPoint("TOPLEFT", 8, -7 - #rows * step - 4)
	panel.fairNote:SetText(more and "" or (GREY .. (s.fairNote or "") .. "|r"))
	panel.fairNote:SetShown(not more)
	panel.more:SetLabel(more and "Fewer numbers" or "More numbers")
end

-- [[ ways to make gold ]] only real chances: a profit after the cut, at the fair price to sell (not a one-off high
-- price), with today's listings for the ones that need buying on the auction house. The best three.
local function fillProfits(panel, s)
	local cur = s.cur
	local list = {}
	local sellAt = s.fairSell or s.usual
	local keep = sellAt and X.AfterCut(sellAt)
	local listedNow = s.fresh and cur and cur.min and (cur.qty or 0) > 0
	local old = s.fresh and "" or " Prices are old: search again first."
	local slow = ""
	if s.rate and s.rate < 0.5 then slow = " It sells slowly (about " .. X.Rate(s.rate) .. " a day)." end
	if listedNow and keep and s.fairBuy and cur.min <= s.fairBuy and keep - cur.min > 0 then
		list[#list + 1] = {keep - cur.min, "Buy it now, sell it later", "Listed now at " .. M(cur.min) .. GREY ..
			", a fair price to buy. Sold at its usual " .. M(sellAt) .. GREY .. " you keep " .. M(keep) .. GREY .. "." .. slow}
	end
	if listedNow and s.vsell and s.vsell > cur.min then
		list[#list + 1] = {s.vsell - cur.min, "Listed under the vendor price", "Buy it for " .. M(cur.min) .. GREY ..
			"; any vendor pays " .. M(s.vsell) .. GREY .. ". No risk."}
	end
	if s.vbuy and keep and keep > s.vbuy then
		local from = s.vbuyInfo and s.vbuyInfo.from
		local lim = s.vbuyInfo and s.vbuyInfo.lim and " (only a few)" or ""
		list[#list + 1] = {keep - s.vbuy, "Buy from a vendor, sell here", "A vendor" .. (from and (" (" .. from .. ")") or "") ..
			" sells it for " .. M(s.vbuy) .. GREY .. lim .. "; here you keep " .. M(keep) .. GREY .. "." .. old .. slow}
	end
	if s.craft and keep and keep > s.craft then
		list[#list + 1] = {keep - s.craft, "Craft it and sell it", "The reagents cost " .. M(s.craft) .. GREY ..
			" (see Crafting); you keep " .. M(keep) .. GREY .. "." .. old .. slow}
	end
	if listedNow and s.de and s.de > cur.min then
		list[#list + 1] = {s.de - cur.min, "Buy it and disenchant it", "Listed at " .. M(cur.min) .. GREY ..
			"; the materials are worth " .. M(s.de) .. GREY .. " on average (needs an enchanter)."}
	end
	table.sort(list, function(a, b) return a[1] > b[1] end)
	local y = -24
	for i = 1, PROFITS do
		local slot, e = panel.prof[i], list[i]
		slot.head:ClearAllPoints()
		slot.text:ClearAllPoints()
		if e or (i == 1 and #list == 0) then
			slot.head:SetPoint("TOPLEFT", panel.profBox, "TOPLEFT", 8, y)
			slot.text:SetPoint("TOPLEFT", panel.profBox, "TOPLEFT", 8, y - 14)
			if e then
				slot.head:SetText(signed(e[1]) .. "  " .. e[2] .. GREY .. " (each)|r")
				slot.text:SetText(GREY .. e[3] .. "|r")
			else
				slot.head:SetText(GREY .. "Nothing worth doing with it right now.|r")
				slot.text:SetText(GREY .. "XNAH looks for: buying it cheap and selling it again, vendor prices, crafting " ..
					"and disenchanting. More scans, vendor visits and profession windows help.|r")
			end
			slot.head:Show()
			slot.text:Show()
			y = y - 14 - math.max(12, slot.text:GetStringHeight() or 24) - 8
		else
			slot.head:Hide()
			slot.text:Hide()
		end
	end
end

local function fillCrafting(panel, s)
	local id = s.id
	local rid = s.craftRid
	local all = X.RecipesFor(id)
	if not rid then rid = all[1] end -- a recipe with a reagent that has no price yet
	local r = rid and X.Recipe(rid)
	for i = 1, PARTS do panel.parts[i]:Hide() end
	for _, h in ipairs(panel.cHead) do h:SetShown(r ~= nil) end
	if not r then
		panel.cTitle:SetText("Crafting")
		panel.cKnown:SetText(GREY .. "No recipe makes this item.|r")
		panel.cFoot:SetText("")
	else
		panel.cTitle:SetText("Crafting" .. (r.prof and (" (" .. r.prof .. ")") or "") .. ": " .. (r.name or "?") ..
			((r.n or 1) ~= 1 and (GREY .. "  makes " .. count(r.n) .. "|r") or "") ..
			(#all > 1 and (GREY .. "  cheapest of " .. #all .. " recipes|r") or ""))
		local who = X.KnownBy(rid)
		if #who > 0 then
			panel.cKnown:SetText(GREY .. "Known by: |r" .. table.concat(who, ", "))
		elseif r.db then
			panel.cKnown:SetText(GREY .. "From the recipe list" .. (r.la and (", needs " .. (r.prof or "skill") .. " " .. r.la) or "") ..
				". None of your characters knows it (yet).|r")
		else
			panel.cKnown:SetText(GREY .. "None of your characters knows this recipe (yet).|r")
		end
		local parts = X.RecipeParts(rid)
		for i = 1, math.min(PARTS, #parts) do
			local p, b = parts[i], panel.parts[i]
			local pkey = tostring(p.id)
			b.cols[1]:SetText(UI.ItemCell(pkey, 12))
			b.cols[2]:SetText(count(p.count))
			b.cols[3]:SetText(p.unit and M(p.unit) or (RED .. "no price|r"))
			b.cols[4]:SetText(GREY .. (HOW[p.how] or "-") .. "|r")
			b.cols[5]:SetText(p.unit and M(p.unit * p.count) or NONE)
			b:SetScript("OnClick", function() UI.ShowItem(pkey) end)
			b:SetScript("OnEnter", function(self) UI.ItemTooltip(self, pkey) end)
			b:SetSelected(false)
			b:Show()
		end
		local cost, missing = X.RecipeCost(rid)
		local text = "Cost to make one: " .. M(cost)
		if (missing or 0) > 0 then text = text .. RED .. "  (" .. missing .. " reagent" .. (missing > 1 and "s" or "") .. " without a price)|r" end
		text = text .. GREY .. "   Sells for |r" .. M(s.sell) .. GREY .. " after the cut|r"
		if #parts > PARTS then text = text .. GREY .. "   (+" .. (#parts - PARTS) .. " more reagents)|r" end
		panel.cFoot:SetText(text)
	end

	-- used in
	local using = X.RecipesUsing(id)
	local list = {}
	for _, urid in ipairs(using) do
		local ur = X.Recipe(urid)
		if ur then
			local okey = ur.out and tostring(ur.out)
			list[#list + 1] = {rid = urid, r = ur, key = okey, price = okey and X.Price(okey) or nil}
		end
	end
	table.sort(list, function(a, b)
		if (a.price ~= nil) ~= (b.price ~= nil) then return a.price ~= nil end
		if a.price and b.price and a.price ~= b.price then return a.price > b.price end
		return (a.r.name or "") < (b.r.name or "")
	end)
	panel.uTitle:SetText("Used in" .. (#list > 0 and (GREY .. " (" .. #list .. " recipe" .. (#list > 1 and "s" or "") .. ", hover one)|r") or ""))
	panel.usedFor = id
	if panel.usedShown ~= id then panel.used.offset = 0 end
	panel.usedShown = id
	panel.used:SetItems(list, GREY .. "Not used in any recipe.|r")
end

-- your sales or buys of the item from `from` on, as dots: {t, v = price of one, color, text}; also how many in all
local function tradeMarks(key, which, from, color, verb)
	local list = X.GraphTrades and X.GraphTrades(key, which) or {}
	local marks = {}
	for _, e in ipairs(list) do
		if e.t >= from then
			local c = math.max(1, e.count or 1)
			marks[#marks + 1] = {t = e.t, v = e.money / c, color = color,
				text = verb .. " " .. X.Num(c) .. " at " .. M(e.money / c) .. " each" .. GREY .. "  " .. X.Date(e.t, "%b %d %H:%M") .. "|r"}
		end
	end
	return marks, #list
end

local function average(points)
	local s, n = 0, 0
	for _, p in ipairs(points) do if p[2] then s, n = s + p[2], n + 1 end end
	return n > 0 and s / n or nil
end

-- the names under the graph, left to right; info = {sales, buys (in all), inSales, inBuys (in the range), fair (fair
-- prices known), cmpName, right}
local function layoutLegend(panel, info)
	local hide = X.S().graphHide
	local x = 0
	for _, b in ipairs(panel.legend) do
		local k = b.key
		local show, text = true, b.base
		if k == "sales" then
			show, text = info.sales > 0, "Your sales (" .. info.inSales .. ")"
		elseif k == "buys" then
			show, text = info.buys > 0, "Your buys (" .. info.inBuys .. ")"
		elseif k == "fair" then
			show = info.fair
		elseif k == "cmp" then
			show = info.cmpName ~= nil
			text = "vs " .. (info.cmpName or "") .. (info.right and GREY .. " (scale on the right)|r" or "") .. RED .. "  x|r"
		end
		local w = 0
		if show then
			b.label:SetText(hide[k] and (GREY .. text .. "|r") or text)
			b.sw:SetAlpha(hide[k] and 0.25 or 1)
			w = math.min(GW - x, (b.label:GetUnboundedStringWidth() or 60) + 14)
			b.label:SetWidth(math.max(1, w - 12))
			b:SetWidth(math.max(1, w))
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", panel.body, "TOPLEFT", GX + x, -266)
			x = x + w + 12
		end
		b:SetShown(show and w >= 30)
	end
end

local function fillGraph(panel, key, fairBuy, fairSell)
	local hide = X.S().graphHide
	for i, b in ipairs(panel.ranges) do b:SetSelected(i == rangeIdx) end
	local range = RANGES[rangeIdx][2]
	local from = range and (X.Now() - range) or 0
	local hist = X.History(key, from)
	local mkt, low, qty = {}, {}, {}
	for i, p in ipairs(hist) do
		mkt[i] = {p[1], p[3]}
		low[i] = {p[1], p[2]}
		qty[i] = {p[1], p[4]}
	end
	local series = {}
	if not hide.mkt then series[#series + 1] = {points = mkt, color = LEGEND[1][3], width = 2, label = "Market value"} end
	if not hide.low then series[#series + 1] = {points = low, color = LEGEND[2][3], width = 1.5, label = "Lowest price"} end
	-- your trades as dots
	local sales, nSales = tradeMarks(key, "sales", from, SALE, "You sold")
	local buys, nBuys = tradeMarks(key, "buys", from, BUY, "You bought")
	local marks = {}
	if not hide.sales then for _, m in ipairs(sales) do marks[#marks + 1] = m end end
	if not hide.buys then for _, m in ipairs(buys) do marks[#marks + 1] = m end end
	-- a second item: on its own scale (numbers on the right) when its price is far from this one's
	local cmpName, right
	local ck = compareKey ~= key and compareKey or nil -- on the compared item's own page: not drawn twice
	if ck then
		local pts = {}
		for i, p in ipairs(X.History(ck, from)) do pts[i] = {p[1], p[3]} end
		local a, b = average(mkt), average(pts)
		right = (a and b and (b > a * 2.5 or b < a / 2.5)) and true or false
		cmpName = X.ItemName(ck) or ck
		local short = #cmpName > 22 and (cmpName:sub(1, 20) .. "..") or cmpName
		series[#series + 1] = {points = pts, color = CMP, width = 2, label = short, right = right}
	end
	panel.cmpBtn:SetSelected(ck ~= nil)
	local empty
	if #hist == 0 and range and #X.History(key, 0) > 0 then empty = "No prices in this time - pick a longer range" end
	if #series == 0 and #marks == 0 and #hist > 0 then empty = "Everything is hidden - click the names under the graph to show them" end
	-- the fair prices as two flat lines
	local levels = {}
	if not hide.fair and fairBuy and fairSell then
		levels[1] = {v = fairSell, color = FAIRSELL, label = "Fair to sell"}
		levels[2] = {v = fairBuy, color = FAIRBUY, label = "Fair to buy"}
	end
	panel.graph:SetSeries(series, {bars = (not hide.bars) and qty or nil, barsLabel = "Listed", empty = empty, marks = marks,
		levels = levels})
	layoutLegend(panel, {sales = nSales, buys = nBuys, inSales = #sales, inBuys = #buys, fair = fairBuy ~= nil and #hist > 0,
		cmpName = cmpName, right = right})
end

-- the graph or the best-time charts
local function fillView(panel, key, s)
	local best = showBest and true or false
	panel.viewBest:SetSelected(best)
	panel.viewPrice:SetSelected(not best)
	for _, b in ipairs(panel.ranges) do b:SetShown(not best) end
	panel.cmpBtn:SetShown(not best)
	if best and panel.cmpEdit:IsShown() then
		K.CloseMenu()
		panel.cmpEdit:ClearFocus()
		panel.cmpEdit:Hide()
	end
	panel.graph:SetShown(not best)
	panel.best:SetShown(best)
	if best then
		for _, b in ipairs(panel.legend) do b:Hide() end
		panel.best:SetData(X.BestTimes(key))
	else
		fillGraph(panel, key, s.fairBuy, s.fairSell)
	end
end

refresh = function(panel)
	local key = UI.itemKey
	local has = key ~= nil
	panel.body:SetShown(has)
	panel.hint:SetShown(not has)
	panel.icon:SetShown(has)
	panel.name:SetShown(has)
	panel.sub:SetShown(has)
	panel.lists:SetShown(has)
	panel.buy:SetShown(has)
	panel.ah:SetShown(has and X.ahOpen == true)
	if not has then return end

	local s = X.Summary(key)
	if X.SaleRate then s.rate, s.rateHours = X.SaleRate(key) end
	if X.DEValue then s.de = X.DEValue(key) end
	if X.LedgerItem then s.ledger = X.LedgerItem(key) end
	if X.StrategyMarks then s.marks = X.StrategyMarks(key) end
	if X.BestDay then s.bestDay = X.BestDay(key) end
	if X.Owned then
		local total, parts = X.Owned(key)
		s.owned, s.ownedBags = total, parts and parts.bags
	end
	s.fairBuy, s.fairSell, s.fairNote = X.FairPrices(key)
	local id = s.id
	local tex = id and X.Try(C_Item.GetItemIconByID, id)
	panel.icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
	panel.name:SetText(X.ItemText(key))
	local _, q = X.ItemName(key)
	local sub = "Item " .. tostring(key) .. "  -  " .. (X.QUALITY_NAMES[q or 1] or "")
	if not s.cur then
		sub = sub .. "  -  never seen on the auction house"
	elseif not s.fresh then
		sub = sub .. "  -  |cffff8040prices are old (" .. X.Ago(s.cur.t) .. ")|r"
	end
	panel.sub:SetText(GREY .. sub .. "|r")
	local wmax = X.WatchMax(key)
	panel.alert:SetLabel(wmax and ("Alert under " .. X.MoneyPlain(wmax)) or "Alert me under ...")
	panel.alert:SetShown(X.AskAlert ~= nil)
	panel.lists:SetText(X.Watched(key) and (wmax and ("Watched, max " .. X.MoneyPlain(wmax)) or "Watched") or "Watch list")
	panel.ah:SetEnabled(X.scan and X.scan.state == "idle")
	-- Buy: set again only when the item or the price changes (it walks its own steps: buy, confirm)
	local buyFor = key .. "/" .. tostring(s.fairBuy)
	if panel.buyFor ~= buyFor or not UI.BuyButton then
		panel.buyFor = buyFor
		panel.buy:SetItem(key, nil, s.fairBuy, "item")
	end
	panel.buy:ClearAllPoints()
	panel.buy:SetPoint("RIGHT", panel.ah:IsShown() and panel.ah or panel.lists, "LEFT", -6, 0)

	fillNumbers(panel, key, s)
	fillView(panel, key, s)
	fillProfits(panel, s)
	fillCrafting(panel, s)
end

UI.AddTab("item", "Item", build, refresh, 2)
