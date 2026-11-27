-- XNAH test scenes, part 38: staying out of the game's own auction house code. In v0.9.0, after a visit to the auction
-- house, the bank opened empty and the game said "XNAH has been blocked from an action only available to the Blizzard
-- UI": XNAH code had run inside the game's own opening / closing of its window, or had called the game's window
-- functions, and the game then refused its own protected action (buying the bank's first tab). These scenes check:
--   * no scripts are added to the game's auction house window (no HookScript / SetScript on it);
--   * the auction house opening and closing reach XNAH one frame later (nothing of XNAH runs inside the game's call);
--   * the double-click / "Search on the auction house" calls none of the game's window functions (they fail here);
--   * no keys are written onto the game's frames or tables (rows, cells, search bar, lists);
--   * the red chat line when the game blocks something and blames XNAH.
-- The window is the detailed stand-in of tools/world-ahpanel.lua.

local function history(X, key, usual, minNow, name)
	local now = X.Now()
	for d = 20, 1, -1 do X.Record(key, now - d * 86400, usual, usual, 100, 10, name, 1) end
	X.Record(key, now, minNow, usual, 100, 10, name, 1)
end

-- every table of the game's window XNAH could touch
local function gameTables(f)
	local out = {f, f.SearchBar, f.SearchBar.SearchBox, f.BrowseResultsFrame, f.ItemBuyFrame, f.CommoditiesBuyFrame}
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

-- makes every function the stand-in window has of its own (the game's Lua functions) fail and write down its name
local function forbid(f)
	local called = {}
	local function stub(t, label)
		for k, v in pairs(t) do
			if type(v) == "function" then
				t[k] = function() called[#called + 1] = label .. ":" .. k error("XNAH called the game's " .. k) end
			end
		end
	end
	stub(f, "window")
	stub(f.SearchBar, "SearchBar")
	stub(f.ItemBuyFrame, "ItemBuyFrame")
	stub(f.CommoditiesBuyFrame, "CommoditiesBuyFrame")
	for name, list in pairs(W.ahLists) do
		stub(list.ScrollBox, name .. ".ScrollBox")
		stub(list.tableBuilder, name .. ".tableBuilder")
		for i, c in ipairs(list.tableBuilder.columns) do stub(c, name .. ".column" .. i) end
	end
	return called
end

local function setup()
	local X = W.start()
	history(X, "2589", 50, 40, "Linen Cloth")
	history(X, "15210:-19", 50000, 60000, "Raider Shortsword of the Bear")
	X.SaleRate = function(key) if key == "2589" then return 3.5, 48 end return nil end
	for _, key in ipairs({"2589", "15210:-19"}) do X.SetWatched(key, true) end
	W.ahWindow()
	return X, W.ahFrame
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
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: the double-click calls none of the game's window functions", function()
	local X, f = setup()
	W.openAH()
	W.advance(0.5)
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	X.UI.Open("items")
	W.advance(0.3)
	local called = forbid(f)
	-- X.ShowOnAuctionHouse straight, the double-click on the tracked list, and the right-click menu entry
	T.check("shown", X.ShowOnAuctionHouse("2589"), true)
	T.check("its name in the search box", f.SearchBar.SearchBox.text, "Linen Cloth")
	local panel = X.UI.tabs.items.panel
	for i, r in ipairs(panel.tbl.items) do
		if r.key == "15210:-19" then
			local row = panel.tbl.rows[i - panel.tbl.offset]
			if row then row:DoubleClick("LeftButton") end
		end
	end
	T.check("double-click: its name in the search box", f.SearchBar.SearchBox.text, "Raider Shortsword of the Bear")
	X.UI.ItemMenu(X.UI.Frame(), "2589")
	local menu
	for _, m in ipairs(W.frames) do if m.strata == "FULLSCREEN_DIALOG" and m:IsVisible() then menu = m end end
	if menu then W.click("Search on the auction house now", menu) end
	T.check("menu: its name in the search box", f.SearchBar.SearchBox.text, "Linen Cloth")
	-- the extra columns and the "which item is shown" fallback, with the game's functions failing
	X.AHPanel.FillLists()
	X.Fire("XNAH_PRICES")
	W.advance(1)
	W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
	W.fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0})
	W.advance(1)
	T.check("none of the game's functions called", table.concat(called, ", "), "")
	T.check("no errors", #W.errors, 0)
end)

T.scene("taint: no keys written onto the game's frames or tables", function()
	local X, f = setup()
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	W.ahRows("item", {{itemKey = {itemID = 15210, itemLevel = 0, itemSuffix = -19, battlePetSpeciesID = 0}, buyoutAmount = 45000,
		quantity = 1, auctionID = 1}})
	W.ahRows("commodity", {{itemID = 2589, unitPrice = 45, quantity = 20, auctionID = 1}})
	local watched = gameTables(f)
	-- the stand-in's own fields (set by the stand-in itself as the game would) and the test world's frame internals
	local GAME = {itemKey = true, itemID = true, price = true, displayMode = true, postLoc = true, searchText = true,
		searched = true, updates = true, frames = true, rowData = true, level = true, text = true}
	local before = {}
	for i, t in ipairs(watched) do
		before[i] = {}
		for k in pairs(t) do before[i][k] = true end
	end
	W.openAH()
	W.advance(0.5)
	X.UI.Open("items")
	W.advance(0.3)
	W.ahClickRow(1)
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 300), W.ahBrowseResult(15210, 60000, 1, -19)})
	X.ShowOnAuctionHouse("2589")
	X.ShowOnAuctionHouse("15210:-19")
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
	-- XNAH's column frames are its own (children of the rows, kept in XNAH's own list)
	local row = W.ahLists.browse.ScrollBox.frames[1]
	local own = 0
	for _, c in ipairs(row.children) do if not c.region then own = own + 1 end end
	T.ok("the columns are XNAH's own frames on the row", own > #row.cells, own)
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
