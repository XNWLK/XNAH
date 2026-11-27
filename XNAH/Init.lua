-- XNAH: auction house prices for WoW Forever. Shared helpers: events, timers, money and time text, safe calls.
local ADDON, X = ...
XNAH = X -- one global, for /dump and the key binding

X.NAME = "XNAH"
X.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

-- [[ secret values ]] the client may hide values from addons (in combat); prices never are, but stay safe
function X.IsSecret(v)
	return issecretvalue ~= nil and issecretvalue(v) == true
end
function X.Plain(v)
	if X.IsSecret(v) then return nil end
	return v
end
-- calls f(...) and returns its results; on an error returns nil (errors about secret values are expected and dropped)
function X.Try(f, ...)
	local ok, a, b, c, d, e, f2, g, h, i, j, k, l, m, n, o, p, q, r = pcall(f, ...)
	if ok then return a, b, c, d, e, f2, g, h, i, j, k, l, m, n, o, p, q, r end
	if not tostring(a):find("secret") then X.Debug("error: " .. tostring(a)) end
	return nil
end

-- [[ output ]]
function X.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffe6b422XNAH|r " .. tostring(msg))
end
function X.Debug(msg)
	if XNAHDB and XNAHDB.settings and XNAHDB.settings.debug then X.Print("|cff999999" .. tostring(msg) .. "|r") end
end

-- [[ events ]] X.On("EVENT", fn) - every handler runs in its own protected call, so one error never stops the others.
-- Names starting with XNAH_ are the addon's own messages (X.Fire), not game events.
local eventFrame = CreateFrame("Frame")
local handlers = {}
local shownErrors = {}
local function onError(err)
	err = tostring(err)
	if err:find("secret") then return end
	if not shownErrors[err] then
		shownErrors[err] = true
		X.Print("|cffff5555error|r " .. err)
	end
end
X.OnError = onError
function X.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		if not event:find("^XNAH_") then
			local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
			if not ok then X.Debug("event not on this client: " .. event) end
		end
	end
	table.insert(handlers[event], fn)
end
-- time spent (ms, debugprofilestop) in XNAH's handlers and jobs: per second for the last 60 s, and the worst one
local perfSec, perfAt = {}, 0
local clock = debugprofilestop or function() return 0 end
local function spent(ms)
	local now = math.floor(GetTime())
	perfSec[now % 60] = (perfAt == now and (perfSec[now % 60] or 0) or 0) + ms
	if perfAt ~= now then
		for s = perfAt + 1, now - 1 do if now - s < 60 then perfSec[s % 60] = 0 end end
		perfAt = now
	end
	if ms > (X.perfWorst or 0) then X.perfWorst = ms end
end
function X.PerfTime()
	local now, sum = math.floor(GetTime()), 0
	for s = now - 59, now do if now - perfAt < 60 then sum = sum + (perfSec[s % 60] or 0) end end
	return sum
end
function X.Fire(event, ...)
	local list = handlers[event]
	if not list then return end
	local t0 = clock()
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then onError(err) end
	end
	spent(clock() - t0)
end
-- The auction house opening and closing reach XNAH one frame later. The game sends these two while its own code is
-- still busy opening or closing its window (closing it also tidies up the game's window manager, which the bank and
-- other windows use next). Running XNAH's handlers in the middle of that marks the game's code as "touched by an
-- addon", and then the game refuses its own protected actions later (the bank opened empty, v0.9.0). One frame later
-- the game has finished, so nothing of XNAH runs inside the game's own work.
X.LATER = {AUCTION_HOUSE_SHOW = true, AUCTION_HOUSE_CLOSED = true}
eventFrame:SetScript("OnEvent", function(_, event, ...)
	if X.LATER[event] then
		local n, args = select("#", ...), {...}
		C_Timer.After(0, function() X.Fire(event, unpack(args, 1, n)) end)
		return
	end
	X.Fire(event, ...)
end)

-- [[ timers ]]
function X.After(seconds, fn)
	C_Timer.After(seconds, function()
		local ok, err = pcall(fn)
		if not ok then onError(err) end
	end)
end
-- runs fn once, `seconds` after the last call with the same key
local debounce = {}
function X.Debounce(key, seconds, fn)
	local token = {}
	debounce[key] = token
	X.After(seconds, function()
		if debounce[key] == token then
			debounce[key] = nil
			fn()
		end
	end)
end
-- long jobs run a slice per frame so the game never stalls ("script ran too long"): step() returns true when done
local jobs = {}
local jobFrame = CreateFrame("Frame")
jobFrame:Hide()
jobFrame:SetScript("OnUpdate", function(self)
	local job = jobs[1]
	if not job then self:Hide() return end
	local t0 = clock()
	local ok, done = pcall(job.step)
	spent(clock() - t0)
	if not ok then onError(done) done = true end
	if done then
		table.remove(jobs, 1)
		if job.finish then local ok2, err = pcall(job.finish) if not ok2 then onError(err) end end
	end
end)
function X.Job(name, step, finish)
	jobs[#jobs + 1] = {name = name, step = step, finish = finish}
	jobFrame:Show()
end
function X.JobList()
	if #jobs == 0 then return "nothing" end
	local names = {}
	for i = 1, #jobs do names[i] = jobs[i].name end
	return table.concat(names, ", ")
end
function X.JobRunning(name)
	for i = 1, #jobs do if jobs[i].name == name then return true end end
	return false
end

-- [[ time ]]
function X.Now()
	return GetServerTime()
end
-- day number (days since 1970, server time) - history is kept per day
function X.Day(t)
	return math.floor((t or X.Now()) / 86400)
end
-- t may have a fraction of a second (old sale times worked out from a mail's days left): whole seconds only, as the
-- date() of newer Lua refuses a fraction
function X.Date(t, fmt)
	if not t then return "-" end
	return date(fmt or "%Y-%m-%d %H:%M", math.floor(t))
end
-- "5m ago", "3h ago", "2d ago"
function X.Ago(t)
	if not t then return "never" end
	local s = X.Now() - t
	if s < 60 then return "just now" end
	if s < 3600 then return math.floor(s / 60) .. "m ago" end
	if s < 86400 * 2 then return math.floor(s / 3600) .. "h ago" end
	return math.floor(s / 86400) .. "d ago"
end
function X.Clock(seconds)
	seconds = math.max(0, math.floor((seconds or 0) + 0.5))
	local m = math.floor(seconds / 60)
	return string.format("%d:%02d", m, seconds % 60)
end

-- [[ numbers and money ]]
function X.Num(n)
	n = math.floor((n or 0) + 0.5)
	local s = tostring(math.abs(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	return (n < 0 and "-" or "") .. out
end
function X.Round(n)
	return math.floor((n or 0) + 0.5)
end
local GOLD, SILVER, COPPER = "ffd100", "c7c7cf", "eda55f"
-- copper -> "12g 34s 56c" (coloured). opts.short: leave out copper above 1g and silver above 1000g
function X.Money(copper, short)
	if copper == nil then return "|cff666666-|r" end
	local neg = copper < 0
	copper = X.Round(math.abs(copper))
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = "|cff" .. GOLD .. X.Num(g) .. "g|r" end
	if s > 0 and not (short and g >= 1000) then parts[#parts + 1] = "|cff" .. SILVER .. s .. "s|r" end
	if c > 0 and not (short and g > 0) or #parts == 0 then parts[#parts + 1] = "|cff" .. COPPER .. c .. "c|r" end
	return (neg and "|cffff5555-|r" or "") .. table.concat(parts, " ")
end
-- the same without colours (for chat and text boxes)
function X.MoneyPlain(copper)
	if copper == nil then return "-" end
	return (X.Money(copper):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end
-- "12g 34s 56c", "12.5g", "1234s", "56c", "12g34s" -> copper; nil if it is not money
function X.ParseMoney(text)
	text = (text or ""):lower():gsub("%s+", "")
	if text == "" then return nil end
	if text:match("^%d+$") then return tonumber(text) * 10000 end -- a bare number = gold
	local total, any = 0, false
	for num, unit in text:gmatch("([%d%.]+)([gsc])") do
		local v = tonumber(num)
		if not v then return nil end
		any = true
		total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
	end
	if not any then return nil end
	return X.Round(total)
end
-- "+12%" green / "-8%" red
function X.Pct(p, invert)
	if p == nil then return "|cff666666-|r" end
	local good = (p >= 0) ~= (invert == true)
	local col = math.abs(p) < 0.5 and "aaaaaa" or (good and "4ade80" or "f87171")
	return "|cff" .. col .. (p >= 0 and "+" or "") .. string.format("%.0f", p) .. "%|r"
end
-- an arrow for a trend in % per week
function X.Arrow(p)
	if p == nil then return "" end
	if p >= 15 then return "|cff4ade80++|r" end
	if p >= 4 then return "|cff4ade80+|r" end
	if p <= -15 then return "|cfff87171" .. string.rep("-", 2) .. "|r" end -- two minus signs (written so, for tools/check-api.js)
	if p <= -4 then return "|cfff87171-|r" end
	return "|cffaaaaaa=|r"
end

-- [[ tables and text ]]
function X.Copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = X.Copy(v) end
	return out
end
function X.Trim(s)
	return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
function X.Contains(list, value)
	for i = 1, #(list or {}) do if list[i] == value then return i end end
	return nil
end

-- [[ items ]]
X.QUALITY_HEX = {[0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "00ccff"}
X.QUALITY_NAMES = {[0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom"}
function X.ItemIcon(id, size)
	size = size or 16
	local icon = id and C_Item and C_Item.GetItemIconByID and X.Try(C_Item.GetItemIconByID, id)
	return "|T" .. (icon or "Interface\\Icons\\INV_Misc_QuestionMark") .. ":" .. size .. ":" .. size .. "|t"
end
