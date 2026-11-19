-- Strategies: ways to make gold, each one a set of rules run over every item XNAH knows. Some come from the game
-- (vendor prices, disenchanting, crafting), some from real markets (buy the dip, momentum, cycles of the day and the
-- week, taking profit, cutting losses). Each strategy lists items with what to do: buy, sell, hold, craft.
--
--   strategy = {key, name, side ("buy" / "sell" / "make"), short (one line), how = {plain lines}, needs (what it needs
--     to find anything), params = {{key, label, default, kind = "pct" / "money" / "number" / "check", tip}},
--     each = function(key, it, st, P, ctx) -> row (one item; most strategies) or list = function(P, ctx) -> rows}
--   row = {key, action, now (copper), target (copper), profit (copper each, after the cut where it applies), qty (how
--     many make sense, or nil), risk ("Low" / "Medium" / "High"), why (short text), total (profit x qty), vendor = true
--     (bought from a vendor, not on the auction house)}
--
-- Results are kept per strategy and worked out again in slices (X.Job) about 2 seconds after prices, the analysis or
-- your bags change - only while the Strategies tab is open or a strategy marks tooltips. Your numbers for a strategy:
-- XNAHDB.strategies[key] = {param = value, ..., on = true (mark its items on tooltips)}.
--
-- X.Strategies() -> list; X.Strategy(key); X.RunStrategy(key) -> rows (cached; worked out now when there is nothing
-- yet); X.StrategyUpdate(key or nil); X.StrategyMarks(itemKey) -> names; X.StrategyHits(itemKey) -> {{name, action,
-- why}}; X.StrategyParams(key); X.SetStrategyParam(key, param, value); X.StrategyOn / X.SetStrategyOn;
-- X.ResetStrategy(key). Event XNAH_STRATEGY when results change.
local ADDON, X = ...

local LIST = {}       -- the strategies, in the order shown
local BY = {}         -- [key] = strategy
local cache = {}      -- [key] = {rows, at = GetTime(), t = server time}
local marks = {}      -- [item key] = {strategy key, ...} of the strategies switched on
local dirty = true    -- prices changed since the last run
local lastScan        -- {rows, t} of the last full scan of this session (every listing, memory only)
local MAX_ROWS = 300
local STEP = 120      -- items looked at per frame (all strategies at once)
local MAX_AGE = 600   -- results older than 10 minutes are worked out again when looked at

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

-- [[ small helpers ]]
-- short money for the "why" text: "12.5g", "45s", "7c"
local function sm(c)
	c = X.Round(c or 0)
	local neg = c < 0 and "-" or ""
	c = abs(c)
	if c >= 1000000 then return neg .. X.Num(c / 10000) .. "g" end
	if c >= 10000 then return neg .. (string.format("%.1f", c / 10000):gsub("%.0$", "")) .. "g" end
	if c >= 100 then return neg .. floor(c / 100) .. "s" end
	return neg .. c .. "c"
end
local function pct(v) return string.format("%.0f%%", v or 0) end
local function cut(c) return c and c * (1 - X.S().cut / 100) or nil end
-- the usual price: 30-day average, else 7-day, else 3-day
local function usualOf(st) return st and (st.avg30 or st.avg7 or st.avg3) or nil end

-- sales per day (estimate) - once per run per item
local function rateOf(ctx, key)
	local v = ctx.rates[key]
	if v == nil then
		v = X.SaleRate and X.Try(X.SaleRate, key) or false
		ctx.rates[key] = v
	end
	return v or nil
end
-- every listing of the item from the last full scan (only when that scan is where the current price comes from)
local function listOf(ctx, key, it)
	local s = ctx.scan
	if not s or not it.cur or not it.cur.t or abs(it.cur.t - s.t) > 60 then return nil end
	local r = s.rows[key]
	return r and r.list or nil
end
-- units listed at or under a price of one (and what they cost); nil when the listings are not known
local function unitsUnder(list, price)
	if not list then return nil end
	local units, cost = 0, 0
	for i = 1, #list do
		local l = list[i]
		if l[1] <= price + 0.001 then
			local n = l[2] or 1
			units = units + n
			cost = cost + l[1] * n
		end
	end
	return units, cost
end
-- how many make sense: what is there, at most `days` of sales when the speed is known
local function sensible(avail, rate, days)
	if rate and rate > 0 then
		local n = max(1, floor(rate * days + 0.5))
		if avail then return min(avail, n) end
		return n
	end
	return avail
end
-- risk from the day-to-day spread, the days of data, the sales speed and the age of the price
local function riskOf(it, st, rate, add)
	local score = add or 0
	local vol = st and st.vol
	if not vol then score = score + 1 elseif vol > 25 then score = score + 2 elseif vol > 12 then score = score + 1 end
	local days = st and st.days or 0
	if days < 3 then score = score + 2 elseif days < 7 then score = score + 1 end
	if not rate then score = score + 1 elseif rate < 0.5 then score = score + 2 elseif rate < 2 then score = score + 1 end
	local t = it and it.cur and it.cur.t
	if not t or X.Now() - t > 24 * 3600 then score = score + 1 end
	if score <= 1 then return "Low" end
	if score <= 3 then return "Medium" end
	return "High"
end
-- how many of an item you have that are not on the auction house already (nil: not known)
local function sellable(key)
	if not X.Owned then return nil end
	local total, parts = X.Try(X.Owned, key)
	if not total then return nil end
	return total - (type(parts) == "table" and parts.auctions or 0)
end
-- what you paid for one on average (sales ledger), or nil
local function paid(key)
	if not X.LedgerItem then return nil end
	local li = X.Try(X.LedgerItem, key)
	return type(li) == "table" and li.avgBuy or nil
end
-- a sell row: profit = what one brings after the cut, minus what you paid when the ledger knows
local function sellRow(key, it, st, rate, action, now, target, qty, why, add)
	local got = cut(now)
	local p = paid(key)
	if p then got = got - p why = why .. "; paid " .. sm(p) end
	return {key = key, action = action, now = now, target = target, profit = got, qty = qty, risk = riskOf(it, st, rate, add),
		why = why}
end

-- [[ the strategies ]]
local function add(s)
	LIST[#LIST + 1] = s
	BY[s.key] = s
end
local function minProfitParam(default)
	return {key = "minProfit", label = "Profit each at least", default = default, kind = "money",
		tip = "Leave out items that bring less than this each (after the auction house cut)."}
end

-- 1 vendor floor (Xn's idea)
add({key = "vendorfloor", name = "Vendor floor", side = "buy",
	short = "Listed under what a vendor pays, or only a little over it.",
	how = {
		"Lists items whose lowest price is under what a vendor pays for them (buy them and sell them to any vendor: a sure profit), and items only a little over that price.",
		"Why it works: a vendor always pays its price, so that is a floor - the price can hardly fall lower. The upside is the usual auction price.",
		"When it fails: an item that never sells for more than the vendor price - the worst case is selling it to a vendor for a little less than you paid.",
		"Real-life idea: buying below the scrap or book value of a thing.",
	},
	needs = "fresh prices (a full scan) and what vendors pay (known for items the game has loaded)",
	params = {
		{key = "near", label = "Up to % over vendor", default = 15, kind = "pct",
			tip = "Also list items whose lowest price is at most this many % over what a vendor pays."},
		minProfitParam(20),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local vs = X.VendorSell(it.id)
		if not vs or not cur.min then return nil end
		local list = listOf(ctx, key, it)
		if cur.min < vs then
			local units, cost = unitsUnder(list, vs - 0.5)
			local each = (units and units > 0) and (vs - cost / units) or (vs - cur.min)
			if each < P.minProfit then return nil end
			return {key = key, action = "Buy and vendor", now = cur.min, target = vs, profit = each, qty = units,
				risk = "Low", why = "Vendor pays " .. sm(vs) .. ": sure profit"}
		end
		if cur.min <= vs * (1 + P.near / 100) then
			local usual = usualOf(st) or cur.mkt
			if not usual then return nil end
			local each = cut(usual) - cur.min
			if each < P.minProfit then return nil end
			local rate = rateOf(ctx, key)
			local units = unitsUnder(list, vs * (1 + P.near / 100))
			return {key = key, action = "Buy", now = cur.min, target = usual, profit = each, qty = sensible(units, rate, 7),
				risk = "Low", why = pct((cur.min / vs - 1) * 100) .. " over vendor (" .. sm(vs) .. ")"}
		end
		return nil
	end})

-- 2 buy the dip (mean reversion)
add({key = "dip", name = "Buy the dip", side = "buy",
	short = "A steady item listed far under its 30-day average.",
	how = {
		"Lists items whose lowest price is far under their 30-day average, but only items whose price is normally steady and that sell.",
		"Why it works: prices of steady items tend to come back to their average after someone sells cheap in a hurry.",
		"When it fails: when the price has really moved (a new source of the item, a patch) - then the average is old news. Items falling fast are left out.",
		"Real-life idea: mean reversion - buying a sound stock after a sudden drop.",
	},
	needs = "a few days of price history per item (one full scan a day) and fresh prices",
	params = {
		{key = "pct", label = "Lowest at most % of avg", default = 70, kind = "pct",
			tip = "The lowest price must be at or under this % of the 30-day average."},
		{key = "spread", label = "Day-to-day spread up to %", default = 25, kind = "pct",
			tip = "How much the price normally moves from day to day. Lower = only very steady items."},
		{key = "days", label = "Days of data at least", default = 5, kind = "number"},
		{key = "rate", label = "Sells a day at least", default = 0.5, kind = "number",
			tip = "Only when the sales speed is known (two full scans close together); unknown speed is allowed."},
		minProfitParam(1000),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local avg = st.avg30
		if not avg or not cur.min or st.days < P.days or not st.vol or st.vol > P.spread then return nil end
		if cur.min > avg * P.pct / 100 or (st.trend or 0) <= -15 then return nil end
		local rate = rateOf(ctx, key)
		if rate and rate < P.rate then return nil end
		local each = cut(avg) - cur.min
		if each < P.minProfit then return nil end
		local units = unitsUnder(listOf(ctx, key, it), avg * P.pct / 100)
		return {key = key, action = "Buy and relist", now = cur.min, target = avg, profit = each, qty = sensible(units, rate, 7),
			risk = riskOf(it, st, rate), why = pct(cur.min / avg * 100) .. " of 30d avg, spread " .. pct(st.vol)}
	end})

-- 3 undercut gap
add({key = "gap", name = "Undercut gap", side = "buy",
	short = "A few cheap listings far under the market value.",
	how = {
		"Lists items whose cheapest listings are far under the market value of all the others, with only a few units at that cheap price.",
		"Buy those few and list them again just under the market value.",
		"Why it works: someone listed too low (in a hurry, or a typo); the rest of the market did not follow.",
		"When it fails: when many sellers move down at once - then the market value itself is falling. Real-life idea: picking up mispriced offers.",
	},
	needs = "fresh prices (a full scan); how many are cheap is known after a full scan in this session",
	params = {
		{key = "pct", label = "Cheapest at most % of mkt", default = 80, kind = "pct",
			tip = "The cheapest listing must be at or under this % of the market value."},
		{key = "units", label = "Cheap units at most", default = 10, kind = "number",
			tip = "Only when this many units or fewer are at the cheap price (a few mistakes, not a new price)."},
		minProfitParam(1000),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local mkt = cur.mkt
		if not mkt or not cur.min or cur.min > mkt * P.pct / 100 then return nil end
		local usual = st.avg7 or st.avg30
		if usual and mkt > usual * 1.3 then return nil end -- the market value itself is far over the usual price
		local units, cost = unitsUnder(listOf(ctx, key, it), mkt * P.pct / 100)
		if units and units > P.units then return nil end
		local target = max(1, mkt - 1)
		local paidEach = (units and units > 0) and cost / units or cur.min
		local each = cut(target) - paidEach
		if each < P.minProfit then return nil end
		local rate = rateOf(ctx, key)
		return {key = key, action = "Buy and relist", now = cur.min, target = target, profit = each, qty = units,
			risk = riskOf(it, st, rate, units and 0 or 1),
			why = pct(cur.min / mkt * 100) .. " of market" .. (units and (", " .. X.Num(units) .. " cheap") or "")}
	end})

-- 4 market reset (thin market)
add({key = "reset", name = "Market reset", side = "buy",
	short = "Buy everything under the usual price, list it at the usual price.",
	how = {
		"In a thin market (few listed), buy every unit listed under 80% of the usual price and list them again at the usual price.",
		"Why it works: with the cheap ones gone, buyers have to pay your price. Risk is set by how many days of sales you need to sell them all.",
		"When it fails: others list cheap again, or the item sells slower than thought - you sit on stock.",
		"Real-life idea: cornering a small market (only for small markets, and never a sure thing).",
	},
	needs = "a full scan in this session and a few days of price history; the sales speed helps (two full scans close together)",
	params = {
		{key = "minTotal", label = "Profit in all at least", default = 10000, kind = "money",
			tip = "Leave out resets that bring less than this in all (after the cut)."},
		{key = "days", label = "Days of sales at most", default = 5, kind = "number",
			tip = "Leave out resets that need more days of sales than this to sell (when the speed is known)."},
	},
	list = function(P, ctx)
		local out = {}
		if not X.Resets then return out end
		local list = X.Try(X.Resets) or {}
		for _, r in ipairs(list) do
			local it = X.Items()[r.key]
			if it and X.Fresh(it) and r.units and r.units > 0 and r.usual and (r.profit or 0) >= P.minTotal then
				local rate = r.rate
				local days = (rate and rate > 0) and r.units / rate or nil
				if not (rate and rate <= 0) and not (days and days > P.days) then
					local risk = not days and "Medium" or days <= 1 and "Low" or days <= 3 and "Medium" or "High"
					out[#out + 1] = {key = r.key, action = "Buy and relist", now = r.cost / r.units, target = r.usual,
						profit = r.profit / r.units, qty = r.units, risk = risk,
						why = X.Num(r.units) .. " under 80%" .. (days and (", " .. string.format("%.1f", days) .. " days to sell") or "")}
				end
			end
		end
		return out
	end})

-- 5 momentum
add({key = "momentum", name = "Momentum", side = "buy",
	short = "Price rising fast while fewer are listed: buy now, sell in 3-7 days.",
	how = {
		"Lists items whose price rose quickly over the last two weeks while fewer are listed than usual.",
		"Buy now and sell in 3 to 7 days, at the price the rise points to.",
		"Why it works: a rise with falling supply often goes on for a while (demand is bigger than what comes in).",
		"When it fails: a rise can stop or turn any day - high risk, keep amounts small. Real-life idea: momentum or trend following.",
	},
	needs = "at least 5 days of price history per item (one full scan a day)",
	params = {
		{key = "trend", label = "Rising at least % a week", default = 10, kind = "pct"},
		{key = "hold", label = "Days to hold", default = 5, kind = "number", tip = "The target is where the rise points after this many days."},
		minProfitParam(1000),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		if not cur.min or not st.trend or st.trend < P.trend or st.days < 5 then return nil end
		if not st.supply or st.supply > -10 then return nil end
		local base = cur.mkt or st.avg3 -- the price now, carried on by the rise
		if not base then return nil end
		local target = base * (1 + min(st.trend, 50) / 100 * P.hold / 7)
		local each = cut(target) - cur.min
		if each < P.minProfit then return nil end
		local rate = rateOf(ctx, key)
		local units = unitsUnder(listOf(ctx, key, it), cur.min * 1.05)
		return {key = key, action = "Buy and relist", now = cur.min, target = target, profit = each, qty = sensible(units, rate, 3),
			risk = "High", why = "+" .. pct(st.trend) .. " a week, " .. pct(-st.supply) .. " fewer listed"}
	end})

-- 6 sell into scarcity
add({key = "scarcity", name = "Sell into scarcity", side = "sell",
	short = "You have it, and far fewer are listed than usual.",
	how = {
		"Lists items you have (bags, bank, mail, your other characters) when far fewer are listed than usual while the price is at or over its usual level.",
		"List yours now: buyers have little choice, so they pay your price.",
		"When it fails: when the few left are cheap, or new supply arrives before yours sells. Profit = what one brings after the cut (minus what you paid, when the ledger knows).",
		"Real-life idea: selling when supply is short.",
	},
	needs = "items you own (log in your characters, open the bank and mailbox) and a few days of price history",
	params = {
		{key = "supply", label = "Listed under usual by %", default = 40, kind = "pct",
			tip = "How many % fewer than the 7-day average must be listed now."},
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		if not st.supply or st.supply > -P.supply or (st.qty7 or 0) < 5 or st.days < 3 then return nil end
		local usual = usualOf(st)
		if not usual or not cur.min or cur.min < usual then return nil end
		local n = sellable(key)
		if not n or n <= 0 then return nil end
		local rate = rateOf(ctx, key)
		return sellRow(key, it, st, rate, "Sell now", cur.min, usual, n, pct(-st.supply) .. " fewer listed, price " ..
			pct(cur.min / usual * 100) .. " of usual")
	end})

-- 7 hold in a flood
add({key = "flood", name = "Hold in a flood", side = "sell",
	short = "You have it, and far more are listed than usual: wait.",
	how = {
		"Lists items you have when far more are listed than usual: the price is under pressure.",
		"Do not sell now - wait a few days until the flood is bought up and the price comes back.",
		"When it fails: when the flood is the new normal (a new way to get the item). Profit = what waiting may bring more for each, after the cut.",
		"Real-life idea: not selling into a glut.",
	},
	needs = "items you own (log in your characters, open the bank and mailbox) and a few days of price history",
	params = {
		{key = "supply", label = "Listed over usual by %", default = 60, kind = "pct",
			tip = "How many % more than the 7-day average must be listed now."},
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		if not st.supply or st.supply < P.supply or (st.qty7 or 0) < 5 or st.days < 3 then return nil end
		local usual = st.avg30 or st.avg14 or usualOf(st)
		local now = cur.min or cur.mkt
		if not usual or not now then return nil end
		local n = sellable(key)
		if not n or n <= 0 then return nil end
		local rate = rateOf(ctx, key)
		return {key = key, action = "Hold", now = now, target = usual, profit = max(0, cut(usual) - cut(now)), qty = n,
			risk = riskOf(it, st, rate), why = string.format("%.1fx the usual number listed", 1 + st.supply / 100)}
	end})

-- 8 crafting margin
add({key = "craft", name = "Crafting margin", side = "make",
	short = "Things that sell for well over what their reagents cost.",
	how = {
		"Lists recipes whose item sells (after the cut) for well over what the reagents cost - each reagent at its cheapest: a vendor, the auction house or crafting it.",
		"Why it works: crafters turn cheap materials into something people want ready-made.",
		"When it fails: when the item sells slowly (only items known to sell are listed when the speed is known), or reagent prices jump.",
		"Real-life idea: manufacturing margin - buy parts, sell the product.",
	},
	needs = "fresh prices of the reagents and the items",
	params = {
		minProfitParam(10000),
		{key = "margin", label = "Margin at least %", default = 20, kind = "pct", tip = "Profit as % of the cost."},
		{key = "rate", label = "Sells a day at least", default = 1, kind = "number",
			tip = "Only when the sales speed is known; unknown speed is allowed."},
		{key = "mine", label = "Only recipes I know", default = true, kind = "check"},
	},
	list = function(P, ctx)
		local out, best = {}, {}
		if not X.CraftList then return out end
		local list = X.Try(X.CraftList, {mine = P.mine}) or {}
		for _, r in ipairs(list) do
			if r.profit and r.profit >= P.minProfit and (r.pct or 0) >= P.margin and not r.stale and not (X.CRAFT_COOLDOWNS or {})[r.rid] then
				local rate = rateOf(ctx, r.key)
				if not (rate and rate < P.rate) and (not best[r.key] or best[r.key].profit < r.profit) then
					local it = X.Items()[r.key]
					local st = it and X.Stats(it)
					local who = r.known and #r.known > 0 and ("; " .. table.concat(r.known, ", ")) or ""
					local row = {key = r.key, action = "Craft", now = r.cost, target = r.sell and r.sell / (1 - X.S().cut / 100),
						profit = r.profit, qty = rate and max(1, floor(rate * 2 + 0.5)) or nil, risk = riskOf(it, st, rate),
						why = "cost " .. sm(r.cost) .. ", +" .. pct(r.pct) .. who}
					best[r.key] = row
				end
			end
		end
		for _, row in pairs(best) do out[#out + 1] = row end
		return out
	end})

-- 9 disenchant arbitrage
add({key = "de", name = "Disenchant", side = "buy",
	short = "Gear listed under what its disenchanting materials bring.",
	how = {
		"Lists gear whose lowest price is under what its disenchanting materials bring (dusts, essences, shards at their prices), less 5%.",
		"Buy it, disenchant it (you or a friend) and sell the materials.",
		"When it fails: the chances are the classic ones (Forever may differ), and luck varies from one piece to the next - it evens out over many.",
		"Real-life idea: buying something for its parts.",
	},
	needs = "fresh prices of the gear and of the materials (a full scan)",
	params = {minProfitParam(1000)},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		if not X.DEValue or not cur.min or not it.q or it.q < 2 or it.q > 4 then return nil end
		local de, _, missing = X.DEValue(key)
		if not de or de <= 0 or cur.min >= de * 0.95 then return nil end
		local each = cut(de) - cur.min
		if each < P.minProfit then return nil end
		local units = unitsUnder(listOf(ctx, key, it), de * 0.95)
		local rate = rateOf(ctx, key)
		return {key = key, action = "Disenchant", now = cur.min, target = de, profit = each, qty = units or cur.qty,
			risk = riskOf(it, st, rate, (missing or 0) > 0 and 1 or 0),
			why = "materials bring " .. sm(de) .. ((missing or 0) > 0 and " (some unpriced)" or "")}
	end})

-- 10 vendor to auction house
add({key = "vendorflip", name = "Vendor to auction house", side = "buy",
	short = "Things a vendor sells that go for more on the auction house.",
	how = {
		"Lists things a vendor sells (from the vendors you have visited) that sell for more on the auction house after the cut.",
		"Buy them from the vendor and list them.",
		"When it fails: when they sell slowly, or many players do the same. Limited-stock items are a little riskier (others buy them first).",
		"Real-life idea: retail - buy wholesale, sell where buyers are.",
	},
	needs = "vendor prices (open merchants' windows) and fresh auction prices",
	params = {minProfitParam(1000)},
	list = function(P, ctx)
		local out = {}
		if not X.VendorFlips then return out end
		for _, r in ipairs(X.Try(X.VendorFlips) or {}) do
			if r.profit >= P.minProfit then
				local it = X.Items()[r.key]
				local st = it and X.Stats(it)
				local rate = rateOf(ctx, r.key)
				local _, info = X.VendorBuy(X.KeyID(r.key))
				out[#out + 1] = {key = r.key, action = "Buy and relist", now = r.buy, target = r.sell / (1 - X.S().cut / 100),
					profit = r.profit, qty = sensible(nil, rate, 3), risk = riskOf(it, st, rate, r.lim and 1 or 0), vendor = true,
					why = "from " .. (info and info.from or "a vendor") .. (r.lim and " (limited)" or "")}
			end
		end
		return out
	end})

-- 11 volume flipping
add({key = "volume", name = "Volume flipping", side = "buy",
	short = "Fast sellers listed a little under their market value: many small flips.",
	how = {
		"Lists items that sell many a day with the lowest price at least a little under the market value.",
		"Buy the cheap ones and list them at the market value - small profit each, but many and quickly.",
		"When it fails: when others do the same (the gap closes) - keep an eye on the profit after the cut.",
		"Real-life idea: market making - many small trades in a busy market.",
	},
	needs = "the sales speed (two full scans up to 4 hours apart) and fresh prices",
	params = {
		{key = "rate", label = "Sells a day at least", default = 10, kind = "number"},
		{key = "pct", label = "Lowest under mkt by %", default = 10, kind = "pct"},
		minProfitParam(50),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local mkt = cur.mkt
		if not mkt or not cur.min or cur.min > mkt * (1 - P.pct / 100) then return nil end
		local rate = rateOf(ctx, key)
		if not rate or rate < P.rate then return nil end
		local each = cut(mkt) - cur.min
		if each < P.minProfit then return nil end
		local units = unitsUnder(listOf(ctx, key, it), mkt * (1 - P.pct / 100))
		return {key = key, action = "Buy and relist", now = cur.min, target = mkt, profit = each, qty = sensible(units, rate, 1),
			risk = riskOf(it, st, rate), why = "sells " .. X.Num(rate) .. " a day, " .. pct((1 - cur.min / mkt) * 100) .. " under"}
	end})

-- 12 time-of-day cycle
local BLOCK = {"night (0-6h)", "morning (6-12h)", "afternoon (12-18h)", "evening (18-24h)"}
add({key = "hours", name = "Time-of-day cycle", side = "buy",
	short = "Cheaper at one time of day than another.",
	how = {
		"From every scan of the last 7 days: the average price in each quarter of the day (night, morning, afternoon, evening - your clock).",
		"Buy in the cheapest quarter, sell in the dearest when the gap is big enough after the cut.",
		"Why it works: sellers and buyers are online at different hours (farmers at night, raiders in the evening).",
		"When it fails: needs scans at different hours on 3 or more days; one odd day can fool it. Real-life idea: intraday cycles.",
	},
	needs = "scans at different times of day on 3 or more days of the last week",
	params = {
		{key = "gap", label = "Gap after cut at least %", default = 15, kind = "pct"},
		minProfitParam(1000),
	},
	each = function(key, it, st, P, ctx)
		if st.days < 3 or not it.h or #it.h < 60 then return nil end
		local from = floor((ctx.now - 7 * 86400) / 60)
		local sum, cnt, days, all = {0, 0, 0, 0}, {0, 0, 0, 0}, {{}, {}, {}, {}}, {}
		local nAll = 0
		for _, p in ipairs(X.UnpackPoints(it.h)) do
			local v = p[3] or p[2]
			if p[1] and p[1] >= from and v and (p[4] or 1) > 0 then
				local t = p[1] * 60 + ctx.off
				local b = floor((t % 86400) / 21600) + 1
				local d = floor(t / 86400)
				sum[b], cnt[b] = sum[b] + v, cnt[b] + 1
				days[b][d] = true
				if not all[d] then all[d] = true nAll = nAll + 1 end
			end
		end
		if nAll < 3 then return nil end
		local lo, hi
		for b = 1, 4 do
			local nd = 0
			for _ in pairs(days[b]) do nd = nd + 1 end
			if nd >= 2 then
				local a = sum[b] / cnt[b]
				if not lo or a < sum[lo] / cnt[lo] then lo = b end
				if not hi or a > sum[hi] / cnt[hi] then hi = b end
			end
		end
		if not lo or lo == hi then return nil end
		local cheap, dear = sum[lo] / cnt[lo], sum[hi] / cnt[hi]
		if cut(dear) < cheap * (1 + P.gap / 100) then return nil end
		local each = cut(dear) - cheap
		if each < P.minProfit then return nil end
		local rate = rateOf(ctx, key)
		local nowBlock = floor(((ctx.now + ctx.off) % 86400) / 21600) + 1
		return {key = key, action = "Buy and relist", now = cheap, target = dear, profit = each, qty = sensible(nil, rate, 1),
			risk = riskOf(it, st, rate), why = "buy " .. BLOCK[lo] .. ", sell " .. BLOCK[hi] .. (nowBlock == lo and " - now!" or "")}
	end})

-- 13 weekday cycle
local WEEKDAY = {"Thursday", "Friday", "Saturday", "Sunday", "Monday", "Tuesday", "Wednesday"} -- day 0 (1 Jan 1970) was a Thursday
add({key = "weekday", name = "Weekday cycle", side = "buy",
	short = "Cheaper on one day of the week than another (raid days).",
	how = {
		"From the daily prices of the last 8 weeks: the average price on each day of the week (server days).",
		"Buy on the cheapest day, sell on the dearest when the gap is big enough after the cut - raid consumables are often dear on raid days and the day before.",
		"When it fails: needs 3 weeks of history; holidays and patches break the pattern.",
		"Real-life idea: weekly seasonality (the weekend effect).",
	},
	needs = "at least 3 weeks of daily prices per item (one full scan a day)",
	params = {
		{key = "gap", label = "Gap after cut at least %", default = 15, kind = "pct"},
		minProfitParam(1000),
	},
	each = function(key, it, st, P, ctx)
		if st.days < 15 or not st.first or st.first > ctx.today - 20 then return nil end
		local sum, cnt = {0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0}
		for _, p in ipairs(X.UnpackPoints(it.d)) do
			local v = p[3] or p[2]
			if p[1] and p[1] > ctx.today - 56 and v then
				local wd = p[1] % 7 + 1
				sum[wd], cnt[wd] = sum[wd] + v, cnt[wd] + 1
			end
		end
		local lo, hi, covered = nil, nil, 0
		for wd = 1, 7 do
			if cnt[wd] >= 2 then
				covered = covered + 1
				local a = sum[wd] / cnt[wd]
				if not lo or a < sum[lo] / cnt[lo] then lo = wd end
				if not hi or a > sum[hi] / cnt[hi] then hi = wd end
			end
		end
		if covered < 5 or not lo or lo == hi then return nil end
		local cheap, dear = sum[lo] / cnt[lo], sum[hi] / cnt[hi]
		if cut(dear) < cheap * (1 + P.gap / 100) then return nil end
		local each = cut(dear) - cheap
		if each < P.minProfit then return nil end
		local rate = rateOf(ctx, key)
		local today = ctx.today % 7 + 1
		return {key = key, action = "Buy and relist", now = cheap, target = dear, profit = each, qty = sensible(nil, rate, 2),
			risk = riskOf(it, st, rate), why = "buy " .. WEEKDAY[lo] .. ", sell " .. WEEKDAY[hi] .. (today == lo and " - today!" or "")}
	end})

-- 14 steady earners
add({key = "steady", name = "Steady earners", side = "buy",
	short = "Steady price, sells every day, a small sure margin: keep posting.",
	how = {
		"Lists items with a steady price that sell several a day and whose lowest price is a little under the market value (after the cut).",
		"Safe things to keep buying cheap and posting again (or to farm or craft and keep posting).",
		"When it fails: rarely badly - the margin is small, so check that the profit still beats the deposit and your time.",
		"Real-life idea: a dividend stock - small, steady returns.",
	},
	needs = "a week of price history and the sales speed (two full scans up to 4 hours apart)",
	params = {
		{key = "spread", label = "Day-to-day spread up to %", default = 15, kind = "pct"},
		{key = "rate", label = "Sells a day at least", default = 3, kind = "number"},
		{key = "margin", label = "Margin after cut at least %", default = 5, kind = "pct"},
		minProfitParam(10),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local mkt = cur.mkt
		if not mkt or not cur.min or not st.vol or st.vol > P.spread then return nil end
		if cut(mkt) < cur.min * (1 + P.margin / 100) then return nil end
		local rate = rateOf(ctx, key)
		if not rate or rate < P.rate then return nil end
		local each = cut(mkt) - cur.min
		if each < P.minProfit then return nil end
		local units = unitsUnder(listOf(ctx, key, it), cut(mkt) / (1 + P.margin / 100))
		return {key = key, action = "Buy and relist", now = cur.min, target = mkt, profit = each, qty = sensible(units, rate, 2),
			risk = riskOf(it, st, rate), why = "spread " .. pct(st.vol) .. ", sells " .. X.Num(rate) .. " a day"}
	end})

-- 15 falling knife
add({key = "knife", name = "Falling knife", side = "sell",
	short = "You have it and its price is falling fast: sell before it drops more.",
	how = {
		"Lists items you have whose price has been falling fast over the last two weeks and is now under its usual level.",
		"Sell soon: a falling price often keeps falling for a while. (Buy the dip leaves these out.)",
		"When it fails: when the fall stops and turns - you sold at the bottom.",
		"Real-life idea: a stop-loss - cut losses early. Profit = what one brings after the cut (minus what you paid, when the ledger knows).",
	},
	needs = "items you own and at least 5 days of price history",
	params = {
		{key = "trend", label = "Falling at least % a week", default = 15, kind = "pct"},
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		if not st.trend or st.trend > -P.trend or st.days < 5 then return nil end
		local usual = usualOf(st)
		local now = cur.min or cur.mkt
		if not usual or not now or now >= usual then return nil end
		local n = sellable(key)
		if not n or n <= 0 then return nil end
		local rate = rateOf(ctx, key)
		return sellRow(key, it, st, rate, "Sell now", now, usual, n, pct(st.trend) .. " a week")
	end})

-- 16 price spike: take profit
add({key = "spike", name = "Price spike", side = "sell",
	short = "You have it and it sells far over its 30-day average: take the profit.",
	how = {
		"Lists items you have whose lowest price now is far over their 30-day average.",
		"Sell now while it lasts: spikes usually come back down.",
		"When it fails: when the price has moved up for good (then you sold early, still with a profit).",
		"Real-life idea: taking profit at a peak. Profit = what one brings after the cut (minus what you paid, when the ledger knows).",
	},
	needs = "items you own and a week of price history",
	params = {
		{key = "pct", label = "Over 30d avg by at least %", default = 25, kind = "pct"},
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local avg = st.avg30
		if not avg or not cur.min or st.days < 7 or cur.min < avg * (1 + P.pct / 100) then return nil end
		local n = sellable(key)
		if not n or n <= 0 then return nil end
		local rate = rateOf(ctx, key)
		return sellRow(key, it, st, rate, "Sell now", cur.min, avg, n, pct((cur.min / avg - 1) * 100) .. " over 30d avg")
	end})

-- 17 recipes worth learning (Xn's gold list, 2026-11-19)
add({key = "learn", name = "Recipes worth learning", side = "make",
	short = "Recipes none of your characters knows yet whose item sells well over its cost.",
	how = {
		"Lists recipes of the game that none of your characters knows (as far as XNAH has seen your profession windows), whose item sells after the cut for well over what the reagents cost, and sells often.",
		"Learn the recipe (trainer, vendor or a recipe item) and craft it. Sorted by profit a day: profit each x how many sell a day.",
		"When it fails: some recipes are rare drops or need a high skill; the price can drop once more crafters make it.",
		"Real-life idea: invest in a new product line.",
	},
	needs = "fresh prices of the reagents and the items, and the sales speed",
	params = {
		minProfitParam(5000),
		{key = "margin", label = "Margin at least %", default = 25, kind = "pct", tip = "Profit as % of the cost."},
		{key = "rate", label = "Sells a day at least", default = 1, kind = "number",
			tip = "Only items known to sell at least this many a day."},
	},
	list = function(P, ctx)
		local out, best = {}, {}
		if not X.CraftList then return out end
		for _, r in ipairs(X.Try(X.CraftList, {mine = false}) or {}) do
			if (not r.known or #r.known == 0) and not (X.CRAFT_COOLDOWNS or {})[r.rid] and r.profit and r.profit >= P.minProfit and (r.pct or 0) >= P.margin and not r.stale then
				local rate = rateOf(ctx, r.key)
				if rate and rate >= P.rate and (not best[r.key] or best[r.key].profit < r.profit) then
					local it = X.Items()[r.key]
					local st = it and X.Stats(it)
					local rec = X.Recipe and X.Recipe(r.rid)
					local need = rec and rec.prof and (rec.prof .. (rec.la and (" " .. rec.la) or "")) or (r.prof or "?")
					best[r.key] = {key = r.key, action = "Learn and craft", now = r.cost, target = r.sell and r.sell / (1 - X.S().cut / 100),
						profit = r.profit, qty = max(1, floor(rate + 0.5)), risk = riskOf(it, st, rate),
						why = need .. ", cost " .. sm(r.cost) .. ", sells " .. X.Num(rate) .. " a day"}
				end
			end
		end
		for _, row in pairs(best) do out[#out + 1] = row end
		return out
	end})

-- 18 daily cooldown crafts: crafts the game lets a character make only once in a while, so supply stays low
local COOLDOWNS = X.CRAFT_COOLDOWNS or {} -- Craft.lua
add({key = "cooldown", name = "Cooldown crafts", side = "make",
	short = "Crafts the game allows only once a day or so: do them every day for steady gold.",
	how = {
		"Lists the crafts with a waiting time (transmutes, Mooncloth and the like) and what one brings after the cut over its reagents.",
		"Their supply stays low because nobody can make many, so the price stays high. Do them every time the wait is over, on every character that knows them.",
		"When it fails: when the reagents get dearer than the result - check the profit before you craft.",
		"Real-life idea: a scarce licence - a small, sure income every day.",
	},
	needs = "prices of the reagents and the results",
	params = {
		minProfitParam(1000),
		{key = "mine", label = "Only recipes I know", default = false, kind = "check"},
	},
	list = function(P, ctx)
		local out = {}
		if not (X.Recipe and X.RecipeCost) then return out end
		for rid, hours in pairs(COOLDOWNS) do
			local r = X.Recipe(rid)
			local who = X.KnownBy and X.KnownBy(rid) or {}
			if r and r.out and (not P.mine or #who > 0) then
				local key = tostring(r.out)
				local cost, missing = X.RecipeCost(rid)
				local price = X.Price(key)
				local sell = cut(price)
				if cost and sell and (missing or 0) == 0 and sell - cost >= P.minProfit then
					local it = X.Items()[key]
					local st = it and X.Stats(it)
					local rate = rateOf(ctx, key)
					local per = hours >= 20 and ("every " .. (hours >= 30 and (floor(hours / 24 + 0.5) .. " days") or "day")) or
						(hours >= 1 and ("every " .. floor(hours + 0.5) .. " h") or "every few minutes")
					out[#out + 1] = {key = key, action = "Craft " .. per, now = cost, target = price, profit = (sell - cost) * (r.n or 1),
						qty = #who > 0 and #who or 1, risk = riskOf(it, st, rate),
						why = (r.name or "?") .. (#who > 0 and ("; " .. table.concat(who, ", ")) or "; nobody knows it yet")}
				end
			end
		end
		return out
	end})

-- 19 what to farm: raw materials that sell fast
add({key = "farm", name = "What to farm", side = "make",
	short = "Raw materials (herbs, ore, cloth, leather...) ranked by the gold they bring a day.",
	how = {
		"Lists materials that go into recipes but are not crafted and not sold by vendors - things you gather or loot - by price after the cut x how many sell a day.",
		"Farm the ones at the top: a cheap herb that sells 200 a day can beat a rare drop that sells once a week.",
		"When it fails: when many players farm the same thing the price falls - watch the trend arrow.",
		"Real-life idea: produce what the market buys every day.",
	},
	needs = "the sales speed (two full scans up to 4 hours apart)",
	params = {
		{key = "rate", label = "Sells a day at least", default = 5, kind = "number"},
		minProfitParam(10),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local id = it.id or X.KeyID(key)
		if not id or tostring(key):find(":", 1, true) then return nil end
		local price = cur.mkt or cur.min
		if not price then return nil end
		local each = cut(price)
		if each < P.minProfit then return nil end
		if not (X.RecipesUsing and X.AllRecipesFor) then return nil end
		if X.VendorBuy(id) then return nil end
		if #X.AllRecipesFor(id) > 0 then return nil end
		local uses = #X.RecipesUsing(id)
		if uses == 0 then return nil end
		local rate = rateOf(ctx, key)
		if not rate or rate < P.rate then return nil end
		return {key = key, action = "Farm and sell", now = price, target = price, profit = each, qty = max(1, floor(rate + 0.5)),
			risk = riskOf(it, st, rate), why = "sells " .. X.Num(rate) .. " a day; in " .. uses .. " recipe" .. (uses > 1 and "s" or "")}
	end})

-- 20 stock up at a low: buy near the month's low, sell when it climbs back
add({key = "seasonal", name = "Stock up at a low", side = "buy",
	short = "Sells steadily and sits near its lowest price of the month: buy now, sell when it climbs back.",
	how = {
		"Lists items that sell steadily, whose price now is close to their lowest of the last 30 days while the month's high was well above it.",
		"Buy some and keep them until the price climbs back towards its average - for example before raid nights, new content or holidays.",
		"When it fails: when the low is a new normal (a new source of the item, fewer buyers). Spread your buys and do not tie up too much gold.",
		"Real-life idea: buy out of season - winter coats in summer.",
	},
	needs = "at least 2 weeks of price history and the sales speed",
	params = {
		{key = "near", label = "Within % of the 30-day low", default = 10, kind = "pct"},
		{key = "swing", label = "30-day high over the low by %", default = 40, kind = "pct"},
		{key = "rate", label = "Sells a day at least", default = 1, kind = "number"},
		minProfitParam(1000),
	},
	each = function(key, it, st, P, ctx)
		local cur = it.cur
		local now = cur.min
		if not now or not st.low30 or not st.high30 or (st.days or 0) < 14 then return nil end
		if now > st.low30 * (1 + P.near / 100) then return nil end
		if st.high30 < st.low30 * (1 + P.swing / 100) then return nil end
		local target = usualOf(st)
		if not target or target <= now then return nil end
		local each = cut(target) - now
		if each < P.minProfit then return nil end
		local rate = rateOf(ctx, key)
		if not rate or rate < P.rate then return nil end
		local units = unitsUnder(listOf(ctx, key, it), st.low30 * (1 + P.near / 100))
		return {key = key, action = "Buy and hold", now = now, target = target, profit = each, qty = sensible(units, rate, 5),
			risk = riskOf(it, st, rate, 1), why = "30-day low " .. sm(st.low30) .. ", high " .. sm(st.high30)}
	end})

-- [[ saved numbers ]]
local function saved(key)
	X.db.strategies = X.db.strategies or {}
	local s = X.db.strategies[key]
	if not s then s = {} X.db.strategies[key] = s end
	return s
end
function X.Strategies() return LIST end
function X.Strategy(key) return BY[key] end
-- the numbers of a strategy: saved ones, else the defaults
function X.StrategyParams(key)
	local s = BY[key]
	if not s then return {} end
	local sv = X.db.strategies and X.db.strategies[key] or {}
	local P = {}
	for _, p in ipairs(s.params or {}) do
		local v = sv[p.key]
		if v == nil then v = p.default end
		P[p.key] = v
	end
	return P
end
function X.SetStrategyParam(key, pkey, value)
	if not BY[key] then return end
	saved(key)[pkey] = value
	cache[key] = nil
	X.StrategyUpdate(key)
end
function X.ResetStrategy(key)
	local s = X.db.strategies and X.db.strategies[key]
	if not s then return end
	local on = s.on
	X.db.strategies[key] = {on = on}
	cache[key] = nil
	X.StrategyUpdate(key)
end
function X.StrategyOn(key)
	local s = X.db.strategies and X.db.strategies[key]
	return s and s.on == true or false
end
function X.SetStrategyOn(key, on)
	if not BY[key] then return end
	saved(key).on = on and true or nil
	if on and (dirty or not cache[key]) then X.StrategyUpdate() else
		X.StrategyMarksBuild()
		X.Fire("XNAH_STRATEGY")
	end
end

-- [[ running ]]
local function newCtx()
	local now = X.Now()
	local tt = date("*t", now)
	local off = 0
	if type(tt) == "table" and tt.hour then off = (tt.hour * 3600 + tt.min * 60 + tt.sec) - now % 86400 end
	return {now = now, today = X.Day(now), off = off, rates = {}, scan = lastScan}
end
-- s: the strategy - buy and make ideas leave out items you never want suggested, and buy ideas grey junk (its only
-- real value is what a vendor pays; Vendor floor is about exactly that, so it keeps them)
local function finish(rows, s)
	if s and s.side ~= "sell" and X.BuyIdea then
		local kept = {}
		for _, r in ipairs(rows) do
			if not X.Ignored(r.key) and (s.key == "vendorfloor" or s.side ~= "buy" or X.BuyIdea(r.key)) then kept[#kept + 1] = r end
		end
		rows = kept
	end
	for _, r in ipairs(rows) do r.total = (r.profit or 0) * (r.qty or 1) end
	table.sort(rows, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.key < b.key
	end)
	for i = #rows, MAX_ROWS + 1, -1 do rows[i] = nil end
	return rows
end
-- one item for one strategy (errors of one item never stop the rest)
local function oneItem(s, key, it, st, P, ctx, out)
	local ok, row = pcall(s.each, key, it, st, P, ctx)
	if ok and row then out[#out + 1] = row elseif not ok then X.Debug("strategy " .. s.key .. ": " .. tostring(row)) end
end
-- can this item be looked at? (a fresh price; listed, or known to be owned for the sell strategies)
local function usable(it)
	return it.cur and it.cur.t and X.Fresh(it)
end
-- everything at once, now (the tests, and a first look when nothing is cached)
local function runNow(s, P, ctx)
	ctx = ctx or newCtx()
	local rows = {}
	if s.each then
		for key, it in pairs(X.Items()) do
			if usable(it) then oneItem(s, key, it, X.Stats(it), P, ctx, rows) end
		end
	elseif s.list then
		local ok, r = pcall(s.list, P, ctx)
		if ok and type(r) == "table" then rows = r end
	end
	return finish(rows, s)
end
for _, s in ipairs(LIST) do
	s.run = function(P) return runNow(s, P or X.StrategyParams(s.key)) end
end

function X.StrategyMarksBuild()
	local m = {}
	for _, s in ipairs(LIST) do
		local c = cache[s.key]
		if c and X.StrategyOn(s.key) then
			for _, r in ipairs(c.rows) do
				m[r.key] = m[r.key] or {}
				table.insert(m[r.key], s.key)
			end
		end
	end
	marks = m
end

-- the rows of a strategy (from the last run; worked out now when there are none)
function X.RunStrategy(key)
	local s = BY[key]
	if not s then return {} end
	local c = cache[key]
	if c then return c.rows, c end
	local rows = runNow(s, X.StrategyParams(key))
	cache[key] = {rows = rows, at = GetTime(), t = X.Now()}
	return rows, cache[key]
end
-- the cached rows only (nil when not worked out yet) - never slow
function X.StrategyRows(key)
	local c = cache[key]
	return c and c.rows or nil, c
end

-- the job: one pass over all items, every strategy that looks at single items, then the list strategies
-- (a request while it runs: everything once more afterwards; gen counts price changes, so a change during a run
-- leaves the results marked old)
local running, again, gen, pending = false, false, 0, false
function X.StrategyBusy() return running end
function X.StrategyUpdate(only)
	if running then
		again = true
		return
	end
	running = true
	local startGen = gen
	local todo = {}
	for _, s in ipairs(LIST) do
		if not only or s.key == only then todo[#todo + 1] = {s = s, P = X.StrategyParams(s.key), rows = {}} end
	end
	local ctx = newCtx()
	local keys, k, phase, li = nil, 0, 1, 0
	local eachers, listers = {}, {}
	for _, t in ipairs(todo) do
		if t.s.each then eachers[#eachers + 1] = t else listers[#listers + 1] = t end
	end
	local items = X.Items()
	X.Job("strategies", function()
		if not keys then
			keys = {}
			if #eachers > 0 then for key in pairs(items) do keys[#keys + 1] = key end end
			return false
		end
		if phase == 1 then
			local stop = min(#keys, k + STEP)
			while k < stop do
				k = k + 1
				local key = keys[k]
				local it = items[key]
				if it and usable(it) then
					local st = X.Stats(it)
					for i = 1, #eachers do
						local t = eachers[i]
						oneItem(t.s, key, it, st, t.P, ctx, t.rows)
					end
				end
			end
			if k >= #keys then phase = 2 end
			return false
		end
		-- one list strategy per frame
		li = li + 1
		local t = listers[li]
		if t then
			local ok, r = pcall(t.s.list, t.P, ctx)
			if ok and type(r) == "table" then t.rows = r elseif not ok then X.Debug("strategy " .. t.s.key .. ": " .. tostring(r)) end
		end
		return li >= #listers
	end, function()
		local at, t = GetTime(), X.Now()
		for _, x in ipairs(todo) do cache[x.s.key] = {rows = finish(x.rows, x.s), at = at, t = t} end
		if not only and gen == startGen then dirty = false end
		running = false
		X.StrategyMarksBuild()
		X.Fire("XNAH_STRATEGY")
		if again then
			again = false
			X.StrategyUpdate()
		end
	end)
end

-- [[ when to work it out again ]] only while the tab is open or tooltips are marked
local function tabShown()
	local UI = X.UI
	local f = UI and UI.Frame and UI.Frame()
	return f and f:IsShown() and UI.current == "strategies" or false
end
local function anyOn()
	for _, s in ipairs(LIST) do if X.StrategyOn(s.key) then return true end end
	return false
end
function X.StrategyNeeded()
	local simple = X.Simple and X.Simple.Frame and X.Simple.Frame()
	return tabShown() or anyOn() or (simple and simple:IsShown()) or false
end
-- the tab calls this when shown: works it out again when prices changed or the results are old
function X.StrategyCheck()
	if running then return end
	local old = false
	for _, s in ipairs(LIST) do
		local c = cache[s.key]
		if not c or GetTime() - c.at > MAX_AGE then old = true break end
	end
	if dirty or old then X.StrategyUpdate() end
end
local function changed()
	dirty = true
	gen = gen + 1
	pending = true
	X.Debounce("strategies", 2, function()
		pending = false
		if X.StrategyNeeded() then X.StrategyUpdate() end
	end)
end
for _, e in ipairs({"XNAH_PRICES", "XNAH_ANALYSIS", "XNAH_INVENTORY", "XNAH_RECIPES", "XNAH_LEDGER"}) do X.On(e, changed) end
X.On("XNAH_FULLSCAN", function(rows, t)
	if type(rows) == "table" and t then lastScan = {rows = rows, t = t} end
end)

-- [[ for the tooltip and the item page ]]
-- names of the strategies switched on that list this item
function X.StrategyMarks(key)
	if dirty and not pending and not running and anyOn() then changed() end
	local list = marks[key]
	if not list then return {} end
	local out = {}
	for i, sk in ipairs(list) do out[i] = BY[sk].name end
	return out
end
-- every strategy (on or not) that lists this item, from the last results: {{key, name, action, why, profit}}
function X.StrategyHits(key)
	local out = {}
	for _, s in ipairs(LIST) do
		local c = cache[s.key]
		if c then
			for _, r in ipairs(c.rows) do
				if r.key == key then
					out[#out + 1] = {key = s.key, name = s.name, action = r.action, why = r.why, profit = r.profit}
					break
				end
			end
		end
	end
	return out
end

-- for the tests: forget the results (all = the last full scan too)
function X.StrategyForget(all)
	cache, marks, dirty = {}, {}, true
	if all then lastScan = nil end
end
