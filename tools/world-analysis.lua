-- The stand-in world, analysis part (sales speed, disenchanting, market shape): item level and item class for gear,
-- seller names in commodity search results, and helpers to "sell" auctions between two full scans.

-- the disenchanting materials (stackable trade goods)
local MATS = {
	[10940] = "Strange Dust", [11083] = "Soul Dust", [11137] = "Vision Dust", [11176] = "Dream Dust", [16204] = "Illusion Dust",
	[10938] = "Lesser Magic Essence", [10939] = "Greater Magic Essence", [10998] = "Lesser Astral Essence",
	[11082] = "Greater Astral Essence", [11134] = "Lesser Mystic Essence", [11135] = "Greater Mystic Essence",
	[11174] = "Lesser Nether Essence", [11175] = "Greater Nether Essence", [16202] = "Lesser Eternal Essence",
	[16203] = "Greater Eternal Essence", [10978] = "Small Glimmering Shard", [11084] = "Large Glimmering Shard",
	[11138] = "Small Glowing Shard", [11139] = "Large Glowing Shard", [11177] = "Small Radiant Shard",
	[11178] = "Large Radiant Shard", [14343] = "Small Brilliant Shard", [14344] = "Large Brilliant Shard", [20725] = "Nexus Crystal",
}
W.DE_MATS = MATS

-- disenchantable gear for the scenes: W.items fields ilvl (item level) and class (2 weapon, 4 armor)
W.DE_GEAR = {
	green = 70001,   -- uncommon armor, item level 25
	greenW = 70002,  -- uncommon weapon, item level 25
	blue = 70003,    -- rare armor, item level 40
	epic = 70004,    -- epic armor, item level 60
	white = 70005,   -- common armor (not disenchantable)
	low = 70006,     -- uncommon armor, item level 3 (too low)
}
function W.addDEItems()
	for id, name in pairs(MATS) do W.items[id] = {name = name, quality = 2, sell = 100, stack = 20} end
	W.items[70001] = {name = "Ashen Leggings", quality = 2, sell = 500, stack = 1, ilvl = 25, class = 4}
	W.items[70002] = {name = "Ashen Axe", quality = 2, sell = 700, stack = 1, ilvl = 25, class = 2}
	W.items[70003] = {name = "Bright Mantle", quality = 3, sell = 3000, stack = 1, ilvl = 40, class = 4}
	W.items[70004] = {name = "Elder Crown", quality = 4, sell = 20000, stack = 1, ilvl = 60, class = 4}
	W.items[70005] = {name = "Plain Shirt", quality = 1, sell = 10, stack = 1, ilvl = 25, class = 4}
	W.items[70006] = {name = "Tiny Gloves", quality = 2, sell = 5, stack = 1, ilvl = 3, class = 4}
end

-- auctions that are bought (or cancelled): removes up to n auctions of an item whose time-left band is `band`
-- (any band when nil); returns how many units went
function W.buyOut(id, n, band)
	local keep, gone, units = {}, 0, 0
	for _, a in ipairs(W.ah) do
		if a.itemID == id and gone < n and (band == nil or a.timeLeft == band) then
			gone = gone + 1
			units = units + (a.count or 1)
		else
			keep[#keep + 1] = a
		end
	end
	W.ah = keep
	return units
end
-- n auctions of `count` at unit price with a given time-left band and owner
function W.listBand(id, unit, count, n, band, owner)
	for i = 1, n do
		W.ah[#W.ah + 1] = {itemID = id, count = count, buyout = math.floor(unit * count + 0.5), bid = 1,
			owner = (owner or "Seller") .. i .. " Smith", timeLeft = band}
	end
end

table.insert(W.onReset, function()
	W.ownerCap = nil -- commodity search rows name at most this many sellers (nil: all)
end)

local function idOf(x)
	if type(x) == "number" then return x end
	if type(x) == "string" then return tonumber(x:match("item:(%-?%d+)") or x) end
	return nil
end
local function pack(...) return {n = select("#", ...), ...} end

table.insert(W.onEnv, function(env)
	-- item level (4th return) and class ID (12th) from W.items when a scene set them
	local getInfo = env.C_Item.GetItemInfo
	env.C_Item.GetItemInfo = function(x)
		local r = pack(getInfo(x))
		local it = W.items[idOf(x) or 0]
		if r[1] and it then
			if it.ilvl then r[4] = it.ilvl end
			if it.class then
				r[12] = it.class
				r[6] = it.class == 2 and "Weapon" or "Armor"
			end
		end
		return (table.unpack or unpack)(r, 1, r.n)
	end
	-- commodity search rows: the sellers at that price (the base world leaves them empty)
	local getRow = env.C_AuctionHouse.GetCommoditySearchResultInfo
	env.C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
		local row = getRow(id, i)
		if type(row) ~= "table" then return row end
		-- like the game: numOwnerItems = how many of the row's units are yours (a row can mix yours and others')
		local names, seen, own = {}, {}, 0
		for _, a in ipairs(W.ah) do
			if a.itemID == id and a.buyout and a.buyout > 0 and a.owner then
				local u = math.floor(a.buyout / math.max(1, a.count or 1) + 0.5)
				if u == row.unitPrice then
					if not seen[a.owner] then seen[a.owner] = true names[#names + 1] = a.owner end
					if W.me and a.owner == W.me then own = own + (a.count or 1) end
				end
			end
		end
		row.totalNumberOfOwners = #names
		if W.ownerCap then for k = #names, W.ownerCap + 1, -1 do names[k] = nil end end
		row.owners = names
		row.numOwnerItems = own
		row.containsOwnerItem = own > 0
		return row
	end
end)
