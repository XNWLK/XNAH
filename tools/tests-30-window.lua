-- XNAH test scenes, part 30: the big window (v0.9) - docked beside the game's auction house window (and made smaller
-- when the screen has not room enough), closing with it when it opened it, the header (views, scan line, scan buttons,
-- Find, the gear), UI.ShowItem, the tracked list, and "Buy cheapest now": a stack that is not a commodity (one press
-- buys the whole auction), a commodity (two presses: the exact price, then the purchase; how many; no answer in time),
-- searching again after each purchase, nothing restricted outside a click.

local MAP = 50001
local KEY = tostring(MAP)
local ONE = 4999         -- 49s 99c each
local STACK = ONE * 40   -- 19g 99s 60c for all 40

local function has(text, part) return tostring(text or ""):find(part, 1, true) ~= nil end
local function items(X) return X.UI.tabs.items.panel end
local function label(b) return W.plain(W.buttonText(b)) end
local function openMenu()
	for _, f in ipairs(W.frames) do
		if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then return f end
	end
end
-- the game's auction house window, its top edge where it is on a real screen (the stand-in's GetTop is its height)
local function ahWindow()
	local f = W.ahWindow()
	f.GetTop = function() return 1060 end
	return f
end
local function history(X, key, usual, days, name)
	for d = days or 5, 1, -1 do X.Record(key, X.Now() - d * 86400, usual, usual, 50, 5, name) end
end

T.scene("window: docks beside the auction house, made smaller to fit, closes with it", function()
	local X = W.start()
	ahWindow()
	T.ok("closed at the start", not (X.UI.Frame() and X.UI.Frame():IsShown()))
	W.openAH()
	W.advance(0.5)
	local f = X.UI.Frame()
	T.ok("opens with the auction house", f and f:IsShown())
	T.ok("docked", X.UI.Docked())
	T.ok("opened by the auction house", X.UI.OpenedByAH())
	local p = f.points[1]
	T.ok("its top left on the auction house's top right", p and p[1] == "TOPLEFT" and p[2] == W.ahFrame and p[3] == "TOPRIGHT" and
		p[4] == 2 and p[5] == 0, p and T.show(p))
	T.near("room enough: the size you picked", f:GetScale(), 1, 0.001)
	T.check("the content is 1080 x 600", X.UI.W .. " x " .. X.UI.H, "1080 x 600")
	-- docked: dragging does not move it (nor save a spot)
	W.step(f.scripts.OnDragStart, f)
	W.step(f.scripts.OnDragStop, f)
	T.check("no spot saved while docked", X.S().window, nil)
	-- the auction house closes: the window it opened goes too
	W.closeAH()
	T.ok("closes with the auction house", not f:IsShown())
	T.ok("not docked any more", not X.UI.Docked())
	-- a smaller screen: made smaller to fit right of the auction house window
	W.env.UIParent.w = 1600
	W.openAH()
	W.advance(0.3)
	T.near("scaled to fit", f:GetScale(), (1600 - 800 - 4) / X.UI.FW, 0.01)
	W.closeAH()
	-- far too small: never under 0.6
	W.env.UIParent.w = 1200
	W.openAH()
	W.advance(0.3)
	T.near("not smaller than 0.6", f:GetScale(), 0.6, 0.001)
	W.closeAH()
	-- a big screen and a bigger size picked: the size picked
	W.env.UIParent.w = 3000
	X.UI.SetScale(1.3)
	W.openAH()
	W.advance(0.3)
	T.near("the size picked", f:GetScale(), 1.3, 0.001)
	-- a size changed while docked: kept, and fitted again
	W.env.UIParent.w = 1600
	X.UI.SetScale(1.2)
	T.check("size kept for later", X.S().uiScale, 1.2)
	T.ok("still docked", X.UI.Docked() and f.points[1][2] == W.ahFrame)
	T.ok("fitted again", f:GetScale() < 1)
	W.closeAH()
	X.UI.SetScale(1)
	-- the setting off: it does not open by itself
	X.S().openWithAH = false
	W.openAH()
	W.advance(0.3)
	T.ok("setting off: stays closed", not f:IsShown())
	-- opened by hand while the auction house is open: docked too
	X.UI.Open()
	T.ok("opened by hand: docked", X.UI.Docked() and f.points[1][2] == W.ahFrame)
	T.ok("opened by hand: not by the auction house", not X.UI.OpenedByAH())
	W.closeAH()
	T.ok("opened by hand: stays when the auction house closes", f:IsShown())
	X.S().openWithAH = true
	-- opened by hand away from the auction house: its own spot, moved by dragging, back there after the auction house
	X.S().window = {"CENTER", "CENTER", 100, 50}
	X.UI.Place()
	T.ok("its own spot", f.points[1] and f.points[1][1] == "CENTER" and f.points[1][2] == W.env.UIParent and f.points[1][4] == 100)
	W.openAH()
	W.advance(0.3)
	T.ok("docked while the auction house is open", X.UI.Docked())
	W.closeAH()
	T.ok("still open", f:IsShown())
	T.ok("back on its own spot", f.points[1] and f.points[1][1] == "CENTER" and f.points[1][4] == 100 and f.points[1][5] == 50,
		f.points[1] and T.show(f.points[1]))
	T.near("its own size", f:GetScale(), 1, 0.001)
	f.points = {{"TOPLEFT", W.env.UIParent, "BOTTOMLEFT", 40, 900}}
	W.step(f.scripts.OnDragStart, f)
	W.step(f.scripts.OnDragStop, f)
	T.check("dragged: the spot saved", X.S().window and X.S().window[3], 40)
	-- Escape closes it
	T.ok("Escape closes it", X.Contains(W.env.UISpecialFrames, "XNAHFrame") ~= nil)
	-- closed with Escape while the auction house opened it: comes back next time
	W.openAH()
	W.advance(0.3)
	f:Hide()
	W.closeAH()
	W.openAH()
	W.advance(0.3)
	T.ok("next time it opens again", f:IsShown())
	W.closeAH()
	-- a reload: the setting and the size stay
	X.S().openWithAH = false
	X = W.reload()
	ahWindow()
	W.openAH()
	W.advance(0.5)
	T.ok("after a reload: setting kept", not (X.UI.Frame() and X.UI.Frame():IsShown()))
end)

T.scene("window: views, the header, the scan line and buttons, Find", function()
	local X = W.start()
	W.list(2589, 50, 20, 3)
	W.list(2592, 80, 20, 2)
	X.UI.Open()
	local f = X.UI.Frame()
	T.check("starts on Items", X.UI.current, "items")
	local views = {Items = "items", Market = "market", ["Your gold"] = "gold", Opportunities = "opps"}
	for title, key in pairs(views) do
		W.click(title, f)
		T.check("view button " .. title, X.UI.current, key)
	end
	W.click("Items", f)
	-- the gear: Settings
	local gear = f.gear
	gear:Click()
	T.check("gear: Settings", X.UI.current, "scan")
	-- old names
	for old, new in pairs({item = "items", trends = "market", ledger = "gold", wealth = "gold", settings = "scan"}) do
		X.UI.Open(old)
		T.check("old name " .. old, X.UI.current, new)
	end
	T.check("TabKey", X.UI.TabKey("item"), "items")
	-- the scan line and buttons: away from the auction house
	T.ok("scan line: no full scan yet", has(W.plain(f.status.text), "Full scan never"), f.status.text)
	T.ok("Full scan: off while closed", f.full.disabled)
	T.ok("Scan tracked: off while closed", f.tracked.disabled)
	-- at the auction house: a full scan from the header
	W.openAH()
	W.advance(0.5)
	T.ok("Full scan: on", not f.full.disabled)
	f.full:Click()
	W.advance(0.1)
	T.ok("scan line follows the scan", X.scan.state == "idle" or has(W.plain(f.status.text), W.plain(X.scan.text or "Scanning")), f.status.text)
	W.waitFor(function() return X.scan.state == "idle" end, 300)
	W.advance(0.5)
	T.ok("scan line: just now, items", has(W.plain(f.status.text), "Full scan just now, 2 items"), f.status.text)
	T.ok("countdown on the button", has(label(f.full), "Ready in 1"), label(f.full))
	T.ok("the countdown ticks", f.ticker:IsShown())
	local before = label(f.full)
	W.advance(2)
	T.ok("a second later: another time", label(f.full) ~= before, label(f.full))
	-- Scan tracked: the tracked items
	X.SetWatched("2589", true)
	f.tracked:Click()
	T.ok("tracked scan started", X.scan.state == "items" or #W.said("scan done") > 0, X.scan.state)
	W.waitFor(function() return X.scan.state == "idle" end, 60)
	T.ok("tracked scan done", #W.said("scan done: 1 items") > 0)
	-- Find (the box in the header): picking an item shows it
	W.type(X.UI.QuickBox, "Wool Cloth")
	W.advance(0.3)
	T.check("Find shows it", X.UI.itemKey, "2592")
	T.check("on the Items view", X.UI.current, "items")
	-- UI.ShowItem from anywhere: an item that is not tracked
	X.UI.Open("market")
	X.UI.ShowItem("4306")
	W.advance(0.2)
	T.check("ShowItem: Items view", X.UI.current, "items")
	T.check("ShowItem: the item", X.UI.itemKey, "4306")
	T.check("X.ShowItem is the same", X.ShowItem, X.UI.ShowItem)
	-- the minimap button: left = the window, right = settings
	f:Hide()
	local mm = W.env.XNAHMinimapButton
	W.step(mm.scripts.OnClick, mm, "LeftButton")
	T.ok("minimap: opens", f:IsShown())
	W.step(mm.scripts.OnClick, mm, "RightButton")
	T.check("minimap right-click: settings", X.UI.current, "scan")
	-- the key binding and /xnah
	W.env.XNAH_Toggle()
	T.ok("key binding toggles", not f:IsShown())
	W.env.SlashCmdList.XNAH("")
	T.ok("/xnah opens", f:IsShown())
	W.env.SlashCmdList.XNAH("settings")
	T.check("/xnah settings", X.UI.current, "scan")
	W.env.SlashCmdList.XNAH("Linen Cloth")
	T.check("/xnah <name> shows it", X.UI.itemKey, "2589")
	W.closeAH()
end)

T.scene("window: the tracked list - add, show, stop tracking", function()
	local X = W.start()
	history(X, "2589", 100, 8, "Linen Cloth")
	history(X, "2592", 300, 8, "Wool Cloth")
	X.Record("2589", X.Now() - 60, 80, 100, 50, 5, "Linen Cloth")
	X.UI.Open("items")
	local panel = items(X)
	T.ok("empty list says how", has(W.screen(panel), "Nothing tracked yet"))
	-- Add an item: Enter takes the best match; tracked and shown
	W.type(panel.add, "Linen Cloth")
	W.advance(0.3)
	T.ok("added: tracked", X.Watched("2589"))
	T.check("added: shown", X.UI.itemKey, "2589")
	T.check("one row", #panel.tbl.items, 1)
	local row = panel.tbl.rows[1]
	local text = W.plain(W.buttonText(row))
	T.ok("row: name", has(text, "Linen Cloth"), text)
	T.ok("row: cheapest now", has(text, "80c"), text)
	T.ok("row: % of usual (green)", has(text, "%") and has(row.cols[3].text, "4ade80"), row.cols[3].text)
	T.ok("row: a 7-day line", row.xnahSpark ~= nil)
	T.ok("header: Tracked", has(W.plain(panel.star.label.text), "Tracked"))
	-- typing a part: a menu of matches
	W.type(panel.add, "wool", false)
	W.advance(0.5)
	local menu = openMenu()
	T.ok("matches in a menu", menu ~= nil)
	if menu then W.click("Wool Cloth", menu) end
	W.advance(0.3)
	T.ok("picked from the menu: tracked", X.Watched("2592"))
	T.check("two rows", #panel.tbl.items, 2)
	-- clicking a row shows it
	for i, r in ipairs(panel.tbl.items) do
		if r.key == "2589" then panel.tbl.rows[i]:Click("LeftButton") end
	end
	T.check("row click shows it", X.UI.itemKey, "2589")
	-- an item that is not tracked: the line above the list, the Track star
	X.UI.ShowItem("4306")
	W.advance(0.2)
	T.ok("Showing line", has(W.plain(panel.showing.text), "Showing: Silk Cloth") and has(W.plain(panel.showing.text), "not tracked"),
		panel.showing.text)
	T.ok("star: Track", has(W.plain(panel.star.label.text), "Track") and not has(W.plain(panel.star.label.text), "Tracked"))
	panel.star:Click()
	W.advance(0.3)
	T.ok("star: tracked now", X.Watched("4306"))
	T.check("three rows", #panel.tbl.items, 3)
	T.ok("line: how many tracked", has(W.plain(panel.showing.text), "Tracked items: 3"), panel.showing.text)
	panel.star:Click()
	W.advance(0.3)
	T.ok("star again: not tracked", not X.Watched("4306"))
	-- right-click a row: Stop tracking
	local idx
	for i, r in ipairs(panel.tbl.items) do if r.key == "2592" then idx = i end end
	panel.tbl.rows[idx]:Click("RightButton")
	menu = openMenu()
	T.ok("right-click: a menu", menu ~= nil)
	T.ok("no max price in it", menu and W.findButton("price", menu) == nil)
	if menu then W.click("Stop tracking", menu) end
	W.advance(0.3)
	T.ok("stopped", not X.Watched("2592"))
	T.check("one row left", #panel.tbl.items, 1)
	-- sorting by a column and scrolling do not lose the lines
	for i = 1, 30 do X.SetWatched(tostring(70000 + i), true) end
	W.advance(0.3)
	W.step(panel.tbl.scripts.OnMouseWheel, panel.tbl, -1)
	T.ok("scrolled", panel.tbl.offset > 0)
end)

-- [[ Buy cheapest now ]]
local function addMap()
	W.items[MAP] = {name = "Lower Map Fragment", quality = 1, sell = 0, stack = 40, nocommodity = true}
end
local function waitReady(X)
	W.waitFor(function() return X.buy.state == "ready" or X.buy.state == "none" end, 10)
	W.advance(0.2)
	return X.buy.state
end
local function calls() return table.concat(W.restrictedCalls, ",") end

T.scene("buy cheapest: a stack that is not a commodity - one press, the whole auction", function()
	local X = W.start()
	addMap()
	history(X, KEY, 5000, 5, "Lower Map Fragment")
	W.list(MAP, ONE, 40, 1, "Ann")     -- 40 at 49s 99c each: the cheapest not yours
	W.list(MAP, 10000, 1, 1, "Bob")    -- one at 1g
	W.mine(MAP, 3000, 1)               -- yours, cheaper: never bought
	X.UI.ShowItem(KEY)
	local panel = items(X)
	T.check("closed: says so", label(panel.buy), "Open the auction house to buy")
	T.ok("closed: off", panel.buy.disabled)
	W.openAH()
	T.check("searched when shown at the auction house", waitReady(X), "ready")
	T.check("nothing restricted yet", #W.restrictedCalls, 0)
	T.check("label: the whole stack, the exact price", label(panel.buy), "Buy cheapest: 40 for " .. X.MoneyPlain(STACK))
	T.ok("no how-many box (not a commodity)", not panel.qty:IsShown())
	T.ok("the line under it", has(W.plain(panel.buyNote.text), "One press buys it"), panel.buyNote.text)
	-- one press: PlaceBid with the price of one (as the game's own Buyout button), the server takes it x 40
	local money = W.money
	local boughtEvents = 0
	X.On("XNAH_BOUGHT", function() boughtEvents = boughtEvents + 1 end)
	panel.buy:Click()
	T.check("one restricted call", calls(), "PlaceBid")
	T.check("amount sent: the price of one", W.bids[1] and W.bids[1].amount, ONE)
	T.ok("no question asked", not (W.env.XNAHConfirm and W.env.XNAHConfirm:IsShown()) and not (W.env.XNAHDialog and W.env.XNAHDialog:IsShown()))
	W.waitFor(function() return #W.won > 0 end, 5)
	T.check("bought the 40", W.won[1] and W.won[1].count, 40)
	T.check("gold taken: 19g 99s 60c", money - W.money, STACK)
	W.advance(0.5)
	T.check("XNAH_BOUGHT", boughtEvents, 1)
	local line = W.said("bought 40 ")[1] or ""
	T.ok("chat: what and for how much", has(line, "bought 40 Lower Map Fragment for " .. W.plain(X.Money(STACK))), line)
	-- searched again at once: ready for the next cheapest
	T.check("ready again", waitReady(X), "ready")
	T.check("label: the next one", label(panel.buy), "Buy 1 for 1g")
	panel.buy:Click()
	W.waitFor(function() return #W.won > 1 end, 5)
	T.check("second press bought it", W.won[2] and W.won[2].price, 10000)
	T.check("one call per press", calls(), "PlaceBid,PlaceBid")
	T.check("then nothing", waitReady(X), "none")
	T.check("label: nothing", label(panel.buy), "Nothing to buy - search again")
	T.ok("your own listing left alone", #W.ah == 1 and W.ah[1].owner == W.me)
	-- pressing now searches again (nothing restricted)
	panel.buy:Click()
	T.check("a search, not a purchase", #W.restrictedCalls, 2)
	-- the ladder shows yours
	W.advance(2)
	T.ok("ladder: yours", has(W.screen(panel.ladder), "yours"), W.screen(panel.ladder))
	W.closeAH()
	W.advance(0.3)
	T.check("closed again", label(panel.buy), "Open the auction house to buy")
end)

T.scene("buy cheapest: a commodity - two presses, the exact price, how many", function()
	local X = W.start()
	history(X, "2589", 100, 5, "Linen Cloth")
	history(X, "2592", 300, 5, "Wool Cloth")
	W.list(2589, 50, 10, 2, "Ann")     -- 20 at 50c
	W.list(2589, 90, 10, 1, "Bob")     -- 10 at 90c
	W.list(2592, 300, 10, 1, "Cid")
	X.UI.ShowItem("2589")
	local panel = items(X)
	W.openAH()
	T.check("ready", waitReady(X), "ready")
	T.ok("how-many box shown", panel.qty:IsShown())
	T.check("how many: 1 at the start", panel.qty:GetText(), "1")
	T.check("label: 1", label(panel.buy), "Buy 1 for 50c")
	-- 25: 20 at 50c and 5 at 90c
	W.type(panel.qty, "25")
	W.advance(0.6)
	T.check("label: 25", label(panel.buy), "Buy 25 for 14s 50c")
	T.check("no new search for it", X.buy.state, "ready")
	W.type(panel.qty, "20")
	W.advance(0.6)
	T.check("label: 20", label(panel.buy), "Buy 20 for 10s")
	-- press 1: the exact price from the server
	panel.buy:Click()
	T.check("press 1: one call", calls(), "StartCommoditiesPurchase")
	T.check("asking", label(panel.buy), "Asking the exact price ...")
	W.advance(0.5)
	T.check("the exact price on the button", label(panel.buy), "Confirm: 20 for 10s")
	T.ok("no question asked in between", not (W.env.XNAHConfirm and W.env.XNAHConfirm:IsShown()))
	T.check("nothing bought yet", #W.won, 0)
	-- the server's price changes while it waits: the button follows
	W.fire("COMMODITY_PRICE_UPDATED", 55, 1100)
	T.check("a new exact price", label(panel.buy), "Confirm: 20 for 11s")
	W.fire("COMMODITY_PRICE_UPDATED", 50, 1000)
	-- press 2: bought
	panel.buy:Click()
	T.check("press 2: one call", calls(), "StartCommoditiesPurchase,ConfirmCommoditiesPurchase")
	W.waitFor(function() return #W.won > 0 end, 5)
	T.check("got 20", W.won[1] and W.won[1].count, 20)
	W.advance(0.5)
	T.ok("chat line", #W.said("bought 20 Linen Cloth for 10s") > 0, W.chat[#W.chat])
	-- searched again: the next cheapest (only 10 left, at 90c)
	T.check("ready again", waitReady(X), "ready")
	T.check("label: what is left", label(panel.buy), "Buy 10 for 9s")
	T.check("how many stays 20", panel.qty:GetText(), "20")
	-- remembered per item while you look at others
	X.UI.ShowItem("2592")
	waitReady(X)
	T.check("another item: its own number", panel.qty:GetText(), "1")
	X.UI.ShowItem("2589")
	waitReady(X)
	T.check("back: 20 again", panel.qty:GetText(), "20")
	-- right-click while it waits for the second press: stopped, nothing restricted
	panel.buy:Click()
	W.advance(0.5)
	T.check("waiting for press 2", X.buy.state, "confirm")
	local n = #W.restrictedCalls
	panel.buy:Click("RightButton")
	T.check("right-click: nothing restricted", #W.restrictedCalls, n)
	T.ok("right-click: stopped", X.buy.state ~= "confirm")
	waitReady(X)
	-- no answer from the server in 5 seconds: stopped and said so
	local AH = W.env.C_AuctionHouse
	local start, cancel = AH.StartCommoditiesPurchase, AH.CancelCommoditiesPurchase
	local cancelled = 0
	AH.StartCommoditiesPurchase = function(...) W.restrictedCalls[#W.restrictedCalls + 1] = "StartCommoditiesPurchase" end
	AH.CancelCommoditiesPurchase = function() cancelled = cancelled + 1 end
	panel.buy:Click()
	T.check("asking", X.buy.state, "quoting")
	W.advance(3)
	T.check("still asking after 3 s", X.buy.state, "quoting")
	W.advance(2.5)
	T.ok("given up after 5 s", X.buy.state ~= "quoting", X.buy.state)
	T.ok("the purchase was stopped", cancelled >= 1)
	T.ok("said so", #W.said("no price came back") > 0)
	T.check("ready for the next press", waitReady(X), "ready")
	AH.StartCommoditiesPurchase, AH.CancelCommoditiesPurchase = start, cancel
	W.closeAH()
end)

T.scene("buy cheapest: nothing restricted outside a click, nothing errors with an empty database", function()
	local X = W.start()
	history(X, "2589", 100, 5, "Linen Cloth")
	W.list(2589, 50, 20, 3, "Ann")
	X.UI.ShowItem("2589")
	W.openAH()
	waitReady(X)
	-- a minute of timers, events, refreshes and prices
	for _ = 1, 6 do
		X.Fire("XNAH_PRICES")
		X.Fire("XNAH_WATCH")
		W.advance(10)
	end
	T.check("ready but waiting for a click", X.buy.state, "ready")
	T.check("no restricted call without a click", #W.restrictedCalls, 0)
	-- other views and back: still nothing
	X.UI.Open("market")
	W.advance(1)
	X.UI.Open("items")
	W.advance(1)
	T.check("still none", #W.restrictedCalls, 0)
	W.closeAH()
	-- an empty database: every view, the auction house open and closed, an unknown item
	X = W.start()
	X.UI.Open()
	for _, key in ipairs(X.UI.order) do X.UI.Select(key) W.advance(0.2) end
	X.UI.ShowItem("424242")
	W.openAH()
	W.advance(3)
	X.UI.Frame().full:Click()
	W.advance(0.5)
	X.UI.Frame().tracked:Click()
	W.advance(3)
	W.closeAH()
	W.advance(1)
	for _, key in ipairs(X.UI.order) do X.UI.Select(key) W.advance(0.2) end
	T.ok("still open", X.UI.Frame():IsShown())
end)

T.scene("window: Settings - the two new settings and the deal settings", function()
	local X = W.start()
	X.UI.Open("scan")
	local p = X.UI.tabs.scan.panel
	local screen = W.screen(p)
	for _, t in ipairs({"Open with the auction house", "Extra columns in the auction house lists", "Opportunities",
		"Far under usual: at most", "Least profit after the cut"}) do
		T.ok("settings: " .. t, has(screen, t), screen)
	end
	T.ok("no bar setting any more", not has(screen, "XNAH bar"))
	W.click("Open with the auction house", p)
	T.check("open with the auction house: off", X.S().openWithAH, false)
	-- the deal settings: typed, kept on leaving the box
	local boxes = {}
	W.walk(p, function(f) if f.kind == "EditBox" and f:IsVisible() then boxes[#boxes + 1] = f end end)
	local pctBox, moneyBox
	for _, e in ipairs(boxes) do
		if e.text == tostring(X.S().dealPct) then pctBox = e end
		if e.text == X.MoneyPlain(X.S().dealMinProfit) then moneyBox = e end
	end
	T.ok("the boxes are there", pctBox ~= nil and moneyBox ~= nil)
	if pctBox then W.type(pctBox, "45", false) W.step(pctBox.scripts.OnEditFocusLost, pctBox) end
	if moneyBox then W.type(moneyBox, "25s", false) W.step(moneyBox.scripts.OnEditFocusLost, moneyBox) end
	T.check("far under usual: 45%", X.S().dealPct, 45)
	T.check("least profit: 25s", X.S().dealMinProfit, 2500)
end)
