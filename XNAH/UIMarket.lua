-- Market overview (a view of the XNAH window): every item seen on this realm's auction house in one sortable list,
-- with a strip of number tiles on top (items known, listed now, scans, rising, falling, short supply), quick filters
-- (Rising, Falling, Short supply, Flooded, Tracked, Listed now, Can be crafted, quality) and a search box.
-- Read-only: no buy or post buttons here. Click a row = that item in the Items view; right-click = the item menu.
-- There can be tens of thousands of items, so nothing big happens in one frame (the game would stutter): the rows are
-- worked out once (a little per frame) after new prices arrive and kept; the order of all rows by a column is worked
-- out once (values, then a merge sort that can stop after any number of steps) and kept until new rows (the last
-- MAX_ORDERS columns); a search or filter then only walks the sorted rows (a long list a part a frame). At most CAP
-- rows are shown. The game's millisecond clock limits each frame to BUDGET_MS of this work.
-- Each row has a small line of its last 7 days of prices (worked out only for the rows on screen, a few a frame, and
-- kept until new prices arrive). UI.MarketSpark(key) gives that line's numbers (the tracked list of the Items view
-- uses it too).
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
local rows            -- one row per known item, in the order of the item keys (nil until first worked out)
local counts = {}     -- numbers for the tiles, worked out with the rows
local dirty = true    -- new prices since the rows were worked out
local building = false
local progress = ""
local refilter = true -- the search or a filter changed
local shown = {}      -- the rows that pass the search and filters, sorted (the table gets the first CAP)
local unnamed = {}    -- rows whose item name had not come in yet when they were worked out
local made            -- [item ID] = true: a recipe makes it (nil until read, again after the recipes change)
local recipesSeen = 0 -- counts the recipe changes (a reading of the recipes that started before one is not kept)
local builtMin        -- the "days of history needed" setting the Rising / Falling marks of the rows were worked out with
local thePanel        -- the view, once built
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
-- draws the line of one row (a few line pieces per row, made once; rows are reused while scrolling); only a line
-- already worked out (drawSparks works out the missing ones over the next frames)
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
	local c = r and sparks[r.key]
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
X.On("XNAH_RECIPES", function()
	recipesSeen = recipesSeen + 1
	made = nil
	if filter.craft then refilter = true end
end)

-- [[ a little per frame ]] In the game (it has a millisecond clock) each frame works until BUDGET_MS went by, `piece`
-- at a time and at most `most`; without that clock (the test stand-in) `slice` a frame. work(n) does n and returns
-- true when everything is done.
local clock = debugprofilestop
local BUDGET_MS = 8
local function inFrame(work, slice, piece, most)
	if not clock then return work(slice) end
	local t0, n = clock(), 0
	repeat
		if work(piece) then return true end
		n = n + piece
	until n >= most or clock() - t0 >= BUDGET_MS
	return false
end
-- how much a frame (slice for the stand-in; piece and most in the game): rows worked out, values read for a sort
-- (the "Sells a day" column reads the sales speed of every item: slower), moves of the merge sort
local ROWS = {40, 20, 1000}
local VALUES, VALUES_SLOW = {3000, 500, 100000}, {150, 10, 5000}
local MOVES_A_FRAME = {6000, 2000, 400000}

-- [[ the merge sort ]] sorts a list of numbers (places in V) by V[place], smallest first; equal values keep the order
-- they had in the list. It can stop after any number of moves and go on in the next frame.
local function newMerge(list, V)
	return {a = list, b = {}, V = V, n = #list, w = 1, lo = 1}
end
local function mergeSteps(st, moves)
	local a, b, n, V = st.a, st.b, st.n, st.V
	local w = st.w
	while w < n do
		local lo = st.lo
		while lo <= n do
			local mid, hi = lo + w - 1, lo + 2 * w - 1
			if mid > n then mid = n end
			if hi > n then hi = n end
			local i, j, k = st.i or lo, st.j or mid + 1, st.k or lo
			while k <= hi do
				if moves <= 0 then
					st.i, st.j, st.k, st.lo, st.w = i, j, k, lo, w
					return false
				end
				moves = moves - 1
				if i <= mid and (j > hi or V[a[i]] <= V[a[j]]) then
					b[k] = a[i]
					i = i + 1
				else
					b[k] = a[j]
					j = j + 1
				end
				k = k + 1
			end
			st.i, st.j, st.k = nil, nil, nil
			lo = hi + 1
		end
		a, b = b, a
		st.a, st.b = a, b
		w = w * 2
		st.lo = 1
	end
	st.w = w
	return true
end

-- [[ the 7-day lines of the rows on screen ]] drawn at once when worked out before; the missing ones are worked out a
-- few a frame (each reads that item's history) and then drawn
local SPARK_COL = 10
local SPARK_NONE = "|cff666666  -|r"
local LINES = {8, 1, 60}
local sparkWant, sparkTbl = {}, nil -- keys whose line is wanted, the table they are in
local function drawSparks(tbl)
	local missing = false
	for i, rowFrame in ipairs(tbl.rows) do
		local r = tbl.items[i + tbl.offset]
		if r and sparks[r.key] == nil then
			missing = true
			sparkWant[#sparkWant + 1] = r.key
		end
		if r or rowFrame.spark then drawSpark(rowFrame, r, SPARK_COL) end
	end
	sparkTbl = tbl
	if not missing or X.JobRunning("market lines") then return end
	local done = 0
	local function work(count)
		local stop = math.min(#sparkWant, done + count)
		for k = done + 1, stop do sparkOf(sparkWant[k]) end
		done = stop
		return done >= #sparkWant
	end
	X.Job("market lines", function() return inFrame(work, LINES[1], LINES[2], LINES[3]) end, function()
		sparkWant = {}
		local t = sparkTbl
		if not (t and t:IsVisible()) then return end
		for k, rowFrame in ipairs(t.rows) do
			local r = t.items[k + t.offset]
			if r then
				drawSpark(rowFrame, r, SPARK_COL)
				local cell = rowFrame.cols and rowFrame.cols[SPARK_COL]
				if cell then cell:SetText(sparks[r.key] == false and SPARK_NONE or "") end
			end
		end
	end)
end

-- [[ items a recipe makes ]] (the "Can be crafted" filter) The same items as Craft.lua's list of every recipe
-- (X.RecipesFor: recipes read in the game, else the built-in list), read here a little per frame so the first use
-- of the filter does not stall the game. Kept until the recipes change.
local MADE = {800, 100, 20000}
local function startMade()
	if X.JobRunning("market recipes") then return end
	local seen = recipesSeen
	local db, list = X.db.recipes or {}, X.RECIPE_DB or {}
	local set, ids, i = {}, {}, 0
	for _, r in pairs(db) do if r.out then set[r.out] = true end end
	for rid in pairs(list) do ids[#ids + 1] = rid end
	local function work(count)
		local stop = math.min(#ids, i + count)
		for k = i + 1, stop do
			local rid = ids[k]
			if not db[rid] then
				local out = tonumber(list[rid]:match("^[^;]*;[^;]*;([^;]*);") or "")
				if out and out ~= 0 then set[out] = true end
			end
		end
		i = stop
		return i >= #ids
	end
	X.Job("market recipes", function() return inFrame(work, MADE[1], MADE[2], MADE[3]) end, function()
		if seen == recipesSeen then made = set end -- (else the recipes changed meanwhile: read again)
		if thePanel and UI.current == "market" then thePanel.tbl:Sort() end
	end)
end

-- [[ rows ]]
-- Rising / Falling / Short supply / Flooded: the same rules as X.Movers (Market.lua) - enough days of history, a fresh
-- price, and the price or the number listed going that way. r.mv = "up" / "down", r.ms = "short" / "flood".
local function markMoves(r, minS)
	r.mv, r.ms = nil, nil
	if r.stale or not r.t or r.days < minS then return end
	r.mv, r.ms = X.MoveKinds(r.trend, r.supply, r.qty7)
end

local function makeRow(key, it, minS)
	local cur = it.cur or {}
	local st = X.Stats(it) or {}
	local id = it.id or X.KeyID(key)
	local usual = st.avg30 or st.avg7 or st.avg3
	local vs
	if cur.min and usual and usual > 0 and (cur.qty or 0) > 0 then vs = (cur.min / usual - 1) * 100 end
	local r = {key = key, id = id, name = (it.n or ""):lower(), q = it.q or 1, min = cur.min, mkt = cur.mkt, usual = usual,
		vs = vs, trend = st.trend, vol = st.vol, supply = st.supply, qty7 = st.qty7, days = st.days or 0, qty = cur.qty,
		t = cur.t, stale = not X.Fresh(it)}
	markMoves(r, minS)
	return r
end

-- [[ sorting all rows ]] (the table itself would only sort the rows it shows) The order of ALL rows by a column is
-- worked out once (a little per frame on a big auction house) and kept until the rows are worked out again; a search
-- or filter then only picks the rows that pass, in that order. The order is the one of a plain sort: by the column's
-- value, equal values by item key, rows without a value last (both ways).
local orders = {}    -- [column] = {asc = rows, desc = rows}
local orderCols = {} -- the columns in orders, oldest first (at most MAX_ORDERS kept)
local MAX_ORDERS = 4
local sorting        -- the sort being worked out: {col, done, ...}
local resetOffset = true -- show the list from its top next time (a new search or filter, new rows)
local pass               -- the last pass of the search and filters through a sorted list (newPass)
local waiting = false    -- the list waits for a sort, a search / filter pass or the recipe list being worked out

local function keepOrder(ci, o)
	orders[ci] = o
	local left = {}
	for _, c in ipairs(orderCols) do if c ~= ci and orders[c] then left[#left + 1] = c end end
	left[#left + 1] = ci
	while #left > MAX_ORDERS do orders[table.remove(left, 1)] = nil end
	orderCols = left
end

-- the sort of column ci of the table's columns: values (sliced), merge sort (sliced), then both directions
local function sorter(ci, col)
	local list, f = rows, col.sort
	local n = #list
	local V, a, na, nils, nn, gi = {}, {}, 0, {}, 0, 0
	local st = {col = ci, rows = list, done = false}
	local merge
	local function gather(count)
		local stop = math.min(n, gi + count)
		for i = gi + 1, stop do
			local v = f(list[i])
			if v ~= nil and v == v then -- (no value, or not a number: last)
				na = na + 1
				a[na] = i
				V[i] = v
			else
				nn = nn + 1
				nils[nn] = i
			end
		end
		gi = stop
		return gi >= n
	end
	local function moves(count) return mergeSteps(merge, count) end
	local phase = 1
	local how = col.slow and VALUES_SLOW or VALUES
	function st.step()
		if phase == 1 then
			if inFrame(gather, how[1], how[2], how[3]) then
				merge = newMerge(a, V)
				phase = 2
			end
			return false
		elseif phase == 2 then
			if inFrame(moves, MOVES_A_FRAME[1], MOVES_A_FRAME[2], MOVES_A_FRAME[3]) then phase = 3 end
			return false
		elseif phase == 4 then
			return true
		end
		-- both directions; going down, equal values stay in item key order
		local s = merge.a
		local asc, desc, d = {}, {}, 0
		for k = 1, na do asc[k] = list[s[k]] end
		local k = na
		while k >= 1 do
			local v = V[s[k]]
			local g = k
			while g > 1 and V[s[g - 1]] == v do g = g - 1 end
			for m = g, k do
				d = d + 1
				desc[d] = list[s[m]]
			end
			k = g - 1
		end
		for m = 1, nn do
			local r = list[nils[m]]
			asc[na + m], desc[na + m] = r, r
		end
		st.order = {asc = asc, desc = desc}
		st.done = true
		phase = 4
		return false -- (the list is shown in the next frame)
	end
	-- a small list is done at once
	if n <= 400 then
		while not st.step() do end
	end
	return st
end

-- starts the sort of column ci (unless it runs already); true when its order is there right away
local function startSort(ci, col)
	if sorting and sorting.col == ci and sorting.rows == rows then return false end
	local st = sorter(ci, col)
	if st.done then
		keepOrder(ci, st.order)
		return true
	end
	sorting = st
	-- worked out over the next frames
	X.Job("market sort", function()
		if sorting ~= st or st.rows ~= rows then return true end -- (another column picked, or new rows)
		return st.step()
	end, function()
		if sorting == st then sorting = nil end
		if st.done and st.rows == rows then
			keepOrder(ci, st.order)
			if thePanel and UI.current == "market" then thePanel.tbl:Sort() end
		end
	end)
	return false
end

-- names that came in since the rows were worked out
local function fixNames()
	if #unnamed == 0 then return end
	local items, left, changed = X.Items(), {}, false
	for _, r in ipairs(unnamed) do
		local it = items[r.key]
		if it and it.n and it.n ~= "" then
			r.name, r.q = it.n:lower(), it.q or r.q
			changed = true
		else
			left[#left + 1] = r
		end
	end
	unnamed = left
	if changed then
		orders[1] = nil -- (the Item column sorts by name)
		pass = nil
	end
end

-- [[ the search and filters ]] one pass through a sorted list: the rows that pass, in that order (a long list a part a
-- frame: a search reads every name)
local FILTER = {2500, 500, 100000}
local function newPass(list, sig, text)
	local p = {list = list, sig = sig, out = {}, done = false}
	local num = tonumber(text)
	local hasText = text ~= ""
	local q, watch, listed, craft, move = filter.q, filter.watch, filter.listed, filter.craft, filter.move
	local out, n, i = p.out, 0, 0
	local function work(count)
		local stop = math.min(#list, i + count)
		for k = i + 1, stop do
			local r = list[k]
			if (not hasText or r.name:find(text, 1, true) or (num and r.id == num) or r.key == text)
				and (not q or (r.q or 1) >= q)
				and (not listed or (r.qty or 0) > 0)
				and (not move or r.mv == move or r.ms == move)
				and (not watch or X.Watched(r.key))
				and (not craft or (r.id ~= nil and made and made[r.id])) then
				n = n + 1
				out[n] = r
			end
		end
		i = stop
		p.done = i >= #list
		return p.done
	end
	function p.step() return inFrame(work, FILTER[1], FILTER[2], FILTER[3]) end
	return p
end
-- the first part at once, the rest over the next frames; then the list is shown
local function startPass(p)
	if p.done or p.step() then return end
	if X.JobRunning("market filter") then return end -- (it goes on with the newest pass)
	X.Job("market filter", function()
		if not pass or pass.done then return true end
		return pass.step()
	end, function()
		if thePanel and UI.current == "market" and waiting then thePanel.tbl:Sort() end
	end)
end

-- the rows that pass the search and filters, in the order of the table's sort column, into the table (its first CAP);
-- false while that order is still being worked out (the table keeps what it shows until then)
local function showRows(tbl)
	fixNames()
	local minS = X.S().minSamples
	if builtMin ~= minS then
		for _, r in ipairs(rows) do markMoves(r, minS) end
		builtMin = minS
		pass = nil
	end
	local ci = tbl.sortCol
	local col = ci and tbl.columns[ci]
	local list = rows
	if col and col.sort then
		if not orders[ci] and not startSort(ci, col) then
			waiting = true
			return false
		end
		list = tbl.sortDesc and orders[ci].desc or orders[ci].asc
	end
	local q, watch, listed, craft, move = filter.q, filter.watch, filter.listed, filter.craft, filter.move
	if craft and not made then
		startMade()
		waiting = true
		return false
	end
	local text = X.Trim(filter.text):lower()
	if text == "" and not q and not watch and not listed and not craft and not move then
		shown = list
	else
		local sig = table.concat({text, tostring(q), tostring(watch), tostring(listed), tostring(craft), tostring(move)}, "|")
		if not (pass and pass.list == list and pass.sig == sig) then pass = newPass(list, sig, text) end
		if not pass.done then
			startPass(pass)
			if not pass.done then
				waiting = true
				return false
			end
		end
		shown = pass.out
	end
	waiting = false
	if resetOffset then
		tbl.offset = 0
		resetOffset = false
	end
	local items = {}
	for i = 1, math.min(CAP, #shown) do items[i] = shown[i] end
	tbl.items = items
	tbl:Refresh()
	return true
end

local function applyFilter(tbl)
	refilter = false
	resetOffset = true
	pass = nil -- (what passes may have changed: tracked items, names, recipes)
	tbl:Sort()
end

local function startRows()
	if building then return end
	building, dirty = true, false
	local items = X.Items()
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local nk = #keys
	-- the item keys in order first (equal values in a sorted column are listed by item key)
	local places = {}
	for i = 1, nk do places[i] = i end
	local keySort = newMerge(places, keys)
	local function keyMoves(count) return mergeSteps(keySort, count) end
	local sorted
	local out, miss, i = {}, {}, 0
	local minS = X.S().minSamples
	local c = {known = 0, listed = 0, up = 0, down = 0, short = 0, flood = 0}
	local function work(count)
		local stop = math.min(nk, i + count)
		while i < stop do
			i = i + 1
			local key = keys[sorted[i]]
			local it = items[key]
			if it then
				local r = makeRow(key, it, minS)
				out[#out + 1] = r
				if r.name == "" then miss[#miss + 1] = r end
				c.known = c.known + 1
				if (r.qty or 0) > 0 then c.listed = c.listed + 1 end
				if r.mv then c[r.mv] = c[r.mv] + 1 end
				if r.ms then c[r.ms] = c[r.ms] + 1 end
			end
		end
		return i >= nk
	end
	progress = "Reading prices: 0 / " .. X.Num(nk)
	X.Job("market rows", function()
		if not sorted then
			if inFrame(keyMoves, MOVES_A_FRAME[1], MOVES_A_FRAME[2], MOVES_A_FRAME[3]) then sorted = keySort.a end
			return false
		end
		local done = inFrame(work, ROWS[1], ROWS[2], ROWS[3])
		progress = "Reading prices: " .. X.Num(i) .. " / " .. X.Num(nk)
		return done
	end, function()
		building = false
		rows, counts, unnamed, builtMin = out, c, miss, minS
		orders, orderCols = {}, {}
		refilter = true
		if UI.current == "market" then UI.Refresh(true) end
	end)
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
local TREND_COL, SUPPLY_COL = 5, 9
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
	{"7 days", 64, "LEFT", text = function(r) return sparks[r.key] == false and SPARK_NONE or "" end},
	{"Seen", 58, "RIGHT", text = function(r)
		if not r.t then return GREY .. "never|r" end
		return (r.stale and "|cff777777" or "") .. X.Ago(r.t) .. (r.stale and "|r" or "")
	end, sort = function(r) return r.t end},
}
COLUMNS[7].slow = true -- (sorting by it reads the sales speed of every item: worked out over a few more frames)
-- the hover line of each column title
local COLUMN_TIPS = {
	"The item. Click a row to see it in the Items view, right-click for its menu (track it and more). Sorts A to Z.",
	"The lowest price of one at the last scan. \"none\" = none listed then. Dimmed = an old price (see Settings: " ..
		"prices count as old after).",
	"What one sells for right now: the average of the cheapest listings, with prices far off the rest left out.",
	"The cheapest price now against the usual price (the average of the last 30 days, else 7 or 3 days). Under 0% = " ..
		"cheaper than usual right now, over 0% = dearer.",
	"How much the price goes up or down in a week, from the last days of scans. Arrow up = rising, down = falling.",
	"How much the price jumps from day to day. Green = steady (under 10%), yellow = some ups and downs, red = wild " ..
		"(over 25%).",
	"About how many sell in a day: worked out from full scans close together (a cancelled auction looks like a sale, " ..
		"so it can come out a bit high), or what you sold yourself if that is more.",
	"How many were listed at the last scan, all auctions together. Grey 0 = none listed.",
	"How many are listed now against the usual number listed over the last 7 days. Far under = short supply (a " ..
		"chance to sell), far over = flooded (better wait).",
	"The price over the last 7 days, one point a day: green = going up, red = going down, grey = about flat. Cannot " ..
		"be sorted.",
	"When the price was last seen at a scan or search. Dimmed = an old price (see Settings: prices count as old " ..
		"after).",
}
for i, c in ipairs(COLUMNS) do c.tip = COLUMN_TIPS[i] end
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
	cols[1] = {COLUMNS[1][1], math.max(160, W - 20 - fixed), "LEFT", text = COLUMNS[1].text, sort = COLUMNS[1].sort, desc = false,
		tip = COLUMNS[1].tip}

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
	end, "All", "Show every item again: clears the search and turns off all the filters.")
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
	end, "Quality", "Only items of this quality or better (click to pick: Poor, Common, Uncommon, Rare, Epic, " ..
		"Legendary).")
	-- search box (the rest of the line)
	local label = K.Label(panel, "Search", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", x + 6, FY - 5)
	search = K.Edit(panel, math.max(100, W - x - 58))
	search:SetPoint("TOPLEFT", x + 52, FY - 1)
	K.Tooltip(search, "Search", "Type part of an item's name, or its item number: only the items that match are listed.")
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
	-- sorting goes through every row that passes the filters, then the first CAP are shown (showRows)
	function tbl:Sort()
		for i, hdr in ipairs(self.headers or {}) do
			local m = (i == self.sortCol) and (self.sortDesc and " v" or " ^") or ""
			hdr:SetText(GREY .. self.columns[i][1] .. m .. "|r")
		end
		if rows then
			showRows(self)
		else
			self:Refresh()
		end
		if panel.footerUpdate then panel.footerUpdate() end
	end
	-- after the rows are filled: the 7-day lines of the rows on screen
	local baseRefresh = tbl.Refresh
	function tbl:Refresh()
		baseRefresh(self)
		drawSparks(self)
	end
	if filter.move then tbl.sortCol, tbl.sortDesc = MOVE_SORT[filter.move][1], MOVE_SORT[filter.move][2] end
	panel.tbl = tbl
	thePanel = panel

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
		if waiting then text = text .. "   Sorting..." end
		if rows and #shown ~= total then text = text .. "   -   " .. X.Num(#shown) .. " match" end
		if #shown > CAP then text = text .. "   |cffffd100showing the first " .. X.Num(CAP) .. " - search to narrow|r" end
		footer:SetText(text)
		if not rows then
			tbl.empty:SetText("Reading prices...")
		elseif total == 0 then
			tbl.empty:SetText("No prices yet. Open the auction house and do a full scan (the Full scan button at the top " ..
				"of this window, or Settings).")
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
	elseif waiting and rows then
		panel.tbl:Sort() -- the order it waited for is there now
	else
		panel.tbl:Refresh() -- stars, "seen" times
	end
	panel.footerUpdate()
end

UI.AddTab("market", "Market", build, refresh, 2)
