-- The double-click on a tracked item (Items view) runs the game's OWN auction house search, exactly as if you had
-- pressed its Search button yourself; a click after that search (or a double-click while the game's list already shows
-- the item) opens the item's own page in the game's window, exactly as if you had clicked its row there.
-- Why this way: a search started by XNAH's own code (calling the game's search functions, or pressing its button from
-- XNAH's code) marks the game's auction house code as "touched by an addon", and the game later refuses its own
-- protected actions (v0.9.0: the bank opened empty). The game has one way for an addon to press one of its buttons
-- cleanly: a "secure" button of the game's own kind (SecureActionButtonTemplate) with type = "click" and
-- clickbutton = the button to press. When you click that secure button with the mouse, the game's own code presses
-- the other button for you - XNAH's code is not part of that press.
-- How it works here:
--   * ONE such button, made once (out of combat), lies over the tracked item under the mouse while the game's auction
--     house is open. It is a child of the whole screen (UIParent) and placed by screen position, not tied to XNAH's
--     window, so XNAH's window never becomes "protected" itself. It is laid over a row when the mouse comes onto it,
--     after each redraw of the list, and by a small watcher (10 times a second, only while the auction house is open)
--     that finds the row under the mouse when no hover told us (the mouse already on a row, the button gone away).
--   * Everything you do on it is passed on to the row below: the hover (tooltip), a click (shows the item), a
--     right-click (the item menu), pressing and dragging (your own order).
--   * Its "PreClick" (XNAH's code, run by the game just BEFORE the secure part of a click, on its own) tells a
--     double-click from a click: on the second click on the same item within X.DOUBLE_CLICK seconds it
--       - does nothing when the game's window already shows that item's own page;
--       - sets clickbutton = the game's own row of that item when the game's list shows it (exactly one row): the
--         game's own row click opens its page (Blizzard_AuctionHouseItemList.lua OnClick -> SelectBrowseResult);
--       - else puts the item's name into the game's search box and sets clickbutton = the game's Search button; the
--         game's own StartSearch reads the box and searches (and goes back to its list from an item's page).
--     When the answer to that search shows the item in exactly one row, the next click on that item (within
--     ARM_TIME) presses that row: its page opens (a one-time chat line says so).
--     "PostClick" clears type again, so any other click does nothing in the secure part.
--   * In combat the game allows no changes to secure buttons: then it hides (when combat starts) and is not shown;
--     the rows work as before (their own double-click: X.ShowOnAuctionHouse). After combat it is placed again.
--   * /xnah dc prints what it is doing (Core.lua); /xnah dc on prints a line for each double-click.
-- Only XNAH's own button is changed; the game's frames are only read (plain fields and GetChildren), never written,
-- and only named in our button's "clickbutton" setting.
local ADDON, X = ...
local UI = X.UI

local ARM_TIME = 60    -- seconds: a click after the search opens the item's page within this time
local EXPECT_TIME = 6  -- seconds: the answer of the search must come within this time to arm that click
local WATCH_EVERY = 0.1

local catcher    -- the one secure button
local watcher    -- XNAH's own plain frame: finds the row under the mouse while the auction house is open
local tbl, opts  -- the tracked list it serves; opts.dragged() = true for the click that ends a drag
local over       -- the row frame it lies over now
local placed     -- where it was put ("left,bottom,width,height" in screen units)
local last       -- the last left click that was a click: {row, key, t, on = "button" or "row"}
local stuck      -- it could not be hidden (combat had already started): hidden after combat
local passing    -- PreClick is passing a click on to the row (then it is not a click that reached the row itself)
local viaPre     -- PreClick is running the row's own double-click (the old way)
local armed      -- {key, t}: the next click on this item opens its page in the game's window
local expect     -- {key, t}: a search of this item went out; armed when its answer shows the item in one row
local hinted     -- the one-time chat line about "click once more" was said (this session)
local live       -- /xnah dc on: a chat line for each double-click
local diag       -- the last double-click: {t, key, path, why, outcome}

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function run(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then X.OnError(err) end
end
local function buttonsHeld()
	return IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and true or false
end
local function itemText(key) return key and X.ItemText and X.ItemText(key) or tostring(key) end

-- [[ what happened: /xnah dc ]]
local function note(path, why, key)
	diag = {t = GetTime(), key = key, path = path, why = why}
	if live then X.Print("double-click on " .. itemText(key) .. ": " .. path .. " - " .. tostring(why)) end
end
-- (Scan.lua: what the old way did next)
function X.DcOutcome(text)
	if not diag or GetTime() - diag.t > 5 then return end
	diag.outcome = text
	if live then X.Print("  then: " .. tostring(text)) end
end

-- [[ the game's window, read only ]]
local function ahFrame()
	local f = AuctionHouseFrame
	if X.ahOpen and type(f) == "table" and f.IsShown and X.Try(f.IsShown, f) then return f end
	return nil
end
-- the game's search box and Search button, while its auction house window is open (plain fields read only)
local function searchBar()
	local f = ahFrame()
	if not f then return nil end
	local bar = f.SearchBar
	if type(bar) ~= "table" then return nil end
	local box, button = bar.SearchBox, bar.SearchButton
	if type(box) ~= "table" or type(button) ~= "table" then return nil end
	return box, button
end
local function isTable(v) return type(v) == "table" end
local function shown(fr) return isTable(fr) and fr.IsShown and X.Try(fr.IsShown, fr) and true or false end
local function visible(fr) return isTable(fr) and fr.IsVisible and X.Try(fr.IsVisible, fr) and true or false end
-- the game's row data (a browse result: {itemKey = {itemID, itemSuffix ...}}) is of this item
local function isItem(itemKey, key)
	if not isTable(itemKey) or not X.KeyOfItemKey then return false end
	local ok, k = pcall(X.KeyOfItemKey, {itemID = X.Plain(itemKey.itemID), itemSuffix = X.Plain(itemKey.itemSuffix)})
	return ok and k ~= nil and k == key
end
-- the game's window shows this item's own page
local function onPageOf(f, key)
	local mode = X.AHModeName and X.AHModeName(f)
	local id = X.KeyID(key)
	if mode == "ItemBuy" then
		local page = f.ItemBuyFrame
		return shown(page) and isItem(page.itemKey, key)
	elseif mode == "CommoditiesBuy" then
		local page = f.CommoditiesBuyFrame
		local list = isTable(page) and page.ItemList
		return shown(page) and isTable(list) and id ~= nil and X.Plain(list.itemID) == id
	end
	return false
end
-- how many rows of the game's list (all of them, also those scrolled away) are this item
local function resultsOf(f, key)
	local brf = f.BrowseResultsFrame
	local results = isTable(brf) and brf.browseResults
	if not isTable(results) then return 0 end
	local n = 0
	for _, r in ipairs(results) do
		if isTable(r) and isItem(r.itemKey, key) then n = n + 1 end
	end
	return n
end
-- the game's own row button of this item in its list, when the list shows exactly one row of it (nil + why)
local function resultRow(key)
	local f = ahFrame()
	if not f then return nil, "the auction house is not open" end
	if not (X.AHOnItemList and X.AHOnItemList(f)) then return nil, "the game's window is not on its list" end
	local n = resultsOf(f, key)
	if n == 0 then return nil, "the game's list does not hold it" end
	if n > 1 then return nil, "the game's list holds it " .. n .. " times" end
	local list = isTable(f.BrowseResultsFrame) and f.BrowseResultsFrame.ItemList
	local sb = isTable(list) and list.ScrollBox
	local target = isTable(sb) and sb.ScrollTarget
	if not (isTable(target) and target.GetChildren) then return nil, "the game's list rows were not found" end
	-- (the rows are re-used for other items on scrolling and sorting: the one that shows this item now)
	for _, row in ipairs({X.Try(target.GetChildren, target)}) do
		if isTable(row) and visible(row) and isTable(row.rowData) and isItem(row.rowData.itemKey, key) and row.Click then
			if row.IsEnabled and X.Try(row.IsEnabled, row) == false then return nil, "its row in the game's list is switched off" end
			return row
		end
	end
	return nil, "its row is scrolled out of sight in the game's list"
end

-- the item of a row of the tracked list
local function keyOf(row)
	if not (tbl and row) then return nil end
	for i, r in ipairs(tbl.rows) do
		if r == row then
			local item = tbl.items[i + tbl.offset]
			return item and item.key
		end
	end
end
local function rowIndex(row)
	if not (tbl and row) then return nil end
	for i, r in ipairs(tbl.rows) do if r == row then return i end end
end

local function hide()
	if not catcher then return true end
	if inCombat() then
		if catcher:IsShown() then stuck = true end
		return false
	end
	if over then X.Try(over.UnlockHighlight, over) end
	over, placed, stuck = nil, nil, false
	if catcher:GetAttribute("type") ~= nil then catcher:SetAttribute("type", nil) end
	if catcher:IsShown() then catcher:Hide() end
	catcher:ClearAllPoints()
	return true
end

-- the secure part presses this button (the game's Search button, or the game's own row of an item)
local function press(self, button)
	self:SetAttribute("clickbutton", button)
	self:SetAttribute("type", "click")
end
-- the item's own page: the game's own row of it pressed by the secure part
local function openPage(self, row, key)
	if inCombat() then return false end
	press(self, row)
	armed, expect = nil, nil
	-- (XNAH's own search of the item waits: the game's page searches it first)
	if X.HoldSearches then X.HoldSearches(2) end
	return true
end
-- the search: the name into the game's box, then the secure part presses its Search button. false + why: not possible
-- now (the old way runs instead)
local function searchSecure(self, key)
	if inCombat() then return false, "in combat" end
	local box, button = searchBar()
	if not box then return false, "the game's search bar was not found" end
	if not visible(box) then return false, "the game's search box is not shown (Sell or Auctions tab)" end
	if not visible(button) then return false, "the game's Search button is not shown" end
	if button.IsEnabled and X.Try(button.IsEnabled, button) == false then return false, "the game's Search button is switched off" end
	local name = X.AHSearchName(key)
	if not name then return true, "no name to search (said in chat)" end
	if not pcall(box.SetText, box, name) then return false, "the name could not go into the game's search box" end
	press(self, button)
	armed, expect = nil, {key = key, t = GetTime()}
	-- XNAH's own search of the item (for Buy cheapest now) waits for the answer of the game's search
	if X.HoldSearches then X.HoldSearches(3, true) end
	X.Print("searching the auction house for " .. X.ItemText(key) .. ".")
	return true, "pressed the game's Search button"
end
-- the old way (XNAH's own search, or the name in the box for Enter): the row's own double-click
local function oldWay(row, key, why)
	note("old way", why, key)
	expect = {key = key, t = GetTime()}
	viaPre = true
	run(row:GetScript("OnDoubleClick"), row, "LeftButton")
	viaPre = false
end
local function doubleClick(self, row, key)
	if inCombat() then oldWay(row, key, "in combat (the game allows no changes to secure buttons)") return end
	local f = ahFrame()
	if f and onPageOf(f, key) then
		armed = nil
		note("secure button", "the game's window already shows its page: nothing to do", key)
		return
	end
	local gameRow = resultRow(key)
	if gameRow and openPage(self, gameRow, key) then
		note("secure button", "the game's list shows it: pressed its row there (its page opens)", key)
		return
	end
	local ok, why = searchSecure(self, key)
	if ok then note("secure button", why, key) return end
	oldWay(row, key, why)
end

local function preClick(self, button)
	if not inCombat() and self:GetAttribute("type") ~= nil then self:SetAttribute("type", nil) end
	local row = over
	if not (row and row:IsVisible()) then last = nil return end
	local key = keyOf(row)
	local dragged = opts and opts.dragged and opts.dragged() or false
	local now = GetTime()
	if button == "LeftButton" and not dragged and last and last.row == row and last.key == key and key
		and now - last.t <= X.DOUBLE_CLICK then
		last = nil
		doubleClick(self, row, key)
		return
	end
	passing = true
	run(row:GetScript("OnClick"), row, button) -- a click, as on the row itself
	passing = false
	if button == "LeftButton" and not dragged and key then
		last = {row = row, key = key, t = now, on = "button"}
		-- the click after a search that found it: its page in the game's window
		if armed and armed.key == key and now - armed.t <= ARM_TIME and not inCombat() then
			local gameRow, why = resultRow(key)
			if gameRow and openPage(self, gameRow, key) then
				note("secure button", "a click after the search: pressed its row in the game's list (its page opens)", key)
			else
				armed = nil
				if live then X.Print("click on " .. itemText(key) .. ": its page cannot open - " .. tostring(why)) end
			end
		end
	else
		last = nil
	end
end
local function postClick(self)
	if not inCombat() and self:GetAttribute("type") ~= nil then self:SetAttribute("type", nil) end
end

local function mouseOn(self, r)
	return X.Try(self.IsMouseOver, self) or (r and X.Try(r.IsMouseOver, r)) or false
end

local function make()
	if catcher then return catcher end
	if inCombat() then return nil end
	local ok, b = pcall(CreateFrame, "Button", "XNAHSearchClick", UIParent, "SecureActionButtonTemplate")
	if not ok or not b then return nil end
	b:Hide()
	b:EnableMouse(true)
	-- a click acts when the mouse button is let go, once: only "up" clicks reach it, and useOnKeyDown = false makes the
	-- secure part act on "up" whatever the game's setting "cast on key down" (ActionButtonUseKeyDown) is
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetAttribute("useOnKeyDown", false)
	b:SetScript("PreClick", preClick)
	b:SetScript("PostClick", postClick)
	-- pressing and letting go: passed on to the row (dragging your own order)
	b:SetScript("OnMouseDown", function(_, button) local r = over if r then run(r:GetScript("OnMouseDown"), r, button) end end)
	b:SetScript("OnMouseUp", function(_, button) local r = over if r then run(r:GetScript("OnMouseUp"), r, button) end end)
	b:SetScript("OnEnter", function() local r = over if r then run(r:GetScript("OnEnter"), r) end end)
	b:SetScript("OnLeave", function(self)
		local r = over
		if r then run(r:GetScript("OnLeave"), r) end
		if not buttonsHeld() and not (r and X.Try(r.IsMouseOver, r)) then hide() end
	end)
	-- while shown: goes away when the row, the auction house or the mouse leaves; follows the row if it moved. "The
	-- mouse left" = neither on the button nor on its row (a button placed this very frame may not know its own place
	-- yet; the row does)
	b:SetScript("OnUpdate", function(self)
		if inCombat() then return end
		local r = over
		if not (r and r:IsVisible() and searchBar()) then hide() return end
		if not mouseOn(self, r) and not buttonsHeld() then
			run(r:GetScript("OnLeave"), r)
			hide()
			return
		end
		UI.SearchClickPlace(r)
	end)
	catcher = b
	return b
end

-- lays the secure button over a row of the tracked list (out of combat, while the auction house is open)
function UI.SearchClickPlace(row)
	if not (tbl and row) or inCombat() then return end
	if not row:IsVisible() or not searchBar() then hide() return end
	if row ~= over and buttonsHeld() then return end -- (not while a button is held: a drag goes on)
	if not keyOf(row) then hide() return end
	if not make() then return end
	local l, b, w, h = row:GetLeft(), row:GetBottom(), row:GetWidth(), row:GetHeight()
	local screen = UIParent:GetEffectiveScale()
	if not (l and b and w and h and screen and screen > 0) then return end
	local s = (row:GetEffectiveScale() or 1) / screen
	local where = string.format("%.1f,%.1f,%.1f,%.1f", l * s, b * s, w * s, h * s)
	if over ~= row then
		if over then X.Try(over.UnlockHighlight, over) end
		over = row
	end
	if where ~= placed then
		catcher:ClearAllPoints()
		catcher:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * s, b * s)
		catcher:SetSize(w * s, h * s)
		placed = where
	end
	local strata = row:GetFrameStrata()
	if strata and catcher:GetFrameStrata() ~= strata then catcher:SetFrameStrata(strata) end
	local level = (row:GetFrameLevel() or 1) + 20
	if catcher:GetFrameLevel() ~= level then catcher:SetFrameLevel(level) end
	X.Try(row.LockHighlight, row) -- (the row looks hovered: the mouse is on the button above it)
	if not catcher:IsShown() then catcher:Show() end
end

-- after the list redrew (scrolling, sorting, a drag ended), and from the watcher: the row the mouse is on now; a row
-- gone: away
function UI.SearchClickCheck()
	if not tbl or inCombat() then return end
	if over and not over:IsVisible() then hide() end
	if not searchBar() then if catcher and catcher:IsShown() then hide() end return end
	if buttonsHeld() then return end
	if catcher and catcher:IsShown() and over and X.Try(over.IsMouseOver, over) then return end
	for _, row in ipairs(tbl.rows) do
		if row ~= over and row:IsVisible() and X.Try(row.IsMouseOver, row) then UI.SearchClickPlace(row) return end
	end
end

-- a click that reached the row ITSELF (the secure button was not over it; the tracked list's OnClick calls this).
-- Returns true when it was the second click of a double-click whose first click was on the secure button (then the
-- old way ran). Also lays the secure button over that row, so a second click goes to it.
function UI.SearchClickRowClick(row, key, button)
	if passing or not tbl then return false end
	if button ~= "LeftButton" or not key then last = nil return false end
	local now = GetTime()
	if last and last.on == "button" and last.row == row and last.key == key and now - last.t <= X.DOUBLE_CLICK then
		last = nil
		viaPre = true -- (the reason is said here, not by the row's double-click)
		note("old way", "the second click landed on the row (the secure button moved or went away after the first)", key)
		expect = {key = key, t = now}
		run(row:GetScript("OnDoubleClick"), row, "LeftButton")
		viaPre = false
		return true
	end
	last = {row = row, key = key, t = now, on = "row"}
	if not inCombat() and ahFrame() then UI.SearchClickPlace(row) end
	return false
end

-- why the row itself got a double-click (the secure button did not catch it)
local function whyRow(row)
	if inCombat() then return "in combat (the secure button stays hidden then)" end
	if not ahFrame() then return "the auction house is not open" end
	if not catcher then return "the secure button was not made yet (it is made when the mouse comes onto a tracked item with the auction house open)" end
	if not catcher:IsShown() then return "the secure button was hidden at that moment" end
	if over ~= row then return "the secure button lay over another row" end
	return string.format("the secure button lay over this row, but the row got the clicks (button %s level %s, row %s level %s)",
		tostring(X.Try(catcher.GetFrameStrata, catcher)), tostring(X.Try(catcher.GetFrameLevel, catcher)),
		tostring(X.Try(row.GetFrameStrata, row)), tostring(X.Try(row.GetFrameLevel, row)))
end

-- the tracked list (UIItem.lua) hands its table over once it is built
function UI.SearchClickAttach(t, o)
	tbl, opts = t, o or {}
	t.onRowEnter = function(row)
		if over == row and catcher and catcher:IsShown() then return end
		UI.SearchClickPlace(row)
	end
	-- the row's own double-click (the old way): when it is not run by PreClick, the row itself got the clicks
	local own = t.onDoubleClick
	if type(own) == "function" and not t.xnahDcWrapped then
		t.xnahDcWrapped = true
		t.onDoubleClick = function(r, rowFrame)
			if not viaPre then
				note("old way", whyRow(rowFrame), r and r.key)
				expect = r and r.key and {key = r.key, t = GetTime()} or nil
			end
			return own(r, rowFrame)
		end
	end
end
UI.SearchClickButton = function() return catcher end -- (for the test scenes)

-- the watcher: XNAH's own plain frame, shown only while the auction house is open
local function watch()
	if watcher then return end
	watcher = CreateFrame("Frame")
	watcher:Hide()
	local wait = 0
	watcher:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - (elapsed or 0)
		if wait > 0 then return end
		wait = WATCH_EVERY
		if inCombat() or not tbl or not tbl:IsVisible() then return end
		UI.SearchClickCheck()
	end)
end

-- the answer to a search of the item: its row in the game's list -> the next click opens its page
X.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	local e = expect
	if not e then return end
	X.After(0.15, function() -- (the game's list fills first)
		if expect ~= e then return end
		expect = nil
		if GetTime() - e.t > EXPECT_TIME then return end
		local f = ahFrame()
		if not (f and X.AHOnItemList and X.AHOnItemList(f)) then return end
		local n = resultsOf(f, e.key)
		if n ~= 1 then
			if live then X.Print("the answer shows " .. itemText(e.key) .. " in " .. n .. " rows: a click does not open a page") end
			return
		end
		armed = {key = e.key, t = GetTime()}
		if live then X.Print("the answer shows " .. itemText(e.key) .. ": the next click on it opens its page") end
		if not hinted then
			hinted = true
			X.Print("click " .. X.ItemText(e.key) .. " once more in XNAH's list to open its page in the auction house.")
		end
	end)
end)

-- combat: the game allows no changes to secure buttons once it has started. The game sends PLAYER_REGEN_DISABLED just
-- before, so it is hidden then; if that was too late, it is hidden after combat. Until then the rows work as before.
X.On("PLAYER_REGEN_DISABLED", function()
	last = nil
	if catcher and catcher:IsShown() then hide() end
end)
X.On("PLAYER_REGEN_ENABLED", function()
	if catcher and (catcher:IsShown() or stuck) then hide() end
	X.After(0, function() if UI.SearchClickCheck then UI.SearchClickCheck() end end) -- (the row under the mouse again)
end)
X.On("XNAH_AH", function(open)
	if open then
		watch()
		watcher:Show()
		X.After(0, function() if UI.SearchClickCheck then UI.SearchClickCheck() end end) -- (the mouse already on a row)
	else
		last, armed, expect = nil, nil, nil
		if watcher then watcher:Hide() end
		hide()
	end
end)

-- [[ /xnah dc ]] one fact per line; only reads (the game's values and XNAH's own)
local function yes(v) return v and "yes" or "no" end
local function frameName(fr)
	if not isTable(fr) then return tostring(fr) end
	local n = X.Try(fr.GetDebugName, fr) or X.Try(fr.GetName, fr)
	return n and tostring(n) or "a frame without a name"
end
local function describeClick(v)
	if v == nil then return "none" end
	local f = AuctionHouseFrame
	local search = isTable(f) and isTable(f.SearchBar) and f.SearchBar.SearchButton
	if search and rawequal(v, search) then return "the game's Search button" end
	if isTable(v) and isTable(v.rowData) and isTable(v.rowData.itemKey) and X.KeyOfItemKey then
		local ok, k = pcall(X.KeyOfItemKey, v.rowData.itemKey)
		return "a row of the game's list (" .. (ok and k and itemText(k) or "?") .. ")"
	end
	return frameName(v)
end
local function cvar(name)
	local v
	if C_CVar and C_CVar.GetCVar then v = X.Try(C_CVar.GetCVar, name) end
	if v == nil and GetCVar then v = X.Try(GetCVar, name) end
	return v
end
function X.SearchClickReport(arg)
	arg = (arg or ""):lower()
	if arg == "on" then live = true X.Print("double-click lines on: each double-click on a tracked item says which way it went and why (/xnah dc off)") return end
	if arg == "off" then live = false X.Print("double-click lines off") return end
	local lines = {}
	local function add(fn)
		local ok, text = pcall(fn)
		lines[#lines + 1] = ok and tostring(text) or ("(could not read: " .. tostring(text) .. ")")
	end
	add(function() return "SearchClick.lua: loaded. Secure button: " .. (catcher and ("made (" .. frameName(catcher) .. ")") or "not made yet (made when the mouse comes onto a tracked item with the auction house open)") end)
	add(function()
		if not catcher then return "button shown: no" end
		local w, h = X.Try(catcher.GetWidth, catcher), X.Try(catcher.GetHeight, catcher)
		local l, b = X.Try(catcher.GetLeft, catcher), X.Try(catcher.GetBottom, catcher)
		return string.format("button shown: %s, size %s x %s, at left %s bottom %s (screen units)", yes(catcher:IsShown()),
			w and string.format("%.0f", w) or "?", h and string.format("%.0f", h) or "?",
			l and string.format("%.0f", l) or "?", b and string.format("%.0f", b) or "?")
	end)
	add(function()
		if not over then return "button lies over: no row" end
		local i = rowIndex(over)
		local l, b = X.Try(over.GetLeft, over), X.Try(over.GetBottom, over)
		local s = (X.Try(over.GetEffectiveScale, over) or 1) / (X.Try(UIParent.GetEffectiveScale, UIParent) or 1)
		return string.format("button lies over: row %s (%s), that row at left %s bottom %s (screen units)", tostring(i),
			itemText(keyOf(over)), l and string.format("%.0f", l * s) or "?", b and string.format("%.0f", b * s) or "?")
	end)
	add(function() return "mouse on the button: " .. yes(catcher and X.Try(catcher.IsMouseOver, catcher)) .. ", mouse on its row: " .. yes(over and X.Try(over.IsMouseOver, over)) .. ", mouse enabled: " .. yes(catcher and X.Try(catcher.IsMouseEnabled, catcher)) end)
	add(function()
		if type(GetMouseFoci) ~= "function" then return "under the mouse: (the game cannot tell)" end
		local names = {}
		local foci = X.Try(GetMouseFoci) -- (a list of the frames under the mouse, the top one first)
		if isTable(foci) and not foci.GetObjectType then
			for _, fr in ipairs(foci) do names[#names + 1] = frameName(fr) end
		elseif isTable(foci) then
			names[1] = frameName(foci)
		end
		return "under the mouse: " .. (#names > 0 and table.concat(names, ", ") or "nothing")
	end)
	add(function()
		local fr = UI.Frame and UI.Frame()
		return string.format("strata / level: button %s / %s, XNAH's window %s / %s, the row %s / %s",
			tostring(catcher and X.Try(catcher.GetFrameStrata, catcher) or "-"), tostring(catcher and X.Try(catcher.GetFrameLevel, catcher) or "-"),
			tostring(fr and X.Try(fr.GetFrameStrata, fr) or "-"), tostring(fr and X.Try(fr.GetFrameLevel, fr) or "-"),
			tostring(over and X.Try(over.GetFrameStrata, over) or "-"), tostring(over and X.Try(over.GetFrameLevel, over) or "-"))
	end)
	add(function() return "in combat: " .. yes(inCombat()) end)
	add(function()
		local f = AuctionHouseFrame
		return "auction house open: XNAH thinks " .. yes(X.ahOpen) .. ", the game's window shown " .. yes(isTable(f) and shown(f))
	end)
	add(function()
		local f = AuctionHouseFrame
		if not isTable(f) then return "the game's window shows: (not loaded yet)" end
		local mode = X.AHModeName and X.AHModeName(f)
		local onList = X.AHOnItemList and X.AHOnItemList(f)
		local text = mode == "Buy" and "its list" or (mode == "ItemBuy" or mode == "CommoditiesBuy") and "an item's page" or "another view"
		return "the game's window shows: " .. tostring(mode or "a view XNAH does not know") .. " (" .. text .. "); recognised as its list: " .. yes(onList)
	end)
	add(function()
		local f = AuctionHouseFrame
		local brf = isTable(f) and f.BrowseResultsFrame
		local res = isTable(brf) and brf.browseResults
		return "its list (BrowseResultsFrame) shown: " .. yes(shown(brf)) .. ", rows in it: " .. (isTable(res) and #res or "?")
	end)
	add(function()
		local f = AuctionHouseFrame
		local bar = isTable(f) and f.SearchBar
		local button = isTable(bar) and bar.SearchButton
		return "search bar shown: " .. yes(visible(bar)) .. ", Search button shown: " .. yes(visible(button)) .. ", switched on: " .. yes(isTable(button) and button.IsEnabled and X.Try(button.IsEnabled, button))
	end)
	add(function()
		local f = ahFrame()
		if not f then return "item pages: (auction house closed)" end
		local mode = X.AHModeName and X.AHModeName(f)
		if mode == "ItemBuy" and isTable(f.ItemBuyFrame) and isTable(f.ItemBuyFrame.itemKey) and X.KeyOfItemKey then
			local ok, k = pcall(X.KeyOfItemKey, f.ItemBuyFrame.itemKey)
			return "the page shown is of: " .. (ok and k and itemText(k) or "?")
		elseif mode == "CommoditiesBuy" and isTable(f.CommoditiesBuyFrame) and isTable(f.CommoditiesBuyFrame.ItemList) then
			local id = X.Plain(f.CommoditiesBuyFrame.ItemList.itemID)
			return "the page shown is of: " .. (id and itemText(tostring(id)) or "?")
		end
		return "the page shown is of: (no item page)"
	end)
	add(function() return "game setting ActionButtonUseKeyDown: " .. tostring(cvar("ActionButtonUseKeyDown")) .. "; the button's useOnKeyDown: " .. tostring(catcher and catcher:GetAttribute("useOnKeyDown")) end)
	add(function() return "the button's type: " .. tostring(catcher and catcher:GetAttribute("type")) .. ", clickbutton: " .. describeClick(catcher and catcher:GetAttribute("clickbutton")) end)
	add(function()
		if armed and GetTime() - armed.t <= ARM_TIME then
			local _, why = resultRow(armed.key)
			return string.format("next click opens the page of: %s (%d s left)%s", itemText(armed.key), math.floor(ARM_TIME - (GetTime() - armed.t)),
				why and (" - but now: " .. why) or "")
		end
		return "next click opens a page: no"
	end)
	add(function()
		if not diag then return "last double-click: none yet (since the last /reload)" end
		return string.format("last double-click: %d s ago on %s, way: %s - %s%s", math.floor(GetTime() - diag.t), itemText(diag.key), diag.path,
			tostring(diag.why), diag.outcome and ("; then: " .. diag.outcome) or "")
	end)
	add(function() return "a line for each double-click: " .. (live and "on (/xnah dc off)" or "off (/xnah dc on)") end)
	for _, l in ipairs(lines) do X.Print(l) end
	return lines
end
