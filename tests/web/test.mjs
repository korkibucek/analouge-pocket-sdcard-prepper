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
assert.ok(!panel.innerHTML.includes('needs a modern browser'), 'unsupported-browser guard should stand down on a supported browser');
assert.strictEqual(dom.window.__pocketUp, true, 'app should mark itself up');

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

// 6. Action hub: when a target is already selected, the app lands on the menu (not the
//    forced wizard), shows the standalone action buttons, and the nav is clickable.
const API2 = {
  '/api/health': { ok: true, root: '/tmp/PocketSDTest', testMode: true, dryRun: false, targetReady: true },
  '/api/card-summary': { Firmware: { Present: false }, Cores: { Count: 0 }, Roms: { TotalFiles: 0, Systems: [] }, Config: { Exists: false, SourceCount: 0 }, Bios: [] },
};
const calls2 = [];
const dom2 = new JSDOM(html, {
  runScripts: 'dangerously',
  url: 'http://127.0.0.1:8770/',
  beforeParse(win) {
    // Map values may be functions of the request init, so POST stubs can vary by body.
    win.fetch = (url, init) => {
      const path = String(url).split('?')[0]; calls2.push(path);
      const v = API2[path];
      const body = typeof v === 'function' ? v(init) : (v ?? {});
      return Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(body) });
    };
    win.POCKETPREP_TOKEN = 'TESTTOKEN';
  },
});
dom2.window.eval(appJs);
await new Promise((r) => setTimeout(r, 400));
const doc2 = dom2.window.document;
const panel2 = doc2.getElementById('panel');
assert.ok(/what do you want to do/i.test(panel2.textContent), 'target-ready boot should land on the action menu');
assert.ok(panel2.querySelectorAll('button.menu-act').length >= 5, 'menu should offer multiple standalone actions');
assert.ok(/upload roms/i.test(panel2.textContent), 'menu should offer an Upload ROMs action');
assert.ok(/favourites/i.test(panel2.textContent), 'menu should offer a Favourites action');
assert.ok(/activity log/i.test(panel2.textContent), 'menu should offer an Activity log action');
assert.ok(/health check/i.test(panel2.textContent), 'menu should offer a Health check action');
assert.ok(doc2.getElementById('dry-toggle'), 'menu should expose a global dry-run toggle');
const menuChip = [...doc2.querySelectorAll('#steps span[data-go]')].find(s => s.dataset.go === 'menu');
assert.ok(menuChip, 'a clickable ☰ Menu nav chip should be present when a target is set');
const ejectBtn = doc2.getElementById('ejectBtn');
assert.ok(ejectBtn && !ejectBtn.hidden, 'the global Eject & quit button should be visible once a target is set');
assert.ok(ejectBtn.classList.contains('danger'), 'the Eject & quit button should be styled as dangerous');

// 7. BIOS reference panel: the card step lists EVERY expected filename per system/core
//    (with purpose labels), present and missing alike, with upload inputs only on missing.
API2['/api/card-summary'] = {
  Firmware: { Present: true, Version: '2.5', FileName: 'pocket_firmware_2_5.bin' },
  Cores: { Count: 1 }, Roms: { TotalFiles: 0, Systems: [] }, Config: { Exists: true, SourceCount: 1 },
  Bios: [],
  RequiredFiles: [{
    Identifier: 'Test.NeoGeo', PlatformId: 'ng', Satisfied: false, Missing: ['uni-bios_4_0.rom'],
    Required: [
      { Name: 'BIOS', Filename: 'uni-bios_4_0.rom', Found: false, Location: '/x/Assets/ng/common/uni-bios_4_0.rom' },
      { Name: 'LO', Filename: '000-lo.lo', Found: true, Location: '/x/Assets/ng/common/000-lo.lo' },
    ],
  }],
};
API2['/api/empty'] = { IsEmpty: true, EntryCount: 0, Entries: [] };
dom2.window.eval('go(1)');
await new Promise((r) => setTimeout(r, 400));
const cardHtml = panel2.innerHTML;
assert.ok(cardHtml.includes('uni-bios_4_0.rom'), 'BIOS panel should name the missing expected file');
assert.ok(cardHtml.includes('000-lo.lo'), 'BIOS panel should also list files that are already present');
assert.ok(/expects 2 file/.test(panel2.textContent), 'BIOS panel should state how many files the core expects');
assert.ok(/BIOS/.test(cardHtml) && /LO/.test(cardHtml), 'BIOS panel should show the slot purpose labels');
assert.ok(panel2.querySelector('button[data-bios]'), 'missing files should offer an Install BIOS button');
assert.ok(panel2.querySelectorAll('button[data-bios]').length === 1, 'present files should NOT offer an upload button');

// 8. Favourites picker thumbnails (#191): rows show cached box art via /api/images/get
//    (cached-only — the picker must never trigger a scrape via /api/images/sync).
const PNG_1PX = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
API2['/api/card-summary'] = {
  Firmware: { Present: true, Version: '2.5' }, Cores: { Count: 1 }, Config: { Exists: true, SourceCount: 1 }, Bios: [],
  Roms: { TotalFiles: 2, Systems: [
    { PlatformId: 'gb', DisplayName: 'Game Boy', FileCount: 2, RomFormat: 'file' },
    // Folder-format systems (Neo Geo) launch via core instance jsons, not from common —
    // the favourites picker must exclude them (#200).
    { PlatformId: 'ng', DisplayName: 'Neo Geo', FileCount: 3, RomFormat: 'folder' },
  ] },
};
API2['/api/favorites'] = { Platforms: [{ PlatformId: 'gb', Names: ['Tetris.gb'] }] };
API2['/api/rom/list'] = { names: ['Tetris.gb', 'Zelda.gb'] };
API2['/api/images/get'] = (init) => {
  const req = JSON.parse((init && init.body) || '{}');
  return req.name === 'Tetris' ? { found: true, dataUrl: PNG_1PX } : { found: false };
};
calls2.length = 0;
dom2.window.eval('go("favorites")');
await new Promise((r) => setTimeout(r, 400));
const favPlatOpts = [...doc2.querySelectorAll('#fav-plat option')].map(o => o.value);
assert.ok(favPlatOpts.includes('gb') && !favPlatOpts.includes('ng'), 'folder-format systems (Neo Geo) must be excluded from the favourites picker');
const thumbs = panel2.querySelectorAll('.fav-thumb');
assert.ok(thumbs.length === 2, `each favourites row should carry a thumbnail slot (got ${thumbs.length})`);
// Tetris is favourited, so it sorts to the top row — and it's the one with cached art.
assert.ok(thumbs[0].querySelector('img') && thumbs[0].querySelector('img').src.startsWith('data:image/png'), 'cached art should render as the row thumbnail');
assert.ok(!thumbs[1].querySelector('img'), 'a game without cached art keeps the empty placeholder');
assert.ok(calls2.includes('/api/images/get'), 'thumbnails should come from /api/images/get');
assert.ok(!calls2.includes('/api/images/sync'), 'the favourites picker must never scrape');

// 9. Memory cleaner (#204): list save states; auto-select = keep newest per game;
//    backup hits /api/savestates/backup; delete only fires with confirm.
API2['/api/savestates'] = {
  Total: 4, TotalBytes: 4096,
  Items: [
    { Game: 'Sonic', Name: 'Sonic.sta', RelativePath: 'gb/c/Sonic.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-01T10:00:00.0000000Z', IsLatestForGame: false },
    { Game: 'Sonic', Name: 'Sonic #2.sta', RelativePath: 'gb/c/Sonic #2.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-05T10:00:00.0000000Z', IsLatestForGame: false },
    { Game: 'Sonic', Name: 'Sonic #3.sta', RelativePath: 'gb/c/Sonic #3.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-09T10:00:00.0000000Z', IsLatestForGame: true },
    { Game: 'Tetris', Name: 'Tetris.sta', RelativePath: 'gb/c/Tetris.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-03T10:00:00.0000000Z', IsLatestForGame: true },
  ],
  Games: [
    { Game: 'Sonic', Count: 3, Items: [
      { Game: 'Sonic', Name: 'Sonic #3.sta', RelativePath: 'gb/c/Sonic #3.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-09T10:00:00.0000000Z', IsLatestForGame: true },
      { Game: 'Sonic', Name: 'Sonic #2.sta', RelativePath: 'gb/c/Sonic #2.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-05T10:00:00.0000000Z', IsLatestForGame: false },
      { Game: 'Sonic', Name: 'Sonic.sta', RelativePath: 'gb/c/Sonic.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-01T10:00:00.0000000Z', IsLatestForGame: false },
    ] },
    { Game: 'Tetris', Count: 1, Items: [
      { Game: 'Tetris', Name: 'Tetris.sta', RelativePath: 'gb/c/Tetris.sta', SizeBytes: 1024, LastWriteUtc: '2026-06-03T10:00:00.0000000Z', IsLatestForGame: true },
    ] },
  ],
};
let backupPaths = null, deleteBody = null;
API2['/api/savestates/backup'] = (init) => { backupPaths = JSON.parse((init && init.body) || '{}').paths; return { fileName: 'pocket-memories-x.zip', count: 2, dataUrl: 'data:application/zip;base64,UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==' }; };
API2['/api/savestates/delete'] = (init) => { deleteBody = JSON.parse((init && init.body) || '{}'); return { Examined: deleteBody.paths.length, DeleteCount: deleteBody.paths.length, Deleted: deleteBody.paths, Skipped: [], BackupZip: 'pocketprep/save-backups/save-states-x.zip', DryRun: false }; };
// Auto-confirm dialogs and neutralise the download anchor's navigation in jsdom.
dom2.window.confirm = () => true;
dom2.window.HTMLAnchorElement.prototype.click = function () {};
calls2.length = 0;
dom2.window.eval('go("memories")');
await new Promise((r) => setTimeout(r, 300));
assert.ok(/Memory cleaner/i.test(panel2.textContent), 'memory cleaner panel should render');
assert.strictEqual(panel2.querySelectorAll('.mc-pick').length, 4, 'every save state should get a checkbox');
assert.strictEqual(panel2.querySelectorAll('.tag.rm').length, 2, 'the newest state of each game should be tagged');
// Auto-select keeps newest per game → 2 of 4 checked (the two older Sonic states).
dom2.window.document.getElementById('mc-auto').click();
await new Promise((r) => setTimeout(r, 50));
const checked = [...panel2.querySelectorAll('.mc-pick')].filter(c => c.checked).map(c => c.dataset.p);
assert.strictEqual(checked.length, 2, 'keep-newest-per-game should select all but the newest of each game');
assert.ok(checked.includes('gb/c/Sonic.sta') && checked.includes('gb/c/Sonic #2.sta') && !checked.includes('gb/c/Sonic #3.sta') && !checked.includes('gb/c/Tetris.sta'), 'auto-select math: only the non-newest states');
// Backup downloads the current selection without deleting.
dom2.window.document.getElementById('mc-backup').click();
await new Promise((r) => setTimeout(r, 50));
assert.ok(calls2.includes('/api/savestates/backup'), 'backup should call /api/savestates/backup');
assert.strictEqual(backupPaths.length, 2, 'backup should send the selected paths');
assert.ok(!calls2.includes('/api/savestates/delete'), 'backup must not delete');
// Delete fires only on the explicit Delete button, and with confirm:true.
dom2.window.document.getElementById('mc-delete').click();
await new Promise((r) => setTimeout(r, 50));
assert.ok(calls2.includes('/api/savestates/delete'), 'delete should call /api/savestates/delete');
assert.strictEqual(deleteBody.confirm, true, 'delete must be confirm-gated');
assert.strictEqual(deleteBody.paths.length, 2, 'delete should send exactly the selected paths');

console.log(`OK: web UI bootstrapped, called [${[...new Set(calls)].join(', ')}], rendered the target step; action menu renders on target-ready boot; favourites thumbnails render from cache; memory cleaner select/backup/delete wired; a11y hooks present.`);
process.exit(0);
