-- Opportunities (a view of the XNAH window): one read-only list of the chances the price analysis finds, best first.
--   Far under usual     listed far under its usual price (the same rule as X.Deals: Settings "Deals and trends need")
--   Vendor flip         a vendor sells it for less than it brings on the auction house (X.VendorFlips)
--   Under vendor price  listed for less than a vendor pays for it (X.BelowVendor)
--   Under disenchant    gear listed under what its disenchanting materials bring (X.UnderDE)
--   Reset the price     everything listed far under the usual price costs this much to buy (X.Resets, Shape.lua)
--   Few sellers         only a few sellers, one seller with half or more, or a wall of one price (X.FewSellers)
-- No buy buttons: buy with the game's auction house. Click a row = that item in the Items view; right-click = menu.
-- The items are gone through a few hundred per frame (X.Job) after new prices arrive; the small lists (vendor flips,
-- resets, few sellers) in the last step.
-- Layout (UI.W x UI.H, read when the view is built): kind chips at the top; a second line with "Hide slow sellers",
-- the profit filter, the search box and a summary; the list from y -72; a footer line at the bottom.
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local GREEN, RED = "|cff4ade80", "|cfff87171"
local SLICE = 300

local KINDS = {
	{"deal", "Far under usual", "Listed far under its usual price (the 30-day average, else 7 or 3 days). Sells for = the " ..
		"usual price after the cut."},
	{"vflip", "Vendor flip", "A vendor sells it for less than it brings on the auction house after the cut. Buy at = " ..
		"the vendor's price."},
	{"below", "Under vendor price", "Listed for less than a vendor pays for it: buy it and sell it to any vendor, no risk."},
	{"de", "Under disenchant", "Gear listed under what its disenchanting materials bring (an average of what one " ..
		"disenchant gives, the materials at their price, after the cut). Needs an enchanter."},
	{"reset", "Reset the price", "Everything listed far under the usual price (under 80%): buy it all and list again at the " ..
		"usual price. Not a sure thing: others may list cheap again."},
	{"few", "Few sellers", "Only a few sellers, one seller with half or more of the listings, or a wall (many listed at one " ..
		"price). Sellers are counted when you look at an item on the auction house."},
}
local KIND_NAME = {}
for _, k in ipairs(KINDS) do KIND_NAME[k[1]] = k[2] end

-- [[ state ]]
local rows        -- every chance found (nil until first worked out)
local count = {}  -- rows per kind
local dirty = true
local building = false
local builtSig    -- the settings the rows were worked out with
local progress = ""
X.Default("oppsFilter", {})
local filter = {kind = nil, slow = false, minProfit = nil, text = ""}
local function loadFilter()
	local f = X.S().oppsFilter or {}
	filter.kind = KIND_NAME[f.kind or ""] and f.kind or nil
	filter.slow, filter.minProfit, filter.text = f.slow == true, tonumber(f.minProfit), f.text or ""
end
local function saveFilter()
	X.S().oppsFilter = {kind = filter.kind, slow = filter.slow, minProfit = filter.minProfit, text = filter.text}
end

local function markDirty() dirty = true end
for _, e in ipairs({"XNAH_PRICES", "XNAH_ANALYSIS", "XNAH_IGNORE"}) do X.On(e, markDirty) end

-- the settings the rules use: when one changes, the list is worked out again
local function settingsSig()
	local S = X.S()
	return table.concat({tostring(S.dealPct), tostring(S.dealMinProfit), tostring(S.minSamples), tostring(S.staleHours),
		tostring(S.cut), tostring(S.source)}, ",")
end

-- [[ rows ]] {key, kind, why, buy (one), sell (what one brings, after the cut), profit (of one), pct, qty (listed), t
-- (when the price was seen), vol (ups and downs %), rate (sells a day), name}
local function add(out, key, it, kind, why, buy, sell)
	local profit = (buy and sell) and (sell - buy) or nil
	it = it or X.Items()[key]
	local cur = it and it.cur or {}
	local st = it and X.Stats(it) or {}
	out[#out + 1] = {key = key, kind = kind, why = why, buy = buy, sell = sell, profit = profit,
		pct = (profit and buy and buy > 0) and profit / buy * 100 or nil, qty = cur.qty, t = cur.t, vol = st.vol,
		name = ((it and it.n) or X.ItemName(key) or ""):lower()}
end

-- one item of the realm: far under usual, under vendor price, under disenchant value (the rules of X.Deals,
-- X.BelowVendor and X.UnderDE, item by item so the work can be split over frames)
local function checkItem(out, key, it, S)
	local cur = it.cur
	if not cur or not cur.min or (cur.qty or 0) <= 0 or not X.Fresh(it) then return end
	if X.BuyIdea(key, it) then
		local usual, st = X.Usual(key)
		if usual and st.days >= S.minSamples then
			local pct = cur.min / usual * 100
			local sell = X.AfterCut(usual)
			if pct <= S.dealPct and sell - cur.min >= S.dealMinProfit then
				add(out, key, it, "deal", "Far under usual (" .. string.format("%.0f", pct) .. "%)", cur.min, sell)
			end
		end
	end
	local vs = X.VendorSell(it.id or X.KeyID(key))
	if vs and cur.min < vs then add(out, key, it, "below", "Under vendor price", cur.min, vs) end
	if it.q == nil or (it.q >= 2 and it.q <= 4) then
		local de = X.DEValue(key)
		if de and de > 0 and cur.min < de * 0.95 then
			add(out, key, it, "de", "Under disenchant (" .. string.format("%.0f", cur.min / de * 100) .. "%)", cur.min, X.AfterCut(de))
		end
	end
end

-- the small lists (one step)
local function addOthers(out)
	for _, r in ipairs(X.VendorFlips()) do
		add(out, r.key, nil, "vflip", "A vendor sells it" .. (r.lim and " (few)" or ""), r.buy, r.sell)
	end
	for _, r in ipairs(X.Resets()) do
		if (r.units or 0) > 0 and r.usual then
			add(out, r.key, nil, "reset", "Buy all " .. X.Num(r.units) .. " under 80%", r.cost / r.units, X.AfterCut(r.usual))
			out[#out].profit = r.profit / r.units
			out[#out].pct = r.cost > 0 and r.profit / r.cost * 100 or nil
		end
	end
	for _, r in ipairs(X.FewSellers()) do
		local why
		if r.wallU then why = "Wall: " .. X.Num(r.wallU) .. " at one price"
		elseif r.top and r.top >= 0.5 then why = "One seller has " .. string.format("%.0f", r.top * 100) .. "%"
		elseif r.sellers then why = "Only " .. r.sellers .. (r.sellers == 1 and " seller" or " sellers")
		else why = "Few sellers" end
		local usual = X.Usual(r.key)
		add(out, r.key, nil, "few", why, r.min, usual and X.AfterCut(usual) or nil)
	end
end

local function start()
	if building then return end
	building, dirty = true, false
	builtSig = settingsSig()
	local items = X.Items()
	local keys = {}
	for key in pairs(items) do keys[#keys + 1] = key end
	local S = X.S()
	local out, i = {}, 0
	progress = "Looking: 0 / " .. X.Num(#keys)
	X.Job("opportunities", function()
		if i >= #keys then
			addOthers(out)
			for _, r in ipairs(out) do r.rate = X.SaleRate and X.SaleRate(r.key) or nil end
			return true
		end
		local stop = math.min(#keys, i + SLICE)
		while i < stop do
			i = i + 1
			local it = items[keys[i]]
			if it then checkItem(out, keys[i], it, S) end
		end
		progress = "Looking: " .. X.Num(i) .. " / " .. X.Num(#keys)
		return false
	end, function()
		building = false
		rows = out
		count = {}
		for _, r in ipairs(out) do count[r.kind] = (count[r.kind] or 0) + 1 end
		if UI.current == "opps" then UI.Refresh(true) end
	end)
end
-- for the tests: the rows as worked out last (nil while never done)
UI.OppsRows = function() return rows end

local function passes(r, text)
	if filter.kind and r.kind ~= filter.kind then return false end
	if filter.slow and r.rate and r.rate < 1 then return false end
	if filter.minProfit and (not r.profit or r.profit < filter.minProfit) then return false end
	if text ~= "" and not (r.name:find(text, 1, true) or r.key == text or r.why:lower():find(text, 1, true)) then return false end
	return true
end

-- [[ the columns ]]
local function riskText(v)
	if not v then return NONE end
	if v < 10 then return GREEN .. "low|r" end
	if v < 25 then return "|cffffd100medium|r" end
	return RED .. "high|r"
end
local COLUMNS = {
	{"Item", 220, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return r.name end, desc = false},
	{"Why", 150, "LEFT", text = function(r) return r.why end, sort = function(r) return r.why end, desc = false},
	{"Buy at", 76, "RIGHT", text = function(r) return UI.MoneyCell(r.buy and X.Round(r.buy)) end, sort = function(r) return r.buy end},
	{"Sells for", 76, "RIGHT", text = function(r) return UI.MoneyCell(r.sell and X.Round(r.sell)) end, sort = function(r) return r.sell end},
	{"Profit", 76, "RIGHT", text = function(r)
		if not r.profit then return NONE end
		if r.profit < 0 then return RED .. "-" .. X.MoneyPlain(X.Round(-r.profit)) .. "|r" end
		return X.Money(X.Round(r.profit), true)
	end, sort = function(r) return r.profit end},
	{"%", 50, "RIGHT", text = function(r)
		if not r.pct then return NONE end
		return (r.pct >= 0 and GREEN or RED) .. string.format("%+.0f%%", r.pct) .. "|r"
	end, sort = function(r) return r.pct end},
	{"Listed", 46, "RIGHT", text = function(r) return r.qty and X.Num(r.qty) or NONE end, sort = function(r) return r.qty end},
	{"Sells a day", 62, "RIGHT", text = function(r) return r.rate and X.Rate(r.rate) or NONE end, sort = function(r) return r.rate end},
	{"Price seen", 62, "RIGHT", text = function(r) return r.t and (GREY .. X.Ago(r.t) .. "|r") or NONE end,
		sort = function(r) return r.t end},
	{"Risk", 52, "RIGHT", text = function(r) return riskText(r.vol) end, sort = function(r) return r.vol end},
}
local PROFITS = {{"any", nil}, {"10s", 1000}, {"1g", 10000}, {"5g", 50000}, {"20g", 200000}, {"100g", 1000000}}

-- [[ the view ]]
local function build(panel)
	local W, H = UI.W, UI.H
	loadFilter()
	local fixed = 0
	for i = 2, #COLUMNS do fixed = fixed + COLUMNS[i][2] end
	local cols = {}
	for i, c in ipairs(COLUMNS) do cols[i] = c end
	cols[1] = {COLUMNS[1][1], math.max(160, W - 20 - fixed), "LEFT", text = COLUMNS[1].text, sort = COLUMNS[1].sort, desc = false}

	local tbl
	local function changed()
		saveFilter()
		panel.update()
	end
	-- kind chips
	panel.chips = {}
	local x = 0
	local function chip(kind, text, w, tip)
		local b = K.Flat(panel, w, 22)
		b:SetPoint("TOPLEFT", x, 0)
		b.label:SetJustifyH("CENTER")
		b.text = text
		b:SetScript("OnClick", function()
			filter.kind = (kind ~= "all" and filter.kind ~= kind) and kind or nil
			changed()
		end)
		if tip then K.Tooltip(b, text, tip) end
		panel.chips[kind] = b
		x = x + w + 4
	end
	chip("all", "All", 70)
	local cw = math.floor((W - 74 - 4 * #KINDS) / #KINDS)
	for _, k in ipairs(KINDS) do chip(k[1], k[2], math.min(150, cw), k[3]) end

	-- second line: slow sellers, profit, search, summary
	local LY = -28
	local slow = K.Check(panel, "Hide slow sellers", function(on) filter.slow = on changed() end)
	slow:SetPoint("TOPLEFT", 0, LY)
	slow:SetChecked(filter.slow)
	K.Tooltip(slow, "Hide slow sellers", "Leaves out items that sell under 1 a day (items whose sales speed is not " ..
		"known yet stay).")
	panel.slow = slow
	local profitBtn = K.Flat(panel, 120, 22)
	profitBtn:SetPoint("TOPLEFT", 140, LY)
	profitBtn.label:SetJustifyH("CENTER")
	profitBtn:SetScript("OnClick", function(self)
		local items = {{text = "Profit of one at least", isTitle = true}}
		for _, p in ipairs(PROFITS) do
			items[#items + 1] = {text = p[1], checked = filter.minProfit == p[2], func = function() filter.minProfit = p[2] changed() end}
		end
		K.Menu(self, items)
	end)
	panel.profitBtn = profitBtn
	local label = K.Label(panel, "Search", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", 272, LY - 5)
	local search = K.Edit(panel, 180)
	search:SetPoint("TOPLEFT", 318, LY - 1)
	search:SetText(filter.text)
	search:SetScript("OnTextChanged", function(self, user)
		if not user then return end
		filter.text = self:GetText() or ""
		saveFilter()
		X.Debounce("xnah-opps-search", 0.3, changed)
	end)
	panel.search = search
	local summary = K.Label(panel, "", "GameFontDisableSmall", "RIGHT")
	summary:SetPoint("TOPRIGHT", 0, LY - 5)
	summary:SetWidth(math.max(100, W - 510))
	summary:SetWordWrap(false)

	-- the list
	local TY = 72
	tbl = K.Table(panel, W, H - TY - 20, cols, function(row, button, rowFrame)
		if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
	end)
	tbl:SetPoint("TOPLEFT", 0, -TY)
	tbl:SortBy(5, true) -- profit, most first
	panel.tbl = tbl

	local footer = K.Label(panel, "", "GameFontDisableSmall")
	footer:SetPoint("BOTTOMLEFT", 2, 4)
	footer:SetWidth(W - 260)
	footer:SetWordWrap(false)
	local help = K.Label(panel, GREY .. "Click: see the item   Right-click: menu|r", "GameFontDisableSmall", "RIGHT")
	help:SetPoint("BOTTOMRIGHT", -2, 4)
	help:SetWidth(250)

	-- shows the rows that pass the filters (keeps the sorting)
	function panel.update()
		-- the filters as saved (they are the settings "oppsFilter")
		loadFilter()
		slow:SetChecked(filter.slow)
		if (search:GetText() or "") ~= filter.text then search:SetText(filter.text) end
		local total = rows and #rows or 0
		panel.chips.all:SetLabel("All " .. GREY .. X.Num(total) .. "|r")
		panel.chips.all:SetSelected(filter.kind == nil)
		for _, k in ipairs(KINDS) do
			local b = panel.chips[k[1]]
			b:SetLabel(b.text .. " " .. GREY .. X.Num(count[k[1]] or 0) .. "|r")
			b:SetSelected(filter.kind == k[1])
		end
		local pname = "any"
		for _, p in ipairs(PROFITS) do if p[2] == filter.minProfit then pname = p[1] end end
		profitBtn:SetLabel("Profit at least: " .. pname)
		profitBtn:SetSelected(filter.minProfit ~= nil)
		local text = X.Trim(filter.text):lower()
		local list = {}
		for _, r in ipairs(rows or {}) do if passes(r, text) then list[#list + 1] = r end end
		local empty
		if not rows then
			empty = "Looking for chances..."
		elseif total == 0 then
			empty = "Nothing yet. Do a full scan at the auction house; ideas appear once items have " .. X.S().minSamples ..
				" days of prices (one full scan a day is enough). Vendor flips need a visit to vendors, resets and sellers " ..
				"a look at items on the auction house."
		else
			empty = "Nothing matches the filters."
		end
		tbl:SetRows(list, empty)
		local S = X.S()
		summary:SetText(GREY .. "Far under usual: at most " .. S.dealPct .. "% of usual, " .. X.MoneyPlain(S.dealMinProfit) ..
			"+ profit. Prices over " .. S.staleHours .. " h old left out.|r")
		local ft = X.Num(#list) .. (#list == 1 and " chance" or " chances") .. (#list ~= total and (" of " .. X.Num(total)) or "") ..
			"   -   last full scan " .. X.Ago(X.Realm().lastFull)
		if building then ft = ft .. "   " .. progress end
		footer:SetText(ft)
	end
end

local function refresh(panel)
	if not building and (not rows or (builtSig and builtSig ~= settingsSig())) then
		start()
	elseif dirty and not building then
		-- new prices while shown: once they have settled for a second
		X.Debounce("xnah-opps", 1, function()
			if dirty and not building and UI.current == "opps" then start() end
		end)
	end
	panel.update()
end

UI.AddTab("opps", "Opportunities", build, refresh, 4)
