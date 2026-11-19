-- The simple window's Wealth page: all your gold and what everything you own is worth (with its line over time), then
-- each character, then your best sellers this week. Nothing to press: it only tells (All details opens the full
-- window's Wealth page).
local ADDON, X = ...
local S = X.Simple
if not S then return end

local DAY = 86400
local GRAPH_DAYS = 90
local MAX_AGE = 60      -- seconds: the characters' worth is worked out again at least this often ...
local MIN_GAP = 5       -- ... and after a change, at most this often
local GREY, GREEN, RED, GOLD = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local BAG = "Interface\\Icons\\INV_Misc_Bag_10"
local NOTE = "Interface\\Icons\\INV_Misc_Note_01"
local WORTH_COLOR, GOLD_COLOR, SALES_COLOR = {0.9, 0.7, 0.13}, {0.29, 0.87, 0.5}, {1, 0.55, 0.2}

local chars, charsAt, dirty = nil, 0, true
X.On("XNAH_INVENTORY", function() dirty = true end)
X.On("XNAH_PRICES", function() dirty = true end)
local function getChars()
	local now = X.Now()
	if not chars or now - charsAt >= MAX_AGE or (dirty and now - charsAt >= MIN_GAP) then
		chars = X.Chars and X.Try(X.Chars) or {}
		charsAt, dirty = now, false
	end
	return chars
end

-- "12,480g" (whole gold from 100g on), else "12g 34s 56c"
local function goldText(c)
	if not c then return "-" end
	if math.abs(c) >= 1000000 then return X.Num(math.floor(c / 10000)) .. "g" end
	return X.MoneyPlain(c)
end
X.GoldText = goldText
local function pctOf(change, now)
	local before = (now or 0) - (change or 0)
	if not change or before <= 0 then return nil end
	return change / before * 100
end
local function pctText(p)
	if not p then return "" end
	return (p >= 0 and GREEN .. "+" or RED .. "-") .. string.format("%.1f%%", math.abs(p)) .. "|r"
end

-- gold per day from the daily notes (the first gold seen each day, per character): points {{t, copper}, ...}
local function goldPoints(charKey, from)
	local book = X.Realm().homeGold or {}
	local days = {}
	for d in pairs(book) do days[#days + 1] = d end
	table.sort(days)
	local out = {}
	for _, d in ipairs(days) do
		local t = d * DAY + DAY / 2
		if t >= from then
			local sum, any = 0, false
			for k, v in pairs(book[d]) do
				if not charKey or k == charKey then sum, any = sum + v, true end
			end
			if any then out[#out + 1] = {t, sum} end
		end
	end
	return out
end
X.WealthGoldPoints = goldPoints

local function drawWorth(g, charKey, nowWorth, nowGold)
	local from = X.Now() - GRAPH_DAYS * DAY
	local worth = X.WorthHistory and X.WorthHistory(charKey, from) or {}
	local gold = goldPoints(charKey, from)
	-- today's numbers at the end of the lines
	local now = X.Now()
	if nowWorth and worth[#worth] and worth[#worth][1] < now then worth[#worth + 1] = {now, nowWorth} end
	if nowGold and gold[1] then gold[#gold + 1] = {now, nowGold} end
	g:SetSeries({
		{points = worth, color = WORTH_COLOR, width = 2, label = "Everything"},
		{points = gold, color = GOLD_COLOR, width = 1.5, label = "Gold"},
	}, {empty = "XNAH notes what you own once a day when you play - come back tomorrow for a line."})
end

local function allEntry(n, list)
	local gold = n and n.gold or 0
	local nChars = n and n.chars or #list
	local worth = n and n.worth
	if not worth then
		worth = X.WarbankWorth and X.Try(X.WarbankWorth) or 0
		for _, c in ipairs(list) do worth = worth + (c.worth or 0) end
	end
	local gp = pctOf(n and n.goldWeek, gold)
	local wp = pctOf(n and n.worthWeek, worth)
	local e = {id = "wealth:all", icon = COIN, title = "All your gold", name = "All your gold", price = gold,
		badge = gp and (pctText(gp) .. GREY .. " this week|r") or nil}
	e.sub = GOLD .. goldText(gold) .. "|r" .. GREY .. " on " .. nChars .. " character" .. (nChars == 1 and "" or "s") .. "|r"
	e.sentence = "You have " .. goldText(gold) .. " on " .. nChars .. " character" .. (nChars == 1 and "" or "s") ..
		(gp and ("; " .. pctText(gp) .. " this week.") or ".")
	e.why = "With what your bags, banks, mail and auctions are worth you own about " .. goldText(worth) ..
		(wp and (" (" .. pctText(wp) .. " this week)") or "") ..
		". Items count at what they sell for after the auction house cut; soulbound ones at what a vendor pays."
	e.lines = {
		{"Gold", S.Money(gold)},
		{"Items", S.Money(math.max(0, worth - gold))},
		{"Gold this week", n and n.goldWeek and S.Signed(n.goldWeek) or (GREY .. "-|r")},
		{"Gold today", n and n.goldToday and S.Signed(n.goldToday) or (GREY .. "-|r")},
	}
	e.graph = function(g) drawWorth(g, nil, worth, gold) end
	e.button2 = {label = "All details", tip = "The full window's Wealth page: every character, place and item.",
		run = function()
			local f = S.Frame()
			if f then f:Hide() end
			X.UI.Open("wealth")
		end}
	return e
end

local function charEntry(c)
	local e = {id = "wealth:char:" .. c.name, icon = BAG, title = c.name, name = c.name, price = c.gold}
	e.sub = GOLD .. goldText(c.gold) .. "|r" .. GREY .. " gold, " .. goldText(c.worth) .. " in all|r"
	local items = (c.bags or 0) + (c.bank or 0) + (c.mail or 0) + (c.auctions or 0)
	e.sentence = c.name .. (c.me and " (playing now)" or "") .. " has " .. goldText(c.gold) .. " and things worth " ..
		goldText(items) .. "."
	local parts = {}
	for _, p in ipairs({{"bags", c.bags}, {"bank", c.bank}, {"mail", c.mail}, {"auctions", c.auctions}}) do
		if (p[2] or 0) > 0 then parts[#parts + 1] = p[1] .. " " .. goldText(p[2]) end
	end
	e.why = (#parts > 0 and ("In the " .. table.concat(parts, ", ") .. ". ") or "No items seen yet. ") ..
		(c.at and ("Last seen " .. X.Ago(c.at) .. ".") or "") ..
		(c.acct and (" From your other account (" .. tostring(c.acct) .. ").") or "")
	e.lines = {
		{"Gold", S.Money(c.gold)},
		{"Bags", S.Money(c.bags)},
		{"Bank", S.Money(c.bank)},
		{"Mail and auctions", S.Money((c.mail or 0) + (c.auctions or 0))},
	}
	local key, gold, worth = c.key or c.name, c.gold, c.worth
	e.graph = function(g) drawWorth(g, key, worth, gold) end
	return e
end

local function bestEntry(n)
	local top = n and n.top or {}
	if #top == 0 then return nil end
	local w = n.week or {}
	local first = top[1]
	local firstName = first.key and X.ItemName(first.key) or first.name or "?"
	local e = {id = "wealth:top", key = first.key, title = "Your best sellers this week",
		name = "Your best sellers this week", price = w.income, icon = not first.key and NOTE or nil}
	e.sub = GREY .. "sales brought |r" .. GOLD .. goldText(w.income or 0) .. "|r"
	e.sentence = "Best this week: " .. firstName .. " brought " .. goldText(first.income) .. " (" .. X.Num(first.units) ..
		" sold). Keep posting it."
	local others = {}
	for i = 2, #top do
		local t = top[i]
		others[#others + 1] = (t.key and X.ItemName(t.key) or t.name or "?") .. " " .. goldText(t.income)
	end
	e.why = "This week you sold " .. X.Num(w.units or 0) .. " things in " .. X.Num(w.sales or 0) .. " sales for " ..
		goldText(w.income or 0) .. " after the cut" .. (#others > 0 and ("; next: " .. table.concat(others, ", ")) or "") .. "."
	e.lines = {}
	for i = 1, math.min(4, #top) do
		local t = top[i]
		local nm = t.key and X.ItemName(t.key) or t.name or "?"
		if #nm > 18 then nm = nm:sub(1, 16) .. ".." end
		e.lines[i] = {nm, S.Money(t.income)}
	end
	-- the graph: what your sales brought each day, the last 30 days
	e.graph = function(g)
		local pts = {}
		for _, d in ipairs(X.LedgerDays and X.LedgerDays(30) or {}) do pts[#pts + 1] = {d.day * DAY + DAY / 2, d.income} end
		g:SetSeries({{points = pts, color = SALES_COLOR, width = 2, label = "Sales that day"}},
			{empty = "No sales in the ledger yet."})
	end
	return e
end

local function list()
	local n = X.HomeNumbers and X.Try(X.HomeNumbers)
	local cl = getChars()
	local out = {allEntry(n, cl)}
	for _, c in ipairs(cl) do out[#out + 1] = charEntry(c) end
	local best = bestEntry(n)
	if best then out[#out + 1] = best end
	return out, ""
end

S.AddView("wealth", {title = "Wealth", order = 5, list = list})
