-- The Buy and Sell pages of the simple window (UISimple.lua): what is worth buying now, what to post, what to cancel,
-- what to sell to a vendor - each with ONE button whose label always says what the next click does.
--   S.BuyEntries(limit)  -> buy entries, best first: your shopping lists and watch-list items under your max price,
--     then good buys from the buy-side strategies' last results and the deals (only fresh prices, the profit worked
--     out again from today's cheapest price, after the auction house cut; risky ones only when the profit is big).
--     The button drives Buy.lua: "Check the price" (a search) -> "Buy 4 for about 2g" -> "Confirm: buy 4 for 2g"
--     (stackable things need a second click) -> "Bought 4 for 2g".
--   S.SellEntries(limit) -> sell entries, best first: your undercut auctions ("Cancel this auction"), then things in
--     your bags worth posting at X.PostPrice ("Post 20 at 89c each"; a price warning needs a second click), then things
--     a vendor pays more for, then your junk. Each entry has `profit` = copper it brings.
-- Every button that buys, posts or cancels makes at most ONE such call, straight from the click. Nothing here does that
-- from a timer or an event; the background work (checking your auctions, searching prices about one a second, a deals
-- pass in slices) is never restricted. Buy / Post buttons for any item on Find: S.itemActions.
local ADDON, X = ...
local S = X.Simple
if not S then return end

local GREY, GREEN, RED, GOLD = "|cff999999", "|cff4ade80", "|cfff87171", "|cffffd100"
local MIN_TOTAL = 5000        -- 50s: a smaller buy is not worth the clicks
local BIG_TOTAL = 500000      -- 50g: a risky buy is shown only when it makes at least this much
local MIN_POST = 100          -- 1s: a post that brings less is not shown
local CANCEL_EVERY = 300      -- seconds between XNAH's own checks of your auctions (while the auction house is open)
local SEARCH_AGAIN = 120      -- a bag item's price is searched again after this many seconds without an answer
local SEARCHES_AT_ONCE = 8    -- bag items searched per listing at most (the queue does one a second)
local NOT_BUY = {de = true, vendorflip = true} -- buy-side strategies that are not "buy on the auction house"

local function money(c) return S.Money(c) end
local function plain(c) return X.MoneyPlain(math.floor((c or 0) + 0.5)) end
local function nameOf(key) return (X.ItemName(key)) or ("item " .. tostring(key)) end
local function fit(text, n)
	if #text <= n then return text end
	return text:sub(1, n - 3) .. "..."
end
local function gold() return GetMoney and GetMoney() or 0 end
-- the cheapest price of one right now that is not yours: a search of the last 10 minutes, else a fresh scan price
local function priceNow(key)
	local low = X.LiveLowest(key, 600)
	if low then return low, "search" end
	local it = X.Items()[key]
	if it and it.cur and it.cur.min and (it.cur.qty or 0) > 0 and X.Fresh(it) then return it.cur.min, "scan" end
	return nil
end
local function stackable(key)
	local l = X.live[key]
	if l and l.commodity ~= nil then return l.commodity end
	return (X.Try(C_Item.GetItemMaxStackSizeByID, X.KeyID(key)) or 1) > 1
end
local function rateOf(key) return X.SaleRate and X.Try(X.SaleRate, key) or nil end

-- [[ the Buy button ]] one Buy.lua purchase at a time; the entry whose purchase it is shows its state
local function buyButton(key, source, tag, need, max)
	if not X.ahOpen then return {label = "Open the auction house first", disabled = true, tip = "Buying works only while the auction house window is open."} end
	local b = X.buy
	local s = b.state
	local mine = b.key == key and b.source == source and b.tag == tag
	if not mine then
		if s == "quoting" or s == "confirm" or s == "buying" then return {label = "Wait: another purchase is going on", disabled = true} end
		if X.scan.state ~= "idle" then return {label = "Wait until the scan is done", disabled = true} end
		return {label = "Check the price", tip = "Searches the auction house for the live price. Nothing is bought yet.",
			run = function() X.BuyStart(key, need, max, source, tag) end}
	end
	if s == "ready" and b.plan then
		local p = b.plan
		if p.total > gold() then return {label = "Not enough gold", disabled = true} end
		local label
		if p.commodity then label = "Buy " .. X.Num(p.qty) .. " for about " .. plain(p.total)
		elseif (b.need or 1) > 1 then label = "Buy one for " .. plain(p.buyout) .. " (" .. X.Num(b.need) .. " to go)"
		else label = "Buy it for " .. plain(p.buyout) end
		return {label = label, run = function() X.BuyClick() end,
			tip = p.commodity and "The server then tells the exact price; a second click buys." or "One click buys this one auction."}
	end
	if s == "confirm" and b.quote then
		if (b.quote.total or 0) > gold() then return {label = "Not enough gold", disabled = true} end
		return {label = "Confirm: buy " .. X.Num(b.quote.qty) .. " for " .. plain(b.quote.total), run = function() X.BuyClick() end,
			tip = "The exact price from the server. This click buys."}
	end
	if s == "searching" or s == "idle" then return {label = "Checking the price ...", disabled = true} end
	if s == "quoting" then return {label = "Asking the exact price ...", disabled = true} end
	if s == "buying" then return {label = "Buying ...", disabled = true} end
	if s == "toohigh" then return {label = "The price went up: check again", run = function() X.BuyCancel() end} end
	if s == "none" then return {label = "None at a good price: check again", run = function() X.BuyResearch() end} end
	if s == "done" then return {label = "Bought " .. X.Num(b.bought or 0) .. " for " .. plain(b.spent), disabled = true} end
	return {label = "Check the price", run = function() X.BuyStart(key, need, max, source, tag) end}
end

-- [[ deals ]] listed far under the usual price (the same test as the Deals page), over all items in slices, at most
-- once a minute after prices changed (and every 10 minutes anyway) - only while someone looks at these pages
local deals = {rows = {}}
local dealsRunning, dealsDirty = false, true
local candidates, version, builtFor = {}, 1, 0
local function dealsPass()
	dealsRunning = true
	local items, Sx = X.Items(), X.S()
	local keys, k, found = nil, 0, {}
	X.Job("simple deals", function()
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
			if cur and cur.min and (cur.qty or 0) > 0 and X.Fresh(it) then
				local usual, st = X.Usual(key)
				if usual and st and st.days >= Sx.minSamples and cur.min / usual * 100 <= Sx.dealPct and
					X.AfterCut(usual) - cur.min >= Sx.dealMinProfit then
					found[#found + 1] = {key = key, action = "Buy and relist", target = usual, qty = nil, risk = nil}
				end
			end
		end
		return k >= #keys
	end, function()
		deals = {rows = found, at = GetTime()}
		dealsRunning = false
		version = version + 1
		S.RefreshSoon()
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
for _, ev in ipairs({"XNAH_STRATEGY", "XNAH_SHOP", "XNAH_WATCH", "XNAH_BOUGHT"}) do
	X.On(ev, function() version = version + 1 end)
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
						take({key = r.key, action = r.action, target = r.target, qty = r.qty, risk = r.risk, from = s.name},
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

local RISK_BADGE = {Low = GREEN .. "low risk|r", Medium = GOLD .. "some risk|r", High = RED .. "risky|r"}
local RISK_WHY = {Medium = " Its price moves a little.", High = " Risky: its price jumps around."}

local function buyEntry(c, price, each, qty, total, rate)
	local key = c.key
	local id = "buy:" .. key
	local vendor = c.action == "Buy and vendor"
	local hold = c.action == "Buy and hold"
	local many = qty > 1
	local e = {id = id, key = key, title = fit("Buy " .. X.Num(qty) .. " " .. nameOf(key), 30), sub = "you make " .. S.Signed(total),
		profit = total, price = price, badge = RISK_BADGE[c.risk or "Medium"], skip = true}
	if vendor then
		e.sentence = (many and ("Buy all " .. X.Num(qty) .. " now and sell them to a vendor") or "Buy it now and sell it to a vendor") ..
			" for " .. plain(c.target) .. (many and " each." or ".")
		e.why = "A vendor pays more for it than it is listed for: a sure profit."
	else
		e.sentence = (many and ("Buy all " .. X.Num(qty) .. " now and post them again") or "Buy it now and post it again") ..
			(hold and " when the price is back up, at about " or " at ") .. plain(c.target) .. (many and " each." or ".")
		e.why = "It usually sells for " .. plain(c.target) .. (rate and (" and about " .. X.Rate(rate) .. " sell a day.") or ".") ..
			(RISK_WHY[c.risk or "Medium"] or "")
	end
	e.lines = {{"Price now", money(price)}, {vendor and "Vendor pays" or "Sells for", money(c.target)},
		{"You make", S.Signed(total)}, {"Each", S.Signed(each)}}
	-- the most it may cost each: still at least half of the profit
	local max = math.floor(price + each / 2)
	e.button = buyButton(key, "simple", id, qty, max)
	return e
end

-- your shopping lists and your watch list (things you asked for), when they can be had at or under your max price
local function wishEntries(out, seen)
	for _, list in ipairs(X.ShopLists()) do
		local l = X.ShopList(list)
		for _, se in ipairs(l and l.items or {}) do
			local need = X.ShopNeed(se)
			local price = need > 0 and priceNow(se.key)
			if price and (not se.max or price <= se.max) and not seen[se.key] then
				seen[se.key] = true
				local id = "shop:" .. list .. ":" .. se.key
				out[#out + 1] = {id = id, key = se.key, title = fit("Buy " .. X.Num(need) .. " " .. nameOf(se.key), 30),
					sub = GREY .. "on your list " .. list .. "|r", price = price, profit = 0, skip = true,
					sentence = "Buy the " .. X.Num(need) .. " still on your shopping list \"" .. list .. "\".",
					why = se.max and ("It is listed at " .. plain(price) .. " each - at or under your max of " .. plain(se.max) .. ".") or
						("It is listed at " .. plain(price) .. " each (no max price set)."),
					button = buyButton(se.key, "shop", list, need, se.max)}
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
			local id = "watch:" .. key
			local profit = usual and (X.AfterCut(usual) - price) * need or 0
			out[#out + 1] = {id = id, key = key, title = fit("Buy " .. X.Num(need) .. " " .. nameOf(key), 30),
				sub = GREY .. "watched: under your max|r", price = price, profit = profit, skip = true,
				sentence = "Buy " .. (need > 1 and ("the " .. X.Num(need) .. " listed") or "it") .. " at or under your max of " .. plain(max) .. ".",
				why = "You starred it with a max price of " .. plain(max) .. ", and it is listed at " .. plain(price) .. " each.",
				button = buyButton(key, "simple", id, need, max)}
		end
	end
end

function S.BuyEntries(limit)
	if GetTime() - lastStrategyCheck > 20 and X.StrategyCheck then
		lastStrategyCheck = GetTime()
		X.Try(X.StrategyCheck)
	end
	dealsCheck()
	local out, seen = {}, {}
	wishEntries(out, seen)
	local good = {}
	for _, c in ipairs(buildCandidates()) do
		if not seen[c.key] then
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
		out[#out + 1] = buyEntry(g.c, g.price, g.each, g.qty, g.total, g.rate)
	end
	return out
end

-- [[ the Post button ]] one post per click (Post.lua); a price warning: Confirm / Don't post
local function postButtons(row, price, qty, deposit)
	local key = row.key
	if not X.ahOpen then return {label = "Open the auction house first", disabled = true, tip = "Posting works only while the auction house window is open."} end
	local p = X.post
	if p.state == "warning" and p.key == key then
		return {label = "Confirm: post anyway", run = function() X.PostConfirmClick() end,
			tip = "The auction house warns that this price is far from what it usually sells for. This click posts it anyway."},
			{label = "Don't post", run = function() X.PostCancelWarning() end}
	end
	if p.state == "sent" and p.key == key then return {label = "Posting ...", disabled = true} end
	if p.state ~= "idle" then return {label = "Wait: another post is going on", disabled = true} end
	if X.scan.state ~= "idle" then return {label = "Wait until the scan is done", disabled = true} end
	if deposit and deposit > gold() then return {label = "Not enough gold for the deposit", disabled = true} end
	local label = qty > 1 and ("Post " .. X.Num(qty) .. " at " .. plain(price) .. " each") or ("Post it at " .. plain(price))
	local duration = X.PostRule(key).duration
	return {label = label, tip = "One click = one auction, for " .. X.DURATIONS[duration or 3] .. ".", run = function()
		-- the bags may have changed since the list was made: the item's slots now, the price and amount on the button
		for _, r in ipairs(X.SellItems()) do
			if r.key == key then
				if r.have >= qty then X.PostClick(r, price, qty, duration) end
				return
			end
		end
	end}
end

-- the reason for a post price, in plain words
local function postWhy(reason, info)
	reason = reason or ""
	local scan = info and info.from == "scan" and " (price from the last scan)" or ""
	if reason:find("^undercut") then
		return "The cheapest other seller asks " .. plain(info.lowest) .. scan .. ". XNAH asks a little less, so yours sells first " ..
			"(that is called undercutting)."
	elseif reason:find("under your floor", 1, true) then
		return "Others sell it far under its usual price right now. XNAH asks a normal price instead of chasing the price down."
	elseif reason:find("over your ceiling", 1, true) then
		return "Others ask far more than usual. XNAH asks at most twice its usual price."
	elseif reason:find("nobody else", 1, true) then
		return "Nobody else sells it right now, so XNAH asks its usual price."
	elseif reason:find("no fresh lowest", 1, true) then
		return "XNAH has no fresh price of it, so it asks its usual price."
	end
	return reason
end

-- [[ background work for the Sell page ]] your auctions (the cancel scan) and the live prices of your bag items
local lastCancelCheck, checking = nil, {}
X.On("AUCTION_HOUSE_CLOSED", function() lastCancelCheck = nil checking = {} end)
-- XNAH searches by itself only while you look at the To do or the Sell page of the simple window (its searches could
-- get in the way of your own browsing at the auction house otherwise)
local function looking()
	local f = S.Frame and S.Frame()
	local view = X.S().simpleView
	return f and f:IsShown() and (view == "todo" or view == "sell") or false
end
local function cancelCheck()
	if not X.ahOpen or X.scan.state ~= "idle" or not looking() then return end
	if X.cancel.state == "asking" or X.cancel.state == "checking" then return end
	if X.routine and X.routine.state == "on" then return end
	if lastCancelCheck and GetTime() - lastCancelCheck < CANCEL_EVERY then return end
	lastCancelCheck = GetTime()
	X.CancelScan()
end
local function searchBags(rows)
	if not X.ahOpen or X.scan.state ~= "idle" or not looking() then return end
	local n = 0
	for _, r in ipairs(rows) do
		if n >= SEARCHES_AT_ONCE then break end
		local key = r.key
		if not X.LiveLowest(key, 600) and (not checking[key] or GetTime() - checking[key] > SEARCH_AGAIN) then
			checking[key] = GetTime()
			n = n + 1
			X.LiveSearch(key, function()
				checking[key] = GetTime() - 10 -- answered (or given up): the button may post now
				S.RefreshSoon()
			end)
		end
	end
end
local function waitingForPrice(key)
	return X.ahOpen and checking[key] and not X.LiveLowest(key, 600) and GetTime() - checking[key] < 8
end

local function cancelEntry(r)
	local id = "cancel:" .. tostring(r.auctionID)
	local by = (r.unit and r.lowest) and (r.unit - r.lowest) or nil
	local e = {id = id, key = r.key, title = fit("Cancel " .. nameOf(r.key) .. " x" .. X.Num(r.qty or 1), 30),
		sub = by and (RED .. "someone asks " .. plain(by) .. " less|r") or (RED .. "undercut|r"), price = r.unit,
		profit = r.lowest and math.floor(X.AfterCut(r.lowest * (r.qty or 1)) - (r.cost or 0)) or 0,
		sentence = "Cancel it. When it is back in your bags (it comes by mail), post it again here.",
		why = "You ask " .. plain(r.unit) .. " each, but someone else asks " .. plain(r.lowest) .. ": buyers take theirs first " ..
			"(that is called undercut), so yours will not sell.",
		lines = {{"Your price", money(r.unit)}, {"Cheapest now", money(r.lowest)}, {"Cancelling costs", r.cost and money(r.cost) or "-"},
			{"Time left", X.TimeLeftText(r.timeLeftSeconds, r.timeLeft)}}}
	if not X.ahOpen then e.button = {label = "Open the auction house first", disabled = true}
	elseif r.cancelling then e.button = {label = "Cancelling ...", disabled = true}
	elseif r.cost and r.cost > gold() then e.button = {label = "Not enough gold to cancel", disabled = true}
	else
		local auctionID = r.auctionID
		e.button = {label = "Cancel this auction", tip = "One click cancels this one auction. The deposit is not paid back.", run = function()
			for _, row in ipairs(X.cancel.rows) do
				if row.auctionID == auctionID then X.CancelClick(row) return end
			end
		end}
	end
	return e
end

-- one bag item: a Post entry, a Vendor entry, or nil (not worth anything / no price)
local function bagEntry(r)
	local key = r.key
	local price, reason, info = X.PostPrice(key)
	local qty = r.commodity and r.have or 1
	local vs = X.VendorSell(r.id)
	local vendorAll = vs and vs * r.have or 0
	local deposit = price and X.PostDeposit(r, X.PostRule(key).duration, qty) or nil
	local net = price and (X.AfterCut(price * qty) - (deposit or 0)) or nil
	local netAll = net and (r.commodity and net or net * r.have) or nil
	if netAll and netAll >= MIN_POST and netAll > vendorAll then
		local many = qty > 1
		local e = {id = "post:" .. key, key = key, title = fit("Sell " .. X.Num(r.have) .. " " .. nameOf(key), 30),
			sub = "brings " .. S.Signed(netAll), price = price, profit = math.floor(netAll), skip = true}
		if r.commodity then
			e.sentence = many and ("Post all " .. X.Num(qty) .. " at " .. plain(price) .. " each.") or ("Post it at " .. plain(price) .. ".")
		else
			e.sentence = r.have > 1 and ("Post them at " .. plain(price) .. " each - one click per piece.") or ("Post it at " .. plain(price) .. ".")
		end
		e.why = postWhy(reason, info)
		e.lines = {{"Price each", money(price)}, {"Cheapest now", money(info and info.lowest)},
			{"Usually sells for", money(info and info.usual)}, {"Deposit", money(deposit)}}
		if waitingForPrice(key) then
			e.button = {label = "Checking the price ...", disabled = true}
		else
			e.button, e.button2 = postButtons(r, price, qty, deposit)
		end
		return e, "post"
	end
	if vendorAll > 0 and netAll and vendorAll >= netAll then
		return {id = "vendor:" .. key, key = key, title = fit("Vendor " .. X.Num(r.have) .. " " .. nameOf(key), 30),
			sub = "brings " .. S.Signed(vendorAll), price = vs, profit = vendorAll, skip = true,
			sentence = "Sell " .. (r.have > 1 and "them" or "it") .. " to any vendor: right-click " .. (r.have > 1 and "them" or "it") ..
				" while a vendor's window is open.",
			why = "A vendor pays " .. plain(vendorAll) .. "; on the auction house " .. (r.have > 1 and "they" or "it") ..
				" would bring about " .. plain(netAll) .. " after the cut and the deposit."}, "vendor"
	end
	return nil
end

-- poor (grey) things in your bags: one entry for all of them
local function junkEntry()
	local total, n, icon = 0, 0, nil
	for bag = 0, 5 do
		for slot = 1, X.Try(C_Container.GetContainerNumSlots, bag) or 0 do
			local info = X.Try(C_Container.GetContainerItemInfo, bag, slot)
			if info and info.itemID and info.quality == 0 and not info.hasNoValue then
				local vs = X.VendorSell(info.itemID)
				if vs then
					total = total + vs * (info.stackCount or 1)
					n = n + 1
					icon = icon or info.iconFileID
				end
			end
		end
	end
	if n == 0 then return nil end
	return {id = "junk", icon = icon, title = "Sell your junk", sub = "brings " .. S.Signed(total), name = "Junk (grey things)",
		price = total, profit = total, graph = false, skip = true,
		sentence = "Sell the " .. X.Num(n) .. " grey thing" .. (n > 1 and "s" or "") .. " in your bags to any vendor (right-click them while " ..
			"a vendor's window is open).",
		why = "Grey things cannot go on the auction house; a vendor pays " .. plain(total) .. " for them."}
end

function S.SellEntries(limit)
	cancelCheck()
	local out = {}
	if X.cancel.state == "done" then
		for _, r in ipairs(X.cancel.rows) do out[#out + 1] = cancelEntry(r) end
	end
	local rows = X.SellItems()
	searchBags(rows)
	local posts, vendors = {}, {}
	for _, r in ipairs(rows) do
		local e, kind = bagEntry(r)
		if kind == "post" then posts[#posts + 1] = e elseif kind == "vendor" then vendors[#vendors + 1] = e end
	end
	local function byProfit(a, b)
		if a.profit ~= b.profit then return a.profit > b.profit end
		return a.id < b.id
	end
	table.sort(posts, byProfit)
	table.sort(vendors, byProfit)
	for _, e in ipairs(posts) do out[#out + 1] = e end
	for _, e in ipairs(vendors) do out[#out + 1] = e end
	local junk = junkEntry()
	if junk then out[#out + 1] = junk end
	if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
	return out
end

-- "Check your auctions": the cancel scan on a click (not restricted; it only asks and searches)
local function checkEntry()
	local c = X.cancel
	local busy = c.state == "asking" or c.state == "checking"
	local e = {id = "check", title = "Check your auctions", graph = false, name = "Check your auctions",
		icon = "Interface\\Icons\\INV_Misc_Spyglass_02", profit = 0,
		sub = GREY .. (busy and "checking ..." or (lastCancelCheck and ("last checked " .. X.Clock(GetTime() - lastCancelCheck) .. " ago") or
			"not checked yet")) .. "|r",
		sentence = "Check your auctions for cheaper sellers.",
		why = "XNAH asks the auction house for your auctions and searches each item (one a second). Auctions someone sells " ..
			"cheaper show up here with a Cancel button. Checking buys and cancels nothing."}
	if not X.ahOpen then e.button = {label = "Open the auction house first", disabled = true}
	elseif busy then e.button = {label = "Checking ...", disabled = true}
	elseif X.scan.state ~= "idle" then e.button = {label = "Wait until the scan is done", disabled = true}
	else
		e.button = {label = "Check your auctions", run = function()
			lastCancelCheck = GetTime()
			X.CancelScan()
		end}
	end
	return e
end
S.CheckAuctionsEntry = checkEntry

-- [[ the pages ]]
S.AddView("buy", {title = "Buy", order = 2, list = function()
	local out = S.BuyEntries(40)
	if #out > 0 then return out end
	if X.Realm().lastFull == nil then return out, "Nothing to buy yet: XNAH needs prices. Do a full scan at the auction house." end
	return out, "Nothing worth buying right now. XNAH looks again when prices change."
end})
S.AddView("sell", {title = "Sell", order = 3, list = function()
	local out = S.SellEntries(40)
	-- while it checks: first (so you see it is busy); else last
	if X.cancel.state == "asking" or X.cancel.state == "checking" then table.insert(out, 1, checkEntry())
	else out[#out + 1] = checkEntry() end
	return out, X.ahOpen and "Nothing to sell: nothing in your bags is worth posting, and none of your auctions is undercut." or
		"Nothing to sell in your bags. Open the auction house to check your auctions too."
end})

-- [[ Find ]] a Post button for something in your bags, else a Buy button for something on the auction house
table.insert(S.itemActions, function(key, e)
	for _, r in ipairs(X.SellItems()) do
		if r.key == key then
			local price = X.PostPrice(key)
			if price then
				local qty = r.commodity and r.have or 1
				local b1, b2 = postButtons(r, price, qty, X.PostDeposit(r, X.PostRule(key).duration, qty))
				e.button = b1
				if b2 then e.button2 = b2 end
				return
			end
		end
	end
	if not priceNow(key) and not X.live[key] then return end
	local need = stackable(key) and math.min(20, X.Try(C_Item.GetItemMaxStackSizeByID, X.KeyID(key)) or 20) or 1
	local usual = X.Usual(key)
	e.button = buyButton(key, "simple", "find:" .. key, need, usual and math.floor(usual * 1.1) or nil)
end)
