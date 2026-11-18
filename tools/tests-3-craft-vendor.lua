-- XNAH test scenes, part 3: vendors (what they sell, flips, auctions under the vendor price), crafting (recipes, costs),
-- deals and movers over 10 days, tooltip lines and slash commands.

T.scene("vendor: merchant prices, cheapest kept, flips and below-vendor auctions", function()
	local X = W.start()
	W.merchant = {
		{itemID = 3371, price = 20, stackCount = 5, numAvailable = -1},  -- Empty Vial, 5 for 20c = 4c each
		{itemID = 2320, price = 10, stackCount = 1, numAvailable = -1},  -- Coarse Thread
		{itemID = 2678, price = 100, stackCount = 1, numAvailable = 3},  -- Mild Spices, only 3 in stock
		{itemID = 4306, price = 500, stackCount = 1, numAvailable = -1, extended = true}, -- paid with tokens: ignored
	}
	W.openMerchant("Alchemy Supplies")
	W.advance(1)
	local p, info = X.VendorBuy(3371)
	T.check("vial: price of one", p, 4)
	T.check("vial: who sells it", info and info.from, "Alchemy Supplies")
	T.check("vial: unlimited", info and info.lim, nil)
	T.check("spices: limited stock", select(2, X.VendorBuy(2678)) and select(2, X.VendorBuy(2678)).lim, true)
	T.check("token item ignored", X.VendorBuy(4306), nil)
	W.closeMerchant()
	-- a dearer vendor does not replace the cheaper one; a cheaper one does
	W.merchant = {{itemID = 3371, price = 25, stackCount = 5, numAvailable = -1}}
	W.openMerchant("Other Vendor")
	W.advance(1)
	T.check("dearer vendor: cheaper price kept", X.VendorBuy(3371), 4)
	W.merchant = {{itemID = 3371, price = 3, stackCount = 1, numAvailable = -1}}
	W.openMerchant("Cheap Vendor")
	W.advance(1)
	T.check("cheaper vendor: new price", X.VendorBuy(3371), 3)
	-- auction house: vials sell at 50c each (a flip), Linen listed at 5c (a vendor pays 13c)
	W.list(3371, 50, 20, 4, "Vial")
	W.list(2589, 5, 10, 1, "Hasty")
	W.list(2589, 50, 20, 5, "Ann")
	W.list(2592, 80, 20, 3, "Wool") -- above the vendor price: no row
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	local flips = X.VendorFlips()
	T.check("one vendor flip", #flips, 1)
	T.check("flip: the vial", flips[1] and flips[1].key, "3371")
	T.check("flip: buy at", flips[1] and flips[1].buy, 3)
	T.near("flip: sells for after the cut", flips[1] and flips[1].sell, 47.5)
	T.near("flip: profit", flips[1] and flips[1].profit, 44.5)
	local below = X.BelowVendor()
	T.check("one below-vendor auction", #below, 1)
	T.check("below: Linen", below[1] and below[1].key, "2589")
	T.check("below: buy at", below[1] and below[1].buy, 5)
	T.check("below: the vendor pays", below[1] and below[1].sell, 13)
	T.check("below: profit", below[1] and below[1].profit, 8)
	-- 4 days later the prices are old: no flips, no below-vendor rows
	W.advance(4 * 86400)
	T.check("old prices: no flips", #X.VendorFlips(), 0)
	T.check("old prices: no below-vendor rows", #X.BelowVendor(), 0)
end)

-- recipes of the scenes (IDs are made up; the items are real)
local function recipes()
	W.items[900001] = {name = "Arcane Thing", quality = 2, sell = 100, stack = 20}
	W.items[900002] = {name = "Bright Thing", quality = 2, sell = 100, stack = 20}
	W.items[900010] = {name = "Steel Bar", quality = 1, sell = 50, stack = 20}
	W.items[900011] = {name = "Iron Ore", quality = 1, sell = 20, stack = 20}
	W.items[900012] = {name = "Coal", quality = 1, sell = 1, stack = 20}
	W.items[900020] = {name = "Steel Buckle", quality = 2, sell = 200, stack = 20}
	W.recipes = {
		[1] = {name = "Smelt Copper", out = 2840, reagents = {{2770, 1}}, learned = true, prof = "Mining"},
		[2] = {name = "Smelt Bronze", out = 2841, qMin = 2, qMax = 2, reagents = {{2840, 1}, {3576, 1}}, learned = true, prof = "Mining"},
		[3] = {name = "Minor Healing Potion", out = 118, reagents = {{2447, 1}, {765, 1}, {3371, 1}}, learned = true, prof = "Alchemy"},
		[4] = {name = "Lesser Healing Potion", out = 858, reagents = {{118, 1}, {785, 1}, {3371, 1}}, learned = false, prof = "Alchemy"},
		[5] = {name = "Bolt of Linen Cloth", out = 2996, reagents = {{2589, 2}}, prof = "Tailoring"},
		[6] = {name = "Red Linen Shirt", out = 2575, reagents = {{2996, 1}, {2320, 1}, {2678, 1}}, prof = "Tailoring"},
		[7] = {name = "Make Arcane Thing", out = 900001, reagents = {{900002, 1}}, learned = true, prof = "Mining"},
		[8] = {name = "Make Bright Thing", out = 900002, reagents = {{900001, 1}}, learned = true, prof = "Mining"},
		[9] = {name = "Smelt Steel", out = 900010, reagents = {{900011, 1}, {900012, 1}}, learned = true, prof = "Mining"},
		[10] = {name = "Steel Buckle", out = 900020, reagents = {{900010, 2}}, learned = true, prof = "Mining"},
		[11] = {name = "Enchant Bracer", out = nil, reagents = {{2589, 1}}, learned = true, prof = "Mining"},
	}
	-- the market
	W.list(2770, 10, 20, 5)    -- Copper Ore 10c
	W.list(2840, 30, 20, 5)    -- Copper Bar 30c: smelting is cheaper
	W.list(3576, 40, 20, 5)    -- Tin Bar 40c
	W.list(2841, 50, 20, 5)    -- Bronze Bar 50c
	W.list(2447, 20, 20, 5)    -- Peacebloom
	W.list(765, 15, 20, 5)     -- Silverleaf
	W.list(3371, 50, 20, 5)    -- Empty Vial 50c on the AH (a vendor sells it for 4c)
	W.list(118, 10000, 5, 5)   -- Minor Healing Potion 1g
	W.list(858, 30000, 5, 5)   -- Lesser Healing Potion 3g
	W.list(785, 25, 20, 5)     -- Mageroyal
	W.list(2589, 50, 20, 5)    -- Linen Cloth
	W.list(2996, 150, 20, 5)   -- Bolt 1s 50c (2 Linen = 1s)
	W.list(2575, 5000, 1, 3)   -- Red Linen Shirt 50s
	W.list(2320, 5, 20, 3)     -- Coarse Thread 5c on the AH, 10c at the vendor
	W.list(900001, 100, 20, 3) -- Arcane Thing 1s
	W.list(900010, 80, 20, 3)  -- Steel Bar 80c on the AH
	W.list(900012, 5, 20, 3)   -- Coal 5c (Iron Ore has no price at all)
	W.list(900020, 2000, 20, 3) -- Steel Buckle 20s
	W.merchant = {{itemID = 3371, price = 4, stackCount = 1, numAvailable = -1}, {itemID = 2320, price = 10, stackCount = 1, numAvailable = -1}}
end

T.scene("craft: recipes from profession windows, costs, intermediate reagents, cycles", function()
	local X = W.start()
	recipes()
	W.openProfession("Mining")
	W.advance(3)
	local r1 = X.db.recipes[1]
	T.ok("Smelt Copper read", r1 ~= nil)
	T.check("recipe: output", r1 and r1.out, 2840)
	T.check("recipe: makes 1", r1 and r1.n, 1)
	T.check("recipe: reagent", r1 and r1.r[1][1], 2770)
	T.check("recipe: profession", r1 and r1.prof, "Mining")
	T.check("bronze makes 2", X.db.recipes[2] and X.db.recipes[2].n, 2)
	T.check("enchant (no item made) stored without output", X.db.recipes[11] and X.db.recipes[11].out, nil)
	T.check("known by me", table.concat(X.KnownBy(1), ","), "Xn Ascalon")
	W.closeProfession()
	W.openProfession("Alchemy")
	W.advance(3)
	T.check("alchemy: learned recipe known", #X.KnownBy(3), 1)
	T.check("alchemy: unlearned recipe not known", #X.KnownBy(4), 0)
	T.ok("alchemy: unlearned recipe still stored", X.db.recipes[4] ~= nil)
	W.closeProfession()
	-- someone links their tailoring: recipes are stored, but not as mine
	W.openProfession("Tailoring", true)
	W.advance(3)
	T.ok("linked: recipes stored", X.db.recipes[5] ~= nil and X.db.recipes[6] ~= nil)
	T.check("linked: not known by me", #X.KnownBy(5), 0)
	T.check("professions", table.concat(X.Professions(), ","), "Alchemy,Mining,Tailoring")
	T.check("recipes for Copper Bar", table.concat(X.RecipesFor(2840), ","), "1")
	T.check("recipes using Copper Ore", table.concat(X.RecipesUsing(2770), ","), "1")
	-- prices
	W.openMerchant("Supplies")
	W.advance(1)
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	local c, how, via = X.ReagentCost(2840)
	T.check("Copper Bar: cheapest is smelting it", how, "craft")
	T.check("Copper Bar: cost 10c (one ore)", c, 10)
	T.check("Copper Bar: via recipe 1", via, 1)
	T.check("Bronze Bar: (copper bar 10 + tin bar 40) / 2", X.RecipeCost(2), 25)
	c, how = X.ReagentCost(3371)
	T.check("Empty Vial: from the vendor", how, "vendor")
	T.check("Empty Vial: 4c", c, 4)
	c, how = X.ReagentCost(2320)
	T.check("Coarse Thread: the auction house is cheaper than the vendor", how, "ah")
	T.check("Coarse Thread: 5c", c, 5)
	T.check("Minor Healing Potion: 20 + 15 + 4", X.RecipeCost(3), 39)
	T.check("crafting cost of the potion", X.CraftCost(118), 39)
	-- Lesser potion: the minor potion is cheaper to make (39c) than to buy (1g)
	T.check("Lesser Healing Potion: 39 + 25 + 4", X.RecipeCost(4), 68)
	-- a cycle (A makes B, B makes A) ends
	local a = X.CraftCost(900001)
	T.ok("cycle: a cost or nothing, no hang", a == nil or a > 0, a)
	T.check("cycle: buying Arcane Thing (1s) is cheapest", (X.ReagentCost(900001)), 100)
	-- missing reagent price (Mild Spices has none): the cost is not a crafting cost
	local cost, missing = X.RecipeCost(6)
	T.check("shirt: one reagent without a price", missing, 1)
	T.check("shirt: no crafting cost", X.CraftCost(2575), nil)
	-- the parts for the detail page
	local parts = X.RecipeParts(3)
	T.check("parts: 3 reagents", #parts, 3)
	T.check("parts: the vial from the vendor", parts[3] and parts[3].how, "vendor")
	T.check("parts: total of the vial", parts[3] and parts[3].total, 4)
	-- the crafting list
	local list = X.CraftList()
	local sorted = true
	for i = 2, #list do
		local p, q = list[i - 1], list[i]
		if q.profit and not p.profit then sorted = false end
		if p.profit and q.profit and q.profit > p.profit then sorted = false end
	end
	T.ok("list: profit first, highest first", sorted)
	T.check("list: the enchant (no item) is left out", (function() for _, r in ipairs(list) do if r.rid == 11 then return true end end return false end)(), false)
	local potion
	for _, r in ipairs(list) do if r.rid == 3 then potion = r end end
	T.near("list: potion profit = 1g after cut - 39c", potion and potion.profit, 9500 - 39)
	T.check("list (mine): only known recipes", (function()
		for _, r in ipairs(X.CraftList({mine = true})) do if #r.known == 0 then return false end end
		return true end)(), true)
	T.check("list (Alchemy)", #X.CraftList({prof = "Alchemy"}), 2)
end)

T.scene("craft: a reagent made from something without a price is not 'cheap to craft'", function()
	-- Steel Bar = Iron Ore (no price anywhere) + Coal (5c). Crafting it is NOT known to cost 5c: the auction house's
	-- 80c is the cheapest known way. Craft.lua's reagentCost takes a recipe's partial cost (missing reagents left out).
	local X = W.start()
	recipes()
	W.openProfession("Mining")
	W.advance(3)
	W.openAH()
	T.fullScan(X)
	local cost, missing = X.RecipeCost(9)
	T.check("Smelt Steel: one reagent without a price", missing, 1)
	local c, how = X.ReagentCost(900010)
	T.check("Steel Bar: bought on the auction house", how, "ah")
	T.check("Steel Bar: 80c", c, 80)
	T.check("Steel Buckle: 2 Steel Bars at 80c", X.RecipeCost(10), 160)
end)

T.scene("craft: a recipe with a missing reagent price does not top the list", function()
	-- The Red Linen Shirt's Mild Spices have no price: its cost (1s 15c without the spices) is too low, so the list's
	-- profit is made up. Such rows should not be ranked by that profit.
	local X = W.start()
	recipes()
	W.openProfession("Tailoring")
	W.advance(3)
	W.openAH()
	T.fullScan(X)
	local list = X.CraftList()
	local shirt
	for i, r in ipairs(list) do if r.rid == 6 then shirt = r shirt.pos = i end end
	T.check("shirt: missing 1", shirt and shirt.missing, 1)
	T.check("shirt: no profit shown (its cost is incomplete)", shirt and shirt.profit, nil)
end)

T.scene("market: deals and movers over 10 days", function()
	local X = W.start()
	W.makeMarket(21, 300, {lastDay = 9, uncached = 0})
	W.openAH()
	for day = 0, 9 do
		W.marketDay(day, 9)
		local t0 = W.NOW
		T.ok("full scan day " .. day, T.fullScan(X))
		W.advance(86400 - (W.NOW - t0))
	end
	local deals = X.Deals()
	local set = {}
	for _, r in ipairs(deals) do set[r.key] = r end
	local expected, found = 0, 0
	for _, e in ipairs(W.market.items) do
		if e.special == "deal" and e.base * 0.7 > 1500 then
			expected = expected + 1
			if set[tostring(e.id)] then found = found + 1 end
		end
	end
	T.check("deals: every planted deal found (" .. expected .. ")", found, expected)
	local allowed = {}
	for _, k in ipairs({"deal", "below", "fall"}) do for _, id in ipairs(W.market.byKind[k]) do allowed[tostring(id)] = true end end
	local stray = {}
	for _, r in ipairs(deals) do if not allowed[r.key] then stray[#stray + 1] = r.key end end
	T.check("deals: no ordinary item listed as a deal", table.concat(stray, ","), "")
	local sorted = true
	for i = 2, #deals do if deals[i].profit > deals[i - 1].profit then sorted = false end end
	T.ok("deals: best profit first", sorted)
	-- movers
	local function has(list, ids)
		local s, miss = {}, {}
		for _, r in ipairs(list) do s[r.key] = true end
		-- stackable items only (a sword's suffixes are listed too seldom for a trend)
		for _, id in ipairs(ids) do if W.items[id].stack > 1 and not s[tostring(id)] then miss[#miss + 1] = id end end
		return table.concat(miss, ",")
	end
	local up = X.Movers("up")
	T.check("movers up: every rising item", has(up, W.market.byKind.rise), "")
	local riseSet = {}
	for _, id in ipairs(W.market.byKind.rise) do riseSet[tostring(id)] = true end
	T.ok("movers up: the top one is a rising item", up[1] and riseSet[tostring(X.KeyID(up[1].key))], up[1] and up[1].key)
	T.check("movers down: every falling item", has(X.Movers("down"), W.market.byKind.fall), "")
	T.check("movers short: every item whose supply dropped", has(X.Movers("short"), W.market.byKind.short), "")
	T.check("movers flood: every item whose supply jumped", has(X.Movers("flood"), W.market.byKind.flood), "")
	T.check("movers: limit", #X.Movers("up", 3), math.min(3, #up))
	-- the summary of one deal item
	local d = deals[1]
	if d then
		local s = X.Summary(d.key)
		T.ok("summary: fresh", s.fresh)
		T.ok("summary: usual price", s.usual and s.usual > d.buy)
		T.ok("summary: flip profit", s.flip ~= nil)
	end
	T.check("10 full scans logged", #X.Realm().scans, 10)
	-- everything survives a reload
	local n = #deals
	X = W.reload()
	T.check("after reload: same deals", #X.Deals(), n)
	local items, bytes = X.DataSize()
	T.note(string.format("10 days, %d items, 1 full scan a day: DataSize %d bytes (%.0f per item), saved file %d bytes",
		items, bytes, bytes / items, W.savedSize()))
end)

T.scene("tooltip: a stack in the bags, vendor-only items, suffixes", function()
	local X = W.start()
	W.list(2589, 50, 20, 5)
	W.list(15210, 50000, 1, 2, "Cid", -19)
	W.openAH()
	T.fullScan(X)
	local text = W.tipText(W.hoverItem(2589, 0, 1, 20))
	T.ok("stack: header with x20", text:find("XNAH x20", 1, true) ~= nil, text)
	T.ok("stack: lowest price of 20 = 10s, 50c each", text:find("Lowest price  10s (50c each)", 1, true) ~= nil, text)
	T.ok("stack: market value", text:find("Market value", 1, true) ~= nil, text)
	T.ok("stack: vendor price of 20 (13c x 20 = 2s 60c)", text:find("2s 60c (13c each)", 1, true) ~= nil, text)
	text = W.tipText(W.hoverItem(2589, 0, 2, 1))
	T.ok("one: no x1 and no 'each'", text:find("x1", 1, true) == nil and text:find("each", 1, true) == nil, text)
	-- an item only a vendor knows
	text = W.tipText(W.hoverItem(2320, 0, 3, 1))
	T.ok("vendor only: header", text:find("XNAH", 1, true) ~= nil, text)
	T.ok("vendor only: vendor price 2c", text:find("2c", 1, true) ~= nil, text)
	T.ok("vendor only: no auction lines", text:find("Lowest", 1, true) == nil, text)
	-- an item nobody knows a price of
	W.items[2575].sell = 0
	text = W.tipText(W.hoverItem(2575, 0, 4, 1))
	T.ok("no price at all: no XNAH lines", text:find("XNAH", 1, true) == nil, text)
	-- a sword with a random suffix: its own price
	text = W.tipText(W.hoverItem(15210, 0, 5, 1, -19))
	T.ok("suffix: price of the Bear sword", text:find("5g", 1, true) ~= nil, text)
	-- the item link in chat (ItemRefTooltip) gets the lines too
	W.env.ItemRefTooltip:SetHyperlink(W.link(2589))
	T.ok("item link tooltip has lines", W.tipText(W.env.ItemRefTooltip.lines):find("XNAH", 1, true) ~= nil)
	-- switched off
	X.S().tooltip = false
	text = W.tipText(W.hoverItem(2589, 0, 1, 20))
	T.ok("switched off: no lines", text:find("XNAH", 1, true) == nil, text)
	X.S().tooltip = true
	X.S().tipStack = false
	text = W.tipText(W.hoverItem(2589, 0, 1, 20))
	T.ok("tipStack off: no x20 in the header", text:find("x20", 1, true) == nil, text)
end)

T.scene("slash: /xnah, scan without the auction house, item names", function()
	local X = W.start()
	local slash = W.env.SlashCmdList.XNAH
	T.ok("slash command registered", slash ~= nil and W.env.SLASH_XNAH1 == "/xnah")
	slash("")
	local f = X.UI.Frame and X.UI.Frame()
	T.ok("/xnah opens the window", f and f:IsShown())
	slash("")
	T.ok("/xnah again closes it", f and not f:IsShown())
	W.chat = {}
	slash("scan")
	T.ok("/xnah scan without the auction house: told to open it", #W.said("open the auction house first") == 1, W.lastSaid())
	slash("watch")
	T.ok("/xnah watch without the auction house: told to open it", #W.said("open the auction house first") == 2, W.lastSaid())
	slash("help")
	T.ok("/xnah help lists the commands", #W.said("/xnah") >= 5)
	slash("debug")
	T.check("/xnah debug on", X.S().debug, true)
	slash("debug")
	T.check("/xnah debug off", X.S().debug, false)
	-- items by name or link
	local now = X.Now()
	X.Record("2589", now, 50, 50, 10, 1, "Linen Cloth", 1)
	X.Record("2996", now, 150, 150, 10, 1, "Bolt of Linen Cloth", 1)
	slash("bolt of linen")
	T.check("/xnah <part of a name> opens the item", X.UI.itemKey, "2996")
	T.ok("the window is open on the item tab", f:IsShown())
	slash(W.link(15210, -19))
	T.check("/xnah <link> opens that item (with its suffix)", X.UI.itemKey, "15210:-19")
	slash("nothing like this")
	T.ok("unknown name: a message", #W.said("no item found") == 1, W.lastSaid())
	-- an exact name wins over longer names that contain it
	-- (X.Find returns the first match in table order, which in the game is any order; the stand-in keeps the order
	-- items were added, so the longer names are added first here)
	X.db.realms[X.realmKey] = nil
	for i = 1, 7 do
		local id = 800000 + i
		W.items[id] = {name = 'Heavy Linen Cloth ' .. i, quality = 1, sell = 1, stack = 20}
		X.Record(tostring(id), now, 10, 10, 1, 1, W.items[id].name, 1)
	end
	X.Record('2589', now, 50, 50, 10, 1, 'Linen Cloth', 1)
	X.UI.itemKey = nil
	slash('Linen Cloth')
	T.check('/xnah Linen Cloth opens Linen Cloth itself (not a longer name containing it)', X.UI.itemKey, '2589')
	-- forget asks first
	slash("forget")
	local yes = W.findButton("Yes")
	T.ok("forget: asks", yes ~= nil)
	if yes then yes:Click() end
	T.check("forget: the realm's prices are gone", T.count(X.Items()), 0)
	-- the key binding
	W.env.XNAH_Toggle()
	W.env.XNAH_Toggle()
end)
