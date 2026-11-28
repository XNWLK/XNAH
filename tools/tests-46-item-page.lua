-- XNAH test scenes, part 46: the double-click on a tracked item ends on the item's own page in the game's auction
-- house (SearchClick.lua): the double-click searches through the game's own Search button; when the answer shows the
-- item in exactly one row of the game's list, the next click on the item presses that row of the game's (through the
-- same secure button: the game's own row click opens the page); a double-click while the list already shows the item
-- opens its page at once. Also: the secure button is found again without a new hover (the watcher), a double-click
-- whose first click reached the row itself, and /xnah dc (the check of all this).
-- The game's rows are children of its ScrollBox.ScrollTarget and open the page in the game's own code
-- (tools/world-ahpanel.lua); the secure template is tools/world-secure.lua.
-- Every scene title starts with "46" (node tools/test.js 46).

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
local function onRow(X, row)
	W.hover(row)
	local c = X.UI.SearchClickButton()
	if c and c:IsShown() then W.hover(c) end
	return c
end
local function click(c, button) W.mouseDown(c, 30, 10, button) W.mouseUp(button) end
local function dbl(c) click(c) W.advance(0.15) click(c) end
local function mode(f) return f.displayMode and f.displayMode.name end
local function slash(text) W.env.SlashCmdList.XNAH(text) end
local function chatSince(n)
	local out = {}
	for i = n + 1, #W.chat do out[#out + 1] = W.plain(W.chat[i]) end
	return table.concat(out, "\n")
end
-- the game's list shows these results (its rows and its own list of results, as after an answer)
local function gameList(f, results)
	W.ahRows("browse", results)
	f.BrowseResultsFrame.browseResults = results
end
local HINT = "once more in XNAH's list to open its page in the auction house."

T.scene("46 item page: after the search a click opens the item's page, through the game's own row click", function()
	local X, panel, f = setup()
	local c = onRow(X, rowOf(panel, "2589"))
	if not c then T.ok("a secure button", false) return end
	dbl(c)
	T.check("double-click: the game searched", (W.browseQueries[1] or {}).byGame, true)
	W.advance(1.2)
	T.check("the answer: one row of it in the game's list", #f.BrowseResultsFrame.browseResults, 1)
	T.check("a one-time line says a click opens its page", #W.said(HINT), 1)
	-- the click: the game's own row pressed by the secure part
	clear(f.calls) clear(f.gameCalls)
	local actions = #W.secureActions
	click(c)
	T.check("click: the secure part pressed a button", #W.secureActions - actions, 1)
	T.check("click: the game's own row click ran once", W.ahRowClicks, 1)
	T.check("click: the item's page is open (a commodity: its listings)", mode(f), "CommoditiesBuy")
	T.check("click: the page of that item", f.CommoditiesBuyFrame.itemID, 2589)
	T.ok("click: opened by the game's own code", has(table.concat(f.gameCalls, " | "), "open 2589:0"), table.concat(f.gameCalls, " | "))
	T.check("click: XNAH called nothing of the game's window", table.concat(f.calls, " | "), "")
	T.check("click: the setting cleared again afterwards", c.attr.type, nil)
	T.check("click: also shown in XNAH", X.UI.itemKey, "2589")
	T.check("click: no new search of the game's list", #W.browseQueries, 1)
	-- once used: a later click does nothing more
	W.advance(1)
	click(c)
	T.check("a later click: no second row click", W.ahRowClicks, 1)
	-- a double-click while its page is open: nothing to do
	W.advance(1)
	actions = #W.secureActions
	dbl(c)
	T.check("double-click on its open page: no search", #W.browseQueries, 1)
	T.check("double-click on its open page: nothing pressed", #W.secureActions - actions, 0)
	T.check("double-click on its open page: the page stays", mode(f), "CommoditiesBuy")
	-- from that page, a double-click on another item: the game's Search (back to its list), then a click opens it
	W.advance(1)
	local c2 = onRow(X, rowOf(panel, "15210:-19"))
	dbl(c2)
	T.check("another item from a page: the game searched", (W.browseQueries[2] or {}).byGame, true)
	T.check("another item from a page: back on the game's list", mode(f), "Buy")
	W.advance(1.2)
	T.check("the line about the click is said only once", #W.said(HINT), 1)
	click(c2)
	T.check("gear: its page (single auctions)", mode(f), "ItemBuy")
	T.check("gear: the page of that item and suffix", f.ItemBuyFrame.itemKey and (f.ItemBuyFrame.itemKey.itemID .. ":" .. f.ItemBuyFrame.itemKey.itemSuffix), "15210:-19")
	T.check("no buying, posting or cancelling", #W.restrictedCalls, 0)
	T.check("nothing refused by the game", table.concat(W.blocked, ", "), "")
	T.check("no errors", #W.errors, 0)
end)

T.scene("46 item page: a double-click while the game's list shows the item opens its page at once", function()
	local X, panel, f = setup()
	gameList(f, {W.ahBrowseResult(2589, 40, 60), W.ahBrowseResult(4306, 900, 40)})
	local c = onRow(X, rowOf(panel, "4306"))
	if not c then T.ok("a secure button", false) return end
	clear(f.calls) clear(f.gameCalls)
	dbl(c)
	T.check("no new search", #W.browseQueries, 0)
	T.check("the game's own row click ran", W.ahRowClicks, 1)
	T.check("its page is open", mode(f), "CommoditiesBuy")
	T.check("the page of that item", f.CommoditiesBuyFrame.itemID, 4306)
	T.check("XNAH called nothing of the game's window", table.concat(f.calls, " | "), "")
	T.check("no line about searching", #W.said("searching the auction house"), 0)
	-- a plain click while the list shows an item (no search of XNAH's before): only shows it in XNAH
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	gameList(f, {W.ahBrowseResult(2589, 40, 60), W.ahBrowseResult(4306, 900, 40)})
	W.advance(1)
	c = onRow(X, rowOf(panel, "2589"))
	click(c)
	T.check("a plain click: no page", mode(f), "Buy")
	T.check("a plain click: shown in XNAH", X.UI.itemKey, "2589")
	-- the item twice in the game's list (two item levels): no page, the game's Search instead
	W.advance(1)
	local a, b = W.ahBrowseResult(2589, 40, 60), W.ahBrowseResult(2589, 45, 10)
	b.itemKey.itemLevel = 5
	gameList(f, {a, b})
	local clicks = W.ahRowClicks
	dbl(c)
	T.check("twice in the list: no row pressed", W.ahRowClicks, clicks)
	T.check("twice in the list: the game's Search instead", (W.browseQueries[1] or {}).byGame, true)
	-- in the game's results but scrolled out of sight (no row shows it): the game's Search
	W.advance(1.5)
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.ahRows("browse", {W.ahBrowseResult(2589, 40, 60)})
	f.BrowseResultsFrame.browseResults = {W.ahBrowseResult(2589, 40, 60), W.ahBrowseResult(4306, 900, 40)}
	local n = #W.browseQueries
	c = onRow(X, rowOf(panel, "4306"))
	dbl(c)
	T.check("scrolled away: the game's Search", #W.browseQueries, n + 1)
	T.check("no errors", #W.errors, 0)
end)

T.scene("46 item page: the rows of the game's list are re-used - a click only presses a row that shows the item now", function()
	local X, panel, f = setup()
	local c = onRow(X, rowOf(panel, "2589"))
	if not c then T.ok("a secure button", false) return end
	dbl(c)
	W.advance(1.2)
	T.check("the answer came", #f.BrowseResultsFrame.browseResults, 1)
	-- the game's list now shows another item in that same row frame (you searched something else meanwhile)
	local rowFrame = W.ahLists.browse.ScrollBox.frames[1]
	gameList(f, {W.ahBrowseResult(4306, 900, 40)})
	T.ok("the same row frame shows another item now", W.ahLists.browse.ScrollBox.frames[1] == rowFrame)
	-- the keys on the game's rows and results before: XNAH must add none
	local before = {}
	for k in pairs(rowFrame) do before[k] = true end
	local res = f.BrowseResultsFrame.browseResults[1]
	local resBefore = {}
	for k in pairs(res) do resBefore[k] = true end
	W.advance(1)
	click(c)
	T.check("click: no row pressed (the row shows another item)", W.ahRowClicks, 0)
	T.check("click: the game's list stays", mode(f), "Buy")
	T.check("click: nothing set to happen", c.attr.type, nil)
	-- the next click does not press anything either (the offer is gone)
	gameList(f, {W.ahBrowseResult(2589, 40, 60)})
	W.advance(1)
	click(c)
	T.check("the offer is gone after that", W.ahRowClicks, 0)
	local new = {}
	for k in pairs(rowFrame) do if not before[k] and k ~= "rowData" then new[#new + 1] = tostring(k) end end
	for k in pairs(res) do if not resBefore[k] then new[#new + 1] = "result." .. tostring(k) end end
	T.check("no new keys on the game's rows or results", table.concat(new, ", "), "")
	-- combat with the offer open: nothing pressed, nothing refused
	gameList(f, {})
	W.advance(1)
	dbl(c)
	W.advance(1.2)
	T.check("combat: the offer is open again", #f.BrowseResultsFrame.browseResults, 1)
	local rowClicks = W.ahRowClicks
	W.enterCombat()
	rowOf(panel, "2589"):Click("LeftButton")
	T.check("combat: no row pressed", W.ahRowClicks, rowClicks)
	T.check("combat: nothing refused", table.concat(W.blocked, ", "), "")
	W.leaveCombat()
	T.check("no errors", #W.errors, 0)
end)

T.scene("46 secure search: the button is found again without a new hover; a first click on the row itself counts", function()
	local X, panel, f = setup()
	local row = rowOf(panel, "2589")
	local c = onRow(X, row)
	if not c then T.ok("a secure button", false) return end
	-- the mouse left; then it is on the row again without the row hearing of it (the game sends no new hover)
	W.unhover(c)
	T.ok("the mouse left: hidden", not c:IsShown())
	W.mouseMove(30, 10, row)
	W.advance(0.25)
	T.ok("the watcher lays it over the row under the mouse", c:IsShown())
	-- the mouse already on a row when the auction house opens
	W.unhover(c)
	W.closeAH()
	W.advance(0.2)
	W.openAH()
	W.advance(0.3)
	X.UI.Open("items")
	W.mouseMove(30, 10, row)
	W.advance(0.3)
	T.ok("auction house opened with the mouse on a row: over it", c:IsShown())
	-- the first click reaches the row itself (the button was not there), the second the button: a double-click
	W.mouseFocus = nil -- (the mouse goes somewhere else)
	W.unhover(c)
	W.advance(0.2)
	T.ok("hidden again", not c:IsShown())
	row:Click("LeftButton")
	T.ok("a click on the row lays the button over it at once", c:IsShown())
	W.hover(c)
	W.advance(0.1)
	click(c)
	T.check("then a click on the button: the game's own search", (W.browseQueries[1] or {}).byGame, true)
	T.check("searched for its name", (W.browseQueries[1] or {}).searchString, "Linen Cloth")
	-- the first click on the button, the second on the row (the button went away between): the old way, once
	W.advance(1.5)
	c = onRow(X, rowOf(panel, "4306"))
	click(c)
	W.unhover(c)
	local n = #W.browseQueries
	rowOf(panel, "4306"):Click("LeftButton")
	W.advance(0.5)
	T.check("second click on the row: one search (XNAH's own, the old way)", #W.browseQueries, n + 1)
	T.check("second click on the row: XNAH's own", (W.browseQueries[n + 1] or {}).byGame, false)
	local lines = X.SearchClickReport()
	T.ok("/xnah dc says why", has(table.concat(lines, "\n"), "the second click landed on the row"), table.concat(lines, "\n"))
	T.check("nothing refused by the game", table.concat(W.blocked, ", "), "")
	T.check("no errors", #W.errors, 0)
end)

T.scene("46 /xnah dc: one fact per line, the last double-click's way and why, a line per double-click when on", function()
	local X, panel, f = setup()
	local n = #W.chat
	slash("dc")
	local text = chatSince(n)
	for _, part in ipairs({"SearchClick.lua: loaded", "not made yet", "button shown: no", "lies over: no row",
		"strata / level", "in combat: no", "XNAH thinks yes, the game's window shown yes",
		"the game's window shows: Buy (its list); recognised as its list: yes", "(BrowseResultsFrame) shown: yes",
		"search bar shown: yes, Search button shown: yes", "ActionButtonUseKeyDown", "the button's type: nil",
		"next click opens a page: no", "last double-click: none yet", "a line for each double-click: off"}) do
		T.ok("dc: " .. part, has(text, part), text)
	end
	-- after a double-click through the secure button
	W.env.GetMouseFoci = function() return {X.UI.SearchClickButton()} end
	local c = onRow(X, rowOf(panel, "2589"))
	dbl(c)
	W.advance(1.2)
	n = #W.chat
	slash("dc")
	text = chatSince(n)
	for _, part in ipairs({"made (XNAHSearchClick)", "button shown: yes", "lies over: row 1 (Linen Cloth)",
		"under the mouse: XNAHSearchClick", "mouse on the button: yes", "useOnKeyDown: false",
		"way: secure button - pressed the game's Search button", "next click opens the page of: Linen Cloth"}) do
		T.ok("dc after: " .. part, has(text, part), text)
	end
	-- the row's own double-click on an item's page (the old way): the reason and what happened
	W.ahRows("browse", {W.ahBrowseResult(15210, 60000, 1, -19)})
	W.ahClickRow(1)
	W.advance(1)
	W.enterCombat()
	rowOf(panel, "4306"):DoubleClick("LeftButton")
	W.leaveCombat()
	W.advance(0.5)
	n = #W.chat
	slash("dc")
	text = chatSince(n)
	T.ok("dc: the old way, in combat", has(text, "way: old way - in combat"), text)
	T.ok("dc: what the old way found", has(text, "shows ItemBuy, not its list"), text)
	T.ok("dc: the page shown", has(text, "the page shown is of: Raider Shortsword of the Bear"), text)
	-- on: a line for each double-click; off: none
	slash("dc on")
	T.check("dc on: said", #W.said("double-click lines on"), 1)
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	W.advance(1)
	c = onRow(X, rowOf(panel, "4306"))
	n = #W.chat
	dbl(c)
	T.ok("dc on: the line of that double-click", has(chatSince(n), "double-click on Silk Cloth: secure button - pressed the game's Search button"), chatSince(n))
	W.advance(1.2)
	T.ok("dc on: the answer's line", has(chatSince(n), "the next click on it opens its page"), chatSince(n))
	slash("dc off")
	W.advance(1)
	c = onRow(X, rowOf(panel, "2589"))
	n = #W.chat
	dbl(c)
	T.check("dc off: no such line", has(chatSince(n), "double-click on"), false)
	-- never an error: the game's window not loaded, no GetMouseFoci, the auction house closed
	local saved = W.env.AuctionHouseFrame
	W.env.GetMouseFoci = nil
	W.env.AuctionHouseFrame = nil
	n = #W.chat
	slash("dc")
	W.env.AuctionHouseFrame = saved
	T.ok("no window: says so", has(chatSince(n), "(not loaded yet)"), chatSince(n))
	T.check("no window: no line that could not be read", has(chatSince(n), "could not read"), false)
	W.closeAH()
	W.advance(0.2)
	n = #W.chat
	slash("dc")
	T.ok("closed: says so", has(chatSince(n), "XNAH thinks no"), chatSince(n))
	n = #W.chat
	slash("help")
	T.ok("help lists /xnah dc", has(chatSince(n), "/xnah dc - check the double-click"), chatSince(n))
	T.check("nothing refused by the game", table.concat(W.blocked, ", "), "")
	T.check("no errors", #W.errors, 0)
end)
