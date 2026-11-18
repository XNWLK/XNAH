// Plays XNAH outside the game: tools/world.lua is a stand-in for the WoW: Forever client with an auction house server
// (auctions, full scans, searches), a merchant, profession windows, bags and tooltips; the addon runs in it from its
// .toc, then every tools/tests-*.lua scene runs. Needs fengari (a Lua VM in JavaScript, test tool only), taken from
// the Warlock Sim addon's tools folder next to this project.
//   node tools/test.js            all scenes
//   node tools/test.js scan       only scenes whose title contains "scan"
//   XNAH_TIMES=1 node tools/test.js   also how long each scene took
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const FENGARI = path.join(ROOT, '..', 'warlock-sim-addon', 'tools', 'node_modules', 'fengari');
if (!fs.existsSync(FENGARI)) { console.log('SKIPPED: fengari not found at ' + FENGARI); process.exit(0); }
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);

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

// the game's Lua is 5.1: at most 60 upvalues per function (fengari does not enforce it). Counted after every scene by
// walking every function reachable from the addon table, its globals and its frames, and the upvalues of those.
run(`HOSTUP = {max = 0, where = ""}
function HOSTUP.walk()
  local seen = {}
  local function visit(v, depth)
    if depth > 12 or seen[v] then return end
    local kind = type(v)
    if kind == "table" then
      seen[v] = true
      for k, x in pairs(v) do visit(k, depth + 1) visit(x, depth + 1) end
    elseif kind == "function" then
      seen[v] = true
      local i = debug.getinfo(v, "uS")
      if i.what == "Lua" and i.source:sub(1, 1) == "@" and not i.source:find("world") and not i.source:find("tests") then
        if i.nups > HOSTUP.max then HOSTUP.max = i.nups HOSTUP.where = i.short_src .. ":" .. i.linedefined end
        for u = 1, i.nups do local _, x = debug.getupvalue(v, u) visit(x, depth + 1) end
      end
    end
  end
  if W.X then visit(W.X, 0) end
  if W.env then for k, v in pairs(W.env) do visit(v, 0) end end
  for _, f in ipairs(W.frames or {}) do visit(f.scripts, 0) end
end`, '=host');
run(fs.readFileSync(path.join(__dirname, 'world.lua'), 'utf8'), '@world.lua');
for (const f of files) {
  const p = path.join(ROOT, 'XNAH', f);
  setString('__src', fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '');
  run(`W.source(${JSON.stringify(f)}, __src)`, '=src');
}
run(`W.addonFiles({${files.map(f => JSON.stringify(f)).join(',')}})`, '=files');
setString('FILTER', process.argv[2] || '');
setString('SHOW_TIMES', process.env.XNAH_TIMES ? '1' : '');
let crashed = null;
for (const f of fs.readdirSync(__dirname).filter(f => /^tests.*\.lua$/.test(f)).sort()) {
  try { run(fs.readFileSync(path.join(__dirname, f), 'utf8'), '@' + f); }
  catch (e) { crashed = (crashed ? crashed + '\n' : '') + f + ': ' + e.message; }
}
const out = run('return T.report()', '=report');
const notes = run('return T.notes and #T.notes > 0 and table.concat(T.notes, "\\n") or nil', '=notes'); // numbers a scene reports
if (notes) console.log(notes);
if (crashed) console.log('FAIL (a test file crashed): ' + crashed);
console.log(out);
run('HOSTUP.walk()', '=walk');
const ups = Number(run('return HOSTUP.max', '=up')), where = run('return HOSTUP.where', '=up');
// fengari counts the globals table (_ENV) as one upvalue; the game's Lua does not
console.log('Most upvalues in one function: ' + ups + ' (limit in the game: 60) at ' + where + (ups > 58 ? '  <-- TOO MANY' : ''));
process.exit(/FAIL/.test(out) || crashed || ups > 58 ? 1 : 0);
