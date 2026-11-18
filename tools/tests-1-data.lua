-- XNAH test scenes, part 1: market value, recording prices, history packing and the numbers worked out from it.

T.scene("data: money and number text", function()
	local X = W.start()
	T.check("money 12g 34s 56c", W.plain(X.Money(123456)), "12g 34s 56c")
	T.check("money short above 1g", W.plain(X.Money(123456, true)), "12g 34s")
	T.check("money 0", W.plain(X.Money(0)), "0c")
	T.check("money nil", W.plain(X.Money(nil)), "-")
	T.check("money negative", W.plain(X.Money(-250)), "-2s 50c")
	T.check("parse 12g 3s", X.ParseMoney("12g 3s"), 120300)
	T.check("parse 12.5g", X.ParseMoney("12.5g"), 125000)
	T.check("parse bare number = gold", X.ParseMoney("7"), 70000)
	T.check("parse 56c", X.ParseMoney("56c"), 56)
	T.check("parse nonsense", X.ParseMoney("abc"), nil)
	T.check("number with commas", X.Num(1234567), "1,234,567")
	T.check("clock", X.Clock(125), "2:05")
	T.check("key from a link", X.KeyFromLink(W.link(2589)), "2589")
	T.check("key from a link with a random suffix", X.KeyFromLink(W.link(15210, -19)), "15210:-19")
	T.check("id of a key", X.KeyID("15210:-19"), 15210)
end)

T.scene("data: market value", function()
	local X = W.start()
	-- one listing
	local min, mkt, qty, auc = X.MarketValue({{500, 1}})
	T.check("single: min", min, 500)
	T.check("single: market value", mkt, 500)
	T.check("single: quantity", qty, 1)
	T.check("single: auctions", auc, 1)
	-- a wall of cheap units: the market value is the wall's price
	min, mkt, qty = X.MarketValue({{300, 5}, {100, 200}, {150, 10}})
	T.check("wall: min", min, 100)
	T.check("wall: market value", mkt, 100)
	T.check("wall: quantity", qty, 215)
	-- one silly-high outlier does not move it
	min, mkt = X.MarketValue({{1000, 2}, {1050, 2}, {1100, 2}, {1200, 2}, {500000, 1}})
	T.ok("outlier: market value stays near 1,000", mkt >= 1000 and mkt <= 1100, mkt)
	min, mkt = X.MarketValue({{1000, 1}, {1020, 1}, {1040, 1}, {990000, 1}})
	T.ok("outlier (4 single auctions): market value near 1,000", mkt >= 1000 and mkt <= 1040, mkt)
	-- one absurdly cheap listing: it is the lowest price, but not the market value
	min, mkt = X.MarketValue({{1, 1}, {10000, 50}, {10500, 50}})
	T.check("cheap one: min", min, 1)
	T.check("cheap one: market value", mkt, 10000)
	min, mkt = X.MarketValue({{5, 1}, {10000, 1}, {10100, 1}, {10200, 1}, {10300, 1}, {10400, 1}})
	T.ok("cheap one among single auctions: market value about 10,000", mkt >= 9900 and mkt <= 10400, mkt)
	-- empty
	T.check("empty list", X.MarketValue({}), nil)
	T.check("no list", X.MarketValue(nil), nil)
	-- an even spread: the cheap end counts
	local list = {}
	for i = 1, 20 do list[i] = {1000 + i * 10, 5} end
	min, mkt = X.MarketValue(list)
	T.ok("spread: between the lowest and the middle", mkt >= 1010 and mkt <= 1100, mkt)
end)

T.scene("data: base 36 packing round trip", function()
	local X = W.start()
	for _, n in ipairs({0, 1, 35, 36, 1295, 1296, 99999, 123456789, 29916720, -42}) do
		T.check("b36 " .. n, X.n36(X.b36(n)), n)
	end
	T.check("b36 rounds", X.n36(X.b36(12.6)), 13)
	T.check("b36 nil", X.b36(nil), "")
	T.check("n36 empty", X.n36(""), nil)
end)

T.scene("data: recording prices and the history strings", function()
	local X = W.start()
	local t0 = X.Now()
	local it = X.Record("2589", t0, 100, 120, 50, 3, "Linen Cloth", 1)
	T.check("name kept", it.n, "Linen Cloth")
	T.check("current min", it.cur.min, 100)
	local p = X.UnpackPoints(it.h)
	T.check("one scan point", #p, 1)
	T.check("point time (minutes)", p[1][1], math.floor(t0 / 60))
	T.check("point min", p[1][2], 100)
	T.check("point mkt", p[1][3], 120)
	T.check("point qty", p[1][4], 50)
	T.check("point auctions", p[1][5], 3)
	-- the same minute again replaces the point
	X.Record("2589", t0 + 20, 90, 110, 40, 2)
	p = X.UnpackPoints(it.h)
	T.check("same minute: still one point", #p, 1)
	T.check("same minute: newer min", p[1][2], 90)
	local d = X.UnpackPoints(it.d)
	T.check("one day point", #d, 1)
	T.check("day point: lowest min", d[1][2], 90)
	T.check("day point: average mkt", d[1][3], 115)
	T.check("day point: 2 observations", d[1][5], 2)
	-- an older observation never replaces a newer one
	X.Record("2589", t0 - 3600, 1, 1, 1, 1)
	T.check("older observation ignored", it.cur.min, 90)
	-- another minute: a second point
	X.Record("2589", t0 + 120, 95, 130, 45, 3)
	T.check("next minute: two points", #X.UnpackPoints(it.h), 2)
	T.check("day point: three observations, average mkt", X.UnpackPoints(it.d)[1][3], 120)
	-- the saved data survives a reload (written as text and read back)
	local h, dd = it.h, it.d
	X = W.reload()
	T.check("after reload: scan points", X.Items()["2589"].h, h)
	T.check("after reload: day points", X.Items()["2589"].d, dd)
	T.check("after reload: current min", X.Items()["2589"].cur.min, 95)
end)

T.scene("data: pruning old points", function()
	local X = W.start()
	local S = X.S()
	S.keepScanDays, S.keepDays = 10, 365
	local t0 = X.Now()
	for day = 0, 12 do X.Record("2589", t0 + day * 86400, 100 + day, 100 + day, 10, 1) end
	local it = X.Items()["2589"]
	local h = X.UnpackPoints(it.h)
	T.check("scan points: only the last 10 days kept (11 points: day 2 .. 12)", #h, 11)
	T.check("oldest scan point kept is day 2", h[1][2], 102)
	T.check("day points: all 13 kept", #X.UnpackPoints(it.d), 13)
	S.keepDays = 5
	X.Record("2589", t0 + 13 * 86400, 200, 200, 10, 1)
	local d = X.UnpackPoints(it.d)
	T.check("day points pruned to keepDays", #d, 6)
	T.check("oldest day point kept", d[1][1], X.Day(t0) + 8)
end)

T.scene("data: statistics from the history", function()
	local X = W.start()
	-- 14 days rising by 100 a day, with the clock at the last day
	local now = X.Now()
	for i = 0, 13 do
		local t = now - (13 - i) * 86400
		X.Record("2589", t, 1000 + i * 100 - 20, 1000 + i * 100, 100 + i, 5, "Linen Cloth", 1)
	end
	local st = X.Stats("2589")
	T.check("days with data", st.days, 14)
	T.near("3-day average", st.avg3, 2200)
	T.near("7-day average", st.avg7, 2000)
	T.near("30-day average", st.avg30, 1650)
	T.check("30-day low", st.low30, 1000)
	T.check("30-day high", st.high30, 2300)
	T.ok("trend is rising", st.trend and st.trend > 0, st.trend)
	-- slope 100 a day = 700 a week, over the 14-day average 1650: about +42 % a week
	T.near("trend in % a week", st.trend, 700 / 1650 * 100, 1)
	T.ok("spread (vol) above 0", st.vol and st.vol > 0, st.vol)
	T.near("average quantity of 7 days", st.qty7, 110)
	T.near("supply now vs 7 days", st.supply, (113 / 110 - 1) * 100, 0.1)
	T.check("cached until the next observation", X.Stats("2589"), st)
	-- falling series: trend below 0
	for i = 0, 13 do X.Record("2592", now - (13 - i) * 86400, nil, 5000 - i * 200, 10, 1) end
	T.ok("falling series: trend below 0", (X.Stats("2592").trend or 0) < 0, X.Stats("2592").trend)
	-- price sources
	T.check("price: mkt", X.Price("2589", "mkt"), 2300)
	T.check("price: min", X.Price("2589", "min"), 2280)
	T.near("price: avg7", X.Price("2589", "avg7"), 2000)
	T.check("price: unknown item", X.Price("999999"), nil)
	T.near("after cut (5 %)", X.AfterCut(10000), 9500)
end)

T.scene("data: the statistics cache is not saved and does not go stale", function()
	-- X.Stats caches its numbers on the item (it.stats) until the item's next observation. That table is part of
	-- XNAHDB, so it is written to the saved file, and it is not renewed when the days move on without a new scan.
	local X = W.start()
	local now = X.Now()
	for i = 0, 4 do X.Record("2589", now - (4 - i) * 86400, 100, 100, 10, 1) end
	X.Deals() -- works out the statistics of every item (so does the Trends tab)
	T.ok("saved file holds no statistics cache", not W.saveText(W.env.XNAHDB):find("avg3", 1, true))
	T.ok("3-day average now", X.Stats("2589").avg3 ~= nil)
	-- 10 days without a scan of it: nothing in the last 3 days any more
	W.advance(10 * 86400)
	T.check("10 days later: no 3-day average", X.Stats("2589").avg3, nil)
end)

T.scene("data: history for graphs, oldest first", function()
	local X = W.start()
	X.S().keepScanDays = 10
	local now = X.Now()
	for i = 0, 19 do
		X.Record("2589", now - (19 - i) * 86400, 100 + i, 110 + i, 10, 1)
		X.Record("2589", now - (19 - i) * 86400 + 3600, 101 + i, 111 + i, 10, 1)
	end
	local h = X.History("2589")
	local sorted = true
	for i = 2, #h do if h[i][1] <= h[i - 1][1] then sorted = false end end
	T.ok("points oldest first, no two at the same time", sorted)
	-- 10 days of scan points (2 a day, the oldest day possibly cut) + day points before them
	T.ok("day points before the scan points", #h >= 28 and #h <= 32, #h)
	T.check("last point is the latest scan", h[#h][2], 120)
	local from = X.History("2589", now - 3 * 86400)
	T.ok("from: only the last 3 days", #from >= 6 and #from <= 8, #from)
	T.check("unknown item: empty", #X.History("424242"), 0)
end)

T.scene("data: sold out (RecordGone) and the price falling back", function()
	local X = W.start()
	local now = X.Now()
	X.Record("2589", now - 86400, 100, 120, 50, 3)
	X.Record("2589", now - 3600, 100, 130, 50, 3)
	X.RecordGone("2589", now)
	local it = X.Items()["2589"]
	T.check("quantity 0", it.cur.qty, 0)
	T.check("no lowest price now", it.cur.min, nil)
	T.ok("market price falls back to the recent average", X.Price("2589") ~= nil, X.Price("2589"))
	T.near("falls back to the 3-day average", X.Price("2589"), (120 + 130) / 2, 1)
	-- a second time: nothing new is written, only the time moves
	local h = it.h
	X.RecordGone("2589", now + 600)
	T.check("already gone: no new point", it.h, h)
	T.check("already gone: time moved", it.cur.t, now + 600)
	-- an item never seen is not created
	X.RecordGone("4242", now)
	T.check("unknown item not created", X.Items()["4242"], nil)
end)

T.scene("data: watch list, finding items, size", function()
	local X = W.start()
	X.Record("2589", X.Now(), 10, 10, 1, 1, "Linen Cloth", 1)
	X.Record("2996", X.Now(), 10, 10, 1, 1, "Bolt of Linen Cloth", 1)
	X.Record("2592", X.Now(), 10, 10, 1, 1, "Wool Cloth", 1)
	X.SetWatched("2589", true)
	T.check("watched", X.Watched("2589"), true)
	X.SetWatched("2589", false)
	T.check("unwatched", X.Watched("2589"), false)
	T.check("find by part of the name", #X.Find("linen"), 2)
	T.check("find nothing", #X.Find("zzz"), 0)
	T.check("find by key", X.Find("2592")[1], "2592")
	local items, bytes = X.DataSize()
	T.check("size: items", items, 3)
	T.ok("size: bytes", bytes > 0, bytes)
end)
