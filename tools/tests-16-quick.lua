-- XNAH test scenes, part 16: quick search (alt-click, the title bar's Find box) and window comfort (size, remembered
-- sorting and filters, copy a list as text).

T.scene("quick: alt-click an item and the Find box", function()
	local X = W.start()
	X.Record("2589", X.Now(), 50, 50, 60, 3, "Linen Cloth", 1)
	X.UI.Open("market")
	W.advance(0.3)
	-- alt-click a link: the item page opens
	W.alt = true
	W.env.HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
	W.alt = false
	T.check("alt-click opens the item page", X.UI.current, "items")
	T.check("for that item", X.UI.itemKey, "2589")
	-- shift-click (linking in chat) does nothing here
	X.UI.Open("market")
	W.shift = true
	W.env.HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
	W.shift = false
	T.check("shift-click left alone", X.UI.current, "market")
	-- the setting turns it off
	X.S().quickAltClick = false
	W.alt = true
	W.env.HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r")
	W.alt = false
	T.check("off: nothing", X.UI.current, "market")
	X.S().quickAltClick = true
	-- the Find box: items first, also items only the recipe list knows, then recipes
	local hits = X.QuickFind("linen cloth", 20)
	T.check("exact name first", hits[1] and hits[1].key, "2589")
	local bolt, recipe = false, false
	for _, h in ipairs(hits) do
		if h.key == "2996" then bolt = true end
		if h.rid then recipe = true end
	end
	T.ok("an item only the recipe list knows (Bolt of Linen Cloth)", bolt)
	hits = X.QuickFind("enchant bracer", 20)
	T.ok("recipes by name", hits[1] and hits[1].rid ~= nil, hits[1] and hits[1].text)
	T.check("too short: nothing", #X.QuickFind("l"), 0)
	-- typing in the box and pressing Enter opens the best match
	local box = X.UI.QuickBox
	T.ok("the box is in the title bar", box ~= nil)
	box:SetText("Linen Cloth")
	box.scripts.OnEnterPressed(box)
	T.check("Enter opens it", X.UI.itemKey, "2589")
	T.check("and empties the box", box:GetText(), "")
end)

T.scene("window: size, remembered sorting and filters, copy as text", function()
	local X = W.start()
	for i, p in ipairs({{"2589", 50, "Linen Cloth"}, {"2770", 10, "Copper Ore"}, {"2840", 60, "Copper Bar"}}) do
		X.Record(p[1], X.Now(), p[2], p[2], 50 * i, 3, p[3], 1)
	end
	X.UI.Open("market")
	W.advance(1)
	-- size
	X.UI.SetScale(1.25)
	T.check("size saved", X.S().uiScale, 1.25)
	T.check("window drawn bigger", X.UI.Frame():GetScale(), 1.25)
	X.UI.SetScale(5)
	T.check("not bigger than 160%", X.S().uiScale, 1.6)
	X.UI.SetScale(1)
	W.env.SlashCmdList.XNAH("size 90")
	T.check("/xnah size", X.S().uiScale, 0.9)
	X.UI.SetScale(1)
	-- sorting: pick a column, it is remembered after a reload
	local tbl = X.UI.tabs.market.panel.tbl
	T.ok("the Market table remembers under a page key", tbl.saveKey ~= nil and tbl.saveKey:find("^market:") ~= nil, tbl.saveKey)
	local col = 2
	tbl.sortCol, tbl.sortDesc = nil, true
	local saveKey = tbl.saveKey
	X.S().sorts[saveKey] = {col, false}
	-- filters
	X.S().marketFilter = {text = "copper", watch = false, listed = true, craft = false}
	X = W.reload()
	X.UI.Open("market")
	W.advance(1)
	tbl = X.UI.tabs.market.panel.tbl
	T.check("sort column back", tbl.sortCol, col)
	T.check("sort direction back", tbl.sortDesc, false)
	T.check("search text back", X.UI.tabs.market.panel.search:GetText(), "copper")
	-- copy as text: one line per row, columns split by tabs, no colour codes
	local text, n = tbl:AsText()
	T.ok("rows copied", n >= 1, n)
	T.ok("header line", text:find("^[^\n]*\t") ~= nil, text)
	T.ok("no colour codes", text:find("|c", 1, true) == nil, text)
	T.ok("item names in it", text:find("Copper", 1, true) ~= nil, text)
end)
