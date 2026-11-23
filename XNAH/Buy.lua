-- Live searches of one item, and buying from them (the purchase engine; "Buy cheapest now" is built on it).
--   X.LiveSearch(key, fn): one search of one item (queued, about one a second, never while a scan runs); the answer
--     is kept in X.live[key] with every offer and which of them are YOURS (the game marks them), so prices "not ours"
--     are known.
--   Buying: X.BuyStart(key, need, max, source, tag) searches the item and works out what the next click buys.
--     X.BuyClick() must be called straight from a click on one of OUR buttons (the game allows buying only then) and
--     does ONE thing per click: stackable items (commodities) "start" (the server answers with the exact price) and a
--     second click confirms; other items are bought ONE item per click (also from an auction of 7: the game sells one
--     of them for the price of one, verified in the game 2026-11-23). One purchase at a time (X.buy).
--   X.PriceNow(key): the cheapest price of one now (not yours); X.BuyLimit(key): the most to pay when you did not say.
local ADDON, X = ...

-- [key] = {t, at, commodity, offers = {{unit (price of one), qty (not ours), own (ours), auctionID, buyout, total}},
-- lowest, ownLowest, qty}; buyout (other items only) = what the game's Buyout button sends for that auction (the price
-- of one; one press buys one), total = what all of that auction would cost (price of one x how many, for the ladder)
X.live = {}
X.SEARCH_GAP = 1.0 -- seconds between two searches of ours
X.QUOTE_WAIT = 5   -- seconds to wait for the exact price of a commodity purchase

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
-- quantity. PlaceBid with it buys ONE item of the auction for the price of one (verified in the game 2026-11-23: an
-- auction of 7 at 34s 13c each, one press = one item for 34s 13c, 6 left).
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
-- other items = ONE item of the cheapest auction at most `max` each (one press buys one, whatever the auction's size;
-- plan.listed = how many that auction has). plan.total = what the next press costs (other items: the price of one);
-- plan.buyout = the amount sent with the click. anyStack is no longer needed (kept so callers do not break).
function X.BuyPlan(key, need, max, anyStack)
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
			else
				local one = o.buyout or o.unit
				plan.offers[#plan.offers + 1] = {unit = o.unit, qty = o.qty, auctionID = o.auctionID, buyout = one}
				if not plan.auctionID then
					plan.auctionID, plan.buyout, plan.qty, plan.total, plan.listed = o.auctionID, one, 1, one, o.qty
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
		local plan = X.BuyPlan(b.key, b.need, b.max, b.cheapest)
		b.plan = plan
		if plan then setState("ready", nil)
		else setState("none", "Nothing listed" .. (b.max and (" at or under " .. X.MoneyPlain(b.max) .. " each") or "") ..
			(b.cheapest and " that is not yours" or "") .. " right now.") end
	end)
end
X.BuyResearch = function() if X.buy.key then research() end end

-- start buying `need` of an item, at most `max` copper each (nil = any price); need nil = as many as are listed at or
-- under `max` (worked out again after each purchase). cheapest = true ("Buy cheapest now"): other items buy one item of
-- the cheapest auction that is not yours, whatever its size; after each purchase it searches again and is ready for the
-- next one (`need` - the commodities to buy per purchase - stays as it is)
function X.BuyStart(key, need, max, source, tag, cheapest)
	if X.buy.state == "quoting" or X.buy.state == "confirm" or X.buy.state == "toohigh" then X.BuyCancel() end
	X.buy = {state = "idle", key = key, itemID = X.KeyID(key), need = math.max(0, need or 0), all = need == nil, max = max,
		source = source, tag = tag, token = {}, bought = 0, spent = 0, cheapest = cheapest and true or nil}
	research()
end
-- "Buy cheapest now": how many of a commodity one purchase buys. Worked out again from the last search (no new search),
-- or, when the exact price was already asked, that purchase is stopped and the item searched again.
function X.BuyNeed(n)
	local b = X.buy
	n = math.max(1, math.floor(tonumber(n) or 1))
	if not b.key or b.need == n then return end
	b.need = n
	if b.state == "quoting" or b.state == "confirm" then
		X.BuyCancel()
	elseif b.state == "ready" or b.state == "none" then
		b.plan = X.BuyPlan(b.key, b.need, b.max, b.cheapest)
		if b.plan then setState("ready", nil) else setState("none", "Nothing listed right now.") end
	end
end
function X.BuyClear()
	if X.buy.state == "quoting" or X.buy.state == "confirm" or X.buy.state == "toohigh" then X.BuyCancel() end
	X.buy = {state = "idle"}
	X.Fire("XNAH_BUY")
end

-- the "Buy cheapest now" button: its label always shows the exact amount the next press pays
local function cheapestLabel(b)
	local s = b.state
	if not X.ahOpen then return "Open the auction house to buy", false end
	if s == "ready" and b.plan then
		local p = b.plan
		return "Buy " .. X.Num(p.qty) .. " for " .. X.MoneyPlain(p.total), true
	elseif s == "confirm" and b.quote then
		return "Confirm: " .. X.Num(b.quote.qty) .. " for " .. X.MoneyPlain(b.quote.total), true
	elseif s == "searching" then return "Searching ...", false
	elseif s == "quoting" then return "Asking the exact price ...", false
	elseif s == "buying" then return "Buying ...", false
	elseif s == "none" then return "Nothing to buy - search again", true end
	return "Search the auction house", true
end

-- the label and state of the Buy button: text, enabled
function X.BuyButton()
	local b = X.buy
	local s = b.state
	if not b.key then return "Buy", false end
	if b.cheapest then return cheapestLabel(b) end
	if not X.ahOpen then return "Buy (auction house closed)", false end
	if s == "ready" and b.plan then
		if b.plan.commodity then return "Buy " .. X.Num(b.plan.qty) .. " for about " .. X.MoneyPlain(b.plan.total), true end
		return "Buy 1 for " .. X.MoneyPlain(b.plan.total), true
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
			-- no price back within 5 seconds: stopped, said so, and searched again (the next press starts over)
			local token = b.token
			X.After(X.QUOTE_WAIT, function()
				if X.buy.token ~= token or X.buy.state ~= "quoting" then return end
				X.Try(C_AuctionHouse.CancelCommoditiesPurchase)
				X.Print("no price came back from the auction house in " .. X.QUOTE_WAIT .. " seconds - stopped, press again")
				research()
			end)
		else
			-- the amount sent is the auction's buyoutAmount as the search gave it (the price of one), exactly as the
			-- game's own Buyout button does; it buys ONE item for that (gold before, to see what was really taken)
			b.buyingID, b.buyingListed = plan.auctionID, plan.listed or 1
			b.buyingOne, b.moneyBefore = plan.buyout, GetMoney and GetMoney() or nil
			C_AuctionHouse.PlaceBid(plan.auctionID, plan.buyout)
			setState("buying", "Buying 1 for " .. X.MoneyPlain(plan.buyout) .. " ...")
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
	if not b.cheapest then b.need = math.max(0, b.need - qty) end
	b.bought = b.bought + qty
	b.spent = b.spent + (total or 0)
	X.Print("bought " .. X.Num(qty) .. " " .. X.ItemText(b.key) .. " for " .. X.Money(total or 0))
	X.Fire("XNAH_BOUGHT", b.key, qty, total, b.source, b.tag)
	research()
end

-- the exact price of a started commodity purchase (again when it changes while the purchase waits for its confirm, so
-- the button always shows what the next press pays)
X.On("COMMODITY_PRICE_UPDATED", function(unit, total)
	local b = X.buy
	if b.state ~= "quoting" and b.state ~= "confirm" then return end
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
	-- one press buys ONE item for the price of one (verified in the game). The gold that went is the truth when it is
	-- already known: about k x the price of one (a little over is allowed) = k bought. In the game the gold often has
	-- not changed yet when this event comes (0 went): then it is 1 at the price of one - never the whole auction.
	local one = b.buyingOne or 0
	local qty, cost = 1, one
	local now = GetMoney and GetMoney() or nil
	if one > 0 and type(now) == "number" and type(b.moneyBefore) == "number" then
		local went = b.moneyBefore - now
		local k = math.floor(went / one)
		if k >= 1 and k <= math.max(1, b.buyingListed or 1) and went <= k * one + math.max(1, math.floor(one / 20)) then
			qty, cost = k, went
		end
	end
	b.moneyBefore, b.buyingOne, b.buyingListed = nil, nil, nil
	bought(qty, cost)
end)
X.On("AUCTION_HOUSE_SHOW_ERROR", function()
	if X.buy.state == "buying" and X.buy.buyingID then
		X.buy.buyingID = nil
		X.Print("the purchase did not go through - searching again")
		research()
	end
end)

-- [[ prices for buying ]]
-- the cheapest price of one right now that is not yours: a search of the last 10 minutes, else a fresh scan price;
-- second value "search" or "scan"
function X.PriceNow(key)
	local low = X.LiveLowest(key, 600)
	if low then return low, "search" end
	local it = X.Items()[key]
	if it and it.cur and it.cur.min and (it.cur.qty or 0) > 0 and X.Fresh(it) then return it.cur.min, "scan" end
	return nil
end

-- the most XNAH pays for one when you did not say: a little over the usual price, else a little over the cheapest now
function X.BuyLimit(key)
	local usual = X.Usual(key)
	if usual then return math.floor(usual * 1.1) end
	local low = X.PriceNow(key)
	if low then return math.floor(low * 1.2) end
	return nil
end
