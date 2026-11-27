-- Items view, Sellers page: who sells the item picked, over time (X.SellerHistory through Sellers.lua).
-- Layout (810 x 532): 4 number tiles; a line in plain words (how fast the price gets cut, or how to get seller numbers)
-- with the range buttons; two graphs side by side (how many sellers, the biggest seller's share); undercuts a day
-- across; the sellers of the last search this session.
-- On WoW: Forever the full scan gives no seller names: seller numbers exist only for items searched by themselves
-- (tracked items with "Scan tracked", or the item picked while the auction house is open). Undercuts come from every
-- scan and search.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY, ORANGE = "|cff999999", "|cffff9933"
local NONE = "|cff666666-|r"
local DAY = 86400
local RANGES = {{"30 days", 30}, {"90 days", 90}, {"1 year", 365}}
X.Default("sellersRange", 1) -- an index of RANGES

local HOW_TO_SHORT = "No seller numbers yet: the full scan on Forever has no seller names. Track the item (the star) and " ..
	"press Scan tracked, or pick it while the auction house is open."
local HOW_TO = "No seller numbers for this item yet. The full scan on Forever does not say who sells what, so sellers " ..
	"are only counted when the item is searched by itself: track it (the star) and press Scan tracked, or pick the item " ..
	"while the auction house is open."

local TILES = {
	{"Sellers now", "How many different players sell it, at the last search of the item by itself (the full scan has no " ..
		"seller names on Forever)."},
	{"Biggest seller", "How much of everything listed the biggest seller holds, and who it is. Over 50%: one player " ..
		"sets the price."},
	{"Undercuts a day", "How many times a day the cheapest price went down while it stayed listed (someone listed " ..
		"cheaper), on average over the last 7 days. Only counted between your own scans and searches."},
	{"How fast they undercut", "How quickly someone lists cheaper than the cheapest price, in plain words: slow, " ..
		"steady, fast or very fast. Hover the line under the tiles for the numbers."},
}

local COLUMNS = {
	{"Seller", 260, "LEFT", text = function(r) return (r.mine and "|cff4ade80" or (r.unnamed and GREY or "|cffffffff")) .. r.name .. "|r" ..
		(r.mine and (GREY .. " (you)|r") or "") end, sort = function(r) return r.name:lower() end, desc = false},
	{"Share", 90, "RIGHT", text = function(r) return r.share and string.format("%.0f%%", r.share * 100) or NONE end,
		sort = function(r) return r.share end},
	{"Units", 90, "RIGHT", text = function(r)
		local u = r.units
		return (u == math.floor(u)) and X.Num(u) or string.format("%.1f", u)
	end, sort = function(r) return r.units end},
	{"Auctions", 90, "RIGHT", text = function(r) return X.Num(r.auctions) end, sort = function(r) return r.auctions end},
	{"Cheapest", 130, "RIGHT", text = function(r) return X.Money(r.lowest, true) end, sort = function(r) return r.lowest end,
		desc = false},
}
local COLUMN_TIPS = {
	"The player selling it (green: you). Grey: sellers the game gives no name for, all in one row.",
	"How much of everything listed this seller holds.",
	"How many this seller has listed. Several sellers in one price row share it out evenly (a guess).",
	"In how many auctions or price rows this seller is.",
	"This seller's cheapest price of one.",
}

local fill -- below

local function build(page, w, h)
	page.tiles = UI.NumberTiles(page, w, TILES, 0)
	page.line = K.Label(page, "", "GameFontHighlightSmall")
	page.line:SetPoint("TOPLEFT", 0, -54)
	page.line:SetWidth(w - 200)
	page.line:SetJustifyV("TOP")
	-- hovering the line: the whole sentence (it may be cut short)
	local hot = CreateFrame("Frame", nil, page)
	hot:SetPoint("TOPLEFT", 0, -50)
	hot:SetSize(w - 200, 28)
	hot:EnableMouse(true)
	hot:SetScript("OnEnter", function(self)
		if not self.text then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.title or "Sellers")
		GameTooltip:AddLine(self.text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	hot:SetScript("OnLeave", function() GameTooltip:Hide() end)
	page.hot = hot
	page.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(page, 56, 18)
		b:SetPoint("TOPRIGHT", -(#RANGES - i) * 60, -52)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() X.S().sellersRange = i fill(page, UI.itemKey) end)
		K.Tooltip(b, r[1], "Shows the last " .. r[1] .. " on the graphs.")
		page.ranges[i] = b
	end
	local gw = math.floor((w - 8) / 2)
	page.gSellers = K.Graph(page, gw, 134)
	page.gSellers:SetPoint("TOPLEFT", 0, -82)
	page.gShare = K.Graph(page, gw, 134)
	page.gShare:SetPoint("TOPLEFT", gw + 8, -82)
	page.gCuts = K.Graph(page, w, 110)
	page.gCuts:SetPoint("TOPLEFT", 0, -222)
	page.tblTitle = K.Label(page, "", "GameFontNormalSmall")
	page.tblTitle:SetPoint("TOPLEFT", 0, -340)
	page.tblTitle:SetWidth(w)
	page.tblTitle:SetWordWrap(false)
	local ty = -372
	for i, c in ipairs(COLUMNS) do c.tip = COLUMN_TIPS[i] end -- the hover line of each column title
	page.tbl = K.Table(page, w, h + ty, COLUMNS, function(row) end)
	page.tbl:SetPoint("TOPLEFT", 0, ty)
	page.tbl:SortBy(3, true)
end

local function dayText(day) return X.Date(day * DAY + DAY / 2, "%b %d") end

fill = function(page, key)
	if not key then return end
	local ri = RANGES[X.S().sellersRange] and X.S().sellersRange or 1
	for i, b in ipairs(page.ranges) do b:SetSelected(i == ri) end
	local st = X.SellerStats(key)
	local t = page.tiles
	local now = st.now
	local today = X.Day()
	if now then
		UI.SetTile(t[1], X.Num(now.sellers), now.day == today and "today" or (dayText(now.day)))
		UI.SetTile(t[2], now.topShare and string.format("%d%%", now.topShare) or NONE, now.topName)
	else
		UI.SetTile(t[1], GREY .. "not known|r")
		UI.SetTile(t[2], GREY .. "not known|r")
	end
	if st.perDay then
		UI.SetTile(t[3], (st.perDay == math.floor(st.perDay)) and string.format("%d", st.perDay) or string.format("%.1f", st.perDay),
			st.undercuts7 .. " in 7 days")
	else
		UI.SetTile(t[3], GREY .. "not known|r")
	end
	UI.SetTile(t[4], st.speed.word, st.speed.sub)
	-- the line: how to get seller numbers, else how fast they undercut
	if not st.hasSellers then
		page.line:SetText(ORANGE .. HOW_TO_SHORT .. "|r")
		page.hot.title, page.hot.text = "No seller numbers yet", HOW_TO
	else
		page.line:SetText(GREY .. st.speed.text .. "|r")
		page.hot.title, page.hot.text = "How fast they undercut", st.speed.text
	end
	-- the graphs
	local fromDay = today - RANGES[ri][2] + 1
	local sellers, share, cuts = X.SellerSeries(key, fromDay)
	local noSellers = st.hasSellers and "No seller numbers in this time - pick a longer range" or
		"No seller numbers yet - search the item by itself (see above)"
	page.gSellers:SetSeries({{points = sellers, label = "Sellers", color = {0.4, 0.75, 1}}},
		{labels = "number", legend = true, empty = noSellers})
	page.gShare:SetSeries({{points = share, label = "Biggest seller's share", color = {1, 0.6, 0.25}}},
		{labels = "percent", legend = true, empty = noSellers,
		levels = #share > 0 and {{v = 50, color = {0.6, 0.6, 0.6}, label = "half"}} or nil})
	page.gCuts:SetSeries({{points = cuts, label = "Undercuts a day", color = {0.97, 0.44, 0.44}}},
		{labels = "number", legend = true, empty = "No scans of this item in this time"})
	-- the sellers of the last search
	local live = X.SellersNow(key)
	if live then
		page.tblTitle:SetText("Sellers at the last search (" .. X.Ago(live.t) .. "): " .. #live.rows .. GREY ..
			"  - this session only|r")
		page.tbl:SetRows(live.rows, "Nothing listed at that search.")
	else
		page.tblTitle:SetText("Sellers now" .. GREY .. "  - from a search of the item while the auction house is open|r")
		page.tbl:SetRows({}, X.ahOpen and "Searching ... (or pick the item again)" or
			"Open the auction house and pick the item (or Scan tracked) to see who sells it.")
	end
end

UI.AddItemPage("sellers", "Sellers", build, function(page, key) fill(page, key) end, 4,
	"Who sells the item over time: how many sellers, the biggest one's share, how often and how fast the price gets " ..
	"cut, and the sellers of the last search. Seller numbers need searches of the item by itself.")
