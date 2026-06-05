// Headless test for the web UI (app.js) using jsdom + a stubbed fetch.
// Verifies the wizard bootstraps, talks to the API, and renders without errors.
// Dev-only: run `npm install` then `npm test` in this folder. Not a runtime dep.
//
// Note: we evaluate app.js directly in the jsdom window rather than relying on jsdom's
// ResourceLoader to fetch /app.js — that keeps the test working across jsdom versions
// (ResourceLoader was removed in jsdom 27+).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import assert from 'node:assert';
import jsdomPkg from 'jsdom';
const { JSDOM } = jsdomPkg;

const here = dirname(fileURLToPath(import.meta.url));
const webDir = join(here, '..', '..', 'src', 'PocketPrep', 'web');

// Load index.html, inject the test token, and strip the external asset references
// (we run app.js manually below; style.css is irrelevant to the logic test).
let html = readFileSync(join(webDir, 'index.html'), 'utf8').replace('__POCKETPREP_TOKEN__', 'TESTTOKEN');
html = html.replace('<script src="/app.js"></script>', '')
           .replace('<link rel="stylesheet" href="/style.css" />', '');

// Canned API responses for whatever app.js requests.
const API = {
  '/api/health': { ok: true, root: '/tmp/PocketSDTest', testMode: true, dryRun: false, targetReady: false },
  '/api/drives': { drives: [
    { DriveLetter: '/media/u/POCKET', RootPath: '/media/u/POCKET', Label: 'POCKET', FileSystem: 'exFAT', SizeBytes: 64424509440, FreeBytes: 64000000000, IsRemovable: true, BusType: 'usb' },
  ] },
};

const calls = [];
function stubFetch(url) {
  calls.push(url);
  const path = String(url).split('?')[0];
  const body = API[path] ?? {};
  return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(body) });
}

const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  url: 'http://127.0.0.1:8770/',
  beforeParse(win) {
    win.fetch = stubFetch;
    win.POCKETPREP_TOKEN = 'TESTTOKEN';
  },
});

// Run the real app.js in the window's global scope (no resource loader needed).
const appJs = readFileSync(join(webDir, 'app.js'), 'utf8');
dom.window.eval(appJs);

// Wait for async bootstrap + first step render.
await new Promise((r) => setTimeout(r, 400));

const doc = dom.window.document;
const panel = doc.getElementById('panel');
const ctx = doc.getElementById('ctx');

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

// 5. Accessibility hooks: a polite live region exists and was populated; the panel is a
//    focus target; and every radio/checkbox/text input has an associated <label>.
const live = doc.getElementById('sr-status');
assert.ok(live && live.getAttribute('aria-live') === 'polite', 'expected an aria-live status region');
assert.ok((live.textContent || '').trim().length > 0, 'expected the live region to be announced on step render');
assert.strictEqual(panel.getAttribute('tabindex'), '-1', 'panel should be focusable for step focus management');
for (const input of doc.querySelectorAll('input[type=radio], input[type=checkbox], input[type=text]')) {
  const hasLabel = (input.id && doc.querySelector(`label[for="${input.id}"]`)) || input.closest('label');
  assert.ok(hasLabel, `form control #${input.id || input.outerHTML} must have an associated label`);
}

console.log(`OK: web UI bootstrapped, called [${[...new Set(calls)].join(', ')}], rendered the target step; a11y hooks present.`);
process.exit(0);
