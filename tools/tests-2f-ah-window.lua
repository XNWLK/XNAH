-- XNAH test scenes, part 2f: "Search on the auction house now" (the right-click menu of an item) and the double-click
-- put the item's name into the game's own auction house search box, and say "press Enter to search". XNAH calls none
-- of the game's window functions (that can make the game refuse its own protected actions later: the empty bank of
-- v0.9.0); tools/tests-38-taint.lua checks that with failing stand-ins. The window is the detailed stand-in of
-- tools/world-ahpanel.lua.

T.scene("search: the item's name goes into the game's search box", function()
	local X = W.start()
	W.list(2589, 50, 20, 3)
	W.ahWindow()
	W.openAH()
	W.advance(0.3)
	local f = W.ahFrame
	local box = f.SearchBar.SearchBox
	for i = #f.calls, 1, -1 do f.calls[i] = nil end
	X.Record("2589", X.Now(), 50, 50, 60, 3, "Linen Cloth", 1) -- the name XNAH knows
	T.check("shown", X.ShowOnAuctionHouse("2589"), true)
	T.check("its name in the search box", box.text, "Linen Cloth")
	T.ok("the search box has the keyboard (Enter searches)", W.focus == box)
	T.check("nothing asked of the game's window", table.concat(f.calls, " | "), "")
	T.check("no search started by XNAH", f.searched, nil)
	T.check("one chat line: press Enter", #W.said("is in the auction house search box - press Enter to search."), 1)
	-- an item the game has not loaded (no name anywhere): a chat line, nothing typed
	box:SetText("")
	T.check("no name yet: not shown", X.ShowOnAuctionHouse("424242"), false)
	T.check("no name yet: the box stays empty", box.text, "")
	T.check("no name yet: a chat line", #W.said("has not loaded this item's name yet"), 1)
	-- the game's window on its Sell tab: no search box there - the name in chat to type in
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.ItemSell)
	for i = #f.calls, 1, -1 do f.calls[i] = nil end
	T.check("Sell tab: still true", X.ShowOnAuctionHouse("2589"), true)
	T.check("Sell tab: the tab stays", f.displayMode.name, "ItemSell")
	T.check("Sell tab: the name in chat", #W.said("type Linen Cloth into the auction house search box (on its Buy tab) and press Enter."), 1)
	T.check("Sell tab: nothing asked of the game's window", #f.calls, 0)
	-- the right-click menu of an item: the name in the box and XNAH's own search
	f:SetDisplayMode(W.env.AuctionHouseFrameDisplayMode.Buy)
	for i = #f.calls, 1, -1 do f.calls[i] = nil end
	X.UI.ShowItem("2589")
	X.UI.ItemMenu(X.UI.Frame(), "2589")
	local menu
	for _, m in ipairs(W.frames) do if m.strata == "FULLSCREEN_DIALOG" and m:IsVisible() then menu = m end end
	T.ok("a menu", menu ~= nil)
	if menu then W.click("Search on the auction house now", menu) end
	T.check("menu entry: the name in the box", box.text, "Linen Cloth")
	T.ok("and XNAH searches it", X.scan.state == "items" or #W.said("scan done") > 0, X.scan.state)
	T.check("menu entry: nothing asked of the game's window", table.concat(f.calls, " | "), "")
	-- auction house closed: nothing
	W.closeAH()
	box:SetText("")
	T.check("closed: nothing", X.ShowOnAuctionHouse("2589"), false)
	T.check("closed: the box stays empty", box.text, "")
	T.check("no errors", #W.errors, 0)
end)
