-- Stand-in world, part "next" (v0.8, the Next step key): a key press counts as a click for the mailbox too, and a
-- switch that makes taking mail outside a click or key press an error. Test tool only - never part of the addon.
--   W.mailNeedsPress   true: TakeInboxMoney / TakeInboxItem throw outside a click or key press (default false: the
--                      mailbox part lets the game's own "Open all" take mail on a timer)
--   W.pressCalls()     every restricted call so far: the auction house ones, crafts and mail takes, as one list of names

table.insert(W.onReset, function()
	W.mailNeedsPress = false
	-- W.pressKey (tools/world-routine.lua, loaded after this file): a key press is a hardware event for the mailbox too
	if W.pressKey and not W.nextPressWrapped then
		W.nextPressWrapped = true
		local base = W.pressKey
		W.pressKey = function(fnName)
			local prev = W.mailClicking
			W.mailClicking = true
			local ok, e = pcall(base, fnName)
			W.mailClicking = prev
			if not ok then error(e, 0) end
		end
	end
end)

table.insert(W.onEnv, function(env)
	for _, name in ipairs({"TakeInboxMoney", "TakeInboxItem"}) do
		local real = env[name]
		if real then
			env[name] = function(...)
				if W.mailNeedsPress and not (W.hardware or W.mailClicking) then
					error(name .. " was called outside a click or key press", 2)
				end
				return real(...)
			end
		end
	end
end)

function W.pressCalls()
	local out = {}
	for _, n in ipairs(W.restrictedCalls or {}) do out[#out + 1] = n end
	for _ = 1, #(W.crafted or {}) do out[#out + 1] = "CraftRecipe" end
	for _, t in ipairs(W.mailTakes or {}) do out[#out + 1] = t.what == "money" and "TakeInboxMoney" or "TakeInboxItem" end
	return out
end
