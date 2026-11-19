-- Crafting: every recipe is read when you open a profession window (yours, or one someone linked), so XNAH knows
-- what goes into what. A crafting cost = the reagents at the cheapest way to get them (a vendor, the auction house, or
-- crafting the reagent itself), divided by how many one craft makes.
--   XNAHDB.recipes[recipeID] = {name, out = itemID or nil (enchants make no item), n = how many one craft makes,
--     r = {{itemID, count}, ...}, prof = "Alchemy", at = t}
--   XNAHDB.known[character] = {[recipeID] = true}  recipes your characters know
-- Besides those, RecipeDB.lua lists every recipe of the game: X.Recipe(rid) gives either kind in the same
-- shape (list ones carry db = true, la = skill needed, colors). Crafting costs, the crafting list and "used in" use
-- both (Xn, 2026-11-19: "use all recipes"); "Only recipes my characters know" narrows the lists to known ones, and the
-- posting floor uses recipes read in the game only (X.CraftCost(id, true)).
local ADDON, X = ...

local byOutput -- [itemID] = {recipeID, ...}
local function index()
	byOutput = {}
	for rid, r in pairs(X.db.recipes) do
		if r.out then
			byOutput[r.out] = byOutput[r.out] or {}
			table.insert(byOutput[r.out], rid)
		end
	end
	for _, list in pairs(byOutput) do table.sort(list) end
end
-- every recipe that makes an item; gameOnly: only those read from a profession window
function X.RecipesFor(itemID, gameOnly)
	if not gameOnly then return X.AllRecipesFor(itemID) end
	if not byOutput then index() end
	return byOutput[itemID] or {}
end

-- [[ the recipe list ]] one text per recipe, unpacked when asked (kept while something holds it)
local unpacked = setmetatable({}, {__mode = "v"})
local function fromList(rid)
	local s = X.RECIPE_DB and X.RECIPE_DB[rid]
	if not s then return nil end
	local r = unpacked[rid]
	if r then return r end
	local sk, la, out, n, rg, colors, name = s:match("^([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);([^;]*);(.*)$")
	if not sk then return nil end
	r = {name = name, out = tonumber(out), n = tonumber(n) or 1, r = {}, prof = X.RECIPE_PROFS and X.RECIPE_PROFS[tonumber(sk)],
		la = tonumber(la), db = true}
	if r.out == 0 then r.out = nil end
	if r.la == 0 then r.la = nil end
	for id, c in rg:gmatch("(%d+)%*(%d+)") do r.r[#r.r + 1] = {tonumber(id), tonumber(c)} end
	local c = {}
	for v in colors:gmatch("%d+") do c[#c + 1] = tonumber(v) end
	if #c == 4 then r.colors = c end
	unpacked[rid] = r
	return r
end
-- a recipe read in the game, else the one in the list
function X.Recipe(rid)
	return X.db.recipes[rid] or fromList(rid)
end
-- [itemID] = {recipeID, ...}: made by / used in, over both kinds (built once, again after a profession window is read)
local allByOutput, allUsing
local function indexAll()
	allByOutput, allUsing = {}, {}
	local function add(rid, out, ids)
		if out then
			allByOutput[out] = allByOutput[out] or {}
			table.insert(allByOutput[out], rid)
		end
		for _, id in ipairs(ids) do
			local l = allUsing[id]
			if not l then l = {} allUsing[id] = l end
			if l[#l] ~= rid then l[#l + 1] = rid end
		end
	end
	for rid, r in pairs(X.db.recipes) do
		local ids = {}
		for _, re in ipairs(r.r or {}) do ids[#ids + 1] = re[1] end
		add(rid, r.out, ids)
	end
	for rid, s in pairs(X.RECIPE_DB or {}) do
		if not X.db.recipes[rid] then
			local out, rg = s:match("^[^;]*;[^;]*;([^;]*);[^;]*;([^;]*);")
			local ids = {}
			for id in (rg or ""):gmatch("(%d+)%*") do ids[#ids + 1] = tonumber(id) end
			out = tonumber(out)
			add(rid, out ~= 0 and out or nil, ids)
		end
	end
	for _, l in pairs(allByOutput) do table.sort(l) end
	for _, l in pairs(allUsing) do table.sort(l) end
end
-- every recipe that makes an item (read in the game or in the list)
function X.AllRecipesFor(itemID)
	if not allByOutput then indexAll() end
	return allByOutput[itemID] or {}
end
-- recipes that use an item: {recipeID, ...}
function X.RecipesUsing(itemID)
	if not allUsing then indexAll() end
	local out = {}
	for i, rid in ipairs(allUsing[itemID] or {}) do out[i] = rid end
	return out
end
-- the made item's name, or the recipe's name for one that makes no item (an enchant)
function X.RecipeTitle(rid)
	local r = X.Recipe(rid)
	if not r then return "?" end
	return r.name or (r.out and X.ItemName(tostring(r.out))) or "?"
end

function X.CharKey()
	local name, surname = UnitName("player")
	name, surname = X.Plain(name), X.Plain(surname)
	if not name then return "?" end
	if surname and surname ~= "" and RegionalUniqueNamesEnabled and X.Try(RegionalUniqueNamesEnabled) then
		return name .. " " .. surname
	end
	return name
end
-- which of your characters know a recipe: "Ann, Tor"
function X.KnownBy(rid)
	local who = {}
	for char, list in pairs(X.db.known or {}) do
		if list[rid] then who[#who + 1] = char end
	end
	table.sort(who)
	return who
end

-- [[ reading the profession window ]]
local reading = false
local function readRecipes()
	if reading then return end
	if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs) then return end
	if C_TradeSkillUI.IsTradeSkillReady and not X.Try(C_TradeSkillUI.IsTradeSkillReady) then
		X.Debounce("tradeskill", 1, readRecipes)
		return
	end
	local ids = X.Try(C_TradeSkillUI.GetAllRecipeIDs)
	if not ids or #ids == 0 then return end
	local mine = not (X.Try(C_TradeSkillUI.IsTradeSkillLinked) or X.Try(C_TradeSkillUI.IsTradeSkillGuild) or X.Try(C_TradeSkillUI.IsNPCCrafting))
	local prof = X.Try(C_TradeSkillUI.GetBaseProfessionInfo)
	local profName = prof and prof.professionName ~= "" and prof.professionName or nil
	X.db.known = X.db.known or {}
	local char = X.CharKey()
	if mine then X.db.known[char] = X.db.known[char] or {} end
	local i, added, now = 0, 0, X.Now()
	reading = true
	X.Job("recipes", function()
		local stop = math.min(#ids, i + 40)
		while i < stop do
			i = i + 1
			local rid = ids[i]
			local info = X.Try(C_TradeSkillUI.GetRecipeInfo, rid)
			local sch = X.Try(C_TradeSkillUI.GetRecipeSchematic, rid, false)
			if info and sch and sch.recipeType ~= nil then
				local reagents = {}
				for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
					local basic = slot.reagentType == 1 or (Enum and Enum.CraftingReagentType and slot.reagentType == Enum.CraftingReagentType.Basic)
					local first = slot.reagents and slot.reagents[1]
					if basic and first and first.itemID and (slot.quantityRequired or 0) > 0 then
						reagents[#reagents + 1] = {first.itemID, slot.quantityRequired}
					end
				end
				local out = sch.outputItemID
				if out == 0 then out = nil end
				local n = ((sch.quantityMin or 1) + (sch.quantityMax or sch.quantityMin or 1)) / 2
				if #reagents > 0 then
					if not X.db.recipes[rid] then added = added + 1 end
					X.db.recipes[rid] = {name = sch.name or info.name, out = out, n = math.max(1, n), r = reagents,
						prof = profName or (X.db.recipes[rid] and X.db.recipes[rid].prof), at = now}
				end
				if mine and info.learned then X.db.known[char][rid] = true end
			end
		end
		return i >= #ids
	end, function()
		reading = false
		byOutput, allByOutput, allUsing = nil, nil, nil
		X.Debug("recipes read: " .. #ids .. " (" .. added .. " new)" .. (profName and (" - " .. profName) or ""))
		X.Fire("XNAH_RECIPES")
	end)
end
X.On("TRADE_SKILL_SHOW", function() X.Debounce("tradeskill", 1, readRecipes) end)
X.On("TRADE_SKILL_LIST_UPDATE", function() X.Debounce("tradeskill", 1, readRecipes) end)
X.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() X.Debounce("tradeskill", 1, readRecipes) end)
X.On("NEW_RECIPE_LEARNED", function() X.Debounce("tradeskill", 1, readRecipes) end)

-- [[ costs ]]
-- crafts with a waiting time (transmutes, Mooncloth...): a character can make one only now and then, so they are never
-- counted as a way to get a reagent (the elemental transmutes go round in a circle: Water -> Undeath -> Water, and
-- would make every essence look as cheap as the cheapest one). The Cooldown crafts strategy lists them.
X.CRAFT_COOLDOWNS = { -- recipe (spell) -> hours between crafts on WoW Forever
	[17187] = 47,                    -- Transmute: Arcanite
	[17559] = 23, [17560] = 23, [17561] = 23, [17562] = 23, -- elemental transmutes
	[17563] = 23, [17564] = 23, [17565] = 23, [17566] = 23,
	[18560] = 95,                    -- Mooncloth
	[11479] = 1, [11480] = 1,        -- Iron to Gold, Mithril to Truesilver
	[25146] = 0.2,                   -- Elemental Fire
}
-- the cheapest way to get one of an item: returns copper, how ("vendor" / "ah" / "craft"), and for "craft" the recipe
local costCache, costAt = {}, -100
local function clearCosts() costCache = {} end
X.On("XNAH_PRICES", clearCosts)
X.On("XNAH_RECIPES", clearCosts)
local function reagentCost(id, depth, visiting)
	local now = GetTime()
	if now - costAt > 5 then costCache, costAt = {}, now end
	local hit = costCache[id]
	if hit then return hit[1], hit[2], hit[3] end
	local best, how, via
	local vb = X.VendorBuy(id)
	if vb and X.S().vendorBuyFirst then best, how = vb, "vendor" end
	local ah = X.Price(tostring(id))
	if ah and (not best or ah < best) then best, how = ah, "ah" end
	if vb and not X.S().vendorBuyFirst and not best then best, how = vb, "vendor" end
	if depth < 3 and not visiting[id] then
		visiting[id] = true
		for _, rid in ipairs(X.RecipesFor(id)) do
			if not X.CRAFT_COOLDOWNS[rid] then
				local c, miss = X.RecipeCost(rid, depth + 1, visiting)
				-- a recipe with a reagent of unknown price would look too cheap: not used
				if c and miss == 0 and (not best or c < best) then best, how, via = c, "craft", rid end
			end
		end
		visiting[id] = nil
	end
	-- only a full answer is kept (one worked out inside another item's recipe may stop early)
	if depth == 0 and next(visiting) == nil then costCache[id] = {best, how, via} end
	return best, how, via
end
X.ReagentCost = function(id) return reagentCost(id, 0, {}) end

-- cost of ONE item made by a recipe; second value = how many reagents had no price (cost is then too low)
function X.RecipeCost(rid, depth, visiting)
	local r = X.Recipe(rid)
	if not r then return nil end
	local total, missing = 0, 0
	for _, re in ipairs(r.r) do
		local c = reagentCost(re[1], depth or 0, visiting or {})
		if c then total = total + c * re[2] else missing = missing + 1 end
	end
	if missing == #r.r then return nil, missing end
	return total / (r.n or 1), missing
end
-- cheapest crafting cost of an item (any recipe that makes it)
function X.CraftCost(itemID, gameOnly)
	local best, bestRid, bestMissing
	for _, rid in ipairs(X.RecipesFor(itemID, gameOnly)) do
		local c, missing = X.RecipeCost(rid)
		if c and missing == 0 and (not best or c < best) then best, bestRid, bestMissing = c, rid, missing end
	end
	return best, bestRid, bestMissing
end
-- the reagents of a recipe with their prices, for the detail page: {{id, count, unit, how, total}}
function X.RecipeParts(rid)
	local r = X.Recipe(rid)
	if not r then return {} end
	local out = {}
	for _, re in ipairs(r.r) do
		local unit, how = X.ReagentCost(re[1])
		out[#out + 1] = {id = re[1], count = re[2], unit = unit, how = how, total = unit and unit * re[2] / (r.n or 1)}
	end
	return out
end

-- [[ crafting list ]] every recipe that makes an item: {rid, key, cost, sell, profit, pct, missing, qty, known, prof}
-- opts.mine: only recipes your characters know; opts.prof: one profession
-- every recipe id: read in the game, then the list's others
local function allRecipeIDs()
	local ids = {}
	for rid in pairs(X.db.recipes) do ids[#ids + 1] = rid end
	for rid in pairs(X.RECIPE_DB or {}) do
		if not X.db.recipes[rid] then ids[#ids + 1] = rid end
	end
	return ids
end
X.AllRecipeIDs = allRecipeIDs
function X.CraftList(opts)
	opts = opts or {}
	local out = {}
	for _, rid in ipairs(allRecipeIDs()) do
		local r = X.Recipe(rid)
		if r and r.out and (not opts.prof or r.prof == opts.prof) then
			local known = X.KnownBy(rid)
			if not opts.mine or #known > 0 then
				local cost, missing = X.RecipeCost(rid)
				local key = tostring(r.out)
				local price = X.Price(key)
				local sell = X.AfterCut(price)
				local it = X.Items()[key]
				local row = {rid = rid, key = key, name = r.name, cost = cost, sell = sell, missing = missing or 0, known = known,
					prof = r.prof, qty = it and it.cur and it.cur.qty, stale = not X.Fresh(it)}
				-- no profit while a reagent has no price (the cost would be too low)
				if cost and sell and row.missing == 0 then
					row.profit = sell - cost
					row.pct = cost > 0 and (row.profit / cost * 100) or nil
				end
				out[#out + 1] = row
			end
		end
	end
	table.sort(out, function(a, b)
		if (a.profit ~= nil) ~= (b.profit ~= nil) then return a.profit ~= nil end
		if a.profit and b.profit and a.profit ~= b.profit then return a.profit > b.profit end
		return (a.name or "") < (b.name or "")
	end)
	return out
end
function X.Professions()
	local set, out = {}, {}
	for _, r in pairs(X.db.recipes) do if r.prof and not set[r.prof] then set[r.prof] = true out[#out + 1] = r.prof end end
	for _, name in pairs(X.RECIPE_PROFS or {}) do if not set[name] then set[name] = true out[#out + 1] = name end end
	table.sort(out)
	return out
end
