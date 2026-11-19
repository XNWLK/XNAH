-- XNAH test scenes, part 17: the simple window (UISimple.lua): gold on top, a list on the left, the picked entry on the
-- right with its graph, sentence, reason and one big button; the pages at the bottom; More opens the full window.

T.scene("simple window: layout, picking, the big button, skip, Find, More", function()
	local X = W.start()
	X.Record("2589", X.Now() - 86400, 50, 52, 60, 3, "Linen Cloth", 1)
	X.Record("2589", X.Now(), 40, 41, 80, 4, "Linen Cloth", 1)
	X.Record("2770", X.Now(), 10, 10, 40, 2, "Copper Ore", 1)
	local S = X.Simple
	T.ok("the simple window exists", S ~= nil)
	local ran = 0
	S.AddView("testpage", {title = "Test", order = 99, list = function()
		return {
			{id = "a", key = "2589", title = "Buy 20 Linen Cloth", sub = "you make +5s", sentence = "Buy all 20.", why = "It is cheap.",
				button = {label = "Buy 20 for 8s", run = function() ran = ran + 1 end}, skip = true},
			{id = "b", key = "2770", title = "Sell Copper Ore", sub = "+1s", sentence = "Post them.", graph = false},
		}, "nothing"
	end})
	-- /xnah opens the simple window (setting simpleUI)
	X.Toggle()
	W.advance(0.5)
	T.ok("shown", S.Frame():IsShown())
	T.ok("the full window stays closed", not (X.UI.Frame() and X.UI.Frame():IsShown()))
	S.Select("testpage")
	W.advance(0.5)
	T.check("two entries", #S.list.items, 2)
	T.check("the first is picked", S.detail.entry and S.detail.entry.id, "a")
	T.check("its sentence", S.detail.sentence:GetText(), "Buy all 20.")
	T.check("its button", S.detail.button:GetText(), "Buy 20 for 8s")
	T.ok("its graph", S.detail.graph:IsShown())
	S.detail.button:Click()
	T.check("the button runs the job", ran, 1)
	-- pick the second
	S.list.rows[2]:Click()
	T.check("second picked", S.detail.entry.id, "b")
	T.ok("no graph for it", not S.detail.graph:IsShown())
	T.ok("no button for it", not S.detail.button:IsShown())
	-- skip
	S.list.rows[1]:Click()
	S.detail.skip:Click()
	W.advance(0.5)
	T.check("skipped: one left", #S.list.items, 1)
	-- Find / alt-click: one item on the right
	X.ShowItem("2589")
	W.advance(0.5)
	T.check("an item shown", S.detail.entry and S.detail.entry.id, "item:2589")
	T.ok("its usual price is told", (S.detail.sentence:GetText() or ""):find("usually sells", 1, true) ~= nil, S.detail.sentence:GetText())
	-- the pages at the bottom
	T.ok("page buttons", #S.Frame().nav >= 1)
	-- More: the full window
	local more
	for _, child in ipairs(S.Frame().children or {}) do if child.GetText and child:GetText() == "More" then more = child end end
	T.ok("a More button", more ~= nil)
	if more then more:Click() end
	T.ok("More opens the full window", X.UI.Frame() and X.UI.Frame():IsShown())
	T.ok("and closes the simple one", not S.Frame():IsShown())
	-- the setting off: /xnah opens the full window as before
	X.UI.Frame():Hide()
	X.S().simpleUI = false
	X.Toggle()
	T.ok("simpleUI off: the full window", X.UI.Frame():IsShown())
	X.S().simpleUI = true
	X.UI.Frame():Hide()
	-- /xnah <name> shows the item in the simple window
	W.env.SlashCmdList.XNAH("linen cloth")
	W.advance(0.5)
	T.ok("/xnah <name>: the simple window", S.Frame():IsShown())
	T.check("on that item", S.detail.entry and S.detail.entry.id, "item:2589")
	T.ok("its graph has points", S.detail.graph:IsShown())
end)
