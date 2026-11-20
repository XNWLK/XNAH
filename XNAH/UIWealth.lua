-- The "Characters" view of the Gold tab (UILedger.lua builds the tab): your characters of this realm and faction -
-- gold, and what their bags, bank, mailbox and auctions are worth - with the total over time, and for this character
-- what to do with each thing in the bags.
-- Layout (940 x 522, under the Gold tab's view buttons): help and "Delete a character" on top; the characters table
-- (6 rows) and the total line; below the net worth graph (left, 440 wide) and "Your bags" (right, 490 wide).
local ADDON, X = ...
local K, UI = X.K, X.UI

local W, H = UI.W, UI.H - 28
local GREY = "|cff999999"
local NONE = "|cff666666-|r"
local DAY = 86400
local RANGES = {{"30 days", 30 * DAY}, {"90 days", 90 * DAY}, {"All", nil}}
local rangeIdx = 1
local GW = 440           -- graph width
local BX = GW + 10       -- "Your bags" left edge
local BW = W - BX        -- 490
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
	{"Sold/day", 40, "RIGHT", text = function(r)
		if not r.rate then return NONE end
		return r.rate >= 10 and X.Num(r.rate) or string.format("%.1f", r.rate)
	end, sort = function(r) return r.rate end},
}

local function onBagRow(row, button, rowFrame)
	if button == "RightButton" then UI.ItemMenu(rowFrame, row.key) else UI.ShowItem(row.key) end
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
	p.help:SetText(GREY .. "Gold and items of your characters, worth their auction house price after the cut (soulbound: what a " ..
		"vendor pays). Open your bank and mailbox once to count them. " .. (sync and sync.at and
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

local function build(p)
	local help = K.Label(p, "Gold and items of your characters here, worth their auction house price after the cut " ..
		"(soulbound: what a vendor pays). Open your bank and mailbox once to count them.", "GameFontDisableSmall")
	help:SetPoint("TOPLEFT", 0, 0)
	help:SetWidth(W - 160)
	help:SetWordWrap(true)
	p.help = help
	local del = K.Button(p, "Delete a character", 150, 20, function(self)
		local items = {{text = "Delete which character?", isTitle = true}}
		local mine = X.CharKey()
		for _, c in ipairs(X.Chars()) do
			if c.key ~= mine then
				items[#items + 1] = {text = c.name, func = function()
					X.Confirm("Forget " .. c.name .. "'s gold, bags, bank and net worth history?", function() X.DeleteChar(c.key) end)
				end}
			end
		end
		if #items == 1 then items[2] = {text = "No other characters saved", disabled = true} end
		K.Menu(self, items)
	end)
	del:SetPoint("TOPRIGHT", 0, 0)
	K.Tooltip(del, "Delete a character", "Forget a character you deleted or moved (this one comes back when you log in).")

	p.chars = K.Table(p, W, 6 * 18 + 4, CHAR_COLS)
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
	local bt = K.Label(p, "Your bags: sell or keep?", "GameFontNormalSmall")
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
	p.bags = K.Table(p, BW, H - top, BAG_COLS, onBagRow)
	p.bags:SetPoint("TOPLEFT", BX, -top)
end

-- the Gold tab (UILedger.lua) calls these for its Characters view (UI.lua refreshes the shown page on XNAH_INVENTORY)
UI.GoldChars = {build = build, refresh = refresh}
