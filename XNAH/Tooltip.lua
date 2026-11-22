-- Lines on every item tooltip: auction house price and market value, averages and trend, vendor prices, crafting cost.
-- On Forever, tooltip lines go through TooltipDataProcessor (hooking GameTooltip's Set* functions breaks bag tooltips).
local ADDON, X = ...

local GREY = "|cff999999"

-- how many of the item the tooltip is about (a stack in the bags), or 1
local function stackOf(tooltip)
	local info = tooltip.GetProcessingTooltipInfo and X.Try(tooltip.GetProcessingTooltipInfo, tooltip)
	local getter, args = info and info.getterName, info and info.getterArgs
	if getter == "GetBagItem" and args and C_Container and C_Container.GetContainerItemInfo then
		local c = X.Try(C_Container.GetContainerItemInfo, args[1], args[2])
		if c and c.stackCount and c.stackCount > 1 then return c.stackCount end
	end
	return 1
end

-- the lines for one item: {{left, right}, ...} (also used by the item page)
function X.TooltipLines(key, count)
	local S = X.S()
	count = count or 1
	local s = X.Summary(key)
	local lines = {}
	local function add(label, value, each)
		if value == nil then return end
		local text = X.Money(value * count, true)
		if count > 1 and each ~= false then text = text .. GREY .. " (" .. X.Money(value, true) .. GREY .. " each)|r" end
		lines[#lines + 1] = {label, text}
	end
	local head = "|cffe6b422XNAH|r"
	if count > 1 and S.tipStack then head = head .. GREY .. " x" .. count .. "|r" end
	if s.cur then
		local age = s.fresh and "" or " |cffff8040(old)|r"
		if (s.cur.qty or 0) == 0 then
			lines[#lines + 1] = {head .. age, GREY .. "none listed " .. X.Ago(s.cur.t) .. "|r"}
		else
			lines[#lines + 1] = {head .. age, GREY .. X.Num(s.cur.qty) .. " listed, " .. X.Ago(s.cur.t) .. "|r"}
			add("  Lowest price", s.cur.min)
			add("  Market value", s.cur.mkt)
		end
		if S.tipHistory and s.st then
			if s.st.avg7 then
				local trend = s.st.trend and ("  " .. X.Arrow(s.st.trend) .. " " .. X.Pct(s.st.trend) .. GREY .. "/wk|r") or ""
				lines[#lines + 1] = {"  7-day average", X.Money(s.st.avg7 * count, true) .. trend}
			end
			add("  30-day average", s.st.avg30)
		end
		-- how many sell a day (an estimate from comparing full scans, or your own sales)
		if S.tipSpeed and X.SaleRate then
			local rate = X.SaleRate(key)
			if rate then lines[#lines + 1] = {"  Sells per day", GREY .. "about|r " .. X.Rate(rate)} end
		end
		-- the weekday it sells highest on (only when the history shows one clearly)
		if S.tipHistory and X.BestDay then
			local bd = X.BestDay(key)
			if bd then lines[#lines + 1] = {"  Best day to sell", bd.name .. " " .. GREY .. "(|r" .. X.Pct(bd.pct) .. GREY .. ")|r"} end
		end
	end
	if S.tipLedger and X.LedgerItem then
		local l = X.LedgerItem(key)
		if l and ((l.sold or 0) > 0 or (l.bought or 0) > 0) then
			if #lines == 0 then lines[#lines + 1] = {head, ""} end
			local parts = {}
			if (l.sold or 0) > 0 then parts[#parts + 1] = "sold " .. X.Num(l.sold) .. (l.avgSell and (" at " .. X.MoneyPlain(l.avgSell)) or "") end
			if (l.bought or 0) > 0 then parts[#parts + 1] = "bought " .. X.Num(l.bought) .. (l.avgBuy and (" at " .. X.MoneyPlain(l.avgBuy)) or "") end
			lines[#lines + 1] = {"  You", GREY .. table.concat(parts, ", ") .. "|r"}
		end
	end
	if S.tipVendor then
		if s.vsell then
			if #lines == 0 then lines[#lines + 1] = {head, ""} end
			add("  Vendor pays", s.vsell)
		end
		if s.vbuy then
			if #lines == 0 then lines[#lines + 1] = {head, ""} end
			add("  Vendor sells at", s.vbuy)
		end
	end
	if S.tipCraft and s.craft then
		if #lines == 0 then lines[#lines + 1] = {head, ""} end
		local profit = s.craftProfit and ("  " .. (s.craftProfit >= 0 and "|cff4ade80" or "|cfff87171") .. X.MoneyPlain(s.craftProfit * count) .. "|r") or ""
		lines[#lines + 1] = {"  Crafting cost", X.Money(s.craft * count, true) .. profit}
	end
	-- strategies (Strategies page) that list this item, for those with "mark on tooltips" on
	if X.StrategyMarks then
		local marks = X.StrategyMarks(key)
		if marks and #marks > 0 then
			if #lines == 0 then lines[#lines + 1] = {head, ""} end
			lines[#lines + 1] = {"  Strategy", "|cffffd100" .. table.concat(marks, ", ") .. "|r"}
		end
	end
	if S.tipDE and X.DEValue then
		local de = X.DEValue(key)
		if de then
			if #lines == 0 then lines[#lines + 1] = {head, ""} end
			add("  Disenchant value", de)
		end
	end
	return lines
end
X.Default("tipSpeed", true)
X.Default("tipLedger", true)
X.Default("tipDE", true)

-- "3.5", "0.4", "12" (units per day)
function X.Rate(r)
	if not r then return "-" end
	if r >= 10 then return X.Num(r) end
	if r >= 1 then return string.format("%.1f", r) end
	return string.format("%.2f", r)
end

local function onItem(tooltip, data)
	if not X.db or not X.S().tooltip then return end
	if tooltip ~= GameTooltip and tooltip ~= (ItemRefTooltip or false) then return end
	local link
	if tooltip.GetItem then
		local _, l = X.Try(tooltip.GetItem, tooltip)
		link = l
	end
	local key = X.KeyFromLink(link) or (data and data.id and tostring(data.id))
	if not key then return end
	local lines = X.TooltipLines(key, stackOf(tooltip))
	if #lines == 0 then return end
	for _, l in ipairs(lines) do tooltip:AddDoubleLine(l[1], l[2], 1, 1, 1, 1, 1, 1) end
end

X.On("PLAYER_LOGIN", function()
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			local ok, err = pcall(onItem, tooltip, data)
			if not ok then X.OnError(err) end
		end)
	else
		X.Debug("no tooltip hook on this client")
	end
end)
