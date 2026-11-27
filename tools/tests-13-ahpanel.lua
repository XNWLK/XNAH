-- XNAH test scenes, part 13: XNAH and the game's auction house window (AHPanel.lua) - the item picked in the game's
-- window is shown in XNAH's window (Items view), and the extra columns in the game's lists. The window is the
-- detailed stand-in of tools/world-ahpanel.lua.

-- 20 days of history at a usual price (market value) of `usual`, then a price now
local function history(X, key, usual, minNow, name)
	local now = X.Now()
	for d = 20, 1, -1 do X.Record(key, now - d * 86400, usual, usual, 100, 10, name, 1) end
	X.Record(key, now, minNow, usual, 100, 10, name, 1)
end

-- the text of XNAH's column overlay on a row of the game's list (nil when there is none or it is hidden)
local function columns(row)
	local isCell = {}
	for _, c in ipairs(row.cells) do isCell[c] = true end
	for _, c in ipairs(row.children) do
		if not c.region and not isCell[c] then
			if not c:IsVisible() then return nil end
			local parts = {}
			for _, r in ipairs(c.children) do if r.kind == "FontString" then parts[#parts + 1] = W.plain(r.text) end end
			return table.concat(parts, " | "), c
		end
	end
	return nil
end
local function colour(row)
	local _, o = columns(row)
	for _, r in ipairs(o and o.children or {}) do
		if r.kind == "FontString" then return tostring(r.text):match("^|cff(%x%x%x%x%x%x)") end
	end
end

local function setup()
	local X = W.start()
	history(X, "2589", 50, 40, "Linen Cloth")
	history(X, "15210:-19", 50000, 60000, "Raider Shortsword of the Bear")
	history(X, "4306", 1000, 900, "Silk Cloth")
	X.SaleRate = function(key) if key == "2589" then return 3.5, 48 end return nil end
	W.ahWindow()
	W.openAH()
	W.advance(0.5)
	return X
end

T.scene("ah panel: an item picked in the game's auction house window shows in XNAH's window", function()
	local X = setup()
	local f = X.UI.Frame()
	T.ok("XNAH's window opened beside the auction house", f and f:IsShown())
	T.ok("no panel beside the window any more", W.env.XNAHAuctionPanel == nil)
	-- the game's list: Linen Cloth (stackable) and a sword with a suffix
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	W.ahClickRow(1)
	T.check("the stackable item", X.AHPanel.key, "2589")
	T.check("the game still opened its listings page", W.ahFrame.displayMode.name, "CommoditiesBuy")
	W.advance(0.5)
	T.check("XNAH shows it", X.UI.itemKey, "2589")
	T.check("on the Items view", X.UI.current, "items")
	local panel = X.UI.tabs.items.panel
	T.ok("its name in the analysis", W.plain(panel.name.text):find("Linen Cloth", 1, true) ~= nil, panel.name.text)

	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahClickRow(2)
	T.check("the sword with its suffix", X.AHPanel.key, "15210:-19")
	T.check("its gear listings page", W.ahFrame.displayMode.name, "ItemBuy")
	T.check("XNAH shows the sword", X.UI.itemKey, "15210:-19")

	-- another view in XNAH: picking an item in the game's window brings the Items view back
	X.UI.Select("market")
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahRows("browse", {W.ahBrowseResult(4306, 900, 20)})
	W.ahClickRow(1)
	W.advance(0.5)
	T.check("picked in the game's list", X.AHPanel.key, "4306")
	T.check("Items view again", X.UI.current, "items")
	T.check("showing it", X.UI.itemKey, "4306")

	-- an item looked at in XNAH, then the same item as before picked again in the game: shown again
	X.UI.ShowItem("2589")
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahClickRow(1)
	W.advance(0.5)
	T.check("picked again: shown again", X.UI.itemKey, "4306")
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})

	-- an item from the bags picked for posting
	W.ahFrame:SetPostItem({link = W.link(2589), id = 2589})
	T.check("item to post", X.AHPanel.key, "2589")
	T.check("shown", X.UI.itemKey, "2589")

	-- fallback: the game's search answer for the window's own item (as if a hook had missed it) ...
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.CommoditiesBuy)
	W.ahFrame.CommoditiesBuyFrame.ItemList.itemID = 2592 -- (the game keeps it there)
	W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2592)
	T.check("fallback: the window's item", X.AHPanel.key, "2592")
	-- ... but XNAH's own searches for other items do not move it
	X.UI.ShowItem("4306")
	W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2592)
	W.fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0})
	T.check("a search answer for the same item: XNAH stays on its item", X.UI.itemKey, "4306")

	-- XNAH's window closed by hand: a pick is kept for when it opens
	f:Hide()
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahClickRow(1)
	T.ok("closed: not opened by a pick", not f:IsShown())
	X.UI.Open()
	T.check("opened: that item", X.UI.itemKey, "2589")

	-- the auction house closes: XNAH's window (opened by hand now) stays; opens again: nothing picked yet
	W.closeAH()
	T.ok("opened by hand: stays", f:IsShown())
	W.openAH()
	W.advance(0.5)
	T.check("starts with nothing picked", X.AHPanel.key, nil)
end)

T.scene("ah panel: extra columns in the game's lists", function()
	local X = setup()
	-- the item list: % of usual (from the game's own lowest price) and sells a day
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19), W.ahBrowseResult(2592, 10, 0),
		W.ahBrowseResult(424242, 99, 5)})
	local rows = W.ahLists.browse.ScrollBox.frames
	T.check("cheaper than usual, sells a day", columns(rows[1]), "80% | 3.5")
	T.check("green", colour(rows[1]), "4ade80")
	T.check("dearer than usual", columns(rows[2]), "120% | -")
	T.check("red", colour(rows[2]), "f87171")
	T.check("none listed / unknown item", columns(rows[3]), "- | -")
	T.check("an item XNAH does not know", columns(rows[4]), "- | -")
	local _, o = columns(rows[1])
	T.ok("at the right end of the name column", o.points[1] and o.points[1][2] == rows[1] and o.points[1][4] == 444, o.points[1] and o.points[1][4])
	T.ok("above the game's cells", (o.level or 0) > (rows[1].level or 1))
	T.ok("a light band behind short names", o.children[1].color and o.children[1].color[4] < 0.5)
	-- the header: "% usual" and "a day" over the columns
	local hc = W.ahLists.browse.HeaderContainer
	local head
	for _, c in ipairs(hc.children) do if not c.region then head = c end end
	T.ok("header shown", head and head:IsVisible())
	local htext = {}
	for _, r in ipairs(head and head.children or {}) do if r.kind == "FontString" then htext[#htext + 1] = r.text end end
	T.check("header text", table.concat(htext, " | "), "% usual | a day")

	-- rows are re-used by the game for other items: the columns follow
	W.ahRows("browse", {W.ahBrowseResult(15210, 25000, 1, -19), W.ahBrowseResult(2589, 50, 300)})
	T.check("re-used row 1", columns(rows[1]), "50% | -")
	T.check("re-used row 2", columns(rows[2]), "100% | 3.5")
	-- a very long name runs under the columns: a darker band
	W.items[2589].name = "Linen Cloth With A Really Very Long Name Indeed To Fill"
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300)})
	_, o = columns(rows[1])
	T.ok("a dark band behind a long name", o.children[1].color and o.children[1].color[4] > 0.5)

	-- the gear listings: % of usual for each auction (buyout of one)
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemBuy)
	W.ahRows("item", {
		{itemKey = {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0}, buyoutAmount = 45000, quantity = 1, auctionID = 1},
		{itemKey = {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0}, bidAmount = 100, quantity = 1, auctionID = 2},
	})
	local irows = W.ahLists.item.ScrollBox.frames
	T.check("gear listing", columns(irows[1]), "90%")
	T.check("bid only: no price", columns(irows[2]), "-")
	-- the listings of a stackable item: % of usual for each price
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.CommoditiesBuy)
	W.ahRows("commodity", {{itemID = 2589, unitPrice = 45, quantity = 20, auctionID = 1}, {itemID = 2589, unitPrice = 75, quantity = 5, auctionID = 2}})
	local crows = W.ahLists.commodity.ScrollBox.frames
	T.check("commodity listing", columns(crows[1]), "90%")
	T.check("commodity listing, dearer", columns(crows[2]), "150%")

	-- new prices: the columns change (a moment later)
	history(X, "2589", 50, 40, nil)
	X.Record("2589", X.Now() + 60, 30, 30, 100, 10)
	X.Fire("XNAH_PRICES")
	W.advance(0.5)
	T.ok("after new prices", columns(crows[1]) ~= nil)

	-- switched off in the settings: gone; on again: back
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	X.UI.Open("scan")
	T.ok("the setting is in Settings", W.findButton("Extra columns in the auction house lists", X.UI.tabs.scan.panel) ~= nil)
	W.click("Extra columns in the auction house lists", X.UI.tabs.scan.panel)
	T.check("setting off", X.S().ahColumns, false)
	T.check("columns gone", columns(W.ahLists.browse.ScrollBox.frames[1]), nil)
	T.ok("header gone", not head:IsVisible())
	W.click("Extra columns in the auction house lists", X.UI.tabs.scan.panel)
	T.ok("columns back", columns(W.ahLists.browse.ScrollBox.frames[1]) ~= nil)
	-- the window closes: the column text goes with it
	W.closeAH()
	T.check("closed: no column text", columns(W.ahLists.browse.ScrollBox.frames[1]), nil)
end)

T.scene("ah panel: never writes into the game's window", function()
	local X = W.start()
	history(X, "2589", 50, 40, "Linen Cloth")
	local f = W.ahWindow()
	local L = W.ahLists
	-- every table of the game's window that XNAH sees, with the keys it has before XNAH looks at it
	local watched = {f, f.ItemBuyFrame, f.CommoditiesBuyFrame, f.BrowseResultsFrame, L.browse, L.item, L.commodity,
		L.browse.ScrollBox, L.item.ScrollBox, L.commodity.ScrollBox, L.browse.tableBuilder, L.browse.HeaderContainer}
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	for _, row in ipairs(L.browse.ScrollBox.frames) do
		watched[#watched + 1] = row
		for _, c in ipairs(row.cells) do watched[#watched + 1] = c end
	end
	-- the game's own fields (set by the stand-in itself while it works) and the frame internals of the test world
	local GAME = {itemKey = true, itemID = true, price = true, displayMode = true, postLoc = true, searchText = true, searched = true,
		updates = true, frames = true, rowData = true, level = true, text = true}
	local before = {}
	for i, t in ipairs(watched) do
		before[i] = {}
		for k in pairs(t) do before[i][k] = true end
	end
	W.openAH()
	W.advance(0.5)
	W.ahClickRow(1)
	W.ahFrame:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahClickRow(2)
	W.ahFrame:SetPostItem({link = W.link(2589), id = 2589})
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300)})
	X.Fire("XNAH_PRICES")
	W.advance(1)
	W.closeAH()
	local added = {}
	for i, t in ipairs(watched) do
		for k in pairs(t) do
			if not before[i][k] and not GAME[k] then added[#added + 1] = tostring(k) end
		end
	end
	T.check("no new fields in the game's tables", table.concat(added, ", "), "")
	T.ok("followed only with hooksecurefunc", (W.tableHooks or 0) >= 7, W.tableHooks)
	T.ok("XNAH's window is its own frame", W.env.XNAHFrame and W.env.XNAHFrame.parent == W.env.UIParent)
	T.ok("no panel beside the window any more", W.env.XNAHAuctionPanel == nil)
end)

T.scene("ah panel: a bare auction house window (pieces missing) does no harm", function()
	local X = W.start()
	W.openAH() -- the plain stand-in window: none of the game's pieces
	W.advance(4)
	T.ok("XNAH's window beside it", W.env.XNAHFrame and W.env.XNAHFrame:IsShown())
	X.Fire("XNAH_PRICES")
	W.advance(1)
	W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
	T.check("nothing picked", X.AHPanel.key, nil)
	W.closeAH()
	T.ok("closed with it", not W.env.XNAHFrame:IsShown())
end)
