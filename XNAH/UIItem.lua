-- Item tab: everything about one item - prices now and over time (graph), ways to make gold with it, its recipe and
-- what it is used in. UI.ShowItem(key) opens it; "Back" goes to the item before.
-- Layout (940 x 550): header 48 high; below it numbers (left, 300 wide) and the graph (right, 630 x 256); under
-- those the profit box (left) and the crafting box (right), 208 high.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED = "|cff999999", "|cff4ade80", "|cfff87171"
local NONE = "|cff666666-|r"
local RANGES = {{"1 day", 86400}, {"7 days", 7 * 86400}, {"30 days", 30 * 86400}, {"90 days", 90 * 86400}, {"All", nil}}
local rangeIdx = 3
local HOW = {vendor = "Vendor", ah = "Auction", craft = "Craft"}
local NUMBERS = 19  -- rows in the number grid
local PROFITS = 4   -- slots in the profit box (the best four ways)
local PARTS = 8     -- reagent rows

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

	panel.ah = K.Button(panel, "Search on the auction house", 200, 22, function()
		if UI.itemKey then
			X.ShowOnAuctionHouse(UI.itemKey)
			X.ScanItems({UI.itemKey}, "one item")
		end
	end)
	panel.ah:SetPoint("TOPRIGHT", 0, -25)
	K.Tooltip(panel.ah, "Search on the auction house", "Looks this item up now and records its prices. " ..
		"The game's auction house window shows its listings too, ready to buy.")
	panel.star = K.Button(panel, "Add to watch list", 150, 22, function()
		local key = UI.itemKey
		if key then X.SetWatched(key, not X.Watched(key)) end
	end)
	panel.star:SetPoint("RIGHT", panel.ah, "LEFT", -6, 0)
	-- highest price to buy at (the sniper on the Buy tab watches for it)
	panel.max = K.Button(panel, "Max price", 96, 22, function()
		local key = UI.itemKey
		if not key then return end
		local cur = X.WatchMax(key)
		K.Ask("Highest price to buy " .. X.ItemName(key) .. " at (each; empty = none)", cur and X.MoneyPlain(cur) or "", false, function(text)
			local c = X.ParseMoney(text)
			if not X.Watched(key) then X.SetWatched(key, true) end
			X.SetWatchMax(key, c)
		end, "Set")
	end)
	panel.max:SetPoint("RIGHT", panel.star, "LEFT", -6, 0)
	K.Tooltip(panel.max, "Max price", "Puts the item on the watch list with the highest price you would pay for one. " ..
		"With the sniper on (Buy tab) XNAH tells you when one is listed at or under it.")
	panel.shop = K.Button(panel, "Shopping list", 104, 22, function()
		local key = UI.itemKey
		if not key or not X.ShopAdd then return end
		local price = X.Price(key)
		K.Ask2("Add " .. X.ItemName(key) .. " to a shopping list", {"How many", "20"},
			{"Max price each", price and X.MoneyPlain(math.floor(price * 1.1)) or "", "List: " .. ((X.ShopLists and X.ShopLists()[1]) or "Shopping")},
			function(qty, max)
				local list = (X.ShopLists and X.ShopLists()[1]) or "Shopping"
				X.ShopAdd(list, key, tonumber(qty) or 1, X.ParseMoney(max))
				X.Print("added to the shopping list \"" .. list .. "\"")
			end, "Add")
	end)
	panel.shop:SetPoint("RIGHT", panel.max, "LEFT", -6, 0)

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
	K.Tooltip(nums, "The numbers", "Lowest now and market value come from the last scan (grey when old). Averages use " ..
		"one value per day. Trend: how fast the price moved over the last 14 days. Spread: how much it jumps from day " ..
		"to day. Supply: how many are listed now compared with the last 7 days.")
	panel.numL, panel.numR = {}, {}
	for i = 1, NUMBERS do
		local l = K.Label(nums, "", "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, -6 - (i - 1) * 14.3)
		l:SetWidth(128)
		l:SetWordWrap(false)
		local r = K.Label(nums, "", "GameFontHighlightSmall")
		r:SetPoint("TOPLEFT", 138, -6 - (i - 1) * 14.3)
		r:SetWidth(156)
		r:SetWordWrap(false)
		panel.numL[i], panel.numR[i] = l, r
	end

	-- [[ graph ]] with range buttons and a legend
	panel.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(body, 66, 20)
		b:SetPoint("TOPLEFT", 310 + (i - 1) * 70, 0)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() rangeIdx = i refresh(panel) end)
		panel.ranges[i] = b
	end
	local legend = K.Label(body, "|cffffd100Market value|r   |cff4ade80Lowest price|r   |cff8aa4ffBars: listed|r", "GameFontHighlightSmall", "RIGHT")
	legend:SetPoint("TOPRIGHT", -2, -4)
	legend:SetWidth(260)
	panel.graph = K.Graph(body, W - 310, 256)
	panel.graph:SetPoint("TOPLEFT", 310, -24)

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
local function fillNumbers(panel, key, s)
	local cur, st = s.cur, s.st or {}
	local stale = not s.fresh
	local info = s.vbuyInfo
	-- "4 sellers, wall 200 at 1g 2s"
	local shape = NONE
	if s.shape then
		local parts = {}
		if s.shape.sellers then parts[#parts + 1] = X.Num(s.shape.sellers) .. GREY .. " sellers|r" end
		if s.shape.wall then
			parts[#parts + 1] = GREY .. "wall |r" .. X.Num(s.shape.wall.units or 0) .. GREY .. " at |r" .. M(s.shape.wall.price)
		end
		if #parts > 0 then shape = table.concat(parts, GREY .. ", |r") end
	end
	local rows = {
		{"Lowest now", cur and ((cur.qty or 0) == 0 and GREY .. "none listed|r" or UI.MoneyCell(cur.min, stale)) or NONE},
		{"Market value", cur and UI.MoneyCell(cur.mkt, stale) or NONE},
		{"Listed", cur and cur.qty and (X.Num(cur.qty) .. GREY .. " (" .. X.Num(cur.auc or 0) .. " auctions" ..
			(cur.sellers and (", " .. X.Num(cur.sellers) .. " sellers") or "") .. ")|r") or NONE},
		{"3-day average", M(st.avg3)},
		{"7-day average", M(st.avg7)},
		{"30-day average", M(st.avg30)},
		{"30-day low / high", st.low30 and (M(st.low30) .. GREY .. " / |r" .. M(st.high30)) or NONE},
		{"Trend", st.trend and (X.Arrow(st.trend) .. " " .. X.Pct(st.trend) .. GREY .. " a week|r") or NONE},
		{"Day-to-day spread", st.vol and string.format("%.0f%%", st.vol) or NONE},
		{"Supply vs 7 days", st.supply and (X.Pct(st.supply, true) .. GREY .. " (usually " .. X.Num(st.qty7) .. ")|r") or NONE},
		{"Sells per day", s.rate and (GREY .. "about |r" .. X.Rate(s.rate) .. (s.rateHours and (GREY .. "  (" .. X.Num(s.rateHours) .. " h seen)|r") or "")) or NONE},
		{"Vendor pays", M(s.vsell)},
		{"Vendor sells at", s.vbuy and (M(s.vbuy) .. (info and info.lim and (GREY .. " limited|r") or "") ..
			(info and info.from and (GREY .. "  " .. info.from .. "|r") or "")) or NONE},
		{"Disenchant value", s.de and M(s.de) or NONE},
		{"After the " .. X.S().cut .. "% cut", M(s.sell)},
		{"Your trades", s.ledger and (((s.ledger.sold or 0) > 0 or (s.ledger.bought or 0) > 0) and
			(GREY .. "sold |r" .. X.Num(s.ledger.sold or 0) .. GREY .. ", bought |r" .. X.Num(s.ledger.bought or 0) ..
			(s.ledger.sellThrough and (GREY .. ", " .. string.format("%.0f%%", s.ledger.sellThrough * 100) .. " sell|r") or "")) or NONE) or NONE},
		{"Market shape", shape},
		{"Strategies", s.marks and #s.marks > 0 and ("|cffffd100" .. table.concat(s.marks, ", ") .. "|r") or NONE},
		{"Seen", cur and cur.t and (X.Ago(cur.t) .. GREY .. (st.first and ("  (first " .. X.Date(st.first * 86400 + 43200, "%b %d") .. ")") or "") .. "|r") or NONE},
	}
	for i = 1, NUMBERS do
		local r = rows[i]
		panel.numL[i]:SetText(r and (GREY .. r[1] .. "|r") or "")
		panel.numR[i]:SetText(r and r[2] or "")
	end
end

local function fillProfits(panel, s)
	local cut = X.S().cut
	local cur = s.cur
	local list = {}
	local old = s.fresh and "" or " (old prices)"
	if s.flip and cur and (cur.qty or 0) > 0 then
		list[#list + 1] = {s.flip, "Buy the cheapest, sell it again", "Buy one for " .. M(cur.min) .. GREY .. ", list it at " ..
			M(s.price) .. GREY .. ". After the " .. cut .. "% cut you keep " .. M(s.sell) .. GREY .. old .. "."}
	end
	if s.vendorFlip then
		local from = s.vbuyInfo and s.vbuyInfo.from
		list[#list + 1] = {s.vendorFlip, "Buy from a vendor, sell here", "A vendor" .. (from and (" (" .. from .. ")") or "") ..
			" sells it for " .. M(s.vbuy) .. GREY .. "; here it brings " .. M(s.sell) .. GREY .. " after the cut" .. old .. "."}
	end
	if s.belowVendor and s.belowVendor > 0 and cur and (cur.qty or 0) > 0 then
		list[#list + 1] = {s.belowVendor, "Listed under the vendor price", "Listed for " .. M(cur.min) .. GREY ..
			" but any vendor pays " .. M(s.vsell) .. GREY .. ": buy it and sell it to a vendor. No risk" .. old .. "."}
	end
	if s.craftProfit then
		list[#list + 1] = {s.craftProfit, "Craft it and sell it", "The reagents for one cost " .. M(s.craft) .. GREY ..
			" (see Crafting); it brings " .. M(s.sell) .. GREY .. " after the cut" .. old .. "."}
	end
	if s.de and cur and cur.min and (cur.qty or 0) > 0 and s.de > cur.min then
		list[#list + 1] = {s.de - cur.min, "Buy it and disenchant it", "Listed for " .. M(cur.min) .. GREY ..
			"; disenchanting gives materials worth " .. M(s.de) .. GREY .. " on average (needs an enchanter)" .. old .. "."}
	end
	if s.shape and s.shape.reset and (s.shape.reset.profit or 0) > 0 then
		local r = s.shape.reset
		list[#list + 1] = {r.profit / math.max(1, r.units or 1), "Buy the cheap ones, relist", "Buying all " .. X.Num(r.units or 0) ..
			" listed under the usual price costs " .. M(r.cost) .. GREY .. "; sold again at the usual price they bring " ..
			M(r.profit) .. GREY .. " profit in all (if they sell)" .. old .. "."}
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
				slot.head:SetText(GREY .. "Nothing found yet.|r")
				slot.text:SetText(GREY .. "More scans, vendor visits and opened profession windows fill this in.|r")
			end
			slot.head:Show()
			slot.text:Show()
			y = y - 14 - math.max(12, slot.text:GetStringHeight() or 24) - 7
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

local function fillGraph(panel, key)
	for i, b in ipairs(panel.ranges) do b:SetSelected(i == rangeIdx) end
	local range = RANGES[rangeIdx][2]
	local hist = X.History(key, range and (X.Now() - range) or 0)
	local mkt, low, qty = {}, {}, {}
	for i, p in ipairs(hist) do
		mkt[i] = {p[1], p[3]}
		low[i] = {p[1], p[2]}
		qty[i] = {p[1], p[4]}
	end
	local empty
	if #hist == 0 and range and #X.History(key, 0) > 0 then empty = "No prices in this time - pick a longer range" end
	panel.graph:SetSeries({
		{points = mkt, color = {1, 0.82, 0}, width = 2, label = "Market value"},
		{points = low, color = {0.29, 0.87, 0.5}, width = 1.5, label = "Lowest price"},
	}, {bars = qty, barsLabel = "Listed", empty = empty})
end

refresh = function(panel)
	local key = UI.itemKey
	local has = key ~= nil
	panel.body:SetShown(has)
	panel.hint:SetShown(not has)
	panel.icon:SetShown(has)
	panel.name:SetShown(has)
	panel.sub:SetShown(has)
	panel.star:SetShown(has)
	panel.max:SetShown(has)
	panel.shop:SetShown(has and X.ShopAdd ~= nil)
	panel.ah:SetShown(has and X.ahOpen == true)
	if not has then return end

	local s = X.Summary(key)
	if X.SaleRate then s.rate, s.rateHours = X.SaleRate(key) end
	if X.DEValue then s.de = X.DEValue(key) end
	if X.LedgerItem then s.ledger = X.LedgerItem(key) end
	if X.Shape then s.shape = X.Shape(key) end
	if X.StrategyMarks then s.marks = X.StrategyMarks(key) end
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
	panel.star:SetText(X.Watched(key) and "Remove from watch list" or "Add to watch list")
	local wmax = X.WatchMax(key)
	panel.max:SetText(wmax and ("Max " .. X.MoneyPlain(wmax)) or "Max price")
	panel.ah:SetEnabled(X.scan and X.scan.state == "idle")

	fillNumbers(panel, key, s)
	fillGraph(panel, key)
	fillProfits(panel, s)
	fillCrafting(panel, s)
end

UI.AddTab("item", "Item", build, refresh, 2)
