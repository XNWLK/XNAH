-- Merges the XNAH saved data of several WoW accounts (run by tools/sync-accounts.js through fengari; never part of the
-- addon). Each account keeps its own characters, mailbox ledger and settings; it gets a copy of:
--   - the characters of the other accounts (XNAHDB.chars[name] with acct = that account's label) and their net worth
--     history, so the Wealth page shows every character;
--   - the ledger entries (sales, purchases, expired, cancelled) of those characters;
--   - prices: per item the newest observation of any account (a scan on one account helps all), vendor prices,
--     recipes and which characters know them.
-- In:  ACCTS = {{label = "wow1", db = XNAHDB table or nil}, ...}, NOW = seconds
-- Out: SYNC.out[i] = text of the new XNAH.lua of ACCTS[i]; SYNC.report = lines
SYNC = {out = {}, report = {}}
local function say(s) SYNC.report[#SYNC.report + 1] = s end

local function copy(t)
	if type(t) ~= "table" then return t end
	local o = {}
	for k, v in pairs(t) do o[k] = copy(v) end
	return o
end

-- [[ who owns which character ]] a character without acct (or acct = this label) was written by this account
local owner = {} -- [char] = {label, rec, worth}
for _, a in ipairs(ACCTS) do
	local db = a.db
	if db and db.chars then
		for name, c in pairs(db.chars) do
			if not c.acct or c.acct == a.label then
				local prev = owner[name]
				if not prev or (c.at or 0) > (prev.rec.at or 0) then
					owner[name] = {label = a.label, rec = c, worth = db.worth and db.worth[name]}
				end
			end
		end
	end
end

-- [[ prices: newest per item, per realm ]]
local realms = {} -- [rk] = {items = {[key] = item}, lastFull}
local vsell, vbuy, recipes, known = {}, {}, {}, {}
local function curT(it) return it and it.cur and it.cur.t or 0 end
for _, a in ipairs(ACCTS) do
	local db = a.db
	if db then
		for rk, r in pairs(db.realms or {}) do
			local m = realms[rk] or {items = {}}
			realms[rk] = m
			for key, it in pairs(r.items or {}) do
				local have = m.items[key]
				if not have or curT(it) > curT(have) then m.items[key] = it end
			end
			if r.lastFull and (not m.lastFull or r.lastFull > m.lastFull) then m.lastFull = r.lastFull end
		end
		for id, v in pairs(db.vsell or {}) do vsell[id] = v end
		for id, v in pairs(db.vbuy or {}) do
			if not vbuy[id] or (v.at or 0) > (vbuy[id].at or 0) then vbuy[id] = v end
		end
		for rid, rec in pairs(db.recipes or {}) do
			if not recipes[rid] or (rec.at or 0) > (recipes[rid].at or 0) then recipes[rid] = rec end
		end
		for char, list in pairs(db.known or {}) do
			known[char] = known[char] or {}
			for rid, v in pairs(list) do known[char][rid] = v end
		end
	end
end

-- [[ ledger entries of each account's own characters ]]
local KINDS = {"sales", "buys", "expired", "cancelled"}
local function ownedBy(char, label)
	local o = char and owner[char]
	return o and o.label == label
end

-- [[ build each account's new data ]]
local labels = {}
for _, a in ipairs(ACCTS) do labels[#labels + 1] = a.label end
for i, a in ipairs(ACCTS) do
	local db = a.db and copy(a.db) or {v = 1}
	db.chars = db.chars or {}
	db.worth = db.worth or {}
	-- characters: own ones stay, the others' come in fresh (and ones no longer owned anywhere are dropped)
	local imported = 0
	for name, c in pairs(db.chars) do
		if c.acct and c.acct ~= a.label then db.chars[name] = nil db.worth[name] = nil end
	end
	for name, o in pairs(owner) do
		if o.label ~= a.label then
			local c = copy(o.rec)
			c.acct = o.label
			db.chars[name] = c
			db.worth[name] = o.worth
			imported = imported + 1
		end
	end
	-- prices
	db.realms = db.realms or {}
	local prices = 0
	for rk, m in pairs(realms) do
		local r = db.realms[rk] or {items = {}, scans = {}}
		db.realms[rk] = r
		r.items = r.items or {}
		for key, it in pairs(m.items) do
			if curT(it) > curT(r.items[key]) then r.items[key] = copy(it) prices = prices + 1 end
		end
		if m.lastFull and (not r.lastFull or m.lastFull > r.lastFull) then r.lastFull = m.lastFull end
	end
	db.vsell, db.vbuy, db.recipes, db.known = copy(vsell), copy(vbuy), copy(recipes), copy(known)
	-- ledger: this account's own entries + the other accounts' own entries
	local moved = 0
	for rk, r in pairs(db.realms) do
		r.ledger = r.ledger or {}
		for _, kind in ipairs(KINDS) do
			local list = {}
			for _, e in ipairs(r.ledger[kind] or {}) do
				if not e.char or ownedBy(e.char, a.label) or not owner[e.char] then list[#list + 1] = e end
			end
			for _, b in ipairs(ACCTS) do
				if b ~= a and b.db and b.db.realms and b.db.realms[rk] and b.db.realms[rk].ledger then
					for _, e in ipairs(b.db.realms[rk].ledger[kind] or {}) do
						if e.char and ownedBy(e.char, b.label) then list[#list + 1] = copy(e) moved = moved + 1 end
					end
				end
			end
			table.sort(list, function(x, y) return (x.t or 0) < (y.t or 0) end)
			r.ledger[kind] = list
		end
	end
	db.sync = {at = NOW, label = a.label, accounts = labels}
	say(a.label .. ": " .. imported .. " characters from other accounts, " .. prices .. " newer prices, " .. moved ..
		" ledger entries of other accounts")
	SYNC.out[i] = db
end

-- [[ writing ]] the same form the game writes
local function key(k)
	if type(k) == "number" then return "[" .. string.format("%.14g", k) .. "]" end
	return "[" .. string.format("%q", k) .. "]"
end
local function value(v, indent, out)
	local t = type(v)
	if t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(x, y)
			if type(x) ~= type(y) then return type(x) == "number" end
			return x < y
		end)
		out[#out + 1] = "{\n"
		for _, k in ipairs(keys) do
			out[#out + 1] = indent .. "\t" .. key(k) .. " = "
			value(v[k], indent .. "\t", out)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	elseif t == "string" then out[#out + 1] = string.format("%q", v):gsub("\\\n", "\\n")
	elseif t == "number" then
		if v ~= v then out[#out + 1] = "0" -- not a number: written as 0
		elseif v == math.huge then out[#out + 1] = "1e309"
		elseif v == -math.huge then out[#out + 1] = "-1e309"
		elseif v == math.floor(v) and math.abs(v) < 1e15 then out[#out + 1] = string.format("%.0f", v)
		else out[#out + 1] = string.format("%.14g", v) end
	elseif t == "boolean" then out[#out + 1] = tostring(v)
	else out[#out + 1] = "nil" end
end
for i, db in ipairs(SYNC.out) do
	local out = {"\nXNAHDB = "}
	value(db, "", out)
	out[#out + 1] = "\n"
	SYNC.out[i] = table.concat(out)
end
