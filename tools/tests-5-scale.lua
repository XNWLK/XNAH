-- XNAH test scenes, part 5: a big auction house. A 30,000-auction full scan must be read in slices (no frame of the
-- game doing too much), and the saved data after 20 days must stay a sensible size. The numbers are printed above the
-- result line.

T.scene("scale: 30,000-auction full scan and 20 days of history", function()
	local X = W.start()
	W.makeMarket(99, 1850, {uncached = 0.1})
	T.ok("30,000+ auctions", #W.ah >= 30000, #W.ah)
	W.openAH()
	W.maxStepRows, W.maxStepTime, W.rowsRead = 0, 0, 0
	local c0, ticks0 = os.clock(), W.ticks
	local g0 = W.NOW
	T.ok("full scan finished", T.fullScan(X))
	local secs = os.clock() - c0
	T.note(string.format("scale: full scan of %d auctions (%d items, 10%% not loaded at first): %.1f s game time, %d frames, %d rows read, most rows in one step %d, slowest step %.0f ms here (fengari; the game is far faster), %.1f s here in all",
		#W.ah, T.count(X.Items()), W.NOW - g0, W.ticks - ticks0, W.rowsRead, W.maxStepRows, W.maxStepTime * 1000, secs))
	-- the retry of not-loaded items reads them all in one go: about 3,000 rows in one step at this size
	T.ok("no single step read more than about 1,000 rows", W.maxStepRows <= 1100, W.maxStepRows)
	local items = T.count(X.Items())
	-- 19 more days, one full scan a day (recorded directly: the same as a scan's saving, without reading 30,000 rows)
	local r = W.rng(5)
	local c1 = os.clock()
	for day = 1, 19 do
		W.advance(86400)
		local t = X.Now()
		for key, it in pairs(X.Items()) do
			local c = it.cur
			if c and c.mkt then
				local f = 0.9 + r() * 0.2
				X.Record(key, t, c.min and c.min * f, c.mkt * f, math.max(1, math.floor((c.qty > 0 and c.qty or 10) * (0.8 + r() * 0.4))), c.auc, nil, nil)
			end
		end
	end
	T.note(string.format("scale: 19 days x %d items recorded in %.1f s here", items, os.clock() - c1))
	-- the 20th day: a real full scan again
	W.advance(86400)
	W.marketDay(1)
	W.maxStepRows = 0
	T.ok("full scan on day 20", T.fullScan(X))
	local n, bytes = X.DataSize()
	local file = W.savedSize()
	T.note(string.format("scale: after 20 days (1 full scan a day): %d items, DataSize %d bytes (%.0f a item), saved file %.2f MB",
		n, bytes, bytes / n, file / 1048576))
	T.ok("saved file under 10 MB", file < 10 * 1048576, file)
	-- the statistics of every item (the Trends tab, deals) - and what that does to the saved file
	local c2 = os.clock()
	X.Deals()
	X.Movers("up")
	local file2 = W.savedSize()
	T.note(string.format("scale: deals + movers over %d items: %.1f s here; saved file then %.2f MB (statistics cache saved too: +%.2f MB)",
		n, os.clock() - c2, file2 / 1048576, (file2 - file) / 1048576))
	-- a reload with this much data
	local c3 = os.clock()
	X = W.reload()
	T.note(string.format("scale: reload (write + read the saved file): %.1f s here", os.clock() - c3))
	T.check("after reload: same number of items", T.count(X.Items()), n)
end)

T.scene("scale: data size per item with 4 full scans a day", function()
	local X = W.start()
	local S = X.S()
	local now = X.Now()
	-- 200 items, 4 scans a day for 30 days (scan points kept 10 days, day points for all 30)
	local r = W.rng(7)
	for i = 1, 200 do
		local key = tostring(500000 + i)
		local base = 100 + r() * 100000
		for day = 0, 29 do
			for s = 0, 3 do
				local t = now - (29 - day) * 86400 + s * 6 * 3600
				X.Record(key, t, base * 0.95, base, r(10, 2000), r(5, 200), "Item " .. i, 1)
			end
		end
	end
	local n, bytes = X.DataSize()
	local per = bytes / n
	T.note(string.format("scale: 4 full scans a day, keepScanDays %d: %.0f bytes a item (DataSize) -> 5,000 items about %.1f MB, 20,000 items about %.1f MB",
		S.keepScanDays, per, per * 5000 / 1048576, per * 20000 / 1048576))
	-- a year of day points: what one item costs then
	local it = X.Items()["500001"]
	local dp, hp = X.UnpackPoints(it.d), X.UnpackPoints(it.h)
	local dBytes, hBytes = #it.d / #dp, #it.h / #hp
	local year = 365 * dBytes + S.keepScanDays * 4 * hBytes + 60
	T.note(string.format('scale: a day point %.1f bytes, a scan point %.1f bytes; after a year (365 day points + 10 days of 4 scans) %.0f bytes a item -> 5,000 items about %.1f MB, 20,000 items about %.1f MB',
		dBytes, hBytes, year, year * 5000 / 1048576, year * 20000 / 1048576))
end)
