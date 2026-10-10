# DamageBDD.com

The DamageBDD product and documentation site. Write in Org; publish a static
site with Emacs. The source remains readable without the website, and the
website remains readable without JavaScript.

## Build

From the repository root:

```sh
sh scripts/publish.sh
```

The script prefers local Emacs. If it is absent, the existing Docker fallback
uses `silex/emacs:latest`. Set `DAMAGEBDD_EMACS_IMAGE` to your tested image or
pinned digest for reproducible production builds. No Node, npm, React or CSS
build step is required.

Direct Emacs invocation, without Docker:

```sh
emacs -Q --script scripts/publish.el
```

Both paths call `damagebdd-publish`, not a bare `org-publish-project`: discovery
files, paired Markdown, freshness metadata and managed-file cleanup are part
of the same build. Do not combine auto-publication with a second explicit call.

Generated output is written to `public/`:

```text
<page>.html                 Human-readable page
<page>.md                   Markdown from the same Org source
assets/                    Local styles, scripts and existing media
llms.txt                   Agent discovery
sitemap.html, sitemap.xml   Human/machine navigation
docs/index.md              Documentation directory
docs/index.json            Search inventory and content hashes
docs/capabilities.json      Author-supplied status and evidence metadata
```

An existing OpenAPI file is copied when present; the publisher does not infer
an API contract. Never edit `public/` as the content source.

## Preview

```sh
sh scripts/preview.sh
```

Preview requires local Emacs and uses the bundled `scripts/simple-httpd.el`.
Open `http://127.0.0.1:8081/`; stop the foreground process with Ctrl+C. The named
preview daemon is separate from a normal Emacs server. To change its binding:

```sh
DAMAGEBDD_PREVIEW_HOST=127.0.0.1 DAMAGEBDD_PREVIEW_PORT=8082 sh scripts/preview.sh
```

The shell scripts resolve paths from their own location, not the caller’s
working directory. `DAMAGEBDD_PROJECT_ROOT` is available for direct publisher
use with a separate source tree.

## Edit the site

| Source | Responsibility |
| --- | --- |
| `org/index.org` | Homepage copy and its native Org sections |
| `org/articles/index.org`, `index.inc` | Curated article directory |
| `org/**/*.org` | Documentation and articles |
| `snippets/header.html` | Shared head assets; no page-specific canonical |
| `snippets/preamble.html` | Brand, navigation, search entry and theme control |
| `snippets/postamble.html` | Footer and native search dialog |
| `assets/css/damage.css`, `nav.css` | Shared design and responsive layout |
| `assets/js/theme.js` | Theme before first paint; guarded local storage |
| `assets/js/nav.js` | Responsive disclosure and current-section markers |
| `assets/js/site.js` | Code copy, Gherkin highlighting, tables and heading links |
| `assets/js/search.js` | Lazy search of the generated inventory |
| `scripts/publish.el` | HTML layout, paired exports, metadata and discovery |

System fonts are used. The existing DamageBDD logo, book and media assets are
retained. The shared shell loads no third-party runtime or font service.
Existing page-specific integrations, including pricing and the Nostr feed,
remain separate and may contact their own external services.

### Layouts

Ordinary pages need no change:

```org
#+TITLE: A readable page title
#+DESCRIPTION: A useful one-sentence summary for readers and search.
#+SITE_LAYOUT: document
```

`document` is the default: readable content, documentation navigation, an
outline of exported headings, and a Markdown alternative. The sidebar links
only entry pages that exist in the source tree.

`collection` gives native top-level headings a directory-card layout.
`home` supplies the wide landing-page layout and lets its Org source provide
the single hero H1. Unsupported layout values fail the build.

Home sections use `HTML_CONTAINER_CLASS` properties instead of duplicating
all their text in raw HTML. Keep ordinary prose, links, tables and examples in
Org. Raw HTML is reserved for layout. Critical links in HTML-only blocks have
explicit Markdown export equivalents.

### Paths and asset freshness

Shared snippets support these publisher-expanded placeholders:

```html
<a href="{{base}}/manual.html">Documentation</a>
<link rel="stylesheet" href="{{asset:assets/css/damage.css}}">
<meta property="og:image" content="{{origin}}/assets/img/og-damagebdd.png">
```

`{{base}}` is the deployment path prefix; `{{origin}}` is the canonical site
base URL, including that prefix. `{{asset:...}}` validates a file under
`assets/` and appends the first 12 hexadecimal characters of its SHA-256.
Changing a referenced CSS/JS asset therefore changes the page HTML hash and
existing content revision. Missing or escaping asset references fail export.

```sh
DAMAGEBDD_SITE_URL=https://example.org/docs sh scripts/publish.sh
SOURCE_DATE_EPOCH=0 sh scripts/publish.sh
```

The shared shell and new homepage links support a prefix. Older page-specific
raw HTML and widgets can still contain absolute root paths; audit those before
moving the entire historical site beneath a subdirectory. Existing output
filenames are retained. New navigation uses explicit `.html` targets so the
local static preview does not require extensionless-route rewrites.

Search reads `docs/index.json` on demand with revalidation, without a separate
hard-coded page inventory. It searches titles, summaries and document paths,
not full page bodies. It has keyboard navigation, an eight-second timeout,
retry on reopen, and a sitemap fallback. Adding/removing an exported page
updates search on the next publication.

### Truth and dates

Do not use a build time as a validation claim. `generated_at`, document
`last_modified`, content hashes and author-supplied evidence fields retain
their distinct meanings. The UI displays an updated date only when the
publisher knows one. Component implementation and live verification are
separate; absent validation metadata remains `not_recorded`.

See `scripts/publish_agent_docs.txt` for the existing agent-documentation and
hosting contract.

## Verify before release

Run all existing publisher regressions plus the new presentation tests:

```sh
emacs -Q --batch \
  -l scripts/publish-tests.el \
  -l scripts/site-tests.el \
  -f ert-run-tests-batch-and-exit

sh scripts/publish.sh
sh scripts/preview.sh
```

The added tests cover layout opt-in, one title/canonical/viewport, semantic
main content, available sidebar entries, escaped metadata, asset validation,
prefixed asset URLs, clean Markdown and HTML revision changes after CSS edits.

In the native preview, check the homepage, manual, articles and pricing at
320px, 390px, 768px and desktop widths. Exercise mobile navigation, Tab/Escape,
Ctrl/Cmd+K, an unavailable inventory, code-copy permission denial, light/dark
preferences, no JavaScript, print and long tables. Test the live pricing and
Nostr integrations separately against the intended deployment.

The build and browser validation performed for this change, including its
limits, are recorded in `MODERNIZATION.md`.

## Deployment

Building does not deploy. The legacy deployment actions remain explicit:

```sh
DAMAGEBDD_LOCAL_TARGET=/var/www/damagebdd/ sh scripts/publish.sh sync
DAMAGEBDD_DEPLOY_TARGET=user@host:/var/www/damagebdd/ sh scripts/publish.sh sync_prod
```

These actions use `rsync --delete` after a successful build. Review the target
and preserve a rollback before invoking them. Atomic deployment, headers,
ETags and cache policy remain hosting responsibilities. Serve Markdown with
`text/markdown; charset=utf-8`, JSON with `application/json`, and revalidate
HTML/discovery files rather than marking them immutable. Asset query hashes
are cache-version hints, not a substitute for an appropriate server policy.

The public static `use.html` page now points users to the existing hosted
dashboard and setup guides. It does not ask for wallet signatures or create
invoices. Legacy transaction assets are retained but are not loaded in the
shared documentation shell.
