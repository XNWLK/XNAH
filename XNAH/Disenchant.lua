-- Disenchanting value: what the materials of one piece of gear bring on the auction house, and gear listed for less
-- than that (buy it, disenchant it - or have a friend do it - and sell the materials).
local ADDON, X = ...

-- [[ the materials ]]
local DUST = {strange = 10940, soul = 11083, vision = 11137, dream = 11176, illusion = 16204}
local ESS = {lmagic = 10938, gmagic = 10939, lastral = 10998, gastral = 11082, lmystic = 11134, gmystic = 11135,
	lnether = 11174, gnether = 11175, leternal = 16202, geternal = 16203}
local SHARD = {sglim = 10978, lglim = 11084, sglow = 11138, lglow = 11139, srad = 11177, lrad = 11178, sbril = 14343,
	lbril = 14344}
local NEXUS = 20725
X.DE_MATERIALS = {DUST.strange, DUST.soul, DUST.vision, DUST.dream, DUST.illusion, ESS.lmagic, ESS.gmagic, ESS.lastral,
	ESS.gastral, ESS.lmystic, ESS.gmystic, ESS.lnether, ESS.gnether, ESS.leternal, ESS.geternal, SHARD.sglim, SHARD.lglim,
	SHARD.sglow, SHARD.lglow, SHARD.srad, SHARD.lrad, SHARD.sbril, SHARD.lbril, NEXUS}

-- ===================================================================================================================
-- [[ DISENCHANTING TABLES - classic values; Forever may differ - correct here ]]
-- One line per item level range: {highest item level, {material, chance (0..1), average count}, ...}.
-- Average count: "1-2" = 1.5, "2-3" = 2.5, "2-5" = 3.5, "4-6" = 5, "2-4" = 3.
-- Uncommon (green) ARMOR: mostly dust (~75%), some essence (~20%), a few shards (~5%).
local GREEN_ARMOR = {
	{15, {DUST.strange, 0.80, 1.5}, {ESS.lmagic, 0.20, 1.5}},
	{20, {DUST.strange, 0.75, 2.5}, {ESS.gmagic, 0.20, 1.5}, {SHARD.sglim, 0.05, 1}},
	{25, {DUST.strange, 0.75, 5}, {ESS.lastral, 0.15, 1.5}, {SHARD.sglim, 0.10, 1}},
	{30, {DUST.soul, 0.75, 1.5}, {ESS.gastral, 0.20, 1.5}, {SHARD.lglim, 0.05, 1}},
	{35, {DUST.soul, 0.75, 3.5}, {ESS.lmystic, 0.20, 1.5}, {SHARD.sglow, 0.05, 1}},
	{40, {DUST.vision, 0.75, 1.5}, {ESS.gmystic, 0.20, 1.5}, {SHARD.lglow, 0.05, 1}},
	{45, {DUST.vision, 0.75, 3.5}, {ESS.lnether, 0.20, 1.5}, {SHARD.srad, 0.05, 1}},
	{50, {DUST.dream, 0.75, 1.5}, {ESS.gnether, 0.20, 1.5}, {SHARD.lrad, 0.05, 1}},
	{55, {DUST.dream, 0.75, 3.5}, {ESS.leternal, 0.20, 1.5}, {SHARD.sbril, 0.05, 1}},
	{60, {DUST.illusion, 0.75, 1.5}, {ESS.geternal, 0.20, 1.5}, {SHARD.lbril, 0.05, 1}},
	{999, {DUST.illusion, 0.75, 3.5}, {ESS.geternal, 0.20, 2.5}, {SHARD.lbril, 0.05, 1}},
}
-- Uncommon WEAPONS: the same, with dust and essence swapped (mostly essence).
local GREEN_WEAPON = {
	{15, {DUST.strange, 0.20, 1.5}, {ESS.lmagic, 0.80, 1.5}},
	{20, {DUST.strange, 0.20, 2.5}, {ESS.gmagic, 0.75, 1.5}, {SHARD.sglim, 0.05, 1}},
	{25, {DUST.strange, 0.15, 5}, {ESS.lastral, 0.75, 1.5}, {SHARD.sglim, 0.10, 1}},
	{30, {DUST.soul, 0.20, 1.5}, {ESS.gastral, 0.75, 1.5}, {SHARD.lglim, 0.05, 1}},
	{35, {DUST.soul, 0.20, 3.5}, {ESS.lmystic, 0.75, 1.5}, {SHARD.sglow, 0.05, 1}},
	{40, {DUST.vision, 0.20, 1.5}, {ESS.gmystic, 0.75, 1.5}, {SHARD.lglow, 0.05, 1}},
	{45, {DUST.vision, 0.20, 3.5}, {ESS.lnether, 0.75, 1.5}, {SHARD.srad, 0.05, 1}},
	{50, {DUST.dream, 0.20, 1.5}, {ESS.gnether, 0.75, 1.5}, {SHARD.lrad, 0.05, 1}},
	{55, {DUST.dream, 0.20, 3.5}, {ESS.leternal, 0.75, 1.5}, {SHARD.sbril, 0.05, 1}},
	{60, {DUST.illusion, 0.20, 1.5}, {ESS.geternal, 0.75, 1.5}, {SHARD.lbril, 0.05, 1}},
	{999, {DUST.illusion, 0.20, 3.5}, {ESS.geternal, 0.75, 2.5}, {SHARD.lbril, 0.05, 1}},
}
-- Rare (blue) armor and weapons: one shard (a small chance of a Nexus Crystal at the top).
local BLUE = {
	{25, {SHARD.sglim, 1, 1}},
	{30, {SHARD.lglim, 1, 1}},
	{35, {SHARD.sglow, 1, 1}},
	{40, {SHARD.lglow, 1, 1}},
	{45, {SHARD.srad, 1, 1}},
	{50, {SHARD.lrad, 1, 1}},
	{55, {SHARD.sbril, 1, 1}},
	{999, {SHARD.lbril, 0.995, 1}, {NEXUS, 0.005, 1}},
}
-- Epic (purple) armor and weapons: 2-4 shards, Nexus Crystals from item level 56.
local PURPLE = {
	{45, {SHARD.srad, 1, 3}},
	{50, {SHARD.lrad, 1, 3}},
	{55, {SHARD.sbril, 1, 3}},
	{60, {NEXUS, 1, 1}},
	{999, {NEXUS, 1, 1.5}},
}
-- ===================================================================================================================

local WEAPON, ARMOR = 2, 4
local MIN_LEVEL = 5 -- under this item level nothing comes out

-- what disenchanting one item gives: {{itemID, chance, avgCount}, ...} or nil (not disenchantable / not loaded)
local info = {} -- [itemID] = {q, lvl, class} (or false: never disenchantable), kept while the game runs
local function itemInfo(id)
	local v = info[id]
	if v ~= nil then return v end
	local name, _, q, lvl, _, _, _, _, _, _, _, class = X.Try(C_Item.GetItemInfo, id)
	if not name then
		if C_Item.RequestLoadItemDataByID then X.Try(C_Item.RequestLoadItemDataByID, id) end
		return nil -- not loaded yet: asked for, try again later
	end
	if (class ~= WEAPON and class ~= ARMOR) or not q or q < 2 or q > 4 or not lvl then
		info[id] = false
	else
		info[id] = {q = q, lvl = lvl, class = class}
	end
	return info[id]
end
function X.DEParts(key)
	local id = X.KeyID(key)
	local v = id and itemInfo(id)
	if not v or v.lvl < MIN_LEVEL then return nil end
	local tbl = v.q == 2 and (v.class == WEAPON and GREEN_WEAPON or GREEN_ARMOR) or v.q == 3 and BLUE or PURPLE
	for _, line in ipairs(tbl) do
		if v.lvl <= line[1] then
			if v.q == 4 and v.lvl < 40 then return nil end -- no epic tables under 40 (none sold that low)
			local parts = {}
			for i = 2, #line do parts[#parts + 1] = {line[i][1], line[i][2], line[i][3]} end
			return parts, v
		end
	end
	return nil
end

-- [[ X.DEValue(key) ]] -> copper per item (each material at its price), parts {{itemID, chance, avgCount, price}},
-- missing (materials without a price; they count as 0). nil when not disenchantable or no material has a price.
function X.DEValue(key)
	local parts = X.DEParts(key)
	if not parts then return nil end
	local value, known, missing = 0, 0, 0
	for _, p in ipairs(parts) do
		local price = X.Price(tostring(p[1]))
		p[4] = price
		if price then
			value = value + p[2] * p[3] * price
			known = known + 1
		else
			missing = missing + 1
		end
	end
	if known == 0 then return nil, parts, missing end
	return value, parts, missing
end

-- [[ gear under its disenchanting value ]] lowest price under the value minus 5%; rows {key, buy, de, profit (the
-- materials sold after the cut, minus the price), pct (price as % of the value), qty, missing}
function X.UnderDE()
	local out = {}
	for key, it in pairs(X.Items()) do
		local cur = it.cur
		if cur and cur.min and (cur.qty or 0) > 0 and (it.q == nil or (it.q >= 2 and it.q <= 4)) and X.Fresh(it) then
			local de, _, missing = X.DEValue(key)
			if de and de > 0 and cur.min < de * 0.95 then
				out[#out + 1] = {key = key, buy = cur.min, de = de, profit = X.AfterCut(de) - cur.min, pct = cur.min / de * 100,
					qty = cur.qty, missing = missing}
			end
		end
	end
	table.sort(out, function(a, b) return a.profit > b.profit end)
	return out
end

-- for the tests: forget what is known about items (the game may load them later)
function X.DEForget() info = {} end
