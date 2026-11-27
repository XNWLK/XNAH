-- Trends view, Item groups page (UI.AddTrendsPage, order 2): a table of the item groups (X.ItemGroup: Trade Goods,
-- Armor ...) and their subgroups (Cloth, Herb ...) with how many items, units and gold are listed now, how their
-- prices moved over 7 and 30 days (each group's own market index) and how the number listed changed in 7 days.
-- Clicking a group shows its index line on the right and the items of it that rose and fell the most (click one to
-- see it on the Items view). The numbers come from X.TrendsData (Trends.lua), worked out a little per frame.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local LIST_W = 640
local RX = LIST_W + 16      -- the right side
local MOVERS = 40           -- rows in each movers list

X.Default("trendsGroup", "all") -- the group picked on this page (its key)

local refresh

local function pct(v) return UI.TrendsPct(v) end
local COLUMNS = {
	{"Group", 210, "LEFT", text = function(r)
		local sel = r.gk == X.S().trendsGroup
		local name = (r.depth == 1 and "     " or "") .. r.name
		return sel and ("|cffffd100> " .. name .. "|r") or name
	end, sort = function(r) return r.name:lower() end, desc = false},
	{"Items", 54, "RIGHT", text = function(r) return X.Num(r.items) end, sort = function(r) return r.items end},
	{"Listed", 64, "RIGHT", text = function(r) return X.Num(r.units) end, sort = function(r) return r.units end},
	{"Gold listed", 100, "RIGHT", text = function(r) return r.gold > 0 and X.Money(r.gold, true) or NONE end,
		sort = function(r) return r.gold end},
	{"Price 7d", 64, "RIGHT", text = function(r) return pct(r.p7) end, sort = function(r) return r.p7 end},
	{"Price 30d", 64, "RIGHT", text = function(r) return pct(r.p30) end, sort = function(r) return r.p30 end},
	{"Supply 7d", 64, "RIGHT", text = function(r) return pct(r.supply) end, sort = function(r) return r.supply end},
}
local TIPS = {
	"The game's item groups, and under each its subgroups (for trade goods: Cloth, Herb, Metal & Stone ...). Click one " ..
		"to see its price line and its biggest movers on the right.",
	"How many different items of this group XNAH knows (listed now or not).",
	"How many units of this group are listed on the auction house now (at the last scan).",
	"Roughly how much gold is listed in this group now: the units listed times each item's market value.",
	"How the group's prices moved in the last 7 days: its own market index (the typical item's price change).",
	"How the group's prices moved in the last 30 days.",
	"How the number of units listed changed against 7 days ago (items known then). Up = more for sale, down = fewer.",
}
local MOVER_TIPS = {
	"The item. Click to see it on the Items view.",
	"Its price (market value of the day) at the start: 30 days ago, or when XNAH first saw it in that time.",
	"Its price now (the latest day).",
	"How much its price changed since then.",
}

-- one row per group and subgroup (and All items at the top)
local function makeRows(res)
	local rows = {}
	local i7, i30 = res.index[7], res.index[30]
	for gk, s in pairs(res.groups or {}) do
		local name, parent = X.TrendsGroupName(gk)
		if gk == "all" then name = "All items" end
		local function change(idx)
			local v = idx and idx.last[gk]
			return v and (v - 100) or nil
		end
		rows[#rows + 1] = {gk = gk, name = name, parent = parent, depth = parent and 1 or 0, items = s.items, units = s.units,
			gold = s.gold, p7 = change(i7), p30 = change(i30), supply = s.supply, top = gk == "all"}
	end
	return rows
end
X.TrendsGroupRows = makeRows

-- sorting keeps each subgroup under its group (All items stays on top)
local function sortRows(tbl)
	local c = tbl.sortCol and tbl.columns[tbl.sortCol]
	local f = c and c.sort
	local desc = tbl.sortDesc
	local master = tbl.master or {}
	local vals = {}
	for _, r in ipairs(master) do vals[r] = f and f(r) or r.name:lower() end
	local function cmp(a, b)
		local va, vb = vals[a], vals[b]
		if va == vb or (va == nil and vb == nil) then return a.name < b.name end
		if va == nil then return false end
		if vb == nil then return true end
		if not f then return va < vb end
		if desc then return va > vb end
		return va < vb
	end
	local tops, subs, out = {}, {}, {}
	for _, r in ipairs(master) do
		if r.top then out[1] = r
		elseif r.parent then subs[r.parent] = subs[r.parent] or {} table.insert(subs[r.parent], r)
		else tops[#tops + 1] = r end
	end
	table.sort(tops, cmp)
	for _, r in ipairs(tops) do
		out[#out + 1] = r
		local list = subs[r.name]
		if list then
			table.sort(list, cmp)
			for _, s in ipairs(list) do out[#out + 1] = s end
		end
	end
	tbl.items = out
	for i, hdr in ipairs(tbl.headers or {}) do
		local m = (i == tbl.sortCol) and (tbl.sortDesc and " v" or " ^") or ""
		hdr:SetText(GREY .. tbl.columns[i][1] .. m .. "|r")
	end
	tbl:Refresh()
end

-- puts x into the sorted list (better(a, b) = a first) when it is among the best MOVERS so far
local function keepBest(list, x, better)
	local n = #list
	if n >= MOVERS and not better(x, list[n]) then return end
	local pos = n + 1
	while pos > 1 and better(x, list[pos - 1]) do pos = pos - 1 end
	table.insert(list, pos, x)
	if #list > MOVERS then list[#list] = nil end
end

local function moverTable(page, y, h, title, tip)
	local rw = page.rw
	local label = K.Label(page, title, "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", RX, y)
	local hot = CreateFrame("Frame", nil, page)
	hot:SetAllPoints(label)
	hot:EnableMouse(true)
	K.Tooltip(hot, title, tip)
	local cols = {
		{"Item", rw - 20 - 64 - 64 - 52, "LEFT", text = function(r) return UI.ItemCell(r.key) end,
			sort = function(r) return (X.ItemName(r.key) or ""):lower() end, desc = false},
		{"Then", 64, "RIGHT", text = function(r) return UI.MoneyCell(r.base) end, sort = function(r) return r.base end},
		{"Now", 64, "RIGHT", text = function(r) return UI.MoneyCell(r.now) end, sort = function(r) return r.now end},
		{"Change", 52, "RIGHT", text = function(r) return UI.TrendsPct((r.r - 1) * 100, 0) end, sort = function(r) return r.r end},
	}
	for i, c in ipairs(cols) do c.tip = MOVER_TIPS[i] end -- the hover line of each column title
	local tbl = K.Table(page, rw, h, cols, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	tbl:SetPoint("TOPLEFT", RX, y - 34)
	return tbl
end

local function build(page, w, h)
	page.rw = w - RX
	for i, c in ipairs(COLUMNS) do c.tip = TIPS[i] end -- the hover line of each column title
	local tbl = K.Table(page, LIST_W, h - 18 - 22, COLUMNS, function(row)
		X.S().trendsGroup = row.gk
		refresh(page)
	end)
	tbl:SetPoint("TOPLEFT", 0, -18)
	tbl:SortBy(4, true) -- gold listed, most first
	tbl.Sort = sortRows
	page.tbl = tbl
	page.foot = K.Label(page, GREY .. "Click a group: its price line and its biggest movers on the right.|r", "GameFontDisableSmall")
	page.foot:SetPoint("BOTTOMLEFT", 2, 4)
	page.foot:SetWidth(LIST_W)
	page.foot:SetWordWrap(false)
	-- the right side: the picked group
	page.title = K.Label(page, "", "GameFontNormal")
	page.title:SetPoint("TOPLEFT", RX, 0)
	page.title:SetWidth(page.rw)
	page.title:SetWordWrap(false)
	page.sub = K.Label(page, GREY .. "Its price index of the last 30 days (100 = prices 30 days ago).|r", "GameFontHighlightSmall")
	page.sub:SetPoint("TOPLEFT", RX, -18)
	page.sub:SetWidth(page.rw)
	page.sub:SetWordWrap(false)
	page.graph = K.Graph(page, page.rw, 186)
	page.graph:SetPoint("TOPLEFT", RX, -36)
	page.risers = moverTable(page, -232, 132, "Rising most (30 days)",
		"The items of this group whose price went up the most in the last 30 days (items with enough days of prices).")
	page.fallers = moverTable(page, -406, h - 406 - 34, "Falling most (30 days)",
		"The items of this group whose price went down the most in the last 30 days.")
	page.risers:SortBy(4, true)
	page.fallers:SortBy(4, false)
end

refresh = function(page)
	local res, busy, progress = X.TrendsData()
	if not res then
		page.tbl.master = {}
		page.tbl:SetRows({}, busy and ("Working it out ... " .. (progress or "")) or "No prices yet. Open the auction house and do a full scan.")
		page.title:SetText("")
		page.graph:SetSeries({}, {empty = busy and "Working it out ..." or "No prices yet"})
		page.risers:SetRows({}, "")
		page.fallers:SetRows({}, "")
		return busy and "working ..." or nil
	end
	local rows = makeRows(res)
	page.tbl.master = rows
	page.tbl:SetRows(rows, "No items known yet.")
	-- the picked group (All items when it is not there any more)
	local gk = X.S().trendsGroup
	if not (res.groups and res.groups[gk]) then gk = "all" X.S().trendsGroup = gk end
	local name, parent = X.TrendsGroupName(gk)
	if gk == "all" then name, parent = "All items", nil end
	page.title:SetText(name .. (parent and (GREY .. "  (" .. parent .. ")|r") or ""))
	local idx = res.index[30]
	local line = idx and idx.lines[gk]
	page.graph:SetSeries(line and {{points = line, label = X.TrendsGroupLabel(gk), color = {1, 1, 1}, width = 2}} or {},
		{labels = "number", levels = {{v = 100, color = {0.6, 0.6, 0.6}, label = "start"}},
		empty = "Fewer than 3 items of this group have enough days of prices for a line yet."})
	-- the biggest movers: only the best MOVERS of each kept while going through the items (sorting all of them - several
	-- thousand on a real auction house - took too long for one frame)
	local up, down = {}, {}
	local function rises(a, b) if a.r ~= b.r then return a.r > b.r end return a.key < b.key end
	local function falls(a, b) if a.r ~= b.r then return a.r < b.r end return a.key < b.key end
	for _, it in ipairs(idx and idx.items or {}) do
		if gk == "all" or it.g == gk or it.leaf == gk then
			if it.r > 1.005 then keepBest(up, it, rises) elseif it.r < 0.995 then keepBest(down, it, falls) end
		end
	end
	page.risers:SetRows(up, "No item of this group rose in this time.")
	page.fallers:SetRows(down, "No item of this group fell in this time.")
	local n = 0
	for _, r in ipairs(rows) do if not r.top then n = n + 1 end end
	page.foot:SetText(GREY .. "Click a group: its price line and its biggest movers on the right.|r" ..
		(busy and ("   " .. (progress or "")) or ""))
	return X.Num(n) .. " groups"
end

UI.AddTrendsPage("groups", "Item groups", build, refresh, 2,
	"Each item group: how much is listed, and how its prices and supply moved. Click a group for its line and movers.")
