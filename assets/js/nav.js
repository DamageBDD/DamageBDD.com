(() => {
  "use strict";
  const nav = document.getElementById("primary-nav");
  const toggle = document.getElementById("menu-toggle");
  if (!nav || !toggle) return;
  const narrow = window.matchMedia("(max-width: 900px)");
  const setOpen = (open, restoreFocus = false) => {
    nav.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    toggle.setAttribute("aria-label", `${open ? "Close" : "Open"} navigation`);
    if (restoreFocus) toggle.focus();
  };
  toggle.hidden = false;
  toggle.addEventListener("click", () => setOpen(toggle.getAttribute("aria-expanded") !== "true"));
  nav.addEventListener("click", event => { if (event.target.closest("a")) setOpen(false); });
  document.addEventListener("click", event => {
    if (narrow.matches && !nav.contains(event.target) && !toggle.contains(event.target)) setOpen(false);
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && nav.classList.contains("is-open")) setOpen(false, true);
  });
  // A focused link must not become hidden when the viewport crosses the breakpoint.
  narrow.addEventListener("change", () => setOpen(false, narrow.matches && nav.contains(document.activeElement)));
  document.documentElement.dataset.navReady = "true";
  const normalize = path => path.replace(/\/index(?:\.html)?$/, "").replace(/\.html$/, "").replace(/\/$/, "");
  const current = normalize(location.pathname);
  document.querySelectorAll(".sidebar-links a, .primary-nav a").forEach(link => {
    if (normalize(new URL(link.href).pathname) === current) link.setAttribute("aria-current", "page");
  });
  // Nested article/ECAI pages identify their parent section without claiming it is the current page.
  const section = document.querySelector('meta[name="damagebdd-section"]')?.content;
  nav.querySelectorAll("a[data-section]").forEach(link => {
    if (!link.hasAttribute("aria-current") && link.dataset.section === section) link.setAttribute("aria-current", "true");
  });
})();
