-- Stand-in world: the game's secure buttons and combat (tests-45: the double-click that presses the auction house's
-- own Search button). Shaped like Blizzard_FrameXML SecureTemplates.xml / .lua on Forever:
--   * CreateFrame(..., "SecureActionButtonTemplate"): a protected button whose OnClick is the game's own
--     SecureActionButton_OnClick (run as the game's code, W.asGame). It acts on the press (down) when the attribute
--     "useOnKeyDown" is true, or when it is not set and the game's setting ActionButtonUseKeyDown (W.useKeyDown, on by
--     default as in the game) is on; else on letting go. type = "click": clickbutton:Click(button), still as the
--     game's code. W.secureActions lists every action it ran ("click" ...), W.secureClicks how often its OnClick ran.
--     Attributes are looked up like SecureButton_GetModifiedAttribute: "*type1" / "type1" / "*type*" / "type".
--   * Combat: W.enterCombat(late) - PLAYER_REGEN_DISABLED, then the lockdown (late = true: the lockdown first, then
--     the event); W.leaveCombat() - the lockdown ends, then PLAYER_REGEN_ENABLED. In combat a protected frame refuses
--     to be shown, hidden, moved, sized, re-parented or given attributes by an addon: the call does nothing, it is
--     written to W.blocked and ADDON_ACTION_BLOCKED is sent (as the game does). Making one in combat is refused too.
-- The order of a click (PreClick, OnClick, PostClick) is the stand-in's Frame:Click (tools/world.lua).

table.insert(W.onReset, function()
	W.combat = false
	W.useKeyDown = true
	W.blocked, W.secureActions, W.secureClicks = {}, {}, 0
end)

local SECURE = "SecureActionButtonTemplate"
local GUARDED = {"SetAttribute", "Show", "Hide", "SetShown", "SetPoint", "ClearAllPoints", "SetAllPoints", "SetSize",
	"SetWidth", "SetHeight", "SetParent", "EnableMouse", "SetFrameLevel", "SetFrameStrata", "SetScale", "RegisterForClicks"}

local function blocked(what)
	W.blocked[#W.blocked + 1] = what
	W.fire("ADDON_ACTION_BLOCKED", W.ADDON, what)
end

local function suffixOf(button)
	if button == "LeftButton" then return "1" elseif button == "RightButton" then return "2" elseif button == "MiddleButton" then return "3" end
	return ""
end
local function attr(f, name, button)
	local a = f.attr or {}
	local s = suffixOf(button)
	local v = a["*" .. name .. s]
	if v == nil then v = a[name .. s] end
	if v == nil then v = a["*" .. name .. "*"] end
	if v == nil then v = a[name] end
	return v
end
W.secureAttr = attr

-- the game's own SecureActionButton_OnClick (SecureTemplates.lua), as far as type = "click" goes
local function secureOnClick(self, button, down)
	W.asGame(function()
		W.secureClicks = W.secureClicks + 1
		local useDown = self.attr and self.attr.useOnKeyDown
		if useDown == nil then useDown = W.useKeyDown == true end
		local act = (down and useDown) or (not down and not useDown)
		if not act then return end
		local kind = attr(self, "type", button)
		if kind == nil then return end
		W.secureActions[#W.secureActions + 1] = tostring(kind)
		if kind == "click" then
			local d = attr(self, "clickbutton", button)
			if type(d) == "table" and d.Click then d:Click(button) end
		end
	end)
end

local function protect(f)
	f.protected = true
	f.scripts.OnClick = secureOnClick
	f.gameOnClick = secureOnClick
	for _, m in ipairs(GUARDED) do
		local orig = W.Frame[m]
		f[m] = function(self, ...)
			if W.combat and W.gameCode == 0 then blocked(m) return end
			return orig(self, ...)
		end
	end
	-- the game's OnClick of the template stays: an addon may not replace it (HookScript / PreClick / PostClick are fine)
	local setScript = W.Frame.SetScript
	f.SetScript = function(self, k, fn)
		if k == "OnClick" then error("XNAH replaced the secure OnClick of a SecureActionButtonTemplate") end
		if W.combat and W.gameCode == 0 then blocked("SetScript") return end
		return setScript(self, k, fn)
	end
end

local newFrame = W.newFrame
function W.newFrame(kind, name, parent, template)
	local secure = type(template) == "string" and template:find(SECURE, 1, true) ~= nil
	if secure and W.combat and (W.gameCode or 0) == 0 then
		blocked("CreateFrame")
		error("CreateFrame: protected frames cannot be made in combat")
	end
	local f = newFrame(kind, name, parent, template)
	if secure then protect(f) end
	return f
end

function W.enterCombat(late)
	if late then
		W.combat = true
		W.fire("PLAYER_REGEN_DISABLED")
	else
		W.fire("PLAYER_REGEN_DISABLED") -- (the game sends it just before the lockdown starts)
		W.combat = true
	end
end
function W.leaveCombat()
	W.combat = false
	W.fire("PLAYER_REGEN_ENABLED")
end
