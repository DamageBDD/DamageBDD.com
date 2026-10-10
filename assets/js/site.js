/* Progressive reading enhancements; content and navigation work without this. */
(() => {
  "use strict";
  const main = document.getElementById("content");
  if (!main) return;
  const announce = message => {
    const live = document.getElementById("site-status");
    if (live) live.textContent = message;
  };
  // Keep the skip link focusable in both Org and fallback HTML exports.
  main.tabIndex = -1;
  const highlightGherkin = pre => {
    if (pre.querySelector(".code-keyword")) return;
    const text = pre.textContent;
    if (!/^(\s*)(Feature:|Scenario:)/m.test(text)) return;
    const fragment = document.createDocumentFragment();
    const pattern = /(\b(?:Feature|Scenario Outline|Scenario|Background|Examples):|\b(?:Given|When|Then|And|But)\b|"[^"\n]*"|#[^\n]*)/g;
    let position = 0;
    for (const match of text.matchAll(pattern)) {
      fragment.append(document.createTextNode(text.slice(position, match.index)));
      const span = document.createElement("span");
      span.className = match[0].startsWith('"') ? "code-string" : match[0].startsWith("#") ? "code-comment" : "code-keyword";
      span.textContent = match[0];
      fragment.append(span);
      position = match.index + match[0].length;
    }
    fragment.append(document.createTextNode(text.slice(position)));
    pre.replaceChildren(fragment);
  };
  main.querySelectorAll("pre").forEach((pre, index) => {
    if (pre.closest(".code-block")) return;
    const text = pre.textContent;
    const language = pre.dataset.language || [...pre.classList].find(name => name.startsWith("src-"))?.slice(4) || pre.querySelector("code")?.className.replace("language-", "") || "Code";
    highlightGherkin(pre);
    const wrapper = document.createElement("div");
    wrapper.className = "code-block";
    const toolbar = document.createElement("div");
    toolbar.className = "code-toolbar";
    const label = document.createElement("span");
    label.className = "code-toolbar-label";
    label.textContent = language;
    const button = document.createElement("button");
    button.type = "button";
    button.className = "copy-button";
    button.textContent = "Copy";
    button.setAttribute("aria-label", `Copy ${language} example ${index + 1}`);
    button.addEventListener("click", async () => {
      try {
        if (!navigator.clipboard?.writeText) throw new Error("Clipboard unavailable");
        await navigator.clipboard.writeText(text);
        button.textContent = "Copied";
        announce("Code copied to clipboard.");
      } catch (_) {
        // Do not report success when browser permissions or secure-context checks fail.
        const range = document.createRange();
        range.selectNodeContents(pre);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        button.textContent = "Selected";
        announce("Code selected. Use your device’s copy command to copy it.");
      }
      window.setTimeout(() => { button.textContent = "Copy"; }, 2200);
    });
    toolbar.append(label, button);
    pre.before(wrapper);
    wrapper.append(toolbar, pre);
  });
  main.querySelectorAll("table").forEach(table => {
    if (table.closest(".table-scroll")) return;
    const wrapper = document.createElement("div");
    wrapper.className = "table-scroll";
    wrapper.setAttribute("role", "region");
    wrapper.setAttribute("aria-label", table.caption?.textContent.trim() || "Scrollable data table");
    table.before(wrapper);
    wrapper.append(table);
    const update = () => { wrapper.tabIndex = wrapper.scrollWidth > wrapper.clientWidth + 1 ? 0 : -1; };
    update();
    if ("ResizeObserver" in window) new ResizeObserver(update).observe(wrapper);
  });
  main.querySelectorAll(".document-body h2[id], .document-body h3[id]").forEach(heading => {
    if (heading.closest("#table-of-contents") || heading.querySelector(".heading-anchor")) return;
    const anchor = document.createElement("a");
    anchor.className = "heading-anchor";
    anchor.href = `#${encodeURIComponent(heading.id)}`;
    anchor.textContent = "#";
    anchor.setAttribute("aria-label", `Link to ${heading.textContent.trim()}`);
    heading.append(anchor);
  });
  // Highlight the visible section; all outline links are present in the HTML already.
  const outline = document.querySelector(".page-outline");
  if (outline && "IntersectionObserver" in window) {
    const observer = new IntersectionObserver(entries => {
      const visible = entries.find(entry => entry.isIntersecting);
      if (!visible) return;
      outline.querySelectorAll("a").forEach(link => {
        if (decodeURIComponent(link.hash.slice(1)) === visible.target.id) link.setAttribute("aria-current", "location");
        else link.removeAttribute("aria-current");
      });
    }, { rootMargin: "-110px 0px -65% 0px", threshold: 0 });
    main.querySelectorAll(".document-body h2[id], .document-body h3[id]").forEach(heading => observer.observe(heading));
  }
})();
