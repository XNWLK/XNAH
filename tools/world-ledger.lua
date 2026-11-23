-- Stand-in world, ledger and inventory part (helper A): the mailbox with auction house mails, gold, the bank (bank
-- tabs 6-14, account bank 15-23, only readable while open), soulbound items, and your own auctions when no other
-- extension provides them.
--   W.mail = {{sender, subject, money, cod, daysLeft (nil = 30 minus the days since it arrived), arrived (server time),
--     invoice = {type, itemName, player, bid, buyout, deposit, consignment, count}, items = {{id, count, suffix} or {link, count}}}}
--   W.bags[bag][slot] = {id, count, suffix, bound = true}
--   W.owned = {{itemID, suffix, count, status (0 active, 1 sold), buyout}} (as in tools/world-auction.lua, which makes them when present)

local function serverNow() return W.START + math.floor(W.NOW - 1000) end
local MAX_SHOWN = 50

table.insert(W.onReset, function()
	W.mail = {}
	W.mailOpen = false
	W.bankOpen = false
	W.owned = {}
end)

local function mailAt(i)
	if not W.mailOpen then return nil end
	return W.mail[i]
end
local function attachment(m, a)
	local it = m and m.items and m.items[a]
	if not it then return nil end
	local link = it.link or W.link(it.id, it.suffix)
	local id = it.id or tonumber(tostring(link):match("item:(%d+)"))
	return it, link, id
end

table.insert(W.onEnv, function(env)
	env.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
	env.AUCTION_REMOVED_MAIL_SUBJECT = "Auction canceled: %s"
	env.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
	env.AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
	env.AUCTION_INVOICE_MAIL_SUBJECT = "Sale Pending: %s"

	-- [[ the mailbox ]]
	env.GetInboxNumItems = function()
		if not W.mailOpen then return 0, 0 end
		return math.min(#W.mail, MAX_SHOWN), #W.mail
	end
	env.GetInboxHeaderInfo = function(i)
		local m = mailAt(i)
		if not m then return nil end
		local days = m.daysLeft or (30 - (serverNow() - (m.arrived or serverNow())) / 86400)
		local n, first = 0, nil
		for a = 1, 16 do
			local it = attachment(m, a)
			if it then n = n + 1 first = first or a end
		end
		local _, firstLink = attachment(m, first or 0)
		local firstIt = first and m.items[first]
		return 133468, nil, m.sender or "Auction House", m.subject or "", m.money or 0, m.cod or 0, days, n, m.read or false,
			false, true, false, false, firstIt and firstIt.count or nil, firstLink
	end
	env.GetInboxInvoiceInfo = function(i)
		local m = mailAt(i)
		local v = m and m.invoice
		if not v then return nil end
		return v.type, v.itemName, v.player, v.bid or 0, v.buyout or 0, v.deposit or 0, v.consignment or 0, 0, 0, 0, v.count or 1, false
	end
	env.GetInboxItemLink = function(i, a)
		local _, link = attachment(mailAt(i), a)
		return link
	end
	env.GetInboxItem = function(i, a)
		local it, link, id = attachment(mailAt(i), a)
		if not it then return nil end
		local def = W.items[id] or {}
		return W.itemName(id, it.suffix) or tostring(link):match("%[(.-)%]"), id, W.icon(id), it.count or 1, def.quality or 1, true, false
	end

	-- [[ bags and bank ]] bank bags (6 and up) are only readable while the bank is open; soulbound marks
	local C = env.C_Container
	local numSlots, itemInfo = C.GetContainerNumSlots, C.GetContainerItemInfo
	C.GetContainerNumSlots = function(bag)
		if bag >= 6 and not W.bankOpen then return 0 end
		return numSlots(bag)
	end
	C.GetContainerItemInfo = function(bag, slot)
		if bag >= 6 and not W.bankOpen then return nil end
		local info = itemInfo(bag, slot)
		local s = W.bags[bag] and W.bags[bag][slot]
		if info and s and s.bound then info.isBound = true end
		return info
	end

	-- [[ your auctions ]] only when no other extension made them
	if not env.C_AuctionHouse.GetOwnedAuctions then
		env.C_AuctionHouse.GetOwnedAuctions = function()
			local out = {}
			for i, a in ipairs(W.owned or {}) do
				out[#out + 1] = {auctionID = i, itemKey = {itemID = a.itemID, itemLevel = 0, itemSuffix = a.suffix or 0, battlePetSpeciesID = 0},
					itemLink = W.link(a.itemID, a.suffix), status = a.status or 0, quantity = a.count or a.quantity or 1, timeLeft = 2,
					buyoutAmount = a.buyout}
			end
			return out
		end
	end
end)

-- [[ helpers for scenes ]]
function W.addMail(m)
	m.arrived = m.arrived or serverNow()
	table.insert(W.mail, 1, m) -- the newest on top, as in the game
	if W.mailOpen then W.fire("MAIL_INBOX_UPDATE") end
	return m
end
function W.openMail()
	W.mailOpen = true
	W.fire("MAIL_SHOW")
	W.fire("MAIL_INBOX_UPDATE")
	W.advance(2)
end
function W.closeMail()
	W.mailOpen = false
	W.fire("MAIL_CLOSED")
	W.advance(1)
end
-- the player takes a mail's money and items: the mail is gone
function W.takeMail(m)
	for i, x in ipairs(W.mail) do
		if x == m then table.remove(W.mail, i) break end
	end
	if W.mailOpen then W.fire("MAIL_INBOX_UPDATE") end
end
function W.openBank()
	W.bankOpen = true
	W.fire("BANKFRAME_OPENED")
	W.advance(2)
end
function W.closeBank()
	W.bankOpen = false
	W.fire("BANKFRAME_CLOSED")
	W.advance(1)
end
function W.setMoney(c)
	W.money = c
	W.fire("PLAYER_MONEY")
end
function W.bagsChanged()
	W.fire("BAG_UPDATE_DELAYED")
	W.advance(2)
end
function W.ownedChanged()
	W.fire("OWNED_AUCTIONS_UPDATED")
	W.advance(1)
end
-- puts items in a bag: W.fill(bag, {{id, count, suffix, bound}, ...})
function W.fill(bag, list)
	W.bags[bag] = {}
	for i, s in ipairs(list) do W.bags[bag][i] = {id = s[1], count = s[2] or 1, suffix = s[3], bound = s[4]} end
end

-- auction house mails, as the game sends them
function W.mailSold(id, bid, count, buyer, cut, deposit, suffix)
	local name = W.itemName(id, suffix)
	cut = cut or math.floor(bid * 0.05)
	deposit = deposit or 0
	return {sender = "Auction House", subject = "Auction successful: " .. name, money = bid + deposit - cut,
		invoice = {type = "seller", itemName = name, player = buyer, bid = bid, buyout = bid, deposit = deposit, consignment = cut, count = count or 1}}
end
function W.mailPending(id, bid, count, buyer, cut, deposit, suffix)
	local m = W.mailSold(id, bid, count, buyer, cut, deposit, suffix)
	m.subject = "Sale Pending: " .. W.itemName(id, suffix)
	m.money = 0
	m.invoice.type = "seller_temp_invoice"
	return m
end
function W.mailWon(id, bid, count, seller, suffix)
	local name = W.itemName(id, suffix)
	return {sender = "Auction House", subject = "Auction won: " .. name, money = 0, items = {{id = id, count = count or 1, suffix = suffix}},
		invoice = {type = "buyer", itemName = name, player = seller, bid = bid, buyout = bid, deposit = 0, consignment = 0, count = count or 1}}
end
function W.mailExpired(id, count, suffix)
	return {sender = "Auction House", subject = "Auction expired: " .. W.itemName(id, suffix), money = 0,
		items = {{id = id, count = count or 1, suffix = suffix}}}
end
function W.mailCancelled(id, count, suffix)
	return {sender = "Auction House", subject = "Auction canceled: " .. W.itemName(id, suffix), money = 0,
		items = {{id = id, count = count or 1, suffix = suffix}}}
end

-- W.mailAgo(mail, days): the mail arrived `days` days ago (it has 30 - days days left, as auction house mails do)
function W.mailAgo(m, days)
	m.daysLeft = 30 - days
	return m
end
