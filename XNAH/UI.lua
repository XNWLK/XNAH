-- The XNAH window: one big window with views (Items, Market, Your gold, Opportunities; Settings from the gear), chosen
-- with the buttons in its header. It docks beside the game's auction house window when that opens, and /xnah, the
-- minimap button or the key binding open it anywhere. Also here: shared pieces for the views (a sortable table, item
-- cells, the right-click item menu, a yes / no question).
-- Each view lives in its own file and registers itself with UI.AddTab; this file is loaded before them.
local ADDON, X = ...
local K = X.K
local UI = {tabs = {}, order = {}}
X.UI = UI

-- the content area of every view (views use these fixed sizes; the window only changes size through its scale)
UI.W, UI.H = 1080, 600
local HEAD = 40                       -- the header row
local FW, FH = UI.W + 20, UI.H + HEAD + 10 -- the whole window (1100 x 650)
UI.FW, UI.FH = FW, FH

-- window size: the whole window (text included) is drawn bigger or smaller; drag the corner, or /xnah size 120
X.Default("uiScale", 1)
X.Default("sorts", {}) -- each table's sort column, per view ("market:1" = {column, descending})
X.Default("openWithAH", true) -- the window opens by itself beside the auction house
local MIN_SCALE, MAX_SCALE = 0.6, 1.6
local DOCK_MIN = 0.6 -- docked beside the auction house: never drawn smaller than this

-- a view: build(panel) once, refresh(panel) whenever something changed while it is shown. hidden = true: no button in
-- the header (Settings opens from the gear button)
function UI.AddTab(key, title, build, refresh, order, hidden)
	UI.tabs[key] = {key = key, title = title, build = build, refresh = refresh, n = order or (#UI.order + 1), hidden = hidden}
	UI.order[#UI.order + 1] = key
	table.sort(UI.order, function(a, b) return UI.tabs[a].n < UI.tabs[b].n end)
end

-- views that were joined into others or renamed: old names still open the right one
UI.ALIASES = {item = "items", trends = "market", ledger = "gold", wealth = "gold", settings = "scan", deals = "opps"}
-- and the part of the new view they open (a setting the view reads when it is shown)
UI.ALIAS_VIEWS = {ledger = {"goldView", "items"}, wealth = {"goldView", "chars"}}

-- the view an old or current name opens
function UI.TabKey(key)
	if key and not UI.tabs[key] and UI.ALIASES[key] then return UI.ALIASES[key] end
	return key
end

local frame
local docked, byAH, ahWasOpen = false, false, false
local function selectTab(key)
	if not UI.tabs[key] and UI.ALIASES[key] then
		local v = UI.ALIAS_VIEWS[key]
		if v then X.S()[v[1]] = v[2] end
		key = UI.ALIASES[key]
	end
	if not UI.tabs[key] then key = UI.order[1] end
	UI.current = key
	for _, k in ipairs(UI.order) do
		local tab = UI.tabs[k]
		local on = k == key
		if tab.button then tab.button:SetSelected(on) end
		if on and not tab.panel then
			tab.panel = CreateFrame("Frame", nil, frame.content)
			tab.panel:SetAllPoints(frame.content)
			UI.building, UI.tableCount = k, 0 -- tables made while building remember their sorting under this view
			local ok, err = pcall(tab.build, tab.panel)
			UI.building = nil
			if not ok then X.OnError(err) end
		end
		if tab.panel then tab.panel:SetShown(on) end
	end
	if frame.gear then frame.gear:SetAlpha(key == "scan" and 1 or 0.75) end
	X.S().tab = key
	UI.Refresh(true)
end
UI.Select = selectTab

-- [[ the header: scan status and the two scan buttons ]]
local function fullScanText()
	local left = X.FullScanLeft()
	if left > 0 then return "Ready in " .. X.Clock(left) end
	return "Full scan"
end
UI.FullScanText = fullScanText
local function itemCount()
	local n = 0
	for _ in pairs(X.Items()) do n = n + 1 end
	return n
end
-- "Full scan 12m ago, 12,345 items" or what the scan is doing now
function UI.ScanStatus()
	local s = X.scan
	if s.state ~= "idle" then
		local text = s.text or "Scanning ..."
		if (s.total or 0) > 0 then text = text .. "  (" .. math.floor(math.min(s.done or 0, s.total) / s.total * 100 + 0.5) .. "%)" end
		return "|cffffd100" .. text .. "|r"
	end
	return "|cff999999Full scan " .. X.Ago(X.Realm().lastFull) .. ", " .. X.Num(itemCount()) .. " items|r"
end
local function updateHeader()
	if not frame or not frame:IsShown() then return end
	local idle = X.scan.state == "idle"
	frame.status:SetText(UI.ScanStatus())
	frame.full:SetText(fullScanText())
	frame.full:SetEnabled(X.ahOpen == true and X.FullScanReady())
	frame.tracked:SetEnabled(X.ahOpen == true and idle)
	-- the countdown on the Full scan button moves every second (only while there is one to show)
	frame.ticker:SetShown(X.ahOpen == true and X.FullScanLeft() > 0)
end
UI.UpdateHeader = updateHeader

function UI.Refresh(now)
	if not frame or not frame:IsShown() then return end
	local function run()
		updateHeader()
		local tab = UI.tabs[UI.current]
		if tab and tab.panel and tab.refresh then
			local ok, err = pcall(tab.refresh, tab.panel)
			if not ok then X.OnError(err) end
		end
	end
	if now then run() else X.Debounce("ui", 0.2, run) end
end
for _, e in ipairs({"XNAH_PRICES", "XNAH_SCAN", "XNAH_RECIPES", "XNAH_WATCH", "XNAH_AH", "XNAH_ANALYSIS", "XNAH_LEDGER",
	"XNAH_INVENTORY", "XNAH_IGNORE"}) do
	X.On(e, function() UI.Refresh() end)
end
-- the scan status follows every step of a scan (the views wait until the scan is quiet)
X.On("XNAH_SCAN", function() updateHeader() end)

-- [[ docking beside the auction house window ]]
-- the game's auction house window while it is shown
local function ahWindow()
	local f = AuctionHouseFrame
	if type(f) == "table" and f.IsShown and X.Try(f.IsShown, f) then return f end
	return nil
end
-- the scale at which the window fits right of the auction house window (and below its top): the size you picked, made
-- smaller when there is not room enough, never under DOCK_MIN
function UI.DockScale(ah)
	local want = UI.ClampScale(X.S().uiScale)
	local ui = UIParent
	local ues = X.Try(ui.GetEffectiveScale, ui) or 1
	local aes = X.Try(ah.GetEffectiveScale, ah) or ues
	local screenR, screenB = X.Try(ui.GetRight, ui), X.Try(ui.GetBottom, ui) or 0
	local ahR, ahT = X.Try(ah.GetRight, ah), X.Try(ah.GetTop, ah)
	if type(screenR) == "number" and type(ahR) == "number" and ues > 0 then
		local fitW = (screenR * ues - ahR * aes - 4 * aes) / (FW * ues)
		if fitW > 0 then want = math.min(want, fitW) end
	end
	if type(ahT) == "number" and ues > 0 then
		local fitH = (ahT * aes - screenB * ues) / (FH * ues)
		if fitH > 0 then want = math.min(want, fitH) end
	end
	return math.max(DOCK_MIN, want)
end
-- beside the auction house window when it is open, else on its own saved spot (where it can be moved)
function UI.Place()
	if not frame then return end
	local ah = X.ahOpen and ahWindow()
	frame:ClearAllPoints()
	if ah then
		docked = true
		frame:SetScale(UI.DockScale(ah))
		frame:SetPoint("TOPLEFT", ah, "TOPRIGHT", 2, 0)
	else
		docked = false
		frame:SetScale(UI.ClampScale(X.S().uiScale))
		local pos = X.S().window
		if pos and pos[1] then frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else frame:SetPoint("CENTER") end
	end
end
function UI.Docked() return docked end
function UI.OpenedByAH() return byAH end

local build
-- the auction house window came or went (AHPanel.lua and the XNAH_AH message call this): opens the window beside it
-- (setting "Open with the auction house"); a window the auction house opened closes with it, one you opened stays
-- and goes back to its own spot
function UI.AuctionWindow()
	local open = X.ahOpen == true and ahWindow() ~= nil
	local was = ahWasOpen
	ahWasOpen = open
	if open and not was then
		if not frame then build() end
		if X.S().openWithAH and not frame:IsShown() then
			frame:Show()
			byAH = true
			selectTab(UI.current or X.S().tab or "items")
		end
	elseif not open and was and frame and byAH then
		byAH = false
		frame:Hide()
	end
	if frame and frame:IsShown() then UI.Place() end
end
X.On("XNAH_AH", function() UI.AuctionWindow() end)

-- [[ the window ]]
-- a small square button with an icon (the gear)
local function iconButton(parent, icon, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b:SetNormalTexture(icon)
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
	return b
end

local function buildHeader()
	frame.title = K.Label(frame, "|cffe6b422XNAH|r", "GameFontNormalLarge")
	frame.title:SetPoint("TOPLEFT", 12, -12)
	-- the view buttons
	local x, last = 62, nil
	for _, key in ipairs(UI.order) do
		local tab = UI.tabs[key]
		if not tab.hidden then
			local w = math.max(60, #tab.title * 7 + 20)
			local b = K.Flat(frame, w, 24)
			b:SetPoint("TOPLEFT", x, -9)
			b:SetLabel(tab.title)
			b.label:SetJustifyH("CENTER")
			b:SetScript("OnClick", function() selectTab(key) end)
			tab.button = b
			x = x + w + 3
			last = b
		end
	end
	-- right side: close, gear (Settings), Find, Scan tracked, Full scan
	local close = K.Button(frame, "X", 24, 22, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -9)
	K.Tooltip(close, "Close", "Escape closes it too.")
	local gear = iconButton(frame, "Interface\\Icons\\INV_Misc_Gear_01", 22)
	gear:SetPoint("RIGHT", close, "LEFT", -6, 0)
	gear:SetScript("OnClick", function() selectTab("scan") end)
	K.Tooltip(gear, "Settings", "Scans, prices, tooltips and the other settings.")
	frame.gear = gear
	local anchor = gear
	if UI.QuickSearchBox then
		local box = UI.QuickSearchBox(frame)
		box:SetPoint("RIGHT", gear, "LEFT", -10, 0)
		local findLabel = K.Label(frame, "Find", "GameFontNormalSmall", "RIGHT")
		findLabel:SetPoint("RIGHT", box, "LEFT", -8, 0)
		anchor = findLabel
	end
	frame.tracked = K.Button(frame, "Scan tracked", 96, 22, function() X.ScanItems() updateHeader() end)
	frame.tracked:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
	K.Tooltip(frame.tracked, "Scan tracked items", "Searches every item on your tracked list one by one, any time the " ..
		"auction house is open.")
	frame.full = K.Button(frame, "Full scan", 100, 22, function() X.FullScan() updateHeader() end)
	frame.full:SetPoint("RIGHT", frame.tracked, "LEFT", -4, 0)
	K.Tooltip(frame.full, "Full scan", "Reads every auction at once (the auction house must be open). The server allows " ..
		"one about every 15 minutes.")
	-- the scan line between the view buttons and the scan buttons
	frame.status = K.Label(frame, "", "GameFontHighlightSmall")
	frame.status:SetPoint("LEFT", last or frame.title, "RIGHT", 12, 0)
	frame.status:SetPoint("RIGHT", frame.full, "LEFT", -8, 0)
	frame.status:SetWordWrap(false)
	-- the Full scan countdown, once a second while it runs
	local ticker = CreateFrame("Frame", nil, frame)
	local acc = 0
	ticker:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc >= 1 then
			acc = 0
			updateHeader()
		end
	end)
	ticker:Hide()
	frame.ticker = ticker
end

-- the size grip in the bottom right corner: drag = bigger / smaller, right-click = normal size
local function buildGrip()
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
	grip:SetFrameLevel((frame:GetFrameLevel() or 1) + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	grip:SetScript("OnMouseDown", function(self, button)
		if button ~= "LeftButton" then return end
		local s = frame:GetScale()
		local left, top = frame:GetLeft() * s, frame:GetTop() * s
		local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
		local width = frame:GetWidth() * s
		self:SetScript("OnUpdate", function()
			local x = GetCursorPosition() / UIParent:GetEffectiveScale()
			UI.SetScale((width + x - cx) / frame:GetWidth(), left, top)
		end)
	end)
	grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	grip:SetScript("OnClick", function(_, button) if button == "RightButton" then UI.SetScale(1) end end)
	K.Tooltip(grip, "Window size", "Drag to make the window (and its text) bigger or smaller. Right-click: normal size. " ..
		"Also: /xnah size 120. Beside the auction house it is made smaller when the screen has not room enough.")
	frame.grip = grip
end

build = function()
	frame = CreateFrame("Frame", "XNAHFrame", UIParent, "BackdropTemplate")
	frame:SetSize(FW, FH)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	K.Backdrop(frame, K.colors.bg)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	-- moved by dragging only when it is not docked beside the auction house
	frame:SetScript("OnDragStart", function(self) if not docked then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if docked then return end
		local p, _, rp, x, y = self:GetPoint()
		X.S().window = {p, rp, x, y}
	end)
	frame:SetScale(UI.ClampScale(X.S().uiScale))
	local pos = X.S().window
	if pos and pos[1] then frame:ClearAllPoints() frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end
	tinsert(UISpecialFrames, "XNAHFrame")
	frame:SetScript("OnHide", function() K.CloseMenu() byAH, docked = false, false end)
	frame:SetScript("OnShow", function() UI.Place() UI.Refresh(true) end)
	buildHeader()
	buildGrip()
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", 10, -HEAD)
	frame.content:SetSize(UI.W, UI.H)
	frame:Hide()
end
UI.Frame = function() return frame end

function UI.ClampScale(s)
	s = tonumber(s) or 1
	return math.max(MIN_SCALE, math.min(MAX_SCALE, s))
end
-- sets the window size (1 = normal); the top left corner stays where it is (left / top in the screen's units). Docked
-- beside the auction house, the size is kept for later and the window is fitted again.
function UI.SetScale(s, left, top)
	s = UI.ClampScale(s)
	X.S().uiScale = math.floor(s * 100 + 0.5) / 100
	if not frame then return end
	if docked then UI.Place() return end
	local old = frame:GetScale()
	left = left or (frame:GetLeft() and frame:GetLeft() * old)
	top = top or (frame:GetTop() and frame:GetTop() * old)
	frame:SetScale(X.S().uiScale)
	if left and top then
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / X.S().uiScale, top / X.S().uiScale)
		X.S().window = {"TOPLEFT", "BOTTOMLEFT", left / X.S().uiScale, top / X.S().uiScale}
	end
end

-- opening it yourself (not by the auction house): it stays when the auction house closes
local function show()
	if not frame then build() end
	if not frame:IsShown() then
		frame:Show()
		byAH = false
	end
end
function UI.Toggle(tab)
	if frame and frame:IsShown() and (not tab or UI.TabKey(tab) == UI.current) then frame:Hide() return end
	show()
	selectTab(tab or UI.current or X.S().tab or "items")
end
function UI.Open(tab)
	show()
	selectTab(tab or UI.current or X.S().tab or "items")
end
X.Toggle = function() UI.Toggle() end

-- [[ shared bits for the views ]]
-- shows an item ("2589" or "15210:-19") on the Items view (also an item that is not tracked)
function UI.ShowItem(key)
	if not key then return end
	UI.itemKey = key
	UI.history = UI.history or {}
	if UI.history[#UI.history] ~= key then UI.history[#UI.history + 1] = key end
	UI.Open("items")
end
X.ShowItem = UI.ShowItem
-- an item picked in the game's auction house window: shown when the window is open, else kept for when it opens
function UI.FollowItem(key)
	if not key then return end
	if frame and frame:IsShown() then
		if key ~= UI.itemKey or UI.current ~= "items" then UI.ShowItem(key) end
	else
		UI.itemKey = key
	end
end

-- "[icon] Name" in the item's quality colour; a star in front when tracked
function UI.ItemCell(key, size)
	local star = X.Watched(key) and "|cffffd100*|r " or ""
	return star .. X.ItemIcon(X.KeyID(key), size or 14) .. " " .. X.ItemText(key)
end
-- money cell; dimmed when the price is old
function UI.MoneyCell(copper, stale)
	if copper == nil then return "|cff666666-|r" end
	local text = X.Money(copper, true)
	if stale then text = "|cff777777" .. X.MoneyPlain(copper) .. "|r" end
	return text
end
-- shows the game's tooltip for an item next to a frame (with XNAH's lines)
function UI.ItemTooltip(owner, key)
	local id = X.KeyID(key)
	if not id then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	local suffix = tostring(key):match(":(%-?%d+)$")
	if GameTooltip.SetHyperlink then
		GameTooltip:SetHyperlink("item:" .. id .. (suffix and ("::::::" .. suffix) or ""))
	end
	GameTooltip:Show()
end
-- double-click on an item in a list: the game's own auction house window shows it too (its listings page, with its name
-- in the game's search box), so you can buy or sell it there with the game's own buttons. Only while that window is open.
function UI.ShowInAuctionHouse(key)
	if not key then return false end
	local f = AuctionHouseFrame
	if not (X.ahOpen and type(f) == "table" and f.IsShown and X.Try(f.IsShown, f)) then
		X.Print("open the auction house first, then double-click again.")
		return false
	end
	return X.Try(X.ShowOnAuctionHouse, key) and true or false
end
-- right-click menu on an item row: show it, track / stop tracking, search on the auction house, never suggest
function UI.ItemMenu(anchor, key)
	local items = {
		{text = X.ItemText(key), isTitle = true},
		{text = "Show it", func = function() UI.ShowItem(key) end},
		{text = X.Watched(key) and "Stop tracking" or "Track this item", func = function() X.SetWatched(key, not X.Watched(key)) end},
	}
	if X.ahOpen then
		items[#items + 1] = {text = "Search on the auction house now", func = function()
			X.ShowOnAuctionHouse(key)
			X.ScanItems({key}, "one item")
		end}
	end
	if X.Ignored(key) then
		items[#items + 1] = {text = "Suggest buying it again", func = function() X.SetIgnored(key, false) end}
	else
		items[#items + 1] = {text = "Never suggest buying this", func = function()
			X.SetIgnored(key, true)
			X.Print(X.ItemText(key) .. " will not be suggested as a buy again (right-click it: Suggest buying it again).")
		end}
	end
	local tbl = UI.menuTable
	if tbl and tbl.ShowAsText then
		items[#items + 1] = {text = "Copy this list as text", func = function() tbl:ShowAsText() end}
	end
	K.Menu(anchor, items)
end

-- [[ sortable table ]] K.Table(parent, w, h, columns, onClick, onDoubleClick, doubleClickTip)
-- columns = {{title, width, justify, text = function(row) -> string, sort = function(row) -> number or string}, ...}
-- tbl:SetRows(rows, emptyText); clicking a header sorts by it (again: the other way); clicking a row: onClick(row, button,
-- rowFrame). Rows with row.key get the item tooltip on hover. Optional: a left double-click on a row runs
-- onDoubleClick(row, rowFrame) (the game runs the row's click for the first press, the double-click for the second),
-- and doubleClickTip is a grey line added to the row's item tooltip. Tables without them are unchanged.
function K.Table(parent, w, h, columns, onClick, onDoubleClick, doubleClickTip)
	local cols = {}
	for i, c in ipairs(columns) do cols[i] = {c[1], c[2], c[3]} end
	local tbl
	local list = K.List(parent, w, h, 18, function(rowFrame, row)
		local texts = {}
		for i, c in ipairs(columns) do
			local ok, t = pcall(c.text, row)
			texts[i] = ok and t or "?"
		end
		rowFrame:SetCols(unpack(texts))
		rowFrame:SetScript("OnClick", function(self, button)
			-- a right-click menu opened from here offers "copy this list"
			UI.menuTable = tbl
			if onClick then
				local ok, err = pcall(onClick, row, button, self)
				if not ok then X.OnError(err) end
			end
			UI.menuTable = nil
		end)
		if tbl.onDoubleClick then
			rowFrame:SetScript("OnDoubleClick", function(self, button)
				if button ~= "LeftButton" then return end
				local ok, err = pcall(tbl.onDoubleClick, row, self)
				if not ok then X.OnError(err) end
			end)
		end
		if row.key then
			rowFrame:SetScript("OnEnter", function(self)
				UI.ItemTooltip(self, row.key)
				if tbl.doubleClickTip and X.KeyID(row.key) then -- (the item tooltip was shown)
					GameTooltip:AddLine(tbl.doubleClickTip, 0.6, 0.6, 0.6, true)
					GameTooltip:Show()
				end
			end)
			rowFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
		else
			rowFrame:SetScript("OnEnter", nil)
			rowFrame:SetScript("OnLeave", nil)
		end
	end, cols)
	tbl = list
	tbl.columns = columns
	tbl.onDoubleClick, tbl.doubleClickTip = onDoubleClick, doubleClickTip
	tbl.sortCol, tbl.sortDesc = nil, true
	-- the sorting you pick is remembered per view (tables made while a view is built: "market:1", "market:2", ...)
	if UI.building then
		UI.tableCount = (UI.tableCount or 0) + 1
		tbl.saveKey = UI.building .. ":" .. UI.tableCount
		local saved = X.S().sorts[tbl.saveKey]
		if saved and columns[saved[1]] and columns[saved[1]].sort then
			tbl.sortCol, tbl.sortDesc, tbl.savedSort = saved[1], saved[2] and true or false, true
		end
	end
	-- headers become buttons: click = sort, right-click = copy this list
	for i, hdr in ipairs(list.headers or {}) do
		local c = columns[i]
		local b = CreateFrame("Button", nil, list)
		b:SetAllPoints(hdr)
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				K.Menu(self, {{text = "This list", isTitle = true}, {text = "Copy this list as text", func = function() tbl:ShowAsText() end}})
				return
			end
			if not c.sort then return end
			if tbl.sortCol == i then tbl.sortDesc = not tbl.sortDesc else tbl.sortCol, tbl.sortDesc = i, c.desc ~= false end
			if tbl.saveKey then X.S().sorts[tbl.saveKey] = {tbl.sortCol, tbl.sortDesc} end
			tbl:Sort()
		end)
	end
	-- the list as plain text, one row a line, columns split by tabs (pastes into a spreadsheet)
	local function plain(t)
		t = tostring(t or "")
		t = t:gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		return X.Trim(t)
	end
	function tbl:AsText(maxRows)
		maxRows = maxRows or 2000
		local lines, head = {}, {}
		for i, c in ipairs(self.columns) do head[i] = c[1] end
		lines[1] = table.concat(head, "\t")
		for r = 1, math.min(#self.items, maxRows) do
			local row, cells = self.items[r], {}
			for i, c in ipairs(self.columns) do
				local ok, v = pcall(c.text, row)
				cells[i] = plain(ok and v or "")
			end
			lines[#lines + 1] = table.concat(cells, "\t")
		end
		if #self.items > maxRows then lines[#lines + 1] = "(first " .. maxRows .. " of " .. #self.items .. " rows)" end
		return table.concat(lines, "\n"), math.min(#self.items, maxRows)
	end
	function tbl:ShowAsText()
		local text, n = self:AsText()
		K.ShowText("This list (" .. n .. " rows, columns split by tabs)", text)
	end
	function tbl:Sort()
		local c = self.sortCol and self.columns[self.sortCol]
		for i, hdr in ipairs(self.headers or {}) do
			local mark = (i == self.sortCol) and (self.sortDesc and " v" or " ^") or ""
			hdr:SetText("|cff999999" .. self.columns[i][1] .. mark .. "|r")
		end
		if c and c.sort then
			local desc = self.sortDesc
			local vals = {}
			for _, row in ipairs(self.items) do
				local ok, v = pcall(c.sort, row)
				vals[row] = ok and v or nil
			end
			table.sort(self.items, function(a, b)
				local va, vb = vals[a], vals[b]
				if va == nil and vb == nil then return false end
				if va == nil then return false end
				if vb == nil then return true end
				if type(va) ~= type(vb) then va, vb = tostring(va), tostring(vb) end
				if desc then return va > vb end
				return va < vb
			end)
		end
		self:Refresh()
	end
	function tbl:SetRows(rows, emptyText)
		self.items = rows or {}
		self.empty:SetText(emptyText or "")
		self:Sort()
	end
	-- sort by column i at the start
	function tbl:SortBy(i, desc)
		if self.savedSort then return end -- the sorting you picked last time wins
		self.sortCol, self.sortDesc = i, desc ~= false
	end
	return tbl
end

-- a yes / no question
local confirm
function X.Confirm(text, onYes)
	if not confirm then
		confirm = K.Panel(UIParent, 380, 96, K.colors.bg)
		confirm:SetFrameStrata("DIALOG")
		confirm:SetPoint("CENTER", 0, 140)
		confirm:EnableMouse(true)
		confirm.text = K.Label(confirm, "", "GameFontHighlight", "CENTER")
		confirm.text:SetPoint("TOP", 0, -14)
		confirm.text:SetWidth(350)
		confirm.yes = K.Button(confirm, "Yes", 90, 22)
		confirm.yes:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -6, 12)
		confirm.no = K.Button(confirm, "No", 90, 22, function() confirm:Hide() end)
		confirm.no:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 6, 12)
		tinsert(UISpecialFrames, "XNAHConfirm")
		_G.XNAHConfirm = confirm
	end
	confirm.text:SetText(text)
	confirm.yes:SetScript("OnClick", function() confirm:Hide() onYes() end)
	confirm:Show()
end
