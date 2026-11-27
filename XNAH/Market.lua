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
function X.Movers(kind, limit)
	local S = X.S()
	local out = {}
	for key, it in pairs(X.Items()) do
		if it.cur and X.Fresh(it) then
			local st = X.Stats(it)
			if st.days >= S.minSamples then
				local v
				if kind == "up" and st.trend and st.trend > 0 then v = st.trend
				elseif kind == "down" and st.trend and st.trend < 0 then v = -st.trend
				elseif kind == "short" and st.supply and st.supply <= -40 and (st.trend or 0) >= -5 and (st.qty7 or 0) >= 5 then v = -st.supply
				elseif kind == "flood" and st.supply and st.supply >= 60 and (st.qty7 or 0) >= 5 then v = st.supply end
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
