;;; occur-kwic-tests.el --- KWIC behavior tests -*- lexical-binding: t; -*-

;; Author: Minoru Yasui
;; Assisted-by: Codex:GPT-6.1

(require 'ert)
(require 'cl-lib)
(require 'occur-kwic)

(defmacro occur-kwic-test--with-results (spec &rest body)
  "Search SPEC (TEXT REGEXP &optional SETUP REGION), then run BODY in results."
  (declare (indent 1))
  `(let ((initial-buffers (buffer-list))
         (source (generate-new-buffer " *kwic-source*"))
         (occur-kwic-alignment 'left)
         (next-error-last-buffer nil)
         (next-error-highlight nil)
         (occur-hook nil)
         result)
     (unwind-protect
         (save-window-excursion
           (with-current-buffer source
             (insert ,(nth 0 spec))
             (goto-char (point-min))
             (setq-local case-fold-search nil)
             (set-buffer-modified-p nil)
             ,(nth 2 spec)
             (setq result (occur-kwic ,(nth 1 spec) ,(nth 3 spec))))
           (when result (select-window (get-buffer-window result t)))
           ,@body)
       (dolist (buffer (buffer-list))
         (unless (memq buffer initial-buffers) (kill-buffer buffer))))))

(defun occur-kwic-test--visible (entry window)
  "Read displayed row text and match column from actual WINDOW properties.
Return (TEXT MATCH-COLUMN), without consulting the layout calculation."
  (let ((position (occur-kwic--entry-row-begin entry))
        (end (occur-kwic--entry-row-end entry))
        (match (+ (occur-kwic--entry-text-begin entry) (occur-kwic--entry-begin entry)))
        (text "") match-column)
    (while (< position (1+ end))
      (unless (get-char-property position 'invisible window)
        (when (= position match) (setq match-column (string-width text)))
        (let ((before (get-char-property position 'before-string window))
              (display (get-char-property position 'display window)))
          (when before (setq text (concat text before)))
          (unless (= position end)
            (setq text (concat text (if (stringp display) display
                                     (char-to-string (char-after position))))))))
      (setq position (1+ position)))
    (list text match-column)))

(ert-deftest occur-kwic-test-full-lines-and-source-state ()
  (occur-kwic-test--with-results
      ("long context X with a long suffix\nX\n" "X" (goto-char 4))
    (should (derived-mode-p 'occur-mode))
    (should buffer-read-only)
    (should truncate-lines)
    (should-not (buffer-modified-p))
    (should (= (length occur-kwic--entries) 2))
    (should (string-match-p "long context X with a long suffix" (buffer-string)))
    (with-current-buffer source
      (should (= (point) 4))
      (should-not (buffer-modified-p))
      (should (equal (buffer-string) "long context X with a long suffix\nX\n")))))

(ert-deftest occur-kwic-test-alignment-including-japanese ()
  (occur-kwic-test--with-results
      ("short X tail\nlonger YY suffix\nあいうえ ZZZ かきくけ\n" "X\\|YY\\|ZZZ")
    (let* ((window (selected-window)) (anchor (/ (window-body-width window) 2)))
      (dolist (alignment '(left center right))
        (occur-kwic-set-alignment alignment)
        (cl-mapc
         (lambda (entry width)
           (let ((column (cadr (occur-kwic-test--visible entry window))))
             (should (= (+ column (pcase alignment
                                    ('left 0) ('center (/ width 2)) ('right width)))
                        anchor))))
         occur-kwic--entries '(1 2 3))))))

(ert-deftest occur-kwic-test-tabs-and-copy ()
  (occur-kwic-test--with-results
      ("a\tX tail\nX tail\nあ\tX tail\n" "X" (setq-local tab-width 4))
    (let ((window (selected-window)))
      (dolist (entry occur-kwic--entries)
        (let ((visible (occur-kwic-test--visible entry window)))
          (should (= (cadr visible) (/ (window-body-width window) 2)))
          (should-not (string-match-p "\t" (car visible))))))
    (let ((entry (car occur-kwic--entries)))
      (should (equal (substring-no-properties
                      (filter-buffer-substring (occur-kwic--entry-text-begin entry)
                                               (occur-kwic--entry-row-end entry)))
                     "a\tX tail")))))

(ert-deftest occur-kwic-test-long-matches-clip-without-data-loss ()
  (occur-kwic-test--with-results ((concat (make-string 200 ?X) "\n") "X+")
    (let ((entry (car occur-kwic--entries)) (window (selected-window)))
      (dolist (alignment '(left center right))
        (occur-kwic-set-alignment alignment)
        (should (<= (string-width (car (occur-kwic-test--visible entry window)))
                    (1- (window-body-width window))))
        (should (= (length (occur-kwic--entry-text entry)) 200))))))

(ert-deftest occur-kwic-test-two-windows-and-resize ()
  (occur-kwic-test--with-results
      ((concat (make-string 80 ?a) "X" (make-string 80 ?b) "\n") "X")
    (delete-other-windows)
    (let* ((first (selected-window))
           (second (split-window-right 30))
           (entry (car occur-kwic--entries))
           (text (buffer-string))
           (target (caar (occur-kwic--entry-targets entry))))
      (set-window-buffer second result)
      (occur-kwic--refresh-windows)
      (dolist (window (list first second))
        (should (= (cadr (occur-kwic-test--visible entry window))
                   (/ (window-body-width window) 2))))
      (let ((small-text (car (occur-kwic-test--visible entry first))))
        (window-resize first 5 t)
        (run-hook-with-args 'window-size-change-functions first)
        (should-not (equal small-text (car (occur-kwic-test--visible entry first)))))
      (should (equal text (buffer-string)))
      (should (eq entry (car occur-kwic--entries)))
      (should (eq target (caar (occur-kwic--entry-targets entry))))
      (should-not (buffer-modified-p))
      (dolist (window (list first second))
        (should (= (cadr (occur-kwic-test--visible entry window))
                   (/ (window-body-width window) 2))))
      (delete-window second)
      (occur-kwic--refresh-windows)
      (should (= (length occur-kwic--views) 1)))))

(ert-deftest occur-kwic-test-zero-width-and-standard-navigation ()
  (dolist (regexp '("^" "$"))
    (occur-kwic-test--with-results ("abc\n\ndef" regexp)
      (should (= (length occur-kwic--entries) 3))
      (goto-char (point-min))
      (dolist (entry occur-kwic--entries)
        (occur-next)
        (should (eq (get-text-property (point) 'occur-kwic-entry) entry))
        (let ((visible (occur-kwic-test--visible entry (selected-window))))
          (should (= (cadr visible) (/ (window-body-width) 2)))
          (should (string-match-p "|" (car visible)))))
      (should-error (occur-next) :type 'user-error))))

(ert-deftest occur-kwic-test-zero-width-at-end-and-empty-buffer ()
  (occur-kwic-test--with-results ("abc\n" "^")
    (should (= (length occur-kwic--entries) 1)))
  (occur-kwic-test--with-results ("" "^") (should-not result))
  (occur-kwic-test--with-results ("abc" "$")
    (should (= (length occur-kwic--entries) 1))
    (should (= (occur-kwic--entry-begin (car occur-kwic--entries)) 3))))

(ert-deftest occur-kwic-test-each-match-target-and-occur-jump ()
  (occur-kwic-test--with-results ("one X two X three\n" "X")
    (should (= (length occur-kwic--entries) 2))
    (cl-mapc
     (lambda (entry position)
       (with-current-buffer result
         (goto-char (occur-kwic--entry-row-begin entry))
         (occur-mode-goto-occurrence)
         (should (eq (current-buffer) source))
         (should (= (point) position))))
     occur-kwic--entries '(5 11))
    (with-current-buffer result
      (goto-char (point-min))
      (occur-next-error 1 t)
      (should (eq (current-buffer) source))
      (should (= (point) 5)))))

(ert-deftest occur-kwic-test-narrowing-does-not-expose-outside-context ()
  (occur-kwic-test--with-results
      ("outside X\nprefix X suffix\noutside X\n" "X"
       (progn (search-forward "prefix ")
              (let ((start (point)))
                (search-forward "X suffix")
                (narrow-to-region start (point)))))
    (should (= (length occur-kwic--entries) 1))
    (should (equal (occur-kwic--entry-text (car occur-kwic--entries)) "X suffix"))
    (should-not (string-match-p "outside\\|prefix" (buffer-string)))
    (with-current-buffer source (should (buffer-narrowed-p)))))

(ert-deftest occur-kwic-test-refresh-and-saved-region ()
  (occur-kwic-test--with-results
      ("X\ninside X\nX\n" "X" nil (cons 3 11))
    (should (= (length occur-kwic--entries) 1))
    (should (eq (marker-buffer (car occur-kwic--region)) source))
    (occur-kwic-set-alignment 'right)
    (rename-buffer " *kwic-renamed*" t)
    (let ((name (buffer-name))
          (old-marker (caar (occur-kwic--entry-targets (car occur-kwic--entries)))))
      (with-current-buffer source
        (goto-char 1) (insert "before\n")
        (search-forward "inside ") (insert "X "))
      (revert-buffer nil t)
      (should (equal name (buffer-name)))
      (should (eq occur-kwic-alignment 'right))
      (should (= (length occur-kwic--entries) 2))
      (should-not (marker-buffer old-marker))
      (should (eq (marker-buffer (car occur-kwic--region)) source))
      (should-not (string-match-p "before" (occur-kwic--entry-text (car occur-kwic--entries)))))))

(ert-deftest occur-kwic-test-multiline-and-invalid-search-preserve-results ()
  (occur-kwic-test--with-results ("a X\nb Y\n" "X")
    (let ((text (buffer-string))
          (entries occur-kwic--entries))
      (dolist (regexp '("a X\nb" "[" ""))
        (with-current-buffer source (should-error (occur-kwic regexp)))
        (should (equal text (buffer-string)))
        (should (eq entries occur-kwic--entries)))
      ;; A regexp capable of matching newlines is accepted when its actual
      ;; matches do not contain one.
      (with-current-buffer source (occur-kwic "X\\|\nNEVER"))
      (should (= (length occur-kwic--entries) 1)))))

(ert-deftest occur-kwic-test-case-folding-like-occur ()
  (occur-kwic-test--with-results
      ("x\nX\n" "x" (setq-local case-fold-search t))
    (should (= (length occur-kwic--entries) 2)))
  (occur-kwic-test--with-results
      ("x\nX\n" "X" (setq-local case-fold-search t))
    (should (= (length occur-kwic--entries) 1))))

(ert-deftest occur-kwic-test-edit-disabled-and-standard-occur-unaffected ()
  (occur-kwic-test--with-results ("one X two X\n" "X")
    (should (eq (key-binding "e") #'occur-kwic--no-edit))
    (should-error (call-interactively (key-binding "e")) :type 'user-error)
    (let ((this-command 'occur-edit-mode) (real-this-command 'occur-edit-mode))
      (should-error (call-interactively #'occur-edit-mode) :type 'user-error))
    (should (eq major-mode 'occur-kwic-mode))
    (should buffer-read-only)
    (goto-char (point-min))
    (should-error (insert "bad") :type 'buffer-read-only)
    (with-current-buffer source (occur "X"))
    (with-current-buffer "*Occur*"
      (occur-edit-mode)
      (should (eq major-mode 'occur-edit-mode))
      (should-not buffer-read-only))))

(ert-deftest occur-kwic-test-clone-and-marker-cleanup ()
  (occur-kwic-test--with-results ("one X two X\n" "X")
    (let* ((entry (car occur-kwic--entries))
           (target (caar (occur-kwic--entry-targets entry)))
           (clone (occur-kwic-clone-buffer))
           (clone-target (caar (occur-kwic--entry-targets (car occur-kwic--entries)))))
      (should-not (eq target clone-target))
      (kill-buffer clone)
      (should-not (marker-buffer clone-target))
      (should (eq (marker-buffer target) source))
      (kill-buffer result)
      (should-not (marker-buffer target)))))

(ert-deftest occur-kwic-test-isearch-and-full-line-view ()
  (occur-kwic-test--with-results
      ((concat "hidden " (make-string 100 ?a) "X tail\n") "X")
    (let* ((entry (car occur-kwic--entries))
           (window (selected-window))
           (begin (occur-kwic--entry-text-begin entry)))
      (goto-char begin)
      (should (get-char-property begin 'invisible window))
      (run-hooks 'isearch-mode-hook)
      (should-not (get-char-property begin 'invisible window))
      (should (search-forward "hidden" nil t))
      (run-hooks 'isearch-mode-end-hook)
      (should-not (get-char-property begin 'invisible window))
      (occur-kwic-toggle-line)
      (should (get-char-property begin 'invisible window))
      (should (string-match-p "hidden" (buffer-string))))))

(ert-deftest occur-kwic-test-no-matches-and-killed-source ()
  (occur-kwic-test--with-results ("abc\n" "X") (should-not result))
  (occur-kwic-test--with-results ("X\n" "X")
    (kill-buffer source)
    (should-error (revert-buffer nil t) :type 'user-error))
  (occur-kwic-test--with-results ("X\n" "X")
    (with-current-buffer source (erase-buffer))
    (revert-buffer nil t)
    (should-not (buffer-live-p result))))

(ert-deftest occur-kwic-test-isearch-ignores-other-windows-hiding ()
  (occur-kwic-test--with-results
      ((concat "HIDDEN_START " (make-string 100 ?a) "X\n") "X")
    (delete-other-windows)
    (let* ((second (split-window-right 30))
           (entry (car occur-kwic--entries))
           (begin (occur-kwic--entry-text-begin entry)))
      (set-window-buffer second result)
      (occur-kwic--refresh-windows)
      (goto-char begin)
      (should (invisible-p begin))
      (run-hooks 'isearch-mode-hook)
      ;; This is the buffer-level test used by actual isearch, rather
      ;; than only looking up properties for the selected window.
      (should-not (invisible-p begin))
      (run-hooks 'isearch-mode-end-hook)
      (should-not (invisible-p begin))
      (occur-kwic-toggle-line)
      (should (invisible-p begin)))))

(ert-deftest occur-kwic-test-interactive-active-region ()
  (occur-kwic-test--with-results ("X\ninside X\nX\n" "X")
    (with-current-buffer source
      (let ((transient-mark-mode t) (current-prefix-arg nil))
        (goto-char 3)
        (set-mark 11)
        (activate-mark)
        (cl-letf (((symbol-function 'read-regexp) (lambda (&rest _args) "X")))
          (setq result (call-interactively #'occur-kwic)))))
    (with-current-buffer result
      (should (= (length occur-kwic--entries) 1))
      (should (equal (occur-kwic--entry-text (car occur-kwic--entries)) "inside X")))))

(ert-deftest occur-kwic-test-refresh-uses-current-source-restriction ()
  (occur-kwic-test--with-results
      ("outside X\ninside X\n" "X" (narrow-to-region 11 (point-max)))
    (should (= (length occur-kwic--entries) 1))
    (with-current-buffer source (widen))
    (revert-buffer nil t)
    (should (= (length occur-kwic--entries) 2))))

(ert-deftest occur-kwic-test-specific-search-hook ()
  (let ((calls 0) (occur-kwic-hook nil))
    (occur-kwic-test--with-results
        ("X\n" "X"
         (setq occur-kwic-hook (list (lambda () (setq calls (1+ calls))))
               occur-hook (list (lambda () (error "Ordinary Occur hook ran")))))
      (should (= calls 1))
      (revert-buffer nil t)
      (should (= calls 2)))))

(ert-deftest occur-kwic-test-combining-context-stays-with-its-base ()
  (occur-kwic-test--with-results
      ((concat (apply #'concat (make-list 50 "é")) "X"
               (apply #'concat (make-list 50 "é")) "\n") "X")
    (let* ((entry (car occur-kwic--entries))
           (visible (occur-kwic-test--visible entry (selected-window))))
      (should (= (cadr visible) (/ (window-body-width) 2)))
      (should-not (string-match-p ":́" (car visible)))
      (should (string-suffix-p "é" (car visible))))))

(ert-deftest occur-kwic-test-extremely-narrow-window-recovers ()
  ;; With a three-digit line prefix, very small windows cannot show both
  ;; the prefix and the aligned match.  Do not prescribe which fragment
  ;; survives; require safe layout and full recovery when widened.
  (occur-kwic-test--with-results
      ((concat "X\nprefix XX suffix\nあいう XXX かきく\n"
               (make-string 98 ?\n) "X\n") "X+")
    (delete-other-windows)
    (let* ((window-min-width 1)
           (window (selected-window))
           (other (split-window-right 4))
           (text (buffer-string))
           (entries occur-kwic--entries)
           (targets (mapcar (lambda (entry) (caar (occur-kwic--entry-targets entry)))
                            entries)))
      (dolist (alignment '(left center right))
        (occur-kwic-set-alignment alignment)
        (dolist (width '(3 4 5 6 8 10 12))
          (window-resize window (- width (window-body-width window)) t)
          (occur-kwic--refresh-windows)
          (should (equal text (buffer-string)))
          (should (eq entries occur-kwic--entries))
          (dolist (target targets)
            (should (eq (marker-buffer target) source)))))
      (delete-window other)
      (occur-kwic-set-alignment 'left)
      (occur-kwic--refresh-windows)
      (dolist (entry entries)
        (should (= (cadr (occur-kwic-test--visible entry window))
                   (/ (window-body-width window) 2))))
      (should (equal text (buffer-string)))
      (should-not (buffer-modified-p)))))

;;; occur-kwic-tests.el ends here
