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
--   W.ahBrowseResult(id, minPrice, qty, suffix)  one row of the item list as the game gives it
--   W.ahFrame.calls              what was called on the window, in order ("mode Buy", "text Linen Cloth",
--                                "open 2589:0", "search"), for scenes that check what XNAH asked of it

local unpackf = table.unpack or unpack

table.insert(W.onReset, function()
	-- a window from an earlier scene holds hooks of an earlier login: never re-used
	if W.ahFrame and W.ahFrame.xnahStandIn then W.ahFrame = nil end
	W.ahLists = nil
end)

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
				row = W.newFrame("Button", nil, sb)
				row.cells = {}
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
	f.calls = {}
	local function called(text) f.calls[#f.calls + 1] = text end
	f.SearchBar = W.newFrame("Frame", nil, f)
	f.SearchBar.StartSearch = function() f.searched = true called("search") end
	-- the game's search box (a plain text box; the game empties it each time the search bar shows again)
	f.SearchBar.SearchBox = W.newFrame("EditBox", nil, f.SearchBar)
	f.SearchBar:SetScript("OnShow", function(self) self.SearchBox:SetText("") end)
	W.ahLists = {browse = f.BrowseResultsFrame.ItemList, item = f.ItemBuyFrame.ItemList, commodity = f.CommoditiesBuyFrame.ItemList}

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
	f:SetScript("OnShow", function(self) self:SetDisplayMode(modes.Buy) end)
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
