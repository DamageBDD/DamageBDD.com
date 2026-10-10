;;; site-tests.el --- Presentation/export regression tests -*- lexical-binding: t; -*-
;; Run with: emacs -Q --batch -l scripts/publish-tests.el -l scripts/site-tests.el
;;           -f ert-run-tests-batch-and-exit
(unless (fboundp 'damagebdd-test--put)
  (load-file (expand-file-name "publish-tests.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))

(defun damagebdd-site-test--count (regexp text)
  "Count non-overlapping REGEXP occurrences in TEXT."
  (let ((start 0) (count 0))
    (while (string-match regexp text start)
      (setq start (match-end 0) count (1+ count)))
    count))

(ert-deftest damagebdd-site-snippets-have-prefixed-content-addressed-assets ()
  (damagebdd-test--site
    (damagebdd-test--put "assets/css/site.css" "body { color: green; }\n")
    (let ((text (damagebdd--expand-snippet
                 "<a href=\"{{base}}/manual.html\">Docs</a><link href=\"{{asset:assets/css/site.css}}\"><meta content=\"{{origin}}\">")))
      (should (string-match-p "href=\"/docs/manual.html\"" text))
      (should (string-match-p "/docs/assets/css/site.css?v=[[:xdigit:]]\\{12\\}" text))
      (should (string-match-p "https://example.invalid/docs" text))
      (should-not (string-match-p "{{" text)))))

(ert-deftest damagebdd-site-rejects-missing-or-escaping-snippet-assets ()
  (damagebdd-test--site
    (damagebdd-test--put "outside.css" "body {}")
    (should-error (damagebdd--expand-snippet "{{asset:assets/missing.css}}"))
    (should-error (damagebdd--expand-snippet "{{asset:assets/../outside.css}}"))))

(ert-deftest damagebdd-site-document-has-one-title-and-canonical ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Readable & inspectable\n#+DESCRIPTION: A short description.\n* First\nText.\n** Second\nMore text.\n")
    (damagebdd-publish)
    (let ((html (damagebdd--read (damagebdd--root "public/index.html"))))
      (should (= 1 (damagebdd-site-test--count "<h1[ >]" html)))
      (should (= 1 (damagebdd-site-test--count "rel=\"canonical\"" html)))
      (should (= 1 (damagebdd-site-test--count "name=\"viewport\"" html)))
      (should (string-match-p "<main id=\"content\" tabindex=\"-1\"" html))
      (should (string-match-p "class=\"document-layout\"" html))
      (should (string-match-p "href=\"#first\"" html))
      (should (string-match-p "href=\"/docs/index.md\"" html))
      (should (string-match-p "content=\"Readable &amp; inspectable\"" html))
      (should-not (string-match-p "Updated <time" html)))))

(ert-deftest damagebdd-site-home-is-opt-in-and-markdown-remains-clean ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org"
                        (concat "#+TITLE: Home\n#+SITE_LAYOUT: home\n"
                                "#+BEGIN_EXPORT html\n<h1>Hero title</h1>\n#+END_EXPORT\n"
                                "An ordinary Org paragraph.\n* Workflow\n"
                                ":PROPERTIES:\n:HTML_CONTAINER_CLASS: home-section\n:END:\n"
                                "Native content.\n"))
    (damagebdd-publish)
    (let ((html (damagebdd--read (damagebdd--root "public/index.html")))
          (md (damagebdd--read (damagebdd--root "public/index.md"))))
      (should (string-match-p "class=\"home-page\"" html))
      (should (= 1 (damagebdd-site-test--count "<h1[ >]" html)))
      (should (string-match-p "class=\"outline-2 home-section\"" html))
      (should-not (string-match-p "doc-sidebar" html))
      (should (string-match-p "An ordinary Org paragraph" md))
      (should (string-match-p "Native content" md))
      (should-not (string-match-p "Hero title\\|home-page\\|NAVIGATION-MARKER" md)))))

(ert-deftest damagebdd-site-collection-and-layout-validation ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Articles\n#+SITE_LAYOUT: collection\n* Guide\nA guide.\n")
    (damagebdd-publish)
    (should (string-match-p "class=\"collection-layout\""
                            (damagebdd--read (damagebdd--root "public/index.html"))))
    (damagebdd-test--put "org/index.org" "#+TITLE: Bad layout\n#+SITE_LAYOUT: unknown\nText.\n")
    (should-error (damagebdd-publish))))

(ert-deftest damagebdd-site-sidebar-skips-absent-entry-pages ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nSome text.\n")
    (damagebdd-test--put "org/manual.org" "#+TITLE: Manual\nRead this.\n")
    (damagebdd-publish)
    (let ((html (damagebdd--read (damagebdd--root "public/manual.html"))))
      (should (string-match-p "href=\"/docs/manual.html\" aria-current=\"page\"" html))
      (should-not (string-match-p "href=\"/docs/install.html\"" html)))))

(ert-deftest damagebdd-site-asset-changes-invalidate-existing-html-revisions ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nContent unchanged.\n")
    (damagebdd-test--put "assets/site.css" "body { color: green; }\n")
    (damagebdd-test--put "snippets/header.html" "<link rel=\"stylesheet\" href=\"{{asset:assets/site.css}}\">")
    (damagebdd-publish)
    (let* ((before (damagebdd-test--inventory))
           (doc (damagebdd-test--document "org/index.org" before)))
      (damagebdd-test--put "assets/site.css" "body { color: black; }\n")
      (damagebdd-publish)
      (let* ((after (damagebdd-test--inventory))
             (updated (damagebdd-test--document "org/index.org" after)))
        (should-not (equal (alist-get 'content_revision before) (alist-get 'content_revision after)))
        (should-not (equal (alist-get 'html_sha256 doc) (alist-get 'html_sha256 updated)))
        (should (equal (alist-get 'markdown_sha256 doc) (alist-get 'markdown_sha256 updated)))))))

(ert-deftest damagebdd-site-metadata-escapes-attribute-quotes ()
  (should (equal (damagebdd--html-attribute "A \"quote\" & <tag>")
                 "A &quot;quote&quot; &amp; &lt;tag&gt;")))

(provide 'site-tests)
;;; site-tests.el ends here
