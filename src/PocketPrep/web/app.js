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
  if (!res.ok) { const e = new Error((data && data.error) || `HTTP ${res.status}`); e.data = data; throw e; }
  return data;
}
const fmtGB = (b) => (b ? (b / 1073741824).toFixed(1) + ' GB' : '—');
const busy = (on) => { $('#busy').hidden = !on; };
function panel(html) { $('#panel').innerHTML = html; }
function errLine(msg) { return `<p class="error">${msg}</p>`; }
// Clear, specific in-progress message so a long single-threaded operation can never
// look silently hung (downloads also have a server-side timeout).
function inProgress(label) { return `<p class="busy">${label}… please keep this tab open. This can take up to a minute and the page may be unresponsive while it runs.</p>`; }

const STEP_LABELS = ['Target', 'Card', 'Firmware', 'Folders', 'Cores', 'ROMs', 'Done'];
const S = { health: null, step: 0, drive: null, firmware: null, folder: null, roms: [], cores: [] };

function renderNav() {
  $('#steps').innerHTML = STEP_LABELS.map((l, i) =>
    `<span class="${i === S.step ? 'active' : (i < S.step ? 'done' : '')}">${i + 1}. ${l}</span>`).join('');
}
function setCtx() {
  const h = S.health;
  $('#ctx').textContent = h && h.targetReady
    ? `Target: ${h.root}${h.testMode ? ' (TEST MODE)' : ''}${h.dryRun ? ' · DRY-RUN' : ''}`
    : 'No target selected yet';
}
function go(step) { S.step = step; renderNav(); RENDER[step](); }

/* ---- Step 0: Target ---- */
async function stepTarget() {
  panel('<h2>1. Choose the SD card</h2><p>Loading drives…</p>');
  let drives = [];
  try { drives = (await api('/api/drives')).drives || []; } catch (e) { /* ignore */ }
  const rows = drives.map((d, i) => `
    <li><input type="radio" name="drv" id="drv${i}" value="${i}">
      <label for="drv${i}"><strong>${d.RootPath || d.DriveLetter}</strong>
      <span class="meta">${d.Label || '(no label)'} · ${d.FileSystem || '?'} · ${fmtGB(d.SizeBytes)} (${fmtGB(d.FreeBytes)} free)</span>
      <span class="tag ${d.IsRemovable ? 'rm' : 'fixed'}">${d.IsRemovable ? 'removable' : 'FIXED'}</span></label></li>`).join('');
  panel(`
    <h2>1. Choose the SD card</h2>
    ${drives.length ? `<ul class="list">${rows}</ul>` : '<p class="warnote">No removable drives detected.</p>'}
    <label class="row"><input type="checkbox" id="adv"> Advanced: allow a non-removable drive (the system disk is never allowed)</label>
    <div class="card">
      <label class="row"><input type="checkbox" id="tm"> Use a test folder instead of a real card</label>
      <label class="row">Folder: <input type="text" id="tmpath" placeholder="e.g. C:\\Temp\\PocketSDTest or /tmp/PocketSDTest"></label>
    </div>
    <div id="terr"></div>
    <button id="useBtn">Use this target →</button>`);
  window.__drives = drives;
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
    go(1);
  } catch (e) {
    const reasons = e.data && e.data.verdict && e.data.verdict.Reasons ? '<ul>' + e.data.verdict.Reasons.map(x => `<li>${x}</li>`).join('') + '</ul>' : '';
    $('#terr').innerHTML = errLine(e.message) + reasons;
  } finally { busy(false); }
}

/* ---- Step 1: Card checks ---- */
async function stepCard() {
  panel('<h2>2. Card checks</h2><p>Checking…</p>');
  let html = '<h2>2. Card checks</h2>';
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
      panel(html); $('#c').onclick = () => go(2); return;
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
    $('#ok').onchange = (e) => { $('#c').disabled = !e.target.checked; };
    $('#c').onclick = () => go(2);
    if ($('#bbtn')) $('#bbtn').onclick = async () => {
      const d = $('#bdest').value.trim(); if (!d) { $('#bout').innerHTML = errLine('Enter a destination.'); return; }
      busy(true);
      try { const r = await api('/api/saves/backup', 'POST', { destination: d, includeMemories: $('#bmem').checked });
        $('#bout').innerHTML = `<p class="ok">Backed up ${r.FileCount} file(s) to ${r.Destination}${r.DryRun ? ' [dry-run]' : ''}.</p>`;
      } catch (e) { $('#bout').innerHTML = errLine(e.message); } finally { busy(false); }
    };
  } catch (e) { panel(html + errLine(e.message) + '<button id="c">Continue →</button>'); $('#c').onclick = () => go(2); }
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
  const rows = cores.map((c, i) => {
    const have = instById[c.Identifier];
    return `<div class="card"><strong>${c.DisplayName}</strong> <span class="meta">${c.Identifier}</span>
      ${have ? `<span class="tag rm">installed v${have.Version}</span>` : ''}
      <div class="row">
        <button data-i="${i}" data-mode="download" data-ow="${have ? 1 : 0}">${have ? 'Reinstall / update' : 'Download & install'}</button>
        <input type="text" id="cz${i}" placeholder="or path to ${c.Identifier} .zip">
        <button data-i="${i}" data-mode="offline" data-ow="${have ? 1 : 0}" class="secondary">Install local zip</button>
      </div><div id="cout${i}"></div></div>`;
  }).join('');
  panel(`<h2>5. openFPGA cores (optional)</h2>
    <p class="warnote">Cores are made by independent authors under their own licences.</p>
    ${instLine}
    <p><button id="chk" class="secondary">Check for updates</button>
       <button id="updall" class="secondary">Update all</button>
       <span id="updout" class="meta"></span></p>
    ${cores.length ? rows : '<p>No cores manifest available.</p>'}
    <button id="c">Continue →</button>`);
  $('#c').onclick = () => go(5);
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
}

/* ---- Step 5: ROMs ---- */
async function stepRoms() {
  panel('<h2>6. ROM import</h2><p>Loading systems…</p>');
  let systems = [];
  try { systems = (await api('/api/systems')).systems || []; } catch (e) { panel('<h2>6. ROM import</h2>' + errLine(e.message)); }
  const rows = systems.map((s, i) => `
    <div class="card"><strong>${s.DisplayName}</strong> <span class="meta">[${s.Id}] ${s.SupportedExtensions.join(' ')}</span>
      <div class="row"><input type="text" id="src${i}" placeholder="source ROM folder">
        <label class="row"><input type="checkbox" id="rec${i}"> subfolders</label>
        <button data-i="${i}" data-act="plan" class="secondary">Count</button>
        <button data-i="${i}" data-act="copy">Copy</button></div>
      <div id="rout${i}"></div></div>`).join('');
  panel(`<h2>6. ROM import</h2>
    <p class="warnote">Copies ROMs you already own. BIOS files are not copied automatically.</p>
    ${rows}<button id="c">Continue to summary →</button>`);
  $('#c').onclick = () => go(6);
  document.querySelectorAll('button[data-act]').forEach(btn => btn.onclick = async () => {
    const i = +btn.dataset.i, act = btn.dataset.act, out = $('#rout' + i);
    const body = { systemId: systems[i].Id, sourceFolder: $('#src' + i).value.trim(), recurse: $('#rec' + i).checked };
    if (!body.sourceFolder) { out.innerHTML = errLine('Enter a source folder.'); return; }
    busy(true);
    try {
      if (act === 'plan') { const p = await api('/api/rom/plan', 'POST', body);
        const warn = p.PlatformProvided === false ? `<p class="warnote">No installed core provides platform "${systems[i].PlatformId}" yet — install the core (step 5) or these ROMs won't load.</p>` : '';
        const space = p.FitsInDestination === false ? `<p class="error">Not enough free space on the card (${(p.DestinationFreeBytes / 1048576).toFixed(1)} MB free) for ${(p.TotalBytes / 1048576).toFixed(1)} MB of ROMs.</p>` : '';
        out.innerHTML = `<p>${p.FileCount} match (${(p.TotalBytes / 1048576).toFixed(1)} MB); ${p.SkippedNonMatching} other files ignored.</p>${space}${warn}`;
      } else { const r = await api('/api/rom/copy', 'POST', body); S.roms = S.roms.filter(x => x.SystemId !== r.SystemId); S.roms.push(r);
        out.innerHTML = `<p class="ok">Copied ${r.CopiedCount}, skipped ${r.SkippedCount}, failed ${r.FailedCount}${r.DryRun ? ' [dry-run]' : ''}.</p>`;
      }
    } catch (e) { out.innerHTML = errLine(e.message); } finally { busy(false); }
  });
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
  try {
    S.health = await api('/api/health'); setCtx();
    go(S.health.targetReady ? 1 : 0);
  } catch (e) {
    panel(errLine('Could not reach the local server: ' + e.message));
  }
})();
