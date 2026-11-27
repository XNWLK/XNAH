-- Items view: your tracked items (left) and everything about one item (right). Read-only analysis plus one button:
-- "Buy cheapest now" (works while the auction house is open). UI.ShowItem(key) shows an item here, tracked or not.
-- Layout (1080 x 600): the tracked list 260 wide (an "Add an item" box, a line about the item shown, the list); the
-- analysis 810 wide: header 44 high (icon, name, track star, how many listed; Buy cheapest now on the right - shown on
-- every page), a row of page buttons at y -46, then the page picked (810 x 532 from y -68).
-- The pages: other files add theirs with UI.AddItemPage (below). The first, Overview: 12 number tiles (2 rows of 6),
-- the price graph (range buttons, graph 160 high, names under it), then 3 boxes 240 high: the auction house now (a
-- price ladder), the best time to sell, crafting and your trades.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED, GOLD = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"
local NONE = "|cff666666-|r"
local DAY = 86400
local LIST_W = 260                -- the tracked list
local AX = LIST_W + 10            -- where the analysis starts
local AW = UI.W - AX              -- its width (810)
local PAGE_BUTTONS_Y = -46        -- the row of page buttons
local PAGE_Y = -68                -- the pages start here
local PAGE_H = UI.H + PAGE_Y      -- their height (532)
-- the Overview page (y inside the page)
local TILE_Y, TILE_H, TILE_GAP = 0, 38, 4
local RANGE_Y, GRAPH_Y, GRAPH_H, LEGEND_Y = -88, -108, 160, -272
local BOX_Y = -292
local BOX_H = PAGE_H + BOX_Y      -- 240
local B1, B2 = 252, 290           -- widths of the ladder box and the best-time box (the third gets the rest)
local B3 = AW - B1 - B2 - 16
local LADDER = 12                 -- price steps shown
local CRAFT_ROWS = 14
local SPARK_W, SPARK_H = 28, 12
local RANGES = {{"7 days", 7 * DAY}, {"30 days", 30 * DAY}, {"90 days", 90 * DAY}, {"1 year", 365 * DAY}}
local HOW = {vendor = "vendor", ah = "auction", craft = "crafted"}
X.Default("itemRange", 2)  -- the graph's range (an index of RANGES)
X.Default("graphHide", {}) -- names under the graph clicked off: {mkt, low, bars, fair, sales, buys = true}
X.Default("usualBand", true) -- the usual range band on the price graphs (Overview and Compare)

X.Default("itemPage", "overview") -- the page shown on the right (its key)

local qtyByKey = {} -- "Buy cheapest now": how many of a commodity per purchase, per item (this session)

-- [[ the pages ]] UI.AddItemPage(key, title, build(page, w, h), refresh(page, itemKey), order, help)
-- Adds a page to the right side of the Items view (call it when the file loads). page = a frame under the item's header
-- and the page buttons: w x h = 810 x 532. build(page, w, h) runs once when the view is first opened; refresh(page,
-- itemKey) runs when the picked item changes, when the page is shown and whenever the view refreshes (new prices, a
-- scan ...), only while the page is shown and an item is picked. The header (icon, name, track star, how many listed,
-- Buy cheapest now) stays above every page. Lowest order first; Overview is 1. help = the tooltip of the page's button.
local PAGES = UI.PageSet()
function UI.AddItemPage(key, title, build, refresh, order, help)
	UI.AddPageTo(PAGES, key, title, build, refresh, order, help)
end
UI.ITEM_PAGES = PAGES
local itemPanel   -- the Items view's panel (while it is built and after)
local lastSummary -- the numbers of the item, worked out once per refresh (the header and Overview both use them)

local function M(v) return X.Money(v, true) end
local function signed(v)
	if v >= 0 then return GREEN .. "+" .. X.MoneyPlain(v) .. "|r" end
	return RED .. "-" .. X.MoneyPlain(-v) .. "|r"
end
local function count(n)
	if n == math.floor(n) then return tostring(n) end
	return string.format("%.1f", n)
end
-- the price now as a % of the usual price, coloured (green = cheaper than usual)
local function pctText(p)
	if not p then return NONE end
	if p >= 999.5 then return RED .. ">999%|r" end
	local col = p < 99.5 and GREEN or (p > 100.5 and RED or "|cffffffff")
	return col .. string.format("%d%%", math.floor(p + 0.5)) .. "|r"
end
local function pctOf(key)
	local it = X.Items()[key]
	local cur = it and it.cur
	if not (cur and cur.min and (cur.qty or 0) > 0) then return nil end
	local usual = X.Usual(key)
	if not usual or usual <= 0 then return nil end
	return cur.min / usual * 100
end

local refresh -- below

-- [[ the tracked list ]]
X.Default("listSpark", true) -- the small 7-day price line in each row of the tracked list (Settings can hide it)
local function sparkOn() return X.S().listSpark ~= false end
-- the line of an item (false: none; nil: not worked out yet, next frame - at most a few ms of work a frame)
local function sparkOf(key) if sparkOn() then return X.Spark(key, true) end return false end
local LIST_COLUMNS = {
	{"Item", 96, "LEFT", text = function(r) return X.ItemIcon(X.KeyID(r.key), 12) .. " " .. X.ItemText(r.key) end,
		sort = function(r) return (X.ItemName(r.key) or r.key):lower() end, desc = false,
		tip = "The items you track. Click one to see everything about it on the right, right-click it for more (like Stop tracking), " ..
			"double-click it to put its name in the auction house search box."},
	{"Cheapest", 62, "RIGHT", text = function(r)
		local it = X.Items()[r.key]
		local cur = it and it.cur
		if not cur then return NONE end
		if (cur.qty or 0) == 0 then return GREY .. "none|r" end
		return UI.MoneyCell(cur.min, not X.Fresh(it))
	end, sort = function(r) local it = X.Items()[r.key] return it and it.cur and (it.cur.qty or 0) > 0 and it.cur.min or nil end, desc = false,
		tip = "The lowest price of one at the last scan or search. \"none\": none were listed then. Grey: the price is old."},
	{"% usual", 44, "RIGHT", text = function(r) return pctText(pctOf(r.key)) end, sort = function(r) return pctOf(r.key) end, desc = false,
		tip = "The cheapest price now against the usual price (its average over the last 30 days). Under 100% (green): " ..
			"cheaper than usual. Over 100% (red): dearer than usual."},
	{"", 14, "CENTER", text = function(r)
		local it = X.Items()[r.key]
		return it and X.Arrow(X.Stats(it).trend) or ""
	end, sort = function(r) local it = X.Items()[r.key] return it and X.Stats(it).trend or nil end,
		tip = "Which way the price went over the last 14 days. Green plus: rising (two: fast). Red minus: falling (two: " ..
			"fast). Grey =: about the same."},
	-- the line itself is drawn over this cell (drawSpark); "-" when there is no line (fewer than 2 days with a price)
	{"7 days", 34, "LEFT", text = function(r)
		if not sparkOn() or sparkOf(r.key) ~= false then return "" end
		return GREY .. "  -|r"
	end, sort = function(r) local c = sparkOf(r.key) return c and c.change or nil end,
		tip = function()
			if not sparkOn() then return "The 7-day price lines are hidden. Turn them back on in Settings (the gear)." end
			return "The price over the last 7 days as a small line, one point a day. Green: up 3% or more from the first " ..
				"day to the last. Red: down 3% or more. Grey: about the same. Sorting by it: the biggest move up first."
		end},
}

-- the 7-day line of a row (Sparkline.lua), a few line pieces made once per row (rows are reused while scrolling)
local function drawSpark(rowFrame, key)
	local s = rowFrame.xnahSpark
	if not s then
		s = K.Sparkline(rowFrame, SPARK_W, SPARK_H)
		local cell = rowFrame.cols and rowFrame.cols[5]
		if cell then s:SetPoint("LEFT", cell, "LEFT", 1, 0) else s:SetPoint("RIGHT", rowFrame, "RIGHT", -3, 0) end
		rowFrame.xnahSpark = s
	end
	local c = key and sparkOf(key)
	s:SetData(c or nil)
	s:SetShown(c and true or false)
end

-- an item picked in the "Add an item" box: on the tracked list, and shown
local function addItem(panel, key)
	if not key then return end
	panel.add:SetText("")
	panel.add:ClearFocus()
	K.CloseMenu()
	X.SetWatched(key, true)
	UI.ShowItem(key)
end

local function buildList(panel)
	local label = K.Label(panel, "Add an item", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 0, -5)
	local add = K.Edit(panel, LIST_W - 84, function(text)
		local hits = X.QuickFind and X.QuickFind(text, 1) or {}
		K.CloseMenu()
		if hits[1] and hits[1].key then addItem(panel, hits[1].key) end
	end)
	add:SetPoint("TOPLEFT", 80, 0)
	add:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-items-add", 0.25, function()
			local text = self:GetText() or ""
			if not self:HasFocus() or #X.Trim(text) < 2 or not X.QuickFind then K.CloseMenu() return end
			local entries = {}
			for _, h in ipairs(X.QuickFind(text, 15)) do
				entries[#entries + 1] = {text = h.text, disabled = h.key == nil, func = function() addItem(panel, h.key) end}
			end
			if #entries == 0 then entries[1] = {text = "Nothing found", disabled = true} end
			K.Menu(self, entries)
		end)
	end)
	K.Tooltip(add, "Add an item", "Type an item's name and pick it: it goes on your tracked list and is shown on the right.")
	panel.add = add
	-- "Showing: <item>" when the item shown is not tracked, else how many are tracked
	panel.showing = K.Label(panel, "", "GameFontHighlightSmall")
	panel.showing:SetPoint("TOPLEFT", 0, -30)
	panel.showing:SetWidth(LIST_W)
	panel.showing:SetWordWrap(false)
	-- click: shown on the right; double-click: its name goes into the game's own auction house search box
	local tbl = K.Table(panel, LIST_W, UI.H - 62, LIST_COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end, function(row)
		UI.ShowInAuctionHouse(row.key) -- (the first press of the double-click already showed it on the right)
	end, "Double-click: put its name in the auction house search box")
	tbl:SetPoint("TOPLEFT", 0, -62)
	tbl:SortBy(1, false)
	-- after each redraw (sorting, scrolling): the 7-day lines, and the item shown marked; lines that had to wait for the
	-- next frame: sorted and drawn again then
	local base = tbl.Refresh
	function tbl:Refresh()
		base(self)
		for i, rowFrame in ipairs(self.rows) do
			local r = self.items[i + self.offset]
			if r and rowFrame:IsShown() then
				drawSpark(rowFrame, r.key)
				rowFrame:SetSelected(r.key == UI.itemKey)
			end
		end
		if X.SparkBusy() then X.SparkAgain(self, function() if self:IsVisible() then self:Sort() end end) end
	end
	panel.tbl = tbl
end

local function fillList(panel)
	local rows = {}
	for key in pairs(X.db.watch) do rows[#rows + 1] = {key = key} end
	LIST_COLUMNS[5][1] = sparkOn() and "7 days" or "" -- (the title goes with the lines when Settings hides them)
	panel.tbl:SetRows(rows, "Nothing tracked yet.\nType a name in Add an item.")
	local key = UI.itemKey
	if key and not X.Watched(key) then
		panel.showing:SetText(GREY .. "Showing:|r " .. X.ItemText(key) .. GREY .. "  (not tracked)|r")
	else
		panel.showing:SetText(GREY .. "Tracked items: " .. #rows .. "  (right-click one: Stop tracking)|r")
	end
end

-- [[ the analysis: header ]]
local function buildHeader(panel, a)
	local icon = CreateFrame("Button", nil, a)
	icon:SetSize(36, 36)
	icon:SetPoint("TOPLEFT", 0, 0)
	icon.tex = icon:CreateTexture(nil, "ARTWORK")
	icon.tex:SetAllPoints()
	icon:SetScript("OnEnter", function(self) if UI.itemKey then UI.ItemTooltip(self, UI.itemKey) end end)
	icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	panel.icon = icon
	panel.name = K.Label(a, "", "GameFontNormalLarge")
	panel.name:SetPoint("TOPLEFT", 44, -2)
	panel.name:SetWidth(360)
	panel.name:SetWordWrap(false)
	-- the track star
	local star = K.Flat(a, 74, 18)
	star:SetPoint("TOPLEFT", 44, -23)
	star:SetScript("OnClick", function()
		local key = UI.itemKey
		if key then X.SetWatched(key, not X.Watched(key)) end
	end)
	K.Tooltip(star, "Track", "Puts the item on your tracked list (left), or takes it off. \"Scan tracked\" searches every " ..
		"tracked item.")
	panel.star = star
	panel.sub = K.Label(a, "", "GameFontHighlightSmall")
	panel.sub:SetPoint("TOPLEFT", 124, -26)
	panel.sub:SetWidth(330)
	panel.sub:SetWordWrap(false)
end

-- [[ Buy cheapest now ]] the button, the "how many" box for goods with one price each, a line under it
local function buyClick(button)
	local key = UI.itemKey
	local b = X.buy
	if button == "RightButton" then
		if b.state == "quoting" or b.state == "confirm" then X.BuyCancel() end
		return
	end
	if not (X.ahOpen and key) then return end
	if b.key ~= key or not b.cheapest then
		X.BuyStart(key, qtyByKey[key] or 1, nil, "items", "cheapest", true)
	elseif b.state == "ready" or b.state == "confirm" then
		X.BuyClick() -- the one restricted call of this press
	elseif b.state == "none" or b.state == "closed" or b.state == "idle" then
		X.BuyResearch()
	end
end

local function buildBuy(panel, a)
	local buy = K.Button(a, "", 270, 24)
	buy:SetPoint("TOPRIGHT", 0, 0)
	buy:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	buy:SetScript("OnClick", function(_, button) buyClick(button) end)
	K.Tooltip(buy, "Buy cheapest now", "Buys the cheapest listing that is not yours, at exactly the price on the button, " ..
		"without asking. Gear and other items: one press buys ONE item for the price of one (also from an auction of 7: " ..
		"press again for the next one). Goods with one price " ..
		"each (ore, cloth ...): the first press asks the server for the exact price, the second press buys. After each " ..
		"purchase it looks again, so you can keep pressing. Right-click: stop a purchase that was started.")
	panel.buy = buy
	local qty = K.Edit(a, 44, function(text)
		local key = UI.itemKey
		local n = math.floor(tonumber(text) or 0)
		if key and n >= 1 then
			qtyByKey[key] = n
			if X.buy.key == key then X.BuyNeed(n) end
		end
	end)
	qty:SetPoint("RIGHT", buy, "LEFT", -8, 0)
	qty:SetNumeric(true)
	qty:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-buy-qty", 0.5, function()
			local key = UI.itemKey
			local n = math.floor(tonumber(self:GetText() or "") or 0)
			if key and n >= 1 then
				qtyByKey[key] = n
				if X.buy.key == key then X.BuyNeed(n) end
			end
		end)
	end)
	K.Tooltip(qty, "How many", "How many one purchase buys (goods with one price each). Remembered for this item until you log out.")
	panel.qty = qty
	panel.qtyLabel = K.Label(a, "How many", "GameFontNormalSmall", "RIGHT")
	panel.qtyLabel:SetPoint("RIGHT", qty, "LEFT", -8, 0)
	panel.buyNote = K.Label(a, "", "GameFontDisableSmall", "RIGHT")
	panel.buyNote:SetPoint("TOPRIGHT", 0, -29)
	panel.buyNote:SetWidth(340)
	panel.buyNote:SetWordWrap(false)
end

-- what the line under the button says
local function buyNote(b, key)
	if not X.ahOpen then return "Buying works while the auction house is open." end
	if b.key ~= key or not b.cheapest then return "" end
	local s, p = b.state, b.plan
	local done = (b.bought or 0) > 0 and ("  Bought so far: " .. X.Num(b.bought) .. " for " .. X.MoneyPlain(b.spent) .. ".") or ""
	if s == "ready" and p then
		if p.commodity then
			return "The cheapest " .. X.Num(p.qty) .. ", about " .. X.MoneyPlain(math.floor(p.total / math.max(1, p.qty) + 0.5)) ..
				" each. Press: exact price, press again: buy." .. done
		end
		if (p.listed or 1) > 1 then
			return "Cheapest not yours: " .. X.MoneyPlain(p.total) .. " each (" .. X.Num(p.listed) .. " listed in that auction)." ..
				" One press buys one." .. done
		end
		return "Cheapest listing not yours. One press buys it." .. done
	elseif s == "confirm" and b.quote then
		return "Exact price: " .. X.MoneyPlain(b.quote.unit or 0) .. " each. Press again to buy, right-click to stop."
	elseif s == "searching" then return "Looking for the cheapest listing ..." .. done
	elseif s == "quoting" then return "Asking the server for the exact price ..."
	elseif s == "buying" then return "Buying ..." end
	return (b.text or "") .. done
end

local function updateBuy(panel)
	local key = UI.itemKey
	if not key then return end
	local b = X.buy
	local mine = b.key == key and b.cheapest
	local text, on
	if not X.ahOpen then text, on = "Open the auction house to buy", false
	elseif not mine then text, on = "Searching ...", false
	else text, on = X.BuyButton() end
	panel.buy:SetText(text)
	panel.buy:SetEnabled(on and true or false)
	local live = X.live[key]
	local commodity = X.ahOpen and ((mine and b.plan and b.plan.commodity) or (live and live.commodity)) and true or false
	panel.qty:SetShown(commodity)
	panel.qtyLabel:SetShown(commodity)
	if commodity and not panel.qty:HasFocus() then panel.qty:SetText(tostring(qtyByKey[key] or 1)) end
	panel.buyNote:SetText(buyNote(b, key))
end

-- the purchase engine for the item shown: searched as soon as it is shown at the auction house, so the button is ready
local function syncBuy(key)
	if not (X.ahOpen and key) then return end
	local b = X.buy
	if b.state == "buying" then return end -- a purchase on its way finishes first
	if b.key == key and b.cheapest and b.state ~= "closed" and b.state ~= "idle" then return end
	X.BuyStart(key, qtyByKey[key] or 1, nil, "items", "cheapest", true)
end

-- [[ number tiles ]] {title, what it means in plain words}
local TILES = {
	{"Cheapest now", "The lowest price of one at the last scan or search (your own listings not counted). Grey when the " ..
		"price is old."},
	{"Market value", "What one goes for right now: the average of the cheaper listings, so a single silly price moves it little."},
	{"Usual price", "The average market value over the last 30 days (7 or 3 days while there is less history). Everything " ..
		"in XNAH that says \"usual\" means this."},
	{"Now vs usual", "The cheapest price now against the usual price. Under 100% (green): cheaper than usual, a good time to " ..
		"buy. Over 100% (red): dearer than usual, a good time to sell."},
	{"Trend a week", "How fast the price moved over the last 14 days, in % a week. Plus: rising. Minus: falling."},
	{"Ups and downs", "How much the price jumps from one day to the next. Small: a steady price. Big: risky - or a chance " ..
		"to buy on a low day and sell on a high one."},
	{"Sells a day", "About how many are sold each day, worked out from scans one after another and from your own sales. " ..
		"More: easier to sell."},
	{"Listed vs normal", "How many are listed now, against the last 7 days. Far more than normal: prices tend to drop. " ..
		"Far fewer: prices tend to rise."},
	{"Fair price to buy", "A good price to pay: in the last 14 days it was listed this cheap or cheaper about 1 time in 4."},
	{"Fair price to sell", "A good price to ask: its usual market value over the last 14 days (never over the 30-day high). " ..
		"Small: what you keep after the auction house cut."},
	{"Vendor pays", "What any vendor pays for one. Never sell it for less on the auction house."},
	{"Crafting cost", "What the reagents for one craft cost, each at its cheapest (vendor, auction house or crafting it). " ..
		"Small: the profit when sold at its price, after the auction house cut."},
}

local function buildTiles(panel, a)
	local tw = math.floor((AW - 5 * 6) / 6)
	panel.tiles = {}
	for i, def in ipairs(TILES) do
		local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
		local t = K.Panel(a, tw, TILE_H, {0, 0, 0, 0.3})
		t:SetPoint("TOPLEFT", col * (tw + 6), TILE_Y - row * (TILE_H + TILE_GAP))
		local title = K.Label(t, GREY .. def[1] .. "|r", "GameFontNormalSmall")
		title:SetPoint("TOPLEFT", 6, -4)
		title:SetWidth(tw - 12)
		title:SetWordWrap(false)
		t.value = K.Label(t, NONE, "GameFontHighlight")
		t.value:SetPoint("BOTTOMLEFT", 6, 5)
		t.value:SetWidth(math.floor(tw * 0.64) - 6)
		t.value:SetWordWrap(false)
		t.sub = K.Label(t, "", "GameFontDisableSmall", "RIGHT")
		t.sub:SetPoint("BOTTOMRIGHT", -6, 6)
		t.sub:SetWidth(math.floor(tw * 0.36) - 4)
		t.sub:SetWordWrap(false)
		t:EnableMouse(true)
		K.Tooltip(t, def[1], def[2])
		panel.tiles[i] = t
	end
end

-- the value and the small text of each tile, in the order of TILES
local function tileValues(s)
	local cur, st = s.cur, s.st or {}
	local stale = s.cur and not s.fresh
	local listed = cur and (cur.qty or 0) > 0
	local v = {}
	v[1] = {cur and (listed and UI.MoneyCell(cur.min, stale) or (GREY .. "none listed|r")) or NONE, stale and "old" or nil}
	v[2] = {cur and UI.MoneyCell(cur.mkt, stale) or NONE}
	v[3] = {M(s.usual)}
	local p = listed and s.usual and s.usual > 0 and cur.min / s.usual * 100 or nil
	v[4] = {pctText(p), p and (p < 99.5 and "cheaper" or (p > 100.5 and "dearer" or "as usual")) or nil}
	v[5] = {st.trend and X.Pct(st.trend) or (GREY .. "too new|r"), st.trend and (math.abs(st.trend) < 4 and "steady" or (st.trend > 0 and "rising" or "falling")) or nil}
	v[6] = {st.vol and string.format("%.0f%%", st.vol) or NONE, st.vol and (st.vol < 5 and "steady" or (st.vol < 15 and "some" or "jumpy")) or nil}
	v[7] = {s.rate and X.Rate(s.rate) or (GREY .. "not known|r")}
	v[8] = {cur and cur.qty and X.Num(cur.qty) or NONE, st.supply and (st.supply >= 0 and "+" or "") .. string.format("%.0f%%", st.supply) or nil}
	v[9] = {s.fairBuy and M(s.fairBuy) or (GREY .. "not known yet|r")}
	v[10] = {s.fairSell and M(s.fairSell) or (GREY .. "not known yet|r"), s.fairSell and ("keep " .. X.MoneyPlain(X.AfterCut(s.fairSell))) or nil}
	v[11] = {M(s.vsell)}
	v[12] = {s.craft and M(s.craft) or (#X.RecipesFor(s.id) > 0 and (GREY .. "no price|r") or (GREY .. "no recipe|r")),
		s.craftProfit and ((s.craftProfit >= 0 and "+" or "-") .. X.MoneyPlain(math.abs(s.craftProfit))) or nil}
	return v
end

local function fillTiles(panel, s)
	for i, val in ipairs(tileValues(s)) do
		local t = panel.tiles[i]
		t.value:SetText(val[1] or NONE)
		t.sub:SetText(val[2] and (GREY .. val[2] .. "|r") or "")
	end
end

-- [[ the price graph ]]
local SALE, BUY = {1, 0.55, 0.2}, {0.75, 0.5, 1}
local FAIRBUY, FAIRSELL = {0.55, 0.95, 0.7}, {1, 0.9, 0.55}
local LEGEND = {
	{"mkt", "Market value", {1, 0.82, 0}, "The market value at each scan: the average of the cheaper listings (price of one)."},
	{"low", "Lowest price", {0.29, 0.87, 0.5}, "The cheapest listing at each scan (price of one)."},
	{"bars", "Listed", {0.54, 0.64, 1}, "The faint bars: how many were listed at each scan."},
	{"fair", "Fair prices", {0.85, 0.85, 0.85}, "Two thin flat lines: the fair price to buy (lower) and the fair price " ..
		"to sell (upper), worked out from the last 14 days."},
	{"band", "Usual range", {0.6, 0.5, 0.12}, "The soft band behind the lines: where the market value usually sat in " ..
		"the 30 days up to each day (the middle half of its day prices - the same days as the usual price). A red dot: " ..
		"the price was well over it; a green dot: well under it."},
	{"sales", "Your sales", SALE, "Your own sales of this item (from the ledger): a dot at the price of one. Hover it for the details."},
	{"buys", "Your buys", BUY, "Your own purchases of this item (from the ledger): a dot at the price of one. Hover it for the details."},
}

-- a name under the graph clicked off? (the usual range has its own setting, shared with the Compare page)
local function legendHidden(k)
	if k == "band" then return not X.S().usualBand end
	return X.S().graphHide[k]
end

local function buildGraph(panel, a)
	panel.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(a, 56, 18)
		b:SetPoint("TOPLEFT", (i - 1) * 60, RANGE_Y)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().itemRange = i refresh(panel) end)
		panel.ranges[i] = b
	end
	local note = K.Label(a, GREY .. "Prices of one. Hover for the numbers, right-click to add a note, click a name below to hide it.|r",
		"GameFontHighlightSmall", "RIGHT")
	note:SetPoint("TOPRIGHT", 0, RANGE_Y - 3)
	note:SetWidth(AW - 260)
	note:SetWordWrap(false)
	panel.graph = K.Graph(a, AW, GRAPH_H)
	panel.graph:SetPoint("TOPLEFT", 0, GRAPH_Y)
	-- the names under the graph
	panel.legend = {}
	for i, e in ipairs(LEGEND) do
		local b = CreateFrame("Button", nil, a)
		b:SetSize(80, 16)
		b.sw = b:CreateTexture(nil, "ARTWORK")
		b.sw:SetSize(8, 8)
		b.sw:SetPoint("LEFT", 0, 0)
		b.sw:SetColorTexture(e[3][1], e[3][2], e[3][3], 1)
		b.label = K.Label(b, e[2], "GameFontHighlightSmall")
		b.label:SetPoint("LEFT", 12, 0)
		b.label:SetWordWrap(false)
		b.key, b.base = e[1], e[2]
		b:SetScript("OnClick", function()
			local hide = X.S().graphHide
			if e[1] == "band" then X.S().usualBand = not X.S().usualBand else hide[e[1]] = (not hide[e[1]]) or nil end
			refresh(panel)
		end)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(e[2])
			GameTooltip:AddLine(e[4], 1, 1, 1, true)
			GameTooltip:AddLine(legendHidden(e[1]) and "Hidden - click to show it." or "Click to hide it.", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		b:Hide()
		panel.legend[i] = b
	end
end

-- your sales or buys of the item from `from` on, as dots: {t, v = price of one, color, text}; also how many in all
local function tradeMarks(key, which, from, color, verb)
	local list = X.GraphTrades and X.GraphTrades(key, which) or {}
	local marks = {}
	for _, e in ipairs(list) do
		if e.t >= from then
			local c = math.max(1, e.count or 1)
			marks[#marks + 1] = {t = e.t, v = e.money / c, color = color,
				text = verb .. " " .. X.Num(c) .. " at " .. M(e.money / c) .. " each" .. GREY .. "  " .. X.Date(e.t, "%b %d %H:%M") .. "|r"}
		end
	end
	return marks, #list
end

-- the names under the graph, left to right; info = {sales, buys (in all), inSales, inBuys (in the range), fair}
local function layoutLegend(panel, info)
	local x = 0
	for _, b in ipairs(panel.legend) do
		local k = b.key
		local show, text = true, b.base
		if k == "sales" then
			show, text = info.sales > 0, "Your sales (" .. info.inSales .. ")"
		elseif k == "buys" then
			show, text = info.buys > 0, "Your buys (" .. info.inBuys .. ")"
		elseif k == "fair" then
			show = info.fair
		elseif k == "band" then
			show = info.band
		end
		local w = 0
		local off = legendHidden(k)
		if show then
			b.label:SetText(off and (GREY .. text .. "|r") or text)
			b.sw:SetAlpha(off and 0.25 or 1)
			w = math.min(AW - x, (b.label:GetUnboundedStringWidth() or 60) + 14)
			b.label:SetWidth(math.max(1, w - 12))
			b:SetWidth(math.max(1, w))
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", 0 + x, LEGEND_Y)
			x = x + w + 14
		end
		b:SetShown(show and w >= 30)
	end
end

local function fillGraph(panel, key, fairBuy, fairSell)
	local hide = X.S().graphHide
	local ri = RANGES[X.S().itemRange] and X.S().itemRange or 2
	for i, b in ipairs(panel.ranges) do b:SetSelected(i == ri) end
	local from = X.Now() - RANGES[ri][2]
	local hist = X.History(key, from)
	local mkt, low, qty = {}, {}, {}
	for i, p in ipairs(hist) do
		mkt[i] = {p[1], p[3]}
		low[i] = {p[1], p[2]}
		qty[i] = {p[1], p[4]}
	end
	local series = {}
	if not hide.mkt then series[#series + 1] = {points = mkt, color = LEGEND[1][3], width = 2, label = "Market value"} end
	if not hide.low then series[#series + 1] = {points = low, color = LEGEND[2][3], width = 1.5, label = "Lowest price"} end
	local sales, nSales = tradeMarks(key, "sales", from, SALE, "You sold")
	local buys, nBuys = tradeMarks(key, "buys", from, BUY, "You bought")
	local marks = {}
	if not hide.sales then for _, m in ipairs(sales) do marks[#marks + 1] = m end end
	if not hide.buys then for _, m in ipairs(buys) do marks[#marks + 1] = m end end
	local empty
	if #hist == 0 and #X.History(key, 0) > 0 then empty = "No prices in this time - pick a longer range" end
	if #hist == 0 and not empty then empty = "No prices yet - a scan or a search at the auction house brings the first" end
	if #series == 0 and #marks == 0 and #hist > 0 then empty = "Everything is hidden - click the names under the graph to show them" end
	local levels = {}
	if not hide.fair and fairBuy and fairSell then
		levels[1] = {v = fairSell, color = FAIRSELL, label = "Fair to sell"}
		levels[2] = {v = fairBuy, color = FAIRBUY, label = "Fair to buy"}
	end
	-- the usual range behind the lines; the market value's points well outside it get a dot
	local band = X.UsualBand and X.UsualBand(key, from) or {}
	panel.graph:SetSeries(series, {bars = (not hide.bars) and qty or nil, barsLabel = "Listed", empty = empty, marks = marks,
		levels = levels, band = X.S().usualBand and #band > 0 and {points = band, check = (not hide.mkt) and 1 or nil} or nil})
	layoutLegend(panel, {sales = nSales, buys = nBuys, inSales = #sales, inBuys = #buys, fair = fairBuy ~= nil and #hist > 0,
		band = #band > 0 and #hist > 0})
end

-- [[ box 1: on the auction house now ]] a price ladder from the last search (every price step, how many there)
local function boxTitle(box, text)
	local t = K.Label(box, text, "GameFontNormalSmall")
	t:SetPoint("TOPLEFT", 8, -6)
	return t
end

local function ladderTip(self)
	local d = self.data
	if not d then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:AddLine(X.Num(d.qty + d.own) .. " listed at " .. X.MoneyPlain(d.unit) .. " each")
	if d.n > 1 or not d.commodity then
		GameTooltip:AddLine(d.n .. (d.commodity and " price row" or " auction") .. (d.n == 1 and "" or "s"), 0.8, 0.8, 0.8)
	end
	if d.own > 0 then GameTooltip:AddLine(X.Num(d.own) .. " of them are yours", 0.29, 0.87, 0.5) end
	if d.upQty > 0 then
		GameTooltip:AddLine("To buy everything (not yours) up to this price: " .. X.Num(d.upQty) .. " for " ..
			X.MoneyPlain(d.upCost) .. " (" .. X.MoneyPlain(math.floor(d.upCost / d.upQty + 0.5)) .. " each on average)", 1, 1, 1, true)
	end
	GameTooltip:Show()
end

local function buildLadder(panel, a)
	local box = K.Panel(a, B1, BOX_H, {0, 0, 0, 0.25})
	box:SetPoint("TOPLEFT", 0, BOX_Y)
	boxTitle(box, "On the auction house now")
	box.note = K.Label(box, "", "GameFontDisableSmall", "RIGHT")
	box.note:SetPoint("TOPRIGHT", -8, -7)
	box.note:SetWidth(100)
	box.rows = {}
	local barX, barW = 92, B1 - 92 - 70
	for i = 1, LADDER do
		local r = K.Flat(box, B1 - 10, 14)
		r:SetPoint("TOPLEFT", 5, -24 - (i - 1) * 15)
		r.label:Hide()
		r.price = K.Label(r, "", "GameFontHighlightSmall", "RIGHT")
		r.price:SetPoint("LEFT", 2, 0)
		r.price:SetWidth(barX - 8)
		r.price:SetWordWrap(false)
		r.bar = r:CreateTexture(nil, "ARTWORK")
		r.bar:SetPoint("LEFT", barX, 0)
		r.bar:SetHeight(9)
		r.barW = barW
		r.count = K.Label(r, "", "GameFontHighlightSmall", "RIGHT")
		r.count:SetPoint("RIGHT", -2, 0)
		r.count:SetWidth(64)
		r.count:SetWordWrap(false)
		r:SetScript("OnEnter", ladderTip)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:Hide()
		box.rows[i] = r
	end
	box.text = K.Label(box, "", "GameFontHighlightSmall")
	box.text:SetPoint("TOPLEFT", 10, -26)
	box.text:SetWidth(B1 - 20)
	box.text:SetJustifyV("TOP")
	box.foot = K.Label(box, "", "GameFontDisableSmall")
	box.foot:SetPoint("BOTTOMLEFT", 8, 8)
	box.foot:SetWidth(B1 - 16)
	box.foot:SetWordWrap(false)
	panel.ladder = box
end

-- the offers of a search as price steps (cheapest first): {unit, qty (not yours), own, n (auctions or rows)}
local function ladderSteps(live)
	local steps, byUnit = {}, {}
	for _, o in ipairs(live.offers or {}) do
		local st = byUnit[o.unit]
		if not st then
			st = {unit = o.unit, qty = 0, own = 0, n = 0, commodity = live.commodity}
			byUnit[o.unit] = st
			steps[#steps + 1] = st
		end
		st.qty, st.own, st.n = st.qty + (o.qty or 0), st.own + (o.own or 0), st.n + 1
	end
	table.sort(steps, function(x, y) return x.unit < y.unit end)
	local upQty, upCost = 0, 0
	for _, st in ipairs(steps) do
		upQty, upCost = upQty + st.qty, upCost + st.qty * st.unit
		st.upQty, st.upCost = upQty, upCost
	end
	return steps
end

-- away from the auction house (or before the first search): what the last scan saw
local function lastScanText(s)
	local cur = s.cur
	if not cur then return GREY .. "Not seen on the auction house yet.|r" end
	local lines = {GREY .. "The last scan (" .. X.Ago(cur.t) .. "):|r"}
	if (cur.qty or 0) == 0 then
		lines[#lines + 1] = "None listed."
	else
		lines[#lines + 1] = GREY .. "Cheapest:|r " .. M(cur.min)
		lines[#lines + 1] = GREY .. "Market value:|r " .. M(cur.mkt)
		lines[#lines + 1] = GREY .. "Listed:|r " .. X.Num(cur.qty) .. (cur.auc and (GREY .. " in " .. X.Num(cur.auc) .. " auctions|r") or "") ..
			(cur.sellers and (GREY .. " by " .. X.Num(cur.sellers) .. " sellers|r") or "")
	end
	return table.concat(lines, "\n")
end

local function fillLadder(panel, key, s)
	local box = panel.ladder
	local live = X.ahOpen and X.live[key] or nil
	for _, r in ipairs(box.rows) do r:Hide() r.data = nil end
	if not live then
		box.note:SetText("")
		if X.ahOpen then
			box.text:SetText(GREY .. "Searching the auction house ...|r\n\n" .. lastScanText(s))
			box.foot:SetText("")
		else
			box.text:SetText(lastScanText(s))
			box.foot:SetText("Open the auction house to see every listing.")
		end
		box.text:Show()
		return
	end
	box.text:Hide()
	box.note:SetText("searched " .. X.Ago(live.t))
	local steps = ladderSteps(live)
	local most = 1
	for i = 1, math.min(LADDER, #steps) do most = math.max(most, steps[i].qty + steps[i].own) end
	local all, yours = 0, 0
	for _, st in ipairs(steps) do all, yours = all + st.qty, yours + st.own end
	for i = 1, math.min(LADDER, #steps) do
		local st, r = steps[i], box.rows[i]
		r.data = st
		r.price:SetText(M(st.unit))
		r.bar:SetWidth(math.max(1, r.barW * (st.qty + st.own) / most))
		if st.qty == 0 then r.bar:SetColorTexture(0.29, 0.87, 0.5, 0.6) else r.bar:SetColorTexture(0.54, 0.64, 1, 0.7) end
		r.count:SetText(X.Num(st.qty + st.own) .. (st.own > 0 and (GREEN .. " (" .. X.Num(st.own) .. " yours)|r") or ""))
		r:Show()
	end
	if #steps == 0 then
		box.text:SetText(GREY .. "Nothing listed right now.|r")
		box.text:Show()
		box.foot:SetText("")
	elseif #steps > LADDER then
		box.foot:SetText("+ " .. (#steps - LADDER) .. " more prices, up to " .. X.MoneyPlain(steps[#steps].unit) .. ".  " ..
			X.Num(all + yours) .. " listed")
	else
		box.foot:SetText(X.Num(all + yours) .. " listed" .. (yours > 0 and (", " .. X.Num(yours) .. " of them yours") or "") ..
			". Hover a price for more.")
	end
end

-- [[ box 2: the best time to sell ]] a small weekday x time-of-day grid of the price (K.Heatmap, numbers from
-- Patterns.lua; the whole grid with supply too is on the Patterns page), the cheapest and dearest time, the best day
-- and hour in short. Clicking the grid or "Patterns" opens the Patterns page.
local function openPatterns(panel)
	X.S().itemPage = "patterns"
	refresh(panel)
end
local function buildBest(panel, a)
	local box = K.Panel(a, B2, BOX_H, {0, 0, 0, 0.25})
	box:SetPoint("TOPLEFT", B1 + 8, BOX_Y)
	local title = boxTitle(box, "Best time to sell")
	-- hovering the title: the whole story in sentences
	local hot = CreateFrame("Frame", nil, box)
	hot:SetPoint("TOPLEFT", 4, -2)
	hot:SetSize(B2 - 96, 16)
	hot:EnableMouse(true)
	hot:SetScript("OnEnter", function(self)
		local key = UI.itemKey
		if not key then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("Best time to sell")
		for _, l in ipairs(X.BestTimesText(X.BestTimes(key))) do GameTooltip:AddLine(l, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	box.title, box.hot = title, hot
	-- "Patterns": the whole grid (price and supply), how jumpy, market size
	local more = K.Flat(box, 80, 16)
	more:SetPoint("TOPRIGHT", -6, -4)
	more:SetLabel("Patterns >")
	more.label:SetJustifyH("CENTER")
	more:SetScript("OnClick", function() openPatterns(panel) end)
	K.Tooltip(more, "Patterns", "Opens the Patterns page: the big grid (price and how many are listed at each time), how " ..
		"jumpy the price is, and about how much sells a day.")
	box.more = more
	box.gridTitle = K.Label(box, "", "GameFontDisableSmall")
	box.gridTitle:SetPoint("TOPLEFT", 8, -22)
	box.gridTitle:SetWidth(B2 - 16)
	box.gridTitle:SetWordWrap(false)
	local rows = UI.PATTERN_ROWS or {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
	local cols = UI.PATTERN_COLS or {"0-4", "4-8", "8-12", "12-16", "16-20", "20-24"}
	box.grid = K.Heatmap(box, B2 - 14, 144, {rows = rows, cols = cols, labelW = 28, headH = 12, small = true,
		onClick = function() openPatterns(panel) end})
	box.grid:SetPoint("TOPLEFT", 6, -36)
	box.sum = K.Label(box, "", "GameFontHighlightSmall")
	box.sum:SetPoint("TOPLEFT", 8, -186)
	box.sum:SetWidth(B2 - 16)
	box.sum:SetWordWrap(false)
	local sumHot = CreateFrame("Frame", nil, box)
	sumHot:SetPoint("TOPLEFT", 4, -184)
	sumHot:SetSize(B2 - 8, 14)
	sumHot:EnableMouse(true)
	K.Tooltip(sumHot, "Cheapest and dearest time", "The weekday and time of day (4 hours, server time) when its market " ..
		"value was lowest and highest against its usual price, from the grid above. Buy at the cheap time, sell at the dear one.")
	box.day = K.Label(box, "", "GameFontHighlightSmall")
	box.day:SetPoint("TOPLEFT", 8, -202)
	box.day:SetWidth(B2 - 16)
	box.day:SetWordWrap(false)
	box.hour = K.Label(box, "", "GameFontHighlightSmall")
	box.hour:SetPoint("TOPLEFT", 8, -218)
	box.hour:SetWidth(B2 - 16)
	box.hour:SetWordWrap(false)
	panel.bestBox = box
	panel.best = box.grid
end

local function fillBest(panel, key)
	local box = panel.bestBox
	local bt = X.BestTimes(key)
	local _, known = X.ServerShift()
	box.gridTitle:SetText("Price by weekday and time of day " .. (known and "(server time)" or "(your clock)") ..
		" - click for more")
	local grid
	if UI.PatternGridData then
		local data
		data, grid = UI.PatternGridData(key, "price", true)
		box.grid:SetData(data)
	end
	box.sum:SetText(UI.PatternSummary and UI.PatternSummary(grid, "price") or "")
	local bd = X.BestDay and X.BestDay(key)
	if type(bd) == "table" then
		box.day:SetText("Best day to sell: " .. GOLD .. bd.name .. "|r (" .. X.BestPctText(bd.pct) .. " over the other days)")
	else
		box.day:SetText("Best day to sell: " .. GREY .. "no day clearly better yet|r")
	end
	if bt.hourEnough and bt.bestHour then
		box.hour:SetText("Best hour: " .. GOLD .. string.format("%02d:00 - %02d:00", bt.bestHour, (bt.bestHour + 1) % 24) ..
			"|r (" .. X.BestPctText(bt.hours[bt.bestHour].pct) .. ")")
	else
		box.hour:SetText("Best hour: " .. GREY .. "not enough scans yet|r")
	end
end

-- [[ box 3: crafting and your trades ]] label / value rows; a row without a label is one line across
local function buildCraft(panel, a)
	local box = K.Panel(a, B3, BOX_H, {0, 0, 0, 0.25})
	box:SetPoint("TOPLEFT", B1 + B2 + 16, BOX_Y)
	boxTitle(box, "Crafting and your trades")
	box:EnableMouse(true)
	box:SetScript("OnEnter", function(self)
		if self.rid then UI.RecipeTooltip(self, self.rid, self.itemID) end
	end)
	box:SetScript("OnLeave", function() GameTooltip:Hide() end)
	box.left, box.right = {}, {}
	for i = 1, CRAFT_ROWS do
		local y = -22 - (i - 1) * 15
		local l = K.Label(box, "", "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", 8, y)
		l:SetWidth(92)
		l:SetWordWrap(false)
		local r = K.Label(box, "", "GameFontHighlightSmall")
		r:SetWordWrap(false)
		box.left[i], box.right[i] = l, r
	end
	panel.craftBox = box
end

-- the rows of box 3: {label, value} or {nil, a line across}
local function craftRows(s, key)
	local rows = {}
	local id = s.id
	local all = X.RecipesFor(id)
	local rid = s.craftRid or all[1]
	local r = rid and X.Recipe(rid)
	if r then
		local cost, missing = X.RecipeCost(rid)
		rows[#rows + 1] = {"Crafting cost", (missing or 0) > 0 and (M(cost) .. RED .. " (" .. missing .. " without a price)|r") or
			(M(cost) .. ((r.n or 1) ~= 1 and (GREY .. " makes " .. count(r.n) .. "|r") or ""))}
		local parts = X.RecipeParts(rid)
		for i = 1, math.min(3, #parts) do
			local p = parts[i]
			rows[#rows + 1] = {nil, count(p.count) .. "x " .. X.ItemIcon(p.id, 11) .. " " .. X.ItemText(tostring(p.id)) .. "  " ..
				(p.unit and (M(p.unit * p.count) .. GREY .. " " .. (HOW[p.how] or "") .. "|r") or (RED .. "no price|r"))}
		end
		if #parts > 3 then rows[#rows + 1] = {nil, GREY .. "+ " .. (#parts - 3) .. " more reagents (hover this box)|r"} end
		rows[#rows + 1] = {"Profit (after cut)", s.craftProfit and signed(s.craftProfit) or NONE}
	else
		rows[#rows + 1] = {"Crafting", GREY .. "no recipe makes it|r"}
	end
	local using = #X.RecipesUsing(id)
	rows[#rows + 1] = {"Used in", using > 0 and (using .. " recipe" .. (using == 1 and "" or "s")) or (GREY .. "no recipes|r")}
	local li = X.LedgerItem and X.LedgerItem(key)
	if li and ((li.sold or 0) > 0 or (li.bought or 0) > 0) then
		rows[#rows + 1] = {"Your trades", "sold " .. X.Num(li.sold) .. ", bought " .. X.Num(li.bought)}
		rows[#rows + 1] = {"Average price", GREY .. "sell |r" .. M(li.avgSell) .. GREY .. ", buy |r" .. M(li.avgBuy)}
		rows[#rows + 1] = {"Your profit", signed(li.profit or 0) .. (li.sellThrough and (GREY .. ", " ..
			string.format("%.0f%%", li.sellThrough * 100) .. " of posts sold|r") or "")}
		if (li.soldPerDay or 0) > 0 then rows[#rows + 1] = {"You sell a day", X.Rate(li.soldPerDay)} end
	else
		rows[#rows + 1] = {"Your trades", GREY .. "none yet|r"}
	end
	if X.Owned then
		local total, parts = X.Owned(key)
		rows[#rows + 1] = {"You own", (total or 0) > 0 and (X.Num(total) .. (parts and (parts.bags or 0) > 0 and (parts.bags or 0) < total and
			(GREY .. " (" .. X.Num(parts.bags) .. " in bags)|r") or "")) or (GREY .. "none|r")}
	end
	local sh = X.Shape and X.Shape(key)
	if sh then
		if sh.sellers then
			rows[#rows + 1] = {"Sellers", X.Num(sh.sellers) .. (sh.topShare and (GREY .. ", the biggest has " ..
				string.format("%.0f%%", sh.topShare * 100) .. "|r") or "")}
		end
		if sh.wall then rows[#rows + 1] = {"Price wall", X.Num(sh.wall.units) .. GREY .. " at |r" .. M(sh.wall.price)} end
		if sh.reset then
			rows[#rows + 1] = {"Reset the price", GREY .. "buy " .. X.Num(sh.reset.units) .. " for |r" .. M(sh.reset.cost) ..
				GREY .. ", |r" .. signed(sh.reset.profit or 0)}
		end
	end
	local de = X.DEValue and X.DEValue(key)
	if de then rows[#rows + 1] = {"Disenchant value", M(de)} end
	return rows, rid
end

local function fillCraft(panel, key, s)
	local box = panel.craftBox
	local rows, rid = craftRows(s, key)
	box.rid, box.itemID = rid, s.id
	for i = 1, CRAFT_ROWS do
		local row, l, r = rows[i], box.left[i], box.right[i]
		r:ClearAllPoints()
		if row and row[1] then
			l:SetText(GREY .. row[1] .. "|r")
			r:SetPoint("TOPLEFT", 102, -22 - (i - 1) * 15)
			r:SetWidth(B3 - 110)
		else
			l:SetText("")
			r:SetPoint("TOPLEFT", 14, -22 - (i - 1) * 15)
			r:SetWidth(B3 - 22)
		end
		r:SetText(row and row[2] or "")
	end
end

-- [[ a recipe as a tooltip ]] profession and skill, who knows it, what it makes, every reagent with its price, the cost,
-- the price it sells for and the profit. mark = an item ID shown in green (the item shown).
local SKILL_COLORS = {"ff8040", "ffff00", "40c040", "808080"}
function UI.RecipeTooltip(owner, rid, mark)
	local r = X.Recipe(rid)
	if not r then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:AddLine(r.name or "?", 1, 0.82, 0)
	local sub = (r.prof or "Recipe") .. (r.la and (" " .. r.la) or "")
	if r.colors then
		local c = {}
		for i = 1, 4 do
			if (r.colors[i] or 0) > 0 then c[#c + 1] = "|cff" .. SKILL_COLORS[i] .. r.colors[i] .. "|r" end
		end
		sub = sub .. GREY .. "   skill-ups: |r" .. table.concat(c, " ")
	end
	GameTooltip:AddLine(sub, 0.8, 0.8, 0.8)
	local who = X.KnownBy(rid)
	if #who > 0 then
		GameTooltip:AddLine("Known by: " .. table.concat(who, ", "), 0.29, 0.87, 0.5)
	else
		GameTooltip:AddLine("None of your characters knows it (that XNAH has seen in a profession window).", 0.6, 0.6, 0.6, true)
	end
	GameTooltip:AddLine(" ")
	if r.out then
		GameTooltip:AddDoubleLine("Makes", ((r.n or 1) ~= 1 and (count(r.n) .. " x ") or "") .. X.ItemText(tostring(r.out)), 0.6, 0.6, 0.6, 1, 1, 1)
	end
	local parts, total, missing = X.RecipeParts(rid), 0, 0
	for _, p in ipairs(parts) do
		local name = X.ItemText(tostring(p.id))
		if p.id == mark then name = GREEN .. "> |r" .. name end
		local cost = p.unit and (M(p.unit * p.count) .. GREY .. " " .. (HOW[p.how] or "") .. "|r") or (RED .. "no price|r")
		GameTooltip:AddDoubleLine(count(p.count) .. " x " .. name, cost, 1, 1, 1, 1, 1, 1)
		if p.unit then total = total + p.unit * p.count else missing = missing + 1 end
	end
	GameTooltip:AddLine(" ")
	local each = r.out and (r.n or 1) ~= 1 and (GREY .. " (" .. M(total / (r.n or 1)) .. GREY .. " each)|r") or ""
	GameTooltip:AddDoubleLine("Cost of one craft", M(total) .. each, 0.6, 0.6, 0.6, 1, 1, 1)
	if missing > 0 then
		GameTooltip:AddLine(missing .. " reagent" .. (missing > 1 and "s have" or " has") .. " no price yet: the cost is too low.", 0.97, 0.44, 0.44, true)
	end
	if r.out then
		local sell = X.AfterCut(X.Price(tostring(r.out)))
		GameTooltip:AddDoubleLine("Sells for (after the cut)", sell and M(sell * (r.n or 1)) or NONE, 0.6, 0.6, 0.6, 1, 1, 1)
		if sell and missing == 0 then GameTooltip:AddDoubleLine("Profit per craft", signed(sell * (r.n or 1) - total), 0.6, 0.6, 0.6, 1, 1, 1) end
	end
	GameTooltip:Show()
end

-- [[ the Overview page ]] everything about the item on one page (the tiles, the graph and the three boxes)
local function summaryOf(key)
	if lastSummary and lastSummary.key == key then return lastSummary end
	local s = X.Summary(key)
	if X.SaleRate then s.rate = X.SaleRate(key) end
	s.fairBuy, s.fairSell = X.FairPrices(key)
	return s
end
UI.AddItemPage("overview", "Overview", function(f)
	local panel = itemPanel
	buildTiles(panel, f)
	buildGraph(panel, f)
	buildLadder(panel, f)
	buildBest(panel, f)
	buildCraft(panel, f)
end, function(f, key)
	local panel = itemPanel
	local s = summaryOf(key)
	fillTiles(panel, s)
	fillGraph(panel, key, s.fairBuy, s.fairSell)
	fillBest(panel, key)
	fillCraft(panel, key, s)
	fillLadder(panel, key, s)
end, 1, "Everything about the item: the numbers, the price graph, the auction house now, the best time to sell, " ..
	"crafting and your trades.")

-- [[ building and filling the view ]]
local function build(panel)
	itemPanel = panel
	buildList(panel)
	local a = CreateFrame("Frame", nil, panel)
	a:SetPoint("TOPLEFT", AX, 0)
	a:SetSize(AW, UI.H)
	panel.ana = a
	panel.body = a
	buildHeader(panel, a)
	buildBuy(panel, a)
	panel.pages = UI.PageBar(a, PAGES, {x = 0, y = PAGE_BUTTONS_Y, px = 0, py = PAGE_Y, pw = AW, ph = PAGE_H, name = "items",
		pick = function(key) X.S().itemPage = key refresh(panel) end})
	panel.hint = K.Label(panel, "Pick an item on the left, type a name in Add an item, or use Find at the top: everything " ..
		"about it shows here. Double-click an item on the left: its name goes into the auction house search box.", "GameFontDisable", "CENTER")
	panel.hint:SetPoint("CENTER", panel, "TOPLEFT", AX + AW / 2, -UI.H / 2)
	panel.hint:SetWidth(AW - 100)
end

-- "120 listed in 14 auctions by 6 sellers, updated 12m ago"
local function subText(s)
	local cur = s.cur
	if not cur then return GREY .. "Not seen on the auction house yet.|r" end
	local text
	if (cur.qty or 0) == 0 then
		text = "None listed"
	else
		text = X.Num(cur.qty) .. " listed" .. (cur.auc and (" in " .. X.Num(cur.auc) .. " auction" .. (cur.auc == 1 and "" or "s")) or "") ..
			(cur.sellers and (" by " .. X.Num(cur.sellers) .. " seller" .. (cur.sellers == 1 and "" or "s")) or "")
	end
	local when = ", updated " .. X.Ago(cur.t)
	if not s.fresh then when = "|cffff8040" .. when .. " (old)|r" end
	return GREY .. text .. "|r" .. when
end

-- the parts that follow searches and purchases (also on their own, without the rest): the button, and the ladder
-- while the Overview page is shown
local function fillLive(panel, key)
	if panel.ladder and panel.ladder:IsVisible() then fillLadder(panel, key, X.Summary(key)) end
	updateBuy(panel)
end

refresh = function(panel)
	fillList(panel)
	local key = UI.itemKey
	local has = key ~= nil
	panel.ana:SetShown(has)
	panel.hint:SetShown(not has)
	if not has then return end

	lastSummary = nil
	local s = summaryOf(key)
	lastSummary = s
	local tex = s.id and X.Try(C_Item.GetItemIconByID, s.id)
	panel.icon.tex:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
	panel.name:SetText(X.ItemText(key))
	local tracked = X.Watched(key)
	panel.star:SetLabel(tracked and (GOLD .. "*|r Tracked") or (GREY .. "*|r Track"))
	panel.star:SetSelected(tracked and true or false)
	panel.sub:SetText(subText(s))
	syncBuy(key)
	updateBuy(panel)
	-- the page picked (Overview at first)
	local page = UI.ShowPage(panel.pages, X.S().itemPage)
	UI.RefreshPage(panel.pages, page, key)
	lastSummary = nil
end

UI.AddTab("items", "Items", build, refresh, 1)

-- searches and purchases: the ladder and the button (not the whole view)
local function liveChanged()
	local tab = UI.tabs.items
	local panel = tab and tab.panel
	if not (panel and panel:IsVisible() and UI.itemKey) then return end
	local b = X.buy
	if b.state ~= "buying" and (b.key ~= UI.itemKey or not b.cheapest) then syncBuy(UI.itemKey) end
	fillLive(panel, UI.itemKey)
end
X.On("XNAH_BUY", liveChanged)
X.On("XNAH_LIVE", liveChanged)
