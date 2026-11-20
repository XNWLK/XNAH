-- Hourly web data: XNAH's PC tool (tools/api-fetch.js) fetches the whole auction house from the game's official web
-- API every hour and writes it into a small companion addon, XNAH_Data, which the game reads at login (new data needs a
-- /reload or a relog). Here the snapshots that are new since the last import are recorded like full scans: one price
-- point per item with the snapshot's time. X.Record never lets an older snapshot replace a newer price, and every
-- snapshot is imported only once (the time of the last one is kept per realm). Data source: Blizzard Entertainment.
--
-- XNAH_API = {v = 1, made = t, house = 111, region = "eu", faction = "Alliance", realm = "" (or "Realm 6946-Alliance"),
--   snapshots = {{t = t, n = items, auctions = n, items = "key,min,mkt,qty,auc;..."}, ...}}  (numbers in base 36)
-- Saved per realm: apiLast = time of the newest imported snapshot, apiInfo = {t, at, n, items, auctions, house}.
local ADDON, X = ...

X.api = {state = "none"}   -- none / wrong / waiting / importing / done
local SLICE = 300          -- items recorded per frame
local OLD_HOURS = 3        -- newer data than this is expected while the PC tool runs

local function n36(s)
	if s == nil or s == "" then return nil end
	return tonumber(s, 36)
end

-- the faction of a realm key ("Realm 93-Alliance" -> "Alliance")
local function factionOf(key)
	return key and key:match("%-([^%-]+)$")
end

local function newestOf(data)
	local t = nil
	for _, s in ipairs(data.snapshots) do
		if type(s) == "table" and tonumber(s.t) and (not t or s.t > t) then t = s.t end
	end
	return t
end

-- after the import: free the memory of the data (the game reads the file again at the next login or /reload)
local function release()
	_G.XNAH_API = nil
end

local function finish(list, newest)
	local r = X.Realm()
	local last = list[#list]
	r.apiLast = last.t
	r.apiInfo = {t = last.t, at = X.Now(), n = #list, items = last.n, auctions = last.auctions, house = X.api.house}
	table.insert(r.scans, {t = last.t, kind = "web data", items = last.n, auctions = last.auctions})
	while #r.scans > 200 do table.remove(r.scans, 1) end
	X.api.state = "done"
	X.api.imported = #list
	X.api.newest = newest
	X.Print("hourly web data: " .. #list .. " new snapshot" .. (#list > 1 and "s" or "") .. " recorded (newest from " ..
		X.Date(last.t, "%H:%M") .. ", " .. X.Num(last.n or 0) .. " items)")
	if X.FillNames then X.FillNames() end
	X.Fire("XNAH_SCAN")
	X.Fire("XNAH_PRICES")
end

-- reads XNAH_API (if XNAH_Data is installed) and records what is new; returns the number of snapshots to import
function X.ApiImport()
	local data = _G.XNAH_API
	if type(data) ~= "table" or type(data.snapshots) ~= "table" then
		X.api = {state = "none"}
		return 0
	end
	local key = X.realmKey or X.RealmKey()
	local newest = newestOf(data)
	X.api = {state = "done", house = data.house, made = data.made, newest = newest, imported = 0}
	-- data of another realm or faction is never mixed in
	local want = (data.realm and data.realm ~= "") and data.realm or nil
	if (want and want ~= key) or (not want and data.faction and data.faction ~= "" and data.faction ~= factionOf(key)) then
		X.api.state = "wrong"
		X.api.forWhom = want or ((data.faction == "Neutral" and "the neutral" or ("the " .. tostring(data.faction))) .. " auction house")
		release()
		return 0
	end
	local r = X.Realm()
	local list = {}
	for _, s in ipairs(data.snapshots) do
		if type(s) == "table" and tonumber(s.t) and type(s.items) == "string" and s.t > (r.apiLast or 0) then list[#list + 1] = s end
	end
	release()
	if #list == 0 then return 0 end
	table.sort(list, function(a, b) return a.t < b.t end)
	X.api.state = "importing"
	X.api.total, X.api.done = #list, 0
	local si, pos = 1, 1
	local seen, gone, g = nil, nil, 0
	X.Job("web data", function()
		local s = list[si]
		if s then
			local text = s.items
			local isLast = si == #list
			if isLast and not seen then seen = {} end
			local n = 0
			while n < SLICE and pos <= #text do
				local stop = text:find(";", pos, true) or (#text + 1)
				local k, a, b, c, d = text:sub(pos, stop - 1):match("^([^,]+),([^,]*),([^,]*),([^,]*),([^,]*)$")
				pos = stop + 1
				if k then
					local it = X.Record(k, s.t, n36(a), n36(b), n36(c) or 0, n36(d) or 0)
					if it.cur and it.cur.t == s.t then it.cur.web = 1 end -- marked: hourly web data
					if isLast then seen[k] = true end
				end
				n = n + 1
			end
			if pos > #text then
				si, pos = si + 1, 1
				X.api.done = si - 1
				r.apiLast = s.t -- a snapshot is never imported twice, even if the game closes half-way
			end
			return false
		end
		-- the newest snapshot is the whole auction house: an item not in it is sold out (as after a full scan)
		local last = list[#list]
		if (last.n or 0) < 50 or newest ~= last.t then return true end
		if not gone then
			gone = {}
			for k in pairs(X.Items()) do if not seen[k] then gone[#gone + 1] = k end end
		end
		local stop = math.min(#gone, g + SLICE)
		while g < stop do
			g = g + 1
			X.RecordGone(gone[g], last.t)
		end
		return g >= #gone
	end, function()
		finish(list, newest)
	end)
	return #list
end

X.On("XNAH_LOGIN", function()
	if type(_G.XNAH_API) ~= "table" then return end
	X.api = {state = "waiting"}
	X.After(3, X.ApiImport)
end)

-- one line for the Settings page
function X.ApiStatus()
	local a = X.api or {}
	local r = X.db and X.Realm()
	local info = r and r.apiInfo
	if a.state == "waiting" then return "Hourly web data: read after login ..." end
	if a.state == "importing" then
		return "Hourly web data: recording snapshot " .. math.min((a.done or 0) + 1, a.total or 1) .. " of " .. (a.total or 1) .. " ..."
	end
	if a.state == "wrong" then
		return "Hourly web data: the PC tool's data is for " .. tostring(a.forWhom) .. " - not used here."
	end
	if a.state == "none" and not info then
		return "Hourly web data: not set up (the PC tool and the XNAH_Data folder - see the README)."
	end
	local newest = a.newest or (info and info.t)
	local text = "Hourly web data: newest from " .. X.Date(newest, "%b %d %H:%M") .. " (" .. X.Ago(newest) .. ")"
	if info and info.items then text = text .. ", " .. X.Num(info.items) .. " items" end
	if a.state == "done" then
		text = text .. ((a.imported or 0) > 0 and ("; " .. a.imported .. " new at this login") or "; nothing new at this login")
	else
		text = text .. "; XNAH_Data not loaded"
	end
	if newest and X.Now() - newest > OLD_HOURS * 3600 then text = text .. " - is the PC tool running?" end
	return text .. ". New data comes with /reload."
end
