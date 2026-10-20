;;; run-tests.el --- Shared batch check and test runner -*- lexical-binding: t; -*-

;; Author: Minoru Yasui
;; Assisted-by: Codex:GPT-6.1

;; Run with: emacs -Q --batch -l scripts/run-tests.el [--test-only]
(require 'ert)

(let* ((root (expand-file-name ".." (file-name-directory load-file-name)))
       (test-only (equal command-line-args-left '("--test-only")))
       (default-directory (file-name-as-directory root)))
  (unless (or (null command-line-args-left) test-only)
    (error "Usage: emacs -Q --batch -l scripts/run-tests.el [--test-only]"))
  (setq command-line-args-left nil)
  (add-to-list 'load-path root)
  (add-to-list 'load-path (expand-file-name "legacy" root))
  (unless test-only
    (load (expand-file-name "scripts/check.el" root) nil t t))
  (dolist (name '("eyegrep-tests.el" "occur-kwic-tests.el" "occur-kwic-corpus-tests.el"))
    (load (expand-file-name name (expand-file-name "test" root)) nil t t))
  (ert-run-tests-batch-and-exit))

;;; run-tests.el ends here
