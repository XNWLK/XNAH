-- A stand-in for the WoW: Forever client and its auction house server, for testing XNAH outside the game.
-- One player runs the addon in its own globals (W.env); the "server" holds the auctions (W.ah), items (W.items), a
-- merchant, profession recipes, bags and the clock. Frames accept any method; the ones that keep state (text, shown,
-- points, scripts, checked, values) remember it, so the tests can click buttons and read what the window shows.
-- Test tool only - never part of the addon.
unpack = unpack or table.unpack
math.atan2 = math.atan2 or math.atan
W = {}
W.START = 1795003200 -- 2026-11-18 12:00 server time (UTC)
W.ADDON = "XNAH"

local function noop() end
local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end
W.copy = copy

-- [[ errors and steps ]] every timer callback and frame script is one "step" (one frame of the game would run a few):
-- W.stepRows counts the full-scan rows read in the current step, W.maxStepRows the most seen in one step.
function W.err(e) W.errors[#W.errors + 1] = tostring(e) end
local function step(fn, ...)
	W.stepRows = 0
	local t0 = os.clock()
	local ok, e = pcall(fn, ...)
	local dt = os.clock() - t0
	if W.stepRows > W.maxStepRows then W.maxStepRows = W.stepRows end
	if dt > W.maxStepTime then W.maxStepTime = dt end
	if not ok then W.err(e) end
	return ok
end
W.step = step

-- [[ timers ]] sorted by time, then by order of creation
function W.after(delay, fn)
	W.seq = W.seq + 1
	local item = {t = W.NOW + math.max(0, delay or 0), fn = fn, seq = W.seq, gen = W.gen}
	local list = W.timers
	local lo, hi = 1, #list + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if list[mid].t <= item.t then lo = mid + 1 else hi = mid end
	end
	table.insert(list, lo, item)
end
local function runTimersUntil(stop)
	local ran = 0
	while true do
		local x = W.timers[1]
		if not x or x.t > stop then break end
		table.remove(W.timers, 1)
		if x.t > W.NOW then W.NOW = x.t end
		if x.gen == W.gen then step(x.fn) ran = ran + 1 end
	end
	return ran
end

-- frames with an OnUpdate script that are visible right now
local function updaters()
	local out = {}
	for _, f in ipairs(W.frames) do
		if f.scripts.OnUpdate and f:IsVisible() then out[#out + 1] = f end
	end
	return out
end
local function runUpdates(elapsed)
	local list = updaters()
	for _, f in ipairs(list) do
		local s = f.scripts.OnUpdate
		if s and f:IsVisible() then step(s, f, elapsed) W.ticks = W.ticks + 1 end
	end
	return #list
end

-- W.advance(seconds): time passes. Frames are drawn every 0.05 s (OnUpdate runs) while some frame has an OnUpdate
-- script; with none, the clock jumps from timer to timer. Long advances (a day) draw at most W.MAX_FRAMES frames one
-- by one (enough for any slice job), then jump from timer to timer and draw one frame after each jump.
W.FRAME = 0.05
W.MAX_FRAMES = 2400
function W.advance(dt)
	local stop = W.NOW + (dt or 0)
	local frames = 0
	while W.NOW < stop - 1e-9 do
		local anyUpdate = #updaters() > 0
		if anyUpdate and frames < W.MAX_FRAMES then
			local nextT = math.min(stop, W.NOW + W.FRAME)
			runTimersUntil(nextT)
			W.NOW = nextT
			runUpdates(W.FRAME)
			frames = frames + 1
		else
			local x = W.timers[1]
			local nextT = (x and x.t <= stop) and x.t or stop
			local jumped = nextT - W.NOW
			runTimersUntil(nextT)
			W.NOW = nextT
			if anyUpdate or #updaters() > 0 then runUpdates(math.max(W.FRAME, jumped)) end
		end
	end
	-- frame times add up with rounding errors: timers due at `stop` still run
	runTimersUntil(stop + 1e-6)
	W.NOW = stop
	-- a few frames at the end, so a job started by the last timer gets going
	if frames >= W.MAX_FRAMES then for _ = 1, 3 do runUpdates(W.FRAME) end end
end
-- runs frames until cond() is true (or `limit` seconds passed); returns true if it became true
function W.waitFor(cond, limit)
	local stop = W.NOW + (limit or 60)
	while W.NOW < stop do
		if cond() then return true end
		W.advance(W.FRAME)
	end
	return cond() and true or false
end

-- [[ events ]]
function W.fire(event, ...)
	local list = W.events[event]
	if not list then return end
	local frames = {}
	for f in pairs(list) do frames[#frames + 1] = f end
	table.sort(frames, function(a, b) return a.id < b.id end)
	for _, f in ipairs(frames) do
		local s = f.scripts.OnEvent
		if s then step(s, f, event, ...) end
	end
end

-- [[ items ]] W.items[id] = {name, quality, sell (vendor pays), stack (max stack; > 1 = a "commodity" on the auction house),
-- icon, uncached = true (details not loaded until asked), never = true (never loads)}
W.SUFFIXES = {[-5] = "of the Monkey", [-11] = "of the Eagle", [-19] = "of the Bear", [-23] = "of the Owl", [-31] = "of the Tiger"}
local QHEX = {[0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000"}
function W.itemName(id, suffix)
	local it = W.items[id]
	if not it then return nil end
	if suffix and suffix ~= 0 and W.SUFFIXES[suffix] then return it.name .. " " .. W.SUFFIXES[suffix] end
	return it.name
end
-- "|cff...|Hitem:ID::::::SUFFIX::...|h[Name]|h|r" - the random suffix is the 7th field after "item:"
function W.link(id, suffix)
	local it = W.items[id]
	if not it then return nil end
	local s = (suffix and suffix ~= 0) and tostring(suffix) or ""
	return "|cff" .. (QHEX[it.quality or 1] or "ffffff") .. "|Hitem:" .. id .. "::::::" .. s .. "::60:::::::|h[" .. W.itemName(id, suffix) .. "]|h|r"
end
function W.icon(id)
	local it = W.items[id]
	return it and (it.icon or 134400)
end
-- the default items of a scene (real Forever item IDs where it matters little)
function W.defaultItems()
	return {
		[2589] = {name = "Linen Cloth", quality = 1, sell = 13, stack = 200},
		[2592] = {name = "Wool Cloth", quality = 1, sell = 33, stack = 200},
		[2996] = {name = "Bolt of Linen Cloth", quality = 1, sell = 40, stack = 200},
		[2770] = {name = "Copper Ore", quality = 1, sell = 5, stack = 20},
		[2840] = {name = "Copper Bar", quality = 1, sell = 10, stack = 20},
		[2771] = {name = "Tin Ore", quality = 1, sell = 25, stack = 20},
		[3576] = {name = "Tin Bar", quality = 1, sell = 25, stack = 20},
		[2841] = {name = "Bronze Bar", quality = 1, sell = 50, stack = 20},
		[2447] = {name = "Peacebloom", quality = 1, sell = 10, stack = 20},
		[765] = {name = "Silverleaf", quality = 1, sell = 10, stack = 20},
		[785] = {name = "Mageroyal", quality = 1, sell = 15, stack = 20},
		[118] = {name = "Minor Healing Potion", quality = 1, sell = 5, stack = 5},
		[858] = {name = "Lesser Healing Potion", quality = 1, sell = 25, stack = 5},
		[3371] = {name = "Empty Vial", quality = 1, sell = 1, stack = 20},
		[2320] = {name = "Coarse Thread", quality = 1, sell = 2, stack = 20},
		[2678] = {name = "Mild Spices", quality = 1, sell = 1, stack = 20},
		[4306] = {name = "Silk Cloth", quality = 1, sell = 150, stack = 200},
		[15210] = {name = "Raider Shortsword", quality = 2, sell = 1540, stack = 1},
		[15248] = {name = "Gleaming Claymore", quality = 2, sell = 3210, stack = 1},
		[6266] = {name = "Disciple's Vest", quality = 2, sell = 90, stack = 1},
		[2575] = {name = "Red Linen Shirt", quality = 1, sell = 25, stack = 1},
		[14047] = {name = "Runecloth", quality = 1, sell = 400, stack = 200},
	}
end

-- [[ the world for one scene ]] W.reset() = nothing loaded yet; W.login() loads the addon
-- extension points for tools/world-*.lua: W.onReset fns run at the end of W.reset(); W.onEnv fns get the new
-- addon environment (add game functions to it) at the end of every login
W.onReset, W.onEnv = W.onReset or {}, W.onEnv or {}
function W.reset()
	W.NOW = 1000           -- GetTime()
	W.timers, W.seq, W.gen = {}, 0, (W.gen or 0) + 1
	W.frames, W.events, W.frameId = {}, {}, 0
	W.errors, W.chat = {}, {}
	W.stepRows, W.maxStepRows, W.maxStepTime, W.ticks = 0, 0, 0, 0
	W.items = W.defaultItems()
	W.ah = {}              -- auctions {itemID, suffix, count, buyout (the WHOLE auction), bid, owner, timeLeft}
	W.ahOpen = false
	W.replicateBuyoutIsTotal = true -- the full scan's buyout is for the whole auction (switch off: per unit)
	W.lastReplicate = nil
	W.replicateCalls = 0
	W.replicaDelay = 2
	W.replica = nil
	W.searchDrop = {}      -- [itemID] = true: the server never answers a search for it
	W.searches = {}        -- every search sent: {key, t}
	W.browse = {}
	W.throttleUntil = 0
	W.merchant = {}        -- {{itemID, price (for stackCount), stackCount, numAvailable (-1 = unlimited)}}
	W.npc = nil
	W.recipes = {}         -- [rid] = {name, out, qMin, qMax, reagents = {{itemID, count}}, learned, prof}
	W.prof = nil
	W.bags = {}            -- [bag] = {[slot] = {id, count, suffix}}
	W.tooltipHooks = {}
	W.realm, W.faction = "Stormreach", "Horde"
	W.player, W.surname = "Xn", "Ascalon"
	W.cursor = {0, 0}
	W.mouseFocus = nil
	W.focus = nil
	W.saved = nil
	W.env = nil
	W.X = nil
	-- extensions (tools/world-*.lua) reset their own state here
	for _, fn in ipairs(W.onReset) do fn() end
	W.market = nil
	W.loadRequests = 0
end

-- [[ frames ]]
local Frame = {}
W.Frame = Frame
local SPECIAL_GET = {GetNormalTexture = true, GetHighlightTexture = true, GetPushedTexture = true, GetDisabledTexture = true,
	GetCheckedTexture = true, GetFontString = true, GetStatusBarTexture = true, GetThumbTexture = true, GetScrollChild = false}
local meta = {__index = function(t, k)
	local m = Frame[k]
	if m then return m end
	if type(k) ~= "string" or not k:match("^%u") then return nil end
	if SPECIAL_GET[k] then
		return function(self)
			self.parts = self.parts or {}
			if not self.parts[k] then self.parts[k] = W.newFrame(k:find("FontString") and "FontString" or "Texture", nil, self) end
			return self.parts[k]
		end
	end
	if k:match("^Get") then return function() return 0 end end -- an unknown getter: a number, so arithmetic works
	return noop
end}
function W.newFrame(kind, name, parent, template)
	W.frameId = W.frameId + 1
	local f = setmetatable({kind = kind, name = name, parent = parent, scripts = {}, shown = true, id = W.frameId,
		w = 100, h = 20, children = {}, points = {}, template = template, alpha = 1, scale = 1}, meta)
	if kind == "Texture" or kind == "FontString" or kind == "Line" or kind == "MaskTexture" then f.region = true end
	W.frames[#W.frames + 1] = f
	if parent and type(parent) == "table" and parent.children then parent.children[#parent.children + 1] = f end
	if name and W.env then W.env[name] = f end
	if template and template:find("ScrollFrame") then f.ScrollBar = W.newFrame("Slider", nil, f) end
	if template and template:find("UIPanelButtonTemplate") then f.Text = W.newFrame("FontString", nil, f) end
	return f
end

function Frame:SetScript(k, f) self.scripts[k] = f end
function Frame:GetScript(k) return self.scripts[k] end
function Frame:HookScript(k, f) local old = self.scripts[k] self.scripts[k] = function(...) if old then old(...) end return f(...) end end
function Frame:HasScript() return true end
function Frame:RegisterEvent(e)
	if type(e) ~= "string" or not e:match("^[A-Z_]+$") then error("RegisterEvent: bad event " .. tostring(e)) end
	W.events[e] = W.events[e] or {}
	W.events[e][self] = true
end
function Frame:RegisterUnitEvent(e) self:RegisterEvent(e) end
function Frame:UnregisterEvent(e) if W.events[e] then W.events[e][self] = nil end end
function Frame:UnregisterAllEvents() for _, l in pairs(W.events) do l[self] = nil end end
function Frame:IsEventRegistered(e) return W.events[e] and W.events[e][self] or false end
function Frame:CreateTexture(n) return W.newFrame("Texture", n, self) end
function Frame:CreateFontString(n) return W.newFrame("FontString", n, self) end
function Frame:CreateMaskTexture(n) return W.newFrame("MaskTexture", n, self) end
function Frame:CreateLine(n) return W.newFrame("Line", n, self) end
function Frame:CreateAnimationGroup(n) return W.newFrame("AnimationGroup", n, self) end
function Frame:CreateAnimation(kind, n) return W.newFrame("Animation", n, self) end
function Frame:SetText(t)
	self.text = t ~= nil and tostring(t) or nil
	if self.kind == "EditBox" then
		local s = self.scripts.OnTextChanged
		if s then step(s, self, false) end
	elseif self.Text and self.kind == "Button" then
		self.Text.text = self.text
	end
end
function Frame:GetText() return self.text end
function Frame:SetFormattedText(f, ...) self:SetText(string.format(f, ...)) end
function Frame:SetNumber(n) self:SetText(tostring(n)) end
function Frame:GetNumber() return tonumber(self.text or "") or 0 end
function Frame:SetTexture(t) self.texture = t end
function Frame:GetTexture() return self.texture end
function Frame:SetColorTexture(r, g, b, a) self.color = {r, g, b, a} end
function Frame:SetVertexColor(r, g, b, a) self.color = {r, g, b, a} end
function Frame:SetTextColor(r, g, b, a) self.textColor = {r, g, b, a} end
function Frame:GetTextColor() local c = self.textColor or {1, 1, 1, 1} return c[1], c[2], c[3], c[4] end
function Frame:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then step(self.scripts.OnShow, self) end
end
function Frame:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then step(self.scripts.OnHide, self) end
	if W.focus == self then W.focus = nil end
end
function Frame:SetShown(s) if s then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible()
	local f = self
	while f do
		if type(f) ~= "table" then error("frame " .. tostring(self.kind) .. " has a parent of type " .. type(f)) end
		if not f.shown then return false end
		f = f.parent
	end
	return true
end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale end
function Frame:GetEffectiveScale() local s, f = 1, self while f and type(f) == "table" do s = s * (f.scale or 1) f = f.parent end return s end
function Frame:SetSize(w, h) self.w, self.h = w, h end
function Frame:SetWidth(w) self.w = w end
function Frame:SetHeight(h) self.h = h end
function Frame:GetWidth() return self.w or 0 end
function Frame:GetHeight() return self.h or 0 end
function Frame:GetSize() return self.w or 0, self.h or 0 end
function Frame:GetRect() return 0, 0, self.w or 0, self.h or 0 end
function Frame:GetCenter() return (self.w or 0) / 2, (self.h or 0) / 2 end
function Frame:GetLeft() return 0 end
function Frame:GetRight() return self.w or 0 end
function Frame:GetBottom() return 0 end
function Frame:GetTop() return self.h or 0 end
function Frame:SetPoint(p, a, b, c, d)
	self.points[#self.points + 1] = {p, a, b, c, d}
	if type(a) == "table" and a == self then error("SetPoint: a frame anchored to itself") end
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(rel) self.points = {{"TOPLEFT", rel}, {"BOTTOMRIGHT", rel}} end
function Frame:GetPoint(i)
	local p = self.points[i or 1]
	if not p then return nil end
	local rel, rp, x, y = p[2], p[3], p[4], p[5]
	if type(rel) ~= "table" then rel, rp, x, y = nil, p[1], p[2], p[3] end
	return p[1], rel, rp or p[1], x or 0, y or 0
end
function Frame:GetNumPoints() return #self.points end
function Frame:GetName() return self.name end
function Frame:GetDebugName() return self.name or ("frame" .. self.id) end
function Frame:GetParent() return self.parent end
function Frame:SetParent(p)
	if self.parent and self.parent.children then
		for i, c in ipairs(self.parent.children) do if c == self then table.remove(self.parent.children, i) break end end
	end
	self.parent = p
	if p and p.children then p.children[#p.children + 1] = self end
end
function Frame:GetChildren()
	local out = {}
	for _, c in ipairs(self.children) do if not c.region then out[#out + 1] = c end end
	return unpack(out)
end
function Frame:GetRegions()
	local out = {}
	for _, c in ipairs(self.children) do if c.region then out[#out + 1] = c end end
	return unpack(out)
end
function Frame:GetNumChildren() return select("#", self:GetChildren()) end
function Frame:SetChecked(v) self.checked = v and true or false end
function Frame:GetChecked() return self.checked or false end
function Frame:SetValue(v)
	v = math.max(self.min or v, math.min(self.max or v, v))
	local changed = self.value ~= v
	self.value = v
	local s = self.scripts.OnValueChanged
	if s and changed then step(s, self, v, false) end
end
function Frame:GetValue() return self.value or 0 end
function Frame:SetMinMaxValues(a, b) self.min, self.max = a, b end
function Frame:GetMinMaxValues() return self.min or 0, self.max or 0 end
function Frame:Enable() self.disabled = false end
function Frame:Disable() self.disabled = true end
function Frame:SetEnabled(v) self.disabled = not v end
function Frame:IsEnabled() return not self.disabled end
function Frame:GetStringWidth() return #(tostring(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end
function Frame:GetUnboundedStringWidth() return self:GetStringWidth() end
function Frame:GetStringHeight() return 12 end
function Frame:GetLineHeight() return 12 end
function Frame:GetNumLines() return 1 end
function Frame:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Frame:IsMouseOver()
	local f = W.mouseFocus
	while f do
		if f == self then return true end
		f = f.parent
	end
	return false
end
function Frame:IsMouseEnabled() return self.mouse ~= false end
function Frame:EnableMouse(on) self.mouse = on ~= false end
function Frame:GetVerticalScroll() return self.vscroll or 0 end
function Frame:SetVerticalScroll(v) self.vscroll = v end
function Frame:GetVerticalScrollRange() return 0 end
function Frame:SetScrollChild(c) self.scrollChild = c if c and c.parent ~= self then c:SetParent(self) end end
function Frame:GetScrollChild() return self.scrollChild end
function Frame:SetFocus() W.focus = self local s = self.scripts.OnEditFocusGained if s then step(s, self) end end
function Frame:ClearFocus() if W.focus == self then W.focus = nil end local s = self.scripts.OnEditFocusLost if s then step(s, self) end end
function Frame:HasFocus() return W.focus == self end
function Frame:GetObjectType() return self.kind end
function Frame:IsObjectType(t) return self.kind == t or t == "Frame" and not self.region end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:SetFrameLevel(l) self.level = l end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetFrameStrata(s) self.strata = s end
function Frame:SetAttribute(k, v) self.attr = self.attr or {} self.attr[k] = v end
function Frame:GetAttribute(k) return self.attr and self.attr[k] end
function Frame:SetID(i) self.fid = i end
function Frame:GetID() return self.fid or 0 end
function Frame:GetCursorPosition() return 0 end
function Frame:SetBackdrop(b) self.backdrop = b end
function Frame:GetBackdrop() return self.backdrop end
-- clicks like a mouse would: a check box flips first, then OnClick
function Frame:Click(button)
	if self.disabled then return end
	if self.kind == "CheckButton" then self.checked = not self.checked end
	local s = self.scripts.PreClick if s then step(s, self, button or "LeftButton", false) end
	s = self.scripts.OnClick if s then step(s, self, button or "LeftButton", false) end
	s = self.scripts.PostClick if s then step(s, self, button or "LeftButton", false) end
end

-- [[ the tooltip ]] lines added by the addon are recorded; SetHyperlink / SetItemByID run the tooltip hooks
local function newTooltip(name)
	local tip = W.newFrame("GameTooltip", name)
	tip.shown = false
	tip.lines = {}
	function tip:ClearLines() self.lines = {} end
	function tip:SetOwner(owner) self.owner = owner self.lines = {} self.item = nil end
	function tip:AddLine(t) self.lines[#self.lines + 1] = {tostring(t)} end
	function tip:AddDoubleLine(l, r) self.lines[#self.lines + 1] = {tostring(l), tostring(r)} end
	function tip:NumLines() return #self.lines end
	function tip:GetItem() if self.item then return W.itemName(self.item.id, self.item.suffix), W.link(self.item.id, self.item.suffix), self.item.id end end
	function tip:GetProcessingTooltipInfo() return self.info end
	function tip:SetHyperlink(link)
		local body = tostring(link):match("item:([%-%d:]+)")
		if not body then return end
		local fields = {}
		for f in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
		W.showItemTooltip(self, tonumber(fields[1]), tonumber(fields[7] or ""), {getterName = "GetHyperlink", getterArgs = {link}})
	end
	function tip:SetItemByID(id) W.showItemTooltip(self, id, nil, {getterName = "GetItemByID", getterArgs = {id}}) end
	return tip
end
function W.showItemTooltip(tip, id, suffix, info)
	tip.lines = {}
	tip.item = {id = id, suffix = suffix}
	tip.info = info
	if W.items[id] then tip.lines[1] = {W.itemName(id, suffix)} end
	for _, fn in ipairs(W.tooltipHooks[0] or {}) do step(fn, tip, {id = id, type = 0, hyperlink = W.link(id, suffix)}) end
	tip.info = nil
	tip.shown = true
	return tip.lines
end
-- the player points at a stack in the bags: returns the tooltip's lines
function W.hoverItem(id, bag, slot, count, suffix)
	bag, slot = bag or 0, slot or 1
	W.bags[bag] = W.bags[bag] or {}
	W.bags[bag][slot] = {id = id, count = count or 1, suffix = suffix}
	local tip = W.env.GameTooltip
	tip.owner = nil
	return W.showItemTooltip(tip, id, suffix, {getterName = "GetBagItem", getterArgs = {bag, slot}})
end
-- the tooltip's lines as text, one per line
function W.tipText(lines)
	local out = {}
	for _, l in ipairs(lines or W.env.GameTooltip.lines) do out[#out + 1] = W.plain(table.concat(l, "  ")) end
	return table.concat(out, "\n")
end
-- text without colour codes and icons
function W.plain(s)
	return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end

-- [[ the auction house server ]]
local function unitOf(a) return a.buyout and a.buyout > 0 and a.buyout / math.max(1, a.count or 1) or nil end
W.unitOf = unitOf
local function keyStr(id, suffix) return (suffix and suffix ~= 0) and (id .. ":" .. suffix) or tostring(id) end
W.keyStr = keyStr

function W.openAH()
	W.ahOpen = true
	W.env.AuctionHouseFrame = W.ahFrame or W.newFrame("Frame", "AuctionHouseFrame", W.env.UIParent)
	W.ahFrame = W.env.AuctionHouseFrame
	W.ahFrame:Show()
	W.fire("AUCTION_HOUSE_SHOW")
end
function W.closeAH()
	W.ahOpen = false
	if W.ahFrame then W.ahFrame:Hide() end
	W.fire("AUCTION_HOUSE_CLOSED")
end

-- the full scan: the server copies the auction house ~2 s after the call (refused, without a word, within 15 minutes of
-- the last one)
local function replicateItems()
	W.replicateCalls = W.replicateCalls + 1
	if not W.ahOpen then return end
	if W.lastReplicate and W.NOW - W.lastReplicate < 900 then W.refused = (W.refused or 0) + 1 return end
	W.lastReplicate = W.NOW
	W.after(W.replicaDelay, function()
		if not W.ahOpen then return end
		W.replica = {}
		for i, a in ipairs(W.ah) do W.replica[i] = a end
		W.fire("REPLICATE_ITEM_LIST_UPDATE")
	end)
end
local function replicaRow(i)
	if not W.ahOpen or not W.replica then return nil end
	if type(i) ~= "number" then error("GetReplicateItemInfo: index must be a number") end
	return W.replica[i + 1] -- 0-based
end
local function loaded(id)
	local it = W.items[id]
	return it and not it.uncached
end
local function getReplicateItemInfo(i)
	W.stepRows = W.stepRows + 1
	W.rowsRead = (W.rowsRead or 0) + 1
	local a = replicaRow(i)
	if not a then return nil end
	local it = W.items[a.itemID] or {}
	local has = loaded(a.itemID)
	local name = has and W.itemName(a.itemID, a.suffix) or nil
	local buyout = a.buyout or 0
	if not W.replicateBuyoutIsTotal and buyout > 0 then buyout = math.floor(buyout / math.max(1, a.count or 1)) end
	local owner = a.owner
	local short = owner and owner:match("^(%S+)") or owner
	return name, has and W.icon(a.itemID) or nil, a.count or 1, it.quality or 1, true, 60, "", a.bid or 0, 0, buyout,
		0, nil, nil, short, owner, 0, a.itemID, has and true or false
end
local function getReplicateItemLink(i)
	local a = replicaRow(i)
	if not a or not loaded(a.itemID) then return nil end
	return W.link(a.itemID, a.suffix)
end
local function requestLoad(id)
	W.loadRequests = W.loadRequests + 1
	local it = W.items[id]
	if not it or not it.uncached or it.never or it.loading then return end
	it.loading = true
	W.after(1, function()
		it.uncached, it.loading = nil, nil
		W.fire("ITEM_DATA_LOAD_RESULT", id, true)
		W.fire("GET_ITEM_INFO_RECEIVED", id, true)
	end)
end

-- browse: one row per item (and random suffix), the lowest price of ONE and how many are listed
local function sendBrowseQuery(query)
	if not W.ahOpen then return end
	W.throttleUntil = W.NOW + 0.1
	local text = (query and query.searchString or ""):lower()
	W.after(0.5, function()
		local rows, order = {}, {}
		for _, a in ipairs(W.ah) do
			local name = W.itemName(a.itemID, a.suffix) or ""
			if text == "" or name:lower():find(text, 1, true) then
				local k = keyStr(a.itemID, a.suffix)
				local r = rows[k]
				if not r then
					r = {itemKey = {itemID = a.itemID, itemLevel = 0, itemSuffix = a.suffix or 0, battlePetSpeciesID = 0}, totalQuantity = 0, containsOwnerItem = false}
					rows[k] = r
					order[#order + 1] = k
				end
				r.totalQuantity = r.totalQuantity + (a.count or 1)
				local u = unitOf(a)
				if u and (not r.minPrice or u < r.minPrice) then r.minPrice = math.floor(u + 0.5) end
			end
		end
		W.browse = {}
		for _, k in ipairs(order) do
			local r = rows[k]
			r.minPrice = r.minPrice or 0
			W.browse[#W.browse + 1] = r
		end
		W.fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
	end)
end

-- searching one item: stackable items answer with a list of prices of ONE (commodities), gear with one row per auction
W.commodity, W.itemResults = {}, {}
local function isCommodity(id) local it = W.items[id] return it and (it.stack or 1) > 1 end
local function sendSearchQuery(itemKey, sorts, separate)
	if not W.ahOpen then return end
	if type(itemKey) ~= "table" or not itemKey.itemID then error("SendSearchQuery: bad itemKey") end
	W.throttleUntil = W.NOW + 0.1
	local id, suffix = itemKey.itemID, itemKey.itemSuffix or 0
	W.searches[#W.searches + 1] = {key = keyStr(id, suffix), t = W.NOW}
	if W.searchDrop[id] then return end
	W.after(0.3, function()
		if not W.ahOpen then return end
		if isCommodity(id) then
			-- the same price from several sellers is one row
			local byPrice, prices = {}, {}
			for _, a in ipairs(W.ah) do
				if a.itemID == id then
					local u = unitOf(a)
					if u then
						u = math.floor(u + 0.5)
						if not byPrice[u] then byPrice[u] = 0 prices[#prices + 1] = u end
						byPrice[u] = byPrice[u] + (a.count or 1)
					end
				end
			end
			table.sort(prices)
			local list = {}
			for i, u in ipairs(prices) do list[i] = {itemID = id, quantity = byPrice[u], unitPrice = u, auctionID = i, owners = {}, totalNumberOfOwners = 1} end
			W.commodity[id] = list
			W.fire("COMMODITY_SEARCH_RESULTS_UPDATED", id)
		else
			local list = {}
			for _, a in ipairs(W.ah) do
				if a.itemID == id and (suffix == 0 or (a.suffix or 0) == suffix) and a.buyout and a.buyout > 0 then
					list[#list + 1] = {itemKey = {itemID = id, itemLevel = 0, itemSuffix = a.suffix or 0, battlePetSpeciesID = 0},
						owners = {a.owner}, totalNumberOfOwners = 1, timeLeft = 2, auctionID = #list + 1, quantity = a.count or 1,
						itemLink = W.link(id, a.suffix), buyoutAmount = a.buyout, bidAmount = a.bid}
				end
			end
			table.sort(list, function(x, y) return x.buyoutAmount < y.buyoutAmount end)
			W.itemResults[keyStr(id, suffix)] = list
			-- the event hands over a fresh copy of the key (the addon must not rely on getting its own table back)
			W.fire("ITEM_SEARCH_RESULTS_UPDATED", {itemID = id, itemLevel = 0, itemSuffix = suffix, battlePetSpeciesID = 0})
		end
	end)
end

-- [[ the merchant ]]
function W.openMerchant(npc, list)
	W.npc = npc or "Tharynn Bouden"
	if list then W.merchant = list end
	W.fire("MERCHANT_SHOW")
end
function W.closeMerchant() W.npc = nil W.fire("MERCHANT_CLOSED") end

-- [[ professions ]] W.openProfession(name, linked): a profession window opens (yours, or a link someone posted)
function W.openProfession(name, linked)
	W.prof = {name = name, linked = linked and true or false}
	W.fire("TRADE_SKILL_SHOW")
	W.fire("TRADE_SKILL_LIST_UPDATE")
end
function W.closeProfession() W.prof = nil W.fire("TRADE_SKILL_CLOSE") end
local function profRecipes()
	local out = {}
	if not W.prof then return out end
	for rid, r in pairs(W.recipes) do
		if not r.prof or r.prof == W.prof.name then out[#out + 1] = rid end
	end
	table.sort(out)
	return out
end

-- [[ saved data ]] written like the game writes SavedVariables (text), read back on the next login
local function ser(v, indent, out, path)
	local t = type(v)
	if t == "string" then out[#out + 1] = string.format("%q", v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then error("saved data: bad number at " .. path) end
		if math.type and math.type(v) == "integer" or v == math.floor(v) and math.abs(v) < 2^53 then out[#out + 1] = string.format("%d", v)
		else out[#out + 1] = string.format("%.17g", v) end
	elseif t == "boolean" then out[#out + 1] = tostring(v)
	elseif t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) < type(b) end
			return a < b
		end)
		out[#out + 1] = "{\n"
		for _, k in ipairs(keys) do
			out[#out + 1] = indent .. "\t["
			ser(k, "", out, path)
			out[#out + 1] = "] = "
			ser(v[k], indent .. "\t", out, path .. "." .. tostring(k))
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	else
		error("saved data: a " .. t .. " can not be saved (at " .. path .. ")")
	end
end
function W.saveText(v)
	local out = {}
	ser(v, "", out, "XNAHDB")
	return "XNAHDB = " .. table.concat(out) .. "\n"
end

-- [[ the client: the addon's globals ]]
local ADDON_FILES, SOURCES = {}, {}
function W.addonFiles(list) ADDON_FILES = list end
function W.source(file, text) SOURCES[file] = text end

local function makeEnv()
	local env = setmetatable({}, {__index = _G})
	env._G = env
	W.env = env
	env.UIParent = W.newFrame("Frame", "UIParent")
	env.UIParent.w, env.UIParent.h = 1920, 1080
	env.WorldFrame = W.newFrame("Frame", "WorldFrame")
	env.Minimap = W.newFrame("Frame", "Minimap", env.UIParent)
	env.Minimap.w, env.Minimap.h = 140, 140
	env.GameTooltip = newTooltip("GameTooltip")
	env.ItemRefTooltip = newTooltip("ItemRefTooltip")
	env.UISpecialFrames = {}
	env.SlashCmdList = {}
	env.DEFAULT_CHAT_FRAME = {AddMessage = function(_, m) W.chat[#W.chat + 1] = tostring(m) end}
	for _, f in ipairs({"GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalLarge", "GameFontDisableSmall",
		"ChatFontNormal", "GameFontNormalSmall", "GameFontHighlightLarge", "GameFontNormalHuge", "GameFontDisable", "NumberFontNormal",
		"GameFontHighlightMedium", "GameFontNormalMed3", "SystemFont_Small", "GameFontRed", "GameFontGreen"}) do env[f] = f end
	env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

	env.CreateFrame = function(kind, name, parent, template)
		if type(kind) ~= "string" then error("CreateFrame: frame type must be a string") end
		return W.newFrame(kind, name, parent, template)
	end
	env.issecretvalue = function(v) return v == W.SECRET end
	env.GetTime = function() return W.NOW end
	env.GetServerTime = function() return W.START + math.floor(W.NOW - 1000) end
	env.time = function(t) if t then return os.time(t) end return env.GetServerTime() end
	env.date = function(fmt, t) return os.date(fmt, t or env.GetServerTime()) end
	env.C_Timer = {
		After = function(d, fn)
			if type(fn) ~= "function" then error("C_Timer.After: no function") end
			W.after(d, fn)
		end,
		NewTimer = function(d, fn)
			local t = {cancelled = false}
			W.after(d, function() if not t.cancelled then fn(t) end end)
			function t:Cancel() self.cancelled = true end
			function t:IsCancelled() return self.cancelled end
			return t
		end,
		NewTicker = function(d, fn, n)
			local ticker = {cancelled = false, left = n}
			local function tick()
				if ticker.cancelled then return end
				fn(ticker)
				if ticker.left then ticker.left = ticker.left - 1 if ticker.left <= 0 then return end end
				W.after(d, tick)
			end
			W.after(d, tick)
			function ticker:Cancel() self.cancelled = true end
			function ticker:IsCancelled() return self.cancelled end
			return ticker
		end,
	}
	env.C_AddOns = {GetAddOnMetadata = function(a, k) if k == "Version" then return "0.1.0" end if k == "Title" then return "XNAH" end end,
		IsAddOnLoaded = function(a) return a == W.ADDON end}
	env.GetRealmName = function() return W.realm end
	env.GetNormalizedRealmName = function() return (W.realm:gsub("%s", "")) end
	env.UnitFactionGroup = function(u) if u == "player" then return W.faction, W.faction end end
	env.UnitName = function(u)
		if u == "player" then return W.player, W.surname end
		if u == "npc" then return W.npc end
		return nil
	end
	env.UnitFullName = function(u) if u == "player" then return W.player, W.realm end end
	env.UnitExists = function(u) return u == "player" or (u == "npc" and W.npc ~= nil) end
	env.RegionalUniqueNamesEnabled = function() return true end
	env.InCombatLockdown = function() return W.combat == true end
	env.GetCursorPosition = function() return W.cursor[1], W.cursor[2] end
	env.GetScreenWidth = function() return 1920 end
	env.GetScreenHeight = function() return 1080 end
	env.IsAltKeyDown, env.IsControlKeyDown, env.IsShiftKeyDown = function() return W.alt == true end, function() return W.ctrl == true end, function() return W.shift == true end
	env.IsModifiedClick = function() return false end
	env.GetMouseFocus = function() return W.mouseFocus end
	env.GetMouseFoci = function() return {W.mouseFocus} end
	env.PlaySound = noop
	env.GetMoney = function() return W.money or 1234567 end
	env.hooksecurefunc = function(a, b, c)
		if type(a) == "string" then W.hooks = W.hooks or {} W.hooks[a] = b end
	end
	env.HandleModifiedItemClick = function(link) if W.hooks and W.hooks.HandleModifiedItemClick then W.hooks.HandleModifiedItemClick(link) end end
	env.strsplit = function(sep, s, n)
		local out = {}
		for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
		return unpack(out)
	end
	env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	env.strjoin = function(sep, ...) return table.concat({...}, sep) end
	env.tinsert, env.tremove = table.insert, table.remove
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.floor, env.ceil, env.abs, env.min, env.max = math.floor, math.ceil, math.abs, math.min, math.max
	env.format = string.format
	env.CopyTable = copy
	env.GetBindingKey = noop
	env.SetCursor = noop
	env.ResetCursor = noop
	env.CloseDropDownMenus = noop
	env.Enum = {TooltipDataType = {Item = 0, Spell = 1, Unit = 2}, CraftingReagentType = {Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3},
		AuctionHouseSortOrder = {Price = 0, Name = 1, Level = 2, Bid = 3, Buyout = 4, TimeRemaining = 5},
		ItemCommodityStatus = {Unknown = 0, Item = 1, Commodity = 2}, AuctionHouseTimeLeftBand = {Short = 0, Medium = 1, Long = 2, VeryLong = 3}}
	env.TooltipDataProcessor = {
		AddTooltipPostCall = function(kind, fn)
			W.tooltipHooks[kind] = W.tooltipHooks[kind] or {}
			table.insert(W.tooltipHooks[kind], fn)
		end,
		AddTooltipPreCall = noop, AddLinePreCall = noop, AddLinePostCall = noop,
	}
	env.TooltipUtil = {GetDisplayedItem = function(tip) return tip:GetItem() end}

	-- items
	env.C_Item = {
		GetItemInfo = function(x)
			local id, suffix = nil, nil
			if type(x) == "number" then id = x
			elseif type(x) == "string" then
				local body = x:match("item:([%-%d:]+)")
				if body then
					local f = {}
					for v in (body .. ":"):gmatch("([^:]*):") do f[#f + 1] = v end
					id, suffix = tonumber(f[1]), tonumber(f[7] or "")
				else
					id = tonumber(x)
					if not id then for i, v in pairs(W.items) do if v.name == x and not v.uncached then id = i end end end
				end
			end
			local it = id and W.items[id]
			if not it or it.uncached then
				if it then requestLoad(id) end
				return nil
			end
			return W.itemName(id, suffix), W.link(id, suffix), it.quality or 1, 30, 1, it.stack and it.stack > 1 and "Trade Goods" or "Armor", "",
				it.stack or 1, "", W.icon(id), it.sell or 0, 7, 0, 0, 0, nil, (it.stack or 1) > 1, ""
		end,
		GetItemInfoInstant = function(x)
			local id = type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)") or x)
			local it = id and W.items[id]
			if not it then return nil end
			return id, "Trade Goods", "", "", W.icon(id), 7, 0
		end,
		GetItemIconByID = function(id) return W.icon(id) end,
		GetItemNameByID = function(id) local it = W.items[id] return it and not it.uncached and it.name or nil end,
		GetItemQualityByID = function(id) local it = W.items[id] return it and it.quality end,
		GetItemMaxStackSizeByID = function(id) local it = W.items[id] return it and it.stack or 1 end,
		IsItemDataCachedByID = function(id) return loaded(id) and true or false end,
		RequestLoadItemDataByID = requestLoad,
		GetItemCount = function(id) local n = 0 for _, bag in pairs(W.bags) do for _, s in pairs(bag) do if s.id == id then n = n + s.count end end end return n end,
	}
	env.GetItemInfo = nil -- gone on Forever (C_Item only)
	env.C_Container = {
		GetContainerNumSlots = function(bag) local n = 0 for s in pairs(W.bags[bag] or {}) do if s > n then n = s end end return n end,
		GetContainerItemInfo = function(bag, slot)
			local s = W.bags[bag] and W.bags[bag][slot]
			if not s then return nil end
			return {iconFileID = W.icon(s.id), stackCount = s.count, isLocked = false, quality = W.items[s.id] and W.items[s.id].quality,
				hyperlink = W.link(s.id, s.suffix), itemID = s.id, isBound = false, itemName = W.itemName(s.id, s.suffix), hasNoValue = false}
		end,
		GetContainerItemLink = function(bag, slot) local s = W.bags[bag] and W.bags[bag][slot] return s and W.link(s.id, s.suffix) end,
	}

	-- the auction house
	env.C_AuctionHouse = {
		ReplicateItems = replicateItems,
		GetNumReplicateItems = function() if not W.ahOpen or not W.replica then return 0 end return #W.replica end,
		GetReplicateItemInfo = getReplicateItemInfo,
		GetReplicateItemLink = getReplicateItemLink,
		GetReplicateItemTimeLeft = function(i) local a = replicaRow(i) return a and (a.timeLeft or 2) end,
		SendBrowseQuery = sendBrowseQuery,
		GetBrowseResults = function() return copy(W.browse) end,
		HasFullBrowseResults = function() return true end,
		RequestMoreBrowseResults = noop,
		MakeItemKey = function(itemID, itemLevel, itemSuffix, species)
			return {itemID = itemID, itemLevel = itemLevel or 0, itemSuffix = itemSuffix or 0, battlePetSpeciesID = species or 0}
		end,
		SendSearchQuery = sendSearchQuery,
		SendSellSearchQuery = sendSearchQuery,
		GetNumCommoditySearchResults = function(id) return W.commodity[id] and #W.commodity[id] or 0 end,
		GetCommoditySearchResultInfo = function(id, i) local l = W.commodity[id] return l and copy(l[i]) end,
		HasFullCommoditySearchResults = function(id) return W.commodity[id] ~= nil end,
		GetNumItemSearchResults = function(k) local l = W.itemResults[keyStr(k.itemID, k.itemSuffix)] return l and #l or 0 end,
		GetItemSearchResultInfo = function(k, i) local l = W.itemResults[keyStr(k.itemID, k.itemSuffix)] return l and copy(l[i]) end,
		HasFullItemSearchResults = function(k) return W.itemResults[keyStr(k.itemID, k.itemSuffix)] ~= nil end,
		IsThrottledMessageSystemReady = function() return W.NOW >= W.throttleUntil end,
		GetItemKeyInfo = function(k)
			local it = k and W.items[k.itemID]
			if not it or it.uncached then return nil end
			return {itemID = k.itemID, battlePetSpeciesID = 0, itemName = W.itemName(k.itemID, k.itemSuffix), quality = it.quality or 1,
				iconFileID = W.icon(k.itemID), isPet = false, isCommodity = isCommodity(k.itemID), isEquipment = not isCommodity(k.itemID)}
		end,
		GetItemCommodityStatus = function() return 0 end,
	}

	-- the merchant
	env.GetMerchantNumItems = function() return W.npc and #W.merchant or 0 end
	env.GetMerchantItemID = function(i) local m = W.npc and W.merchant[i] return m and m.itemID end
	env.GetMerchantItemLink = function(i) local m = W.npc and W.merchant[i] return m and W.link(m.itemID) end
	env.GetMerchantItemMaxStack = function(i) local m = W.merchant[i] return m and W.items[m.itemID] and W.items[m.itemID].stack or 1 end
	env.C_MerchantFrame = {GetItemInfo = function(i)
		local m = W.npc and W.merchant[i]
		if not m then return nil end
		return {name = W.itemName(m.itemID), texture = W.icon(m.itemID), price = m.price, stackCount = m.stackCount or 1,
			numAvailable = m.numAvailable or -1, isPurchasable = true, isUsable = true, hasExtendedCost = m.extended or false}
	end}

	-- professions
	env.C_TradeSkillUI = {
		GetAllRecipeIDs = profRecipes,
		GetFilteredRecipeIDs = profRecipes,
		GetRecipeInfo = function(rid)
			local r = W.recipes[rid]
			if not r then return nil end
			local learned = r.learned and true or false
			if W.prof and W.prof.linked then learned = true end -- a linked profession shows what ITS owner knows
			return {recipeID = rid, name = r.name, learned = learned, craftable = learned, categoryID = 1, icon = 1,
				hyperlink = "|cffffd000|Henchant:" .. rid .. "|h[" .. r.name .. "]|h|r"}
		end,
		GetRecipeSchematic = function(rid, isRecraft)
			local r = W.recipes[rid]
			if not r then return nil end
			local slots = {}
			for i, re in ipairs(r.reagents or {}) do
				slots[i] = {reagents = {{itemID = re[1]}}, reagentType = 1, quantityRequired = re[2], slotIndex = i, dataSlotIndex = i, required = true}
			end
			if r.optional then slots[#slots + 1] = {reagents = {{itemID = r.optional}}, reagentType = 0, quantityRequired = 1, slotIndex = #slots + 1} end
			return {recipeID = rid, icon = 1, quantityMin = r.qMin or 1, quantityMax = r.qMax or r.qMin or 1, name = r.name, recipeType = 1,
				outputItemID = r.out, reagentSlotSchematics = slots, isRecraft = false, hasCraftingOperationInfo = false}
		end,
		IsTradeSkillReady = function() return W.prof ~= nil and not W.prof.notReady end,
		IsTradeSkillLinked = function() return W.prof and W.prof.linked or false end,
		IsTradeSkillGuild = function() return false end,
		IsNPCCrafting = function() return false end,
		GetBaseProfessionInfo = function() return {professionName = W.prof and W.prof.name or "", professionID = 1} end,
		GetChildProfessionInfo = function() return {professionName = W.prof and W.prof.name or ""} end,
	}
	for _, fn in ipairs(W.onEnv) do fn(env) end
	return env
end

-- loads the addon (as the game does on login): the files in .toc order, then ADDON_LOADED, PLAYER_LOGIN
function W.login(saved)
	W.frames, W.events, W.timers, W.tooltipHooks = {}, {}, {}, {}
	W.gen = (W.gen or 0) + 1
	W.focus, W.mouseFocus = nil, nil
	local env = makeEnv()
	if saved then
		local fn, e = load(saved, "=XNAHDB", "t", env)
		if not fn then error("saved data does not load: " .. tostring(e)) end
		fn()
	end
	local X = {}
	W.X = X
	for _, file in ipairs(ADDON_FILES) do
		local fn, e = load(SOURCES[file], "@" .. file, "t", env)
		if not fn then W.err(e) else
			local ok, e2 = pcall(fn, W.ADDON, X)
			if not ok then W.err(e2) end
		end
	end
	W.fire("ADDON_LOADED", W.ADDON)
	W.fire("PLAYER_LOGIN")
	W.fire("PLAYER_ENTERING_WORLD", true, false)
	return X
end
-- /reload: the saved data is written out as text and read back; everything else starts over
function W.reload()
	if W.ahOpen then W.ahOpen = false end
	W.saved = W.saveText(W.env.XNAHDB)
	return W.login(W.saved)
end
-- size in bytes of the saved file right now
function W.savedSize() return #W.saveText(W.env.XNAHDB) end

-- a fresh world with the addon loaded
function W.start()
	W.reset()
	return W.login()
end

-- [[ test helpers ]]
-- every frame under root (root included), depth first
function W.walk(root, fn)
	local function visit(f)
		fn(f)
		for _, c in ipairs(f.children) do visit(c) end
	end
	visit(root)
end
-- all shown text under a frame (font strings and edit boxes), one per line
function W.screen(root)
	local out = {}
	local function walk(f)
		if not f.shown then return end
		if (f.kind == "FontString" or f.kind == "EditBox" or f.kind == "Button") and f.text and f.text ~= "" then out[#out + 1] = W.plain(f.text) end
		for _, c in ipairs(f.children) do walk(c) end
	end
	walk(root)
	return table.concat(out, "\n")
end
-- the text of a button: its own, or that of its shown font strings
function W.buttonText(f)
	if f.text then return f.text end
	local parts = {}
	for _, c in ipairs(f.children) do if c.kind == "FontString" and c.text and c.text ~= "" and c.shown then parts[#parts + 1] = c.text end end
	return table.concat(parts, " ")
end
function W.findButton(text, root)
	for _, f in ipairs(W.frames) do
		if (f.kind == "Button" or f.kind == "CheckButton") and f.scripts.OnClick and f:IsVisible() then
			local inside = true
			if root then
				inside = false
				local p = f
				while p do if p == root then inside = true break end p = p.parent end
			end
			if inside and W.plain(W.buttonText(f)):find(text, 1, true) then return f end
		end
	end
end
function W.click(text, root, button)
	local f = W.findButton(text, root)
	if not f then error("no visible button '" .. text .. "'") end
	f:Click(button)
	return f
end
-- the player types into a text box (each change is the user's), then presses Enter
function W.type(box, text, enter)
	W.focus = box
	box.text = text
	local s = box.scripts.OnTextChanged
	if s then step(s, box, true) end
	s = box.scripts.OnChar
	if s and #text > 0 then step(s, box, text:sub(-1)) end
	if enter ~= false then
		s = box.scripts.OnEnterPressed
		if s then step(s, box) end
	end
end
-- the mouse moves over a frame (and off it)
function W.hover(f, x, y)
	W.mouseFocus = f
	W.cursor = {x or 10, y or 10}
	local s = f.scripts.OnEnter
	if s then step(s, f, true) end
end
function W.unhover(f)
	if W.mouseFocus == f then W.mouseFocus = nil end
	local s = f.scripts.OnLeave
	if s then step(s, f) end
end
-- chat lines (without colours) that contain text
function W.said(text)
	local out = {}
	for _, l in ipairs(W.chat) do if W.plain(l):find(text, 1, true) then out[#out + 1] = W.plain(l) end end
	return out
end
function W.lastSaid() return W.plain(W.chat[#W.chat] or "") end

-- [[ auctions ]] W.list(itemID, unitPrice, count, n, owner, suffix): n auctions of `count` each at unitPrice per one
function W.list(id, unit, count, n, owner, suffix)
	count, n = count or 1, n or 1
	for i = 1, n do
		W.ah[#W.ah + 1] = {itemID = id, suffix = suffix, count = count, buyout = math.floor(unit * count + 0.5), bid = math.floor(unit * count * 0.8),
			owner = (owner or "Seller") .. (n > 1 and i or "") .. " Smith", timeLeft = 2}
	end
end

-- [[ a whole market ]] deterministic random numbers (the same seed gives the same auction house)
local function rng(seed)
	local s = (seed or 1) % 2147483647
	if s <= 0 then s = s + 2147483646 end
	return function(a, b)
		s = (s * 16807) % 2147483647
		local r = (s - 1) / 2147483646
		if a then return a + math.floor(r * (b - a + 1)) end
		return r
	end
end
W.rng = rng
local HERB = {"Bloom", "Leaf", "Thistle", "Root", "Moss", "Lotus", "Weed", "Briar"}
local ORE = {"Ore", "Bar", "Stone", "Gem", "Dust", "Shard", "Essence", "Powder"}
local CLOTH = {"Cloth", "Silk", "Weave", "Thread", "Hide", "Leather", "Scale", "Pelt"}
local GEAR = {"Blade", "Helm", "Gloves", "Boots", "Robe", "Ring", "Cloak", "Staff", "Bracers", "Belt"}
local ADJ = {"Ashen", "Bright", "Copper", "Dusky", "Elder", "Frost", "Grim", "Hollow", "Iron", "Jade", "Kings", "Lunar", "Mossy",
	"Noble", "Oak", "Pale", "Quiet", "Red", "Storm", "Thorn", "Umber", "Vile", "Wild", "Young", "Zephyr"}

-- W.makeMarket(seed, nItems, opts) builds items and auctions: ~70% stackable trade goods (many sellers, stacks of
-- 1-20), ~25% gear (one per auction, random suffixes), a few listed under the vendor price ("below vendor") and a few
-- vendor reagents that sell for more on the auction house ("flip"). opts.uncached = share of items not loaded at the
-- start (default 0.1). Returns W.market = {items = {{id, kind, base, ...}}, byKind = {stack, gear, below, flip}}.
-- W.marketDay(day) then lists the auctions of that day (prices drift with each item's trend).
function W.makeMarket(seed, nItems, opts)
	opts = opts or {}
	local r = rng(seed)
	local m = {seed = seed, items = {}, byKind = {stack = {}, gear = {}, below = {}, flip = {}, rise = {}, fall = {}, deal = {}, short = {}, flood = {}}}
	local nextID = opts.firstID or 100000
	for n = 1, nItems do
		local id = nextID
		nextID = nextID + 1
		local roll = r()
		local e = {id = id}
		if roll < 0.7 then
			e.kind = "stack"
			local group = r(1, 3)
			local words = group == 1 and HERB or group == 2 and ORE or CLOTH
			local name = ADJ[r(1, #ADJ)] .. " " .. words[r(1, #words)] .. " " .. n
			e.base = math.floor(10 * 10 ^ (r() * 3.7)) -- 10c .. 50g a piece
			W.items[id] = {name = name, quality = 1, sell = math.max(1, math.floor(e.base * (0.1 + r() * 0.2))), stack = 20}
			e.auctions = r(5, 40)
		else
			e.kind = "gear"
			local name = ADJ[r(1, #ADJ)] .. " " .. GEAR[r(1, #GEAR)] .. " " .. n
			e.base = math.floor(5000 * 10 ^ (r() * 2.5)) -- 50s .. 158g
			W.items[id] = {name = name, quality = r(2, 4), sell = math.floor(e.base * (0.05 + r() * 0.15)), stack = 1}
			e.auctions = r(1, 6)
			e.suffixes = {}
			if r() < 0.6 then
				local list = {-5, -11, -19, -23, -31}
				for i = 1, r(1, 3) do e.suffixes[#e.suffixes + 1] = list[r(1, #list)] end
			end
		end
		if r() < (opts.uncached or 0.1) then W.items[id].uncached = true end
		-- the trend of its price, % per day: most flat, some rising or falling
		local t = r()
		e.trend = 0
		if t < 0.05 then e.trend = 0.06 m.byKind.rise[#m.byKind.rise + 1] = id
		elseif t < 0.1 then e.trend = -0.05 m.byKind.fall[#m.byKind.fall + 1] = id end
		e.supply = 1
		m.items[#m.items + 1] = e
		table.insert(m.byKind[e.kind], id)
	end
	-- special cases among the stackables (not trending ones)
	local flat = {}
	for _, e in ipairs(m.items) do if e.kind == "stack" and e.trend == 0 then flat[#flat + 1] = e end end
	local function pick(kind, count)
		for _ = 1, count do
			if #flat == 0 then return end
			local e = table.remove(flat, r(1, #flat))
			e.special = kind
			table.insert(m.byKind[kind], e.id)
		end
	end
	pick("below", 4)  -- one cheap auction under what a vendor pays
	pick("flip", 4)   -- a vendor sells it for less than the auction house
	pick("deal", 4)   -- on the last day one auction far under its usual price
	pick("short", 3)  -- supply drops on the last days
	pick("flood", 3)  -- supply jumps on the last days
	W.merchant = W.merchant or {}
	for _, id in ipairs(m.byKind.flip) do
		local e
		for _, x in ipairs(m.items) do if x.id == id then e = x end end
		W.merchant[#W.merchant + 1] = {itemID = id, price = math.floor(e.base * 0.5) * 5, stackCount = 5, numAvailable = -1}
		W.items[id].sell = math.max(1, math.floor(e.base * 0.02))
	end
	W.market = m
	W.marketDay(0, opts.lastDay)
	return m
end
-- lists the auctions of day `day` (0 = first); lastDay = the day the deals / supply changes show up
function W.marketDay(day, lastDay)
	local m = W.market
	local r = rng(m.seed * 7919 + day * 104729)
	W.ah = {}
	for _, e in ipairs(m.items) do
		local base = e.base * (1 + e.trend) ^ day
		local n = e.auctions
		local special = (lastDay and day >= lastDay) and e.special or nil
		if special == "short" then n = math.max(1, math.floor(n * 0.2)) end
		if special == "flood" then n = n * 4 end
		for i = 1, n do
			local unit = base * (0.95 + r() * 0.35)
			local count = e.kind == "stack" and r(1, 20) or 1
			local suffix = e.kind == "gear" and #e.suffixes > 0 and e.suffixes[r(1, #e.suffixes)] or nil
			W.ah[#W.ah + 1] = {itemID = e.id, suffix = suffix, count = count, buyout = math.max(1, math.floor(unit * count + 0.5)),
				bid = math.floor(unit * count * 0.7), owner = "Seller" .. r(1, 400) .. " Trader", timeLeft = r(0, 3)}
		end
		if e.special == "below" then
			local vs = W.items[e.id].sell
			W.ah[#W.ah + 1] = {itemID = e.id, count = 3, buyout = math.max(1, math.floor(vs * 0.5)) * 3, bid = 1, owner = "Cheap Seller", timeLeft = 1}
		end
		if special == "deal" then
			W.ah[#W.ah + 1] = {itemID = e.id, count = 5, buyout = math.floor(base * 0.3) * 5, bid = 1, owner = "Hasty Seller", timeLeft = 1}
		end
	end
	-- the auction house hands them over in no particular order
	for i = #W.ah, 2, -1 do
		local j = r(1, i)
		W.ah[i], W.ah[j] = W.ah[j], W.ah[i]
	end
	return #W.ah
end
