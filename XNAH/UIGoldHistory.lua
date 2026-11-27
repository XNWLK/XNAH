-- Your gold view, "Gold over time" page (UI.AddGoldPage, order 5): read-only.
--   tiles: gold now, its change over 7 and 30 days, your best week and your average profit a week
--   buttons: the range (7 days / 30 days / 90 days / 1 year), which lines the top graph shows (all characters together,
--     net worth, each character - picked in a small menu)
--   top graph: gold of each character and of all of them together (X.GoldHistory, Inventory.lua), and net worth
--     (X.WorthHistory), one point a day, with a legend
--   bottom graph: profit per week (sales after the cut minus purchases, X.LedgerWeeks) and its 4-week average
-- Worked out again only when the gold, the items or the ledger changed, or another range / line was picked.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED = "|cff999999", "|cff4ade80", "|cfff87171"
local NONE = "|cff666666-|r"
local DAY = 86400
local RANGES = {{"7 days", 7}, {"30 days", 30}, {"90 days", 90}, {"1 year", 365}}
local AVG_WEEKS = 4                 -- the profit trend line: the average of this many weeks
local ACCOUNT, WORTH = "~all", "~worth" -- keys of the two lines that are not one character (in goldHistHide)
local GOLD_COLOR, WORTH_COLOR = {1, 0.82, 0}, {0.55, 0.95, 0.9}
local CHAR_COLORS = {{0.4, 0.75, 1}, {0.29, 0.87, 0.5}, {0.97, 0.44, 0.44}, {0.8, 0.55, 1}, {1, 0.6, 0.25},
	{0.95, 0.6, 0.8}, {0.75, 0.75, 0.75}, {0.7, 0.9, 0.35}}
local TILES = {
	{"Gold now", "The gold of all your characters on this realm (both factions) right now. Next to it: how many " ..
		"characters that is."},
	{"Change, 7 days", "How much the gold of all your characters changed over the last 7 days. XNAH notes the gold every " ..
		"day it sees it; when it has not seen 7 days yet, the change covers the days it has (told next to it)."},
	{"Change, 30 days", "The same over the last 30 days."},
	{"Best week", "Your best week of profit (auction house sales after the cut minus what you bought there) among the " ..
		"weeks in the profit graph below. Next to it: the Monday it started."},
	{"Profit a week", "Your average profit a week over the weeks in the profit graph below (only weeks since XNAH has " ..
		"read your auction house mails count). Next to it: how many weeks."},
}

X.Default("goldHistRange", 2)
X.Default("goldHistHide", {}) -- [character key or "~all" / "~worth"] = true: that line is not drawn

local function plain(v) return (X.Money(v, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function signed(v)
	if not v then return nil end
	if v >= 0 then return GREEN .. "+" .. plain(X.Round(v)) .. "|r" end
	return RED .. "-" .. plain(X.Round(-v)) .. "|r"
end
local function hidden() return X.S().goldHistHide or {} end
local function rangeIdx()
	local i = tonumber(X.S().goldHistRange) or 2
	if not RANGES[i] then i = 2 end
	return i
end

-- [[ the numbers ]] cached until something changes
local cache, dirty = nil, true
local function markDirty() dirty = true end
for _, e in ipairs({"XNAH_LEDGER", "XNAH_INVENTORY", "XNAH_LOGIN"}) do X.On(e, markDirty) end

-- the day of the ledger's oldest entry (weeks before it are not counted for the profit tiles), nil when empty
local function ledgerFirstDay()
	local L = X.Ledger()
	local first
	for _, name in ipairs({"sales", "buys", "expired", "cancelled"}) do
		for _, e in ipairs(L[name] or {}) do
			if e.t and (not first or e.t < first) then first = e.t end
		end
	end
	return first and X.Day(first) or nil
end

-- the change of the gold of all characters from `days` ago (or the oldest day known) to now: change, days covered
local function change(points, days)
	local last = points[#points]
	if not last then return nil end
	local today = X.Day()
	local want = today - days
	local from
	for _, p in ipairs(points) do
		if X.Day(p[1]) >= want then from = p break end
	end
	if not from or from == last then return nil end
	return last[2] - from[2], today - X.Day(from[1])
end

-- X.GoldHistoryNumbers(rangeIndex) -> {gold, chars, change7, days7, change30, days30, weeks = {{start, profit, avg}},
-- best (the best week), avgWeek, nWeeks, lines = series for the top graph}; also for the tests
function X.GoldHistoryNumbers(ri)
	ri = ri or rangeIdx()
	local days = RANGES[ri][2]
	local today = X.Day()
	local hide = hidden()
	local n = {}
	-- tiles: gold now and its change (all characters, whatever lines are hidden)
	local chars = X.GoldChars()
	local gold = 0
	for _, c in ipairs(chars) do gold = gold + (c.gold or 0) end
	n.gold, n.chars = #chars > 0 and gold or nil, #chars
	local all30 = X.GoldHistory(nil, today - 30)
	n.change7, n.days7 = change(all30, 7)
	n.change30, n.days30 = change(all30, 30)
	-- the top graph
	local from = today - days
	local lines = {}
	if not hide[ACCOUNT] then
		local pts = X.GoldHistory(nil, from)
		if #pts > 0 then lines[#lines + 1] = {points = pts, label = "All characters", color = GOLD_COLOR, width = 3} end
	end
	if not hide[WORTH] then
		local pts = X.WorthHistory(nil, from * DAY)
		if #pts > 0 then lines[#lines + 1] = {points = pts, label = "Net worth", color = WORTH_COLOR, width = 2} end
	end
	for i, c in ipairs(chars) do
		if not hide[c.key] then
			local pts = X.GoldHistory(c.key, from)
			if #pts > 0 then
				lines[#lines + 1] = {points = pts, label = c.key, color = CHAR_COLORS[(i - 1) % #CHAR_COLORS + 1], width = 1.5}
			end
		end
	end
	n.lines = lines
	-- profit per week: the weeks of the range (at least 4), and AVG_WEEKS - 1 more before them for the average
	local nWeeks = math.max(4, math.ceil(days / 7))
	local all = X.LedgerWeeks(nWeeks + AVG_WEEKS - 1)
	local firstDay = ledgerFirstDay()
	local firstWeek = firstDay and X.LedgerWeekOf(firstDay) or nil
	n.weeks = {}
	local sum, counted = 0, 0
	for i = AVG_WEEKS, #all do
		local wk = all[i]
		local s, c = 0, 0
		for j = i - AVG_WEEKS + 1, i do
			if firstWeek and all[j].week >= firstWeek then s, c = s + all[j].profit, c + 1 end
		end
		local row = {start = wk.start, profit = wk.profit, avg = c > 0 and s / c or nil, counted = firstWeek and wk.week >= firstWeek}
		n.weeks[#n.weeks + 1] = row
		if row.counted then
			sum, counted = sum + wk.profit, counted + 1
			if not n.best or wk.profit > n.best.profit then n.best = row end
		end
	end
	n.avgWeek = counted > 0 and sum / counted or nil
	n.nWeeks = counted
	return n
end

-- [[ the page ]]
local function setButtons(f)
	local ri = rangeIdx()
	for i, b in ipairs(f.ranges) do b:SetSelected(i == ri) end
	local hide = hidden()
	f.accountBtn:SetSelected(not hide[ACCOUNT])
	f.worthBtn:SetSelected(not hide[WORTH])
	local chars = X.GoldChars()
	local shown = 0
	for _, c in ipairs(chars) do if not hide[c.key] then shown = shown + 1 end end
	f.charsBtn:SetLabel("Characters (" .. shown .. " of " .. #chars .. ")")
end

local function refresh(f)
	local key = rangeIdx()
	local hide = hidden()
	local sig = {tostring(key), tostring(X.Day())}
	for k, v in pairs(hide) do if v then sig[#sig + 1] = k end end
	table.sort(sig)
	local sigText = table.concat(sig, "|")
	setButtons(f)
	if dirty or not cache or cache.sig ~= sigText then
		cache = X.GoldHistoryNumbers(key)
		cache.sig = sigText
		dirty = false
		f.drawn = false
	end
	local n = cache
	if not f.drawn then
		f.drawn = true
		local t = f.tiles
		UI.SetTile(t[1], n.gold and X.Money(n.gold, true) or nil, n.chars > 0 and (n.chars .. (n.chars == 1 and " character" or " characters")) or nil)
		UI.SetTile(t[2], signed(n.change7), n.days7 and n.days7 < 7 and (n.days7 .. (n.days7 == 1 and " day" or " days")) or nil)
		UI.SetTile(t[3], signed(n.change30), n.days30 and n.days30 < 30 and (n.days30 .. (n.days30 == 1 and " day" or " days")) or nil)
		UI.SetTile(t[4], n.best and signed(n.best.profit) or nil, n.best and X.Date(n.best.start * DAY + 43200, "%b %d") or nil)
		UI.SetTile(t[5], signed(n.avgWeek), n.nWeeks > 0 and (n.nWeeks .. (n.nWeeks == 1 and " week" or " weeks")) or nil)
		f.gold:SetSeries(n.lines, {legend = true, empty = "No gold history yet: XNAH notes the gold of your characters " ..
			"every day it sees it (from the day this version is installed). Log in and play a little."})
		local prof, avg, any = {}, {}, false
		for _, wk in ipairs(n.weeks) do
			local t = wk.start * DAY + 43200
			if wk.counted then
				prof[#prof + 1] = {t, wk.profit}
				if wk.avg then avg[#avg + 1] = {t, wk.avg} end
				any = true
			end
		end
		f.profit:SetSeries(any and {
			{points = prof, label = "Profit of the week", color = {0.29, 0.87, 0.5}, width = 1.5},
			{points = avg, label = AVG_WEEKS .. "-week average", color = GOLD_COLOR, width = 2.5},
		} or {}, {legend = true, levels = {{v = 0, color = {0.6, 0.6, 0.6}, label = "0"}},
			empty = "No sales or purchases yet - open your mailbox after selling or buying (XNAH reads the auction house mails)"})
	end
	local range = RANGES[key][1]:gsub("^1 ", "")
	return "last " .. range
end

-- the menu of lines: all characters together, net worth, each character
local function linesMenu(f, anchor)
	local hide = hidden()
	local function toggle(k)
		local S = X.S()
		S.goldHistHide = S.goldHistHide or {}
		S.goldHistHide[k] = (not S.goldHistHide[k]) or nil
		refresh(f)
		linesMenu(f, anchor) -- open again: pick several in a row
	end
	local items = {{text = "Lines on the gold graph", isTitle = true},
		{text = "All characters together", checked = not hide[ACCOUNT], func = function() toggle(ACCOUNT) end},
		{text = "Net worth (gold and items)", checked = not hide[WORTH], func = function() toggle(WORTH) end}}
	local chars = X.GoldChars()
	if #chars > 0 then items[#items + 1] = {text = "Characters", isTitle = true} end
	for _, c in ipairs(chars) do
		local k = c.key
		items[#items + 1] = {text = k .. GREY .. "  " .. plain(c.gold) .. "|r", checked = not hide[k], func = function() toggle(k) end}
	end
	items[#items + 1] = {text = "Show every character", func = function()
		local S = X.S()
		for _, c in ipairs(X.GoldChars()) do if S.goldHistHide then S.goldHistHide[c.key] = nil end end
		refresh(f)
	end}
	items[#items + 1] = {text = "Hide every character", func = function()
		local S = X.S()
		S.goldHistHide = S.goldHistHide or {}
		for _, c in ipairs(X.GoldChars()) do S.goldHistHide[c.key] = true end
		refresh(f)
	end}
	K.Menu(anchor, items)
end

local function build(f, w, h)
	f.tiles = UI.NumberTiles(f, w, TILES, 0)
	local y = -54
	f.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(f, 64, 20)
		b:SetPoint("TOPLEFT", (i - 1) * 68, y)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().goldHistRange = i refresh(f) end)
		local range = r[1]:gsub("^1 ", "")
		K.Tooltip(b, r[1], "Show the last " .. range .. " in both graphs (the profit graph shows at least 4 weeks).")
		f.ranges[i] = b
	end
	local x = #RANGES * 68 + 16
	local function chip(text, width, tip, onClick)
		local b = K.Flat(f, width, 20)
		b:SetPoint("TOPLEFT", x, y)
		b:SetLabel(text)
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", onClick)
		K.Tooltip(b, text, tip)
		x = x + width + 4
		return b
	end
	local function flip(k)
		local S = X.S()
		S.goldHistHide = S.goldHistHide or {}
		S.goldHistHide[k] = (not S.goldHistHide[k]) or nil
		refresh(f)
	end
	f.accountBtn = chip("All characters", 110, "Show or hide the thick gold line: the gold of all your characters on this " ..
		"realm added up.", function() flip(ACCOUNT) end)
	f.worthBtn = chip("Net worth", 90, "Show or hide your net worth: gold and items of all your characters (and the account " ..
		"bank), items at their auction house price after the cut. Noted once a day.", function() flip(WORTH) end)
	f.charsBtn = chip("Characters", 150, "Pick which characters get their own line (their gold). Lit buttons and ticked " ..
		"lines are shown.", function(self) linesMenu(f, self) end)
	local help = K.Label(f, GREY .. "Gold = the gold your characters carry (not items). Between two notes the gold counts " ..
		"as unchanged.|r", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", x + 8, y - 4)
	help:SetWidth(math.max(40, w - x - 8))
	help:SetWordWrap(false)

	local gy = 80
	local gt = K.Label(f, "Gold over time " .. GREY .. "(one point a day; hover the graph for the numbers)|r", "GameFontNormalSmall")
	gt:SetPoint("TOPLEFT", 4, -gy)
	f.gold = K.Graph(f, w, 232)
	f.gold:SetPoint("TOPLEFT", 0, -gy - 16)
	local py = gy + 16 + 232 + 8
	local pt = K.Label(f, "Profit per week " .. GREY .. "(sales after the cut minus purchases; weeks start on Monday; " ..
		"the " .. AVG_WEEKS .. "-week average shows the trend)|r", "GameFontNormalSmall")
	pt:SetPoint("TOPLEFT", 4, -py)
	f.profit = K.Graph(f, w, math.max(80, h - py - 16))
	f.profit:SetPoint("TOPLEFT", 0, -py - 16)
end

UI.AddGoldPage("history", "Gold over time", build, refresh, 5,
	"Your gold, net worth and profit per week over time.")
