-- The crafting queue: per recipe a target - "restock" (keep this many: in your bags, bank, mail, on the auction house
-- and on your other characters) or "craft" (craft it this many times). From that: how many crafts are still to do, the
-- profit, the materials to buy (minus what you own), and one "Craft next" click at the profession window.
--   XNAHDB.queue[recipeID] = {mode = "restock" / "craft", n = number, at = when it was added}
local ADDON, X = ...

local function db()
	X.db.queue = X.db.queue or {}
	return X.db.queue
end

-- how many of an item you own: every character of this realm (when the inventory part knows them), else this
-- character's bags and bank
function X.QueueOwned(itemID)
	if not itemID then return 0 end
	if X.Owned then
		local total = X.Try(X.Owned, itemID)
		if type(total) == "number" then return total end
	end
	if C_Item and C_Item.GetItemCount then
		local n = X.Try(C_Item.GetItemCount, itemID, true, false, true, true)
		if type(n) == "number" then return n end
	end
	return 0
end

function X.QueueGet(rid)
	return db()[rid]
end
-- sets a recipe's target (mode "restock" or "craft"); n of 0 or less (or nil) takes it out of the queue
function X.QueueSet(rid, mode, n)
	if not rid or not X.Recipe(rid) then return false end
	n = tonumber(n)
	if not n or n <= 0 then
		db()[rid] = nil
	else
		n = math.min(9999, math.floor(n + 0.5))
		local q = db()[rid]
		if q then
			q.mode, q.n = mode == "craft" and "craft" or "restock", n
		else
			db()[rid] = {mode = mode == "craft" and "craft" or "restock", n = n, at = X.Now()}
		end
	end
	X.Fire("XNAH_QUEUE")
	return true
end
function X.QueueCount()
	local n = 0
	for _ in pairs(db()) do n = n + 1 end
	return n
end

-- [[ the queue's rows ]] {rid, key, name, mode, target, have, craft (crafts still to do), makes (items one craft makes),
-- cost (of one item), sell (one, after the cut), profit (of all crafts; nil while a reagent has no price), missing}
function X.QueueRows()
	local out = {}
	for rid, q in pairs(db()) do
		local r = X.Recipe(rid)
		if r and r.out then
			local makes = r.n or 1
			local key = tostring(r.out)
			local have = X.QueueOwned(r.out)
			local craft
			if q.mode == "craft" then
				craft = q.n
			else
				craft = math.max(0, math.ceil((q.n - have) / makes - 1e-9))
			end
			local cost, missing = X.RecipeCost(rid)
			local sell = X.AfterCut(X.Price(key))
			local row = {rid = rid, key = key, name = r.name, mode = q.mode, target = q.n, have = have, craft = craft,
				makes = makes, cost = cost, sell = sell, missing = missing or 0, prof = r.prof, at = q.at or 0}
			if cost and sell and row.missing == 0 then row.profit = craft * makes * (sell - cost) end
			out[#out + 1] = row
		end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		return a.rid < b.rid
	end)
	return out
end

-- [[ materials ]] every reagent of the queue's crafts, minus what you own:
-- {id, key, need, have, buy, unit, how ("vendor" / "ah" / "craft" / nil), vendor (name), total (cost of what to buy)}
-- second value: totals {cost (all to buy), vendor = {[vendor name] = {rows}}}
function X.QueueMaterials(rows)
	rows = rows or X.QueueRows()
	local need, order = {}, {}
	for _, row in ipairs(rows) do
		local r = X.Recipe(row.rid)
		if r and row.craft > 0 then
			for _, re in ipairs(r.r or {}) do
				if not need[re[1]] then need[re[1]] = 0 order[#order + 1] = re[1] end
				need[re[1]] = need[re[1]] + re[2] * row.craft
			end
		end
	end
	local out, totals = {}, {cost = 0, vendor = {}, missing = 0}
	for _, id in ipairs(order) do
		local have = X.QueueOwned(id)
		local unit, how = X.ReagentCost(id)
		local m = {id = id, key = tostring(id), need = need[id], have = have, buy = math.max(0, need[id] - have), unit = unit, how = how}
		if unit then m.total = unit * m.buy else totals.missing = totals.missing + (m.buy > 0 and 1 or 0) end
		if how == "vendor" then
			local _, info = X.VendorBuy(id)
			m.vendor = info and info.from or "a vendor"
			if m.buy > 0 then
				totals.vendor[m.vendor] = totals.vendor[m.vendor] or {}
				table.insert(totals.vendor[m.vendor], m)
			end
		end
		totals.cost = totals.cost + (m.total or 0)
		out[#out + 1] = m
	end
	table.sort(out, function(a, b)
		if (a.buy > 0) ~= (b.buy > 0) then return a.buy > 0 end
		return (a.total or 0) > (b.total or 0)
	end)
	return out, totals
end

-- puts every material still to buy (not the vendor ones) on the shopping list "Crafting queue", at most 120% of the
-- current price; returns how many items were added (nil when there is no shopping list part)
X.QUEUE_LIST = "Crafting queue"
function X.QueueToShop()
	if not X.ShopAdd then return nil end
	local n = 0
	for _, m in ipairs((X.QueueMaterials())) do
		if m.buy > 0 and m.how ~= "vendor" then
			local price = X.Price(m.key, "mkt") or X.Price(m.key)
			X.ShopAdd(X.QUEUE_LIST, m.key, m.buy, price and X.Round(price * 1.2) or nil)
			n = n + 1
		end
	end
	return n
end

-- [[ craft next ]] the first queued recipe with crafts to do that the open profession window can make
-- returns row, count (crafts to start now) - or nil, the reason in plain words
function X.CraftNextTarget()
	local T = C_TradeSkillUI
	if not (T and T.GetAllRecipeIDs and T.CraftRecipe) then return nil, "Crafting from XNAH is not possible on this client." end
	if not (T.IsTradeSkillReady and X.Try(T.IsTradeSkillReady)) then return nil, "Open your profession window to craft." end
	if X.Try(T.IsTradeSkillLinked) or X.Try(T.IsTradeSkillGuild) or X.Try(T.IsNPCCrafting) then
		return nil, "This is someone else's profession window."
	end
	local set = {}
	for _, id in ipairs(X.Try(T.GetAllRecipeIDs) or {}) do set[id] = true end
	local short
	for _, row in ipairs(X.QueueRows()) do
		if row.craft > 0 and set[row.rid] then
			local info = T.GetRecipeInfo and X.Try(T.GetRecipeInfo, row.rid)
			if not info or info.learned ~= false then
				local can = row.craft
				if T.GetCraftableCount then
					local c = X.Try(T.GetCraftableCount, row.rid)
					if type(c) == "number" then can = math.min(can, c) end
				end
				if can > 0 then return row, can end
				short = short or row
			end
		end
	end
	if short then return nil, "Not enough reagents in your bags for " .. (short.name or "the next recipe") .. "." end
	return nil, "Nothing in the queue for this profession window."
end
-- ONE click = one CraftRecipe call. Call it only from the OnClick of XNAH's own button (the game needs a click).
function X.CraftNext()
	local row, count = X.CraftNextTarget()
	if not row then X.Print(count) return false end
	local ok, err = pcall(C_TradeSkillUI.CraftRecipe, row.rid, count)
	if not ok then X.Print("could not start crafting: " .. tostring(err)) return false end
	X.Print("crafting " .. (row.name or "?") .. (count > 1 and (" x" .. count) or ""))
	return true
end

-- a finished craft of a "craft N times" recipe counts down (the recipe's ID is the spell cast)
X.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
	if unit ~= "player" or not X.db then return end
	spellID = X.Plain(spellID)
	local q = spellID and db()[spellID]
	if not q or q.mode ~= "craft" then return end
	q.n = q.n - 1
	if q.n <= 0 then db()[spellID] = nil end
	X.Debounce("queue", 0.3, function() X.Fire("XNAH_QUEUE") end)
end)
-- what you own changed: the numbers again
X.On("BAG_UPDATE_DELAYED", function() X.Debounce("queue", 0.5, function() X.Fire("XNAH_QUEUE") end) end)
X.On("TRADE_SKILL_SHOW", function() X.Debounce("queue", 0.5, function() X.Fire("XNAH_QUEUE") end) end)
X.On("TRADE_SKILL_CLOSE", function() X.Debounce("queue", 0.5, function() X.Fire("XNAH_QUEUE") end) end)
X.On("XNAH_INVENTORY", function() X.Debounce("queue", 0.5, function() X.Fire("XNAH_QUEUE") end) end)
