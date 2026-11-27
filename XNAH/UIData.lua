-- The "Your data" window (Settings: the "Your data" button, or /xnah data): data health on the left (how old the
-- scans are, how much is kept, the size of each part of the saved data, the items with the most data, items not seen
-- for a long time, Slim down with a yes / no step inside the window) and exports on the right (text to copy into a
-- spreadsheet). The numbers and the work are in DataTools.lua; this file only shows them.
local ADDON, X = ...
local K, UI = X.K, X.UI

local FW, FH = 1000, 640          -- the window
local PW, PH = 480, 572           -- each half
local LEFT, RIGHT = 10, 510       -- x of the halves
local BOX_W, BOX_H = 470, 326     -- the copy box
local ORANGE = "|cffffa040"
local GREY = "|cff999999"
local GREEN = "|cff4ade80"

local frame
local D = {}  -- the window's parts and its state (one table: keeps the functions below small)
D.item = nil  -- the item of the "Price history of one item" export

local function S() return X.S() end
local function grey(t) return GREY .. t .. "|r" end
-- "1 item", "12 items"
local function count(n, one, many) return X.Num(n) .. " " .. (n == 1 and one or (many or (one .. "s"))) end

-- [[ data health ]]
local PART_COLUMNS = {
	{"Part", 270, "LEFT", text = function(r) return r.name end},
	{"Size", 100, "RIGHT", text = function(r) return X.SizeText(r.bytes) end, sort = function(r) return r.bytes end},
	{"Share", 70, "RIGHT", text = function(r) return r.share and string.format("%.0f%%", r.share) or "-" end,
		sort = function(r) return r.bytes end},
}
local TOP_COLUMNS = {
	{"Item", 280, "LEFT", text = function(r) return UI.ItemCell(r.key) end},
	{"Size", 80, "RIGHT", text = function(r) return X.SizeText(r.bytes) end},
	{"Days", 80, "RIGHT", text = function(r) return X.Num(r.days or 0) end},
}

local function healthLines(res)
	local full = "Last full scan: " .. X.Ago(res.lastFull)
	local sc = res.lastFullScan
	if sc and sc.auctions then full = full .. grey("  (" .. X.Num(sc.auctions) .. " auctions, " .. X.Num(sc.items or 0) .. " items)") end
	D.l1:SetText(full)
	D.l2:SetText("Last scan of your tracked items: " .. X.Ago(res.lastTracked))
	D.l3:SetText("Kept on this realm: " .. count(res.items, "item") .. ", " .. count(res.scans, "scan") .. " (" ..
		count(res.fullScans, "full scan") .. "), " .. count(res.sales, "sale") .. " and " .. count(res.buys, "buy"))
	D.l4:SetText("Saved data in all: about " .. X.SizeText(res.total) .. grey("  (worked out " .. X.Ago(res.t) .. ")"))
	local parts = {}
	for _, p in ipairs(res.parts) do
		if p.bytes > 0 then
			parts[#parts + 1] = {name = p.name, bytes = p.bytes, share = res.total > 0 and p.bytes / res.total * 100 or nil}
		end
	end
	D.parts:SetRows(parts, "Nothing saved yet.")
	D.top:SetRows(res.top, "No items yet.")
	local bits = {}
	for _, d in ipairs(X.UNSEEN_DAYS) do bits[#bits + 1] = d .. " days: " .. X.Num(res.unseen[d] or 0) end
	D.unseen:SetText(table.concat(bits, "     ") .. (res.never > 0 and grey("   (" .. X.Num(res.never) ..
		" never seen with a price)") or ""))
end

local function slimDays() return S().dataSlimDays or 90 end

-- the Slim down line: the button, or the question, or what is going on
local function showSlim(state, text)
	D.slimState = state
	D.slimBtn:SetShown(state == "idle")
	D.daysBtn:SetEnabled(state == "idle")
	D.yes:SetShown(state == "ask")
	D.no:SetShown(state == "ask")
	D.slimText:SetText(text or "")
end

function D.RefreshHealth()
	if not frame or not frame:IsShown() then return end
	local res, busy, progress = X.DataHealth()
	D.again:SetEnabled(not busy)
	if res then healthLines(res) end
	if busy then
		D.busy:SetText(ORANGE .. (progress or "Working it out") .. " ...|r")
	else
		D.busy:SetText("")
	end
	if not res and not busy then D.l1:SetText(grey("Nothing worked out yet.")) end
	D.daysBtn:SetText("Not seen for " .. slimDays() .. " days")
	if D.slimState == "idle" then
		D.slimBtn:SetEnabled(res ~= nil and not busy)
		local s = res and res.slim[slimDays()]
		-- what the last slim down did stays until the next choice
		D.slimText:SetText(D.done or (s and grey("Would remove " .. count(s.n, "item") .. " (about " .. X.SizeText(s.bytes) .. ").")) or "")
	end
end

-- the question, inside the window
local function askSlim()
	D.done = nil
	local res = X.DataHealth()
	local days = slimDays()
	local s = res and res.slim[days]
	if not s then return end
	if X.scan and X.scan.state ~= "idle" then
		showSlim("idle")
		D.slimText:SetText(ORANGE .. "A scan is running: slim down when it is done.|r")
		return
	end
	if s.n == 0 then
		showSlim("idle")
		D.slimText:SetText("Nothing to remove: every item not seen for " .. days .. " days is one that is always kept.")
		return
	end
	showSlim("ask", ORANGE .. "Remove " .. count(s.n, "item") .. " not seen for " .. days .. " days or more (about " ..
		X.SizeText(s.bytes) .. ")? Their price history goes too and cannot be brought back." ..
		(s.kept > 0 and (" " .. count(s.kept, "old item") .. " kept (tracked, compared, traded or owned).") or "") .. "|r")
end

local function doSlim()
	local days = slimDays()
	local ok, B = X.DataSlim(days, function(done)
		local text
		if done.stopped then
			text = ORANGE .. "Stopped: the realm changed. Removed " .. count(done.removed, "item") .. ".|r"
		else
			text = GREEN .. "Removed " .. count(done.removed, "item") .. " (about " .. X.SizeText(done.bytes) .. ").|r " ..
				"The saved file gets smaller at your next /reload or logout (the game writes it only then)."
		end
		showSlim("idle")
		D.done = text
		X.DataHealth(true)
		D.RefreshHealth()
		D.slimText:SetText(text)
	end)
	if not ok then
		showSlim("idle")
		D.slimText:SetText(ORANGE .. (B == "scan" and "A scan is running: slim down when it is done." or
			"Already removing items.") .. "|r")
		return
	end
	showSlim("busy", ORANGE .. "Removing items ...|r")
	D.slimJob = B
end

local function buildHealth(p)
	local title = K.Label(p, "Data health", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	D.again = K.Button(p, "Work it out again", 140, 20, function() X.DataHealth(true) D.RefreshHealth() end)
	D.again:SetPoint("TOPRIGHT", -8, -6)
	local y = -30
	for i = 1, 4 do
		local l = K.Label(p, "")
		l:SetPoint("TOPLEFT", 10, y)
		l:SetWidth(PW - 20)
		l:SetWordWrap(false)
		D["l" .. i] = l
		y = y - 16
	end
	D.busy = K.Label(p, "")
	D.busy:SetPoint("TOPLEFT", 10, -96)
	D.busy:SetWidth(PW - 20)
	local pl = K.Label(p, "Size of each part (as the game writes it into the saved file)", "GameFontNormalSmall")
	pl:SetPoint("TOPLEFT", 10, -114)
	D.parts = K.Table(p, PW - 20, 7 * 18 + 4, PART_COLUMNS)
	D.parts:SetPoint("TOPLEFT", 10, -146)
	D.parts:SortBy(2, true)
	local tl = K.Label(p, "Items with the most data (click one to show it)", "GameFontNormalSmall")
	tl:SetPoint("TOPLEFT", 10, -286)
	D.top = K.Table(p, PW - 20, 5 * 18 + 4, TOP_COLUMNS, function(row) if row.key then UI.ShowItem(row.key) end end)
	D.top:SetPoint("TOPLEFT", 10, -318)
	local ul = K.Label(p, "Items not seen on the auction house for", "GameFontNormalSmall")
	ul:SetPoint("TOPLEFT", 10, -420)
	D.unseen = K.Label(p, "")
	D.unseen:SetPoint("TOPLEFT", 10, -436)
	D.unseen:SetWidth(PW - 20)
	D.unseen:SetWordWrap(false)
	-- slim down
	local sl = K.Label(p, "Slim down", "GameFontNormal")
	sl:SetPoint("TOPLEFT", 10, -460)
	local help = K.Label(p, grey("Removes items not seen for a long time, with their history. Always kept: tracked, " ..
		"compared, sold or bought, owned and the item shown now."))
	help:SetPoint("TOPLEFT", 10, -478)
	help:SetWidth(PW - 20)
	help:SetWordWrap(true)
	D.daysBtn = K.Button(p, "", 170, 22, function(self)
		local res = X.DataHealth()
		local list = {{text = "Remove items not seen for", isTitle = true}}
		for _, d in ipairs(X.SLIM_DAYS) do
			local s = res and res.slim[d]
			list[#list + 1] = {text = d .. " days" .. (s and grey("  (" .. X.Num(s.n) .. " items)") or ""),
				checked = slimDays() == d, func = function() S().dataSlimDays = d D.done = nil D.RefreshHealth() end}
		end
		K.Menu(self, list)
	end)
	D.daysBtn:SetPoint("TOPLEFT", 10, -512)
	D.slimBtn = K.Button(p, "Slim down ...", 120, 22, askSlim)
	D.slimBtn:SetPoint("LEFT", D.daysBtn, "RIGHT", 6, 0)
	D.yes = K.Button(p, "Yes, remove them", 140, 22, doSlim)
	D.yes:SetPoint("LEFT", D.daysBtn, "RIGHT", 6, 0)
	D.no = K.Button(p, "Cancel", 80, 22, function() showSlim("idle") D.RefreshHealth() end)
	D.no:SetPoint("LEFT", D.yes, "RIGHT", 6, 0)
	D.slimText = K.Label(p, "")
	D.slimText:SetPoint("TOPLEFT", 10, -538)
	D.slimText:SetWidth(PW - 20)
	D.slimText:SetWordWrap(true)
	showSlim("idle")
end

-- [[ export ]]
local function exportKind()
	local kind = S().dataExport
	return X.ExportSpec(kind) and kind or "history"
end
local function rangeDays()
	local d = S().dataRange
	return type(d) == "number" and d or 90
end
-- the item of the price history export: the one picked here, else the one shown on the Items view, else the first
-- tracked one
local function exportItem()
	if D.item and X.Items()[D.item] then return D.item end
	if UI.itemKey and X.Items()[UI.itemKey] then return UI.itemKey end
	local first, firstName
	for key in pairs(X.db.watch or {}) do
		local name = X.ItemName(key)
		if X.Items()[key] and (not firstName or name < firstName) then first, firstName = key, name end
	end
	return first
end

-- focus = true: the box takes the keyboard with the text selected (Ctrl+C copies it; Escape gives the keyboard back)
local function setBoxText(text, focus)
	D.text = text or ""
	D.box:SetText(D.text)
	D.box.edit:SetCursorPosition(0)
	if focus then
		D.box.edit:SetFocus()
		D.box.edit:HighlightText()
	end
end

local function exportDone(res)
	D.exporting = nil
	D.focused = D.wantFocus == true
	setBoxText(res.text, D.focused)
	local line = count(res.rows, "row") .. ", " .. X.SizeText(res.bytes) .. ". " .. (D.focused and
		"The text is selected: press Ctrl+C to copy, then paste it into a spreadsheet." or
		"Press Select all, then Ctrl+C to copy, then paste it into a spreadsheet.")
	if res.note == "pick" then
		line = ORANGE .. "Pick an item first (the button above).|r"
	elseif res.note == "noitem" then
		line = ORANGE .. "XNAH has no prices of this item.|r"
	elseif res.rows == 0 then
		line = grey("Nothing to copy for this time span (only the header row).")
	end
	if res.cut then
		line = line .. "\n" .. ORANGE .. "Cut short: only the newest " .. X.Num(res.rows) .. " of " .. X.Num(res.total) ..
			" rows fit in the box. Pick a shorter time span for the rest.|r"
	end
	D.status:SetText(line)
end

-- focus = true (a choice of yours): the box takes the keyboard with the text selected when it is ready. Opening the
-- window makes the text without it, so the keyboard stays with the game until you pick something or press a button.
function D.MakeExport(focus)
	if not frame then return end
	D.wantFocus = focus == true
	local kind = exportKind()
	local spec = X.ExportSpec(kind)
	D.kindBtn:SetText(spec.title)
	local key = spec.item and exportItem() or nil
	D.itemLabel:SetShown(spec.item == true)
	D.itemBtn:SetShown(spec.item == true)
	if spec.item then D.itemBtn:SetText(key and X.ItemText(key) or "Pick an item") end
	for _, b in ipairs(D.ranges) do
		b:SetSelected(spec.range and b.days == rangeDays())
		b:SetEnabled(spec.range == true)
		b:SetAlpha(spec.range and 1 or 0.4)
	end
	D.status:SetText(ORANGE .. "Making the text ...|r")
	setBoxText("")
	D.exporting = X.Export(kind, {key = key, days = spec.range and rangeDays() or 0}, exportDone)
end

local function kindMenu(self)
	local list = {{text = "What to copy", isTitle = true}}
	for _, e in ipairs(X.EXPORTS) do
		list[#list + 1] = {text = e.title, checked = exportKind() == e.key, func = function()
			S().dataExport = e.key
			D.MakeExport(true)
		end}
	end
	K.Menu(self, list)
end
local function itemMenu(self)
	local list = {{text = "Price history of", isTitle = true}}
	local seen = {}
	local function add(key, note)
		if not key or seen[key] or not X.Items()[key] then return end
		seen[key] = true
		list[#list + 1] = {text = X.ItemText(key) .. (note and grey("  " .. note) or ""), checked = key == exportItem(),
			func = function() D.item = key D.MakeExport(true) end}
	end
	add(UI.itemKey, "(shown on the Items view)")
	local tracked = {}
	for key in pairs(X.db.watch or {}) do tracked[#tracked + 1] = {key = key, name = X.ItemName(key)} end
	table.sort(tracked, function(a, b) return a.name < b.name end)
	for _, t in ipairs(tracked) do add(t.key) end
	if #list == 1 then list[2] = {text = "No item: show one on the Items view, or track some", disabled = true} end
	K.Menu(self, list)
end

local function buildExport(p)
	local title = K.Label(p, "Export", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -8)
	local help = K.Label(p, grey("Plain text with the columns split by tabs and a header row: paste it straight into a " ..
		"spreadsheet. Prices are in gold: 12.3456 = 12g 34s 56c."))
	help:SetPoint("TOPLEFT", 10, -26)
	help:SetWidth(PW - 20)
	help:SetWordWrap(true)
	local wl = K.Label(p, "What:")
	wl:SetPoint("TOPLEFT", 10, -68)
	D.kindBtn = K.Button(p, "", 260, 22, kindMenu)
	D.kindBtn:SetPoint("TOPLEFT", 80, -63)
	D.itemLabel = K.Label(p, "Item:")
	D.itemLabel:SetPoint("TOPLEFT", 10, -96)
	D.itemBtn = K.Button(p, "", 300, 22, itemMenu)
	D.itemBtn:SetPoint("TOPLEFT", 80, -91)
	local rl = K.Label(p, "Time span:")
	rl:SetPoint("TOPLEFT", 10, -124)
	D.ranges = {}
	local x = 80
	for _, r in ipairs(X.EXPORT_RANGES) do
		local b = K.Flat(p, 100, 20)
		b:SetPoint("TOPLEFT", x, -120)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b.days = r[2]
		b:SetScript("OnClick", function() S().dataRange = r[2] D.MakeExport(true) end)
		D.ranges[#D.ranges + 1] = b
		x = x + 104
	end
	D.status = K.Label(p, "")
	D.status:SetPoint("TOPLEFT", 10, -150)
	D.status:SetWidth(PW - 20)
	D.status:SetWordWrap(true)
	-- the copy box: typing in it changes nothing (the text goes back and stays selected)
	D.box = K.TextArea(p, BOX_W, BOX_H, function()
		D.box:SetText(D.text or "")
		D.box.edit:HighlightText()
	end)
	D.box:SetPoint("TOPLEFT", 5, -204)
	-- the box taking the keyboard (a click in it too) selects the whole text
	D.box.edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	local sel = K.Button(p, "Select all", 110, 22, function()
		D.box.edit:SetFocus()
		D.box.edit:HighlightText()
	end)
	sel:SetPoint("TOPLEFT", 10, -536)
	K.Tooltip(sel, "Select all", "Selects the whole text in the box; then press Ctrl+C to copy it.")
	local again = K.Button(p, "Make it again", 120, 22, function() D.MakeExport(true) end)
	again:SetPoint("LEFT", sel, "RIGHT", 6, 0)
	K.Tooltip(again, "Make it again", "Makes the text again with the numbers of now.")
end

-- [[ the window ]]
local function build()
	frame = K.Panel(UIParent, FW, FH, K.colors.bg)
	_G.XNAHDataFrame = frame
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetPoint("CENTER")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "XNAHDataFrame")
	local title = K.Label(frame, "|cffe6b422XNAH|r  Your data", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 12, -12)
	local sub = K.Label(frame, grey("How much XNAH keeps, slimming it down, and copying it into a spreadsheet."))
	sub:SetPoint("LEFT", title, "RIGHT", 14, 0)
	local close = K.Button(frame, "X", 24, 22, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -9)
	K.Tooltip(close, "Close", "Escape closes it too.")
	local left = K.Panel(frame, PW, PH, {0, 0, 0, 0.25})
	left:SetPoint("TOPLEFT", LEFT, -58)
	local right = K.Panel(frame, PW, PH, {0, 0, 0, 0.25})
	right:SetPoint("TOPLEFT", RIGHT, -58)
	D.left, D.right = left, right
	buildHealth(left)
	buildExport(right)
	-- the progress of the health walk and of a slim down, a few times a second while one runs
	local acc = 0
	frame:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc < 0.25 then return end
		acc = 0
		if X.DataHealthBusy() then D.RefreshHealth() end
		local job = D.slimJob
		if job and D.slimState == "busy" then
			D.slimText:SetText(ORANGE .. "Removing items: " .. X.Num(job.i) .. " / " .. X.Num(job.total) .. " looked at, " ..
				X.Num(job.removed) .. " removed ...|r")
		end
		if D.exporting and not D.exporting.result then D.status:SetText(ORANGE .. (D.exporting.progress or "") .. " ...|r") end
	end)
	frame:SetScript("OnShow", function()
		frame:SetScale(UI.ClampScale(S().uiScale))
		-- the numbers again when the last ones are older than a minute
		local res = X.DataHealth()
		if res and X.Now() - res.t > 60 then X.DataHealth(true) end
		D.RefreshHealth()
		D.MakeExport()
	end)
	frame:SetScript("OnHide", function() K.CloseMenu() if D.box then D.box.edit:ClearFocus() end end)
	frame:Hide()
end

-- open (or bring back) the window
function UI.OpenData()
	if not frame then build() end
	if frame:IsShown() then
		frame:Raise()
		return frame
	end
	frame:Show()
	return frame
end
function UI.ToggleData()
	if frame and frame:IsShown() then frame:Hide() return end
	UI.OpenData()
end
UI.DataFrame = function() return frame end
UI.DataParts = D

X.On("XNAH_DATA", function() D.RefreshHealth() end)
