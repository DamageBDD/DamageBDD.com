(defun org-sitemap-date-entry-format (entry style project)
  "Format ENTRY in org-publish PROJECT Sitemap format ENTRY ENTRY STYLE format that includes date."
  (let ((filename (org-publish-find-title entry project)))
    (if (= (length filename) 0)
        (format "*%s*" entry)
      (format "{{{timestamp(%s)}}} [[file:%s][%s]]"
              (format-time-string "%Y-%m-%d"
                                  (org-publish-find-date entry project))
              entry
              filename))))


(defvar damagebdd-html-head
  "<div class='head'></div>"
  )
(defvar damagebdd-html-preamble
  "<div class='preamble'>
        <div class='columns'>
            <a href='/'><img src='/assets/img/logo.avif' id='logo' alt='Logo' /></a>
            <h1> DamageBDD</h1>
            <h2>
                Behaviour Driven Development At Planetary Scale.
            </h2>
        </div>
    </div>"
  )
(defvar damagebdd-html-postamble
  "<div class='footer'>
        Copyright 2024 %a (%v HTML).<br>
        Last updated %C. <br>
        Built with %c.

        <a href=\"/sitemap.html\">Sitemap</a>
    </div>"
  )
(require 'ox-publish)

(setq
           org-confirm-babel-evaluate nil
           org-html-checkbox-type 'html

           org-publish-project-alist
           `(
             ("damagebdd" :components ("damagebdd.pages" "damagebdd.static" "damagebdd.articles"))
             ("damagebdd.pages"
              :base-directory ,default-directory
              :base-extension "org"
              :publishing-directory ,(expand-file-name "public" default-directory)
              :recursive t
              :publishing-function org-html-publish-to-html
              :auto-preamble t
              :auto-sitemap t
              :auto-index t
              :sitemap-title "DamageBDD - BDD At Planetary Scale."
              :sitemap-filename "sitemap.org"
              :sitemap-sort-files anti-chronologically
              :makeindex t
              :sitemap-format-entry org-sitemap-date-entry-format
              ;;:section-numbers nil
              :with-toc nil
              :html-doctype "html5"
              :html-html5-fancy t
              :html-head-include-scripts nil
              :html-head-include-default-style nil
              :html-head ,damagebdd-html-head
              :html-preamble ,damagebdd-html-preamble
              :html-postamble ,damagebdd-html-postamble
                                        ;:sitemap-file-entry-format "%d - %t"
              )
             ("damagebdd.articles"
              :base-directory ,(expand-file-name "articles" default-directory)
              :base-extension "jpeg\\|pdf"
              :publishing-directory ,(expand-file-name "public/articles" default-directory)
              :recursive t
              :publishing-function org-publish-attachment
              )
             ("damagebdd.static"
              :base-directory ,(expand-file-name "assets" default-directory)
              :base-extension "css\\|js\\|png\\|jpg\\|jpeg\\|gif\\|pdf\\|mp3\\|ogg\\|swf\\|ttf\\|map\\|svg\\|woff\\|woff2\\|ico\\|avif"
              :publishing-directory ,(expand-file-name "public/assets" default-directory)
              :recursive t
              :publishing-function org-publish-attachment
              )
             )

           org-export-global-macros
           '(("timestamp" . "@@html:<span class=\"timestamp\">[$1]</span>@@"))
           org-export-with-toc nil
           )


(setq org-confirm-babel-evaluate nil
      org-html-validate-link nil
      org-export-in-background nil
      org-export-use-babel nil
      org-publish-use-timestamps-flag nil
      org-publish-list-skipped-files nil
      org-publish-timestamp-directory "~/.org-timestamps/"
      org-publish-project-alist org-publish-project-alist
      vc-handled-backends nil)

(setq-default noninteractive-init t
              inhibit-startup-screen t
              inhibit-startup-message t)

;; Disable yes/no prompts in batch mode
(fset 'yes-or-no-p (lambda (&rest args) t))
(fset 'y-or-n-p (lambda (&rest args) t))


(defun publish-and-serve ()
  "Publish the org project and serve the output directory via simple-httpd."
  (interactive)
  ;; Run the org-publish command
  (org-publish-project "damagebdd" t)

  ;; Add current directory to load-path and require simple-httpd
  (add-to-list 'load-path
               (file-name-directory (or load-file-name buffer-file-name default-directory)))
  (require 'simple-httpd)

  ;; Set the root directory for the web server to the published HTML output
  (setq httpd-root (expand-file-name "public"))  ;; Change "public" if needed

  ;; Optional: set port (default is 8080)
  (setq httpd-port 8081)

  ;; Start the server if not already running
  (unless (process-status "httpd")
    (message "Starting Emacs web server on http://localhost:8081")
    (httpd-start)))
