-- The To do page of the simple window (the first page): everything worth doing now, most valuable or most urgent first,
-- at most 12 entries:
--   - prices missing or too old (a full scan first: nothing else works without prices)
--   - the best few buys and sells of the Buy and Sell pages (S.BuyEntries / S.SellEntries, SimpleTrade.lua), by profit
--   - mail to collect (gold and items waiting in your characters' mailboxes, as seen at the last visit)
--   - expired auctions back in your bags (post them again)
--   - cooldown crafts worth doing (transmutes, Mooncloth ...): XNAH cannot always see the game's waiting time, so the
--     entry has a Done button; a craft XNAH sees you make, or a waiting time it reads while your profession window is
--     open, marks it done too. Saved in XNAHDB.todoCooldowns["character|recipe"] = time it is ready again.
--   - the crafting queue, a check of your auctions for cheaper listings, an older full scan
-- Ranked by the gold an entry brings (entry.profit for trades, the gold waiting for mail, ...); entries without a
-- value come after those, the scan that is only getting old last.
local ADDON, X = ...
local S, UI = X.Simple, X.UI
if not S then return end

local MAX = 12
local TRADE_N = 4         -- best buys and best sells taken from each page
local RECENT = 3 * 86400  -- expired auctions of the last 3 days
local GREY, GREEN = "|cff999999", "|cff4ade80"
local ICON = {
	mail = "Interface\\Icons\\INV_Letter_15",
	bags = "Interface\\Icons\\INV_Misc_Bag_08",
	scan = "Interface\\Icons\\INV_Misc_Spyglass_02",
	queue = "Interface\\Icons\\Trade_BlackSmithing",
	check = "Interface\\Icons\\INV_Misc_Note_01",
	page = "Interface\\Icons\\INV_Misc_Coin_02",
}

local function plural(n, one, many) return X.Num(n) .. " " .. (n == 1 and one or (many or one .. "s")) end
local function realmChars()
	local rk = X.realmKey or X.RealmKey()
	local out = {}
	for k, c in pairs((X.db and X.db.chars) or {}) do if c.realm == rk then out[k] = c end end
	return out
end
local function me() return X.db.chars and X.db.chars[X.CharKey()] end
local function worth(key, count)
	local each = X.UnitWorth and X.UnitWorth(key) or X.AfterCut(X.Price(key)) or 0
	return (each or 0) * (count or 1)
end
-- a page of the simple window, else the tab of the full window
local function openPage(view, tab)
	return function()
		if view and S.views[view] then S.Select(view) return end
		local f = S.Frame()
		if f then f:Hide() end
		UI.Open(tab or view)
	end
end

-- [[ cooldown crafts ]]
local function doneBook()
	X.db.todoCooldowns = X.db.todoCooldowns or {}
	return X.db.todoCooldowns
end
local function hoursText(h)
	if h >= 30 then return X.Round(h / 24) .. " days" end
	if h >= 1 then return X.Round(h) .. " hours" end
	return X.Round(h * 60) .. " minutes"
end
-- marks a cooldown craft done for a character until its waiting time is over (seconds: when known from the game)
function X.TodoCooldownDone(char, rid, seconds)
	local hours = X.CRAFT_COOLDOWNS and X.CRAFT_COOLDOWNS[rid]
	if not hours or not char then return end
	doneBook()[char .. "|" .. rid] = X.Now() + (seconds or hours * 3600)
	S.RefreshSoon()
end
function X.TodoCooldownReady(char, rid)
	local t = doneBook()[char .. "|" .. rid]
	return not t or t <= X.Now()
end
-- can this character craft it right now in the open profession window?
local function craftableNow(rid)
	local T = C_TradeSkillUI
	if not (T and T.CraftRecipe and T.IsTradeSkillReady and X.Try(T.IsTradeSkillReady)) then return false end
	if X.Try(T.IsTradeSkillLinked) or X.Try(T.IsTradeSkillGuild) or X.Try(T.IsNPCCrafting) then return false end
	local found = false
	for _, id in ipairs(X.Try(T.GetAllRecipeIDs) or {}) do if id == rid then found = true break end end
	if not found then return false end
	local n = T.GetCraftableCount and X.Try(T.GetCraftableCount, rid)
	return type(n) ~= "number" or n > 0
end
local function cooldownEntries(out)
	if not (X.CRAFT_COOLDOWNS and X.Recipe and X.RecipeCost and X.KnownBy) then return end
	local P = X.StrategyParams and X.StrategyParams("cooldown") or {}
	local minProfit = P.minProfit or 1000
	local mine = X.CharKey()
	for rid, hours in pairs(X.CRAFT_COOLDOWNS) do
		local r = X.Recipe(rid)
		local who = X.KnownBy(rid)
		if r and r.out and #who > 0 then
			local key = tostring(r.out)
			local cost, missing = X.RecipeCost(rid)
			local price = X.Price(key)
			local sell = X.AfterCut(price)
			local profit = cost and sell and (sell - cost) * (r.n or 1)
			if profit and (missing or 0) == 0 and profit >= minProfit then
				local name = r.name or X.ItemName(key)
				local title = name:find("^Transmute") and name or ("Make " .. name)
				for _, char in ipairs(who) do
					if X.TodoCooldownReady(char, rid) then
						local here = char == mine
						local e = {id = "todo:cd:" .. char .. "|" .. rid, key = key, title = title, value = profit,
							name = name, price = price,
							sub = S.Signed(profit) .. GREY .. (here and " - ready to craft" or (" - on " .. char)) .. "|r",
							sentence = here and "Open your profession window and craft it now." or ("Log in on " .. char .. " and craft it."),
							why = "It brings " .. X.MoneyPlain(profit) .. " over its reagents after the cut, and it can be made only " ..
								"every " .. hoursText(hours) .. ". XNAH cannot always see that waiting time: press Done after you made it, " ..
								"and it comes back when the wait is over.",
							lines = {{"Reagents cost", S.Money(cost * (r.n or 1))}, {"Sells for", S.Money(price)},
								{"Can be made", "every " .. hoursText(hours)}},
							button = {label = "Done", run = function() X.TodoCooldownDone(char, rid) end,
								tip = "You made it: hide it until it can be made again (" .. hoursText(hours) .. ")."},
							skip = true}
						if here and craftableNow(rid) then
							e.button2 = e.button
							e.button = {label = "Craft it now", run = function()
								local ok, err = pcall(C_TradeSkillUI.CraftRecipe, rid, 1)
								if not ok then X.Print("could not start crafting: " .. tostring(err)) end
							end, tip = "Starts the craft in your open profession window."}
						end
						out[#out + 1] = e
					end
				end
			end
		end
	end
end
-- a craft XNAH sees you make: done (the recipe's ID is the spell cast, as in Queue.lua)
X.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" or not X.db then return end
	spellID = X.Plain(spellID)
	if spellID and X.CRAFT_COOLDOWNS and X.CRAFT_COOLDOWNS[spellID] then X.TodoCooldownDone(X.CharKey(), spellID) end
end)
-- the profession window tells the waiting time (GUESS: C_TradeSkillUI.GetRecipeCooldown -> seconds left first): only
-- ever used to hide a craft, never to show one again early
local function readCooldowns()
	local T = C_TradeSkillUI
	if not (X.db and X.CRAFT_COOLDOWNS and T and T.GetRecipeCooldown and T.GetAllRecipeIDs) then return end
	if T.IsTradeSkillReady and not X.Try(T.IsTradeSkillReady) then return end
	if X.Try(T.IsTradeSkillLinked) or X.Try(T.IsTradeSkillGuild) or X.Try(T.IsNPCCrafting) then return end
	local mine = X.CharKey()
	for _, rid in ipairs(X.Try(T.GetAllRecipeIDs) or {}) do
		if X.CRAFT_COOLDOWNS[rid] then
			local left = X.Plain(X.Try(T.GetRecipeCooldown, rid))
			if type(left) == "number" and left > 60 then
				local t = doneBook()[mine .. "|" .. rid]
				if not t or t < X.Now() + left - 60 then X.TodoCooldownDone(mine, rid, left) end
			end
		end
	end
end
X.On("TRADE_SKILL_SHOW", function() X.Debounce("xnah-todo-cd", 1, readCooldowns) end)
X.On("TRADE_SKILL_LIST_UPDATE", function() X.Debounce("xnah-todo-cd", 1, readCooldowns) end)

-- [[ the other jobs ]]
local function mailEntry(out)
	local gold, items, iworth, chars, expired = 0, 0, 0, {}, 0
	local mine = X.CharKey()
	local L = X.Ledger and X.Ledger()
	local recentExpired = {}
	for _, e in ipairs((L and L.expired) or {}) do
		if (e.t or 0) >= X.Now() - RECENT and e.key then recentExpired[e.key] = true end
	end
	for k, c in pairs(realmChars()) do
		local any = false
		if (c.mailMoney or 0) > 0 then gold, any = gold + c.mailMoney, true end
		if k == mine then
			for key, n in pairs(c.mail or {}) do
				items, iworth, any = items + n, iworth + worth(key, n), true
				if recentExpired[key] then expired = expired + 1 end
			end
		end
		if any then chars[#chars + 1] = k end
	end
	if gold == 0 and items == 0 then return end
	table.sort(chars)
	local parts = {}
	if gold > 0 then parts[#parts + 1] = S.Money(gold) end
	if items > 0 then parts[#parts + 1] = plural(items, "item") end
	local where = (#chars == 1 and chars[1] == mine) and "" or (" on " .. table.concat(chars, ", "))
	out[#out + 1] = {id = "todo:mail", icon = ICON.mail, graph = false, value = gold + iworth,
		title = "Collect your mail", sub = table.concat(parts, " and ") .. GREY .. " waiting|r",
		name = "Your mail", price = gold > 0 and gold or nil,
		sentence = "Open a mailbox and take everything" .. where .. ".",
		why = "Gold from your sales and items from the auction house wait in the mail until you take them (as XNAH saw it " ..
			"at your last visit)." .. (expired > 0 and (" " .. plural(expired, "of them is an expired auction", "of them are expired auctions") ..
			": post them again after you take them.") or ""),
		lines = {{"Gold", S.Money(gold > 0 and gold or nil)}, {"Items", items > 0 and (X.Num(items) .. " (" .. X.MoneyPlain(iworth) .. ")") or "-"}}}
end

local function expiredEntry(out, skipKeys)
	local c = me()
	local L = X.Ledger and X.Ledger()
	if not (c and L) then return end
	local mine, seen, n, value, first = X.CharKey(), {}, 0, 0, nil
	for _, e in ipairs(L.expired or {}) do
		local key = e.key
		if key and (e.t or 0) >= X.Now() - RECENT and (not e.char or e.char == mine) and not seen[key] and not skipKeys[key] then
			seen[key] = true
			local have = c.bags and c.bags[key] or 0
			if have > 0 then
				n, value = n + 1, value + worth(key, have)
				first = first or key
			end
		end
	end
	if n == 0 then return end
	out[#out + 1] = {id = "todo:expired", icon = ICON.bags, graph = false, value = value,
		title = "Post your expired items again", sub = plural(n, "item") .. GREY .. " - worth |r" .. S.Money(value),
		name = "Expired auctions", price = value,
		sentence = "Post " .. (n == 1 and "it" or "them") .. " again on the Sell page.",
		why = "Your auction" .. (n == 1 and " was" or "s were") .. " not bought in time and came back by mail. " ..
			(n == 1 and ("It is " .. X.ItemName(first) .. ".") or ("The first one: " .. X.ItemName(first) .. ".")),
		button = {label = "Open the Sell page", run = openPage("sell")}}
end

local function queueEntry(out)
	if not X.QueueRows then return end
	local rows = X.QueueRows()
	local crafts, profit = 0, 0
	for _, r in ipairs(rows) do
		if (r.craft or 0) > 0 then crafts, profit = crafts + r.craft, profit + (r.profit or 0) end
	end
	if crafts == 0 then return end
	local toBuy = 0
	if X.QueueMaterials then
		for _, m in ipairs((X.QueueMaterials(rows))) do if (m.buy or 0) > 0 and m.how ~= "vendor" then toBuy = toBuy + 1 end end
	end
	local e = {id = "todo:queue", icon = ICON.queue, graph = false, value = profit > 0 and profit or nil,
		title = "Craft your queue", sub = plural(crafts, "craft") .. (profit > 0 and (GREY .. " - |r" .. S.Signed(profit)) or ""),
		name = "Your crafting queue", price = profit > 0 and profit or nil,
		lines = {{"Crafts to do", X.Num(crafts)}, {"Materials to buy", X.Num(toBuy)}}}
	local function openQueue()
		X.S().craftView = "queue"
		local f = S.Frame()
		if f then f:Hide() end
		UI.Open("craft")
	end
	local row, count = nil, nil
	if X.CraftNextTarget then row, count = X.CraftNextTarget() end
	if row then
		e.sentence = "Press the button to craft " .. (row.name or "the next recipe") .. (count > 1 and (" x" .. count) or "") .. "."
		e.why = "Your profession window is open and you have the materials. One click starts one recipe."
		e.button = {label = "Craft next", run = function() X.CraftNext() end}
		e.button2 = {label = "Open the queue", run = openQueue}
	elseif toBuy > 0 and X.QueueToShop then
		e.sentence = "Buy the materials first: the button puts them on a shopping list."
		e.why = plural(toBuy, "material is", "materials are") .. " missing. Then open your profession window and craft."
		e.button = {label = "Put materials on a list", run = function()
			local n = X.QueueToShop()
			if n then X.Print(plural(n, "material") .. " put on the shopping list \"" .. (X.QUEUE_LIST or "Crafting queue") .. "\"") end
		end, tip = "Adds every material still to buy to a shopping list (it buys nothing)."}
		e.button2 = {label = "Open the queue", run = openQueue}
	else
		e.sentence = "Open your profession window, then come back here to craft."
		e.why = "You have the materials for your queue."
		e.button = {label = "Open the queue", run = openQueue}
	end
	out[#out + 1] = e
end

local function checkEntry(out)
	local c = me()
	local cs = X.cancel
	if not (X.ahOpen and X.CancelScan and cs and cs.state == "idle" and c and next(c.auctions or {})) then return end
	local n = 0
	for _ in pairs(c.auctions) do n = n + 1 end
	out[#out + 1] = {id = "todo:check", icon = ICON.check, graph = false,
		title = "Check your auctions", sub = plural(n, "item") .. GREY .. " on the auction house|r", name = "Your auctions",
		sentence = "Press Check: XNAH looks for cheaper listings of the things you sell.",
		why = "When someone sells the same thing cheaper (an undercut), yours will not sell. The Sell page then shows " ..
			"them with a Cancel button. Checking buys and cancels nothing.",
		button = {label = "Check", run = function() X.CancelScan() end}}
end

-- the full scan: urgent = no prices, or too old to use
local function scanEntry(n, urgent)
	local St = X.S()
	if n.scanning then
		if not urgent then return nil end
		return {id = "todo:scan", icon = ICON.scan, graph = false, urgent = true, title = "Scanning the auction house",
			sub = GREY .. (X.scan.text or "") .. "|r", name = "Full scan", sentence = "Wait a moment: XNAH is reading every auction.",
			why = "When it is done, this page shows what is worth doing with the new prices."}
	end
	local stale = not n.lastFull or n.scanAge > St.staleHours * 3600
	if urgent ~= stale then return nil end
	if not stale and n.scanAge <= St.homeScanHours * 3600 then return nil end
	local e = {id = "todo:scan", icon = ICON.scan, graph = false, urgent = urgent, title = "Do a full scan", name = "Full scan"}
	if not n.lastFull then
		e.sub = GREY .. "no prices yet|r"
		e.why = "XNAH needs prices to find gold for you. One full scan reads every auction at once."
	else
		e.sub = GREY .. "prices are " .. (X.Ago(n.lastFull):gsub(" ago", "")) .. " old|r"
		e.why = stale and ("Prices older than " .. St.staleHours .. " hours are not used: no buys or sells until you scan.") or
			"A fresh scan finds today's chances and keeps the price history going."
	end
	if n.ahOpen and n.scanReady then
		e.sentence = "Press Scan now: XNAH reads every auction at once (it takes a minute or two)."
		e.button = {label = "Scan now", run = function() X.FullScan() end}
	elseif n.ahOpen then
		e.sentence = "The server allows the next full scan in " .. X.Clock(n.scanLeft) .. "."
		e.button = {label = "Scan now (in " .. X.Clock(n.scanLeft) .. ")", disabled = true, run = function() end}
	else
		e.sentence = "Do a full scan at the auction house."
	end
	return e
end

-- without the Buy and Sell pages (an older SimpleTrade.lua): the home page's trade jobs, opening the full window
local TRADE_JOBS = {deals = "deals", watch = "buy", strategies = "strategies", undercut = "sell", bags = "sell", shop = "buy"}
local function homeTradeEntries(out)
	if not X.HomeTodo then return end
	for _, job in ipairs(X.HomeTodo()) do
		local tab = TRADE_JOBS[job.id]
		if tab then
			out[#out + 1] = {id = "todo:home:" .. job.id, icon = ICON.page, graph = false, title = job.text, sub = job.why,
				name = job.text, sentence = job.why, why = "Opens the full window, where you can do it.",
				button = {label = "Open " .. (job.button or "it"), run = openPage(tab, tab)}}
		end
	end
end

-- [[ the page ]]
local EMPTY_NO_PRICES = "Do a full scan at the auction house - XNAH needs prices to find gold for you."
local EMPTY = "Nothing to do right now - well done! Come back after your next visit to the auction house or the mailbox."

function X.TodoEntries()
	local out = {}
	local n = X.HomeNumbers()
	local urgent = scanEntry(n, true)
	if urgent then out[#out + 1] = urgent end
	-- the best buys and sells (each entry's profit ranks it)
	local tradeKeys, trade = {}, {}
	local function take(fn)
		local ok, list = pcall(fn, TRADE_N)
		if not ok then X.OnError(list) return end
		for i = 1, math.min(TRADE_N, #(list or {})) do
			local e = list[i]
			trade[e] = true
			out[#out + 1] = e
			if e.key then tradeKeys[e.key] = true end
		end
	end
	if S.BuyEntries then take(S.BuyEntries) end
	if S.SellEntries then take(S.SellEntries) end
	if not S.BuyEntries and not S.SellEntries then homeTradeEntries(out) end
	mailEntry(out)
	expiredEntry(out, tradeKeys)
	cooldownEntries(out)
	queueEntry(out)
	checkEntry(out)
	local old = scanEntry(n, false)
	if old then old.last = true out[#out + 1] = old end
	-- most urgent, then most valuable; the old scan last (R's entries are not changed: their numbers are kept aside)
	local value, rank = {}, {}
	for i, e in ipairs(out) do
		rank[e] = i
		if trade[e] then value[e] = e.profit else value[e] = e.value end
	end
	table.sort(out, function(a, b)
		if (a.urgent == true) ~= (b.urgent == true) then return a.urgent == true end
		if (a.last == true) ~= (b.last == true) then return b.last == true end
		local va, vb = value[a], value[b]
		if (va ~= nil) ~= (vb ~= nil) then return va ~= nil end
		if va and vb and va ~= vb then return va > vb end
		return rank[a] < rank[b]
	end)
	for i = #out, MAX + 1, -1 do out[i] = nil end
	-- only a scan that no button can start (the auction house is closed): a friendly line instead
	if #out == 1 and out[1].id == "todo:scan" and not out[1].button and not n.scanning then
		if not n.lastFull or next(X.Items()) == nil then return {}, EMPTY_NO_PRICES end
		if out[1].urgent then return {}, "Do a full scan at the auction house - your prices are too old to find gold with." end
		return {}, EMPTY .. " A full scan at the auction house would freshen your prices."
	end
	if #out == 0 then return out, next(X.Items()) == nil and EMPTY_NO_PRICES or EMPTY end
	return out, EMPTY
end

S.AddView("todo", {title = "To do", order = 1, list = X.TodoEntries, emptyText = EMPTY})
