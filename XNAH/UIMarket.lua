-- Market page: every item seen on this realm's auction house in one sortable list, with a search box and quick filters.
-- There can be tens of thousands of items, so the rows are worked out once (a little per frame) after new prices
-- arrive and kept; searching and filtering only go through those rows. At most CAP rows are shown.
-- Rising / Falling (the old Trends page): only items whose price went up / down over the last two weeks, biggest
-- change first. Each row has a small line of its last 7 days of prices (worked out only for the rows on screen, and
-- kept until new prices arrive).
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
-- move: nil, "up" (Rising) or "down" (Falling)
local filter = {text = "", watch = false, listed = false, craft = false, q = nil, move = nil}
X.Default("marketFilter", {}) -- the search and quick filters, kept for next time
local function saveFilter()
	X.S().marketFilter = {text = filter.text, watch = filter.watch, listed = filter.listed, craft = filter.craft, q = filter.q,
		move = filter.move}
end
local function loadFilter()
	local f = X.S().marketFilter or {}
	filter.text, filter.watch, filter.listed, filter.craft, filter.q = f.text or "", f.watch == true, f.listed == true, f.craft == true, f.q
	filter.move = (f.move == "up" or f.move == "down") and f.move or nil
end

-- [[ the 7-day line ]] per item: {pts = {{x 0..1, y 0..1}, ...}, change (% first to last day), color} or false
local SPARK_DAYS = 7
local SPARK_W, SPARK_H = 56, 12
local sparks = {}
local function sparkOf(key)
	local c = sparks[key]
	if c ~= nil then return c end
	c = false
	local from = X.Now() - SPARK_DAYS * 86400
	local sums, counts = {}, {}
	for _, p in ipairs(X.History(key, from)) do
		local v = p[3] or p[2]
		if v and v > 0 then
			local d = math.max(1, math.min(SPARK_DAYS, math.floor((p[1] - from) / 86400) + 1))
			sums[d], counts[d] = (sums[d] or 0) + v, (counts[d] or 0) + 1
		end
	end
	local vals = {}
	for d = 1, SPARK_DAYS do
		if counts[d] then vals[#vals + 1] = {d, sums[d] / counts[d]} end
	end
	if #vals >= 2 then
		local lo, hi = math.huge, 0
		for _, v in ipairs(vals) do lo, hi = math.min(lo, v[2]), math.max(hi, v[2]) end
		local flat = hi - lo < hi * 0.01
		local pts = {}
		for i, v in ipairs(vals) do
			pts[i] = {(v[1] - 1) / (SPARK_DAYS - 1), flat and 0.5 or (v[2] - lo) / (hi - lo)}
		end
		local first, last = vals[1][2], vals[#vals][2]
		local change = (last - first) / first * 100
		local color = change >= 3 and {0.29, 0.87, 0.5} or change <= -3 and {0.97, 0.44, 0.44} or {0.7, 0.7, 0.7}
		c = {pts = pts, change = change, color = color}
	end
	sparks[key] = c
	return c
end
-- draws the line of one row (a few line pieces per row, made once; rows are reused while scrolling)
local function drawSpark(rowFrame, r, col)
	local s = rowFrame.spark
	if not s then
		if not rowFrame.cols or not rowFrame.cols[col] then return end
		s = CreateFrame("Frame", nil, rowFrame)
		s:SetSize(SPARK_W, SPARK_H)
		s:SetPoint("LEFT", rowFrame.cols[col], "LEFT", 4, 0)
		s.lines = {}
		rowFrame.spark = s
	end
	local c = r and sparkOf(r.key)
	local n = 0
	if c then
		local col3 = c.color
		for i = 2, #c.pts do
			n = n + 1
			local l = s.lines[n]
			if not l then
				l = s:CreateLine(nil, "ARTWORK")
				l:SetThickness(1.5)
				s.lines[n] = l
			end
			local a, b = c.pts[i - 1], c.pts[i]
			l:SetColorTexture(col3[1], col3[2], col3[3], 0.95)
			l:SetStartPoint("BOTTOMLEFT", s, a[1] * SPARK_W, a[2] * SPARK_H)
			l:SetEndPoint("BOTTOMLEFT", s, b[1] * SPARK_W, b[2] * SPARK_H)
			l:Show()
		end
	end
	for i = n + 1, #s.lines do s.lines[i]:Hide() end
end
-- for the tests
UI.MarketSpark = sparkOf

X.On("XNAH_PRICES", function()
	dirty = true
	sparks = {}
end)
X.On("XNAH_WATCH", function() if filter.watch then refilter = true end end)
X.On("XNAH_RECIPES", function() if filter.craft then refilter = true end end)

-- [[ rows ]]
local function makeRow(key, it)
	local cur = it.cur or {}
	local st = X.Stats(it) or {}
	local id = it.id or X.KeyID(key)
	local vs = X.db.vsell[id] -- only the saved value here (asking the game for 20,000 items would be slow)
	return {key = key, id = id, name = (it.n or ""):lower(), q = it.q or 1, min = cur.min, mkt = cur.mkt, avg7 = st.avg7,
		trend = st.trend, days = st.days or 0, qty = cur.qty, vsell = (vs and vs > 0) and vs or nil, t = cur.t, stale = not X.Fresh(it)}
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
	if filter.move then
		-- the same test as the old Trends page: enough days of history, a fresh price, a price going that way
		if r.stale or not r.trend or r.days < X.S().minSamples then return false end
		if filter.move == "up" and r.trend <= 0 then return false end
		if filter.move == "down" and r.trend >= 0 then return false end
	end
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
local TREND_COL, SPARK_COL = 5, 6
local COLUMNS = {
	{"Item", 250, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return r.name end, desc = false},
	{"Lowest", 84, "RIGHT", text = function(r)
		if r.qty == 0 then return GREY .. "none|r" end
		return money(r.min, r.stale)
	end, sort = function(r) return r.min end},
	{"Market", 84, "RIGHT", text = function(r) return money(r.mkt, r.stale) end, sort = function(r) return r.mkt end},
	{"7-day avg", 84, "RIGHT", text = function(r) return money(r.avg7) end, sort = function(r) return r.avg7 end},
	{"Trend", 64, "RIGHT", text = function(r)
		if not r.trend then return "|cff666666-|r" end
		return X.Arrow(r.trend) .. " " .. X.Pct(r.trend)
	end, sort = function(r) return r.trend end},
	-- the 7-day line is drawn over this cell (no sorting: it would have to read the history of every item)
	{"7 days", 66, "LEFT", text = function(r) return sparkOf(r.key) and "" or "|cff666666  -|r" end},
	{"Listed", 56, "RIGHT", text = function(r)
		if r.qty == nil then return "|cff666666-|r" end
		return (r.qty == 0 and GREY or "") .. X.Num(r.qty) .. (r.qty == 0 and "|r" or "")
	end, sort = function(r) return r.qty end},
	{"Vendor pays", 80, "RIGHT", text = function(r)
		local v = r.vsell or X.VendorSell(r.id)
		if v then r.vsell = v end
		return v and X.Money(v, true) or "|cff666666-|r"
	end, sort = function(r) return r.vsell end},
	-- sells per day (estimate; filled in as rows are shown or sorted)
	{"Sells a day", 70, "RIGHT", text = function(r)
		if r.rate == nil then r.rate = X.SaleRate and X.SaleRate(r.key) or false end
		return r.rate and X.Rate(r.rate) or "|cff666666-|r"
	end, sort = function(r)
		if r.rate == nil then r.rate = X.SaleRate and X.SaleRate(r.key) or false end
		return r.rate or nil
	end},
	{"Seen", 66, "RIGHT", text = function(r)
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
	loadFilter()
	search:SetText(filter.text or "")

	-- quick filters
	local buttons = {}
	local function mark()
		local any = filter.watch or filter.listed or filter.craft or filter.q ~= nil or filter.move ~= nil or X.Trim(filter.text) ~= ""
		buttons.all:SetSelected(not any)
		buttons.watch:SetSelected(filter.watch)
		buttons.listed:SetSelected(filter.listed)
		buttons.craft:SetSelected(filter.craft)
		buttons.q:SetSelected(filter.q ~= nil)
		buttons.q:SetLabel(filter.q and ("Quality: |cff" .. X.QUALITY_HEX[filter.q] .. X.QUALITY_NAMES[filter.q] .. "|r+") or "Quality: any")
		buttons.up:SetSelected(filter.move == "up")
		buttons.down:SetSelected(filter.move == "down")
	end
	-- Rising / Falling sort by the trend (biggest change first); the sorting picked before comes back when switched off
	local before
	local function setMove(move)
		local tbl = panel.tbl
		if move and not filter.move then before = {tbl.sortCol, tbl.sortDesc} end
		filter.move = move
		if move then
			tbl.sortCol, tbl.sortDesc = TREND_COL, move == "up"
		elseif before then
			tbl.sortCol, tbl.sortDesc = before[1], before[2]
			before = nil
		end
	end
	local function changed()
		refilter = true
		saveFilter()
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
		setMove(nil)
		search:SetText("")
		changed()
	end)
	add("watch", "Watch list", 84, function() filter.watch = not filter.watch changed() end)
	K.Tooltip(buttons.watch, "Watch list", "Only the items you starred (right-click an item to star it).")
	add("listed", "Listed now", 84, function() filter.listed = not filter.listed changed() end)
	K.Tooltip(buttons.listed, "Listed now", "Only items that were on the auction house at the last scan.")
	add("craft", "Can be crafted", 104, function() filter.craft = not filter.craft changed() end)
	K.Tooltip(buttons.craft, "Can be crafted", "Only items a recipe makes (any recipe of the game, also ones your characters do not know).")
	add("q", "Quality: any", 130, function(self)
		local items = {{text = "Lowest quality to show", isTitle = true},
			{text = "Any quality", checked = filter.q == nil, func = function() filter.q = nil changed() end}}
		for q = 0, 5 do
			items[#items + 1] = {text = "|cff" .. X.QUALITY_HEX[q] .. X.QUALITY_NAMES[q] .. "|r" .. (q < 5 and " or better" or ""),
				checked = filter.q == q, func = function() filter.q = q changed() end}
		end
		K.Menu(self, items)
	end)
	add("up", "Rising", 64, function()
		setMove(filter.move ~= "up" and "up" or nil)
		changed()
	end)
	K.Tooltip(buttons.up, "Rising prices", "Only items whose price went up over the last two weeks, fastest rise first " ..
		"(Trend = change a week). A good time to sell what you hold. Needs a few days of scans and a fresh price.")
	add("down", "Falling", 64, function()
		setMove(filter.move ~= "down" and "down" or nil)
		changed()
	end)
	K.Tooltip(buttons.down, "Falling prices", "Only items whose price went down over the last two weeks, fastest fall " ..
		"first. Sell soon, or wait and buy cheap later. Needs a few days of scans and a fresh price.")
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
	-- after the rows are filled: the 7-day lines of the rows on screen
	local baseRefresh = tbl.Refresh
	function tbl:Refresh()
		baseRefresh(self)
		for i, rowFrame in ipairs(self.rows) do
			local r = self.items[i + self.offset]
			if r or rowFrame.spark then drawSpark(rowFrame, r, SPARK_COL) end
		end
	end
	if filter.move then tbl.sortCol, tbl.sortDesc = TREND_COL, filter.move == "up" end
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
		elseif filter.move then
			tbl.empty:SetText("Nothing " .. (filter.move == "up" and "rising" or "falling") .. " here. Rising and Falling " ..
				"need at least " .. X.S().minSamples .. " days of scans per item (one full scan a day is enough) and a fresh price.")
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
