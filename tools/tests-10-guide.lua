-- XNAH test scenes, part 10: the guide window (Guide.lua). It comes by itself on the first login and not after,
-- every part opens, Previous / Next walk through all of them, "Open this page" opens the right tab, the "Show this
-- guide when I log in" box works, Escape closes it.

local function guide() return W.env.XNAHGuide end
local function guideShown()
	local f = guide()
	return f ~= nil and f:IsShown()
end
-- what the game does on Escape: every shown window named in UISpecialFrames is hidden
local function escape()
	for _, name in ipairs(W.env.UISpecialFrames) do
		local f = W.env[name]
		if f and f.IsShown and f:IsShown() then f:Hide() end
	end
end

T.scene("guide: shown on the first login only", function()
	local X = W.start()
	T.ok("not shown at once", not guideShown())
	W.advance(5)
	T.ok("shown about 4 seconds after the first login", guideShown())
	T.check("starts on the first part", guide().page, 1)
	T.check("the box is not ticked (shown once, not at every login)", guide().check:GetChecked(), false)
	T.ok("not seen while still open", X.db.guideSeen == false)
	-- a reload before closing it: it comes again
	X = W.reload()
	W.advance(5)
	T.ok("shown again after a reload when it was never closed", guideShown())
	W.click("Close", guide())
	T.ok("closed with Close", not guideShown())
	T.ok("marked as seen when closed", type(X.db.guideSeen) == "string" and X.db.guideSeen ~= "", X.db.guideSeen)
	-- after a reload: not again
	X = W.reload()
	W.advance(6)
	T.ok("not shown after it was seen", not guideShown())
	-- the box ticked: it comes at every login
	X.ShowGuide()
	T.ok("/xnah guide way opens it", guideShown())
	W.click("Show this guide when I log in", guide())
	T.check("box ticked", X.S().guideAtLogin, true)
	escape()
	T.ok("Escape closes it", not guideShown())
	X = W.reload()
	W.advance(5)
	T.ok("shown at login when the box is ticked", guideShown())
	T.check("the box shows ticked", guide().check:GetChecked(), true)
	-- untick it again
	W.click("Show this guide when I log in", guide())
	T.check("box unticked", X.S().guideAtLogin, false)
	W.click("Close", guide())
	X = W.reload()
	W.advance(5)
	T.ok("not shown at login when the box is unticked", not guideShown())
	X.ShowGuide()
	T.ok("Escape list holds the guide", X.Contains(W.env.UISpecialFrames, "XNAHGuide") ~= nil)
	escape()
	T.ok("Escape closes it again", not guideShown())
end)

T.scene("guide: every part, Previous / Next, Open this page", function()
	local X = W.start()
	W.advance(5)
	local pages = X.GuidePages()
	T.check("13 parts", #pages, 13)
	local keys = {}
	for i, p in ipairs(pages) do
		keys[p.key] = i
		T.ok("part " .. i .. " has a key, a title and text", type(p.key) == "string" and type(p.title) == "string" and
			type(p.text) == "string" and #p.text > 200, p.key)
		T.ok("part " .. i .. " text is plain ASCII", not p.text:find("[\128-\255]"), p.key)
	end
	for _, k in ipairs({"welcome", "home", "scanning", "market", "tooltips", "deals", "craft", "sell", "buy",
		"gold", "settings", "good"}) do
		T.ok("part " .. k .. " is there", keys[k] ~= nil)
	end
	T.check("deals page belongs to its tab", pages[keys.deals].tab, "deals")

	-- every part opens (by number and by key)
	local f = guide()
	for i, p in ipairs(pages) do
		X.ShowGuide(i)
		T.check("part " .. i .. " shown", f.page, i)
		T.check("part " .. i .. " title", W.plain(f.pageTitle:GetText()), p.title)
		T.check("part " .. i .. " text", f.text:GetText(), p.text)
		T.ok("part " .. i .. " scroll area has a height", f.child:GetHeight() > 10)
		X.ShowGuide(p.key)
		T.check("part " .. p.key .. " by its key", f.page, i)
	end
	-- the list on the left
	W.click("Gold", f)
	T.check("list button opens its part", f.page, keys.gold)

	-- Next walks through all, Previous back
	X.ShowGuide(1)
	T.ok("Previous is off on the first part", f.prev.disabled == true)
	for i = 2, #pages do
		f.next:Click("LeftButton")
		T.check("Next to part " .. i, f.page, i)
	end
	T.ok("Next is off on the last part", f.next.disabled == true)
	for i = #pages - 1, 1, -1 do
		f.prev:Click("LeftButton")
		T.check("Previous to part " .. i, f.page, i)
	end

	-- Open this page: the right tab, the guide closes
	for i, p in ipairs(pages) do
		X.ShowGuide(i)
		if p.tab and X.UI.tabs[p.tab] then
			T.ok("part " .. i .. ": Open this page is on", not f.open.disabled)
			f.open:Click("LeftButton")
			W.advance(0.3)
			T.check("part " .. i .. ": opens tab", X.UI.current, p.tab)
			T.ok("part " .. i .. ": main window shown", X.UI.Frame() and X.UI.Frame():IsShown())
			T.ok("part " .. i .. ": guide closed", not guideShown())
		else
			T.ok("part " .. i .. ": Open this page is off (no tab)", f.open.disabled == true, p.key)
		end
	end
	-- the guide comes back on the part shown last
	X.ShowGuide()
	T.ok("opens again", guideShown())
	-- the X in the corner
	W.click("X", f)
	T.ok("X closes it", not guideShown())
	-- hovering everything (tooltips)
	X.ShowGuide(1)
	W.walk(f, function(fr) if fr.scripts.OnEnter and fr:IsVisible() then W.hover(fr) W.unhover(fr) end end)
	W.advance(0.5)
end)
