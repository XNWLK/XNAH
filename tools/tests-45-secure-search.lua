-- XNAH test scenes, part 45: the double-click on a tracked item presses the game's OWN Search button of its auction
-- house, through a secure button of the game's kind (SecureActionButtonTemplate, type = "click", clickbutton = the
-- Search button: SearchClick.lua). The stand-in of that template and of combat is tools/world-secure.lua; the auction
-- house window (with its Search button and StartSearch, run as the game's own code) is tools/world-ahpanel.lua.
-- Checked: a click picks the item, a double-click searches through the secure button and the game's StartSearch runs
-- as the game's own code; nothing XNAH writes reaches the auction house's tables; right-click and dragging still work
-- through the button; in combat nothing of it changes (and it is placed again after combat); XNAH's own search of the
-- item waits for the double-click time and for the game's answer.
-- Every scene title starts with "45" (node tools/test.js 45).

local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
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
	W.list(2589, 40, 20, 3)
	W.list(4306, 900, 20, 2)
	W.list(15210, 60000, 1, 1, nil, -19)
	W.ahWindow()
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	return X, X.UI.tabs.items.panel, W.ahFrame
end
local function rowOf(panel, key)
	for i, r in ipairs(panel.tbl.items) do
		if r.key == key then return panel.tbl.rows[i - panel.tbl.offset] end
	end
end
local function clear(t) for i = #t, 1, -1 do t[i] = nil end end
-- the mouse onto a row: the row's hover lays the secure button over it, and the mouse is then on that button (as in
-- the game: the button is on top)
local function onRow(X, row)
	W.hover(row)
	local c = X.UI.SearchClickButton()
	if c and c:IsShown() then W.hover(c) end
	return c
end
local function click(c, button) W.mouseDown(c, 30, 10, button) W.mouseUp(button) end
local function dbl(c) click(c) W.advance(0.15) click(c) end
local function listNames()
	local out = {}
	for _, row in ipairs(W.ahLists.browse.ScrollBox.frames) do
		local d = row.rowData
		out[#out + 1] = W.itemName(d.itemKey.itemID, d.itemKey.itemSuffix) or "?"
	end
	return table.concat(out, ", ")
end
local function tipText()
	local out = {}
	for _, l in ipairs(W.env.GameTooltip.lines or {}) do out[#out + 1] = W.plain(table.concat(l, " ")) end
	return table.concat(out, "\n")
end
local function searchesOf(key)
	local n = 0
	for _, s in ipairs(W.searches) do if s.key == key then n = n + 1 end end
	return n
end

T.scene("45 secure search: a click picks, a double-click presses the game's own Search button", function()
	local X, panel, f = setup()
	local box = f.SearchBar.SearchBox
	T.ok("no secure button before the mouse is on a row", not (X.UI.SearchClickButton() and X.UI.SearchClickButton():IsShown()))
	local row = rowOf(panel, "2589")
	local c = onRow(X, row)
	T.ok("the mouse on a row: the secure button lies over it", c ~= nil and c:IsShown())
	if not c then return end
	T.ok("of the game's secure kind", c.protected == true and c.template == "SecureActionButtonTemplate")
	T.ok("a child of the whole screen, not of XNAH's window", c.parent == W.env.UIParent)
	local p = c.points[1]
	T.ok("placed by screen position only (never tied to XNAH's frames)", #c.points == 1 and p and p[2] == W.env.UIParent, #c.points)
	T.check("acts when the mouse button is let go, whatever the game's setting", c.attr and c.attr.useOnKeyDown, false)
	T.check("only clicks that let go reach it", table.concat(c.clicksFor or {}, ","), "LeftButtonUp,RightButtonUp")
	T.check("nothing set to happen yet", c.attr and c.attr.type, nil)
	T.ok("the game's own OnClick of the template is kept", c.scripts.OnClick == c.gameOnClick)
	T.ok("the row's tooltip shows (passed on to the row)", has(tipText(), "Linen Cloth"), tipText())
	T.ok("the tooltip says what the double-click does", has(tipText(), "Double-click"), tipText())
	-- a single click: picks the item, the secure part does nothing
	X.UI.ShowItem("4306")
	W.advance(1)
	clear(f.calls) clear(f.gameCalls)
	local before = #W.searches
	click(c)
	T.check("click: shown in XNAH", X.UI.itemKey, "2589")
	T.check("click: one press of the secure part", W.secureClicks, 1)
	T.check("click: it did nothing", #W.secureActions, 0)
	T.check("click: no search of the game's list", #W.browseQueries, 0)
	T.check("click: XNAH's own search of the item waits a moment (a double-click may follow)", #W.searches - before, 0)
	W.advance(0.8)
	T.ok("click: then the item is looked up (for Buy cheapest now)", searchesOf("2589") >= 1, #W.searches - before)
	T.check("click: nothing asked of the game's window", table.concat(f.calls, " | ") .. table.concat(f.gameCalls, " | "), "")
	-- a double-click: the name into the box, the game's own Search button pressed by the game
	X.UI.ShowItem("4306") -- (so the first press of the double-click picks it again and looks it up)
	W.advance(1)
	clear(f.calls) clear(f.gameCalls)
	before = searchesOf("2589")
	dbl(c)
	T.check("double-click: the name in the game's search box", box.text, "Linen Cloth")
	T.check("double-click: the secure part pressed a button", table.concat(W.secureActions, ","), "click")
	T.check("double-click: the game's own StartSearch ran, as the game's code", f.gameCalls[1], "search")
	T.check("double-click: XNAH called nothing of the game's window", table.concat(f.calls, " | "), "")
	local q = W.browseQueries[1] or {}
	T.check("double-click: one search of the game's list", #W.browseQueries, 1)
	T.check("double-click: searched for its name", q.searchString, "Linen Cloth")
	T.check("double-click: sent by the game's own code", q.byGame, true)
	T.check("double-click: the setting cleared again afterwards", c.attr.type, nil)
	T.check("double-click: one chat line", #W.said("searching the auction house for Linen Cloth."), 1)
	T.check("double-click: no press Enter", #W.said("press Enter"), 0)
	T.check("double-click: still the same item in XNAH", X.UI.itemKey, "2589")
	T.check("double-click: XNAH's own search of the item waits for the game's answer", searchesOf("2589") - before, 0)
	W.advance(1.2)
	T.check("the game's own list shows the answer", listNames(), "Linen Cloth")
	T.ok("after the answer: XNAH's own search of the item", searchesOf("2589") - before >= 1, searchesOf("2589") - before)
	-- a third click right after: a click again (no second search)
	click(c)
	W.advance(0.1)
	T.check("a third click: no new search", #W.browseQueries, 1)
	-- two clicks too far apart: two clicks
	W.advance(1)
	click(c)
	W.advance(0.8)
	click(c)
	T.check("clicks far apart: no search", #W.browseQueries, 1)
	-- quick clicks on two different items: no search
	W.advance(1)
	click(c)
	local c2 = onRow(X, rowOf(panel, "4306"))
	T.ok("the same button moves to the other row", c2 == c and c:IsShown())
	click(c)
	T.check("two different items: no search", #W.browseQueries, 1)
	T.check("two different items: the second one shown", X.UI.itemKey, "4306")
	-- the game's setting "act on key down" off: still once per click, the same double-click
	W.advance(1)
	W.useKeyDown = false
	local presses = W.secureClicks
	dbl(c)
	T.check("setting off: one secure press per click", W.secureClicks - presses, 2)
	T.check("setting off: searched", (W.browseQueries[2] or {}).searchString, "Silk Cloth")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	T.check("nothing refused by the game", table.concat(W.blocked, ", "), "")
	T.check("no errors", #W.errors, 0)
end)

T.scene("45 secure search: on an item's page the game goes back to its list; on the Sell tab the name is said", function()
	local X, panel, f = setup()
	W.ahRows("browse", {W.ahBrowseResult(15210, 60000, 1, -19)})
	W.ahClickRow(1)
	T.check("the game's window on an item's page", f.displayMode.name, "ItemBuy")
	clear(f.calls) clear(f.gameCalls)
	local c = onRow(X, rowOf(panel, "2589"))
	if not c then T.ok("a secure button", false) return end
	dbl(c)
	T.check("item page: searched by the game", (W.browseQueries[1] or {}).byGame, true)
	T.check("item page: the game went back to its list itself", f.displayMode.name, "Buy")
	T.ok("item page: that was the game's own code", has(table.concat(f.gameCalls, " | "), "mode Buy"), table.concat(f.gameCalls, " | "))
	T.check("item page: XNAH called nothing of the game's window", table.concat(f.calls, " | "), "")
	W.advance(1)
	T.check("item page: the list shows the answer", listNames(), "Linen Cloth")
	-- the Sell tab: no search box there - the name in chat, the tab stays, nothing pressed
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemSell)
	clear(f.calls) clear(f.gameCalls)
	W.advance(1)
	c = onRow(X, rowOf(panel, "2589"))
	local n = #W.secureActions
	dbl(c)
	T.check("Sell tab: nothing pressed", #W.secureActions, n)
	T.check("Sell tab: the tab stays", f.displayMode.name, "ItemSell")
	T.check("Sell tab: no search", #W.browseQueries, 1)
	T.check("Sell tab: type it in", #W.said("type Linen Cloth into the auction house search box (on its Buy tab) and press Enter."), 1)
	T.check("Sell tab: nothing asked of the game's window", table.concat(f.calls, " | ") .. table.concat(f.gameCalls, " | "), "")
	-- gear with a suffix: its full name
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.advance(1)
	c = onRow(X, rowOf(panel, "15210:-19"))
	dbl(c)
	T.check("suffix: its full name searched", (W.browseQueries[2] or {}).searchString, "Raider Shortsword of the Bear")
	T.check("no errors", #W.errors, 0)
end)

T.scene("45 secure search: nothing XNAH writes reaches the auction house's tables", function()
	local X, panel, f = setup()
	local env = W.env
	local button = f.SearchBar.SearchButton
	local watched = {f, f.SearchBar, f.SearchBar.SearchBox, button, f.BrowseResultsFrame, f.CategoriesList,
		env.g_auctionHouseSortsBySearchContext, env.AuctionHouseSearchContext, env.AuctionCategories}
	local GAME = {displayMode = true, searched = true, text = true, frames = true, rowData = true, updates = true,
		browseResults = true, level = true,
		HookScript = true, SetScript = true} -- (the last two: this scene's own watchers, below)
	local before = {}
	for i, t in ipairs(watched) do
		before[i] = {}
		for k in pairs(t) do before[i][k] = true end
	end
	-- writes into the game's saved filters: XNAH's never, the game's own StartSearch writes its level range back
	local writes, gameWrites = {}, 0
	local real = env.g_auctionHouseFilters
	env.g_auctionHouseFilters = setmetatable({}, {__index = real, __newindex = function(_, k, v)
		if W.gameCode == 0 then writes[#writes + 1] = tostring(k) else gameWrites = gameWrites + 1 end
		real[k] = v
	end})
	-- scripts on the game's frames
	local added = {}
	for label, fr in pairs({window = f, SearchBar = f.SearchBar, SearchBox = f.SearchBar.SearchBox, SearchButton = button}) do
		local hs, ss = fr.HookScript, fr.SetScript
		fr.HookScript = function(self, k, fn) added[#added + 1] = label .. " HookScript " .. tostring(k) return hs(self, k, fn) end
		fr.SetScript = function(self, k, fn) if W.gameCode == 0 then added[#added + 1] = label .. " SetScript " .. tostring(k) end return ss(self, k, fn) end
	end
	local onClick = button.scripts.OnClick
	local c = onRow(X, rowOf(panel, "2589"))
	dbl(c)
	W.advance(1)
	c = onRow(X, rowOf(panel, "4306"))
	dbl(c)
	W.advance(1)
	T.check("two searches by the game", #W.browseQueries, 2)
	local new = {}
	for i, t in ipairs(watched) do
		for k in pairs(t) do if not before[i][k] and not GAME[k] then new[#new + 1] = tostring(k) end end
	end
	T.check("no new keys on the game's frames and tables", table.concat(new, ", "), "")
	T.check("XNAH wrote nothing into the game's saved filters", table.concat(writes, ", "), "")
	T.ok("the game's own search wrote its level range back (as when you press the button)", gameWrites > 0, gameWrites)
	T.check("no scripts added to the game's frames", table.concat(added, ", "), "")
	T.ok("the Search button's OnClick is the game's own", button.scripts.OnClick == onClick)
	T.ok("the secure button only names the Search button in its setting", c.attr.clickbutton == button)
	T.check("no errors", #W.errors, 0)
end)

T.scene("45 secure search: right-click and dragging still work through the secure button", function()
	local X, panel, f = setup()
	local tbl = panel.tbl
	local function rowY(i) return (tbl:GetTop() - 2 - (i - 0.5) * tbl.rowH) * tbl:GetEffectiveScale() end
	local function gapY(g) return (tbl:GetTop() - 2 - g * tbl.rowH) * tbl:GetEffectiveScale() end
	local x = 30 * tbl:GetEffectiveScale()
	local function order() local t = {} for i, r in ipairs(tbl.items) do t[i] = r.key end return table.concat(t, ",") end
	T.check("at first", order(), "2589,15210:-19,4306")
	-- right-click: the item menu, nothing pressed
	local c = onRow(X, tbl.rows[1])
	if not c then T.ok("a secure button", false) return end
	click(c, "RightButton")
	local menu
	for _, m in ipairs(W.frames) do if m.strata == "FULLSCREEN_DIALOG" and m:IsVisible() then menu = m end end
	T.ok("right-click: the item menu", menu ~= nil and W.findButton("Stop tracking", menu) ~= nil)
	T.ok("right-click: with the search entry", menu ~= nil and W.findButton("Search on the auction house now", menu) ~= nil)
	X.K.CloseMenu()
	T.check("right-click: nothing pressed", #W.secureActions, 0)
	T.check("right-click: no search", #W.browseQueries, 0)
	-- a right double-click: the menu twice, never a search
	click(c, "RightButton")
	click(c, "RightButton")
	X.K.CloseMenu()
	T.check("right double-click: no search", #W.browseQueries, 0)
	-- the drag: pressed on the secure button over row 1, moved down past row 3, let go there
	X.UI.ShowItem("4306")
	W.advance(1)
	c = onRow(X, tbl.rows[1])
	W.mouseDown(c, x, rowY(1))
	W.mouseMove(x, rowY(1) - 8)
	W.advance(0.1)
	T.ok("picked up through the secure button", panel.ghost:IsShown())
	T.ok("the secure button stays while the button is held", c:IsShown())
	W.mouseMove(x, gapY(3) - 2, tbl.rows[3])
	W.advance(0.1)
	T.ok("the line where it lands", panel.dropLine:IsShown())
	W.mouseUp()
	-- the mouse is on row 3 now: the button follows there (and the mouse is then on it, as in the game)
	c = X.UI.SearchClickButton()
	T.ok("the secure button moved to the row under the mouse", c:IsShown())
	W.hover(c)
	W.advance(0.1)
	T.check("dropped: moved", order(), "15210:-19,4306,2589")
	T.check("dropped: not a click (the item shown stays)", X.UI.itemKey, "4306")
	T.check("dropped: nothing pressed, no search", #W.secureActions + #W.browseQueries, 0)
	T.ok("still there", c:IsShown())
	T.ok("its hover: the item of that row", has(tipText(), "Linen Cloth"), tipText())
	-- a click right after the drag picks again, a double-click searches
	click(c)
	T.check("the next click picks", X.UI.itemKey, "2589")
	W.advance(1)
	dbl(c)
	T.check("and a double-click searches", (W.browseQueries[1] or {}).searchString, "Linen Cloth")
	-- a drag that starts and ends on the same row with a double-click before it: no search from the drag's click
	W.advance(1)
	click(c)
	W.mouseDown(c, x, rowY(3))
	W.mouseMove(x, rowY(3) - 10)
	W.advance(0.05)
	W.mouseMove(x, rowY(3))
	W.advance(0.05)
	W.mouseUp()
	T.check("a click then a short drag: no search", #W.browseQueries, 1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("45 secure search: in combat nothing of it changes; after combat it is placed again", function()
	local X, panel, f = setup()
	local tbl = panel.tbl
	local row = rowOf(panel, "2589")
	local c = onRow(X, row)
	T.ok("shown before combat", c and c:IsShown())
	if not c then return end
	-- combat starts (the game sends PLAYER_REGEN_DISABLED just before the lockdown): hidden in time
	W.enterCombat()
	T.ok("combat: hidden", not c:IsShown())
	T.check("combat: nothing refused", table.concat(W.blocked, ", "), "")
	-- in combat: the mouse on rows, scrolling, the list redrawn: the secure button is left alone
	W.hover(row)
	T.ok("combat: not shown on a row", not c:IsShown())
	tbl.offset = 1
	tbl:Refresh()
	tbl.offset = 0
	tbl:Refresh()
	X.Fire("XNAH_PRICES")
	W.advance(0.5)
	-- the rows work as before: a click picks, the double-click the old way (XNAH's own search of the list)
	X.UI.ShowItem("4306")
	W.advance(1)
	row:Click("LeftButton")
	T.check("combat: a click picks", X.UI.itemKey, "2589")
	W.advance(1)
	row:DoubleClick("LeftButton")
	W.advance(0.5)
	T.check("combat: the double-click still searches (the old way)", (W.browseQueries[1] or {}).searchString, "Linen Cloth")
	T.check("combat: that one is XNAH's own", (W.browseQueries[1] or {}).byGame, false)
	T.check("combat: nothing pressed", #W.secureActions, 0)
	T.check("combat: nothing refused", table.concat(W.blocked, ", "), "")
	-- combat ends: placed again over the row under the mouse
	W.hover(row)
	W.leaveCombat()
	W.advance(0)
	T.ok("after combat: over the row again", c:IsShown())
	-- combat that starts before XNAH hears of it (the lockdown first): it stays, but changes nothing
	W.hover(c)
	W.enterCombat(true)
	T.ok("late: still there (it cannot be hidden in combat)", c:IsShown())
	W.advance(1)
	click(c)
	T.check("late: a click still picks", X.UI.itemKey, "2589")
	W.advance(1)
	local n = #W.browseQueries
	dbl(c)
	W.advance(0.5)
	T.check("late: nothing pressed", #W.secureActions, 0)
	T.check("late: the double-click the old way", #W.browseQueries, n + 1)
	W.unhover(c)
	W.advance(0.2)
	T.check("late: nothing refused (no change tried in combat)", table.concat(W.blocked, ", "), "")
	W.leaveCombat()
	W.advance(0.1)
	T.ok("after combat: hidden (the mouse left it)", not c:IsShown())
	-- combat before the button was ever made: it is not made in combat
	local X2, panel2 = setup()
	W.enterCombat()
	W.hover(rowOf(panel2, "2589"))
	T.ok("never made in combat", X2.UI.SearchClickButton() == nil)
	T.check("never made in combat: nothing refused", table.concat(W.blocked, ", "), "")
	W.leaveCombat()
	W.advance(0)
	T.ok("made after combat, over the row under the mouse", X2.UI.SearchClickButton() and X2.UI.SearchClickButton():IsShown())
	T.check("no errors", #W.errors, 0)
end)

T.scene("45 secure search: only while the auction house is open; it goes away with the row, the window or the mouse", function()
	local X, panel, f = setup()
	local row = rowOf(panel, "2589")
	local c = onRow(X, row)
	T.ok("shown", c and c:IsShown())
	if not c then return end
	W.closeAH()
	W.advance(0.1)
	T.ok("auction house closed: hidden", not c:IsShown())
	W.hover(row)
	T.ok("auction house closed: not shown on a row", not c:IsShown())
	row:DoubleClick("LeftButton")
	T.check("auction house closed: one chat line", #W.said("open the auction house first, then double-click again."), 1)
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	c = onRow(X, row)
	T.ok("open again: shown", c:IsShown())
	-- the mouse leaves
	W.unhover(c)
	T.ok("the mouse left: hidden", not c:IsShown())
	-- XNAH's window closed while the mouse was on a row
	c = onRow(X, row)
	X.UI.Frame():Hide()
	W.advance(0.1)
	T.ok("XNAH's window closed: hidden", not c:IsShown())
	T.check("nothing refused", table.concat(W.blocked, ", "), "")
	T.check("no errors", #W.errors, 0)
end)
