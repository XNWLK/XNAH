// Automatic "Sync accounts": runs in the background (started at Windows sign-in) and joins the XNAH data of all your
// WoW accounts every time the last game window closes - only when the game changed a file since the last sync.
// What it did goes to private/sync.log.
//   node tools/sync-watch.js          watch (until the PC shuts down)
//   node tools/sync-watch.js --once   one check now, then stop (for testing)
const fs = require('fs'), path = require('path'), { execSync, spawnSync } = require('child_process');
const ROOT = path.join(__dirname, '..');
const LOG = path.join(ROOT, 'private', 'sync.log');
const once = process.argv.includes('--once');

let conf = {};
const confFile = path.join(ROOT, 'private', 'sync-accounts.json');
if (fs.existsSync(confFile)) conf = JSON.parse(fs.readFileSync(confFile, 'utf8'));
const ACC = path.join(conf.wtf || 'C:\\Program Files (x86)\\World of Warcraft\\_forever_\\WTF', 'Account');

function log(text) {
  const line = new Date().toISOString().replace('T', ' ').slice(0, 19) + '  ' + text;
  fs.mkdirSync(path.dirname(LOG), { recursive: true });
  fs.appendFileSync(LOG, line + '\n');
  // keep the log short
  const all = fs.readFileSync(LOG, 'utf8').split('\n');
  if (all.length > 600) fs.writeFileSync(LOG, all.slice(-400).join('\n'));
}
function gameRunning() {
  try { return /Wow\.exe/i.test(execSync('tasklist /FI "IMAGENAME eq Wow.exe" /NH', { encoding: 'utf8', windowsHide: true })); }
  catch (e) { return false; }
}
function sleep(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }
// newest change time of any account's XNAH file
function newestFile() {
  let t = 0;
  try {
    for (const n of fs.readdirSync(ACC)) {
      const f = path.join(ACC, n, 'SavedVariables', 'XNAH.lua');
      if (fs.existsSync(f)) t = Math.max(t, fs.statSync(f).mtimeMs);
    }
  } catch (e) { }
  return t;
}
const STAMP = path.join(ROOT, 'private', 'sync-last.txt');
function lastSync() { try { return Number(fs.readFileSync(STAMP, 'utf8')) || 0; } catch (e) { return 0; } }

function syncIfNeeded() {
  if (newestFile() <= lastSync()) return false;
  const r = spawnSync(process.execPath, [path.join(__dirname, 'sync-accounts.js')], { encoding: 'utf8', windowsHide: true });
  const out = ((r.stdout || '') + (r.stderr || '')).trim().split('\n').filter(l => /characters from|Done|running|nothing|rror/.test(l));
  log((r.status === 0 ? 'synced: ' : 'sync FAILED: ') + out.join(' | '));
  // the files just written are the new "last sync" (so the sync's own writes do not count as changes)
  fs.writeFileSync(STAMP, String(Math.max(newestFile(), Date.now())));
  return true;
}

if (once) { if (!gameRunning()) syncIfNeeded(); process.exit(0); }
log('watching for the game to close');
let wasRunning = gameRunning();
if (!wasRunning) syncIfNeeded(); // changes from before the PC started
for (;;) {
  sleep(20000);
  const now = gameRunning();
  if (wasRunning && !now) {
    sleep(10000); // the game writes its saved data while closing
    if (!gameRunning()) syncIfNeeded();
  }
  wasRunning = gameRunning();
}
