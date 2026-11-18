-- Start-up, slash commands, the key binding.
local ADDON, X = ...

X.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	X.InitDB()
	X.Fire("XNAH_READY")
end)
X.On("PLAYER_LOGIN", function()
	if not X.db then X.InitDB() end
	X.realmKey = X.RealmKey()
	X.MigrateRealms(X.realmKey)
	X.Realm()
	X.Fire("XNAH_LOGIN")
end)

local HELP = {
	"/xnah - open or close the window",
	"/xnah scan - full scan (auction house open; about every 15 minutes)",
	"/xnah watch - scan the watch list (auction house open)",
	"/xnah <item name or link> - show that item",
	"/xnah raw [n] - print the first n auctions of the last full scan as the game gives them (to check prices)",
	"/xnah guide - the guide to every page",
	"/xnah perf - what XNAH is doing and how much memory it uses",
	"/xnah debug - more messages",
	"/xnah forget - delete this realm's price data (asks first)",
}
SLASH_XNAH1 = "/xnah"
SlashCmdList.XNAH = function(msg)
	msg = X.Trim(msg or "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		if X.Toggle then X.Toggle() end
	elseif cmd == "scan" then
		X.FullScan(rest == "force")
	elseif cmd == "watch" then
		X.ScanItems()
	elseif cmd == "raw" then
		X.RawDump(tonumber(rest) or 5)
	elseif cmd == "perf" then
		X.Perf()
	elseif cmd == "guide" then
		if X.ShowGuide then X.ShowGuide() end
	elseif cmd == "debug" then
		X.S().debug = not X.S().debug
		X.Print("debug " .. (X.S().debug and "on" or "off"))
	elseif cmd == "forget" then
		if X.Confirm then
			X.Confirm("Delete all price data of " .. (X.realmKey or "this realm") .. "?", function()
				X.db.realms[X.realmKey or X.RealmKey()] = nil
				X.Realm()
				X.Fire("XNAH_PRICES")
				X.Print("price data deleted")
			end)
		end
	elseif cmd == "help" or cmd == "?" then
		for _, l in ipairs(HELP) do X.Print(l) end
	else
		-- an item: a link, or a name
		local key = X.KeyFromLink(msg)
		if not key then
			local found = X.Find(msg, 1)
			key = found[1]
		end
		if key and X.ShowItem then X.ShowItem(key)
		else X.Print("no item found for \"" .. msg .. "\" (/xnah help)") end
	end
end

-- key binding (Bindings.xml)
BINDING_HEADER_XNAH = "XNAH"
BINDING_NAME_XNAH_TOGGLE = "Open / close XNAH"
function XNAH_Toggle()
	if X.Toggle then X.Toggle() end
end
