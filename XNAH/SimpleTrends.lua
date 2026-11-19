-- The simple window's Trends page: the items whose price moves most, going up or going down, that are worth knowing
-- about (sold often enough, worth a few silver, a fresh price, a move bigger than the usual day-to-day jumps).
-- Each entry: its graph, what to do in one sentence, why (the numbers in words), Watch it, and Sell it when you own some.
-- The items are picked in a pass over all prices in slices (at most once a minute, after new prices); the page only
-- reads the result, so listing it is cheap.
local ADDON, X = ...
local S = X.Simple
if not S then return end

local DAY = 86400
local MAX = 20          -- entries at most
local MAX_KIND = 12     -- at most this many going up (or going down)
local MIN_TREND = 5     -- % a week: smaller moves are not news
local MAX_TREND = 400   -- % a week: bigger ones are mistakes in the data
local MIN_PRICE = 500   -- copper: cheaper items are left out
local MIN_LISTED = 5    -- usually this many listed at least
local SLICE = 300       -- items looked at per frame
local MIN_GAP = 60      -- seconds: never worked out more often
local MAX_AGE = 600     -- seconds: worked out again at least this often
local GREY, GREEN, RED = "|cff999999", "|cff4ade80", "|cfff87171"

local rows, rowsAt, dirty, running, waiting = nil, 0, true, false, false
X.On("XNAH_PRICES", function() dirty = true end)

-- the price about a week ago: the last point 6 or more days old, within the last 9 days
local function weekAgo(key, now)
	local v
	for _, p in ipairs(X.History(key, now - 9 * DAY)) do
		if p[1] > now - 6 * DAY then break end
		v = p[3] or p[2] or v
	end
	return v
end

local function pass()
	running = true
	local items = X.Items()
	local minDays = X.S().minSamples or 3
	local keys, k, found = nil, 0, {}
	X.Job("simple trends", function()
		if not keys then
			keys = {}
			for key in pairs(items) do keys[#keys + 1] = key end
			return #keys == 0
		end
		local stop = math.min(#keys, k + SLICE)
		while k < stop do
			k = k + 1
			local key = keys[k]
			local it = items[key]
			if it and it.cur and X.Fresh(it) then
				local st = X.Stats(it)
				local tr = st and st.trend
				if tr and st.days >= minDays and math.abs(tr) >= MIN_TREND and math.abs(tr) <= MAX_TREND and
					(not st.vol or math.abs(tr) >= st.vol * 0.5) then
					local price = X.Price(key)
					local listed = math.max(st.qty7 or 0, it.cur.qty or 0)
					if price and price >= MIN_PRICE and listed >= MIN_LISTED then
						found[#found + 1] = {key = key, trend = tr, price = price, st = st}
					end
				end
			end
		end
		return k >= #keys
	end, function()
		table.sort(found, function(a, b)
			if math.abs(a.trend) ~= math.abs(b.trend) then return math.abs(a.trend) > math.abs(b.trend) end
			return a.key < b.key
		end)
		local out, up, down = {}, 0, 0
		local now = X.Now()
		for _, r in ipairs(found) do
			if #out >= MAX then break end
			local ok = false
			if r.trend > 0 and up < MAX_KIND then up, ok = up + 1, true
			elseif r.trend < 0 and down < MAX_KIND then down, ok = down + 1, true end
			if ok then
				r.week = weekAgo(r.key, now)
				out[#out + 1] = r
			end
		end
		rows, rowsAt, running = out, X.Now(), false
		S.RefreshSoon()
	end)
end

local function short(name, n)
	if #name <= n then return name end
	return name:sub(1, n - 2) .. ".."
end
local function pctText(p)
	return string.format("%s%.0f%%", p >= 0 and "+" or "-", math.abs(p))
end

-- the entry of one moving item
local function entry(r)
	local key, st, up = r.key, r.st, r.trend > 0
	local name = X.ItemName(key) or ("Item " .. key)
	local it = X.Items()[key]
	local cur = it and it.cur or {}
	local owned = X.Owned and X.Try(X.Owned, key) or 0
	local col = up and GREEN or RED
	local change = r.week and r.week > 0 and (r.price / r.week - 1) * 100 or nil
	local e = {id = "trend:" .. key, key = key, price = r.price}
	e.title = short(name, 19) .. (up and " going up" or " going down")
	e.sub = col .. (change and (pctText(change) .. " this week") or (pctText(r.trend) .. " a week")) .. "|r" ..
		(owned > 0 and (GREY .. ", you have |r" .. X.Num(owned)) or "")
	e.badge = col .. (up and "rising" or "falling") .. "|r"
	-- what to do
	local span = (st.days or 0) >= 14 and "2 weeks" or ((st.days or 0) .. " days")
	if up then
		e.sentence = "Its price has been rising for " .. span .. ". " .. (owned > 0 and
			("You have " .. X.Num(owned) .. ": now is a good time to sell.") or "If you have some, now is a good time to sell.")
	else
		e.sentence = "Its price has been falling for " .. span .. ". " .. (owned > 0 and
			("You have " .. X.Num(owned) .. ": sell them before it drops more, or keep them until it climbs back.") or
			"Wait before you buy: it may get cheaper still.")
	end
	-- why, the numbers in words
	local why = {}
	if r.week and change then
		why[#why + 1] = "A week ago it sold for about " .. X.MoneyPlain(r.week) .. ", now about " .. X.MoneyPlain(r.price) ..
			" (" .. pctText(change) .. ")."
	else
		why[#why + 1] = "It moves about " .. pctText(r.trend) .. " a week; now it sells for about " .. X.MoneyPlain(r.price) .. "."
	end
	if (st.vol or 0) > 0 then
		why[#why + 1] = "Its usual ups and downs from day to day are about " .. string.format("%.0f%%", st.vol) ..
			", so this is more than chance."
	end
	local listed = cur.qty and (X.Num(cur.qty) .. " are listed now" .. (st.qty7 and (" (usually " .. X.Num(st.qty7) .. ")") or ""))
	local rate = X.SaleRate and X.Try(X.SaleRate, key)
	if listed or rate then
		why[#why + 1] = (listed or "") .. (listed and rate and "; " or "") .. (rate and ("about " .. X.Rate(rate) .. " sell a day") or "") .. "."
	end
	e.why = table.concat(why, " ")
	e.lines = {
		{"Sells for now", S.Money(r.price)},
		{"A week ago", S.Money(r.week)},
		{"Usually (30 days)", S.Money(st.avg30 or st.avg7)},
		{"You have", owned > 0 and X.Num(owned) or (GREY .. "none|r")},
	}
	local watched = X.Watched(key)
	e.button = {label = watched and "Stop watching" or "Watch it",
		run = function() X.SetWatched(key, not X.Watched(key)) end,
		tip = watched and "Takes it off your watch list." or
			"Puts it on your watch list: the watch list scan looks it up, and it is easy to find again."}
	if owned > 0 then
		e.button2 = {label = "Sell it", tip = "Shows what to sell and lets you post it.",
			run = function() if S.views.sell then S.Select("sell") else S.ShowItem(key) end end}
	elseif not up and S.views.buy then
		e.button2 = {label = "Buy page", tip = "Good buys right now (this one too, once it is cheap).",
			run = function() S.Select("buy") end}
	end
	e.skip = true
	return e
end

local function list()
	local now = X.Now()
	local old = not rows or now - rowsAt >= MAX_AGE
	if not running then
		if old or (dirty and now - rowsAt >= MIN_GAP) then
			dirty = false
			pass()
		elseif dirty and not waiting then
			-- new prices came too soon after the last pass: look again when the minute is up
			waiting = true
			X.After(MIN_GAP - (now - rowsAt) + 1, function() waiting = false S.RefreshSoon() end)
		end
	end
	if not rows then return {}, "Looking at the prices - a moment..." end
	local out = {}
	for _, r in ipairs(rows) do
		local ok, e = pcall(entry, r)
		if ok and e then out[#out + 1] = e end
	end
	return out, "No price is moving much right now. With a few more days of full scans XNAH sees more."
end

S.AddView("trends", {title = "Trends", order = 4, list = list})
