-- XNAH and the game's own auction house window:
--   * the item you pick in the game's window (clicked in its list, or picked to post) is shown in XNAH's window on the
--     Items view; XNAH's window docks beside the game's window (UI.lua);
--   * two extra columns in the game's lists (setting "Extra columns in the auction house lists"): "% of usual price"
--     (green = cheaper than usual, red = dearer) and "sells a day".
-- How it stays out of the game's way: the game's functions are never replaced and never called to change anything.
-- XNAH only listens AFTER the game's own functions have run (hooksecurefunc, the game's sanctioned way to follow them)
-- and reads what they were given. The column text sits in XNAH's own small frames laid on top of the game's rows;
-- nothing is written into the game's tables.
local ADDON, X = ...
local K, UI = X.K, X.UI

X.Default("ahColumns", true) -- the extra columns in the game's lists

local A = {}
X.AHPanel = A
local GREY = "|cff999999"

-- [[ item keys ]] the game's item key {itemID, itemSuffix, ...} -> XNAH's key ("2589" or "15210:-19")
local function keyOf(ik)
	if type(ik) ~= "table" then return nil end
	local id = X.Plain(ik.itemID)
	if type(id) ~= "number" or id <= 0 then return nil end
	local suffix = X.Plain(ik.itemSuffix)
	if type(suffix) == "number" and suffix ~= 0 then return id .. ":" .. suffix end
	return tostring(id)
end
A.KeyOf = keyOf

local function window()
	local f = AuctionHouseFrame
	if type(f) == "table" and f.IsShown and f:IsShown() then return f end
	return nil
end
local function isTable(v) return type(v) == "table" end

-- the item the game's window shows right now (its listings page), read from the game's frames; nil on the list
function A.WindowKey()
	local f = window()
	if not f then return nil end
	local ib, cb = f.ItemBuyFrame, f.CommoditiesBuyFrame
	if isTable(ib) and ib.IsShown and ib:IsShown() then return keyOf(ib.itemKey) end
	if isTable(cb) and cb.IsShown and cb:IsShown() and type(cb.GetItemID) == "function" then
		local id = X.Plain(X.Try(cb.GetItemID, cb))
		if type(id) == "number" and id > 0 then return tostring(id) end
	end
	return nil
end

-- [[ following the game's window ]] each hook runs after the game's own function, in its own protected call
local hookedOn = setmetatable({}, {__mode = "k"})
local function hook(obj, method, fn)
	if not isTable(obj) or type(obj[method]) ~= "function" or not hooksecurefunc then return false end
	local done = hookedOn[obj]
	if not done then done = {} hookedOn[obj] = done end
	if done[method] then return true end
	done[method] = true
	hooksecurefunc(obj, method, function(...)
		local ok, err = pcall(fn, ...)
		if not ok and X.OnError then X.OnError(err) end
	end)
	return true
end

-- [[ the item picked ]] shown in XNAH's window on the Items view (UI.FollowItem). picked = true: you picked it in the
-- game's window just now (its list, or an item to post) - shown even when it is the same item as before (you may have
-- looked at others in XNAH since); otherwise only a new item is shown (the game's listings pages and search answers)
local function setKey(key, picked)
	if not key then return end
	if key == A.key and not (picked and key ~= UI.itemKey) then return end
	A.key = key
	if UI.FollowItem then UI.FollowItem(key) end
end
A.SetKey = setKey

-- the auction house window came or went: XNAH's window docks beside it (UI.lua)
function A.Update()
	if UI.AuctionWindow then UI.AuctionWindow() end
end

-- [[ the extra columns ]] for each of the game's lists: an overlay frame of XNAH's own on each row (a child of the row,
-- so it scrolls and clips with it), filled after the game's scroll box has laid its rows out. Rows are re-used by the
-- game for other items, so every fill reads the row's item again.
local lists = {}                                     -- {list, sb, kind, cols, x, head}
local overlays = setmetatable({}, {__mode = "k"})    -- [the game's row] = XNAH's overlay frame
local cache = {}                                     -- [key] = {usual, rate} until prices change
local COLW = 46

local function numbersOf(key)
	local c = cache[key]
	if not c then
		c = {usual = X.Usual(key), rate = X.SaleRate and X.SaleRate(key) or nil}
		cache[key] = c
	end
	return c
end

-- the row's item and the price of one, by kind of list
local function rowItem(kind, d)
	if not isTable(d) then return nil end
	if kind == "browse" then
		local qty = X.Plain(d.totalQuantity)
		return keyOf(d.itemKey), (qty ~= 0) and X.Plain(d.minPrice) or nil
	elseif kind == "item" then
		-- the buyout of an item search row is already the price of ONE (also for a stack)
		local buyout = X.Plain(d.buyoutAmount)
		return keyOf(d.itemKey), (type(buyout) == "number" and buyout > 0) and buyout or nil
	elseif kind == "commodity" then
		local id = X.Plain(d.itemID)
		return type(id) == "number" and tostring(id) or nil, X.Plain(d.unitPrice)
	end
	return nil
end
A.RowItem = rowItem

-- "85%" green (cheaper than usual) / "130%" red (dearer)
function A.PctText(price, usual)
	if not (type(price) == "number" and price > 0 and type(usual) == "number" and usual > 0) then return GREY .. "-|r" end
	local p = price / usual * 100
	if p >= 999.5 then return "|cfff87171>999%|r" end
	local col = p < 99.5 and "4ade80" or (p > 100.5 and "f87171" or "ffffff")
	return "|cff" .. col .. string.format("%d%%", math.floor(p + 0.5)) .. "|r"
end

local function makeOverlay(row, cols)
	local o = CreateFrame("Frame", nil, row)
	o:SetFrameLevel((X.Try(row.GetFrameLevel, row) or 1) + 10) -- above the game's cells of the row
	o:SetWidth(cols * COLW)
	o.band = o:CreateTexture(nil, "BACKGROUND")
	o.band:SetAllPoints()
	o.band:SetColorTexture(0, 0, 0, 0.35)
	o.pct = K.Label(o, "", "GameFontHighlightSmall", "RIGHT")
	o.pct:SetPoint("TOPLEFT", 0, 0)
	o.pct:SetPoint("BOTTOMRIGHT", o, "BOTTOMLEFT", COLW - 4, 0)
	if cols > 1 then
		o.rate = K.Label(o, "", "GameFontHighlightSmall", "RIGHT")
		o.rate:SetPoint("TOPLEFT", COLW, 0)
		o.rate:SetPoint("BOTTOMRIGHT", -4, 0)
	end
	overlays[row] = o
	return o
end

-- where the columns go: the right end of the list's wide (fill) column, as an offset from the row's left edge
local function fillColumn(spec)
	local tb = spec.list.tableBuilder
	local columns = isTable(tb) and type(tb.GetColumns) == "function" and X.Try(tb.GetColumns, tb)
	if not isTable(columns) then return nil end
	for i, c in ipairs(columns) do
		local fc = isTable(c) and type(c.GetFillCoefficient) == "function" and X.Try(c.GetFillCoefficient, c)
		if type(fc) == "number" and fc > 0 then return i, c end
	end
	return nil
end
local function measure(spec, row, index)
	local cell = index and isTable(row.cells) and row.cells[index]
	if not isTable(cell) then return nil end
	local right, left = X.Try(cell.GetRight, cell), X.Try(row.GetLeft, row)
	if type(right) == "number" and type(left) == "number" and right > left then return math.floor(right - left - 2 + 0.5), cell end
	return nil
end
-- a fallback when nothing can be measured: the fixed columns right of the wide one
local RIGHT_OF_FILL = {browse = 124, item = 176, commodity = 8}
-- the stackable goods list: price, then the quantity right-aligned in the wide column - so the numbers go just right
-- of the price (where the wide column is empty), not at its right end (over the quantity; Xn saw that in the game)
local AFTER_PRICE = 6

local function header(spec, on)
	local hc = spec.list.HeaderContainer
	-- the listings of stackable goods have no header row (the game lays that list over its empty header frame)
	if not on or spec.kind == "commodity" or not isTable(hc) or not spec.x then
		if spec.head then spec.head:Hide() end
		return
	end
	if not spec.head then
		local h = CreateFrame("Frame", nil, hc)
		h:SetFrameLevel((X.Try(hc.GetFrameLevel, hc) or 1) + 10)
		h:SetSize(spec.cols * COLW, 18)
		h.pct = K.Label(h, "% usual", "GameFontNormalSmall", "RIGHT")
		h.pct:SetPoint("LEFT", 0, 0)
		h.pct:SetWidth(COLW - 4)
		if spec.cols > 1 then
			h.rate = K.Label(h, "a day", "GameFontNormalSmall", "RIGHT")
			h.rate:SetPoint("LEFT", COLW, 0)
			h.rate:SetWidth(COLW - 4)
		end
		spec.head = h
	end
	if spec.head.x ~= spec.x then
		spec.head:ClearAllPoints()
		spec.head:SetPoint("RIGHT", hc, "LEFT", spec.x, 0)
		spec.head.x = spec.x
	end
	spec.head:Show()
end

local function fillList(spec)
	if not X.db then return end
	local on = X.S().ahColumns and window() and true or false
	local frames = type(spec.sb.GetFrames) == "function" and X.Try(spec.sb.GetFrames, spec.sb)
	if not isTable(frames) then frames = {} end
	local index = on and (spec.kind == "commodity" and 1 or fillColumn(spec))
	for _, row in ipairs(frames) do
		local o = overlays[row]
		if on and isTable(row) then
			o = o or makeOverlay(row, spec.cols)
			local x, cell = measure(spec, row, index)
			if x and spec.kind == "commodity" then x = x + AFTER_PRICE + spec.cols * COLW end
			if x then spec.x = x end
			x = spec.x
			if not x then
				local w = X.Try(row.GetWidth, row)
				if type(w) == "number" and w > 100 then
					if spec.kind == "commodity" then x = math.floor(w * 0.45) + spec.cols * COLW else x = w - RIGHT_OF_FILL[spec.kind] end
				end
			end
			local key, price = rowItem(spec.kind, row.rowData)
			if x and key then
				if o.x ~= x then
					o:ClearAllPoints()
					o:SetPoint("TOPRIGHT", row, "TOPLEFT", x, 0)
					o:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", x, 0)
					o.x = x
				end
				local n = numbersOf(key)
				o.pct:SetText(A.PctText(price, n.usual))
				if o.rate then o.rate:SetText(n.rate and X.Rate(n.rate) or (GREY .. "-|r")) end
				-- a long item name runs under the columns: the band gets dark so the numbers stay readable
				local txt = cell and cell.Text
				local dark = false
				if isTable(txt) and type(txt.GetStringWidth) == "function" then
					local sw, tl = X.Try(txt.GetStringWidth, txt), X.Try(txt.GetLeft, txt)
					local rl = X.Try(row.GetLeft, row)
					if type(sw) == "number" and type(tl) == "number" and type(rl) == "number" then
						dark = tl - rl + sw > x - spec.cols * COLW - 4
					end
				end
				o.band:SetColorTexture(0, 0, 0, dark and 0.85 or 0.35)
				o:Show()
			else
				o:Hide()
			end
		elseif o then
			o:Hide()
		end
	end
	header(spec, on)
end
A.FillList = fillList

function A.FillLists()
	for _, spec in ipairs(lists) do fillList(spec) end
end

local function attachList(itemList, kind, cols)
	if not isTable(itemList) or not isTable(itemList.ScrollBox) then return end
	for _, s in ipairs(lists) do if s.list == itemList then return end end
	local spec = {list = itemList, sb = itemList.ScrollBox, kind = kind, cols = cols}
	if hook(spec.sb, "Update", function() fillList(spec) end) then lists[#lists + 1] = spec end
end

-- [[ hooking the game's window ]] once it exists (the game loads it when the auction house first opens)
local hooked = false
function A.Hook()
	local f = AuctionHouseFrame
	if hooked or not isTable(f) or not hooksecurefunc then return hooked end
	hooked = true
	-- XNAH's window docks and undocks with the game's window (the game may show it before or after XNAH hears the auction
	-- house opened)
	if f.HookScript then
		f:HookScript("OnShow", function() X.Try(A.Update) end)
		f:HookScript("OnHide", function() X.Try(A.Update) X.Try(A.FillLists) end)
	end
	-- an item picked in the list (also XNAH's own "show on the auction house")
	hook(f, "SelectBrowseResult", function(_, result) if isTable(result) then setKey(keyOf(result.itemKey), true) end end)
	-- the listings pages of gear and of stackable goods
	hook(f.ItemBuyFrame, "SetItemKey", function(_, itemKey) setKey(keyOf(itemKey)) end)
	hook(f.CommoditiesBuyFrame, "SetItemIDAndPrice", function(_, itemID)
		if type(X.Plain(itemID)) == "number" then setKey(tostring(itemID)) end
	end)
	-- an item from the bags put up for sale
	hook(f, "SetPostItem", function(_, loc)
		if not isTable(loc) then return end
		local link = C_Item.GetItemLink and X.Try(C_Item.GetItemLink, loc)
		local key = X.KeyFromLink(link)
		if not key and C_Item.GetItemID then
			local id = X.Plain(X.Try(C_Item.GetItemID, loc))
			if type(id) == "number" then key = tostring(id) end
		end
		setKey(key, true)
	end)
	-- the extra columns: the list of items, the listings of gear, the listings of stackable goods
	attachList(isTable(f.BrowseResultsFrame) and f.BrowseResultsFrame.ItemList, "browse", 2)
	attachList(isTable(f.ItemBuyFrame) and f.ItemBuyFrame.ItemList, "item", 1)
	attachList(isTable(f.CommoditiesBuyFrame) and f.CommoditiesBuyFrame.ItemList, "commodity", 1)
	return true
end

-- the game's search answers: a fallback in case a hook above missed the item (the window's own item, not XNAH's searches)
local function fromWindow()
	local key = A.WindowKey()
	if key then setKey(key) end
end
X.On("ITEM_SEARCH_RESULTS_UPDATED", fromWindow)
X.On("COMMODITY_SEARCH_RESULTS_UPDATED", fromWindow)

X.On("ADDON_LOADED", function(name)
	if name == "Blizzard_AuctionHouseUI" then A.Hook() end
end)
local function opened(try)
	if not X.ahOpen then return end
	if not A.Hook() then
		try = try or 0
		if try < 6 then X.After(0.5, function() opened(try + 1) end) end
		return
	end
	A.Update()
	A.FillLists()
end
X.On("XNAH_AH", function(open)
	if open == true then
		A.key = nil
		cache = {}
		opened()
	else
		A.Update()
		A.FillLists() -- hides the column text
	end
end)

-- new prices, watch list, sales speed, bags: the columns again (a moment later, once)
local function changed()
	cache = {}
	if not X.ahOpen then return end
	X.Debounce("ahpanel", 0.3, function()
		A.FillLists()
	end)
end
for _, e in ipairs({"XNAH_PRICES", "XNAH_WATCH", "XNAH_ANALYSIS", "XNAH_INVENTORY", "XNAH_RECIPES"}) do X.On(e, changed) end
