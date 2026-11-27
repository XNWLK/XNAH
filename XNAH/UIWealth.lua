-- The "Characters" part of the Your gold view (UILedger.lua builds the view): your characters of this realm (both
-- factions) - gold, and what their bags, bank, mailbox and auctions are worth - with the total over time, and for this
-- character where each thing in the bags brings more (auction house or vendor). Read-only; right-click a character to
-- forget one you deleted or moved.
-- Layout (w x h given by the Your gold view): help on top; the characters table (6 rows) and the total line; below the
-- net worth graph (left, 45% wide) and "Your bags" (right).
local ADDON, X = ...
local K, UI = X.K, X.UI

local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local DAY = 86400
local RANGES = {{"30 days", 30 * DAY}, {"90 days", 90 * DAY}, {"All", nil}}
local rangeIdx = 1
local LOW = 186          -- top of the lower half

local function M(v)
	if not v or v == 0 then return NONE end
	return X.Money(v, true)
end

local CHAR_COLS = {
	{"Character", 180, "LEFT", text = function(r)
		if r.warbank then return "|cff8aa4ffAccount bank|r" end
		return (r.me and "|cffffd100" or "|cffffffff") .. r.name .. "|r" .. (r.me and (GREY .. "  (this one)|r") or "") ..
			(r.acct and (GREY .. "  (" .. r.acct .. ")|r") or "")
	end, sort = function(r) return r.name end, desc = false},
	{"Gold", 115, "RIGHT", text = function(r) return M(r.gold) end, sort = function(r) return r.gold end},
	{"Bags", 100, "RIGHT", text = function(r) return M(r.bags) end, sort = function(r) return r.bags end},
	{"Bank", 100, "RIGHT", text = function(r) return M(r.bank) end, sort = function(r) return r.bank end},
	{"Mail", 100, "RIGHT", text = function(r) return M(r.mail) end, sort = function(r) return r.mail end},
	{"Auctions", 100, "RIGHT", text = function(r) return M(r.auctions) end, sort = function(r) return r.auctions end},
	{"Total", 125, "RIGHT", text = function(r) return M(r.worth) end, sort = function(r) return r.worth end},
	{"Updated", 100, "RIGHT", text = function(r) return GREY .. X.Ago(r.at) .. "|r" end, sort = function(r) return r.at end},
}
local BEST = {["Auction house"] = "|cff4ade80Auction house|r", Vendor = "|cffffd100Vendor|r", ["Keep (bound)"] = GREY .. "Keep (bound)|r"}
local BAG_COLS = {
	{"Item", 165, "LEFT", text = function(r) return UI.ItemCell(r.key) end, sort = function(r) return (X.ItemName(r.key)) end, desc = false},
	{"Count", 40, "RIGHT", text = function(r) return X.Num(r.count) end, sort = function(r) return r.count end},
	{"AH value", 85, "RIGHT", text = function(r) return UI.MoneyCell(r.ah) end, sort = function(r) return r.ah end},
	{"Vendor", 75, "RIGHT", text = function(r) return UI.MoneyCell(r.vendor) end, sort = function(r) return r.vendor end},
	{"Best", 80, "LEFT", text = function(r) return r.best and (BEST[r.best] or r.best) or NONE end, sort = function(r) return r.best end},
	{"Sold/day", 48, "RIGHT", text = function(r)
		if not r.rate then return NONE end
		return r.rate >= 10 and X.Num(r.rate) or string.format("%.1f", r.rate)
	end, sort = function(r) return r.rate end},
}
-- the first column takes the room the others leave
local function fit(columns, w)
	local fixed = 0
	for i = 2, #columns do fixed = fixed + columns[i][2] end
	local out = {}
	for i, c in ipairs(columns) do out[i] = c end
	local first = columns[1]
	out[1] = {first[1], math.max(120, w - 20 - fixed), first[3], text = first.text, sort = first.sort, desc = first.desc}
	return out
end

local function onBagRow(row, button, rowFrame)
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
end
-- right-click a character: forget it (not this one: it comes back when you log in)
local function onCharRow(row, button, rowFrame)
	if button ~= "RightButton" or row.warbank then return end
	local items = {{text = row.name, isTitle = true}}
	if row.me then
		items[2] = {text = "This character (cannot be forgotten)", disabled = true}
	else
		items[2] = {text = "Forget this character", func = function()
			X.Confirm("Forget " .. row.name .. "'s gold, bags, bank and net worth history?", function() X.DeleteChar(row.key) end)
		end}
	end
	K.Menu(rowFrame, items)
end

local function refresh(p)
	local chars = X.Chars()
	local rows, total = {}, 0
	for _, c in ipairs(chars) do
		rows[#rows + 1] = c
		total = total + c.worth
	end
	local wb = X.db.warbank
	if wb then
		local v = X.WarbankWorth()
		rows[#rows + 1] = {warbank = true, name = "~", bank = v, worth = v, gold = 0, bags = 0, mail = 0, auctions = 0, at = wb.at}
		total = total + v
	end
	p.chars:SetRows(rows, "No characters yet - log in, open your bags, bank and mailbox.")
	local sync = X.db.sync
	p.help:SetText(GREY .. "Worth = auction house price after the cut (soulbound: what a vendor pays). Open your bank and " ..
		"mailbox once to count them. Right-click a character to forget it. " .. (sync and sync.at and
		("Other accounts joined " .. X.Ago(sync.at) .. " (Sync accounts on your PC, game closed).") or
		"Characters of your other WoW accounts: run \"Sync accounts\" in the XNAH folder on your PC with the game closed.") .. "|r")
	local gold = 0
	for _, c in ipairs(chars) do gold = gold + (c.gold or 0) end
	p.total:SetText("All characters" .. (wb and " and the account bank" or "") .. ":  " .. X.Money(total, true) ..
		GREY .. "   (gold " .. X.MoneyPlain(gold) .. ")|r")
	-- graph
	for i, b in ipairs(p.ranges) do b:SetSelected(i == rangeIdx) end
	local span = RANGES[rangeIdx][2]
	local pts = X.WorthHistory(nil, span and (X.Now() - span) or nil)
	p.graph:SetSeries({{points = pts, color = {1, 0.82, 0}, width = 2, label = "Net worth"}},
		{empty = "No history yet - recorded once a day when you log in"})
	-- bags
	local bags = X.BagRows()
	p.bags:SetRows(bags, "Nothing in your bags (or not read yet).")
	local sum = 0
	for _, r in ipairs(bags) do
		if r.best == "Auction house" then sum = sum + (r.ah or 0) elseif r.best == "Vendor" then sum = sum + (r.vendor or 0) end
	end
	p.bagSum:SetText(GREY .. "best way for all:|r " .. X.Money(sum, true))
end

local function build(p, W, H)
	W, H = W or UI.W, H or UI.H
	local GW = math.floor(W * 0.45)  -- graph width
	local BX = GW + 10                -- "Your bags" left edge
	local BW = W - BX
	local help = K.Label(p, "", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 0, 0)
	help:SetWidth(W)
	help:SetWordWrap(true)
	p.help = help

	p.chars = K.Table(p, W, 6 * 18 + 4, fit(CHAR_COLS, W), onCharRow)
	p.chars:SetPoint("TOPLEFT", 0, -46)
	p.chars:SortBy(7, true)
	p.total = K.Label(p, "", "GameFontNormal")
	p.total:SetPoint("TOPLEFT", 2, -46 - 6 * 18 - 12)
	p.total:SetWidth(W)
	p.total:SetWordWrap(false)

	-- [[ net worth graph ]]
	local gt = K.Label(p, "Net worth of all characters", "GameFontNormalSmall")
	gt:SetPoint("TOPLEFT", 0, -LOW)
	p.ranges = {}
	for i, r in ipairs(RANGES) do
		local b = K.Flat(p, 60, 18)
		b:SetPoint("TOPRIGHT", p, "TOPLEFT", GW - (#RANGES - i) * 64, -LOW + 2)
		b:SetLabel(r[1])
		b.label:SetJustifyH("CENTER")
		b:SetScript("OnClick", function() rangeIdx = i refresh(p) end)
		p.ranges[i] = b
	end
	p.graph = K.Graph(p, GW, H - LOW - 24)
	p.graph:SetPoint("TOPLEFT", 0, -LOW - 24)

	-- [[ your bags ]]
	local bt = K.Label(p, "Your bags: auction house or vendor?", "GameFontNormalSmall")
	bt:SetPoint("TOPLEFT", BX, -LOW)
	p.bagSum = K.Label(p, "", "GameFontHighlightSmall", "RIGHT")
	p.bagSum:SetPoint("TOPRIGHT", 0, -LOW)
	p.bagSum:SetWidth(260)
	p.bagSum:SetWordWrap(false)
	local bh = K.Label(p, "Best: where it brings more. Slow sellers (under 0.2 a day) go to a vendor unless the auction " ..
		"house pays 3 times as much.", "GameFontDisableSmall")
	bh:SetPoint("TOPLEFT", BX, -LOW - 16)
	bh:SetWidth(BW)
	bh:SetWordWrap(false)
	local top = LOW + 48
	p.bags = K.Table(p, BW, H - top, fit(BAG_COLS, BW), onBagRow)
	p.bags:SetPoint("TOPLEFT", BX, -top)
end

-- the Characters page of the Your gold view (UILedger.lua; UI.lua refreshes the shown view on XNAH_INVENTORY):
-- build(frame, width, height), refresh(frame)
UI.AddGoldPage("chars", "Characters", build, refresh, 4, "Gold and items of your characters on this realm (both factions).")
