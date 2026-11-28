-- The double-click on a tracked item (Items view) runs the game's OWN auction house search, exactly as if you had
-- pressed its Search button yourself.
-- Why this way: a search started by XNAH's own code (calling the game's search functions, or pressing its button from
-- XNAH's code) marks the game's auction house code as "touched by an addon", and the game later refuses its own
-- protected actions (v0.9.0: the bank opened empty). The game has one way for an addon to press one of its buttons
-- cleanly: a "secure" button of the game's own kind (SecureActionButtonTemplate) with type = "click" and
-- clickbutton = the button to press. When you click that secure button with the mouse, the game's own code presses
-- the other button for you - XNAH's code is not part of that press.
-- How it works here:
--   * ONE such button, made once (out of combat), lies over the tracked item under the mouse while the game's auction
--     house is open. It is a child of the whole screen (UIParent) and placed by screen position, not tied to XNAH's
--     window, so XNAH's window never becomes "protected" itself.
--   * Everything you do on it is passed on to the row below: the hover (tooltip), a click (shows the item), a
--     right-click (the item menu), pressing and dragging (your own order).
--   * Its "PreClick" (XNAH's code, run by the game just BEFORE the secure part of a click, on its own) tells a
--     double-click from a click: on the second click on the same item within X.DOUBLE_CLICK seconds it puts the
--     item's name into the game's search box and sets type = "click" on OUR button. The secure part then presses the
--     game's Search button; the game's own StartSearch reads the box and searches (and goes back to its list from an
--     item's page). "PostClick" clears type again, so any other click does nothing in the secure part.
--   * In combat the game allows no changes to secure buttons: then it hides (when combat starts) and is not shown;
--     the rows work as before (their own double-click: X.ShowOnAuctionHouse). After combat it is placed again.
-- Only XNAH's own button is changed; the game's Search button is only named in its "clickbutton" setting.
local ADDON, X = ...
local UI = X.UI

local catcher    -- the one secure button
local tbl, opts  -- the tracked list it serves; opts.dragged() = true for the click that ends a drag
local over       -- the row frame it lies over now
local placed     -- where it was put ("left,bottom,width,height" in screen units)
local last       -- the last left click that was a click: {row, key, t}
local stuck      -- it could not be hidden (combat had already started): hidden after combat

local function inCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function run(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then X.OnError(err) end
end
local function buttonsHeld()
	return IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and true or false
end

-- the game's search box and Search button, while its auction house window is open (plain fields read only)
local function searchBar()
	local f = AuctionHouseFrame
	if not (X.ahOpen and type(f) == "table" and f.IsShown and X.Try(f.IsShown, f)) then return nil end
	local bar = f.SearchBar
	if type(bar) ~= "table" then return nil end
	local box, button = bar.SearchBox, bar.SearchButton
	if type(box) ~= "table" or type(button) ~= "table" then return nil end
	return box, button
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

-- the double-click: the name into the game's box, then the secure part presses its Search button. false: not
-- possible now (the old way runs instead)
local function searchSecure(self, key)
	if inCombat() then return false end
	local box, button = searchBar()
	if not box then return false end
	if not (X.Try(box.IsVisible, box) and X.Try(button.IsVisible, button)) then return false end -- (Sell / Auctions tabs)
	if button.IsEnabled and X.Try(button.IsEnabled, button) == false then return false end
	local name = X.AHSearchName(key)
	if not name then return true end -- (said why)
	if not pcall(box.SetText, box, name) then return false end
	self:SetAttribute("clickbutton", button)
	self:SetAttribute("type", "click")
	-- XNAH's own search of the item (for Buy cheapest now) waits for the answer of the game's search
	if X.HoldSearches then X.HoldSearches(3, true) end
	X.Print("searching the auction house for " .. X.ItemText(key) .. ".")
	return true
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
		if not searchSecure(self, key) then run(row:GetScript("OnDoubleClick"), row, "LeftButton") end -- (the old way)
		return
	end
	run(row:GetScript("OnClick"), row, button) -- a click, as on the row itself
	if button == "LeftButton" and not dragged and key then last = {row = row, key = key, t = now} else last = nil end
end
local function postClick(self)
	if not inCombat() and self:GetAttribute("type") ~= nil then self:SetAttribute("type", nil) end
end

local function make()
	if catcher then return catcher end
	if inCombat() then return nil end
	local ok, b = pcall(CreateFrame, "Button", "XNAHSearchClick", UIParent, "SecureActionButtonTemplate")
	if not ok or not b then return nil end
	b:Hide()
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
	b:SetScript("OnLeave", function()
		local r = over
		if r then run(r:GetScript("OnLeave"), r) end
		if not buttonsHeld() then hide() end
	end)
	-- while shown: goes away when the row, the auction house or the mouse leaves; follows the row if it moved
	b:SetScript("OnUpdate", function(self)
		if inCombat() then return end
		local r = over
		if not (r and r:IsVisible() and searchBar()) then hide() return end
		if not X.Try(self.IsMouseOver, self) and not buttonsHeld() then
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

-- after the list redrew (scrolling, sorting, a drag ended): the row the mouse is on now; a row gone: away
function UI.SearchClickCheck()
	if not tbl or inCombat() then return end
	if over and not over:IsVisible() then hide() end
	if not searchBar() then if catcher and catcher:IsShown() then hide() end return end
	if buttonsHeld() then return end
	for _, row in ipairs(tbl.rows) do
		if row ~= over and row:IsVisible() and X.Try(row.IsMouseOver, row) then UI.SearchClickPlace(row) return end
	end
end

-- the tracked list (UIItem.lua) hands its table over once it is built
function UI.SearchClickAttach(t, o)
	tbl, opts = t, o or {}
	t.onRowEnter = function(row)
		if over == row and catcher and catcher:IsShown() then return end
		UI.SearchClickPlace(row)
	end
end
UI.SearchClickButton = function() return catcher end -- (for the test scenes)

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
	if not open then last = nil hide() end
end)
