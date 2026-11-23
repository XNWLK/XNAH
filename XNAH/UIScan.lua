-- The Settings view (key "scan", no view button: the gear in the window's header opens it): scans (start, stop, how
-- far, the last scans), every setting, the size of the saved data. Also here: the minimap button.
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H
local LEFT_W = 500           -- scan box, last scans, saved data
local RIGHT_X = LEFT_W + 10  -- settings
local RIGHT_W = W - RIGHT_X
local SCAN_ROWS = 11         -- rows in the list of the last scans
local WHITE = "Interface\\Buttons\\WHITE8x8"

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
	b.full:SetText(UI.FullScanText())
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
	local b = K.Panel(p, LEFT_W, 170, {0, 0, 0, 0.25})
	b:SetPoint("TOPLEFT", 0, 0)
	p.scanBox = b
	local title = K.Label(b, "Auction house scan", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	b.status = K.Label(b, "")
	b.status:SetPoint("TOPLEFT", 10, -28)
	b.status:SetWidth(LEFT_W - 20)
	local help = K.Label(b, "Full scan: every auction at once (the server allows one about every 15 minutes). " ..
		"Tracked items: searches the items on your tracked list one by one, any time.")
	help:SetPoint("TOPLEFT", 10, -44)
	help:SetWidth(LEFT_W - 20)
	help:SetWordWrap(true)
	b.full = K.Button(b, "Full scan", 150, 22, function() X.FullScan() updateScanBox(p) end)
	b.full:SetPoint("TOPLEFT", 10, -72)
	b.watch = K.Button(b, "Scan tracked items", 140, 22, function() X.ScanItems() updateScanBox(p) end)
	b.watch:SetPoint("LEFT", b.full, "RIGHT", 6, 0)
	b.stop = K.Button(b, "Stop", 70, 22, function() X.ScanStop("stopped") updateScanBox(p) end)
	b.stop:SetPoint("LEFT", b.watch, "RIGHT", 6, 0)
	-- progress bar
	local bar = CreateFrame("StatusBar", nil, b)
	bar:SetSize(LEFT_W - 20, 16)
	bar:SetPoint("TOPLEFT", 10, -102)
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
	b.text:SetPoint("TOPLEFT", 10, -126)
	b.text:SetWidth(LEFT_W - 20)
	b.text:SetWordWrap(false)
	b.last = K.Label(b, "")
	b.last:SetPoint("TOPLEFT", 10, -146)
	b.last:SetWidth(LEFT_W - 20)
	b.last:SetWordWrap(false)
	-- the countdown and the bar move every second while the view is shown
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
	{"When", 140, "LEFT", text = function(r) return X.Date(r.t, "%b %d  %H:%M") end},
	{"Kind", 130, "LEFT", text = function(r) return tostring(r.kind or "-") end},
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

-- the controls of the settings box: check boxes and number boxes, each filled again on refresh
local function controls(s, binds)
	local c = {}
	function c.title(text, y)
		local t = K.Label(s, text, "GameFontNormal")
		t:SetPoint("TOPLEFT", 10, y)
	end
	function c.check(x, y, text, get, set, tip)
		local box = K.Check(s, text, function(on) set(on) UI.Refresh(true) end)
		box:SetPoint("TOPLEFT", x, y)
		if tip then K.Tooltip(box, text, tip) end
		binds[#binds + 1] = function() box:SetChecked(get() and true or false) end
		return box
	end
	-- "label [box] after": a number setting, kept between lo and hi
	function c.number(y, before, w, key, lo, hi, after, prices, whole)
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
	-- the same for an amount of money ("10s", "1g 50s"; a bare number = gold)
	function c.money(x, y, before, w, key, after)
		local l = K.Label(s, before)
		l:SetPoint("TOPLEFT", x, y - 4)
		local e = K.Edit(s, w)
		e:SetPoint("LEFT", l, "RIGHT", 10, 0)
		e:SetScript("OnEditFocusLost", function(self)
			local v = X.ParseMoney(self:GetText())
			if v and v >= 0 and v ~= X.S()[key] then
				X.S()[key] = v
				X.Fire("XNAH_PRICES")
			end
			self:SetText(X.MoneyPlain(X.S()[key]))
		end)
		local a = K.Label(s, "|cff999999" .. after .. "|r")
		a:SetPoint("LEFT", e, "RIGHT", 4, 0)
		binds[#binds + 1] = function() if not e:HasFocus() then e:SetText(X.MoneyPlain(X.S()[key])) end end
	end
	return c
end

-- [[ Opportunities ]] what counts as "far under usual" (the Opportunities view)
local function buildDealSettings(p)
	local box = K.Panel(p, LEFT_W, 88, {0, 0, 0, 0.25})
	box:SetPoint("TOPLEFT", 0, -H + 150)
	local c = controls(box, p.binds)
	c.title("Opportunities", -8)
	local function pct(y)
		local l = K.Label(box, "Far under usual: at most")
		l:SetPoint("TOPLEFT", 12, y - 4)
		local e = K.Edit(box, 40)
		e:SetPoint("LEFT", l, "RIGHT", 10, 0)
		e:SetScript("OnEditFocusLost", function(self)
			local v = tonumber((X.Trim(self:GetText()):gsub("%%", "")))
			if v then
				v = math.max(1, math.min(100, X.Round(v)))
				if v ~= X.S().dealPct then
					X.S().dealPct = v
					X.Fire("XNAH_PRICES")
				end
			end
			self:SetText(tostring(X.S().dealPct))
		end)
		local a = K.Label(box, "|cff999999% of the usual price|r")
		a:SetPoint("LEFT", e, "RIGHT", 4, 0)
		p.binds[#p.binds + 1] = function() if not e:HasFocus() then e:SetText(tostring(X.S().dealPct)) end end
	end
	pct(-32)
	c.money(12, -58, "Least profit after the cut:", 90, "dealMinProfit", "(e.g. 10s or 1g 50s)")
end

-- prices and how long they are kept
local function buildPriceSettings(s, binds, c)
	c.title("Settings", -8)
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
	c.number(-60, "Auction house cut:", 40, "cut", 0, 50, "%  (what the auction house keeps of a sale)", true, false)
	c.number(-86, "Prices count as old after", 45, "staleHours", 1, 720, "hours  (shown dimmed, not used for deals)", true, true)
	c.number(-112, "Deals and trends need", 35, "minSamples", 1, 30, "days of price history per item", true, true)
	c.number(-138, "Keep every scan for", 35, "keepScanDays", 1, 60, "days, then one price a day", false, true)
	c.number(-164, "Keep the daily prices for", 45, "keepDays", 7, 3650, "days", false, true)
end

-- the window, the auction house, the minimap button and the rest
local function buildWindowSettings(s, c)
	local get, set = boolSetting("vendorBuyFirst", true)
	c.check(10, -194, "Use vendor prices for crafting reagents", get, set,
		"On: a reagent a vendor sells counts at the vendor price when that is cheaper than the auction house.\n" ..
		"Off: the vendor price only counts when the auction house has no price.")
	get, set = boolSetting("scanOnOpen")
	c.check(10, -218, "Start a full scan by itself when the auction house opens", get, set,
		"Only when the server allows one (about every 15 minutes).")
	get, set = boolSetting("openWithAH")
	c.check(10, -242, "Open with the auction house", get, set,
		"XNAH's window opens by itself beside the auction house window (and closes with it). Opened by hand, it stays.")
	c.check(10, -266, "Extra columns in the auction house lists", function() return X.S().ahColumns end, function(on)
		X.S().ahColumns = on
		if X.AHPanel then X.AHPanel.FillLists() end
	end, "Adds \"% usual\" (the price now against XNAH's usual price: green = cheaper, red = dearer) and \"a day\" " ..
		"(how many sell a day) to the game's auction house lists.")
	c.check(10, -290, "Show the minimap button", function() return not X.S().minimap.hide end, function(on)
		X.S().minimap.hide = not on
		UI.UpdateMinimap()
	end)
	c.check(10, -314, "All my characters are on one realm", function() return X.S().oneRealm end, function(on)
		X.S().oneRealm = on
		if on and X.CheckRealm then X.CheckRealm() end
	end, "On: XNAH keeps one set of prices, whatever realm number the game gives (it is not always the same). " ..
		"Prices kept under other realm numbers are joined in. Off: a set per realm (for characters on several realms).")
	get, set = boolSetting("awayLine")
	c.check(10, -338, "Welcome back lines", get, set,
		"A chat line when you log in after a while (your auctions that ran out, gold in mailboxes) and at the mailbox " ..
		"(what sold, came back or was bought since you were last there).")
	get, set = boolSetting("debug")
	c.check(290, -338, "Debug messages in chat", get, set)
end

-- the lines XNAH adds to item tooltips, alt-click, items never suggested
local function buildTipSettings(s, binds, c)
	c.title("Item tooltips", -372)
	local get, set = boolSetting("tooltip")
	c.check(10, -394, "Show XNAH prices on item tooltips", get, set)
	get, set = boolSetting("tipVendor")
	c.check(30, -418, "Vendor prices", get, set)
	get, set = boolSetting("tipCraft")
	c.check(30, -442, "Crafting cost and profit", get, set)
	get, set = boolSetting("tipHistory")
	c.check(30, -466, "7-day and 30-day averages, trend", get, set)
	get, set = boolSetting("tipStack")
	c.check(30, -490, "Stack size next to the XNAH line (prices are for the whole stack)", get, set)
	get, set = boolSetting("tipSpeed")
	c.check(290, -418, "Sells per day", get, set)
	get, set = boolSetting("tipLedger")
	c.check(290, -442, "Your own sales and buys", get, set)
	get, set = boolSetting("tipDE")
	c.check(290, -466, "Disenchant value", get, set)
	get, set = boolSetting("quickAltClick")
	c.check(10, -524, "Alt-click an item (bags, chat, loot) to show it in XNAH", get, set)
	-- items you said never to suggest buying (right-click an item): click one to have it suggested again
	local hidden = K.Button(s, "", 260, 22, function(self)
		local items = {{text = "Never suggested as a buy (click to allow again)", isTitle = true}}
		for _, key in ipairs(X.IgnoredList()) do
			items[#items + 1] = {text = X.ItemText(key), func = function() X.SetIgnored(key, false) end}
		end
		if #items == 1 then items[2] = {text = "None - right-click an item: Never suggest buying this", disabled = true} end
		K.Menu(self, items)
	end)
	hidden:SetPoint("TOPLEFT", 10, -558)
	K.Tooltip(hidden, "Items never suggested", "Items you right-clicked and chose Never suggest buying this. Grey items are never " ..
		"suggested as buys anyway (except to sell to a vendor).")
	binds[#binds + 1] = function() hidden:SetText("Never suggested as a buy: " .. #X.IgnoredList()) end
end

local function buildSettings(p)
	local s = K.Panel(p, RIGHT_W, H, {0, 0, 0, 0.25})
	s:SetPoint("TOPLEFT", RIGHT_X, 0)
	local binds = {}
	p.binds = binds
	local c = controls(s, binds)
	buildPriceSettings(s, binds, c)
	buildWindowSettings(s, c)
	buildTipSettings(s, binds, c)
end

-- guild price sharing and the price export were taken out in v0.7: their saved bits go
X.On("XNAH_LOGIN", function()
	local db = X.db
	if not db then return end
	db.share = nil
	if db.settings then
		db.settings.share = nil
		db.settings.ahPanel = nil -- the panel beside the auction house window (v0.9: the big window docks there instead)
	end
	for _, r in pairs(db.realms or {}) do
		if type(r) == "table" then r.sharedFull = nil end
	end
end)

-- [[ the view ]]
local function refresh(p)
	updateScanBox(p)
	for _, f in ipairs(p.binds) do f() end
	local scans = X.Realm().scans
	local rows = {}
	for i = #scans, math.max(1, #scans - SCAN_ROWS + 1), -1 do rows[#rows + 1] = scans[i] end
	p.scans:SetRows(rows, "No scans on this realm yet.")
	local items, bytes = X.DataSize()
	p.size:SetText("Saved price data: " .. X.Num(items) .. " items (all realms), about " ..
		X.Num(math.max(1, bytes / 1024)) .. " KB")
end

local function build(p)
	buildScanBox(p)
	local st = K.Label(p, "The last scans on this realm", "GameFontNormal")
	st:SetPoint("TOPLEFT", 0, -182)
	p.scans = K.Table(p, LEFT_W, SCAN_ROWS * 18 + 4, SCAN_COLUMNS)
	p.scans:SetPoint("TOPLEFT", 0, -216)
	p.size = K.Label(p, "")
	p.size:SetPoint("TOPLEFT", 0, -H + 34)
	p.size:SetWidth(LEFT_W - 180)
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
	del:SetPoint("TOPLEFT", LEFT_W - 160, -H + 40)
	buildSettings(p)
	buildDealSettings(p)
end

-- the Settings view has no view button: the gear in the window's header opens it
UI.AddTab("scan", "Settings", build, refresh, 10, true)

-- the scan box follows every step of a scan (the window's own refresh waits until the scan is quiet)
X.On("XNAH_SCAN", function()
	local tab = UI.tabs.scan
	if tab and tab.panel and tab.panel:IsShown() then updateScanBox(tab.panel) end
end)

-- [[ minimap button ]] left click: the window; right click: the settings; drag: move it around the minimap
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
