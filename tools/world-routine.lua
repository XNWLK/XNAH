-- Stand-in world, part "routine": a press of a key binding (a hardware event, like a click: W.hardware is true only
-- during it), the key bound to it, and auction house answers that refuse a cancel or a post. Test tool only - never part
-- of the addon.

table.insert(W.onReset, function()
	W.bindings = {}          -- [binding name] = key, e.g. W.bindings.XNAH_NEXT = "F"
	W.cancelRefuse = false   -- true: every cancel is answered with AUCTION_HOUSE_SHOW_ERROR
	W.postErrorNext = false  -- true: the next post is answered with AUCTION_HOUSE_POST_ERROR
end)

-- the player presses the key of a binding: its function runs inside a hardware event
function W.pressKey(fnName)
	local was = W.hardware
	W.hardware = true
	local ok, e = pcall(W.env[fnName or "XNAH_Next"])
	W.hardware = was
	if not ok then error(e, 0) end
end

table.insert(W.onEnv, function(env)
	env.GetBindingKey = function(name) return W.bindings[name] end
	local AH = env.C_AuctionHouse
	local function restricted(name)
		W.restrictedCalls[#W.restrictedCalls + 1] = name
		if not W.hardware then error(name .. " was called outside a click or key press (the game needs a hardware event)", 3) end
	end
	local cancel = AH.CancelAuction
	AH.CancelAuction = function(id)
		if not W.cancelRefuse then return cancel(id) end
		restricted("CancelAuction")
		W.after(0.3, function() W.fire("AUCTION_HOUSE_SHOW_ERROR", 1) end)
	end
	local function failing(name, real)
		return function(...)
			if not W.postErrorNext then return real(...) end
			W.postErrorNext = false
			restricted(name)
			W.after(0.2, function() W.fire("AUCTION_HOUSE_POST_ERROR") end)
			return false
		end
	end
	AH.PostCommodity = failing("PostCommodity", AH.PostCommodity)
	AH.PostItem = failing("PostItem", AH.PostItem)
end)
