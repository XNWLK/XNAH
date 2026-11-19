-- XNAH test scenes, part 3b: the recipe list (RecipeDB.lua, every recipe of the game) - "used in" shows
-- every recipe an item goes into, hovering one shows the whole recipe.

T.scene("recipe list: every recipe, used in, and the recipe tooltip", function()
	local X = W.start()
	T.ok("the list is loaded", X.RECIPE_DB ~= nil and X.RECIPE_DB[2329] ~= nil)
	local n = 0
	for _ in pairs(X.RECIPE_DB) do n = n + 1 end
	T.ok("over 2,000 recipes", n > 2000, n)
	local r = X.Recipe(2329)
	T.check("name", r and r.name, "Elixir of Minor Strength")
	T.check("profession", r and r.prof, "Alchemy")
	T.check("skill needed", r and r.la, 15)
	T.check("makes", r and r.out, 2454)
	T.check("reagents", r and #r.r, 3)
	T.check("first reagent", r and r.r[1][1] .. "x" .. r.r[1][2], "2449x1")
	T.check("skill-up levels", r and table.concat(r.colors, ","), "15,55,75,95")
	T.check("marked as from the list", r and r.db, true)
	-- an enchant makes no item
	local e = X.Recipe(7418)
	T.check("enchant: no item", e and e.out, nil)
	T.check("enchant: its title is the recipe name", X.RecipeTitle(7418), "Enchant Bracer - Inferior Stamina")
	-- used in: Copper Ore goes into Smelt Copper, Linen Cloth into many tailoring recipes
	T.ok("Copper Ore: Smelt Copper", X.Contains(X.RecipesUsing(2770), 2657) ~= nil)
	T.ok("Linen Cloth: many recipes", #X.RecipesUsing(2589) >= 10, #X.RecipesUsing(2589))
	T.ok("made by: Copper Bar", X.Contains(X.AllRecipesFor(2840), 2657) ~= nil)
	T.ok("crafting costs use the list too", X.Contains(X.RecipesFor(2840), 2657) ~= nil)
	T.check("posting floor: only recipes read in the game", #X.RecipesFor(2840, true), 0)
	-- names of items the game has not loaded come from the list
	T.check("name from the list", (X.ItemName("2454")), "Elixir of Minor Strength")

	-- the item page: a scrolling "used in" list; hover = the recipe
	W.list(2589, 50, 20, 3)
	X.Record("2589", X.Now(), 50, 50, 60, 3, "Linen Cloth", 1)
	X.UI.ShowItem("2589")
	W.advance(0.3)
	local panel = X.UI.tabs.item.panel
	local used = panel.used
	T.ok("used-in list filled", #used.items >= 10, #used.items)
	T.ok("title counts them", panel.uTitle:GetText():find(#used.items .. " recipes", 1, true) ~= nil, panel.uTitle:GetText())
	T.ok("it scrolls", used.track:IsShown())
	local row = used.rows[1]
	row.scripts.OnEnter(row)
	local text = {}
	for _, l in ipairs(W.env.GameTooltip.lines) do text[#text + 1] = table.concat(l, " | ") end
	text = table.concat(text, "\n")
	local first = X.Recipe(used.items[1].rid)
	if os.getenv and os.getenv("SHOWTIP") then print(text) end
	T.ok("tooltip: the recipe name", text:find(first.name, 1, true) ~= nil, text)
	T.ok("tooltip: Linen Cloth marked", text:find("> |r", 1, true) ~= nil, text)
	T.ok("tooltip: the cost", text:find("Cost of one craft", 1, true) ~= nil, text)
	T.ok("tooltip: the profession", text:find(first.prof, 1, true) ~= nil, text)
	-- an item made by a list recipe shows it in the crafting box
	X.UI.ShowItem("2840")
	W.advance(0.3)
	T.ok("crafting box: the list recipe", panel.cTitle:GetText():find("Smelt Copper", 1, true) ~= nil, panel.cTitle:GetText())
	T.ok("crafting box: from the recipe list", panel.cKnown:GetText():find("recipe list", 1, true) ~= nil, panel.cKnown:GetText())
end)

T.scene("recipe list: the crafting list uses every recipe, quickly", function()
	local X = W.start()
	-- prices of some reagents and products (most items have none: like a fresh install)
	for _, p in ipairs({{"2589", 50, "Linen Cloth"}, {"2996", 400, "Bolt of Linen Cloth"}, {"2770", 10, "Copper Ore"}, {"2840", 60, "Copper Bar"}}) do
		X.Record(p[1], X.Now(), p[2], p[2], 50, 3, p[3], 1)
	end
	local t0 = os.clock()
	local list = X.CraftList({})
	local first = os.clock() - t0
	T.ok("every recipe that makes an item is listed", #list > 1800, #list)
	local priced = 0
	for _, r in ipairs(list) do if r.cost then priced = priced + 1 end end
	T.ok("costs worked out", priced > 0, priced)
	T.check("Bolt of Linen Cloth costs 2 Linen", X.RecipeCost(2963), 100)
	t0 = os.clock()
	X.CraftList({})
	local again = os.clock() - t0
	if os.getenv and os.getenv("SHOWTIME") then print(string.format("craft list: %.3f s, again %.3f s (%d rows, %d priced)", first, again, #list, priced)) end
	T.ok("the second time is quicker (costs remembered)", again <= first + 0.05, first .. " / " .. again)
	-- the Craft tab: unknown recipes listed when "only mine" is off
	X.S().craftMine = false
	X.UI.Open("craft")
	W.advance(0.5)
	T.ok("Professions include the list's", X.Contains(X.Professions(), "Tailoring") ~= nil)
	-- posting floor ignores recipes nobody has read in the game
	T.check("no posting floor from list recipes", (X.CraftCost(2840, true)), nil)
end)
