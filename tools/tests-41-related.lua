-- XNAH test scenes, part 41: the Items page "Moves with" - items whose prices rise and fall on the same days as the
-- item picked (ore and its bars), and ones that move the opposite way (Related.lua, UIItemRelated.lua): the maths
-- (only shared days, day-to-day changes, too little data, flat prices, crazy prices, chance links left out), the
-- work sliced per frame and cached until new prices, and the page (tables, hovers, + Compare, the range setting).
-- Every scene title starts with "41" (node tools/test.js 41).

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function items(X) return X.UI.tabs.items.panel end
local function pageOf(X, key) return items(X).pages.frames[key] end
local function keysOf(rows)
	local out = {}
	for _, r in ipairs(rows or {}) do out[#out + 1] = r.key end
	return table.concat(out, ",")
end
-- a small random walk that is the same every run
local function walk(seed, n, step)
	local s, v, out = seed, 1, {}
	for i = 1, n do
		s = (s * 1103515245 + 12345) % 2147483648
		v = v * (1 + ((s / 2147483648) - 0.5) * 2 * (step or 0.1))
		out[i] = v
	end
	return out
end
-- one price a day, `days` days up to yesterday: priceOf(daysAgo) (nil = no price that day)
local function daily(X, key, days, priceOf, name)
	local today = X.Day()
	for d = days, 1, -1 do
		local v = priceOf(d)
		if v then
			v = math.floor(v + 0.5)
			X.Record(key, (today - d) * DAY + 3600, v, v, 20, 4, name, 1)
		end
	end
end
-- ore, its bar (three times its price, a little noise), a bar of another metal moving the other way, an unrelated
-- cloth, a flat one, one with too few days, one seen every other day only
local function market(X)
	local ore = walk(7, 41, 0.12)
	local noise, noise2 = walk(99, 41, 0.01), walk(98, 41, 0.06)
	local other = walk(12345, 41, 0.12)
	daily(X, "2770", 40, function(d) return 1000 * ore[d] end, "Copper Ore")
	daily(X, "2840", 40, function(d) return 3000 * ore[d] * noise[d] end, "Copper Bar")
	daily(X, "3576", 40, function(d) return 2000 / ore[d] end, "Tin Bar")
	daily(X, "2589", 40, function(d) return 500 * other[d] end, "Linen Cloth")
	daily(X, "2592", 40, function() return 800 end, "Wool Cloth")
	daily(X, "2771", 5, function(d) return 1500 * ore[d] end, "Tin Ore")
	daily(X, "2841", 40, function(d) return d % 2 == 0 and 5000 * ore[d] * noise2[d] or nil end, "Bronze Bar")
end
-- shows an item and one of its pages; returns the page frame
local function show(X, key, title, pageKey)
	X.UI.ShowItem(key)
	W.advance(0.3)
	W.click(title, items(X))
	W.advance(0.3)
	return pageOf(X, pageKey)
end

T.scene("41 related: the maths - shared days, changes, together and opposite", function()
	local X = W.start()
	market(X)
	-- two items
	local p = X.RelatedPair("2770", "2840", 30)
	T.ok("ore and its bar: a match", p ~= nil)
	T.ok("ore and its bar: very close to 1", p and p.r > 0.95, p and p.r)
	T.check("30 shared days", p and p.shared, 30)
	T.check("29 changes", p and p.changes, 29)
	T.ok("sure of it", p and p.r > X.RelatedNeed(p.changes) and p.low > 0.8, p and p.z)
	p = X.RelatedPair("2770", "3576", 30)
	T.ok("the other way: close to -1", p and p.r < -0.95, p and p.r)
	p = X.RelatedPair("2770", "2589", 30)
	T.ok("unrelated: far from 1 and -1", p and math.abs(p.r) < 0.5, p and p.r)
	T.check("flat price: no match", X.RelatedPair("2770", "2592", 30), nil)
	T.check("too few days: no match", X.RelatedPair("2770", "2771", 30), nil)
	p = X.RelatedPair("2770", "2841", 30)
	T.ok("every other day: still a match", p and p.r > 0.9, p and p.r)
	T.check("every other day: 15 shared days", p and p.shared, 15)
	T.check("every other day: 14 changes (two days apart)", p and p.changes, 14)
	p = X.RelatedPair("2770", "2840", 90)
	T.check("90 days: the whole history (40 days)", p and p.shared, 40)
	T.check("unknown item: nothing", X.RelatedPair("2770", "999999", 30), nil)
	-- the words
	T.check("0.9: very closely", X.RelatedWord(0.9), "Very closely")
	T.check("0.7: closely", X.RelatedWord(0.7), "Closely")
	T.check("0.4: a bit", X.RelatedWord(0.4), "A bit")
	T.check("-0.7: opposite", X.RelatedWord(-0.7), "Opposite")
	-- one item against all
	local res = X.RelatedRun("2770", 30)
	T.check("together: the bar first", res.together[1] and res.together[1].key, "2840")
	T.ok("together: the bronze bar too", has(keysOf(res.together), "2841"), keysOf(res.together))
	T.check("opposite: the tin bar", keysOf(res.opposite), "3576")
	T.ok("the cloth is not listed", not has(keysOf(res.together) .. keysOf(res.opposite), "2589"))
	T.ok("the item itself is not listed", not has(keysOf(res.together), "2770"))
	T.check("words on the rows", res.together[1] and res.together[1].word, "Very closely")
	T.check("compared: bar, tin bar, cloth, bronze bar", res.compared, 4)
	T.check("the item has 30 priced days", res.have, 30)
	for _, r in ipairs(res.together) do T.ok("every row is sure enough (" .. r.key .. ")", math.abs(r.r) >= X.RelatedNeed(r.changes), r.r) end
	-- the item picked has too few prices / hardly moves
	res = X.RelatedRun("2771", 30)
	T.ok("too few: said so", res.tooFew == true and res.have == 5, res.have)
	T.check("too few: no rows", #res.together + #res.opposite, 0)
	res = X.RelatedRun("2592", 30)
	T.ok("flat: said so", res.flat == true)
	T.check("nothing known: too few", X.RelatedRun("999999", 30).tooFew, true)
end)

T.scene("41 related: crazy prices left out, only days both have, chance links not listed", function()
	local X = W.start()
	local ore = walk(7, 41, 0.12)
	daily(X, "2770", 40, function(d) return 1000 * ore[d] end, "Copper Ore")
	-- the bar has one crazy day (50 times its price)
	daily(X, "2840", 40, function(d) return 3000 * ore[d] * (d == 12 and 50 or 1) end, "Copper Bar")
	local p = X.RelatedPair("2770", "2840", 30)
	T.ok("one crazy day does not spoil it", p and p.r > 0.99, p and p.r)
	T.check("the crazy day is not a shared day", p and p.shared, 29)
	-- days only one of them has are not used: the bar's prices on the ore's missing days are skipped
	local X2 = W.start()
	daily(X2, "2770", 40, function(d) return d > 20 and 1000 * ore[d] or nil end, "Copper Ore")
	daily(X2, "2840", 40, function(d) return 3000 * ore[d] end, "Copper Bar")
	p = X2.RelatedPair("2770", "2840", 90)
	T.check("only the ore's 20 days", p and p.shared, 20)
	-- a gap of more than 7 days between shared days is not one change
	local X3 = W.start()
	daily(X3, "2770", 40, function(d) return (d > 25 or d < 14) and 1000 * ore[d] or nil end, "Copper Ore")
	daily(X3, "2840", 40, function(d) return 3000 * ore[d] end, "Copper Bar")
	p = X3.RelatedPair("2770", "2840", 90)
	T.check("28 shared days", p and p.shared, 28)
	T.check("26 changes (the 12-day gap is not one)", p and p.changes, 26)
	-- few days and a so-so link: not listed (two unrelated items can look linked by chance)
	local X4 = W.start()
	local a, b = walk(1, 12, 0.1), walk(2, 12, 0.1)
	daily(X4, "2770", 11, function(d) return 1000 * a[d] end, "Copper Ore")
	daily(X4, "2840", 11, function(d) return 1000 * (a[d] + b[d]) end, "Copper Bar")
	p = X4.RelatedPair("2770", "2840", 30)
	T.ok("a so-so link on 11 days", p and p.r > 0.3 and p.r < 0.9, p and p.r)
	local res = X4.RelatedRun("2770", 30)
	T.check("not listed", #res.together, 0)
	-- how big a link must be: bigger with few days
	T.near("9 changes: about 0.95", X.RelatedNeed(9), 0.95, 0.001)
	T.near("29 changes: between 25 and 30", X.RelatedNeed(29), 0.653, 0.002)
	T.ok("more changes: smaller", X.RelatedNeed(60) < X.RelatedNeed(30) and X.RelatedNeed(120) < X.RelatedNeed(90))
	T.check("fewer than 8: as for 8", X.RelatedNeed(5), X.RelatedNeed(8))
end)

T.scene("41 related: the whole market moving is not a link, few listed are left out", function()
	local X = W.start()
	-- 40 items that follow the market (all dearer and cheaper on the same days) plus a little of their own
	local market = walk(5, 41, 0.15)
	for i = 1, 40 do
		local own = walk(1000 + i, 41, 0.04)
		daily(X, tostring(600000 + i), 40, function(d) return 1000 * market[d] * own[d] end, "Market Item " .. i)
	end
	local ore = walk(7, 41, 0.04)
	daily(X, "2770", 40, function(d) return 1000 * market[d] * ore[d] end, "Copper Ore")
	daily(X, "2840", 40, function(d) return 3000 * market[d] * ore[d] end, "Copper Bar")
	-- without taking the market out, every one of them looks linked
	local plain = X.RelatedPair("2770", "600001", 30)
	T.ok("without the market taken out: looks linked", plain and plain.r > 0.6, plain and plain.r)
	local level = X.RelatedMarket(30)
	local p = X.RelatedPair("2770", "600001", 30, level)
	T.ok("with it: no link", p and math.abs(p.r) < X.RelatedNeed(p.changes), p and p.r)
	local res = X.RelatedRun("2770", 30)
	T.check("only the bar is listed", keysOf(res.together), "2840")
	T.check("nothing opposite", #res.opposite, 0)
	-- the market level: the typical change of the day, added up
	local mkt = walk(5, 41, 0.15)
	local today0 = X.Day()
	local step = level[today0 - 1] - level[today0 - 2]
	T.near("the market's change of a day (yesterday)", step, math.log(mkt[1] / mkt[2]), 0.05)
	-- one or two listed: left out (and as the item picked: said so)
	local today = X.Day()
	for d = 30, 1, -1 do X.Record("2841", (today - d) * DAY + 3600, 3000 * ore[d], 3000 * ore[d], 2, 2, "Bronze Bar", 1) end
	T.check("two listed: no match", X.RelatedPair("2770", "2841", 30), nil)
	res = X.RelatedRun("2841", 30)
	T.ok("two listed: said so", res.fewListed ~= nil and res.fewListed < 5, res.fewListed)
	-- a market where no item moved stays at 0 (no change at all is the middle step)
	local Y = W.start()
	for i = 1, 25 do daily(Y, tostring(610000 + i), 20, function() return 500 end, "Still Item " .. i) end
	local still = Y.RelatedMarket(30)
	T.check("no item moved: the market stays at 0", still[Y.Day() - 1], 0)
end)

T.scene("41 related: worked out a little per frame, cached until new prices", function()
	local X = W.start()
	market(X)
	-- a big auction house: 3,000 more items with 60 days of prices each, written straight into the history
	local today = X.Day()
	for i = 1, 3000 do
		local it = X.Item(tostring(400000 + i), true)
		local w = walk(100000 + i, 61, 0.1)
		local parts = {}
		for d = 60, 1, -1 do
			local v = math.floor(1000 * w[d] + 0.5)
			parts[#parts + 1] = X.b36(today - d) .. "," .. X.b36(v) .. "," .. X.b36(v) .. ",k,1"
		end
		it.d = table.concat(parts, ";")
		it.n = "Item " .. i
	end
	W.advance(15) -- (the login is done: bags and the like are written)
	local before = W.savedSize()
	W.maxStepTime = 0
	local res, busy, progress = X.Related("2770", 30)
	T.ok("busy at first", busy == true and res == nil)
	T.ok("a progress line", has(progress, "Working... 0%"), progress)
	local steps = 0
	W.waitFor(function()
		steps = steps + 1
		local _, b = X.Related("2770", 30)
		return not b
	end, 120)
	res, busy = X.Related("2770", 30)
	T.ok("done", not busy and res ~= nil)
	T.ok("it took several frames", steps > 5, steps)
	T.check("the bar first", res and res.together[1] and res.together[1].key, "2840")
	T.check("the tin bar opposite", res and res.opposite[1] and res.opposite[1].key, "3576")
	T.ok("all compared", res and res.compared >= 3000, res and res.compared)
	T.note(string.format("41 related: 3,007 items compared in %d frames, slowest frame %.0f ms (stand-in, slower than the game)",
		steps, W.maxStepTime * 1000))
	-- cached: the same result, not busy
	local again, b2 = X.Related("2770", 30)
	T.ok("cached", again == res and not b2)
	-- item names coming in change nothing
	X.Fire("XNAH_PRICES", "names")
	again, b2 = X.Related("2770", 30)
	T.ok("names: still cached", again == res and not b2)
	T.check("nothing saved", W.savedSize() - before, 0)
	-- new prices: worked out again, the old result shown meanwhile
	X.Record("2770", X.Now(), 900, 900, 20, 4)
	X.Fire("XNAH_PRICES")
	local old, b3, prog = X.Related("2770", 30)
	T.ok("new prices: busy again, the old result meanwhile", b3 == true and old == res, prog)
	-- another item while busy: the first stops, the second runs
	local _, b4 = X.Related("2840", 30)
	T.ok("another item: busy", b4 == true)
	W.waitFor(function() local _, b = X.Related("2840", 30) return not b end, 120)
	local r2 = X.Related("2840", 30)
	T.check("the bar: the ore first", r2 and r2.together[1] and r2.together[1].key, "2770")
	-- the ore again: worked out (the stopped run kept nothing new)
	local _, b5 = X.Related("2770", 30)
	T.ok("the ore: again busy", b5 == true)
	W.waitFor(function() local _, b = X.Related("2770", 30) return not b end, 120)
	T.ok("the ore: done again", select(2, X.Related("2770", 30)) == false)
	-- too few prices: answered at once, no work
	local r3, b6 = X.Related("2771", 30)
	T.ok("too few: at once", r3 and r3.tooFew and not b6)
end)

T.scene("41 related: the page - tables, hovers, + Compare, the range setting", function()
	local X = W.start()
	market(X)
	local page = show(X, "2770", "Moves with", "related")
	T.ok("the page is shown", page and page:IsVisible())
	T.check("the page key kept", X.S().itemPage, "related")
	W.advance(1)
	local text = W.screen(page)
	T.ok("says moving together proves nothing", has(text, "does not prove"), text)
	T.ok("the two tables", has(text, "Moves together") and has(text, "Moves the opposite way"), text)
	T.check("together: the bar first", page.together.items[1] and page.together.items[1].key, "2840")
	T.check("opposite: the tin bar", page.opposite.items[1] and page.opposite.items[1].key, "3576")
	local tt = W.screen(page.together)
	T.ok("words, days, prices", has(tt, "Very closely") and has(tt, "Copper Bar") and has(tt, "30") and has(tt, "%"), tt)
	T.ok("opposite in words", has(W.screen(page.opposite), "Opposite"), W.screen(page.opposite))
	T.ok("compared line", has(W.plain(page.note.text), "Compared with 4 items"), page.note.text)
	-- the column hovers
	T.ok("every column has a hover", page.together.columns[2].tip ~= nil and page.together.columns[7].tip ~= nil)
	W.hover(page.together.headerButtons[2])
	T.ok("hover: how closely", has(W.tipText(), "Opposite"), W.tipText())
	W.unhover(page.together.headerButtons[2])
	-- the row hover: the number
	local rf = page.together.rows[1]
	W.hover(rf)
	T.ok("row hover: the match number", has(W.tipText(), "Match: ") and has(W.tipText(), "30 days both had a price"), W.tipText())
	W.unhover(rf)
	-- + Compare
	T.check("the button", W.plain(rf.compare.label.text), "+ Compare")
	rf.compare:Click("LeftButton")
	W.advance(0.3)
	T.check("on the Compare list", table.concat(X.CompareList("2770"), ","), "2840")
	T.check("the button says so", W.plain(page.together.rows[1].compare.label.text), "on Compare")
	T.ok("a line says so", has(W.plain(page.note.text), "on the Compare page now"), page.note.text)
	page.together.rows[1].compare:Click("LeftButton")
	W.advance(0.3)
	T.check("twice: still once", table.concat(X.CompareList("2770"), ","), "2840")
	for _, k in ipairs({"2589", "2592", "2771"}) do X.CompareAdd("2770", k) end
	X.UI.Refresh(true)
	W.advance(0.3)
	T.check("full: the button says so", W.plain(page.opposite.rows[1].compare.label.text), "Compare full")
	page.opposite.rows[1].compare:Click("LeftButton")
	W.advance(0.3)
	T.ok("full: a line says why", has(W.plain(page.note.text), "full"), page.note.text)
	T.check("full: not added", #X.CompareList("2770"), 4)
	-- click a row: that item is picked, the page stays
	W.click("Tin Bar", page.opposite)
	W.advance(1)
	T.check("the row's item is picked", X.UI.itemKey, "3576")
	T.check("the page stays", X.S().itemPage, "related")
	T.check("its own list: the ore the other way", page.opposite.items[1] and page.opposite.items[1].key, "2770")
	-- the range
	W.click("90 days", page)
	W.advance(1)
	T.check("range kept", X.S().relatedRange, 90)
	T.ok("90 days: 40 shared days", page.opposite.items[1] and page.opposite.items[1].shared == 40)
	-- too few prices: a plain line
	X.UI.ShowItem("2771")
	W.advance(1)
	T.ok("too few: says so", has(page.together.empty.text, "Not enough prices") and has(page.together.empty.text, "it has 5"),
		page.together.empty.text)
	X.UI.ShowItem("2592")
	W.advance(1)
	T.ok("flat: says so", has(page.together.empty.text, "hardly moved"), page.together.empty.text)
	-- a short history: a warning that a match can be chance
	local ore = walk(7, 41, 0.12)
	local wob = walk(77, 41, 0.05)
	daily(X, "2842", 15, function(d) return 2000 * ore[d] * wob[d] end, "Silver Bar")
	X.UI.ShowItem("2842")
	W.advance(1)
	T.ok("short history: a warning", has(W.plain(page.note.text), "15 days of prices so far"), page.note.text)
	T.ok("short history: still listed", has(keysOf(page.together.items), "2770"), keysOf(page.together.items))
	-- after a reload: the range and the page are kept
	X = W.reload()
	W.advance(1)
	T.check("after a reload: 90 days", X.S().relatedRange, 90)
	page = show(X, "2770", "Moves with", "related")
	W.advance(1)
	T.ok("after a reload: 90 days picked", page.ranges[90] ~= nil)
	T.check("after a reload: the bar first", page.together.items[1] and page.together.items[1].key, "2840")
	-- a range that is not offered any more: 30 days
	X.S().relatedRange = 45
	X.UI.Refresh(true)
	W.advance(1)
	T.check("odd range: 30 days used", page.together.items[1] and page.together.items[1].shared, 30)
end)
