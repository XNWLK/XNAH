-- XNAH test scenes, part 38: staying out of the game's own auction house code. In v0.9.0, after a visit to the auction
-- house, the bank opened empty and the game said "XNAH has been blocked from an action only available to the Blizzard
-- UI": XNAH code had run inside the game's own opening / closing of its window, or had called the game's window
-- functions, and the game then refused its own protected action (buying the bank's first tab). The game's window
-- manager (Blizzard_UIParentPanelManager) opens and closes the auction house AND the bank; whatever the auction house
-- window reads while it opens or closes (its view, its search bar's saved filters, its lists) must never have been
-- written by XNAH. These scenes check:
--   * no scripts are added to the game's auction house window (no HookScript / SetScript on it);
--   * the auction house opening and closing reach XNAH one frame later (nothing of XNAH runs inside the game's call);
--   * the double-click / "Search on the auction house" calls none of the game's window functions (they fail here),
--     none of the window manager's (ShowUIPanel, HideUIPanel, UpdateUIPanelPositions ...: they fail here too), and
--     shows, hides, moves or sizes none of the game's frames; the search it starts is the server function any addon may
--     use (C_AuctionHouse.SendBrowseQuery), and the game's list fills itself from the answer in its own code;
--   * no keys are written onto the game's frames or tables (rows, cells, search bar, lists, categories), and nothing
--     the game reads when its window opens or closes is changed (its view, its saved filters, its sort orders);
--   * the red chat line when the game blocks something and blames XNAH.
-- The window is the detailed stand-in of tools/world-ahpanel.lua ("as far as the stand-in can tell": the real game
-- marks every value XNAH writes, the stand-in can only check what XNAH wrote and called).

local function history(X, key, usual, minNow, name)
	local now = X.Now()
	for d = 20, 1, -1 do X.Record(key, now - d * 86400, usual, usual, 100, 10, name, 1) end
	X.Record(key, now, minNow, usual, 100, 10, name, 1)
end

-- every table of the game's window XNAH could touch
local function gameTables(f)
	local env = W.env
	local out = {f, f.SearchBar, f.SearchBar.SearchBox, f.BrowseResultsFrame, f.ItemBuyFrame, f.CommoditiesBuyFrame, f.CategoriesList,
		env.g_auctionHouseFilters, env.g_auctionHouseFilters.filters, env.g_auctionHouseSortsBySearchContext,
		env.AuctionHouseSearchContext, env.AuctionCategories, env.AuctionHouseFrameDisplayMode}
	for _, s in pairs(env.g_auctionHouseSortsBySearchContext) do
		if type(s) == "table" then
			out[#out + 1] = s
			for _, one in ipairs(s) do out[#out + 1] = one end
		end
	end
	for _, c in ipairs(env.AuctionCategories) do out[#out + 1] = c end
	for _, list in pairs(W.ahLists) do
		out[#out + 1] = list
		out[#out + 1] = list.ScrollBox
		out[#out + 1] = list.ScrollBox.view
		out[#out + 1] = list.tableBuilder
		for _, c in ipairs(list.tableBuilder.columns) do out[#out + 1] = c end
		if rawget(list, "HeaderContainer") then out[#out + 1] = list.HeaderContainer end -- (the stand-in answers any missing key)
		for _, row in ipairs(list.ScrollBox.frames) do
			out[#out + 1] = row
			for _, c in ipairs(row.cells or {}) do out[#out + 1] = c; out[#out + 1] = c.Text end
		end
	end
	return out
end

-- a table and everything in it as one line of text (keys sorted), to compare before / after
local function dump(v, depth)
	if type(v) ~= "table" then return tostring(v) end
	if (depth or 0) > 6 then return "{...}" end
	local parts = {}
	for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. dump(x, (depth or 0) + 1) end
	table.sort(parts)
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- makes every function the stand-in window has of its own (the game's Lua functions) fail and write down its name when
-- XNAH calls it (the game's own code running by itself, W.gameCode > 0, still gets the real one)
local function forbid(f)
	local called = {}
	local function stub(t, label)
		for k, v in pairs(t) do
			if type(v) == "function" then
				t[k] = function(...)
					if W.gameCode > 0 then return v(...) end
					called[#called + 1] = label .. ":" .. k
					error("XNAH called the game's " .. k)
				end
			end
		end
	end
	stub(f, "window")
	stub(f.SearchBar, "SearchBar")
	stub(f.ItemBuyFrame, "ItemBuyFrame")
	stub(f.CommoditiesBuyFrame, "CommoditiesBuyFrame")
	stub(f.BrowseResultsFrame, "BrowseResultsFrame")
	stub(f.CategoriesList, "CategoriesList")
	for name, list in pairs(W.ahLists) do
		stub(list, name)
		stub(list.ScrollBox, name .. ".ScrollBox")
		stub(list.tableBuilder, name .. ".tableBuilder")
		for i, c in ipairs(list.tableBuilder.columns) do stub(c, name .. ".column" .. i) end
	end
	-- the window manager: XNAH must never ask it for anything
	for _, fn in ipairs({"ShowUIPanel", "HideUIPanel", "ToggleUIPanel", "UpdateUIPanelPositions", "SetUIPanelAttribute",
		"ShowUIPanelFailed", "CloseWindows", "CloseAllWindows", "UpdateScaleForFitForOpenPanels"}) do
		W.env[fn] = function() called[#called + 1] = "window manager:" .. fn error("XNAH called the game's " .. fn) end
	end
	-- showing, hiding, moving, sizing or setting attributes of the game's frames
	for label, fr in pairs({window = f, SearchBar = f.SearchBar, BrowseResultsFrame = f.BrowseResultsFrame,
		ItemBuyFrame = f.ItemBuyFrame, CommoditiesBuyFrame = f.CommoditiesBuyFrame, CategoriesList = f.CategoriesList}) do
		for _, m in ipairs({"Show", "Hide", "SetShown", "SetAttribute", "SetWidth", "SetHeight", "SetSize", "SetPoint",
			"ClearAllPoints", "SetScale", "SetParent", "SetFrameStrata"}) do
			local orig = fr[m]
			fr[m] = function(...)
				if W.gameCode == 0 then called[#called + 1] = label .. ":" .. m end
				return orig(...)
			end
		end
	end
	return called
end

local function setup()
	local X = W.start()
	history(X, "2589", 50, 40, "Linen Cloth")
	history(X, "15210:-19", 50000, 60000, "Raider Shortsword of the Bear")
	X.SaleRate = function(key) if key == "2589" then return 3.5, 48 end return nil end
	for _, key in ipairs({"2589", "15210:-19"}) do X.SetWatched(key, true) end
	-- what the auction house has (the stand-in server answers the searches from this)
	W.list(2589, 40, 20, 3)
	W.list(15210, 60000, 1, 1, nil, -19)
	W.ahWindow()
	return X, W.ahFrame
end

-- the row frame of the tracked list that shows `key`
local function rowOf(X, key)
	local panel = X.UI.tabs.items.panel
	for i, r in ipairs(panel.tbl.items) do
		if r.key == key then return panel.tbl.rows[i - panel.tbl.offset] end
	end
end

T.scene("taint: no scripts are added to the game's auction house window", function()
	local X, f = setup()
	local added = {}
	local hookScript, setScript = f.HookScript, f.SetScript
	f.HookScript = function(self, k, fn) added[#added + 1] = "HookScript " .. tostring(k) return hookScript(self, k, fn) end
	f.SetScript = function(self, k, fn) added[#added + 1] = "SetScript " .. tostring(k) return setScript(self, k, fn) end
	local onShow, onHide = f.scripts.OnShow, f.scripts.OnHide
	W.openAH()
	W.advance(1)
	T.ok("XNAH's window docked beside it", W.env.XNAHFrame and W.env.XNAHFrame:IsShown())
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300)})
	W.ahClickRow(1)
	W.closeAH()
	W.advance(1)
	W.openAH()
	W.advance(1)
	X.UI.Open("items")
	W.advance(0.3)
	X.ShowOnAuctionHouse("2589") -- the search XNAH starts itself: no scripts either
	W.advance(1)
	W.closeAH()
	W.advance(1)
	T.check("no HookScript / SetScript on the game's window", table.concat(added, ", "), "")
	T.ok("its OnShow is the game's own", f.scripts.OnShow == onShow)
	T.ok("its OnHide is the game's own", f.scripts.OnHide == onHide)
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: the auction house opening and closing reach XNAH one frame later", function()
	local X, f = setup()
	local heard = {}
	X.On("XNAH_AH", function(open) heard[#heard + 1] = open end)
	-- the game opens its window and sends the event (as inside its own code)
	W.ahOpen = true
	f:Show()
	W.fire("AUCTION_HOUSE_SHOW")
	T.ok("not yet inside the game's call", not X.ahOpen)
	T.check("no XNAH message yet", #heard, 0)
	T.ok("XNAH's window not opened inside the game's call", not (W.env.XNAHFrame and W.env.XNAHFrame:IsShown()))
	W.advance(0) -- the next frame
	T.check("one frame later: open", X.ahOpen, true)
	T.check("one frame later: the message", heard[1], true)
	W.advance(1)
	T.ok("XNAH's window docked beside it", W.env.XNAHFrame and W.env.XNAHFrame:IsShown())
	-- the game closes its window (its OnHide sends the event while it is still busy)
	W.ahOpen = false
	f:Hide()
	W.fire("AUCTION_HOUSE_CLOSED")
	T.check("still open inside the game's call", X.ahOpen, true)
	T.check("no close message yet", #heard, 1)
	T.ok("XNAH's window not hidden inside the game's call", W.env.XNAHFrame:IsShown())
	W.advance(0)
	T.check("one frame later: closed", X.ahOpen, false)
	T.check("one frame later: the message", heard[2], false)
	T.ok("XNAH's window closed with it", not W.env.XNAHFrame:IsShown())
	-- the game's window shows a little after the event (first visit, the game still loading it): XNAH's own timer docks
	W.ahOpen = true
	W.fire("AUCTION_HOUSE_SHOW")
	W.advance(0)
	T.ok("window not there yet: XNAH waits", not W.env.XNAHFrame:IsShown())
	f:Show()
	W.advance(0.5)
	T.ok("shown later: docked by XNAH's own timer", W.env.XNAHFrame:IsShown())
	f:Hide()
	W.advance(0.5)
	T.ok("hidden before the event: closed by XNAH's own timer", not W.env.XNAHFrame:IsShown())
	W.ahOpen = false
	W.fire("AUCTION_HOUSE_CLOSED")
	W.advance(1)
	T.ok("the timer stops once closed", not X.AHPanel.Watcher:IsShown())
	-- a search XNAH started just before the window closes: nothing of it runs after (no message, no search)
	W.openAH()
	W.advance(1)
	W.throttleUntil = W.NOW + 1
	X.ShowOnAuctionHouse("2589")
	W.closeAH()
	W.advance(2)
	T.check("closed before the server was ready: no search", #W.browseQueries, 0)
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: the double-click calls none of the game's window or window manager functions", function()
	local X, f = setup()
	W.openAH()
	W.advance(0.5)
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	X.UI.Open("items")
	W.advance(0.3)
	local called = forbid(f)
	-- X.ShowOnAuctionHouse straight, on the game's list of items: the name in the box and the search sent
	T.check("shown", X.ShowOnAuctionHouse("2589"), true)
	T.check("its name in the search box", f.SearchBar.SearchBox.text, "Linen Cloth")
	W.advance(0.5)
	T.check("the search sent to the server", (W.browseQueries[1] or {}).searchString, "Linen Cloth")
	T.check("the game's own list filled itself from the answer", #W.ahLists.browse.ScrollBox.frames, 1)
	-- the double-click on the tracked list
	local row = rowOf(X, "15210:-19")
	if row then row:DoubleClick("LeftButton") end
	T.check("double-click: its name in the search box", f.SearchBar.SearchBox.text, "Raider Shortsword of the Bear")
	W.advance(0.5)
	T.check("double-click: searched", (W.browseQueries[#W.browseQueries] or {}).searchString, "Raider Shortsword of the Bear")
	-- the right-click menu entry
	X.UI.ItemMenu(X.UI.Frame(), "2589")
	local menu
	for _, m in ipairs(W.frames) do if m.strata == "FULLSCREEN_DIALOG" and m:IsVisible() then menu = m end end
	if menu then W.click("Search on the auction house now", menu) end
	T.check("menu: its name in the search box", f.SearchBar.SearchBox.text, "Linen Cloth")
	W.advance(0.5)
	T.check("menu: searched", (W.browseQueries[#W.browseQueries] or {}).searchString, "Linen Cloth")
	-- on an item's page (the game switched it there itself): only the box, no search, no view switch
	local n = #W.browseQueries
	W.asGame(function() f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemBuy) end)
	X.ShowOnAuctionHouse("2589")
	W.advance(0.5)
	T.check("item page: no search", #W.browseQueries, n)
	T.check("item page: the page stays", f.displayMode.name, "ItemBuy")
	-- the extra columns and the "which item is shown" fallback, with the game's functions failing
	X.AHPanel.FillLists()
	X.Fire("XNAH_PRICES")
	W.advance(1)
	W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
	W.fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0})
	W.advance(1)
	T.check("none of the game's functions called, nothing of its frames shown, hidden or moved", table.concat(called, ", "), "")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: the double-click through the secure button: only the game's own code touches its window", function()
	-- (SearchClick.lua: the game's secure button presses the game's Search button; XNAH only writes the box's text and
	-- its own button's settings. tools/tests-45-secure-search.lua has the rest.)
	local X, f = setup()
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	local called = forbid(f)
	local row = rowOf(X, "2589")
	W.hover(row)
	local c = X.UI.SearchClickButton()
	T.ok("the secure button over the row", c ~= nil and c:IsShown())
	if not c then return end
	W.hover(c)
	for i = #f.gameCalls, 1, -1 do f.gameCalls[i] = nil end
	W.mouseDown(c, 30, 10) W.mouseUp()
	W.advance(0.15)
	W.mouseDown(c, 30, 10) W.mouseUp()
	T.check("the game's own StartSearch ran (as the game's code)", table.concat(f.gameCalls, " | "), "search | browse Linen Cloth | mode Buy")
	T.check("searched by the game", (W.browseQueries[1] or {}).byGame, true)
	W.advance(1)
	T.check("the game's own list filled itself from the answer", #W.ahLists.browse.ScrollBox.frames, 1)
	T.check("XNAH called none of the game's functions, showed, hid or moved none of its frames", table.concat(called, ", "), "")
	T.check("nothing refused", table.concat(W.blocked, ", "), "")
	W.closeAH()
	W.advance(1)
	W.openAH()
	W.advance(1)
	T.check("opened again: on its list", f.displayMode.name, "Buy")
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: no keys written onto the game's frames or tables, nothing it reads on open / close changed", function()
	local X, f = setup()
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	W.ahRows("item", {{itemKey = {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0}, buyoutAmount = 45000,
		quantity = 1, auctionID = 1}})
	W.ahRows("commodity", {{itemID = 2589, unitPrice = 45, quantity = 20, auctionID = 1}})
	local watched = gameTables(f)
	-- the stand-in's own fields (set by the stand-in itself as the game would) and the test world's frame internals
	local GAME = {itemKey = true, itemID = true, price = true, displayMode = true, postLoc = true, searchText = true,
		searched = true, updates = true, frames = true, rowData = true, level = true, text = true, browseResults = true}
	local before = {}
	for i, t in ipairs(watched) do
		before[i] = {}
		for k in pairs(t) do before[i][k] = true end
	end
	-- what the game reads when its window opens or closes (its search bar's saved filters, its sort orders, the
	-- categories, the category picked)
	local env = W.env
	local function readOnOpen()
		return dump({env.g_auctionHouseFilters, env.g_auctionHouseSortsBySearchContext, env.AuctionCategories,
			env.AuctionHouseSearchContext, f.CategoriesList.selectedCategoryIndex})
	end
	local settings = readOnOpen()
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	W.ahClickRow(1)
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	local mode = f.displayMode
	X.ShowOnAuctionHouse("2589")
	W.advance(0.5)
	X.ShowOnAuctionHouse("15210:-19")
	W.advance(0.5)
	T.check("two searches sent", #W.browseQueries, 2)
	T.ok("the window's view: the game's own, untouched", rawequal(f.displayMode, mode))
	X.Fire("XNAH_PRICES")
	W.advance(1)
	W.closeAH()
	W.advance(1)
	local added = {}
	for i, t in ipairs(watched) do
		for k in pairs(t) do
			if not before[i][k] and not GAME[k] then added[#added + 1] = tostring(k) end
		end
	end
	T.check("no new keys on the game's frames and tables", table.concat(added, ", "), "")
	T.check("the game's saved filters, sort orders and categories unchanged", readOnOpen(), settings)
	-- XNAH's searches are its own new tables, never the game's
	for i, q in ipairs(W.browseQueries) do
		T.ok("search " .. i .. ": XNAH's own filter list", q.filters ~= nil and q.filters ~= env.g_auctionHouseFilters.filters)
	end
	-- XNAH's column frames are its own (children of the rows, kept in XNAH's own list)
	local row = W.ahLists.browse.ScrollBox.frames[1]
	local own = 0
	for _, c in ipairs(row and row.children or {}) do if not c.region then own = own + 1 end end
	T.ok("the columns are XNAH's own frames on the row", row and own > #row.cells, own)
	-- the window opens again (the game's own code: view, search bar, saved filters): still nothing of XNAH's in there
	W.openAH()
	W.advance(1)
	T.check("opened again: the game's settings still unchanged", readOnOpen(), settings)
	T.check("opened again: on its list", f.displayMode.name, "Buy")
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: the search writes nothing into the game's saved filters or sort orders, not even the same value", function()
	-- (the game's own StartSearch writes the level range back into its saved filters each time; done by XNAH, that
	-- write alone would carry XNAH's mark into the search bar's opening code, even with the same number)
	local X, f = setup()
	local env = W.env
	local writes = {}
	local function watchWrites(name)
		local real = env[name]
		env[name] = setmetatable({}, {__index = real, __newindex = function(_, k, v)
			if W.gameCode == 0 then writes[#writes + 1] = name .. "." .. tostring(k) end
			real[k] = v
		end})
	end
	watchWrites("g_auctionHouseFilters")
	watchWrites("g_auctionHouseSortsBySearchContext")
	watchWrites("AuctionHouseSearchContext")
	watchWrites("AuctionCategories")
	local filtersReal = rawget(getmetatable(env.g_auctionHouseFilters), "__index").filters
	local proxyFilters = setmetatable({}, {__index = filtersReal, __newindex = function(_, k, v)
		if W.gameCode == 0 then writes[#writes + 1] = "g_auctionHouseFilters.filters." .. tostring(k) end
		filtersReal[k] = v
	end, __pairs = function() return next, filtersReal, nil end})
	rawget(getmetatable(env.g_auctionHouseFilters), "__index").filters = proxyFilters
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	X.ShowOnAuctionHouse("2589")
	W.advance(0.5)
	local row = rowOf(X, "15210:-19")
	if row then row:DoubleClick("LeftButton") end
	W.advance(1)
	T.check("two searches sent", #W.browseQueries, 2)
	T.check("the game's filters were read (the level range)", tostring(W.browseQueries[1] and W.browseQueries[1].minLevel), "0")
	T.check("no writes into the game's saved settings", table.concat(writes, ", "), "")
	W.closeAH()
	W.advance(1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: a red chat line when the game blocks something and blames XNAH", function()
	local X = W.start()
	W.fire("ADDON_ACTION_FORBIDDEN", "XNAH", "C_Bank.PurchaseBankTab()")
	local said = W.said("C_Bank.PurchaseBankTab()")
	T.check("one line", #said, 1)
	T.ok("says which action", said[1] and said[1]:find("blamed XNAH", 1, true) ~= nil, said[1])
	T.ok("asks for a screenshot", said[1] and said[1]:find("Please send a screenshot to Xn's helper.", 1, true) ~= nil, said[1])
	local raw = W.chat[#W.chat] or ""
	T.ok("in red", raw:find("|cffff4040", 1, true) ~= nil, raw)
	W.fire("ADDON_ACTION_FORBIDDEN", "XNAH", "C_Bank.PurchaseBankTab()")
	T.check("the same action again: no second line", #W.said("C_Bank.PurchaseBankTab()"), 1)
	W.fire("ADDON_ACTION_BLOCKED", "XNAH", "UseAction()")
	T.check("blocked (not only refused) too", #W.said("UseAction()"), 1)
	W.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "CastSpellByName()")
	T.check("another addon: not XNAH's business", #W.said("CastSpellByName()"), 0)
	T.check("no errors", #W.errors, 0)
end)
