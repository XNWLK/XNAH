// Dry run of a login with a real saved data file, outside the game: loads the file into the stand-in world, logs in
// with the current addon (as the game would, optionally without a realm ID at first) and reports what XNAH sees and
// which realm keys are left. Never writes to the given file (it is only read).
//   node tools/dryrun-login.js "<path to WTF\Account\...\SavedVariables\XNAH.lua>" [realmID] [--pages]
// --pages: the clock is set to now, then every view and every page is opened (the Trends pages, the pages of the
// tracked item with the most history, the Your gold pages) and its work run to the end; reports errors, how long each
// page took to fill (CPU seconds of this stand-in, slower than the game), the slowest single step (one timer or one
// frame of a script: the game stutters when that is long) and the size of the saved data before and after.
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const FENGARI = path.join(ROOT, '..', 'warlock-sim-addon', 'tools', 'node_modules', 'fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);
const file = process.argv[2];
const realmID = Number(process.argv.slice(3).find(a => /^\d+$/.test(a)) || 0);
const PAGES = process.argv.includes('--pages');
if (!file || !fs.existsSync(file)) { console.log('give the path of an XNAH.lua saved data file'); process.exit(1); }
const toc = fs.readFileSync(path.join(ROOT, 'XNAH', 'XNAH.toc'), 'utf8');
const files = toc.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith('#') && l.endsWith('.lua'));
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    const msg = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); throw new Error(msg);
  }
  const v = lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tolstring(L, -1)); lua.lua_pop(L, 1); return v;
}
function setString(name, value) { lua.lua_pushstring(L, to_luastring(value)); lua.lua_setglobal(L, to_luastring(name)); }
run(fs.readFileSync(path.join(__dirname, 'world.lua'), 'utf8'), '@world.lua');
for (const f of fs.readdirSync(__dirname).filter(f => /^world-.*.lua$/.test(f)).sort()) run(fs.readFileSync(path.join(__dirname, f), 'utf8'), '@' + f);
for (const f of files) {
  const p = path.join(ROOT, 'XNAH', f);
  setString('__src', fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '');
  run(`W.source(${JSON.stringify(f)}, __src)`, '=src');
}
run(`W.addonFiles({${files.map(f => JSON.stringify(f)).join(',')}})`, '=files');
setString('__saved', fs.readFileSync(file, 'latin1'));
setString('__pages', PAGES ? '1' : '');
const report = run(`
  W.reset()
  if __pages ~= "" then W.START = os.time() end -- the clock at now (the saved prices are from the last days)
  W.realmID, W.realm = ${realmID}, ""
  local X = W.login(__saved)
  W.advance(10)
  local out = {}
  out[#out + 1] = "realm key after login: " .. tostring(X.realmKey) .. "  (remembered: " .. tostring(X.db.lastRealm) .. ")"
  local keys = {}
  for k in pairs(X.db.realms) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local r, n, deep, pts = X.db.realms[k], 0, 0, 0
    local first
    for key, it in pairs(r.items or {}) do
      n = n + 1
      local h = X.History(key and key, 0, true)
      if k == X.realmKey then
        local c = 0
        for p in (it.d or ""):gmatch("[^;]+") do c = c + 1 local d = X.n36(p:match("^([^,]*)")) if d and (not first or d < first) then first = d end end
        pts = pts + c
        if c >= 3 then deep = deep + 1 end
      end
    end
    out[#out + 1] = string.format("  %-24s %6d items%s", "'" .. k .. "'", n,
      k == X.realmKey and string.format(", %d day points, %d items with 3+ days, history from %s, %d scans listed, %d sales",
        pts, deep, first and os.date("!%Y-%m-%d", first * 86400) or "-", #(r.scans or {}), r.ledger and r.ledger.sales and #r.ledger.sales or 0) or "")
  end
  for _, l in ipairs(W.chat or {}) do if tostring(l):find("joined") then out[#out + 1] = "chat: " .. tostring(l):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end end
  if __pages ~= "" then
    local before, atLogin = #__saved, #W.saveText(W.env.XNAHDB)
    -- the slowest single step of each sliced job (by its name)
    local jobMax = {}
    local job = X.Job
    X.Job = function(name, stepFn, finish)
      return job(name, function(...)
        local t0 = os.clock()
        local r = stepFn(...)
        local dt = os.clock() - t0
        if dt > (jobMax[name] or 0) then jobMax[name] = dt end
        return r
      end, finish)
    end
    -- runs fn, then frames until no sliced work is left (at most 10 minutes of game time); returns cpu seconds, the
    -- slowest step (seconds) and where, and the errors
    local function fill(label, fn)
      W.errors = {}
      local chatFrom = #W.chat
      W.maxStepTime, W.maxStepWhere = 0, "-"
      local t0 = os.clock()
      local ok, e = pcall(fn)
      if not ok then W.err(e) end
      local waited = 0
      repeat
        W.advance(0.05)
        waited = waited + 0.05
      until (X.JobList() == "nothing" and waited >= 0.5) or waited > 600
      local secs = os.clock() - t0
      out[#out + 1] = string.format("  %-34s %6.2f s   slowest step %5.0f ms (%s)%s%s", label, secs, W.maxStepTime * 1000,
        tostring(W.maxStepWhere), waited > 600 and "  STILL WORKING after 10 min" or "",
        #W.errors > 0 and ("  ERRORS: " .. #W.errors) or "")
      for i = 1, math.min(#W.errors, 3) do out[#out + 1] = "      " .. tostring(W.errors[i]):sub(1, 400) end
      -- errors XNAH caught and printed in chat (X.OnError) while this step ran
      for i = chatFrom + 1, #W.chat do
        local l = W.plain(W.chat[i])
        if l:lower():find("error", 1, true) then out[#out + 1] = "      chat: " .. l:sub(1, 400) end
      end
      local names = {}
      for name, dt in pairs(jobMax) do if dt > 0.05 then names[#names + 1] = string.format("%s %.0f ms", name, dt * 1000) end end
      table.sort(names)
      if #names > 0 then out[#out + 1] = "      slowest slice of each job: " .. table.concat(names, ", ") end
      jobMax = {}
      return secs
    end
    out[#out + 1] = ""
    out[#out + 1] = "pages (the clock at " .. os.date("!%Y-%m-%d %H:%M", X.Now()) .. " UTC):"
    local UI = X.UI
    for _, v in ipairs({"items", "market", "gold", "trends", "scan"}) do
      fill("view " .. v, function() UI.Open(v) end)
    end
    local trendsTotal = 0
    for _, pg in ipairs(UI.TRENDS_PAGES) do
      UI.Open("trends")
      local panel = UI.tabs.trends.panel
      trendsTotal = trendsTotal + fill("trends: " .. pg.title, function() W.click(pg.title, panel) end)
    end
    out[#out + 1] = string.format("  %-34s %6.2f s", "trends: all four pages", trendsTotal)
    -- the tracked item with the most day points (else any item with the most)
    local best, bestN
    for key, it in pairs(X.Items()) do
      local n = 0
      for _ in (it.d or ""):gmatch("[^;]+") do n = n + 1 end
      if X.Watched(key) then n = n + 100000 end
      if not bestN or n > bestN then best, bestN = key, n end
    end
    if best then
      out[#out + 1] = "  item: " .. tostring(X.ItemName(best)) .. " (" .. best .. ")"
      fill("items: show it", function() UI.ShowItem(best) end)
      local panel = UI.tabs.items.panel
      for _, pg in ipairs(UI.ITEM_PAGES) do
        fill("items: " .. pg.title, function() W.click(pg.title, panel) end)
      end
    end
    UI.Open("gold")
    local g = UI.tabs.gold.panel
    for _, pg in ipairs(UI.GOLD_PAGES) do
      fill("gold: " .. pg.title, function() W.click(pg.title, g) end)
    end
    local after = #W.saveText(W.env.XNAHDB)
    out[#out + 1] = string.format("saved data: %d bytes in the file, %d written out right after the login (%+d), %d after " ..
      "every page (%+d more)", before, atLogin, atLogin - before, after, after - atLogin)
    local items, bytes = X.DataSize()
    out[#out + 1] = string.format("X.DataSize: %d items, about %d bytes of history", items, bytes)
    -- the Your data window: data health, every export (all days), then a slim down - in memory only (this tool never
    -- writes the file)
    out[#out + 1] = ""
    out[#out + 1] = "your data:"
    fill("data: open the window (health)", function() UI.OpenData() end)
    local res = X.DataHealth()
    if res then
      out[#out + 1] = string.format("  health: %d items, about %d bytes in all (the file has %d)", res.items, res.total, before)
      for _, p in ipairs(res.parts) do
        if p.bytes > 0 then out[#out + 1] = string.format("    %-40s %10d bytes", p.name, p.bytes) end
      end
      local bits = {}
      for _, d in ipairs(X.UNSEEN_DAYS) do bits[#bits + 1] = d .. " days " .. res.unseen[d] end
      out[#out + 1] = "  not seen for: " .. table.concat(bits, ", ") .. "; never seen with a price " .. res.never
      bits = {}
      for _, d in ipairs(X.SLIM_DAYS) do
        local s = res.slim[d]
        bits[#bits + 1] = string.format("%d days %d items %d KB (%d kept)", d, s.n, math.floor(s.bytes / 1024), s.kept)
      end
      out[#out + 1] = "  slim down would remove: " .. table.concat(bits, "; ")
    end
    for _, e in ipairs(X.EXPORTS) do
      local got
      fill("data: export " .. e.title, function()
        X.Export(e.key, {key = best, days = 0}, function(r) got = r end)
      end)
      if got then
        out[#out + 1] = string.format("      %d of %d rows, %d characters%s", got.rows, got.total, got.bytes, got.cut and " (cut)" or "")
      end
    end
    local slim
    fill("data: slim down 180 days", function() X.DataSlim(180, function(B) slim = B end) end)
    if slim then
      local after2 = #W.saveText(W.env.XNAHDB)
      out[#out + 1] = string.format("      removed %d items (about %d bytes); written out now %d bytes (%+d)", slim.removed,
        slim.bytes, after2, after2 - after)
    end
  end
  return table.concat(out, "\\n")
`, '=dryrun');
console.log(report);
