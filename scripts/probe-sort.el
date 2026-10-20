;;; probe-sort.el --- Explore logical context sort keys -*- lexical-binding: t; -*-

;; Run with: emacs -Q --batch -l scripts/probe-sort.el
;; Optional microbenchmarks: set OCCUR_KWIC_SORT_PROBE_BENCH=1.
;; Historical exploration: its exclusion policy predates the implemented
;; fragment-inclusive word sorting.  Production behavior is covered by ERT.

(require 'cl-lib)
(require 'text-mode)
(require 'subword)
(require 'sort)
(add-to-list 'load-path
             (expand-file-name ".." (file-name-directory load-file-name)))
(require 'occur-kwic)

(defun kwic-sort-probe--spans ()
  "Return word spans using the current buffer's native word motion."
  (save-excursion
    (save-match-data
      (goto-char (point-min))
      (let ((inhibit-field-text-motion t) spans)
        (while (and (< (point) (point-max)) (forward-word 1))
          (let ((end (point)))
            (push (cons (save-excursion (backward-word 1) (point)) end) spans)))
        (nreverse spans)))))

(defun kwic-sort-probe--keys (begin end spans count)
  "Build COUNT-word keys outside BEGIN..END using SPANS.
This experiment skips words intersecting the match and ignores case."
  (let (before after)
    (dolist (span spans)
      (cond ((<= (cdr span) begin)
             (push (downcase (buffer-substring-no-properties (car span) (cdr span))) before))
            ((>= (car span) end)
             (push (downcase (buffer-substring-no-properties (car span) (cdr span))) after))))
    (setq after (nreverse after))
    (list (cl-subseq before 0 (min count (length before)))
          (cl-subseq after 0 (min count (length after))))))

(defun kwic-sort-probe--less (left right)
  "Compare LEFT and RIGHT word tuples lexicographically."
  (while (and left right (equal (car left) (car right)))
    (setq left (cdr left) right (cdr right)))
  (cond ((null left) (and right t))
        ((null right) nil)
        (t (string-lessp (car left) (car right)))))

(defun kwic-sort-probe--words (text setup)
  "Extract words from TEXT after calling SETUP in a temporary buffer."
  (with-temp-buffer
    (funcall setup)
    (insert text)
    (mapcar (lambda (span) (buffer-substring-no-properties (car span) (cdr span)))
            (kwic-sort-probe--spans))))

(defun kwic-sort-probe--examples ()
  "Check tuple ordering and examples of customized word boundaries."
  (dolist (mode '(fundamental-mode text-mode))
    (princ (format "WORDS %S %S\n" mode
                   (kwic-sort-probe--words "don't well-known rock'n'roll" mode))))
  (dolist (joined '(nil t))
    (let ((words (kwic-sort-probe--words
                  "well-known state-of-the-art"
                  (lambda ()
                    (text-mode)
                    (set-syntax-table (copy-syntax-table (syntax-table)))
                    (when joined (modify-syntax-entry ?- "w"))))))
      (cl-assert (equal words (if joined '("well-known" "state-of-the-art")
                               '("well" "known" "state" "of" "the" "art"))))
      (princ (format "CUSTOM hyphens-word=%S %S\n" joined words))))
  (dolist (enabled '(nil t))
    (let ((words (kwic-sort-probe--words
                  "AlphaBeta lowerCase"
                  (lambda () (text-mode) (when enabled (subword-mode 1))))))
      (cl-assert (equal words (if enabled '("Alpha" "Beta" "lower" "Case")
                               '("AlphaBeta" "lowerCase"))))
      (princ (format "BOUNDARY-TABLE subword=%S %S\n" enabled words))))
  (with-temp-buffer
    (text-mode)
    (insert "before MATCH, the last word.")
    (goto-char (point-min))
    (search-forward "MATCH")
    (let ((keys (kwic-sort-probe--keys (- (point) 5) (point) (kwic-sort-probe--spans) 3)))
      (cl-assert (equal keys '(("before") ("the" "last" "word"))))
      (princ (format "THREE-WORD-KEYS %S\n" keys))))
  (let ((lines '("They argue for the proposal."
                 "They argue that it works."
                 "They argue about the cost."
                 "They argue for a change."
                 "They argue for the proposal.")) rows)
    (cl-loop for line in lines for ordinal from 1 do
             (with-temp-buffer
               (text-mode)
               (insert line)
               (goto-char (point-min))
               (search-forward "argue")
               (push (list ordinal
                           (cadr (kwic-sort-probe--keys (- (point) 5) (point)
                                                       (kwic-sort-probe--spans) 3)))
                     rows)))
    (let ((order (mapcar #'car
                        (cl-stable-sort (nreverse rows)
                                        (lambda (a b)
                                          (kwic-sort-probe--less (cadr a) (cadr b)))))))
      (cl-assert (equal order '(3 4 1 5 2)))
      (princ (format "AFTER-3 source-row-order=%S\n" order)))))

(defun kwic-sort-probe--benchmark ()
  "Time boundary extraction and sorting separately, without result rendering."
  (require 'benchmark)
  (dolist (size '(1000 10000))
    (with-temp-buffer
      (text-mode)
      (dotimes (_ size) (insert "They argue for the proposal in this example.\n"))
      (let* ((text (buffer-substring-no-properties (point-min) (point-max)))
             (columns (benchmark-run 1 (occur-kwic--columns text 8)))
             (words (benchmark-run 1 (kwic-sort-probe--spans))))
        (princ (format "BOUNDARIES lines=%d chars=%d columns=%S words=%S\n"
                       size (length text) columns words)))))
  (dolist (size '(1000 10000))
    (let (rows)
      (dotimes (index size)
        (push (list (format "word%05d" (mod (* index 7919) 997))
                    (format "word%05d" (mod (* index 31) 499)) "tail") rows))
      (princ (format "SORT precomputed-tuples=%d time=%S\n" size
                     (benchmark-run 1 (cl-stable-sort rows #'kwic-sort-probe--less)))))))

(defun kwic-sort-probe--reorder-results ()
  "Explore native text sorting without changing canonical entry ownership."
  (let ((source (generate-new-buffer " *kwic-sort-probe-source*")) result)
    (unwind-protect
        (save-window-excursion
          (with-current-buffer source
            (insert "zebra MATCH tail\nalpha MATCH tail\n")
            (setq result (occur-kwic "MATCH")))
          (with-current-buffer result
            (let ((canonical occur-kwic--entries)
                  (header (buffer-substring (point-min)
                                            (save-excursion (goto-char (point-min))
                                                            (forward-line 1) (point)))))
              (dolist (view occur-kwic--views)
                (occur-kwic--delete-view view)
                (setf (occur-kwic--view-width view) nil))
              (let ((inhibit-read-only t)
                    (inhibit-modification-hooks t)
                    (buffer-undo-list t)
                    (inhibit-field-text-motion t))
                (save-restriction
                  (goto-char (point-min))
                  (forward-line 1)
                  (narrow-to-region (point) (point-max))
                  (sort-subr nil #'forward-line #'end-of-line
                             (lambda ()
                               (if (eq (get-text-property (point) 'occur-kwic-entry)
                                       (car canonical)) 1 0))))
                ;; Text properties keep their entry objects; integer offsets
                ;; must be refreshed after the native text sorter moves rows.
                (goto-char (point-min))
                (forward-line 1)
                (while (< (point) (point-max))
                  (let ((entry (get-text-property (point) 'occur-kwic-entry)))
                    (setf (occur-kwic--entry-row-begin entry) (point)
                          (occur-kwic--entry-text-begin entry) (+ (point) occur-kwic--prefix-width)
                          (occur-kwic--entry-row-end entry) (line-end-position)))
                  (forward-line 1)))
              (cl-assert (eq canonical occur-kwic--entries))
              (goto-char (point-min))
              (cl-assert (equal header (buffer-substring (point-min)
                                                        (progn (forward-line 1) (point)))))
              (cl-assert (eq (get-text-property (point) 'occur-kwic-entry) (cadr canonical)))
              (occur-kwic--refresh-windows)
              (dolist (entry canonical)
                (with-current-buffer result
                  (goto-char (+ (occur-kwic--entry-text-begin entry)
                                (occur-kwic--entry-begin entry)))
                  (occur-mode-goto-occurrence)
                  (cl-assert (eq (current-buffer) source))
                  (cl-assert (= (point) (caar (occur-kwic--entry-targets entry))))))
              (princ "NATIVE-REORDER header, entry identity, canonical order, source jumps: OK\n"))))
      (when (buffer-live-p result) (kill-buffer result))
      (kill-buffer source))))

(kwic-sort-probe--examples)
(kwic-sort-probe--reorder-results)
(when (getenv "OCCUR_KWIC_SORT_PROBE_BENCH") (kwic-sort-probe--benchmark))

;;; probe-sort.el ends here
