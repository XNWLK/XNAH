// Dry run of a login with a real saved data file, outside the game: loads the file into the stand-in world, logs in
// with the current addon (as the game would, optionally without a realm ID at first) and reports what XNAH sees and
// which realm keys are left. Never writes to the given file.
//   node tools/dryrun-login.js "<path to WTF\Account\...\SavedVariables\XNAH.lua>" [realmID]
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const FENGARI = path.join(ROOT, '..', 'warlock-sim-addon', 'tools', 'node_modules', 'fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);
const file = process.argv[2];
const realmID = Number(process.argv[3] || 0);
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
const report = run(`
  W.reset()
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
  return table.concat(out, "\\n")
`, '=dryrun');
console.log(report);
