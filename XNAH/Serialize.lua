-- Turns tables into text and back, for addon messages (guild price sharing). No code is ever run from received text:
-- the reader only understands numbers, strings, true / false and tables, and refuses anything else.
-- Format: n<number>;  s<length>:<bytes>  T / F (true / false)  t <key value ...> e
local ADDON, X = ...

local concat, type, pairs = table.concat, type, pairs

local function put(out, v, depth)
	local kind = type(v)
	if kind == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			out[#out + 1] = "n0;" -- not a real number: sent as 0
		elseif v == math.floor(v) and v > -1e15 and v < 1e15 then
			out[#out + 1] = "n" .. string.format("%d", v) .. ";"
		else
			out[#out + 1] = "n" .. (string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", "")) .. ";"
		end
	elseif kind == "string" then
		out[#out + 1] = "s" .. #v .. ":" .. v
	elseif kind == "boolean" then
		out[#out + 1] = v and "T" or "F"
	elseif kind == "table" then
		if depth > 20 then error("table too deep") end
		out[#out + 1] = "t"
		for k, val in pairs(v) do
			local kk = type(k)
			if (kk == "string" or kk == "number") and type(val) ~= "function" then
				put(out, k, depth + 1)
				put(out, val, depth + 1)
			end
		end
		out[#out + 1] = "e"
	else
		out[#out + 1] = "F" -- functions and the like: sent as false
	end
end

function X.Ser(v)
	local out = {}
	put(out, v, 0)
	return concat(out)
end

-- returns value, next position (or nil, error)
local function get(s, i, depth)
	local c = s:sub(i, i)
	if c == "n" then
		local j = s:find(";", i + 1, true)
		if not j or j - i > 30 then return nil, "bad number" end
		local n = tonumber(s:sub(i + 1, j - 1))
		if not n or n ~= n then return nil, "bad number" end
		return n, j + 1
	elseif c == "s" then
		local j = s:find(":", i + 1, true)
		if not j or j - i > 8 then return nil, "bad string" end
		local len = tonumber(s:sub(i + 1, j - 1))
		if not len or len < 0 or len ~= math.floor(len) or j + len > #s then return nil, "bad string" end
		return s:sub(j + 1, j + len), j + len + 1
	elseif c == "T" then
		return true, i + 1
	elseif c == "F" then
		return false, i + 1
	elseif c == "t" then
		if depth > 20 then return nil, "too deep" end
		local t = {}
		local pos = i + 1
		while true do
			if pos > #s then return nil, "unfinished table" end
			if s:sub(pos, pos) == "e" then return t, pos + 1 end
			local k, v
			k, pos = get(s, pos, depth + 1)
			if k == nil then return nil, pos end
			v, pos = get(s, pos, depth + 1)
			if v == nil then return nil, pos end
			if type(k) == "string" or type(k) == "number" then t[k] = v end
		end
	end
	return nil, "unknown type '" .. c .. "'"
end

function X.Deser(s)
	if type(s) ~= "string" or s == "" then return nil, "empty" end
	local ok, v, pos = pcall(get, s, 1, 0)
	if not ok then return nil, "unreadable" end
	if v == nil then return nil, pos end
	if pos ~= #s + 1 then return nil, "trailing data" end
	return v
end
