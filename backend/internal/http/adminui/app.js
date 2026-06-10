// Librefy admin — single-file vanilla JS app.
// Talks to /admin/v1/* with a bearer token kept in localStorage.

const LS_TOKEN = "librefy.adminToken";
const api = {
  base: "/admin/v1",
  token: () => localStorage.getItem(LS_TOKEN) || "",
  async req(method, path, body) {
    const r = await fetch(this.base + path, {
      method,
      headers: {
        "X-Admin-Token": this.token(),
        "Content-Type": "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (r.status === 401) {
      localStorage.removeItem(LS_TOKEN);
      showLogin("Token rejected. Try again.");
      throw new Error("unauthorized");
    }
    if (!r.ok && r.status !== 204) {
      const err = await r.text();
      throw new Error(`${r.status} ${err}`);
    }
    if (r.status === 204) return null;
    const ct = r.headers.get("Content-Type") || "";
    return ct.includes("application/json") ? r.json() : r.text();
  },
  get(p)    { return this.req("GET",    p); },
  post(p,b) { return this.req("POST",   p, b); },
  del(p)    { return this.req("DELETE", p); },
};

// ---------- Auth gate ----------

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => [...document.querySelectorAll(sel)];

function showLogin(errMsg) {
  $("#loginCard").classList.remove("hidden");
  $$(".tab").forEach(t => t.classList.add("hidden"));
  $("#tabs").style.visibility = "hidden";
  setConnStatus(false);
  if (errMsg) {
    $("#loginError").textContent = errMsg;
    $("#loginError").classList.remove("hidden");
  }
}

function showApp() {
  $("#loginCard").classList.add("hidden");
  $("#tabs").style.visibility = "visible";
  switchTab("dashboard");
  setConnStatus(true);
  loadStats();
}

function setConnStatus(ok) {
  const el = $("#connStatus");
  el.textContent = ok ? "connected" : "disconnected";
  el.classList.toggle("ok", ok);
  el.classList.toggle("bad", !ok);
}

$("#loginBtn").addEventListener("click", async () => {
  const token = $("#tokenInput").value.trim();
  if (!token) return;
  localStorage.setItem(LS_TOKEN, token);
  try {
    await fetch(`/admin/v1/ping`, { headers: { "X-Admin-Token": token } })
      .then(r => { if (!r.ok) throw new Error("rejected"); });
    showApp();
  } catch {
    localStorage.removeItem(LS_TOKEN);
    showLogin("Token rejected.");
  }
});
$("#tokenInput").addEventListener("keydown", e => { if (e.key === "Enter") $("#loginBtn").click(); });

$("#logoutBtn").addEventListener("click", () => {
  localStorage.removeItem(LS_TOKEN);
  showLogin();
});

// ---------- Tabs ----------

$$("#tabs button").forEach(b => b.addEventListener("click", () => switchTab(b.dataset.tab)));
function switchTab(name) {
  $$("#tabs button").forEach(b => b.classList.toggle("active", b.dataset.tab === name));
  $$(".tab").forEach(t => t.classList.toggle("hidden", t.id !== name));
  if (name === "dashboard") loadStats();
  if (name === "tracks") loadTracks();
  if (name === "playlists") loadPlaylists();
}

// ---------- Dashboard ----------

async function loadStats() {
  try {
    const s = await api.get("/stats");
    $("#statsGrid").innerHTML = Object.entries(s)
      .map(([k, v]) => `<div class="stat"><div class="v">${v}</div><div class="k">${labelFor(k)}</div></div>`)
      .join("");
  } catch (e) { $("#statsGrid").textContent = e.message; }
}
const STAT_LABELS = { tracks: "Tracks", playlists: "Playlists", playlistLinks: "Playlist links", plays: "Total plays" };
function labelFor(k) { return STAT_LABELS[k] || k; }

// ---------- Tracks ----------

let tracksCache = [];

async function loadTracks() {
  try {
    const { tracks } = await api.get("/tracks?limit=500");
    tracksCache = tracks || [];
    renderTracks();
  } catch (e) { console.error(e); }
}

function renderTracks() {
  const q = ($("#trackSearch").value || "").toLowerCase();
  const tbody = $("#tracksTable tbody");
  tbody.innerHTML = "";
  tracksCache
    .filter(t => !q || t.title.toLowerCase().includes(q) || (t.artist || "").toLowerCase().includes(q))
    .forEach(t => {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td><strong>${esc(t.title)}</strong><div class="muted small">${esc(t.id)}</div></td>
        <td>${esc(t.artist)}</td>
        <td>${esc(t.license?.code || "")}</td>
        <td><span class="dot ${t.streamUrl ? "ok" : "no"}"></span></td>
        <td><span class="dot ${t.magnet ? "ok" : "no"}"></span></td>
        <td><div class="row actions">
          <button data-edit="${esc(t.id)}">Edit</button>
          <button class="danger" data-del="${esc(t.id)}">Delete</button>
        </div></td>`;
      tbody.appendChild(tr);
    });

  tbody.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click",
    () => openTrackModal(tracksCache.find(t => t.id === b.dataset.edit))));
  tbody.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
    if (!confirm(`Delete ${b.dataset.del}?`)) return;
    await api.del(`/tracks/${encodeURIComponent(b.dataset.del)}`);
    loadTracks(); loadStats();
  }));
}
$("#trackSearch").addEventListener("input", renderTracks);
$("#newTrackBtn").addEventListener("click", () => openTrackModal(null));
$("#importUrlBtn").addEventListener("click", async () => {
  const url = prompt(
    "Paste a rutracker topic URL.\n\n" +
    "We'll fetch the page, extract the magnet + metadata, and either " +
    "prefill the New Track form (single release) or show the tracklist " +
    "(compilation) so you can pick which songs to import."
  );
  if (!url) return;
  let parsed;
  try {
    parsed = await api.get(
      "/import/rutracker?url=" + encodeURIComponent(url.trim())
    );
  } catch (e) {
    alert("Import failed: " + e.message);
    return;
  }

  if (parsed.tracks && parsed.tracks.length > 0) {
    openTracklistImport(parsed);
    return;
  }

  // Single-release: prefill the New Track modal.
  const prefill = {
    id: slugify(parsed.artist || "") + "-" + slugify(parsed.title || parsed.album || ""),
    title: parsed.title || parsed.album || "",
    artist: parsed.artist || "",
    album: parsed.album || "",
    durationMs: 0,
    artworkUrl: parsed.artworkUrl || "",
    streamUrl: "",
    magnet: parsed.magnet || "",
    infoHash: parsed.infoHash || "",
    fileIndex: 0,
    license: {
      code: "CC-BY-4.0",
      name: "Creative Commons Attribution 4.0",
      url: "https://creativecommons.org/licenses/by/4.0/",
    },
    attribution: parsed.artist
      ? `${parsed.title || parsed.album || "Track"} by ${parsed.artist}`
      : "",
    tags: parsed.tags || [],
  };
  openTrackModal(prefill);
});

// ---------- Tracklist import (compilation albums) ----------

function openTracklistImport(parsed) {
  $("#modalTitle").textContent =
    `Import tracklist (${parsed.tracks.length} tracks)`;
  const rows = parsed.tracks
    .map((t, i) => `
      <tr>
        <td><input type="checkbox" name="sel" value="${i}" checked></td>
        <td>${t.position}</td>
        <td>${esc(t.artist)}</td>
        <td>${esc(t.title)}</td>
        <td>${t.durationMs ? fmtDuration(t.durationMs) : ""}</td>
      </tr>`)
    .join("");
  $("#modalForm").innerHTML = `
    <p class="muted small">Release: <b>${esc(parsed.album || parsed.title)}</b>
      — ${parsed.tracks.length} tracks share the same magnet.
      File index defaults to (position - 1) — adjust if the torrent's
      actual file order differs.</p>
    <div class="row gap" style="margin-bottom:8px">
      <button type="button" id="selAll">Select all</button>
      <button type="button" id="selNone">Clear</button>
    </div>
    <div style="max-height:50vh; overflow:auto; border:1px solid var(--border); border-radius:8px">
      <table style="margin:0">
        <thead><tr>
          <th></th><th>#</th><th>Artist</th><th>Title</th><th>Dur.</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>
    <div class="row gap" style="margin-top:12px">
      <label style="flex:1">License code
        <select name="licenseCode" style="margin-top:4px">
          ${["CC-BY-4.0","CC-BY-SA-4.0","CC-BY-NC-4.0","PD","UNKNOWN"]
            .map(c => `<option ${c === "UNKNOWN" ? "selected" : ""}>${c}</option>`).join("")}
        </select>
      </label>
    </div>
    <div class="muted small" style="margin-top:8px">
      ⚠ Bulk-imported tracks default to UNKNOWN license. Only ship them
      to users once you've verified redistribution rights for the release.
    </div>
    <div class="actions">
      <button type="button" class="ghost" data-cancel>Cancel</button>
      <button type="submit" class="primary">Import selected</button>
    </div>
  `;
  $("#modalForm").querySelector("[data-cancel]").addEventListener("click", closeModal);
  $("#selAll").addEventListener("click", () =>
    $$('input[name="sel"]').forEach(c => (c.checked = true)));
  $("#selNone").addEventListener("click", () =>
    $$('input[name="sel"]').forEach(c => (c.checked = false)));
  $("#modalForm").onsubmit = async (e) => {
    e.preventDefault();
    const selected = $$('input[name="sel"]:checked').map(c => Number(c.value));
    if (selected.length === 0) return alert("Select at least one track.");
    const licenseCode = new FormData(e.target).get("licenseCode");
    const license = licenseMeta(licenseCode);
    const releaseSlug =
      slugify(parsed.artist || "") + "-" + slugify(parsed.album || parsed.title);

    const tracks = selected.map(i => {
      const t = parsed.tracks[i];
      return {
        id: `${releaseSlug}-${String(t.position).padStart(2, "0")}-${slugify(t.title)}`,
        title: t.title,
        artist: t.artist,
        album: parsed.album || parsed.title || "",
        durationMs: t.durationMs || 0,
        artworkUrl: parsed.artworkUrl || "",
        streamUrl: "",
        magnet: parsed.magnet,
        infoHash: parsed.infoHash,
        fileIndex: t.fileIndex,
        license,
        attribution: `${t.title} by ${t.artist}`,
        tags: parsed.tags || [],
      };
    });

    try {
      const r = await api.post("/tracks/bulk", { tracks });
      closeModal();
      alert(`Imported: ${r.ok} ok, ${r.failed} failed` +
        (r.errors?.length ? "\n\n" + r.errors.slice(0, 5).join("\n") : ""));
      loadTracks();
      loadStats();
    } catch (err) {
      alert(err.message);
    }
  };
  $("#modal").classList.remove("hidden");
}

function licenseMeta(code) {
  const map = {
    "CC0": ["Public Domain / CC0", "https://creativecommons.org/publicdomain/zero/1.0/"],
    "CC-BY-4.0": ["Creative Commons Attribution 4.0", "https://creativecommons.org/licenses/by/4.0/"],
    "CC-BY-SA-4.0": ["Creative Commons BY-SA 4.0", "https://creativecommons.org/licenses/by-sa/4.0/"],
    "CC-BY-NC-4.0": ["Creative Commons BY-NC 4.0", "https://creativecommons.org/licenses/by-nc/4.0/"],
    "PD": ["Public domain", ""],
  };
  const [name, url] = map[code] || ["Unknown", ""];
  return { code, name, url };
}

function fmtDuration(ms) {
  const s = Math.round(ms / 1000);
  const m = Math.floor(s / 60);
  const ss = String(s % 60).padStart(2, "0");
  return `${m}:${ss}`;
}

function slugify(s) {
  return (s || "")
    .toLowerCase()
    .replace(/[^a-z0-9а-я\s-]+/gi, "")
    .replace(/\s+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
}

function openTrackModal(t) {
  // "Edit" mode iff this track already exists on the server (its id is
  // in our cache). Prefilled drafts from importers are treated as new.
  const isEdit = !!t && tracksCache.some((c) => c.id === t.id);
  const v = t || {
    id: "", title: "", artist: "", album: "", durationMs: 0, artworkUrl: "",
    streamUrl: "", magnet: "", infoHash: "",
    license: { code: "CC-BY-4.0", name: "Creative Commons Attribution 4.0", url: "https://creativecommons.org/licenses/by/4.0/" },
    attribution: "", tags: [],
  };
  $("#modalTitle").textContent = isEdit ? "Edit track" : "New track";
  $("#modalForm").innerHTML = `
    <div class="field-grid">
      <div><label>ID</label><input name="id" value="${esc(v.id)}" ${isEdit ? "readonly" : ""} required placeholder="my-artist-track-1"></div>
      <div><label>Duration (ms)</label><input name="durationMs" type="number" value="${v.durationMs || 0}"></div>
      <div class="full"><label>Title</label><input name="title" value="${esc(v.title)}" required></div>
      <div><label>Artist</label><input name="artist" value="${esc(v.artist)}" required></div>
      <div><label>Album</label><input name="album" value="${esc(v.album || "")}"></div>
      <div class="full"><label>Artwork URL</label><input name="artworkUrl" value="${esc(v.artworkUrl || "")}"></div>
      <div class="full"><label>HTTP stream URL</label><input name="streamUrl" value="${esc(v.streamUrl || "")}"></div>
      <div class="full"><label>Magnet URI</label><input name="magnet" value="${esc(v.magnet || "")}" placeholder="magnet:?xt=urn:btih:…"></div>
      <div><label>Info hash</label><input name="infoHash" value="${esc(v.infoHash || "")}"></div>
      <div><label>File index</label><input name="fileIndex" type="number" min="0" value="${v.fileIndex || 0}"></div>
      <div><label>License code</label>
        <select name="licenseCode">
          ${["CC0","CC-BY-4.0","CC-BY-SA-4.0","CC-BY-ND-4.0","CC-BY-NC-4.0","PD"].map(c =>
            `<option ${c === v.license?.code ? "selected" : ""}>${c}</option>`).join("")}
        </select>
      </div>
      <div class="full"><label>License name</label><input name="licenseName" value="${esc(v.license?.name || "")}"></div>
      <div class="full"><label>License URL</label><input name="licenseUrl" value="${esc(v.license?.url || "")}"></div>
      <div class="full"><label>Attribution</label><input name="attribution" value="${esc(v.attribution || "")}"></div>
      <div class="full"><label>Tags (comma-separated)</label><input name="tags" value="${esc((v.tags || []).join(", "))}"></div>
    </div>
    <div class="actions">
      <button type="button" class="ghost" data-cancel>Cancel</button>
      <button type="submit" class="primary">Save</button>
    </div>
  `;
  $("#modalForm").querySelector("[data-cancel]").addEventListener("click", closeModal);
  $("#modalForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const payload = {
      id: f.get("id"),
      title: f.get("title"),
      artist: f.get("artist"),
      album: f.get("album"),
      durationMs: Number(f.get("durationMs") || 0),
      artworkUrl: f.get("artworkUrl"),
      streamUrl: f.get("streamUrl"),
      magnet: f.get("magnet"),
      infoHash: f.get("infoHash"),
      fileIndex: Number(f.get("fileIndex") || 0),
      license: {
        code: f.get("licenseCode"),
        name: f.get("licenseName"),
        url: f.get("licenseUrl"),
      },
      attribution: f.get("attribution"),
      tags: (f.get("tags") || "").split(",").map(s => s.trim()).filter(Boolean),
    };
    try {
      await api.post("/tracks", payload);
      closeModal();
      loadTracks(); loadStats();
    } catch (err) { alert(err.message); }
  };
  $("#modal").classList.remove("hidden");
}

// ---------- Playlists ----------

let playlistsCache = [];

async function loadPlaylists() {
  try {
    const { playlists } = await api.get("/playlists");
    playlistsCache = playlists || [];
    renderPlaylists();
  } catch (e) { console.error(e); }
}

function renderPlaylists() {
  const tbody = $("#playlistsTable tbody");
  tbody.innerHTML = "";
  playlistsCache.forEach(p => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><strong>${esc(p.title)}</strong><div class="muted small">${esc(p.id)}</div></td>
      <td>${p.curated ? "yes" : "no"}</td>
      <td>${(p.trackIds || []).length}</td>
      <td><div class="row actions">
        <button data-edit="${esc(p.id)}">Edit</button>
        <button class="danger" data-del="${esc(p.id)}">Delete</button>
      </div></td>`;
    tbody.appendChild(tr);
  });
  tbody.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click",
    () => openPlaylistModal(playlistsCache.find(p => p.id === b.dataset.edit))));
  tbody.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
    if (!confirm(`Delete playlist ${b.dataset.del}?`)) return;
    await api.del(`/playlists/${encodeURIComponent(b.dataset.del)}`);
    loadPlaylists(); loadStats();
  }));
}
$("#newPlaylistBtn").addEventListener("click", () => openPlaylistModal(null));

function openPlaylistModal(p) {
  const isEdit = !!p;
  const v = p || { id: "", title: "", description: "", artworkUrl: "", curated: true, trackIds: [] };
  $("#modalTitle").textContent = isEdit ? "Edit playlist" : "New playlist";
  $("#modalForm").innerHTML = `
    <label>ID</label><input name="id" value="${esc(v.id)}" ${isEdit ? "readonly" : ""} required placeholder="focus-pack">
    <label>Title</label><input name="title" value="${esc(v.title)}" required>
    <label>Description</label><input name="description" value="${esc(v.description || "")}">
    <label>Artwork URL</label><input name="artworkUrl" value="${esc(v.artworkUrl || "")}">
    <label><input type="checkbox" name="curated" ${v.curated ? "checked" : ""}/> Curated (shown in Featured)</label>
    <label>Track IDs (one per line; bare or "catalog:…")</label>
    <textarea name="trackIds" rows="8" placeholder="kevin-macleod-cipher&#10;catalog:scott-buckley-i-walk-with-ghosts">${esc((v.trackIds || []).join("\n"))}</textarea>
    <div class="actions">
      <button type="button" class="ghost" data-cancel>Cancel</button>
      <button type="submit" class="primary">Save</button>
    </div>
  `;
  $("#modalForm").querySelector("[data-cancel]").addEventListener("click", closeModal);
  $("#modalForm").onsubmit = async (e) => {
    e.preventDefault();
    const f = new FormData(e.target);
    const payload = {
      id: f.get("id"),
      title: f.get("title"),
      description: f.get("description"),
      artworkUrl: f.get("artworkUrl"),
      curated: !!f.get("curated"),
      trackIds: (f.get("trackIds") || "").split(/\r?\n/).map(s => s.trim()).filter(Boolean),
    };
    try {
      await api.post("/playlists", payload);
      closeModal();
      loadPlaylists(); loadStats();
    } catch (err) { alert(err.message); }
  };
  $("#modal").classList.remove("hidden");
}

// ---------- Modal helpers ----------

function closeModal() {
  $("#modal").classList.add("hidden");
}
$("#modalClose").addEventListener("click", closeModal);
document.addEventListener("keydown", e => { if (e.key === "Escape") closeModal(); });

// ---------- Import / Export ----------

$("#exportBtn").addEventListener("click", () => {
  const token = api.token();
  // Browser download via a temporary anchor — bypasses fetch so the
  // file dialog appears and we don't load the whole payload into memory.
  const a = document.createElement("a");
  a.href = `/admin/v1/seed/export?token=${encodeURIComponent(token)}`;
  a.download = "tracks.json";
  a.click();
});

$("#bulkBtn").addEventListener("click", async () => {
  const raw = $("#bulkText").value.trim();
  if (!raw) return;
  let payload;
  try { payload = JSON.parse(raw); }
  catch (e) { return alert("Invalid JSON: " + e.message); }
  try {
    const r = await api.post("/tracks/bulk", payload);
    $("#bulkResult").textContent = `Imported: ${r.ok} ok, ${r.failed} failed`;
    if (r.errors?.length) $("#bulkResult").textContent += " — " + r.errors.slice(0, 3).join(" | ");
    loadStats();
  } catch (e) { alert(e.message); }
});

// ---------- Util ----------

function esc(s) {
  return String(s ?? "")
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

// ---------- Boot ----------

if (api.token()) {
  // Validate cached token quietly.
  fetch("/admin/v1/ping", { headers: { "X-Admin-Token": api.token() } })
    .then(r => { if (r.ok) showApp(); else { localStorage.removeItem(LS_TOKEN); showLogin(); } })
    .catch(() => showLogin());
} else {
  showLogin();
}
