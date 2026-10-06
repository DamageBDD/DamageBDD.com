;;; publish-tests.el --- Integration checks for the Org publisher -*- lexical-binding: t; -*-
;; Run: emacs -Q --batch -l scripts/publish-tests.el -f ert-run-tests-batch-and-exit
(require 'ert)
(defconst damagebdd-test--publisher-file
  (expand-file-name "publish.el" (file-name-directory (or load-file-name buffer-file-name))))
(let ((process-environment (copy-sequence process-environment)))
  (setenv "DAMAGEBDD_PUBLISH_NO_AUTO" "1")
  (load-file damagebdd-test--publisher-file))

(defun damagebdd-test--put (relative text)
  (let ((file (expand-file-name relative damagebdd-project-root)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

(defmacro damagebdd-test--site (&rest body)
  (declare (indent 0))
  `(let* ((damagebdd-project-root (file-name-as-directory (make-temp-file "damagebdd-publish-test-" t)))
          (damagebdd-site-url "https://example.invalid/docs")
          (damagebdd-entry-pages '("index.org"))
          (damagebdd-capability-pages nil)
          (damagebdd-openapi-source "openapi.json")
          (process-environment (copy-sequence process-environment)))
     (unwind-protect
         (progn
           (setenv "SOURCE_DATE_EPOCH" "0")
           (dolist (dir '("org/articles" "org/papers" "assets"))
             (make-directory (expand-file-name dir damagebdd-project-root) t))
           (damagebdd-test--put "snippets/header.html" "<meta name=\"test\" content=\"yes\">")
           (damagebdd-test--put "snippets/preamble.html" "<nav>NAVIGATION-MARKER</nav>")
           (damagebdd-test--put "snippets/postamble.html" "<footer>FOOTER-MARKER</footer>")
           ,@body)
       (dolist (buffer (buffer-list))
         (let ((file (buffer-local-value 'buffer-file-name buffer)))
           (when (and file (string-prefix-p damagebdd-project-root file))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer))))
       (delete-directory damagebdd-project-root t))))

(defmacro damagebdd-test--record-dirty-file-disposals (disposals &rest body)
  "Record file buffers killed with unsaved changes while evaluating BODY.
Batch Emacs skips the interactive confirmation, so observe its trigger at
kill time instead.  This also covers temporary buffers with inhibited hooks."
  (declare (indent 1))
  `(let ((real-kill-buffer (symbol-function 'kill-buffer)))
     (cl-letf (((symbol-function 'kill-buffer)
                (lambda (&optional buffer)
                  (with-current-buffer (or buffer (current-buffer))
                    (when (and buffer-file-name (buffer-modified-p))
                      (push (buffer-name) ,disposals)))
                  (funcall real-kill-buffer buffer))))
       ,@body)))

(ert-deftest damagebdd-fragment-cleanup-does-not-prompt-or-touch-author-buffer ()
  (damagebdd-test--site
    (damagebdd-test--put "org/chapter.org" "#+TITLE: Chapter\n* Details\nSaved text.\n")
    (damagebdd-test--put "org/part.inc" "* Included\nIncluded text.\n")
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\n#+INCLUDE: \"part.inc\"\n")
    (let* ((file (damagebdd--root "org/chapter.org"))
           (before (damagebdd--hash-file file))
           (author (find-file-noselect file))
           disposals)
      (with-current-buffer author
        (goto-char (point-max))
        (insert "Unsaved author edit.\n"))
      (let ((author-text (with-current-buffer author (buffer-string))))
        (damagebdd-test--record-dirty-file-disposals disposals
          (should (equal "#details" (damagebdd--fragment file "*Details")))
          (should (equal "#included" (damagebdd--fragment
                                     (damagebdd--root "org/index.org") "*Included"))))
        (should-not disposals)
        (should (equal before (damagebdd--hash-file file)))
        (should (buffer-live-p author))
        (with-current-buffer author
          (should (buffer-modified-p))
          (should (equal author-text (buffer-string))))))))

(ert-deftest damagebdd-fragment-error-cleanup-does-not-prompt ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org"
                        "#+TITLE: Start\n#+INCLUDE: \"missing.inc\"\n* Details\n")
    (let* ((file (damagebdd--root "org/index.org"))
           (before (damagebdd--hash-file file))
           disposals)
      (damagebdd-test--record-dirty-file-disposals disposals
        (should-error (damagebdd--fragment file "*Details")))
      (should-not disposals)
      (should (equal before (damagebdd--hash-file file))))))

(ert-deftest damagebdd-paired-export-preserves-content-and-boundaries ()
  (damagebdd-test--site
    (damagebdd-test--put
     "org/index.org"
     (concat "#+TITLE: Start [here]\n#+DESCRIPTION: Fixture overview\n"
             "#+DATE: 2026-10-05\n#+CAPABILITY_ID: fixture\n"
             "#+CONTENT_CLASS: implementation-reference\n"
             "#+IMPLEMENTATION_STATUS: implemented\n#+VALIDATION_STATUS: live_verified\n"
             "#+EVIDENCE_DATE: 2026-09-25\n#+VERIFIED_RELEASE: fixture-1\n"
             "#+EVIDENCE_URL: https://example.invalid/evidence/one\n"
             "#+EVIDENCE_URL: https://example.invalid/evidence/two\n"
             "#+INCLUDE: \"part.inc\"\n\n"
             "[[file:articles/chapter space.org::*Details][Read details]]\n\n"
             "| Method | Result |\n|--------+--------|\n| =ping= | =pong= |\n\n"
             "#+BEGIN_SRC emacs-lisp :eval yes :exports code\n"
             "(error \"BABEL-MUST-NOT-EXECUTE\")\n#+END_SRC\n\n"
             "#+BEGIN_EXPORT html\n<script>UNWANTED-SCRIPT</script>\n#+END_EXPORT\n"
             "* Private :noexport:\nHIDDEN-MARKER\n#+EVIDENCE_URL: https://private.invalid/HIDDEN-METADATA\n"))
    (damagebdd-test--put "org/part.inc" "* Included\nIncluded text.\n")
    (damagebdd-test--put "org/articles/chapter space.org"
                        "#+TITLE: Chapter\n* Details\nFirst.\n* Details\nSecond.\n")
    (let ((before (damagebdd--hash-file (damagebdd--root "org/index.org"))))
      (damagebdd-publish)
      (should (equal before (damagebdd--hash-file (damagebdd--root "org/index.org")))))
    (let* ((md (damagebdd--read (damagebdd--root "public/index.md")))
           (html (damagebdd--read (damagebdd--root "public/index.html")))
           (chapter (damagebdd--read (damagebdd--root "public/articles/chapter space.md")))
           (caps (damagebdd--read-json (damagebdd--root "public/docs/capabilities.json")))
           (cap (aref (alist-get 'capabilities caps) 0)))
      (should (string-match-p "Included text" md))
      (should (string-match-p (regexp-quote "| `ping` | `pong` |") md))
      (should (string-match-p (regexp-quote "```emacs-lisp") md))
      (should (string-match-p "BABEL-MUST-NOT-EXECUTE" md))
      (should-not (string-match-p "NAVIGATION-MARKER\\|FOOTER-MARKER\\|UNWANTED-SCRIPT\\|HIDDEN-MARKER" md))
      (should-not (string-match-p "HIDDEN-MARKER" html))
      (should (string-match-p "chapter%20space.md#details" md))
      (should (string-match-p "id=\"details-2\"" chapter))
      (should (string-match-p "text/markdown" html))
      (should (string-match-p "https://example.invalid/docs/llms.txt" html))
      (should (equal "live_verified" (alist-get 'validation_status cap)))
      (should (equal "2026-09-25" (alist-get 'evidence_date cap)))
      (should (equal "fixture-1" (alist-get 'verified_release cap)))
      (should (= 2 (length (alist-get 'evidence_urls cap))))
      (should-not (string-match-p "HIDDEN-METADATA" (json-encode caps)))
      (should (equal "1970-01-01T00:00:00Z" (alist-get 'generated_at caps))))))

(ert-deftest damagebdd-does-not-infer-verification-or-api ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org"
                        "#+TITLE: Untested feature\n#+DATE: 2026-10-05\n#+CAPABILITY_ID: unknown\nTests passed in a hypothetical example.\n")
    (damagebdd-publish)
    (let* ((caps (damagebdd--read-json (damagebdd--root "public/docs/capabilities.json")))
           (cap (aref (alist-get 'capabilities caps) 0)))
      (should (equal "not_recorded" (alist-get 'validation_status cap)))
      (should (null (alist-get 'evidence_date cap)))
      (should (null (alist-get 'verified_release cap)))
      (should (equal [] (alist-get 'evidence_urls cap)))
      (should (null (alist-get 'openapi_url caps))))
    (should-not (file-exists-p (damagebdd--root "public/openapi.json")))
    (should-not (string-match-p "OpenAPI" (damagebdd--read (damagebdd--root "public/llms.txt"))))))

(ert-deftest damagebdd-copies-real-api-and-refuses-invalid-contract ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nDocumentation.\n")
    (damagebdd-test--put "openapi.json"
                        "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"Fixture\",\"version\":\"1\"},\"paths\":{}}\n")
    (damagebdd-publish)
    (should (equal (damagebdd--hash-file (damagebdd--root "openapi.json"))
                   (damagebdd--hash-file (damagebdd--root "public/openapi.json"))))
    (should (string-match-p "OpenAPI" (damagebdd--read (damagebdd--root "public/llms.txt"))))
    (damagebdd-test--put "openapi.json" "{\"not_an_api\": true}\n")
    (should-error (damagebdd-publish))))

(ert-deftest damagebdd-removes-only-unchanged-owned-stale-artifacts ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nDocumentation.\n")
    (damagebdd-test--put "org/old.org" "#+TITLE: Old\nOld documentation.\n")
    (damagebdd-test--put "org/edited.org" "#+TITLE: Edited\nOld documentation.\n")
    (damagebdd-publish)
    (damagebdd-test--put "public/edited.md" "Manual edit: preserve me.\n")
    (damagebdd-test--put "public/edited.html" "Manual HTML: preserve me.\n")
    (damagebdd-test--put "public/unrelated.md" "Unrelated: preserve me.\n")
    (delete-file (damagebdd--root "org/old.org"))
    (delete-file (damagebdd--root "org/edited.org"))
    (damagebdd-publish)
    (should-not (file-exists-p (damagebdd--root "public/old.md")))
    (should-not (file-exists-p (damagebdd--root "public/old.html")))
    (should (equal "Manual edit: preserve me.\n" (damagebdd--read (damagebdd--root "public/edited.md"))))
    (should (equal "Manual HTML: preserve me.\n" (damagebdd--read (damagebdd--root "public/edited.html"))))
    (should (file-exists-p (damagebdd--root "public/unrelated.md")))
    (should-not (string-match-p "old.md" (damagebdd--read (damagebdd--root "public/docs/index.md"))))))

(ert-deftest damagebdd-duplicate-capability-ids-fail-build ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: A\n#+CAPABILITY_ID: duplicate\nA.\n")
    (damagebdd-test--put "org/other.org" "#+TITLE: B\n#+CAPABILITY_ID: duplicate\nB.\n")
    (should-error (damagebdd-publish))))

(defun damagebdd-test--inventory ()
  (damagebdd--read-json (damagebdd--root "public/docs/index.json")))

(defun damagebdd-test--document (source inventory)
  (cl-find source (alist-get 'documents inventory)
           :key (lambda (doc) (alist-get 'source_path doc)) :test #'equal))

(ert-deftest damagebdd-freshness-stable-across-build-times-and-source-mtimes ()
  (damagebdd-test--site
    (damagebdd-test--put
     "org/index.org"
     (concat "#+TITLE: Stable\n#+CAPABILITY_ID: stable\n"
             "#+LAST_MODIFIED: 2026-10-05\n#+EVIDENCE_DATE: 2026-09-25\n"
             "* Details\nText[fn:one] with [[named-code][a code link]].\n"
             "#+NAME: named-code\n#+BEGIN_SRC text\nhello\n#+END_SRC\n"
             "[fn:one] Footnote.\n"))
    (damagebdd-test--put "org/other.org" "#+TITLE: Other\nNo declared date.\n")
    (damagebdd-publish)
    (let* ((first (damagebdd-test--inventory))
           (revision (alist-get 'content_revision first))
           (html (damagebdd--hash-file (damagebdd--root "public/index.html"))))
      (setenv "SOURCE_DATE_EPOCH" "1791237600")
      (set-file-times (damagebdd--root "org/index.org") (seconds-to-time 1000000000))
      (set-file-times (damagebdd--root "org/other.org") (seconds-to-time 1000000001))
      (damagebdd-publish)
      (let* ((second (damagebdd-test--inventory))
             (doc (damagebdd-test--document "org/index.org" second))
             (caps (damagebdd--read-json (damagebdd--root "public/docs/capabilities.json"))))
        (should-not (equal (alist-get 'generated_at first) (alist-get 'generated_at second)))
        (should (equal revision (alist-get 'content_revision second)))
        (should (equal revision (alist-get 'content_revision caps)))
        (should (equal html (alist-get 'html_sha256 doc)))
        (should (equal "2026-10-05" (alist-get 'last_modified doc)))
        (should (equal "declared" (alist-get 'last_modified_source doc)))
        (should (equal "2026-09-25" (alist-get 'evidence_date doc)))
        (should-not (alist-get 'last_modified (damagebdd-test--document "org/other.org" second)))
        (should (string-match-p "<lastmod>2026-10-05</lastmod>"
                                (damagebdd--read (damagebdd--root "public/sitemap.xml"))))
        (should-not (string-match-p "1970-01-01\\|2001-09-09"
                                    (damagebdd--read (damagebdd--root "public/sitemap.xml"))))))))

(ert-deftest damagebdd-freshness-tracks-includes-metadata-additions-and-removals ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\n#+INCLUDE: \"part.inc\"\n")
    (damagebdd-test--put "org/part.inc" "Included version one.\n")
    (damagebdd-publish)
    (let* ((first (damagebdd-test--inventory))
           (doc (damagebdd-test--document "org/index.org" first))
           (revision (alist-get 'content_revision first)))
      (damagebdd-test--put "org/part.inc" "Included version two.\n")
      (damagebdd-publish)
      (let ((changed (damagebdd-test--document "org/index.org" (damagebdd-test--inventory))))
        (should (equal (alist-get 'source_sha256 doc) (alist-get 'source_sha256 changed)))
        (should-not (equal (alist-get 'markdown_sha256 doc) (alist-get 'markdown_sha256 changed))))
      (dolist (change '(metadata add remove))
        (should-not (equal revision (alist-get 'content_revision (damagebdd-test--inventory))))
        (setq revision (alist-get 'content_revision (damagebdd-test--inventory)))
        (pcase change
          ('metadata (damagebdd-test--put "org/index.org"
                                         "#+TITLE: Start\n#+VALIDATION_STATUS: source_reviewed\n#+INCLUDE: \"part.inc\"\n"))
          ('add (damagebdd-test--put "org/new.org" "#+TITLE: New\nNew page.\n"))
          ('remove (delete-file (damagebdd--root "org/new.org"))))
        (damagebdd-publish))
      (should-not (equal revision (alist-get 'content_revision (damagebdd-test--inventory))))
      (should-not (damagebdd-test--document "org/new.org" (damagebdd-test--inventory)))
      (should-not (file-exists-p (damagebdd--root "public/new.html")))
      (should-not (file-exists-p (damagebdd--root "public/new.md"))))))

(ert-deftest damagebdd-freshness-tracks-html-only-and-api-changes ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nPublic documentation.\n")
    (damagebdd-publish)
    (let* ((first (damagebdd-test--inventory))
           (revision (alist-get 'content_revision first))
           (md (alist-get 'markdown_sha256 (damagebdd-test--document "org/index.org" first))))
      (damagebdd-test--put "snippets/postamble.html" "<footer>Updated footer</footer>")
      (damagebdd-publish)
      (should-not (equal revision (alist-get 'content_revision (damagebdd-test--inventory))))
      (should (equal md (alist-get 'markdown_sha256
                                  (damagebdd-test--document "org/index.org" (damagebdd-test--inventory)))))
      (dolist (version '("1" "2" nil))
        (setq revision (alist-get 'content_revision (damagebdd-test--inventory)))
        (if version
            (damagebdd-test--put "openapi.json"
                                (format "{\"openapi\":\"3.1.0\",\"info\":{\"title\":\"Test\",\"version\":\"%s\"},\"paths\":{}}" version))
          (delete-file (damagebdd--root "openapi.json")))
        (damagebdd-publish)
        (should-not (equal revision (alist-get 'content_revision (damagebdd-test--inventory))))
        (when version
          (should (equal (alist-get 'sha256 (alist-get 'openapi (damagebdd-test--inventory)))
                         (damagebdd--hash-file (damagebdd--root "public/openapi.json")))))))))

(ert-deftest damagebdd-freshness-rejects-invalid-modification-dates ()
  (damagebdd-test--site
    (dolist (date '("yesterday" "2026-02-30" "2026-10-05T24:00:00Z"))
      (damagebdd-test--put "org/index.org" (format "#+TITLE: Start\n#+LAST_MODIFIED: %s\nText.\n" date))
      (should-error (damagebdd-publish)))
    (should (equal "2026-10-05T12:13:14Z" (damagebdd--modified-date "2026-10-05T12:13:14Z")))))

(ert-deftest damagebdd-freshness-git-dates-require-clean-tracked-dependencies ()
  (skip-unless (executable-find "git"))
  (damagebdd-test--site
    (make-directory (damagebdd--root "scripts") t)
    (copy-file damagebdd-test--publisher-file (damagebdd--root "scripts/publish.el"))
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\n#+INCLUDE: \"parts/outer.inc\"\n")
    (damagebdd-test--put "org/parts/outer.inc" "#+INCLUDE: \"inner space.inc\"\n")
    (damagebdd-test--put "org/parts/inner space.inc" "Original include.\n")
    (dolist (key '("GIT_AUTHOR_NAME" "GIT_COMMITTER_NAME")) (setenv key "Publisher Test"))
    (dolist (key '("GIT_AUTHOR_EMAIL" "GIT_COMMITTER_EMAIL")) (setenv key "test@example.invalid"))
    (dolist (key '("GIT_AUTHOR_DATE" "GIT_COMMITTER_DATE")) (setenv key "2026-09-01T12:00:00Z"))
    (should (damagebdd--git "init" "-q"))
    (should (damagebdd--git "add" "."))
    (should (damagebdd--git "-c" "commit.gpgsign=false" "commit" "-qm" "Fixture"))
    (damagebdd-publish)
    (let ((doc (damagebdd-test--document "org/index.org" (damagebdd-test--inventory))))
      (should (equal "2026-09-01T12:00:00Z" (alist-get 'last_modified doc)))
      (should (equal "git" (alist-get 'last_modified_source doc))))
    (damagebdd-test--put "org/parts/inner space.inc" "Dirty include.\n")
    (damagebdd-publish)
    (should-not (alist-get 'last_modified (damagebdd-test--document "org/index.org" (damagebdd-test--inventory))))
    (should (damagebdd--git "add" "org/parts/inner space.inc"))
    (dolist (key '("GIT_AUTHOR_DATE" "GIT_COMMITTER_DATE")) (setenv key "2026-10-01T12:00:00Z"))
    (should (damagebdd--git "-c" "commit.gpgsign=false" "commit" "-qm" "Update include"))
    (damagebdd-publish)
    (should (equal "2026-10-01T12:00:00Z"
                   (alist-get 'last_modified (damagebdd-test--document "org/index.org" (damagebdd-test--inventory)))))
    ;; An unrelated dirty source does not invalidate this page's date.
    (damagebdd-test--put "unrelated.txt" "Not an export input.\n")
    (damagebdd-publish)
    (should (alist-get 'last_modified (damagebdd-test--document "org/index.org" (damagebdd-test--inventory))))
    (damagebdd-test--put "snippets/header.html" "<meta name=\"dirty\" content=\"yes\">")
    (damagebdd-publish)
    (should-not (alist-get 'last_modified (damagebdd-test--document "org/index.org" (damagebdd-test--inventory))))))
;;; publish-tests.el ends here
