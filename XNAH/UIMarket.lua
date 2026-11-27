-- Market overview (a view of the XNAH window): every item seen on this realm's auction house in one sortable list,
-- with a strip of number tiles on top (items known, listed now, scans, rising, falling, short supply), quick filters
-- (Rising, Falling, Short supply, Flooded, Tracked, Listed now, Can be crafted, quality) and a search box.
-- Read-only: no buy or post buttons here. Click a row = that item in the Items view; right-click = the item menu.
-- There can be tens of thousands of items, so the rows are worked out once (a little per frame) after new prices
-- arrive and kept; searching and filtering only go through those rows. At most CAP rows are shown.
-- Each row has a small line of its last 7 days of prices (worked out only for the rows on screen, and kept until new
-- prices arrive). UI.MarketSpark(key) gives that line's numbers (the tracked list of the Items view uses it too).
-- Also here: UI.NumberTiles / UI.SetTile, the small number tiles the other views use too.
-- Layout (UI.W x UI.H, read when the view is built): tiles 46 high at the top; filters at y -54; the list from y -100;
-- a footer line at the bottom.
local ADDON, X = ...
local K, UI = X.K, X.UI

local CAP = 2000
local GREY = "|cff999999"
local NONE = "|cff666666-|r"

-- [[ number tiles ]] UI.NumberTiles(parent, w, n, y) -> {tile, ...}: n tiles side by side across w, top edge at y.
-- UI.SetTile(tile, value, sub): the big number and the small grey text next to it. Titles and hover help are set once:
-- UI.NumberTiles(...)[i] gets them from defs = {{title, help}, ...}.
local TILE_H = 46
function UI.NumberTiles(parent, w, defs, y)
	local n = #defs
	local gap = 6
	local tw = math.floor((w - gap * (n - 1)) / n)
	local tiles = {}
	for i, def in ipairs(defs) do
		local t = K.Panel(parent, tw, TILE_H, {0, 0, 0, 0.3})
		t:SetPoint("TOPLEFT", (i - 1) * (tw + gap), y or 0)
		t.title = K.Label(t, GREY .. def[1] .. "|r", "GameFontNormalSmall")
		t.title:SetPoint("TOPLEFT", 8, -6)
		t.title:SetWidth(tw - 16)
		t.title:SetWordWrap(false)
		t.value = K.Label(t, NONE, "GameFontHighlight")
		t.value:SetPoint("BOTTOMLEFT", 8, 7)
		t.value:SetWidth(math.floor(tw * 0.6) - 8)
		t.value:SetWordWrap(false)
		t.sub = K.Label(t, "", "GameFontDisableSmall", "RIGHT")
		t.sub:SetPoint("BOTTOMRIGHT", -8, 8)
		t.sub:SetWidth(math.floor(tw * 0.4) - 4)
		t.sub:SetWordWrap(false)
		t:EnableMouse(true)
		if def[2] then K.Tooltip(t, def[1], def[2]) end
		tiles[i] = t
	end
	return tiles
end
function UI.SetTile(t, value, sub)
	t.value:SetText(value or NONE)
	t.sub:SetText(sub and (GREY .. sub .. "|r") or "")
end

-- [[ state ]]
local rows            -- one row per known item (nil until first worked out)
local counts = {}     -- numbers for the tiles, worked out with the rows
local dirty = true    -- new prices since the rows were worked out
local building = false
local progress = ""
local refilter = true -- the search or a filter changed
local shown = {}      -- the rows that pass the search and filters, sorted (the table gets the first CAP)
-- move: nil, "up" (Rising), "down" (Falling), "short" (Short supply) or "flood" (Flooded); watch = tracked items only
local filter = {text = "", watch = false, listed = false, craft = false, q = nil, move = nil}
local MOVES = {up = true, down = true, short = true, flood = true}
X.Default("marketFilter", {}) -- the search and quick filters, kept for next time
local function saveFilter()
	X.S().marketFilter = {text = filter.text, watch = filter.watch, listed = filter.listed, craft = filter.craft, q = filter.q,
		move = filter.move}
end
local function loadFilter()
	local f = X.S().marketFilter or {}
	filter.text, filter.watch, filter.listed, filter.craft, filter.q = f.text or "", f.watch == true, f.listed == true, f.craft == true, f.q
	filter.move = MOVES[f.move or ""] and f.move or nil
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
	local sums, cnt = {}, {}
	for _, p in ipairs(X.History(key, from)) do
		local v = p[3] or p[2]
		if v and v > 0 then
			local d = math.max(1, math.min(SPARK_DAYS, math.floor((p[1] - from) / 86400) + 1))
			sums[d], cnt[d] = (sums[d] or 0) + v, (cnt[d] or 0) + 1
		end
	end
	local vals = {}
	for d = 1, SPARK_DAYS do
		if cnt[d] then vals[#vals + 1] = {d, sums[d] / cnt[d]} end
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
UI.MarketSpark = sparkOf

X.On("XNAH_PRICES", function()
	dirty = true
	sparks = {}
end)
X.On("XNAH_WATCH", function() if filter.watch then refilter = true end end)
X.On("XNAH_RECIPES", function() if filter.craft then refilter = true end end)

-- [[ rows ]]
-- Rising / Falling / Short supply / Flooded: the same rules as X.Movers (Market.lua) - enough days of history, a fresh
-- price, and the price or the number listed going that way
local function isMover(r, kind)
	if r.stale or not r.t or r.days < X.S().minSamples then return false end
	if kind == "up" then return r.trend ~= nil and r.trend > 0 end
	if kind == "down" then return r.trend ~= nil and r.trend < 0 end
	if kind == "short" then return r.supply ~= nil and r.supply <= -40 and (r.trend or 0) >= -5 and (r.qty7 or 0) >= 5 end
	if kind == "flood" then return r.supply ~= nil and r.supply >= 60 and (r.qty7 or 0) >= 5 end
	return false
end

local function makeRow(key, it)
	local cur = it.cur or {}
	local st = X.Stats(it) or {}
	local id = it.id or X.KeyID(key)
	local usual = st.avg30 or st.avg7 or st.avg3
	local vs
	if cur.min and usual and usual > 0 and (cur.qty or 0) > 0 then vs = (cur.min / usual - 1) * 100 end
	return {key = key, id = id, name = (it.n or ""):lower(), q = it.q or 1, min = cur.min, mkt = cur.mkt, usual = usual, vs = vs,
		trend = st.trend, vol = st.vol, supply = st.supply, qty7 = st.qty7, days = st.days or 0, qty = cur.qty, t = cur.t,
		stale = not X.Fresh(it)}
end

local function startRows()
	if building then return end
	building, dirty = true, false
	local items = X.Items()
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local out, i = {}, 0
	local c = {known = 0, listed = 0, up = 0, down = 0, short = 0, flood = 0}
	progress = "Reading prices: 0 / " .. X.Num(#keys)
	X.Job("market rows", function()
		local stop = math.min(#keys, i + 150) -- (300 a frame took too long on a real auction house of 8,000+ items)
		while i < stop do
			i = i + 1
			local it = items[keys[i]]
			if it then
				local r = makeRow(keys[i], it)
				out[#out + 1] = r
				c.known = c.known + 1
				if (r.qty or 0) > 0 then c.listed = c.listed + 1 end
				for kind in pairs(MOVES) do if isMover(r, kind) then c[kind] = c[kind] + 1 end end
			end
		end
		progress = "Reading prices: " .. X.Num(i) .. " / " .. X.Num(#keys)
		return i >= #keys
	end, function()
		building = false
		rows, counts = out, c
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
	if filter.move and not isMover(r, filter.move) then return false end
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

-- [[ the columns ]]
local function money(v, stale) return UI.MoneyCell(v, stale) end
local function rateOf(r)
	if r.rate == nil then r.rate = X.SaleRate and X.SaleRate(r.key) or false end
	return r.rate or nil
end
-- ups and downs: how much the price moves from day to day (% spread); steady under 10%, wild over 25%
local function volText(v)
	if not v then return NONE end
	local col = v < 10 and "|cff4ade80" or (v < 25 and "|cffffd100" or "|cfff87171")
	return col .. string.format("%.0f%%", v) .. "|r"
end
UI.VolText = volText
local TREND_COL, SUPPLY_COL, SPARK_COL = 5, 9, 10
local COLUMNS = {
	{"Item", 274, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return r.name end, desc = false},
	{"Cheapest", 78, "RIGHT", text = function(r)
		if r.qty == 0 then return GREY .. "none|r" end
		return money(r.min, r.stale)
	end, sort = function(r) return r.min end},
	{"Market value", 78, "RIGHT", text = function(r) return money(r.mkt, r.stale) end, sort = function(r) return r.mkt end},
	-- the cheapest listing against the usual price (30-day average, else 7 or 3 days): under = cheap now
	{"vs usual", 58, "RIGHT", text = function(r) return r.vs and X.Pct(r.vs, true) or NONE end, sort = function(r) return r.vs end},
	{"Trend/wk", 70, "RIGHT", text = function(r)
		if not r.trend then return NONE end
		return X.Arrow(r.trend) .. " " .. X.Pct(r.trend)
	end, sort = function(r) return r.trend end},
	{"Ups & downs", 64, "RIGHT", text = function(r) return volText(r.vol) end, sort = function(r) return r.vol end},
	{"Sells a day", 64, "RIGHT", text = function(r)
		local rate = rateOf(r)
		return rate and X.Rate(rate) or NONE
	end, sort = rateOf},
	{"Listed", 52, "RIGHT", text = function(r)
		if r.qty == nil then return NONE end
		return (r.qty == 0 and GREY or "") .. X.Num(r.qty) .. (r.qty == 0 and "|r" or "")
	end, sort = function(r) return r.qty end},
	-- listed now against the 7-day average number listed
	{"vs normal", 60, "RIGHT", text = function(r) return r.supply and X.Pct(r.supply, true) or NONE end,
		sort = function(r) return r.supply end},
	-- the 7-day line is drawn over this cell (no sorting: it would have to read the history of every item)
	{"7 days", 64, "LEFT", text = function(r) return sparkOf(r.key) and "" or "|cff666666  -|r" end},
	{"Seen", 58, "RIGHT", text = function(r)
		if not r.t then return GREY .. "never|r" end
		return (r.stale and "|cff777777" or "") .. X.Ago(r.t) .. (r.stale and "|r" or "")
	end, sort = function(r) return r.t end},
}
-- the sorting each quick filter starts with: {column, descending}
local MOVE_SORT = {up = {TREND_COL, true}, down = {TREND_COL, false}, short = {SUPPLY_COL, false}, flood = {SUPPLY_COL, true}}
local MOVE_NAMES = {up = "rising", down = "falling", short = "in short supply", flood = "flooded"}

local TILES = {
	{"Items known", "Every item XNAH has seen on this realm's auction house."},
	{"Listed now", "Items that were on the auction house at the last scan."},
	{"Scans, last 24 h", "Scans of the auction house in the last 24 hours (full scans and searches), and how long ago the " ..
		"last full scan was."},
	{"Rising", "Items whose price goes up (a fresh price and a few days of history needed)."},
	{"Falling", "Items whose price goes down."},
	{"Short supply", "Far fewer listed than usual while the price holds: a chance to sell. Next to it: how many are " ..
		"flooded (far more listed than usual: wait before selling)."},
}

local function refreshTiles(panel)
	local t = panel.tiles
	if not rows then
		for i = 1, #t do UI.SetTile(t[i], building and (GREY .. "...|r") or nil) end
	else
		UI.SetTile(t[1], X.Num(counts.known))
		UI.SetTile(t[2], X.Num(counts.listed), counts.known > 0 and (math.floor(counts.listed / counts.known * 100 + 0.5) .. "%") or nil)
		UI.SetTile(t[4], X.Num(counts.up))
		UI.SetTile(t[5], X.Num(counts.down))
		UI.SetTile(t[6], X.Num(counts.short), X.Num(counts.flood) .. " flooded")
	end
	local realm = X.Realm()
	local since, n = X.Now() - 86400, 0
	for _, s in ipairs(realm.scans or {}) do if (s.t or 0) >= since then n = n + 1 end end
	UI.SetTile(t[3], X.Num(n), "full " .. X.Ago(realm.lastFull))
end

-- [[ the view ]]
local function build(panel)
	local W, H = UI.W, UI.H
	local cols = {}
	local fixed = 0
	for i, c in ipairs(COLUMNS) do
		cols[i] = c
		if i > 1 then fixed = fixed + c[2] end
	end
	-- the item column takes the room left (the list leaves 20 for its edges and scroll bar)
	cols[1] = {COLUMNS[1][1], math.max(160, W - 20 - fixed), "LEFT", text = COLUMNS[1].text, sort = COLUMNS[1].sort, desc = false}

	panel.tiles = UI.NumberTiles(panel, W, TILES, 0)

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
		for kind in pairs(MOVES) do buttons[kind]:SetSelected(filter.move == kind) end
	end
	-- Rising / Falling / Short supply / Flooded start with their own sorting; the sorting picked before comes back
	-- when switched off
	local before
	local function setMove(move)
		local tbl = panel.tbl
		if move and not filter.move then before = {tbl.sortCol, tbl.sortDesc} end
		filter.move = move
		if move then
			tbl.sortCol, tbl.sortDesc = MOVE_SORT[move][1], MOVE_SORT[move][2]
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
	local FY = -(TILE_H + 8)
	local x = 0
	local function add(id, text, w, onClick, tipTitle, tip)
		local b = K.Flat(panel, w, 22)
		b:SetPoint("TOPLEFT", x, FY)
		b:SetLabel(text)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function(self) onClick(self) end)
		if tip then K.Tooltip(b, tipTitle, tip) end
		buttons[id] = b
		x = x + w + 4
		return b
	end
	local search
	add("all", "All", 40, function()
		filter.watch, filter.listed, filter.craft, filter.q, filter.text = false, false, false, nil, ""
		setMove(nil)
		search:SetText("")
		changed()
	end)
	local function moveButton(kind, text, w, tip)
		add(kind, text, w, function()
			setMove(filter.move ~= kind and kind or nil)
			changed()
		end, text, tip .. " Needs " .. X.S().minSamples .. "+ days of scans per item and a fresh price.")
	end
	moveButton("up", "Rising", 56, "Only items whose price goes up, fastest rise first (Trend/wk = change a week). " ..
		"A good time to sell what you hold.")
	moveButton("down", "Falling", 56, "Only items whose price goes down, fastest fall first. Sell soon, or wait and " ..
		"buy cheap later.")
	moveButton("short", "Short supply", 82, "Far fewer listed than usual (vs normal) while the price holds: a chance " ..
		"to sell at a good price.")
	moveButton("flood", "Flooded", 60, "Far more listed than usual: prices may drop, better wait before selling.")
	add("watch", "Tracked", 60, function() filter.watch = not filter.watch changed() end, "Tracked",
		"Only the items on your tracked list (right-click an item to add or remove it).")
	add("listed", "Listed now", 72, function() filter.listed = not filter.listed changed() end, "Listed now",
		"Only items that were on the auction house at the last scan.")
	add("craft", "Can be crafted", 96, function() filter.craft = not filter.craft changed() end, "Can be crafted",
		"Only items a recipe makes (any recipe of the game, also ones your characters do not know).")
	add("q", "Quality: any", 116, function(self)
		local items = {{text = "Lowest quality to show", isTitle = true},
			{text = "Any quality", checked = filter.q == nil, func = function() filter.q = nil changed() end}}
		for q = 0, 5 do
			items[#items + 1] = {text = "|cff" .. X.QUALITY_HEX[q] .. X.QUALITY_NAMES[q] .. "|r" .. (q < 5 and " or better" or ""),
				checked = filter.q == q, func = function() filter.q = q changed() end}
		end
		K.Menu(self, items)
	end)
	-- search box (the rest of the line)
	local label = K.Label(panel, "Search", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", x + 6, FY - 5)
	search = K.Edit(panel, math.max(100, W - x - 58))
	search:SetPoint("TOPLEFT", x + 52, FY - 1)
	panel.search = search
	loadFilter()
	search:SetText(filter.text or "")
	search:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		filter.text = self:GetText() or ""
		X.Debounce("xnah-market-search", 0.3, changed)
	end)
	panel.buttons = buttons

	-- the list
	local TY = TILE_H + 8 + 22 + 24 -- headers sit just above it
	local tbl = K.Table(panel, W, H - TY - 20, cols, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	tbl:SetPoint("TOPLEFT", 0, -TY)
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
	if filter.move then tbl.sortCol, tbl.sortDesc = MOVE_SORT[filter.move][1], MOVE_SORT[filter.move][2] end
	panel.tbl = tbl

	-- footer
	local footer = K.Label(panel, "", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", 2, 4)
	footer:SetWidth(W - 260)
	footer:SetWordWrap(false)
	local help = K.Label(panel, GREY .. "Click: see the item   Right-click: menu|r", "GameFontDisableSmall", "RIGHT")
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
			tbl.empty:SetText("No prices yet. Open the auction house and do a full scan (Settings, or the XNAH bar on the " ..
				"auction house window).")
		elseif filter.move then
			tbl.empty:SetText("Nothing " .. MOVE_NAMES[filter.move] .. " here. This needs at least " .. X.S().minSamples ..
				" days of scans per item (one full scan a day is enough) and a fresh price.")
		else
			tbl.empty:SetText("Nothing matches the search and filters.")
		end
		refreshTiles(panel)
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

UI.AddTab("market", "Market", build, refresh, 2)
