;; ~/Org/damagebdd/.dir-locals.el
((org-mode
  . ((eval . (load-file (expand-file-name "scripts/publish.el"
                                          (locate-dominating-file buffer-file-name ".dir-locals.el")))))))
