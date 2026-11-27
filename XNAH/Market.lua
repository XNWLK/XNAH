-- Looking for money: the usual price, movers (prices and supply that changed), and the numbers for one item that tell
-- whether it is worth trading.
local ADDON, X = ...

-- the usual price of an item, for comparing a listing against: 30-day average, else 7-day, else 3-day
function X.Usual(key)
	local it = X.Items()[key]
	if not it then return nil end
	local st = X.Stats(it)
	return st.avg30 or st.avg7 or st.avg3, st
end

-- [[ movers ]] kind = "up" (price rising), "down" (falling), "short" (supply far under its 7-day average while the
-- price holds or rises: a chance to sell), "flood" (supply far over: wait before selling)
-- X.MoveKinds(trend, supply, qty7) -> "up" / "down" / nil (the price), "short" / "flood" / nil (the number listed): the
-- rules in one place (the Market view's Rising / Falling / Short supply / Flooded buttons use them too). The caller checks
-- first that the price is fresh and the item has enough days of history.
function X.MoveKinds(trend, supply, qty7)
	local p, s
	if trend then
		if trend > 0 then p = "up" elseif trend < 0 then p = "down" end
	end
	if supply and (qty7 or 0) >= 5 then
		if supply <= -40 and (trend or 0) >= -5 then s = "short" elseif supply >= 60 then s = "flood" end
	end
	return p, s
end

function X.Movers(kind, limit)
	local S = X.S()
	local out = {}
	for key, it in pairs(X.Items()) do
		if it.cur and X.Fresh(it) then
			local st = X.Stats(it)
			if st.days >= S.minSamples then
				local v
				local p, s = X.MoveKinds(st.trend, st.supply, st.qty7)
				if kind == "up" and p == "up" then v = st.trend
				elseif kind == "down" and p == "down" then v = -st.trend
				elseif kind == "short" and s == "short" then v = -st.supply
				elseif kind == "flood" and s == "flood" then v = st.supply end
				if v then
					out[#out + 1] = {key = key, v = v, trend = st.trend, supply = st.supply, price = X.Price(key), avg7 = st.avg7,
						qty = it.cur.qty, qty7 = st.qty7}
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.v > b.v end)
	if limit then for i = #out, limit + 1, -1 do out[i] = nil end end
	return out
end

-- [[ one item, all the numbers ]] for the item page and the tooltip
function X.Summary(key)
	local it = X.Items()[key]
	local id = X.KeyID(key)
	local s = {key = key, id = id, it = it}
	s.vsell = X.VendorSell(id)
	s.vbuy, s.vbuyInfo = X.VendorBuy(id)
	s.craft, s.craftRid = X.CraftCost(id)
	if it then
		s.cur = it.cur
		s.st = X.Stats(it)
		s.usual = s.st.avg30 or s.st.avg7 or s.st.avg3
		s.fresh = X.Fresh(it)
	end
	local price = X.Price(key)
	s.price = price
	s.sell = X.AfterCut(price)
	-- buying the cheapest listing and selling it again at the market value
	if s.cur and s.cur.min and price then s.flip = s.sell - s.cur.min end
	if s.craft and s.sell then s.craftProfit = s.sell - s.craft end
	if s.vbuy and s.sell then s.vendorFlip = s.sell - s.vbuy end
	if s.vsell and s.cur and s.cur.min then s.belowVendor = s.vsell - s.cur.min end
	return s
end
