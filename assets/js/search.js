/* Search the published inventory, not a duplicated hand-maintained page list.
   No network request until opened; no third-party search or persistent cache. */
(() => {
  "use strict";
  const trigger = document.getElementById("search-trigger");
  const dialog = document.getElementById("site-search");
  const input = document.getElementById("search-input");
  const results = document.getElementById("search-results");
  const status = document.getElementById("search-status");
  const indexMeta = document.querySelector('meta[name="damagebdd-search-index"]');
  if (!trigger || !dialog?.showModal || !input || !results || !status || !indexMeta) return;
  let indexURL;
  try { indexURL = new URL(indexMeta.content, location.href); } catch (_) { return; }
  if (indexURL.origin !== location.origin) return;
  const siteBase = new URL("../", indexURL);
  let documents = [];
  let state = "idle";
  let controller;
  let opener;
  const normalize = value => String(value).normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const render = () => {
    results.replaceChildren();
    if (state !== "ready") return;
    const query = normalize(input.value.trim());
    const words = query.split(/\s+/).filter(Boolean);
    const ranked = documents.map(doc => {
      const title = normalize(doc.title);
      const haystack = normalize(`${doc.title} ${doc.summary} ${doc.path}`);
      const matches = words.every(word => haystack.includes(word));
      const score = (title === query ? 100 : 0) + (query && title.includes(query) ? 30 : 0) + words.filter(word => title.includes(word)).length * 10;
      return { doc, score, matches };
    }).filter(item => item.matches).sort((a, b) => b.score - a.score || a.doc.title.localeCompare(b.doc.title));
    const visible = ranked.slice(0, 16);
    status.textContent = query
      ? ranked.length ? `${ranked.length} matching ${ranked.length === 1 ? "page" : "pages"}${ranked.length > 16 ? "; showing the first 16" : ""}.` : "No matching pages. Try a broader term or browse the sitemap."
      : `${documents.length} pages available. Search titles, summaries and document paths.`;
    for (const { doc } of visible) {
      const li = document.createElement("li");
      const link = document.createElement("a");
      link.href = doc.url;
      const title = document.createElement("strong");
      title.textContent = doc.title;
      const summary = document.createElement("span");
      summary.textContent = doc.summary.length > 190 ? `${doc.summary.slice(0, 187)}…` : doc.summary;
      const path = document.createElement("small");
      path.textContent = doc.path;
      link.append(title, summary, path);
      li.append(link);
      results.append(li);
    }
  };
  const load = async () => {
    controller?.abort();
    const request = new AbortController();
    controller = request;
    state = "loading";
    documents = [];
    results.replaceChildren();
    status.textContent = "Loading the current document index…";
    const timeout = window.setTimeout(() => request.abort(), 8000);
    try {
      const response = await fetch(indexURL, { cache: "no-cache", signal: request.signal, credentials: "same-origin" });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!Array.isArray(data.documents)) throw new Error("Invalid document inventory");
      const loaded = [];
      for (const item of data.documents) {
        if (!item || typeof item.title !== "string" || typeof item.html_path !== "string") continue;
        // Only relative HTML paths inside this deployment. Never trust an injected URL/title.
        const parts = item.html_path.split("/");
        if (!item.html_path.endsWith(".html") || /[\\\u0000-\u001f]/.test(item.html_path) || parts.some(part => !part || part === "." || part === "..")) continue;
        if (/(^|\/)(header|sitemap|theindex)\.html$/.test(item.html_path)) continue;
        const url = new URL(parts.map(encodeURIComponent).join("/"), siteBase);
        if (url.origin !== location.origin || !url.pathname.startsWith(siteBase.pathname)) continue;
        loaded.push({ title: item.title, summary: typeof item.summary === "string" ? item.summary : "", path: item.html_path, url: url.href });
      }
      if (controller !== request) return;
      documents = loaded;
      state = "ready";
      render();
    } catch (_) {
      if (controller !== request) return;
      state = "error";
      status.textContent = "The document index is unavailable. Browse all pages below, or close and reopen search to retry.";
    } finally { window.clearTimeout(timeout); }
  };
  const open = () => {
    if (dialog.open) { input.focus(); return; }
    opener = document.activeElement;
    dialog.showModal();
    input.focus();
    load(); // Revalidate on each open, including after a failed request.
  };
  trigger.setAttribute("role", "button");
  trigger.setAttribute("aria-haspopup", "dialog");
  trigger.addEventListener("click", event => { event.preventDefault(); open(); });
  trigger.addEventListener("keydown", event => { if (event.key === " ") { event.preventDefault(); open(); } });
  const shortcut = trigger.querySelector("kbd");
  if (shortcut && /Mac|iPhone|iPad/.test(navigator.platform)) shortcut.textContent = "⌘ K";
  document.addEventListener("keydown", event => {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && event.key.toLowerCase() === "k") { event.preventDefault(); open(); }
  });
  input.addEventListener("input", render);
  input.addEventListener("keydown", event => {
    const first = results.querySelector("a");
    if (first && event.key === "ArrowDown") { event.preventDefault(); first.focus(); }
    if (first && event.key === "Enter") { event.preventDefault(); first.click(); }
  });
  results.addEventListener("keydown", event => {
    if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;
    const links = [...results.querySelectorAll("a")];
    const position = links.indexOf(document.activeElement);
    if (position < 0) return;
    event.preventDefault();
    if (event.key === "ArrowUp" && position === 0) input.focus();
    else links[Math.min(links.length - 1, Math.max(0, position + (event.key === "ArrowDown" ? 1 : -1)))].focus();
  });
  // A search input can consume Escape to clear itself before native dialog
  // cancellation. Keep the advertised close shortcut consistent across browsers.
  dialog.addEventListener("keydown", event => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    dialog.close();
  });
  dialog.addEventListener("click", event => {
    if (event.target !== dialog) return;
    const box = dialog.getBoundingClientRect();
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) dialog.close();
  });
  dialog.addEventListener("close", () => {
    controller?.abort();
    controller = null;
    if (opener instanceof HTMLElement && opener.isConnected) opener.focus();
  });
})();
