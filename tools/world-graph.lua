-- Stand-in world, graph part: the game's clock of the realm (GetGameTime: hour and minute of the server).
-- W.gameShift = seconds the realm's clock is ahead of UTC (default one hour); nil = GetGameTime is missing.
table.insert(W.onReset, function() W.gameShift = 3600 end)
table.insert(W.onEnv, function(env)
	env.GetGameTime = function()
		if not W.gameShift then error("GetGameTime is not there") end
		local t = os.date("!*t", env.GetServerTime() + W.gameShift)
		return t.hour, t.min
	end
end)
