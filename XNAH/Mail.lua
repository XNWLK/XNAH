-- The mailbox: an "Open all auction mail" button next to the game's mail window. One click takes the gold and the items
-- of every auction house mail (sold, won, expired, cancelled, outbid), one at a time with a short pause (the server
-- needs it), and stops when the bags are full (gold is still taken) or the mailbox closes. Other mails (from players,
-- cash on delivery, from a Game Master) are never touched. The ledger (Ledger.lua) reads every mail before it is taken.
--   XNAHDB.mailLast = {t, text}  what the last run took (shown on the Settings page)
-- The game's own "Open all" also takes mail on a timer, so taking mail is not limited to clicks. Should the game still
-- block XNAH (it says so with ADDON_ACTION_BLOCKED), the button goes over to one mail per click.
local ADDON, X = ...
-- (loaded before UIKit.lua: the widgets are looked up when the bar is first made)

X.Default("mailButton", true)

local STEP = 0.3        -- seconds between two takes
local WAIT_MAX = 10     -- seconds to wait for the server to finish one take before going on
local TRIES = 3         -- tries on one mail before it is left alone
local ATTACH = 16

-- the run in progress: {money0, items (units taken), mails (how many emptied), tries, skip, failed (item IDs the
-- server refused), seen, waitUntil, lastAdd}
local run
local perClick = false  -- the game blocked a timed take: one take per click from now on (this session)
local paused            -- one per click: the run between two clicks
local readDirty = true  -- the mailbox changed since the ledger read it
local bar

-- [[ which mails ]]
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

-- is mail i an auction house mail XNAH may empty? -> true, money, items (attachments with something in them), id
local function auctionMail(i)
	local _, _, sender, subject, money, cod, daysLeft, itemCount, _, _, _, _, isGM = X.Try(GetInboxHeaderInfo, i)
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
	money = X.Plain(money) or 0
	local items = 0
	if (X.Plain(itemCount) or 0) > 0 then
		for a = 1, ATTACH do
			if (HasInboxItem and X.Try(HasInboxItem, i, a)) or (GetInboxItemLink and X.Try(GetInboxItemLink, i, a)) then items = items + 1 end
		end
	end
	return true, money, items, tostring(sender) .. "|" .. tostring(subject) .. "|" .. string.format("%.3f", tonumber(daysLeft) or 0)
end

-- what is waiting: mails, gold, items (auction house mails only)
function X.MailWaiting()
	local n = GetInboxNumItems and (X.Try(GetInboxNumItems) or 0) or 0
	local mails, money, items = 0, 0, 0
	for i = 1, n do
		local ok, m, it = auctionMail(i)
		if ok and (m > 0 or it > 0) then
			mails = mails + 1
			money = money + m
			items = items + it
		end
	end
	return mails, money, items
end

function X.MailLast() return X.db and X.db.mailLast end
function X.MailRunning() return run ~= nil end

-- [[ the bar ]]
local function freeSlots()
	if C_Container and C_Container.CalculateTotalNumberOfFreeBagSlots then
		return X.Plain(X.Try(C_Container.CalculateTotalNumberOfFreeBagSlots)) or 1
	end
	return 1
end

local function updateBar(text)
	if not bar or not bar:IsShown() then return end
	if run then
		bar.go:SetText("Stop")
		bar.text:SetText(text or ("Taking auction house mail ... " .. X.Money(math.max(0, (X.Plain(GetMoney()) or 0) - run.money0), true) ..
			", " .. run.items .. (run.items == 1 and " item" or " items") .. " so far"))
		return
	end
	local mails, money, items = X.MailWaiting()
	bar.go:SetText(perClick and "Take next auction mail" or "Open all auction mail")
	bar.go:SetEnabled(mails > 0)
	if text then bar.text:SetText(text) return end
	if mails == 0 then
		bar.text:SetText("|cff999999No auction house mail with gold or items.|r")
	else
		bar.text:SetText(mails .. " auction house mail" .. (mails == 1 and "" or "s") .. ": " .. X.Money(money, true) ..
			(items > 0 and (", " .. items .. (items == 1 and " item" or " items")) or ""))
	end
end

-- [[ taking ]]
local function finish(why)
	if not run then return end
	local r = run
	run = nil
	if C_Mail and C_Mail.SetOpeningAll then X.Try(C_Mail.SetOpeningAll, false) end
	local gold = math.max(0, (X.Plain(GetMoney()) or 0) - r.money0)
	local parts = {}
	if gold > 0 then parts[#parts + 1] = X.MoneyPlain(gold) end
	if r.items > 0 then parts[#parts + 1] = r.items .. (r.items == 1 and " item" or " items") end
	local text = (#parts > 0 and ("took " .. table.concat(parts, " and ")) or "took nothing") ..
		(r.mails > 0 and (" from " .. r.mails .. " auction house mail" .. (r.mails == 1 and "" or "s")) or "")
	if why == "bags" then text = text .. ". Your bags are full: the other items wait in the mailbox."
	elseif why == "closed" then text = text .. " (the mailbox was closed)."
	elseif why == "stopped" then text = text .. " (stopped)."
	elseif why == "blocked" then text = text .. ". The game asked for a click per mail: click the button for each one."
	else
		local shown, total = X.Try(GetInboxNumItems)
		if (tonumber(total) or 0) > (tonumber(shown) or 0) then
			text = text .. ". More mail waits on the server: it shows up in about a minute (close and open the mailbox)."
		else
			text = text .. "."
		end
	end
	X.db.mailLast = {t = X.Now(), text = text}
	X.Print(text)
	X.Fire("XNAH_MAIL")
	updateBar(text)
end

-- one take: the first auction house mail with something left (r = the run: the Open-all run, or the one-at-a-time
-- state of X.MailTakeOne). Returns "took", "wait" (nothing to do yet), "bags" (only items are left and the bags are
-- full) or "done". r.last = what this take asked for: {money = copper} or {name, count}
local function takeOne(r)
	if readDirty and X.LedgerReadMail then
		readDirty = false
		X.LedgerReadMail() -- every mail is in the ledger before it goes
	end
	local n = X.Try(GetInboxNumItems) or 0
	local onlyItemsLeft = false
	-- r.moneyFirst (one take per call): first the gold of every mail, then the items; Open all goes mail by mail
	for pass = r.moneyFirst and 1 or 2, 2 do
		for i = 1, n do
			local ok, money, items, id = auctionMail(i)
			if ok and not r.skip[id] and (money > 0 or (pass == 2 and items > 0)) then
				if money > 0 then
					r.tries[id] = (r.tries[id] or 0) + 1
					if r.tries[id] > TRIES then r.skip[id] = true
					else
						if not r.seen[id] then r.seen[id] = true r.mails = r.mails + 1 end
						r.lastAdd = 0
						r.last = {money = money}
						TakeInboxMoney(i)
						return "took"
					end
				elseif freeSlots() <= 0 then
					onlyItemsLeft = true
				else
					for a = 1, ATTACH do
						local link = GetInboxItemLink and X.Try(GetInboxItemLink, i, a)
						local has = (HasInboxItem and X.Try(HasInboxItem, i, a)) or link
						local itemID = GetInboxItem and select(2, X.Try(GetInboxItem, i, a))
						if has and not (itemID and r.failed[itemID]) then
							local key = id .. "#" .. a
							r.tries[key] = (r.tries[key] or 0) + 1
							if r.tries[key] > TRIES then
								r.skip[id] = true
							else
								if not r.seen[id] then r.seen[id] = true r.mails = r.mails + 1 end
								local iname, _, _, count
								if GetInboxItem then iname, _, _, count = X.Try(GetInboxItem, i, a) end
								r.lastAdd = tonumber(X.Plain(count)) or 1
								r.items = r.items + r.lastAdd
								r.last = {name = X.Plain(iname), count = r.lastAdd}
								TakeInboxItem(i, a)
								return "took"
							end
							break
						end
					end
				end
			end
		end
	end
	if onlyItemsLeft then return "bags" end
	return "done"
end

local step
local function schedule(delay)
	local r = run
	X.After(delay, function() if run == r then step() end end)
end
step = function()
	if not run then return end
	if not (bar and bar:IsShown()) then finish("closed") return end
	-- the server is still busy with the last take: wait (a little)
	if C_Mail and C_Mail.IsCommandPending and X.Try(C_Mail.IsCommandPending) and X.Now() < run.waitUntil then
		schedule(STEP)
		return
	end
	local what = takeOne(run)
	if not run then return end -- the game blocked the take (see ADDON_ACTION_BLOCKED below)
	if what == "took" then
		run.waitUntil = X.Now() + WAIT_MAX
		updateBar()
		if perClick then
			-- one per click: the next click goes on
			local r = run
			run = nil
			paused = r
			updateBar("Click again for the next mail.")
			return
		end
		schedule(STEP)
	else
		finish(what)
	end
end

local function start()
	if not (GetInboxNumItems and TakeInboxMoney and TakeInboxItem) then
		X.Print("taking mail is not possible on this client")
		return
	end
	if run then finish("stopped") return end
	if paused then
		run = paused -- one per click: go on with the same run
		paused = nil
	else
		run = {money0 = X.Plain(GetMoney()) or 0, items = 0, mails = 0, tries = {}, skip = {}, failed = {}, seen = {}, waitUntil = 0}
		readDirty = true
		if C_Mail and C_Mail.SetOpeningAll then X.Try(C_Mail.SetOpeningAll, true) end
	end
	step() -- the first take straight from the click
end
X.MailOpenAll = start
X.MailStop = function() if run then finish("stopped") end end

-- [[ one take per call ]] X.MailTakeOne() -> ok, text. For the next-step key (Next.lua): call it straight from a key
-- press or a click, never from a timer. Takes ONE thing out of the first auction house mail with something in it
-- (gold before items; the same mails as Open all: sold, bought, expired, cancelled, outbid - never mail from players,
-- cash on delivery or Game Masters); the ledger reads the mailbox first. ok = false (and why) when the mailbox is
-- closed, Open all is running, the server is still busy with the last take, the bags are full or nothing is left.
local single -- the one-at-a-time state while the mailbox is open: {tries, skip, failed, seen, items, mails}
function X.MailTakeOne()
	if not (GetInboxNumItems and TakeInboxMoney and TakeInboxItem) then return false, "Taking mail is not possible on this client." end
	if not (MailFrame and MailFrame:IsShown()) then return false, "Open your mailbox first." end
	if run then return false, "Open all is already taking the auction house mail." end
	if C_Mail and C_Mail.IsCommandPending and X.Try(C_Mail.IsCommandPending) then
		return false, "The mailbox is still busy with the last mail - press again in a moment."
	end
	if not single then single = {items = 0, mails = 0, tries = {}, skip = {}, failed = {}, seen = {}, moneyFirst = true} end
	single.last = nil
	local what = takeOne(single)
	if what == "took" then
		local l = single.last or {}
		local text
		if l.money then
			text = "took " .. X.MoneyPlain(l.money) .. " from an auction house mail"
		else
			text = "took " .. (l.count and l.count > 1 and (l.count .. " x ") or "") .. (l.name or "an item") .. " from an auction house mail"
		end
		X.Fire("XNAH_MAIL")
		return true, text
	end
	if what == "bags" then return false, "Your bags are full: the other items wait in the mailbox." end
	return false, "No auction house mail with gold or items left."
end

local function buildBar()
	local K = X.K
	-- a child of the game's mail window: it can never stay when that window closes (Xn saw it stay after walking
	-- away - the mailbox closed signal does not always come on Forever)
	bar = CreateFrame("Frame", "XNAHMailBar", MailFrame or UIParent, "BackdropTemplate")
	if MailFrame and MailFrame.HookScript then
		MailFrame:HookScript("OnHide", function() X.UpdateMailButton(false) end)
	end
	bar:SetSize(384, 50)
	bar:SetFrameStrata("HIGH")
	bar:SetClampedToScreen(true)
	K.Backdrop(bar, K.colors.bg)
	local name = K.Label(bar, "|cffe6b422XNAH|r", "GameFontNormal")
	name:SetPoint("TOPLEFT", 8, -8)
	bar.go = K.Button(bar, "Open all auction mail", 180, 22, function() start() end)
	bar.go:SetPoint("TOPLEFT", 52, -4)
	K.Tooltip(bar.go, "Open all auction mail", "Takes the gold and items of every auction house mail (sold, bought, " ..
		"expired, cancelled, outbid), one after the other, and writes them in the ledger (tab Gold). Mails from players, " ..
		"cash on delivery and Game Masters are left alone. Stops when your bags are full (gold is still taken). " ..
		"Click again to stop.")
	bar.text = K.Label(bar, "")
	bar.text:SetPoint("TOPLEFT", 8, -30)
	bar.text:SetPoint("RIGHT", -8, 0)
	bar.text:SetWordWrap(false)
	bar:Hide()
end

-- shows or hides the button with the game's mail window
function X.UpdateMailButton(open)
	if open == nil then open = MailFrame ~= nil and MailFrame:IsShown() end
	if not open or not X.S().mailButton or not MailFrame then
		if run then finish("closed") end
		paused = nil
		if bar then bar:Hide() end
		return
	end
	if not bar then buildBar() end
	bar:ClearAllPoints()
	bar:SetPoint("BOTTOMLEFT", MailFrame, "TOPLEFT", 0, 2) -- above it (an opened mail shows at its right)
	bar:Show()
	updateBar()
end

X.On("MAIL_SHOW", function()
	readDirty = true
	single = nil
	X.After(0.2, function() X.UpdateMailButton(true) end)
end)
X.On("MAIL_CLOSED", function()
	readDirty = true
	single = nil
	X.UpdateMailButton(false)
end)
-- walking away from the mailbox closes it through the game's interaction manager
X.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function()
	if bar and bar:IsShown() and not (MailFrame and MailFrame:IsShown()) then
		readDirty = true
		X.UpdateMailButton(false)
	end
end)
X.On("MAIL_INBOX_UPDATE", function()
	readDirty = true
	if not run then X.Debounce("xnah-mailbar", 0.3, function() updateBar() end) end
end)
X.On("MAIL_FAILED", function(itemID)
	itemID = X.Plain(itemID)
	if run and itemID then run.failed[itemID] = true end
	if single and itemID then single.failed[itemID] = true end
end)
-- the game refused a take that did not come from a click: the item it was about is not counted, and from now on every
-- click takes one
local function blocked(addon)
	if addon ~= ADDON or not run or perClick then return end
	perClick = true
	run.items = run.items - (run.lastAdd or 0)
	finish("blocked")
end
X.On("ADDON_ACTION_BLOCKED", blocked)
X.On("ADDON_ACTION_FORBIDDEN", blocked)
