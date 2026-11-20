// XNAH's PC tool for hourly auction house data. Every hour it fetches the whole auction house of your realm and faction
// from the game's official web API (the Battle.net developer API), boils it down to a few numbers per item (lowest price
// of one, market value, how many listed, how many auctions) and writes them into a small companion addon folder,
// XNAH_Data, which the game reads at login. XNAH then records them like a full scan. New data reaches a running game
// only with /reload or a relog.
// Data source: the game's official web API (Battle.net, Blizzard Entertainment). Each player uses their own developer
// key (never shared, never part of XNAH). What is kept: the per-item numbers of each hourly snapshot, at most 7 days,
// in private/api/ - no raw listings.
//
//   node tools/api-fetch.js --once         fetch now (when the house has new data), write XNAH_Data, stop
//   node tools/api-fetch.js --watch        keep running: fetch every hour, a few minutes after the house updates
//   node tools/api-fetch.js --dry          use the sample files in tools/api-sample/ instead of the network (tests)
//   node tools/api-fetch.js --find-house 2592=35s 14047=1g2s50c 2589*1200
//        which house is yours: give a few items with a price of one you saw in game (ID=price) or how many were
//        listed (ID*count); houses 110, 111, 119 and 123 are compared (or --houses=110,111)
// More options: --config=<file> (default private/api.json), --store=<folder> (default private/api), --out=<AddOns
// folder> (default: the game's), --sample=<folder>, --dry-time=<unix seconds> (the time of a dry snapshot).
//
// private/api.json (local only, never shared):
//   {"clientId": "...", "clientSecret": "...", "region": "eu", "houseId": 111,
//    optional: "ruleset": 2, "gameFolder": "C:\\Program Files (x86)\\World of Warcraft\\_forever_",
//    "realm": "Realm 6946-Alliance" (only import there), "addonHours": 24, "addonEveryHours": 4, "keepDays": 7,
//    "delayMinutes": 5}
'use strict';
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');

// [[ settings ]]
const DEFAULTS = {
  clientId: '', clientSecret: '', region: 'eu', ruleset: 2, houseId: null,
  gameFolder: 'C:\\Program Files (x86)\\World of Warcraft\\_forever_',
  realm: '',           // e.g. "Realm 6946-Alliance": XNAH imports only on that realm (empty: any realm of the faction)
  faction: '',         // Alliance / Horde / Neutral: taken from the house number when empty
  addonHours: 24,      // the last this many hours go into XNAH_Data
  addonEveryHours: 4,  // ... one snapshot per this many hours (and always the newest): keeps XNAH's saved data small
  keepDays: 7,         // snapshots kept on this PC (at most 7: the data may be kept 30 days by the web API's terms)
  delayMinutes: 5,     // fetch this long after the house's hourly update
  findHouses: [110, 111, 119, 123],
};
// the houses the web API has for Forever (community findings, unofficial): Alliance, Horde, Blackwater (neutral)
const HOUSE_FACTION = {};
[110, 111, 112, 119, 123].forEach(h => HOUSE_FACTION[h] = 'Alliance');
[113, 114, 115, 120, 124].forEach(h => HOUSE_FACTION[h] = 'Horde');
[116, 117, 118, 121, 125].forEach(h => HOUSE_FACTION[h] = 'Neutral');

function parseArgs(argv) {
  const a = { list: [] };
  for (const s of argv) {
    const m = s.match(/^--([\w-]+)(?:=(.*))?$/);
    if (m) a[m[1]] = m[2] === undefined ? true : m[2];
    else a.list.push(s);
  }
  return a;
}

function loadConfig(args) {
  const file = args.config || path.join(ROOT, 'private', 'api.json');
  let conf = {};
  if (fs.existsSync(file)) {
    try { conf = JSON.parse(fs.readFileSync(file, 'utf8')); }
    catch (e) { throw new Error(file + ' is not valid JSON: ' + e.message); }
  } else if (!args.dry) {
    throw new Error('No settings file: ' + file + '\nMake it with your developer key (see the README): ' +
      '{"clientId": "...", "clientSecret": "...", "region": "eu", "houseId": 111}');
  }
  const c = Object.assign({}, DEFAULTS, conf);
  c.region = String(c.region || 'eu').toLowerCase();
  c.keepDays = Math.min(7, Math.max(1, Number(c.keepDays) || 7));
  c.addonHours = Math.min(c.keepDays * 24, Math.max(1, Number(c.addonHours) || 24));
  c.addonEveryHours = Math.max(1, Number(c.addonEveryHours) || 4);
  c.delayMinutes = Math.max(1, Number(c.delayMinutes) || 5);
  if (args.dry && !c.houseId) c.houseId = 111;
  if (c.houseId) c.houseId = Number(c.houseId);
  c.faction = c.faction || HOUSE_FACTION[c.houseId] || '';
  return c;
}

// [[ numbers ]]
const round = n => Math.floor((n || 0) + 0.5); // like X.Round in the addon
const DIGITS = '0123456789abcdefghijklmnopqrstuvwxyz';
function b36(n) { // like the addon's packing (Data.lua)
  if (n === null || n === undefined) return '';
  n = Math.floor(n + 0.5);
  if (n === 0) return '0';
  const neg = n < 0;
  if (neg) n = -n;
  let out = '';
  while (n > 0) { const r = n % 36; out = DIGITS[r] + out; n = (n - r) / 36; }
  return (neg ? '-' : '') + out;
}
// "12g 3s 50c", "1.5g", "35s", "12" (gold) -> copper; null if it is not money (like X.ParseMoney)
function parseMoney(text) {
  text = String(text || '').toLowerCase().replace(/\s+/g, '');
  if (!text) return null;
  if (/^\d+$/.test(text)) return Number(text) * 10000;
  let total = 0, any = false;
  const re = /([\d.]+)([gsc])/g; let m;
  while ((m = re.exec(text))) {
    const v = Number(m[1]); if (isNaN(v)) return null;
    any = true; total += v * (m[2] === 'g' ? 10000 : m[2] === 's' ? 100 : 1);
  }
  return any ? round(total) : null;
}
function money(c) {
  if (c === null || c === undefined) return '-';
  c = round(c);
  const g = Math.floor(c / 10000), s = Math.floor((c % 10000) / 100), k = c % 100;
  const parts = [];
  if (g) parts.push(g + 'g'); if (s) parts.push(s + 's'); if (k || !parts.length) parts.push(k + 'c');
  return parts.join(' ');
}

// Market value: the same as X.MarketValue in XNAH/Data.lua (tools/api-test.js compares both). list = [[price of one,
// count], ...] (buyouts only). The cheapest 15% of all units always count, more up to 30% while the price does not jump
// (over 20% above the one before); units under half the middle price of those are dropped, then units more than 1.5
// standard deviations off the average, and the rest averaged again. Returns {min, mkt, qty, auc} or null.
function marketValue(list) {
  if (!list || list.length === 0) return null;
  list = list.slice().sort((a, b) => a[0] - b[0]);
  let total = 0;
  for (const e of list) total += e[1];
  if (total <= 0) return null;
  const base = Math.min(3, total);
  const lo = Math.max(base, total * 0.15), hi = Math.max(base, total * 0.30);
  const taken = [];
  let n = 0, prev = null;
  for (const [price, count] of list) {
    if (n >= lo && (n >= hi || (prev !== null && price > prev * 1.2))) break;
    const take = Math.min(count, Math.max(1, Math.ceil(hi - n)));
    taken.push([price, take]);
    n += take;
    prev = price;
  }
  let median = taken[taken.length - 1][0], c = 0;
  for (const u of taken) { c += u[1]; if (c >= n / 2) { median = u[0]; break; } }
  const used = [];
  let sum = 0;
  n = 0;
  for (const u of taken) if (u[0] >= median * 0.5) { used.push(u); n += u[1]; sum += u[0] * u[1]; }
  const mean = sum / n;
  let v = 0;
  for (const u of used) v += Math.pow(u[0] - mean, 2) * u[1];
  const sd = Math.sqrt(v / n);
  let s2 = 0, n2 = 0;
  for (const u of used) if (Math.abs(u[0] - mean) <= 1.5 * sd + 0.5) { s2 += u[0] * u[1]; n2 += u[1]; }
  const mkt = n2 > 0 ? s2 / n2 : mean;
  return { min: list[0][0], mkt: round(mkt), qty: total, auc: list.length };
}

// XNAH's item key: the item ID, or "id:suffix" for an item with a random bonus ("of the Bear"). Which field of the
// web API holds that bonus on Forever is not known yet: "rand" (as on other Classic versions) is used when present.
function keyOf(item) {
  const id = item && Number(item.id);
  if (!id) return null;
  const r = Number(item.rand || 0);
  return r ? id + ':' + r : String(id);
}

// listings (regular + commodities, as the web API sends them) -> per item numbers
// regular listing: {id, item: {id, ...}, buyout (the whole auction), bid, quantity, time_left}
// commodity listing: {id, item: {id}, quantity, unit_price, time_left}
function reduce(regular, commodities) {
  const rows = new Map(), fields = new Set();
  let auctions = 0;
  const row = key => { let r = rows.get(key); if (!r) { r = { list: [], bidOnly: 0 }; rows.set(key, r); } return r; };
  for (const a of (regular && regular.auctions) || []) {
    const key = keyOf(a.item); if (!key) continue;
    Object.keys(a.item).forEach(f => fields.add(f));
    auctions++;
    const q = Math.max(1, Number(a.quantity) || 1);
    const r = row(key);
    if (a.buyout > 0) r.list.push([a.buyout / q, q]);
    else if (a.unit_price > 0) r.list.push([a.unit_price, q]);
    else r.bidOnly += q;
  }
  for (const a of (commodities && commodities.auctions) || []) {
    const key = keyOf(a.item); if (!key) continue;
    auctions++;
    const q = Math.max(1, Number(a.quantity) || 1);
    const r = row(key);
    if (a.unit_price > 0) r.list.push([a.unit_price, q]);
    else if (a.buyout > 0) r.list.push([a.buyout / q, q]);
    else r.bidOnly += q;
  }
  const items = new Map();
  for (const [key, r] of rows) {
    const mv = marketValue(r.list);
    // like a full scan in game: bid-only units count in the quantity, auctions = listings with a buyout
    items.set(key, mv ? { min: round(mv.min), mkt: mv.mkt, qty: mv.qty + r.bidOnly, auc: mv.auc }
      : { min: null, mkt: null, qty: r.bidOnly, auc: 0 });
  }
  return { items, auctions, fields: [...fields].sort() };
}
// every price of one per item (for --find-house)
function priceLists(regular, commodities) {
  const out = new Map();
  const add = (key, unit, q) => { let r = out.get(key); if (!r) { r = { prices: [], qty: 0 }; out.set(key, r); } r.qty += q; if (unit > 0) r.prices.push(round(unit)); };
  for (const a of (regular && regular.auctions) || []) {
    const key = keyOf(a.item); if (!key) continue;
    const q = Math.max(1, Number(a.quantity) || 1);
    add(key, a.buyout > 0 ? a.buyout / q : (a.unit_price || 0), q);
  }
  for (const a of (commodities && commodities.auctions) || []) {
    const key = keyOf(a.item); if (!key) continue;
    const q = Math.max(1, Number(a.quantity) || 1);
    add(key, a.unit_price || (a.buyout > 0 ? a.buyout / q : 0), q);
  }
  return out;
}

// [[ the local store ]] one small text file per snapshot: "key min mkt qty auc" per line ("-" = none)
function snapName(t) { return 'snap-' + t + '.txt'; }
function writeSnapshot(dir, snap) {
  fs.mkdirSync(dir, { recursive: true });
  const lines = ['# XNAH hourly snapshot t=' + snap.t + ' house=' + snap.house + ' auctions=' + snap.auctions + ' items=' + snap.items.size];
  const keys = [...snap.items.keys()].sort((a, b) => parseFloat(a) - parseFloat(b) || (a < b ? -1 : a > b ? 1 : 0));
  for (const k of keys) {
    const v = snap.items.get(k);
    lines.push([k, v.min ?? '-', v.mkt ?? '-', v.qty, v.auc].join(' '));
  }
  const file = path.join(dir, snapName(snap.t));
  fs.writeFileSync(file + '.tmp', lines.join('\n') + '\n');
  fs.renameSync(file + '.tmp', file);
  return file;
}
function readSnapshot(file) {
  const text = fs.readFileSync(file, 'utf8').split('\n');
  const head = text[0].match(/t=(\d+) house=(\d+) auctions=(\d+)/);
  if (!head) return null;
  const items = new Map();
  for (let i = 1; i < text.length; i++) {
    const p = text[i].split(' ');
    if (p.length < 5) continue;
    const num = s => s === '-' ? null : Number(s);
    items.set(p[0], { min: num(p[1]), mkt: num(p[2]), qty: Number(p[3]), auc: Number(p[4]) });
  }
  return { t: Number(head[1]), house: Number(head[2]), auctions: Number(head[3]), items };
}
function listSnapshots(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).map(n => n.match(/^snap-(\d+)\.txt$/)).filter(Boolean)
    .map(m => ({ t: Number(m[1]), file: path.join(dir, m[0]) })).sort((a, b) => a.t - b.t);
}
// snapshots older than keepDays are deleted (the web API's data must not be kept long)
function pruneSnapshots(dir, keepDays, now) {
  let gone = 0;
  for (const s of listSnapshots(dir)) if (s.t < now - keepDays * 86400) { fs.rmSync(s.file, { force: true }); gone++; }
  return gone;
}
// which snapshots go to the addon: the last addonHours, one per addonEveryHours block, and always the newest
function pickForAddon(list, conf, now) {
  const from = now - conf.addonHours * 3600, block = conf.addonEveryHours * 3600;
  const out = [], seen = new Set();
  const recent = list.filter(s => s.t >= from);
  recent.forEach((s, i) => {
    const b = Math.floor(s.t / block);
    if (!seen.has(b) || i === recent.length - 1) { seen.add(b); out.push(s); }
  });
  return out;
}

// [[ the companion addon ]] Interface/AddOns/XNAH_Data: XNAH_Data.toc + Data.lua
function interfaceVersion() {
  try { const m = fs.readFileSync(path.join(ROOT, 'XNAH', 'XNAH.toc'), 'utf8').match(/^## Interface:\s*(\d+)/m); if (m) return m[1]; }
  catch (e) { /* use the default */ }
  return '16001';
}
function tocText() {
  return ['## Interface: ' + interfaceVersion(),
    '## Title: XNAH Data',
    '## Notes: Hourly auction house data for XNAH, written by XNAH\'s PC tool (tools/api-fetch.js). Data: the game\'s official web API (Blizzard Entertainment).',
    '## Author: Xn',
    '## Dependencies: XNAH',
    '',
    'Data.lua', ''].join('\n');
}
const luaStr = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/[^\x20-\x7e]/g, '?') + '"';
function packItems(items) {
  const parts = [];
  for (const [k, v] of items) parts.push(k + ',' + b36(v.min) + ',' + b36(v.mkt) + ',' + b36(v.qty) + ',' + b36(v.auc));
  return parts.join(';');
}
function dataText(snaps, conf, now) {
  const out = [
    '-- XNAH_Data: hourly auction house data for XNAH, written by XNAH\'s PC tool (tools/api-fetch.js). Do not edit:',
    '-- it is written again every hour. Data source: the game\'s official web API (Blizzard Entertainment).',
    '-- items = "key,lowest price,market value,quantity,auctions;..." (numbers in base 36, like XNAH\'s saved data)',
    'XNAH_API = {',
    '\tv = 1,',
    '\tmade = ' + now + ',',
    '\thouse = ' + Number(conf.houseId) + ',',
    '\tregion = ' + luaStr(conf.region) + ',',
    '\tfaction = ' + luaStr(conf.faction || '') + ',',
    '\trealm = ' + luaStr(conf.realm || '') + ',',
    '\tsnapshots = {',
  ];
  for (const s of snaps) {
    out.push('\t\t{t = ' + s.t + ', n = ' + s.items.size + ', auctions = ' + s.auctions + ', items = ' + luaStr(packItems(s.items)) + '},');
  }
  out.push('\t},', '}', '');
  return out.join('\n');
}
// fengari (a Lua in JavaScript, from the Warlock Sim addon's tools) checks the file loads before it replaces the old one
function luaCheck(text) {
  const FENGARI = path.join(ROOT, '..', 'warlock-sim-addon', 'tools', 'node_modules', 'fengari');
  if (!fs.existsSync(FENGARI)) return null;
  const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(FENGARI);
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const code = text + '\nreturn type(XNAH_API) == "table" and type(XNAH_API.snapshots) == "table" and #XNAH_API.snapshots or -1';
  if (lauxlib.luaL_loadbuffer(L, to_luastring(code), null, to_luastring('=Data.lua')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    throw new Error('the new Data.lua does not load: ' + to_jsstring(lua.lua_tostring(L, -1)));
  }
  return lua.lua_tonumber(L, -1);
}
function writeAddon(addonsDir, snaps, conf, now) {
  if (!fs.existsSync(addonsDir)) throw new Error('AddOns folder not found: ' + addonsDir + ' (set "gameFolder" in private/api.json)');
  const dir = path.join(addonsDir, 'XNAH_Data');
  fs.mkdirSync(dir, { recursive: true });
  const toc = path.join(dir, 'XNAH_Data.toc'), want = tocText();
  if (!fs.existsSync(toc) || fs.readFileSync(toc, 'utf8') !== want) fs.writeFileSync(toc, want);
  const text = dataText(snaps, conf, now);
  const n = luaCheck(text);
  if (n !== null && n !== snaps.length) throw new Error('the new Data.lua has ' + n + ' snapshots, expected ' + snaps.length);
  const file = path.join(dir, 'Data.lua');
  fs.writeFileSync(file + '.tmp', text);
  fs.renameSync(file + '.tmp', file);
  return { file, bytes: text.length };
}

// [[ the web API ]] client-credentials token (kept ~23 h), ruleset routes of the dynamic-forever namespace
const sleep = ms => new Promise(r => setTimeout(r, ms));
function readJSON(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { return fallback; } }
function writeJSON(file, v) { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(v, null, 1)); }

async function getToken(conf, store, renew) {
  const file = path.join(store, 'token.json');
  const have = readJSON(file, null);
  if (!renew && have && have.token && have.expires > Date.now() + 3600 * 1000) return have.token;
  if (!conf.clientId || !conf.clientSecret) throw new Error('clientId / clientSecret missing in private/api.json');
  const host = conf.region === 'cn' ? 'https://oauth.battlenet.com.cn/token' : 'https://oauth.battle.net/token';
  const res = await fetch(host, {
    method: 'POST',
    headers: { Authorization: 'Basic ' + Buffer.from(conf.clientId + ':' + conf.clientSecret).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded' },
    body: 'grant_type=client_credentials',
    signal: AbortSignal.timeout(60000),
  });
  if (res.status === 401 || res.status === 400) throw new Error('the developer key was refused (check clientId and clientSecret in private/api.json)');
  if (!res.ok) throw new Error('getting a token failed: HTTP ' + res.status);
  const j = await res.json();
  const token = { token: j.access_token, expires: Date.now() + (Number(j.expires_in) || 86399) * 1000 };
  writeJSON(file, token);
  return token.token;
}
function apiUrl(conf, house, commodities) {
  const host = conf.region === 'cn' ? 'https://gateway.battlenet.com.cn' : 'https://' + conf.region + '.api.blizzard.com';
  return host + '/data/wow/ruleset/' + conf.ruleset + '/auctions/' + house + (commodities ? '/commodities' : '') +
    '?namespace=dynamic-forever-' + conf.region;
}
const WHY = {
  401: 'the token was refused', 403: 'refused: wrong region or the Forever namespace is gone',
  404: 'not found: wrong house number, or the web API changed (these Forever routes are unofficial)',
};
// GET with If-Modified-Since; a few tries on busy / server errors
async function apiGet(conf, store, url, since) {
  let renewed = false;
  for (let attempt = 1; ; attempt++) {
    const token = await getToken(conf, store, false);
    const headers = { Authorization: 'Bearer ' + token, 'Accept-Encoding': 'gzip' };
    if (since) headers['If-Modified-Since'] = since;
    let res;
    try { res = await fetch(url, { headers, signal: AbortSignal.timeout(300000) }); }
    catch (e) {
      if (attempt >= 3) throw new Error('no answer from the web API (' + e.message + ')');
      await sleep(20000 * attempt); continue;
    }
    if (res.status === 401 && !renewed) { renewed = true; await getToken(conf, store, true); attempt--; continue; }
    if ((res.status === 429 || res.status >= 500) && attempt < 3) { await sleep(30000 * attempt); continue; }
    if (res.status === 304) return { status: 304 };
    if (!res.ok) throw new Error('HTTP ' + res.status + ' ' + (WHY[res.status] || '') + ' - ' + url.replace(/\?.*/, ''));
    const lastModified = res.headers.get('last-modified');
    return { status: 200, body: await res.json(), lastModified };
  }
}
// one house: {changed, regular, commodities, t (the snapshot's time: Last-Modified)}
async function fetchHouse(conf, store, house, state, useSince) {
  const url = apiUrl(conf, house, false);
  const since = useSince ? state.lastModified && state.lastModified[url] : null;
  const reg = await apiGet(conf, store, url, since);
  if (reg.status === 304) return { changed: false };
  const com = await apiGet(conf, store, apiUrl(conf, house, true), null);
  const lm = Date.parse(reg.lastModified || '') || Date.now();
  if (useSince && reg.lastModified) { state.lastModified = state.lastModified || {}; state.lastModified[url] = reg.lastModified; }
  return { changed: true, regular: reg.body, commodities: com.body, t: Math.floor(lm / 1000) };
}
// --dry: the sample files (tools/api-sample/house-<id>.json and house-<id>-commodities.json)
function sampleHouse(sampleDir, house, timeArg) {
  const reg = path.join(sampleDir, 'house-' + house + '.json'), com = path.join(sampleDir, 'house-' + house + '-commodities.json');
  if (!fs.existsSync(reg)) throw new Error('no sample for house ' + house + ': ' + reg);
  const regular = JSON.parse(fs.readFileSync(reg, 'utf8'));
  const commodities = fs.existsSync(com) ? JSON.parse(fs.readFileSync(com, 'utf8')) : { auctions: [] };
  // the sample's time is now - 5 minutes (or --dry-time), so a dry run always looks fresh
  const t = timeArg ? Number(timeArg) : Math.floor(Date.now() / 1000) - 300;
  return { changed: true, regular, commodities, t };
}

// [[ one round ]] fetch -> reduce -> store -> XNAH_Data
async function runOnce(ctx) {
  const { conf, args, store, log } = ctx;
  if (!conf.houseId) throw new Error('"houseId" is missing in private/api.json (find yours with --find-house)');
  const stateFile = path.join(store, 'state.json');
  const state = readJSON(stateFile, {});
  const got = args.dry ? sampleHouse(ctx.sample, conf.houseId, args['dry-time']) : await fetchHouse(conf, store, conf.houseId, state, true);
  const now = args.dry ? got.t + 300 : Math.floor(Date.now() / 1000);
  let snap = null;
  if (!got.changed) {
    log('No new data yet (the house updates about once an hour).');
  } else {
    const r = reduce(got.regular, got.commodities);
    snap = { t: got.t, house: conf.houseId, auctions: r.auctions, items: r.items };
    if (!state.fieldsShown || args.dry) log('Item fields the web API sends: ' + r.fields.join(', '));
    state.fieldsShown = true;
    if (r.items.size === 0) log('The house has no auctions (wrong house number?) - nothing saved.');
    else {
      writeSnapshot(store, snap);
      log('Snapshot of ' + new Date(snap.t * 1000).toISOString().slice(0, 16).replace('T', ' ') + ' UTC: ' +
        r.auctions + ' auctions, ' + r.items.size + ' items.');
    }
    state.last = { t: snap.t, items: r.items.size, auctions: r.auctions, at: now };
  }
  const gone = pruneSnapshots(store, conf.keepDays, now);
  if (gone) log(gone + ' snapshot(s) older than ' + conf.keepDays + ' days deleted.');
  const all = listSnapshots(store);
  const pick = pickForAddon(all, conf, now);
  let written = null;
  if (pick.length && (got.changed || args.dry || !state.written)) {
    const snaps = pick.map(s => readSnapshot(s.file)).filter(Boolean);
    written = writeAddon(ctx.addons, snaps, conf, now);
    state.written = now;
    log('XNAH_Data written: ' + snaps.length + ' snapshot(s), ' + Math.round(written.bytes / 1024) + ' KB -> ' + written.file +
      ' (the game reads it at login or /reload).');
  }
  writeJSON(stateFile, state);
  return { changed: got.changed, t: snap ? snap.t : (state.last && state.last.t), written, kept: all.length };
}

// [[ --find-house ]] which house holds the listings you saw in game
function parseObservations(list) {
  const out = [];
  for (const s of list) {
    let m = s.match(/^(\d+)=(.+)$/);
    if (m) { const p = parseMoney(m[2]); if (p === null) throw new Error('not a price: ' + s); out.push({ id: m[1], price: p, text: s }); continue; }
    m = s.match(/^(\d+)\*(\d+)$/);
    if (m) { out.push({ id: m[1], count: Number(m[2]), text: s }); continue; }
    throw new Error('not understood: ' + s + ' (use ID=price like 2592=35s, or ID*count like 2589*1200)');
  }
  return out;
}
function scoreHouse(lists, obs) {
  let score = 0;
  const lines = [];
  for (const o of obs) {
    const r = lists.get(o.id);
    if (!r) { lines.push(o.text + ': not listed'); continue; }
    if (o.price !== undefined) {
      let best = Infinity;
      for (const p of r.prices) best = Math.min(best, Math.abs(p - o.price));
      if (best === 0) { score += 1; lines.push(o.text + ': listed at exactly that price'); }
      else if (best <= o.price * 0.01) { score += 0.5; lines.push(o.text + ': close (' + money(best) + ' off)'); }
      else lines.push(o.text + ': no listing at that price (lowest ' + money(Math.min(...r.prices)) + ')');
    } else {
      const off = Math.abs(r.qty - o.count) / Math.max(1, o.count);
      if (off <= 0.05) { score += 1; lines.push(o.text + ': ' + r.qty + ' listed - matches'); }
      else if (off <= 0.25) { score += 0.5; lines.push(o.text + ': ' + r.qty + ' listed - close'); }
      else lines.push(o.text + ': ' + r.qty + ' listed - does not match');
    }
  }
  return { score, lines };
}
async function findHouse(ctx) {
  const { conf, args, store, log } = ctx;
  const obs = parseObservations(args.list);
  if (!obs.length) throw new Error('give a few items you saw in game, e.g. --find-house 2592=35s 14047=1g2s50c 2589*1200');
  const houses = (args.houses ? String(args.houses).split(',') : conf.findHouses).map(Number).filter(Boolean);
  const cacheDir = path.join(store, 'find');
  fs.mkdirSync(cacheDir, { recursive: true });
  // cached price lists older than a day are deleted
  for (const n of fs.readdirSync(cacheDir)) {
    const f = path.join(cacheDir, n);
    if (Date.now() - fs.statSync(f).mtimeMs > 86400 * 1000) fs.rmSync(f, { force: true });
  }
  const results = [];
  for (const h of houses) {
    let lists;
    if (args.dry) {
      const got = sampleHouse(ctx.sample, h, null);
      lists = priceLists(got.regular, got.commodities);
    } else {
      const cache = path.join(cacheDir, 'house-' + h + '.json');
      const have = readJSON(cache, null);
      if (have && Date.now() - have.at < 50 * 60 * 1000) lists = new Map(have.lists);
      else {
        log('Fetching house ' + h + ' ...');
        const got = await fetchHouse(conf, store, h, {}, false);
        lists = priceLists(got.regular, got.commodities);
        writeJSON(cache, { at: Date.now(), lists: [...lists] });
      }
    }
    const s = scoreHouse(lists, obs);
    results.push({ house: h, score: s.score, lines: s.lines });
    log('House ' + h + ' (' + (HOUSE_FACTION[h] || '?') + '): ' + s.score + ' of ' + obs.length);
    s.lines.forEach(l => log('    ' + l));
  }
  results.sort((a, b) => b.score - a.score);
  const best = results[0], second = results[1];
  if (best && best.score > 0 && (!second || best.score >= second.score + 1)) {
    log('=> House ' + best.house + ' matches best. Put "houseId": ' + best.house + ' into private/api.json.');
    return best.house;
  }
  log('=> Not clear yet. Best: a rare item with one seller and a price nobody else uses, plus how many of a common item are listed.');
  return null;
}

// [[ start ]]
async function main() {
  const args = parseArgs(process.argv.slice(2));
  const log = s => console.log((args.watch ? new Date().toTimeString().slice(0, 8) + '  ' : '') + s);
  const conf = loadConfig(args);
  const store = args.store || path.join(ROOT, 'private', args.dry ? 'api-dry' : 'api');
  const addons = args.out || (args.dry ? path.join(store, 'AddOns') : path.join(conf.gameFolder, 'Interface', 'AddOns'));
  if (args.dry) fs.mkdirSync(addons, { recursive: true });
  const ctx = { conf, args, store, addons, log, sample: args.sample || path.join(__dirname, 'api-sample') };
  fs.mkdirSync(store, { recursive: true });
  if (args['find-house']) { await findHouse(ctx); return; }
  if (!args.watch || args.dry) {
    await runOnce(ctx);
    if (args.watch) log('(--dry: one round only)');
    return;
  }
  log('Watching house ' + conf.houseId + ' (' + conf.region + '): a fetch every hour, ' + conf.delayMinutes +
    ' minutes after the house updates. Close this window to stop.');
  for (;;) {
    let wait;
    try {
      const r = await runOnce(ctx);
      const nowS = Date.now() / 1000;
      const due = r.t ? r.t + 3600 + conf.delayMinutes * 60 : nowS + 300; // the next update + a few minutes
      wait = due > nowS ? due - nowS : 300;                            // late: look again in 5 minutes
    } catch (e) {
      log('Problem: ' + e.message + ' - trying again in 10 minutes.');
      wait = 600;
    }
    wait = Math.min(Math.max(wait, 60), 65 * 60);
    log('Next look in ' + Math.round(wait / 60) + ' min.');
    await sleep(wait * 1000);
  }
}

module.exports = { marketValue, reduce, priceLists, keyOf, b36, parseMoney, pickForAddon, dataText, packItems, scoreHouse,
  parseObservations, readSnapshot, HOUSE_FACTION };
if (require.main === module) {
  main().catch(e => { console.log('Problem: ' + e.message); process.exit(1); });
}
