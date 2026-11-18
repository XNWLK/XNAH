-- XNAH test scenes, part 2e: the realm key. On Forever GetRealmName() is the server shard (it changes from login to
-- login); GetRealmID() is the realm. Data saved under shard names moves into "Realm <id>-<faction>".

table.insert(W.onEnv, function(env)
	env.GetRealmID = function() return W.realmID end
end)
table.insert(W.onReset, function() W.realmID = nil end)

T.scene("realm: data under shard names joins the realm key", function()
	local X = W.start()
	W.realm = "CAMWOW EU5 Realm 4 PvP"
	X = W.reload()
	local oldKey = X.RealmKey()
	T.check("without a realm ID the shard name is used", oldKey, "CAMWOW EU5 Realm 4 PvP-Horde")
	X.realmKey = oldKey
	X.Record("2589", X.Now() - 100, 40, 45, 100, 5, "Linen Cloth", 1)
	X.db.chars["Xn Ascalon"] = {realm = oldKey, money = 5, bags = {}, bank = {}, mail = {}, auctions = {}, bound = {}}
	-- another shard, a newer price of the same item and one more item
	local other = "CAMWOW EU4 Realm 6 PvP-Horde"
	X.realmKey = other
	X.Record("2589", X.Now(), 50, 52, 80, 4, "Linen Cloth", 1)
	X.Record("2770", X.Now(), 12, 13, 40, 2, "Copper Ore", 1)
	X.db.realms["CAMWOW EU5 Realm 4 PvP-Alliance"] = {items = {["1"] = {id = 1}}, scans = {}}
	-- next login: the game gives the realm ID
	W.realmID = 93
	X = W.reload()
	T.check("the key is now the realm", X.realmKey, "Realm 93-Horde")
	local r = X.db.realms["Realm 93-Horde"]
	T.ok("the realm has the data", r ~= nil)
	T.check("newest price kept", r and r.items["2589"].cur.min, 50)
	T.check("the other shard's item came along", r and r.items["2770"] and r.items["2770"].cur.min, 12)
	T.check("shard keys of this faction are gone", X.db.realms["CAMWOW EU5 Realm 4 PvP-Horde"], nil)
	T.ok("the other faction stays apart", X.db.realms["CAMWOW EU5 Realm 4 PvP-Alliance"] ~= nil)
	T.check("the character moved along", X.db.chars["Xn Ascalon"].realm, "Realm 93-Horde")
	W.advance(9)
	T.ok("Xn is told", #W.said("joined under Realm 93-Horde") > 0)
	-- once moved, nothing more happens
	X = W.reload()
	T.check("second login: nothing to move", X.MigrateRealms(X.realmKey), 0)
end)
