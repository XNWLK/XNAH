-- Market tab: every item seen on this realm's auction house in one sortable list, with a search box and quick filters.
-- There can be tens of thousands of items, so the rows are worked out once (a little per frame) after new prices
-- arrive and kept; searching and filtering only go through those rows. At most CAP rows are shown.
local ADDON, X = ...
local K, UI = X.K, X.UI

local CAP = 2000
local GREY = "|cff999999"

local rows            -- one row per known item (nil until first worked out)
local dirty = true    -- new prices since the rows were worked out
local building = false
local progress = ""
local refilter = true -- the search or a filter changed
local shown = {}      -- the rows that pass the search and filters, sorted (the table gets the first CAP)
local filter = {text = "", watch = false, listed = false, craft = false, q = nil}

X.On("XNAH_PRICES", function() dirty = true end)
X.On("XNAH_WATCH", function() if filter.watch then refilter = true end end)
X.On("XNAH_RECIPES", function() if filter.craft then refilter = true end end)

-- [[ rows ]]
local function makeRow(key, it)
	local cur = it.cur or {}
	local st = X.Stats(it) or {}
	local id = it.id or X.KeyID(key)
	local vs = X.db.vsell[id] -- only the saved value here (asking the game for 20,000 items would be slow)
	return {key = key, id = id, name = (it.n or ""):lower(), q = it.q or 1, min = cur.min, mkt = cur.mkt, avg7 = st.avg7,
		trend = st.trend, qty = cur.qty, vsell = (vs and vs > 0) and vs or nil, t = cur.t, stale = not X.Fresh(it)}
end

local function startRows()
	if building then return end
	building, dirty = true, false
	local items = X.Items()
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local out, i = {}, 0
	progress = "Reading prices: 0 / " .. X.Num(#keys)
	X.Job("market rows", function()
		local stop = math.min(#keys, i + 300)
		while i < stop do
			i = i + 1
			local it = items[keys[i]]
			if it then out[#out + 1] = makeRow(keys[i], it) end
		end
		progress = "Reading prices: " .. X.Num(i) .. " / " .. X.Num(#keys)
		return i >= #keys
	end, function()
		building = false
		rows = out
		refilter = true
		if UI.current == "market" then UI.Refresh(true) end
	end)
end

-- [[ sorting all rows ]] (the table itself would only sort the rows it shows)
local function sortRows(list, col, desc)
	local f = col and col.sort
	if not f then return end
	local vals = {}
	for i = 1, #list do
		local r = list[i]
		vals[r] = f(r)
	end
	table.sort(list, function(a, b)
		local va, vb = vals[a], vals[b]
		if va == vb then return a.key < b.key end
		if va == nil then return false end
		if vb == nil then return true end
		if desc then return va > vb end
		return va < vb
	end)
end

local function passes(r, text, num, items)
	if r.name == "" then -- the name may have arrived since
		local it = items[r.key]
		if it and it.n then r.name, r.q = it.n:lower(), it.q or r.q end
	end
	if text ~= "" and not (r.name:find(text, 1, true) or (num and r.id == num) or r.key == text) then return false end
	if filter.q and (r.q or 1) < filter.q then return false end
	if filter.watch and not X.Watched(r.key) then return false end
	if filter.listed and (r.qty or 0) <= 0 then return false end
	if filter.craft and #X.RecipesFor(r.id) == 0 then return false end
	return true
end

local function applyFilter(tbl)
	refilter = false
	local text = X.Trim(filter.text):lower()
	local num = tonumber(text)
	local items = X.Items()
	shown = {}
	for _, r in ipairs(rows or {}) do
		if passes(r, text, num, items) then shown[#shown + 1] = r end
	end
	tbl.offset = 0
	tbl:Sort()
end

-- [[ the tab ]]
local function money(v, stale) return UI.MoneyCell(v, stale) end
local COLUMNS = {
	{"Item", 290, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return r.name end, desc = false},
	{"Lowest", 90, "RIGHT", text = function(r)
		if r.qty == 0 then return GREY .. "none|r" end
		return money(r.min, r.stale)
	end, sort = function(r) return r.min end},
	{"Market", 90, "RIGHT", text = function(r) return money(r.mkt, r.stale) end, sort = function(r) return r.mkt end},
	{"7-day avg", 90, "RIGHT", text = function(r) return money(r.avg7) end, sort = function(r) return r.avg7 end},
	{"Trend", 72, "RIGHT", text = function(r)
		if not r.trend then return "|cff666666-|r" end
		return X.Arrow(r.trend) .. " " .. X.Pct(r.trend)
	end, sort = function(r) return r.trend end},
	{"Listed", 62, "RIGHT", text = function(r)
		if r.qty == nil then return "|cff666666-|r" end
		return (r.qty == 0 and GREY or "") .. X.Num(r.qty) .. (r.qty == 0 and "|r" or "")
	end, sort = function(r) return r.qty end},
	{"Vendor pays", 90, "RIGHT", text = function(r)
		local v = r.vsell or X.VendorSell(r.id)
		if v then r.vsell = v end
		return v and X.Money(v, true) or "|cff666666-|r"
	end, sort = function(r) return r.vsell end},
	-- sells per day (estimate; filled in as rows are shown or sorted)
	{"Sold/day", 64, "RIGHT", text = function(r)
		if r.rate == nil then r.rate = X.SaleRate and X.SaleRate(r.key) or false end
		return r.rate and X.Rate(r.rate) or "|cff666666-|r"
	end, sort = function(r)
		if r.rate == nil then r.rate = X.SaleRate and X.SaleRate(r.key) or false end
		return r.rate or nil
	end},
	{"Seen", 80, "RIGHT", text = function(r)
		if not r.t then return GREY .. "never|r" end
		return (r.stale and "|cff777777" or "") .. X.Ago(r.t) .. (r.stale and "|r" or "")
	end, sort = function(r) return r.t end},
}

local function build(panel)
	local W = UI.W
	-- search box
	local label = K.Label(panel, "Search", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 0, -6)
	local search = K.Edit(panel, 200)
	search:SetPoint("TOPLEFT", 52, -2)
	panel.search = search

	-- quick filters
	local buttons = {}
	local function mark()
		local any = filter.watch or filter.listed or filter.craft or filter.q ~= nil or X.Trim(filter.text) ~= ""
		buttons.all:SetSelected(not any)
		buttons.watch:SetSelected(filter.watch)
		buttons.listed:SetSelected(filter.listed)
		buttons.craft:SetSelected(filter.craft)
		buttons.q:SetSelected(filter.q ~= nil)
		buttons.q:SetLabel(filter.q and ("Quality: |cff" .. X.QUALITY_HEX[filter.q] .. X.QUALITY_NAMES[filter.q] .. "|r+") or "Quality: any")
	end
	local function changed()
		refilter = true
		mark()
		if rows then applyFilter(panel.tbl) end
		panel.footerUpdate()
	end
	local x = 270
	local function add(id, text, w, onClick)
		local b = K.Flat(panel, w, 22)
		b:SetPoint("TOPLEFT", x, -1)
		b:SetLabel(text)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function(self) onClick(self) end)
		buttons[id] = b
		x = x + w + 4
		return b
	end
	add("all", "All", 50, function()
		filter.watch, filter.listed, filter.craft, filter.q, filter.text = false, false, false, nil, ""
		search:SetText("")
		changed()
	end)
	add("watch", "Watch list", 84, function() filter.watch = not filter.watch changed() end)
	K.Tooltip(buttons.watch, "Watch list", "Only the items you starred (right-click an item to star it).")
	add("listed", "Listed now", 84, function() filter.listed = not filter.listed changed() end)
	K.Tooltip(buttons.listed, "Listed now", "Only items that were on the auction house at the last scan.")
	add("craft", "Can be crafted", 104, function() filter.craft = not filter.craft changed() end)
	K.Tooltip(buttons.craft, "Can be crafted", "Only items a known recipe makes (recipes are read from profession windows).")
	add("q", "Quality: any", 130, function(self)
		local items = {{text = "Lowest quality to show", isTitle = true},
			{text = "Any quality", checked = filter.q == nil, func = function() filter.q = nil changed() end}}
		for q = 0, 5 do
			items[#items + 1] = {text = "|cff" .. X.QUALITY_HEX[q] .. X.QUALITY_NAMES[q] .. "|r" .. (q < 5 and " or better" or ""),
				checked = filter.q == q, func = function() filter.q = q changed() end}
		end
		K.Menu(self, items)
	end)
	search:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		filter.text = self:GetText() or ""
		X.Debounce("xnah-market-search", 0.3, changed)
	end)

	-- the list
	local tbl = K.Table(panel, W, 478, COLUMNS, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	tbl:SetPoint("TOPLEFT", 0, -48)
	tbl:SortBy(3, true) -- market value, highest first
	-- sorting goes through every row that passes the filters, then the first CAP are shown
	function tbl:Sort()
		sortRows(shown, self.sortCol and self.columns[self.sortCol], self.sortDesc)
		local items = {}
		for i = 1, math.min(CAP, #shown) do items[i] = shown[i] end
		self.items = items
		for i, hdr in ipairs(self.headers or {}) do
			local m = (i == self.sortCol) and (self.sortDesc and " v" or " ^") or ""
			hdr:SetText(GREY .. self.columns[i][1] .. m .. "|r")
		end
		self:Refresh()
	end
	panel.tbl = tbl

	-- footer
	local footer = K.Label(panel, "", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", 2, 4)
	footer:SetWidth(W - 260)
	footer:SetWordWrap(false)
	local help = K.Label(panel, GREY .. "Click: item page   Right-click: menu|r", "GameFontDisableSmall", "RIGHT")
	help:SetPoint("BOTTOMRIGHT", -2, 4)
	help:SetWidth(250)
	function panel.footerUpdate()
		local total = rows and #rows or 0
		local text = X.Num(total) .. " items, last full scan " .. X.Ago(X.Realm().lastFull)
		if building then text = text .. "   " .. progress end
		if rows and #shown ~= total then text = text .. "   -   " .. X.Num(#shown) .. " match" end
		if #shown > CAP then text = text .. "   |cffffd100showing the first " .. X.Num(CAP) .. " - search to narrow|r" end
		footer:SetText(text)
		if not rows then
			tbl.empty:SetText("Reading prices...")
		elseif total == 0 then
			tbl.empty:SetText("No prices yet. Open the auction house and start a full scan (Scan tab).")
		else
			tbl.empty:SetText("Nothing matches the search and filters.")
		end
	end
	mark()
end

local function refresh(panel)
	if dirty and not building then startRows() end
	if refilter and rows then
		applyFilter(panel.tbl)
	else
		panel.tbl:Refresh() -- stars, "seen" times
	end
	panel.footerUpdate()
end

UI.AddTab("market", "Market", build, refresh, 1)
