-- Your gold view, "Your items" page (UI.AddGoldPage, order 6): your results per item, from the auction house mails
-- (Ledger.lua): sold, bought, average buying and selling price, total profit, profit of one, average time to sell and
-- sell-through. Read-only; click a row to open the item, right-click for the item menu. Every column header tells
-- what it means when you hover it.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, GREEN, RED, YELLOW = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"
local NONE = "|cff666666-|r"

local function M(v) return X.Money(v, true) end
local function plain(v) return (X.Money(v, true):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function signed(v)
	if not v then return NONE end
	if v >= 0 then return GREEN .. "+" .. plain(X.Round(v)) .. "|r" end
	return RED .. "-" .. plain(X.Round(-v)) .. "|r"
end
local function num(n) return (n and n > 0) and X.Num(n) or NONE end

-- seconds as "45m", "5h 20m", "2d 4h"
local function span(secs)
	if not secs then return nil end
	secs = math.max(0, X.Round(secs))
	if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. "m" end
	if secs < 86400 then
		local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
		return h .. "h" .. (m > 0 and (" " .. string.format("%02d", m) .. "m") or "")
	end
	local d, h = math.floor(secs / 86400), math.floor((secs % 86400) / 3600)
	return d .. "d" .. (h > 0 and (" " .. h .. "h") or "")
end
X.SpanText = span

local function timeCell(r)
	if not r.timeToSell then return NONE end
	return (r.ttsAtLeast and (GREY .. "over |r") or "") .. span(r.timeToSell)
end
local function sellThrough(r)
	if not r.sellThrough then return NONE end
	local pct = r.sellThrough * 100
	local col = pct >= 60 and GREEN or (pct >= 30 and YELLOW or RED)
	return col .. string.format("%.0f%%", pct) .. "|r"
end

local function since()
	local L = X.Ledger()
	return L.postsSince and X.Date(L.postsSince, "%b %d") or nil
end

local COLS = {
	{"Item", 260, "LEFT", text = function(r)
		if r.key then return UI.ItemCell(r.key) end
		return GREY .. (r.name or "?") .. "|r"
	end, sort = function(r) return r.key and (X.ItemName(r.key)) or r.name or "" end, desc = false},
	{"Sold", 54, "RIGHT", text = function(r) return num(r.sold) end, sort = function(r) return r.sold end},
	{"Bought", 58, "RIGHT", text = function(r) return num(r.bought) end, sort = function(r) return r.bought end},
	{"Avg buy", 86, "RIGHT", text = function(r) return UI.MoneyCell(r.avgBuy and X.Round(r.avgBuy)) end,
		sort = function(r) return r.avgBuy end},
	{"Avg sell", 86, "RIGHT", text = function(r) return UI.MoneyCell(r.avgSell and X.Round(r.avgSell)) end,
		sort = function(r) return r.avgSell end},
	{"Total profit", 96, "RIGHT", text = function(r) return (r.sold or 0) > 0 and signed(r.profit) or NONE end,
		sort = function(r) return (r.sold or 0) > 0 and r.profit or nil end},
	{"Profit each", 86, "RIGHT", text = function(r) return signed(r.profitEach) end, sort = function(r) return r.profitEach end},
	{"Time to sell", 92, "RIGHT", text = timeCell, sort = function(r) return r.timeToSell end},
	{"Sell-through", 84, "RIGHT", text = sellThrough, sort = function(r) return r.sellThrough end},
}
-- the hover line of each column (the time-to-sell one says since when XNAH counts)
local function tips()
	local from = since()
	return {
		"The item. Click a row to open it on the Items view; right-click for the item menu.",
		"How many you sold on the auction house (from the sale mails in your mailbox).",
		"How many you bought on the auction house (from the purchase mails).",
		"What you paid for one, on average. - = you never bought it there.",
		"What one sold for, on average, after the auction house cut. - = you never sold it there.",
		"What your sales brought (after the cut) minus what the units you sold cost you, at your average buying price. " ..
			"Units you never bought there (farmed, crafted) cost nothing here.",
		"Total profit divided by the units you sold.",
		"How long it took from putting an auction up to its sale, on average. XNAH learns when you put an auction up " ..
			"from your auctions list at the auction house (open the Auctions tab now and then), so this fills in from " ..
			(from and ("the day it started counting (" .. from .. ")") or "the day this version is installed") ..
			". - = no sale yet that XNAH could match with an auction it saw you put up. \"over\" = XNAH saw those " ..
			"auctions only later, so the real time was longer.",
		"How much of what you put up actually sold: units sold out of units sold + expired + cancelled (from the mails). " ..
			"Auctions still running do not count yet. - = you never put it up (only bought it).",
	}
end

-- the item column takes the room the others leave (the list keeps 20 for its edges and scroll bar)
local function fit(columns, w)
	local fixed = 0
	for i = 2, #columns do fixed = fixed + columns[i][2] end
	local out = {}
	for i, c in ipairs(columns) do out[i] = c end
	local first = columns[1]
	out[1] = {first[1], math.max(140, w - 20 - fixed), first[3], text = first.text, sort = first.sort, desc = first.desc}
	return out
end

local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

-- the rows are made again only after new mails (or a new day)
local dirty = true
X.On("XNAH_LEDGER", function() dirty = true end)
X.On("XNAH_LOGIN", function() dirty = true end)

-- the line over the table: how many items, and over all of them the sell-through and the time to sell
function X.GoldItemsSummary(rows)
	local sold, posted, tts, ttsN, late = 0, 0, 0, 0, 0
	for _, r in ipairs(rows) do
		sold = sold + (r.sold or 0)
		posted = posted + (r.posted or 0)
		if r.timeToSell and (r.ttsUnits or 0) > 0 then
			if r.ttsAtLeast then late = late + r.ttsUnits
			else tts, ttsN = tts + r.timeToSell * r.ttsUnits, ttsN + r.ttsUnits end
		end
	end
	return {items = #rows, sellThrough = posted > 0 and sold / posted or nil, timeToSell = ttsN > 0 and tts / ttsN or nil,
		ttsUnits = ttsN, lateUnits = late}
end

local function build(f, w, h)
	f.note = K.Label(f, "", "GameFontDisableSmall")
	f.note:SetPoint("TOPLEFT", 0, -2)
	f.note:SetWidth(w)
	f.note:SetWordWrap(false)
	local columns = fit(COLS, w)
	for i, c in ipairs(columns) do c.tip = function() return tips()[i] end end -- the hover line of each column title
	f.tbl = K.Table(f, w, h - 20, columns, onRow)
	f.tbl:SetPoint("TOPLEFT", 0, -20)
	f.tbl:SortBy(6, true) -- total profit, most first
	-- the note tells more when hovered
	local hot = CreateFrame("Frame", nil, f)
	hot:SetPoint("TOPLEFT", 0, 0)
	hot:SetSize(w, 18)
	hot:EnableMouse(true)
	K.Tooltip(hot, "Your items", "Everything you sold or bought on the auction house, from the mails XNAH read in your " ..
		"mailbox (sold, bought, expired, cancelled). Time to sell also needs your auctions list: open the Auctions tab of " ..
		"the auction house now and then. Hover a column name to see what it means.")
end

local function refresh(f)
	if dirty or not f.rows or f.day ~= X.Day() then
		f.rows = X.LedgerByItem()
		f.day = X.Day()
		dirty = false
		f.tbl:SetRows(f.rows, "Nothing yet. Open your mailbox: XNAH reads the auction house mails there (sold, bought, " ..
			"expired, cancelled).")
		local s = X.GoldItemsSummary(f.rows)
		local parts = {}
		if s.sellThrough then parts[#parts + 1] = "sold " .. string.format("%.0f%%", s.sellThrough * 100) .. " of what you put up" end
		if s.timeToSell then
			parts[#parts + 1] = "average time to sell " .. span(s.timeToSell) .. " (" .. X.Num(s.ttsUnits) .. " sold)"
		elseif s.lateUnits > 0 then
			parts[#parts + 1] = "time to sell: only rough numbers yet (XNAH saw those auctions late)"
		else
			parts[#parts + 1] = "time to sell: no numbers yet (it fills in as XNAH sees you put auctions up)"
		end
		f.note:SetText(GREY .. "All items: " .. table.concat(parts, "; ") .. ". Click a row to open the item.|r")
	end
	return X.Num(#f.rows) .. (#f.rows == 1 and " item" or " items")
end

UI.AddGoldPage("results", "Your items", build, refresh, 6,
	"Your results per item: profit, time to sell, sell-through.")
