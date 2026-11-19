-- The simple XNAH window (Xn, 2026-11-19: "simplify the entire ui/ux ... B with the graphical setup of C").
-- One layout for every page:
--   top:    your gold (all characters) and how it changed today; Find (any item or recipe)
--   left:   a list of entries (things to do, good buys, what to sell, ...)
--   right:  the picked entry: the item's price graph, one sentence what to do, one sentence why, and one big button
--   bottom: the pages (To do, Buy, Sell, Trends, Wealth) and More (the full window with every page)
-- Pages register with S.AddView(key, {title, order, list = function() -> entries, emptyText}).
--   entry = {id (unique text, keeps the selection), key (item key, for the icon and the graph), icon (texture, else the
--     item's icon), title, sub (one short line under the title, colour codes allowed),
--     name (header; default: the item's name), price (header, copper), badge (short coloured text next to the price),
--     sentence (what to do), why (why), lines = {{label, value}, ...} (a few numbers, optional),
--     graph (nil: the item's price graph; false: none; function(g, entry): draw your own on g),
--     button = {label, run = function(entry, button) end, disabled = true, tip}, button2 = same (smaller),
--     skip = true (a Skip button: hides the entry until the next session)}
--   button.run is called straight from the click (a hardware event), so it may buy, post or cancel.
-- S.ShowItem(key) shows one item on the right (from Find, alt-click, or another page).
local ADDON, X = ...
local K, UI = X.K, X.UI
local S = {views = {}, order = {}, skipped = {}}
X.Simple = S

X.Default("simpleUI", true)   -- /xnah opens this window (off: the full window, as before)
X.Default("simpleView", "todo")

local W, H = 900, 580
local LEFT_W = 270
local TOP_H, NAV_H = 40, 34
local GREY, GREEN, RED, GOLD = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"

-- [[ pages ]]
function S.AddView(key, def)
	def.key = key
	S.views[key] = def
	S.order[#S.order + 1] = key
	table.sort(S.order, function(a, b) return (S.views[a].order or 9) < (S.views[b].order or 9) end)
end

local frame
local current = {}  -- {view, entries, selected (id), item (key shown by S.ShowItem)}

-- [[ small pieces ]]
local function money(c) return c and X.Money(c, true) or (GREY .. "-|r") end
S.Money = money
local function signed(c)
	if not c then return GREY .. "-|r" end
	if c >= 0 then return GREEN .. "+" .. X.MoneyPlain(c) .. "|r" end
	return RED .. "-" .. X.MoneyPlain(-c) .. "|r"
end
S.Signed = signed
local function itemIcon(key)
	local id = key and X.KeyID(key)
	local icon = id and C_Item and C_Item.GetItemIconByID and X.Try(C_Item.GetItemIconByID, id)
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- [[ the price graph of an item ]] market value, lowest price, the usual price as a flat line, your sales as dots
local function drawItemGraph(g, key)
	local hist = X.History(key, X.Now() - 30 * 86400) or {}
	local mkt, low = {}, {}
	for i, p in ipairs(hist) do
		mkt[i] = {p[1], p[3]} -- X.History: {t, min, mkt, qty}
		low[i] = {p[1], p[2]}
	end
	local series = {
		{points = mkt, color = {0.9, 0.7, 0.13}, width = 2, label = "Market value"},
		{points = low, color = {0.55, 0.55, 0.55}, width = 1, label = "Lowest"},
	}
	local usual = X.Usual and X.Usual(key)
	if usual and #hist >= 2 then
		series[#series + 1] = {points = {{hist[1][1], usual}, {hist[#hist][1], usual}}, color = {0.45, 0.45, 0.45}, width = 1, label = "Usual"}
	end
	local marks = {}
	for _, e in ipairs(X.GraphTrades and X.GraphTrades(key, "sales") or {}) do
		if e.t >= X.Now() - 30 * 86400 and (e.count or 0) > 0 then
			marks[#marks + 1] = {t = e.t, v = e.money / e.count, color = {0.29, 0.87, 0.5},
				text = "You sold " .. e.count .. " at " .. X.MoneyPlain(e.money / e.count) .. " each"}
		end
	end
	g:SetSeries(series, {marks = marks, empty = "No prices yet - do a full scan at the auction house."})
end
S.DrawItemGraph = drawItemGraph

-- the entry for one item (Find, alt-click): what XNAH knows, and what pages add (S.itemActions)
S.itemActions = {} -- functions(key, entry): may set entry.button / button2 / sentence / why
function S.ItemEntry(key)
	local it = X.Items()[key]
	local cur = it and it.cur or {}
	local usual = X.Usual and X.Usual(key)
	local e = {id = "item:" .. key, key = key, title = X.ItemName(key), price = cur.min or cur.mkt}
	if cur.min and usual and usual > 0 then
		local p = (cur.min / usual - 1) * 100
		if p <= -5 then e.badge = GREEN .. string.format("%.0f%% cheaper than usual", -p) .. "|r"
		elseif p >= 5 then e.badge = RED .. string.format("%.0f%% dearer than usual", p) .. "|r"
		else e.badge = GREY .. "about its usual price|r" end
	end
	local rate = X.SaleRate and X.Try(X.SaleRate, key)
	e.sentence = usual and ("It usually sells for " .. X.MoneyPlain(usual) .. ".") or "XNAH has no usual price for it yet."
	e.why = (cur.qty and (X.Num(cur.qty) .. " listed at the last scan") or "Not seen on the auction house yet") ..
		(rate and (", about " .. X.Rate(rate) .. " sell a day.") or ".")
	e.lines = {}
	local vs = X.VendorSell(X.KeyID(key))
	if vs and vs > 0 then e.lines[#e.lines + 1] = {"Vendor pays", money(vs)} end
	local craft = X.CraftCost and X.CraftCost(X.KeyID(key))
	if craft then e.lines[#e.lines + 1] = {"Cost to craft", money(craft)} end
	local owned = X.Owned and X.Try(X.Owned, key)
	if owned and owned > 0 then e.lines[#e.lines + 1] = {"You own", X.Num(owned)} end
	e.button2 = {label = "All details", run = function() UI.ShowItem(key) end, tip = "Opens this item in the full window."}
	for _, f in ipairs(S.itemActions) do X.Try(f, key, e) end
	return e
end

-- the item's name inside a line in its rarity colour (Xn: names should be coloured like in the game)
function S.ColorName(text, key)
	if not key or text:find("|c", 1, true) then return text end
	local name, q = X.ItemName(key)
	if not name or name == "" or name:find("^item %-?%d+$") then return text end
	local a, b = text:find(name, 1, true)
	if not a then return text end
	return text:sub(1, a - 1) .. "|cff" .. (X.QUALITY_HEX[q or 1] or "ffffff") .. name .. "|r" .. text:sub(b + 1)
end

-- [[ the window ]]
local list, detail
local function showDetail(e)
	local d = detail
	d.entry = e
	if not e then
		d.icon:Hide() d.name:SetText("") d.price:SetText("") d.badge:SetText("")
		d.graph:Hide() d.sentence:SetText("") d.why:SetText("")
		for _, l in ipairs(d.lines) do l[1]:SetText("") l[2]:SetText("") end
		d.button:Hide() d.button2:Hide() d.skip:Hide()
		d.empty:Show()
		return
	end
	d.empty:Hide()
	d.icon.tex:SetTexture(e.icon or itemIcon(e.key))
	d.icon:Show()
	d.name:SetText(e.name or (e.key and X.ItemText(e.key)) or e.title or "")
	d.price:SetText(e.price and X.Money(e.price, true) or "")
	d.badge:SetText(e.badge or "")
	if e.graph == false or (not e.key and type(e.graph) ~= "function") then
		d.graph:Hide()
	else
		d.graph:Show()
		if type(e.graph) == "function" then X.Try(e.graph, d.graph, e) else X.Try(drawItemGraph, d.graph, e.key) end
	end
	-- the text block sits under the graph, or where the graph would be
	local top = d.graph:IsShown() and -262 or -60
	d.sentence:ClearAllPoints()
	d.sentence:SetPoint("TOPLEFT", 14, top)
	d.sentence:SetText(e.sentence or "")
	d.why:SetText(e.why or "")
	for i, l in ipairs(d.lines) do
		local v = e.lines and e.lines[i]
		l[1]:SetText(v and (GREY .. v[1] .. "|r") or "")
		l[2]:SetText(v and v[2] or "")
	end
	local function setButton(b, spec)
		if not spec then b:Hide() return end
		b:SetText(spec.label or "?")
		b:SetEnabled(not spec.disabled)
		b.spec = spec
		b:Show()
	end
	setButton(d.button, e.button)
	setButton(d.button2, e.button2)
	d.skip:SetShown(e.skip == true)
end

local function drawRow(row, e)
	row.icon:SetTexture(e.icon or itemIcon(e.key))
	row.title:SetText(S.ColorName(e.title or "", e.key))
	row.sub:SetText(e.sub or "")
	row:SetSelected(current.selected == e.id and not current.item)
	row:SetScript("OnClick", function(_, button)
		current.selected, current.item = e.id, nil
		list:Refresh()
		showDetail(e)
		if button == "RightButton" and e.key then UI.ItemMenu(row, e.key) end
	end)
	row:SetScript("OnEnter", function(self) if e.key then UI.ItemTooltip(self, e.key) end end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- works the current page's list out again; keeps the picked entry when it is still there
function S.Refresh()
	if not frame or not frame:IsShown() then return end
	local n = X.HomeNumbers and X.Try(X.HomeNumbers)
	if n and n.gold then
		frame.gold:SetText(X.Money(n.gold, true))
		frame.goldChange:SetText(n.goldToday and (signed(n.goldToday) .. GREY .. " today|r") or "")
	else
		frame.gold:SetText(GREY .. "-|r")
		frame.goldChange:SetText("")
	end
	for _, b in ipairs(frame.nav) do b:SetSelected(b.view == current.view) end
	local view = S.views[current.view]
	local entries, emptyText = {}, ""
	if view and view.list then
		local ok, a, b = pcall(view.list)
		if ok then entries, emptyText = a or {}, b or view.emptyText or "" else X.OnError(a) end
	end
	local shown = {}
	for _, e in ipairs(entries) do if not (e.skip and S.skipped[e.id]) then shown[#shown + 1] = e end end
	current.entries = shown
	frame.listTitle:SetText((view and view.title or "") .. (#shown > 0 and (GREY .. "  (" .. #shown .. ")|r") or ""))
	list:SetItems(shown, GREY .. emptyText .. "|r")
	if current.item then
		showDetail(S.ItemEntry(current.item))
		return
	end
	local pick
	for _, e in ipairs(shown) do if e.id == current.selected then pick = e break end end
	pick = pick or shown[1]
	current.selected = pick and pick.id or nil
	list:Refresh()
	showDetail(pick)
end
local function refreshSoon() X.Debounce("xnah-simple", 0.4, S.Refresh) end
S.RefreshSoon = refreshSoon
for _, ev in ipairs({"XNAH_PRICES", "XNAH_HOME", "XNAH_STRATEGY", "XNAH_INVENTORY", "XNAH_LEDGER", "XNAH_POSTED",
	"XNAH_POST", "XNAH_BUY", "XNAH_ROUTINE", "XNAH_AH", "XNAH_WATCH", "XNAH_CANCEL", "XNAH_RECIPES", "XNAH_ANALYSIS", "XNAH_SHOP", "BAG_UPDATE_DELAYED", "XNAH_IGNORE"}) do
	X.On(ev, refreshSoon)
end

function S.Select(viewKey)
	if not S.views[viewKey] then viewKey = S.order[1] end
	if current.view ~= viewKey then current.selected = nil end
	current.view, current.item = viewKey, nil
	X.S().simpleView = viewKey
	if list then list.offset = 0 end
	S.Refresh()
end
-- one item on the right (the list stays as it is, nothing picked in it)
function S.ShowItem(key)
	if not key then return end
	S.Open()
	current.item = key
	S.Refresh()
end

local function build()
	frame = CreateFrame("Frame", "XNAHSimple", UIParent, "BackdropTemplate")
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
		X.S().simpleWindow = {p, rp, x, y}
	end)
	frame:SetScale(UI.ClampScale and UI.ClampScale(X.S().uiScale) or 1)
	local pos = X.S().simpleWindow
	if pos and pos[1] then frame:ClearAllPoints() frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end
	tinsert(UISpecialFrames, "XNAHSimple")
	frame:SetScript("OnShow", function() S.Refresh() end)
	frame:SetScript("OnHide", function() K.CloseMenu() end)

	-- top: XNAH, your gold, Find, close
	local name = K.Label(frame, "|cffe6b422XNAH|r", "GameFontNormalLarge")
	name:SetPoint("TOPLEFT", 14, -12)
	local goldLabel = K.Label(frame, GREY .. "Your gold|r", "GameFontNormalSmall")
	goldLabel:SetPoint("LEFT", name, "RIGHT", 18, -1)
	frame.gold = K.Label(frame, "", "GameFontHighlightLarge")
	frame.gold:SetPoint("LEFT", goldLabel, "RIGHT", 8, 1)
	frame.goldChange = K.Label(frame, "", "GameFontHighlightSmall")
	frame.goldChange:SetPoint("LEFT", frame.gold, "RIGHT", 10, -1)
	local close = K.Button(frame, "X", 24, 20, function() frame:Hide() end)
	close:SetPoint("TOPRIGHT", -8, -10)
	local guide = K.Button(frame, "?", 24, 20, function() if X.ShowGuide then X.ShowGuide() end end)
	guide:SetPoint("RIGHT", close, "LEFT", -4, 0)
	K.Tooltip(guide, "Guide", "How XNAH works.")
	local find = K.Edit(frame, 180, function(text)
		local hits = X.QuickFind and X.QuickFind(text, 1) or {}
		K.CloseMenu()
		if hits[1] and hits[1].key then frame.find:SetText("") S.ShowItem(hits[1].key) end
	end)
	find:SetPoint("RIGHT", guide, "LEFT", -12, 0)
	frame.find = find
	local findLabel = K.Label(frame, "Find", "GameFontNormalSmall", "RIGHT")
	findLabel:SetPoint("RIGHT", find, "LEFT", -8, 0)
	find:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		X.Debounce("xnah-simple-find", 0.25, function()
			local text = self:GetText() or ""
			if not self:HasFocus() or #X.Trim(text) < 2 then K.CloseMenu() return end
			local items = {}
			for _, h in ipairs(X.QuickFind and X.QuickFind(text, 15) or {}) do
				items[#items + 1] = {text = h.text, disabled = h.key == nil, func = function()
					self:SetText("")
					self:ClearFocus()
					S.ShowItem(h.key)
				end}
			end
			if #items == 0 then items[1] = {text = "Nothing found", disabled = true} end
			K.Menu(self, items)
		end)
	end)

	-- left: the list
	local body = CreateFrame("Frame", nil, frame)
	body:SetPoint("TOPLEFT", 10, -TOP_H)
	body:SetPoint("BOTTOMRIGHT", -10, NAV_H + 6)
	local bodyH = H - TOP_H - NAV_H - 6
	frame.listTitle = K.Label(body, "", "GameFontNormal")
	frame.listTitle:SetPoint("TOPLEFT", 4, -2)
	list = K.List(body, LEFT_W, bodyH - 22, 38, drawRow)
	list:SetPoint("TOPLEFT", 0, -20)
	for _, row in ipairs(list.rows) do
		row.label:Hide()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(26, 26)
		row.icon:SetPoint("LEFT", 5, 0)
		row.title = K.Label(row, "", "GameFontHighlight")
		row.title:SetPoint("TOPLEFT", 38, -4)
		row.title:SetPoint("RIGHT", -4, 0)
		row.title:SetWordWrap(false)
		row.sub = K.Label(row, "", "GameFontHighlightSmall")
		row.sub:SetPoint("TOPLEFT", 38, -20)
		row.sub:SetPoint("RIGHT", -4, 0)
		row.sub:SetWordWrap(false)
	end
	S.list = list

	-- right: the picked entry
	local dw = W - 20 - LEFT_W - 10
	detail = K.Panel(body, dw, bodyH, {0, 0, 0, 0.25})
	detail:SetPoint("TOPLEFT", LEFT_W + 10, 0)
	detail.icon = CreateFrame("Button", nil, detail)
	detail.icon:SetSize(34, 34)
	detail.icon:SetPoint("TOPLEFT", 12, -12)
	detail.icon.tex = detail.icon:CreateTexture(nil, "ARTWORK")
	detail.icon.tex:SetAllPoints()
	detail.icon:SetScript("OnEnter", function(self) if detail.entry and detail.entry.key then UI.ItemTooltip(self, detail.entry.key) end end)
	detail.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
	detail.name = K.Label(detail, "", "GameFontNormalLarge")
	detail.name:SetPoint("TOPLEFT", 54, -12)
	detail.name:SetWidth(dw - 70)
	detail.name:SetWordWrap(false)
	detail.price = K.Label(detail, "", "GameFontHighlightLarge")
	detail.price:SetPoint("TOPLEFT", 54, -32)
	detail.badge = K.Label(detail, "", "GameFontHighlight")
	detail.badge:SetPoint("LEFT", detail.price, "RIGHT", 12, 0)
	detail.graph = K.Graph(detail, dw - 20, 196)
	detail.graph:SetPoint("TOPLEFT", 10, -58)
	detail.sentence = K.Label(detail, "", "GameFontHighlight")
	detail.sentence:SetWidth(dw - 28)
	detail.sentence:SetJustifyV("TOP")
	detail.why = K.Label(detail, "", "GameFontDisable")
	detail.why:SetPoint("TOPLEFT", detail.sentence, "BOTTOMLEFT", 0, -6)
	detail.why:SetWidth(dw - 28)
	detail.why:SetJustifyV("TOP")
	detail.lines = {}
	for i = 1, 4 do
		local l = K.Label(detail, "", "GameFontHighlightSmall")
		l:SetPoint("TOPLEFT", detail.why, "BOTTOMLEFT", ((i - 1) % 2) * 220, -10 - math.floor((i - 1) / 2) * 16)
		l:SetWidth(110)
		local v = K.Label(detail, "", "GameFontHighlightSmall", "RIGHT")
		v:SetPoint("LEFT", l, "RIGHT", 0, 0)
		v:SetWidth(100)
		detail.lines[i] = {l, v}
	end
	local function runSpec(self)
		local e, spec = detail.entry, self.spec
		if not (e and spec and spec.run) then return end
		local ok, err = pcall(spec.run, e, self)
		if not ok then X.OnError(err) end
		refreshSoon()
	end
	detail.button = K.Button(detail, "", 260, 30, runSpec)
	detail.button:SetPoint("BOTTOMLEFT", 14, 14)
	detail.button:SetScript("OnEnter", function(self)
		if self.spec and self.spec.tip then GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:AddLine(self.spec.tip, 1, 1, 1, true) GameTooltip:Show() end
	end)
	detail.button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	detail.button2 = K.Button(detail, "", 150, 30, runSpec)
	detail.button2:SetPoint("LEFT", detail.button, "RIGHT", 8, 0)
	detail.button2:SetScript("OnEnter", detail.button:GetScript("OnEnter"))
	detail.button2:SetScript("OnLeave", function() GameTooltip:Hide() end)
	detail.skip = K.Button(detail, "Skip", 70, 30, function()
		local e = detail.entry
		if e then S.skipped[e.id] = true end
		S.Refresh()
	end)
	detail.skip:SetPoint("BOTTOMRIGHT", -14, 14)
	K.Tooltip(detail.skip, "Skip", "Hides this until you log in again.")
	detail.empty = K.Label(detail, GREY .. "Pick something on the left.|r", "GameFontHighlight", "CENTER")
	detail.empty:SetPoint("CENTER")
	S.detail = detail

	-- bottom: the pages and More
	frame.nav = {}
	local x = 10
	for _, key in ipairs(S.order) do
		local v = S.views[key]
		local b = K.Flat(frame, 110, 26)
		b:SetPoint("BOTTOMLEFT", x, 8)
		b:SetLabel(v.title)
		b.label:SetJustifyH("CENTER")
		b.view = key
		b:SetScript("OnClick", function() S.Select(key) end)
		frame.nav[#frame.nav + 1] = b
		x = x + 114
	end
	local more = K.Button(frame, "More", 90, 26, function()
		frame:Hide()
		UI.Open(X.S().tab or "home")
	end)
	more:SetPoint("BOTTOMRIGHT", -10, 8)
	K.Tooltip(more, "More", "The full XNAH window with every page: scans and settings, crafting, the ledger, strategies and their numbers.")
	frame:Hide()
end

function S.Frame() return frame end
function S.Open(viewKey)
	if not frame then build() end
	frame:Show()
	if viewKey or not current.view then S.Select(viewKey or X.S().simpleView or "todo") else S.Refresh() end
end
function S.Toggle()
	if frame and frame:IsShown() then frame:Hide() else S.Open() end
end

-- /xnah, the key binding, the minimap button and the auction house bar open the simple window (setting simpleUI)
local fullToggle = X.Toggle
X.Toggle = function()
	if X.S().simpleUI then S.Toggle() else fullToggle() end
end
-- alt-click, Find and the panel at the auction house show items here too
local fullShowItem = X.ShowItem
X.ShowItem = function(key)
	if X.S().simpleUI and not (UI.Frame() and UI.Frame():IsShown()) then S.ShowItem(key) else fullShowItem(key) end
end
