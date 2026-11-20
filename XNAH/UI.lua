-- The XNAH window: tabs (Market, Item, Deals, Crafting, Trends, Scan), shared pieces for them (a sortable table, item
-- cells, a yes/no question), the key binding.
-- Each tab lives in its own file and registers itself with UI.AddTab; this file is loaded before them.
local ADDON, X = ...
local K = X.K
local UI = {tabs = {}, order = {}}
X.UI = UI

local W, H = 960, 620
UI.W, UI.H = W - 20, H - 70 -- content area (940 x 550)

-- window size: the whole window (text included) is drawn bigger or smaller; drag the corner, or /xnah size 120
X.Default("uiScale", 1)
X.Default("sorts", {}) -- each table's sort column, per page ("market:1" = {column, descending})
local MIN_SCALE, MAX_SCALE = 0.6, 1.6

-- a tab: build(panel) once, refresh(panel) whenever something changed while it is shown
function UI.AddTab(key, title, build, refresh, order)
	UI.tabs[key] = {key = key, title = title, build = build, refresh = refresh, n = order or (#UI.order + 1)}
	UI.order[#UI.order + 1] = key
	table.sort(UI.order, function(a, b) return UI.tabs[a].n < UI.tabs[b].n end)
end

local frame
local function selectTab(key)
	if not UI.tabs[key] then key = UI.order[1] end
	UI.current = key
	for _, k in ipairs(UI.order) do
		local tab = UI.tabs[k]
		local on = k == key
		if tab.button then tab.button:SetSelected(on) end
		if on and not tab.panel then
			tab.panel = CreateFrame("Frame", nil, frame.content)
			tab.panel:SetAllPoints(frame.content)
			UI.building, UI.tableCount = k, 0 -- tables made while building remember their sorting under this page
			local ok, err = pcall(tab.build, tab.panel)
			UI.building = nil
			if not ok then X.OnError(err) end
		end
		if tab.panel then tab.panel:SetShown(on) end
	end
	X.S().tab = key
	UI.Refresh(true)
end
UI.Select = selectTab

function UI.Refresh(now)
	if not frame or not frame:IsShown() then return end
	local function run()
		local items = 0
		for _ in pairs(X.Items()) do items = items + 1 end
		local last = X.Realm().lastFull
		frame.title:SetText("|cffe6b422XNAH|r  |cff999999" .. (X.realmKey or X.RealmKey()) .. "  -  " .. X.Num(items) ..
			" items  -  full scan " .. X.Ago(last) .. "|r")
		frame.title:SetWidth(W - 360)
		local tab = UI.tabs[UI.current]
		if tab and tab.panel and tab.refresh then
			local ok, err = pcall(tab.refresh, tab.panel)
			if not ok then X.OnError(err) end
		end
	end
	if now then run() else X.Debounce("ui", 0.2, run) end
end
for _, e in ipairs({"XNAH_PRICES", "XNAH_SCAN", "XNAH_RECIPES", "XNAH_WATCH", "XNAH_AH", "XNAH_ANALYSIS", "XNAH_LEDGER",
	"XNAH_INVENTORY", "XNAH_QUEUE", "XNAH_SHARE", "XNAH_SHOP", "XNAH_HOME", "XNAH_IGNORE"}) do
	X.On(e, function() UI.Refresh() end)
end

local function build()
	frame = CreateFrame("Frame", "XNAHFrame", UIParent, "BackdropTemplate")
	frame:SetSize(W, H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	K.Backdrop(frame, K.colors.bg)
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		X.S().window = {p, rp, x, y}
	end)
	frame:SetScale(UI.ClampScale(X.S().uiScale))
	local pos = X.S().window
	if pos and pos[1] then frame:ClearAllPoints() frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end
	tinsert(UISpecialFrames, "XNAHFrame")
	frame:SetScript("OnHide", function() K.CloseMenu() end)
	frame:SetScript("OnShow", function() UI.Refresh(true) end)

	frame.title = K.Label(frame, "", "GameFontNormal")
	frame.title:SetPoint("TOPLEFT", 12, -10)
	local close = K.Button(frame, "X", 24, 20, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -6, -6)
	-- the guide (Guide.lua) - how every page works
	local guide = K.Button(frame, "Guide", 64, 20, function() if X.ShowGuide then X.ShowGuide() end end)
	guide:SetPoint("RIGHT", close, "LEFT", -4, 0)
	K.Tooltip(guide, "Guide", "How every page of XNAH works and how to use it to make gold.")
	-- quick search (Quick.lua): any item or recipe by name
	if UI.QuickSearchBox then
		local box = UI.QuickSearchBox(frame)
		box:SetPoint("RIGHT", guide, "LEFT", -10, 0)
		local findLabel = K.Label(frame, "Find", "GameFontNormalSmall", "RIGHT")
		findLabel:SetPoint("RIGHT", box, "LEFT", -8, 0)
	end
	-- the size grip in the bottom right corner: drag = bigger / smaller, right-click = normal size
	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -2, 2)
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
		"Also: /xnah size 120")
	frame.grip = grip

	-- tabs share the width of the window
	local x, n = 10, #UI.order
	local tw = math.floor((W - 20 - 3 * (n - 1)) / math.max(1, n))
	for _, key in ipairs(UI.order) do
		local tab = UI.tabs[key]
		local b = K.Flat(frame, tw, 22)
		b:SetPoint("TOPLEFT", x, -32)
		b:SetLabel(tab.title)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() selectTab(key) end)
		tab.button = b
		x = x + tw + 3
	end
	frame.content = CreateFrame("Frame", nil, frame)
	frame.content:SetPoint("TOPLEFT", 10, -60)
	frame.content:SetPoint("BOTTOMRIGHT", -10, 10)
	frame:Hide()
end
UI.Frame = function() return frame end

function UI.ClampScale(s)
	s = tonumber(s) or 1
	return math.max(MIN_SCALE, math.min(MAX_SCALE, s))
end
-- sets the window size (1 = normal); the top left corner stays where it is (left / top in the screen's units)
function UI.SetScale(s, left, top)
	s = UI.ClampScale(s)
	X.S().uiScale = math.floor(s * 100 + 0.5) / 100
	if not frame then return end
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

function UI.Toggle(tab)
	if not frame then build() end
	if frame:IsShown() and (not tab or tab == UI.current) then frame:Hide() return end
	frame:Show()
	selectTab(tab or UI.current or X.S().tab or "market")
end
function UI.Open(tab)
	if not frame then build() end
	frame:Show()
	selectTab(tab or UI.current or X.S().tab or "market")
end
X.Toggle = function() UI.Toggle() end

-- [[ shared bits for the tabs ]]
-- open the item page for an item key ("2589" or "15210:-19")
function UI.ShowItem(key)
	if not key then return end
	UI.itemKey = key
	UI.history = UI.history or {}
	if UI.history[#UI.history] ~= key then UI.history[#UI.history + 1] = key end
	UI.Open("item")
end
X.ShowItem = UI.ShowItem

-- "[icon] Name" in the item's quality colour; a star in front when watched
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
-- right-click menu on an item row: open, watch / unwatch, search on the auction house
function UI.ItemMenu(anchor, key)
	local items = {
		{text = X.ItemText(key), isTitle = true},
		{text = "Open item page", func = function() UI.ShowItem(key) end},
		{text = X.Watched(key) and "Remove from watch list" or "Add to watch list", func = function() X.SetWatched(key, not X.Watched(key)) end},
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

-- [[ sortable table ]] K.Table(parent, w, h, columns, onClick)
-- columns = {{title, width, justify, text = function(row) -> string, sort = function(row) -> number or string}, ...}
-- tbl:SetRows(rows, emptyText); clicking a header sorts by it (again: the other way); clicking a row: onClick(row, button,
-- rowFrame). Rows with row.key get the item tooltip on hover.
function K.Table(parent, w, h, columns, onClick)
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
		if row.key then
			rowFrame:SetScript("OnEnter", function(self) UI.ItemTooltip(self, row.key) end)
			rowFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
		else
			rowFrame:SetScript("OnEnter", nil)
			rowFrame:SetScript("OnLeave", nil)
		end
	end, cols)
	tbl = list
	tbl.columns = columns
	tbl.sortCol, tbl.sortDesc = nil, true
	-- the sorting you pick is remembered per page (tables made while a page is built: "market:1", "market:2", ...)
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
