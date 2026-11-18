-- XNAH test scenes, part 8: analysis - sales speed from two full scans, the best hours to post, disenchanting values,
-- gear under its disenchanting value, walls and reset chances, sellers from searches, and the new Deals / Trends views.

-- runs the jobs that follow a full scan (sales speed, market shape)
local function settle() W.advance(2) end
local function scanAt(X)
	T.ok("full scan", T.fullScan(X))
	settle()
	return X.Realm().scans[#X.Realm().scans].t
end

T.scene("analysis: sales estimate from two full scans (sold vs expired bands)", function()
	local X = W.start()
	W.openAH()
	-- Linen Cloth, 100 units: 40 with over 12 h left (band 3), 20 with 2-12 h (band 2), 20 with 30 min-2 h, 20 under 30 min
	W.listBand(2589, 50, 10, 4, 3, "Ann")
	W.listBand(2589, 55, 10, 2, 2, "Bob")
	W.listBand(2589, 60, 10, 2, 1, "Cid")
	W.listBand(2589, 65, 10, 2, 0, "Dan")
	-- Wool Cloth: two auctions that look the same (5 at 80c), one with a long time left, one about to run out
	W.listBand(2592, 80, 5, 1, 3, "Eve")
	W.listBand(2592, 80, 5, 1, 0, "Fay")
	local t1 = scanAt(X)
	T.check("one scan: nothing measured yet", X.SaleRate("2589"), nil)
	-- an hour later: 2 of the long ones and 1 of the 2-12 h ones are gone (sold), 1 medium and both short ones too
	-- (those may simply have run out: never counted); one of the two Wool auctions is gone
	W.advance(3600)
	T.check("bought: 2 auctions over 12 h", W.buyOut(2589, 2, 3), 20)
	T.check("bought: 1 auction 2-12 h", W.buyOut(2589, 1, 2), 10)
	W.buyOut(2589, 1, 1)
	W.buyOut(2589, 2, 0)
	W.buyOut(2592, 1, 3)
	local t2 = scanAt(X)
	local gap = t2 - t1
	T.ok("scans about an hour apart", gap >= 3600 and gap < 3700, gap)
	local info = X.speedInfo
	T.check("units seen sold (band 3 + band 2 under 2 h)", info and info.units, 30)
	T.check("items measured", info and info.items, 2)
	-- watched: 60 of the 100 Linen units could not have run out -> the hour counts as 0.6 hours
	local minutes = math.floor(gap / 60 * 0.6 + 0.5)
	local rate, hours = X.SaleRate("2589")
	T.near("Linen: units a day", rate, 30 / minutes * 1440, 0.01)
	T.near("Linen: hours watched", hours, minutes / 60, 0.01)
	-- Wool: the gone one is taken to be the one about to run out -> nothing counted
	T.check("Wool: two look the same, the gone one counts as expired", (X.SaleRate("2592")), 0)
	T.ok("saved per item, base 36", type(X.Realm().speed["2589"]) == "string" and X.Realm().speed["2589"]:find(",", 1, true) ~= nil,
		X.Realm().speed["2589"])
	-- 2.5 hours later: a 2-12 h auction gone no longer counts (it may have run out), one over 12 h does
	W.advance(2.5 * 3600)
	W.buyOut(2589, 1, 2)
	W.buyOut(2589, 1, 3)
	local t3 = scanAt(X)
	T.check("second window: only the band 3 auction counts", X.speedInfo.units, 10)
	T.check("second window: its start", X.speedInfo.from, t2)
	-- 5 hours later: too far apart, not compared
	W.advance(5 * 3600)
	W.buyOut(2589, 1, 3)
	scanAt(X)
	T.check("scans over 4 hours apart are not compared", X.speedInfo.from, t2)
	T.ok("XNAH_ANALYSIS fired", X.speedInfo.t == t3)
	-- the sales ledger (when there is one) is a sure lower limit: own sales per day
	X.LedgerItem = function(key) if key == "2592" then return {sold = 300, days = 10} end end
	T.near("Wool: own sales 30 a day are the lower limit", (X.SaleRate("2592")), 30, 0.001)
	-- kept 30 days
	W.advance(31 * 86400)
	T.check("after 30 days: nothing known", X.SaleRate("2589"), nil)
	-- a reload keeps the speed but forgets the previous scan (memory only)
	X = W.reload()
	T.ok("speed saved", X.Realm().speed ~= nil)
end)

T.scene("analysis: best hours to post", function()
	local X = W.start()
	W.openAH()
	local share = X.BestHours()
	local any = 0
	for h = 0, 23 do any = any + share[h] end
	T.check("nothing known: all hours 0", any, 0)
	W.listBand(2589, 50, 10, 10, 3, "Ann")
	local t1 = scanAt(X)
	W.advance(3600)
	W.buyOut(2589, 6, 3)
	local t2 = scanAt(X)
	-- a quiet window later in the day: 1 sold in 2.5 hours
	W.advance(2.5 * 3600)
	W.buyOut(2589, 1, 3)
	local t3 = scanAt(X)
	local minutes
	share, minutes = X.BestHours()
	local sum = 0
	for h = 0, 23 do sum = sum + share[h] end
	T.near("shares add up to 1", sum, 1, 0.001)
	local h1 = tonumber(W.env.date("%H", t1 + 1800))
	local h2 = tonumber(W.env.date("%H", t2 + 75 * 60))
	T.ok("the busy hour was watched", minutes[h1] > 0, minutes[h1])
	T.ok("the busy hour has the bigger share", share[h1] > share[h2], T.show({busy = share[h1], quiet = share[h2]}))
	local never = (h1 + 12) % 24
	T.check("an hour never watched: share 0", share[never], 0)
	T.check("an hour never watched: 0 minutes", minutes[never], 0)
	T.ok("units saved per hour", X.Realm().hours[h1] ~= nil)
end)

local function deWorld(X)
	W.addDEItems()
	local now = X.Now()
	X.Record("10940", now, 100, 100, 50, 5, "Strange Dust", 2)
	X.Record("10998", now, 1000, 1000, 50, 5, "Lesser Astral Essence", 2)
	X.Record("10978", now, 2000, 2000, 50, 5, "Small Glimmering Shard", 3)
	X.Record("11139", now, 5000, 5000, 50, 5, "Large Glowing Shard", 3)
	X.Record("20725", now, 30000, 30000, 10, 5, "Nexus Crystal", 3)
end

T.scene("analysis: disenchanting values of a green, a blue and an epic", function()
	local X = W.start()
	W.addDEItems()
	local G = W.DE_GEAR
	T.check("green armor: no material prices yet", (X.DEValue(tostring(G.green))), nil)
	local parts = X.DEParts(tostring(G.green))
	T.check("green armor item level 25: 3 materials", parts and #parts, 3)
	T.check("green armor: mostly dust", parts and parts[1][1], 10940)
	T.check("green armor: dust 75%", parts and parts[1][2], 0.75)
	-- only the dust has a price: the value counts the rest as 0 and says so
	X.Record("10940", X.Now(), 100, 100, 50, 5, "Strange Dust", 2)
	local v, _, missing = X.DEValue(tostring(G.green))
	T.near("green armor with only dust priced", v, 375, 0.01)
	T.check("green armor: 2 materials without a price", missing, 2)
	deWorld(X)
	v, parts, missing = X.DEValue(tostring(G.green))
	-- 0.75 x 5 Strange Dust (100c) + 0.15 x 1.5 Lesser Astral (10s) + 0.10 x 1 Small Glimmering Shard (20s)
	T.near("green armor (item level 25)", v, 800, 0.01)
	T.check("green armor: all priced", missing, 0)
	T.check("parts carry the price", parts[3][4], 2000)
	-- weapons: essence and dust swapped
	T.near("green weapon (item level 25)", (X.DEValue(tostring(G.greenW))), 0.15 * 5 * 100 + 0.75 * 1.5 * 1000 + 0.10 * 2000, 0.01)
	T.near("blue armor (item level 40): one Large Glowing Shard", (X.DEValue(tostring(G.blue))), 5000, 0.01)
	T.near("epic armor (item level 60): one Nexus Crystal", (X.DEValue(tostring(G.epic))), 30000, 0.01)
	T.check("common gear: not disenchantable", X.DEValue(tostring(G.white)), nil)
	T.check("item level 3: nothing comes out", X.DEValue(tostring(G.low)), nil)
	T.check("cloth: not disenchantable", X.DEValue("2589"), nil)
	T.check("unknown item: nil", X.DEValue("999999"), nil)
	-- an item the game has not loaded yet: nil now, a value once loaded
	W.items[70007] = {name = "Late Boots", quality = 2, sell = 1, stack = 1, ilvl = 25, class = 4, uncached = true}
	T.check("not loaded yet: nil", X.DEValue("70007"), nil)
	W.advance(2)
	T.near("loaded later: a value", (X.DEValue("70007")), 800, 0.01)
end)

T.scene("analysis: gear under its disenchanting value", function()
	local X = W.start()
	deWorld(X)
	local G = W.DE_GEAR
	local now = X.Now()
	X.Record(tostring(G.green), now, 500, 520, 2, 2, "Ashen Leggings", 2)   -- value 800: under
	X.Record(tostring(G.greenW), now, 1500, 1500, 1, 1, "Ashen Axe", 2)     -- value 1400: over
	X.Record(tostring(G.blue), now, 4000, 4100, 3, 3, "Bright Mantle", 3)   -- value 5000: under
	X.Record(tostring(G.epic), now, 29000, 29000, 1, 1, "Elder Crown", 4)   -- value 30000: within 5%, not shown
	X.Record(tostring(G.white), now, 1, 1, 1, 1, "Plain Shirt", 1)
	local rows = X.UnderDE()
	T.check("two pieces under their value", #rows, 2)
	T.check("best profit first: the blue", rows[1] and rows[1].key, tostring(G.blue))
	T.near("blue: profit = value after the cut - price", rows[1] and rows[1].profit, 5000 * 0.95 - 4000, 0.01)
	T.near("blue: % of value", rows[1] and rows[1].pct, 80, 0.01)
	T.check("blue: listed", rows[1] and rows[1].qty, 3)
	T.near("green: profit", rows[2] and rows[2].profit, 800 * 0.95 - 500, 0.01)
	T.check("green: buy", rows[2] and rows[2].buy, 500)
	T.near("green: value", rows[2] and rows[2].de, 800, 0.01)
	-- old prices are not used
	W.advance(4 * 86400)
	T.check("old prices: none", #X.UnderDE(), 0)
end)

T.scene("analysis: walls and reset chances", function()
	local X = W.start()
	W.openAH()
	-- 5 days of history at 1s a Linen Cloth
	local now = X.Now()
	for d = 1, 5 do X.Record("2589", now - d * 86400, 100, 100, 50, 5, "Linen Cloth", 1) end
	-- now: 3 single ones at 60c (under 80%), a wall of 40 at 85c, 5 more at 120c
	W.listBand(2589, 60, 1, 3, 3, "Cheap")
	W.listBand(2589, 85, 20, 2, 3, "Wall")
	W.listBand(2589, 120, 5, 1, 3, "Dear")
	-- gear with three different prices: no wall
	W.list(15210, 50000, 1, 1, "Cid", -19)
	W.list(15210, 60000, 1, 1, "Dan", -19)
	W.list(15210, 70000, 1, 1, "Eve", -19)
	scanAt(X)
	local s = X.Shape("2589")
	T.ok("Linen: a shape", s ~= nil)
	T.check("wall price", s and s.wall and s.wall.price, 85)
	T.check("wall units", s and s.wall and s.wall.units, 40)
	local usual = X.Usual("2589")
	T.check("reset: units under 80% of the usual price", s and s.reset and s.reset.units, 3)
	T.check("reset: cost", s and s.reset and s.reset.cost, 180)
	T.near("reset: profit when listed again at the usual price", s and s.reset and s.reset.profit, usual * 0.95 * 3 - 180, 1)
	T.ok("reset: time", s and s.t ~= nil)
	local sword = X.Realm().shape["15210:-19"]
	T.ok("sword: no wall, no reset -> not stored", sword == nil or (not sword.wall and not sword.reset), sword)
	-- the lists
	local resets = X.Resets()
	T.check("reset list: Linen", resets[1] and resets[1].key, "2589")
	T.near("reset list: usual", resets[1] and resets[1].usual, usual, 0.01)
	local few = X.FewSellers()
	local found
	for _, r in ipairs(few) do if r.key == "2589" then found = r end end
	T.check("few sellers / walls list: the wall", found and found.wallU, 40)
	-- a reset is only a chance when the item sells: 3 units but known to sell none a day -> no reset
	X.Realm().speed = {["2589"] = X.b36(X.Day()) .. ",0," .. X.b36(600)}
	local list = {{60, 1}, {60, 1}, {60, 1}, {85, 20}}
	T.check("sells nothing: no reset", X.ShapeReset("2589", list), nil)
	X.Realm().speed = {["2589"] = X.b36(X.Day()) .. "," .. X.b36(2) .. "," .. X.b36(1440)} -- 2 a day: 3 units sell within 5 days
	T.check("sells 2 a day: reset of 3 units", X.ShapeReset("2589", list).u, 3)
	-- walls: a lone small listing is no wall; 30% rule
	T.check("one unit: no wall", X.ShapeWall({{100, 1}}), nil)
	T.check("spread out: no wall", X.ShapeWall({{100, 2}, {101, 2}, {102, 2}, {103, 2}, {104, 2}}), nil)
	T.check("a big stack above 1.5 x the lowest is not looked at", X.ShapeWall({{10, 1}, {11, 1}, {20, 100}}), nil)
	-- the next scan without the cheap ones: the reset is gone, the wall stays; 4 days later old entries are pruned
	W.advance(3600)
	W.buyOut(2589, 3, 3)
	scanAt(X)
	s = X.Shape("2589")
	T.check("cheap ones bought: no reset", s and s.reset, nil)
	T.check("the wall stays", s and s.wall and s.wall.units, 40)
	W.advance(4 * 86400)
	W.ah = {}
	W.list(2592, 80, 1, 1, "Fay")
	scanAt(X)
	T.check("old entries pruned", X.Realm().shape["2589"], nil)
end)

T.scene("analysis: sellers from a search", function()
	local X = W.start()
	W.openAH()
	-- Wool Cloth: one seller with 20 at 80c, two with 5 each at 90c
	W.list(2592, 80, 10, 1, "Big")
	W.list(2592, 80, 10, 1, "Big")
	W.list(2592, 90, 5, 2, "Small")
	W.list(15210, 50000, 1, 2, "Cid", -19)
	W.list(15210, 60000, 1, 1, "Dan", -19)
	T.check("search", X.ScanItems({"2592", "15210:-19"}, "test"), true)
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	local s = X.Shape("2592")
	T.check("Wool: 3 sellers", s and s.sellers, 3)
	T.near("Wool: the top seller holds 20 of 30", s and s.topShare, 0.667, 0.001)
	local g = X.Shape("15210:-19")
	T.check("sword: 3 sellers", g and g.sellers, 3)
	T.near("sword: top seller share", g and g.topShare, 0.333, 0.001)
	-- rows that name only some of their sellers: the others still count
	W.ownerCap = 1
	X.ScanItems({"2592"}, "test")
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	T.check("names cut short: still 3 sellers", X.Shape("2592").sellers, 3)
	-- sold out: the seller count goes
	W.buyOut(2592, 10)
	X.ScanItems({"2592"}, "test")
	W.waitFor(function() return X.scan.state == "idle" end, 30)
	W.advance(1)
	local e = X.Realm().shape["2592"]
	T.check("sold out: sellers gone", e and e.sellers, nil)
	-- the few sellers list
	local few = X.FewSellers()
	local sword
	for _, r in ipairs(few) do if r.key == "15210:-19" then sword = r end end
	T.check("few sellers list: the sword", sword and sword.sellers, 3)
end)

T.scene("analysis: Deals and Trends views render", function()
	local X = W.start()
	W.openAH()
	deWorld(X)
	local G = W.DE_GEAR
	X.Record(tostring(G.blue), X.Now(), 4000, 4100, 3, 3, "Bright Mantle", 3)
	local now = X.Now()
	for d = 1, 5 do X.Record("2589", now - d * 86400, 100, 100, 50, 5, "Linen Cloth", 1) end
	W.listBand(2589, 60, 1, 3, 3, "Cheap")
	W.listBand(2589, 85, 20, 2, 3, "Wall")
	W.listBand(2589, 70, 10, 2, 3, "Mid")
	W.listBand(2592, 80, 10, 3, 3, "Wool")
	W.list(G.blue, 4000, 1, 3, "Gear")
	scanAt(X)
	W.advance(3600)
	W.buyOut(2592, 1, 3)
	W.buyOut(2589, 1, 3)
	scanAt(X)
	W.env.SlashCmdList.XNAH("")
	local frame = X.UI.Frame()
	X.UI.Open("deals")
	W.advance(0.5)
	local panel = X.UI.tabs.deals.panel
	T.ok("deals: sells/day column", W.screen(panel):find("Sells/day", 1, true) ~= nil)
	W.click("Under disenchant value", panel)
	W.advance(0.5)
	local text = W.screen(panel)
	T.ok("disenchant view: the blue is listed", text:find("Bright Mantle", 1, true) ~= nil, text)
	T.ok("disenchant view: says who it is for", text:find("you or a friend can disenchant", 1, true) ~= nil)
	W.click("Reset chances", panel)
	W.advance(0.5)
	text = W.screen(panel)
	T.ok("reset view: Linen", text:find("Linen Cloth", 1, true) ~= nil, text)
	T.ok("reset view: columns", text:find("Units to buy", 1, true) ~= nil and text:find("Sells per day", 1, true) ~= nil)
	-- the speed filter: on with a high minimum hides Wool (known speed), keeps items without a known speed
	W.click("Under usual price", panel)
	W.advance(0.3)
	X.S().dealSpeedMin = 100000
	W.click("Hide items that sell under", panel)
	W.advance(0.3)
	T.check("filter switched on", X.S().dealSpeedHide, true)
	W.click("Hide items that sell under", panel)
	W.advance(0.3)
	T.check("filter switched off", X.S().dealSpeedHide, false)
	-- Trends
	X.UI.Open("trends")
	W.advance(0.5)
	panel = X.UI.tabs.trends.panel
	T.ok("trends: the four lists still there", W.screen(panel):find("Rising prices", 1, true) ~= nil)
	W.click("Best time to post", panel)
	W.advance(0.5)
	text = W.screen(panel)
	T.ok("best time view: hours", text:find("23", 1, true) ~= nil and text:find("Most sales", 1, true) ~= nil, text)
	W.click("Few sellers / walls", panel)
	W.advance(0.5)
	text = W.screen(panel)
	T.ok("few sellers view: Linen with its wall", text:find("Linen Cloth", 1, true) ~= nil, text)
	T.ok("few sellers view: columns", text:find("Top seller share", 1, true) ~= nil and text:find("Wall units", 1, true) ~= nil)
	-- an empty start: every view says something
	X = W.start()
	W.env.SlashCmdList.XNAH("")
	for _, tab in ipairs({"deals", "trends"}) do
		X.UI.Open(tab)
		W.advance(0.3)
		local p = X.UI.tabs[tab].panel
		local names = tab == "deals" and {"Under disenchant value", "Reset chances"} or {"Best time to post", "Few sellers / walls"}
		for _, n in ipairs(names) do
			W.click(n, p)
			W.advance(0.3)
			T.ok(tab .. " / " .. n .. ": empty text", W.screen(p) ~= "")
		end
	end
	T.ok("window", frame ~= nil)
end)

T.scene("analysis: scale - two full scans of 30,000 auctions compared in slices", function()
	local X = W.start()
	W.makeMarket(99, 1850, {uncached = 0})
	W.openAH()
	T.ok("first scan", T.fullScan(X))
	W.advance(2)
	W.advance(3600)
	-- the next hour: a new day's listings (most of the earlier ones gone, many with a long time left: lots of "sales")
	W.marketDay(1)
	T.ok("second scan", T.fullScan(X))
	W.maxStepTime = 0
	local ticks, c0 = W.ticks, os.clock()
	W.advance(5)
	T.ok("compared", X.speedInfo ~= nil and X.speedInfo.items > 1000, X.speedInfo and X.speedInfo.items)
	local n = 0
	for _ in pairs(X.Realm().shape or {}) do n = n + 1 end
	T.note(string.format("analysis scale: %d auctions, %d items compared, %d units seen sold, %d shape entries; %.1f s here, slowest step %.0f ms here (fengari)",
		#W.ah, X.speedInfo.items, X.speedInfo.units, n, os.clock() - c0, W.maxStepTime * 1000))
	T.ok("no step slower than 400 ms here", W.maxStepTime < 0.4, W.maxStepTime)
end)
