-- The Next step key: ONE key (or the big "Next step" button on the Home page) for everything. Each press does the ONE
-- thing that comes next where you are:
--   at your profession window: craft the next recipe of your crafting queue (Queue.lua)
--   at a mailbox: take the next auction house mail (one gold or one item per press; only when you press, never by itself)
--   at the auction house: a purchase already going on first (confirm it), then cancel your undercut auctions and post
--     the ticked items (the one-key routine, Routine.lua), then buy: your shopping lists and the crafting queue's
--     materials first, then the best buy ideas (Buy.lua)
-- The game allows buying, posting, cancelling, crafting and taking mail only on a click or a key press: each press makes
-- at most ONE such call, and only the one X.DoNextPeek() names. Nothing here runs from a timer or an event.
--   X.DoNextPeek()        -> {what, text, area = "mail" / "cancel" / "post" / "buy" / "craft" / nil, act (true when a
--                            press does something), from = "craft" / "mail" / "routine" / "buy"}
--   X.DoNext(src, expect) ONE step. Call it only straight from a click or a key press. src "key" = the key binding (a
--                         line in chat says what happened); expect = the label the button showed: when the next step
--                         changed since it was drawn, the press only shows the new one (as UI.BuyButton does)
--   UI.DoNextButton(parent, w, h) (UIHome.lua) a big button for any page
local ADDON, X = ...

local ATTACH = 16

local function nameOf(key) return (X.ItemName(key)) or ("item " .. tostring(key)) end
local function plain(c) return X.MoneyPlain(math.floor((c or 0) + 0.5)) end
local function tell(src, text)
	if src == "key" and text then X.Print(text) end
end
local function changed() X.Fire("XNAH_NEXT") end

-- [[ where you are ]]
local function professionOpen()
	local T = C_TradeSkillUI
	return (T and T.IsTradeSkillReady and X.Try(T.IsTradeSkillReady)) and true or false
end
local mailShown = false
local function mailboxOpen()
	if MailFrame then return MailFrame:IsShown() == true end
	return mailShown
end
X.On("MAIL_SHOW", function() mailShown = true changed() end)
X.On("MAIL_CLOSED", function() mailShown = false changed() end)
for _, e in ipairs({"MAIL_INBOX_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "XNAH_AH", "XNAH_ROUTINE", "XNAH_BUY", "XNAH_MAIL"}) do
	X.On(e, function() X.Debounce("xnah-next", 0.2, changed) end)
end

-- [[ the mailbox ]] one take per press: the gold of an auction house mail first, else one of its items. Mail.lua's
-- X.MailTakeOne is used when it is there; else the same test of which mails are auction house mails as Mail.lua's.
local outbid
local function isOutbid(subject)
	if not outbid then
		outbid = {}
		for _, fmt in ipairs({AUCTION_OUTBID_MAIL_SUBJECT, "Outbid on %s"}) do
			if type(fmt) == "string" and fmt ~= "" then
				local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.+)")
				outbid[#outbid + 1] = "^" .. p .. "$"
			end
		end
	end
	if type(subject) ~= "string" then return false end
	for _, p in ipairs(outbid) do if subject:find(p) then return true end end
	return false
end
-- is mail i an auction house mail? -> true, money, items (attachments with something in them)
local function auctionMail(i)
	local _, _, _, subject, money, cod, _, itemCount, _, _, _, _, isGM = X.Try(GetInboxHeaderInfo, i)
	subject = X.Plain(subject)
	if X.Plain(isGM) or (X.Plain(cod) or 0) > 0 then return false end
	local kind
	if GetInboxInvoiceInfo then
		local itype = X.Try(GetInboxInvoiceInfo, i)
		if itype == "seller" or itype == "buyer" or itype == "seller_temp_invoice" then kind = itype end
	end
	if not kind and X.LedgerSubject and X.LedgerSubject(subject) then kind = "returned" end
	if not kind and isOutbid(subject) then kind = "outbid" end
	if not kind then return false end
	local items = 0
	if (X.Plain(itemCount) or 0) > 0 then
		for a = 1, ATTACH do
			if (HasInboxItem and X.Try(HasInboxItem, i, a)) or (GetInboxItemLink and X.Try(GetInboxItemLink, i, a)) then items = items + 1 end
		end
	end
	return true, X.Plain(money) or 0, items
end
local function freeSlots()
	if C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots then
		return X.Plain(X.Try(C_Container.CalculateTotalNumberOfFreeBagSlots)) or 1
	end
	return 1
end
local failed = {} -- item IDs the server would not give (this session)
X.On("MAIL_FAILED", function(itemID)
	itemID = X.Plain(itemID)
	if itemID then failed[itemID] = true end
end)
-- ONE take. -> true and what was taken, or false and why not
local function takeMail()
	if X.MailTakeOne then return X.MailTakeOne() end
	if not (GetInboxNumItems and TakeInboxMoney and TakeInboxItem) then return false, "taking mail is not possible on this client" end
	if X.LedgerReadMail then X.LedgerReadMail() end -- every mail is in the ledger before it goes
	local n = X.Try(GetInboxNumItems) or 0
	for i = 1, n do
		local ok, money = auctionMail(i)
		if ok and money > 0 then
			TakeInboxMoney(i)
			return true, "took " .. plain(money) .. " from an auction house mail"
		end
	end
	if freeSlots() <= 0 then return false, "your bags are full" end
	for i = 1, n do
		local ok, _, items = auctionMail(i)
		if ok and items > 0 then
			for a = 1, ATTACH do
				local link = GetInboxItemLink and X.Try(GetInboxItemLink, i, a)
				local has = (HasInboxItem and X.Try(HasInboxItem, i, a)) or link
				local name, itemID, _, count
				if GetInboxItem then name, itemID, _, count = X.Try(GetInboxItem, i, a) end
				if has and not (itemID and failed[itemID]) then
					TakeInboxItem(i, a)
					return true, "took " .. X.Num(tonumber(X.Plain(count)) or 1) .. " x " .. tostring(X.Plain(name) or link or "an item")
				end
			end
		end
	end
	return false, "no auction house mail with gold or items"
end
local function mailPeek()
	if X.MailRunning and X.MailRunning() then return {what = "busy", area = "mail", from = "mail", text = "Taking auction house mail ..."} end
	if C_Mail and C_Mail.IsCommandPending and X.Try(C_Mail.IsCommandPending) then
		return {what = "busy", area = "mail", from = "mail", text = "Waiting for the mailbox ..."}
	end
	local mails, money, items = 0, 0, 0
	if X.MailWaiting then mails, money, items = X.MailWaiting() end
	if mails == 0 then return {what = "none", area = "mail", from = "mail", text = "No auction house mail waiting"} end
	if money == 0 and freeSlots() <= 0 then
		return {what = "full", area = "mail", from = "mail", text = "Your bags are full: " .. X.Num(items) .. (items == 1 and " item waits" or " items wait") .. " in the mailbox"}
	end
	local parts = {}
	if money > 0 then parts[#parts + 1] = plain(money) end
	if items > 0 then parts[#parts + 1] = X.Num(items) .. (items == 1 and " item" or " items") end
	return {what = "mail", area = "mail", from = "mail", act = true,
		text = "Take the next auction mail (" .. X.Num(mails) .. " left: " .. table.concat(parts, ", ") .. ")"}
end

-- [[ the auction house ]]
local GOING = {ready = true, confirm = true, quoting = true, buying = true, searching = true} -- a purchase going on
local BUY_ACTS = {check = true, buy = true, confirm = true, poor = true}
local function buyPeek()
	local p = X.NextBuyPeek()
	return {what = p.what, text = p.text, area = "buy", from = "buy", act = BUY_ACTS[p.what] == true, idea = p.idea}
end
local function routinePeek()
	local R = X.routine
	if R.state == "off" and R.userStopped then return nil end -- you stopped it (tab Sell): on to buying
	local r = X.RoutinePeek()
	local s = r.step
	if r.what == "start" then
		return {what = "start", area = "cancel", from = "routine", act = true, text = "Check your auctions and bags (to cancel and post)"}
	elseif r.what == "cancel" then
		local by = (s.unit and s.lowest) and (" (undercut by " .. plain(s.unit - s.lowest) .. ")") or " (undercut)"
		return {what = "cancel", area = "cancel", from = "routine", act = true, text = "Cancel " .. nameOf(s.key) .. " x" .. X.Num(s.qty or 1) .. by}
	elseif r.what == "post" then
		local p = r.post
		return {what = "post", area = "post", from = "routine", act = true, text = "Post " .. (p.qty > 1 and (X.Num(p.qty) .. " ") or "") ..
			nameOf(s.key) .. " at " .. plain(p.unit) .. (p.qty > 1 and " each" or "")}
	elseif r.what == "confirm" then
		return {what = "confirm", area = "post", from = "routine", act = true,
			text = "Confirm: post " .. X.Num(s.qty or 1) .. " " .. nameOf(s.key) .. " (the auction house warns about the price)"}
	elseif r.what == "wait" or r.what == "busy" then
		return {what = r.what, area = R.phase == "cancel" and "cancel" or "post", from = "routine", text = r.text}
	end
	return nil -- done / finish: nothing left to cancel or post
end
local function ahPeek()
	local b = X.buy
	if b.key and GOING[b.state] then return buyPeek() end
	local r = routinePeek()
	if r then return r end
	local p = buyPeek()
	if p.what == "none" then
		return {what = "recheck", from = "routine", act = true, text = "All done here - press to check your auctions again"}
	end
	return p
end

function X.DoNextPeek()
	local craftWhy
	if professionOpen() and X.CraftNextTarget then
		local row, count = X.CraftNextTarget()
		if row then
			return {what = "craft", area = "craft", from = "craft", act = true, row = row, count = count,
				text = "Craft " .. nameOf(row.key) .. (count > 1 and (" x" .. X.Num(count)) or "")}
		end
		craftWhy = count
	end
	if mailboxOpen() then return mailPeek() end
	if X.ahOpen then return ahPeek() end
	if craftWhy then return {what = "none", area = "craft", from = "craft", text = craftWhy} end
	return {what = "away", text = "Go to the auction house, a mailbox or your profession window"}
end

-- ONE step. Call it only straight from a click or a key press.
function X.DoNext(src, expect)
	local a = X.DoNextPeek()
	-- only what the label said: when the next step changed since it was drawn, this press only shows the new one
	if expect and expect ~= a.text then changed() return false end
	local did = false
	if a.what == "craft" then
		did = X.CraftNext()
	elseif a.what == "mail" then
		local ok, what = takeMail()
		did = ok
		tell(src, what)
	elseif a.what == "recheck" then
		X.RoutineStart()
		tell(src, "checking your auctions and bags again - press again in a moment")
	elseif a.from == "buy" then
		did = X.NextBuy(src)
	elseif a.from == "routine" then
		did = X.RoutineNext(src)
	else
		tell(src, a.text)
	end
	changed()
	return did and true or false
end

-- [[ the key binding ]] (Bindings.xml; the key is set in the game's key bindings, under AddOns)
BINDING_NAME_XNAH_NEXT = "Next step: buy, sell, cancel, craft, mail"
function XNAH_Next()
	X.DoNext("key")
end
