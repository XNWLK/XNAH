-- XNAH test scenes, part 2e: the realm key. On Forever GetRealmName() is the server shard (it changes from login to
-- login); GetRealmID() is the realm. Alliance and Horde share one auction house (Xn, 2026-11-21), so the key is just
-- "Realm <id>". Data saved under shard names or per faction ("Realm <id>-Alliance", up to v0.7.1) joins it.

table.insert(W.onEnv, function(env)
	env.GetRealmID = function() return W.realmID end
end)
table.insert(W.onReset, function() W.realmID = nil end)

T.scene("realm: shard names and both factions join one realm key", function()
	local X = W.start()
	W.realm = "CAMWOW EU5 Realm 4 PvP"
	X = W.reload()
	local shardKey = X.RealmKey()
	T.check("without a realm ID the shard name is used", shardKey, "CAMWOW EU5 Realm 4 PvP")
	-- old data: a shard key (v0.3.0), and per faction keys (up to v0.7.1)
	X.realmKey = "CAMWOW EU5 Realm 4 PvP-Horde"
	X.Record("2589", X.Now() - 100, 40, 45, 100, 5, "Linen Cloth", 1)
	X.realmKey = "Realm 93-Alliance"
	X.Record("2589", X.Now(), 50, 52, 80, 4, "Linen Cloth", 1)
	X.Record("2770", X.Now(), 12, 13, 40, 2, "Copper Ore", 1)
	X.db.realms["Realm 93-Alliance"].ledger = {sales = {{t = X.Now() - 50, key = "2589", count = 5, money = 250}}}
	X.db.realms["Realm 93-Alliance"].ahTime = {[X.Day()] = 600}
	X.realmKey = "Realm 93-Horde"
	X.Record("2592", X.Now() - 10, 30, 31, 60, 3, "Wool Cloth", 1)
	X.db.realms["Realm 93-Horde"].ledger = {sales = {{t = X.Now() - 70, key = "2592", count = 2, money = 60}}}
	X.db.realms["Realm 93-Horde"].ahTime = {[X.Day()] = 300}
	X.db.chars["Ann Lee"] = {realm = "Realm 93-Alliance", money = 5, bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
	X.db.chars["Bob Stone"] = {realm = "Realm 93-Horde", money = 7, bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
	X.db.chars["Cid Moss"] = {realm = "CAMWOW EU5 Realm 4 PvP-Horde", money = 1, bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
	-- another realm stays apart
	X.db.realms["Realm 77-Alliance"] = {items = {["1"] = {id = 1}}, scans = {}}
	-- next login: the game gives the realm ID
	W.realmID = 93
	X = W.reload()
	T.check("the key is the realm, no faction", X.realmKey, "Realm 93")
	local r = X.db.realms["Realm 93"]
	T.ok("the realm has the data", r ~= nil)
	T.check("newest price kept", r and r.items["2589"].cur.min, 50)
	T.ok("the Alliance item came along", r and r.items["2770"] ~= nil)
	T.ok("the Horde item came along", r and r.items["2592"] ~= nil)
	T.check("both factions' sales", r and r.ledger and #r.ledger.sales, 2)
	T.ok("sales in time order", r and r.ledger.sales[1].t < r.ledger.sales[2].t)
	T.check("auction house time added up", r and r.ahTime[X.Day()], 900)
	T.check("faction keys gone (Alliance)", X.db.realms["Realm 93-Alliance"], nil)
	T.check("faction keys gone (Horde)", X.db.realms["Realm 93-Horde"], nil)
	T.check("shard key gone", X.db.realms["CAMWOW EU5 Realm 4 PvP-Horde"], nil)
	T.ok("another realm stays apart", X.db.realms["Realm 77-Alliance"] ~= nil)
	T.check("Alliance character moved", X.db.chars["Ann Lee"].realm, "Realm 93")
	T.check("Horde character moved", X.db.chars["Bob Stone"].realm, "Realm 93")
	T.check("shard character moved", X.db.chars["Cid Moss"].realm, "Realm 93")
	W.advance(9)
	T.ok("Xn is told", #W.said("Alliance and Horde share one auction house") > 0)
	-- once moved, nothing more happens
	X = W.reload()
	T.check("second login: nothing to move", X.MigrateRealms(X.realmKey), 0)
end)
