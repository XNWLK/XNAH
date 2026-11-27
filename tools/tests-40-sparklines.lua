-- XNAH test scenes, part 40: the small 7-day price lines of the tracked list (Sparkline.lua, UIItem.lua) - the numbers
-- of a line, its colour by direction, the cache (worked out again only when the item gets new prices or the hour
-- changes), only the rows on screen drawn, the setting that hides them; and the hover lines on the column titles of
-- the older tables (tracked list, Your gold Overview / Best sellers / Recent / Characters, the scans in Settings).
-- Every scene title starts with "40" (node tools/test.js 40).

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function items(X) return X.UI.tabs.items.panel end
-- one price a day for `days` days up to now (today included), oldest first: priceOf(daysAgo)
local function daily(X, key, days, priceOf, name)
	local now = X.Now()
	for d = days - 1, 0, -1 do
		local v = priceOf(d)
		X.Record(key, now - d * DAY - 60, v, v, 20, 4, name, 1)
	end
end
-- how many 7-day lines were worked out (each reads one item's price history) while fn runs
local function historyReads(X, fn)
	local before = X.sparkWorked
	fn()
	return W.X.sparkWorked - before -- (W.X: a reload in fn makes a new addon table)
end
local function openItems(X)
	if not X.UI.Frame() or not X.UI.Frame():IsShown() then X.UI.Toggle() end
	X.UI.Open("items")
	W.advance(0.5)
	return items(X)
end
local function sameColor(a, b)
	return a and b and math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01
end

T.scene("40 sparklines: the numbers and the colour of a line", function()
	local X = W.start()
	daily(X, "2589", 7, function(d) return 100 + (6 - d) * 10 end, "Linen Cloth")   -- 100 .. 160: rising
	daily(X, "2592", 7, function(d) return 300 - (6 - d) * 20 end, "Wool Cloth")    -- 300 .. 180: falling
	daily(X, "2770", 7, function(d) return 500 + (d % 2) end, "Copper Ore")         -- about flat
	X.Record("3576", X.Now() - 60, 80, 80, 5, 1, "Tin Bar", 1)                         -- one day only
	local up, down, flat = X.Spark("2589"), X.Spark("2592"), X.Spark("2770")
	T.ok("rising: a line", up ~= false)
	T.check("rising: one point a day", up and #up.pts, 7)
	T.ok("rising: green", up and up.color == X.SPARK_UP)
	T.near("rising: +60%", up and up.change, 60, 0.5)
	T.ok("rising: the first point at the bottom left", up and up.pts[1][1] == 0 and up.pts[1][2] == 0, up and T.show(up.pts[1]))
	T.ok("rising: the last point at the top right", up and math.abs(up.pts[7][1] - 1) < 1e-9 and math.abs(up.pts[7][2] - 1) < 1e-9,
		up and T.show(up.pts[7]))
	T.ok("falling: red", down and down.color == X.SPARK_DOWN)
	T.near("falling: -40%", down and down.change, -40, 0.5)
	T.ok("about flat: grey", flat and flat.color == X.SPARK_FLAT)
	T.check("about flat: drawn in the middle", flat and flat.pts[3][2], 0.5)
	T.check("one day of prices: no line", X.Spark("3576"), false)
	T.check("an item never seen: no line", X.Spark("99999"), false)
	T.check("no key: no line", X.Spark(nil), false)
	-- the same colours as the arrows elsewhere in XNAH (green up, red down)
	T.ok("green like a rising arrow", has(X.Arrow(20), "4ade80") and X.SparkText(up):find("4ade80", 1, true) ~= nil)
	T.check("the change as text", W.plain(X.SparkText(down)), "-40%")
	-- prices older than 7 days do not count
	daily(X, "2840", 12, function(d) return d >= 7 and 300 or 200 end, "Copper Bar")
	local old = X.Spark("2840")
	T.ok("older prices left out", old and old.hi == 200 and old.days == 7, old and T.show({old.lo, old.hi, old.days}))
	T.check("nothing saved", X.Items()["2589"].spark, nil)
end)

T.scene("40 sparklines: kept until new prices or the next hour", function()
	local X = W.start()
	daily(X, "2589", 7, function(d) return 100 + (6 - d) * 10 end, "Linen Cloth")
	daily(X, "2592", 7, function(d) return 300 end, "Wool Cloth")
	local a = X.Spark("2589")
	local reads = historyReads(X, function()
		for _ = 1, 20 do X.Spark("2589") end
	end)
	T.check("asked again: no new history read", reads, 0)
	T.ok("asked again: the same line", X.Spark("2589") == a)
	-- new prices for one item: only that one is worked out again
	local wool = X.Spark("2592")
	X.Record("2589", X.Now(), 90, 90, 20, 4, "Linen Cloth", 1)
	reads = historyReads(X, function()
		X.Spark("2589")
		X.Spark("2592")
	end)
	T.check("new prices: only that item read again", reads, 1)
	T.ok("the other item keeps its line", X.Spark("2592") == wool)
	T.ok("new prices: a new line", X.Spark("2589") ~= a)
	-- the next hour: worked out again (the days move on)
	W.advance(3600)
	reads = historyReads(X, function() X.Spark("2592") end)
	T.check("the next hour: read again", reads, 1)
end)

T.scene("40 sparklines: the tracked list draws the rows on screen only", function()
	local X = W.start()
	local keys = {}
	for i = 1, 60 do
		local key = tostring(70000 + i)
		keys[#keys + 1] = key
		local rising = i % 2 == 0
		daily(X, key, 7, function(d) return rising and (100 + (6 - d) * 10) or (300 - (6 - d) * 20) end, "Thing " .. string.format("%02d", i))
		X.SetWatched(key, true)
	end
	local reads
	local panel
	reads = historyReads(X, function() panel = openItems(X) end)
	local tbl = panel.tbl
	T.check("60 rows in the list", #tbl.items, 60)
	local onScreen = 0
	for _, row in ipairs(tbl.rows) do if row:IsShown() then onScreen = onScreen + 1 end end
	T.ok("fewer rows on screen than tracked", onScreen > 0 and onScreen < 60, onScreen)
	T.ok("history read only for the rows on screen", reads > 0 and reads <= onScreen, reads .. " reads, " .. onScreen .. " rows")
	-- each row on screen: its line, in the colour of its direction
	local right, drawn = 0, 0
	for i, row in ipairs(tbl.rows) do
		local r = tbl.items[i + tbl.offset]
		local s = row.xnahSpark
		if r and row:IsShown() and s and s:IsShown() then
			drawn = drawn + 1
			local want = (tonumber(r.key) % 2 == 0) and X.SPARK_UP or X.SPARK_DOWN
			if s.drawn == 6 and sameColor(s.lines[1].color, want) and s.dot:IsShown() then right = right + 1 end
		end
	end
	T.check("every row on screen has its line", drawn, onScreen)
	T.check("6 pieces and the right colour in each", right, onScreen)
	-- redrawn (new scan progress, the view refreshed): nothing read again
	reads = historyReads(X, function()
		X.UI.Refresh(true)
		W.advance(0.5)
	end)
	T.check("refreshed: no history read again", reads, 0)
	-- scrolled down: only the rows that came on screen
	reads = historyReads(X, function()
		W.step(tbl.scripts.OnMouseWheel, tbl, -3)
	end)
	T.ok("scrolled: only the new rows read", reads > 0 and reads <= 9, reads)
	T.ok("scrolled: the rows show other items", tbl.offset > 0)
	-- hover: the title of the 7-day column explains the colours
	W.hover(tbl.headerButtons[5])
	T.ok("hover the title: what the line means", has(W.tipText(), "last 7 days") and has(W.tipText(), "Green"), W.tipText())
	W.unhover(tbl.headerButtons[5])
	-- sorting by it: the biggest rise first
	W.step(tbl.headerButtons[5].scripts.OnClick, tbl.headerButtons[5], "LeftButton")
	T.ok("sorted by the 7-day change: a rising item first", tonumber(tbl.items[1].key) % 2 == 0, tbl.items[1].key)
	T.ok("and a falling one last", tonumber(tbl.items[60].key) % 2 == 1, tbl.items[60].key)
end)

T.scene("40 sparklines: a few milliseconds of lines a frame, the rest the next frames", function()
	local X = W.start()
	for i = 1, 40 do
		local key = tostring(71000 + i)
		daily(X, key, 7, function(d) return 100 + (6 - d) * 10 end, "Thing " .. string.format("%02d", i))
		X.SetWatched(key, true)
	end
	-- a clock that says each line takes 1 ms (the stand-in has none)
	local ms = 0
	W.env.debugprofilestop = function() ms = ms + 1 return ms end
	X.SparkReset()
	local before = X.sparkWorked
	X.UI.Toggle()
	X.UI.Open("items")
	local first = X.sparkWorked - before
	T.ok("the first frame: only some lines", first > 0 and first <= 8, first)
	local tbl = items(X).tbl
	local function drawnRows()
		local n, shown = 0, 0
		for _, row in ipairs(tbl.rows) do
			if row:IsShown() then
				shown = shown + 1
				if row.xnahSpark and row.xnahSpark:IsShown() then n = n + 1 end
			end
		end
		return n, shown
	end
	W.advance(1)
	local n, shown = drawnRows()
	T.check("a moment later: every row on screen has its line", n, shown)
	T.ok("still only the rows on screen worked out", X.sparkWorked - before <= shown, X.sparkWorked - before)
	-- sorted by the 7-day change while lines wait: sorted again when they are there
	X.Record("71001", X.Now(), 400, 400, 20, 4, "Thing 01", 1) -- now far up
	W.step(tbl.headerButtons[5].scripts.OnClick, tbl.headerButtons[5], "LeftButton")
	W.advance(1)
	T.check("sorted again once every line is there: the biggest rise first", tbl.items[1].key, "71001")
	W.env.debugprofilestop = nil
end)

T.scene("40 sparklines: the setting hides them", function()
	local X = W.start()
	daily(X, "2589", 7, function(d) return 100 + (6 - d) * 10 end, "Linen Cloth")
	X.SetWatched("2589", true)
	X.Record("3576", X.Now() - 60, 80, 80, 5, 1, "Tin Bar", 1)
	X.SetWatched("3576", true)
	T.ok("on by default", X.S().listSpark == true)
	local panel = openItems(X)
	local tbl = panel.tbl
	local function rowOf(key)
		for i, row in ipairs(tbl.rows) do
			local r = tbl.items[i + tbl.offset]
			if r and r.key == key then return row end
		end
	end
	T.ok("a line", rowOf("2589").xnahSpark:IsShown())
	T.check("no line: a dash", X.Trim(W.plain(rowOf("3576").cols[5].text or "")), "-")
	T.check("the title", W.plain(tbl.headers[5].text or ""), "7 days")
	-- Settings: the tick box
	X.UI.Open("scan")
	W.advance(0.3)
	local box = W.findButton("7-day price lines in the tracked list", X.UI.tabs.scan.panel)
	T.ok("a tick box in Settings", box ~= nil)
	if box then box:Click() end
	W.advance(0.3)
	T.check("off", X.S().listSpark, false)
	local reads = historyReads(X, function() openItems(X) end)
	T.ok("hidden: no line", not rowOf("2589").xnahSpark:IsShown())
	T.check("hidden: no dash", W.plain(rowOf("3576").cols[5].text or ""), "")
	T.check("hidden: no title", W.plain(tbl.headers[5].text or ""), "")
	T.check("hidden: no history read for lines", reads, 0)
	W.hover(tbl.headerButtons[5])
	T.ok("hidden: the title's hover says where to turn them on", has(W.tipText(), "Settings"), W.tipText())
	W.unhover(tbl.headerButtons[5])
	-- kept after a reload
	X = W.reload()
	T.check("still off after a reload", X.S().listSpark, false)
	X.S().listSpark = true
	panel = openItems(X)
	tbl = panel.tbl
	T.ok("on again: the line is back", rowOf("2589") and rowOf("2589").xnahSpark and rowOf("2589").xnahSpark:IsShown())
end)

-- [[ column hovers ]] every column title of every table has a hover line (the Market view has its own scene)
local function columnTips(root, label, out)
	W.walk(root, function(f)
		if f.headers and f.columns and f.headerButtons then
			for i = 1, #f.headers do
				local b = f.headerButtons[i]
				local text = ""
				if b and b.scripts.OnEnter then
					W.hover(b)
					text = W.tipText()
					W.unhover(b)
				end
				-- the title line and at least a short explanation
				if #text < #(f.columns[i][1] or "") + 12 then out[#out + 1] = label .. ": " .. tostring(f.columns[i][1]) end
			end
			out.tables = (out.tables or 0) + 1
		end
	end)
end

T.scene("40 column hovers: the tracked list, Your gold and Settings explain every column", function()
	local X = W.start()
	X.SetWatched("2589", true)
	local missing = {}
	columnTips(openItems(X).tbl, "tracked list", missing)
	X.UI.Open("gold")
	W.advance(0.3)
	local g = X.UI.tabs.gold.panel
	for _, pg in ipairs(X.UI.GOLD_PAGES) do
		W.click(pg.title, g)
		W.advance(0.3)
		columnTips(g.bar.frames[pg.key], "gold " .. pg.title, missing)
	end
	X.UI.Open("scan")
	W.advance(0.3)
	columnTips(X.UI.tabs.scan.panel, "settings", missing)
	T.ok("tables found (list, flips, best sellers, recent, characters, bags, scans and the newer ones)", (missing.tables or 0) >= 7,
		missing.tables)
	T.check("columns without a hover line", table.concat(missing, "; "), "")
	-- a few of the lines say what they should
	local tbl = items(X).tbl
	W.hover(tbl.headerButtons[3])
	T.ok("% usual: green = cheaper", has(W.tipText(), "cheaper than usual"), W.tipText())
	W.unhover(tbl.headerButtons[3])
	X.UI.Open("gold")
	W.advance(0.3)
	W.click("Best sellers", g)
	W.advance(0.3)
	local best = g.bar.frames.items.tbl
	W.hover(best.headerButtons[10])
	T.ok("sell-through: how it is worked out", has(W.tipText(), "sold / (sold + expired + cancelled)"), W.tipText())
	T.ok("and that it sorts", has(W.tipText(), "Click to sort"), W.tipText())
	W.unhover(best.headerButtons[10])
end)
