// Joins the XNAH data of all your WoW accounts on this PC: every account then shows the characters of the others on
// the Wealth page (and their gold and items in "you own"), their sales in the ledger, and the newest prices of any
// account. Run it while the game is CLOSED (the game writes its saved data when it closes and would undo the merge).
//   node tools/sync-accounts.js           merge now (stops if the game is running)
//   node tools/sync-accounts.js --wait    wait until every game window is closed, then merge
//   node tools/sync-accounts.js --dry     show what would happen, write nothing
// Optional private/sync-accounts.json: {"wtf": "path to the WTF folder", "labels": {"ACCOUNTFOLDER": "short name"}}.
// Every file is backed up first to private/backups/sync-<date>/.
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const ROOT = path.join(__dirname, '..');
const FENGARI = path.join(ROOT, '..', 'warlock-sim-addon', 'tools', 'node_modules', 'fengari');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);
const args = process.argv.slice(2), dry = args.includes('--dry'), wait = args.includes('--wait');

let conf = {};
const confFile = path.join(ROOT, 'private', 'sync-accounts.json');
if (fs.existsSync(confFile)) conf = JSON.parse(fs.readFileSync(confFile, 'utf8'));
// --wtf=<folder>: another WTF folder (a copy, for testing: then a running game does not matter)
const wtfArg = (args.find(a => a.startsWith('--wtf=')) || '').slice(6);
const WTF = wtfArg || conf.wtf ||'C:\\Program Files (x86)\\World of Warcraft\\_forever_\\WTF';
const labels = conf.labels || {};

function gameRunning() {
  try { return /Wow\.exe/i.test(execSync('tasklist /FI "IMAGENAME eq Wow.exe" /NH', { encoding: 'utf8' })); }
  catch (e) { return false; }
}
function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }

if (!wtfArg && gameRunning()) {
  if (!wait) { console.log('The game is running: close every game window first (or use --wait). Nothing changed.'); process.exit(1); }
  console.log('Waiting for every game window to close ...');
  while (gameRunning()) sleep(5000);
  sleep(5000); // the game writes its files while closing
}

// accounts = folders with a SavedVariables folder (the "SavedVariables" folder next to them is not an account)
const ACC = path.join(WTF, 'Account');
const accounts = fs.readdirSync(ACC).filter(n => n !== 'SavedVariables' && fs.existsSync(path.join(ACC, n, 'SavedVariables')));
if (accounts.length < 2) { console.log('Only ' + accounts.length + ' account found in ' + ACC + ': nothing to join.'); process.exit(0); }

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function run(code, name) {
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring(name)) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    const msg = to_jsstring(lua.lua_tostring(L, -1)); lua.lua_pop(L, 1); throw new Error(msg);
  }
  const v = lua.lua_isnil(L, -1) ? null : to_jsstring(lua.lua_tolstring(L, -1)); lua.lua_pop(L, 1); return v;
}
function setString(name, value) { lua.lua_pushstring(L, to_luastring(value)); lua.lua_setglobal(L, to_luastring(name)); }

run('ACCTS = {}', '=init');
accounts.forEach((acct, i) => {
  const file = path.join(ACC, acct, 'SavedVariables', 'XNAH.lua');
  const label = labels[acct] || acct;
  setString('__label', label);
  if (fs.existsSync(file)) {
    setString('__src', fs.readFileSync(file, 'utf8'));
    run('XNAHDB = nil local f = assert(load(__src, "=" .. __label)) f() ACCTS[#ACCTS + 1] = {label = __label, db = XNAHDB}', '=load');
    console.log(label + ': XNAH data read (' + fs.statSync(file).size + ' bytes)');
  } else {
    run('ACCTS[#ACCTS + 1] = {label = __label}', '=load');
    console.log(label + ': no XNAH data yet (it gets the other accounts\' characters now)');
  }
});
run('NOW = ' + Math.floor(Date.now() / 1000), '=now');
run(fs.readFileSync(path.join(__dirname, 'sync-accounts.lua'), 'utf8'), '@sync-accounts.lua');
console.log(run('return table.concat(SYNC.report, "\\n")', '=report'));
if (dry) { console.log('dry run: nothing written'); process.exit(0); }

const stamp = new Date().toISOString().replace(/[:T]/g, '-').slice(0, 16);
const backup = path.join(ROOT, 'private', 'backups', 'sync-' + stamp);
fs.mkdirSync(backup, { recursive: true });
accounts.forEach((acct, i) => {
  const file = path.join(ACC, acct, 'SavedVariables', 'XNAH.lua');
  if (fs.existsSync(file)) fs.copyFileSync(file, path.join(backup, acct.replace(/[^\w-]/g, '_') + '.XNAH.lua'));
  const text = run('return SYNC.out[' + (i + 1) + ']', '=out');
  // the new text must load again before it replaces anything
  setString('__chk', text);
  run('XNAHDB = nil assert(load(__chk))() assert(type(XNAHDB) == "table")', '=check');
  fs.writeFileSync(file, text);
});
console.log('Done. Backups: ' + backup);
