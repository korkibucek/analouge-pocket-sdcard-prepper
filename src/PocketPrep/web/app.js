// Minimal bootstrap client (the full wizard UI is built in issue #22).
// Confirms the server is reachable and the session token works.
const TOKEN = window.POCKETPREP_TOKEN;

async function api(path, opts = {}) {
  const res = await fetch(path, {
    ...opts,
    headers: { 'Content-Type': 'application/json', 'X-PocketPrep-Token': TOKEN, ...(opts.headers || {}) },
  });
  if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || `HTTP ${res.status}`);
  return res.json();
}

(async () => {
  const statusEl = document.getElementById('status');
  const outEl = document.getElementById('out');
  try {
    const health = await api('/api/health');
    const drives = await api('/api/drives');
    statusEl.textContent = `Connected. Target: ${health.root}${health.testMode ? ' (test mode)' : ''}${health.dryRun ? ' [dry-run]' : ''}`;
    outEl.hidden = false;
    outEl.textContent = JSON.stringify({ health, drives }, null, 2);
  } catch (e) {
    statusEl.className = 'error';
    statusEl.textContent = 'Error talking to the local server: ' + e.message;
  }
})();
