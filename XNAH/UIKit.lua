-- Small pieces the windows are built from: panels, buttons, labels, text boxes, scrolling lists, pop-up menus.
-- Only the game's basic templates (UIPanelButtonTemplate, InputBoxTemplate, UICheckButtonTemplate,
-- UIPanelScrollFrameTemplate, BackdropTemplate); everything else is drawn here.
local ADDON, X = ...
local K = {}
X.K = K

local WHITE = "Interface\\Buttons\\WHITE8x8"
K.colors = {bg = {0.06, 0.06, 0.08, 1}, panel = {0.11, 0.11, 0.14, 0.95}, edge = {0.38, 0.32, 0.18, 1},
	accent = {0.9, 0.71, 0.13}, row = {1, 1, 1, 0.04}, rowHi = {0.9, 0.71, 0.13, 0.22}, sel = {0.9, 0.71, 0.13, 0.4}}

function K.Backdrop(f, bg, edge)
	if not f.SetBackdrop then return end
	f:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
	local b, e = bg or K.colors.panel, edge or K.colors.edge
	f:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
	f:SetBackdropBorderColor(e[1], e[2], e[3], e[4] or 1)
end
function K.Panel(parent, w, h, bg)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	if w then f:SetSize(w, h) end
	K.Backdrop(f, bg)
	return f
end
function K.Label(parent, text, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetText(text or "")
	return fs
end
function K.Button(parent, text, w, h, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w or 100, h or 22)
	b:SetText(text or "")
	if onClick then b:SetScript("OnClick", function(self, button) onClick(self, button) end) end
	return b
end
-- a flat text button (for list rows, slots, small links)
function K.Flat(parent, w, h)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w or 100, h or 18)
	K.Backdrop(b, K.colors.row, {0, 0, 0, 0})
	local hi = b:CreateTexture(nil, "HIGHLIGHT")
	hi:SetAllPoints()
	hi:SetColorTexture(K.colors.rowHi[1], K.colors.rowHi[2], K.colors.rowHi[3], K.colors.rowHi[4])
	b.label = K.Label(b, "", "GameFontHighlightSmall")
	b.label:SetPoint("LEFT", 4, 0)
	b.label:SetPoint("RIGHT", -4, 0)
	b.label:SetWordWrap(false)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	function b:SetLabel(t) self.label:SetText(t or "") end
	function b:SetSelected(on)
		local c = on and K.colors.sel or K.colors.row
		self:SetBackdropColor(c[1], c[2], c[3], c[4])
	end
	return b
end
function K.Check(parent, text, onChange)
	local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	c:SetSize(22, 22)
	c.label = K.Label(c, text)
	c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
	if onChange then c:SetScript("OnClick", function(self) onChange(self:GetChecked() and true or false) end) end
	return c
end
function K.Edit(parent, w, onEnter)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(w or 120, 20)
	e:SetAutoFocus(false)
	e:SetFontObject("ChatFontNormal")
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnEnterPressed", function(self) self:ClearFocus() if onEnter then onEnter(self:GetText()) end end)
	return e
end
-- a box for several lines of text (notes, pasting, export)
function K.TextArea(parent, w, h, onChange)
	local box = K.Panel(parent, w, h, {0, 0, 0, 0.5})
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -26, 6)
	local e = CreateFrame("EditBox", nil, scroll)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetMaxLetters(0) -- no limit (exports are long)
	e:SetFontObject("ChatFontNormal")
	e:SetWidth(w - 36)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	if onChange then e:SetScript("OnTextChanged", function(self, user) if user then onChange(self:GetText()) end end) end
	scroll:SetScrollChild(e)
	box:SetScript("OnMouseDown", function() e:SetFocus() end)
	box.edit = e
	function box:SetText(t) e:SetText(t or "") end
	function box:GetText() return e:GetText() end
	function box:SetEnabled(on) e:SetEnabled(on) end
	return box
end

-- [[ scrolling list ]] K.List(parent, w, h, rowHeight, draw(row, item, index), columns); list:SetItems(items)
-- columns (optional): {{"Header", width, "LEFT" / "RIGHT"}, ...} - a header line above the list, and in each row
-- aligned cells filled with row:SetCols(text1, text2, ...)
-- A scroll bar on the right (drag it, click above / below it, or use the mouse wheel); the rows leave room for it.
local BAR = 10
function K.List(parent, w, h, rowH, draw, columns)
	local list = K.Panel(parent, w, h, {0, 0, 0, 0.35})
	list.rowH = rowH
	list.items = {}
	list.offset = 0
	list.rows = {}
	local count = math.floor((h - 4) / rowH)
	local rowW = w - 6 - BAR
	if columns then
		-- columns wider than the room left by the scroll bar: the first (usually the item name) gives way
		local total = 0
		for _, col in ipairs(columns) do total = total + col[2] end
		local over = total + 4 - rowW
		if over > 0 then
			local copy = {}
			for c, col in ipairs(columns) do copy[c] = {col[1], col[2], col[3]} end
			copy[1][2] = math.max(40, copy[1][2] - over)
			columns = copy
		end
	end
	if columns then
		list.headers = {}
		local x = 6
		for c, col in ipairs(columns) do
			local hdr = K.Label(list, "|cff999999" .. col[1] .. "|r", "GameFontHighlightSmall", col[3] or "LEFT")
			hdr:SetPoint("BOTTOMLEFT", list, "TOPLEFT", x, 2)
			hdr:SetWidth(col[2] - 4)
			list.headers[c] = hdr
			x = x + col[2]
		end
	end
	for i = 1, count do
		local row = K.Flat(list, rowW, rowH - 1)
		row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * rowH)
		row:Hide()
		if columns then
			row.label:Hide()
			row.cols = {}
			local x = 4
			for c, col in ipairs(columns) do
				local fs = K.Label(row, "", "GameFontHighlightSmall", col[3] or "LEFT")
				fs:SetPoint("LEFT", x, 0)
				fs:SetWidth(col[2] - 4)
				fs:SetWordWrap(false)
				row.cols[c] = fs
				x = x + col[2]
			end
			function row:SetCols(...)
				for c = 1, #self.cols do self.cols[c]:SetText((select(c, ...)) or "") end
			end
		end
		list.rows[i] = row
	end
	list.empty = K.Label(list, "", "GameFontDisableSmall", "CENTER")
	list.empty:SetPoint("TOP", 0, -12)
	list.empty:SetWidth(w - 20)
	-- [[ scroll bar ]] a track and a thumb; hidden when everything fits
	local track = CreateFrame("Button", nil, list)
	track:SetPoint("TOPRIGHT", -2, -2)
	track:SetPoint("BOTTOMRIGHT", -2, 2)
	track:SetWidth(BAR)
	local trackTex = track:CreateTexture(nil, "BACKGROUND")
	trackTex:SetAllPoints()
	trackTex:SetColorTexture(1, 1, 1, 0.05)
	local thumb = CreateFrame("Button", nil, track)
	thumb:SetWidth(BAR)
	local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetAllPoints()
	thumbTex:SetColorTexture(K.colors.accent[1], K.colors.accent[2], K.colors.accent[3], 0.55)
	local thumbHi = thumb:CreateTexture(nil, "HIGHLIGHT")
	thumbHi:SetAllPoints()
	thumbHi:SetColorTexture(1, 1, 1, 0.15)
	list.track, list.thumb = track, thumb
	local function maxOffset() return math.max(0, #list.items - #list.rows) end
	local function placeThumb()
		local max = maxOffset()
		track:SetShown(max > 0)
		if max == 0 then return end
		local th = track:GetHeight() or (h - 4)
		if th <= 0 then th = h - 4 end
		local size = math.max(16, th * #list.rows / #list.items)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -(th - size) * (list.offset / max))
	end
	-- offset from the mouse's height on the track (grab = where on the thumb it was taken)
	local function offsetAtCursor(grab)
		local top = track:GetTop()
		local th = track:GetHeight()
		if not top or not th or th <= 0 then return list.offset end
		local _, y = GetCursorPosition()
		y = y / (track:GetEffectiveScale() or 1)
		local size = thumb:GetHeight() or 16
		local frac = (top - y - (grab or size / 2)) / math.max(1, th - size)
		frac = math.max(0, math.min(1, frac))
		return math.floor(frac * maxOffset() + 0.5)
	end
	thumb:SetScript("OnMouseDown", function(self)
		local _, y = GetCursorPosition()
		y = y / (self:GetEffectiveScale() or 1)
		local grab = (self:GetTop() or y) - y
		self:SetScript("OnUpdate", function()
			local o = offsetAtCursor(grab)
			if o ~= list.offset then list.offset = o list:Refresh() end
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
	thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
	-- a click above or below the thumb moves one page
	track:SetScript("OnClick", function()
		local _, y = GetCursorPosition()
		y = y / (track:GetEffectiveScale() or 1)
		local tTop = thumb:GetTop()
		local page = math.max(1, #list.rows - 1)
		if tTop and y > tTop then list.offset = math.max(0, list.offset - page)
		else list.offset = math.min(maxOffset(), list.offset + page) end
		list:Refresh()
	end)

	function list:Refresh()
		local max = math.max(0, #self.items - #self.rows)
		if self.offset > max then self.offset = max end
		placeThumb()
		for i, row in ipairs(self.rows) do
			local item = self.items[i + self.offset]
			if item then
				row:Show()
				row:SetSelected(false)
				draw(row, item, i + self.offset)
			else
				row:Hide()
			end
		end
		self.empty:SetShown(#self.items == 0)
	end
	function list:SetItems(items, emptyText)
		self.items = items or {}
		self.empty:SetText(emptyText or "")
		self:Refresh()
	end
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(self, delta)
		self.offset = math.max(0, self.offset - delta * 3)
		self:Refresh()
	end)
	return list
end

-- [[ pop-up menu ]] K.Menu(anchor, {{text, func, checked, disabled, isTitle}})
local menu, catcher
function K.CloseMenu()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end
function K.Menu(anchor, items)
	if not menu then
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN")
		catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		catcher:SetScript("OnClick", K.CloseMenu)
		menu = K.Panel(UIParent, 180, 20, K.colors.bg)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu.buttons = {}
		menu:EnableMouseWheel(true)
	end
	local maxRows = 26
	local start = 0
	local function draw()
		for _, b in ipairs(menu.buttons) do b:Hide() end
		local width = 120
		local shown = math.min(#items, maxRows)
		for i = 1, shown do
			local item = items[i + start]
			local b = menu.buttons[i]
			if not b then
				b = K.Flat(menu, 176, 18)
				b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
				menu.buttons[i] = b
			end
			b:Show()
			local text = item.text or ""
			if item.checked then text = "|cff33ff33>|r " .. text end
			if item.isTitle then text = "|cffffd100" .. text .. "|r" end
			if item.disabled then text = "|cff777777" .. text .. "|r" end
			b:SetLabel(text)
			b:SetSelected(false)
			b:SetScript("OnClick", function(_, button)
				if item.isTitle or item.disabled then return end
				K.CloseMenu()
				if item.func then item.func(button) end
			end)
			width = math.max(width, (b.label:GetStringWidth() or 100) + 16)
		end
		width = math.min(width, 300)
		for _, b in ipairs(menu.buttons) do b:SetWidth(width - 4) end
		menu:SetSize(width, shown * 18 + 4)
	end
	menu:SetScript("OnMouseWheel", function(_, delta)
		start = math.max(0, math.min(#items - maxRows, start - delta * 3))
		draw()
	end)
	draw()
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	catcher:Show()
	menu:Show()
	return menu
end

-- [[ a small dialog: one line or a text area, OK / Cancel ]]
local dialog
function K.Ask(title, text, multiline, onOK, okText)
	if not dialog then
		dialog = K.Panel(UIParent, 420, 140, K.colors.bg)
		dialog:SetFrameStrata("DIALOG")
		dialog:SetPoint("CENTER", 0, 120)
		dialog:EnableMouse(true)
		dialog:SetMovable(true)
		dialog:RegisterForDrag("LeftButton")
		dialog:SetScript("OnDragStart", dialog.StartMoving)
		dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
		dialog.title = K.Label(dialog, "", "GameFontNormal")
		dialog.title:SetPoint("TOPLEFT", 12, -10)
		dialog.line = K.Edit(dialog, 390)
		dialog.area = K.TextArea(dialog, 396, 230)
		dialog.ok = K.Button(dialog, "OK", 90, 22)
		dialog.cancel = K.Button(dialog, "Cancel", 90, 22, function() dialog:Hide() end)
		dialog.ok:SetPoint("BOTTOMRIGHT", -110, 10)
		dialog.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
		tinsert(UISpecialFrames, "XNAHDialog")
		_G.XNAHDialog = dialog
	end
	dialog.title:SetText(title or "")
	dialog.line:Hide()
	dialog.area:Hide()
	local box
	if multiline then
		dialog:SetSize(420, 300)
		dialog.area:ClearAllPoints()
		dialog.area:SetPoint("TOPLEFT", 12, -30)
		dialog.area:Show()
		dialog.area:SetText(text or "")
		box = dialog.area
	else
		dialog:SetSize(420, 100)
		dialog.line:ClearAllPoints()
		dialog.line:SetPoint("TOPLEFT", 18, -36)
		dialog.line:Show()
		dialog.line:SetText(text or "")
		dialog.line:SetScript("OnEnterPressed", function() dialog.ok:Click() end)
		box = dialog.line
	end
	dialog.ok:SetText(okText or "OK")
	dialog.cancel:SetShown(onOK ~= nil)
	dialog.ok:SetScript("OnClick", function()
		local value = box:GetText()
		dialog:Hide()
		if onOK then onOK(value) end
	end)
	dialog:Show()
	if multiline then box.edit:SetFocus() box.edit:HighlightText() else box:SetFocus() box:HighlightText() end
	return dialog
end
-- a dialog with two labelled boxes: K.Ask2(title, {label, value}, {label, value}, onOK(first, second), okText)
local dialog2
function K.Ask2(title, first, second, onOK, okText)
	if not dialog2 then
		dialog2 = K.Panel(UIParent, 420, 150, K.colors.bg)
		dialog2:SetFrameStrata("DIALOG")
		dialog2:SetPoint("CENTER", 0, 120)
		dialog2:EnableMouse(true)
		dialog2:SetMovable(true)
		dialog2:RegisterForDrag("LeftButton")
		dialog2:SetScript("OnDragStart", dialog2.StartMoving)
		dialog2:SetScript("OnDragStop", dialog2.StopMovingOrSizing)
		dialog2.title = K.Label(dialog2, "", "GameFontNormal")
		dialog2.title:SetPoint("TOPLEFT", 12, -10)
		dialog2.label1 = K.Label(dialog2, "", "GameFontHighlightSmall")
		dialog2.label1:SetPoint("TOPLEFT", 14, -34)
		dialog2.box1 = K.Edit(dialog2, 270)
		dialog2.box1:SetPoint("TOPLEFT", 130, -30)
		dialog2.label2 = K.Label(dialog2, "", "GameFontHighlightSmall")
		dialog2.label2:SetPoint("TOPLEFT", 14, -64)
		dialog2.box2 = K.Edit(dialog2, 270)
		dialog2.box2:SetPoint("TOPLEFT", 130, -60)
		dialog2.hint = K.Label(dialog2, "", "GameFontDisableSmall")
		dialog2.hint:SetPoint("TOPLEFT", 14, -88)
		dialog2.hint:SetWidth(390)
		dialog2.ok = K.Button(dialog2, "OK", 90, 22)
		dialog2.cancel = K.Button(dialog2, "Cancel", 90, 22, function() dialog2:Hide() end)
		dialog2.ok:SetPoint("BOTTOMRIGHT", -110, 10)
		dialog2.cancel:SetPoint("BOTTOMRIGHT", -12, 10)
		dialog2.box1:SetScript("OnTabPressed", function() dialog2.box2:SetFocus() end)
		dialog2.box2:SetScript("OnTabPressed", function() dialog2.box1:SetFocus() end)
		tinsert(UISpecialFrames, "XNAHDialog2")
		_G.XNAHDialog2 = dialog2
		-- shift-click an item while the first box has the cursor: its link goes in (a post-hook, nothing replaced)
		if hooksecurefunc and HandleModifiedItemClick then
			hooksecurefunc("HandleModifiedItemClick", function(link)
				if dialog2:IsShown() and dialog2.box1:HasFocus() and type(link) == "string" and link:find("item:", 1, true) then
					dialog2.box1:SetText(link)
				end
			end)
		end
	end
	dialog2.title:SetText(title or "")
	dialog2.label1:SetText(first[1])
	dialog2.label2:SetText(second[1])
	dialog2.box1:SetText(first[2] or "")
	dialog2.box2:SetText(second[2] or "")
	dialog2.hint:SetText(first[3] or "")
	dialog2.ok:SetText(okText or "OK")
	local function done()
		local a, b = dialog2.box1:GetText(), dialog2.box2:GetText()
		dialog2:Hide()
		onOK(a, b)
	end
	dialog2.ok:SetScript("OnClick", done)
	dialog2.box1:SetScript("OnEnterPressed", function() dialog2.box2:SetFocus() end)
	dialog2.box2:SetScript("OnEnterPressed", done)
	dialog2:Show()
	dialog2.box1:SetFocus()
	return dialog2
end

-- shows text to copy (export)
function K.ShowText(title, text)
	return K.Ask(title .. "  |cff999999(Ctrl+C to copy)|r", text, true, nil, "Close")
end

function K.Tooltip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(title)
		if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
