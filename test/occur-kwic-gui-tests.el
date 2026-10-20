;;; occur-kwic-gui-tests.el --- Redisplay alignment regressions -*- lexical-binding: t; -*-

;; Run in a fresh GUI Emacs with: emacs -Q -l scripts/run-gui-tests.el
;; The runner also loads the shared helpers in occur-kwic-tests.el.

(require 'ert)
(require 'occur-kwic)

(defun occur-kwic-gui-test--choose-alignment (alignment)
  "Choose ALIGNMENT through the result buffer's a binding and minibuffer."
  (should (eq (key-binding "a") #'occur-kwic-set-alignment))
  (minibuffer-with-setup-hook
      (lambda ()
        (insert (symbol-name alignment))
        (setq unread-command-events (cons ?\r unread-command-events)))
    (call-interactively (key-binding "a"))))

(defun occur-kwic-gui-test--check-anchors (windows alignment)
  "Check actual match coordinates in WINDOWS after redisplay for ALIGNMENT."
  (redisplay t)
  (dolist (window windows)
    (should (zerop (window-hscroll window)))
    (dolist (entry occur-kwic--entries)
      ;; Test data uses three ASCII characters in the default fixed-width font.
      (let* ((begin (+ (occur-kwic--entry-text-begin entry)
                       (occur-kwic--entry-begin entry)))
             (position (posn-at-point begin window))
             (offset (pcase alignment ('left 0) ('center 1) ('right 3)))
             (expected (* (- (/ (window-body-width window) 2) offset)
                          (frame-char-width (window-frame window)))))
        (should position)
        (should (= (car (posn-x-y position)) expected))))))

(ert-deftest occur-kwic-gui-test-combining-context-and-source-visibility ()
  (skip-unless (display-graphic-p))
  (occur-kwic-test--with-results
      ("e\u0301 prefix XXX tail\nplain prefix XXX tail\n" "XXX"
       ;; A hidden source skips the automatic-composition path in
       ;; `string-width', masking the old per-character overmeasurement.
       (set-window-buffer (selected-window) source))
    (let* ((source-window (get-buffer-window source))
           (result-window (selected-window))
           (columns (copy-sequence (occur-kwic--entry-columns (car occur-kwic--entries))))
           (placeholder (generate-new-buffer " *kwic-hidden-source*")))
      (should source-window)
      (dolist (alignment '(left center right))
        (occur-kwic-gui-test--choose-alignment alignment)
        (occur-kwic-gui-test--check-anchors (list result-window) alignment))
      (set-window-buffer source-window placeholder)
      (revert-buffer nil t)
      (should (equal columns (occur-kwic--entry-columns (car occur-kwic--entries))))
      (occur-kwic-gui-test--check-anchors (list result-window) 'right)
      (set-window-buffer source-window source)
      (revert-buffer nil t)
      (should (equal columns (occur-kwic--entry-columns (car occur-kwic--entries))))
      (occur-kwic-gui-test--check-anchors (list result-window) 'right))))

(ert-deftest occur-kwic-gui-test-interactive-alignment-and-header-point ()
  (skip-unless (display-graphic-p))
  (occur-kwic-test--with-results
      ((concat (make-string 100 ?a) "XXX tail\nprefix XXX suffix\n") "XXX"
       (rename-buffer (concat " *kwic-long-source-" (make-string 120 ?s)) t))
    (delete-other-windows)
    (let* ((first (selected-window))
           (second (split-window-right 31))
           (windows (list first second)))
      (set-window-buffer second result)
      ;; A cursor in the long header used to scroll the aligned rows away
      ;; again during redisplay, after the command had reset their scroll.
      (goto-char (point-min))
      (end-of-line)
      (dolist (alignment '(left center right left right center left))
        (occur-kwic-gui-test--choose-alignment alignment)
        (occur-kwic-gui-test--check-anchors windows alignment))
      (set-window-hscroll first 7)
      (set-window-hscroll second 11)
      (occur-kwic-gui-test--choose-alignment 'left)
      (occur-kwic-gui-test--check-anchors windows 'left)
      (window-resize first 4 t)
      ;; Redisplay must invoke the real window hooks; do not call them here.
      (occur-kwic-gui-test--check-anchors windows 'left))))

(ert-deftest occur-kwic-gui-test-alignment-after-expanded-row-scroll ()
  (skip-unless (display-graphic-p))
  (occur-kwic-test--with-results
      ((concat (make-string 100 ?a) "XXX tail\nprefix XXX suffix\n") "XXX")
    (let ((entry (car occur-kwic--entries))
          (window (selected-window)))
      (dolist (alignment '(left center right left))
        (goto-char (occur-kwic--entry-row-begin entry))
        (occur-kwic-toggle-line)
        (redisplay t)
        (goto-char (+ (occur-kwic--entry-text-begin entry)
                     (occur-kwic--entry-end entry)))
        (redisplay t)
        ;; Check that the setup actually exercises automatic scrolling.
        (should (> (window-hscroll window) 0))
        (occur-kwic-gui-test--choose-alignment alignment)
        (should-not occur-kwic--expanded)
        (occur-kwic-gui-test--check-anchors (list window) alignment)))))

(ert-deftest occur-kwic-gui-test-named-clone-keeps-both-layouts ()
  (skip-unless (display-graphic-p))
  (occur-kwic-test--with-results
      ((concat (make-string 100 ?a) "XXX tail\nprefix XXX suffix\n") "XXX")
    (delete-other-windows)
    (let* ((second (split-window-right 31))
           (entry (car occur-kwic--entries))
           (target (caar (occur-kwic--entry-targets entry)))
           clone)
      (set-window-buffer second result)
      (occur-kwic-set-alignment 'right)
      (goto-char (occur-kwic--entry-row-begin entry))
      (let ((current-prefix-arg '(4)))
        (minibuffer-with-setup-hook
            (lambda ()
              (insert " *kwic-gui-named-clone*")
              (setq unread-command-events (cons ?\r unread-command-events)))
          (setq clone (call-interactively (key-binding "c")))))
      (should (equal (buffer-name clone) " *kwic-gui-named-clone*"))
      (should-not (eq (car occur-kwic--entries) entry))
      ;; Initial layout must come from real window/redisplay hooks after
      ;; clone-buffer displays the clone; do not refresh the views here.
      (occur-kwic-gui-test--check-anchors
       (get-buffer-window-list clone nil t) 'right)
      (with-current-buffer result
        (should (get-buffer-window-list result nil t))
        (occur-kwic-gui-test--check-anchors
         (get-buffer-window-list result nil t) 'right))
      (kill-buffer clone)
      (should (eq (marker-buffer target) source))
      (with-current-buffer result
        (occur-kwic-gui-test--check-anchors
         (get-buffer-window-list result nil t) 'right)))))

(ert-deftest occur-kwic-gui-test-interactive-sort-keeps-anchors-after-reordering ()
  (skip-unless (display-graphic-p))
  (occur-kwic-test--with-results
      ("z XXX zebra\nalpha XXX apple\nmiddle XXX banana\n" "XXX")
    (delete-other-windows)
    (let* ((first (selected-window))
           (second (split-window-right 31))
           (windows (list first second)))
      (set-window-buffer second result)
      (should (eq (key-binding "s") #'occur-kwic-sort))
      ;; Exercise both real minibuffer prompts, including the numeric one.
      (let ((minibuffer-setup-hook
             (cons (lambda ()
                     (delete-minibuffer-contents)
                     (insert (if (string-prefix-p "Number" (minibuffer-prompt))
                                 "1" "after-words"))
                     (setq unread-command-events (cons ?\r unread-command-events)))
                   minibuffer-setup-hook)))
        (call-interactively (key-binding "s")))
      (should (equal (occur-kwic-test--display-order) '(2 3 1)))
      (dolist (alignment '(left center right))
        (occur-kwic-gui-test--choose-alignment alignment)
        (occur-kwic-gui-test--check-anchors windows alignment)
        (occur-kwic-sort 'source)
        (occur-kwic-gui-test--check-anchors windows alignment)
        (occur-kwic-sort 'after-words 1)
        (occur-kwic-gui-test--check-anchors windows alignment)))))

;;; occur-kwic-gui-tests.el ends here
