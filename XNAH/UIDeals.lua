-- The ideas for making gold (until v0.7 the Deals tab; since v0.8 they live on the tabs where you act on them):
--   Buy ideas: on the Buy tab, view Best buys (UIBuy.lua shows them together with the best buys of the Next buy key).
--   Sell ideas: on the Sell tab, view Sell ideas. Make ideas: on the Crafting tab, view Make ideas.
--   Adjust ideas (UIStrategies.lua): on the Buy tab, view Adjust ideas.
-- This file keeps what they share: the list of ideas (UI.Ideas), X.DealIdeas(side) (one row per item, best first),
-- the cells, and UI.IdeasView(parent, w, h, side) - the Sell ideas and Make ideas views.
local ADDON, X = ...
local K, UI = X.K, X.UI

-- ideas left out of the lists: [idea key] = true
X.Default("dealsHidden", {})

-- [[ the ideas ]] the strategies (Strategy.lua) plus "Under usual price" (the deals test, Market.lua: X.Deals), which
-- has its numbers in the settings (dealPct, dealMinProfit)
local USUAL = {key = "usual", name = "Under usual price", side = "buy",
	short = "Listed far under its usual price (the 30-day average).",
	how = {
		"Lists items whose lowest price is at or under a share of their usual price (the 30-day average, else the 7-day one), with enough profit after the auction house cut.",
		"Buy them now and sell them again at the usual price.",
		"When it fails: when the price has really moved (a patch, a new source) - the usual price is then old news.",
	},
	needs = "fresh prices (a full scan) and a few days of price history per item (one full scan a day)",
	params = {
		{key = "pct", label = "Share of usual price at most", kind = "pct",
			tip = "The lowest price must be at or under this % of the usual price."},
		{key = "minProfit", label = "Profit each at least", kind = "money",
			tip = "Leave out items that bring less than this each (after the auction house cut)."},
	},
}
local IDEAS = {}
-- every idea, in the order shown (Under usual price first)
function IDEAS.list()
	local out = {USUAL}
	for _, s in ipairs(X.Strategies and X.Strategies() or {}) do out[#out + 1] = s end
	return out
end
function IDEAS.get(key)
	if key == USUAL.key then return USUAL end
	return X.Strategy and X.Strategy(key) or nil
end
function IDEAS.params(idea)
	if idea == USUAL then
		local S = X.S()
		return {pct = S.dealPct, minProfit = S.dealMinProfit}
	end
	return X.StrategyParams(idea.key)
end
local dirty -- forward: the lists must be worked out again
function IDEAS.setParam(idea, pkey, value)
	if idea == USUAL then
		if pkey == "pct" then X.S().dealPct = math.max(1, math.min(100, X.Round(value))) end
		if pkey == "minProfit" then X.S().dealMinProfit = value end
		dirty()
		return
	end
	X.SetStrategyParam(idea.key, pkey, value)
end
function IDEAS.reset(idea)
	if idea == USUAL then
		X.S().dealPct, X.S().dealMinProfit = X.DEFAULTS.dealPct, X.DEFAULTS.dealMinProfit
		dirty()
		return
	end
	X.ResetStrategy(idea.key)
end
-- is the idea used in the lists (Best buys, Sell ideas, Make ideas)?
function IDEAS.shown(key) return not (X.S().dealsHidden or {})[key] end
function IDEAS.setShown(key, on)
	X.S().dealsHidden = X.S().dealsHidden or {}
	X.S().dealsHidden[key] = (not on) and true or nil
	dirty()
end
-- something changed (Adjust ideas): work the lists out again
function IDEAS.changed() dirty() end
UI.Ideas = IDEAS

-- [[ the rows ]]
-- Low / Medium / High from how much the price jumps, how many days of history and how fast it sells
local function riskOf(st, rate)
	local score = 0
	local vol = st and st.vol
	if not vol then score = score + 1 elseif vol > 25 then score = score + 2 elseif vol > 12 then score = score + 1 end
	local days = st and st.days or 0
	if days < 7 then score = score + 1 end
	if not rate then score = score + 1 elseif rate < 0.5 then score = score + 2 elseif rate < 2 then score = score + 1 end
	if score <= 1 then return "Low" end
	if score <= 3 then return "Medium" end
	return "High"
end
UI.IdeaRisk = riskOf
-- the deals of "Under usual price" as idea rows (how many: about 3 days of sales when the speed is known); kept
-- until prices or the numbers change (a minute at most: prices get old)
local usualCache, usualAt, usualDirty
local function usualRows()
	if usualCache and not usualDirty and GetTime() - usualAt <= 60 then return usualCache end
	local out = {}
	for _, d in ipairs(X.Deals()) do
		local rate = X.SaleRate and X.Try(X.SaleRate, d.key) or nil
		local qty
		if rate and rate > 0 then qty = math.max(1, math.min(d.qty or 1, math.floor(rate * 3 + 0.5))) end
		local it = X.Items()[d.key]
		out[#out + 1] = {key = d.key, action = "Buy and relist", now = d.buy, target = d.usual, profit = d.profit, qty = qty,
			risk = riskOf(it and X.Stats(it), rate), rate = rate, total = d.profit * (qty or 1),
			why = string.format("%.0f%% of its usual price", d.pct)}
	end
	usualCache, usualAt, usualDirty = out, GetTime(), false
	return out
end
-- the rows one idea finds right now (nil: not worked out yet)
function IDEAS.rows(idea)
	if idea == USUAL then return usualRows() end
	return X.StrategyRows(idea.key)
end

-- all ideas of one side, one row per item (the one bringing the most in all), best first
local cache, cacheAt, cacheDirty = {}, {}, {}
local function markDirty()
	cacheDirty.buy, cacheDirty.sell, cacheDirty.make = true, true, true
	usualDirty = true
end
dirty = function()
	markDirty()
	UI.Refresh()
end
for _, e in ipairs({"XNAH_PRICES", "XNAH_STRATEGY", "XNAH_IGNORE", "XNAH_ANALYSIS", "XNAH_INVENTORY"}) do X.On(e, markDirty) end
local function merge(side)
	local best, others = {}, {}
	local function take(idea, r)
		local row = {}
		for k, v in pairs(r) do row[k] = v end
		row.idea, row.ideaName = idea.key, idea.name
		row.total = row.total or (row.profit or 0) * (row.qty or 1)
		local old = best[row.key]
		others[row.key] = (others[row.key] or 0) + 1
		if not old or row.total > old.total then best[row.key] = row end
	end
	for _, idea in ipairs(IDEAS.list()) do
		if idea.side == side and IDEAS.shown(idea.key) then
			local rows = (idea == USUAL) and usualRows() or (X.StrategyRows(idea.key) or {})
			for _, r in ipairs(rows) do if r.key then take(idea, r) end end
		end
	end
	local out = {}
	for key, row in pairs(best) do
		row.more = others[key] - 1
		if row.rate == nil then row.rate = X.SaleRate and X.Try(X.SaleRate, key) or nil end
		out[#out + 1] = row
	end
	table.sort(out, function(a, b)
		if a.total ~= b.total then return a.total > b.total end
		return a.key < b.key
	end)
	return out
end
-- every idea of one side ("buy", "sell" or "make"; one row per item, best first): {key, idea, ideaName, action, now,
-- target, profit, qty, total, risk, why, rate, more (other ideas that found it too), vendor (bought from a vendor)}
function X.DealIdeas(side)
	side = side or "buy"
	if cacheDirty[side] ~= false or not cache[side] or GetTime() - (cacheAt[side] or 0) > 60 then
		cache[side] = merge(side)
		cacheAt[side], cacheDirty[side] = GetTime(), false
	end
	return cache[side]
end

-- [[ cells ]] (the Best buys list of the Buy tab uses them too)
local RISK_COLOR = {Low = "4ade80", Medium = "facc15", High = "f87171"}
local GREY = "|cff999999"
local function field(name) return function(r) return r[name] end end
local function money(name) return function(r) return UI.MoneyCell(r[name]) end end
local function itemName(r) return (X.ItemName(r.key)) end
local function itemCell(r) return UI.ItemCell(r.key) end
-- sells per day (an estimate): "-" when not known yet
function UI.RateText(rate)
	if not rate then return "|cff666666-|r" end
	if rate >= 10 then return X.Num(rate) end
	if rate >= 0.1 then return string.format("%.1f", rate) end
	return "|cff999999<0.1|r"
end
local function ideaCell(r)
	return (r.ideaName or "") .. ((r.more or 0) > 0 and (GREY .. " +" .. r.more .. "|r") or "")
end
local function riskCell(r)
	if not r.risk then return "|cff666666-|r" end
	return "|cff" .. (RISK_COLOR[r.risk] or "ffffff") .. r.risk .. "|r"
end
local function riskSort(r) return r.risk == "Low" and 1 or r.risk == "Medium" and 2 or r.risk == "High" and 3 or nil end
-- what to do with it after buying, in front of the why
local THEN = {["Buy and vendor"] = "sell to a vendor: ", ["Disenchant"] = "disenchant: ", ["Buy and hold"] = "keep a while: "}
local function whyText(r)
	local pre = r.vendor and "buy from a vendor: " or THEN[r.action] or ""
	return pre .. (r.why or "")
end
local function whyCell(r) return "|cffbbbbbb" .. whyText(r) .. "|r" end
local function qtyCell(r) return r.qty and X.Num(r.qty) or "|cff666666-|r" end
UI.IdeaCells = {idea = ideaCell, risk = riskCell, riskSort = riskSort, why = whyCell, whyText = whyText, qty = qtyCell}

local function onRow(row, button, rowFrame)
	if not row.key then return end
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end

-- the Sell ideas / Make ideas list (widths add up to 914 of the 920 a 940 wide list has room for)
local COLUMNS = {
	{"Item", 200, "LEFT", text = itemCell, sort = itemName, desc = false},
	{"Idea", 130, "LEFT", text = ideaCell, sort = field("ideaName"), desc = false},
	{"Action", 100, "LEFT", text = function(r)
		local a = r.action or ""
		if a == "Hold" then return "|cff9db4ff" .. a .. "|r" end
		if a == "Sell now" then return "|cffffd100" .. a .. "|r" end
		return a
	end, sort = field("action"), desc = false},
	{"Now", 80, "RIGHT", text = money("now"), sort = field("now"), desc = false},
	{"Target", 80, "RIGHT", text = money("target"), sort = field("target")},
	{"Profit each", 80, "RIGHT", text = money("profit"), sort = field("profit")},
	{"Qty", 44, "RIGHT", text = qtyCell, sort = field("qty")},
	{"Risk", 50, "LEFT", text = riskCell, sort = riskSort, desc = false},
	{"Why", 150, "LEFT", text = whyCell},
}

-- [[ what to say when a list is empty ]]
local NO_PRICES = "No prices yet. Open the auction house and press Full scan (Settings)."
function UI.IdeasEmptyText(side)
	local S = X.S()
	if next(X.Items()) == nil then return NO_PRICES end
	if X.StrategyBusy and X.StrategyBusy() then return "Working out the ideas ..." end
	if side == "buy" then
		return "No buy ideas right now. They need fresh prices (a full scan; prices older than " .. S.staleHours ..
			" hours are not used), a few days of price history per item, and for some the sales speed or vendors visited. " ..
			"Adjust ideas changes their numbers."
	elseif side == "sell" then
		return "No sell ideas right now. They look at what you have (log in your characters, open the bank and the " ..
			"mailbox) and need a few days of price history."
	end
	return "No make ideas right now. They need recipes (open your profession windows) and fresh prices of what goes in " ..
		"and what comes out. The Recipes view lists every recipe."
end

-- the hour of the day with the most sales (estimate), for the sell ideas
local function bestHour()
	if not X.BestHours then return nil end
	local share = X.Try(X.BestHours)
	if type(share) ~= "table" then return nil end
	local best, h = 0, nil
	for i = 0, 23 do if (share[i] or 0) > best then best, h = share[i], i end end
	return h
end

-- [[ the Sell ideas / Make ideas view ]] UI.IdeasView(parent, w, h, side) -> a frame; view:Refresh() draws it again
local HELP = {
	sell = "What to do with things you have: sell now while the price is good, or hold while it is low.",
	make = "Crafting for profit, recipes worth learning, cooldown crafts and what to gather.",
}
function UI.IdeasView(parent, w, h, side)
	local v = CreateFrame("Frame", nil, parent)
	v:SetSize(w, h)
	v.help = K.Label(v, HELP[side] or "", "GameFontHighlight")
	v.help:SetPoint("TOPLEFT", 0, -4)
	v.help:SetWidth(w - 250)
	v.help:SetWordWrap(false)
	local adjust = K.Button(v, "Adjust ideas", 110, 22, function()
		X.S().buyView = "adjust"
		UI.Open("buy")
	end)
	adjust:SetPoint("TOPRIGHT", 0, 0)
	K.Tooltip(adjust, "Adjust ideas", "Opens Adjust ideas (tab Buy): which ideas go into the lists, their numbers, and how each one works.")
	v.count = K.Label(v, "", "GameFontDisableSmall", "RIGHT")
	v.count:SetPoint("RIGHT", adjust, "LEFT", -8, 0)
	v.count:SetWidth(120)
	v.note = K.Label(v, "", "GameFontHighlightSmall")
	v.note:SetPoint("TOPLEFT", 0, -24)
	v.note:SetWidth(w)
	v.note:SetWordWrap(false)
	v.tbl = K.Table(v, w, h - 56 - 20, COLUMNS, onRow)
	v.tbl:SetPoint("TOPLEFT", 0, -56)
	v.tbl:SortBy(6, true) -- the most profit first
	local hint = K.Label(v, GREY .. "Click a row: item page.  Right-click: menu.  +1 = another idea found it too.  " ..
		"Click a column title to sort.|r")
	hint:SetPoint("BOTTOMLEFT", 0, 2)
	hint:SetWidth(w)
	hint:SetWordWrap(false)
	function v:Refresh()
		if X.StrategyCheck then X.StrategyCheck() end -- works the ideas out again when prices changed or they are old
		local rows = X.DealIdeas(side)
		if side == "sell" then
			local hr = bestHour()
			self.note:SetText(GREY .. (hr and ("Most sales happen about " .. string.format("%02d:00", hr) .. " (your clock): post an hour or two before. ")
				or "") .. "Sell ideas look at what you have on all your characters.|r")
		else
			self.note:SetText(GREY .. "Profit = what it sells for after the cut, minus what goes in at today's prices. " ..
				"The Recipes view has every recipe.|r")
		end
		self.tbl:SetRows(rows, UI.IdeasEmptyText(side))
		local status = #rows == 1 and "1 item" or (X.Num(#rows) .. " items")
		if X.StrategyBusy and X.StrategyBusy() then status = status .. ", working ..." end
		self.count:SetText(status)
	end
	return v
end

X.On("XNAH_STRATEGY", function() UI.Refresh() end)
