-- XNAH test scenes, part 2d: characters of other WoW accounts (brought in by tools/sync-accounts.js) on the Wealth page.

T.scene("accounts: characters of other accounts show with their account name", function()
	local X = W.start()
	local rk = X.RealmKey()
	-- what the sync tool writes into this account's data
	X.db.chars["Stressy Testyye"] = {realm = rk, money = 1234567, at = X.Now() - 3600, acct = "wow1",
		bags = {["2589"] = 40}, bank = {}, mail = {}, auctions = {}, bound = {}}
	X.db.sync = {at = X.Now() - 600, label = "ASCFIGHTER", accounts = {"ASCFIGHTER", "wow1", "wow2"}}
	local found
	for _, c in ipairs(X.Chars()) do if c.name == "Stressy Testyye" then found = c end end
	T.ok("the other account's character is listed", found ~= nil)
	T.check("with its account", found and found.acct, "wow1")
	T.check("its gold", found and found.gold, 1234567)
	-- this account's own character never carries an account name
	local me = X.InventoryMe()
	me.acct = "wow2"
	X.InventoryMe()
	T.check("own character: no account name", X.db.chars[X.CharKey()].acct, nil)
	X.UI.Open("wealth")
	W.advance(1)
	local s = W.screen(W.env.UIParent)
	local text = type(s) == "table" and table.concat(s, "\n") or tostring(s)
	T.ok("the page shows the account name", text:find("(wow1)", 1, true) ~= nil)
	T.ok("the page says when accounts were joined", text:find("Other accounts joined", 1, true) ~= nil)
end)
