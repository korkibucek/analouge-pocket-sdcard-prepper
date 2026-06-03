// Headless test for the web UI (app.js) using jsdom + a stubbed fetch.
// Verifies the wizard bootstraps, talks to the API, and renders without errors.
// Dev-only: run `npm install` then `npm test` in this folder. Not a runtime dep.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import { JSDOM, ResourceLoader } from 'jsdom';

const here = dirname(fileURLToPath(import.meta.url));
const webDir = join(here, '..', '..', 'src', 'PocketPrep', 'web');
const html = readFileSync(join(webDir, 'index.html'), 'utf8').replace('__POCKETPREP_TOKEN__', 'TESTTOKEN');

// Canned API responses for whatever app.js requests.
const API = {
  '/api/health': { ok: true, root: '/tmp/PocketSDTest', testMode: true, dryRun: false, targetReady: false },
  '/api/drives': { drives: [
    { DriveLetter: '/media/u/POCKET', RootPath: '/media/u/POCKET', Label: 'POCKET', FileSystem: 'exFAT', SizeBytes: 64424509440, FreeBytes: 64000000000, IsRemovable: true, BusType: 'usb' },
  ] },
};

let calls = [];
function makeFetch(win) {
  return (url, opts = {}) => {
    calls.push(url);
    const path = url.split('?')[0];
    const body = API[path] ?? {};
    return Promise.resolve({
      ok: true, status: 200,
      json: () => Promise.resolve(body),
    });
  };
}

// Serve /app.js and /style.css from disk; ignore other resource requests.
class LocalLoader extends ResourceLoader {
  fetch(url, options) {
    const m = url.match(/\/(app\.js|style\.css)$/);
    if (m) return Promise.resolve(Buffer.from(readFileSync(join(webDir, m[1]))));
    return null;
  }
}

const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  resources: new LocalLoader(),
  url: 'http://127.0.0.1:8770/',
  beforeParse(win) {
    win.fetch = makeFetch(win);
    win.POCKETPREP_TOKEN = 'TESTTOKEN';
  },
});

// Wait for async bootstrap + first step render.
await new Promise((r) => setTimeout(r, 400));

const doc = dom.window.document;
const panel = doc.getElementById('panel');
const ctx = doc.getElementById('ctx');

function fail(msg) { console.error('FAIL: ' + msg); process.exit(1); }

// 1. The token-authenticated API was actually called.
assert.ok(calls.includes('/api/health'), 'expected /api/health to be called');
assert.ok(calls.includes('/api/drives'), 'expected /api/drives to be called (target not ready -> step 0)');

// 2. The drive we returned is rendered in the target step.
assert.ok(panel.innerHTML.includes('POCKET'), 'expected the POCKET drive to render in the panel');
assert.ok(panel.querySelector('#useBtn'), 'expected the "Use this target" button to render');

// 3. The context line reflects "no target selected yet".
assert.ok(/no target/i.test(ctx.textContent), 'expected the context line to say no target selected');

// 4. No uncaught error left the panel in the error state.
assert.ok(!panel.querySelector('.error'), 'panel should not be in an error state');

console.log(`OK: web UI bootstrapped, called [${[...new Set(calls)].join(', ')}], rendered the target step.`);
process.exit(0);
