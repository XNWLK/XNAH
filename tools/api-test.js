// Tests of the PC tool for hourly web data (tools/api-fetch.js), no network: the market value is the same as XNAH's
// X.MarketValue (taken from XNAH/Data.lua and run in fengari, a Lua in JavaScript), the --dry rounds keep at most 7 days
// and write a Data.lua that loads, --find-house picks the right sample house.
//   node tools/api-test.js
'use strict';
const fs = require('fs'), path = require('path'), os = require('os'), { spawnSync } = require('child_process');
const ROOT = path.join(__dirname, '..');
const tool = require('./api-fetch.js');
let pass = 0, fail = 0;
function ok(title, cond, detail) {
  if (cond) pass++; else { fail++; console.log('FAIL ' + title + (detail !== undefined ? '\n  ' + JSON.stringify(detail) : '')); }
}

// [[ the market value: JS == Lua ]]
const FENGARI = path.join(ROOT, '..', 'warlock-sim-addon', 'tools', 'node_modules', 'fengari');
if (!fs.existsSync(FENGARI)) console.log('SKIPPED (fengari not found): market value compared with the Lua one');
else {
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const run = code => {
    if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('=test')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
      throw new Error(to_jsstring(lua.lua_tostring(L, -1)));
    }
    const v = lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tolstring(L, -1)); lua.lua_pop(L, 1); return v;
  };
  const data = fs.readFileSync(path.join(ROOT, 'XNAH', 'Data.lua'), 'utf8');
  const m = data.match(/\nfunction X\.MarketValue\(list\)[\s\S]*?\nend\n/);
  ok('X.MarketValue found in Data.lua', !!m);
  run('X = {Round = function(n) return math.floor((n or 0) + 0.5) end}\n' + m[0] + '\nreturn "ok"');
  let seed = 42;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
  const lists = [
    [[100, 1]], [[100, 2], [50, 1]], [[100, 3], [1, 1]], [[500, 200], [490, 1], [10, 1]], [[100, 0], [200, 5]],
    [[175, 7000], [10000, 2]], [[1, 1], [1, 1], [1, 1]], [[100, 1], [100, 5], [130, 20], [131, 20], [400, 3]],
  ];
  for (let i = 0; i < 400; i++) {
    const n = 1 + Math.floor(rnd() * 40), base = 10 + Math.floor(rnd() * 100000), list = [];
    for (let k = 0; k < n; k++) {
      // a few equal prices on purpose (ties), some silly cheap or dear listings
      const r = rnd();
      const price = r < 0.05 ? Math.max(1, Math.round(base * 0.1)) : r > 0.95 ? base * 10 : Math.round(base * (0.8 + Math.floor(rnd() * 12) * 0.05));
      list.push([price, [1, 1, 5, 20, 200][Math.floor(rnd() * 5)]]);
    }
    lists.push(list);
  }
  let same = 0;
  for (const list of lists) {
    const js = tool.marketValue(list);
    const luaList = '{' + list.map(e => '{' + e[0] + ',' + e[1] + '}').join(',') + '}';
    const got = run('local a, b, c, d = X.MarketValue(' + luaList + ') return a and table.concat({a, b, c, d}, " ") or "nil"');
    const want = js ? [js.min, js.mkt, js.qty, js.auc].join(' ') : 'nil';
    if (got === want) same++; else ok('market value of ' + JSON.stringify(list).slice(0, 200), false, { lua: got, js: want });
  }
  ok('market value: JS and Lua agree on ' + lists.length + ' lists', same === lists.length, same);
}

// [[ small pieces ]]
ok('b36 like the addon', tool.b36(0) === '0' && tool.b36(35) === 'z' && tool.b36(36) === '10' && tool.b36(-19) === '-j' && tool.b36(null) === '');
ok('money text', tool.parseMoney('1g 2s 50c') === 10250 && tool.parseMoney('35s') === 3500 && tool.parseMoney('12') === 120000 && tool.parseMoney('x') === null);
ok('item key with a random bonus', tool.keyOf({ id: 15210, rand: -19 }) === '15210:-19' && tool.keyOf({ id: 2589 }) === '2589');
const red = tool.reduce({ auctions: [
  { item: { id: 4071 }, buyout: 90000, quantity: 1 }, { item: { id: 4071 }, buyout: 95000, quantity: 1 },
  { item: { id: 7524 }, bid: 9000, quantity: 1 },
] }, { auctions: [{ item: { id: 2589 }, unit_price: 60, quantity: 20 }, { item: { id: 2589 }, unit_price: 55, quantity: 5 }] });
ok('reduce: lowest, quantity, auctions', red.items.get('4071').min === 90000 && red.items.get('4071').qty === 2 && red.items.get('4071').auc === 2);
ok('reduce: a bid-only auction counts in the quantity, no price', red.items.get('7524').min === null && red.items.get('7524').qty === 1 && red.items.get('7524').auc === 0);
ok('reduce: commodities per unit', red.items.get('2589').min === 55 && red.items.get('2589').qty === 25);
ok('reduce: auctions counted', red.auctions === 5);
// which snapshots go to the addon
const H = 3600, conf = { addonHours: 24, addonEveryHours: 4 };
const snaps = []; for (let i = 0; i < 48; i++) snaps.push({ t: 1795000000 + i * H });
const now = snaps[47].t + 300;
const pick = tool.pickForAddon(snaps, conf, now);
ok('addon: only the last 24 hours', pick.every(s => s.t >= now - 24 * H));
ok('addon: about one per 4 hours plus the newest', pick.length >= 6 && pick.length <= 8, pick.length);
ok('addon: the newest is in', pick[pick.length - 1].t === snaps[47].t);

// [[ dry rounds ]] a temporary store and AddOns folder
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'xnah-api-'));
const store = path.join(tmp, 'store'), out = path.join(tmp, 'AddOns');
fs.mkdirSync(out, { recursive: true });
const cfg = path.join(tmp, 'api.json');
fs.writeFileSync(cfg, JSON.stringify({ region: 'eu', houseId: 111, keepDays: 30, realm: 'Realm 6946-Alliance' }));
function dry(extra) {
  const r = spawnSync(process.execPath, [path.join(__dirname, 'api-fetch.js'), '--dry', '--config=' + cfg, '--store=' + store, '--out=' + out].concat(extra || []), { encoding: 'utf8' });
  return { code: r.status, text: (r.stdout || '') + (r.stderr || '') };
}
const T0 = 1795000000 + 19 * 60;
let last;
for (let d = 0; d < 9 * 24; d += 6) last = dry(['--dry-time=' + (T0 + d * H)]);
ok('dry rounds run', last.code === 0, last.text);
const kept = fs.readdirSync(store).filter(n => /^snap-\d+\.txt$/.test(n)).map(n => Number(n.match(/\d+/)[0]));
const newest = T0 + (9 * 24 - 6) * H;
ok('at most 7 days kept (keepDays 30 in the settings is capped)', kept.length > 0 && Math.min(...kept) >= newest + 300 - 7 * 86400, kept.length);
ok('the newest snapshot is kept', kept.includes(newest));
const dataFile = path.join(out, 'XNAH_Data', 'Data.lua');
ok('Data.lua written', fs.existsSync(dataFile));
ok('XNAH_Data.toc written', /## Dependencies: XNAH/.test(fs.readFileSync(path.join(out, 'XNAH_Data', 'XNAH_Data.toc'), 'utf8')));
const text = fs.readFileSync(dataFile, 'utf8');
ok('Data.lua is plain ASCII', /^[\x0a\x09\x20-\x7e]*$/.test(text));
ok('Data.lua names the realm and faction', /realm = "Realm 6946-Alliance"/.test(text) && /faction = "Alliance"/.test(text));
const snapTimes = (text.match(/\{t = (\d+)/g) || []).map(s => Number(s.slice(5)));
ok('Data.lua: snapshots of the last 24 hours only', snapTimes.length >= 1 && snapTimes.every(t => t >= newest + 300 - 24 * H), snapTimes);
if (fs.existsSync(FENGARI)) {
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  // the newest snapshot read back the way XNAH/Api.lua reads it, compared with the store's text file
  const code = text + `
local s = XNAH_API.snapshots[#XNAH_API.snapshots]
local out = {}
for entry in s.items:gmatch("[^;]+") do
  local key, a, b, c, d = entry:match("^([^,]+),([^,]*),([^,]*),([^,]*),([^,]*)$")
  local n = function(x) return x ~= "" and tonumber(x, 36) or "-" end
  out[#out + 1] = key .. " " .. n(a) .. " " .. n(b) .. " " .. n(c) .. " " .. n(d)
end
return s.t .. "\\n" .. table.concat(out, "\\n")`;
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('=Data.lua')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    ok('Data.lua loads in Lua', false, to_jsstring(lua.lua_tostring(L, -1)));
  } else {
    const lines = to_jsstring(lua.lua_tolstring(L, -1)).split('\n');
    const t = Number(lines.shift());
    const snapText = fs.readFileSync(path.join(store, 'snap-' + t + '.txt'), 'utf8').trim().split('\n').slice(1);
    ok('Data.lua numbers == the stored snapshot', lines.join('\n') === snapText.join('\n'), { lua: lines.slice(0, 3), store: snapText.slice(0, 3) });
    ok('a random-bonus key in the data', lines.some(l => l.startsWith('15210:-19 ')));
  }
}
// find the house
const fh = dry(['--find-house', '13468=33g33s33c', '4071=8g88s', '2589*150']);
ok('--find-house picks house 111', fh.code === 0 && /House 111 matches best/.test(fh.text), fh.text);
const fh2 = dry(['--find-house', '2589*150']);
ok('--find-house says when it is not clear', /Not clear yet/.test(fh2.text), fh2.text);
const bad = dry(['--find-house', 'linen']);
ok('--find-house: a wrong word is explained', bad.code === 1 && /not understood/.test(bad.text), bad.text);
// no settings file: a plain message
const r = spawnSync(process.execPath, [path.join(__dirname, 'api-fetch.js'), '--once', '--config=' + path.join(tmp, 'none.json'), '--store=' + store], { encoding: 'utf8' });
ok('no settings file: told how to make it', r.status === 1 && /No settings file/.test(r.stdout), r.stdout);
fs.rmSync(tmp, { recursive: true, force: true });

console.log((fail ? 'FAIL' : 'OK') + ': ' + pass + ' checks passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
