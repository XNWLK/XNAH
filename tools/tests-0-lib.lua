-- XNAH test scenes: the small test kit (checks, scenes, the report). Run by tools/test.js inside tools/world.lua.
T = {results = {}, pass = 0, fail = 0, notes = {}, times = {}}

local function show(v)
	if type(v) == "table" then
		local parts = {}
		for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end
T.show = show

function T.check(title, got, expect)
	if got == expect then T.pass = T.pass + 1
	else
		T.fail = T.fail + 1
		T.results[#T.results + 1] = "FAIL " .. (T.current and (T.current .. " / ") or "") .. title .. "\n  expected: " .. show(expect) .. "\n  got:      " .. show(got)
	end
end
function T.ok(title, cond, detail)
	if cond then T.pass = T.pass + 1
	else
		T.fail = T.fail + 1
		T.results[#T.results + 1] = "FAIL " .. (T.current and (T.current .. " / ") or "") .. title .. (detail ~= nil and ("\n  " .. show(detail)) or "")
	end
end
-- numbers within `tol` (default 0.5)
function T.near(title, got, expect, tol)
	T.ok(title, type(got) == "number" and type(expect) == "number" and math.abs(got - expect) <= (tol or 0.5),
		"expected about " .. tostring(expect) .. ", got " .. tostring(got))
end
-- a number the report prints (sizes, timings)
function T.note(text) T.notes[#T.notes + 1] = "  " .. text end

-- a scene: errors thrown, Lua errors caught by the world and error lines printed in chat all fail it
function T.scene(title, fn)
	if FILTER ~= "" and not title:lower():find(FILTER:lower(), 1, true) then return end
	T.current = title
	W.errors = W.errors or {}
	local started = os.clock()
	local ok, e = xpcall(fn, function(m) return debug.traceback(m, 2) end)
	T.times[#T.times + 1] = string.format("%6.1fs  %s", os.clock() - started, title)
	if SHOW_TIMES == "live" then print(T.times[#T.times]) end
	if not ok then T.fail = T.fail + 1 T.results[#T.results + 1] = "FAIL " .. title .. ": " .. tostring(e) end
	if HOSTUP then HOSTUP.walk() end
	if W.errors and #W.errors > 0 then
		T.fail = T.fail + 1
		local lines = {}
		for i = 1, math.min(#W.errors, 6) do lines[#lines + 1] = "  " .. W.errors[i] end
		T.results[#T.results + 1] = "FAIL " .. title .. ": Lua errors (" .. #W.errors .. ")\n" .. table.concat(lines, "\n")
	end
	local bad = {}
	for _, l in ipairs(W.chat or {}) do
		local p = W.plain(l)
		if p:lower():find("error", 1, true) and not T.allowErrorText then bad[#bad + 1] = "  " .. p end
	end
	if #bad > 0 then
		T.fail = T.fail + 1
		T.results[#T.results + 1] = "FAIL " .. title .. ": errors printed in chat\n" .. table.concat(bad, "\n", 1, math.min(#bad, 6))
	end
	T.allowErrorText = nil
	T.current = nil
	W.errors = {}
	W.chat = {}
end

function T.report()
	local out = table.concat(T.results, "\n")
	if SHOW_TIMES ~= "" then out = table.concat(T.times, "\n") .. "\n" .. out end
	return (out ~= "" and out .. "\n" or "") .. (T.fail == 0 and "OK" or "FAIL") .. ": " .. T.pass .. " checks passed, " .. T.fail .. " failed"
end

-- [[ shortcuts for scenes ]]
-- runs a full scan to the end (the auction house must be open); returns true when it finished
function T.fullScan(X, force)
	if not X.FullScan(force) then return false end
	return W.waitFor(function() return X.scan.state == "idle" end, 300)
end
-- items of the realm, counted
function T.count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
-- the distinct item keys listed on the auction house right now
function T.ahKeys()
	local set = {}
	for _, a in ipairs(W.ah) do if a.buyout and a.buyout > 0 then set[W.keyStr(a.itemID, a.suffix)] = true end end
	return set
end
-- lowest price of one of an item on the auction house right now
function T.ahMin(id, suffix)
	local best
	for _, a in ipairs(W.ah) do
		if a.itemID == id and (a.suffix or 0) == (suffix or 0) then
			local u = W.unitOf(a)
			if u and (not best or u < best) then best = u end
		end
	end
	return best
end
