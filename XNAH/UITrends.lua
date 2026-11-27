-- Trends (a view of the XNAH window): pages about the whole auction house over time, picked with a row of small buttons
-- at the top (the same buttons as the pages of Your gold). This file is only the frame around them: the pages come
-- from other files, each adding itself when it loads with
--   UI.AddTrendsPage(key, title, build(page, w, h), refresh(page), order, help)
-- page = a frame of the area under the buttons, w x h = 1080 x 574 (UI.W x UI.H - 26). build(page, w, h) runs once when
-- the view is first opened; refresh(page) runs whenever the view refreshes while the page is shown (picked, new prices,
-- a scan ...) and may return a short text for the top right ("1,234 items"). Lowest order first. help = the grey line
-- next to the buttons. With no page added the view says "Nothing here yet".
-- Read-only, like every view (no buttons that buy, post or cancel).
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local TOP = 26 -- the pages start here (under the buttons)

local PAGES = UI.PageSet()
function UI.AddTrendsPage(key, title, build, refresh, order, help)
	UI.AddPageTo(PAGES, key, title, build, refresh, order, help)
end
UI.TRENDS_PAGES = PAGES

-- the page shown last is kept in the setting trendsPage (its key; none at first)

local function refresh(p)
	if #PAGES == 0 then
		p.none:Show()
		p.help:SetText("")
		p.count:SetText("")
		return
	end
	p.none:Hide()
	local page = UI.ShowPage(p.bar, X.S().trendsPage)
	if page then X.S().trendsPage = page.key end
	p.help:SetText(page and page.help and (GREY .. page.help .. "|r") or "")
	local text = UI.RefreshPage(p.bar, page)
	p.count:SetText(type(text) == "string" and text or "")
end

local function build(p)
	local W, H = UI.W, UI.H
	p.bar = UI.PageBar(p, PAGES, {x = 0, y = 0, px = 0, py = -TOP, pw = W, ph = H - TOP, name = "trends",
		pick = function(key) X.S().trendsPage = key refresh(p) end})
	p.pages, p.pageButtons = p.bar.frames, p.bar.buttons
	local x = p.bar.right
	p.help = K.Label(p, "", "GameFontDisableSmall")
	p.help:SetPoint("TOPLEFT", x + 6, -4)
	p.help:SetWidth(math.max(40, W - x - 6 - 130))
	p.help:SetWordWrap(false)
	p.count = K.Label(p, "", "GameFontDisableSmall", "RIGHT")
	p.count:SetPoint("TOPRIGHT", 0, -4)
	p.count:SetWidth(124)
	p.count:SetWordWrap(false)
	p.none = K.Label(p, "Nothing here yet", "GameFontDisable", "CENTER")
	p.none:SetPoint("CENTER", p, "TOPLEFT", W / 2, -H / 2)
	p.none:SetWidth(W - 100)
	p.none:Hide()
end

UI.AddTab("trends", "Trends", build, refresh, 4)
