-- Stand-in world, part "share" (helper D): the guild addon channel, crafting at the profession window. Test tool only.
-- (Items in the bank: put them in W.bags[6] and up - the world's C_Item.GetItemCount counts every bag.)
--   W.inGuild            the player is in a guild (default false)
--   W.sent               every addon message sent: {prefix, text, channel, t}
--   W.addonRestricted    the game blocks addon messages (SendAddonMessage answers 11, AreOutgoing... true)
--   W.throttleNext       the next n sends answer 3 (too fast)
--   W.echoGuild          a guild message comes back to the sender too (as on the live game; default true)
--   W.deliver(list, sender)  hands sent messages to this client as if `sender` had sent them
--   W.craftable[rid]     what GetCraftableCount answers (default: worked out from the bags)
--   W.crafted            every CraftRecipe call: {rid, count, t}; W.craftCasts: the casts finish (2 s each), the
--                        reagents leave the bags, the items made arrive, UNIT_SPELLCAST_SUCCEEDED fires
--   W.hardware           true only while a click runs (Frame:Click); CraftRecipe fails without it

table.insert(W.onReset, function()
	W.inGuild = false
	W.sent = {}
	W.prefixes = {}
	W.addonRestricted = false
	W.throttleNext = 0
	W.echoGuild = true
	W.craftable = {}
	W.crafted = {}
	W.craftCasts = false
	W.hardware = false
end)

-- a click is a hardware event: W.hardware is true while its scripts run (kept if another part already does the same)
if not W.shareClickWrapped then
	W.shareClickWrapped = true
	local base = W.Frame.Click
	W.Frame.Click = function(self, button)
		local prev = W.hardware
		W.hardware = true
		local ok, e = pcall(base, self, button)
		W.hardware = prev
		if not ok then error(e, 0) end
	end
end

-- [[ items in bags ]] bags 0-5 (the bank tabs, 6 and up, are not carried)
local function bagCount(id)
	local n = 0
	for b = 0, 5 do local bag = W.bags[b] or {} for _, s in pairs(bag) do if s.id == id then n = n + s.count end end end
	return n
end
W.bagCount = bagCount
-- puts n of an item in the bags (a new slot in bag 4)
function W.give(id, n)
	W.bags[4] = W.bags[4] or {}
	local slot = 1
	while W.bags[4][slot] do slot = slot + 1 end
	W.bags[4][slot] = {id = id, count = n}
end
-- takes n of an item out of the bags
function W.take(id, n)
	for _, bag in pairs(W.bags) do
		for slot, s in pairs(bag) do
			if n <= 0 then return end
			if s.id == id then
				local t = math.min(n, s.count)
				s.count = s.count - t
				n = n - t
				if s.count <= 0 then bag[slot] = nil end
			end
		end
	end
end

-- hands addon messages to this client: list = {{prefix, text, channel}, ...} (as W.sent records them)
function W.deliver(list, sender)
	for _, m in ipairs(list) do W.fire("CHAT_MSG_ADDON", m.prefix, m.text, m.channel or "GUILD", sender or "Ann Smith") end
end
-- the messages sent, from index `from` on (copies)
function W.sentSince(from)
	local out = {}
	for i = from or 1, #W.sent do out[#out + 1] = W.copy(W.sent[i]) end
	return out
end

table.insert(W.onEnv, function(env)
	env.IsInGuild = function() return W.inGuild == true end
	env.C_ChatInfo = env.C_ChatInfo or {}
	env.C_ChatInfo.RegisterAddonMessagePrefix = function(p)
		if type(p) ~= "string" or #p > 16 then error("RegisterAddonMessagePrefix: bad prefix") end
		W.prefixes[p] = true
		return true
	end
	env.C_ChatInfo.IsAddonMessagePrefixRegistered = function(p) return W.prefixes[p] == true end
	env.C_ChatInfo.AreOutgoingAddonChatMessagesRestricted = function() return W.addonRestricted == true end
	env.C_ChatInfo.SendAddonMessage = function(prefix, text, channel, target)
		if type(prefix) ~= "string" or type(text) ~= "string" or type(channel) ~= "string" then error("SendAddonMessage: bad arguments") end
		if #text > 255 then error("SendAddonMessage: message longer than 255 bytes (" .. #text .. ")") end
		if text:find("\0", 1, true) then error("SendAddonMessage: a zero byte in the message") end
		if not W.prefixes[prefix] then return 1 end -- InvalidPrefix
		if W.addonRestricted then return 11 end -- AddOnMessageLockdown
		if (W.throttleNext or 0) > 0 then W.throttleNext = W.throttleNext - 1 return 3 end -- AddonMessageThrottle
		if channel == "GUILD" and not W.inGuild then return 10 end -- NotInGuild
		local m = {prefix = prefix, text = text, channel = channel, target = target, t = W.NOW}
		W.sent[#W.sent + 1] = m
		if channel == "GUILD" and W.echoGuild then
			local me = W.player .. " " .. W.surname
			W.after(0.05, function() W.fire("CHAT_MSG_ADDON", prefix, text, channel, me) end)
		end
		return 0
	end
	-- crafting
	env.C_TradeSkillUI.GetCraftableCount = function(rid)
		if W.craftable[rid] then return W.craftable[rid] end
		local r = W.recipes[rid]
		if not r then return 0 end
		local can
		for _, re in ipairs(r.reagents or {}) do
			local n = math.floor(bagCount(re[1]) / re[2])
			if not can or n < can then can = n end
		end
		return can or 0
	end
	env.C_TradeSkillUI.CraftRecipe = function(rid, count)
		if not W.hardware then error("CraftRecipe: only allowed during a click (hardware event)") end
		if not W.prof then error("CraftRecipe: no profession window open") end
		count = count or 1
		W.crafted[#W.crafted + 1] = {rid = rid, count = count, t = W.NOW}
		if W.craftCasts then
			local r = W.recipes[rid]
			for i = 1, count do
				W.after(2 * i, function()
					for _, re in ipairs(r.reagents or {}) do W.take(re[1], re[2]) end
					if r.out then W.give(r.out, r.qMin or 1) end
					W.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. i, rid)
					W.fire("BAG_UPDATE_DELAYED")
				end)
			end
		end
	end
end)
