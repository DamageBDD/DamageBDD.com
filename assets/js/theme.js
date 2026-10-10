/* Runs in <head>: do not touch document.body or depend on storage access. */
(() => {
  "use strict";
  const root = document.documentElement;
  const preference = window.matchMedia("(prefers-color-scheme: dark)");
  let saved;
  try { saved = localStorage.getItem("damagebdd-theme") || localStorage.getItem("theme"); } catch (_) { /* Private/blocked storage. */ }
  let explicit = saved === "dark" || saved === "light";
  const apply = value => {
    root.dataset.theme = value;
    const button = document.getElementById("theme-toggle");
    if (button) {
      button.setAttribute("aria-label", `Switch to ${value === "dark" ? "light" : "dark"} theme`);
      button.title = button.getAttribute("aria-label");
    }
  };
  apply(explicit ? saved : preference.matches ? "dark" : "light");
  preference.addEventListener("change", event => { if (!explicit) apply(event.matches ? "dark" : "light"); });
  window.addEventListener("storage", event => {
    if (event.key !== "damagebdd-theme" && event.key !== null) return;
    explicit = event.newValue === "dark" || event.newValue === "light";
    apply(explicit ? event.newValue : preference.matches ? "dark" : "light");
  });
  document.addEventListener("DOMContentLoaded", () => {
    const button = document.getElementById("theme-toggle");
    if (!button) return;
    button.hidden = false;
    apply(root.dataset.theme);
    button.addEventListener("click", () => {
      const next = root.dataset.theme === "dark" ? "light" : "dark";
      explicit = true;
      apply(next);
      try { localStorage.setItem("damagebdd-theme", next); } catch (_) { /* Theme still works for this page. */ }
    });
  }, { once: true });
})();
