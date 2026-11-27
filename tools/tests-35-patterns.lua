-- XNAH test scenes, part 35: Patterns - the weekday x time-of-day grid kept per item (its maths, fading, filling it from
-- the scan points, browse results left out, forgetting it), how jumpy the price is (the words, the 30-day low / high,
-- where today sits), the market size (drops in the number listed, Speed.lua's numbers), the Patterns page and the
-- Overview's small grid, with an item that has nothing and one that has a lot.
-- Every scene title starts with "35" (node tools/test.js 35).

local DAY, HOUR = 86400, 3600
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function blank()
	local agg = {parts = {}}
	for i = 1, 42 do agg.parts[i] = "" end
	return agg
end
-- a server time `daysBack` days ago at `hour` on the realm's clock
local function at(X, daysBack, hour)
	local shift = X.ServerShift()
	local today = math.floor((X.Now() + shift) / DAY)
	return (today - daysBack) * DAY - shift + hour * HOUR
end
-- 4 weeks of scans every 4 hours (1 hour into each block): price 100, Tuesday 8-12 at 80, Saturday 20-24 at 120;
-- 50 listed, 10 on Sundays
local function patterned(X, key, name)
	X.SetWatched(key, true)
	for back = 28, 1, -1 do
		for b = 0, 5 do
			local t = at(X, back, b * 4 + 1)
			local wd = X.ServerWeekday(t)
			local v = 100
			if wd == 2 and b == 2 then v = 80 elseif wd == 6 and b == 5 then v = 120 end
			X.Record(key, t, v - 5, v, wd == 0 and 10 or 50, 5, name, 1)
		end
	end
end

T.scene("35 patterns: the grid's maths, fading and its saved text", function()
	local X = W.start()
	-- the cell of a time: weekday and block of 4 hours on the realm's clock (an hour ahead of UTC here)
	local t = 999 * DAY + 9 * HOUR -- day 999 = a Tuesday (UTC); 10:00 on the realm's clock
	local wd, b = X.PatternCell(t)
	T.check("cell of a time: Tuesday 8-12", wd .. "/" .. b, "2/2")
	T.check("time text", X.PatternTime(2, 2), "Tuesday 08:00 - 12:00")
	T.check("time text, short", X.PatternTime(6, 5, true), "Sat 20-24")
	T.check("time text: the last block ends at 24:00", X.PatternTime(0, 5), "Sunday 20:00 - 24:00")
	-- one observation at the very start of a day: weight 1 (saved x100), price as usual (1000), 12 listed (x10)
	local t0 = 999 * DAY -- Tuesday 01:00 on the realm's clock: block 0-4
	local agg = blank()
	T.ok("counted", X.PatternAdd(agg, t0, 500, 12))
	T.check("weights start from that day", agg.e, 999)
	T.check("first cell text", agg.parts[2 * 6 + 0 + 1], X.b36(100) .. "," .. X.b36(1000) .. "," .. X.b36(120))
	T.check("the running usual price starts at the price", agg.b, 500)
	-- again 10 minutes later: left out (closer than 20 minutes)
	T.ok("10 minutes later: not counted", not X.PatternAdd(agg, t0 + 600, 400, 12))
	T.ok("older: not counted", not X.PatternAdd(agg, t0 - 3600, 400, 12))
	-- 6 hours later at 400 (the next cell, 4-8): 20% under the running usual price
	T.ok("6 hours later: counted", X.PatternAdd(agg, t0 + 6 * HOUR, 400, 30))
	local c2 = agg.parts[2 * 6 + 1 + 1]
	T.check("second cell: 20% cheaper (ratio 0.8)", X.n36(c2:match("^[^,]*,([^,]*)")), 800)
	T.ok("the running usual price moved toward 400 a little", agg.b < 500 and agg.b > 440, agg.b)
	-- sold out a week later in the first cell (no price): the weight grows, the price weight not (4th field)
	T.ok("sold out: counted", X.PatternAdd(agg, t0 + 7 * DAY, nil, 0))
	local c3 = agg.parts[2 * 6 + 0 + 1]
	local w3, r3, q3, p3 = c3:match("^([^,]*),([^,]*),([^,]*),?([^,]*)$")
	-- a week later an observation weighs 2^(7/21)
	T.near("week later: weight 1 + 2^(1/3)", X.n36(w3) / 100, 1 + 2 ^ (1 / 3), 0.011)
	T.check("price weight stays 1 (the sold-out moment has no price)", X.n36(p3), 100)
	T.check("ratio unchanged", X.n36(r3), 1000)
	T.near("listed: weighted average", X.n36(q3) / 10, 12 / (1 + 2 ^ (1 / 3)), 0.06)
	-- 14 weeks later (the same weekday and time): the weights are made small again (old cells nearly gone)
	T.ok("14 weeks later: counted", X.PatternAdd(agg, t0 + 98 * DAY, 500, 5))
	T.check("weights start from a new day", agg.e, 1097)
	local w1 = X.n36(agg.parts[2 * 6 + 1 + 1]:match("^([^,]*)"))
	T.check("an old cell: its weight x 2^(-98/21), saved x100", w1, X.Round(X.Round(100 * 2 ^ (0.25 / 21)) * 2 ^ (-98 / 21)))
	local w4 = X.n36(agg.parts[2 * 6 + 0 + 1]:match("^([^,]*)"))
	T.check("the cell seen again: old weight shrunk + 1", w4, X.Round(X.n36(w3) * 2 ^ (-98 / 21)) + 100)

	-- the item flow: a watched item, the same time 3 weeks apart = 1 + 1/2 observations now
	X.SetWatched("2592", true)
	local t2 = at(X, 0, 0) + 30
	if t2 > X.Now() then t2 = t2 - DAY end
	X.Record("2592", t2 - 21 * DAY, 300, 300, 20, 2, "Wool Cloth", 1)
	T.ok("watched: a grid at the first observation", type(X.Items()["2592"].pw) == "string")
	X.Record("2592", t2, 300, 300, 20, 2, "Wool Cloth", 1)
	local grid = X.PatternGrid("2592")
	T.check("one cell", grid.filled, 1)
	local cwd, cb = X.PatternCell(t2)
	local cell = grid.cells[cwd][cb]
	T.near("3 weeks old counts half: 1.5 observations", cell and cell.n, 1.5 * 2 ^ (-(X.Now() - t2) / (21 * DAY)), 0.01)
	T.ok("not enough to go by", not grid.enough)

	-- saved: survives a reload unchanged
	local before = X.Items()["2592"].pw
	X = W.reload()
	T.check("after a reload: the same text", X.Items()["2592"].pw, before)
end)

T.scene("35 patterns: a known pattern, filling from the scan points, browse left out, forgetting", function()
	local X = W.start()
	patterned(X, "2589", "Linen Cloth")
	local grid = X.PatternGrid("2589")
	T.check("every cell seen", grid.filled, 42)
	T.ok("enough to go by", grid.enough)
	T.check("cheapest: Tuesday 8-12", grid.cheap and (grid.cheap.wd .. "/" .. grid.cheap.b), "2/2")
	T.check("dearest: Saturday 20-24", grid.dear and (grid.dear.wd .. "/" .. grid.dear.b), "6/5")
	T.ok("Tuesday 8-12: about 20% cheaper", grid.cheap.cell.pct < -14 and grid.cheap.cell.pct > -24, grid.cheap.cell.pct)
	T.ok("Saturday 20-24: about 20% dearer", grid.dear.cell.pct > 14 and grid.dear.cell.pct < 24, grid.dear.cell.pct)
	T.check("scarcest: a Sunday", grid.scarce and grid.scarce.wd, 0)
	T.ok("Sunday: far fewer listed", grid.scarce.cell.qpct < -60, grid.scarce.cell.qpct)
	local plain = grid.cells[3][1]
	T.ok("a plain time: about usual", plain and math.abs(plain.pct) < 4, plain and plain.pct)
	T.near("its price: about the usual price", plain and plain.price, X.Usual("2589"), X.Usual("2589") * 0.05)
	T.ok("4 weeks, 4 of them in a cell (older count less)", plain.n > 2 and plain.n < 4, plain.n)
	T.note("patterns: grid of an item after 4 weeks, 6 scans a day: " .. #X.Items()["2589"].pw .. " bytes")

	-- browse results (only a lowest price) are not counted; a search is
	local pw = X.Items()["2589"].pw
	X.Observe("2589", X.Now() - 60, 90, 40, "Linen Cloth", 1)
	T.check("browse result: the grid unchanged", X.Items()["2589"].pw, pw)
	X.Record("2589", X.Now(), 95, 100, 40, 5)
	T.ok("a search: counted", X.Items()["2589"].pw ~= pw)

	-- an item not tracked: no grid while recording, filled from its scan points the first time it is looked at
	for i = 6 * 7, 1, -1 do X.Record("4306", X.Now() - i * 4 * HOUR, 480, 500, 30, 3, "Silk Cloth", 1) end
	T.check("not tracked: no grid", X.Items()["4306"].pw, nil)
	local g2 = X.PatternGrid("4306")
	T.ok("looked at: filled from the scan points kept (7 days)", g2.filled >= 30 and type(X.Items()["4306"].pw) == "string", g2.filled)
	local n0 = g2.n
	X.Record("4306", X.Now() + 3600, 480, 500, 30, 3)
	W.advance(3601)
	T.ok("looked at: kept up from then on", X.PatternGrid("4306").n > n0)
	-- an item with no prices: no grid
	local g3 = X.PatternGrid("99999")
	T.check("unknown item: nothing", g3.filled .. "/" .. tostring(X.Items()["99999"]), "0/nil")
	-- not tracked and not looked at for 60 days: forgotten at its next observation
	local it = X.Items()["4306"]
	it.pw = it.pw:gsub("^([^,]*,[^,]*,[^,]*,)[^;]*", "%1" .. X.b36(X.Day() - 61))
	X.Record("4306", X.Now() + 3600, 480, 500, 30, 3)
	T.check("not looked at for 61 days: gone", it.pw, nil)
	-- tracked items keep it
	local lin = X.Items()["2589"]
	lin.pw = lin.pw:gsub("^([^,]*,[^,]*,[^,]*,)[^;]*", "%1" .. X.b36(X.Day() - 61))
	X.Record("2589", X.Now() + 3600, 95, 100, 40, 5)
	T.ok("tracked: kept", type(lin.pw) == "string")

	-- size: a tracked item after a year of 4 scans a day at changing times
	X.SetWatched("2996", true)
	for back = 365, 1, -1 do
		for k = 0, 3 do
			local t = at(X, back, (k * 6 + back % 6) % 24)
			X.Record("2996", t, 1900 + (back % 7) * 10, 2000 + (back % 7) * 10, 100 + (k * 13 + back) % 40, 8, "Bolt of Linen Cloth", 1)
		end
	end
	local size = #X.Items()["2996"].pw
	T.ok("a year: small", size < 520, size)
	T.note("patterns: grid of an item after a year of 4 scans a day: " .. size .. " bytes (" .. X.PatternGrid("2996").filled .. " of 42 cells)")
end)

T.scene("35 patterns: how jumpy, the 30-day low and high, where today sits", function()
	local X = W.start()
	T.check("word: steady", X.JumpyWord(2), "Steady")
	T.check("word: moves a bit", X.JumpyWord(5), "Moves a bit")
	T.check("word: jumpy", X.JumpyWord(12), "Jumpy")
	T.check("word: wild", X.JumpyWord(30), "Wild")
	T.check("word: unknown", X.JumpyWord(nil), nil)
	T.check("place: cheapest", X.PlaceText(8, 100, 90, 200), "cheapest 10% of the month")
	T.check("place: normal", X.PlaceText(50, 100, 90, 200), "a normal price for the month")
	T.check("place: dearest", X.PlaceText(95, 190, 90, 200), "dearest 10% of the month")
	T.check("place: under the low", X.PlaceText(0, 80, 90, 200), "cheaper than any day this month")
	T.check("place: over the high", X.PlaceText(100, 210, 90, 200), "dearer than any day this month")
	local today = X.Day()
	-- a price rising 1 a day from 100, today 102 (the third cheapest of 30 days)
	for i = 0, 28 do X.Record("2589", (today - 29 + i) * DAY + 43200, 100 + i, 100 + i, 20, 2, "Linen Cloth", 1) end
	X.Record("2589", X.Now(), 102, 102, 20, 2)
	local j = X.Jumpy("2589")
	T.check("30 days", #j.days, 30)
	T.check("30-day low", j.low, 100)
	T.check("30-day high", j.high, 128)
	T.check("now", j.now, 102)
	T.near("today: 10% of the days were cheaper (2, and 2 the same)", j.pct, 10, 0.01)
	T.check("today in words", j.place, "cheapest 10% of the month")
	T.check("steady", j.word, "Steady")
	T.near("its average move", j.move, ((function() local s = 0 for i = 0, 27 do s = s + 1 / (100 + i) end return s end)() * 100 + 26 / 128 * 100) / 29, 0.01)
	-- jumping between 1000 and 1150 every day: about 14% a day
	for i = 0, 19 do X.Record("2592", (today - 20 + i) * DAY + 43200, nil, i % 2 == 0 and 1000 or 1150, 20, 2, "Wool Cloth", 1) end
	j = X.Jumpy("2592")
	T.check("alternating: jumpy", j.word, "Jumpy")
	T.ok("alternating: about 14% a day", j.move > 13 and j.move < 15, j.move)
	-- too few days
	for i = 0, 2 do X.Record("4306", (today - 3 + i) * DAY + 43200, 500, 500, 20, 2, "Silk Cloth", 1) end
	j = X.Jumpy("4306")
	T.ok("3 days: no word, no place", j.word == nil and j.place == nil and j.moves == 2, j.moves)
	T.check("unknown item", #X.Jumpy("99999").days, 0)
end)

T.scene("35 patterns: market size from drops and from full scans compared", function()
	local X = W.start()
	local byDay, units, secs = X.PatternDrops({{0, 1, 1, 100}, {3600, 1, 1, 80}, {7200, 1, 1, 90}, {10800, 1, 1, 60},
		{10800 + 13 * 3600, 1, 1, 10}})
	T.check("drops: units gone (new listings and long gaps left out)", units, 50)
	T.check("drops: time compared", secs, 10800)
	T.check("drops: per day", byDay[0] and byDay[0].u, 50)
	-- scans every 2 hours for a day, 10 fewer each time
	local now = X.Now()
	for i = 12, 0, -1 do X.Record("2589", now - i * 2 * HOUR, 95, 100, 200 - (12 - i) * 10, 5, "Linen Cloth", 1) end
	local ms = X.MarketSize("2589")
	T.near("drops: 120 a day", ms.perDay, 120, 0.01)
	T.check("from drops", ms.how, "drops")
	T.check("its price", ms.price, X.Usual("2589"))
	T.near("gold a day", ms.gold, 120 * X.Usual("2589"), 0.5)
	T.ok("a point per day in the graph", #ms.daily >= 1 and #ms.daily <= 2, #ms.daily)
	-- full scans compared (Speed.lua): 30 seen sold in 12 hours watched = 60 a day; that wins
	local day = X.Day()
	X.Realm().speed = {["2589"] = X.b36(day) .. "," .. X.b36(30) .. "," .. X.b36(720)}
	ms = X.MarketSize("2589")
	T.near("full scans: 60 a day", ms.perDay, 60, 0.01)
	T.check("from full scans", ms.how, "scans")
	local last = ms.daily[#ms.daily]
	T.near("the graph: today 60", last and last[2], 60, 0.01)
	T.ok("the graph: gold that day", last and last[3] and last[3] > 0)
	-- nothing known
	ms = X.MarketSize("99999")
	T.ok("unknown: nothing", ms.perDay == nil and #ms.daily == 0)
	X.Record("4306", now, 500, 500, 20, 2, "Silk Cloth", 1)
	ms = X.MarketSize("4306")
	T.ok("one scan: not known yet", ms.perDay == nil and ms.gold == nil)
end)

T.scene("35 patterns: the Patterns page and the Overview's small grid", function()
	local X = W.start()
	local keys = {}
	for _, pg in ipairs(X.UI.ITEM_PAGES) do keys[#keys + 1] = pg.key end
	T.ok("Patterns is the second page", keys[1] == "overview" and keys[2] == "patterns", table.concat(keys, ","))
	X.Record("4306", X.Now() - 600, 500, 500, 20, 2, "Silk Cloth", 1) -- one price only
	X.UI.Toggle()
	X.UI.ShowItem("4306")
	W.advance(0.5)
	local panel = X.UI.tabs.items.panel
	-- the Overview's box: the small grid, the cheapest / dearest time, the best day and hour
	local box = W.screen(panel.bestBox)
	T.ok("overview: the box title", has(box, "Best time to sell"), box)
	T.ok("overview: the grid's title", has(box, "Price by weekday and time of day (server time)"), box)
	T.ok("overview: day and hour lines", has(box, "Best day to sell:") and has(box, "Best hour:"), box)
	T.ok("overview: cheapest and dearest line", has(box, "Cheapest:") and has(box, "Dearest:"), box)
	T.ok("overview: the grid is shown", panel.best:IsShown() and panel.best.GetInfo().scheme == "price")
	T.ok("overview: weekday names", has(box, "Mon") and has(box, "Sun"), box)

	-- an item with nothing at all: the page says so, nothing breaks
	X.UI.ShowItem("99999")
	W.advance(0.3)
	W.click("Patterns", panel.ana)
	W.advance(0.3)
	T.check("the page remembered", X.S().itemPage, "patterns")
	local page = panel.pages.frames.patterns
	T.ok("the page shown, Overview hidden", page:IsVisible() and not panel.tiles[1]:IsVisible())
	local screen = W.screen(page)
	T.ok("nothing: the grid says so", has(screen, "No prices yet"), screen)
	T.ok("nothing: too new", has(screen, "too new"), screen)
	T.ok("nothing: market size not known", has(screen, "Not known yet"), screen)
	T.ok("nothing: the graphs say so", has(screen, "No daily prices yet") and has(screen, "No sales seen yet"), screen)
	T.check("nothing: no grid made", X.Items()["99999"], nil)

	-- an item with a lot
	patterned(X, "2589", "Linen Cloth")
	X.UI.ShowItem("2589")
	W.advance(0.3)
	screen = W.screen(page)
	T.ok("lots: the tiles", has(screen, "Steady or jumpy") and has(screen, "30-day low") and has(screen, "Gold a day"), screen)
	T.ok("lots: cheapest time", has(screen, "Cheapest: Tue 8-12 (-"), screen)
	T.ok("lots: dearest time", has(screen, "Dearest: Sat 20-24 (+"), screen)
	T.ok("lots: a word for the price", has(screen, "Steady") or has(screen, "Moves a bit") or has(screen, "Jumpy"), screen)
	T.ok("lots: the market size", has(screen, "This item moves about") and has(screen, "sold a day"), screen)
	T.ok("lots: the estimate said", has(screen, "listings disappearing"), screen)
	T.ok("lots: enough to go by", has(screen, "observations at 42 of 42 times"), screen)
	T.check("lots: every square coloured", page.heat.GetInfo().shown, 42)
	-- hover a square: its numbers
	local tue = page.heat.cells[2][3] -- Tuesday (row 2, Monday first), 8-12
	W.hover(tue)
	local tip = W.plain(W.tipText(W.env.GameTooltip.lines))
	W.unhover(tue)
	T.ok("hover a square: when", has(tip, "Tuesday 08:00 - 12:00"), tip)
	T.ok("hover a square: price, listed, seen", has(tip, "Price then") and has(tip, "cheaper than usual") and has(tip, "Listed then") and
		has(tip, "Seen"), tip)
	-- hover a tile: what it means
	W.hover(page.tiles[5])
	tip = W.plain(W.tipText(W.env.GameTooltip.lines))
	W.unhover(page.tiles[5])
	T.ok("hover a tile: the estimate explained", has(tip, "bought - or cancelled"), tip)
	-- hover the graph: numbers
	W.hover(page.jumpGraph.plot, 200, 10)
	W.advance(0.1)
	W.unhover(page.jumpGraph.plot)
	local gi = page.jumpGraph.GetInfo()
	T.ok("the jumpy graph: the low and high lines", gi and gi.levels and #gi.levels == 2, gi and gi.levels and #gi.levels)
	-- the supply switch
	W.click("Supply", page)
	W.advance(0.2)
	screen = W.screen(page)
	T.check("supply: kept", X.S().patternsMode, "supply")
	T.ok("supply: the title and the line", has(screen, "When is it scarce?") and has(screen, "Scarcest: Sun"), screen)
	T.check("supply: the colours", page.heat.GetInfo().scheme, "supply")
	W.click("Price", page)
	W.advance(0.2)
	T.ok("price again", has(W.screen(page), "When is it cheap?"))
	-- refreshing with new prices keeps working
	X.Record("2589", X.Now(), 95, 100, 40, 5)
	X.Fire("XNAH_PRICES")
	W.advance(0.5)
	T.ok("refreshed: still there", has(W.screen(page), "Cheapest: Tue 8-12"), W.screen(page))

	-- the Overview's grid: the same answer, and "Patterns >" opens the page
	W.click("Overview", panel.ana)
	W.advance(0.3)
	box = W.screen(panel.bestBox)
	T.ok("overview: cheapest time", has(box, "Cheapest: Tue 8-12"), box)
	T.check("overview: every square coloured", panel.best.GetInfo().shown, 42)
	W.hover(panel.best.cells[2][3])
	tip = W.plain(W.tipText(W.env.GameTooltip.lines))
	W.unhover(panel.best.cells[2][3])
	T.ok("overview: hover a square", has(tip, "Tuesday 08:00 - 12:00") and has(tip, "Price then"), tip)
	W.click("Patterns >", panel.bestBox)
	W.advance(0.3)
	T.ok("Patterns > opens the page", page:IsVisible() and X.S().itemPage == "patterns")
	-- after a reload the page and the grid are still there
	X = W.reload()
	W.advance(1)
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	panel = X.UI.tabs.items.panel
	T.ok("after a reload: the Patterns page again", panel.pages.frames.patterns:IsVisible() and
		has(W.screen(panel.pages.frames.patterns), "Cheapest: Tue 8-12"))
end)
