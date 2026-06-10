/* Analogue Pocket SD Card Prepper - browser wizard.
   Talks to the localhost API. Copies files only; never formats or deletes. */
const TOKEN = window.POCKETPREP_TOKEN;
const $ = (sel) => document.querySelector(sel);

async function api(path, method = 'GET', body) {
  const opts = { method, headers: { 'Content-Type': 'application/json', 'X-PocketPrep-Token': TOKEN } };
  if (method !== 'GET') opts.body = JSON.stringify(body || {});
  const res = await fetch(path, opts);
  let data = null;
  try { data = await res.json(); } catch {}
  if (!res.ok) {
    if (method !== 'GET') logActivity(method, path, false, (data && data.error) || `HTTP ${res.status}`);
    const e = new Error((data && data.error) || `HTTP ${res.status}`); e.data = data; throw e;
  }
  if (method !== 'GET') logActivity(method, path, true);
  return data;
}
const fmtGB = (b) => (b ? (b / 1073741824).toFixed(1) + ' GB' : '—');
// Record state-changing (non-GET) actions for the session activity log.
function logActivity(method, path, ok, err) {
  const t = new Date().toISOString().replace('T', ' ').slice(0, 19);
  S.activity.push({ t, method, path, ok, err: err || '' });
  if (S.activity.length > 500) S.activity.shift();
}
// Spinner + disable in-panel buttons (and eject) during an operation, so a long request
// can't be double-submitted and the UI never looks idly clickable.
const busy = (on) => {
  $('#busy').hidden = !on;
  document.querySelectorAll('#panel button, #ejectBtn').forEach(b => { b.disabled = on; });
};
function announce(msg) { const el = $('#sr-status'); if (el) el.textContent = msg; }

// Folder picker: opens a modal that browses the local filesystem (via the server) and
// resolves to the chosen folder path, or null if cancelled.
function pickFolder(startPath) {
  return new Promise((resolve) => {
    const overlay = document.createElement('div');
    overlay.className = 'modal-overlay';
    overlay.innerHTML = `<div class="modal" role="dialog" aria-modal="true" aria-label="Choose a folder">
      <h3>Choose a folder</h3>
      <p id="fb-path" class="meta"></p>
      <div id="fb-roots" class="row"></div>
      <ul id="fb-list" class="list" style="max-height:50vh;overflow:auto"></ul>
      <div class="row"><button id="fb-up" class="secondary">▲ Up</button>
        <button id="fb-use">Use this folder</button>
        <button id="fb-cancel" class="secondary">Cancel</button></div>
    </div>`;
    document.body.appendChild(overlay);
    let cur = startPath || '';
    const close = (val) => { overlay.remove(); resolve(val); };

    async function load(path) {
      let d;
      try { d = await api('/api/browse', 'POST', { path }); }
      catch (e) { $('#fb-path').innerHTML = errLine(e.message); return; }
      cur = d.Path;
      $('#fb-path').textContent = cur;
      $('#fb-roots').innerHTML = (d.Roots || []).map(r => `<button class="secondary fb-root" data-p="${encodeURIComponent(r.Path)}">${r.Name}</button>`).join(' ');
      $('#fb-list').innerHTML = (d.Directories || []).length
        ? d.Directories.map(x => `<li><button class="fb-dir" data-p="${encodeURIComponent(x.Path)}">📁 ${x.Name}</button></li>`).join('')
        : '<li class="meta">(no sub-folders)</li>';
      overlay.querySelectorAll('.fb-dir, .fb-root').forEach(b => b.onclick = () => load(decodeURIComponent(b.dataset.p)));
      $('#fb-up').disabled = !d.Parent;
      $('#fb-up').onclick = () => d.Parent && load(d.Parent);
    }
    $('#fb-use').onclick = () => close(cur);
    $('#fb-cancel').onclick = () => close(null);
    overlay.onclick = (e) => { if (e.target === overlay) close(null); };
    load(cur);
  });
}
function panel(html) {
  const p = $('#panel');
  p.innerHTML = html;
  // Move keyboard/screen-reader focus to the new step, and announce it (heading, or the
  // panel text for error-only panels).
  const h = p.querySelector('h2');
  announce(h ? h.textContent : (p.textContent || '').trim().slice(0, 200));
  try { p.focus({ preventScroll: false }); } catch { p.focus(); }
}
function errLine(msg) { return `<p class="error">${msg}</p>`; }
// Clear, specific in-progress message so a long single-threaded operation can never
// look silently hung (downloads also have a server-side timeout).
function inProgress(label) { return `<p class="busy">${label}… please keep this tab open. This can take up to a minute and the page may be unresponsive while it runs.</p>`; }

const STEP_LABELS = ['Target', 'Card', 'Firmware', 'Folders', 'Cores', 'ROMs', 'Done'];
const S = { health: null, space: null, step: 0, drive: null, firmware: null, folder: null, roms: [], cores: [], activity: [] };

function renderNav() {
  // Non-linear once a target is set: every chip (and the Menu) is clickable.
  const ready = !!(S.health && S.health.targetReady);
  const chip = (label, key) => {
    const active = key === S.step ? ' active' : '';
    const nav = ready ? ` role="button" tabindex="0" data-go="${key}"` : '';
    return `<span class="${active.trim()}"${nav}>${label}</span>`;
  };
  const steps = STEP_LABELS.map((l, i) => chip(`${i + 1}. ${l}`, i)).join('');
  $('#steps').innerHTML = chip('☰ Menu', 'menu') + steps;
  document.querySelectorAll('#steps span[data-go]').forEach(s => {
    const t = s.dataset.go === 'menu' ? 'menu' : +s.dataset.go;
    s.onclick = () => go(t);
    s.onkeydown = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); go(t); } };
  });
}
/* ---- Action hub: pick a single task or run the full wizard ---- */
function showMenu() {
  const acts = [
    { go: 1, icon: '🧙', label: 'Run the full setup wizard', desc: 'Step through firmware, folders, cores and ROMs in order.' },
    { go: 1, icon: '💳', label: 'Card overview, breakdown & reorganize ROMs', desc: "See what's installed; split big libraries into folders; onboard a used card." },
    { go: 2, icon: '🔧', label: 'Firmware', desc: 'Install or update the Analogue Pocket firmware.' },
    { go: 3, icon: '📁', label: 'Folder structure', desc: 'Create the openFPGA folder structure on the card.' },
    { go: 4, icon: '🧩', label: 'Cores: install / update', desc: 'Install the whole core set or update installed cores.' },
    { go: 5, icon: '🎮', label: 'Upload ROMs', desc: 'Copy ROMs for any core (built-in, installed, catalog or custom).' },
    { go: 'favorites', icon: '⭐', label: 'Favourites', desc: 'Tag ROMs; surface them in a per-system Favorites folder.' },
    { go: 'activity', icon: '📝', label: 'Activity log', desc: 'See and download everything done this session.' },
    { go: 'profiles', icon: '💾', label: 'Setup profiles', desc: "Export this card's setup, or import one to a fresh card." },
    { go: 6, icon: '🧾', label: 'Summary', desc: 'Review what was done this session.' }
  ];
  const dr = !!(S.health && S.health.dryRun);
  panel(`<h2>What do you want to do?</h2>
    <p class="meta">Pick a single task, or run the full wizard. Return here any time via <strong>☰ Menu</strong>.</p>
    <label class="row card" style="gap:.5rem"><input type="checkbox" id="dry-toggle" ${dr ? 'checked' : ''}>
      <span><strong>Dry-run mode</strong> — preview actions without writing to the card${dr ? ' <span class="tag fixed">ON</span>' : ''}</span></label>
    <ul class="list" id="menu-list">${acts.map((a, i) =>
      `<li><button class="menu-act" data-i="${i}">${a.icon} <strong>${a.label}</strong><br><span class="meta">${a.desc}</span></button></li>`).join('')}</ul>`);
  document.querySelectorAll('.menu-act').forEach(b => b.onclick = () => go(acts[+b.dataset.i].go));
  $('#dry-toggle').onchange = async (e) => {
    try { const r = await api('/api/dryrun', 'POST', { enabled: e.target.checked }); if (S.health) S.health.dryRun = r.dryRun; setCtx(); showMenu(); }
    catch (err) { announce('Could not change dry-run mode: ' + err.message); }
  };
}
/* ---- Activity log: session record of state-changing actions, downloadable ---- */
function showActivity() {
  const esc = v => String(v == null ? '' : v).replace(/&/g, '&amp;').replace(/</g, '&lt;');
  const rows = S.activity.length
    ? S.activity.slice().reverse().map(a => `<li><span class="meta">${a.t}</span> ${a.ok ? '<span class="ok">✓</span>' : '<span class="error">✗</span>'} <code>${esc(a.method)} ${esc(a.path)}</code>${a.err ? ` <span class="error">${esc(a.err)}</span>` : ''}</li>`).join('')
    : '<li class="meta">No actions yet this session.</li>';
  panel(`<h2>📝 Activity log</h2>
    <p class="meta">Every state-changing request this session (newest first). A full log is also written to disk by the tool.</p>
    <div class="row"><button id="act-dl">Download log (.txt)</button> <span class="meta">${S.activity.length} entr${S.activity.length === 1 ? 'y' : 'ies'}</span></div>
    <ul class="list" style="max-height:55vh;overflow:auto">${rows}</ul>`);
  $('#act-dl').onclick = () => {
    const text = S.activity.map(a => `${a.t}\t${a.ok ? 'OK ' : 'ERR'}\t${a.method} ${a.path}${a.err ? '\t' + a.err : ''}`).join('\n') || '(no activity)';
    const blob = new Blob([`Analogue Pocket SD Card Prepper - session activity\n\n${text}\n`], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a'); a.href = url; a.download = 'pocketprep-activity.txt';
    document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);
  };
}
function setCtx() {
  const h = S.health;
  const space = (S.space && S.space.ready && S.space.totalBytes)
    ? ` · ${fmtGB(S.space.freeBytes)} free of ${fmtGB(S.space.totalBytes)}` : '';
  $('#ctx').textContent = h && h.targetReady
    ? `Target: ${h.root}${h.testMode ? ' (TEST MODE)' : ''}${h.dryRun ? ' · DRY-RUN' : ''}${space}`
    : 'No target selected yet';
}
// Refresh the card's free/total space and update the context line (after target + big ops).
async function refreshSpace() {
  try { S.space = await api('/api/space'); } catch { S.space = null; }
  setCtx();
}
// Global "Eject & quit": flush + eject the card then stop the app. Available on every page
// (footer button) once a target is set. Clearly dangerous; behind a confirm.
function wireEject() {
  const btn = $('#ejectBtn');
  if (!btn) return;
  btn.hidden = !(S.health && S.health.targetReady);
  btn.onclick = async () => {
    if (!window.confirm('Eject the card and close the app?\n\nThis flushes pending writes and ejects the card, then shuts the server down. Make sure no operation is running.')) return;
    busy(true);
    try {
      const r = await api('/api/eject', 'POST', {});
      const safe = r.Ejected ? 'Card ejected — safe to remove.' : (r.Flushed ? 'Writes flushed. ' + (r.Message || 'Please eject the card via your OS before unplugging.') : (r.Message || ''));
      try { await api('/api/shutdown', 'POST', {}); } catch { /* server going away */ }
      panel(`<h2>Done</h2><p class="ok">${safe}</p><p>The app has been closed. You can close this tab.</p>`);
    } catch (e) { panel(`<h2>Done</h2>` + errLine(e.message) + '<p>You can close this tab; eject the card via your OS to be safe.</p>'); }
    finally { busy(false); }
  };
}
function go(step) { S.step = step; renderNav(); if (step === 'menu') { showMenu(); } else if (step === 'favorites') { showFavorites(); } else if (step === 'activity') { showActivity(); } else if (step === 'profiles') { showProfiles(); } else { RENDER[step](); } }

/* ---- Setup profiles: export this card's setup; import one onto a fresh card ---- */
function showProfiles() {
  panel(`<h2>💾 Setup profiles</h2>
    <p class="meta">A profile records this card's <strong>installed cores</strong>, <strong>ROM source folders</strong> and <strong>favourites</strong> — references only, no ROMs or BIOS — so you can reproduce the setup on another card or after a reformat.</p>
    <div class="card"><strong>Export</strong>
      <div class="row"><button id="pf-export">Download this card's profile (.json)</button></div></div>
    <div class="card"><strong>Import</strong>
      <p class="meta">Installs the profile's cores, restores the ROM folder list and favourites.</p>
      <label class="row"><input type="file" id="pf-file" accept="application/json,.json"></label>
      <label class="row"><input type="checkbox" id="pf-rescan"> Also copy ROMs now from the restored source folders</label>
      <div class="row"><button id="pf-import">Import profile</button></div>
      <div id="pf-out"></div></div>`);
  $('#pf-export').onclick = async () => {
    busy(true);
    try {
      const p = await api('/api/profile/export');
      const blob = new Blob([JSON.stringify(p, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a'); a.href = url; a.download = 'pocketprep-profile.json';
      document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url);
    } catch (e) { $('#pf-out').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  $('#pf-import').onclick = async () => {
    const f = ($('#pf-file').files || [])[0];
    if (!f) { $('#pf-out').innerHTML = errLine('Choose a profile .json file first.'); return; }
    busy(true); $('#pf-out').innerHTML = inProgress('Importing profile (installing cores, restoring config)');
    try {
      const profile = JSON.parse(await f.text());
      const r = await api('/api/profile/import', 'POST', { profile, rescan: $('#pf-rescan').checked });
      const cores = r.CoreResult ? `${r.CoreResult.InstalledCount}/${r.CoreResult.Requested} cores installed` : `${r.CoresRequested} core(s) requested`;
      const rescan = r.RescanResult ? `; ${r.RescanResult.TotalCopied} ROM(s) copied` : '';
      $('#pf-out').innerHTML = `<p class="ok">Imported: ${cores}, ${r.RomSourcesRestored} source folder(s), ${r.FavoritesRestored} favourite set(s)${rescan}${r.DryRun ? ' [dry-run]' : ''}.</p>`;
      refreshSpace();
    } catch (e) { $('#pf-out').innerHTML = errLine(e.message); } finally { busy(false); }
  };
}

/* ---- Favourites: tag ROMs; surfaced in a per-system Favorites folder ---- */
async function showFavorites() {
  panel('<h2>⭐ Favourites</h2><p>Loading…</p>');
  let sum, favs;
  try { sum = await api('/api/card-summary'); favs = await api('/api/favorites'); }
  catch (e) { panel('<h2>⭐ Favourites</h2>' + errLine(e.message)); return; }
  const systems = sum.Roms.Systems || [];
  if (!systems.length) { panel('<h2>⭐ Favourites</h2><p class="warnote">No ROMs on the card yet — upload some first (🎮 Upload ROMs).</p>'); return; }
  // favMap: platformId -> array of original favourite names (preserved even when filtered out).
  const favMap = {}; (favs.Platforms || []).forEach(p => { favMap[p.PlatformId] = (p.Names || []).slice(); });
  const esc = v => (v || '').replace(/"/g, '&quot;');
  const opts = systems.map(s => `<option value="${esc(s.PlatformId)}">${s.DisplayName} (${s.FileCount})</option>`).join('');
  panel(`<h2>⭐ Favourites</h2>
    <p class="meta">Tag ROMs as favourites. They appear in a per-system <strong>!Favorites</strong> folder (sorted to the top of the menu) — symlinked where the filesystem allows, otherwise copied — while the original stays in place.</p>
    <p class="warnote">On a FAT32/exFAT card (a real Pocket card) favourites are <strong>copies</strong>: they use extra space and the copy has its own save file.</p>
    <label class="row">System: <select id="fav-plat">${opts}</select></label>
    <div id="fav-current" class="meta"></div>
    <label class="row">Filter: <input type="text" id="fav-filter" placeholder="type to filter the list">
      <label class="row" style="margin-left:.5rem"><input type="checkbox" id="fav-only"> favourited only</label></label>
    <div id="fav-list" class="list" style="max-height:50vh;overflow:auto;border:1px solid var(--line);border-radius:8px;padding:.5rem"></div>
    <div class="row"><button id="fav-save">Save favourites</button>
      <button id="fav-syncsaves" class="secondary" title="Reconcile save data between favourites and their originals (newest wins; original is the master)">Sync saves now</button>
      <span id="fav-count" class="meta"></span></div>
    <div id="fav-out"></div>`);
  let names = [];
  let selected = new Map();   // lowercase -> original name, for the current platform
  const curPlat = () => $('#fav-plat').value;
  const updateCurrent = () => {
    const cur = [...selected.values()].sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
    $('#fav-current').innerHTML = cur.length
      ? `<strong>★ Current favourites (${cur.length}):</strong> ${cur.map(esc).join(', ')}`
      : '<em>No favourites tagged for this system yet.</em>';
    $('#fav-count').textContent = `${selected.size} favourite(s)`;
  };
  const renderList = () => {
    const filt = ($('#fav-filter').value || '').toLowerCase();
    const onlyFav = !!($('#fav-only') || {}).checked;
    // Favourited games sort to the TOP (and are always shown), so they're obvious.
    const matches = names.filter(n => (!filt || n.toLowerCase().includes(filt)) && (!onlyFav || selected.has(n.toLowerCase())));
    const isFav = n => selected.has(n.toLowerCase());
    matches.sort((a, b) => (isFav(b) - isFav(a)) || a.toLowerCase().localeCompare(b.toLowerCase()));
    const shown = matches.slice(0, 1000);
    $('#fav-list').innerHTML = shown.length
      ? shown.map(n => `<label class="row"><input type="checkbox" class="fav-pick" data-n="${esc(n)}" ${isFav(n) ? 'checked' : ''}> ${isFav(n) ? '★ ' : ''}${n}</label>`).join('')
      : '<p class="meta">(no matching ROMs)</p>';
    document.querySelectorAll('.fav-pick').forEach(c => c.onchange = () => {
      const n = c.dataset.n; const k = n.toLowerCase();
      if (c.checked) selected.set(k, n); else selected.delete(k);
      updateCurrent();
    });
    updateCurrent();
  };
  const loadPlat = async () => {
    selected = new Map((favMap[curPlat()] || []).map(n => [n.toLowerCase(), n]));
    $('#fav-list').innerHTML = '<p>Loading…</p>';
    try { names = (await api('/api/rom/list', 'POST', { platformId: curPlat() })).names || []; }
    catch (e) { $('#fav-list').innerHTML = errLine(e.message); return; }
    renderList();
  };
  $('#fav-plat').onchange = loadPlat;
  $('#fav-filter').oninput = renderList;
  $('#fav-only').onchange = renderList;
  $('#fav-save').onclick = async () => {
    const plat = curPlat(); const picked = [...selected.values()];
    busy(true); $('#fav-out').innerHTML = '<p>Saving & syncing…</p>';
    try {
      const r = await api('/api/favorites', 'POST', { platformId: plat, names: picked });
      favMap[plat] = picked;
      const s = r.sync, miss = (s.Missing || []).length ? `; ${s.Missing.length} not found` : '';
      const sv = s.SaveSync, svNote = sv && (sv.LinkedCount + sv.CopiedToFavorite + sv.CopiedToOriginal + sv.FoldedBackCount) > 0
        ? ` Saves synced (${sv.Method}): ${sv.LinkedCount} linked, ${sv.CopiedToFavorite}→favourite, ${sv.CopiedToOriginal}→original, ${sv.FoldedBackCount} folded back.` : '';
      $('#fav-out').innerHTML = `<p class="ok">${picked.length} favourite(s) saved — ${s.Method} (${s.LinkedCount} linked, ${s.CopiedCount} copied, ${s.RemovedCount} removed${miss})${s.DryRun ? ' [dry-run]' : ''}.${svNote}</p>`;
      renderList();
    } catch (e) { $('#fav-out').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  // Re-sync save data without changing the favourites list (e.g. after a play session).
  $('#fav-syncsaves').onclick = async () => {
    busy(true); $('#fav-out').innerHTML = '<p>Syncing save data…</p>';
    try {
      const sv = await api('/api/favorites/sync-saves', 'POST', { platformId: curPlat() });
      $('#fav-out').innerHTML = `<p class="ok">Saves synced (${sv.Method}): ${sv.LinkedCount} linked, ${sv.CopiedToFavorite} copied to favourites, ${sv.CopiedToOriginal} copied to originals, ${sv.FoldedBackCount} folded back; ${sv.BackupCount} backup(s) in pocketprep/save-backups${sv.DryRun ? ' [dry-run]' : ''}.</p>`;
    } catch (e) { $('#fav-out').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  loadPlat();
}

/* ---- Step 0: Target ---- */
async function stepTarget() {
  panel('<h2>1. Choose the SD card</h2><p>Loading drives…</p>');
  let drives = [], candidates = [];
  try { const d = await api('/api/drives'); drives = d.drives || []; candidates = d.candidates || []; } catch (e) { /* ignore */ }
  const hint = (drives.length === 0 && candidates.length > 0)
    ? `<p class="warnote">No removable drives found, but these fixed drives look like they could be your SD card (some readers report cards as fixed): ${candidates.map(c => `${c.RootPath} (${c.FileSystem}, ${(c.SizeBytes / 1073741824).toFixed(0)} GB)`).join('; ')}. Tick "advanced" below to select one.</p>`
    : '';
  // Selectable list = removable drives + likely-card fixed candidates (the latter need
  // the advanced override to actually be used).
  const listDrives = drives.concat(candidates.filter(c => !drives.some(d => d.RootPath === c.RootPath)));
  const rows = listDrives.map((d, i) => `
    <li><input type="radio" name="drv" id="drv${i}" value="${i}">
      <label for="drv${i}"><strong>${d.RootPath || d.DriveLetter}</strong>
      <span class="meta">${d.Label || '(no label)'} · ${d.FileSystem || '?'} · ${fmtGB(d.SizeBytes)} (${fmtGB(d.FreeBytes)} free)</span>
      <span class="tag ${d.IsRemovable ? 'rm' : 'fixed'}">${d.IsRemovable ? 'removable' : 'FIXED'}</span></label></li>`).join('');
  panel(`
    <h2>1. Choose the SD card</h2>
    ${hint}
    ${listDrives.length ? `<ul class="list">${rows}</ul>` : '<p class="warnote">No removable drives detected.</p>'}
    <label class="row"><input type="checkbox" id="adv"> Advanced: allow a non-removable drive (the system disk is never allowed)</label>
    <div class="card">
      <label class="row"><input type="checkbox" id="tm"> Use a test folder instead of a real card</label>
      <label class="row">Folder: <input type="text" id="tmpath" placeholder="e.g. C:\\Temp\\PocketSDTest or /tmp/PocketSDTest"></label>
    </div>
    <div id="terr"></div>
    <button id="useBtn">Use this target →</button>`);
  window.__drives = listDrives;
  $('#useBtn').onclick = onUseTarget;
}
async function onUseTarget() {
  $('#terr').innerHTML = ''; busy(true);
  try {
    const tm = $('#tm').checked;
    let body;
    if (tm) {
      const p = $('#tmpath').value.trim();
      if (!p) { $('#terr').innerHTML = errLine('Enter a test folder path.'); return; }
      body = { testMode: true, rootPath: p };
    } else {
      const sel = document.querySelector('input[name=drv]:checked');
      if (!sel) { $('#terr').innerHTML = errLine('Select a drive, or use a test folder.'); return; }
      S.drive = window.__drives[+sel.value];
      body = { drive: S.drive, allowOverride: $('#adv').checked };
    }
    const r = await api('/api/target', 'POST', body);
    S.health = await api('/api/health'); setCtx();
    refreshSpace(); wireEject();
    go('menu');
  } catch (e) {
    const reasons = e.data && e.data.verdict && e.data.verdict.Reasons ? '<ul>' + e.data.verdict.Reasons.map(x => `<li>${x}</li>`).join('') + '</ul>' : '';
    $('#terr').innerHTML = errLine(e.message) + reasons;
  } finally { busy(false); }
}

/* ---- Step 1: Card checks ---- */
function cardBreakdownHtml(sum) {
  // Compact "what's already on this card" panel for returning users.
  const fw = sum.Firmware.Present ? `v${sum.Firmware.Version} (${sum.Firmware.FileName})` : 'none';
  const roms = (sum.Roms.Systems || []).length
    ? (sum.Roms.Systems.map(s => `${s.DisplayName} ${s.FileCount}`).join(', '))
    : 'none';
  const cfg = sum.Config.Exists ? `${sum.Config.SourceCount} saved folder(s)` : 'no saved folder list';
  // BIOS-dependent systems (e.g. Neo Geo) whose BIOS is missing. The tool never downloads
  // copyrighted BIOS — it only flags what the user must supply themselves.
  // Required files each installed core declares but is missing (data.json-driven) — the
  // authoritative "what do I still need" signal. Covers BIOS-needing cores generally.
  const reqMissing = (sum.RequiredFiles || []).filter(c => !c.Satisfied);
  const reqNote = reqMissing.length
    ? `<li class="warnote">Required files missing: ${reqMissing.map(c => `${c.Identifier} needs ${c.Missing.join(', ')}`).join('; ')} — place your own under Assets/&lt;platform&gt;/common; this tool never downloads BIOS/ROMs.</li>`
    : '';
  // Fall back to the systems-manifest BIOS check for platforms not already covered above.
  const covered = new Set(reqMissing.map(c => String(c.PlatformId).toLowerCase()));
  const biosMissing = (sum.Bios || []).filter(b => !b.Satisfied && !covered.has(String(b.PlatformId).toLowerCase()));
  const biosNote = biosMissing.length
    ? `<li class="warnote">BIOS needed: ${biosMissing.map(b => `${b.DisplayName} (missing ${b.Missing.join(', ')})`).join('; ')} — supply your own; this tool never downloads BIOS.</li>`
    : '';
  // BIOS upload: every missing declared requirement (installed-core data.json slots +
  // manifest biosRequired systems), deduped — and nothing else, so this path can only
  // ever fill genuinely required slots.
  const biosTargets = [];
  const seenBios = new Set();
  (sum.RequiredFiles || []).forEach(c => (c.Required || []).forEach(r => {
    if (r.Found) return;
    const k = `${String(c.PlatformId).toLowerCase()}|${String(r.Filename).toLowerCase()}`;
    if (!seenBios.has(k)) { seenBios.add(k); biosTargets.push({ plat: c.PlatformId, file: r.Filename, by: c.Identifier }); }
  }));
  (sum.Bios || []).forEach(b => (b.Missing || []).forEach(f => {
    const k = `${String(b.PlatformId).toLowerCase()}|${String(f).toLowerCase()}`;
    if (!seenBios.has(k)) { seenBios.add(k); biosTargets.push({ plat: b.PlatformId, file: f, by: b.DisplayName }); }
  }));
  const biosPanel = biosTargets.length ? `
    <details class="card" style="margin-top:.6rem" open><summary><strong>Install BIOS / required files</strong> — ${biosTargets.length} missing</summary>
      <p class="meta">These cores declare files they need to run. Point each at the copy <strong>you own</strong> — it's renamed to the exact expected filename and placed in the declared slot. This tool never downloads BIOS.</p>
      ${biosTargets.map((t, i) => `<div class="row" data-bios-row="${i}">
        <span><strong>${t.file}</strong> <span class="meta">(${t.plat} · needed by ${t.by})</span></span>
        <input type="text" id="bios-src-${i}" placeholder="path to your ${t.file}">
        <button data-bios="${i}" class="secondary">Install BIOS</button></div>
        <div id="bios-out-${i}"></div>`).join('')}
    </details>` : '';
  S.biosTargets = biosTargets;   // for the wire-up after the panel is injected
  const anything = sum.Firmware.Present || sum.Cores.Count > 0 || sum.Roms.TotalFiles > 0;
  if (!anything && !sum.Config.Exists) return '';
  // Used card with ROMs but no saved config -> offer to onboard (generate the config).
  const canOnboard = sum.Roms.TotalFiles > 0 && !sum.Config.Exists;
  const onboardBtn = canOnboard ? `<button id="onboard">Onboard this card (generate config)</button>` : '';
  // Library Organizer (separate maintenance tool): multiselect the platforms with ROMs and
  // split each core's library into subfolders so no folder exceeds the per-folder game limit.
  const romSystems = sum.Roms.Systems || [];
  const organizer = romSystems.length ? `
    <details class="card" style="margin-top:.6rem"><summary><strong>Organize library into folders</strong> — keep each core under the per-folder game limit (~1300)</summary>
      <p class="meta">Select the cores to reorganize; each is split into alphabetical subfolders. Move-only — nothing is deleted.</p>
      <div id="org-list">${romSystems.map(s => `<label class="row"><input type="checkbox" class="org-pick" value="${s.PlatformId}"> ${s.DisplayName} <span class="meta">(${s.FileCount} ROMs)</span></label>`).join('')}</div>
      <label class="row">Max games per folder: <input type="number" id="org-cap" value="1000" min="1" style="min-width:6rem"></label>
      <label class="row"><input type="checkbox" id="org-shorten"> Shorten overlong filenames to <input type="number" id="org-namelen" value="100" min="16" max="255" style="min-width:5rem"> chars</label>
      <div class="row"><button id="org-preview" class="secondary">Preview</button><button id="org-run">Organize selected</button></div>
      <div id="org-out"></div>
    </details>` : '';
  // Region-priority duplicate finder (1G1R-style): recommends which region variants to drop.
  const deduper = romSystems.length ? `
    <details class="card" style="margin-top:.6rem"><summary><strong>De-duplicate by region</strong> — recommend which region variants to remove</summary>
      <p class="meta">Finds the same game in multiple regions (e.g. USA / Europe / Japan) and recommends keeping your preferred region. Apply moves the rest to a reversible quarantine (<code>pocketprep/quarantine</code>) — nothing is deleted.</p>
      <label class="row">System: <select id="dd-plat">${romSystems.map(s => `<option value="${s.PlatformId}">${s.DisplayName} (${s.FileCount})</option>`).join('')}</select></label>
      <label class="row">Region priority (drag-free: comma list): <input type="text" id="dd-order" value="USA,EU,JPN,Global" style="min-width:12rem"></label>
      <div class="row"><button id="dd-preview" class="secondary">Preview recommendations</button><button id="dd-run">Quarantine duplicates</button></div>
      <div id="dd-out"></div>
    </details>` : '';
  // Maintenance / cleanup: report leftovers; remove only empty + temp dirs.
  const cleaner = `
    <details class="card" style="margin-top:.6rem"><summary><strong>Maintenance &amp; cleanup</strong> — leftovers, empty folders, integrity</summary>
      <p class="meta">Scans for unmanaged cores, orphan asset folders, empty folders and the tool's own temp files. Removal only ever clears <strong>empty</strong> and temp folders — never a ROM, save or core.</p>
      <div class="row"><button id="cl-scan" class="secondary">Scan</button><button id="cl-run">Remove empty &amp; temp folders</button></div>
      <div id="cl-out"></div>
    </details>`;
  return `<div class="card"><strong>Already on this card</strong>
    <ul class="list" style="margin-top:.4rem">
      <li>Firmware: ${fw}</li>
      <li>Cores: ${sum.Cores.Count}</li>
      <li>ROMs: ${sum.Roms.TotalFiles} total — ${roms}</li>
      <li>ROM config: ${cfg}</li>
      ${reqNote}
      ${biosNote}
    </ul>
    <div class="row" style="margin-top:.5rem">
      ${onboardBtn}
      <button id="manageroms" class="secondary">${sum.Config.Exists ? 'Rescan / modify ROM folders →' : 'Manage ROM folders →'}</button>
    </div><div id="onboardout"></div>
    ${biosPanel}
    ${organizer}
    ${deduper}
    ${cleaner}</div>`;
}

async function stepCard() {
  panel('<h2>2. Card checks</h2><p>Checking…</p>');
  let html = '<h2>2. Card checks</h2>';
  // Breakdown of existing content first, so returning users can jump straight to rescan.
  let breakdown = '';
  try { breakdown = cardBreakdownHtml(await api('/api/card-summary')); } catch { /* non-fatal */ }
  html += breakdown;
  const wireManage = () => {
    if ($('#manageroms')) $('#manageroms').onclick = () => go(5);
    if ($('#onboard')) $('#onboard').onclick = async () => {
      busy(true);
      $('#onboardout').innerHTML = `<p>Scanning the card and generating a config…</p>`;
      try { const r = await api('/api/card/onboard', 'POST', {});
        const extra = r.UnmappedCount ? ` (${r.UnmappedCount} platform(s) had no matching system and were skipped)` : '';
        $('#onboardout').innerHTML = `<p class="ok">Onboarded: registered ${r.DetectedCount} system(s) from the card${extra}. Open ROM folders to point them at your library or rescan.</p>`;
        if ($('#onboard')) $('#onboard').disabled = true;
      } catch (e) { $('#onboardout').innerHTML = errLine(e.message); } finally { busy(false); }
    };
    // Library Organizer: preview (dry-run) or run the subfoldering for each selected platform.
    const orgPicks = () => Array.from(document.querySelectorAll('.org-pick:checked')).map(c => c.value);
    const orgCap = () => Math.max(1, parseInt(($('#org-cap') || {}).value, 10) || 1000);
    const orgShorten = () => !!($('#org-shorten') || {}).checked;
    const orgNameLen = () => Math.min(255, Math.max(16, parseInt(($('#org-namelen') || {}).value, 10) || 100));
    const orgRun = async (dry) => {
      const picks = orgPicks();
      if (!picks.length) { $('#org-out').innerHTML = errLine('Select at least one core.'); return; }
      busy(true); $('#org-out').innerHTML = `<p>${dry ? 'Previewing' : 'Organizing'}…</p>`;
      try {
        const lines = [];
        for (const platformId of picks) {
          const body = { platformId, maxPerFolder: orgCap(), shortenNames: orgShorten(), maxFileNameLength: orgNameLen() };
          if (dry) {
            const p = await api('/api/rom/organize/plan', 'POST', body);
            const ren = p.RenamedCount ? `, ${p.RenamedCount} rename(s)` : '';
            lines.push(`${platformId}: ${p.FileCount} ROMs → ${p.NeedsBuckets ? `${p.BucketCount} folder(s) (${p.MoveCount} move(s))` : 'fits in one folder'}${ren}`);
          } else {
            const r = await api('/api/rom/organize', 'POST', body);
            lines.push(`${platformId}: moved ${r.MovedCount} (${r.RenamedCount} renamed), skipped ${r.SkippedCount}, failed ${r.FailedCount}${r.DryRun ? ' [dry-run]' : ''}`);
          }
        }
        $('#org-out').innerHTML = `<p class="${dry ? '' : 'ok'}">${lines.join('<br>')}</p>`;
      } catch (e) { $('#org-out').innerHTML = errLine(e.message); } finally { busy(false); }
    };
    if ($('#org-preview')) $('#org-preview').onclick = () => orgRun(true);
    if ($('#org-run')) $('#org-run').onclick = () => orgRun(false);

    // Region-priority de-duplication.
    const ddOrder = () => (($('#dd-order') || {}).value || 'USA,EU,JPN,Global').split(',').map(s => s.trim().toUpperCase()).filter(Boolean);
    const ddRun = async (apply) => {
      const platformId = ($('#dd-plat') || {}).value; if (!platformId) return;
      const body = { platformId, regionOrder: ddOrder() };
      busy(true); $('#dd-out').innerHTML = `<p>${apply ? 'Quarantining duplicates' : 'Scanning for region duplicates'}…</p>`;
      try {
        if (!apply) {
          const p = await api('/api/rom/dedupe/plan', 'POST', body);
          if (!p.RemoveCount) { $('#dd-out').innerHTML = `<p class="ok">No region duplicates found for ${platformId}.</p>`; return; }
          const rows = (p.Sets || []).slice(0, 50).map(s => `<li>Keep <strong>${s.Keep.Name}</strong>; remove ${s.Remove.map(x => x.Name).join(', ')}</li>`).join('');
          $('#dd-out').innerHTML = `<p class="warnote">${p.RemoveCount} duplicate(s) recommended for removal (${(p.ReclaimBytes / 1048576).toFixed(1)} MB), keeping your preferred region:</p><ul class="list">${rows}</ul>`;
        } else {
          const r = await api('/api/rom/dedupe', 'POST', body);
          $('#dd-out').innerHTML = `<p class="ok">Quarantined ${r.MovedCount} duplicate(s) to ${r.QuarantineDir}${r.DryRun ? ' [dry-run]' : ''}. Nothing was deleted — restore from there if needed.</p>`;
          refreshSpace();
        }
      } catch (e) { $('#dd-out').innerHTML = errLine(e.message); } finally { busy(false); }
    };
    if ($('#dd-preview')) $('#dd-preview').onclick = () => ddRun(false);
    if ($('#dd-run')) $('#dd-run').onclick = () => ddRun(true);

    // Maintenance / cleanup.
    const renderCleanup = (c) => {
      const parts = [];
      if ((c.UnmanagedCores || []).length) parts.push(`<li class="meta">Unmanaged cores (not in catalog, won't auto-update): ${c.UnmanagedCores.join(', ')}</li>`);
      if ((c.OrphanAssetPlatforms || []).length) parts.push(`<li class="warnote">ROMs for platforms with no installed core: ${c.OrphanAssetPlatforms.map(o => `${o.PlatformId} (${o.FileCount})`).join(', ')} — install the matching core, or they won't load. (Not removed.)</li>`);
      if (c.SaveStateCount) parts.push(`<li class="meta">${c.SaveStateCount} save-state file(s) under Memories (left untouched).</li>`);
      const removable = (c.RemovableDirCount != null) ? c.RemovableDirCount : ((c.EmptyDirs || []).length + (c.ProbeDirs || []).length);
      parts.push(`<li>${removable} empty/temp folder(s) can be removed.</li>`);
      return `<ul class="list">${parts.join('')}</ul>`;
    };
    if ($('#cl-scan')) $('#cl-scan').onclick = async () => {
      busy(true); $('#cl-out').innerHTML = '<p>Scanning…</p>';
      try { $('#cl-out').innerHTML = renderCleanup(await api('/api/cleanup')); }
      catch (e) { $('#cl-out').innerHTML = errLine(e.message); } finally { busy(false); }
    };
    if ($('#cl-run')) $('#cl-run').onclick = async () => {
      busy(true); $('#cl-out').innerHTML = '<p>Removing empty &amp; temp folders…</p>';
      try { const r = await api('/api/cleanup', 'POST', {});
        $('#cl-out').innerHTML = `<p class="ok">Removed ${r.RemovedCount} empty/temp folder(s)${r.DryRun ? ' [dry-run]' : ''}. No ROMs, saves or cores were touched.</p>` + renderCleanup(r);
        refreshSpace();
      } catch (e) { $('#cl-out').innerHTML = errLine(e.message); } finally { busy(false); }
    };

    // BIOS upload: place a user-supplied file into the declared slot (renamed to the
    // exact expected filename). Only declared requirements are offered/accepted.
    document.querySelectorAll('button[data-bios]').forEach(btn => btn.onclick = async () => {
      const i = +btn.dataset.bios, t = (S.biosTargets || [])[i];
      const out = $('#bios-out-' + i), src = ($('#bios-src-' + i) || {}).value;
      if (!t) return;
      if (!src || !src.trim()) { out.innerHTML = errLine(`Enter the path to your ${t.file}.`); return; }
      busy(true); out.innerHTML = `<p>Placing ${t.file}…</p>`;
      try {
        const r = await api('/api/bios/install', 'POST', { platformId: t.plat, fileName: t.file, sourceFile: src.trim() });
        out.innerHTML = r.Installed
          ? `<p class="ok">${r.FileName} placed at ${r.Destination}${r.Renamed ? ' (renamed from your file)' : ''}${r.DryRun ? ' [dry-run]' : ''}.</p>`
          : `<p class="warnote">${r.Message || 'Not installed.'}</p>`;
      } catch (e) { out.innerHTML = errLine(e.message); } finally { busy(false); }
    });
  };
  try {
    if (S.drive && S.drive.FileSystem) {
      const fs = await api('/api/filesystem', 'POST', { fileSystem: S.drive.FileSystem });
      html += `<p>Filesystem <strong>${fs.FileSystem}</strong>: ${fs.Acceptable ? '<span class="ok">acceptable</span>' : '<span class="error">not acceptable</span>'}</p>`;
      if (fs.Remediation) html += `<p class="warnote">${fs.Remediation}</p>`;
    }
    const empty = await api('/api/empty');
    if (empty.IsEmpty) {
      html += '<p class="ok">Card appears empty — good.</p>';
      html += '<button id="c">Continue →</button>';
      panel(html); $('#c').onclick = () => go(2); wireManage(); return;
    }
    html += `<p class="warnote">Card is NOT empty (${empty.EntryCount} item(s)). Nothing will be deleted.</p>`;
    html += '<ul class="list">' + empty.Entries.slice(0, 12).map(x => `<li>${x}</li>`).join('') + '</ul>';
    if (empty.Entries.includes('Saves')) {
      html += `<div class="card"><strong>Back up existing Saves</strong>
        <div class="row"><input type="text" id="bdest" placeholder="backup destination folder">
        <label class="row"><input type="checkbox" id="bmem"> include Memories</label>
        <button id="bbtn" class="secondary">Back up</button></div><div id="bout"></div></div>`;
    }
    html += '<label class="row"><input type="checkbox" id="ok"> I understand; leave existing files in place and continue</label>';
    html += '<button id="c" disabled>Continue →</button>';
    panel(html);
    wireManage();
    $('#ok').onchange = (e) => { $('#c').disabled = !e.target.checked; };
    $('#c').onclick = () => go(2);
    if ($('#bbtn')) $('#bbtn').onclick = async () => {
      const d = $('#bdest').value.trim(); if (!d) { $('#bout').innerHTML = errLine('Enter a destination.'); return; }
      busy(true);
      try { const r = await api('/api/saves/backup', 'POST', { destination: d, includeMemories: $('#bmem').checked });
        $('#bout').innerHTML = `<p class="ok">Backed up ${r.FileCount} file(s) to ${r.Destination}${r.DryRun ? ' [dry-run]' : ''}.</p>`;
      } catch (e) { $('#bout').innerHTML = errLine(e.message); } finally { busy(false); }
    };
  } catch (e) { panel(html + errLine(e.message) + '<button id="c">Continue →</button>'); $('#c').onclick = () => go(2); wireManage(); }
}

/* ---- Step 2: Firmware ---- */
async function stepFirmware() {
  panel('<h2>3. Firmware</h2><p>Loading…</p>');
  let rel, age;
  try { const f = await api('/api/firmware'); rel = f.release; age = f.age; } catch (e) { panel('<h2>3. Firmware</h2>' + errLine(e.message) + '<button id="s">Skip →</button>'); $('#s').onclick = () => go(3); return; }
  const stale = age && age.Stale ? `<p class="warnote">This firmware data is ${age.AgeDays} days old; a newer Pocket firmware may exist. Check <a href="https://www.analogue.co/support/pocket/firmware" target="_blank" rel="noopener">analogue.co</a> and install it via offline mode if newer.</p>` : '';
  panel(`
    <h2>3. Firmware</h2>
    <p>Latest: <strong>v${rel.version}</strong> (${rel.releaseDate}). It will be placed at the card root and verified by MD5.</p>
    ${stale}
    <button id="dl">Download &amp; install</button>
    <div class="card"><label class="row">Or install a file you already downloaded:
      <input type="text" id="lf" placeholder="path to pocket_firmware_*.bin"></label>
      <button id="off" class="secondary">Install local file</button></div>
    <button id="skip" class="secondary">Skip firmware →</button>
    <div id="fout"></div>`);
  const done = (r) => { S.firmware = r; $('#fout').innerHTML = `<p class="ok">Firmware v${r.Version} → ${r.FileName}${r.Md5Verified ? ' (MD5 verified)' : ''}${r.DryRun ? ' [dry-run]' : ''}</p><button id="c">Continue →</button>`; $('#c').onclick = () => go(3); };
  $('#dl').onclick = async () => { busy(true); $('#fout').innerHTML = inProgress('Downloading &amp; installing firmware (~52 MB)'); try { done(await api('/api/firmware/install', 'POST', { mode: 'download' })); } catch (e) { $('#fout').innerHTML = errLine(e.message); } finally { busy(false); } };
  $('#off').onclick = async () => { const p = $('#lf').value.trim(); if (!p) return; busy(true); $('#fout').innerHTML = inProgress('Installing firmware'); try { done(await api('/api/firmware/install', 'POST', { mode: 'offline', localFile: p })); } catch (e) { $('#fout').innerHTML = errLine(e.message); } finally { busy(false); } };
  $('#skip').onclick = () => go(3);
}

/* ---- Step 3: Folders ---- */
async function stepFolders() {
  panel('<h2>4. Folder structure</h2><button id="mk">Create openFPGA folders</button><button id="skip" class="secondary">Skip →</button><div id="oout"></div>');
  $('#skip').onclick = () => go(4);
  $('#mk').onclick = async () => {
    busy(true);
    try { const r = await api('/api/folders', 'POST', {}); S.folder = r;
      $('#oout').innerHTML = `<p class="ok">Created: ${r.Created.join(', ') || '(none)'}${r.DryRun ? ' [dry-run]' : ''}. Already present: ${r.Existing.length}.</p><button id="c">Continue →</button>`;
      $('#c').onclick = () => go(4);
    } catch (e) { $('#oout').innerHTML = errLine(e.message); } finally { busy(false); }
  };
}

/* ---- Step 4: Cores ---- */
async function stepCores() {
  panel('<h2>5. openFPGA cores (optional)</h2><p>Loading…</p>');
  let cores = [], installed = [];
  try { cores = (await api('/api/cores')).cores || []; } catch {}
  try { installed = (await api('/api/installed-cores')).cores || []; } catch {}
  const instById = {}; installed.forEach(ic => { instById[ic.Identifier] = ic; });
  const instLine = installed.length
    ? `<p>Already installed: ${installed.map(ic => `${ic.Identifier} <span class="meta">v${ic.Version}</span>`).join(', ')}</p>`
    : '<p class="meta">No cores installed yet.</p>';
  const esc = v => (v || '').replace(/"/g, '&quot;');
  const rows = cores.map((c, i) => {
    const have = instById[c.Identifier];
    const hay = `${c.DisplayName} ${c.Identifier} ${c.Owner || ''} ${(c.PlatformIds || []).join(' ')}`.toLowerCase();
    return `<div class="card core-row" data-hay="${esc(hay)}">
      <label class="row"><input type="checkbox" class="core-pick" value="${i}"> <strong>${c.DisplayName}</strong></label>
      <span class="meta">${c.Identifier}${c.Owner ? ' · ' + c.Owner : ''}${(c.PlatformIds || []).length ? ' · ' + c.PlatformIds.join(',') : ''}</span>
      ${have ? `<span class="tag rm">installed v${have.Version}</span>` : ''}
      ${c.BiosRequired ? '<span class="tag fixed">BIOS needed</span>' : ''}
      <div class="row">
        <button data-i="${i}" data-mode="download" data-ow="${have ? 1 : 0}">${have ? 'Reinstall / update' : 'Download & install'}</button>
        <input type="text" id="cz${i}" placeholder="or path to ${c.Identifier} .zip">
        <button data-i="${i}" data-mode="offline" data-ow="${have ? 1 : 0}" class="secondary">Install local zip</button>
        <button data-repair="${esc(c.Id)}" class="secondary" title="Re-download & reinstall this core's files (ROMs and saves are untouched)">Repair</button>
      </div><div id="cout${i}"></div></div>`;
  }).join('');
  panel(`<h2>5. openFPGA cores (optional)</h2>
    <p class="warnote">Cores are made by independent authors under their own licences.</p>
    ${instLine}
    <div class="card"><strong>Install cores</strong>
      <p class="meta">${cores.length} cores in the catalog. Filter, tick the ones you want, and install the selection — or install everything (large download).</p>
      <label class="row">Filter: <input type="text" id="core-filter" placeholder="name, author or platform"></label>
      <div class="row">
        <button id="instSel">Install selected (<span id="selN">0</span>)</button>
        <button id="instAll" class="secondary">Install ALL ${cores.length}</button>
        <button id="selAll" class="secondary">Select all (filtered)</button>
        <button id="selNone" class="secondary">Clear</button>
      </div><div id="allout"></div></div>
    <p><button id="chk" class="secondary">Check for updates</button>
       <button id="updall" class="secondary">Update all</button>
       <button id="integ" class="secondary">Check integrity</button>
       <span id="updout" class="meta"></span></p>
    <details class="card"><summary><strong>Install a core you supply</strong> — e.g. jotego's Neo Geo Pocket Color beta</summary>
      <p class="meta">Some cores aren't publicly downloadable — notably <strong>jotego's beta cores</strong> (Neo Geo Pocket Color, CPS, …), distributed to supporters via
        <a href="https://www.patreon.com/jotego" target="_blank" rel="noopener">jotego's Patreon</a>. Get the core zip there, then install it here:
        it's validated (openFPGA structure, zip-slip-safe) and merged non-destructively like any other core. After install, its system appears in the ROM step automatically.</p>
      <label class="row">Core zip: <input type="text" id="byo-zip" placeholder="path to the core .zip you obtained"></label>
      <label class="row"><input type="checkbox" id="byo-ow"> overwrite existing files (update an installed copy)</label>
      <div class="row"><button id="byo-install">Install supplied core</button></div>
      <div id="byo-out"></div></details>
    <details class="card"><summary><strong>Platform images</strong> — system artwork for the openFPGA menu (Platforms/_images)</summary>
      <p class="meta">Installs a platform image pack from a GitHub release you choose, or a local zip. The tool bundles none and picks no default — supply the source (check its licence). Only <code>Platforms/_images</code> is written.</p>
      <label class="row">GitHub owner: <input type="text" id="ip-owner" placeholder="e.g. someuser"></label>
      <label class="row">Repo: <input type="text" id="ip-repo" placeholder="image-pack repo"></label>
      <label class="row">…or local zip: <input type="text" id="ip-zip" placeholder="path to image-pack .zip"></label>
      <label class="row"><input type="checkbox" id="ip-ow"> overwrite existing images</label>
      <div class="row"><button id="ip-install">Install platform images</button></div>
      <div id="ip-out"></div></details>
    <div id="core-rows">${cores.length ? rows : '<p>No cores manifest available.</p>'}</div>
    <button id="c">Continue →</button>`);
  $('#c').onclick = () => go(5);

  // Search/filter + multi-select install.
  const pickEls = () => Array.from(document.querySelectorAll('.core-pick'));
  const selectedIds = () => pickEls().filter(c => c.checked).map(c => cores[+c.value].Id);
  const refreshCount = () => { $('#selN').textContent = pickEls().filter(c => c.checked).length; };
  const visibleRows = () => Array.from(document.querySelectorAll('.core-row')).filter(r => r.style.display !== 'none');
  $('#core-filter').oninput = () => {
    const q = $('#core-filter').value.trim().toLowerCase();
    document.querySelectorAll('.core-row').forEach(r => { r.style.display = (!q || r.dataset.hay.includes(q)) ? '' : 'none'; });
  };
  pickEls().forEach(c => c.onchange = refreshCount);
  $('#selAll').onclick = () => { visibleRows().forEach(r => { const cb = r.querySelector('.core-pick'); if (cb) cb.checked = true; }); refreshCount(); };
  $('#selNone').onclick = () => { pickEls().forEach(c => { c.checked = false; }); refreshCount(); };
  const installIds = async (ids, label) => {
    $('#allout').innerHTML = inProgress(`Downloading & installing ${label} (tip: set GITHUB_TOKEN if it rate-limits)`);
    busy(true);
    try {
      const r = await api('/api/cores/install-all', 'POST', (ids && ids.length) ? { ids } : {});
      let summary = `<p class="ok">Installed ${r.InstalledCount}/${r.Requested}; failed ${r.FailedCount}; skipped ${r.SkippedCount}${r.DryRun ? ' [dry-run]' : ''}.</p>`;
      if (r.RateLimited) summary += '<p class="warnote">GitHub rate limit reached — set GITHUB_TOKEN and retry to finish the rest.</p>';
      const fails = (r.Results || []).filter(x => x.Status === 'failed').slice(0, 8);
      if (fails.length) summary += '<p class="meta">Failed: ' + fails.map(x => `${x.Identifier} (${x.Error})`).join('; ') + '</p>';
      $('#allout').innerHTML = summary;
      refreshSpace();
    } catch (e) { $('#allout').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  $('#instSel').onclick = () => { const ids = selectedIds(); if (!ids.length) { $('#allout').innerHTML = errLine('Tick at least one core, or use Install ALL.'); return; } installIds(ids, `${ids.length} selected core(s)`); };
  $('#instAll').onclick = () => installIds(null, `all ${cores.length} cores`);
  $('#chk').onclick = async () => {
    $('#updout').textContent = 'checking…'; busy(true);
    try {
      const u = (await api('/api/cores/updates')).updates || [];
      $('#updout').innerHTML = u.length
        ? u.map(x => `${x.Identifier}: ${x.UpdateAvailable ? `<span class="warnote">update ${x.Installed}→${x.Latest}</span>` : `up to date (${x.Installed})`}`).join(' · ')
        : 'no installed cores from the manifest.';
    } catch (e) { $('#updout').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  $('#updall').onclick = async () => {
    $('#updout').innerHTML = inProgress('Downloading & installing core updates'); busy(true);
    try {
      const r = (await api('/api/cores/update-all', 'POST', {})).results || [];
      $('#updout').innerHTML = r.length
        ? r.map(x => `${x.Identifier}: <span class="ok">${x.Action} ${x.From}→${x.To}</span>`).join(' · ')
        : 'nothing to update.';
    } catch (e) { $('#updout').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  document.querySelectorAll('button[data-mode]').forEach(btn => btn.onclick = async () => {
    const i = +btn.dataset.i, mode = btn.dataset.mode, out = $('#cout' + i);
    const body = { coreId: cores[i].Id, mode };
    if (btn.dataset.ow === '1') body.overwrite = true;
    if (mode === 'offline') { const p = $('#cz' + i).value.trim(); if (!p) { out.innerHTML = errLine('Enter a zip path.'); return; } body.localZip = p; }
    busy(true); out.innerHTML = inProgress(`${mode === 'offline' ? 'Installing' : 'Downloading & installing'} ${cores[i].Identifier}`);
    try { const r = await api('/api/cores/install', 'POST', body); S.cores.push(r);
      out.innerHTML = `<p class="ok">${r.Identifier}: ${r.PlacedCount} placed, ${r.SkippedCount} skipped${r.Version ? ' (v' + r.Version + ')' : ''}${r.DryRun ? ' [dry-run]' : ''}</p>`;
    } catch (e) { out.innerHTML = errLine(e.message); } finally { busy(false); }
  });
  // Per-core Repair: re-download & reinstall the core's files (ROMs/saves untouched).
  document.querySelectorAll('button[data-repair]').forEach(btn => btn.onclick = async () => {
    const row = btn.closest('.core-row'); const out = row ? row.querySelector('[id^=cout]') : null;
    busy(true); if (out) out.innerHTML = inProgress(`Repairing ${btn.dataset.repair}`);
    try { const r = await api('/api/cores/repair', 'POST', { coreId: btn.dataset.repair });
      if (out) out.innerHTML = `<p class="ok">Repaired: ${r.PlacedCount} file(s) placed${r.Version ? ' (v' + r.Version + ')' : ''}${r.DryRun ? ' [dry-run]' : ''}. ROMs & saves untouched.</p>`;
    } catch (e) { if (out) out.innerHTML = errLine(e.message); } finally { busy(false); }
  });
  // Integrity check: list installed cores missing required definition files.
  $('#integ').onclick = async () => {
    $('#updout').textContent = 'checking…'; busy(true);
    try {
      const c = (await api('/api/cores/integrity')).cores || [];
      const bad = c.filter(x => !x.Ok);
      $('#updout').innerHTML = c.length
        ? (bad.length ? `<span class="warnote">${bad.length} core(s) look incomplete: ${bad.map(x => `${x.Identifier} (missing ${(x.Missing || []).join(', ') || 'core.json'})`).join('; ')} — use Repair.</span>` : `<span class="ok">All ${c.length} installed core(s) look intact.</span>`)
        : 'no cores installed.';
    } catch (e) { $('#updout').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  // Platform image pack install (user-supplied source).
  // Bring-your-own core (e.g. jotego's Patreon-distributed NGPC beta).
  $('#byo-install').onclick = async () => {
    const zip = $('#byo-zip').value.trim();
    if (!zip) { $('#byo-out').innerHTML = errLine('Enter the path to the core .zip you obtained.'); return; }
    busy(true); $('#byo-out').innerHTML = inProgress('Validating & installing your core');
    try { const r = await api('/api/cores/install-local', 'POST', { localZip: zip, overwrite: $('#byo-ow').checked });
      $('#byo-out').innerHTML = `<p class="ok">Core installed: ${r.PlacedCount} file(s) placed, ${r.SkippedCount} skipped${r.DryRun ? ' [dry-run]' : ''}. Its system now appears in the ROM step (and any required BIOS will be flagged on the card overview).</p>`;
    } catch (e) { $('#byo-out').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  $('#ip-install').onclick = async () => {
    const zip = $('#ip-zip').value.trim(), owner = $('#ip-owner').value.trim(), repo = $('#ip-repo').value.trim();
    const body = zip ? { mode: 'offline', localZip: zip } : { owner, repo };
    if (!zip && (!owner || !repo)) { $('#ip-out').innerHTML = errLine('Enter a GitHub owner + repo, or a local zip path.'); return; }
    if (body.overwrite = $('#ip-ow').checked) { /* set */ }
    busy(true); $('#ip-out').innerHTML = inProgress('Installing platform images');
    try { const r = await api('/api/cores/image-pack', 'POST', body);
      $('#ip-out').innerHTML = `<p class="ok">Platform images: ${r.PlacedCount} placed, ${r.SkippedCount} skipped${r.Version ? ' (' + r.Version + ')' : ''}${r.DryRun ? ' [dry-run]' : ''}.</p>`;
    } catch (e) { $('#ip-out').innerHTML = errLine(e.message); } finally { busy(false); }
  };
}

/* ---- Step 5: ROMs ---- */
async function stepRoms() {
  panel('<h2>6. ROM import</h2><p>Loading systems…</p>');
  let systems = [];
  try { systems = (await api('/api/systems')).systems || []; } catch (e) { panel('<h2>6. ROM import</h2>' + errLine(e.message)); }
  // Platforms declared by installed cores that the manifest doesn't know — so ROM import
  // works for any core you installed, not just the built-in systems (#128).
  let extra = [];
  try { extra = (await api('/api/rom/extra-platforms')).platforms || []; } catch { /* none */ }
  const extraIds = new Set(extra.map(x => x.Id));
  systems = systems.concat(extra);
  // A saved source mapping (if any) lets us prefill folders and offer a one-click rescan.
  let cfg = { Exists: false, Sources: [] };
  try { cfg = await api('/api/rom/config'); } catch { /* no config yet */ }
  const saved = {};
  (cfg.Sources || []).forEach(s => { saved[s.SystemId] = s; });
  // Every other platform the tool knows about (catalog cores not already shown), so ROM
  // upload covers every possible core, plus a custom platform-id escape hatch (#140).
  let allPlatforms = [];
  try { allPlatforms = (await api('/api/rom/all-platforms')).platforms || []; } catch { /* none */ }
  const esc = v => (v || '').replace(/"/g, '&quot;');

  const romRowHtml = (s, i, sv) => `
    <div class="card" id="romrow${i}"><strong>${s.DisplayName}</strong> <span class="meta">[${s.Id}] ${(s.SupportedExtensions || ['*']).join(' ')}</span>
      ${extraIds.has(s.Id) ? '<span class="tag rm">installed core</span>' : ''}
      ${s.Custom ? '<span class="tag rm">custom</span>' : ''}
      ${s.Arcade ? '<span class="tag fixed">arcade — needs built romset</span>' : ''}
      ${s.Experimental ? `<span class="tag fixed">experimental</span>${s.Notes ? `<p class="warnote">${s.Notes}</p>` : ''}` : ''}
      <div class="row"><input type="text" id="src${i}" placeholder="source ROM folder" value="${sv ? esc(sv.Path) : ''}">
        <button data-browse="${i}" class="secondary">Browse…</button>
        <label class="row"><input type="checkbox" id="rec${i}" ${sv && sv.Recurse ? 'checked' : ''}> subfolders</label>
        <button data-i="${i}" data-act="plan" class="secondary">Count</button>
        <button data-i="${i}" data-act="copy">Copy</button>
        ${s.Arcade && s.CoreId ? `<button data-recipes="${i}" class="secondary" title="Download the core's recipe files (.mra) — metadata only, never ROMs">Fetch rom-recipes</button>` : ''}
        ${s.Arcade ? `<button data-arcstatus="${i}" class="secondary" title="Check whether any instance .json + built .rom pairs are on the card">Check romset</button>` : ''}</div>
      <div id="rout${i}"></div></div>`;

  const rows = systems.map((s, i) => romRowHtml(s, i, saved[s.Id])).join('');
  const shown = new Set(systems.map(s => String(s.Id).toLowerCase()));
  const pickOpts = allPlatforms.filter(p => !shown.has(String(p.Id).toLowerCase()))
    .map(p => `<option value="${esc(p.Id)}">${esc(p.DisplayName)}${p.Arcade ? ' [arcade: needs built romset]' : ''}</option>`).join('');
  const rescanBtn = (cfg.Exists && (cfg.Sources || []).length)
    ? `<button id="rescan" class="secondary">Rescan ${cfg.Sources.length} saved folder(s)</button>` : '';
  panel(`<h2>6. ROM import</h2>
    <p class="warnote">Copies ROMs you already own. BIOS files are not copied automatically.</p>
    ${cfg.Exists ? `<p class="ok">A saved ROM-folder list was found on the card and pre-filled below.</p>` : ''}
    <div id="rom-rows">${rows}</div>
    <details class="card"><summary><strong>Add another core / platform</strong> — covers every core, including ones not listed above</summary>
      <label class="row">Known platform:
        <select id="add-known"><option value="">— choose —</option>${pickOpts}</select></label>
      <label class="row">…or custom platform-id: <input type="text" id="add-custom" placeholder="e.g. mycore (→ Assets/mycore/common)"></label>
      <button id="add-row" class="secondary">Add upload row</button>
      <p class="meta">For non-built-in platforms the exact ROM extensions aren't known, so any file you point at the row is copied. Point it at a folder of only that system's ROMs.</p>
    </details>
    <div class="row"><button id="savecfg" class="secondary">Save folder list to card</button>${rescanBtn}</div>
    <div id="cfgout"></div>
    <button id="c">Continue to summary →</button>`);
  $('#c').onclick = () => go(6);

  // Gather the currently-filled rows into a sources[] payload.
  const gather = () => systems.map((s, i) => ({ systemId: s.Id, path: ($('#src' + i) || {}).value ? $('#src' + i).value.trim() : '', recurse: !!($('#rec' + i) || {}).checked }))
    .filter(r => r.path);

  $('#savecfg').onclick = async () => {
    const sources = gather();
    if (!sources.length) { $('#cfgout').innerHTML = errLine('Fill in at least one source folder first.'); return; }
    busy(true);
    try { const r = await api('/api/rom/config', 'POST', { sources });
      $('#cfgout').innerHTML = `<p class="ok">Saved ${r.SourceCount} folder(s) to the card. Next time, just rescan.</p>`;
    } catch (e) { $('#cfgout').innerHTML = errLine(e.message); } finally { busy(false); }
  };

  if (rescanBtn) $('#rescan').onclick = async () => {
    busy(true);
    $('#cfgout').innerHTML = `<p>Rescanning saved folders…</p>`;
    try { const r = await api('/api/rom/rescan', 'POST', {});
      (r.Results || []).forEach(x => { if (!x.Missing) { S.roms = S.roms.filter(y => y.SystemId !== x.SystemId); S.roms.push(x); } });
      const missing = (r.Results || []).filter(x => x.Missing).map(x => x.SystemId);
      $('#cfgout').innerHTML = `<p class="ok">Rescan copied ${r.TotalCopied} file(s) from ${r.SourceCount} folder(s).</p>` +
        (missing.length ? `<p class="warnote">Missing folder(s): ${missing.join(', ')}.</p>` : '');
    } catch (e) { $('#cfgout').innerHTML = errLine(e.message); } finally { busy(false); }
  };
  // Wire the browse/count/copy buttons for a single row (called for initial and added rows).
  const wireRow = (i) => {
    const browse = document.querySelector(`button[data-browse="${i}"]`);
    if (browse) browse.onclick = async () => { const c = await pickFolder($('#src' + i).value.trim()); if (c) $('#src' + i).value = c; };
    document.querySelectorAll(`button[data-act][data-i="${i}"]`).forEach(btn => btn.onclick = () => runRowAct(i, btn.dataset.act));
    // Arcade helpers: fetch the core's rom-recipes; check whether a built romset is present.
    const rec = document.querySelector(`button[data-recipes="${i}"]`);
    if (rec) rec.onclick = async () => {
      const out = $('#rout' + i);
      busy(true); out.innerHTML = inProgress('Downloading rom-recipes (metadata only, never ROMs)');
      try { const r = await api('/api/rom/recipes', 'POST', { coreId: systems[i].CoreId });
        out.innerHTML = `<p class="ok">Recipes ${r.Version ? '(' + r.Version + ') ' : ''}saved: ${r.PlacedCount} file(s) → ${r.Destination}${r.DryRun ? ' [dry-run]' : ''}. Combine them with a MAME set you own using an openFPGA arcade packager, then copy the built .json + .rom here.</p>`;
      } catch (e) { out.innerHTML = errLine(e.message); } finally { busy(false); }
    };
    const arc = document.querySelector(`button[data-arcstatus="${i}"]`);
    if (arc) arc.onclick = async () => {
      const out = $('#rout' + i);
      busy(true);
      try { const r = await api('/api/rom/arcade-status', 'POST', { platformId: systems[i].PlatformId });
        out.innerHTML = r.Ready
          ? `<p class="ok">Romset present: ${r.InstanceJson} instance .json, ${r.BuiltRom} built .rom — games should load.</p>`
          : `<p class="warnote">No playable romset yet (${r.InstanceJson} instance .json, ${r.BuiltRom} built .rom). Build them from the rom-recipes + your MAME set, then copy both file types into Assets/${systems[i].PlatformId}/common.</p>`;
      } catch (e) { out.innerHTML = errLine(e.message); } finally { busy(false); }
    };
  };
  const runRowAct = async (i, act) => {
    const out = $('#rout' + i);
    const body = { systemId: systems[i].Id, sourceFolder: $('#src' + i).value.trim(), recurse: $('#rec' + i).checked };
    if (systems[i].Custom) body.customPlatform = true;
    if (!body.sourceFolder) { out.innerHTML = errLine('Enter a source folder.'); return; }
    busy(true);
    try {
      if (act === 'plan') { const p = await api('/api/rom/plan', 'POST', body);
        const warn = p.PlatformProvided === false ? `<p class="warnote">No installed core provides platform "${systems[i].PlatformId}" yet — install the core (step 5) or these ROMs won't load.</p>` : '';
        const space = p.FitsInDestination === false ? `<p class="error">Not enough free space on the card (${(p.DestinationFreeBytes / 1048576).toFixed(1)} MB free) for ${(p.TotalBytes / 1048576).toFixed(1)} MB of ROMs.</p>` : '';
        const probs = (p.ProblemCount > 0) ? `<p class="warnote">${p.ProblemCount} file(s) will be skipped (can't go on the card): ${p.Problems.slice(0, 5).map(x => `${x.RelativePath} (${x.Reason})`).join('; ')}${p.ProblemCount > 5 ? '…' : ''}</p>` : '';
        const dups = (p.DuplicateCount > 0) ? `<p class="warnote">${p.DuplicateCount} duplicate(s) will be copied once: ${p.Duplicates.slice(0, 5).map(x => `${x.RelativePath} (${x.Reason})`).join('; ')}${p.DuplicateCount > 5 ? '…' : ''}</p>` : '';
        out.innerHTML = `<p>${p.FileCount} match (${(p.TotalBytes / 1048576).toFixed(1)} MB); ${p.SkippedNonMatching} other files ignored.</p>${space}${dups}${probs}${warn}`;
      } else {
        // Batched copy: transfer the library a slice at a time so the request stays short
        // and a determinate progress bar can advance between batches.
        const BATCH = 25;
        const total = (await api('/api/rom/plan', 'POST', body)).FileCount;
        if (total === 0) { out.innerHTML = `<p class="warnote">Nothing to copy.</p>`; busy(false); return; }
        out.innerHTML = `<p>Copying… <progress id="pg${i}" max="${total}" value="0"></progress> <span id="pgt${i}">0 / ${total}</span></p>`;
        const agg = { CopiedCount: 0, SkippedCount: 0, SkippedDuplicateCount: 0, SkippedProblemCount: 0, FailedCount: 0, DryRun: false, SystemId: systems[i].Id };
        for (let skip = 0; skip < total; skip += BATCH) {
          const r = await api('/api/rom/copy', 'POST', { ...body, skip, first: BATCH });
          agg.CopiedCount += r.CopiedCount; agg.SkippedCount += r.SkippedCount;
          agg.SkippedDuplicateCount += r.SkippedDuplicateCount; agg.SkippedProblemCount += r.SkippedProblemCount;
          agg.FailedCount += r.FailedCount; agg.DryRun = r.DryRun;
          const done = Math.min(skip + BATCH, total);
          $('#pg' + i).value = done; $('#pgt' + i).textContent = `${done} / ${total}`;
        }
        S.roms = S.roms.filter(x => x.SystemId !== agg.SystemId); S.roms.push(agg);
        const dupNote = agg.SkippedDuplicateCount > 0 ? `, ${agg.SkippedDuplicateCount} duplicate(s) skipped` : '';
        out.innerHTML = `<p class="ok">Copied ${agg.CopiedCount}, skipped ${agg.SkippedCount}${dupNote}, failed ${agg.FailedCount}${agg.DryRun ? ' [dry-run]' : ''}.</p>`;
        refreshSpace();
      }
    } catch (e) { out.innerHTML = errLine(e.message); } finally { busy(false); }
  };
  systems.forEach((_, i) => wireRow(i));

  // "Add another core/platform": append a fresh upload row for a catalog or custom platform.
  $('#add-row').onclick = () => {
    const known = ($('#add-known').value || '').trim();
    const custom = ($('#add-custom').value || '').trim();
    const id = custom || known;
    if (!id) { $('#cfgout').innerHTML = errLine('Choose a known platform or type a custom platform-id.'); return; }
    if (systems.some(s => String(s.Id).toLowerCase() === id.toLowerCase())) { $('#cfgout').innerHTML = errLine(`"${id}" is already listed above.`); return; }
    const meta = allPlatforms.find(p => String(p.Id).toLowerCase() === id.toLowerCase());
    const sys = meta
      ? { Id: meta.Id, PlatformId: meta.PlatformId, DisplayName: meta.DisplayName, SupportedExtensions: meta.SupportedExtensions || ['*'], Experimental: true, Notes: meta.Notes, Custom: false, Arcade: !!meta.Arcade, CoreId: meta.CoreId }
      : { Id: id, PlatformId: id, DisplayName: id, SupportedExtensions: ['*'], Experimental: true, Notes: `Custom platform — files are copied to Assets/${id}/common.`, Custom: true };
    const i = systems.length; systems.push(sys);
    $('#rom-rows').insertAdjacentHTML('beforeend', romRowHtml(sys, i, null));
    wireRow(i);
    $('#add-custom').value = ''; $('#add-known').value = '';
    $('#src' + i).scrollIntoView({ block: 'nearest' });
  };
}

/* ---- Step 6: Summary ---- */
async function stepSummary() {
  panel('<h2>7. Summary</h2><p>Building…</p>');
  try {
    const r = await api('/api/summary', 'POST', { firmware: S.firmware, folder: S.folder, roms: S.roms, cores: S.cores });
    panel(`<h2>7. Summary</h2><pre>${r.text}</pre>
      <p>When your Pocket arrives, insert the card and power on.</p>
      <button id="fin">Finish &amp; stop server</button><div id="finout"></div>`);
    $('#fin').onclick = async () => {
      try { await api('/api/shutdown', 'POST', {}); } catch {}
      $('#finout').innerHTML = '<p class="ok">Done. You can close this tab.</p>';
    };
  } catch (e) { panel('<h2>7. Summary</h2>' + errLine(e.message)); }
}

const RENDER = [stepTarget, stepCard, stepFirmware, stepFolders, stepCores, stepRoms, stepSummary];

(async () => {
  // Mark the app as up so the index.html "unsupported browser" guard stands down — any
  // failure from here is a real error shown in the panel, not an old-browser parse error.
  window.__pocketUp = true;
  try {
    S.health = await api('/api/health'); setCtx();
    if (S.health.targetReady) { refreshSpace(); }
    wireEject();
    go(S.health.targetReady ? 'menu' : 0);
  } catch (e) {
    panel(errLine('Could not reach the local server: ' + e.message));
  }
})();
