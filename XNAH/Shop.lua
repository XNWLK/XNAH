-- Shopping lists: what to buy, how many, and the most to pay for one.
--   XNAHDB.shop[name] = {items = {{key, qty, max (copper or nil), bought, keep}}}
-- An entry with keep = true is "keep this many in stock": what is still needed is qty minus what you own (bags, bank,
-- mail, auction house, all your characters, and purchases still on their way in the mail - X.QueueOwned), not qty
-- minus what was bought, so it is never bought twice. Lists saved before (no keep field) work as before.
-- Buying goes through the purchase engine (Buy.lua): one click per purchase step.
local ADDON, X = ...

local function lists()
	X.db.shop = X.db.shop or {}
	return X.db.shop
end
local function changed() X.Fire("XNAH_SHOP") end

-- names of all lists, sorted
function X.ShopLists()
	local out = {}
	for name in pairs(lists()) do out[#out + 1] = name end
	table.sort(out, function(a, b) return a:lower() < b:lower() end)
	return out
end
function X.ShopList(name)
	return name and lists()[name] or nil
end
function X.ShopEntry(name, key)
	local l = X.ShopList(name)
	if not l then return nil end
	for i, e in ipairs(l.items) do if e.key == key then return e, i end end
	return nil
end
function X.ShopNew(name)
	name = X.Trim(name)
	if name == "" then return nil end
	local all = lists()
	all[name] = all[name] or {items = {}}
	changed()
	return all[name]
end
-- adds `qty` of an item to a list (made if needed); an item already on it gets the quantity added; max (copper) is
-- the most to pay for one (nil keeps the earlier one). keep = true: "keep this many in stock" (qty is then the number
-- to have, so an item already on the list gets qty as its new number instead of adding); false: back to a plain buy;
-- nil: as it was.
function X.ShopAdd(listName, key, qty, maxPrice, keep)
	if not listName or not key then return nil end
	local l = X.ShopList(listName) or X.ShopNew(listName)
	if not l then return nil end
	qty = math.max(1, math.floor(tonumber(qty) or 1))
	local e = X.ShopEntry(listName, key)
	if e then
		if keep ~= nil then e.keep = keep and true or nil end
		if e.keep and keep then e.qty = qty else e.qty = e.qty + qty end
		if maxPrice and maxPrice > 0 then e.max = maxPrice end
	else
		e = {key = key, qty = qty, max = (maxPrice and maxPrice > 0) and maxPrice or nil, bought = 0, keep = keep and true or nil}
		table.insert(l.items, e)
	end
	changed()
	return e
end
function X.ShopRemove(listName, key)
	local l = X.ShopList(listName)
	local _, i = X.ShopEntry(listName, key)
	if l and i then table.remove(l.items, i) changed() end
end
function X.ShopSet(listName, key, field, value)
	local e = X.ShopEntry(listName, key)
	if not e then return end
	if field == "max" then e.max = (value and value > 0) and value or nil
	elseif field == "qty" then e.qty = math.max(1, math.floor(value or 1))
	elseif field == "bought" then e.bought = math.max(0, math.floor(value or 0))
	elseif field == "keep" then e.keep = value and true or nil end
	changed()
end
function X.ShopDelete(name)
	lists()[name] = nil
	changed()
end
function X.ShopRename(old, new)
	new = X.Trim(new or "")
	local all = lists()
	if new == "" or not all[old] or all[new] then return false end
	all[new], all[old] = all[old], nil
	changed()
	return true
end
-- empties a list (keep = true: only sets "bought" back to 0)
function X.ShopClear(name, keep)
	local l = X.ShopList(name)
	if not l then return end
	if keep then for _, e in ipairs(l.items) do e.bought = 0 end else l.items = {} end
	changed()
end
-- how many of an entry's item you own (all characters, and what you bought that is still on its way in the mail -
-- X.QueueOwned in Queue.lua counts that); an "id:suffix" item counts only that version
function X.ShopOwned(e)
	local key = tostring(e.key)
	return X.QueueOwned and X.QueueOwned(key:find(":", 1, true) and key or X.KeyID(key)) or 0
end
function X.ShopNeed(e)
	if e.keep then return math.max(0, (e.qty or 0) - X.ShopOwned(e)) end
	return math.max(0, (e.qty or 0) - (e.bought or 0))
end
-- the cost to buy the rest: from the last search of the item (offers not yours, at most the max price), else the
-- lowest price of the last scan; second value = how many can be had (nil if only estimated)
function X.ShopCost(e)
	local need = X.ShopNeed(e)
	if need == 0 then return 0, 0 end
	if X.live[e.key] then
		local plan = X.BuyPlan(e.key, need, e.max)
		if not plan then return nil, 0 end
		if plan.commodity then return plan.total, plan.qty end
		local total, n = 0, 0
		for _, o in ipairs(plan.offers) do
			-- the whole auction: its price of one x how many (an auction's buyout is the price of ONE)
			if n + o.qty <= need then total = total + (o.total or o.unit * o.qty) n = n + o.qty end
		end
		return total, n
	end
	local low = X.Price(e.key, "min")
	if low and (not e.max or low <= e.max) then return low * need, nil end
	return nil, nil
end
-- buy the rest of one entry (the purchase panel then needs clicks)
function X.ShopBuy(listName, key)
	local e = X.ShopEntry(listName, key)
	if not e then return end
	X.BuyStart(key, X.ShopNeed(e), e.max, "shop", listName)
end

-- purchases of a list count on it
X.On("XNAH_BOUGHT", function(key, qty, total, source, tag)
	if source ~= "shop" then return end
	local e = X.ShopEntry(tag, key)
	if e then
		e.bought = (e.bought or 0) + (qty or 0) -- counted in keep mode too, but there it does not decide the need
		changed()
	end
end)
