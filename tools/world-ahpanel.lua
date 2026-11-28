-- Stand-in world, the game's own auction house window in more detail (helper A, AHPanel.lua): the pieces XNAH follows
-- or lays its columns over, shaped like Blizzard_AuctionHouseUI on Forever:
--   AuctionHouseFrame:SelectBrowseResult / SetDisplayMode / SetPostItem, .ItemBuyFrame:SetItemKey,
--   .CommoditiesBuyFrame:SetItemIDAndPrice / GetItemID, and three lists (.BrowseResultsFrame.ItemList,
--   .ItemBuyFrame.ItemList, .CommoditiesBuyFrame.ItemList), each with a ScrollBox (Update, GetFrames, view.frames), a
--   tableBuilder (GetColumns, .columns with .fillCoefficient), a HeaderContainer, and rows with rowData + cells (like the
--   game's table builder; rows are re-used for other items); .SearchBar.SearchBox (a text box, shown on the Buy pages).
--   XNAH reads the plain fields only (calling the game's functions from an addon can make the game refuse its own
--   protected actions later); tools/tests-38-taint.lua makes those functions fail to prove it.
-- hooksecurefunc(table, "Method", fn) works here too: fn runs after the original, with the same arguments.
--   W.ahWindow()                 builds the window (call after W.start(), before W.openAH())
--   W.ahRows(listName, results)  shows rows in a list ("browse", "item", "commodity") and lets the scroll box update
--   W.ahClickRow(i)              clicks row i of the item list (as the game does: SelectBrowseResult)
--   rows of the item list are children of its ScrollBox.ScrollTarget (as in the game); a left click on one (its
--   OnClick, the game's own code) opens that item's page; W.ahRowClicks counts those clicks
--   W.ahBrowseResult(id, minPrice, qty, suffix)  one row of the item list as the game gives it
--   W.ahFrame.calls              what XNAH called on the window, in order ("mode Buy", "text Linen Cloth",
--                                "open 2589:0", "search"), for scenes that check what XNAH asked of it
--   W.ahFrame.gameCalls          the same, called by the game's own code (W.asGame)
--   .SearchBar.SearchButton      the game's Search button: its OnClick (the game's code) runs StartSearch, which reads
--                                the box, writes the level range back and calls the window's SendBrowseQuery
--   W.browseQueries              every C_AuctionHouse.SendBrowseQuery (a copy of the query; byGame = sent by the
--                                game's own code), in order
-- The game's own tables the search reads (Blizzard_AuctionHouseSearchBar.lua / Blizzard_AuctionHouseFrame.lua):
--   g_auctionHouseFilters {minLevel, maxLevel, filters = {[filter] = on}}, g_auctionHouseSortsBySearchContext,
--   AuctionHouseSearchContext, AuctionCategories, and .CategoriesList (selectedCategoryIndex ...). The item list
--   (.BrowseResultsFrame) fills itself from AUCTION_HOUSE_BROWSE_RESULTS_UPDATED, as the game's own does.

local unpackf = table.unpack or unpack

table.insert(W.onReset, function()
	-- a window from an earlier scene holds hooks of an earlier login: never re-used
	if W.ahFrame and W.ahFrame.xnahStandIn then W.ahFrame = nil end
	W.ahLists = nil
	W.browseQueries = {}
	W.gameCode = 0
	W.ahRowClicks = 0
end)

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = deepCopy(x) end
	return out
end
W.deepCopy = deepCopy
-- the game's own code running by itself (its event handlers, its window opening): W.gameCode > 0 meanwhile, so
-- tools/tests-38-taint.lua can tell the game's own calls from XNAH's
W.gameCode = 0
function W.asGame(fn, ...)
	W.gameCode = W.gameCode + 1
	local ok, err = pcall(fn, ...)
	W.gameCode = W.gameCode - 1
	if not ok then error(err, 0) end
end

table.insert(W.onEnv, function(env)
	local plain = env.hooksecurefunc
	env.hooksecurefunc = function(a, b, c)
		if type(a) == "table" then
			local orig = rawget(a, b) -- only functions really set on the stand-in (not the frame's catch-all stubs)
			if type(orig) ~= "function" then return end
			W.tableHooks = (W.tableHooks or 0) + 1
			rawset(a, b, function(...)
				local r = {orig(...)}
				c(...)
				return unpackf(r)
			end)
			return
		end
		return plain(a, b, c)
	end
	-- every browse search sent is written down (the stand-in server answers it as before)
	local cah = env.C_AuctionHouse
	if cah and cah.SendBrowseQuery and not cah.xnahRecorded then
		local send = cah.SendBrowseQuery
		cah.SendBrowseQuery = function(query)
			local q = deepCopy(query)
			q.byGame = W.gameCode > 0 -- (sent by the game's own code, not by XNAH)
			W.browseQueries[#W.browseQueries + 1] = q
			return send(query)
		end
		cah.xnahRecorded = true
	end
	-- an item location's link and ID (only when the world has none)
	if env.C_Item and not env.C_Item.GetItemLink then
		env.C_Item.GetItemLink = function(loc) return type(loc) == "table" and loc.link or nil end
	end
	if env.C_Item and not env.C_Item.GetItemID then
		env.C_Item.GetItemID = function(loc) return type(loc) == "table" and loc.id or nil end
	end
end)

-- column widths of each list (the wide "fill" column marked), as Blizzard_AuctionHouseTableBuilder.lua lays them out
local LAYOUT = {
	browse = {widths = {146, 300, 83, 29}, fill = 2},    -- price, name, quantity, favourite
	item = {widths = {146, 146, 120, 24, 140}, fill = 3}, -- bid, buyout, quantity (fill), sockets, time left
	commodity = {widths = {146, 430}, fill = 2},          -- unit price, quantity (fill)
}

local function newList(parent, kind)
	local layout = LAYOUT[kind]
	local list = W.newFrame("Frame", nil, parent)
	list.kind = kind
	if kind ~= "commodity" then list.HeaderContainer = W.newFrame("Frame", nil, list) end
	local sb = W.newFrame("Frame", nil, list)
	list.ScrollBox = sb
	sb.pool, sb.frames, sb.updates = {}, {}, 0
	-- as the game (Blizzard_SharedXML ScrollBox.xml): the rows are children of the scroll box's ScrollTarget
	sb.ScrollTarget = W.newFrame("Frame", nil, sb)
	sb.view = {frames = sb.frames} -- as the game: the scroll box's view keeps the shown rows
	sb.GetFrames = function(self) return self.frames end
	sb.Update = function(self) self.updates = self.updates + 1 end
	local columns = {}
	for i, w in ipairs(layout.widths) do
		columns[i] = {width = w, fillCoefficient = i == layout.fill and 1 or 0,
			GetFillCoefficient = function(self) return self.fillCoefficient end}
	end
	list.tableBuilder = {columns = columns, GetColumns = function(self) return self.columns end}
	-- the game re-uses row frames; each row has one cell per column, side by side
	function list.ShowRows(self, results)
		for _, row in ipairs(sb.frames) do row:Hide() end
		sb.frames = {}
		sb.view.frames = sb.frames
		for i, d in ipairs(results) do
			local row = sb.pool[i]
			if not row then
				row = W.newFrame("Button", nil, sb.ScrollTarget)
				row.cells = {}
				if kind == "browse" then
					-- a left click on a row of the game's list opens that item's page (the game's own code:
					-- Blizzard_AuctionHouseItemList.lua OnClick -> SetSelectedEntry -> OnBrowseResultSelected -> SelectBrowseResult)
					row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
					row:SetScript("OnClick", function(self, button)
						W.asGame(function()
							W.ahRowClicks = (W.ahRowClicks or 0) + 1
							if button == "LeftButton" and self.rowData then W.ahFrame:SelectBrowseResult(self.rowData) end
						end)
					end)
				end
				local total = 0
				for c, col in ipairs(columns) do
					local cell = W.newFrame("Frame", nil, row)
					cell.w = col.width
					cell.left = total
					total = total + col.width
					cell.GetRight = function(self) return self.left + self.w end
					cell.Text = cell:CreateFontString()
					cell.Text.GetLeft = function() return cell.left + 30 end -- after the icon
					row.cells[c] = cell
				end
				row.w = total
				sb.pool[i] = row
			end
			row.rowData = d
			if kind == "browse" then
				local id, suffix = d.itemKey.itemID, d.itemKey.itemSuffix
				row.cells[layout.fill].Text:SetText(W.itemName(id, suffix) or "")
			end
			row:Show()
			sb.frames[i] = row
		end
		sb:Update()
	end
	return list
end

function W.ahWindow()
	local env = W.env
	local modes = {
		Buy = {"BrowseResultsFrame", "SearchBar"}, ItemBuy = {"ItemBuyFrame", "SearchBar"},
		CommoditiesBuy = {"CommoditiesBuyFrame", "SearchBar"},
		ItemSell = {"ItemSellFrame"}, CommoditiesSell = {"CommoditiesSellFrame"},
	}
	for name, m in pairs(modes) do m.name = name end
	env.AuctionHouseFrameDisplayMode = modes
	local f = W.newFrame("Frame", "AuctionHouseFrame", env.UIParent)
	f.xnahStandIn = true
	f.w, f.h = 800, 538
	f.shown = false
	W.ahFrame = f
	f.BrowseResultsFrame = W.newFrame("Frame", nil, f)
	f.BrowseResultsFrame.ItemList = newList(f.BrowseResultsFrame, "browse")
	f.ItemBuyFrame = W.newFrame("Frame", nil, f)
	f.ItemBuyFrame.ItemList = newList(f.ItemBuyFrame, "item")
	f.CommoditiesBuyFrame = W.newFrame("Frame", nil, f)
	f.CommoditiesBuyFrame.ItemList = newList(f.CommoditiesBuyFrame, "commodity")
	f.ItemSellFrame = W.newFrame("Frame", nil, f)
	f.CommoditiesSellFrame = W.newFrame("Frame", nil, f)
	-- calls made by XNAH go to f.calls; the game's own code (W.asGame) writes to f.gameCalls instead
	f.calls, f.gameCalls = {}, {}
	local function called(text)
		local list = W.gameCode > 0 and f.gameCalls or f.calls
		list[#list + 1] = text
	end
	f.SearchBar = W.newFrame("Frame", nil, f)
	-- as Blizzard_AuctionHouseSearchBar.lua StartSearch: reads the box, writes the level range back into its saved
	-- filters, then the window's SendBrowseQuery (the picked category, the sort order, back to the list)
	f.SearchBar.StartSearch = function(self)
		f.searched = true
		called("search")
		local saved = env.g_auctionHouseFilters
		local filters = {}
		if saved then
			saved.minLevel, saved.maxLevel = saved.minLevel, saved.maxLevel
			for k, on in pairs(saved.filters or {}) do if on then filters[#filters + 1] = k end end
			table.sort(filters)
		end
		f:SendBrowseQuery(f.SearchBar.SearchBox:GetText() or "", saved and saved.minLevel or 0, saved and saved.maxLevel or 0, filters)
	end
	f.SendBrowseQuery = function(self, text, minLevel, maxLevel, filters)
		called("browse " .. tostring(text))
		local cat = env.AuctionCategories and self.CategoriesList.selectedCategoryIndex
		local picked = cat and env.AuctionCategories[cat]
		local sorts = env.g_auctionHouseSortsBySearchContext
		env.C_AuctionHouse.SendBrowseQuery({searchString = text, minLevel = minLevel, maxLevel = maxLevel, filters = filters,
			itemClassFilters = picked and picked.filters or nil, sorts = sorts and sorts[0] or {}})
		self:SetDisplayMode(modes.Buy)
	end
	-- the game's Search button (its OnClick is the game's own code: StartSearch)
	f.SearchBar.SearchButton = W.newFrame("Button", nil, f.SearchBar, "UIPanelButtonTemplate")
	f.SearchBar.SearchButton:SetScript("OnClick", function(self)
		W.asGame(function() self:GetParent():StartSearch() end)
	end)
	-- the game's search box (a plain text box; the game empties it each time the search bar shows again)
	f.SearchBar.SearchBox = W.newFrame("EditBox", nil, f.SearchBar)
	f.SearchBar:SetScript("OnShow", function(self) W.asGame(function() self.SearchBox:SetText("") end) end)
	W.ahLists = {browse = f.BrowseResultsFrame.ItemList, item = f.ItemBuyFrame.ItemList, commodity = f.CommoditiesBuyFrame.ItemList}
	-- the game's list of items fills itself from the server's answer to any browse search (its own event handler,
	-- registered when it loads: Blizzard_AuctionHouseBrowseResultsFrame.lua OnLoad / OnEvent / UpdateBrowseResults)
	f.BrowseResultsFrame.browseResults = {}
	f.BrowseResultsFrame:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	f.BrowseResultsFrame:SetScript("OnEvent", function(self)
		W.asGame(function()
			self.browseResults = env.C_AuctionHouse.GetBrowseResults()
			self.ItemList:ShowRows(self.browseResults)
		end)
	end)
	-- the categories on the left (none picked) and the game's saved search settings, as on a fresh character
	f.CategoriesList = W.newFrame("Frame", nil, f)
	f.CategoriesList.selectedCategoryIndex = false -- (false = none picked; a real key, so the stand-in does not answer it)
	env.AuctionHouseSearchContext = {BrowseAll = 0, BrowseTradeGoods = 1, BrowseArmor = 2, BrowseWeapons = 3, AllFavorites = 13}
	env.g_auctionHouseFilters = {minLevel = 0, maxLevel = 0,
		filters = {[1] = false, [2] = false, [3] = false, [4] = false, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true,
			[11] = true, [12] = true}}
	env.g_auctionHouseSortsBySearchContext = {auctionHouseSortVersion = 2,
		[0] = {{sortOrder = 0, reverseSort = false}, {sortOrder = 1, reverseSort = false}},
		[3] = {{sortOrder = 1, reverseSort = true}, {sortOrder = 0, reverseSort = false}}}
	env.AuctionCategories = {
		{name = "Weapons", filters = {{classID = 2}}, subCategories = {{name = "Swords", filters = {{classID = 2, subClassID = 7}}}}},
		{name = "Trade Goods", filters = {{classID = 7}}},
	}

	f.SetDisplayMode = function(self, mode)
		local keep = {}
		for _, sub in ipairs(mode) do keep[sub] = true end
		for _, m in pairs(modes) do for _, sub in ipairs(m) do if not keep[sub] then self[sub]:Hide() end end end
		for _, sub in ipairs(mode) do self[sub]:Show() end
		self.displayMode = mode
		called("mode " .. tostring(mode.name))
	end
	f.GetDisplayMode = function(self) return self.displayMode end
	f.SetSearchText = function(self, text) self.searchText = text called("text " .. tostring(text)) end
	f.ItemBuyFrame.SetItemKey = function(self, itemKey) self.itemKey = itemKey end
	f.CommoditiesBuyFrame.SetItemIDAndPrice = function(self, itemID, price)
		self.itemID, self.price = itemID, price
		self.ItemList.itemID = itemID -- as the game: its list of the listings keeps the item
	end
	f.CommoditiesBuyFrame.GetItemID = function(self) return self.itemID end
	-- as Blizzard_AuctionHouseFrame.lua: a commodity opens its listings page, anything else the gear listings
	f.SelectBrowseResult = function(self, result)
		local itemKey = result.itemKey
		called("open " .. tostring(itemKey.itemID) .. ":" .. tostring(itemKey.itemSuffix))
		local info = env.C_AuctionHouse.GetItemKeyInfo(itemKey)
		if info and info.isCommodity then
			self.CommoditiesBuyFrame:SetItemIDAndPrice(itemKey.itemID, result.minPrice)
			self:SetDisplayMode(modes.CommoditiesBuy)
		else
			self.ItemBuyFrame:SetItemKey(itemKey)
			self:SetDisplayMode(modes.ItemBuy)
		end
	end
	f.SetPostItem = function(self, loc)
		self.postLoc = loc
		self:SetDisplayMode(modes.ItemSell)
	end
	f:SetDisplayMode(modes.Buy)
	-- the game's window starts on the item list each time it opens
	f:SetScript("OnShow", function(self) W.asGame(function() self:SetDisplayMode(modes.Buy) end) end)
	return f
end

function W.ahBrowseResult(id, minPrice, qty, suffix)
	return {itemKey = {itemID = id, itemLevel = 0, itemSuffix = suffix or 0, battlePetSpeciesID = 0}, minPrice = minPrice,
		totalQuantity = qty or 1, containsOwnerItem = false}
end
function W.ahRows(listName, results)
	W.ahLists[listName]:ShowRows(results)
end
function W.ahClickRow(i)
	local row = W.ahLists.browse.ScrollBox.frames[i]
	W.ahFrame:SelectBrowseResult(row.rowData)
end
