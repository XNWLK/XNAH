-- XNAH test scenes, part 26: hourly web data (XNAH/Api.lua). The PC tool (tools/api-fetch.js) writes XNAH_API into the
-- companion addon XNAH_Data; here a file like it is loaded with the saved data at login. Snapshots are recorded once,
-- an older snapshot never replaces a newer price, data of another faction or realm is never used.

local function b36(n)
	if n == nil then return "" end
	n = math.floor(n + 0.5)
	if n == 0 then return "0" end
	local neg = n < 0
	if neg then n = -n end
	local digits, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
	while n > 0 do
		local r = n % 36
		out = digits:sub(r + 1, r + 1) .. out
		n = (n - r) / 36
	end
	return (neg and "-" or "") .. out
end
-- items = {{key, min, mkt, qty, auc}, ...}; filler = that many more items (ids 30001 ...)
local function snap(t, items, filler)
	local parts = {}
	for i, e in ipairs(items) do parts[i] = e[1] .. "," .. b36(e[2]) .. "," .. b36(e[3]) .. "," .. b36(e[4]) .. "," .. b36(e[5]) end
	for i = 1, filler or 0 do parts[#parts + 1] = (30000 + i) .. "," .. b36(100 + i) .. "," .. b36(110 + i) .. ",a,2" end
	return {t = t, n = #parts, auctions = #parts * 3, text = table.concat(parts, ";")}
end
-- the text of XNAH_Data's Data.lua
local function dataFile(snaps, faction, realm)
	local out = {"XNAH_API = {", "v = 1, made = " .. W.START .. ", house = 111, region = \"eu\",",
		"faction = \"" .. (faction or "Alliance") .. "\", realm = \"" .. (realm or "") .. "\",", "snapshots = {"}
	for _, s in ipairs(snaps) do
		out[#out + 1] = "{t = " .. s.t .. ", n = " .. s.n .. ", auctions = " .. s.auctions .. ", items = \"" .. s.text .. "\"},"
	end
	out[#out + 1] = "}}"
	return table.concat(out, "\n")
end
-- login (or relog) with the saved data so far plus a data file
local function login(data)
	local saved = W.env and W.saveText(W.env.XNAHDB) or ""
	return W.login(saved .. "\n" .. data)
end
local function imported(X)
	return W.waitFor(function() return X.api.state ~= "waiting" and X.api.state ~= "importing" end, 60)
end
local function points(X, key)
	local it = X.Items()[key]
	return it and #X.UnpackPoints(it.h) or 0
end
local function skip(X)
	if X.ApiImport then return false end
	T.note("web data scenes skipped: Api.lua is not in XNAH.toc yet")
	return true
end

local H = 3600
local T1, T2, T3 = W.START - 3 * H, W.START - 2 * H, W.START - H
local S1 = snap(T1, {{"2589", 50, 55, 100, 5}, {"2592", 120, 130, 40, 4}, {"15210:-19", 42000, 42000, 1, 1}, {"4071", 90000, 92000, 2, 2}}, 60)
local S2 = snap(T2, {{"2589", 52, 56, 90, 5}, {"2592", 118, 128, 44, 4}, {"15210:-19", 41000, 41000, 1, 1}}, 60)
local S3 = snap(T3, {{"2589", 54, 57, 95, 6}, {"2592", 119, 129, 41, 4}, {"7524", nil, nil, 1, 0}}, 60)

T.scene("web data: snapshots recorded once, at login", function()
	W.reset()
	W.faction = "Alliance"
	local X = login(dataFile({S1, S2}))
	if skip(X) then return end
	T.check("waits a moment after login", X.api.state, "waiting")
	T.ok("imported", imported(X))
	local it = X.Items()["2589"]
	T.check("price of the newest snapshot", it.cur.min, 52)
	T.check("market value", it.cur.mkt, 56)
	T.check("time of the snapshot, not of the login", it.cur.t, T2)
	T.check("marked as hourly web data", it.cur.web, 1)
	T.check("one point per snapshot", points(X, "2589"), 2)
	T.check("random-bonus key", X.Items()["15210:-19"].cur.min, 41000)
	T.check("filler items too", X.Items()["30060"] ~= nil, true)
	T.check("last imported time kept per realm", X.Realm().apiLast, T2)
	local scans = X.Realm().scans
	T.check("listed with the scans", scans[#scans].kind, "web data")
	T.ok("the data is freed after the import", W.env.XNAH_API == nil)
	T.ok("status: 2 new", X.ApiStatus():find("2 new at this login", 1, true), X.ApiStatus())
	-- 4071 was in the older snapshot only: sold out in the newest one
	T.check("missing from the newest snapshot = sold out", X.Items()["4071"].cur.qty, 0)

	-- relog with the same file: nothing is recorded twice
	X = login(dataFile({S1, S2}))
	T.ok("imported again", imported(X))
	T.check("no new points", points(X, "2589"), 2)
	T.ok("status: nothing new", X.ApiStatus():find("nothing new", 1, true), X.ApiStatus())

	-- an hour later the tool wrote one more snapshot: only that one is new
	X = login(dataFile({S1, S2, S3}))
	T.ok("imported the new one", imported(X))
	T.check("one more point", points(X, "2589"), 3)
	T.check("newest price", X.Items()["2589"].cur.min, 54)
	T.check("an item with bids only: listed, no price", X.Items()["7524"].cur.qty, 1)
	T.check("status: 1 new", X.ApiStatus():find("1 new at this login", 1, true) ~= nil, true)
end)

T.scene("web data: an older snapshot never replaces a newer price", function()
	W.reset()
	W.faction = "Alliance"
	local X = W.login()
	if skip(X) then return end
	-- the auction house was scanned in game after the snapshots were made
	X.Record("2592", W.START - 60, 999, 1000, 7, 1, "Wool Cloth", 1)
	X = login(dataFile({S1, S2}))
	T.ok("imported", imported(X))
	local it = X.Items()["2592"]
	T.check("the game's newer price stays", it.cur.min, 999)
	T.check("not marked as web data", it.cur.web, nil)
	T.check("no older points added", points(X, "2592"), 1)
	T.check("other items are recorded", X.Items()["2589"].cur.min, 52)
end)

T.scene("web data: another faction or realm is not used", function()
	W.reset() -- a Horde character
	local X = login(dataFile({S1, S2}, "Alliance"))
	if skip(X) then return end
	T.ok("done", imported(X))
	T.check("nothing recorded", X.Items()["2589"], nil)
	T.check("state", X.api.state, "wrong")
	T.ok("status says why", X.ApiStatus():find("Alliance", 1, true), X.ApiStatus())

	W.reset()
	W.faction = "Alliance"
	X = login(dataFile({S1, S2}, "Alliance", "Realm 6946-Alliance"))
	T.ok("done", imported(X))
	T.check("another realm: nothing recorded", X.Items()["2589"], nil)
	T.ok("status names the realm", X.ApiStatus():find("Realm 6946", 1, true), X.ApiStatus())

	W.reset()
	W.faction = "Alliance"
	X = login(dataFile({S1, S2}, "Alliance", X.RealmKey()))
	T.ok("done", imported(X))
	T.check("this realm: recorded", X.Items()["2589"].cur.min, 52)
end)

T.scene("web data: status without the companion folder, a big snapshot in slices", function()
	local X = W.start()
	if skip(X) then return end
	T.ok("not set up", X.ApiStatus():find("not set up", 1, true), X.ApiStatus())

	W.reset()
	W.faction = "Alliance"
	local big = snap(W.START - 10 * 60, {}, 5000)
	X = login(dataFile({big}))
	W.advance(3.2)
	T.check("recording takes several frames", X.api.state, "importing")
	T.ok("status while recording", X.ApiStatus():find("recording snapshot 1 of 1", 1, true), X.ApiStatus())
	T.ok("finished", imported(X))
	T.check("all items", X.Items()["35000"].cur.min, 5100)
	T.ok("status: fresh, no warning", not X.ApiStatus():find("running", 1, true), X.ApiStatus())
	-- six hours later without new data: the tool may have stopped
	W.advance(6 * 3600)
	T.ok("status: old data", X.ApiStatus():find("is the PC tool running", 1, true), X.ApiStatus())
end)
