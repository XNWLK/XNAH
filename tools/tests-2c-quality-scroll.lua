-- XNAH test scenes, part 2c: item quality (name colours) and the scroll bar of the lists.

T.scene("quality: a wrong saved quality is corrected by the game", function()
	local X = W.start()
	W.list(15210, 50000, 1, 1, "Cid", -19)
	W.list(15210, 40000, 1, 1, "Dan")
	W.openAH()
	T.ok("full scan finished", T.fullScan(X))
	local q = W.items[15210].quality
	T.ok("the test item is not white", q and q >= 2, q)
	-- as Xn saw: saved as white (the full scan gave a wrong quality while the item was not loaded)
	X.Items()["15210"].q = 1
	X.Items()["15210:-19"].q = 1
	X.qualityOK = {}
	local _, got = X.ItemName("15210")
	T.check("asking for the name fixes the quality", got, q)
	X.qualityOK = {}
	X.Items()["15210:-19"].q = 1
	X.NameLoaded(15210)
	T.check("the random-bonus key is fixed too", X.Items()["15210:-19"].q, q)
	T.check("quality from a link colour (epic)", X.QualityFromLink("|cffa335ee|Hitem:1::::|h[x]|h|r"), 4)
	T.check("no link, no quality", X.QualityFromLink(nil), nil)
end)

T.scene("scroll bar: lists scroll by the bar and the wheel", function()
	local X = W.start()
	W.makeMarket(5, 300)
	W.openAH()
	T.ok("full scan finished", T.fullScan(X))
	X.UI.Open("market")
	W.advance(5) -- the market rows are built in slices
	local list
	W.walk(W.env.UIParent, function(f) if f.track and f.thumb and f.items and #f.items > 50 then list = f end end)
	T.ok("the market list has a scroll bar", list ~= nil)
	if not list then return end
	T.ok("the bar is shown when there are more rows than fit", list.track.shown ~= false)
	T.check("starts at the top", list.offset, 0)
	list.track.scripts.OnClick(list.track)
	T.ok("a click on the bar moves down a page", list.offset > 0, list.offset)
	local before = list.offset
	list.scripts.OnMouseWheel(list, 1)
	T.ok("the wheel moves up", list.offset < before, list.offset)
	-- a short list: no bar
	list:SetItems({list.items[1]})
	T.check("one row: the bar hides", list.track.shown, false)
end)
