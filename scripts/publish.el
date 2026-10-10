;;; publish.el --- Publish DamageBDD HTML and agent documentation -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep this file in scripts/publish.el.  Run:
;;   emacs --script scripts/publish.el
;; Or interactively: M-x damagebdd-publish
;;
;; Outputs under public/:
;;   <page>.html and <page>.md, llms.txt, sitemap.xml,
;;   docs/index.md, docs/index.json, docs/capabilities.json.
;; HTML pages advertise their Markdown alternative and /llms.txt.
;; Only an existing OpenAPI specification is copied; none is inferred.
;;
;; Optional per-page Org keywords before the first heading (author-maintained):
;;   #+CAPABILITY_ID: my-feature
;;   #+CONTENT_CLASS: implementation-reference
;;   #+IMPLEMENTATION_STATUS: implemented
;;   #+VALIDATION_STATUS: not_recorded
;;   #+VALIDATION_SCOPE: The exact scenarios covered; not a global guarantee.
;;   #+EVIDENCE_DATE: 2026-10-05
;;   #+VERIFIED_RELEASE: <release actually covered by the evidence>
;;   #+EVIDENCE_URL: https://example.org/report
;;   #+LAST_MODIFIED: 2026-10-06
;;   #+SITE_LAYOUT: document (default), home, or collection
;; Shared snippets support {{base}}, {{origin}} and {{asset:assets/path}}.
;; EVIDENCE_URL may be repeated.  Missing status is "not_recorded", never
;; inferred from prose or the build date.  DATE is the document date only.
;; Existing feature articles are recognised by path, even without these fields.
;;
;; Environment overrides: DAMAGEBDD_PROJECT_ROOT, DAMAGEBDD_SITE_URL.
;; SOURCE_DATE_EPOCH fixes the generated_at timestamp for reproducible builds.
;; Set DAMAGEBDD_PUBLISH_NO_AUTO=1 when loading this file from batch tests.
;; Uses bundled Org, ox-md and json; no MELPA packages.
;; Run publish-tests.el, site-tests.el and publish-asset-tests.el with release Emacs/Org.
;; Publication fails before rsync if snippet tokens survive or copied assets differ.
;; Configure the web server to serve .md as text/markdown; charset=utf-8 and
;; .json as application/json.  Public docs should be readable without JS.
;; Serve current docs/discovery files with Cache-Control: no-cache and ETag.
;; Header policy and atomic deployment are hosting responsibilities.
;; content_revision identifies published content, independently of build time.
;; LAST_MODIFIED accepts YYYY-MM-DD or a UTC YYYY-MM-DDTHH:MM:SSZ timestamp.
;; Otherwise clean, tracked local dependencies in a full Git checkout supply
;; last_modified; unknown dates are null and omitted from the XML sitemap.

;;; Code:
(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'url-util)
(require 'url-parse)
(require 'ox-publish)
(require 'ox-html)
(require 'ox-md)

(defvar damagebdd-project-root
  (file-name-as-directory
   (expand-file-name
    (or (getenv "DAMAGEBDD_PROJECT_ROOT")
        (expand-file-name ".." (file-name-directory
                               (or load-file-name buffer-file-name))))))
  "Project directory containing org/, assets/, snippets/ and public/.")

(defvar damagebdd-site-url
  (or (getenv "DAMAGEBDD_SITE_URL") "https://damagebdd.com")
  "Canonical public origin, optionally including a deployment path prefix.")

(defvar damagebdd-openapi-source "openapi.json"
  "Existing OpenAPI JSON under the project root, or nil.  Never synthesized.")

(defvar damagebdd-capability-pages
  '(("ecai-private-knowledge" . "articles/ecai_private_knowledge.org")
    ("ecai-relation-processing" . "articles/ecai_relation_processing.org")
    ("nostr-reliability" . "articles/nostr_reliability.org")
    ("blossom-media" . "articles/blossom_media.org")
    ("nosternity" . "articles/nosternity.org")
    ("damagebdd-nostr" . "articles/damagebdd_nostr.org")
    ("damage-nsecbunker" . "articles/damage_nsecbunker.org"))
  "Known capability IDs and Org paths; explicit CAPABILITY_ID takes precedence.")

(defvar damagebdd-entry-pages
  '("articles/features_current.org" "manual.org" "install.org"
    "modules/index.org" "node_admins.org")
  "Preferred entry pages for llms.txt; only successfully exported pages appear.")

(defvar damagebdd-html-head nil)
(defvar damagebdd-html-preamble nil)
(defvar damagebdd-html-postamble nil)
(defvar damagebdd--documents nil)
(defvar damagebdd--agent-files nil)
(defvar damagebdd--fragment-cache nil)
(defvar damagebdd--dependency-cache nil)
(defvar damagebdd--snippet-assets nil
  "Hash table of snippet asset paths and SHA-256 values for the current publish.
Bound afresh by `damagebdd-publish'; standalone snippet reads do not retain state.")
(defvar damagebdd--git-root nil)
(defvar httpd-root)
(defvar httpd-port)
(defvar httpd-host)
(declare-function httpd-start "simple-httpd")

(defun damagebdd--root (relative)
  "Resolve RELATIVE under the project root."
  (expand-file-name relative damagebdd-project-root))

(defun damagebdd--url (relative)
  "Make a canonical URL for the public RELATIVE path."
  (concat (string-remove-suffix "/" damagebdd-site-url) "/"
          (mapconcat #'url-hexify-string (split-string relative "/") "/")))

(defun damagebdd--single-line (text)
  "Collapse whitespace in TEXT for metadata and navigation."
  (string-trim (replace-regexp-in-string "[\n\r\t ]+" " " (or text ""))))

(defun damagebdd--label (text)
  "Escape TEXT for a Markdown link label."
  (replace-regexp-in-string "[][\\\\]" "\\\\&"
                            (damagebdd--single-line text)))

(defun damagebdd--read (file)
  "Read UTF-8 FILE."
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun damagebdd--hash-file (file)
  "Return the SHA-256 of FILE's bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun damagebdd--write (relative text &optional track)
  "Write TEXT to public/RELATIVE; TRACK marks a managed agent artifact."
  (let ((file (damagebdd--root (concat "public/" relative)))
        (coding-system-for-write 'utf-8-unix))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))
    (when track (cl-pushnew relative damagebdd--agent-files :test #'equal))
    file))

(defun damagebdd--write-json (relative value &optional track)
  "Write VALUE as pretty-printed JSON to RELATIVE."
  (damagebdd--write
   relative
   (with-temp-buffer
     (insert (json-encode value))
     (json-pretty-print-buffer)
     (concat (buffer-string) "\n")) track))

(defun damagebdd--read-json (file)
  "Read FILE as an alist with vectors and symbol keys."
  (let ((json-object-type 'alist) (json-array-type 'vector)
        (json-key-type 'symbol) (json-false :json-false) (json-null nil))
    (json-read-file file)))

(defun damagebdd--site-path (relative)
  "Return a local URL for RELATIVE, respecting the deployment path prefix."
  (let ((prefix (string-remove-suffix
                 "/" (or (url-filename (url-generic-parse-url damagebdd-site-url)) ""))))
    (concat prefix "/"
            (mapconcat #'url-hexify-string (split-string relative "/") "/"))))

(defun damagebdd--assert-expanded-html (html source)
  "Reject unexpanded snippet placeholders in HTML from SOURCE.
Check both literal and URL-encoded tokens: browsers encode leftover braces
before requesting a malformed asset URL.  Return HTML unchanged on success."
  (save-match-data
    (let ((case-fold-search t))
      (when (string-match
             (concat "\\(?:{{\\|%7b%7b\\)"
                     "\\(?:asset\\(?::\\|%3a\\)"
                     "\\|\\(?:base\\|origin\\)\\(?:}}\\|%7d%7d\\)\\)")
             html)
        (error "Unexpanded site placeholder in %s near: %s"
               source (substring html (match-beginning 0)
                                 (min (length html) (+ (match-beginning 0) 120)))))))
  html)

(defun damagebdd--expand-snippet (text &optional source)
  "Expand deployment and content-addressed asset placeholders in TEXT.
Only local files below assets/ are accepted.  Asset changes therefore also
change HTML hashes and the existing content_revision, without a build clock.
SOURCE, when supplied, identifies the snippet in an error message."
  (let ((expanded
         (replace-regexp-in-string
          "{{asset:\\([^}]+\\)}}"
          (lambda (token)
            ;; This must be INSIDE the callback.  replace-regexp-in-string
            ;; uses the match data again after the callback returns.  URL
            ;; parsing and file helpers may run their own regexp searches;
            ;; leaking those matches splices URLs into the wrong positions.
            (save-match-data
              (let* ((relative (substring token 8 -2))
                     (file (damagebdd--root relative)))
                (unless (and (string-prefix-p "assets/" relative)
                             (file-in-directory-p file (damagebdd--root "assets/"))
                             (file-regular-p file))
                  (error "Missing or invalid snippet asset: %s" relative))
                (let ((hash (damagebdd--hash-file file)))
                  (when damagebdd--snippet-assets
                    (puthash relative hash damagebdd--snippet-assets))
                  (concat (damagebdd--site-path relative) "?v="
                          (substring hash 0 12))))))
          text t t)))
    (setq expanded
          (replace-regexp-in-string
           "{{base}}" (string-remove-suffix "/" (damagebdd--site-path "")) expanded t t))
    (setq expanded
          (replace-regexp-in-string "{{origin}}"
                                    (string-remove-suffix "/" damagebdd-site-url)
                                    expanded t t))
    (damagebdd--assert-expanded-html expanded (or source "HTML snippet"))))

(defun damagebdd-read-snippet (relative-path)
  "Read and expand the HTML snippet at RELATIVE-PATH."
  (damagebdd--expand-snippet (damagebdd--read (damagebdd--root relative-path))
                            relative-path))

(defun damagebdd-load-html-snippets ()
  "Load existing HTML snippets without adding them to Markdown."
  (setq damagebdd-html-head (damagebdd-read-snippet "snippets/header.html")
        damagebdd-html-preamble (damagebdd-read-snippet "snippets/preamble.html")
        damagebdd-html-postamble (damagebdd-read-snippet "snippets/postamble.html")))

(defun org-sitemap-date-entry-format (entry _style project)
  "Format sitemap ENTRY for PROJECT with a visible date."
  (let* ((title (org-publish-find-title entry project))
         (file (expand-file-name entry (org-publish-property :base-directory project)))
         (date (and (file-regular-p file)
                    (damagebdd--date (damagebdd--keyword "DATE" (damagebdd--keywords file))))))
    (if (string-empty-p title) (format "*%s*" entry)
      (concat (when date (format "{{{timestamp(%s)}}} " date))
              (format "[[file:%s][%s]]" entry title)))))

(defun damagebdd--new-reference (references)
  "Allocate a deterministic export anchor unused in REFERENCES."
  (let ((reference 1))
    (while (rassq reference references) (setq reference (1+ reference)))
    reference))

;; Stable anchors are added only to the export copy, never to author sources.
(defun damagebdd--slug (title)
  "Produce a deterministic anchor from TITLE."
  (let ((slug (string-trim
               (replace-regexp-in-string "[^[:alnum:]_-]+" "-" (downcase title))
               "-+" "-+")))
    (if (string-empty-p slug) "section" slug)))

(defun damagebdd--stable-ids (&optional _backend)
  "Set missing CUSTOM_ID properties in the current export buffer."
  (let ((used (make-hash-table :test #'equal)))
    (org-map-entries
     (lambda ()
       (let ((id (org-entry-get nil "CUSTOM_ID")))
         (when id (puthash id t used)))) nil nil)
    (org-map-entries
     (lambda ()
       (unless (org-entry-get nil "CUSTOM_ID")
         (let* ((base (damagebdd--slug (org-get-heading t t t t)))
                (id base) (n 1))
           (while (gethash id used)
             (setq n (1+ n) id (format "%s-%d" base n)))
           (puthash id t used)
           (org-entry-put nil "CUSTOM_ID" id)))) nil nil)))

(defun damagebdd--fragment (file search)
  "Resolve an Org heading SEARCH in FILE to an exported stable fragment."
  (when (and search (not (string-empty-p search)))
    (if (string-prefix-p "#" search) search
      (let* ((key (cons file search))
             (cached (and damagebdd--fragment-cache
                          (gethash key damagebdd--fragment-cache 'missing))))
        (if (and cached (not (eq cached 'missing))) cached
          (let ((fragment
                 (when (file-readable-p file)
                   (with-temp-buffer
                     (unwind-protect
                         (progn
                           (insert-file-contents file)
                           (setq buffer-file-name file
                                 default-directory (file-name-directory file))
                           (org-mode)
                           (org-export-expand-include-keyword)
                           (damagebdd--stable-ids)
                           (let ((title (string-trim (replace-regexp-in-string "\\`\\*+" "" search)))
                                 found)
                             (org-map-entries
                              (lambda ()
                                (when (and (not found) (equal (org-get-heading t t t t) title))
                                  (setq found (concat "#" (org-entry-get nil "CUSTOM_ID"))))))
                             found))
                       ;; Only the disposable copy has generated anchors and
                       ;; expanded includes.  Never offer to save it over FILE,
                       ;; even when resolving the heading signals an error.
                       (set-buffer-modified-p nil)
                       (setq buffer-file-name nil))))))
            (unless fragment
              (message "Warning: unresolved Org search %s in %s; linking to page" search file))
            (when damagebdd--fragment-cache
              (puthash key (or fragment "") damagebdd--fragment-cache))
            fragment))))))

(defun damagebdd--org-link-path (link info extension)
  "Translate an Org file LINK using INFO to EXTENSION, preserving heading targets."
  (when (and (equal (org-element-property :type link) "file")
             (string-equal (downcase (or (file-name-extension
                                         (org-element-property :path link)) "")) "org"))
    (let* ((path (org-element-property :path link))
           (input (plist-get info :input-file))
           (file (expand-file-name path (if input (file-name-directory input) default-directory)))
           (fragment (damagebdd--fragment file (org-element-property :search-option link))))
      (concat (mapconcat #'url-hexify-string
                         (split-string (concat (file-name-sans-extension path) extension) "/") "/")
              (when (and fragment (not (string-empty-p fragment)))
                (concat "#" (url-hexify-string (string-remove-prefix "#" fragment))))))))

(defun damagebdd-md-link (link description info)
  "Export LINK and DESCRIPTION to Markdown using INFO."
  (let ((path (damagebdd--org-link-path link info ".md")))
    (if path
        (format "[%s](%s)" (or description (damagebdd--label (org-element-property :path link))) path)
      (org-md-link link description info))))

(defun damagebdd-html-link (link description info)
  "Export LINK and DESCRIPTION to HTML using INFO."
  (let ((path (damagebdd--org-link-path link info ".html")))
    (if path
        (format "<a href=\"%s\">%s</a>" (org-html-encode-plain-text path)
                (or description (org-html-encode-plain-text (org-element-property :path link))))
      (org-html-link link description info))))

(defun damagebdd-md-headline (headline contents info)
  "Export HEADLINE with an explicit stable anchor even without a local link."
  (let* ((rendered (org-md-headline headline contents info))
         (id (org-element-property :CUSTOM_ID headline))
         (anchor (and id (format "<a id=\"%s\"></a>" (org-html-encode-plain-text id)))))
    (if (and rendered anchor (not (string-match-p (regexp-quote anchor) rendered)))
        (concat anchor "\n\n" rendered)
      rendered)))

(defun damagebdd-md-code (element _contents info)
  "Export a code ELEMENT as a fenced block using INFO."
  (let* ((code (org-export-format-code-default element info))
         (language (or (org-element-property :language element) "text"))
         (longest 2) (start 0))
    (while (string-match "`+" code start)
      (setq longest (max longest (- (match-end 0) (match-beginning 0)))
            start (match-end 0)))
    (let ((fence (make-string (1+ longest) ?`)))
      (format "%s%s\n%s\n%s\n" fence language (string-trim-right code "\n+") fence))))

(defun damagebdd-md-table (table _contents info)
  "Export an Org TABLE as a pipe table, preserving cells through INFO."
  (let (rows)
    (dolist (row (org-element-contents table))
      (when (eq (org-element-property :type row) 'standard)
        (push (mapcar
               (lambda (cell)
                 (replace-regexp-in-string
                  "|" "\\|" (damagebdd--single-line
                               (org-export-data (org-element-contents cell) info)) t t))
               (org-element-contents row)) rows)))
    (setq rows (nreverse rows))
    (if (null rows) ""
      (let* ((width (apply #'max (mapcar #'length rows)))
             (render (lambda (row)
                       (concat "| " (mapconcat #'identity
                                               (append row (make-list (- width (length row)) ""))
                                               " | ") " |\n")))
             (caption (org-export-get-caption table)))
        (concat (when caption (concat (org-export-data caption info) "\n\n"))
                (funcall render (car rows))
                (funcall render (make-list width "---"))
                (mapconcat render (cdr rows) ""))))))

(defun damagebdd-md-export-block (block _contents _info)
  "Keep explicit Markdown BLOCK content; omit HTML layout and scripts."
  (when (member (upcase (org-element-property :type block)) '("MD" "MARKDOWN"))
    (org-remove-indentation (org-element-property :value block))))

(defun damagebdd-md-export-snippet (snippet _contents _info)
  "Keep explicit Markdown SNIPPET content only."
  (when (member (downcase (org-element-property :back-end snippet)) '("md" "markdown"))
    (org-element-property :value snippet)))

(defun damagebdd-md-inner-template (contents info)
  "Export CONTENTS with footnotes but no generated table of contents."
  (org-md-inner-template contents (org-combine-plists info '(:with-toc nil))))

(defun damagebdd-md-template (contents info)
  "Add a compact title, description and canonical link to CONTENTS using INFO."
  (let ((title (org-export-data (plist-get info :title) info))
        (description (damagebdd--single-line (plist-get info :description)))
        (canonical (plist-get info :damagebdd-canonical-url)))
    (concat "# " title "\n\n"
            (unless (string-empty-p description) (concat description "\n\n"))
            (when canonical (format "Canonical HTML: <%s>\n\n" canonical))
            (org-md-template contents
                             (org-combine-plists info '(:with-title nil :with-author nil
                                                        :with-date nil :with-toc nil))))))

(defun damagebdd--html-attribute (text)
  "Escape TEXT for a double-quoted HTML attribute."
  (replace-regexp-in-string "\"" "&quot;" (org-html-encode-plain-text (or text "")) t t))

(defun damagebdd--html-sidebar (info)
  "Build a small documentation navigation and the actual page outline from INFO.
Only existing entry pages are linked.  Search and the sitemap discover all pages."
  (let ((current (plist-get info :damagebdd-html-path))
        (entries '(("manual.org" "Quick start")
                   ("install.org" "Installation")
                   ("modules/index.org" "Module reference")
                   ("node.org" "Run a node")
                   ("node_admins.org" "Node administration")
                   ("articles/features_current.org" "Component map")))
        links outline)
    (dolist (entry entries)
      (when (file-regular-p (damagebdd--root (concat "org/" (car entry))))
        (let ((path (concat (file-name-sans-extension (car entry)) ".html")))
          (push (format "<a href=\"%s\"%s>%s</a>"
                        (org-html-encode-plain-text (damagebdd--site-path path))
                        (if (equal current path) " aria-current=\"page\"" "")
                        (cadr entry)) links))))
    (org-element-map (plist-get info :parse-tree) 'headline
      (lambda (headline)
        (let ((level (org-export-get-relative-level headline info)))
          (when (<= level 2)
            (let ((id (or (org-element-property :CUSTOM_ID headline)
                          (org-export-get-reference headline info))))
              (push (format "<a class=\"toc-depth-%d\" href=\"#%s\">%s</a>"
                            level (url-hexify-string id)
                            (org-html-encode-plain-text
                             (org-element-property :raw-value headline))) outline))))) info)
    (concat "<aside class=\"doc-sidebar\" aria-label=\"Documentation navigation\">"
            (when links
              (concat "<p class=\"sidebar-label\">Build with DamageBDD</p>"
                      "<nav class=\"sidebar-links\" aria-label=\"Documentation sections\">"
                      (mapconcat #'identity (nreverse links) "\n") "</nav>"))
            (when outline
              (concat "<nav class=\"page-outline\" aria-label=\"On this page\">"
                      "<p class=\"sidebar-label\">On this page</p>"
                      (mapconcat #'identity (nreverse outline) "\n") "</nav>"))
            "</aside>")))

(defun damagebdd-html-template (contents info)
  "Wrap exported CONTENTS in the reading layout without changing Org content.
Org remains responsible for document generation, footnotes, IDs and metadata."
  (let* ((layout (or (plist-get info :damagebdd-layout) "document"))
         (home (equal layout "home"))
         (collection (equal layout "collection"))
         (title (org-export-data (plist-get info :title) info))
         (description (damagebdd--single-line (plist-get info :description)))
         (markdown (plist-get info :damagebdd-md-path))
         (modified (plist-get info :damagebdd-modified))
         (header
          (unless home
            (concat
             "<header class=\"doc-header\">"
             (format "<nav class=\"breadcrumbs\" aria-label=\"Breadcrumb\"><a href=\"%s\">Home</a><span aria-hidden=\"true\">/</span><span>%s</span></nav>"
                     (org-html-encode-plain-text (damagebdd--site-path ""))
                     (if collection "Articles" "Documentation"))
             "<h1 class=\"title\">" title "</h1>"
             (unless (string-empty-p description)
               (concat "<p class=\"doc-description\">"
                       (org-html-encode-plain-text description) "</p>"))
             "<div class=\"doc-meta\">"
             (when modified
               (format "<span>Updated <time datetime=\"%s\">%s</time></span>"
                       (org-html-encode-plain-text modified)
                       (org-html-encode-plain-text modified)))
             (when markdown
               (format "<a href=\"%s\">Read as Markdown ↗</a>"
                       (org-html-encode-plain-text (damagebdd--site-path markdown))))
             "</div></header>")))
         (body
          (cond
           (home (concat "<div class=\"home-page\">" contents "</div>"))
           (collection (concat "<div class=\"collection-layout\"><article class=\"doc-article\">"
                               header "<div class=\"document-body\">" contents "</div></article></div>"))
           (t (concat "<div class=\"document-layout\">" (damagebdd--html-sidebar info)
                      "<article class=\"doc-article\">" header
                      "<div class=\"document-body\">" contents "</div></article></div>"))))
         (html (org-html-template body (org-combine-plists info '(:with-title nil)))))
    (setq html (replace-regexp-in-string
                "<body>" (format "<body class=\"page-%s\">" layout) html t t))
    (setq html (replace-regexp-in-string "<main id=\"content\""
                                         "<main id=\"content\" tabindex=\"-1\"" html t t))
    ;; Older bundled Org versions do not always emit a viewport declaration.
    (unless (string-match-p "<meta[^>]+name=[\"']viewport[\"']" html)
      (setq html (replace-regexp-in-string
                  "</head>" "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n</head>"
                  html t t)))
    html))

(org-export-define-derived-backend 'damagebdd-html 'html
  :options-alist '((:damagebdd-layout "SITE_LAYOUT" nil "document")
                   (:damagebdd-html-path nil nil nil)
                   (:damagebdd-md-path nil nil nil)
                   (:damagebdd-modified nil nil nil))
  :translate-alist '((link . damagebdd-html-link)
                    (template . damagebdd-html-template)))
(org-export-define-derived-backend 'damagebdd-md 'md
  :options-alist '((:damagebdd-canonical-url nil nil nil))
  :translate-alist '((link . damagebdd-md-link)
                    (headline . damagebdd-md-headline)
                    (src-block . damagebdd-md-code)
                    (example-block . damagebdd-md-code)
                    (table . damagebdd-md-table)
                    (export-block . damagebdd-md-export-block)
                    (export-snippet . damagebdd-md-export-snippet)
                    (inner-template . damagebdd-md-inner-template)
                    (template . damagebdd-md-template)))

(defun damagebdd--keywords (file)
  "Read export and capability metadata from Org FILE without evaluating code."
  (with-temp-buffer
    (insert-file-contents file)
    (org-mode)
    ;; Only file-level metadata belongs in a public inventory.  In particular,
    ;; do not harvest a keyword from a noexport subtree or a quoted code block.
    (let ((first-heading (org-element-map (org-element-parse-buffer) 'headline
                           (lambda (element) (org-element-property :begin element)) nil t)))
      ;; org-collect-keywords widens its buffer, so remove the body from this
      ;; temporary copy instead of relying on narrowing.
      (when first-heading (delete-region first-heading (point-max)))
      (org-collect-keywords
       '("TITLE" "DESCRIPTION" "DATE" "LAST_MODIFIED" "SITE_LAYOUT" "CAPABILITY_ID"
         "CONTENT_CLASS" "IMPLEMENTATION_STATUS" "VALIDATION_STATUS"
         "VALIDATION_SCOPE" "EVIDENCE_DATE" "VERIFIED_RELEASE" "EVIDENCE_URL")))))

(defun damagebdd--keyword (name keywords)
  "Read first nonempty NAME in KEYWORDS."
  (let ((value (cadr (assoc name keywords))))
    (when (and value (not (string-empty-p (string-trim value))))
      (string-trim value))))

(defun damagebdd--date (text)
  "Extract a date from TEXT, without treating a file timestamp as evidence."
  (when (and text (string-match "[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}" text))
    (match-string 0 text)))

(defun damagebdd--modified-date (value)
  "Validate a declared modification VALUE without normalizing invalid dates."
  (when value
    (unless (and (string-match-p
                  "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\(?:T[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}Z\\)?\\'" value)
                 (condition-case nil
                     (let* ((time (date-to-time (if (= (length value) 10)
                                                    (concat value "T00:00:00Z") value)))
                            (format (if (= (length value) 10) "%Y-%m-%d" "%Y-%m-%dT%H:%M:%SZ")))
                       (equal value (format-time-string format time t)))
                   (error nil)))
      (error "Invalid LAST_MODIFIED: %s (use YYYY-MM-DD or UTC timestamp)" value))
    value))

(defun damagebdd--git (&rest args)
  "Run Git ARGS without a shell; return stdout on success or nil."
  (when (executable-find "git")
    (with-temp-buffer
      (let ((default-directory damagebdd-project-root)
            (process-environment (cons "GIT_OPTIONAL_LOCKS=0" process-environment)))
        (when (zerop (apply #'process-file "git" nil (list t nil) nil
                            "--literal-pathspecs" args))
          (string-trim-right (buffer-string)))))))

(defun damagebdd--dependencies (file &optional seen)
  "Find local export inputs for FILE, including nested includes and setup files.
Return nil if any input cannot be resolved locally.  SEEN breaks cycles."
  (setq file (expand-file-name file))
  (unless (member file seen)
    (let ((cached (and damagebdd--dependency-cache
                       (gethash file damagebdd--dependency-cache 'missing))))
      (if (and cached (not (eq cached 'missing)))
          (unless (eq cached 'unknown) cached)
        (let ((files (list file)) (valid (file-readable-p file)) inputs)
          (when valid
            (with-temp-buffer
              (insert-file-contents file)
              (org-mode)
              (org-element-map (org-element-parse-buffer) '(keyword link)
                (lambda (element)
                  (cond
                   ((and (eq (org-element-type element) 'keyword)
                         (member (org-element-property :key element) '("INCLUDE" "SETUPFILE")))
                    (let ((path (car (split-string-and-unquote (org-element-property :value element)))))
                      (if path (push (car (split-string path "::")) inputs)
                        (setq valid nil))))
                   ((and (eq (org-element-type element) 'link)
                         (equal (org-element-property :type element) "file")
                         (org-element-property :search-option element))
                    ;; Heading links depend on the target's expanded headings.
                    (push (org-element-property :path element) inputs)))))))
          (dolist (input inputs)
            (setq input (string-remove-prefix "file:" input))
            (if (string-match-p "\\`[[:alpha:]][[:alnum:]+.-]*:" input)
                (setq valid nil)
              (let ((path (expand-file-name input (file-name-directory file))))
                (unless (member path (cons file seen))
                  (let ((nested (damagebdd--dependencies path (cons file seen))))
                    (if nested (setq files (append files nested)) (setq valid nil)))))))
          ;; Only cache complete root traversals: caching a cycle-truncated
          ;; subtree could miss a dirty dependency on a later page.
          (when (and damagebdd--dependency-cache (null seen))
            (puthash file (if valid (delete-dups files) 'unknown) damagebdd--dependency-cache))
          (when valid (delete-dups files)))))))

(defun damagebdd--git-modified (file)
  "Return a Git date only when FILE's known export inputs are tracked and clean."
  (when (and damagebdd--git-root
             (not (member (file-relative-name file (damagebdd--root "org/"))
                          '("sitemap.org" "theindex.org"))))
    (let* ((dependencies (damagebdd--dependencies file))
           (files (and dependencies
                       (append dependencies
                               (mapcar #'damagebdd--root
                                       '("snippets/header.html" "snippets/preamble.html"
                                         "snippets/postamble.html" "scripts/publish.el"))))))
      (when (and files (cl-every (lambda (path)
                                  (and (not (file-symlink-p path))
                                       (file-in-directory-p path damagebdd--git-root))) files))
        (let ((paths (mapcar (lambda (path) (file-relative-name path damagebdd-project-root)) files)))
          (when (and (apply #'damagebdd--git "ls-files" "--error-unmatch" "--" paths)
                     (equal "" (apply #'damagebdd--git "status" "--porcelain" "--untracked-files=all" "--" paths)))
            (let ((epoch (apply #'damagebdd--git "log" "-1" "--format=%ct" "--" paths)))
              (when (and epoch (string-match-p "\\`[0-9]+\\'" epoch))
                (format-time-string "%Y-%m-%dT%H:%M:%SZ"
                                    (seconds-to-time (string-to-number epoch)) t)))))))))

(defun damagebdd-publish-page (plist filename pub-dir)
  "Publish FILENAME to HTML and Markdown in PUB-DIR according to PLIST."
  (let* ((keywords (damagebdd--keywords filename))
         (source (file-relative-name filename (damagebdd--root "org/")))
         ;; ox-publish owns the directory layout; exported basenames follow source.
         (relative-dir (file-relative-name pub-dir (damagebdd--root "public/")))
         (stem (file-name-sans-extension (file-name-nondirectory filename)))
         (relative-base (concat (if (equal relative-dir "./") "" relative-dir) stem))
         (html-relative (concat relative-base ".html"))
         (md-relative (concat relative-base ".md"))
         (html-url (damagebdd--url html-relative))
         (md-url (damagebdd--url md-relative))
         (declared-modified (damagebdd--modified-date (damagebdd--keyword "LAST_MODIFIED" keywords)))
         (modified (or declared-modified (damagebdd--git-modified filename)))
         (layout (or (damagebdd--keyword "SITE_LAYOUT" keywords) "document"))
         (section (cond ((string-prefix-p "articles/" source) "articles")
                        ((string-prefix-p "ecai/" source) "ecai")
                        ((equal source "pricing.org") "pricing")
                        ((equal source "index.org") "home")
                        (t "docs")))
         (page-title (damagebdd--html-attribute
                      (or (damagebdd--keyword "TITLE" keywords) stem)))
         (page-description (damagebdd--html-attribute
                            (damagebdd--single-line (damagebdd--keyword "DESCRIPTION" keywords))))
         (parsing-hook (if (boundp 'org-export-before-parsing-functions)
                           'org-export-before-parsing-functions
                         'org-export-before-parsing-hook))
         (head-extra (concat (or (plist-get plist :html-head-extra) "")
                             "\n<link rel=\"canonical\" href=\""
                             (org-html-encode-plain-text html-url) "\">"
                             "\n<link rel=\"alternate\" type=\"text/markdown\" href=\""
                             (org-html-encode-plain-text md-url) "\">\n"
                             "<link rel=\"describedby\" href=\""
                             (org-html-encode-plain-text (damagebdd--url "llms.txt")) "\">"
                             "\n<meta name=\"damagebdd-section\" content=\"" section "\">"
                             "\n<meta property=\"og:title\" content=\"" page-title "\">"
                             "\n<meta property=\"og:description\" content=\"" page-description "\">"
                             "\n<meta property=\"og:url\" content=\""
                             (org-html-encode-plain-text html-url) "\">"
                             "\n<meta name=\"twitter:title\" content=\"" page-title "\">"
                             "\n<meta name=\"twitter:description\" content=\"" page-description "\">"))
         html md)
    (unless (member layout '("home" "collection" "document"))
      (error "Unsupported SITE_LAYOUT %s in %s" layout filename))
    (cl-progv (list parsing-hook)
        (list (cons #'damagebdd--stable-ids (symbol-value parsing-hook)))
      (setq html (org-publish-org-to 'damagebdd-html filename ".html"
                                  (org-combine-plists
                                   plist (list :html-head-extra head-extra
                                               :damagebdd-layout layout
                                               :damagebdd-html-path html-relative
                                               :damagebdd-md-path md-relative
                                               :damagebdd-modified modified)) pub-dir))
    (let ((org-export-global-macros '(("timestamp" . "[$1]")))
          (org-md-headline-style 'atx))
      (setq md (org-publish-org-to
                'damagebdd-md filename ".md"
                (org-combine-plists plist
                                   (list :with-toc nil :section-numbers nil
                                         :md-headline-style 'atx :md-toplevel-hlevel 2
                                         :md-link-org-files-as-md t
                                         :damagebdd-canonical-url html-url)) pub-dir))))
    (unless (and (equal (expand-file-name html) (damagebdd--root (concat "public/" html-relative)))
                 (equal (expand-file-name md) (damagebdd--root (concat "public/" md-relative))))
      (error "Unexpected export destination for %s: %s / %s" source html md))
    (cl-pushnew md-relative damagebdd--agent-files :test #'equal)
    (cl-pushnew html-relative damagebdd--agent-files :test #'equal)
    (push `((id . ,(or (damagebdd--keyword "CAPABILITY_ID" keywords)
                       (car (rassoc source damagebdd-capability-pages))))
            (title . ,(or (damagebdd--keyword "TITLE" keywords) stem))
            (summary . ,(damagebdd--single-line (damagebdd--keyword "DESCRIPTION" keywords)))
            (source_path . ,(concat "org/" source))
            (source_sha256 . ,(damagebdd--hash-file filename))
            (markdown_sha256 . ,(damagebdd--hash-file md))
            (html_sha256 . ,(damagebdd--hash-file html))
            (last_modified . ,modified)
            (last_modified_source . ,(cond (declared-modified "declared") (modified "git")))
            (html_url . ,html-url) (markdown_url . ,md-url)
            (html_path . ,html-relative) (markdown_path . ,md-relative)
            (document_date . ,(damagebdd--date (damagebdd--keyword "DATE" keywords)))
            (content_class . ,(or (damagebdd--keyword "CONTENT_CLASS" keywords) "unclassified"))
            (implementation_status . ,(or (damagebdd--keyword "IMPLEMENTATION_STATUS" keywords)
                                          "not_recorded"))
            (validation_status . ,(or (damagebdd--keyword "VALIDATION_STATUS" keywords)
                                      "not_recorded"))
            (validation_scope . ,(damagebdd--keyword "VALIDATION_SCOPE" keywords))
            (evidence_date . ,(damagebdd--date (damagebdd--keyword "EVIDENCE_DATE" keywords)))
            (verified_release . ,(damagebdd--keyword "VERIFIED_RELEASE" keywords))
            (evidence_urls . ,(vconcat (cdr (assoc "EVIDENCE_URL" keywords)))))
          damagebdd--documents)
    html))

(defun damagebdd--generated-at ()
  "Return a UTC build timestamp, respecting SOURCE_DATE_EPOCH."
  (let ((epoch (getenv "SOURCE_DATE_EPOCH")))
    (when (and epoch (not (string-match-p "\\`[0-9]+\\'" epoch)))
      (error "SOURCE_DATE_EPOCH must be a nonnegative integer"))
    (format-time-string "%Y-%m-%dT%H:%M:%SZ"
                        (when epoch (seconds-to-time (string-to-number epoch))) t)))

(defun damagebdd--doc-for-source (source)
  "Find exported document for Org-relative SOURCE."
  (cl-find (concat "org/" source) damagebdd--documents
           :key (lambda (doc) (alist-get 'source_path doc)) :test #'equal))

(defun damagebdd--doc-link (doc)
  "Create one Markdown navigation line for DOC."
  (format "- [%s](%s)%s\n"
          (damagebdd--label (alist-get 'title doc)) (alist-get 'markdown_url doc)
          (let ((summary (alist-get 'summary doc)))
            (if (string-empty-p summary) "" (concat ": " summary)))))

(defun damagebdd--copy-openapi ()
  "Copy an existing OpenAPI JSON, returning its public URL or nil."
  (let ((source (and damagebdd-openapi-source (damagebdd--root damagebdd-openapi-source))))
    (when (and source (file-exists-p source))
      (let* ((spec (damagebdd--read-json source))
             (version (alist-get 'openapi spec)))
        (unless (and (stringp version) (string-prefix-p "3." version)
                     (assq 'info spec) (assq 'paths spec))
          (error "%s must be an existing OpenAPI 3 JSON document with info and paths" source))
        ;; Preserve the supplied specification exactly, rather than editing APIs.
        (copy-file source (damagebdd--root "public/openapi.json") t)
        (cl-pushnew "openapi.json" damagebdd--agent-files :test #'equal)
        (damagebdd--url "openapi.json")))))

(defun damagebdd--content-revision (documents entries openapi)
  "Hash DOCUMENTS, navigation ENTRIES and OPENAPI independently of build time."
  (let ((json-encoding-pretty-print nil))
    (secure-hash
     'sha256
     (encode-coding-string
      (json-encode `((schema_version . 2) (site_url . ,damagebdd-site-url)
                     (documents . ,(vconcat documents))
                     (entry_sources . ,(vconcat (mapcar (lambda (doc) (alist-get 'source_path doc)) entries)))
                     (openapi . ,openapi)))
      'utf-8-unix))))

(defun damagebdd--freshness-guidance ()
  "Describe the retrieval checks required to use the current published content."
  (concat "## Freshness\n\n"
          (format "Before using cached documentation, revalidate [the document inventory](%s). "
                  (damagebdd--url "docs/index.json"))
          "Compare content_revision, fetch changed documents, and verify the SHA-256 "
          "of their decoded HTTP response bytes against markdown_sha256 or html_sha256. "
          "Remove cached documents that are absent from the current inventory. "
          "Check docs/capabilities.json has the same content_revision before combining it with the inventory. "
          "On a hash or revision mismatch, refresh the inventory and retry; do not combine releases. "
          "Record the revision and retrieval time with your answer. If revalidation fails, "
          "say freshness could not be verified. These checks must be implemented by the consuming agent.\n\n"
          "generated_at is the build time. last_modified describes document inputs when known; "
          "evidence_date and verified_release retain their historical meaning. "
          "A new documentation revision does not establish new runtime verification.\n\n"))

(defun damagebdd--discovery ()
  "Generate navigation, document inventory, capabilities and XML sitemap."
  (setq damagebdd--documents
        (sort damagebdd--documents
              (lambda (a b) (string< (alist-get 'source_path a) (alist-get 'source_path b)))))
  (let* ((generated (damagebdd--generated-at))
         (capabilities (cl-remove-if-not (lambda (doc) (alist-get 'id doc)) damagebdd--documents))
         (entries (delq nil (mapcar #'damagebdd--doc-for-source damagebdd-entry-pages)))
         (openapi-url (damagebdd--copy-openapi))
         (openapi (when openapi-url
                    `((url . ,openapi-url)
                      (sha256 . ,(damagebdd--hash-file (damagebdd--root "public/openapi.json"))))))
         (revision (damagebdd--content-revision damagebdd--documents entries openapi))
         (seen (make-hash-table :test #'equal)))
    (dolist (doc capabilities)
      (let ((id (alist-get 'id doc)))
        (when (gethash id seen) (error "Duplicate CAPABILITY_ID: %s" id))
        (puthash id t seen)))
    (dolist (doc damagebdd--documents)
      (when (member (alist-get 'markdown_path doc) '("docs/index.md"))
        (error "org/docs/index.org conflicts with the generated docs/index.md")))
    (damagebdd--write-json
     "docs/index.json"
     `((schema_version . 2) (site_url . ,damagebdd-site-url) (generated_at . ,generated)
       (content_revision . ,revision)
       (openapi . ,openapi)
       (document_count . ,(length damagebdd--documents))
       (documents . ,(vconcat damagebdd--documents))) t)
    (damagebdd--write-json
     "docs/capabilities.json"
     `((schema_version . 2) (site_url . ,damagebdd-site-url) (generated_at . ,generated)
       (content_revision . ,revision)
       (inventory_url . ,(damagebdd--url "docs/index.json"))
       (status_semantics . "Statuses are author-supplied Org metadata; not_recorded means absent. Build time is not verification time. Evidence is historical, not a live health check.")
       (openapi_url . ,openapi-url)
       (openapi_sha256 . ,(alist-get 'sha256 openapi))
       (capabilities . ,(vconcat capabilities))) t)
    (damagebdd--write
     "docs/index.md"
     (concat "# DamageBDD documentation index\n\n"
             "Generated from the same Org sources as the HTML site. "
             "Follow a topic link rather than loading the entire site.\n\n"
             "Implementation and validation are separate. A build timestamp does not establish verification.\n\n"
             (damagebdd--freshness-guidance)
             "## Start here\n\n" (mapconcat #'damagebdd--doc-link entries "")
             "\n## Feature references\n\n" (mapconcat #'damagebdd--doc-link capabilities "")
             "\n## All exported documents\n\n"
             (mapconcat #'damagebdd--doc-link damagebdd--documents "")) t)
    (damagebdd--write
     "llms.txt"
     (concat "# DamageBDD\n\n"
             "> Behaviour verification, ECAI knowledge retrieval and Nostr signing infrastructure.\n\n"
             "Use the current feature references for implementation details. "
             "Conceptual and historical articles may describe broader goals. "
             "Read each feature's validation limits and evidence date; do not infer that "
             "all components share the same release or verification status.\n\n"
             (damagebdd--freshness-guidance)
             "## Start here\n\n" (mapconcat #'damagebdd--doc-link entries "")
             (format "- [Documentation index](%s): All exported topics.\n" (damagebdd--url "docs/index.md"))
             "\n## Features\n\n" (mapconcat #'damagebdd--doc-link capabilities "")
             "\n## Machine-readable references\n\n"
             (format "- [Capabilities](%s): Explicit status, release and evidence fields.\n"
                     (damagebdd--url "docs/capabilities.json"))
             (format "- [Document inventory](%s): URLs, dates and content hashes.\n"
                     (damagebdd--url "docs/index.json"))
             (when openapi-url (format "- [OpenAPI](%s): Supplied HTTP API contract.\n" openapi-url))) t)
    (damagebdd--write
     "sitemap.xml"
     (concat "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
             "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
             (mapconcat (lambda (doc)
                          (format "  <url><loc>%s</loc>%s</url>\n"
                                  (org-html-encode-plain-text (alist-get 'html_url doc))
                                  (if-let ((modified (alist-get 'last_modified doc)))
                                      (format "<lastmod>%s</lastmod>" modified) "")))
                        damagebdd--documents "") "</urlset>\n") t)))

(defun damagebdd--validate-snippet-assets ()
  "Require every snippet asset to be copied intact into public/.
Hash the deployed bytes, not merely the source file.  This catches missing
attachment extensions, skipped copies and asset changes during the build."
  (when damagebdd--snippet-assets
    (maphash
     (lambda (relative expected-hash)
       (let* ((public (damagebdd--root "public/"))
              (file (expand-file-name relative public)))
         (unless (and (file-in-directory-p file public)
                      (file-regular-p file))
           (error "Missing published snippet asset: public/%s" relative))
         (unless (equal expected-hash (damagebdd--hash-file file))
           (error "Published snippet asset differs from its versioned source: public/%s"
                  relative))))
     damagebdd--snippet-assets)))

(defun damagebdd--validate-artifacts ()
  "Check generated JSON, HTML, copied assets and links without network calls."
  (damagebdd--validate-snippet-assets)
  (dolist (path '("docs/index.json" "docs/capabilities.json"))
    (damagebdd--read-json (damagebdd--root (concat "public/" path))))
  (dolist (doc damagebdd--documents)
    (dolist (pair '((html_path . html_sha256) (markdown_path . markdown_sha256)))
      (let ((file (damagebdd--root (concat "public/" (alist-get (car pair) doc)))))
        (unless (and (file-regular-p file)
                     (equal (alist-get (cdr pair) doc) (damagebdd--hash-file file)))
          (error "Missing or changed exported target: %s" (alist-get (car pair) doc)))
        (when (eq (car pair) 'html_path)
          (damagebdd--assert-expanded-html (damagebdd--read file)
                                           (alist-get 'html_path doc))))))
  (let ((index (damagebdd--read-json (damagebdd--root "public/docs/index.json")))
        (caps (damagebdd--read-json (damagebdd--root "public/docs/capabilities.json"))))
    (unless (equal (alist-get 'content_revision index) (alist-get 'content_revision caps))
      (error "Documentation inventories have mismatched revisions")))
  (dolist (path '("llms.txt" "docs/index.md"))
    (with-temp-buffer
      (insert-file-contents (damagebdd--root (concat "public/" path)))
      (goto-char (point-min))
      (while (re-search-forward "](\\([^ )\n]+\\))" nil t)
        (let* ((url (match-string 1))
               (prefix (concat (string-remove-suffix "/" damagebdd-site-url) "/")))
          (when (string-prefix-p prefix url)
            (let ((relative (decode-coding-string (url-unhex-string (substring url (length prefix))) 'utf-8)))
              (unless (file-regular-p (damagebdd--root (concat "public/" relative)))
                (error "Broken discovery link in %s: %s" path url)))))))))

(defun damagebdd--finish-managed-files (previous)
  "Record managed files and remove only unchanged obsolete files from PREVIOUS."
  (let ((public (file-truename (damagebdd--root "public/"))))
    (mapc
     (lambda (entry)
       (let* ((path (alist-get 'path entry))
              (hash (alist-get 'sha256 entry))
              (file (and (stringp path) (expand-file-name path public))))
         (when (and file (not (file-name-absolute-p path))
                    (file-in-directory-p file public)
                    (not (member path damagebdd--agent-files))
                    (not (file-symlink-p file)) (file-regular-p file)
                    (equal hash (damagebdd--hash-file file)))
           (delete-file file))))
     previous)
    (damagebdd--write-json
     ".damagebdd-agent-files.json"
     (vconcat (mapcar
               (lambda (path)
                 `((path . ,path) (sha256 . ,(damagebdd--hash-file (expand-file-name path public)))))
               (sort (copy-sequence damagebdd--agent-files) #'string<))))))

;;;###autoload
(defun damagebdd-publish ()
  "Publish HTML, Markdown and agent references from the same Org sources."
  (interactive)
  (let* ((parsed-url (url-generic-parse-url damagebdd-site-url))
         (damagebdd--documents nil) (damagebdd--agent-files nil)
         (damagebdd--fragment-cache (make-hash-table :test #'equal))
         (damagebdd--dependency-cache (make-hash-table :test #'equal))
         (damagebdd--snippet-assets (make-hash-table :test #'equal))
         (damagebdd--git-root (when (equal "false" (damagebdd--git "rev-parse" "--is-shallow-repository"))
                               (damagebdd--git "rev-parse" "--show-toplevel")))
         (previous-file (damagebdd--root "public/.damagebdd-agent-files.json"))
         (previous (when (file-readable-p previous-file) (damagebdd--read-json previous-file)))
         (org-export-global-macros '(("timestamp" . "@@html:<span class=\"timestamp\">[$1]</span>@@")))
         (org-export-use-babel nil) (org-export-in-background nil)
         (org-export-with-toc nil)
         (org-html-htmlize-output-type
          (if (require 'htmlize nil t) org-html-htmlize-output-type nil))
         (org-publish-use-timestamps-flag nil)
         (org-publish-cache nil)
         (org-publish-timestamp-directory (damagebdd--root ".org-timestamps/"))
         (vc-handled-backends nil)
         org-publish-project-alist)
    (unless (and (member (url-type parsed-url) '("https" "http"))
                 (url-host parsed-url) (not (url-target parsed-url))
                 (not (string-match-p "[?\n\r]" damagebdd-site-url)))
      (error "DAMAGEBDD_SITE_URL must be an absolute HTTP(S) base URL without query or fragment"))
    (damagebdd-load-html-snippets)
    (setq org-publish-project-alist
          `(("damagebdd" :components ("damagebdd.pages" "damagebdd.static"
                                      "damagebdd.articles" "damagebdd.papers"))
            ("damagebdd.pages"
             :base-directory ,(damagebdd--root "org") :base-extension "org"
             :publishing-directory ,(damagebdd--root "public") :recursive t
             :publishing-function damagebdd-publish-page :auto-preamble t
             :auto-sitemap t :auto-index t :makeindex t
             ;; The index is regenerated and exported by :makeindex.  Exclude
             ;; its previous source from discovery so the first build agrees
             ;; with later builds and old index entries cannot feed back in.
             :exclude "\\`theindex\\.org\\'"
             :sitemap-title "DamageBDD - BDD At Planetary Scale."
             :sitemap-filename "sitemap.org" :sitemap-sort-files alphabetically
             :sitemap-format-entry org-sitemap-date-entry-format :with-toc nil
             :html-doctype "html5" :html-html5-fancy t
             :html-divs ((preamble "div" "preamble") (content "main" "content")
                          (postamble "div" "postamble"))
             :section-numbers nil :with-author nil :with-creator nil
             :time-stamp-file nil
             :html-head-include-scripts nil :html-head-include-default-style nil
             :html-head ,damagebdd-html-head :html-preamble ,damagebdd-html-preamble
             :html-postamble ,damagebdd-html-postamble)
            ("damagebdd.papers"
             :base-directory ,(damagebdd--root "org/papers") :base-extension "jpeg\\|pdf"
             :publishing-directory ,(damagebdd--root "public/papers") :recursive t
             :publishing-function org-publish-attachment)
            ("damagebdd.articles"
             :base-directory ,(damagebdd--root "org/articles")
             :base-extension "jpeg\\|jpg\\|png\\|webp\\|svg\\|pdf"
             :publishing-directory ,(damagebdd--root "public/articles") :recursive t
             :publishing-function org-publish-attachment)
            ("damagebdd.static"
             :base-directory ,(damagebdd--root "assets")
             :base-extension "css\\|js\\|png\\|jpg\\|jpeg\\|gif\\|webp\\|pdf\\|mp3\\|ogg\\|swf\\|ttf\\|map\\|svg\\|woff\\|woff2\\|ico\\|avif"
             :publishing-directory ,(damagebdd--root "public/assets") :recursive t
             :publishing-function org-publish-attachment)))
    ;; Org's default random anchors and export-time HTML comment would change
    ;; hashes on every build even when the published content is unchanged.
    (cl-letf (((symbol-function 'org-export-new-reference) #'damagebdd--new-reference))
      (org-publish-project "damagebdd" t))
    (damagebdd--discovery)
    (damagebdd--validate-artifacts)
    (damagebdd--finish-managed-files previous)
    (message "DamageBDD published: %d HTML/Markdown pages, llms.txt and JSON references."
             (length damagebdd--documents))))

;;;###autoload
(defun publish-and-serve ()
  "Publish and serve the site locally with simple-httpd."
  (interactive)
  (damagebdd-publish)
  (add-to-list 'load-path (damagebdd--root "scripts"))
  (require 'simple-httpd)
  (setq httpd-root (damagebdd--root "public")
        httpd-host (or (getenv "DAMAGEBDD_PREVIEW_HOST") "127.0.0.1")
        httpd-port (string-to-number (or (getenv "DAMAGEBDD_PREVIEW_PORT") "8081")))
  (unless (<= 1 httpd-port 65535)
    (error "DAMAGEBDD_PREVIEW_PORT must be between 1 and 65535"))
  (unless (process-status "httpd") (httpd-start))
  (message "DamageBDD preview: http://%s:%d/" httpd-host httpd-port))

(defun damagebdd-rsync-deploy (node)
  "Publish, then deploy public/ to NODE via rsync over SSH."
  (interactive (list (read-string "Enter user@node: " "root@node0")))
  (damagebdd-publish)
  (let ((default-directory damagebdd-project-root))
    (async-shell-command
     (format "rsync -avz --delete -e ssh public/ %s"
             (shell-quote-argument (concat node ":/var/www/damagebdd.com/")))
     "*DamageBDD Deploy*")))

(provide 'publish)
(when (and noninteractive (not (getenv "DAMAGEBDD_PUBLISH_NO_AUTO")))
  (damagebdd-publish))
;;; publish.el ends here
