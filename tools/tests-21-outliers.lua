-- XNAH test scenes, part 21: crazy prices left out (Solid Stone: one scan at 1g among 1s 75c ones made its usual price
-- 11s 61c), items never suggested as buys (right-click), grey junk never a buy idea, names in their rarity colour.

T.scene("outliers: one crazy scan does not change the usual price", function()
	local X = W.start()
	local key = "7912"
	local t = X.Now() - 3 * 86400
	-- three days of normal scans, one crazy scan in the middle
	for i = 1, 6 do X.Record(key, t + i * 3600, 170, 175, 7000, 36, "Solid Stone", 1) end
	X.Record(key, t + 86400, 10000, 10000, 2, 1, "Solid Stone", 1)        -- 1g: only silly listings at that scan
	for i = 1, 6 do X.Record(key, t + 86400 + i * 3600, 172, 176, 7100, 36, "Solid Stone", 1) end
	for i = 1, 4 do X.Record(key, t + 2 * 86400 + i * 3600, 174, 179, 7244, 36, "Solid Stone", 1) end
	local st = X.Stats(key)
	T.ok("the usual price stays about 1s 75c", st.avg30 and st.avg30 < 200 and st.avg30 > 150, st.avg30)
	T.ok("the 30-day high is not 1g", st.high30 and st.high30 < 300, st.high30)
	for _, p in ipairs(X.History(key, 0)) do T.ok("no 1g point on the graph", (p[3] or p[2]) < 1000, p[3]) end
	-- no deal from it: 1s 74c is its normal price
	local deal = false
	for _, d in ipairs(X.Deals()) do if d.key == key then deal = true end end
	T.ok("no false deal", not deal)

	-- data saved before this fix: a day price already spoiled by the crazy scan
	local it = X.Items()[key]
	local today = X.Day()
	it.d = X.b36(today - 3) .. ",aq,4u,5gw,6;" .. X.b36(today - 2) .. ",aq,9c0,5gw,7;" .. X.b36(today - 1) .. ",aq,4w,5gw,6"
	X.statsCache[it] = nil
	st = X.Stats(key)
	T.ok("old spoiled day left out", st.avg30 and st.avg30 < 200, st.avg30)
	T.check("one day dropped", st.dropped, 1)
end)

T.scene("outliers: a real change of price is taken after three scans", function()
	local X = W.start()
	local key = "2589"
	local t = X.Now() - 86400
	for i = 1, 5 do X.Record(key, t + i * 600, 50, 50, 100, 5, "Linen Cloth", 1) end
	X.Record(key, t + 4000, 400, 400, 20, 2, "Linen Cloth", 1)
	X.Record(key, t + 5000, 410, 410, 20, 2, "Linen Cloth", 1)
	local before = #X.History(key, 0, true)
	X.Record(key, t + 6000, 420, 420, 20, 2, "Linen Cloth", 1)
	T.check("the third high scan in a row is kept", #X.History(key, 0, true), before + 1)
	T.check("the price now follows", X.Items()[key].cur.mkt, 420)
end)

T.scene("never suggest: right-click, grey junk, rarity colours", function()
	local X = W.start()
	local now = X.Now()
	-- a cheap listing of a normally dear item (a deal), a grey item listed far under its silly usual price
	for d = 6, 1, -1 do
		X.Record("2589", now - d * 86400, 40000, 40000, 50, 5, "Linen Cloth", 1)
		X.Record("4865", now - d * 86400, 1000000, 1000000, 1, 1, "Ruined Pelt", 0)
	end
	X.Record("2589", now, 10000, 38000, 50, 5, "Linen Cloth", 1)
	X.Record("4865", now, 10000, 10000, 1, 1, "Ruined Pelt", 0)
	local keys = {}
	for _, d in ipairs(X.Deals()) do keys[d.key] = true end
	T.ok("Linen Cloth is a deal", keys["2589"])
	T.ok("the grey item is never a buy idea", not keys["4865"])
	-- right-click: Never suggest buying this
	X.UI.Open("market")
	W.advance(0.5)
	local anchor = X.UI.Frame()
	X.UI.ItemMenu(anchor, "2589")
	local entry
	for _, m in ipairs(W.menu and W.menu() or {}) do if (m.text or ""):find("Never suggest", 1, true) then entry = m end end
	if entry then entry.func() else X.SetIgnored("2589", true) end
	T.ok("ignored", X.Ignored("2589"))
	keys = {}
	for _, d in ipairs(X.Deals()) do keys[d.key] = true end
	T.ok("ignored: no longer a deal", not keys["2589"])
	T.check("listed as never suggested", X.IgnoredList()[1], "2589")
	X.SetIgnored("2589", false)
	T.ok("allowed again", not X.Ignored("2589"))
end)
