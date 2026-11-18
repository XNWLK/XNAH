-- Crafting: every recipe is read when you open a profession window (yours, or one someone linked), so XNAH knows
-- what goes into what. A crafting cost = the reagents at the cheapest way to get them (a vendor, the auction house, or
-- crafting the reagent itself), divided by how many one craft makes.
--   XNAHDB.recipes[recipeID] = {name, out = itemID or nil (enchants make no item), n = how many one craft makes,
--     r = {{itemID, count}, ...}, prof = "Alchemy", at = t}
--   XNAHDB.known[character] = {[recipeID] = true}  recipes your characters know
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
function X.RecipesFor(itemID)
	if not byOutput then index() end
	return byOutput[itemID] or {}
end
-- recipes that use an item: {recipeID, ...}
function X.RecipesUsing(itemID)
	local out = {}
	for rid, r in pairs(X.db.recipes) do
		for _, re in ipairs(r.r or {}) do
			if re[1] == itemID then out[#out + 1] = rid break end
		end
	end
	table.sort(out)
	return out
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
		byOutput = nil
		X.Debug("recipes read: " .. #ids .. " (" .. added .. " new)" .. (profName and (" - " .. profName) or ""))
		X.Fire("XNAH_RECIPES")
	end)
end
X.On("TRADE_SKILL_SHOW", function() X.Debounce("tradeskill", 1, readRecipes) end)
X.On("TRADE_SKILL_LIST_UPDATE", function() X.Debounce("tradeskill", 1, readRecipes) end)
X.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() X.Debounce("tradeskill", 1, readRecipes) end)
X.On("NEW_RECIPE_LEARNED", function() X.Debounce("tradeskill", 1, readRecipes) end)

-- [[ costs ]]
-- the cheapest way to get one of an item: returns copper, how ("vendor" / "ah" / "craft"), and for "craft" the recipe
local function reagentCost(id, depth, visiting)
	local best, how, via
	local vb = X.VendorBuy(id)
	if vb and X.S().vendorBuyFirst then best, how = vb, "vendor" end
	local ah = X.Price(tostring(id))
	if ah and (not best or ah < best) then best, how = ah, "ah" end
	if vb and not X.S().vendorBuyFirst and not best then best, how = vb, "vendor" end
	if depth < 3 and not visiting[id] then
		visiting[id] = true
		for _, rid in ipairs(X.RecipesFor(id)) do
			local c, miss = X.RecipeCost(rid, depth + 1, visiting)
			-- a recipe with a reagent of unknown price would look too cheap: not used
			if c and miss == 0 and (not best or c < best) then best, how, via = c, "craft", rid end
		end
		visiting[id] = nil
	end
	return best, how, via
end
X.ReagentCost = function(id) return reagentCost(id, 0, {}) end

-- cost of ONE item made by a recipe; second value = how many reagents had no price (cost is then too low)
function X.RecipeCost(rid, depth, visiting)
	local r = X.db.recipes[rid]
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
function X.CraftCost(itemID)
	local best, bestRid, bestMissing
	for _, rid in ipairs(X.RecipesFor(itemID)) do
		local c, missing = X.RecipeCost(rid)
		if c and missing == 0 and (not best or c < best) then best, bestRid, bestMissing = c, rid, missing end
	end
	return best, bestRid, bestMissing
end
-- the reagents of a recipe with their prices, for the detail page: {{id, count, unit, how, total}}
function X.RecipeParts(rid)
	local r = X.db.recipes[rid]
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
function X.CraftList(opts)
	opts = opts or {}
	local out = {}
	for rid, r in pairs(X.db.recipes) do
		if r.out and (not opts.prof or r.prof == opts.prof) then
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
	table.sort(out)
	return out
end
