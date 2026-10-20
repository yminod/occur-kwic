;;; occur-kwic-corpus-tests.el --- Literary excerpt regressions -*- lexical-binding: t; -*-

;; Author: Minoru Yasui
;; Assisted-by: Codex:GPT-6.1

;; Loaded after occur-kwic-tests.el by scripts/run-tests.el.
;; See fixtures/README.md for provenance and expectation review notes.
(require 'ert)
(require 'cl-lib)
(require 'occur-kwic)

(defconst occur-kwic-corpus-test--directory
  (expand-file-name "fixtures" (file-name-directory load-file-name)))

;; Each match is (LINE ZERO-BASED-CHARACTER-OFFSET MATCHED-TEXT).
;; IDs in sort expectations are one-based indices into these source-order lists,
;; so two matches from the same line cannot be confused with one another.
(defconst occur-kwic-corpus-test--alice-matches
  '((2 49 "she") (7 3 "she") (7 51 "she") (15 39 "she")
    (16 24 "she") (19 67 "she") (21 53 "she") (26 13 "she")
    (30 30 "she") (33 34 "she") (33 60 "she") (34 18 "she")
    (35 33 "she") (36 5 "she") (36 66 "she") (38 43 "she")
    (39 16 "She") (39 63 "she") (41 29 "she") (43 13 "she")))

(defconst occur-kwic-corpus-test--botchan-matches
  '((1 26 "から") (1 50 "から") (1 124 "から") (1 168 "から")
    (1 196 "から") (1 242 "から") (1 270 "から") (2 6 "から")
    (2 127 "から") (3 435 "から") (3 491 "から") (3 515 "から")))

(defconst occur-kwic-corpus-test--alice-sorts
  '(((after-words 1) (6 15 18 3 19 10 20 9 1 11 5 7 16 4 17 13 2 8 14 12))
    ((after-words 3) (6 15 18 3 19 20 10 9 11 1 5 7 16 4 17 13 14 2 8 12))
    ((before-words 1) (3 12 18 20 9 7 19 13 11 10 17 2 5 6 15 16 1 14 4 8))
    ((before-words 3) (20 18 12 3 9 7 19 13 11 10 17 2 5 6 15 16 1 14 4 8))
    ((after-characters 1) (6 15 18 1 2 3 4 5 7 8 9 10 11 12 13 14 16 17 19 20))
    ((after-characters 3) (6 15 18 3 19 10 20 9 1 11 5 7 16 4 17 13 2 8 14 12))
    ((before-characters 1) (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))
    ((before-characters 3) (13 7 17 19 8 1 9 16 4 15 2 10 11 3 12 18 20 5 6 14))
    ((match) (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))
    ((source) (1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20))))

;; Other Alice sort orders are unchanged when case folding is disabled.
(defconst occur-kwic-corpus-test--alice-sensitive-sorts
  '(((before-words 1) (13 2 3 12 18 20 9 7 19 11 10 17 5 6 15 16 1 14 4 8))
    ((before-words 3) (13 2 20 18 12 3 9 7 19 11 10 17 5 6 15 16 1 14 4 8))
    ((match) (17 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 19 20))))

(defconst occur-kwic-corpus-test--botchan-sorts
  '(((after-words 1) (11 7 5 9 12 1 10 8 2 4 6 3))
    ((after-words 3) (11 7 5 9 12 1 10 8 2 6 4 3))
    ((before-words 1) (5 4 7 11 2 3 6 10 1 9 12 8))
    ((before-words 3) (5 4 7 11 3 2 6 10 1 9 12 8))
    ((after-characters 1) (7 9 10 11 5 12 1 8 2 4 6 3))
    ((after-characters 3) (11 7 9 10 5 12 1 8 2 4 6 3))
    ((before-characters 1) (6 4 5 7 9 12 10 8 11 1 2 3))
    ((before-characters 3) (6 4 5 9 7 12 10 8 11 1 2 3))
    ((match) (1 2 3 4 5 6 7 8 9 10 11 12))
    ((source) (1 2 3 4 5 6 7 8 9 10 11 12))))

(defun occur-kwic-corpus-test--text (name)
  "Read the pinned UTF-8 excerpt NAME and check its digest."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8-unix))
      (insert-file-contents (expand-file-name (concat name ".txt")
                                             occur-kwic-corpus-test--directory)))
    (let ((text (buffer-string)))
      (should
       (equal (secure-hash 'sha256 (encode-coding-string text 'utf-8-unix))
              (cdr (assoc name
                          '(("alice" . "c5e7692d6176344c3ffff033a28d26fe4325ec52d4ace929784bd3e9302b45c0")
                            ("botchan" . "6c3f85455357df7aa308c7acc9b9775adddd0f91705fadf635d60a57e82c9d5c"))))))
      text)))

(defun occur-kwic-corpus-test--ordered (matches ids)
  "Select fixed MATCHES in the order specified by one-based IDS."
  (mapcar (lambda (id) (nth (1- id) matches)) ids))

(defun occur-kwic-corpus-test--check-rows (source expected &optional target-line-shift)
  "Check actual result rows and source jumps against EXPECTED matches.
TARGET-LINE-SHIFT accounts for source insertions not yet in a snapshot."
  (let ((result (current-buffer)) rows)
    (save-excursion
      (goto-char (point-min))
      (forward-line 1)
      (while (< (point) (point-max))
        (push (point) rows)
        (forward-line 1)))
    (setq rows (nreverse rows))
    (should (= (length rows) (length expected)))
    (cl-mapc
     (lambda (row match)
       (ert-info ((format "Expected match %S at result row %d" match row))
         (let* ((line (nth 0 match)) (column (nth 1 match)) (text (nth 2 match))
                (source-data
                 (with-current-buffer source
                   (save-excursion
                     (goto-char (point-min))
                     (forward-line (1- (+ line (or target-line-shift 0))))
                     (list (+ (point) column)
                           (buffer-substring-no-properties (point) (line-end-position)))))))
           (with-current-buffer result
             (goto-char row)
             (let ((entry (get-text-property row 'occur-kwic-entry)))
               (should entry)
               (should (equal (list (occur-kwic--entry-line entry)
                                    (occur-kwic--entry-begin entry)
                                    (occur-kwic--entry-end entry))
                              (list line column (+ column (length text)))))
               (should (= (occur-kwic--entry-row-begin entry) row))
               (should (= (occur-kwic--entry-row-end entry) (line-end-position)))
               (should (equal (occur-kwic--entry-text entry) (cadr source-data)))
               (should (equal (buffer-substring-no-properties
                               (occur-kwic--entry-text-begin entry) (line-end-position))
                              (cadr source-data)))
               (goto-char (+ (occur-kwic--entry-text-begin entry) column))
               (should (equal (buffer-substring-no-properties (point) (+ (point) (length text)))
                              text))
               (should (= (caar (occur-kwic--entry-targets entry)) (car source-data)))
               (should (= (cdar (occur-kwic--entry-targets entry))
                          (+ (car source-data) (length text))))
               ;; Use standard Occur navigation, with an independently fixed target.
               (occur-mode-goto-occurrence)
               (should (eq (current-buffer) source))
               (should (= (point) (car source-data))))))))
     rows expected)))

(defun occur-kwic-corpus-test--check-sorts (name regexp matches cases &optional sensitive-cases)
  "Exercise all fixed sort CASES for excerpt NAME with REGEXP and MATCHES.
SENSITIVE-CASES overrides the orders affected by case-sensitive comparison."
  (let ((text (occur-kwic-corpus-test--text name)))
    (occur-kwic-test--with-results
        (text regexp (progn (text-mode) (setq-local case-fold-search nil)
                            (setq-local occur-kwic-sort-case-fold t)))
      (let ((original (buffer-substring-no-properties (point-min) (point-max))))
        (dolist (sensitive '(nil t))
          (when sensitive
            (occur-kwic-sort 'before-words 1)
            (occur-kwic-toggle-sort-case)
            (occur-kwic-corpus-test--check-rows
             source (occur-kwic-corpus-test--ordered
                     matches (cadr (assoc '(before-words 1) (or sensitive-cases cases))))))
          (dolist (test-case cases)
            (let* ((spec (car test-case))
                   (ids (cadr (or (and sensitive (assoc spec sensitive-cases)) test-case)))
                   (expected (occur-kwic-corpus-test--ordered matches ids)))
              (ert-info ((format "%s %S; case-sensitive=%S" name spec sensitive))
                ;; A second application must preserve exactly the same matches.
                (dotimes (_ 2)
                  (apply #'occur-kwic-sort spec)
                  (occur-kwic-corpus-test--check-rows source expected)))))
          ;; Every sequence ends with source restoration, including complete text.
          (should (equal original (buffer-substring-no-properties (point-min) (point-max)))))
        (with-current-buffer source
          (should (equal text (buffer-string)))
          (should-not (buffer-modified-p)))))))

(defun occur-kwic-corpus-test--check-refresh-and-clone (name regexp matches sort-case)
  "Check saved excerpt NAME across SORT-CASE, cloning and a source edit."
  (occur-kwic-test--with-results
      ((occur-kwic-corpus-test--text name) regexp
       (progn (text-mode) (setq-local case-fold-search nil)
              (setq-local occur-kwic-sort-case-fold nil)))
    (let* ((spec (car sort-case))
           (ordered (occur-kwic-corpus-test--ordered matches (cadr sort-case))))
      (apply #'occur-kwic-sort spec)
      (let ((clone (occur-kwic-clone-buffer)))
        (with-current-buffer clone
          (occur-kwic-corpus-test--check-rows source ordered)
          (occur-kwic-sort 'source))
        (with-current-buffer result
          (occur-kwic-corpus-test--check-rows source ordered))
        (let ((snapshot (with-current-buffer clone
                          (buffer-substring-no-properties (point-min) (point-max)))))
          (with-current-buffer source
            (goto-char (point-min))
            (insert "\n"))
          (with-current-buffer clone
            (should (equal snapshot (buffer-substring-no-properties (point-min) (point-max))))
            (occur-kwic-corpus-test--check-rows source matches 1))
          (with-current-buffer result
            (revert-buffer nil t)
            (should (equal occur-kwic--sort-spec spec))
            (should-not occur-kwic-sort-case-fold)
            (occur-kwic-corpus-test--check-rows
             source (mapcar (lambda (match) (cons (1+ (car match)) (cdr match))) ordered))
            (occur-kwic-sort 'source)
            (occur-kwic-corpus-test--check-rows
             source (mapcar (lambda (match) (cons (1+ (car match)) (cdr match))) matches)))
          (kill-buffer result)
          (with-current-buffer clone
            (should (equal snapshot (buffer-substring-no-properties (point-min) (point-max))))
            (occur-kwic-corpus-test--check-rows source matches 1)))))))

(ert-deftest occur-kwic-corpus-test-alice-search ()
  (let* ((matches occur-kwic-corpus-test--alice-matches)
         (lowercase (cl-remove-if (lambda (match) (equal (nth 2 match) "She")) matches)))
    (dolist (case `(("\\b[Ss]he\\b" nil ,matches)
                    ("\\bshe\\b" nil ,lowercase)
                    ("\\bshe\\b" t ,matches)
                    ("\\bShe\\b" t (,(nth 16 matches)))))
      (occur-kwic-test--with-results
          ((occur-kwic-corpus-test--text "alice") (car case)
           (progn (text-mode) (setq-local case-fold-search (nth 1 case))
                  (setq-local search-upper-case t)))
        (occur-kwic-corpus-test--check-rows source (nth 2 case))))))

(ert-deftest occur-kwic-corpus-test-botchan-search ()
  (occur-kwic-test--with-results
      ((occur-kwic-corpus-test--text "botchan") "から"
       (progn (text-mode) (setq-local case-fold-search nil)))
    (occur-kwic-corpus-test--check-rows source occur-kwic-corpus-test--botchan-matches)))

(ert-deftest occur-kwic-corpus-test-alice-sorts ()
  (occur-kwic-corpus-test--check-sorts
   "alice" "\\b[Ss]he\\b" occur-kwic-corpus-test--alice-matches
   occur-kwic-corpus-test--alice-sorts occur-kwic-corpus-test--alice-sensitive-sorts))

(ert-deftest occur-kwic-corpus-test-botchan-sorts ()
  (occur-kwic-corpus-test--check-sorts
   "botchan" "から" occur-kwic-corpus-test--botchan-matches
   occur-kwic-corpus-test--botchan-sorts))

(ert-deftest occur-kwic-corpus-test-alice-refresh-and-clone ()
  (occur-kwic-corpus-test--check-refresh-and-clone
   "alice" "\\b[Ss]he\\b" occur-kwic-corpus-test--alice-matches
   (assoc '(before-words 1) occur-kwic-corpus-test--alice-sensitive-sorts)))

(ert-deftest occur-kwic-corpus-test-botchan-refresh-and-clone ()
  (occur-kwic-corpus-test--check-refresh-and-clone
   "botchan" "から" occur-kwic-corpus-test--botchan-matches
   (assoc '(before-words 1) occur-kwic-corpus-test--botchan-sorts)))

;;; occur-kwic-corpus-tests.el ends here
