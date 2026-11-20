-- The Settings page (tab key "scan", no tab button: the Settings button in the title bar opens it): start and watch
-- scans, the last scans, the mailbox button, every setting, the size of the saved data.
-- Also here: the minimap button, and the small XNAH bar on top of the auction house window.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local LEFT_W = 470           -- scan box, last scans, saved data
local RIGHT_X = LEFT_W + 10  -- settings
local RIGHT_W = W - RIGHT_X
local WHITE = "Interface\\Buttons\\WHITE8x8"

-- "Full scan" or "Ready in 12:34" (the server allows a full scan about every 15 minutes)
local function fullScanText()
	local left = X.FullScanLeft()
	if left > 0 then return "Ready in " .. X.Clock(left) end
	return "Full scan"
end
local function fullScanAllowed()
	return X.ahOpen == true and X.FullScanReady()
end

-- [[ the scan box ]]
local function updateScanBox(p)
	local b = p.scanBox
	if not b then return end
	local s = X.scan
	local idle = s.state == "idle"
	if X.ahOpen then
		b.status:SetText("|cff4ade80The auction house is open.|r")
	else
		b.status:SetText("|cff999999The auction house is closed: talk to an auctioneer to scan.|r")
	end
	b.full:SetText(fullScanText())
	b.full:SetEnabled(fullScanAllowed())
	b.watch:SetEnabled(X.ahOpen == true and idle)
	b.stop:SetEnabled(not idle)
	local total, done = s.total or 0, s.done or 0
	if not idle and total > 0 then
		b.bar:SetMinMaxValues(0, total)
		b.bar:SetValue(math.min(done, total))
		b.barText:SetText(X.Num(done) .. " / " .. X.Num(total))
	else
		b.bar:SetMinMaxValues(0, 1)
		b.bar:SetValue(0)
		b.barText:SetText("")
	end
	b.text:SetText(s.text or (idle and "|cff999999No scan running.|r" or ""))
	local r = X.Realm()
	local lastFull
	for i = #r.scans, 1, -1 do
		if r.scans[i].kind == "full" then lastFull = r.scans[i] break end
	end
	local line = "Last full scan: " .. X.Ago(r.lastFull)
	if lastFull and lastFull.auctions then line = line .. "  (" .. X.Num(lastFull.auctions) .. " auctions, " .. X.Num(lastFull.items or 0) .. " items)" end
	b.last:SetText("|cff999999" .. line .. "|r")
end

local function buildScanBox(p)
	local b = K.Panel(p, LEFT_W, 180, {0, 0, 0, 0.25})
	b:SetPoint("TOPLEFT", 0, 0)
	p.scanBox = b
	local title = K.Label(b, "Auction house scan", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	b.status = K.Label(b, "")
	b.status:SetPoint("TOPLEFT", 10, -28)
	b.status:SetWidth(LEFT_W - 20)
	local help = K.Label(b, "Full scan: every auction at once (the server allows one about every 15 minutes). " ..
		"Watch list: searches your starred items one by one, any time.")
	help:SetPoint("TOPLEFT", 10, -44)
	help:SetWidth(LEFT_W - 20)
	help:SetWordWrap(true)
	b.full = K.Button(b, "Full scan", 150, 22, function() X.FullScan() updateScanBox(p) end)
	b.full:SetPoint("TOPLEFT", 10, -76)
	b.watch = K.Button(b, "Scan watch list", 130, 22, function() X.ScanItems() updateScanBox(p) end)
	b.watch:SetPoint("LEFT", b.full, "RIGHT", 6, 0)
	b.stop = K.Button(b, "Stop", 70, 22, function() X.ScanStop("stopped") updateScanBox(p) end)
	b.stop:SetPoint("LEFT", b.watch, "RIGHT", 6, 0)
	-- progress bar
	local bar = CreateFrame("StatusBar", nil, b)
	bar:SetSize(LEFT_W - 20, 16)
	bar:SetPoint("TOPLEFT", 10, -108)
	bar:SetStatusBarTexture(WHITE)
	local a = K.colors.accent
	bar:SetStatusBarColor(a[1], a[2], a[3], 0.8)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(0)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(1, 1, 1, 0.08)
	b.bar = bar
	b.barText = K.Label(bar, "", "GameFontHighlightSmall", "CENTER")
	b.barText:SetPoint("CENTER")
	b.text = K.Label(b, "")
	b.text:SetPoint("TOPLEFT", 10, -132)
	b.text:SetWidth(LEFT_W - 20)
	b.text:SetWordWrap(false)
	b.last = K.Label(b, "")
	b.last:SetPoint("TOPLEFT", 10, -152)
	b.last:SetWidth(LEFT_W - 20)
	b.last:SetWordWrap(false)
	-- the countdown and the bar move every second while the tab is shown
	local acc = 0
	p:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc >= 1 then
			acc = 0
			updateScanBox(p)
		end
	end)
end

-- [[ the last scans ]]
local SCAN_COLUMNS = {
	{"When", 130, "LEFT", text = function(r) return X.Date(r.t, "%b %d  %H:%M") end},
	{"Kind", 120, "LEFT", text = function(r) return tostring(r.kind or "-") end},
	{"Items", 70, "RIGHT", text = function(r) return r.items and X.Num(r.items) or "-" end},
	{"Auctions", 80, "RIGHT", text = function(r) return r.auctions and X.Num(r.auctions) or "-" end},
	{"Took", 60, "RIGHT", text = function(r) return r.secs and X.Clock(r.secs) or "-" end},
}

-- [[ settings ]] each control is filled from X.S() on refresh (binds)
local function boolSetting(key, prices)
	return function() return X.S()[key] end, function(on)
		X.S()[key] = on
		if prices then X.Fire("XNAH_PRICES") end
	end
end

local function buildSettings(p)
	local s = K.Panel(p, RIGHT_W, H, {0, 0, 0, 0.25})
	s:SetPoint("TOPLEFT", RIGHT_X, 0)
	local binds = {}
	p.binds = binds
	local function title(text, y)
		local t = K.Label(s, text, "GameFontNormal")
		t:SetPoint("TOPLEFT", 10, y)
	end
	local function check(x, y, text, get, set, tip)
		local c = K.Check(s, text, function(on) set(on) UI.Refresh(true) end)
		c:SetPoint("TOPLEFT", x, y)
		if tip then K.Tooltip(c, text, tip) end
		binds[#binds + 1] = function() c:SetChecked(get() and true or false) end
		return c
	end
	-- "label [box] after": a number setting, kept between lo and hi
	local function number(y, before, w, key, lo, hi, after, prices, whole)
		local l = K.Label(s, before)
		l:SetPoint("TOPLEFT", 12, y - 4)
		local e = K.Edit(s, w)
		e:SetPoint("LEFT", l, "RIGHT", 10, 0)
		e:SetScript("OnEditFocusLost", function(self)
			local v = tonumber((X.Trim(self:GetText()):gsub("%%", "")))
			if v then
				if whole then v = X.Round(v) end
				v = math.max(lo, math.min(hi, v))
				if v ~= X.S()[key] then
					X.S()[key] = v
					if prices then X.Fire("XNAH_PRICES") end
				end
			end
			self:SetText(tostring(X.S()[key]))
		end)
		local a = K.Label(s, "|cff999999" .. after .. "|r")
		a:SetPoint("LEFT", e, "RIGHT", 4, 0)
		binds[#binds + 1] = function() if not e:HasFocus() then e:SetText(tostring(X.S()[key])) end end
	end

	title("Settings", -8)
	-- price source
	local sl = K.Label(s, "Price used for costs and values:")
	sl:SetPoint("TOPLEFT", 12, -34)
	local source = K.Button(s, "", 160, 22, function(self)
		local items = {}
		for _, key in ipairs(X.SOURCES) do
			items[#items + 1] = {text = X.SOURCE_NAMES[key], checked = X.S().source == key, func = function()
				X.S().source = key
				X.Fire("XNAH_PRICES")
				UI.Refresh(true)
			end}
		end
		K.Menu(self, items)
	end)
	source:SetPoint("LEFT", sl, "RIGHT", 10, 0)
	K.Tooltip(source, "Price used for costs and values",
		"Which price XNAH takes as what an item is worth: for crafting costs, profits, flips and trends.\n" ..
		"Market value: the average of the cheapest listings (one silly price moves it little).\n" ..
		"Lowest price: the single cheapest listing.\nThe averages: steadier, but slow to follow a change.")
	binds[#binds + 1] = function() source:SetText(X.SOURCE_NAMES[X.S().source] or tostring(X.S().source)) end

	number(-60, "Auction house cut:", 40, "cut", 0, 50, "%  (what the auction house keeps of a sale)", true, false)
	number(-86, "Prices count as old after", 45, "staleHours", 1, 720, "hours  (shown dimmed, not used for deals)", true, true)
	number(-112, "Deals and trends need", 35, "minSamples", 1, 30, "days of price history per item", true, true)
	number(-138, "Keep every scan for", 35, "keepScanDays", 1, 60, "days, then one price a day", false, true)
	number(-164, "Keep the daily prices for", 45, "keepDays", 7, 3650, "days", false, true)

	local get, set = boolSetting("vendorBuyFirst", true)
	check(10, -194, "Use vendor prices for crafting reagents", get, set,
		"On: a reagent a vendor sells counts at the vendor price when that is cheaper than the auction house.\n" ..
		"Off: the vendor price only counts when the auction house has no price.")
	get, set = boolSetting("scanOnOpen")
	check(10, -218, "Start a full scan by itself when the auction house opens", get, set,
		"Only when the server allows one (about every 15 minutes).")
	check(10, -242, "Show the XNAH bar on the auction house window", function() return X.S().ahBar end, function(on)
		X.S().ahBar = on
		UI.UpdateAHBar()
	end)
	check(10, -266, "Show the minimap button", function() return not X.S().minimap.hide end, function(on)
		X.S().minimap.hide = not on
		UI.UpdateMinimap()
	end)
	get, set = boolSetting("debug")
	check(10, -290, "Debug messages in chat", get, set)

	title("Item tooltips", -322)
	get, set = boolSetting("tooltip")
	check(10, -344, "Show XNAH prices on item tooltips", get, set)
	get, set = boolSetting("tipVendor")
	check(30, -368, "Vendor prices", get, set)
	get, set = boolSetting("tipCraft")
	check(30, -392, "Crafting cost and profit", get, set)
	get, set = boolSetting("tipHistory")
	check(30, -416, "7-day and 30-day averages, trend", get, set)
	get, set = boolSetting("tipStack")
	check(30, -440, "Stack size next to the XNAH line (prices are for the whole stack)", get, set)
	-- second column: the lines added in v0.2.0
	get, set = boolSetting("tipSpeed")
	check(250, -368, "Sells per day", get, set)
	get, set = boolSetting("tipLedger")
	check(250, -392, "Your own sales and buys", get, set)
	get, set = boolSetting("tipDE")
	check(250, -416, "Disenchant value", get, set)
	-- items you said never to suggest buying (right-click an item): click one to have it suggested again
	local hidden = K.Button(s, "", 260, 22, function(self)
		local items = {{text = "Never suggested as a buy (click to allow again)", isTitle = true}}
		for _, key in ipairs(X.IgnoredList()) do
			items[#items + 1] = {text = X.ItemText(key), func = function() X.SetIgnored(key, false) end}
		end
		if #items == 1 then items[2] = {text = "None - right-click an item: Never suggest buying this", disabled = true} end
		K.Menu(self, items)
	end)
	hidden:SetPoint("TOPLEFT", 10, -470)
	K.Tooltip(hidden, "Items never suggested", "Items you right-clicked and chose Never suggest buying this. Grey items are never " ..
		"suggested as buys anyway (except to sell to a vendor).")
	binds[#binds + 1] = function() hidden:SetText("Never suggested as a buy: " .. #X.IgnoredList()) end
end

-- [[ the mailbox ]] a box under the last scans: the "Open all auction mail" button (Mail.lua) and what it took last
local function updateMailBox(p)
	local b = p.mailBox
	if not b then return end
	b.check:SetChecked(X.S().mailButton and true or false)
	local last = X.MailLast and X.MailLast()
	if last and last.t then
		b.last:SetText("|cff999999Last time (" .. X.Ago(last.t) .. "): " .. (last.text or "") .. "|r")
	else
		b.last:SetText("|cff999999Not used yet.|r")
	end
end

local function buildMailBox(p)
	local b = K.Panel(p, LEFT_W, 86, {0, 0, 0, 0.25})
	b:SetPoint("TOPLEFT", 0, -420)
	p.mailBox = b
	local title = K.Label(b, "Mailbox", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	b.check = K.Check(b, "Show \"Open all auction mail\" at the mailbox", function(on)
		X.S().mailButton = on
		if X.UpdateMailButton then X.UpdateMailButton() end
	end)
	b.check:SetPoint("TOPLEFT", 8, -26)
	K.Tooltip(b.check, "Open all auction mail", "A button next to the game's mail window: it takes the gold and items of " ..
		"every auction house mail (sold, bought, expired, cancelled), one after the other, and stops when your bags are full. " ..
		"Other mails are left alone. Everything is written in the ledger (tab Gold).")
	b.last = K.Label(b, "")
	b.last:SetPoint("TOPLEFT", 10, -60)
	b.last:SetWidth(LEFT_W - 20)
	b.last:SetWordWrap(false)
	-- hourly prices from the PC tool (Api.lua): how fresh they are
	p.api = K.Label(p, "", "GameFontHighlightSmall")
	p.api:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 4, -8)
	p.api:SetWidth(LEFT_W)
	p.api:SetWordWrap(false)
end

X.On("XNAH_MAIL", function()
	local tab = UI.tabs.scan
	if tab and tab.panel and tab.panel:IsShown() then updateMailBox(tab.panel) end
end)

-- guild price sharing and the price export were taken out in v0.7: their saved bits go
X.On("XNAH_LOGIN", function()
	local db = X.db
	if not db then return end
	db.share = nil
	if db.settings then db.settings.share = nil end
	for _, r in pairs(db.realms or {}) do
		if type(r) == "table" then r.sharedFull = nil end
	end
end)

-- [[ the page ]]
local function refresh(p)
	updateScanBox(p)
	for _, f in ipairs(p.binds) do f() end
	local scans = X.Realm().scans
	local rows = {}
	for i = #scans, math.max(1, #scans - 9), -1 do rows[#rows + 1] = scans[i] end
	p.scans:SetRows(rows, "No scans on this realm yet.")
	local items, bytes = X.DataSize()
	updateMailBox(p)
	if p.api then p.api:SetText("|cff999999Hourly prices: |r" .. (X.ApiStatus and X.ApiStatus() or "-")) end
	p.size:SetText("Saved price data: " .. X.Num(items) .. " items (all realms), about " ..
		X.Num(math.max(1, bytes / 1024)) .. " KB")
end

local function build(p)
	buildScanBox(p)
	local st = K.Label(p, "Last 10 scans on this realm", "GameFontNormal")
	st:SetPoint("TOPLEFT", 0, -192)
	p.scans = K.Table(p, LEFT_W, 10 * 18 + 4, SCAN_COLUMNS)
	buildMailBox(p)
	p.scans:SetPoint("TOPLEFT", 0, -228)
	p.size = K.Label(p, "")
	p.size:SetPoint("TOPLEFT", 0, -516)
	p.size:SetWidth(300)
	p.size:SetWordWrap(false)
	local del = K.Button(p, "Delete this realm's data", 160, 22, function()
		local realm = X.realmKey or X.RealmKey()
		X.Confirm("Delete all price data of " .. realm .. "? The price history cannot be brought back.", function()
			X.db.realms[realm] = nil
			X.Realm()
			X.Fire("XNAH_PRICES")
			X.Print("price data of " .. realm .. " deleted")
		end)
	end)
	del:SetPoint("TOPLEFT", LEFT_W - 160, -510)
	buildSettings(p)
end

-- the Settings page has no tab button: the Settings button in the window's title bar opens it
UI.AddTab("scan", "Settings", build, refresh, 10, true)

-- the scan box follows every step of a scan (the window's own refresh waits until the scan is quiet)
X.On("XNAH_SCAN", function()
	local tab = UI.tabs.scan
	if tab and tab.panel and tab.panel:IsShown() then updateScanBox(tab.panel) end
end)

-- [[ minimap button ]] left click: the window; right click: this tab; drag: move it around the minimap
local mm
local function placeMinimap()
	local angle = math.rad(X.S().minimap.angle or 200)
	local r = (Minimap:GetWidth() or 140) / 2 + 5
	mm:ClearAllPoints()
	mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end
function UI.UpdateMinimap()
	if not Minimap then return end
	local S = X.S()
	S.minimap = S.minimap or {angle = 200, hide = false}
	if not mm then
		mm = CreateFrame("Button", "XNAHMinimapButton", Minimap)
		mm:SetSize(31, 31)
		mm:SetFrameStrata("MEDIUM")
		mm:SetFrameLevel(8)
		mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		mm:RegisterForDrag("LeftButton")
		mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
		local bg = mm:CreateTexture(nil, "BACKGROUND")
		bg:SetSize(20, 20)
		bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
		bg:SetPoint("TOPLEFT", 7, -5)
		local icon = mm:CreateTexture(nil, "ARTWORK")
		icon:SetSize(17, 17)
		icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
		icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		icon:SetPoint("TOPLEFT", 7, -6)
		local border = mm:CreateTexture(nil, "OVERLAY")
		border:SetSize(53, 53)
		border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
		border:SetPoint("TOPLEFT")
		mm:SetScript("OnClick", function(_, button)
			if button == "RightButton" then UI.Toggle("scan") else X.Toggle() end
		end)
		mm:SetScript("OnDragStart", function(self)
			self:SetScript("OnUpdate", function()
				local cx, cy = Minimap:GetCenter()
				local scale = Minimap:GetEffectiveScale()
				local x, y = GetCursorPosition()
				X.S().minimap.angle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
				placeMinimap()
			end)
		end)
		mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		K.Tooltip(mm, "XNAH", "Left-click: open / close the window\nRight-click: scans and settings\nDrag: move this button")
	end
	placeMinimap()
	mm:SetShown(not S.minimap.hide)
end
X.On("XNAH_LOGIN", function() UI.UpdateMinimap() end)

-- [[ the bar on the auction house window ]] our own frame (parent UIParent), only anchored to the game's window, so
-- nothing of the game's window is changed
local bar
local function updateBar()
	if not bar or not bar:IsShown() then return end
	bar.full:SetText(fullScanText())
	bar.full:SetEnabled(fullScanAllowed())
	bar.watch:SetEnabled(X.ahOpen == true and X.scan.state == "idle")
	bar.text:SetText(X.scan.text or "|cff999999Full scan: every auction at once.  Watch list: your starred items.|r")
	-- the one-key routine (Routine.lua): what the next press does
	if X.routine and X.routine.state ~= "off" and X.RoutinePeek and X.scan.state == "idle" then
		local peek = X.Try(X.RoutinePeek)
		if peek and peek.text then bar.text:SetText(peek.text) end
	end
end
local function buildBar()
	bar = CreateFrame("Frame", "XNAHAuctionBar", UIParent, "BackdropTemplate")
	bar:SetSize(700, 28)
	bar:SetFrameStrata("HIGH")
	bar:SetClampedToScreen(true)
	K.Backdrop(bar, K.colors.bg)
	local name = K.Label(bar, "|cffe6b422XNAH|r", "GameFontNormal")
	name:SetPoint("LEFT", 8, 0)
	bar.full = K.Button(bar, "Full scan", 120, 22, function() X.FullScan() updateBar() end)
	bar.full:SetPoint("LEFT", 52, 0)
	bar.watch = K.Button(bar, "Watch list", 90, 22, function() X.ScanItems() updateBar() end)
	bar.watch:SetPoint("LEFT", bar.full, "RIGHT", 4, 0)
	K.Tooltip(bar.watch, "Scan the watch list", "Searches your starred items one by one (any time).")
	bar.open = K.Button(bar, "XNAH", 60, 22, function() X.Toggle() end)
	bar.open:SetPoint("LEFT", bar.watch, "RIGHT", 4, 0)
	bar.next = K.Button(bar, "Next step", 90, 22, function() if X.RoutineNext then X.RoutineNext("button") end updateBar() end)
	bar.next:SetPoint("LEFT", bar.open, "RIGHT", 4, 0)
	K.Tooltip(bar.next, "One-key routine", "Each click does the next step: cancel an undercut auction, or post the next " ..
		"ticked item (Sell tab, Worth posting). Your key for it (key bindings, AddOns, XNAH) does the same.")
	bar.text = K.Label(bar, "")
	bar.text:SetPoint("LEFT", bar.next, "RIGHT", 8, 0)
	bar.text:SetPoint("RIGHT", -8, 0)
	bar.text:SetWordWrap(false)
	local acc = 0
	bar:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc >= 1 then
			acc = 0
			updateBar()
		end
	end)
	bar:Hide()
end
-- shows or hides the bar; the auction house window is loaded by the game when it first opens, so it may need a moment
function UI.UpdateAHBar(open, try)
	if open == nil then open = X.ahOpen end
	if not open or not X.S().ahBar then
		if bar then bar:Hide() end
		return
	end
	if not AuctionHouseFrame then
		try = try or 0
		if try < 6 then X.After(0.5, function() if X.ahOpen then UI.UpdateAHBar(true, try + 1) end end) end
		return
	end
	if not bar then buildBar() end
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "TOPLEFT", 0, 2)
	bar:Show()
	updateBar()
end
X.On("XNAH_AH", function(open) UI.UpdateAHBar(open == true) end)
X.On("XNAH_SCAN", updateBar)
X.On("XNAH_ROUTINE", updateBar)
