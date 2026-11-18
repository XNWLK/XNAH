-- XNAH test scenes, part 4: the window. Every tab opens, and every button, box, row and hover spot found in it is used,
-- with a 10-day market loaded - without a Lua error and without "error" in chat. The scene does not know the tabs'
-- insides: it walks the frames each tab built. (The stand-in frames accept any method, so this proves the tabs' own
-- logic runs; tools/check-api.js proves the methods exist in the Forever client.)

-- a market of 10 days with recipes, a merchant and a watch list
local function tenDays(X)
	W.makeMarket(31, 120, {lastDay = 9, uncached = 0})
	W.recipes = {
		[1] = {name = "Smelt Copper", out = 2840, reagents = {{2770, 1}}, learned = true, prof = "Mining"},
		[2] = {name = "Smelt Bronze", out = 2841, qMin = 2, qMax = 2, reagents = {{2840, 1}, {3576, 1}}, learned = true, prof = "Mining"},
		[3] = {name = "Minor Healing Potion", out = 118, reagents = {{2447, 1}, {765, 1}, {3371, 1}}, learned = true, prof = "Alchemy"},
		[4] = {name = "Red Linen Shirt", out = 2575, reagents = {{2996, 1}, {2320, 1}, {2678, 1}}, prof = "Tailoring"},
	}
	for _, p in ipairs({"Mining", "Alchemy"}) do W.openProfession(p) W.advance(2) W.closeProfession() end
	W.openProfession("Tailoring", true) W.advance(2) W.closeProfession()
	W.merchant[#W.merchant + 1] = {itemID = 3371, price = 4, stackCount = 1, numAvailable = -1}
	W.merchant[#W.merchant + 1] = {itemID = 2320, price = 10, stackCount = 1, numAvailable = -1}
	W.openMerchant("Supplies")
	W.advance(1)
	W.closeMerchant()
	W.openAH()
	for day = 0, 9 do
		W.marketDay(day, 9)
		W.list(2589, 50 + day, 20, 5, "Ann")
		W.list(2770, 10, 20, 5) W.list(2840, 30, 20, 5) W.list(3576, 40, 20, 5) W.list(2841, 50, 20, 5)
		W.list(2447, 20, 20, 5) W.list(765, 15, 20, 5) W.list(3371, 50, 20, 5) W.list(118, 10000, 5, 5)
		W.list(2996, 150, 20, 3) W.list(2575, 5000, 1, 3)
		W.list(15210, 50000 + day * 1000, 1, 2, "Cid", -19)
		local t0 = W.NOW
		T.fullScan(X)
		if day < 9 then W.advance(86400 - (W.NOW - t0)) end
	end
	X.SetWatched("2589", true)
	X.SetWatched("15210:-19", true)
	X.SetWatched(tostring(W.market.byKind.stack[1]), true)
end

-- frames under root that are shown right now
local function under(root, test)
	local out = {}
	W.walk(root, function(f) if f:IsVisible() and test(f) then out[#out + 1] = f end end)
	return out
end
local function isClickable(f) return (f.kind == "Button" or f.kind == "CheckButton") and f.scripts.OnClick ~= nil end
-- closes pop-ups the clicks may have opened (menus, dialogs, the yes / no question) without answering them
local function closePopups(X)
	if X.K and X.K.CloseMenu then X.K.CloseMenu() end
	for _, name in ipairs({"XNAHDialog", "XNAHDialog2", "XNAHConfirm"}) do
		local d = W.env[name]
		if d and d.shown then d:Hide() end
	end
end
-- the visible pop-up menu, if any
local function openMenu()
	for _, f in ipairs(W.frames) do
		if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then return f end
	end
end

-- uses everything in one tab; returns counts
local function exercise(X, key, stats)
	local UI = X.UI
	UI.Select(key)
	W.advance(0.5)
	local tab = UI.tabs[key]
	T.ok(key .. ": panel built", tab.panel ~= nil)
	if not tab.panel then return end
	T.ok(key .. ": panel shown", tab.panel:IsVisible())
	T.ok(key .. ": shows some text", W.screen(tab.panel) ~= "", key)
	local function back()
		closePopups(X)
		if UI.current ~= key then UI.Select(key) W.advance(0.3) end
		local f = UI.Frame and UI.Frame()
		if f and not f:IsShown() then UI.Open(key) W.advance(0.3) end
	end
	-- buttons, check boxes, rows, column headers
	local clicks = 0
	for _, f in ipairs(under(tab.panel, isClickable)) do
		if clicks >= 150 then break end
		if f:IsVisible() and not f.disabled then
			f:Click("LeftButton")
			clicks = clicks + 1
			W.advance(0.3)
			-- a scan a button started runs to its end
			if X.scan.state ~= "idle" then W.waitFor(function() return X.scan.state == "idle" end, 120) end
			back()
		end
	end
	-- right-click on a few: every entry of the menu it opens
	local menus = 0
	for i, f in ipairs(under(tab.panel, isClickable)) do
		if i > 12 then break end
		f:Click("RightButton")
		W.advance(0.1)
		local m = openMenu()
		if m then
			local entries = under(m, isClickable)
			closePopups(X)
			for j = 1, #entries do
				back()
				if not f:IsVisible() then break end
				f:Click("RightButton")
				W.advance(0.1)
				local m2 = openMenu()
				local list = m2 and under(m2, isClickable) or {}
				if list[j] then list[j]:Click("LeftButton") menus = menus + 1 end
				W.advance(0.3)
				if X.scan.state ~= "idle" then W.waitFor(function() return X.scan.state == "idle" end, 120) end
			end
		end
		back()
	end
	-- text boxes: typing, Enter, clearing
	local typed = 0
	for _, e in ipairs(under(tab.panel, function(f) return f.kind == "EditBox" end)) do
		if e:IsVisible() then
			for _, text in ipairs({"lin", "Linen Cloth", "10g 5s", "15", "zzz", ""}) do
				W.type(e, text)
				W.advance(0.3)
				typed = typed + 1
				back()
				if not e:IsVisible() then break end
			end
			if e.scripts.OnEscapePressed then W.step(e.scripts.OnEscapePressed, e) end
		end
	end
	-- the mouse over things (tooltips, the graph's hover line), the wheel, mouse buttons
	local hovers = 0
	for _, f in ipairs(under(tab.panel, function(f) return f.scripts.OnEnter or f.scripts.OnMouseWheel or f.scripts.OnMouseDown end)) do
		if hovers >= 80 then break end
		if f:IsVisible() then
			if f.scripts.OnEnter then
				for _, x in ipairs({5, 300, 9999}) do
					W.hover(f, x, 20)
					W.advance(0.1)
				end
				W.unhover(f)
				hovers = hovers + 1
			end
			if f.scripts.OnMouseWheel then W.step(f.scripts.OnMouseWheel, f, -1) W.step(f.scripts.OnMouseWheel, f, 1) end
			if f.scripts.OnMouseDown then W.step(f.scripts.OnMouseDown, f, "LeftButton") end
			if f.scripts.OnMouseUp then W.step(f.scripts.OnMouseUp, f, "LeftButton") end
			back()
		end
	end
	-- sliders
	for _, s in ipairs(under(tab.panel, function(f) return f.kind == "Slider" and f.scripts.OnValueChanged end)) do
		local lo, hi = s:GetMinMaxValues()
		s:SetValue(hi) s:SetValue(lo)
	end
	W.advance(0.5)
	stats[#stats + 1] = string.format("%s: %d clicks, %d menu entries, %d typed, %d hovered", key, clicks, menus, typed, hovers)
end

T.scene("ui: every tab, every button, with a 10-day market", function()
	local X = W.start()
	tenDays(X)
	T.ok("tabs registered", #X.UI.order > 0, #X.UI.order)
	-- with the auction house open
	W.env.SlashCmdList.XNAH("")
	local frame = X.UI.Frame()
	T.ok("window open", frame and frame:IsShown())
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local stats = {}
	for _, key in ipairs(X.UI.order) do
		X.UI.ShowItem("2589")
		exercise(X, key, stats)
	end
	-- the item page for a sword with a suffix and for an item with no prices at all
	X.UI.ShowItem("15210:-19")
	W.advance(0.5)
	T.ok("item page: sword", W.screen(frame):find("Raider Shortsword", 1, true) ~= nil)
	X.UI.ShowItem("2575")
	X.UI.ShowItem("424242")
	W.advance(0.5)
	-- the bar on the auction house window, the minimap button
	for _, root in ipairs({W.env.AuctionHouseFrame, W.env.Minimap}) do
		for _, f in ipairs(under(root, isClickable)) do
			if f:IsVisible() then f:Click("LeftButton") W.advance(0.3) closePopups(X) end
			if X.scan.state ~= "idle" then W.waitFor(function() return X.scan.state == "idle" end, 120) end
		end
		for _, f in ipairs(under(root, function(f) return f.scripts.OnEnter end)) do W.hover(f) W.advance(0.1) W.unhover(f) end
	end
	-- with the auction house closed, every tab again
	W.closeAH()
	X.UI.Open("market")
	for _, key in ipairs(X.UI.order) do exercise(X, key, stats) end
	-- Escape closes it (the window is in UISpecialFrames)
	T.ok("the window closes with Escape", X.Contains(W.env.UISpecialFrames, "XNAHFrame") ~= nil)
	-- a reload with the window state saved
	X = W.reload()
	W.env.SlashCmdList.XNAH("")
	W.advance(1)
	T.ok("window opens after a reload", X.UI.Frame() and X.UI.Frame():IsShown())
	for _, l in ipairs(stats) do T.note("ui " .. l) end
end)

T.scene("ui: an empty start (no data at all)", function()
	local X = W.start()
	W.env.SlashCmdList.XNAH("")
	for _, key in ipairs(X.UI.order) do
		X.UI.Select(key)
		W.advance(0.5)
		local tab = X.UI.tabs[key]
		T.ok(key .. ": built with no data", tab.panel ~= nil)
	end
	X.UI.ShowItem("2589")
	W.advance(0.5)
	W.openAH()
	W.advance(1)
	W.closeAH()
	W.advance(1)
end)
