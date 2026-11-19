-- XNAH test scenes, part 2f: "Search on the auction house" also shows the item in the game's own auction house window
-- (its listings page; a search by name while the game is still loading the item).

local function stubWindow(f)
	local calls = {}
	f.SetDisplayMode = function(self, mode) calls[#calls + 1] = "mode " .. tostring(mode and mode.name) end
	f.SetSearchText = function(self, text) calls[#calls + 1] = "text " .. text end
	f.SelectBrowseResult = function(self, r) calls[#calls + 1] = "open " .. r.itemKey.itemID .. ":" .. r.itemKey.itemSuffix end
	f.SearchBar = {StartSearch = function() calls[#calls + 1] = "search" end}
	return calls
end

T.scene("search: the game's auction house window shows the item too", function()
	local X = W.start()
	W.env.AuctionHouseFrameDisplayMode = {Buy = {name = "Buy"}}
	W.list(2589, 50, 20, 3)
	W.openAH()
	local calls = stubWindow(W.ahFrame)
	T.check("shown", X.ShowOnAuctionHouse("2589"), true)
	T.check("Buy tab, the name, then its listings", table.concat(calls, " | "), "mode Buy | text Linen Cloth | open 2589:0")
	X.Record("2589", X.Now(), 50, 50, 60, 3, "Linen Cloth", 1) -- the name XNAH knows
	-- an item the game is still loading: tries again, then searches by name
	W.items[2589].uncached = true
	for i = #calls, 1, -1 do calls[i] = nil end
	X.ShowOnAuctionHouse("2589")
	W.advance(0.5)
	T.check("not yet given up", calls[#calls], "text Linen Cloth")
	W.items[2589].uncached = nil
	W.advance(0.4)
	T.check("listings once the game knows it", calls[#calls], "open 2589:0")
	W.items[2589].uncached, W.items[2589].never = true, true
	for i = #calls, 1, -1 do calls[i] = nil end
	X.ShowOnAuctionHouse("2589")
	W.advance(2)
	T.check("never known: a search by name", calls[#calls], "search")
	W.items[2589].uncached, W.items[2589].never = nil, nil
	-- the item page's button: the window and XNAH's own search
	for i = #calls, 1, -1 do calls[i] = nil end
	X.ShowItem("2589")
	X.UI.tabs.item.panel.ah:Click()
	T.check("button opens the listings", calls[#calls], "open 2589:0")
	T.ok("and XNAH searches it", X.scan.state == "items" or #W.said("scan done") > 0, X.scan.state)
	-- auction house closed: nothing
	W.closeAH()
	for i = #calls, 1, -1 do calls[i] = nil end
	T.check("closed: nothing", X.ShowOnAuctionHouse("2589"), false)
	T.check("no calls", #calls, 0)
end)
