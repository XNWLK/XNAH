-- XNAH test scenes, part 44: your own order of the tracked list (Items view) - dragging a row with the mouse (press, move,
-- let go: tools/world-mouse.lua), the line where it lands, the dimmed row and the copy at the mouse, scrolling near the
-- edges, the order saved over a reload (XNAHDB.watchOrder), items added and taken off, a click that is not a drag, and
-- the "Your order" sort against the column sorts.
-- Every scene title starts with "44" (node tools/test.js 44).

local function has(text, part) return type(text) == "string" and text:find(part, 1, true) ~= nil end
local function openItems(X)
	if not X.UI.Frame() or not X.UI.Frame():IsShown() then X.UI.Toggle() end
	X.UI.Open("items")
	W.advance(0.3)
	return X.UI.tabs.items.panel
end
-- items with a name and a price (one record each, a minute ago)
local function items(X, list)
	for _, it in ipairs(list) do X.Record(it[1], X.Now() - 60, it[3], it[3], 10, 2, it[2], 1) end
end
local FIVE = {{"2589", "Linen Cloth", 500}, {"2592", "Wool Cloth", 100}, {"4306", "Silk Cloth", 400},
	{"2770", "Copper Ore", 200}, {"3576", "Tin Bar", 300}}
local function trackAll(X, list) for _, it in ipairs(list) do X.SetWatched(it[1], true) end end
local function shown(tbl)
	local t = {}
	for i, r in ipairs(tbl.items) do t[i] = r.key end
	return table.concat(t, ",")
end
local function saved(X) return table.concat(X.db.watchOrder or {}, ",") end
-- screen heights (as GetCursorPosition gives them) of the middle of row i on screen, and of gap g (0 = above row 1)
local function rowY(tbl, i) return (tbl:GetTop() - 2 - (i - 0.5) * tbl.rowH) * tbl:GetEffectiveScale() end
local function gapY(tbl, g) return (tbl:GetTop() - 2 - g * tbl.rowH) * tbl:GetEffectiveScale() end
local function X0(tbl) return 30 * tbl:GetEffectiveScale() end
-- press on row i, move a little so it is picked up, then to gap g, let go
local function dragRow(tbl, i, g)
	local x = X0(tbl)
	W.mouseDown(tbl.rows[i], x, rowY(tbl, i))
	W.mouseMove(x, rowY(tbl, i) - 8 * tbl:GetEffectiveScale())
	W.advance(0.1)
	W.mouseMove(x, gapY(tbl, g))
	W.advance(0.1)
	W.mouseUp()
	W.advance(0.1)
end
local function headerMark(tbl, i) return W.plain(tbl.headers[i].text or "") end
local function tipText()
	local out = {}
	for _, l in ipairs(W.env.GameTooltip.lines or {}) do out[#out + 1] = W.plain(table.concat(l, " ")) end
	return table.concat(out, "\n")
end

T.scene("44 list order: drag a row to move it", function()
	local X = W.start()
	items(X, FIVE)
	trackAll(X, FIVE)
	local panel = openItems(X)
	local tbl = panel.tbl
	T.check("at first: the order the items were added in", shown(tbl), "2589,2592,4306,2770,3576")
	T.check("and that is saved", saved(X), "2589,2592,4306,2770,3576")
	T.ok("no column sort", tbl.sortCol == nil, tbl.sortCol)
	T.ok("Your order is lit", has(panel.order.label.text, "ffd100"), panel.order.label.text)
	T.ok("no sort mark on the titles", not has(headerMark(tbl, 1), " ^") and not has(headerMark(tbl, 1), " v"), headerMark(tbl, 1))
	T.ok("the line above says rows can be dragged", has(W.plain(panel.showing.text), "drag to move"), panel.showing.text)
	X.UI.ShowItem("4306")
	W.advance(0.2)
	-- Linen Cloth (row 1) under Silk Cloth (row 3): picked up, then let go at the gap under row 3
	local x = X0(tbl)
	W.mouseDown(tbl.rows[1], x, rowY(tbl, 1))
	W.advance(0.1)
	T.ok("pressed, not moved: not picked up yet", not panel.ghost:IsShown())
	W.mouseMove(x, rowY(tbl, 1) - 8)
	W.advance(0.1)
	T.ok("moved a few pixels: picked up (a copy follows the mouse)", panel.ghost:IsShown())
	T.ok("the copy shows its name", has(W.plain(panel.ghost.label.text or ""), "Linen Cloth"), panel.ghost.label.text)
	T.ok("the row is dimmed", tbl.rows[1]:GetAlpha() < 0.5, tbl.rows[1]:GetAlpha())
	T.ok("other rows are not", tbl.rows[2]:GetAlpha() == 1)
	W.mouseMove(x, gapY(tbl, 3) - 2)
	W.advance(0.1)
	T.ok("a line shows where it lands", panel.dropLine:IsShown())
	local p = panel.dropLine.points[1]
	T.check("the line: under row 3", p and p[5], -1 - 3 * tbl.rowH)
	T.check("still in the old order while dragging", shown(tbl), "2589,2592,4306,2770,3576")
	W.mouseUp()
	W.advance(0.1)
	T.check("let go: moved there", shown(tbl), "2592,4306,2589,2770,3576")
	T.check("saved", saved(X), "2592,4306,2589,2770,3576")
	T.check("letting go was not a click (the item shown stays)", X.UI.itemKey, "4306")
	T.ok("the copy and the line are gone", not panel.ghost:IsShown() and not panel.dropLine:IsShown())
	T.ok("no row dimmed after", tbl.rows[3]:GetAlpha() == 1)
	T.ok("no column sort after", tbl.sortCol == nil)
	-- the last one to the top
	dragRow(tbl, 5, 0)
	T.check("last row to the top", shown(tbl), "3576,2592,4306,2589,2770")
	-- dropping onto its own place: nothing changes
	dragRow(tbl, 2, 1)
	T.check("dropped where it was: same order", shown(tbl), "3576,2592,4306,2589,2770")
	-- let go far to the side of the list: nothing moves
	W.mouseDown(tbl.rows[1], x, rowY(tbl, 1))
	W.mouseMove(x, rowY(tbl, 1) - 10)
	W.advance(0.1)
	W.mouseMove(x + 400, gapY(tbl, 4))
	W.advance(0.1)
	T.ok("off the list: no line", not panel.dropLine:IsShown())
	W.mouseUp()
	W.advance(0.1)
	T.check("let go off the list: nothing moved", shown(tbl), "3576,2592,4306,2589,2770")
	-- the window made smaller: the mouse is read in the window's own size
	X.UI.SetScale(0.8)
	W.advance(0.1)
	T.ok("window scaled", math.abs(tbl:GetEffectiveScale() - 0.8) < 0.01, tbl:GetEffectiveScale())
	dragRow(tbl, 1, 3)
	T.check("scaled window: moved to the right place", shown(tbl), "2592,4306,3576,2589,2770")
	T.check("no errors", #W.errors, 0)
end)

T.scene("44 list order: a click is not a drag", function()
	local X = W.start()
	items(X, FIVE)
	trackAll(X, FIVE)
	local panel = openItems(X)
	local tbl = panel.tbl
	local x = X0(tbl)
	-- a press with a tiny wobble: a click
	W.mouseDown(tbl.rows[2], x, rowY(tbl, 2))
	W.mouseMove(x + 2, rowY(tbl, 2) - 3)
	W.advance(0.2)
	T.ok("a small wobble does not pick it up", not panel.ghost:IsShown())
	W.mouseUp()
	W.advance(0.1)
	T.check("the click picked the item", X.UI.itemKey, "2592")
	T.check("order unchanged", shown(tbl), "2589,2592,4306,2770,3576")
	-- held still for a while: still a click
	W.mouseDown(tbl.rows[4], x, rowY(tbl, 4))
	W.advance(1)
	T.ok("held still: not picked up", not panel.ghost:IsShown())
	W.mouseUp()
	W.advance(0.1)
	T.check("then a click", X.UI.itemKey, "2770")
	-- a click right after a drag is a click again
	dragRow(tbl, 1, 2)
	T.check("dragged", shown(tbl), "2592,2589,4306,2770,3576")
	T.check("the drag did not pick anything", X.UI.itemKey, "2770")
	W.mouseDown(tbl.rows[3], x, rowY(tbl, 3))
	W.mouseUp()
	W.advance(0.1)
	T.check("the next click picks again", X.UI.itemKey, "4306")
	-- right-click: the item menu, nothing dragged
	W.mouseDown(tbl.rows[1], x, rowY(tbl, 1), "RightButton")
	W.mouseMove(x, rowY(tbl, 1) - 20)
	W.advance(0.1)
	T.ok("right button held and moved: no drag", not panel.ghost:IsShown())
	W.mouseUp("RightButton")
	W.advance(0.1)
	local menu
	for _, f in ipairs(W.frames) do if f.strata == "FULLSCREEN_DIALOG" and f:IsVisible() then menu = f end end
	T.ok("right-click: the item menu", menu ~= nil and W.findButton("Stop tracking", menu) ~= nil)
	X.K.CloseMenu()
	T.check("order unchanged", shown(tbl), "2592,2589,4306,2770,3576")
	-- the double-click is still there on the rows
	T.ok("double-click still set on the rows", tbl.rows[1].scripts.OnDoubleClick ~= nil)
	T.check("no errors", #W.errors, 0)
end)

T.scene("44 list order: kept after a reload", function()
	local X = W.start()
	items(X, FIVE)
	trackAll(X, FIVE)
	local panel = openItems(X)
	dragRow(panel.tbl, 4, 0)
	dragRow(panel.tbl, 5, 2)
	local want = "2770,2589,3576,2592,4306"
	T.check("moved twice", shown(panel.tbl), want)
	X = W.reload()
	T.check("after /reload: the saved order", saved(X), want)
	panel = openItems(X)
	T.check("after /reload: the list in that order", shown(panel.tbl), want)
	T.ok("after /reload: still Your order", panel.tbl.sortCol == nil)
	T.check("no errors", #W.errors, 0)
end)

T.scene("44 list order: adding and taking off items", function()
	local X = W.start()
	items(X, FIVE)
	items(X, {{"2996", "Bolt of Linen Cloth", 150}, {"2997", "Bolt of Woolen Cloth", 250}})
	trackAll(X, FIVE)
	local panel = openItems(X)
	dragRow(panel.tbl, 5, 0)
	T.check("own order", shown(panel.tbl), "3576,2589,2592,4306,2770")
	-- a new item goes at the end
	X.SetWatched("2996", true)
	W.advance(0.3)
	T.check("added: at the end", shown(panel.tbl), "3576,2589,2592,4306,2770,2996")
	-- tracking an item already tracked does not move it
	X.SetWatched("2589", true)
	T.check("tracked again: stays where it is", saved(X), "3576,2589,2592,4306,2770,2996")
	-- a highest price set: stays where it is
	X.SetWatchMax("2592", 99)
	T.check("highest price set: stays", saved(X), "3576,2589,2592,4306,2770,2996")
	-- taken off: gone, the others keep their places
	X.SetWatched("2592", false)
	W.advance(0.3)
	T.check("taken off: gone", shown(panel.tbl), "3576,2589,4306,2770,2996")
	T.check("taken off: saved", saved(X), "3576,2589,4306,2770,2996")
	-- tracked again later: at the end
	X.SetWatched("2592", true)
	W.advance(0.3)
	T.check("tracked again: at the end", shown(panel.tbl), "3576,2589,4306,2770,2996,2592")
	-- added through the Add an item box: at the end too
	W.type(panel.add, "Bolt of Woolen Cloth")
	W.advance(0.3)
	T.ok("added by name", X.Watched("2997"))
	T.check("added by name: at the end", shown(panel.tbl), "3576,2589,4306,2770,2996,2592,2997")
	-- saved data from before there was an order: by name (as the list was sorted before)
	X.db.watchOrder = nil
	T.check("no saved order: by name", table.concat(X.WatchOrder(), ","), "2996,2997,2770,2589,4306,3576,2592")
	-- a saved order with an item no longer tracked, one twice, and one tracked item missing
	X.db.watchOrder = {"4306", "9999", "2589", "4306", "3576"}
	local order = X.WatchOrder()
	T.check("cleaned: untracked dropped, each once, missing ones at the end by name", table.concat(order, ","),
		"4306,2589,3576,2996,2997,2770,2592")
	T.check("X.MoveWatched to the top", X.MoveWatched("2592", 1), true)
	T.check("moved", saved(X), "2592,4306,2589,3576,2996,2997,2770")
	T.check("X.MoveWatched to its own place: no move", X.MoveWatched("2592", 1), false)
	T.check("X.MoveWatched of an item not tracked: no move", X.MoveWatched("9999", 2), false)
	T.check("no errors", #W.errors, 0)
end)

T.scene("44 list order: from a column sort to Your order", function()
	local X = W.start()
	items(X, FIVE)
	trackAll(X, FIVE)
	local panel = openItems(X)
	local tbl = panel.tbl
	-- a column title: sorted by it, Your order not lit, the order kept for later
	tbl.headerButtons[2]:Click("LeftButton")
	T.check("sorted by Cheapest", shown(tbl), "2592,2770,3576,4306,2589")
	T.ok("the title shows the sort", has(headerMark(tbl, 2), "Cheapest ^"), headerMark(tbl, 2))
	T.ok("Your order not lit", not has(panel.order.label.text, "ffd100"), panel.order.label.text)
	T.check("your order is kept meanwhile", saved(X), "2589,2592,4306,2770,3576")
	W.hover(panel.order)
	T.ok("its hover says what is shown", has(tipText(), "Sorted by \"Cheapest\""), tipText())
	W.unhover(panel.order)
	-- Your order: back
	panel.order:Click("LeftButton")
	T.check("Your order: back to it", shown(tbl), "2589,2592,4306,2770,3576")
	T.ok("lit again", has(panel.order.label.text, "ffd100"))
	T.ok("no sort mark", not has(headerMark(tbl, 2), "^"), headerMark(tbl, 2))
	W.hover(panel.order)
	T.ok("its hover says how to drag", has(tipText(), "drag it up or down"), tipText())
	W.unhover(panel.order)
	-- sorted again, then a drag: the order on screen becomes your order, then the move
	tbl.headerButtons[2]:Click("LeftButton")
	T.ok("sorted again", tbl.sortCol == 2)
	T.ok("the sort is remembered", X.S().sorts[tbl.saveKey] ~= nil)
	local x = X0(tbl)
	W.mouseDown(tbl.rows[1], x, rowY(tbl, 1))
	W.mouseMove(x, rowY(tbl, 1) - 8)
	W.advance(0.1)
	T.ok("picked up: Your order now", tbl.sortCol == nil)
	T.check("nothing jumped: the rows as they were shown", shown(tbl), "2592,2770,3576,4306,2589")
	T.check("that is your order now", saved(X), "2592,2770,3576,4306,2589")
	T.ok("Your order lit", has(panel.order.label.text, "ffd100"))
	T.ok("the sort is no longer remembered", X.S().sorts[tbl.saveKey] == nil)
	W.mouseMove(x, gapY(tbl, 2))
	W.advance(0.1)
	W.mouseUp()
	W.advance(0.1)
	T.check("then moved", shown(tbl), "2770,2592,3576,4306,2589")
	T.check("and saved", saved(X), "2770,2592,3576,4306,2589")
	-- a column sort is remembered over a reload, and so is Your order
	tbl.headerButtons[1]:Click("LeftButton")
	X = W.reload()
	panel = openItems(X)
	T.check("after /reload: the column sort", panel.tbl.sortCol, 1)
	panel.order:Click("LeftButton")
	X = W.reload()
	panel = openItems(X)
	T.ok("after /reload: Your order", panel.tbl.sortCol == nil)
	T.check("in your order", shown(panel.tbl), "2770,2592,3576,4306,2589")
	-- the hover on the Item title says rows can be dragged
	W.hover(panel.tbl.headerButtons[1])
	T.ok("Item title hover: drag", has(tipText(), "drag it up or down"), tipText())
	T.ok("Item title hover: the double-click line kept", has(tipText(), "double-click"), tipText())
	W.unhover(panel.tbl.headerButtons[1])
	T.check("no errors", #W.errors, 0)
end)

T.scene("44 list order: near the edge the list scrolls", function()
	local X = W.start()
	local list = {}
	for i = 1, 60 do list[i] = {tostring(60000 + i), string.format("Item %02d", i), 100 + i} end
	items(X, list)
	trackAll(X, list)
	local panel = openItems(X)
	local tbl = panel.tbl
	local rows = #tbl.rows
	T.ok("more items than rows", rows < 60, rows)
	local x = X0(tbl)
	-- picked up at the top, held near the bottom edge: scrolls down a row at a time
	W.mouseDown(tbl.rows[1], x, rowY(tbl, 1))
	W.mouseMove(x, rowY(tbl, 1) - 8)
	W.advance(0.1)
	W.mouseMove(x, gapY(tbl, rows) + 6) -- inside the last row, near the bottom
	W.advance(1)
	local near = tbl.offset
	T.ok("near the bottom edge: scrolled", near >= 4 and near <= 12, near)
	-- past the edge: faster
	W.mouseMove(x, gapY(tbl, rows) - 20)
	W.advance(1)
	local past = tbl.offset - near
	T.ok("past the edge: faster", past > near, {near = near, past = past})
	-- in the middle: stops
	W.mouseMove(x, gapY(tbl, 10))
	local o = tbl.offset
	W.advance(1)
	T.check("in the middle: no scrolling", tbl.offset, o)
	W.mouseUp()
	W.advance(0.1)
	T.check("dropped further down: at its new place", shown(tbl):match("^[^,]+"), "60002")
	local pos
	for i, k in ipairs(X.db.watchOrder) do if k == "60001" then pos = i end end
	T.check("its new place: under row 10 on screen", pos, o + 10)
	-- near the top edge: back up
	W.mouseDown(tbl.rows[5], x, rowY(tbl, 5))
	W.mouseMove(x, rowY(tbl, 5) - 8)
	W.advance(0.1)
	W.mouseMove(x, gapY(tbl, 0) + 20) -- above the list
	W.advance(3)
	T.check("past the top edge: scrolled to the top", tbl.offset, 0)
	W.mouseUp()
	W.advance(0.1)
	-- the window closed while dragging: dropped, nothing moved
	local before = saved(X)
	W.mouseDown(tbl.rows[2], x, rowY(tbl, 2))
	W.mouseMove(x, rowY(tbl, 2) - 30)
	W.advance(0.1)
	T.ok("picked up", panel.ghost:IsShown())
	panel.dragger:Hide() -- (as the game does when the window closes: its frames hide)
	W.advance(0.1)
	T.ok("closed: the copy is gone", not panel.ghost:IsShown())
	W.mouseUp()
	W.advance(0.1)
	T.check("closed while dragging: nothing moved", saved(X), before)
	T.check("no errors", #W.errors, 0)
end)
