-- Vendors: what a merchant sells (and for how much) is recorded every time you open one, so XNAH knows which crafting
-- reagents to buy from a vendor and which vendor items sell for more on the auction house. What a vendor PAYS for an
-- item comes from the game (X.VendorSell in Data.lua).
local ADDON, X = ...

local function readMerchant()
	local n = X.Try(GetMerchantNumItems) or 0
	if n == 0 then return end
	local npc = X.Plain(UnitName("npc")) or "a vendor"
	local now, got = X.Now(), 0
	for i = 1, n do
		local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and X.Try(C_MerchantFrame.GetItemInfo, i)
		local id = X.Try(GetMerchantItemID, i)
		-- only plain gold prices (no tokens or other items as payment)
		if info and id and info.price and info.price > 0 and not info.hasExtendedCost then
			local per = info.price / math.max(1, info.stackCount or 1)
			local lim = (info.numAvailable or 0) > 0 or nil -- a number left = limited stock; unlimited is -1 or 0
			local old = X.db.vbuy[id]
			-- keep the cheapest unlimited offer
			if not old or per <= old.p or (old.lim and not lim) or old.from == npc then
				X.db.vbuy[id] = {p = per, lim = lim, at = now, from = npc}
				got = got + 1
			end
			if info.name then
				local key = tostring(id)
				local it = X.Items()[key]
				if it and not it.n then it.n = info.name end
			end
		end
	end
	if got > 0 then X.Debug("vendor prices: " .. got .. " items from " .. npc) X.Fire("XNAH_PRICES") end
end
X.On("MERCHANT_SHOW", function() X.After(0.3, readMerchant) end)
X.On("MERCHANT_UPDATE", function() X.Debounce("merchant", 0.5, readMerchant) end)

-- vendor flips: items a vendor sells that go for more on the auction house (after the cut)
-- returns {{key, buy, sell, profit, pct, lim}} sorted by profit
function X.VendorFlips()
	local out = {}
	for id, v in pairs(X.db.vbuy) do
		local key = tostring(id)
		local it = X.Items()[key]
		if it and X.Fresh(it) then
			local sell = X.AfterCut(X.Price(key))
			if sell and sell > v.p then
				out[#out + 1] = {key = key, buy = v.p, sell = sell, profit = sell - v.p, pct = (sell / v.p - 1) * 100, lim = v.lim,
					qty = it.cur.qty}
			end
		end
	end
	table.sort(out, function(a, b) return a.profit > b.profit end)
	return out
end

-- below vendor: auctions listed for less than a vendor pays - buy and sell to the vendor, no risk
function X.BelowVendor()
	local out = {}
	for key, it in pairs(X.Items()) do
		local cur = it.cur
		if cur and cur.min and X.Fresh(it) and (cur.qty or 0) > 0 then
			local vs = X.VendorSell(it.id)
			if vs and cur.min < vs then
				out[#out + 1] = {key = key, buy = cur.min, sell = vs, profit = vs - cur.min, pct = (vs / cur.min - 1) * 100, qty = cur.qty}
			end
		end
	end
	table.sort(out, function(a, b) return a.profit > b.profit end)
	return out
end
