;;; eyegrep-tests.el --- Characterize the original eyegrep -*- lexical-binding: t; -*-

;; Author: Minoru Yasui
;; Assisted-by: Codex:GPT-6.1

;; These tests describe the existing implementation, not the proposed
;; occur-kwic API.  Expected failures describe known defects separately.

(require 'ert)
(require 'cl-lib)
(require 'replace)
(require 'eyegrep)

;; Mocking a primitive must not invoke the optional native compiler.
;; Declare this variable for Emacs versions without native compilation too.
(defvar native-comp-enable-subr-trampolines)

(defmacro eyegrep-test--with-search (spec &rest body)
  "Search SPEC, then evaluate BODY with `source' and `result' buffers.
SPEC is (TEXT REGEXP WIDTH &optional SETUP).  SETUP runs in the source
before searching.  WIDTH is the calling window's text width.  Clean up
all buffers created during the search, including on errors."
  (declare (indent 1) (debug (sexp body)))
  (let ((text (nth 0 spec))
        (regexp (nth 1 spec))
        (width (nth 2 spec))
        (setup (nth 3 spec)))
    `(let ((initial-buffers (buffer-list))
           (source (generate-new-buffer " *eyegrep-test-source*"))
           result)
       (unwind-protect
           (save-window-excursion
             (with-current-buffer source
               (insert ,text)
               (goto-char (point-min))
               (setq-local case-fold-search nil)
               (set-buffer-modified-p nil)
               ,setup
               (let ((native-comp-enable-subr-trampolines nil))
                 (cl-letf (((symbol-function 'window-body-width)
                            (lambda (&rest _args) ,width))
                           ((symbol-function 'display-buffer)
                            (lambda (buffer &rest _args)
                              (setq result (get-buffer buffer))
                              nil)))
                   (eyegrep ,regexp)))
               ,@body))
         (dolist (buffer (buffer-list))
           (unless (memq buffer initial-buffers)
             (kill-buffer buffer)))))))

(defun eyegrep-test--rows (buffer)
  "Return BUFFER's result rows, excluding its summary and newline."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (split-string (buffer-substring-no-properties (point) (point-max))
                    "\n" t))))

(defun eyegrep-test--matches (buffer)
  "Return (COLUMN TEXT TARGET) for each highlighted match in BUFFER.
COLUMN is measured by `current-column', including the line prefix."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (let (matches)
        (while (< (point) (point-max))
          (let ((end (line-end-position)))
            (while (and (< (point) end)
                        (not (equal (get-text-property (point) 'face)
                                    list-matching-lines-face)))
              (forward-char 1))
            (should (< (point) end))
            (let ((match-end (next-single-property-change
                              (point) 'face nil end)))
              (push (list (current-column)
                          (buffer-substring-no-properties (point) match-end)
                          (get-text-property (point) 'occur-target))
                    matches)))
          (forward-line 1))
        (nreverse matches)))))

(ert-deftest eyegrep-test-ascii-context-and-padding ()
  (eyegrep-test--with-search
      ("0123456789Xabcdefghij\nX tail\nshort X\n" "X" 20)
    (should (equal (eyegrep-test--rows result)
                   '("1:23456789Xabcdefgh"
                     "2:        X tail"
                     "3:  short X")))
    (should (equal (mapcar #'car (eyegrep-test--matches result))
                   '(10 10 10)))))

(ert-deftest eyegrep-test-japanese-context ()
  (eyegrep-test--with-search
      ("あいうえおXかきくけこ\nあXい\n" "X" 20)
    (should (equal (eyegrep-test--rows result)
                   '("1:いうえおXかきくけ"
                     "2:      あXい")))
    (should (equal (mapcar #'car (eyegrep-test--matches result)) '(10 10)))))

(ert-deftest eyegrep-test-wide-character-at-truncation-boundary ()
  (eyegrep-test--with-search
      ("あいうえおXかきくけこ\n" "X" 22)
    ;; The nine-column context cannot contain half of a wide character.
    (should (equal (eyegrep-test--rows result)
                   '("1: いうえおXかきくけ")))
    (should (= (caar (eyegrep-test--matches result)) 11))))

(ert-deftest eyegrep-test-match-width-and-window-parity ()
  ;; Golden columns preserve the old rounding, including its half-column
  ;; difference between centers of odd- and even-width matches.
  (dolist (case '((20 (10 9 9 8)) (21 (10 10 9 9))))
    (eyegrep-test--with-search
        ("a\nbb\nccc\ndddd\n" "[a-d]+" (car case))
      (should (equal (mapcar #'car (eyegrep-test--matches result))
                     (cadr case))))))

(ert-deftest eyegrep-test-line-number-prefix-width ()
  (eyegrep-test--with-search
      ((concat "a\nbb\nccc\ndddd\n" (make-string 6 ?\n)) "[a-d]+" 20)
    (should (equal (mapcar #'car (eyegrep-test--matches result))
                   '(10 10 9 9)))
    (should (string-prefix-p " 1:" (car (eyegrep-test--rows result))))
    (should (string-prefix-p " 4:" (nth 3 (eyegrep-test--rows result))))))

(ert-deftest eyegrep-test-one-row-per-match-and-source-targets ()
  (eyegrep-test--with-search ("one X two X three\n" "X" 20)
    (let ((matches (eyegrep-test--matches result)))
      (should (= (length matches) 2))
      (should (equal (mapcar #'car matches) '(10 10)))
      (should (equal (mapcar (lambda (match) (marker-position (nth 2 match)))
                            matches)
                     '(5 11)))
      (dolist (match matches)
        (should (eq (marker-buffer (nth 2 match)) source)))
      (dolist (row (eyegrep-test--rows result))
        (should (string-prefix-p "1:" row))))))

(ert-deftest eyegrep-test-non-overlapping-matches ()
  (eyegrep-test--with-search ("aaaaa\n" "aa" 20)
    (should (equal (mapcar (lambda (match) (marker-position (nth 2 match)))
                          (eyegrep-test--matches result))
                   '(1 3)))))

(ert-deftest eyegrep-test-narrowing-and-source-state ()
  (let ((text "outside X\nprefix X suffix\noutside X\n"))
    (eyegrep-test--with-search
        (text "X" 20
              (progn
                (search-forward "prefix ")
                (let ((beg (point)))
                  (search-forward "X suffix")
                  (narrow-to-region beg (point)))
                (goto-char (point-min))))
      (should (buffer-narrowed-p))
      (should (= (point) (point-min)))
      (should (equal (buffer-string) "X suffix"))
      (should-not (buffer-modified-p))
      (should (equal (eyegrep-test--rows result) '("1:        X suffix")))
      (should (= (marker-position (nth 2 (car (eyegrep-test--matches result))))
                 (point-min)))
      (save-restriction
        (widen)
        (should (equal (buffer-string) text))))))

(ert-deftest eyegrep-test-preserves-source-point ()
  (eyegrep-test--with-search
      ("X first\nsecond X\n" "X" 20 (goto-char 4))
    (should (= (point) 4))
    (should-not (buffer-modified-p))))

(ert-deftest eyegrep-test-case-fold-search ()
  (dolist (case '((nil 1) (t 2)))
    (eyegrep-test--with-search
        ("x\nX\n" "X" 20 (setq-local case-fold-search (car case)))
      (should (= (length (eyegrep-test--rows result)) (cadr case))))))

(ert-deftest eyegrep-test-final-line-without-newline ()
  (eyegrep-test--with-search ("X" "X" 20)
    (should (equal (eyegrep-test--rows result) '("1:        X"))))
  (eyegrep-test--with-search ("" "X" 20)
    (should-not result)))

(ert-deftest eyegrep-test-no-match-discards-result-buffer ()
  (eyegrep-test--with-search ("nothing here\n" "X" 20)
    (should-not result)
    (should (equal (cl-set-difference (buffer-list) initial-buffers) (list source)))
    (should (= (point) 1))
    (should-not (buffer-modified-p))))

(ert-deftest eyegrep-test-empty-and-invalid-regexp ()
  (should-error
   (eyegrep-test--with-search ("X\n" "" 20) (ert-fail "Empty regexp accepted"))
   :type 'error)
  (should-error
   (eyegrep-test--with-search ("X\n" "[" 20) (ert-fail "Invalid regexp accepted"))
   :type 'invalid-regexp))

(ert-deftest eyegrep-test-result-mode-properties-and-summary ()
  (eyegrep-test--with-search ("left X right\n" "X" 20)
    (with-current-buffer result
      (should (derived-mode-p 'occur-mode))
      (should buffer-read-only)
      (should-not (buffer-modified-p))
      (goto-char (point-min))
      (should (looking-at (regexp-quote
                           (format "1 match for \"X\" in buffer: %s\n" source))))
      (forward-line 1)
      (should (get-text-property (point) 'occur-prefix))
      (should (eq (get-text-property (point) 'face)
                  list-matching-lines-prefix-face))
      (let ((target (get-text-property (point) 'occur-target)))
        (should (markerp target))
        (should (eq (marker-buffer target) source))
        (should (= (marker-position target) 6))
        (should (eq (get-text-property (line-end-position) 'occur-target) target))))))

(ert-deftest eyegrep-test-standard-occur-jump-to-each-match ()
  (eyegrep-test--with-search ("one X two X three\n" "X" 20)
    (dolist (case '((1 5) (2 11)))
      (with-current-buffer result
        (goto-char (point-min))
        (forward-line (car case))
        (occur-mode-goto-occurrence)
        (should (eq (current-buffer) source))
        (should (= (point) (cadr case)))))))

(ert-deftest eyegrep-test-known-tab-alignment-defect ()
  :expected-result :failed
  ;; Desirable behavior, currently broken: the first X lands at column 8
  ;; and the second at column 15 because tab expansion is position-dependent.
  (eyegrep-test--with-search ("a\tX tail\nX tail\n" "X" 30)
    (should (equal (mapcar #'car (eyegrep-test--matches result)) '(15 15)))))

(define-error 'eyegrep-test--stalled-search "Search repeated a zero-width match")

(ert-deftest eyegrep-test-known-zero-width-progress-defect ()
  :expected-result :failed
  ;; Stop the old infinite loop at its second search attempt.  Unlike a
  ;; timer, this guard also works when Lisp never waits for input.  A search
  ;; loop that advances after a zero-width match will not trip the guard.
  (let ((search (symbol-function 're-search-forward))
        (native-comp-enable-subr-trampolines nil)
        last-empty-match)
    (cl-letf (((symbol-function 're-search-forward)
               (lambda (&rest args)
                 (when (and last-empty-match
                            (eq (current-buffer) (car last-empty-match))
                            (= (point) (cdr last-empty-match)))
                   (signal 'eyegrep-test--stalled-search nil))
                 (let ((found (apply search args)))
                   (setq last-empty-match
                         (and found (= (match-beginning 0) (match-end 0))
                              (cons (current-buffer) (point))))
                   found))))
      (eyegrep-test--with-search ("abc\ndef\n" "^" 20)
        (should (= (length (eyegrep-test--rows result)) 2))))))

;;; eyegrep-tests.el ends here
