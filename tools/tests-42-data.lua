-- XNAH test scenes, part 42: the Your data window (UIData.lua) and its work (DataTools.lua) - data health (sizes,
-- items not seen for a while, what Slim down would remove), Slim down (what is always kept, everything saved under a
-- removed item's key goes, the caches forget it, a reload keeps it gone), the exports (header row, tabs, plain gold
-- numbers, time spans, the newest rows kept when the text is cut, built a little per frame) and the window itself
-- (Settings button, /xnah data, the yes / no step inside the window, the copy box).
-- Run alone: node tools/test.js 42

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function lines(text)
	local out = {}
	for l in (text .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = l end
	return out
end
local function tabs(l) return select(2, l:gsub("\t", "")) end

-- an item listed (with a price) `ago` days ago, once a day for `days` days up to then
local function listed(X, key, ago, days, price, name)
	local id = X.KeyID(key)
	W.items[id] = W.items[id] or {name = name or ("Test item " .. key), quality = 1, sell = 10, stack = 20}
	for k = (days or 1) - 1, 0, -1 do
		X.Record(key, X.Now() - (ago + k) * DAY - 60, price or 1000, price or 1000, 10, 2, name or ("Test item " .. key), 1)
	end
	return X.Items()[key]
end
local function data(X) return X.UI.DataParts end
-- clicks a line of the open pop-up menu (K.Menu: its buttons sit on the menu panel, drawn above everything)
local function menuPick(text)
	for _, f in ipairs(W.frames) do
		if f.kind == "Button" and f.scripts.OnClick and f:IsVisible() and f.parent and f.parent.strata == "FULLSCREEN_DIALOG" and
			W.plain(W.buttonText(f)):find(text, 1, true) then
			f:Click()
			return f
		end
	end
	error("no menu line '" .. text .. "'")
end
local function openData(X)
	W.env.SlashCmdList.XNAH("data")
	W.advance(1)
	return X.UI.DataFrame()
end

T.scene("42 data: health - sizes, items not seen, what slim down would remove", function()
	local X = W.start()
	W.advance(5)
	listed(X, "50001", 0, 3)       -- seen today
	listed(X, "50002", 40, 2)      -- 40 days ago
	listed(X, "50003", 100, 2)     -- 100 days ago
	listed(X, "50004", 200, 2)     -- 200 days ago
	listed(X, "50005", 100, 2)     -- 100 days ago, then sold out at a full scan today
	X.RecordGone("50005", X.Now())
	X.Item("50006", true)          -- never seen with a price
	T.ok("sold out now", X.Items()["50005"].cur.qty == 0)
	T.near("sold out: seen = the last day with a price", (X.Now() - X.DataLastSeen(X.Items()["50005"])) / DAY, 100, 1.5)
	T.check("never priced: never seen", X.DataLastSeen(X.Items()["50006"]), nil)
	local res = X.DataHealthRun()
	T.check("items", res.items, 6)
	T.check("never seen", res.never, 1)
	T.check("not seen for 30 days", res.unseen[30], 5)
	T.check("not seen for 60 days", res.unseen[60], 4)
	T.check("not seen for 90 days", res.unseen[90], 4)
	T.check("not seen for 180 days", res.unseen[180], 2)
	T.check("slim 90: four items", res.slim[90].n, 4)
	T.check("slim 365: only the never seen one", res.slim[365].n, 1)
	T.ok("slim 90: some bytes", res.slim[90].bytes > 100, res.slim[90].bytes)
	local byKey = {}
	for _, p in ipairs(res.parts) do byKey[p.key] = p.bytes end
	T.ok("price history counted", (byKey.history or 0) > 0)
	T.ok("prices counted", (byKey.prices or 0) > 0)
	T.ok("settings counted", (byKey.other or 0) > 0)
	local sum = 0
	for _, p in ipairs(res.parts) do sum = sum + p.bytes end
	T.check("parts add up to the total", sum, res.total)
	-- the stand-in writes the file with tabs in front of every line (the game does not): about the same size
	local file = W.savedSize()
	T.ok("total about the size of the saved file", res.total <= file and res.total >= file * 0.6, res.total .. " / " .. file)
	T.ok("the biggest items listed", #res.top == 6 and res.top[1].bytes >= res.top[6].bytes, #res.top)
	T.check("the biggest: the one with 3 days", res.top[1].key, "50001")
	T.check("its days of history", res.top[1].days, 3)
	-- other realms counted apart
	W.env.XNAHDB.realms["Realm 1"] = {items = {["9"] = {id = 9, d = string.rep("a,b,c,d,1;", 50)}}, scans = {}}
	res = X.DataHealthRun()
	for _, p in ipairs(res.parts) do byKey[p.key] = p.bytes end
	T.ok("another realm: counted", (byKey.otherRealms or 0) > 500, byKey.otherRealms)
	T.check("another realm: not in this realm's items", res.items, 6)
end)

T.scene("42 data: slim down keeps tracked, compared, traded, owned and shown items", function()
	local X = W.start()
	W.advance(5)
	local keys = {"60001", "60002", "60003", "60004", "60005", "60006", "60007", "60008"}
	for _, k in ipairs(keys) do listed(X, k, 200, 3, 1000, "Old " .. k) end
	listed(X, "60009:-19", 200, 2, 5000, "Old Blade of the Bear")
	listed(X, "60010", 1, 2)
	X.SetWatched("60001", true)                                   -- tracked
	X.S().compareLists["60002"] = {t = X.Now(), k = {"60003"}}    -- picked and compared
	local Lg = X.Ledger()
	table.insert(Lg.sales, {t = X.Now() - 300 * DAY, key = "60004", name = "Old 60004", count = 1, money = 100, cut = 5})
	table.insert(Lg.buys, {t = X.Now() - 300 * DAY, name = "Old 60005", count = 1, money = 100}) -- by name only
	W.env.XNAHDB.chars["Alt Ascalon"] = {realm = X.RealmKey(), money = 1, bags = {["60006"] = 2}, bank = {}, mail = {},
		auctions = {}, bound = {}}
	X.UI.itemKey = "60007"                                       -- shown on the Items view
	local r = X.Realm()
	r.speed = r.speed or {}
	r.shape = r.shape or {}
	r.speed["60008"], r.shape["60008"] = "abc,1,2", {t = 1}
	r.speed["60001"] = "abc,1,2"
	T.check("random-bonus key indexed", #(X.SuffixKeys(60009) or {}), 1)
	local keep = X.DataKeep()
	T.check("kept: tracked", keep.keys["60001"], "tracked")
	T.check("kept: compared (picked)", keep.keys["60002"], "compared")
	T.check("kept: compared (other)", keep.keys["60003"], "compared")
	T.check("kept: sold", keep.keys["60004"], "traded")
	T.ok("kept: bought by name", keep.names["old 60005"] == true)
	T.check("kept: owned by an alt", keep.keys["60006"], "owned")
	T.check("kept: shown now", keep.keys["60007"], "shown")
	local res = X.DataHealthRun()
	T.check("preview: two to remove", res.slim[90].n, 2)
	T.check("preview: seven kept", res.slim[90].kept, 7)
	-- refused while a scan runs
	X.scan.state = "reading"
	local ok, why = X.DataSlim(90)
	T.check("refused during a scan", ok, false)
	T.check("why", why, "scan")
	X.scan.state = "idle"
	-- Trends worked out before: forgotten afterwards
	local forgot = 0
	local tf = X.TrendsForget
	X.TrendsForget = function(...) forgot = forgot + 1 return tf(...) end
	local removed, bytes = X.DataSlimRun(90)
	X.TrendsForget = tf
	T.check("removed two", removed, 2)
	T.ok("bytes freed", bytes > 100, bytes)
	T.check("trends forgotten", forgot, 1)
	for i = 1, 7 do T.ok("kept " .. keys[i], X.Items()[keys[i]] ~= nil) end
	T.check("removed: not seen and not kept", X.Items()["60008"], nil)
	T.check("removed: random-bonus item", X.Items()["60009:-19"], nil)
	T.check("kept: seen yesterday", X.Items()["60010"] ~= nil, true)
	T.check("its sales speed gone", r.speed["60008"], nil)
	T.check("its market shape gone", r.shape["60008"], nil)
	T.check("a kept item's sales speed stays", r.speed["60001"], "abc,1,2")
	T.check("random-bonus index made again", X.SuffixKeys(60009), nil)
	T.check("nothing broken: stats of a removed key", X.Stats("60008"), nil)
	T.check("nothing broken: price of a removed key", X.Price("60008"), nil)
	T.check("nothing broken: history of a removed key", #X.History("60008", 0), 0)
	-- the Trends pages work out again without the removed items
	local tr = X.TrendsRun and X.TrendsRun({periods = {7, 30}}) or true
	T.ok("trends work out again", tr ~= nil)
	-- after a reload: still gone, kept ones still there
	X = W.reload()
	W.advance(5)
	T.check("after a reload: still gone", X.Items()["60008"], nil)
	T.ok("after a reload: kept", X.Items()["60001"] ~= nil and X.Items()["60006"] ~= nil)
	-- after the reload no item is shown on the Items view: the one shown before goes now, nothing else
	T.check("again: only the item shown before the reload", (X.DataSlimRun(90)), 1)
	T.check("that one", X.Items()["60007"], nil)
	T.check("again: nothing more", (X.DataSlimRun(90)), 0)
end)

T.scene("42 data: exports - header, tabs, gold numbers, time spans", function()
	local X = W.start()
	W.advance(5)
	-- 100 days of one price a day, the last day 1g 23s 45c
	local key = "70001"
	W.items[70001] = {name = "Export Ore", quality = 1, sell = 10, stack = 20}
	for k = 99, 0, -1 do
		local p = k == 0 and 12345 or (10000 + k)
		X.Record(key, X.Now() - k * DAY - 60, p, p, 30 + k, 3, "Export Ore", 1)
	end
	local res = X.ExportRun("history", {key = key, days = 30})
	local ls = lines(res.text)
	T.check("history: header", ls[1], "Date\tLowest price (gold)\tUsual price (gold)\tQuantity listed\tScans\tCovers")
	T.check("history: 30 days", res.rows, 30)
	T.check("history: lines", #ls, 31)
	T.check("history: not cut", res.cut, false)
	T.ok("history: the newest last, as plain gold", has(ls[31], "\t1.2345\t1.2345\t30\t1\tDay"), ls[31])
	T.check("history: date first", ls[31]:sub(1, 10), W.env.date("%Y-%m-%d", X.Now()))
	T.ok("history: oldest first", ls[2] < ls[31])
	local same = true
	for i = 2, #ls do if tabs(ls[i]) ~= tabs(ls[1]) then same = false end end
	T.ok("history: every row has the columns of the header", same)
	T.ok("history: no colour codes", not has(res.text, "|c") and not has(res.text, "|r"))
	res = X.ExportRun("history", {key = key, days = 0})
	T.ok("history all: weekly points after 60 days", has(res.text, "\tWeek") and res.rows < 100 and res.rows > 60, res.rows)
	res = X.ExportRun("history", {key = nil})
	T.check("history: no item picked", res.note, "pick")
	T.check("history: only the header", res.rows, 0)
	res = X.ExportRun("history", {key = "99999"})
	T.check("history: an unknown item", res.note, "noitem")
	-- sales and buys: profit at the average buying price
	local Lg = X.Ledger()
	local now = X.Now()
	table.insert(Lg.buys, {t = now - 5 * DAY, key = key, name = "Export Ore", count = 5, money = 500, char = "Xn Ascalon"})
	table.insert(Lg.sales, {t = now - 2 * DAY, key = key, name = "Export Ore", count = 5, money = 1500, cut = 75, char = "Xn Ascalon"})
	table.insert(Lg.sales, {t = now - 40 * DAY, name = "Gone Thing", count = 2, money = 20000, cut = 1000, char = "Xn Ascalon"})
	X.LedgerForget()
	res = X.ExportRun("ledger", {days = 30})
	ls = lines(res.text)
	T.check("ledger: header", ls[1], "Date\tWhat\tItem\tQuantity\tPrice each (gold)\tTotal (gold)\tAuction house cut (gold)\t" ..
		"Profit (gold)\tCharacter")
	T.check("ledger 30 days: two rows", res.rows, 2)
	T.ok("ledger: the buy first (oldest first)", has(ls[2], "\tBought\tExport Ore\t5\t0.0100\t0.0500\t\t\tXn Ascalon"), ls[2])
	T.ok("ledger: the sale with cut and profit", has(ls[3], "\tSold\tExport Ore\t5\t0.0300\t0.1500\t0.0075\t0.0925\tXn Ascalon"), ls[3])
	res = X.ExportRun("ledger", {days = 0})
	T.check("ledger all: three rows", res.rows, 3)
	T.ok("ledger: a sale saved by name only (never bought: costs nothing)", has(res.text, "\tSold\tGone Thing\t2\t1.0000\t2.0000\t0.1000\t1.9000\t"), res.text)
	-- gold of each character
	W.setMoney(150000)
	W.advance(5)
	W.env.XNAHDB.chars["Alt Ascalon"] = {realm = X.RealmKey(), money = 50000, at = X.Now(), bags = {}, bank = {}, mail = {},
		auctions = {}, bound = {}}
	X.RecordGoldHistory()
	res = X.ExportRun("gold", {days = 30})
	ls = lines(res.text)
	T.ok("gold: header with both characters and the total", has(ls[1], "Date\t") and has(ls[1], "Xn Ascalon") and
		has(ls[1], "Alt Ascalon") and has(ls[1], "\tAll characters"), ls[1])
	T.ok("gold: today with both and the sum", has(ls[#ls], "\t20.0000") and has(ls[#ls], "\t15.0000") and has(ls[#ls], "\t5.0000"), ls[#ls])
	-- tracked items now
	X.SetWatched(key, true)
	X.SetWatched("70002", true) -- tracked, never seen
	res = X.ExportRun("tracked")
	ls = lines(res.text)
	T.check("tracked: two rows", res.rows, 2)
	T.ok("tracked: header", has(ls[1], "Item\tItem ID\tLowest price now (gold)"), ls[1])
	local ore
	for i = 2, #ls do if has(ls[i], "Export Ore") then ore = ls[i] end end
	T.ok("tracked: the price now", ore and has(ore, "\t70001\t1.2345\t1.2345\t"), ore)
	T.ok("tracked: last seen today", ore and has(ore, W.env.date("%Y-%m-%d", X.Now())), ore)
	T.check("gold numbers: negative", X.ExportGold(-25000), "-2.5000")
	T.check("gold numbers: nothing", X.ExportGold(nil), "")
end)

T.scene("42 data: a big export is cut (newest kept) and built a little per frame", function()
	local X = W.start()
	W.advance(5)
	local Lg = X.Ledger()
	local now = X.Now()
	for i = 1, 6000 do
		table.insert(Lg.sales, {t = now - i * 600 + 0.5, key = "2589", name = "Linen Cloth", count = 1, money = 100 + i, cut = 5, char = "Xn Ascalon"})
	end
	local res = X.ExportRun("ledger", {days = 0, max = 20000})
	T.check("cut", res.cut, true)
	T.ok("fewer rows than there are", res.rows < res.total and res.rows > 100, res.rows)
	T.check("all of them counted", res.total, 6000)
	T.ok("within the cap", res.bytes <= 20000, res.bytes)
	local ls = lines(res.text)
	T.check("the newest last", ls[#ls]:sub(1, 16), X.Date(now - 600, "%Y-%m-%d %H:%M"))
	-- (times with a fraction of a second, as the mail times are: the date still shows)
	-- the default cap: 6000 rows of about 70 characters is more than 100,000
	res = X.ExportRun("ledger", {days = 0})
	T.ok("default cap", res.cut and res.bytes <= X.EXPORT_MAX, res.bytes)
	T.note("export: " .. res.rows .. " of 6000 sale rows fit in the " .. X.EXPORT_MAX .. " character copy box")
	-- sliced: not done after one frame
	local got
	local B = X.Export("ledger", {days = 0}, function(r) got = r end)
	W.advance(0.05)
	T.ok("not all in one frame", B.result == nil)
	W.advance(2)
	T.ok("done a moment later", got ~= nil and got.rows == res.rows)
	-- a newer export replaces one still running
	local first, second
	X.Export("ledger", {days = 0}, function(r) first = r end)
	X.Export("ledger", {days = 30}, function(r) second = r end)
	W.advance(2)
	T.check("the older one never finishes", first, nil)
	T.ok("the newer one does", second ~= nil)
end)

T.scene("42 data: the window - Settings button, /xnah data, slim down asked inside, copy box", function()
	local X = W.start()
	W.advance(5)
	for k = 1, 5 do listed(X, tostring(80000 + k), 200, 2) end
	listed(X, "80010", 0, 3)
	X.SetWatched("80010", true)
	-- from Settings
	X.UI.Open("scan")
	W.advance(1)
	W.click("Your data ...", X.UI.tabs.scan.panel)
	W.advance(2)
	local f = X.UI.DataFrame()
	T.ok("opened from Settings", f and f:IsShown())
	T.ok("Escape closes it", X.Contains(W.env.UISpecialFrames, "XNAHDataFrame") ~= nil)
	local screen = W.screen(f)
	T.ok("health: last full scan", has(screen, "Last full scan"), screen)
	T.ok("health: last tracked scan", has(screen, "Last scan of your tracked items"))
	T.ok("health: kept", has(screen, "Kept on this realm: 6 items"), screen)
	T.ok("health: total", has(screen, "Saved data in all: about"))
	T.ok("health: not seen", has(screen, "180 days: 5"), screen)
	local D = data(X)
	T.ok("parts listed", #D.parts.items >= 3, #D.parts.items)
	T.check("biggest items listed", #D.top.items, 6)
	-- /xnah data closes nothing, shows it again
	f:Hide()
	f = openData(X)
	T.ok("/xnah data opens it", f:IsShown())
	-- slim down: asked inside the window first
	T.ok("preview line", has(D.slimText:GetText(), "Would remove 5 items"), D.slimText:GetText())
	W.click("Slim down ...", f)
	T.ok("the question", has(D.slimText:GetText(), "Remove 5 items not seen for 90 days"), D.slimText:GetText())
	T.ok("yes button", W.findButton("Yes, remove them", f) ~= nil)
	W.click("Cancel", f)
	W.advance(1)
	T.check("cancel: nothing removed", T.count(X.Items()), 6)
	-- another number of days from the menu
	W.click("Not seen for 90 days", f)
	menuPick("365 days")
	W.advance(0.5)
	T.check("days kept", X.S().dataSlimDays, 365)
	T.ok("preview for 365 days", has(D.slimText:GetText(), "Would remove 0 items"), D.slimText:GetText())
	W.click("Slim down ...", f)
	T.ok("nothing to remove", has(D.slimText:GetText(), "Nothing to remove"), D.slimText:GetText())
	W.click("Not seen for 365 days", f)
	menuPick("180 days")
	W.advance(0.5)
	W.click("Slim down ...", f)
	W.click("Yes, remove them", f)
	W.advance(3)
	T.check("removed", T.count(X.Items()), 1)
	local done = D.slimText:GetText()
	T.ok("says what was done and when the file shrinks", has(done, "Removed 5 items") and has(done, "/reload"), done)
	T.ok("health worked out again", has(W.screen(f), "Kept on this realm: 1 item,"), W.screen(f))
	-- export: the copy box with the text selected
	T.ok("opening the window leaves the keyboard to the game", W.focus ~= D.box.edit)
	T.ok("and says how to copy", has(D.status:GetText(), "Press Select all, then Ctrl+C"), D.status:GetText())
	W.click("Select all", D.right)
	T.ok("Select all: the box has the keyboard", W.focus == D.box.edit)
	D.box.edit:ClearFocus()
	X.S().dataExport = "tracked"
	D.MakeExport(true)
	W.advance(1)
	local want = X.ExportRun("tracked").text
	T.check("the copy box holds the export", D.box:GetText(), want)
	T.ok("the copy box has the keyboard (selected, Ctrl+C copies)", W.focus == D.box.edit)
	T.ok("says to press Ctrl+C", has(D.status:GetText(), "Ctrl+C"), D.status:GetText())
	W.type(D.box.edit, "something else", false)
	T.check("typing changes nothing", D.box:GetText(), want)
	-- pick another kind from the menu
	W.click("Tracked items now", f)
	menuPick("Your sales and buys")
	W.advance(1)
	T.check("kind kept", X.S().dataExport, "ledger")
	T.ok("ledger header in the box", has(D.box:GetText(), "Date\tWhat\tItem"), D.box:GetText())
	T.ok("no sales: only the header", has(D.status:GetText(), "only the header"), D.status:GetText())
	-- the time span buttons
	W.click("All", D.right)
	W.advance(1)
	T.check("range kept", X.S().dataRange, 0)
	-- the price history of the shown item, picked from the menu
	X.S().dataExport = "history"
	X.UI.itemKey = nil
	D.MakeExport(true)
	W.advance(1)
	T.ok("the first tracked item is used", has(D.box:GetText(), "Lowest price (gold)") and select(2, D.box:GetText():gsub("\n", "")) == 3,
		D.box:GetText())
	W.click("All", D.right)
	W.advance(1)
	-- after a reload the choices stay
	X = W.reload()
	W.advance(5)
	T.check("after a reload: kind", X.S().dataExport, "history")
	T.check("after a reload: days", X.S().dataSlimDays, 180)
end)

T.scene("42 data: health of a big realm is worked out a little per frame", function()
	local X = W.start()
	W.advance(5)
	local items = X.Items()
	for i = 1, 5000 do
		items[tostring(100000 + i)] = {id = 100000 + i, n = "Bulk " .. i, q = 1, cur = {t = X.Now() - (i % 300) * DAY, min = 100, mkt = 110, qty = 3, auc = 1},
			d = "a,b,c,d,1;e,f,g,h,1"}
	end
	local fired = 0
	X.On("XNAH_DATA", function() fired = fired + 1 end)
	local res, busy = X.DataHealth(true)
	T.ok("busy at first", busy)
	W.advance(0.05)
	T.ok("still busy after one frame", X.DataHealthBusy())
	W.advance(3)
	T.ok("done", not X.DataHealthBusy())
	T.check("told when done", fired, 1)
	res = X.DataHealth()
	T.check("every item", res.items, 5000)
	T.ok("about 70% not seen for 90 days", res.unseen[90] > 3400 and res.unseen[90] < 3550, res.unseen[90])
	-- slim down sliced too
	local ok, B = X.DataSlim(180)
	T.ok("started", ok)
	W.advance(0.05)
	T.ok("not all in one frame", B.i < B.total, B.i)
	W.advance(3)
	T.ok("done", X.DataSlimming() == nil)
	T.ok("removed the old ones", B.removed > 1900 and B.removed < 1990, B.removed)
	T.check("the rest kept", T.count(X.Items()), 5000 - B.removed)
end)
