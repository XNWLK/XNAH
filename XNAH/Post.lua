-- Posting helper: a price for each item in your bags (undercut the cheapest seller that is not you, but never under a
-- floor and never over a ceiling), the deposit, what a sale brings; posting itself needs one click per post on our
-- own button (the game allows posting only then). And the cancel scan: your auctions that someone undercut.
--
-- Price rules (settings, or per item in XNAHDB.postRules[key], only the fields changed):
--   undercut  copper under the cheapest other seller (0 = the smallest step: 1c, or 1s when the auction house works
--             in whole silver)
--   floor     % of the usual price; the floor is the higher of this and the crafting cost (when known)
--   ceiling   % of the usual price
--   normal    the price to post at when nobody else sells it, or when the cheapest is under the floor ("don't chase
--             the price down"); default = the usual price (30-day average, else the market value)
--   duration  1 / 2 / 3 = 2 / 8 / 24 hours
local ADDON, X = ...

X.Default("postFloor", 80)
X.Default("postCeiling", 200)
X.Default("postUndercut", 0)
X.Default("postDuration", 3)
X.DURATIONS = {"2 hours", "8 hours", "24 hours"}
X.DURATION_SHORT = {"2h", "8h", "24h"}

local function rules()
	X.db.postRules = X.db.postRules or {}
	return X.db.postRules
end
-- the rule of one item: its own fields over the settings
function X.PostRule(key)
	local S = X.S()
	local own = key and rules()[key] or {}
	return {floor = own.floor or S.postFloor, ceiling = own.ceiling or S.postCeiling, undercut = own.undercut or S.postUndercut,
		duration = own.duration or S.postDuration, normal = own.normal, own = own}
end
-- one field of an item's rule; nil = back to the setting
function X.SetPostRule(key, field, value)
	local all = rules()
	local r = all[key] or {}
	r[field] = value
	if next(r) == nil then all[key] = nil else all[key] = r end
	X.Fire("XNAH_POST")
end
function X.ResetPostRule(key)
	rules()[key] = nil
	X.Fire("XNAH_POST")
end

-- [[ worth posting, and the ticks ]] Everything in your bags that is worth posting is ticked: the Post next button and
-- the one-key routine (Routine.lua) post the ticked items. Untick an item to keep it (remembered per item):
-- XNAHDB.sellTick[key] = false (keep it) or true (post it although XNAH thinks it is not worth it); no entry = ticked
-- when worth posting. (The sell list of earlier versions, XNAHDB.sellList, is not used any more.)
X.SELL_MIN = 100 -- 1s: a post that brings less (after the cut and the deposit) is not worth it
local function ticks()
	X.db.sellTick = X.db.sellTick or {}
	return X.db.sellTick
end
-- is a bag row (X.SellItems) worth posting? -> worth, info {price, reason, info, qty, deposit, net (what all of it
-- brings after the cut and the deposits), vendor (what a vendor pays for all of it), why (when not worth it)}
function X.SellWorth(row)
	local key = row.key
	local price, reason, pinfo = X.PostPrice(key)
	local qty = row.commodity and row.have or 1
	local vs = X.VendorSell and X.VendorSell(row.id) or nil
	local vendor = vs and vs * row.have or 0
	local out = {price = price, reason = reason, info = pinfo, qty = qty, vendor = vendor}
	if not price then out.why = "no price known yet" return false, out end
	local deposit = X.PostDeposit(row, X.PostRule(key).duration, qty)
	out.deposit = deposit
	local net = X.AfterCut(price * qty) - (deposit or 0)
	out.net = row.commodity and net or net * row.have
	if vendor > 0 and vendor >= out.net then out.why = "a vendor pays more" return false, out end
	if out.net < X.SELL_MIN then out.why = "brings under " .. X.MoneyPlain(X.SELL_MIN) return false, out end
	return true, out
end
-- is it ticked? row = its bag row (needed when there is no choice of yours: then it is ticked when worth posting)
function X.SellTicked(key, row)
	local v = key and ticks()[key]
	if v ~= nil then return v end
	if not row then return false end
	-- everything of it is still needed by your crafting queue: kept (unless you ticked it yourself)
	if X.QueueKeep and (X.Try(X.QueueKeep, key) or 0) >= (row.have or 0) then return false end
	return (X.SellWorth(row))
end
-- your choice: false = keep it, true = post it; nil = back to "ticked when worth posting"
function X.SellChoice(key)
	return key and ticks()[key]
end
function X.SetSellTick(key, on, row)
	if not key then return end
	local worth = row and X.SellWorth(row) or false
	if on then ticks()[key] = (not worth) and true or nil else ticks()[key] = false end
	X.Fire("XNAH_SELLTICK", key)
	X.Fire("XNAH_POST")
end

-- prices in whole silver when the auction house has no copper
function X.CopperOK()
	local ok = X.Try(C_AuctionHouse.SupportsCopperValues)
	return ok ~= false
end
local function roundPrice(p)
	p = math.floor(p + 0.5)
	if not X.CopperOK() then p = math.floor(p / 100) * 100 end
	return math.max(X.CopperOK() and 1 or 100, p)
end
-- the usual price: 30-day average (else 7 / 3 days), else the market value
function X.PostUsual(key)
	return X.Usual(key) or X.Price(key, "mkt")
end

-- X.PostPrice(key) -> copper (price of one), reason text, info {lowest, from, usual, floor, ceiling, normal}
-- the cheapest price that is NOT yours comes from a search of the last 30 minutes; without one, the lowest price of
-- the last scan (which may be your own auction)
function X.PostPrice(key)
	if not key then return nil end
	local rule = X.PostRule(key)
	local usual = X.PostUsual(key)
	local craft = X.CraftCost and X.CraftCost(X.KeyID(key), true) or nil -- recipes read in the game only (ones you can craft)
	local info = {usual = usual, craft = craft}
	local floor, floorWhy
	if usual then floor, floorWhy = usual * rule.floor / 100, rule.floor .. "% of usual" end
	if craft and (not floor or craft > floor) then floor, floorWhy = craft, "crafting cost" end
	local ceiling = usual and usual * rule.ceiling / 100 or nil
	local normal = rule.normal or usual
	info.floor, info.ceiling, info.normal = floor, ceiling, normal
	local lowest, live = X.LiveLowest(key, 1800)
	local from = "search"
	if not live or X.Now() - live.t > 1800 then
		lowest, from = X.Price(key, "min"), "scan"
		local it = X.Items()[key]
		if it and it.cur and (it.cur.qty or 0) == 0 then lowest = nil end
		if it and not X.Fresh(it) then lowest = nil end
	end
	info.lowest, info.from = lowest, from
	local step = (rule.undercut and rule.undercut > 0) and rule.undercut or (X.CopperOK() and 1 or 100)
	if not lowest then
		if not normal and not floor then return nil, "no price known yet (scan or search it)", info end
		local p = math.max(normal or 0, floor or 0)
		return roundPrice(p), (live and "nobody else is selling it: " or "no fresh lowest price: ") ..
			(rule.normal and "your normal price" or (normal and "usual price" or floorWhy)), info
	end
	local cand = lowest - step
	if floor and cand < floor then
		local p = math.max(normal or floor, floor)
		return roundPrice(p), "lowest " .. X.MoneyPlain(lowest) .. " is under your floor (" .. floorWhy .. "): " ..
			(p == floor and "floor" or (rule.normal and "your normal price" or "usual price")), info
	end
	if ceiling and cand > ceiling then
		return roundPrice(ceiling), "lowest " .. X.MoneyPlain(lowest) .. " is over your ceiling: ceiling (" .. rule.ceiling .. "% of usual)", info
	end
	return roundPrice(cand), "undercut " .. X.MoneyPlain(lowest) .. " by " .. X.MoneyPlain(step) ..
		(from == "scan" and " (last scan - may be yours)" or ""), info
end

-- [[ the bags ]] rows by item key: {key, id, have, locs = {{bag, slot, count}}, commodity}
local BAGS = {0, 1, 2, 3, 4, 5}
local function newLoc(bag, slot)
	local loc = CreateFromMixins(ItemLocationMixin)
	loc:SetBagAndSlot(bag, slot)
	return loc
end
X.ItemLoc = newLoc
function X.SellItems()
	local byKey, out = {}, {}
	for _, bag in ipairs(BAGS) do
		local n = X.Try(C_Container.GetContainerNumSlots, bag) or 0
		for slot = 1, n do
			local info = X.Try(C_Container.GetContainerItemInfo, bag, slot)
			if info and info.itemID and not info.isBound then
				local loc = newLoc(bag, slot)
				-- the game says whether it can be sold (only known while the auction house is open)
				local valid = true
				if X.ahOpen then valid = X.Try(C_AuctionHouse.IsSellItemValid, loc, false) == true end
				if valid then
					local key = X.KeyFromLink(info.hyperlink) or tostring(info.itemID)
					local row = byKey[key]
					if not row then
						local status = X.ahOpen and X.Try(C_AuctionHouse.GetItemCommodityStatus, loc) or nil
						local commodity
						if status == 2 then commodity = true elseif status == 1 then commodity = false
						else commodity = (X.Try(C_Item.GetItemMaxStackSizeByID, info.itemID) or 1) > 1 end
						row = {key = key, id = info.itemID, have = 0, locs = {}, commodity = commodity}
						byKey[key] = row
						out[#out + 1] = row
					end
					row.have = row.have + (info.stackCount or 1)
					row.locs[#row.locs + 1] = {bag, slot, info.stackCount or 1}
				end
			end
		end
	end
	return out
end
-- the deposit of a post (the server's number; rounded up to silver when there is no copper)
function X.PostDeposit(row, duration, qty)
	if not row or not X.ahOpen then return nil end
	local d
	if row.commodity then
		d = X.Try(C_AuctionHouse.CalculateCommodityDeposit, row.id, duration, qty)
	else
		local l = row.locs[1]
		d = l and X.Try(C_AuctionHouse.CalculateItemDeposit, newLoc(l[1], l[2]), duration, qty)
	end
	if d and not X.CopperOK() then d = math.ceil(d / 100) * 100 end
	return d
end

-- [[ posting ]] X.post = {state = idle / sent / warning, pending = {...}, text}
X.post = {state = "idle"}
local function postState(state, text)
	X.post.state = state
	X.post.text = text
	X.Fire("XNAH_POST")
end
-- why posting is not possible right now (nil = it is)
function X.PostBlocked(row, unit, qty)
	if not X.ahOpen then return "Open the auction house to post." end
	if X.scan.state ~= "idle" then return "Wait until the scan is done." end
	if not row then return "Pick an item on the left." end
	if not unit or unit <= 0 then return "Type a price." end
	if not qty or qty < 1 or qty > row.have then return "Quantity must be 1 to " .. row.have .. "." end
	if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then return "The auction house is busy - a moment." end
	return nil
end

-- ONE post. Call it only straight from the OnClick of our own button.
function X.PostClick(row, unit, qty, duration)
	if X.PostBlocked(row, unit, qty) then return false end
	local l = row.locs[1]
	local loc = newLoc(l[1], l[2])
	if not X.Try(C_AuctionHouse.IsSellItemValid, loc, false) then postState("idle", "That item is not in your bags any more.") return false end
	unit = roundPrice(unit)
	local args
	local needsConfirm
	if row.commodity then
		args = {loc, duration, qty, unit}
		needsConfirm = C_AuctionHouse.PostCommodity(loc, duration, qty, unit)
	else
		args = {loc, duration, qty, nil, unit}
		needsConfirm = C_AuctionHouse.PostItem(loc, duration, qty, nil, unit)
	end
	local token = {}
	X.post = {state = "sent", key = row.key, commodity = row.commodity, qty = qty, unit = unit, duration = duration, token = token}
	-- no answer at all within 15 s: the button is freed again
	X.After(15, function()
		if X.post.token == token and X.post.state == "sent" then postState("idle", "No answer from the auction house - check your auctions.") end
	end)
	if needsConfirm then
		-- the game wants a second "yes" (AUCTION_HOUSE_POST_WARNING tells why)
		X.post.pending = args
		postState("sent", "Waiting for the auction house ...")
	else
		postState("sent", "Posting " .. X.Num(qty) .. " at " .. X.MoneyPlain(unit) .. " each ...")
	end
	return true
end
-- the second click after a warning
function X.PostConfirmClick()
	local p = X.post
	if p.state ~= "warning" or not p.pending then return false end
	local a = p.pending
	if p.commodity then C_AuctionHouse.ConfirmPostCommodity(a[1], a[2], a[3], a[4])
	else C_AuctionHouse.ConfirmPostItem(a[1], a[2], a[3], a[4], a[5]) end
	p.pending = nil
	postState("sent", "Posting " .. X.Num(p.qty) .. " at " .. X.MoneyPlain(p.unit) .. " each ...")
	return true
end
function X.PostCancelWarning()
	X.post.pending = nil
	postState("idle", "Not posted.")
end
-- gives up waiting for an answer (the one-key routine, after no answer for a long time)
function X.PostForget(text)
	X.post = {state = "idle"}
	postState("idle", text)
end
X.On("AUCTION_HOUSE_POST_WARNING", function()
	if X.post.state == "sent" and X.post.pending then
		postState("warning", "The auction house warns about this price (far from what it usually sells for). Click Confirm to post anyway.")
	end
end)
X.On("AUCTION_HOUSE_POST_ERROR", function()
	if X.post.state == "sent" or X.post.state == "warning" then
		X.post.pending = nil
		postState("idle", "The auction house did not accept that post.")
	end
end)
X.On("AUCTION_HOUSE_AUCTION_CREATED", function(auctionID)
	local p = X.post
	if p.state ~= "sent" or p.pending then return end
	X.Print("posted " .. X.Num(p.qty) .. " " .. X.ItemText(p.key) .. " at " .. X.Money(p.unit) .. " each (" .. X.DURATIONS[p.duration or 3] .. ")")
	X.Fire("XNAH_POSTED", p.key, p.qty, p.unit, auctionID)
	postState("idle", "Posted " .. X.Num(p.qty) .. " at " .. X.MoneyPlain(p.unit) .. " each.")
	-- your own auction is in the list now: look at the item again
	if X.live[p.key] then X.LiveSearch(p.key) end
end)
X.On("AUCTION_HOUSE_CLOSED", function()
	X.post = {state = "idle"}
	if X.cancel.state == "asking" or X.cancel.state == "checking" then X.cancel.state = "idle" end
end)

-- [[ cancel scan ]] your active auctions, each compared with the cheapest price that is not yours
-- X.cancel = {state = idle / asking / checking / done, rows = {{key, auctionID, unit, qty, lowest, timeLeft, timeLeftSeconds,
-- cost, undercut}}, all = every active auction}
X.cancel = {state = "idle", rows = {}, all = {}}
local function cancelState(state, text)
	X.cancel.state = state
	X.cancel.text = text
	X.Fire("XNAH_CANCEL")
end
function X.CancelScan()
	if not X.ahOpen then return false end
	X.cancel = {state = "asking", rows = {}, all = {}, token = {}}
	cancelState("asking", "Asking for your auctions ...")
	C_AuctionHouse.QueryOwnedAuctions({})
	local token = X.cancel.token
	X.After(10, function()
		if X.cancel.token == token and X.cancel.state == "asking" then cancelState("idle", "No answer from the auction house.") end
	end)
	return true
end
local function judge()
	local c = X.cancel
	local rows = {}
	for _, a in ipairs(c.all) do
		local lowest = X.LiveLowest(a.key, 600)
		a.lowest = lowest
		a.undercut = lowest ~= nil and a.unit ~= nil and lowest < a.unit
		if a.undercut then rows[#rows + 1] = a end
	end
	c.rows = rows
	c.at = GetTime()
	cancelState("done", #rows == 0 and ("None of your " .. #c.all .. " auctions is undercut.") or
		(#rows .. " of your " .. #c.all .. " auctions are undercut."))
end
X.On("OWNED_AUCTIONS_UPDATED", function()
	local c = X.cancel
	if c.state ~= "asking" then return end
	local list = X.Try(C_AuctionHouse.GetOwnedAuctions) or {}
	local keys, need = {}, {}
	for _, o in ipairs(list) do
		if o.status == 0 and o.itemKey then
			local key = X.KeyFromLink(o.itemLink) or X.KeyOfItemKey(o.itemKey)
			local qty = o.quantity or 1
			local commodity = X.live[key] and X.live[key].commodity
			if commodity == nil then commodity = (X.Try(C_Item.GetItemMaxStackSizeByID, o.itemKey.itemID) or 1) > 1 end
			-- GUESS (retail): an owned commodity auction's buyout is the price of ONE; other items: of the whole auction
			local unit = o.buyoutAmount and (commodity and o.buyoutAmount or o.buyoutAmount / math.max(1, qty)) or nil
			c.all[#c.all + 1] = {key = key, auctionID = o.auctionID, unit = unit, qty = qty, timeLeft = o.timeLeft,
				timeLeftSeconds = o.timeLeftSeconds, cost = X.Try(C_AuctionHouse.GetCancelCost, o.auctionID)}
			if not keys[key] then
				keys[key] = true
				if not X.LiveLowest(key, 600) then need[#need + 1] = key end
			end
		end
	end
	if #need == 0 then judge() return end
	c.left = #need
	cancelState("checking", "Searching " .. #need .. " items ...")
	local token = c.token
	for _, key in ipairs(need) do
		X.LiveSearch(key, function()
			if X.cancel.token ~= token then return end
			c.left = c.left - 1
			if c.left <= 0 then judge() else cancelState("checking", "Searching " .. c.left .. " items ...") end
		end)
	end
end)
-- [[ the check by itself ]] when the auction house opens, XNAH checks your auctions (asking and searching only, never
-- cancelling): at most every 5 minutes, and never while a full scan runs (then right after it)
X.CANCEL_EVERY = 300
local autoPending, lastAuto = false, nil
function X.CancelAuto()
	if not autoPending or not X.ahOpen or X.scan.state ~= "idle" then return false end
	autoPending = false
	local c = X.cancel
	if c.state == "asking" or c.state == "checking" then return false end
	if c.at and GetTime() - c.at < X.CANCEL_EVERY then return false end
	if lastAuto and GetTime() - lastAuto < X.CANCEL_EVERY then return false end
	lastAuto = GetTime()
	return X.CancelScan()
end
X.On("XNAH_AH", function(open)
	autoPending = open and true or false
	if open then X.After(2, X.CancelAuto) end
end)
X.On("XNAH_SCAN", function()
	if autoPending and X.scan.state == "idle" then X.After(1, X.CancelAuto) end
end)

-- ONE cancel. Call it only straight from the OnClick of our own button.
function X.CancelClick(row)
	if not row or not X.ahOpen or row.cancelling then return false end
	row.cancelling = true
	C_AuctionHouse.CancelAuction(row.auctionID)
	X.Fire("XNAH_CANCEL")
	return true
end
X.On("AUCTION_CANCELED", function(auctionID)
	local c = X.cancel
	for i, r in ipairs(c.rows) do
		if r.auctionID == auctionID then
			table.remove(c.rows, i)
			X.Print("cancelled your auction of " .. X.Num(r.qty) .. " " .. X.ItemText(r.key))
			break
		end
	end
	for i, r in ipairs(c.all) do if r.auctionID == auctionID then table.remove(c.all, i) break end end
	X.Fire("XNAH_CANCEL")
end)

-- time left of an auction as text
local BANDS = {[0] = "< 30 min", "30 min - 2 h", "2 - 12 h", "> 12 h"}
function X.TimeLeftText(seconds, band)
	if seconds then
		if seconds >= 3600 then return math.floor(seconds / 3600) .. "h " .. math.floor((seconds % 3600) / 60) .. "m" end
		return math.floor(seconds / 60) .. "m"
	end
	return band and BANDS[band] or "-"
end
