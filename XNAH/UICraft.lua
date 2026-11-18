-- The Crafting tab: every recipe XNAH has seen, what it costs to make, what it sells for and the profit. Click a recipe
-- for its reagents (and a button that searches them all on the auction house).
-- Two choices are remembered in the settings: craftMine (only recipes your characters know; nil = on when any are
-- known) and craftProf (one profession; nil = all).
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local TOP = 78         -- where the recipe table starts (its column titles sit just above)
local LIST_H = 268     -- recipe table height (14 rows)
local DETAIL_H = H - TOP - LIST_H - 8
local FROM = {vendor = "vendor", ah = "auction house", craft = "crafted"}

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
-- the item made; the recipe name while the game has not loaded the item yet
local function recipeCell(r)
	local name = X.ItemName(r.key)
	if r.name and name:find("^item %-?%d") then return X.ItemIcon(X.KeyID(r.key), 14) .. " " .. r.name end
	return UI.ItemCell(r.key)
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

local function emptyText()
	if next(X.db.recipes) == nil then
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
	local r = rid and X.db.recipes[rid]
	if not r then
		d.title:SetText("|cff999999Click a recipe above to see what goes into it.|r")
		d.summary:SetText("")
		d.shop:SetEnabled(false)
		d.open:SetEnabled(false)
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
end

-- [[ the tab ]]
local function refresh(p)
	p.mine:SetChecked(mineOn())
	p.prof:SetText(X.S().craftProf or "All professions")
	local list = rows()
	p.list:SetRows(list, emptyText())
	p.count:SetText(X.Num(#list) .. (#list == 1 and " recipe" or " recipes"))
	showDetail(p)
end

local function build(p)
	p.mine = K.Check(p, "Only recipes my characters know", function(on)
		X.S().craftMine = on
		dirty = true
		refresh(p)
	end)
	p.mine:SetPoint("TOPLEFT", 0, 0)
	local pl = K.Label(p, "Profession:")
	pl:SetPoint("TOPLEFT", 280, -5)
	p.prof = K.Button(p, "All professions", 170, 22, function(self)
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
	end)
	p.prof:SetPoint("TOPLEFT", 345, 0)
	p.count = K.Label(p, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, -5)
	p.count:SetWidth(150)

	local help = K.Label(p, "Cost to make = the reagents bought the cheapest way (vendor, auction house or crafted). " ..
		"Profit = the sale after the cut, minus that cost.", "GameFontHighlight")
	help:SetPoint("TOPLEFT", 0, -28)
	help:SetWidth(W)
	help:SetWordWrap(false)
	local help2 = K.Label(p, "|cff999999Recipes are learned when you open a profession window (yours or a linked one).  " ..
		"Grey ? = a reagent has no price yet (cost too low).  Right click: menu.|r")
	help2:SetPoint("TOPLEFT", 0, -46)
	help2:SetWidth(W)
	help2:SetWordWrap(false)

	p.list = K.Table(p, W, LIST_H, COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then
			UI.ItemMenu(rowFrame, row.key)
		else
			p.rid = row.rid
			p.list:Refresh()
			showDetail(p)
		end
	end)
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
	local d = K.Panel(p, W, DETAIL_H, {0, 0, 0, 0.25})
	d:SetPoint("TOPLEFT", 0, -(TOP + LIST_H + 8))
	p.detail = d
	d.title = K.Label(d, "", "GameFontHighlight")
	d.title:SetPoint("TOPLEFT", 10, -9)
	d.title:SetWidth(W - 280)
	d.title:SetWordWrap(false)
	d.summary = K.Label(d, "")
	d.summary:SetPoint("TOPLEFT", 10, -28)
	d.summary:SetWidth(W - 20)
	d.summary:SetWordWrap(false)
	d.open = K.Button(d, "Open item", 100, 22, function() if d.key then UI.ShowItem(d.key) end end)
	d.open:SetPoint("TOPRIGHT", -8, -6)
	d.shop = K.Button(d, "Shopping list", 130, 22, function()
		local keys = {}
		for _, part in ipairs(d.partKeys or {}) do keys[#keys + 1] = part.key end
		if #keys > 0 then X.ScanItems(keys, "reagents") end
	end)
	d.shop:SetPoint("RIGHT", d.open, "LEFT", -6, 0)
	K.Tooltip(d.shop, "Shopping list", "Searches every reagent of this recipe on the auction house for its live price " ..
		"(the auction house must be open).")
	d.parts = K.Table(d, W - 16, DETAIL_H - 64, PART_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	d.parts:SetPoint("TOPLEFT", 8, -58)
end

UI.AddTab("craft", "Crafting", build, refresh, 4)
