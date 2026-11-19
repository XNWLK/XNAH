-- The one-key routine: each press of one key (or of the big "Next step" button on the Sell tab) does the next step:
-- first cancel your auctions that someone undercut, then post the items of your sell list that are in your bags, at
-- XNAH's price, one after the other. The game allows posting and cancelling only on a click or a key press, one action
-- each, so this is as automatic as it is allowed to be. Everything that is NOT restricted (asking for your auctions,
-- searching prices about one a second) runs in the background as soon as the routine starts, so each press can act at
-- once. It never buys anything.
--   X.RoutineStart()    start a round (not restricted; the first press does this)
--   X.RoutineNext(src)  ONE step. Call it only straight from a click or a key press (src "key" = the key binding).
--   X.RoutinePeek()     what the next press will do: {what, text, step} (what = closed / start / done / busy / wait /
--                       cancel / post / confirm)
--   X.RoutineSkip()     skip the next step (or say no to a price warning)
--   X.RoutineStop()     stop the round
--   X.RoutineProgress() -> finished steps, all steps
--   X.routine = {state = off / on / done, phase = scan / cancel / posts / ready, steps, cur (the step waiting for the
--     auction house's answer), counts = {cancelled, posted, skipped}, text}
--   step = {kind = cancel / post, key, qty, unit, lowest, auctionID, status = wait / todo / sent / done / skipped, why}
local ADDON, X = ...

X.Default("routineCancel", true)

local R
local function reset(state)
	R = {state = state or "off", steps = {}, counts = {cancelled = 0, posted = 0, skipped = 0}, token = {}}
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
-- post steps: stackable items in one auction (all of them), other items one auction per piece
local function addPostSteps()
	for _, row in ipairs(X.SellItems()) do
		if X.OnSellList(row.key) then
			for _ = 1, row.commodity and 1 or row.have do
				R.steps[#R.steps + 1] = {kind = "post", key = row.key, qty = row.commodity and row.have or 1, status = "wait"}
			end
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
-- the price of each item to post: searched one by one (about one a second, never while a scan runs; Buy.lua's queue)
local function searchPrices()
	R.phase = "posts"
	local token = R.token
	local keys, seen = {}, {}
	for _, s in ipairs(R.steps) do
		if s.kind == "post" and not seen[s.key] then
			seen[s.key] = true
			keys[#keys + 1] = s.key
		end
	end
	local function ready(key)
		for _, s in ipairs(R.steps) do
			if s.kind == "post" and s.key == key and s.status == "wait" then s.status = "todo" end
		end
	end
	local left = 0
	for _, key in ipairs(keys) do
		if X.LiveLowest(key, 600) then ready(key)
		else
			left = left + 1
			X.LiveSearch(key, function()
				if R.token ~= token then return end
				ready(key) -- no answer: the price comes from the last scan (X.PostPrice says so)
				left = left - 1
				if left <= 0 then R.phase = "ready" checkDone() end
				changed()
			end)
		end
	end
	if left == 0 then
		R.phase = "ready"
		checkDone()
	end
	changed()
end
-- your undercut auctions first (Post.lua's cancel scan), then the prices
local function startCancel()
	if not X.S().routineCancel then searchPrices() return end
	R.phase = "cancel"
	if not X.CancelScan() then
		R.note = "Could not ask for your auctions."
		searchPrices()
	end
	changed()
end
local function prepare()
	if R.state == "on" and R.phase == "scan" and X.scan.state == "idle" and X.ahOpen then startCancel() end
end
X.On("XNAH_SCAN", prepare)
X.On("XNAH_CANCEL", function()
	if R.state ~= "on" or R.phase ~= "cancel" then return end
	local c = X.cancel
	if c.state == "done" then
		local list = {}
		for _, row in ipairs(c.rows) do
			list[#list + 1] = {kind = "cancel", key = row.key, auctionID = row.auctionID, qty = row.qty, unit = row.unit,
				lowest = row.lowest, status = "todo"}
		end
		-- cancels before posts
		for i = #list, 1, -1 do table.insert(R.steps, 1, list[i]) end
		searchPrices()
	elseif c.state == "idle" then
		R.note = "Could not check your auctions: " .. (c.text or "no answer") .. ""
		searchPrices()
	end
end)

function X.RoutineStart()
	if not X.ahOpen then return false end
	reset("on")
	addPostSteps()
	R.phase = "scan"
	R.text = nil
	prepare()
	changed()
	return true
end
function X.RoutineStop()
	if R.cur and X.post.state == "warning" then X.PostCancelWarning() end
	reset("off")
	R.text = "Stopped."
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
	local qty = row.commodity and row.have or 1
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
	if R.state ~= "on" then return {what = "start", text = "Start: check your auctions and your sell list"} end
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

-- [[ the key binding ]] (Bindings.xml; the key is set in the game's key bindings, under AddOns)
BINDING_NAME_XNAH_NEXT = "One-key routine: next step"
function XNAH_Next()
	X.RoutineNext("key")
end
