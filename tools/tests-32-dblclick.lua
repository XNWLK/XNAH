-- XNAH test scenes, part 32: double-clicking an item on the tracked list (Items view) puts its name into the game's
-- own auction house search box (press Enter there to search). XNAH changes nothing else in the game's window (no tab
-- change, no listings page opened, no search started: that can make the game refuse its own protected actions later).
-- A single click still only shows it in XNAH. The window is the detailed stand-in of tools/world-ahpanel.lua, which
-- writes down every call made on it (W.ahFrame.calls).

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

T.scene("dblclick: a tracked item's name goes into the game's search box (goods with one price each)", function()
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
	-- a double-click: the name in the game's search box, nothing else changed there
	clear(f.calls)
	local opens = 0
	local open = X.UI.Open
	X.UI.Open = function(...) opens = opens + 1 return open(...) end
	row:DoubleClick("LeftButton")
	T.check("nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("search box text", f.SearchBar.SearchBox.text, "Linen Cloth")
	T.ok("the search box has the keyboard", W.focus == f.SearchBar.SearchBox)
	T.check("the game's window stays on its list", f.displayMode.name, "Buy")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	T.check("chat: press Enter", #W.said("Linen Cloth is in the auction house search box - press Enter to search."), 1)
	W.advance(1)
	T.check("still the same item in XNAH", X.UI.itemKey, "2589")
	T.check("on the Items view", X.UI.current, "items")
	T.check("XNAH's view opened once (by the first press only)", opens, 1)
	T.check("no chat line", #W.said("open the auction house first"), 0)
	X.UI.Open = open
	-- the game's window on its Sell tab (no search box there): the name in chat, the tab stays
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemSell)
	clear(f.calls)
	row:DoubleClick("LeftButton")
	T.check("Sell tab: nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("Sell tab: the tab stays", f.displayMode.name, "ItemSell")
	T.check("Sell tab: type it in", #W.said("type Linen Cloth into the auction house search box (on its Buy tab) and press Enter."), 1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: gear with a suffix: its full name goes into the search box", function()
	local X, panel = setup()
	local f = W.ahFrame
	local row = rowOf(panel, "15210:-19")
	T.ok("the row is on screen", row ~= nil)
	if not row then return end
	clear(f.calls)
	row:DoubleClick("LeftButton")
	T.check("nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("its name with the suffix", f.SearchBar.SearchBox.text, "Raider Shortsword of the Bear")
	T.check("the game's window stays on its list", f.displayMode.name, "Buy")
	T.check("shown in XNAH", X.UI.itemKey, "15210:-19")
	W.fire("ITEM_SEARCH_RESULTS_UPDATED")
	W.advance(1)
	T.check("still the same item", X.UI.itemKey, "15210:-19")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	-- a right double-click does nothing more than the right-click menu
	clear(f.calls)
	row:DoubleClick("RightButton")
	T.check("right double-click: the game's window left alone", #f.calls, 0)
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
	local said = W.said("open the auction house first, then double-click again.")
	T.check("one chat line", #said, 1)
	T.ok("from XNAH", said[1] and has(said[1], "XNAH"), said[1])
	T.check("no errors", #W.errors, 0)
end)

T.scene("dblclick: a changed game window never throws an error; hints; other lists unchanged", function()
	local X, panel = setup()
	local f = W.ahFrame
	-- the game's window changed in a patch: its functions fail
	f.SearchBar.SearchBox.SetText = function() error("changed by a patch") end
	local row = rowOf(panel, "2589")
	local ok = pcall(row.DoubleClick, row, "LeftButton")
	T.ok("no error from the double-click", ok)
	T.check("no errors shown", #W.errors, 0)
	T.check("still shown in XNAH", X.UI.itemKey, "2589")
	T.check("the name in chat instead", #W.said("type Linen Cloth into the auction house search box"), 1)
	-- the hint on the row's tooltip and in the empty Items view
	W.hover(row)
	local lines = {}
	for _, l in ipairs(W.env.GameTooltip.lines or {}) do lines[#lines + 1] = W.plain(tostring(l[1])) end
	T.ok("row tooltip: the double-click", has(table.concat(lines, "\n"), "Double-click: put its name in the auction house search box"),
		table.concat(lines, " / "))
	W.unhover(row)
	T.ok("Items view hint", has(panel.hint.text, "Double-click an item on the left: its name goes into the auction house search box"), panel.hint.text)
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
