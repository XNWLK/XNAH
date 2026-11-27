-- XNAH test scenes, part 32: double-clicking an item on the tracked list (Items view) searches it in the game's own
-- auction house window. While that window shows its list of items, XNAH puts the name into its search box and sends
-- the server the same kind of search the game's Search button sends (C_AuctionHouse.SendBrowseQuery); the game's own
-- list fills itself from the answer. On an item's page XNAH only puts the name into the box and you press Enter
-- (going back to the list is a view switch only the game may make). XNAH never calls the game's window functions or
-- presses its buttons (that can make the game refuse its own protected actions later; tools/tests-38-taint.lua).
-- A single click still only shows it in XNAH. The window is the detailed stand-in of tools/world-ahpanel.lua, which
-- writes down every call made on it (W.ahFrame.calls) and every browse search sent (W.browseQueries).

local function has(text, part) return tostring(text or ""):find(part, 1, true) ~= nil end

-- 20 days of history at a usual price, then a price now
local function history(X, key, usual, minNow, name)
	local now = X.Now()
	for d = 20, 1, -1 do X.Record(key, now - d * 86400, usual, usual, 100, 10, name, 1) end
	X.Record(key, now, minNow, usual, 100, 10, name, 1)
end

local function setup()
	local X = W.start()
	history(X, "2589", 50, 40, "Linen Cloth")
	history(X, "15210:-19", 50000, 60000, "Raider Shortsword of the Bear")
	history(X, "4306", 1000, 900, "Silk Cloth")
	for _, key in ipairs({"2589", "15210:-19", "4306"}) do X.SetWatched(key, true) end
	-- what the auction house has (the stand-in server answers the searches from this)
	W.list(2589, 40, 20, 3)
	W.list(4306, 900, 20, 2)
	W.list(15210, 60000, 1, 1, nil, -19)
	W.ahWindow()
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	return X, X.UI.tabs.items.panel
end

-- the row frame of the tracked list that shows `key`
local function rowOf(panel, key)
	for i, r in ipairs(panel.tbl.items) do
		if r.key == key then return panel.tbl.rows[i - panel.tbl.offset] end
	end
end

local function clear(t) for i = #t, 1, -1 do t[i] = nil end end
-- a double-click, then a moment (XNAH's own search of the item just shown may keep the server busy for a moment)
local function dbl(row) row:DoubleClick("LeftButton") W.advance(0.3) end

-- a table and everything in it as one line of text (keys sorted), to compare before / after
local function dump(v, depth)
	if type(v) ~= "table" then return tostring(v) end
	if (depth or 0) > 6 then return "{...}" end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. dump(x, (depth or 0) + 1) end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- the names on the game's own list of items, as it shows them
local function listNames()
	local out = {}
	for _, row in ipairs(W.ahLists.browse.ScrollBox.frames) do
		local d = row.rowData
		out[#out + 1] = W.itemName(d.itemKey.itemID, d.itemKey.itemSuffix) or "?"
	end
	return table.concat(out, ", ")
end

T.scene("dblclick: on the auction house's list a tracked item is searched there (goods with one price each)", function()
	local X, panel = setup()
	local f = W.ahFrame
	local row = rowOf(panel, "2589")
	T.ok("the row is on screen", row ~= nil)
	if not row then return end
	-- a single click: only XNAH shows it, nothing is asked of the game's window
	X.UI.ShowItem("4306")
	clear(f.calls)
	row:Click("LeftButton")
	T.check("single click: shown in XNAH", X.UI.itemKey, "2589")
	T.check("single click: the game's window left alone", table.concat(f.calls, " | "), "")
	T.check("single click: no search", #W.browseQueries, 0)
	-- a double-click: the name in the game's search box and the search sent, nothing else asked of the window
	clear(f.calls)
	local opens = 0
	local open = X.UI.Open
	X.UI.Open = function(...) opens = opens + 1 return open(...) end
	dbl(row)
	T.check("none of the game's window functions called", table.concat(f.calls, " | "), "")
	T.check("search box text", f.SearchBar.SearchBox.text, "Linen Cloth")
	T.check("one search sent", #W.browseQueries, 1)
	local q = W.browseQueries[1] or {}
	T.check("searched for its name", q.searchString, "Linen Cloth")
	T.ok("the search box is not left with the keyboard", W.focus ~= f.SearchBar.SearchBox)
	T.check("the game's window stays on its list", f.displayMode.name, "Buy")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	T.check("chat: searching", #W.said("searching the auction house for Linen Cloth."), 1)
	T.check("chat: no press Enter", #W.said("press Enter"), 0)
	W.advance(1)
	T.check("the game's own list shows the answer", listNames(), "Linen Cloth")
	T.check("still the same item in XNAH", X.UI.itemKey, "2589")
	T.check("on the Items view", X.UI.current, "items")
	T.check("XNAH's view opened once (by the first press only)", opens, 1)
	T.check("no chat line", #W.said("open the auction house first"), 0)
	X.UI.Open = open
	-- another item: a new search, the list follows
	dbl(rowOf(panel, "4306"))
	W.advance(1)
	T.check("second double-click: its search", (W.browseQueries[2] or {}).searchString, "Silk Cloth")
	T.check("second double-click: the game's list follows", listNames(), "Silk Cloth")
	-- the game's window on its Sell tab (no search box there): the name in chat, the tab stays, no search
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemSell)
	clear(f.calls)
	dbl(row)
	T.check("Sell tab: nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("Sell tab: the tab stays", f.displayMode.name, "ItemSell")
	T.check("Sell tab: no search", #W.browseQueries, 2)
	T.check("Sell tab: type it in", #W.said("type Linen Cloth into the auction house search box (on its Buy tab) and press Enter."), 1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: on an item's page the name goes into the box and Enter searches", function()
	local X, panel = setup()
	local f = W.ahFrame
	-- the game shows the listings of one item (its page; the search bar is still there)
	W.ahRows("browse", {W.ahBrowseResult(15210, 60000, 1, -19)})
	W.ahClickRow(1)
	T.check("the game's window on an item's page", f.displayMode.name, "ItemBuy")
	clear(f.calls)
	dbl(rowOf(panel, "2589"))
	T.check("nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("the page stays (no view switch by XNAH)", f.displayMode.name, "ItemBuy")
	T.check("no search sent by XNAH", #W.browseQueries, 0)
	T.check("its name in the search box", f.SearchBar.SearchBox.text, "Linen Cloth")
	T.ok("the search box has the keyboard (Enter searches)", W.focus == f.SearchBar.SearchBox)
	local said = W.said("Linen Cloth is in the auction house search box - press Enter to search")
	T.check("one chat line: press Enter", #said, 1)
	T.ok("it says why", said[1] and has(said[1], "only while the auction house shows its list of items, not an item's page"), said[1])
	-- back on the list (the game's own Back button): the double-click searches again
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	dbl(rowOf(panel, "2589"))
	T.check("back on the list: searched", #W.browseQueries, 1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: gear with a suffix: its full name is searched", function()
	local X, panel = setup()
	local f = W.ahFrame
	local row = rowOf(panel, "15210:-19")
	T.ok("the row is on screen", row ~= nil)
	if not row then return end
	clear(f.calls)
	dbl(row)
	T.check("nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("its name with the suffix", f.SearchBar.SearchBox.text, "Raider Shortsword of the Bear")
	T.check("searched with the suffix", (W.browseQueries[1] or {}).searchString, "Raider Shortsword of the Bear")
	T.check("the game's window stays on its list", f.displayMode.name, "Buy")
	T.check("shown in XNAH", X.UI.itemKey, "15210:-19")
	W.advance(1)
	T.check("the game's list shows it", listNames(), "Raider Shortsword of the Bear")
	W.fire("ITEM_SEARCH_RESULTS_UPDATED")
	W.advance(1)
	T.check("still the same item", X.UI.itemKey, "15210:-19")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	-- a right double-click does nothing more than the right-click menu
	clear(f.calls)
	row:DoubleClick("RightButton")
	T.check("right double-click: the game's window left alone", #f.calls, 0)
	T.check("right double-click: no search", #W.browseQueries, 1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: the search uses the game's own filters and order, in every category", function()
	local X, panel = setup()
	local env = W.env
	-- Xn's choices on the game's filter button, a column clicked on its list, a category picked on its left
	env.g_auctionHouseFilters.minLevel, env.g_auctionHouseFilters.maxLevel = 10, 40
	env.g_auctionHouseFilters.filters[2] = true  -- usable only
	env.g_auctionHouseFilters.filters[6] = false -- no poor items
	env.g_auctionHouseSortsBySearchContext[0] = {{sortOrder = 1, reverseSort = true}, {sortOrder = 0, reverseSort = false}}
	W.ahFrame.CategoriesList.selectedCategoryIndex = 2
	local before = W.deepCopy({env.g_auctionHouseFilters, env.g_auctionHouseSortsBySearchContext, env.AuctionCategories})
	dbl(rowOf(panel, "2589"))
	local q = W.browseQueries[1] or {}
	T.check("level range", tostring(q.minLevel) .. "-" .. tostring(q.maxLevel), "10-40")
	T.check("filters that are on", table.concat(q.filters or {}, ","), "2,7,8,9,10,11,12")
	T.check("order: name (reversed) first", tostring((q.sorts or {})[1] and q.sorts[1].sortOrder) .. tostring((q.sorts or {})[1] and q.sorts[1].reverseSort), "1true")
	T.check("every category (none picked in the search)", q.itemClassFilters, nil)
	T.ok("XNAH's own tables, not the game's", q.filters ~= env.g_auctionHouseFilters.filters and q.sorts ~= env.g_auctionHouseSortsBySearchContext[0])
	local after = W.deepCopy({env.g_auctionHouseFilters, env.g_auctionHouseSortsBySearchContext, env.AuctionCategories})
	T.check("the game's settings unchanged", dump(after), dump(before))
	T.check("the category picked stays", W.ahFrame.CategoriesList.selectedCategoryIndex, 2)
	-- the game's tables missing (changed in a patch): the plain search, price then name
	env.g_auctionHouseFilters, env.g_auctionHouseSortsBySearchContext = nil, nil
	dbl(rowOf(panel, "4306"))
	local q2 = W.browseQueries[2] or {}
	T.check("no settings: still searched", q2.searchString, "Silk Cloth")
	T.check("no settings: no level range", tostring(q2.minLevel) .. "-" .. tostring(q2.maxLevel), "0-0")
	T.check("no settings: price, then name", tostring(q2.sorts and q2.sorts[1].sortOrder) .. tostring(q2.sorts and q2.sorts[2].sortOrder), "01")
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: while the server is busy XNAH waits a moment; typing meanwhile wins", function()
	local X, panel = setup()
	local f = W.ahFrame
	local box = f.SearchBar.SearchBox
	-- busy for a second: the search goes out once the server is ready
	W.throttleUntil = W.NOW + 1
	dbl(rowOf(panel, "2589"))
	T.check("busy: not sent yet", #W.browseQueries, 0)
	T.check("busy: the name already in the box", box.text, "Linen Cloth")
	W.advance(1.5)
	T.check("ready: sent", #W.browseQueries, 1)
	T.check("ready: one chat line", #W.said("searching the auction house for Linen Cloth."), 1)
	-- busy, and you type something else meanwhile: XNAH leaves your search alone
	W.throttleUntil = W.NOW + 1
	dbl(rowOf(panel, "4306"))
	box:SetText("Wool")
	W.advance(1.5)
	T.check("typed meanwhile: nothing sent", #W.browseQueries, 1)
	T.check("typed meanwhile: your text stays", box.text, "Wool")
	-- busy, and a second double-click before the first went out: only the second is searched
	W.throttleUntil = W.NOW + 1
	dbl(rowOf(panel, "4306"))
	dbl(rowOf(panel, "2589"))
	W.advance(1.5)
	T.check("two quick double-clicks: one search", #W.browseQueries, 2)
	T.check("two quick double-clicks: the last one", (W.browseQueries[2] or {}).searchString, "Linen Cloth")
	-- busy for long: XNAH gives up and asks for Enter
	W.throttleUntil = W.NOW + 60
	dbl(rowOf(panel, "4306"))
	W.advance(5)
	T.check("busy for long: nothing sent", #W.browseQueries, 2)
	T.check("busy for long: press Enter", #W.said("the auction house is busy - Silk Cloth is in its search box: press Enter to search."), 1)
	T.ok("busy for long: the box has the keyboard", W.focus == box)
	-- busy, and the game's window moves to an item's page meanwhile: press Enter instead
	W.throttleUntil = W.NOW + 1
	dbl(rowOf(panel, "2589"))
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemBuy)
	W.advance(1.5)
	T.check("page changed meanwhile: nothing sent", #W.browseQueries, 2)
	T.check("page changed meanwhile: press Enter", #W.said("Linen Cloth is in the auction house search box - press Enter to search"), 1)
	-- busy, and the auction house closed meanwhile: nothing more
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.throttleUntil = W.NOW + 1
	dbl(rowOf(panel, "4306"))
	W.closeAH()
	W.advance(1.5)
	T.check("closed meanwhile: nothing sent", #W.browseQueries, 2)
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: auction house closed - one chat line, still shown in XNAH", function()
	local X, panel = setup()
	W.closeAH()
	W.advance(0.3)
	X.UI.Open("items")
	W.advance(0.3)
	local f = W.ahFrame
	clear(f.calls)
	local row = rowOf(panel, "4306")
	T.ok("the row is on screen", row ~= nil)
	if not row then return end
	row:DoubleClick("LeftButton")
	T.check("shown in XNAH", X.UI.itemKey, "4306")
	T.check("the game's window left alone", #f.calls, 0)
	T.check("no search", #W.browseQueries, 0)
	local said = W.said("open the auction house first, then double-click again.")
	T.check("one chat line", #said, 1)
	T.ok("from XNAH", said[1] and has(said[1], "XNAH"), said[1])
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: a changed game window never throws an error; hints; other lists unchanged", function()
	local X, panel = setup()
	local f = W.ahFrame
	-- the server's search function changed in a patch: it fails - the name stays in the box, press Enter
	local send = W.env.C_AuctionHouse.SendBrowseQuery
	W.env.C_AuctionHouse.SendBrowseQuery = function() error("changed by a patch") end
	local row = rowOf(panel, "2589")
	local ok = pcall(row.DoubleClick, row, "LeftButton")
	W.advance(0.3)
	T.ok("search fails: no error from the double-click", ok)
	T.check("search fails: press Enter", #W.said("Linen Cloth is in the auction house search box - press Enter to search."), 1)
	W.env.C_AuctionHouse.SendBrowseQuery = send
	-- the game's window changed in a patch: its functions fail
	f.SearchBar.SearchBox.SetText = function() error("changed by a patch") end
	ok = pcall(row.DoubleClick, row, "LeftButton")
	T.ok("no error from the double-click", ok)
	T.check("no errors shown", #W.errors, 0)
	T.check("still shown in XNAH", X.UI.itemKey, "2589")
	T.check("the name in chat instead", #W.said("type Linen Cloth into the auction house search box"), 1)
	T.check("box not filled: no search", #W.browseQueries, 0)
	-- the hint on the row's tooltip and in the empty Items view
	W.hover(row)
	local lines = {}
	for _, l in ipairs(W.env.GameTooltip.lines or {}) do lines[#lines + 1] = W.plain(tostring(l[1])) end
	T.ok("row tooltip: the double-click", has(table.concat(lines, "\n"), "Double-click"), table.concat(lines, " / "))
	W.unhover(row)
	T.ok("Items view hint", has(panel.hint.text, "Double-click an item on the left"), panel.hint.text)
	-- the Market list: no double-click (a click there moves to the Items view)
	X.UI.Open("market")
	W.advance(0.3)
	for _, view in ipairs({"market"}) do
		local tbl = X.UI.tabs[view].panel.tbl
		local any = false
		for _, r in ipairs(tbl and tbl.rows or {}) do if r.scripts.OnDoubleClick then any = true end end
		T.ok(view .. ": no double-click", tbl ~= nil and not any)
	end
end)
