;;; check.el --- Check production sources -*- lexical-binding: t; -*-

;; Run with: emacs -Q --batch -l scripts/check.el
(require 'bytecomp)

(let* ((root (expand-file-name ".." (file-name-directory load-file-name)))
       (temporary-directory (make-temp-file "occur-kwic-check-" t)))
  (unwind-protect
      (dolist (name '("eyegrep" "occur-kwic"))
        (let* ((source (expand-file-name (concat name ".el") root))
               (temporary-source (expand-file-name (concat name ".el") temporary-directory)))
          (with-temp-buffer
            (insert-file-contents source)
            (emacs-lisp-mode)
            (check-parens))
          (load source nil t t)
          (unless (and (featurep (intern name)) (commandp (intern name)))
            (error "Missing feature or command: %s" name))
          (copy-file source temporary-source)
          (let ((byte-compile-error-on-warn t))
            (unless (byte-compile-file temporary-source)
              (error "Byte compilation failed: %s" name)))
          (princ (format "%s: parentheses, loading and byte compilation OK\n" name))))
    (delete-directory temporary-directory t)))

;;; check.el ends here
