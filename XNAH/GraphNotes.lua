-- Your own notes on the graphs: mark a day with a few words ("patch", "new raid opened"). Every graph over time shows
-- the notes of the days it covers as a thin upright line with a small square on top; the mouse near the line shows the
-- note in the graph's box. Right-click a graph: "Add a note for <day>" (the day under the mouse); right-click near a
-- note's line: change or remove it.
--
-- Saved per realm: X.Realm().notes = {[day] = {t = when it was written (server seconds), x = "the text"}}, day =
-- X.Day() (days since 1970, UTC; the line sits at noon of that day, like the day prices). One note per day, at most
-- X.NOTES_MAX notes of at most X.NOTE_LEN letters. A removed note keeps {t = when} without text for GONE_DAYS days, so
-- Sync accounts (tools/sync-accounts.lua: per day the one written last wins) does not bring it back from another
-- account. Size: about 60 bytes per note plus its text (200 notes: about 20 KB at most).
--
--   X.NoteGet(day) -> text or nil;  X.NoteSet(day, text) -> true, or false, "full" (empty text removes the note)
--   X.NoteRemove(day);  X.NotesBetween(from, to) -> {{day, text, t = noon of the day}, ...} oldest first
--   X.NotesCount();  X.MergeNotes(toRealm, fromRealm) (X.MigrateRealms)
--   X.GraphNoteLayer(g, plot, pw, ph) -> the notes part of one graph (K.Graph makes it):
--     .draw(t0, t1, xOf) -> the notes drawn {{day, text, t, x}} (draw(nil): none), .near(x) -> the note at x or nil,
--     .menu(x, y) the right-click menu at x, y inside the graph
local ADDON, X = ...
local K = X.K

local DAY = 86400
X.NOTES_MAX = 200
X.NOTE_LEN = 60
local GONE_DAYS = 120 -- a removed note is remembered this long (for Sync accounts)
local NEAR = 5        -- pixels: the mouse this close to a note's line is "at" the note
local COLOR = {1, 0.93, 0.55}
local GREY = "|cff999999"

-- [[ the saved notes ]]
local function store(create)
	local r = X.Realm()
	if type(r.notes) ~= "table" then
		if not create then return nil end
		r.notes = {}
	end
	return r.notes
end

function X.NoteGet(day)
	local n = store()
	local e = n and n[day]
	return type(e) == "table" and e.x or nil
end

-- a few words on one line: no colour codes (| becomes /), no line breaks, at most X.NOTE_LEN letters
local function cleanText(text)
	text = X.Trim(tostring(text or "")):gsub("|", "/"):gsub("%c", " ")
	if #text > X.NOTE_LEN then text = X.Trim(text:sub(1, X.NOTE_LEN)) end
	return text
end
X.NoteClean = cleanText

function X.NotesCount()
	local c = 0
	for _, e in pairs(store() or {}) do if type(e) == "table" and e.x then c = c + 1 end end
	return c
end

-- removed notes older than GONE_DAYS go for good
local function prune(n)
	local old = X.Now() - GONE_DAYS * DAY
	for day, e in pairs(n) do
		if type(e) ~= "table" or (not e.x and (e.t or 0) < old) then n[day] = nil end
	end
end

function X.NoteRemove(day)
	day = math.floor(tonumber(day) or 0)
	local n = store()
	if not (n and type(n[day]) == "table" and n[day].x) then return true end
	n[day] = {t = X.Now()}
	prune(n)
	X.NotesChanged()
	return true
end

function X.NoteSet(day, text)
	day = math.floor(tonumber(day) or 0)
	text = cleanText(text)
	if text == "" then return X.NoteRemove(day) end
	local n = store(true)
	local had = type(n[day]) == "table" and n[day].x
	if not had and X.NotesCount() >= X.NOTES_MAX then return false, "full" end
	n[day] = {t = X.Now(), x = text}
	prune(n)
	X.NotesChanged()
	return true
end

-- the notes of the days between two times (server seconds; a day counts when any part of it is inside), oldest first
function X.NotesBetween(from, to)
	local out = {}
	for day, e in pairs(store() or {}) do
		if type(day) == "number" and type(e) == "table" and e.x and day * DAY <= to and (day + 1) * DAY > from then
			out[#out + 1] = {day = day, text = e.x, t = day * DAY + DAY / 2}
		end
	end
	table.sort(out, function(a, b) return a.day < b.day end)
	return out
end

-- one realm's notes into another (X.MigrateRealms): per day the one written last (a removal counts as written)
function X.MergeNotes(to, from)
	if type(from) ~= "table" or type(from.notes) ~= "table" then return end
	to.notes = type(to.notes) == "table" and to.notes or {}
	for day, e in pairs(from.notes) do
		local have = to.notes[day]
		if type(e) == "table" and (type(have) ~= "table" or (e.t or 0) > (have.t or 0)) then to.notes[day] = e end
	end
end

-- [[ the graphs ]] every graph made (weak: a graph thrown away is forgotten); after a change the ones shown draw again
local graphs = setmetatable({}, {__mode = "k"})
function X.NotesChanged()
	for g in pairs(graphs) do
		if g:IsVisible() and g.Redraw then g.Redraw() end
	end
end

local function dayText(day)
	local t = math.floor(day * DAY + DAY / 2)
	local text = (date("%b %d", t):gsub(" 0", " "))
	if date("%Y", t) ~= date("%Y", X.Now()) then text = text .. " " .. date("%Y", t) end
	return text
end
X.NoteDayText = dayText

-- the box to type a note for a day (an empty box removes the note)
local function ask(day)
	local have = X.NoteGet(day)
	K.Ask("Your note for " .. dayText(day) .. GREY .. (have and "  (an empty box removes it)" or "  (a few words)") .. "|r",
		have or "", false, function(text)
		local ok, why = X.NoteSet(day, text)
		if not ok and why == "full" then
			X.Print("You have " .. X.NOTES_MAX .. " notes already - remove an old one first (right-click its line on a graph).")
		end
	end, "Save")
end
X.NoteAsk = ask

function X.GraphNoteLayer(g, plot, pw, ph)
	graphs[g] = true
	local layer = {shown = {}}
	local lines, flags, n = {}, {}, 0
	local anchor = CreateFrame("Frame", nil, plot)
	anchor:SetSize(1, 1)
	local t0, t1

	-- draws the notes of the time t0 .. t1 (xOf = the graph's x of a time); draw(nil) takes them all off
	function layer.draw(a, b, xOf)
		for i = 1, n do
			lines[i]:Hide()
			flags[i]:Hide()
		end
		n, t0, t1 = 0, a, b
		layer.shown = {}
		if not (a and b and b > a) then return layer.shown end
		for _, note in ipairs(X.NotesBetween(a, b)) do
			local x = math.max(0, math.min(pw, xOf(note.t)))
			n = n + 1
			if not lines[n] then
				local l = plot:CreateTexture(nil, "BORDER", nil, 2)
				l:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], 0.5)
				l:SetWidth(1)
				lines[n] = l
				local f = plot:CreateTexture(nil, "OVERLAY", nil, 1)
				f:SetColorTexture(COLOR[1], COLOR[2], COLOR[3], 0.95)
				f:SetSize(5, 5)
				flags[n] = f
			end
			local l, f = lines[n], flags[n]
			l:ClearAllPoints()
			l:SetPoint("TOP", plot, "TOPLEFT", x, 0)
			l:SetPoint("BOTTOM", plot, "BOTTOMLEFT", x, 0)
			l:Show()
			f:ClearAllPoints()
			f:SetPoint("TOP", plot, "TOPLEFT", x, 0)
			f:Show()
			layer.shown[#layer.shown + 1] = {day = note.day, text = note.text, t = note.t, x = x}
		end
		return layer.shown
	end

	-- the note whose line is nearest x (within NEAR pixels), or nil
	function layer.near(x)
		local best, bd
		for _, note in ipairs(layer.shown) do
			local d = math.abs(note.x - x)
			if d <= NEAR and (not bd or d < bd) then best, bd = note, d end
		end
		return best
	end

	-- the right-click menu at x, y (pixels inside the graph): add a note for the day there; change or remove the note
	-- at the mouse
	function layer.menu(x, y)
		if not (t0 and t1) then return nil end
		x = math.max(0, math.min(pw, x or 0))
		local day = X.Day(t0 + (t1 - t0) * x / pw)
		local near = layer.near(x)
		local items = {}
		if near then
			items[#items + 1] = {text = dayText(near.day) .. ": " .. near.text, isTitle = true}
			items[#items + 1] = {text = "Change this note", func = function() ask(near.day) end}
			items[#items + 1] = {text = "Remove this note", func = function() X.NoteRemove(near.day) end}
		end
		if not near or near.day ~= day then
			items[#items + 1] = {text = (X.NoteGet(day) and "Change the note for " or "Add a note for ") .. dayText(day),
				func = function() ask(day) end}
		end
		anchor:ClearAllPoints()
		anchor:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", x, math.max(0, math.min(ph, y or ph)))
		return K.Menu(anchor, items), items
	end

	plot:SetScript("OnMouseUp", function(self, button)
		if button ~= "RightButton" then return end
		local left, bottom = self:GetLeft(), self:GetBottom()
		if not (left and bottom) then return end
		local scale = self:GetEffectiveScale()
		local cx, cy = GetCursorPosition()
		layer.menu(cx / scale - left, cy / scale - bottom)
	end)
	return layer
end
