-- Items view, Crafting page: for a recipe that makes the item picked, what crafting one cost on each day (from the day
-- prices of its reagents, CraftHistory.lua) against what one sold for after the auction house cut, and the margin
-- between them. A recipe picker when several recipes make it. Under it: the recipes that USE the item (it is a
-- reagent), each with its margin now; click one to show what it makes.
-- Layout (810 x 532): 4 number tiles; the recipe picker and range buttons at y -54; cost and price graph (y -78, 170
-- high); margin graph (y -254, 110 high); the recipes that use it (title at y -372, table from y -404).
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED = "|cff999999", "|cff4ade80", "|cfff87171"
local NONE = "|cff666666-|r"
local DAY = 86400
local RANGES = {{"30 days", 30}, {"90 days", 90}, {"1 year", 365}}
X.Default("craftRange", 1) -- an index of RANGES

local COST, SELL, MARGIN = {0.97, 0.44, 0.44}, {0.29, 0.87, 0.5}, {1, 0.82, 0}
local picked = {} -- [item key] = the recipe picked for it (this session)

local function signed(v)
	if v == nil then return NONE end
	if v >= 0 then return GREEN .. "+" .. X.MoneyPlain(v) .. "|r" end
	return RED .. "-" .. X.MoneyPlain(-v) .. "|r"
end

local TILES = {
	{"Margin now", "What you keep per item made: its price after the auction house cut, minus what the reagents cost " ..
		"now (each at its cheapest: vendor, auction house or crafting it). The same as on the Overview page."},
	{"Average margin, 30 days", "The margin on an average day of the last 30 days, from each day's prices of the " ..
		"reagents and of the item."},
	{"Best day", "The day of the last 30 with the biggest margin, and how big it was."},
	{"Trend", "Is the margin growing or shrinking? A straight line through the margins of the last 14 days, as gold a week."},
}

local COLUMNS = {
	{"Makes", 250, "LEFT", text = function(r) return UI.ItemCell(r.key, 12) end,
		sort = function(r) return (X.ItemName(r.key) or r.name or ""):lower() end, desc = false},
	{"Recipe", 170, "LEFT", text = function(r) return GREY .. (r.prof or "") .. "|r " .. (r.name or "") end,
		sort = function(r) return (r.prof or "") .. (r.name or "") end, desc = false},
	{"Uses", 44, "RIGHT", text = function(r) return X.Num(r.count) .. "x" end, sort = function(r) return r.count end},
	{"Cost", 96, "RIGHT", text = function(r)
		if (r.missing or 0) > 0 then return RED .. "no price|r" end
		return X.Money(r.cost, true)
	end, sort = function(r) return r.cost end},
	{"Sells for", 96, "RIGHT", text = function(r) return X.Money(r.sell, true) end, sort = function(r) return r.sell end},
	{"Margin", 110, "RIGHT", text = function(r) return signed(r.margin) end, sort = function(r) return r.margin end},
}
local COLUMN_TIPS = {
	"What the recipe makes. Click a row to show that item.",
	"The profession and the recipe's name.",
	"How many of the item picked one craft uses.",
	"What the reagents of one craft cost now, per item made (each reagent at its cheapest). \"no price\": a reagent has " ..
		"no price yet.",
	"What one of the made item brings after the auction house cut.",
	"Sells for minus cost: what you keep per item made. Green: a profit.",
}

local fill -- below

-- the recipes that make the item, and the one shown
local function recipesOf(id)
	local out = {}
	for _, rid in ipairs(X.RecipesFor(id) or {}) do out[#out + 1] = rid end
	return out
end
local function currentRid(key, list)
	local rid = picked[key]
	if rid and X.Contains(list, rid) then return rid end
	local best = X.CraftCost and select(2, X.CraftCost(X.KeyID(key)))
	if best and X.Contains(list, best) then return best end
	return list[1]
end
local function recipeLabel(rid)
	local r = X.Recipe(rid)
	if not r then return "?" end
	return (r.name or X.RecipeTitle(rid)) .. (r.prof and (GREY .. " (" .. r.prof .. ")|r") or "")
end

local function build(page, w, h)
	page.tiles = UI.NumberTiles(page, w, TILES, 0)
	local pick = K.Flat(page, 420, 20)
	pick:SetPoint("TOPLEFT", 0, -52)
	pick:SetScript("OnClick", function(self)
		local key = UI.itemKey
		local list = key and recipesOf(X.KeyID(key)) or {}
		if #list < 2 then return end
		local cur = currentRid(key, list)
		local entries = {{text = "Recipes that make it", isTitle = true}}
		for _, rid in ipairs(list) do
			entries[#entries + 1] = {text = recipeLabel(rid), checked = rid == cur, func = function()
				picked[key] = rid
				fill(page, key)
			end}
		end
		K.Menu(self, entries)
	end)
	pick:SetScript("OnEnter", function(self)
		if self.rid then UI.RecipeTooltip(self, self.rid, self.itemID) end
		if self.many then
			GameTooltip:AddLine("Click to pick another recipe that makes it.", 0.6, 0.6, 0.6, true)
			GameTooltip:Show()
		end
	end)
	pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.pick = pick
	page.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(page, 56, 18)
		b:SetPoint("TOPRIGHT", -(#RANGES - i) * 60, -53)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().craftRange = i fill(page, UI.itemKey) end)
		K.Tooltip(b, r[1], "Shows the last " .. r[1] .. " on the graphs.")
		page.ranges[i] = b
	end
	page.gPrice = K.Graph(page, w, 170)
	page.gPrice:SetPoint("TOPLEFT", 0, -78)
	page.gMargin = K.Graph(page, w, 110)
	page.gMargin:SetPoint("TOPLEFT", 0, -254)
	page.none = K.Label(page, "", "GameFontDisable", "CENTER")
	page.none:SetPoint("TOP", page, "TOPLEFT", w / 2, -160)
	page.none:SetWidth(w - 100)
	page.usedTitle = K.Label(page, "", "GameFontNormalSmall")
	page.usedTitle:SetPoint("TOPLEFT", 0, -372)
	page.usedTitle:SetWidth(w)
	page.usedTitle:SetWordWrap(false)
	local ty = -404
	for i, c in ipairs(COLUMNS) do c.tip = COLUMN_TIPS[i] end -- the hover line of each column title
	page.tbl = K.Table(page, w, h + ty, COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	page.tbl:SetPoint("TOPLEFT", 0, ty)
	page.tbl:SortBy(6, true)
end

local function fillTiles(page, rid)
	local t = page.tiles
	if not rid then
		for i = 1, #t do UI.SetTile(t[i], nil) end
		return
	end
	local m = X.CraftMargin(rid)
	if m.margin then
		UI.SetTile(t[1], signed(m.margin), (m.cost and m.cost > 0) and (string.format("%.0f%%", m.margin / m.cost * 100)) or nil)
	elseif (m.missing or 0) > 0 then
		UI.SetTile(t[1], GREY .. "no price|r", m.missing .. " reagent" .. (m.missing == 1 and "" or "s"))
	else
		UI.SetTile(t[1], GREY .. "not known|r", m.sell == nil and "no sell price" or nil)
	end
	UI.SetTile(t[2], m.avg30 and signed(m.avg30) or (GREY .. "not known yet|r"), m.days30 and m.days30 > 0 and
		(m.days30 .. " day" .. (m.days30 == 1 and "" or "s")) or nil)
	if m.best then
		UI.SetTile(t[3], signed(m.best.margin), X.Date(m.best.day * DAY + DAY / 2, "%b %d"))
	else
		UI.SetTile(t[3], GREY .. "not known yet|r")
	end
	if m.trend then
		UI.SetTile(t[4], m.trendWord, (m.trend >= 0 and "+" or "-") .. X.MoneyPlain(math.abs(m.trend)) .. " a week")
	else
		UI.SetTile(t[4], GREY .. "too new|r", "3 days needed")
	end
end

local function fillGraphs(page, key, rid)
	local ri = RANGES[X.S().craftRange] and X.S().craftRange or 1
	for i, b in ipairs(page.ranges) do b:SetSelected(i == ri) end
	local today = X.Day()
	local list = X.CraftSeries(rid, today - RANGES[ri][2] + 1, today)
	local cost, sell, margin = {}, {}, {}
	for _, p in ipairs(list) do
		cost[#cost + 1] = {p.t, p.cost}
		sell[#sell + 1] = {p.t, p.sell}
		margin[#margin + 1] = {p.t, p.margin}
	end
	local empty = "No prices in this time for the reagents or the item - scan the auction house (or pick a longer range)"
	page.gPrice:SetSeries({
		{points = cost, label = "Crafting cost (one)", color = COST, width = 2},
		{points = sell, label = "Sells for, after the cut", color = SELL, width = 2},
	}, {legend = true, empty = empty})
	local any = false
	for _, p in ipairs(margin) do if p[2] then any = true break end end
	page.gMargin:SetSeries({{points = margin, label = "Margin (what you keep)", color = MARGIN, width = 2}},
		{legend = true, empty = any and nil or "No day with both a crafting cost and a price yet",
		levels = any and {{v = 0, color = {0.6, 0.6, 0.6}, label = "break even"}} or nil})
end

fill = function(page, key)
	if not key then return end
	local id = X.KeyID(key)
	local list = recipesOf(id)
	local rid = currentRid(key, list)
	page.pick.rid, page.pick.itemID, page.pick.many = rid, id, #list > 1
	fillTiles(page, rid)
	if rid then
		page.pick:SetLabel(GREY .. "Recipe:|r " .. recipeLabel(rid) .. (#list > 1 and (GREY .. "  - " .. X.Contains(list, rid) .. " of " .. #list ..
			" recipes, click to pick|r") or ""))
		page.pick:Show()
		page.gPrice:Show()
		page.gMargin:Show()
		page.none:Hide()
		fillGraphs(page, key, rid)
	else
		page.pick:Hide()
		page.gPrice:Hide()
		page.gMargin:Hide()
		page.none:SetText("No recipe makes " .. X.ItemText(key) .. "|cff808080, so there is no crafting margin to show." ..
			"\nRecipes that use it (if any) are listed below.|r")
		page.none:Show()
	end
	local uses = X.ReagentUses(id)
	page.usedTitle:SetText("Recipes that use it: " .. #uses .. GREY .. "  - margins from the prices now. Click one to show " ..
		"what it makes.|r")
	page.tbl:SetRows(uses, "No recipe uses " .. (X.ItemName(key) or "this item") .. ".")
end

UI.AddItemPage("craft", "Crafting", build, function(page, key) fill(page, key) end, 5,
	"Crafting it over time: what the reagents cost each day against what it sold for after the cut, and the margin. " ..
	"Also every recipe that uses it, with its margin now.")
