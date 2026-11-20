-- XNAH test scenes, part 9 (helper D): the crafting queue (targets, materials, "Craft next" only on a click).
-- (Guild price sharing and the price export were taken out in v0.7; the Settings page is tested in tests-25-gold.lua.)

-- [[ shared bits ]]
local function craftWorld(X)
	W.recipes = {
		[1] = {name = "Smelt Copper", out = 2840, reagents = {{2770, 1}}, learned = true, prof = "Mining"},
		[2] = {name = "Smelt Bronze", out = 2841, qMin = 2, qMax = 2, reagents = {{2840, 1}, {3576, 1}}, learned = true, prof = "Mining"},
		[3] = {name = "Minor Healing Potion", out = 118, reagents = {{2447, 1}, {765, 1}, {3371, 1}}, learned = true, prof = "Alchemy"},
	}
	W.list(2770, 10, 20, 5)    -- Copper Ore 10c
	W.list(2840, 30, 20, 5)    -- Copper Bar 30c (smelting it costs 10c)
	W.list(3576, 40, 20, 5)    -- Tin Bar 40c
	W.list(2841, 50, 20, 5)    -- Bronze Bar 50c
	W.list(2447, 20, 20, 5)    -- Peacebloom
	W.list(765, 15, 20, 5)     -- Silverleaf
	W.list(3371, 50, 20, 5)    -- Empty Vial 50c (a vendor sells it for 4c)
	W.list(118, 10000, 5, 5)   -- Minor Healing Potion 1g
	W.merchant = {{itemID = 3371, price = 4, stackCount = 1, numAvailable = -1}}
	W.openProfession("Mining") W.advance(3) W.closeProfession()
	W.openProfession("Alchemy") W.advance(3) W.closeProfession()
	W.openMerchant("Alchemy Supplies") W.advance(1) W.closeMerchant()
	W.openAH()
	T.ok("full scan", T.fullScan(X))
	W.closeAH()
end
local function rowOf(rows, rid) for _, r in ipairs(rows) do if r.rid == rid then return r end end end
local function matOf(mats, id) for _, m in ipairs(mats) do if m.id == id then return m end end end

T.scene("queue: restock vs craft, makes-per-craft, owned counts, profit", function()
	local X = W.start()
	craftWorld(X)
	local owned = X.Owned
	X.Owned = nil -- this character's bags and bank only
	W.bags[0] = {[1] = {id = 2841, count = 2}}
	W.bags[6] = {[1] = {id = 2841, count = 1}} -- in the bank
	T.check("owned: bags + bank", X.QueueOwned(2841), 3)
	X.QueueSet(2, "restock", 7) -- Bronze: one craft makes 2
	X.QueueSet(1, "craft", 4)   -- Copper Bar: craft 4 times
	X.QueueSet(3, "restock", 2) -- potion, none owned
	X.QueueSet(999, "craft", 3) -- not a recipe: refused
	T.check("queue count", X.QueueCount(), 3)
	local rows = X.QueueRows()
	local bronze, copper, potion = rowOf(rows, 2), rowOf(rows, 1), rowOf(rows, 3)
	T.check("bronze: have", bronze and bronze.have, 3)
	T.check("bronze: makes 2 a craft", bronze and bronze.makes, 2)
	T.check("bronze: (7 - 3) / 2 = 2 crafts", bronze and bronze.craft, 2)
	T.near("bronze: profit = 2 crafts x 2 x (47.5 - 25)", bronze and bronze.profit, 90, 0.01)
	T.check("copper: craft mode = the number", copper and copper.craft, 4)
	T.near("copper: profit = 4 x (28.5 - 10)", copper and copper.profit, 74, 0.01)
	T.check("potion: 2 crafts", potion and potion.craft, 2)
	X.QueueSet(2, "restock", 5)
	T.check("bronze target 5: ceil(2 / 2) = 1 craft", rowOf(X.QueueRows(), 2).craft, 1)
	X.QueueSet(2, "restock", 3)
	T.check("bronze target reached: 0 crafts", rowOf(X.QueueRows(), 2).craft, 0)
	T.check("bronze target reached: profit 0", rowOf(X.QueueRows(), 2).profit, 0)
	-- with the inventory part: every character's count
	X.Owned = function(id) if id == 2841 then return 10, {} end return 0, {} end
	X.QueueSet(2, "restock", 7)
	T.check("X.Owned used when it exists", rowOf(X.QueueRows(), 2).have, 10)
	T.check("X.Owned: target reached", rowOf(X.QueueRows(), 2).craft, 0)
	X.Owned = owned
	-- taking out
	X.QueueSet(3, "restock", 0)
	T.check("number 0 takes it out", X.QueueGet(3), nil)
	-- survives a reload
	X = W.reload()
	T.check("after reload: the queue is kept", X.QueueCount(), 2)
	T.check("after reload: mode kept", X.QueueGet(1) and X.QueueGet(1).mode, "craft")
end)

T.scene("queue: materials minus what you own, vendor reagents, shopping list", function()
	local X = W.start()
	craftWorld(X)
	local owned, shopAdd = X.Owned, X.ShopAdd
	X.Owned = nil
	X.QueueSet(2, "restock", 4)  -- bronze: 2 crafts
	X.QueueSet(1, "craft", 4)    -- copper bar: 4 crafts
	X.QueueSet(3, "restock", 2)  -- potion: 2 crafts
	W.bags[0] = {[1] = {id = 2840, count = 1}, [2] = {id = 765, count = 5}} -- 1 Copper Bar, 5 Silverleaf
	local mats, totals = X.QueueMaterials()
	local bar, tin, ore, vial, leaf = matOf(mats, 2840), matOf(mats, 3576), matOf(mats, 2770), matOf(mats, 3371), matOf(mats, 765)
	T.check("copper bar: need 2, own 1, buy 1", bar and (bar.need .. "/" .. bar.have .. "/" .. bar.buy), "2/1/1")
	T.check("copper bar: cheapest is crafting it", bar and bar.how, "craft")
	T.check("tin bar: buy 2 at 40c", tin and (tin.buy .. "/" .. tin.unit .. "/" .. tin.total), "2/40/80")
	T.check("copper ore: 4 for the 4 copper crafts", ore and ore.buy, 4)
	T.check("silverleaf: owned, nothing to buy", leaf and leaf.buy, 0)
	T.check("vial: from the vendor", vial and vial.how, "vendor")
	T.check("vial: the vendor's name", vial and vial.vendor, "Alchemy Supplies")
	local list = totals.vendor["Alchemy Supplies"]
	T.check("vendor list: the vial", list and #list == 1 and list[1].id, 3371)
	T.near("total to buy: 10 + 80 + 40 + 2 x 20 + 2 x 4", totals.cost, 10 + 80 + 40 + 40 + 8, 0.01)
	-- the shopping list (the shopping part may not be there: a stand-in records the calls)
	local calls = {}
	X.ShopAdd = function(list, key, qty, max) calls[#calls + 1] = {list = list, key = key, qty = qty, max = max} end
	T.check("send to shopping list: every reagent to buy but the vendor's", X.QueueToShop(), 4)
	local tinCall
	for _, c in ipairs(calls) do if c.key == "3576" then tinCall = c end end
	T.check("shopping list name", calls[1] and calls[1].list, "Crafting queue")
	T.check("tin: 2 at most 120% of 40c", tinCall and (tinCall.qty .. "/" .. tinCall.max), "2/48")
	for _, c in ipairs(calls) do T.ok("no vendor reagent on the list", c.key ~= "3371") end
	X.ShopAdd = nil
	T.check("no shopping part: nothing sent", X.QueueToShop(), nil)
	X.ShopAdd, X.Owned = shopAdd, owned
	-- the Queue view of the Crafting tab
	X.UI.Open("craft")
	W.advance(0.5)
	local tab = X.UI.tabs.craft.panel
	W.click("Queue (", tab)
	W.advance(0.5)
	local text = W.screen(tab)
	T.ok("queue view: summary", text:find("3 recipes in the queue", 1, true) ~= nil, text)
	T.ok("queue view: vendor line", text:find("Alchemy Supplies:", 1, true) ~= nil, text)
	T.ok("queue view: shopping button hidden without the shopping part", W.findButton("Send to shopping list", tab) == nil or X.ShopAdd ~= nil)
	-- + and - on a row, x takes it out
	local before = X.QueueGet(1).n
	W.click("+", tab)
	W.advance(0.5)
	T.check("+ adds one", X.QueueGet(1).n, before + 1)
	W.click("-", tab)
	W.advance(0.5)
	T.check("- takes one off", X.QueueGet(1).n, before)
	W.click("Recipes", tab)
	W.advance(0.5)
	T.check("back to the recipes view", X.S().craftView, "recipes")
end)

T.scene("queue: craft next only on a click, counts down", function()
	local X = W.start()
	craftWorld(X)
	X.QueueSet(2, "craft", 3)    -- bronze 3 times
	X.QueueSet(3, "restock", 2)  -- potions (alchemy)
	local row, why = X.CraftNextTarget()
	T.ok("no profession window: nothing", row == nil and why:find("Open your profession", 1, true) ~= nil, why)
	W.openProfession("Mining")
	W.advance(2)
	W.give(2840, 2) W.give(3576, 5)
	row, why = X.CraftNextTarget()
	T.check("mining window: bronze next", row and row.rid, 2)
	T.check("as many as the bags allow (2 of 3)", why, 2)
	-- not from a click: the game refuses (the stand-in errors, XNAH says so)
	X.CraftNext()
	T.check("outside a click: nothing crafted", #W.crafted, 0)
	T.ok("outside a click: XNAH says it could not", #W.said("could not start crafting") == 1, W.lastSaid())
	-- the button
	X.UI.Open("craft")
	W.advance(0.5)
	local tab = X.UI.tabs.craft.panel
	W.click("Queue (", tab)
	W.advance(0.5)
	W.craftCasts = true
	W.click("Craft next", tab)
	T.check("one click: one CraftRecipe", #W.crafted, 1)
	T.check("CraftRecipe: bronze x2", W.crafted[1] and (W.crafted[1].rid .. "x" .. W.crafted[1].count), "2x2")
	W.advance(5)
	T.check("two casts done: 1 left", X.QueueGet(2) and X.QueueGet(2).n, 1)
	T.check("the bars made arrived", W.bagCount(2841), 4)
	row, why = X.CraftNextTarget()
	T.ok("no bars left: told so", row == nil and why:find("Not enough reagents", 1, true) ~= nil, why)
	W.give(2840, 1) W.give(3576, 1)
	W.advance(1)
	W.click("Craft next", tab)
	T.check("second click: one more call", #W.crafted, 2)
	W.advance(3)
	T.check("all 3 crafted: out of the queue", X.QueueGet(2), nil)
	T.check("restock row still there", X.QueueGet(3) ~= nil, true)
	-- a linked (someone else's) window: never
	W.closeProfession()
	W.openProfession("Alchemy", true)
	W.advance(2)
	row, why = X.CraftNextTarget()
	T.ok("linked window: not crafted from", row == nil and why:find("someone else", 1, true) ~= nil, why)
end)
