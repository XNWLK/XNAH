-- The Crafting tab: every recipe XNAH has seen, what it costs to make, what it sells for and the profit. Click a recipe
-- for its reagents (and a button that searches them all on the auction house, and one that puts it in the queue).
-- The second view, "Queue": the crafting queue (Queue.lua) - targets, crafts to do, profit, the materials to buy and a
-- "Craft next" button for the open profession window.
-- The third view, "Make ideas": crafting for profit, recipes worth learning, cooldowns, what to gather (UI.IdeasView in
-- UIDeals.lua; until v0.7 on the Deals tab).
-- Choices remembered in the settings: craftMine (only recipes your characters know; nil = on when any are known),
-- craftProf (one profession; nil = all), craftView ("recipes" / "queue" / "make").
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 78         -- where the recipe table starts (its column titles sit just above)
local LIST_H = 268     -- recipe table height (14 rows)
local DETAIL_H = H - TOP - LIST_H - 8
local FROM = {vendor = "vendor", ah = "auction house", craft = "crafted"}
local MODE = {restock = "Restock", craft = "Craft"}

X.Default("craftView", "recipes")

local function anyKnown()
	for _, list in pairs(X.db.known or {}) do
		if next(list) then return true end
	end
	return false
end
local function mineOn()
	local v = X.S().craftMine
	if v == nil then return anyKnown() end
	return v
end

-- the list is worked out again only when prices or recipes changed (or a minute passed: prices get old)
local data, dirty, madeAt
local function markDirty() dirty = true end
X.On("XNAH_PRICES", markDirty)
X.On("XNAH_RECIPES", markDirty)
local function rows()
	if dirty or not data or (GetTime() - (madeAt or 0)) > 60 then
		data = X.CraftList({mine = mineOn(), prof = X.S().craftProf})
		dirty, madeAt = false, GetTime()
	end
	return data
end

-- [[ cells ]]
local function field(name) return function(r) return r[name] end end
-- the item made; the recipe name while the game has not loaded the item yet; a green Q when it is in the queue
local function recipeCell(r)
	local q = X.QueueGet and X.QueueGet(r.rid) and "|cff4ade80Q|r " or ""
	local name = X.ItemName(r.key)
	if r.name and name:find("^item %-?%d") then return q .. X.ItemIcon(X.KeyID(r.key), 14) .. " " .. r.name end
	return q .. UI.ItemCell(r.key)
end
local function knownText(r) return table.concat(r.known or {}, ", ") end
local function costCell(r)
	local text = UI.MoneyCell(r.cost)
	if (r.missing or 0) > 0 then text = text .. " |cff888888?|r" end
	return text
end

local COLUMNS = {
	{"Recipe", 280, "LEFT", text = recipeCell, sort = function(r) return (X.ItemName(r.key)) end, desc = false},
	{"Profession", 105, "LEFT", text = function(r) return r.prof or "|cff666666?|r" end, sort = function(r) return r.prof or "" end, desc = false},
	{"Cost to make", 110, "RIGHT", text = costCell, sort = field("cost"), desc = false},
	{"Sells for (after cut)", 125, "RIGHT", text = function(r) return UI.MoneyCell(r.sell, r.stale) end, sort = field("sell")},
	{"Profit", 105, "RIGHT", text = function(r) return UI.MoneyCell(r.profit, r.stale) end, sort = field("profit")},
	{"Margin %", 65, "RIGHT", text = function(r) return X.Pct(r.pct) end, sort = field("pct")},
	{"Listed", 50, "RIGHT", text = function(r) return r.qty and X.Num(r.qty) or "-" end, sort = field("qty")},
	{"Known by", 90, "LEFT", text = knownText, sort = knownText, desc = false},
}
local PART_COLUMNS = {
	{"Reagent", 360, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return (X.ItemName(r.key)) end, desc = false},
	{"Count", 80, "RIGHT", text = function(r) return X.Num(r.count) end, sort = field("count")},
	{"Each", 140, "RIGHT", text = function(r) return UI.MoneyCell(r.unit) end, sort = field("unit")},
	{"From", 150, "LEFT", text = function(r) return r.how and ("    " .. FROM[r.how]) or "    |cff888888no price yet|r" end,
		sort = function(r) return r.how or "" end, desc = false},
	{"Total", 140, "RIGHT", text = function(r) return UI.MoneyCell(r.total) end, sort = field("total")},
}

-- the queue's columns; the last one holds the - / + / x buttons of each row
local QUEUE_COLUMNS = {
	{"Recipe", 300, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return (X.ItemName(r.key)) end, desc = false},
	{"Mode", 90, "LEFT", text = function(r) return MODE[r.mode] or "?" end, sort = field("mode"), desc = false},
	{"Target", 70, "RIGHT", text = function(r) return X.Num(r.target) .. (r.mode == "craft" and "x" or "") end, sort = field("target")},
	{"Have", 70, "RIGHT", text = function(r) return X.Num(r.have) end, sort = field("have")},
	{"To craft", 70, "RIGHT", text = function(r)
		return r.craft > 0 and X.Num(r.craft) or "|cff4ade80done|r" end, sort = field("craft")},
	{"Profit", 140, "RIGHT", text = function(r)
		if r.profit == nil then return "|cff888888?|r" end
		return X.Money(r.profit, true) end, sort = field("profit")},
	{"", 150, "LEFT", text = function() return "" end},
}
local MAT_COLUMNS = {
	{"Reagent", 300, "LEFT", text = function(m) return UI.ItemCell(m.key) end, sort = function(m) return (X.ItemName(m.key)) end, desc = false},
	{"Needed", 70, "RIGHT", text = function(m) return X.Num(m.need) end, sort = field("need")},
	{"You own", 70, "RIGHT", text = function(m) return X.Num(m.have) end, sort = field("have")},
	{"To buy", 70, "RIGHT", text = function(m) return m.buy > 0 and ("|cffffd100" .. X.Num(m.buy) .. "|r") or "|cff4ade800|r" end, sort = field("buy")},
	{"Each", 120, "RIGHT", text = function(m) return UI.MoneyCell(m.unit) end, sort = field("unit")},
	{"From", 170, "LEFT", text = function(m)
		if m.how == "vendor" then return "    vendor: " .. (m.vendor or "?") end
		return m.how and ("    " .. FROM[m.how]) or "    |cff888888no price yet|r" end, sort = function(m) return m.how or "" end, desc = false},
	{"Cost", 130, "RIGHT", text = function(m) return m.buy > 0 and UI.MoneyCell(m.total) or "-" end, sort = field("total")},
}

local function emptyText()
	if next(X.db.recipes) == nil and not X.RECIPE_DB then
		return "No recipes yet. Open a profession window (yours, or a recipe list someone linked in chat): XNAH reads " ..
			"every recipe in it."
	end
	if mineOn() and not anyKnown() then
		return "No recipes of your characters are known yet: open your profession windows on each character, or untick " ..
			"\"Only recipes my characters know\"."
	end
	return "No recipes for this choice."
end

-- [[ the breakdown of one recipe ]]
local function showDetail(p)
	local d = p.detail
	local rid = p.rid
	local r = rid and X.Recipe(rid)
	if not r then
		d.title:SetText("|cff999999Click a recipe above to see what goes into it.|r")
		d.summary:SetText("")
		d.shop:SetEnabled(false)
		d.open:SetEnabled(false)
		d.add:SetEnabled(false)
		d.parts:SetRows({}, "")
		return
	end
	local key = r.out and tostring(r.out)
	local cost, missing = X.RecipeCost(rid)
	local sell = key and X.AfterCut(X.Price(key))
	local n = r.n or 1
	d.title:SetText((key and UI.ItemCell(key) or (r.name or "?")) .. "  |cff999999" .. (r.prof or "") ..
		(n ~= 1 and ("  -  one craft makes " .. (n == math.floor(n) and string.format("%d", n) or string.format("%.1f", n))) or "") .. "|r")
	local line = "Cost to make one: " .. UI.MoneyCell(cost) .. ((missing or 0) > 0 and " |cff888888(?)|r" or "") ..
		"     Sells for (after cut): " .. UI.MoneyCell(sell)
	if cost and sell then
		line = line .. "     Profit: " .. X.Money(sell - cost, true)
	end
	if (missing or 0) > 0 then
		line = line .. "     |cff888888" .. missing .. " reagent" .. (missing == 1 and "" or "s") .. " without a price: the cost is too low|r"
	end
	d.summary:SetText(line)
	local parts = {}
	for _, part in ipairs(X.RecipeParts(rid)) do
		parts[#parts + 1] = {key = tostring(part.id), id = part.id, count = part.count, unit = part.unit, how = part.how, total = part.total}
	end
	d.parts:SetRows(parts, "This recipe has no reagents XNAH knows.")
	d.shop:SetEnabled(X.ahOpen == true and X.scan.state == "idle" and #parts > 0)
	d.open:SetEnabled(key ~= nil)
	d.key = key
	d.partKeys = parts
	-- the queue controls show this recipe's target when it is queued
	if d.shownRid ~= rid then
		d.shownRid = rid
		local q = X.QueueGet(rid)
		d.mode = q and q.mode or "restock"
		if not d.number:HasFocus() then d.number:SetText(tostring(q and q.n or 5)) end
	end
	d.modeButton:SetText(d.mode == "craft" and "Craft x times" or "Restock: keep")
	d.add:SetEnabled(key ~= nil)
	d.add:SetText(X.QueueGet(rid) and "Update queue" or "Add to queue")
end

-- [[ the queue view ]]
local function vendorText(totals)
	local names = {}
	for name in pairs(totals.vendor) do names[#names + 1] = name end
	table.sort(names)
	if #names == 0 then return "|cff999999Nothing to buy from vendors.|r" end
	local parts = {}
	for _, name in ipairs(names) do
		local list = {}
		for _, m in ipairs(totals.vendor[name]) do
			list[#list + 1] = X.ItemText(m.key) .. " x" .. X.Num(m.buy) .. " (" .. X.Money(m.total, true) .. ")"
		end
		parts[#parts + 1] = "|cffffd100" .. name .. ":|r " .. table.concat(list, ", ")
	end
	return "Buy these from vendors:  " .. table.concat(parts, "   ")
end

local function refreshQueue(p)
	local q = p.queue
	local list = X.QueueRows()
	q.list:SetRows(list, "The queue is empty. Click a recipe in the Recipes view, then \"Add to queue\".")
	local crafts, profit, anyProfit = 0, 0, false
	for _, r in ipairs(list) do
		crafts = crafts + r.craft
		if r.profit then profit = profit + r.profit anyProfit = true end
	end
	local mats, totals = X.QueueMaterials(list)
	q.mats:SetRows(mats, #list > 0 and "Nothing to craft right now: every target is reached." or "")
	q.summary:SetText(X.Num(#list) .. (#list == 1 and " recipe" or " recipes") .. " in the queue   -   " .. X.Num(crafts) ..
		(crafts == 1 and " craft" or " crafts") .. " to do   -   total profit " .. (anyProfit and X.Money(profit, true) or "|cff888888?|r") ..
		"   -   materials to buy " .. X.Money(totals.cost, true) .. (totals.missing > 0 and " |cff888888(+ some without a price)|r" or ""))
	q.vendors:SetText(vendorText(totals))
	q.shop:SetShown(X.ShopAdd ~= nil)
	q.shop:SetEnabled(#mats > 0)
	-- the chosen row
	local sel
	for _, r in ipairs(list) do if r.rid == q.rid then sel = r end end
	if not sel then q.rid = nil end
	q.sel:SetText(sel and ("|cff999999Change:|r " .. UI.ItemCell(sel.key)) or "|cff999999Click a row to change its mode or number.|r")
	q.mode:SetEnabled(sel ~= nil)
	q.set:SetEnabled(sel ~= nil)
	q.remove:SetEnabled(sel ~= nil)
	if sel then
		q.mode:SetText(MODE[sel.mode])
		if not q.number:HasFocus() and q.numberFor ~= sel.rid then q.number:SetText(tostring(sel.target)) q.numberFor = sel.rid end
	else
		q.mode:SetText("Mode")
		q.numberFor = nil
	end
	if X.DoNext then
		local key = GetBindingKey and GetBindingKey("XNAH_NEXT")
		q.nextLine:SetText("|cffffd100Tip:|r |cffbbbbbbyour Next step key" .. (key and (" (|cffffd100" .. key .. "|r|cffbbbbbb)") or "") ..
			" does this queue too, one step per press: it buys the materials on the auction house, then crafts at the " ..
			"profession window.|r")
	else
		q.nextLine:SetText("")
	end
	-- craft next
	local row, count = X.CraftNextTarget()
	q.craft:SetEnabled(row ~= nil)
	if row then
		q.craft:SetText("Craft next  (x" .. count .. ")")
		q.craftText:SetText("Next: " .. UI.ItemCell(row.key) .. " x" .. count .. "  |cff999999- one click starts the crafts at the profession window.|r")
	else
		q.craft:SetText("Craft next")
		q.craftText:SetText("|cff999999" .. tostring(count) .. "|r")
	end
end

local function buildQueue(p)
	local q = CreateFrame("Frame", nil, p)
	q:SetPoint("TOPLEFT", 0, -28)
	q:SetSize(W, H - 28)
	p.queue = q
	local QH = H - 28
	q.summary = K.Label(q, "", "GameFontHighlight")
	q.summary:SetPoint("TOPLEFT", 0, 0)
	q.summary:SetWidth(W)
	q.summary:SetWordWrap(false)
	local help = K.Label(q, "|cff999999Restock = keep this many (bags, bank, mail, auction house, your other characters).  " ..
		"Craft = craft it this many times.  - / + change the number (Shift: by 10), x takes it out.|r")
	help:SetPoint("TOPLEFT", 0, -18)
	help:SetWidth(W)
	help:SetWordWrap(false)

	local function change(row, delta)
		if not row then return end
		X.QueueSet(row.rid, row.mode, math.max(1, row.target + delta))
	end
	q.list = K.Table(q, W, 8 * 18 + 4, QUEUE_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then
			UI.ItemMenu(rowFrame, row.key)
		else
			q.rid = row.rid
			q.numberFor = nil
			refreshQueue(p)
		end
	end)
	q.list:SetPoint("TOPLEFT", 0, -54)
	local x = 4
	for i = 1, #QUEUE_COLUMNS - 1 do x = x + QUEUE_COLUMNS[i][2] end
	for _, rowFrame in ipairs(q.list.rows) do
		local minus = K.Button(rowFrame, "-", 24, 16, function() change(rowFrame.qrow, IsShiftKeyDown() and -10 or -1) end)
		minus:SetPoint("LEFT", x + 4, 0)
		local plus = K.Button(rowFrame, "+", 24, 16, function() change(rowFrame.qrow, IsShiftKeyDown() and 10 or 1) end)
		plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
		local del = K.Button(rowFrame, "x", 24, 16, function() if rowFrame.qrow then X.QueueSet(rowFrame.qrow.rid, nil, 0) end end)
		del:SetPoint("LEFT", plus, "RIGHT", 8, 0)
		K.Tooltip(del, "Take out of the queue")
	end
	local baseRefresh = q.list.Refresh
	function q.list:Refresh()
		baseRefresh(self)
		for i, rowFrame in ipairs(self.rows) do
			local row = self.items[i + self.offset]
			rowFrame.qrow = row
			if row and q.rid and row.rid == q.rid then rowFrame:SetSelected(true) end
		end
	end

	-- the chosen row: mode, number, remove; and the craft button
	q.sel = K.Label(q, "")
	q.sel:SetPoint("TOPLEFT", 0, -214)
	q.sel:SetWidth(300)
	q.sel:SetWordWrap(false)
	q.mode = K.Button(q, "Mode", 90, 22, function()
		local row
		for _, r in ipairs(X.QueueRows()) do if r.rid == q.rid then row = r end end
		if row then X.QueueSet(row.rid, row.mode == "craft" and "restock" or "craft", row.target) end
	end)
	q.mode:SetPoint("TOPLEFT", 306, -208)
	K.Tooltip(q.mode, "Mode", "Restock: keep this many (crafts only what is missing).\nCraft: craft it this many times.")
	q.number = K.Edit(q, 50)
	q.number:SetPoint("TOPLEFT", 408, -209)
	q.set = K.Button(q, "Set", 56, 22, function()
		local n = tonumber(X.Trim(q.number:GetText()))
		local row
		for _, r in ipairs(X.QueueRows()) do if r.rid == q.rid then row = r end end
		if row and n then X.QueueSet(row.rid, row.mode, n) end
		q.numberFor = nil
		q.number:ClearFocus()
	end)
	q.set:SetPoint("TOPLEFT", 466, -208)
	q.number:SetScript("OnEnterPressed", function() q.set:Click() end)
	q.remove = K.Button(q, "Remove", 80, 22, function() if q.rid then X.QueueSet(q.rid, nil, 0) end end)
	q.remove:SetPoint("TOPLEFT", 528, -208)
	q.craft = K.Button(q, "Craft next", 200, 22, function()
		X.CraftNext() -- the game allows crafting only from a click: this is that click
		refreshQueue(p)
	end)
	q.craft:SetPoint("TOPRIGHT", 0, -208)
	K.Tooltip(q.craft, "Craft next", "Open your profession window; one click starts the next queued recipe you can make now " ..
		"(as many as your bags allow, at most the number still to craft).")
	q.craftText = K.Label(q, "")
	q.craftText:SetPoint("TOPLEFT", 0, -236)
	q.craftText:SetWidth(W)
	q.craftText:SetWordWrap(false)

	-- materials
	local mt = K.Label(q, "Materials for the queue  |cff999999(what you own is taken off)|r", "GameFontNormal")
	mt:SetPoint("TOPLEFT", 0, -258)
	q.shop = K.Button(q, "Send to shopping list", 170, 22, function()
		local n = X.QueueToShop()
		if n then X.Print(n .. " reagent" .. (n == 1 and "" or "s") .. " put on the shopping list \"" .. X.QUEUE_LIST .. "\" (at most 120% of the current price)") end
	end)
	q.shop:SetPoint("TOPRIGHT", 0, -254)
	K.Tooltip(q.shop, "Send to shopping list", "Puts every reagent still to buy (not the vendor ones) on the shopping list \"" ..
		X.QUEUE_LIST .. "\", with a highest price of 120% of its current price.")
	local matsH = QH - 290 - 58
	q.mats = K.Table(q, W, matsH, MAT_COLUMNS, function(m, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, m.key) else UI.ShowItem(m.key) end
	end)
	q.mats:SetPoint("TOPLEFT", 0, -290)
	q.vendors = K.Label(q, "")
	q.vendors:SetPoint("TOPLEFT", 0, -(290 + matsH + 6))
	q.vendors:SetWidth(W)
	q.vendors:SetWordWrap(true)
	-- the Next step key (Next.lua) does this queue too: buys the materials, then crafts
	q.nextLine = K.Label(q, "")
	q.nextLine:SetPoint("BOTTOMLEFT", 0, 2)
	q.nextLine:SetWidth(W)
	q.nextLine:SetWordWrap(false)
	q:Hide()
end

-- [[ the tab ]]
local VIEW_OK = {recipes = true, queue = true, make = true}
local function setView(p, view)
	if not VIEW_OK[view] then view = "recipes" end
	X.S().craftView = view
	p.shownView = view
	for _, f in ipairs(p.recipeParts) do f:SetShown(view == "recipes") end
	p.queue:SetShown(view == "queue")
	p.make:SetShown(view == "make")
	p.viewRecipes:SetSelected(view == "recipes")
	p.viewQueue:SetSelected(view == "queue")
	p.viewMake:SetSelected(view == "make")
end

local function refresh(p)
	local view = X.S().craftView
	if not VIEW_OK[view] then view = "recipes" end
	if p.shownView ~= view then setView(p, view) end
	p.viewQueue:SetLabel("Queue (" .. X.QueueCount() .. ")")
	if view == "queue" then
		refreshQueue(p)
		return
	elseif view == "make" then
		if p.make.Refresh then p.make:Refresh() end
		return
	end
	p.mine:SetChecked(mineOn())
	p.prof:SetText(X.S().craftProf or "All professions")
	local list = rows()
	p.list:SetRows(list, emptyText())
	p.count:SetText(X.Num(#list) .. (#list == 1 and " recipe" or " recipes"))
	showDetail(p)
end

local function build(p)
	p.recipeParts = {}
	local function part(f) p.recipeParts[#p.recipeParts + 1] = f return f end
	p.mine = part(K.Check(p, "Only recipes my characters know", function(on)
		X.S().craftMine = on
		dirty = true
		refresh(p)
	end))
	p.mine:SetPoint("TOPLEFT", 0, 0)
	local pl = part(K.Label(p, "Profession:"))
	pl:SetPoint("TOPLEFT", 280, -5)
	p.prof = part(K.Button(p, "All professions", 170, 22, function(self)
		local items = {{text = "All professions", checked = X.S().craftProf == nil, func = function()
			X.S().craftProf = nil
			dirty = true
			refresh(p)
		end}}
		for _, name in ipairs(X.Professions()) do
			items[#items + 1] = {text = name, checked = X.S().craftProf == name, func = function()
				X.S().craftProf = name
				dirty = true
				refresh(p)
			end}
		end
		K.Menu(self, items)
	end))
	p.prof:SetPoint("TOPLEFT", 345, 0)
	-- the three views
	p.viewRecipes = K.Flat(p, 90, 22)
	p.viewRecipes:SetPoint("TOPLEFT", 530, 0)
	p.viewRecipes:SetLabel("Recipes")
	p.viewRecipes.label:SetJustifyH("CENTER")
	p.viewRecipes:SetScript("OnClick", function() setView(p, "recipes") refresh(p) end)
	p.viewQueue = K.Flat(p, 100, 22)
	p.viewQueue:SetPoint("TOPLEFT", 624, 0)
	p.viewQueue:SetLabel("Queue")
	p.viewQueue.label:SetJustifyH("CENTER")
	p.viewQueue:SetScript("OnClick", function() setView(p, "queue") refresh(p) end)
	K.Tooltip(p.viewQueue, "Crafting queue", "What to craft: restock targets, crafts to do, the profit, the materials to buy, " ..
		"and a Craft next button.")
	p.viewMake = K.Flat(p, 100, 22)
	p.viewMake:SetPoint("TOPLEFT", 728, 0)
	p.viewMake:SetLabel("Make ideas")
	p.viewMake.label:SetJustifyH("CENTER")
	p.viewMake:SetScript("OnClick", function() setView(p, "make") refresh(p) end)
	K.Tooltip(p.viewMake, "Make ideas", "Crafting for profit, recipes worth learning, cooldown crafts and what to gather.")
	p.count = part(K.Label(p, "", "GameFontDisableSmall", "RIGHT"))
	p.count:SetPoint("TOPRIGHT", 0, -5)
	p.count:SetWidth(100)

	local help = part(K.Label(p, "Cost to make = the reagents bought the cheapest way (vendor, auction house or crafted). " ..
		"Profit = the sale after the cut, minus that cost.", "GameFontHighlight"))
	help:SetPoint("TOPLEFT", 0, -28)
	help:SetWidth(W)
	help:SetWordWrap(false)
	local help2 = part(K.Label(p, "|cff999999Every recipe of the game; open your profession windows so XNAH knows yours.  " ..
		"Grey ? = a reagent has no price yet (cost too low).  Green Q = in the queue.  Right click: menu.|r"))
	help2:SetPoint("TOPLEFT", 0, -46)
	help2:SetWidth(W)
	help2:SetWordWrap(false)

	p.list = part(K.Table(p, W, LIST_H, COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then
			UI.ItemMenu(rowFrame, row.key)
		else
			p.rid = row.rid
			p.list:Refresh()
			showDetail(p)
		end
	end))
	p.list:SetPoint("TOPLEFT", 0, -TOP)
	-- the chosen recipe stays marked
	local baseRefresh = p.list.Refresh
	function p.list:Refresh()
		baseRefresh(self)
		for i, rowFrame in ipairs(self.rows) do
			local row = self.items[i + self.offset]
			if row and p.rid and row.rid == p.rid then rowFrame:SetSelected(true) end
		end
	end

	-- the breakdown under the list
	local d = part(K.Panel(p, W, DETAIL_H, {0, 0, 0, 0.25}))
	d:SetPoint("TOPLEFT", 0, -(TOP + LIST_H + 8))
	p.detail = d
	d.title = K.Label(d, "", "GameFontHighlight")
	d.title:SetPoint("TOPLEFT", 10, -9)
	d.title:SetWidth(W - 540)
	d.title:SetWordWrap(false)
	d.summary = K.Label(d, "")
	d.summary:SetPoint("TOPLEFT", 10, -32)
	d.summary:SetWidth(W - 20)
	d.summary:SetWordWrap(false)
	d.open = K.Button(d, "Open item", 100, 22, function() if d.key then UI.ShowItem(d.key) end end)
	d.open:SetPoint("TOPRIGHT", -8, -6)
	d.shop = K.Button(d, "Search reagents", 130, 22, function()
		local keys = {}
		for _, pt in ipairs(d.partKeys or {}) do keys[#keys + 1] = pt.key end
		if #keys > 0 then X.ScanItems(keys, "reagents") end
	end)
	d.shop:SetPoint("RIGHT", d.open, "LEFT", -6, 0)
	K.Tooltip(d.shop, "Search reagents", "Searches every reagent of this recipe on the auction house for its live price " ..
		"(the auction house must be open).")
	-- the queue: mode, number, add
	d.add = K.Button(d, "Add to queue", 104, 22, function()
		local n = tonumber(X.Trim(d.number:GetText()))
		if p.rid and n then
			X.QueueSet(p.rid, d.mode, n)
			d.number:ClearFocus()
		end
	end)
	d.add:SetPoint("RIGHT", d.shop, "LEFT", -12, 0)
	K.Tooltip(d.add, "Add to queue", "Puts this recipe in the crafting queue (the Queue view at the top) with the mode and " ..
		"number on the left. Already queued: changes them.")
	d.number = K.Edit(d, 44)
	d.number:SetPoint("RIGHT", d.add, "LEFT", -6, 0)
	d.number:SetScript("OnEnterPressed", function() d.add:Click() end)
	d.modeButton = K.Button(d, "Restock: keep", 104, 22, function()
		d.mode = d.mode == "craft" and "restock" or "craft"
		showDetail(p)
	end)
	d.modeButton:SetPoint("RIGHT", d.number, "LEFT", -8, 0)
	K.Tooltip(d.modeButton, "Queue mode", "Restock: keep this many of the item (in bags, bank, mail, on the auction house " ..
		"and on your other characters); only what is missing gets crafted.\nCraft: craft it this many times.")
	d.mode = "restock"
	d.parts = K.Table(d, W - 16, DETAIL_H - 68, PART_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	d.parts:SetPoint("TOPLEFT", 8, -62)

	buildQueue(p)
	-- Make ideas (UIDeals.lua)
	p.make = UI.IdeasView and UI.IdeasView(p, W, H - 28, "make") or CreateFrame("Frame", nil, p)
	p.make:SetPoint("TOPLEFT", 0, -28)
	p.make:Hide()
	setView(p, X.S().craftView)
end

UI.AddTab("craft", "Crafting", build, refresh, 5)

-- the queue changed (or bags, or the profession window): the tab follows while it is shown
X.On("XNAH_QUEUE", function()
	local tab = UI.tabs.craft
	if tab and tab.panel and tab.panel:IsShown() then UI.Refresh() end
end)
