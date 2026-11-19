-- Quick search: get to an item's page from anywhere.
--   * Alt-click an item in your bags, a link in chat or a loot window: its XNAH item page opens (setting quickAltClick).
--     The game sends every modified click on an item through HandleModifiedItemClick(link); XNAH only listens to it
--     (hooksecurefunc - the game's own behaviour stays as it is).
--   * The search box in the window's title bar: items by name (also ones never seen on the auction house) and recipes
--     by name; picking a recipe opens what it makes.
local ADDON, X = ...
local K, UI = X.K, X.UI

X.Default("quickAltClick", true)

-- [[ alt-click ]]
local function keyFromLink(link)
	if type(link) ~= "string" then return nil end
	if X.KeyFromLink then
		local key = X.KeyFromLink(link)
		if key then return key end
	end
	local id = link:match("item:(%d+)")
	return id
end
X.QuickKeyFromLink = keyFromLink
local function onModifiedClick(link)
	if not X.S().quickAltClick then return end
	if not (IsAltKeyDown and IsAltKeyDown()) then return end
	if (IsShiftKeyDown and IsShiftKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then return end
	local key = keyFromLink(link)
	if key and X.ShowItem then X.ShowItem(key) end
end
X.QuickModifiedClick = onModifiedClick
if hooksecurefunc and HandleModifiedItemClick then
	hooksecurefunc("HandleModifiedItemClick", function(link) X.Try(onModifiedClick, link) end)
end

-- [[ search: items and recipes by name ]] -> {{key = itemKey, text = shown text, rid = recipe or nil}, ...}
function X.QuickFind(text, limit)
	text = X.Trim(text or ""):lower()
	limit = limit or 15
	if #text < 2 then return {} end
	local out, seen = {}, {}
	local items = X.Items()
	-- items XNAH has prices for: exact name, then names starting with the text, then the rest (shortest first)
	local hits = X.Find(text, 300)
	local function rank(name)
		if name == text then return 0 end
		if name:sub(1, #text) == text then return 1 end
		return 2
	end
	local ranked = {}
	for _, key in ipairs(hits) do
		local name = ((items[key] and items[key].n) or ""):lower()
		ranked[#ranked + 1] = {key = key, r = rank(name), name = name}
	end
	-- items only the recipe list knows (never seen on the auction house)
	for id, s in pairs(X.RECIPE_ITEMS or {}) do
		local name = (s:match("^%d+;(.+)$") or ""):lower()
		local key = tostring(id)
		if not items[key] and name:find(text, 1, true) then ranked[#ranked + 1] = {key = key, r = rank(name), name = name} end
	end
	table.sort(ranked, function(a, b)
		if a.r ~= b.r then return a.r < b.r end
		if #a.name ~= #b.name then return #a.name < #b.name end
		return a.name < b.name
	end)
	for _, e in ipairs(ranked) do
		if #out >= limit then break end
		if not seen[e.key] then
			seen[e.key] = true
			out[#out + 1] = {key = e.key, text = UI.ItemCell(e.key)}
		end
	end
	-- recipes whose name has the text (not already there through the item they make)
	local recipes = {}
	for rid, s in pairs(X.RECIPE_DB or {}) do
		local name = s:match(";([^;]*)$")
		if name and name:lower():find(text, 1, true) then recipes[#recipes + 1] = {rid = rid, name = name} end
	end
	table.sort(recipes, function(a, b) return a.name < b.name end)
	for _, r in ipairs(recipes) do
		if #out >= limit + 5 then break end
		local rec = X.Recipe(r.rid)
		local okey = rec and rec.out and tostring(rec.out)
		if not (okey and seen[okey]) then
			if okey then seen[okey] = true end
			out[#out + 1] = {key = okey, rid = r.rid, text = "|cffffd100Recipe:|r " .. r.name .. (rec and rec.prof and (" |cff999999(" .. rec.prof .. ")|r") or "")}
		end
	end
	return out
end

-- the box in the title bar (UI.lua calls this when it builds the window)
function UI.QuickSearchBox(parent)
	local box = K.Edit(parent, 170, function(text)
		local hits = X.QuickFind(text, 1)
		K.CloseMenu()
		if hits[1] and hits[1].key then
			UI.QuickBox:SetText("")
			UI.QuickBox:ClearFocus()
			UI.ShowItem(hits[1].key)
		end
	end)
	UI.QuickBox = box
	box:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-quick-find", 0.25, function()
			local text = self:GetText() or ""
			if not self:HasFocus() or #X.Trim(text) < 2 then K.CloseMenu() return end
			local entries = {}
			for _, h in ipairs(X.QuickFind(text, 15)) do
				entries[#entries + 1] = {text = h.text, disabled = h.key == nil, func = function()
					self:SetText("")
					self:ClearFocus()
					if h.key then UI.ShowItem(h.key) end
				end}
			end
			if #entries == 0 then entries[1] = {text = "Nothing found", disabled = true} end
			K.Menu(self, entries)
		end)
	end)
	K.Tooltip(box, "Find", "Type an item or recipe name and pick it. Alt-click an item in your bags, chat or loot to open " ..
		"its page from anywhere.")
	return box
end
