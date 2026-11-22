-- The one-key routine: each press of one key (or of the big "Post next" button on the Sell tab) does the next step:
-- first cancel your auctions that someone undercut, then post the ticked items in your bags (Sell tab, "Worth posting":
-- everything worth posting is ticked; untick what you want to keep), most valuable first, at XNAH's price. The game
-- allows posting and cancelling only on a click or a key press, one action each, so this is as automatic as it is
-- allowed to be. Everything that is NOT restricted (asking for your auctions, searching prices about one a second) runs
-- in the background as soon as the routine starts, so each press can act at once. It never buys anything.
-- The key is the Next step key (Next.lua), which does these steps at the auction house. What your crafting queue still
-- uses (its materials) is not posted, unless you ticked the item yourself.
--   X.RoutineStart()    start a round (not restricted; the first press does this, and the Sell tab when it is shown)
--   X.RoutineAuto()     start a round if none is going on and you did not stop it (the Sell tab calls it)
--   X.RoutineNext(src)  ONE step. Call it only straight from a click or a key press (src "key" = the key binding).
--   X.RoutinePeek()     what the next press will do: {what, text, step} (what = closed / start / done / busy / wait /
--                       cancel / post / confirm / finish)
--   X.RoutineSkip()     skip the next step (or say no to a price warning)
--   X.RoutineStop()     stop the round
--   X.RoutineProgress() -> finished steps, all steps
--   X.routine = {state = off / on / done, phase = scan / cancel / posts / ready, steps, cur (the step waiting for the
--     auction house's answer), counts = {cancelled, posted, skipped}, text}
--   step = {kind = cancel / post, key, qty, unit, lowest, auctionID, status = wait / todo / sent / done / skipped, why}
-- While a round is on, ticking or unticking an item and new things in your bags change its steps at once; a later check
-- of your auctions adds the newly undercut ones (first).
local ADDON, X = ...

X.Default("routineCancel", true)

local R
local function reset(state)
	R = {state = state or "off", steps = {}, counts = {cancelled = 0, posted = 0, skipped = 0}, token = {}, looked = {}, waiting = 0}
	X.routine = R
end
reset()

local function changed() X.Fire("XNAH_ROUTINE") end
local function nameOf(key) return (X.ItemName(key)) or ("item " .. tostring(key)) end
-- a line in chat, only for key presses (the button shows it on the Sell tab)
local function tell(src, text)
	if src == "key" and text then X.Print(text) end
end

function X.RoutineProgress()
	local finished = 0
	for _, s in ipairs(R.steps) do
		if s.status == "done" or s.status == "skipped" then finished = finished + 1 end
	end
	return finished, #R.steps
end
local function doneText()
	local c = R.counts
	if c.cancelled + c.posted + c.skipped == 0 then return "Done: nothing to cancel or post" end
	return "Done: " .. c.cancelled .. " cancelled, " .. c.posted .. " posted" .. (c.skipped > 0 and (", " .. c.skipped .. " skipped") or "")
end

-- [[ the plan ]]
-- what of an item may be posted: all you have, minus what your crafting queue still uses (Queue.lua) unless you ticked
-- the item yourself
local function postable(row)
	local keep = (X.QueueKeep and X.SellChoice(row.key) ~= true) and X.QueueKeep(row.key) or 0
	return math.max(0, row.have - keep), keep
end
-- post steps for the items in your bags you did not untick (looked at once per round), most valuable first: stackable
-- items in one auction (all of them), other items one auction per piece. Their price is searched first ("wait").
local function addPostSteps(rows, only)
	local list = {}
	for _, row in ipairs(rows) do
		if X.SellChoice(row.key) ~= false and not R.looked[row.key] and (not only or only == row.key) and postable(row) > 0 then
			R.looked[row.key] = true
			local _, w = X.SellWorth(row)
			list[#list + 1] = {row = row, value = w.net or 0}
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.row.key < b.row.key
	end)
	local added = {}
	for _, x in ipairs(list) do
		local row = x.row
		local n = postable(row)
		for _ = 1, row.commodity and 1 or n do
			R.steps[#R.steps + 1] = {kind = "post", key = row.key, qty = row.commodity and n or 1, status = "wait"}
		end
		added[#added + 1] = row.key
	end
	return added
end
local function removeSteps(key)
	for i = #R.steps, 1, -1 do
		local s = R.steps[i]
		if s.kind == "post" and (not key or s.key == key) and (s.status == "wait" or s.status == "todo") and
			(key or X.SellChoice(s.key) == false) then
			table.remove(R.steps, i)
		end
	end
end
-- nothing left to do: the round is over
local function checkDone()
	if R.state ~= "on" or R.phase ~= "ready" or R.cur then return end
	for _, s in ipairs(R.steps) do
		if s.status == "todo" or s.status == "wait" or s.status == "sent" then return end
	end
	R.state = "done"
	R.text = doneText()
end
-- its price is known: the item's steps wait for a press when it is ticked (worth posting at that price, or ticked by
-- you); else they are left out
local function priced(key)
	local row
	for _, r in ipairs(X.SellItems()) do if r.key == key then row = r break end end
	if row and X.SellTicked(key, row) then
		for _, s in ipairs(R.steps) do
			if s.kind == "post" and s.key == key and s.status == "wait" then s.status = "todo" end
		end
	else
		removeSteps(key)
	end
end
-- the price of each item to post: searched one by one (about one a second, never while a scan runs; Buy.lua's queue)
local function searchPrices(keys)
	local token = R.token
	for _, key in ipairs(keys) do
		if X.LiveLowest(key, 600) then priced(key)
		else
			R.waiting = R.waiting + 1
			X.LiveSearch(key, function()
				if R.token ~= token then return end
				priced(key) -- no answer: the price comes from the last scan (X.PostPrice says so)
				R.waiting = R.waiting - 1
				if R.waiting <= 0 and R.phase == "posts" then R.phase = "ready" end
				checkDone()
				changed()
			end)
		end
	end
	if R.waiting <= 0 and R.phase == "posts" then R.phase = "ready" end
	checkDone()
	changed()
end
local function startPosts()
	R.phase = "posts"
	local keys, seen = {}, {}
	for _, s in ipairs(R.steps) do
		if s.kind == "post" and s.status == "wait" and not seen[s.key] then
			seen[s.key] = true
			keys[#keys + 1] = s.key
		end
	end
	searchPrices(keys)
end
-- cancel steps for undercut auctions that have none yet (cancels before posts); -> how many were added
local function addCancelSteps(rows)
	local have = {}
	for _, s in ipairs(R.steps) do if s.kind == "cancel" then have[s.auctionID] = true end end
	local list = {}
	for _, row in ipairs(rows) do
		if not have[row.auctionID] then
			list[#list + 1] = {kind = "cancel", key = row.key, auctionID = row.auctionID, qty = row.qty, unit = row.unit,
				lowest = row.lowest, status = "todo"}
		end
	end
	for i = #list, 1, -1 do table.insert(R.steps, 1, list[i]) end
	return #list
end
-- your undercut auctions first (Post.lua's cancel scan: a fresh result is used, a check going on is waited for), then
-- the prices
local function startCancel()
	if not X.S().routineCancel then startPosts() return end
	R.phase = "cancel"
	local c = X.cancel
	if c.state == "asking" or c.state == "checking" then changed() return end
	if c.state == "done" and c.at and GetTime() - c.at < (X.CANCEL_EVERY or 300) then
		addCancelSteps(c.rows)
		startPosts()
		return
	end
	if not X.CancelScan() then
		R.note = "Could not ask for your auctions."
		startPosts()
	end
	changed()
end
local function prepare()
	if R.state == "on" and R.phase == "scan" and X.scan.state == "idle" and X.ahOpen then startCancel() end
end
X.On("XNAH_SCAN", prepare)
X.On("XNAH_CANCEL", function()
	if R.state == "off" then return end
	local c = X.cancel
	if R.phase == "cancel" then
		if c.state == "done" then
			addCancelSteps(c.rows)
			startPosts()
		elseif c.state == "idle" then
			R.note = "Could not check your auctions: " .. (c.text or "no answer")
			startPosts()
		end
	elseif c.state == "done" and X.S().routineCancel and (R.phase == "posts" or R.phase == "ready") then
		-- a later check found more undercut auctions
		if addCancelSteps(c.rows) > 0 then
			if R.state == "done" then R.state, R.text = "on", nil end
			changed()
		end
	end
end)
-- ticks changed, or new things in your bags: the steps follow at once
local function sync(only)
	if R.state == "off" or (R.phase ~= "posts" and R.phase ~= "ready") then return end
	removeSteps(nil)
	local added = addPostSteps(X.SellItems(), only)
	if #added > 0 then
		if R.state == "done" then R.state, R.text, R.phase = "on", nil, "ready" end
		searchPrices(added)
		return
	end
	checkDone()
	changed()
end
X.On("XNAH_SELLTICK", function(key)
	if R.state == "off" then return end
	if key then R.looked[key] = nil end
	sync(key)
end)
X.On("BAG_UPDATE_DELAYED", function() X.Debounce("xnah-routine-bags", 0.5, function() sync() end) end)

function X.RoutineStart()
	if not X.ahOpen then return false end
	reset("on")
	addPostSteps(X.SellItems())
	R.phase = "scan"
	R.text = nil
	prepare()
	changed()
	return true
end
function X.RoutineAuto()
	if X.ahOpen and R.state == "off" and not R.userStopped then return X.RoutineStart() end
	return false
end
function X.RoutineStop()
	if R.cur and X.post.state == "warning" then X.PostCancelWarning() end
	reset("off")
	R.text = "Stopped."
	R.userStopped = true
	changed()
end

-- [[ one step ]]
local function cancelRow(id)
	for _, r in ipairs(X.cancel.rows) do if r.auctionID == id then return r end end
	return nil
end
local function bagRow(key, rows)
	for _, r in ipairs(rows) do if r.key == key then return r end end
	return nil
end
local function money() return GetMoney and GetMoney() or 0 end
-- can this step be done now? the auction's row, or nil and why not (that step is skipped)
local function checkCancel(s)
	local row = cancelRow(s.auctionID)
	if not row then return nil, "already gone (sold, expired or cancelled)" end
	if row.cancelling then return nil, "already being cancelled" end
	if row.cost and money() < row.cost then return nil, "not enough money to cancel it" end
	return row
end
-- {row, qty, unit, duration}, or nil and why not
local function checkPost(s, rows)
	local row = bagRow(s.key, rows)
	if not row then return nil, "not in your bags any more" end
	local unit, why = X.PostPrice(s.key)
	if not unit then return nil, why or "no price known" end
	local n = postable(row)
	if n <= 0 then return nil, "kept for your crafting queue" end
	local qty = row.commodity and n or 1
	local duration = X.PostRule(s.key).duration
	local deposit = X.PostDeposit(row, duration, qty)
	if deposit and money() < deposit then return nil, "not enough money for the deposit" end
	return {row = row, qty = qty, unit = unit, duration = duration, why = why}
end
local function skip(s, why)
	s.status, s.why = "skipped", why
	R.counts.skipped = R.counts.skipped + 1
	if R.cur == s then R.cur = nil end
	X.Print("skipped " .. X.ItemText(s.key) .. ": " .. (why or "?"))
end

-- what the next press does; apply = true marks the steps that cannot be done as skipped on the way
local function nextAction(apply)
	if not X.ahOpen then return {what = "closed", text = "Open the auction house first"} end
	if R.state == "done" then return {what = "done", text = R.text or doneText()} end
	if R.state ~= "on" then return {what = "start", text = "Start: check your auctions and your bags"} end
	local s = R.cur
	if s then
		if s.kind == "post" and X.post.state == "warning" and X.post.key == s.key then
			return {what = "confirm", step = s, text = "Next: confirm the post of " .. X.Num(s.qty or 1) .. " x " .. nameOf(s.key) ..
				" (the auction house warns about the price)"}
		end
		return {what = "busy", text = "Waiting for the auction house ..."}
	end
	if X.post.state ~= "idle" then return {what = "busy", text = "Waiting: a post is still going on"} end
	if R.phase == "scan" then return {what = "wait", text = "Waiting for the scan to finish"} end
	if R.phase == "cancel" then return {what = "wait", text = "Waiting: checking your auctions ..."} end
	local rows
	local waiting = 0
	for _, st in ipairs(R.steps) do
		if st.status == "todo" then
			if st.kind == "cancel" then
				-- your auctions are being checked again right now: their list comes back in a moment
				local cs = X.cancel.state
				if cs == "asking" or cs == "checking" then return {what = "wait", text = "Waiting: checking your auctions ..."} end
				local row, why = checkCancel(st)
				if row then
					local by = (st.unit and st.lowest) and (" (undercut by " .. X.MoneyPlain(st.unit - st.lowest) .. ")") or ""
					return {what = "cancel", step = st, row = row, text = "Next: cancel " .. nameOf(st.key) .. " x" .. X.Num(st.qty or 1) .. by}
				end
				if apply then skip(st, why) end
			else
				rows = rows or X.SellItems()
				local p, why = checkPost(st, rows)
				if p then
					return {what = "post", step = st, post = p, text = "Next: post " .. X.Num(p.qty) .. " x " .. nameOf(st.key) ..
						" at " .. X.MoneyPlain(p.unit) .. (p.qty > 1 and " each" or "")}
				end
				if apply then skip(st, why) end
			end
		elseif st.status == "wait" then
			waiting = waiting + 1
		end
	end
	if waiting > 0 then return {what = "wait", text = "Waiting for prices (" .. waiting .. " left)"} end
	return {what = "finish", text = doneText()}
end
function X.RoutinePeek()
	return nextAction(false)
end

-- the step waits for the auction house's answer; no answer in 15 s: skipped (a price warning waits for you instead)
local function arm(s)
	local token = {}
	R.curToken = token
	X.After(15, function()
		if R.cur ~= s or R.curToken ~= token then return end
		if s.kind == "post" and X.post.state == "warning" then return end
		R.cur = nil
		skip(s, "no answer from the auction house")
		if s.kind == "post" and X.post.state ~= "idle" then X.PostForget("No answer from the auction house - check your auctions.") end
		checkDone()
		changed()
	end)
end
local function sent(s)
	s.status = "sent"
	R.cur = s
	arm(s)
end
local function finished(s, what)
	s.status = "done"
	R.counts[what] = R.counts[what] + 1
	if R.cur == s then R.cur = nil end
	checkDone()
	changed()
end
local function failed(s, why)
	if R.cur ~= s then return end
	R.cur = nil
	skip(s, why)
	checkDone()
	changed()
end

-- ONE step: at most one posting / cancelling call. Call it only straight from a click or a key press.
function X.RoutineNext(src)
	if not X.ahOpen then
		tell(src, "the one-key routine works only while the auction house is open")
		return false
	end
	if R.state ~= "on" then
		local again = R.state == "done"
		X.RoutineStart()
		tell(src, (again and "new round: " or "one-key routine: ") .. "checking your auctions and prices - press again in a moment")
		return false
	end
	prepare()
	local a = nextAction(true)
	local s = a.step
	if a.what == "confirm" then
		if X.PostConfirmClick() then
			arm(s)
			changed()
			return true
		end
	elseif a.what == "cancel" then
		if X.CancelClick(a.row) then
			sent(s)
			changed()
			return true
		end
		skip(s, "could not cancel it")
	elseif a.what == "post" then
		local p = a.post
		local blocked = X.PostBlocked(p.row, p.unit, p.qty)
		if blocked then
			-- busy for a moment: the step stays, the next press tries again
			tell(src, blocked)
			changed()
			return false
		end
		if X.PostClick(p.row, p.unit, p.qty, p.duration) then
			s.qty, s.unit = p.qty, p.unit
			sent(s)
			changed()
			return true
		end
		skip(s, X.post.text or "could not post it")
	elseif a.what == "finish" then
		R.phase = "ready"
		checkDone()
		tell(src, R.text)
	else
		tell(src, a.text)
	end
	changed()
	return false
end

-- skip the next step (not restricted)
function X.RoutineSkip()
	local s = R.cur
	if s then
		if s.kind == "post" and X.post.state == "warning" then
			R.cur = nil
			skip(s, "you said no to the price warning")
			X.PostCancelWarning()
			checkDone()
			changed()
		end
		return
	end
	local a = nextAction(false)
	if a.step then
		skip(a.step, "skipped by you")
		checkDone()
		changed()
	end
end

-- [[ answers of the auction house ]]
X.On("XNAH_POSTED", function(key)
	local s = R.cur
	if s and s.kind == "post" and s.key == key then finished(s, "posted") end
end)
-- the post ended without an auction (an error, "Don't post", no answer)
X.On("XNAH_POST", function()
	local s = R.cur
	if s and s.kind == "post" and X.post.state == "idle" then failed(s, X.post.text or "not posted") end
end)
X.On("AUCTION_CANCELED", function(auctionID)
	local s = R.cur
	if s and s.kind == "cancel" and s.auctionID == auctionID then finished(s, "cancelled") end
end)
X.On("AUCTION_HOUSE_SHOW_ERROR", function()
	local s = R.cur
	if s and s.kind == "cancel" then failed(s, "the auction house did not cancel it") end
end)
X.On("AUCTION_HOUSE_CLOSED", function()
	if R.state == "on" then
		local c = R.counts
		reset("off")
		R.counts = c
		R.text = "Stopped: the auction house was closed."
	end
	changed()
end)
-- (its key binding, XNAH_NEXT, is now the Next step key of Next.lua: at the auction house it does these steps)
