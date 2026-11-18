-- The sniper: while the auction house is open and the sniper is on, every watched item with a max price is searched
-- one by one (one search about every 1.5 s), then it waits `snipeWait` seconds and starts again. A listing at or
-- under the max price is a hit: a sound, the game's icon flashes, a chat line, and it shows in the Hits list where it
-- can be bought with clicks (never by itself). It pauses while a scan runs, while you search yourself, and while a
-- purchase is going on.
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

local function alert(key, hit)
	if X.S().snipeSound and PlaySound then
		local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
		X.Try(PlaySound, kit, "Master")
	end
	if FlashClientIcon then X.Try(FlashClientIcon) end
	X.Print("|cffffd100sniper:|r " .. X.ItemText(key) .. " listed at " .. X.Money(hit.unit) .. " (your max " ..
		X.Money(hit.max) .. ", " .. X.Num(hit.qty) .. " available) - tab Buy")
	X.Fire("XNAH_SNIPE", key, hit)
end

-- looks at the answer of a search for hits
function X.SnipeCheck(key, live)
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
	local hit = {key = key, unit = best, qty = qty, total = total, max = max, t = X.Now(), commodity = live.commodity}
	s.hits[key] = hit
	-- new, cheaper or more than before: tell
	if not old or best < old.unit or qty > old.qty then alert(key, hit) else X.Fire("XNAH_SNIPE") end
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
