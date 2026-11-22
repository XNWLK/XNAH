-- The sniper: while the auction house is open and the sniper is on, every watched item with a max price is searched
-- one by one (one search about every 1.5 s), then it waits `snipeWait` seconds and starts again. A listing at or
-- under the max price is a hit: a sound, the game's icon flashes, a chat line, and it shows in the Hits list where it
-- can be bought with clicks (never by itself). It pauses while a scan runs, while you search yourself, and while a
-- purchase is going on.
-- Price alerts (below the sniper's alert) work the same with the sniper off: any price data that comes in is checked.
local ADDON, X = ...

X.Default("snipeWait", 10)  -- seconds between two rounds
X.Default("snipeSound", true)

X.snipe = {on = false, hits = {}, round = 0, pos = 0}
local STEP = 1.5

-- watched items with a max price
function X.SnipeKeys()
	local out = {}
	for key in pairs(X.db.watch) do if X.WatchMax(key) then out[#out + 1] = key end end
	table.sort(out)
	return out
end
function X.SnipeHits()
	local out = {}
	for _, h in pairs(X.snipe.hits) do out[#out + 1] = h end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

-- why the sniper is waiting (nil = searching)
function X.SnipePause()
	local s = X.snipe
	if not s.on then return "off" end
	if not X.ahOpen then return "the auction house is closed" end
	if X.scan.state ~= "idle" then return "a scan is running" end
	local b = X.buy.state
	if b == "quoting" or b == "confirm" or b == "buying" then return "a purchase is going on" end
	if X.ForeignSearchAge() < 2 then return "you are searching" end
	if #X.SnipeKeys() == 0 then return "no watched items have a max price" end
	return nil
end

-- [[ price alerts ]] (also without the sniper) any price that comes in - a full scan, a watch list or item search, a
-- browse, a search of the Buy or Sell tab - is checked: a watched item with a max price listed at or under it gives a
-- chat line and a sound and goes into the Hits list (buy it from there with clicks; nothing is ever bought by itself).
-- The same item is told again only at a lower price, or after ALERT_AGAIN; never twice for the same reading.
X.Default("alertSound", true) -- a sound with a price alert (the sniper's own hits use snipeSound)
local ALERT_AGAIN = 30 * 60   -- seconds before the same item at the same or a higher price is told again
local FRESH = 15 * 60         -- a scan price older than this is not "listed now"
local told = {}               -- [key] = {unit, t (when told), obs (time of the reading)} - this session only
local sessionStart = math.huge -- readings from before this login are never told (they were, or are old)
X.On("XNAH_LOGIN", function() sessionStart = X.Now() end)

local function sound(on)
	if on and PlaySound then
		local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
		X.Try(PlaySound, kit, "Master")
	end
	if FlashClientIcon then X.Try(FlashClientIcon) end
end
local function remember(key, unit, obs)
	told[key] = {unit = unit, t = X.Now(), obs = obs}
end
-- may a reading of `key` at `unit` be told? (not the same reading twice; again at a lower price, or after 30 minutes)
local function mayTell(key, unit, obs)
	local m = told[key]
	if not m then return true end
	if obs and m.obs == obs then return false end
	if unit < m.unit then return true end
	return X.Now() - m.t >= ALERT_AGAIN
end
X.AlertMayTell = mayTell

local function alert(key, hit, label)
	if label then sound(X.S().alertSound) else sound(X.S().snipeSound) end
	X.Print("|cffffd100" .. (label or "sniper:") .. "|r " .. X.ItemText(key) .. " listed at " .. X.Money(hit.unit) ..
		" (your max " .. X.Money(hit.max) .. ", " .. X.Num(hit.qty) .. " available) - tab Buy")
	remember(key, hit.unit, hit.t)
	X.Fire("XNAH_SNIPE", key, hit)
end

-- looks at the answer of a search for hits (label nil = the sniper's own search; "price alert:" = any other search)
function X.SnipeCheck(key, live, label)
	local max = X.WatchMax(key)
	local s = X.snipe
	if not max or not live then return end
	local qty, best, total = 0, nil, 0
	for _, o in ipairs(live.offers) do
		if o.qty > 0 and o.unit <= max then
			qty = qty + o.qty
			total = total + o.unit * o.qty
			if not best or o.unit < best then best = o.unit end
		end
	end
	local old = s.hits[key]
	if qty == 0 then
		if old then s.hits[key] = nil X.Fire("XNAH_SNIPE") end
		return
	end
	local hit = {key = key, unit = best, qty = qty, total = total, max = max, t = live.t or X.Now(), commodity = live.commodity}
	s.hits[key] = hit
	-- the sniper: new, cheaper or more than before; any other search: a price alert (not twice, see mayTell)
	local tell
	if label then
		tell = mayTell(key, best, hit.t)
	else
		tell = not old or best < old.unit or qty > old.qty
	end
	if tell then alert(key, hit, label) else X.Fire("XNAH_SNIPE") end
end

-- prices from a scan, a browse or the game's search (Scan.lua fires XNAH_PRICES): the lowest price of each watched
-- item with a max price. A hit from these is only an estimate of how many (all listed are counted): when the auction
-- house is open the item is searched once, which puts the real offers in its hit.
local MAX_LINES = 5 -- more alerts at once: one line for the rest
function X.AlertCheckPrices()
	local now = X.Now()
	local s = X.snipe
	local new, changed = {}, false
	for _, key in ipairs(X.SnipeKeys()) do
		local max = X.WatchMax(key)
		local it = X.Items()[key]
		local cur = it and it.cur
		local obs = cur and cur.t
		local old = s.hits[key]
		if obs and obs >= sessionStart and now - obs <= FRESH then
			if (cur.qty or 0) > 0 and cur.min and cur.min <= max then
				-- a search of the item (its real offers) is kept unless this reading is newer and cheaper
				if not old or (old.est and obs >= old.t) or (obs > old.t and cur.min < old.unit) then
					s.hits[key] = {key = key, unit = cur.min, qty = cur.qty, total = cur.min * cur.qty, max = max, t = obs, est = true}
					changed = true
				end
				if mayTell(key, cur.min, obs) and not (old and not old.est and old.unit <= cur.min and old.t >= obs - 60) then
					new[#new + 1] = key
				end
			elseif old and old.t < obs then
				-- a newer reading shows nothing at or under the max any more
				s.hits[key] = nil
				changed = true
			end
		end
	end
	if #new > 0 then
		sound(X.S().alertSound)
		for i, key in ipairs(new) do
			local h = s.hits[key]
			remember(key, h.unit, h.t)
			if i <= MAX_LINES then
				X.Print("|cffffd100price alert:|r " .. X.ItemText(key) .. " listed at " .. X.Money(h.unit) .. " (your max " ..
					X.Money(h.max) .. ") - tab Buy")
			end
			-- the real offers (never while scanning; one search a second, never a purchase)
			if X.ahOpen and X.LiveSearch and X.SearchBlocked and not X.SearchBlocked() then X.LiveSearch(key) end
		end
		if #new > MAX_LINES then
			X.Print("|cffffd100price alert:|r and " .. (#new - MAX_LINES) .. " more watched items at or under your max - tab Buy")
		end
		X.Fire("XNAH_SNIPE", new[1], s.hits[new[1]])
	elseif changed then
		X.Fire("XNAH_SNIPE")
	end
	return new
end
X.On("XNAH_PRICES", function() X.AlertCheckPrices() end)

-- searches that were not the sniper's (Buy and Sell tabs, the searches above): their answers are checked too
local liveSeen = {} -- [key] = the answer last looked at
X.On("XNAH_LIVE", function()
	local b = X.buy
	for _, key in ipairs(X.SnipeKeys()) do
		local live = X.live[key]
		if live and liveSeen[key] ~= live and X.Now() - (live.t or 0) <= 60 then
			liveSeen[key] = live
			-- an item you are buying right now is not announced
			local buying = b and b.key == key and (b.state == "quoting" or b.state == "confirm" or b.state == "buying" or b.state == "ready")
			if not buying and X.snipe.current ~= key then X.SnipeCheck(key, live, "price alert:") end
		end
	end
end)

-- "Alert me when ... is listed at or under:" - sets the watch list max price (empty = no alert; the item stays watched)
function X.AskAlert(key)
	local K = X.K
	if not key or not K or not K.Ask then return end
	key = tostring(key)
	local cur = X.WatchMax(key)
	K.Ask("Alert me when " .. (X.ItemName(key) or key) .. " is listed at or under:", cur and X.MoneyPlain(cur) or "", false, function(text)
		local c = X.ParseMoney(text)
		if not X.Watched(key) then X.SetWatched(key, true) end
		X.SetWatchMax(key, c)
		if c and c > 0 then
			X.Print("price alert: " .. X.ItemText(key) .. " at or under " .. X.Money(c) .. " (from any scan or search)")
		else
			X.Print("price alert off for " .. X.ItemText(key) .. " (still on the watch list)")
		end
	end, "Set")
end

local function tick()
	local s = X.snipe
	if not s.on or not X.ahOpen then s.running = false return end
	local reason = X.SnipePause()
	if reason or GetTime() < (s.waitUntil or 0) or X.SearchQueueLength() > 0 then
		X.After(0.5, tick)
		return
	end
	local keys = X.SnipeKeys()
	s.pos = s.pos + 1
	local key = keys[s.pos]
	if not key then
		-- a round is done: wait, then again
		s.pos = 0
		s.round = s.round + 1
		s.waitUntil = GetTime() + math.max(1, X.S().snipeWait or 10)
		X.Fire("XNAH_SNIPE")
		X.After(0.5, tick)
		return
	end
	s.current = key
	X.LiveSearch(key, function(live)
		X.snipe.current = nil
		if live then liveSeen[key] = live end -- looked at here, not again as a price alert
		X.SnipeCheck(key, live)
	end)
	X.After(STEP, tick)
end

function X.SnipeStart()
	local s = X.snipe
	s.on = true
	s.pos, s.waitUntil = 0, 0
	if not s.running then
		s.running = true
		tick()
	end
	X.Fire("XNAH_SNIPE")
end
function X.SnipeStop()
	X.snipe.on = false
	X.Fire("XNAH_SNIPE")
end
function X.SnipeToggle(on)
	if on == nil then on = not X.snipe.on end
	if on then X.SnipeStart() else X.SnipeStop() end
end
-- buy what a hit offers (the purchase panel then needs clicks)
function X.SnipeBuy(key)
	local h = X.snipe.hits[key]
	if not h then return end
	X.BuyStart(key, h.qty, h.max, "snipe", key)
end

-- the auction house opens: the sniper keeps its on / off from before (stops when it closes)
X.On("XNAH_AH", function(open)
	local s = X.snipe
	if open and s.on and not s.running then
		s.running = true
		s.pos, s.waitUntil = 0, 0
		X.After(1, tick)
	end
	X.Fire("XNAH_SNIPE")
end)
-- something bought from a hit: what is left is checked again by the next search
X.On("XNAH_BOUGHT", function(key, qty, total, source)
	local h = X.snipe.hits[key]
	if h then
		h.qty = h.qty - (qty or 0)
		if h.qty <= 0 then X.snipe.hits[key] = nil end
		X.Fire("XNAH_SNIPE")
	end
end)
