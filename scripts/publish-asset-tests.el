;;; publish-asset-tests.el --- Asset publishing/deployment regressions -*- lexical-binding: t; -*-
;; Run all publisher tests:
;; emacs -Q --batch -l scripts/publish-tests.el -l scripts/site-tests.el \
;;   -l scripts/publish-asset-tests.el -f ert-run-tests-batch-and-exit
(unless (fboundp 'damagebdd-test--put)
  (load-file (expand-file-name "publish-tests.el"
                              (file-name-directory (or load-file-name buffer-file-name)))))

(ert-deftest damagebdd-assets-expand-whole-tokens-at-staging-root ()
  (damagebdd-test--site
    (let ((damagebdd-site-url "https://staging.damagebdd.com"))
      (damagebdd-test--put "assets/css/site.css" "body { margin: 0; }\n")
      (damagebdd-test--put "assets/js/nav.js" "console.log('navigation');\n")
      (let ((css-hash (substring (damagebdd--hash-file (damagebdd--root "assets/css/site.css")) 0 12))
            (js-hash (substring (damagebdd--hash-file (damagebdd--root "assets/js/nav.js")) 0 12)))
        (should
         (equal
          (damagebdd--expand-snippet
           (concat "before<link href=\"{{asset:assets/css/site.css}}\">"
                   "<script src=\"{{asset:assets/js/nav.js}}\"></script>"
                   "<a href=\"{{base}}/manual.html\">Docs</a>"
                   "<meta content=\"{{origin}}\">after"))
          (format (concat "before<link href=\"/assets/css/site.css?v=%s\">"
                          "<script src=\"/assets/js/nav.js?v=%s\"></script>"
                          "<a href=\"/manual.html\">Docs</a>"
                          "<meta content=\"https://staging.damagebdd.com\">after")
                  css-hash js-hash)))))))

(ert-deftest damagebdd-assets-protect-callback-match-data-from-helpers ()
  "A nested regexp must not change which bytes replace-regexp-in-string replaces."
  (damagebdd-test--site
    (damagebdd-test--put "assets/css/site.css" "body {}\n")
    (let* ((real-site-path (symbol-function 'damagebdd--site-path))
           (real-hash (symbol-function 'damagebdd--hash-file))
           (hash (substring (damagebdd--hash-file (damagebdd--root "assets/css/site.css")) 0 12))
           (expected (format "A/docs/assets/css/site.css?v=%sB/docs/assets/css/site.css?v=%sC"
                             hash hash)))
      ;; Deliberately leak unrelated matches from BOTH helpers, independently
      ;; of whether a particular Emacs version's URL/file helpers do so.
      (cl-letf (((symbol-function 'damagebdd--site-path)
                 (lambda (relative)
                   (prog1 (funcall real-site-path relative)
                     (string-match "\\(x\\)" "ax"))))
                ((symbol-function 'damagebdd--hash-file)
                 (lambda (file)
                   (prog1 (funcall real-hash file)
                     (string-match "\\(z\\)" "aaz")))))
        (should (equal expected
                       (damagebdd--expand-snippet
                        "A{{asset:assets/css/site.css}}B{{asset:assets/css/site.css}}C")))))))

(ert-deftest damagebdd-assets-prefix-and-trailing-slash-are-stable ()
  (damagebdd-test--site
    (damagebdd-test--put "assets/css/site.css" "body {}\n")
    (let* ((hash (substring (damagebdd--hash-file (damagebdd--root "assets/css/site.css")) 0 12))
           (expected (format "/docs/assets/css/site.css?v=%s|/docs|https://example.invalid/docs" hash)))
      (dolist (damagebdd-site-url '("https://example.invalid/docs" "https://example.invalid/docs/"))
        (should (equal expected
                       (damagebdd--expand-snippet
                        "{{asset:assets/css/site.css}}|{{base}}|{{origin}}")))))))

(ert-deftest damagebdd-assets-encode-paths-with-spaces ()
  (damagebdd-test--site
    (damagebdd-test--put "assets/css/site theme.css" "body {}\n")
    (let ((hash (substring (damagebdd--hash-file (damagebdd--root "assets/css/site theme.css")) 0 12)))
      (should (equal (format "/docs/assets/css/site%%20theme.css?v=%s" hash)
                     (damagebdd--expand-snippet "{{asset:assets/css/site theme.css}}"))))))

(ert-deftest damagebdd-assets-reject-empty-and-incomplete-tokens ()
  (damagebdd-test--site
    (dolist (text '("{{asset:}}" "{{asset:assets/css/site.css"))
      (should-error (damagebdd--expand-snippet text "snippets/header.html")))))

(ert-deftest damagebdd-assets-reject-literal-and-encoded-placeholder-leaks ()
  (dolist (token '("{{asset:a/assets/js/nav.js?v=123assets/js/nav.js}}"
                   "%7B%7Basset:a/assets/js/nav.js?v=123"
                   "%7b%7basset%3aassets/js/nav.js%7d%7d"
                   "{{base}}/manual.html" "%7B%7Bbase%7D%7D/manual.html"
                   "{{origin}}/assets/logo.png" "%7b%7borigin%7d%7d/assets/logo.png"))
    (let ((err (should-error (damagebdd--assert-expanded-html token "index.html"))))
      (should (string-match-p "index.html" (error-message-string err)))))
  (should (equal "<script src=\"/assets/js/nav.js?v=0123456789ab\"></script>"
                 (damagebdd--assert-expanded-html
                  "<script src=\"/assets/js/nav.js?v=0123456789ab\"></script>" "index.html"))))

(ert-deftest damagebdd-assets-validate-the-copied-bytes ()
  (damagebdd-test--site
    (let ((damagebdd--snippet-assets (make-hash-table :test #'equal)))
      (damagebdd-test--put "assets/css/site.css" "body {}\n")
      (damagebdd--expand-snippet "{{asset:assets/css/site.css}}")
      ;; A source file alone is not a deployable asset.
      (should-error (damagebdd--validate-snippet-assets))
      (damagebdd-test--put "public/assets/css/site.css" "body {}\n")
      (damagebdd--validate-snippet-assets)
      (damagebdd-test--put "public/assets/css/site.css" "body { margin: 0; }\n")
      (should-error (damagebdd--validate-snippet-assets)))))

(ert-deftest damagebdd-assets-reject-source-symlink-escape ()
  (damagebdd-test--site
    (damagebdd-test--put "outside.css" "body {}\n")
    (make-symbolic-link (damagebdd--root "outside.css") (damagebdd--root "assets/escape.css"))
    (should-error (damagebdd--expand-snippet "{{asset:assets/escape.css}}"))))

(ert-deftest damagebdd-assets-reject-public-symlink-escape ()
  (damagebdd-test--site
    (let ((damagebdd--snippet-assets (make-hash-table :test #'equal)))
      (damagebdd-test--put "assets/site.css" "body {}\n")
      (damagebdd--expand-snippet "{{asset:assets/site.css}}")
      (make-directory (damagebdd--root "public/assets") t)
      (make-symbolic-link (damagebdd--root "assets/site.css")
                         (damagebdd--root "public/assets/site.css"))
      (should-error (damagebdd--validate-snippet-assets)))))

(ert-deftest damagebdd-assets-real-export-copies-root-and-nested-page-assets ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nHome.\n")
    (damagebdd-test--put "org/articles/chapter.org" "#+TITLE: Chapter\nNested content.\n")
    (damagebdd-test--put "assets/css/site.css" "body { margin: 0; }\n")
    (damagebdd-test--put "assets/js/nav.js" "console.log('navigation');\n")
    (damagebdd-test--put "assets/img/logo.svg" "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>\n")
    (damagebdd-test--put "snippets/header.html"
                        "<link rel=\"stylesheet\" href=\"{{asset:assets/css/site.css}}\"><script src=\"{{asset:assets/js/nav.js}}\" defer></script>")
    (damagebdd-test--put "snippets/preamble.html"
                        "<nav><a href=\"{{base}}/\"><img src=\"{{asset:assets/img/logo.svg}}\" alt=\"DamageBDD\"></a></nav>")
    (damagebdd-publish)
    (dolist (path '("assets/css/site.css" "assets/js/nav.js" "assets/img/logo.svg"))
      (should (equal (damagebdd--hash-file (damagebdd--root path))
                     (damagebdd--hash-file (damagebdd--root (concat "public/" path))))))
    (dolist (page '("index.html" "articles/chapter.html"))
      (let ((html (damagebdd--read (damagebdd--root (concat "public/" page)))))
        (dolist (path '("assets/css/site.css" "assets/js/nav.js" "assets/img/logo.svg"))
          (should (string-match-p
                   (regexp-quote (format "\"/docs/%s?v=%s\"" path
                                         (substring (damagebdd--hash-file (damagebdd--root path)) 0 12)))
                   html)))
        (should-not (string-match-p "{{\\|%7[Bb]%7[Bb]" html))))))

(ert-deftest damagebdd-assets-publish-fails-when-attachment-rule-omits-an-asset ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org" "#+TITLE: Start\nContent.\n")
    ;; .txt exists locally but is not in the existing static attachment rule.
    (damagebdd-test--put "assets/omitted.txt" "Asset not copied by Org.\n")
    (damagebdd-test--put "snippets/header.html" "<link href=\"{{asset:assets/omitted.txt}}\">")
    (let ((err (should-error (damagebdd-publish))))
      (should (string-match-p "Missing published snippet asset" (error-message-string err))))))

(ert-deftest damagebdd-assets-publish-fails-for-leaks-in-org-export-blocks ()
  (damagebdd-test--site
    (damagebdd-test--put "org/index.org"
                        (concat "#+TITLE: Start\n#+BEGIN_EXPORT html\n"
                                "<img src=\"{{asset:assets/logo.png}}\">\n#+END_EXPORT\n"))
    (let ((err (should-error (damagebdd-publish))))
      (should (string-match-p "Unexpanded site placeholder in index.html" (error-message-string err))))))

(ert-deftest damagebdd-assets-rsync-is-not-started-after-publish-failure ()
  (let ((started nil))
    (cl-letf (((symbol-function 'damagebdd-publish)
               (lambda () (error "Missing published snippet asset: public/assets/js/nav.js")))
              ((symbol-function 'async-shell-command)
               (lambda (&rest _args) (setq started t))))
      (should-error (damagebdd-rsync-deploy "unused.invalid"))
      (should-not started))))

(provide 'publish-asset-tests)
;;; publish-asset-tests.el ends here
