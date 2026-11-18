// Runs every check: Lua 5.1 syntax and upvalues, the Forever API lists, and the scenes in the stand-in world.
//   node tools/check-all.js
const { spawnSync } = require('child_process'), path = require('path');
let failed = 0;
for (const script of ['check-lua51.js', 'check-api.js', 'test.js']) {
  const r = spawnSync(process.execPath, [path.join(__dirname, script)], { encoding: 'utf8' });
  const out = (r.stdout || '') + (r.stderr || '');
  const last = out.trim().split('\n').slice(-2).join('\n');
  console.log('--- ' + script + '\n' + (r.status === 0 ? last : out.trim()));
  if (r.status !== 0) failed++;
}
console.log(failed ? 'FAIL: ' + failed + ' check(s) failed' : 'ALL OK');
process.exit(failed ? 1 : 0);
