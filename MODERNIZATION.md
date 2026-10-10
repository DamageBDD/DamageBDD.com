# DamageBDD.com modernization — implementation and validation

## Delivered source changes

The uploaded Org-publish project remains the source of truth. The modernization
adds a shared product/documentation design without introducing an application
framework, npm pipeline or external font dependency.

The homepage now leads with “Don’t just ship code. Ship evidence.”, an explicitly
illustrative Gherkin example, adoption paths, an ecosystem overview and the
existing book. The existing logo and source media are preserved.

The documentation layout adds a readable content column, existing-page sidebar,
actual-heading outline, Markdown alternative and known modification date when
available. The article directory uses native Org headings as cards. The shared
header/footer include responsive navigation, OS-aware light/dark controls, a skip
link and local inventory search. Code examples gain copy controls and Gherkin
highlighting; wide tables gain keyboard-accessible scrolling when needed.

The publisher still owns HTML/Markdown exports, deterministic IDs, source and
output hashes, content_revision, capability metadata, sitemap, llms.txt and
managed-output cleanup. Shared assets receive SHA-256-based query versions.
Page-specific canonical/social metadata replace the duplicate shared canonical.

Build scripts now resolve their own directory, publish once and deploy only when
an explicit deployment action is requested. Preview defaults to loopback. The
static use page links to the existing dashboard rather than loading the old
wallet-signing/invoice form. Legacy transaction assets remain in the source tree
but are not loaded globally. Pricing and the Nostr social feed remain separate
page-specific integrations; their commercial content and live APIs were not
revalidated or rewritten in this presentation change.

## Checks executed here

**40/40 in-memory Chromium browser checks passed.** The three
layout types were checked at 320, 390, 768, 1024 and 1440 CSS pixels for document
width, one H1 and shared-script runtime errors. Additional checks covered mobile
menu state, dashboard access, outside click/Escape, focus restoration, OS theme
changes, storage denial, lazy search, keyboard navigation, failed-index retry,
empty results, path validation, literal-text rendering, code selection/copy,
reduced motion and light/dark no-JavaScript reading/navigation.

The search test found and fixed a real Escape-key interaction: a search input
could consume Escape to clear its value without closing the dialog. The shared
script now explicitly closes the dialog and restores focus.

**20/20 static and command-dispatch checks passed.** These
include JavaScript syntax, POSIX shell syntax, Elisp lexical delimiter/string
balance, maintained-page local link targets, unique IDs, build invocation count,
failed-export deployment prevention, invalid-action rejection, preview command
construction and `git diff --check`. Shell dispatch used command doubles; it did
not start Emacs, Docker, rsync or a production deployment. Two article links with
Org heading-search suffixes were checked at the target-file level only; exact
native fragment resolution remains part of the publisher ERT suite.

## Important validation boundary

**The native Emacs/Org build and ERT tests were not executed in this environment.**
Emacs is not installed here, and package installation was unavailable. The
existing 12 ERT tests are retained; 8 presentation/export tests are added, for
20 available tests. Elisp lexical checking is not an Emacs evaluation or proof
of exporter compatibility.

The browser previews are **source-derived layout fixtures**, built by parsing
Org with Pandoc and reproducing the intended Org containers and shared template.
They are not generated output from `scripts/publish.el` and are not a deployable
site build. Browser navigation to a local preview server was unavailable, so
screenshots and interactions were rendered in memory. Shared CSS and JavaScript
were used unchanged. Search used a controlled inventory transport fixture;
clipboard-success used a mock. Native dialog behaviour, responsive CSS, blocked
storage and clipboard-selection fallback were exercised in the browser.

No native output hashes, real HTTP caching, live pricing, relay connections,
wallet flows, remote destinations or deployment were verified. No deployment
was performed. The full historical link corpus has not been repaired; legacy
page-specific root-relative paths still need review for subdirectory hosting.

## Release gate on your machine

```sh
emacs -Q --batch \
  -l scripts/publish-tests.el \
  -l scripts/site-tests.el \
  -f ert-run-tests-batch-and-exit

sh scripts/publish.sh
sh scripts/preview.sh
```

Open the native preview at `http://127.0.0.1:8081/`. Check home, manual, articles,
pricing and social pages. Verify the actual exported `docs/index.json`, canonical
and Markdown links, search, keyboard interactions, theme persistence, long
tables and print. Production remains the existing Org pipeline; no Pandoc
renderer or fixture HTML is included in the source deliverable.

## Suggested commit

```text
feat(site): modernize Org product and documentation experience

- redesign homepage, navigation, article directory and reading layouts
- add accessible inventory search, theme controls and code-copy enhancements
- preserve paired exports, discovery files and evidence/freshness semantics
- version shared assets by content and emit page-specific social metadata
- remove global wallet runtime from static documentation
- harden build/preview entry points and add presentation export regressions
```
