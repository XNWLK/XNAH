-- XNAH test scenes, part 39: your own notes on the graphs (GraphNotes.lua: saved per realm, the cap, removed notes
-- remembered for Sync accounts, the lines on every graph over time, the hover text, the right-click menu and its box)
-- and the usual range band (X.UsualBand in Graph.lua: the middle half of the 30 days of day prices up to each day, the
-- dots of prices well outside it, its toggle on the Overview and on Compare). Every scene title starts with "39"
-- (node tools/test.js 39).

local DAY = 86400
local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function items(X) return X.UI.tabs.items.panel end
local function openMenu()
	for _, f in ipairs(W.frames) do
		if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then return f end
	end
end
-- one price a day for `days` days up to yesterday (a little after the day starts), oldest first: priceOf(daysAgo)
local function daily(X, key, days, priceOf, name)
	local today = X.Day()
	for d = days, 1, -1 do
		local v = priceOf(d)
		X.Record(key, (today - d) * DAY + 3600, v, v, 20, 4, name, 1)
	end
end
-- the mouse at x over a graph (a frame passes, the box follows); the box's text
local function hoverAt(g, x)
	W.cursor = {x, 10}
	W.hover(g.plot, x, 10)
	W.advance(0.1)
	local text = g.tip:IsShown() and W.plain(g.tip.text:GetText() or "") or ""
	W.unhover(g.plot)
	return text
end
-- a right-click at x over a graph: the menu (or nil)
local function rightClick(g, x)
	W.cursor = {x, 40}
	g.plot.scripts.OnMouseUp(g.plot, "RightButton")
	return openMenu()
end
local function dialog() return W.env.XNAHDialog end
local function noteAt(info, day)
	for _, n in ipairs(info.notes or {}) do if n.day == day then return n end end
end

T.scene("39 notes: saved per realm, cleaned, capped, removed ones remembered", function()
	local X = W.start()
	local today = X.Day()
	T.check("nothing yet", X.NoteGet(today), nil)
	T.check("no table saved before the first note", X.Realm().notes, nil)
	T.check("none counted", X.NotesCount(), 0)
	T.ok("a note", X.NoteSet(today - 3, "  patch day  "))
	T.check("trimmed", X.NoteGet(today - 3), "patch day")
	T.check("saved under the realm", X.Realm().notes[today - 3].x, "patch day")
	T.check("with when it was written", X.Realm().notes[today - 3].t, X.Now())
	X.NoteSet(today - 2, "a |cffff0000red|r\nline")
	T.check("no colour codes or line breaks", X.NoteGet(today - 2), "a /cffff0000red/r line")
	X.NoteSet(today - 1, string.rep("x", 100))
	T.check("at most 60 letters", #X.NoteGet(today - 1), X.NOTE_LEN)
	X.NoteSet(today - 3, "patch 1.2")
	T.check("changed", X.NoteGet(today - 3), "patch 1.2")
	T.check("three notes", X.NotesCount(), 3)
	-- between two times, oldest first; a day counts when any part of it is inside
	local list = X.NotesBetween((today - 3) * DAY + 80000, (today - 2) * DAY + 10)
	T.check("between: two days", #list, 2)
	T.check("between: oldest first", list[1] and list[1].text, "patch 1.2")
	T.check("between: at noon", list[1] and list[1].t, (today - 3) * DAY + DAY / 2)
	-- an empty text removes it; the removal is remembered (no text) for Sync accounts
	T.ok("removed by an empty text", X.NoteSet(today - 2, "   "))
	T.check("gone", X.NoteGet(today - 2), nil)
	local gone = X.Realm().notes[today - 2]
	T.ok("the removal is remembered", gone and gone.x == nil and gone.t == X.Now())
	X.NoteRemove(today - 1)
	T.check("removed", X.NoteGet(today - 1), nil)
	T.check("one note left", X.NotesCount(), 1)
	T.check("not between any more", #X.NotesBetween(0, X.Now() + DAY), 1)
	-- removals over 120 days old are forgotten at the next change
	X.Realm().notes[today - 2].t = X.Now() - 121 * DAY
	X.NoteSet(today - 5, "new raid opened")
	T.check("an old removal forgotten", X.Realm().notes[today - 2], nil)
	T.ok("a recent removal kept", X.Realm().notes[today - 1] ~= nil)
	-- the cap: X.NOTES_MAX notes, then no new one (changing one still works)
	local before = W.savedSize()
	for d = 1, X.NOTES_MAX do
		if X.NotesCount() < X.NOTES_MAX then X.NoteSet(today - 400 - d, "note number " .. d .. string.rep(" with some words", 3)) end
	end
	T.check("full", X.NotesCount(), X.NOTES_MAX)
	local ok, why = X.NoteSet(today + 1, "one more")
	T.check("no room for a new one", tostring(ok) .. " " .. tostring(why), "false full")
	T.ok("changing one still works", X.NoteSet(today - 3, "patch 1.3"))
	local size = W.savedSize() - before
	T.ok("200 long notes stay small (under 30 KB)", size < 30000, size)
	T.note(string.format("notes: %d notes of about 55 letters = %d bytes saved (%.0f per note)", X.NOTES_MAX, size,
		size / X.NOTES_MAX))
	-- saved and read back
	W.reload()
	X = W.X
	T.check("after a reload", X.NoteGet(today - 3), "patch 1.3")
end)

T.scene("39 notes: joined when realms are joined, the last written wins", function()
	local X = W.start()
	local today = X.Day()
	local a = {notes = {[today - 1] = {t = 100, x = "old"}, [today - 2] = {t = 300, x = "kept"}, [today - 3] = {t = 50, x = "back?"}}}
	local b = {notes = {[today - 1] = {t = 200, x = "newer"}, [today - 2] = {t = 100, x = "older"}, [today - 3] = {t = 90},
		[today - 4] = {t = 10, x = "only here"}}}
	X.MergeNotes(a, b)
	T.check("the newer text wins", a.notes[today - 1].x, "newer")
	T.check("the older text loses", a.notes[today - 2].x, "kept")
	T.check("a newer removal wins", a.notes[today - 3].x, nil)
	T.check("a note only in one", a.notes[today - 4].x, "only here")
	local c = {}
	X.MergeNotes(c, {})
	T.check("nothing to join: nothing made", c.notes, nil)
	-- the realm joining at login (X.MigrateRealms): notes filed under an old realm key come along
	local key = X.RealmKey()
	if key:match("^Realm %d+$") then
		X.NoteSet(today - 1, "here")
		X.db.realms[key .. "-Horde"] = {items = {}, scans = {}, notes = {[today - 6] = {t = X.Now() - 60, x = "from the old key"},
			[today - 1] = {t = X.Now() - 600, x = "older one"}}}
		X.MigrateRealms(key)
		T.check("old key: its note comes along", X.NoteGet(today - 6), "from the old key")
		T.check("old key: the newer note stays", X.NoteGet(today - 1), "here")
		T.check("old key gone", X.db.realms[key .. "-Horde"], nil)
	else
		T.ok("realm key " .. key .. " (no join to test)", true)
	end
end)

T.scene("39 notes: on the price graph - line, hover, right-click to add, change and remove", function()
	local X = W.start()
	daily(X, "2589", 20, function(d) return 1000 + (d % 3) * 20 end, "Linen Cloth")
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = items(X)
	local g = panel.graph
	T.check("no notes yet", #g.GetInfo().notes, 0)
	T.ok("the hint tells about the right-click", has(W.screen(panel), "right-click to add a note"), W.screen(panel))
	local today = X.Day()
	-- a note saved somewhere else shows on the graph at once (graphs shown draw again)
	X.NoteSet(today - 10, "patch")
	local info = g.GetInfo()
	local n = noteAt(info, today - 10)
	T.ok("the note's line is drawn", n ~= nil and n.text == "patch")
	T.ok("inside the graph", n and n.x > 0 and n.x < g.plot:GetWidth())
	-- notes outside the time drawn are not
	X.NoteSet(today - 200, "long ago")
	T.check("a note far back: not on the 30-day graph", noteAt(g.GetInfo(), today - 200), nil)
	-- the mouse at the line: the box tells the note
	local text = hoverAt(g, n.x + 2)
	T.ok("hover: the note", has(text, "Your note") and has(text, "patch"), text)
	text = hoverAt(g, n.x + 40)
	T.ok("hover away from it: no note", not has(text, "Your note"), text)
	-- right-click on an empty spot: add a note for that day
	local x = n.x + 120
	local day = X.Day(g.GetInfo().marks[1].t + (g.GetInfo().marks[#g.GetInfo().marks].t - g.GetInfo().marks[1].t) * x /
		g.plot:GetWidth())
	local menu = rightClick(g, x)
	T.ok("a menu", menu ~= nil)
	T.ok("menu: add a note for the day", menu and has(W.screen(menu), "Add a note for " .. X.NoteDayText(day)), menu and W.screen(menu))
	W.click("Add a note for", menu)
	local dlg = dialog()
	T.ok("a box to type it", dlg and dlg:IsVisible())
	T.ok("the box names the day", dlg and has(W.screen(dlg), X.NoteDayText(day)), dlg and W.screen(dlg))
	W.type(dlg.line, "new raid opened")
	T.check("saved for that day", X.NoteGet(day), "new raid opened")
	T.ok("the box closed", not dlg:IsVisible())
	T.ok("drawn at once", noteAt(g.GetInfo(), day) ~= nil)
	-- right-click at its line: change or remove
	local m = noteAt(g.GetInfo(), day)
	menu = rightClick(g, m.x + 1)
	local screen = menu and W.screen(menu) or ""
	T.ok("menu: the note", has(screen, "new raid opened"), screen)
	T.ok("menu: change it", has(screen, "Change this note"))
	T.ok("menu: remove it", has(screen, "Remove this note"))
	T.ok("menu: no second add for the same day", not has(screen, "Add a note"), screen)
	W.click("Change this note", menu)
	T.check("the box has the text", dlg.line:GetText(), "new raid opened")
	W.type(dlg.line, "new raid opened (Molten Core)")
	T.check("changed", X.NoteGet(day), "new raid opened (Molten Core)")
	menu = rightClick(g, m.x)
	W.click("Remove this note", menu)
	T.check("removed", X.NoteGet(day), nil)
	T.check("its line is gone", noteAt(g.GetInfo(), day), nil)
	-- emptying the box removes it too
	menu = rightClick(g, n.x)
	W.click("Change this note", menu)
	W.type(dlg.line, "")
	T.check("an empty box removes it", X.NoteGet(today - 10), nil)
	-- a graph with nothing on it: no menu
	local g2 = X.K.Graph(W.env.UIParent, 300, 120)
	g2:SetSeries({}, {empty = "Nothing"})
	T.check("empty graph: no menu", rightClick(g2, 50), nil)
	T.ok("no errors", #W.errors == 0, table.concat(W.errors, "\n"))
end)

T.scene("39 notes: on every graph over time (Compare, Gold over time, a plain graph)", function()
	local X = W.start()
	daily(X, "2770", 20, function(d) return 100 + d end, "Copper Ore")
	daily(X, "2840", 20, function(d) return 300 - d end, "Copper Bar")
	local today = X.Day()
	X.NoteSet(today - 5, "patch")
	-- a plain graph: shown unless notes = false
	local g = X.K.Graph(W.env.UIParent, 400, 150)
	g:SetSeries({{points = {{(today - 8) * DAY, 100}, {X.Now(), 120}}, label = "Old"}})
	T.check("plain graph: the note", #g.GetInfo().notes, 1)
	g:SetSeries({{points = {{(today - 8) * DAY, 100}, {X.Now(), 120}}, label = "Old"}}, {notes = false})
	T.check("plain graph: notes = false", #g.GetInfo().notes, 0)
	g:SetSeries({{points = {{(today - 3) * DAY, 100}, {X.Now(), 120}}, label = "Old"}})
	T.check("plain graph: the note's day is not drawn", #g.GetInfo().notes, 0)
	-- today's note shows even before noon (the line sits at the right edge then)
	X.NoteSet(today, "today")
	g:SetSeries({{points = {{(today - 1) * DAY, 100}, {today * DAY + 600, 120}}, label = "Old"}})
	local n = noteAt(g.GetInfo(), today)
	T.ok("today's note before noon: at the right edge", n and math.abs(n.x - g.plot:GetWidth()) < 0.01, n and n.x)
	X.NoteRemove(today)
	-- Compare
	X.UI.Toggle()
	X.UI.ShowItem("2770")
	W.advance(0.3)
	W.click("Compare", items(X))
	W.advance(0.3)
	local page = items(X).pages.frames.compare
	X.CompareAdd("2770", "2840")
	X.UI.Refresh(true)
	W.advance(0.3)
	T.check("compare: the note", noteAt(page.graph.GetInfo(), today - 5) and noteAt(page.graph.GetInfo(), today - 5).text, "patch")
	W.click("% change", page)
	T.ok("compare % change: the note too", noteAt(page.graph.GetInfo(), today - 5) ~= nil)
	W.click("Price", page)
	-- Gold over time: a month of gold
	W.setMoney(100000)
	W.advance(5)
	for i = 1, 10 do
		W.advance(DAY)
		W.setMoney(100000 + i * 1000)
		W.advance(5)
	end
	X.NoteSet(X.Day() - 4, "sold the stock")
	X.UI.Open("gold")
	W.advance(1)
	local gp = X.UI.tabs.gold.panel
	W.click("Gold over time", gp)
	W.advance(0.5)
	local f = gp.views.history
	T.ok("gold over time: the note on the gold graph", noteAt(f.gold.GetInfo(), X.Day() - 4) ~= nil)
	T.ok("no errors", #W.errors == 0, table.concat(W.errors, "\n"))
end)

T.scene("39 usual range: the maths agree with the usual price", function()
	local X = W.start()
	-- 40 days: 100 .. 139 (one more each day, oldest cheapest)
	daily(X, "2589", 40, function(d) return 140 - d end, "Linen Cloth")
	local band = X.UsualBand("2589")
	T.ok("a range for most days", #band >= 36, #band)
	local today = X.Day()
	local last = band[#band]
	T.check("the last one: yesterday at noon", last[1], (today - 1) * DAY + DAY / 2)
	-- yesterday's 30 days: 110 .. 139 -> 25% = 117.25, 75% = 131.75
	T.near("lo = 25th percentile", last[2], 117.25, 0.01)
	T.near("hi = 75th percentile", last[3], 131.75, 0.01)
	-- the first days have too few prices
	T.check("the first day: none", band[1][1] > (today - 40) * DAY + DAY / 2, true)
	T.check("from: only days after it", #X.UsualBand("2589", (today - 5) * DAY), 5)
	-- the usual price (30-day average) is inside today's range
	X.Record("2589", X.Now(), 140, 140, 20, 4)
	band = X.UsualBand("2589")
	last = band[#band]
	local usual = X.Usual("2589")
	T.ok("the usual price is inside today's range", usual >= last[2] and usual <= last[3], usual .. " in " .. last[2] .. " - " .. last[3])
	T.check("the same days as the usual price", X.BAND.days, 30)
	-- silly prices are left out, like for the usual price
	daily(X, "2592", 10, function(d) return d == 4 and 100000 or 500 end, "Wool Cloth")
	band = X.UsualBand("2592")
	T.ok("a silly price does not stretch the range", band[#band][3] <= 500, band[#band][3])
	-- a new item: too few days
	daily(X, "2996", 3, function() return 50 end, "Bolt of Linen Cloth")
	T.check("3 days: no range yet", #X.UsualBand("2996"), 0)
	T.check("unknown item: none", #X.UsualBand("999999"), 0)
	T.check("quantile of nothing", X.Quantile({}, 0.5), nil)
	T.check("quantile of one", X.Quantile({7}, 0.75), 7)
	-- worked out once per day per item (until its day prices change)
	local a1 = X.UsualBand("2589")
	T.ok("kept (the same list)", X.UsualBand("2589")[1] == a1[1])
end)

T.scene("39 usual range: on the Overview graph and on Compare, with its toggle", function()
	local X = W.start()
	-- steady around 1000, then a jump to 1600 two days ago and a drop to 500 yesterday
	daily(X, "2589", 40, function(d) return d == 2 and 1600 or (d == 1 and 500 or 1000 + (d % 4) * 10) end, "Linen Cloth")
	T.check("on by default", X.S().usualBand, true)
	X.UI.Toggle()
	X.UI.ShowItem("2589")
	W.advance(0.5)
	local panel = items(X)
	local g = panel.graph
	local info = g.GetInfo()
	T.ok("the band is drawn", info.band ~= nil and #info.band.pts >= 25, info.band and #info.band.pts)
	T.check("checked against the market value", info.band and info.band.line and info.band.line.label, "Market value")
	local above, below = 0, 0
	for _, o in ipairs(info.outside) do
		if o.how == "above" then above = above + 1 else below = below + 1 end
	end
	T.check("the jump: a red dot", above, 1)
	T.check("the drop: a green dot", below, 1)
	T.ok("the name under the graph", W.findButton("Usual range", panel) ~= nil)
	-- the hover box tells the range and that the price was well over it
	local o
	for _, e in ipairs(info.outside) do if e.how == "above" then o = e end end
	local mx
	for _, m in ipairs(info.marks) do if m.t == o.t then mx = m.x end end
	local text = hoverAt(g, mx)
	T.ok("hover: the range", has(text, "Usual range"), text)
	T.ok("hover: well over it", has(text, "well over the usual range"), text)
	-- the toggle: off and on again, kept in the settings
	W.click("Usual range", panel)
	T.check("off: saved", X.S().usualBand, false)
	T.check("off: no band", g.GetInfo().band, nil)
	T.check("off: no dots", #g.GetInfo().outside, 0)
	T.ok("off: the name stays (to switch it on)", W.findButton("Usual range", panel) ~= nil)
	W.click("Usual range", panel)
	T.check("on again", X.S().usualBand, true)
	T.ok("drawn again", g.GetInfo().band ~= nil)
	-- the market value hidden: the band stays, no dots
	W.click("Market value", panel)
	T.ok("market value hidden: band still there", g.GetInfo().band ~= nil)
	T.check("market value hidden: no dots", #g.GetInfo().outside, 0)
	W.click("Market value", panel)
	-- 7 days: only the band of those days
	W.click("7 days", panel)
	T.ok("7 days: a short band", g.GetInfo().band and #g.GetInfo().band.pts <= 8, g.GetInfo().band and #g.GetInfo().band.pts)
	W.click("30 days", panel)
	-- an item with too little history: no band, no name under the graph
	daily(X, "2996", 2, function() return 50 end, "Bolt of Linen Cloth")
	X.UI.ShowItem("2996")
	W.advance(0.3)
	T.check("new item: no band", g.GetInfo().band, nil)
	T.ok("new item: no name for it", W.findButton("Usual range", panel) == nil)
	-- Compare: price only, the same setting
	daily(X, "2592", 40, function() return 800 end, "Wool Cloth")
	X.UI.ShowItem("2589")
	W.advance(0.3)
	X.CompareAdd("2589", "2592")
	W.click("Compare", panel)
	W.advance(0.3)
	local page = panel.pages.frames.compare
	local ci = page.graph.GetInfo()
	T.ok("compare: the band of the item picked", ci.band ~= nil and ci.band.line and ci.band.line.label == "Linen Cloth")
	T.check("compare: the dots", #ci.outside, 2)
	W.click("% change", page)
	T.check("compare % change: no band", page.graph.GetInfo().band, nil)
	T.ok("compare % change: no toggle", not page.bandBtn:IsShown())
	W.click("Price", page)
	W.click("Usual range", page)
	T.check("compare toggle: the same setting", X.S().usualBand, false)
	T.check("compare toggle: off", page.graph.GetInfo().band, nil)
	W.click("Usual range", page)
	T.ok("compare toggle: on", page.graph.GetInfo().band ~= nil)
	T.ok("no errors", #W.errors == 0, table.concat(W.errors, "\n"))
end)
