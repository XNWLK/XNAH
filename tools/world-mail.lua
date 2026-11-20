-- Stand-in world, part "mail" (round 12, helper G): taking gold and items out of the mailbox (tools/world-ledger.lua
-- has the mailbox itself), the game's mail window and free bag slots. Test tool only.
--   W.bagRoom        free bag slots (default 100); each item taken uses one; at 0 a take fails with MAIL_FAILED
--   W.mailTakes      every take: {what = "money" / "item", index, attachment, t}
--   W.mailBusyFor    seconds the server takes for one take (default 0.2): C_Mail.IsCommandPending() is true meanwhile
--   W.mailBlocked    true: a take from a timer (not a click) is blocked: nothing happens, ADDON_ACTION_BLOCKED fires
-- Auction house mails (sender "Auction House") go away once their gold and items are taken, as in the game.

table.insert(W.onReset, function()
	W.bagRoom = 100
	W.mailTakes = {}
	W.mailBusyFor = 0.2
	W.mailBusyUntil = 0
	W.mailBlocked = false
	W.mailClicking = false
end)

-- a click is a hardware event (W.mailClicking is true while its scripts run)
if not W.mailClickWrapped then
	W.mailClickWrapped = true
	local base = W.Frame.Click
	W.Frame.Click = function(self, button)
		local prev = W.mailClicking
		W.mailClicking = true
		local ok, e = pcall(base, self, button)
		W.mailClicking = prev
		if not ok then error(e, 0) end
	end
end

local function empty(m)
	if (m.money or 0) > 0 then return false end
	for a = 1, 16 do if m.items and m.items[a] then return false end end
	return true
end
local function after(m)
	if empty(m) and (m.sender or "Auction House") == "Auction House" then
		for i, x in ipairs(W.mail) do if x == m then table.remove(W.mail, i) break end end
	end
	W.fire("MAIL_INBOX_UPDATE")
end
local function blocked()
	if W.mailBlocked and not W.mailClicking then
		W.fire("ADDON_ACTION_BLOCKED", W.ADDON, "TakeInbox")
		return true
	end
	return false
end

table.insert(W.onEnv, function(env)
	env.TakeInboxMoney = function(i)
		if blocked() then return end
		local m = W.mailOpen and W.mail[i]
		if not m then return end
		W.mailTakes[#W.mailTakes + 1] = {what = "money", index = i, t = W.NOW}
		W.mailBusyUntil = W.NOW + W.mailBusyFor
		W.after(W.mailBusyFor, function()
			W.money = (W.money or 1234567) + (m.money or 0)
			m.money = 0
			W.fire("PLAYER_MONEY")
			after(m)
		end)
	end
	env.TakeInboxItem = function(i, a)
		if blocked() then return end
		local m = W.mailOpen and W.mail[i]
		local it = m and m.items and m.items[a]
		if not it then return end
		W.mailTakes[#W.mailTakes + 1] = {what = "item", index = i, attachment = a, t = W.NOW}
		W.mailBusyUntil = W.NOW + W.mailBusyFor
		W.after(W.mailBusyFor, function()
			if W.bagRoom <= 0 then
				W.fire("MAIL_FAILED", it.id)
				return
			end
			W.bagRoom = W.bagRoom - 1
			W.bags[4] = W.bags[4] or {}
			local slot = 1
			while W.bags[4][slot] do slot = slot + 1 end
			W.bags[4][slot] = {id = it.id, count = it.count or 1, suffix = it.suffix}
			m.items[a] = nil
			after(m)
		end)
	end
	env.AutoLootMailItem = function(i)
		local m = W.mailOpen and W.mail[i]
		if not m then return end
		if (m.money or 0) > 0 then env.TakeInboxMoney(i) end
		for a = 1, 16 do if m.items and m.items[a] then env.TakeInboxItem(i, a) end end
	end
	env.HasInboxItem = function(i, a)
		local m = W.mailOpen and W.mail[i]
		return (m and m.items and m.items[a]) and true or false
	end
	env.C_Mail = {
		IsCommandPending = function() return W.NOW < W.mailBusyUntil end,
		HasInboxMoney = function(i) local m = W.mailOpen and W.mail[i] return (m and (m.money or 0) > 0) and true or false end,
		SetOpeningAll = function(on) W.openingAll = on end,
		CanCheckInbox = function() return true, 0 end,
	}
	env.C_Container.CalculateTotalNumberOfFreeBagSlots = function() return W.bagRoom end
end)

-- the game's mail window opens and closes with the mailbox
local open, close = W.openMail, W.closeMail
function W.openMail()
	W.env.MailFrame = W.mailFrame or W.newFrame("Frame", "MailFrame", W.env.UIParent)
	W.mailFrame = W.env.MailFrame
	W.mailFrame:Show()
	open()
end
function W.closeMail()
	if W.mailFrame then W.mailFrame:Hide() end
	close()
end
