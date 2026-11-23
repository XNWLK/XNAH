-- Live searches of one item, and buying from them (shared by the Sell tab, the sniper and the shopping lists).
--   X.LiveSearch(key, fn): one search of one item (queued, about one a second, never while a scan runs); the answer
--     is kept in X.live[key] with every offer and which of them are YOURS (the game marks them), so prices "not ours"
--     are known.
--   Buying: X.BuyStart(key, need, max, source, tag) searches the item and works out what the next click buys.
--     X.BuyClick() must be called straight from a click on one of OUR buttons (the game allows buying only then) and
--     does ONE thing per click: stackable items (commodities) "start" (the server answers with the exact price) and a
--     second click confirms; other items are bought one auction per click. One purchase at a time (X.buy).
--   X.BuyIdeas(limit): the best buys right now; X.NextBuy(src): the "Next buy" key (both at the end of this file).
local ADDON, X = ...

-- [key] = {t, at, commodity, offers = {{unit (price of one), qty (not ours), own (ours), auctionID, buyout, total}},
-- lowest, ownLowest, qty}; buyout (other items only) = what the game's Buyout button sends for that auction, total =
-- what all of that auction costs
X.live = {}
X.SEARCH_GAP = 1.0 -- seconds between two searches of ours

local queue, pending, pumping = {}, nil, false
local lastOurs, lastForeign = -100, -100

local function itemKeyFor(key)
	local id = X.KeyID(key)
	local suffix = tonumber((tostring(key):match(":(%-?%d+)$")))
	return C_AuctionHouse.MakeItemKey(id, 0, suffix or 0)
end

-- why XNAH cannot search right now (nil = it can)
function X.SearchBlocked()
	if not X.ahOpen then return "the auction house is closed" end
	if X.scan.state ~= "idle" then return "a scan is running" end
	return nil
end
-- seconds since a search that was not ours answered (you using the auction house yourself)
function X.ForeignSearchAge()
	return GetTime() - lastForeign
end
function X.SearchQueueLength()
	return #queue + (pending and 1 or 0)
end

local function finish(p, live)
	for _, fn in ipairs(p.fns) do
		local ok, err = pcall(fn, live)
		if not ok then X.OnError(err) end
	end
end

local pump
local function later(s)
	X.After(s, pump)
end
pump = function()
	if pending then
		if GetTime() - pending.sentAt < 6 then later(0.3) return end
		-- no answer in 6 s: given up
		local p = pending
		pending = nil
		finish(p, nil)
	end
	if #queue == 0 then pumping = false return end
	if not X.ahOpen then
		local q = queue
		queue = {}
		pumping = false
		for _, p in ipairs(q) do finish(p, nil) end
		return
	end
	local ready = not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
	if X.scan.state ~= "idle" or not ready or GetTime() - lastOurs < X.SEARCH_GAP then later(0.3) return end
	local p = table.remove(queue, 1)
	p.sentAt = GetTime()
	pending = p
	lastOurs = GetTime()
	C_AuctionHouse.SendSearchQuery(itemKeyFor(p.key), {{sortOrder = 0, reverseSort = false}}, true)
	later(0.3)
end

-- one search of one item; fn(live) when it answered, fn(nil) when it did not (closed, no answer)
function X.LiveSearch(key, fn)
	if not key then return end
	if pending and pending.key == key then
		if fn then pending.fns[#pending.fns + 1] = fn end
		return
	end
	for _, q in ipairs(queue) do
		if q.key == key then
			if fn then q.fns[#q.fns + 1] = fn end
			return
		end
	end
	queue[#queue + 1] = {key = key, fns = {fn}}
	if not pumping then
		pumping = true
		pump()
	end
end

-- the lowest price of one that is NOT yours, if searched within maxAge seconds (default 10 minutes)
function X.LiveLowest(key, maxAge)
	local l = X.live[key]
	if not l or X.Now() - l.t > (maxAge or 600) then return nil, l end
	return l.lowest, l
end

local function store(key, offers, commodity)
	table.sort(offers, function(a, b) return a.unit < b.unit end)
	local live = {t = X.Now(), at = GetTime(), commodity = commodity, offers = offers, qty = 0}
	for _, o in ipairs(offers) do
		if o.qty > 0 then
			live.qty = live.qty + o.qty
			if not live.lowest then live.lowest = o.unit end
		end
		if o.own > 0 and not live.ownLowest then live.ownLowest = o.unit end
	end
	X.live[key] = live
	return live
end
local function answered(keys)
	local p = pending
	if p and keys[p.key] then
		pending = nil
		finish(p, X.live[p.key])
	else
		lastForeign = GetTime() -- someone else searched (you, or another part of XNAH)
	end
	X.Debounce("live", 0.1, function() X.Fire("XNAH_LIVE") end)
end

-- stackable items: one row per price, the game tells how many of them are yours
X.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if not itemID then return end
	if not X.Try(C_AuctionHouse.HasFullCommoditySearchResults, itemID) then return end
	local n = X.Try(C_AuctionHouse.GetNumCommoditySearchResults, itemID) or 0
	local offers = {}
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, i)
		if r and r.unitPrice and r.unitPrice > 0 then
			local own = r.numOwnerItems or 0
			if own == 0 and r.containsOwnerItem then own = r.quantity or 0 end
			offers[#offers + 1] = {unit = r.unitPrice, qty = math.max(0, (r.quantity or 0) - own), own = own, auctionID = r.auctionID}
		end
	end
	local key = tostring(itemID)
	store(key, offers, true)
	answered({[key] = true})
end)
-- other items: one row per auction. Its buyoutAmount is the price of ONE, also when the auction is a stack of 40
-- (the game's own list shows it as it is, and its Buyout button sends exactly that amount) - never divide it by the
-- quantity. The whole auction costs buyoutAmount x quantity.
X.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
	if type(itemKey) ~= "table" then return end
	if not X.Try(C_AuctionHouse.HasFullItemSearchResults, itemKey) then return end
	local n = X.Try(C_AuctionHouse.GetNumItemSearchResults, itemKey) or 0
	local main = X.KeyOfItemKey(itemKey)
	local byKey = {}
	if main then byKey[main] = {} end
	for i = 1, n do
		local r = X.Try(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
		if r and r.buyoutAmount and r.buyoutAmount > 0 then
			local key = X.KeyFromLink(r.itemLink) or X.KeyOfItemKey(r.itemKey) or main
			local count = r.quantity or 1
			local mine = r.containsOwnerItem == true
			byKey[key] = byKey[key] or {}
			table.insert(byKey[key], {unit = r.buyoutAmount, qty = mine and 0 or count, own = mine and count or 0,
				auctionID = r.auctionID, buyout = r.buyoutAmount, total = r.buyoutAmount * count})
		end
	end
	local keys = {}
	for key, offers in pairs(byKey) do
		store(key, offers, false)
		keys[key] = true
	end
	answered(keys)
end)
X.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function() lastForeign = GetTime() end)
X.On("AUCTION_HOUSE_CLOSED", function()
	if X.buy.state ~= "idle" then
		X.buy.state = "closed"
		X.buy.text = "The auction house was closed."
	end
	X.Fire("XNAH_BUY")
end)

-- [[ buying ]]
-- X.buy = {state, key, itemID, need, max, source, tag, plan, quote, text}
-- states: idle, searching, ready (plan = what the next click buys), none (nothing at or under the max price),
-- quoting (asked the server for the exact price), confirm (price known: the next click buys), toohigh (the price
-- went over the max), buying (waiting for the server), done (got all), closed
X.buy = {state = "idle"}

-- what to buy from the offers of a search: commodities = the cheapest units up to `need`, each at most `max`;
-- other items = the cheapest auction (at most `max` each and not more than `need`). plan.total = what it all costs
-- (other items: the whole auction, price of one x how many); plan.buyout = the amount sent with the click
function X.BuyPlan(key, need, max)
	local live = X.live[key]
	if not live then return nil end
	local plan = {key = key, commodity = live.commodity, qty = 0, total = 0, offers = {}}
	for _, o in ipairs(live.offers) do
		if o.qty > 0 and (not max or o.unit <= max) then
			if live.commodity then
				local take = math.min(o.qty, need - plan.qty)
				if take <= 0 then break end
				plan.qty = plan.qty + take
				plan.total = plan.total + take * o.unit
				plan.offers[#plan.offers + 1] = {unit = o.unit, qty = take}
			elseif o.qty <= need then
				local all = o.total or o.unit * o.qty
				plan.offers[#plan.offers + 1] = {unit = o.unit, qty = o.qty, auctionID = o.auctionID, buyout = o.buyout, total = all}
				if not plan.auctionID then
					plan.auctionID, plan.buyout, plan.qty, plan.total = o.auctionID, o.buyout, o.qty, all
				end
			end
		end
	end
	if plan.qty == 0 then return nil end
	return plan
end

local function setState(state, text)
	X.buy.state = state
	X.buy.text = text
	X.Fire("XNAH_BUY")
end
local function research()
	local b = X.buy
	local token = b.token
	if not b.all and b.need <= 0 then setState("done", "Bought everything that was needed.") return end
	setState("searching", "Searching " .. X.ItemName(b.key) .. " ...")
	X.LiveSearch(b.key, function(live)
		if X.buy.token ~= token then return end
		if not live then setState("none", X.ahOpen and "No answer from the auction house - press Search again." or "The auction house is closed.") return end
		if b.all then
			-- "as many as there are at or under the max": the need comes from this search
			local n = 0
			for _, o in ipairs(live.offers) do
				if o.qty > 0 and (not b.max or o.unit <= b.max) then n = n + o.qty end
			end
			b.need = n
			if n == 0 and (b.bought or 0) > 0 then setState("done", "Bought all there was at or under your price.") return end
		end
		local plan = X.BuyPlan(b.key, b.need, b.max)
		b.plan = plan
		if plan then setState("ready", nil)
		else setState("none", "Nothing listed" .. (b.max and (" at or under " .. X.MoneyPlain(b.max) .. " each") or "") .. " right now.") end
	end)
end
X.BuyResearch = function() if X.buy.key then research() end end

-- start buying `need` of an item, at most `max` copper each (nil = any price); need nil = as many as are listed at or
-- under `max` (worked out again after each purchase)
function X.BuyStart(key, need, max, source, tag)
	if X.buy.state == "quoting" or X.buy.state == "confirm" or X.buy.state == "toohigh" then X.BuyCancel() end
	X.buy = {state = "idle", key = key, itemID = X.KeyID(key), need = math.max(0, need or 0), all = need == nil, max = max,
		source = source, tag = tag, token = {}, bought = 0, spent = 0}
	research()
end
function X.BuyClear()
	if X.buy.state == "quoting" or X.buy.state == "confirm" or X.buy.state == "toohigh" then X.BuyCancel() end
	X.buy = {state = "idle"}
	X.Fire("XNAH_BUY")
end

-- the label and state of the Buy button: text, enabled
function X.BuyButton()
	local b = X.buy
	local s = b.state
	if not b.key then return "Buy", false end
	if not X.ahOpen then return "Buy (auction house closed)", false end
	if s == "ready" and b.plan then
		if b.plan.commodity then return "Buy " .. X.Num(b.plan.qty) .. " for about " .. X.MoneyPlain(b.plan.total), true end
		if b.plan.qty > 1 then return "Buy " .. X.Num(b.plan.qty) .. " for " .. X.MoneyPlain(b.plan.total), true end
		return "Buy for " .. X.MoneyPlain(b.plan.total), true
	elseif s == "confirm" and b.quote then
		return "Confirm " .. X.Num(b.quote.qty) .. " for " .. X.MoneyPlain(b.quote.total), true
	elseif s == "searching" then return "Searching ...", false
	elseif s == "quoting" then return "Asking the price ...", false
	elseif s == "buying" then return "Buying ...", false
	elseif s == "toohigh" then return "Price went up", false
	elseif s == "done" then return "Done", false end
	return "Buy", false
end

-- ONE purchase step. Call it only straight from the OnClick of our own button.
function X.BuyClick()
	local b = X.buy
	if not X.ahOpen or not b.key then return false end
	if b.state == "ready" and b.plan then
		local plan = b.plan
		if plan.commodity then
			b.quote = nil
			b.asked = plan.qty
			-- the average price of one as a third value, as Blizzard's own buy window does (not in the documents)
			C_AuctionHouse.StartCommoditiesPurchase(b.itemID, plan.qty, math.ceil(plan.total / math.max(1, plan.qty)))
			setState("quoting", "Asking the server for the exact price of " .. X.Num(plan.qty) .. " ...")
		else
			-- the amount sent is the auction's buyoutAmount as the search gave it (the price of one), exactly as the
			-- game's own Buyout button does; the cost is the whole auction (gold before, to see what was really taken)
			b.buyingID, b.buyingQty, b.buyingPrice = plan.auctionID, plan.qty, plan.total
			b.buyingOne, b.moneyBefore = plan.buyout, GetMoney and GetMoney() or nil
			C_AuctionHouse.PlaceBid(plan.auctionID, plan.buyout)
			setState("buying", "Buying " .. (plan.qty > 1 and (X.Num(plan.qty) .. " ") or "") .. "for " .. X.MoneyPlain(plan.total) .. " ...")
		end
	elseif b.state == "confirm" and b.quote then
		if b.max and b.quote.unit > b.max then setState("toohigh", "The price is over your max.") return false end
		b.buyingQty, b.buyingPrice = b.quote.qty, b.quote.total
		C_AuctionHouse.ConfirmCommoditiesPurchase(b.itemID, b.quote.qty)
		setState("buying", "Buying " .. X.Num(b.quote.qty) .. " for " .. X.MoneyPlain(b.quote.total) .. " ...")
	else
		return false
	end
	-- no answer within 15 s: look again
	local token, state = b.token, b.state
	X.After(15, function()
		if X.buy.token == token and X.buy.state == state then research() end
	end)
	return true
end

-- stop a commodity purchase that was started (not restricted)
function X.BuyCancel()
	local b = X.buy
	if b.state == "quoting" or b.state == "confirm" or b.state == "toohigh" then
		X.Try(C_AuctionHouse.CancelCommoditiesPurchase)
	end
	if b.key and X.ahOpen then research() else setState("idle") end
end

local function bought(qty, total)
	local b = X.buy
	b.need = math.max(0, b.need - qty)
	b.bought = b.bought + qty
	b.spent = b.spent + (total or 0)
	X.Print("bought " .. X.Num(qty) .. " " .. X.ItemText(b.key) .. " for " .. X.Money(total or 0))
	X.Fire("XNAH_BOUGHT", b.key, qty, total, b.source, b.tag)
	research()
end

X.On("COMMODITY_PRICE_UPDATED", function(unit, total)
	local b = X.buy
	if b.state ~= "quoting" then return end
	b.quote = {unit = unit, total = total, qty = b.asked}
	if b.max and unit and unit > b.max then
		setState("toohigh", "The real price is " .. X.MoneyPlain(unit) .. " each, over your max of " .. X.MoneyPlain(b.max) .. ". Press Cancel.")
	else
		setState("confirm", "Exact price: " .. X.MoneyPlain(unit) .. " each. Click again to buy.")
	end
end)
X.On("COMMODITY_PRICE_UNAVAILABLE", function()
	if X.buy.state == "quoting" then X.Print("that price is gone - searching again") research() end
end)
X.On("COMMODITY_PURCHASE_SUCCEEDED", function()
	local b = X.buy
	if b.state ~= "buying" or not b.quote then return end
	bought(b.quote.qty, b.quote.total)
end)
X.On("COMMODITY_PURCHASE_FAILED", function()
	if X.buy.state == "buying" then X.Print("the purchase failed - searching again") research() end
end)
X.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
	local b = X.buy
	if b.state ~= "buying" or not b.buyingID or b.buyingID ~= auctionID then return end
	b.buyingID = nil
	-- what it really cost: the gold that went, when that is a believable amount (between the price of one and the whole
	-- auction - not checked in the game whether a stack costs one buyout or buyout x quantity); else the whole auction
	local cost = b.buyingPrice
	local now = GetMoney and GetMoney() or nil
	if type(now) == "number" and type(b.moneyBefore) == "number" and b.buyingOne and cost then
		local went = b.moneyBefore - now
		if went >= b.buyingOne and went <= cost then cost = went end
	end
	b.moneyBefore, b.buyingOne = nil, nil
	bought(b.buyingQty or 1, cost)
end)
X.On("AUCTION_HOUSE_SHOW_ERROR", function()
	if X.buy.state == "buying" and X.buy.buyingID then
		X.buy.buyingID = nil
		X.Print("the purchase did not go through - searching again")
		research()
	end
end)

-- [[ the best buys right now ]] X.BuyIdeas(limit) -> rows, best first:
--   1. your shopping lists, the crafting queue's materials (Queue.lua, X.QueueBuys) and watched items with a max price,
--      when they are listed at or under that price now
--   2. good buys from the buy-side strategies' last results and the deals (listed far under the usual price), one per
--      item, the profit worked out again from today's cheapest price, after the auction house cut; risky ones only when
--      the profit is big. Items you said never to suggest and grey items are left out of these (X.BuyIdea).
-- row = {id, key, kind = "list" / "queue" / "watch" / "idea" / "deal", from (short text: where it comes from), why, action,
--   qty, max (the most to pay for one), price (cheapest now), each (profit each), profit (in all), target, risk,
--   source, tag (for X.BuyStart / UI.BuyButton)}
local MIN_TOTAL = 5000        -- 50s: a smaller buy is not worth the clicks
local BIG_TOTAL = 500000      -- 50g: a risky buy is shown only when it makes at least this much
local NOT_BUY = {de = true, vendorflip = true} -- buy-side strategies that are not "buy on the auction house"

local function nameOf(key) return (X.ItemName(key)) or ("item " .. tostring(key)) end
local function plain(c) return X.MoneyPlain(math.floor((c or 0) + 0.5)) end
local function gold() return GetMoney and GetMoney() or 0 end
-- the cheapest price of one right now that is not yours: a search of the last 10 minutes, else a fresh scan price
local function priceNow(key)
	local low = X.LiveLowest(key, 600)
	if low then return low, "search" end
	local it = X.Items()[key]
	if it and it.cur and it.cur.min and (it.cur.qty or 0) > 0 and X.Fresh(it) then return it.cur.min, "scan" end
	return nil
end
X.PriceNow = priceNow
local function stackable(key)
	local l = X.live[key]
	if l and l.commodity ~= nil then return l.commodity end
	return (X.Try(C_Item.GetItemMaxStackSizeByID, X.KeyID(key)) or 1) > 1
end
local function rateOf(key) return X.SaleRate and X.Try(X.SaleRate, key) or nil end

-- the most XNAH pays for one when you did not say: a little over the usual price, else a little over the cheapest now
function X.BuyLimit(key)
	local usual = X.Usual(key)
	if usual then return math.floor(usual * 1.1) end
	local low = priceNow(key)
	if low then return math.floor(low * 1.2) end
	return nil
end

-- the id of a buy (also of a purchase that is going on): shopping lists count purchases by list name (the tag)
local function ideaId(source, tag, key)
	if source == "shop" then return "shop:" .. tostring(tag) .. ":" .. tostring(key) end
	return tag or tostring(key)
end
X.BuyIdeaId = ideaId

-- deals: the same test as the Deals page, over all items in slices, at most once a minute after prices changed (and
-- every 10 minutes anyway) - only when someone asks for the buy ideas
local deals = {rows = {}}
local dealsRunning, dealsDirty = false, true
local candidates, version, builtFor = {}, 1, 0
local cached, cachedFor, cachedAt, cachedLimit
local function dealsPass()
	dealsRunning = true
	local items, S = X.Items(), X.S()
	local keys, k, found = nil, 0, {}
	X.Job("buy ideas", function()
		if not keys then
			keys = {}
			for key in pairs(items) do keys[#keys + 1] = key end
			return #keys == 0
		end
		local stop = math.min(#keys, k + 300)
		while k < stop do
			k = k + 1
			local key = keys[k]
			local it = items[key]
			local cur = it and it.cur
			if cur and cur.min and (cur.qty or 0) > 0 and X.Fresh(it) and X.BuyIdea(key, it) then
				local usual, st = X.Usual(key)
				if usual and st and st.days >= S.minSamples and cur.min / usual * 100 <= S.dealPct and
					X.AfterCut(usual) - cur.min >= S.dealMinProfit then
					found[#found + 1] = {key = key, action = "Buy and relist", target = usual, from = "deal", kind = "deal"}
				end
			end
		end
		return k >= #keys
	end, function()
		deals = {rows = found, at = GetTime()}
		dealsRunning = false
		version = version + 1
		X.Fire("XNAH_BUYIDEAS")
	end)
end
local function dealsCheck()
	if dealsRunning then return end
	local age = deals.at and GetTime() - deals.at
	if age and (age < 60 or (not dealsDirty and age < 600)) then return end
	dealsDirty = false
	dealsPass()
end
X.On("XNAH_PRICES", function() dealsDirty = true version = version + 1 end)
X.On("XNAH_IGNORE", function() dealsDirty = true version = version + 1 end)
for _, ev in ipairs({"XNAH_STRATEGY", "XNAH_SHOP", "XNAH_WATCH", "XNAH_BOUGHT", "XNAH_LIVE", "XNAH_QUEUE", "XNAH_INVENTORY"}) do
	X.On(ev, function() version = version + 1 end)
end
-- still looking (the deals pass or the strategies are being worked out)
function X.BuyIdeasBusy()
	return dealsRunning or (X.StrategyBusy and X.StrategyBusy()) or false
end

-- the buy-side strategies' last results (never worked out here: X.StrategyCheck starts its sliced job when they are
-- old) and the deals, one per item (the best)
local lastStrategyCheck = -100
local function buildCandidates()
	if builtFor == version then return candidates end
	builtFor = version
	local best = {}
	local function take(c, score)
		local old = best[c.key]
		if not old or score > old.score then
			c.score = score
			best[c.key] = c
		end
	end
	if X.Strategies and X.StrategyRows then
		for _, s in ipairs(X.Strategies()) do
			if s.side == "buy" and not NOT_BUY[s.key] then
				for _, r in ipairs(X.StrategyRows(s.key) or {}) do
					if not r.vendor and r.target and r.action and r.action:find("^Buy") then
						take({key = r.key, action = r.action, target = r.target, qty = r.qty, risk = r.risk, from = s.name, kind = "idea"},
							(r.profit or 0) * (r.qty or 1))
					end
				end
			end
		end
	end
	for _, d in ipairs(deals.rows) do take(d, 0) end
	local out = {}
	for _, c in pairs(best) do out[#out + 1] = c end
	candidates = out
	return out
end

-- your shopping lists, the crafting queue and your watch list (things you asked for), when they can be had at or
-- under your max price
local function wishes(out, seen)
	for _, list in ipairs(X.ShopLists and X.ShopLists() or {}) do
		local l = X.ShopList(list)
		for _, se in ipairs(l and l.items or {}) do
			local need = X.ShopNeed(se)
			local price = need > 0 and priceNow(se.key)
			if price and (not se.max or price <= se.max) and not seen[se.key] then
				seen[se.key] = true
				out[#out + 1] = {id = ideaId("shop", list, se.key), key = se.key, kind = "list", from = "list " .. list,
					why = "Still " .. X.Num(need) .. " to buy on your shopping list " .. list ..
						(se.max and (", at most " .. plain(se.max) .. " each.") or "."),
					action = "Buy", qty = need, max = se.max, price = price, profit = 0, source = "shop", tag = list}
			end
		end
	end
	-- the crafting queue's materials still to buy (Queue.lua: at a max price that keeps the crafts worth it)
	if X.QueueBuys then
		for _, q in ipairs(X.QueueBuys()) do
			local price = priceNow(q.key)
			if price and (not q.max or price <= q.max) and not seen[q.key] then
				seen[q.key] = true
				out[#out + 1] = {id = "queue:" .. q.key, key = q.key, kind = "queue", from = "craft queue",
					why = "Still " .. X.Num(q.buy) .. " to buy for your crafting queue" .. (q.max and (", at most " .. plain(q.max) .. " each.") or "."),
					action = "Buy", qty = q.buy, max = q.max, price = price, profit = 0, source = "queue", tag = "queue:" .. q.key}
			end
		end
	end
	for key, w in pairs(X.db.watch or {}) do
		local max = type(w) == "table" and w.max or nil
		local price = max and priceNow(key)
		if price and price <= max and not seen[key] then
			seen[key] = true
			local need = 1
			local live = X.live[key]
			if live and X.Now() - live.t <= 600 then
				local n = 0
				for _, o in ipairs(live.offers) do if o.unit <= max then n = n + o.qty end end
				need = math.max(1, n)
			elseif stackable(key) then
				need = 20
			end
			local usual = X.Usual(key)
			local each = usual and (X.AfterCut(usual) - price) or nil
			out[#out + 1] = {id = "watch:" .. key, key = key, kind = "watch", from = "watched",
				why = "You watch it with a max price of " .. plain(max) .. "; it is listed at " .. plain(price) .. " each.",
				action = "Buy", qty = need, max = max, price = price, each = each, profit = each and each * need or 0,
				target = usual, source = "watch", tag = "watch:" .. key}
		end
	end
end

function X.BuyIdeas(limit)
	if GetTime() - lastStrategyCheck > 20 and X.StrategyCheck then
		lastStrategyCheck = GetTime()
		X.Try(X.StrategyCheck)
	end
	dealsCheck()
	-- the same answer for a moment (the Buy tab, the key and the deal rows ask often)
	if cached and cachedFor == version and cachedLimit == limit and GetTime() - cachedAt < 2 then return cached end
	local out, seen = {}, {}
	wishes(out, seen)
	local good = {}
	for _, c in ipairs(buildCandidates()) do
		if not seen[c.key] and X.BuyIdea(c.key) then
			local price = priceNow(c.key)
			local net = price and (c.action == "Buy and vendor" and c.target or X.AfterCut(c.target))
			local each = net and net - price
			if each and each > 0 then
				local it = X.Items()[c.key]
				local rate = rateOf(c.key)
				local qty = c.qty
				if not qty then qty = (rate and rate > 0) and math.max(1, math.floor(rate * 3 + 0.5)) or 1 end
				local listed = it and it.cur and it.cur.qty
				local live = X.live[c.key]
				if live and live.qty and X.Now() - live.t <= 600 then listed = live.qty end
				if listed and listed > 0 then qty = math.min(qty, listed) end
				qty = math.max(1, math.floor(qty))
				local total = each * qty
				if total >= MIN_TOTAL and (c.risk ~= "High" or total >= BIG_TOTAL) then
					good[#good + 1] = {c = c, price = price, each = each, qty = qty, total = total, rate = rate}
				end
			end
		end
	end
	table.sort(good, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.c.key < b.c.key
	end)
	for _, g in ipairs(good) do
		if limit and #out >= limit then break end
		local c = g.c
		local vendor = c.action == "Buy and vendor"
		local tag = "idea:" .. c.key
		out[#out + 1] = {id = tag, key = c.key, kind = c.kind, from = c.from, action = c.action, risk = c.risk,
			why = (vendor and ("A vendor pays " .. plain(c.target) .. " for one") or ("It usually sells for " .. plain(c.target))) ..
				(g.rate and (", about " .. X.Rate(g.rate) .. " sell a day") or "") .. ".",
			qty = g.qty, price = g.price, each = g.each, profit = g.total, target = c.target,
			-- the most it may cost each: still at least half of the profit
			max = math.floor(g.price + g.each / 2), source = "idea", tag = tag}
	end
	if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
	cached, cachedFor, cachedAt, cachedLimit = out, version, GetTime(), limit
	return out
end

-- [[ Next buy ]] each press of its key (or of the Next buy button on the Buy tab) does the next step of the best buy:
-- check its price (a search), buy (stackable items: the server answers with the exact price), confirm; then on to the
-- next one. A press does at most ONE buying call, so it must come straight from a click or a key press.
--   X.NextBuyPeek() -> {what = closed / busy / wait / none / check / buy / confirm / poor, text, idea}
--   X.NextBuy(src)  ONE step (src "key" = the key binding: a line in chat says what happened)
--   X.NextBuySkip() leave the current or next buy out for 10 minutes
X.nextBuy = {passed = {}}
local PASS_FOR = 600
local FINISHED = {idle = true, none = true, toohigh = true, done = true, closed = true}
local function passedNow(id)
	local t = X.nextBuy.passed[id]
	return t ~= nil and GetTime() - t < PASS_FOR
end
local function pass(id) if id then X.nextBuy.passed[id] = GetTime() end end
local function currentId()
	local b = X.buy
	return b.key and ideaId(b.source, b.tag, b.key) or nil
end

function X.NextBuyPeek()
	if not X.ahOpen then return {what = "closed", text = "Open the auction house first"} end
	local b = X.buy
	local s = b.state
	if b.key then
		local name = nameOf(b.key)
		if s == "ready" and b.plan then
			local p = b.plan
			if p.total > gold() then return {what = "poor", text = "Not enough gold for " .. name .. " - press to skip it"} end
			return {what = "buy", text = "Buy " .. X.Num(p.qty) .. " " .. name .. (p.commodity and " for about " or " for ") .. plain(p.total)}
		elseif s == "confirm" and b.quote then
			if (b.quote.total or 0) > gold() then return {what = "poor", text = "Not enough gold for " .. name .. " - press to skip it"} end
			return {what = "confirm", text = "Confirm: buy " .. X.Num(b.quote.qty) .. " " .. name .. " for " .. plain(b.quote.total)}
		elseif s == "searching" then return {what = "busy", text = "Checking the price of " .. name .. " ..."}
		elseif s == "quoting" then return {what = "busy", text = "Asking the exact price of " .. name .. " ..."}
		elseif s == "buying" then return {what = "busy", text = "Buying " .. name .. " ..."} end
	end
	if X.scan.state ~= "idle" then return {what = "wait", text = "Wait until the scan is done"} end
	local skip = (b.key and FINISHED[s]) and currentId() or nil
	for _, idea in ipairs(X.BuyIdeas(40)) do
		if idea.id ~= skip and not passedNow(idea.id) then
			return {what = "check", idea = idea, text = "Check the price: " .. X.Num(idea.qty or 1) .. " " .. nameOf(idea.key) ..
				" (" .. (idea.from or "idea") .. ")"}
		end
	end
	if X.BuyIdeasBusy() then return {what = "wait", text = "Looking for good buys ..."} end
	return {what = "none", text = "No good buys right now"}
end

local function tell(src, text)
	if src == "key" and text then X.Print("next buy: " .. text) end
end
-- ONE step. Call it only straight from a click or a key press.
function X.NextBuy(src)
	local a = X.NextBuyPeek()
	if a.what == "buy" or a.what == "confirm" then
		return X.BuyClick()
	elseif a.what == "poor" then
		pass(currentId())
		X.BuyClear()
		tell(src, "skipped: not enough gold")
	elseif a.what == "check" then
		if X.buy.key and FINISHED[X.buy.state] then pass(currentId()) end
		local i = a.idea
		X.BuyStart(i.key, i.qty, i.max, i.source, i.tag)
		tell(src, "checking the price of " .. X.Num(i.qty or 1) .. " " .. X.ItemText(i.key) .. " - press again when it shows")
	else
		tell(src, a.text)
	end
	X.Fire("XNAH_BUY")
	return false
end

-- leave out the purchase going on (or the next buy) for 10 minutes; not restricted
function X.NextBuySkip()
	local b = X.buy
	if b.state == "buying" then return end
	-- a purchase going on: leave it
	if b.key and not FINISHED[b.state] then
		pass(currentId())
		X.BuyClear()
		return
	end
	-- else the buy the next press would check
	local a = X.NextBuyPeek()
	if a.idea then pass(a.idea.id) end
	X.Fire("XNAH_BUY")
end

-- [[ the key binding ]] (Bindings.xml; the key is set in the game's key bindings, under AddOns)
BINDING_NAME_XNAH_NEXTBUY = "Next buy: next step (buying only)"
function XNAH_NextBuy()
	X.NextBuy("key")
end
