-- Stand-in world, part "auction": posting, your own auctions, cancelling, buying, item locations, sounds - and the
-- rule that posting / buying / cancelling happen only inside a click (W.hardware is true only while a button is
-- clicked; the restricted calls throw an error outside one, so a scene fails if XNAH ever calls them from a timer or
-- an event). Test tool only - never part of the addon.

W.me = nil -- the player's "First Last" (set at reset)

-- every click of a button is a hardware event
local click = W.Frame.Click
function W.Frame:Click(...)
	local was = W.hardware
	W.hardware = true
	local ok, e = pcall(click, self, ...)
	W.hardware = was
	if not ok then error(e, 0) end
end

local function restricted(name)
	W.restrictedCalls[#W.restrictedCalls + 1] = name
	if not W.hardware then error(name .. " was called outside a click (the game needs a hardware event)", 2) end
end

table.insert(W.onReset, function()
	W.me = W.player .. " " .. W.surname
	W.hardware = false
	W.restrictedCalls = {}  -- names of restricted calls, in order
	W.nextAuctionID = 1000
	W.owned = {}            -- your auctions (the same tables as in W.ah while active), status 0 active / 1 sold
	W.won = {}              -- bought: {{id, count, suffix, price}} (they go to the mailbox; W.buyToBags puts them in the bags)
	W.returned = {}         -- cancelled: {{id, count}} (by mail)
	W.quote = nil           -- a started commodity purchase
	W.warnNextPost = false  -- true: the next post gets AUCTION_HOUSE_POST_WARNING (needs a confirm)
	W.copperValues = true   -- C_AuctionHouse.SupportsCopperValues()
	W.cancelCost = 0
	W.sounds, W.flashes = {}, 0
	W.money = 1234567
	W.buyToBags = false
	W.moneyLate = false     -- true: PlaceBid's gold goes only after its purchase event (as seen in the game)
	W.bids = {}            -- every PlaceBid: {auctionID, amount}
end)

-- an auction's id (made the first time it is needed)
local function idOf(a)
	if not a.id then
		W.nextAuctionID = W.nextAuctionID + 1
		a.id = W.nextAuctionID
	end
	return a.id
end
W.auctionID = idOf
local function findAuction(id)
	for i, a in ipairs(W.ah) do if a.id == id then return a, i end end
end
local function removeAuction(a)
	for i, x in ipairs(W.ah) do if x == a then table.remove(W.ah, i) return end end
end
local function isCommodity(id) return W.isCommodity(id) end
local function unitOf(a) return a.buyout and a.buyout > 0 and a.buyout / math.max(1, a.count or 1) or nil end
-- the price of one of an auction as the game hands it over (whole copper)
local function oneOf(a) local u = unitOf(a) return u and math.floor(u + 0.5) or nil end
local function bagCount(id, suffix)
	local n = 0
	for _, bag in pairs(W.bags) do
		for _, s in pairs(bag) do if s.id == id and (suffix == nil or (s.suffix or 0) == (suffix or 0)) then n = n + s.count end end
	end
	return n
end
-- takes n of an item out of the bags (the given slot first)
local function takeFromBags(id, n, firstBag, firstSlot, suffix)
	local function take(bag, slot)
		local s = W.bags[bag] and W.bags[bag][slot]
		if not s or s.id ~= id or n <= 0 then return end
		if suffix ~= nil and (s.suffix or 0) ~= (suffix or 0) then return end
		local k = math.min(n, s.count)
		s.count = s.count - k
		n = n - k
		if s.count <= 0 then W.bags[bag][slot] = nil end
	end
	if firstBag then take(firstBag, firstSlot) end
	local bags = {}
	for b in pairs(W.bags) do bags[#bags + 1] = b end
	table.sort(bags)
	for _, b in ipairs(bags) do
		local slots = {}
		for s in pairs(W.bags[b]) do slots[#slots + 1] = s end
		table.sort(slots)
		for _, s in ipairs(slots) do take(b, s) end
	end
end
local function toBags(id, count, suffix)
	W.bags[0] = W.bags[0] or {}
	local slot = 1
	while W.bags[0][slot] do slot = slot + 1 end
	W.bags[0][slot] = {id = id, count = count, suffix = suffix}
end
-- puts a stack in the bags: W.putBag(bag, slot, id, count, suffix)
function W.putBag(bag, slot, id, count, suffix)
	W.bags[bag] = W.bags[bag] or {}
	W.bags[bag][slot] = {id = id, count = count or 1, suffix = suffix}
end

local DEPOSIT_PCT = {0.05, 0.20, 0.60}
local function deposit(id, duration, qty)
	local it = W.items[id]
	if not it or not DEPOSIT_PCT[duration] then return nil end
	return math.max(100, math.floor((it.sell or 0) * qty * DEPOSIT_PCT[duration]))
end
local function slotOf(loc)
	if type(loc) ~= "table" or not loc.bagID then return nil end
	return W.bags[loc.bagID] and W.bags[loc.bagID][loc.slotIndex]
end

-- an auction of yours that is already up: W.mine(itemID, unitPrice, count, suffix) -> the auction
function W.mine(id, unit, count, suffix)
	count = count or 1
	local a = {itemID = id, suffix = suffix, count = count, buyout = math.floor(unit * count + 0.5), bid = 0, owner = W.me,
		timeLeft = 3, seconds = 86400, status = 0, commodity = isCommodity(id), posted = W.NOW}
	idOf(a)
	W.ah[#W.ah + 1] = a
	W.owned[#W.owned + 1] = a
	return a
end

-- someone buys one of your auctions (it becomes "sold")
function W.sellMine(id)
	for _, a in ipairs(W.owned) do
		if a.id == id and a.status == 0 then a.status = 1 removeAuction(a) return true end
	end
	return false
end

local function makePost(loc, duration, qty, unit, commodity)
	local s = slotOf(loc)
	if not s or not W.ahOpen then W.fire("AUCTION_HOUSE_POST_ERROR") return false end
	if type(duration) ~= "number" or duration < 1 or duration > 3 or type(qty) ~= "number" or qty < 1 or not unit or unit <= 0 then
		W.after(0.2, function() W.fire("AUCTION_HOUSE_POST_ERROR") end)
		return false
	end
	local id, suffix = s.id, s.suffix
	if bagCount(id, suffix) < qty then W.after(0.2, function() W.fire("AUCTION_HOUSE_POST_ERROR") end) return false end
	local d = deposit(id, duration, qty) or 0
	if (W.money or 0) < d then W.after(0.2, function() W.fire("AUCTION_HOUSE_POST_ERROR") end) return false end
	W.money = W.money - d
	takeFromBags(id, qty, loc.bagID, loc.slotIndex, suffix)
	local made = {}
	local n, each = 1, qty
	if not commodity then n, each = qty, 1 end -- other items: one auction each
	for _ = 1, n do
		local a = {itemID = id, suffix = suffix, count = each, buyout = math.floor(unit * each + 0.5), bid = 0, owner = W.me,
			timeLeft = 3, seconds = ({7200, 28800, 86400})[duration], status = 0, commodity = commodity, posted = W.NOW}
		idOf(a)
		W.ah[#W.ah + 1] = a
		W.owned[#W.owned + 1] = a
		made[#made + 1] = a.id
	end
	W.after(0.3, function()
		for _, aid in ipairs(made) do W.fire("AUCTION_HOUSE_AUCTION_CREATED", aid) end
		W.fire("BAG_UPDATE_DELAYED")
	end)
	return true
end

table.insert(W.onEnv, function(env)
	local AH = env.C_AuctionHouse
	env.ItemLocationMixin = env.ItemLocationMixin or {
		SetBagAndSlot = function(self, bag, slot) self.bagID, self.slotIndex = bag, slot end,
		GetBagAndSlot = function(self) return self.bagID, self.slotIndex end,
		IsBagAndSlot = function(self) return self.bagID ~= nil end,
		IsValid = function(self) return slotOf(self) ~= nil end,
	}
	env.CreateFromMixins = env.CreateFromMixins or function(...)
		local o = {}
		for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end
		return o
	end
	env.SOUNDKIT = env.SOUNDKIT or {RAID_WARNING = 8959, AUCTION_WINDOW_OPEN = 5274}
	env.PlaySound = function(kit) W.sounds[#W.sounds + 1] = kit return true end
	env.FlashClientIcon = function() W.flashes = W.flashes + 1 end
	env.GetMoney = function() return W.money or 1234567 end

	AH.SupportsCopperValues = function() return W.copperValues end
	AH.IsSellItemValid = function(loc)
		local s = slotOf(loc)
		return W.ahOpen and s ~= nil and W.items[s.id] ~= nil and not W.items[s.id].bound or false
	end
	AH.GetItemCommodityStatus = function(loc)
		local s = slotOf(loc)
		if not s or not W.items[s.id] then return 0 end
		return isCommodity(s.id) and 2 or 1
	end
	AH.GetAvailablePostCount = function(loc) local s = slotOf(loc) return s and bagCount(s.id, s.suffix) or 0 end
	AH.CalculateCommodityDeposit = function(id, duration, qty) return deposit(id, duration, qty) end
	AH.CalculateItemDeposit = function(loc, duration, qty) local s = slotOf(loc) return s and deposit(s.id, duration, qty) end

	-- posting: true = needs a confirm (the warning event follows)
	AH.PostCommodity = function(loc, duration, qty, unit)
		restricted("PostCommodity")
		if W.warnNextPost then
			W.warnNextPost = false
			W.pendingPost = {loc, duration, qty, unit}
			W.after(0.2, function() W.fire("AUCTION_HOUSE_POST_WARNING") end)
			return true
		end
		makePost(loc, duration, qty, unit, true)
		return false
	end
	AH.ConfirmPostCommodity = function(loc, duration, qty, unit)
		restricted("ConfirmPostCommodity")
		W.pendingPost = nil
		makePost(loc, duration, qty, unit, true)
	end
	AH.PostItem = function(loc, duration, qty, bid, buyout)
		restricted("PostItem")
		if W.warnNextPost then
			W.warnNextPost = false
			W.pendingPost = {loc, duration, qty, bid, buyout}
			W.after(0.2, function() W.fire("AUCTION_HOUSE_POST_WARNING") end)
			return true
		end
		makePost(loc, duration, qty, buyout, false)
		return false
	end
	AH.ConfirmPostItem = function(loc, duration, qty, bid, buyout)
		restricted("ConfirmPostItem")
		W.pendingPost = nil
		makePost(loc, duration, qty, buyout, false)
	end

	-- your auctions
	local function ownedInfo()
		local out = {}
		for _, a in ipairs(W.owned) do
			local secs = a.seconds and math.max(0, a.seconds - (W.NOW - (a.posted or W.NOW))) or nil
			out[#out + 1] = {auctionID = a.id, itemKey = {itemID = a.itemID, itemLevel = 0, itemSuffix = a.suffix or 0, battlePetSpeciesID = 0},
				itemLink = W.link(a.itemID, a.suffix), status = a.status or 0, quantity = a.count,
				timeLeftSeconds = secs, timeLeft = a.timeLeft,
				-- your own auction gives the price of ONE, also for a stack of other items (a guess about the real client,
				-- the same as its item search rows)
				buyoutAmount = oneOf(a), bidAmount = a.bid}
		end
		return out
	end
	AH.QueryOwnedAuctions = function()
		if not W.ahOpen then return end
		W.after(0.3, function() W.fire("OWNED_AUCTIONS_UPDATED") end)
	end
	AH.GetOwnedAuctions = function() return ownedInfo() end
	AH.GetNumOwnedAuctions = function() return #W.owned end
	AH.GetOwnedAuctionInfo = function(i) return ownedInfo()[i] end
	AH.GetCancelCost = function() return W.cancelCost end
	AH.CanCancelAuction = function(id) for _, a in ipairs(W.owned) do if a.id == id and a.status == 0 then return true end end return false end
	AH.CancelAuction = function(id)
		restricted("CancelAuction")
		for i, a in ipairs(W.owned) do
			if a.id == id and a.status == 0 then
				table.remove(W.owned, i)
				removeAuction(a)
				W.money = W.money - (W.cancelCost or 0)
				W.returned[#W.returned + 1] = {id = a.itemID, count = a.count}
				W.after(0.3, function() W.fire("AUCTION_CANCELED", id) end)
				return
			end
		end
	end

	-- buying stackable items: start (the server answers with the price), confirm
	local function cheapest(id, qty)
		local list = {}
		for _, a in ipairs(W.ah) do if a.itemID == id and a.owner ~= W.me and unitOf(a) then list[#list + 1] = a end end
		table.sort(list, function(x, y) return unitOf(x) < unitOf(y) end)
		local take, total, left = {}, 0, qty
		for _, a in ipairs(list) do
			if left <= 0 then break end
			local k = math.min(left, a.count)
			take[#take + 1] = {a, k}
			total = total + math.floor(unitOf(a) + 0.5) * k
			left = left - k
		end
		return take, total, left
	end
	AH.StartCommoditiesPurchase = function(id, qty)
		restricted("StartCommoditiesPurchase")
		local _, total, left = cheapest(id, qty)
		if left > 0 or qty < 1 then W.after(0.2, function() W.fire("COMMODITY_PRICE_UNAVAILABLE") end) return end
		W.quote = {id = id, qty = qty, total = total}
		W.after(0.2, function() W.fire("COMMODITY_PRICE_UPDATED", math.floor(total / qty + 0.5), total) end)
	end
	AH.CancelCommoditiesPurchase = function() W.quote = nil end
	AH.ConfirmCommoditiesPurchase = function(id, qty)
		restricted("ConfirmCommoditiesPurchase")
		local q = W.quote
		W.quote = nil
		local take, total, left = cheapest(id, qty)
		if not q or q.id ~= id or q.qty ~= qty or left > 0 or (W.money or 0) < total then
			W.after(0.3, function() W.fire("COMMODITY_PURCHASE_FAILED") end)
			return
		end
		for _, t in ipairs(take) do
			local a, k = t[1], t[2]
			a.buyout = a.buyout - math.floor(unitOf(a) * k + 0.5)
			a.count = a.count - k
			if a.count <= 0 then removeAuction(a) end
		end
		W.money = W.money - total
		W.won[#W.won + 1] = {id = id, count = qty, price = total}
		if W.buyToBags then toBags(id, qty) end
		W.after(0.3, function()
			W.fire("COMMODITY_PURCHASED", id, qty)
			W.fire("COMMODITY_PURCHASE_SUCCEEDED")
		end)
	end
	-- buying other items: ONE item of the auction. The amount sent is the price of ONE (the search row's buyoutAmount,
	-- as the game's own Buyout button sends it); the server sells one item for that and leaves the rest listed
	-- (verified in the game 2026-11-23: an auction of 7 at 34s 13c, one press = one item for 34s 13c, 6 left).
	-- W.moneyLate = true: the gold goes only after the purchase event (as seen in the game: GetMoney often has not
	-- changed yet when AUCTION_HOUSE_PURCHASE_COMPLETED comes).
	AH.PlaceBid = function(auctionID, amount)
		restricted("PlaceBid")
		W.bids[#W.bids + 1] = {auctionID = auctionID, amount = amount}
		local a = findAuction(auctionID)
		local one = a and oneOf(a)
		if not a or a.owner == W.me or not one or type(amount) ~= "number" or amount < one or (W.money or 0) < one then
			W.after(0.3, function() W.fire("AUCTION_HOUSE_SHOW_ERROR", 1) end)
			return
		end
		a.count = (a.count or 1) - 1
		if a.count <= 0 then removeAuction(a) else a.buyout = one * a.count end
		if not W.moneyLate then W.money = W.money - one end
		W.won[#W.won + 1] = {id = a.itemID, count = 1, suffix = a.suffix, price = one}
		if W.buyToBags then toBags(a.itemID, 1, a.suffix) end
		W.after(0.3, function()
			W.fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID)
			W.fire("ITEM_PURCHASED", a.itemID)
			if W.moneyLate then W.after(0.2, function() W.money = W.money - one end) end
		end)
	end

	-- searches: like the plain world's, plus which offers are yours and real auction ids
	local function search(itemKey)
		if not W.ahOpen then return end
		if type(itemKey) ~= "table" or not itemKey.itemID then error("SendSearchQuery: bad itemKey") end
		W.throttleUntil = W.NOW + 0.1
		local id, suffix = itemKey.itemID, itemKey.itemSuffix or 0
		W.searches[#W.searches + 1] = {key = W.keyStr(id, suffix), t = W.NOW}
		if W.searchDrop[id] then return end
		W.after(0.3, function()
			if not W.ahOpen then return end
			if isCommodity(id) then
				local byPrice, prices = {}, {}
				for _, a in ipairs(W.ah) do
					if a.itemID == id then
						local u = unitOf(a)
						if u then
							u = math.floor(u + 0.5)
							local row = byPrice[u]
							if not row then
								row = {itemID = id, quantity = 0, unitPrice = u, auctionID = idOf(a), owners = {}, totalNumberOfOwners = 0,
									numOwnerItems = 0, containsOwnerItem = false, containsAccountItem = false, timeLeftSeconds = 7200}
								byPrice[u] = row
								prices[#prices + 1] = u
							end
							row.quantity = row.quantity + (a.count or 1)
							row.totalNumberOfOwners = row.totalNumberOfOwners + 1
							if a.owner == W.me then
								row.numOwnerItems = row.numOwnerItems + (a.count or 1)
								row.containsOwnerItem = true
								row.owners[#row.owners + 1] = "player"
							end
						end
					end
				end
				table.sort(prices)
				local list = {}
				for i, u in ipairs(prices) do list[i] = byPrice[u] end
				W.commodity[id] = list
				W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
			else
				local list = {}
				for _, a in ipairs(W.ah) do
					if a.itemID == id and (suffix == 0 or (a.suffix or 0) == suffix) and a.buyout and a.buyout > 0 then
						local mine = a.owner == W.me
						list[#list + 1] = {itemKey = {itemID = id, itemLevel = 0, itemSuffix = a.suffix or 0, battlePetSpeciesID = 0},
							owners = {mine and "player" or a.owner}, totalNumberOfOwners = 1, timeLeft = a.timeLeft or 2, auctionID = idOf(a),
							-- as in the game: the buyout of a row is the price of ONE, also when the auction is a stack
							quantity = a.count or 1, itemLink = W.link(id, a.suffix), buyoutAmount = oneOf(a), bidAmount = a.bid,
							containsOwnerItem = mine, containsAccountItem = false, containsSocketedItem = false}
					end
				end
				table.sort(list, function(x, y) return x.buyoutAmount < y.buyoutAmount end)
				W.itemResults[W.keyStr(id, suffix)] = list
				W.fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = id, itemLevel = 0, itemSuffix = suffix, battlePetSpeciesID = 0})
			end
		end)
	end
	AH.SendSearchQuery = search
	AH.SendSellSearchQuery = search
end)
