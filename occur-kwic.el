;;; occur-kwic.el --- Align search matches vertically in context -*- lexical-binding: t; -*-

;; Copyright (C) 2025-2026 Minoru Yasui
;; Author: Minoru Yasui
;; Assisted-by: Codex:GPT-6.1
;; License: GPL-3+
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: matching, convenience

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;; Show one full source line per match, with window-specific KWIC layout.
;; Match starts, centers or ends align at the middle of the result window.
;; Text outside the viewport is hidden, not removed.  Occur navigation is
;; retained; editing results is intentionally unsupported.  Use `g' to
;; refresh, `a' to change alignment and `v' to show a complete result line.
;; Use `s' to sort by context and `S' to toggle case-sensitive sorting.

;;; Code:

(require 'cl-lib)
(require 'replace)
(require 'isearch)
(require 'subr-x)
(require 'sort)

(defgroup occur-kwic nil
  "Search results with vertically aligned matches."
  :group 'matching)

(defcustom occur-kwic-alignment 'left
  "Part of each match to align at the result window's center.
The value is `left', `center' or `right'.  Measured in display columns;
an odd-width match in center alignment rounds its start to the right."
  :type '(choice (const left) (const center) (const right))
  :group 'occur-kwic)

(defcustom occur-kwic-hook nil
  "Hook run after a successful KWIC search has been displayed.
Mode initialization also runs the usual `occur-mode-hook' and
`occur-kwic-mode-hook'.  Use this hook instead of `occur-hook', whose
functions may assume an ordinary line-based Occur buffer."
  :type 'hook
  :group 'occur-kwic)

(defcustom occur-kwic-word-motion-function #'forward-word
  "Function used in the source buffer to collect word boundaries.
Accept a signed word count, like `forward-word': positive moves to word
ends, negative to word beginnings.  Return non-nil on successful movement,
nil when no further word exists.  Respect narrowing and do not edit text.
This option is buffer-local.  Word ranges are saved with search results;
change it in the source and refresh results to use different boundaries."
  :type 'function
  :group 'occur-kwic)
(make-variable-buffer-local 'occur-kwic-word-motion-function)

(defcustom occur-kwic-sort-case-fold t
  "Whether KWIC sorting ignores case, independently of search settings.
Results inherit this buffer-local option from the source.  In a result
buffer, use `occur-kwic-toggle-sort-case' to change it and sort again."
  :type 'boolean
  :group 'occur-kwic)
(make-variable-buffer-local 'occur-kwic-sort-case-fold)

(defcustom occur-kwic-output-size-warning-threshold (* 10 1024 1024)
  "Estimated result-text bytes above which a search asks to continue.
The default is 10 MiB.  Nil disables the warning.  Each search, including
refresh, asks at most once.  Declining preserves previous results.
The estimate includes repeated source lines, line-number prefixes and
newlines in Emacs's internal multibyte representation, but excludes the
header and metadata.  This is a warning threshold, not a memory limit;
markers, text properties and display data require additional memory.
In batch mode, exceeding the threshold signals an error instead of asking."
  :type '(choice (const :tag "Do not warn" nil) (natnum :tag "Bytes"))
  :group 'occur-kwic)

(cl-defstruct (occur-kwic--entry (:constructor occur-kwic--entry-create))
  line text columns words begin end targets row-begin text-begin row-end)
(cl-defstruct (occur-kwic--view (:constructor occur-kwic--view-create))
  window width alignment overlays expanded)

(defvar-local occur-kwic--entries nil)
(defvar-local occur-kwic--source nil)
(defvar-local occur-kwic--regexp nil)
(defvar-local occur-kwic--case-fold nil)
(defvar-local occur-kwic--region nil)
(defvar-local occur-kwic--views nil)
(defvar-local occur-kwic--expanded nil)
(defvar-local occur-kwic--prefix-width 2)
(defvar-local occur-kwic--sort-spec nil)

(defun occur-kwic--word-spans (begin end)
  "Capture word spans between BEGIN and END in the current source buffer.
Return a vector of offset pairs, shared by matches on the same line."
  (save-excursion
    (save-restriction
      (save-match-data
        (narrow-to-region begin end)
        (goto-char begin)
        (let ((motion occur-kwic-word-motion-function)
              (inhibit-field-text-motion t)
              (buffer-read-only t)
              spans done)
          (while (and (not done) (< (point) end))
            (let ((previous (point)))
              (if (not (funcall motion 1))
                  (setq done t)
                (let ((stop (point)))
                  (unless (> stop previous)
                    (user-error "KWIC word motion did not move forward"))
                  (funcall motion -1)
                  (unless (and (>= (point) previous) (< (point) stop))
                    (user-error "KWIC word motion returned inconsistent boundaries"))
                  (push (cons (- (point) begin) (- stop begin)) spans)
                  (goto-char stop)))))
          (vconcat (nreverse spans)))))))

(defun occur-kwic--columns (text tab-size)
  "Return cumulative display columns of TEXT, expanding tabs at TAB-SIZE."
  (let ((columns (make-vector (1+ (length text)) 0))
        (column 0))
    (dotimes (index (length text))
      (let ((character (aref text index)))
        (setq column (+ column (if (= character ?\t)
                                   (- tab-size (% column tab-size))
                                 (char-width character)))))
      (aset columns (1+ index) column))
    columns))

(defun occur-kwic--release-entries (entries &optional newest-first)
  "Release source markers belonging to ENTRIES, newest markers first.
ENTRIES are in source order unless NEWEST-FIRST is non-nil.  Do not
modify their lists: callers may still hold references to them."
  ;; Emacs unlinks a marker by scanning its buffer's marker chain, which
  ;; has newly created markers at the front.  Oldest-first removal makes
  ;; even an otherwise isolated result's cleanup quadratic.
  (let ((inhibit-quit t))
    (dolist (entry (if newest-first entries (reverse entries)))
      (dolist (target (reverse (occur-kwic--entry-targets entry)))
        (set-marker (cdr target) nil)
        (set-marker (car target) nil)))))

(defun occur-kwic--confirm-output-size (bytes)
  "Ask whether to continue generating at least BYTES of result text.
Signal quit on refusal, or a user error in batch mode."
  (when noninteractive
    (user-error
     "KWIC result text exceeds the size warning threshold; adjust `occur-kwic-output-size-warning-threshold' to continue"))
  (unless (yes-or-no-p
           (format (concat "KWIC result text already needs about %.1f MiB, plus metadata; "
                           "Emacs may slow down or run out of memory.  Continue? ")
                   (/ bytes 1048576.0)))
    (signal 'quit nil)))

(defun occur-kwic--collect (source regexp case-fold region)
  "Collect SOURCE matches for REGEXP under CASE-FOLD within REGION.
REGION is nil or a pair of source positions.  Keep line numbers relative
to SOURCE's original accessible portion.  Do not change SOURCE."
  (with-current-buffer source
    (save-excursion
      (save-restriction
        (save-match-data
          (let ((start (if region (max (point-min) (car region)) (point-min)))
                (limit (if region (min (point-max) (cdr region)) (point-max))))
            ;; `narrow-to-region' accepts reversed endpoints, so an empty
            ;; intersection must be handled before changing the restriction.
            (when (< start limit)
              (let ((line-offset (1- (line-number-at-pos start)))
                    (inhibit-field-text-motion t)
                    (case-fold-search case-fold)
                    (tab-size (max 1 tab-width))
                    (warning-threshold occur-kwic-output-size-warning-threshold)
                    (text-bytes 0) (match-count 0)
                    entries complete done
                    cached-begin cached-end cached-line cached-text cached-columns cached-words
                    cached-bytes cached-row-overhead)
                (narrow-to-region start limit)
                (goto-char start)
                (unwind-protect
                    (progn
                      (while (and (not done) (< (point) limit)
                                  (re-search-forward regexp limit t))
                        (let ((begin (match-beginning 0))
                              (end (match-end 0)))
                          ;; Matches arrive in source order, so one cached
                          ;; line is enough.  Cache only immutable line data;
                          ;; match offsets and source markers remain per entry.
                          (when (or (null cached-end) (> begin cached-end))
                            (setq cached-begin (save-excursion
                                                 (goto-char begin) (line-beginning-position))
                                  cached-end (save-excursion
                                               (goto-char begin) (line-end-position))
                                  cached-line (+ line-offset (line-number-at-pos begin))
                                  cached-text nil cached-columns nil cached-words nil
                                  cached-bytes nil
                                  cached-row-overhead (+ 2 (length (number-to-string cached-line)))))
                          (when (> end cached-end)
                            (user-error "KWIC does not support matches containing a newline"))
                          ;; A final newline does not create an extra result line.
                          (unless (and (= begin end limit) (eq (char-before limit) ?\n))
                            (unless cached-text
                              (setq cached-text (buffer-substring-no-properties
                                                 cached-begin cached-end)))
                            (when warning-threshold
                              (unless cached-bytes
                                ;; Inserting unibyte text into the multibyte
                                ;; result also expands non-ASCII raw bytes.
                                (setq cached-bytes
                                      (string-bytes (if (multibyte-string-p cached-text)
                                                        cached-text
                                                      (string-to-multibyte cached-text)))))
                              (setq text-bytes (+ text-bytes cached-bytes)
                                    match-count (1+ match-count))
                              ;; A larger line number widens ALL row prefixes.
                              (let ((bytes (+ text-bytes (* match-count cached-row-overhead))))
                                (when (> bytes warning-threshold)
                                  (occur-kwic--confirm-output-size bytes)
                                  (setq warning-threshold nil))))
                            (unless cached-columns
                              (setq cached-columns (occur-kwic--columns cached-text tab-size)
                                    cached-words (occur-kwic--word-spans cached-begin cached-end)))
                            ;; Register both markers before a pending quit
                            ;; can interrupt; only this small allocation is atomic.
                            (let ((inhibit-quit t))
                              (push (occur-kwic--entry-create
                                     :line cached-line :text cached-text :columns cached-columns
                                     :words cached-words
                                     :begin (- begin cached-begin) :end (- end cached-begin)
                                     :targets (list (cons (copy-marker begin)
                                                          (copy-marker end t))))
                                    entries)))
                          (when (= begin end)
                            (if (< (point) limit) (forward-char 1) (setq done t)))))
                      (setq complete t)
                      (nreverse entries))
                  (unless complete (occur-kwic--release-entries entries t)))))))))))

(defun occur-kwic--delete-view (view)
  "Remove the display overlays for VIEW."
  (mapc #'delete-overlay (occur-kwic--view-overlays view))
  (setf (occur-kwic--view-overlays view) nil))

(defun occur-kwic--cleanup ()
  "Release this result buffer's private markers and overlays."
  (let ((inhibit-quit t))
    (mapc #'occur-kwic--delete-view occur-kwic--views)
    (when occur-kwic--region
      (set-marker (cdr occur-kwic--region) nil)
      (set-marker (car occur-kwic--region) nil))
    (occur-kwic--release-entries occur-kwic--entries)
    ;; Cleanup also runs before mode initialization in a fresh buffer.
    ;; Do not touch the shared arrow belonging to another Occur buffer.
    (when (local-variable-p 'overlay-arrow-position)
      (when (and (markerp overlay-arrow-position)
                 (eq (marker-buffer overlay-arrow-position) (current-buffer)))
        (set-marker overlay-arrow-position nil))
      (setq overlay-arrow-position nil))
    (setq occur-kwic--views nil occur-kwic--entries nil occur-kwic--region nil
          occur-kwic--expanded nil)))

(defun occur-kwic--discard-result (buffer entries &optional newest-first)
  "Discard incomplete BUFFER and release its collected ENTRIES.
NEWEST-FIRST has the same meaning as in `occur-kwic--release-entries'."
  (let ((inhibit-quit t))
    (occur-kwic--release-entries entries newest-first)
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (when (eq occur-kwic--entries entries) (setq occur-kwic--entries nil))
        (occur-kwic--cleanup)
        ;; This is generated, incomplete output, including on failed refresh.
        (set-buffer-modified-p nil)
        (let ((kill-buffer-query-functions nil)) (kill-buffer buffer))))))

(defun occur-kwic--entry-at-point ()
  "Return the result entry on the current line, or nil."
  (get-text-property (line-beginning-position) 'occur-kwic-entry))

(defun occur-kwic--clone-state ()
  "Give a standard buffer clone its own KWIC markers and display state.
Run in the clone via `clone-buffer-hook', after its text and buffer-local
variables have been copied.  Never clean up the borrowed original state."
  (let ((entries occur-kwic--entries)
        (region occur-kwic--region)
        (expanded occur-kwic--expanded)
        (arrow overlay-arrow-position)
        (modified (buffer-modified-p))
        complete
        (newest-first t))
    ;; Drop borrowed ownership before allocating or changing anything.
    (setq occur-kwic--views nil occur-kwic--entries nil
          occur-kwic--region nil occur-kwic--expanded (eq expanded t)
          overlay-arrow-position nil)
    (unwind-protect
        (progn
          (when (markerp arrow)
            (setq overlay-arrow-position (copy-marker (marker-position arrow))))
          (when region
            (let ((inhibit-quit t))
              (setq occur-kwic--region (cons (copy-marker (car region))
                                            (copy-marker (cdr region) t)))))
          (dolist (entry entries)
            (let ((inhibit-quit t)
                  (copy (copy-occur-kwic--entry entry)))
              (setf (occur-kwic--entry-targets copy)
                    (mapcar (lambda (target)
                              (cons (copy-marker (car target))
                                    (copy-marker (cdr target) t)))
                            (occur-kwic--entry-targets entry)))
              ;; Register each completed copy, so a quit between entries
              ;; still leaves an owned list for cleanup.
              (push copy occur-kwic--entries)
              (when (eq expanded entry) (setq occur-kwic--expanded copy))))
          (let ((inhibit-quit t))
            (setq occur-kwic--entries (nreverse occur-kwic--entries)
                  newest-first nil))
          (let ((inhibit-read-only t)
                (inhibit-modification-hooks t)
                (buffer-undo-list t))
            (unwind-protect
                (save-restriction
                  (widen)
                  (dolist (entry occur-kwic--entries)
                    (add-text-properties
                     (occur-kwic--entry-row-begin entry) (1+ (occur-kwic--entry-row-end entry))
                     `(occur-kwic-entry ,entry
                       occur-target ,(if (fboundp 'occur--targets-start)
                                         (occur-kwic--entry-targets entry)
                                       (caar (occur-kwic--entry-targets entry)))))))
              (set-buffer-modified-p modified)))
          (occur-kwic--refresh-windows)
          (setq complete t))
      (unless complete
        (occur-kwic--discard-result (current-buffer) occur-kwic--entries newest-first)))))

(defun occur-kwic--bound (columns column upper)
  "Binary search COLUMNS for COLUMN.
Return the first index >= COLUMN, or the last <= COLUMN if UPPER."
  (let ((low 0) (high (length columns)))
    (while (< low high)
      (let ((middle (/ (+ low high) 2)))
        (if (if upper (<= (aref columns middle) column)
              (< (aref columns middle) column))
            (setq low (1+ middle))
          (setq high middle))))
    (if upper (max 0 (1- low)) (min low (1- (length columns))))))

(defun occur-kwic--layout (entry width alignment)
  "Return (START END PADDING) for ENTRY in WIDTH columns under ALIGNMENT.
START and END are offsets into its full text.  Reserve the final window
column for Emacs's truncation/continuation indicator."
  (let* ((columns (occur-kwic--entry-columns entry))
         (begin (occur-kwic--entry-begin entry))
         (end (occur-kwic--entry-end entry))
         (match-width (- (aref columns end) (aref columns begin)))
         (anchor (/ width 2))
         (offset (pcase alignment
                   ('left 0) ('center (/ match-width 2)) ('right match-width)
                   (_ (user-error "Invalid KWIC alignment: %S" alignment))))
         (origin (- anchor offset (aref columns begin)))
         (right (- width 1 origin (if (= begin end) 1 0)))
         (start (occur-kwic--bound columns (max 0 (- occur-kwic--prefix-width origin)) nil))
         (stop (occur-kwic--bound columns (max 0 right) t)))
    ;; Never leave combining marks without their hidden base character.
    (while (and (< start (1- (length columns)))
                (= (aref columns start) (aref columns (1+ start))))
      (setq start (1+ start)))
    (list start (max start stop)
          (max 0 (min (- width 1 occur-kwic--prefix-width)
                      (- (+ origin (aref columns start)) occur-kwic--prefix-width))))))

(defun occur-kwic--overlay (view begin end &rest properties)
  "Add to VIEW an overlay from BEGIN to END with PROPERTIES."
  (let (overlay)
    (let ((inhibit-quit t))
      (setq overlay (make-overlay begin end nil t nil))
      (push overlay (occur-kwic--view-overlays view)))
    (overlay-put overlay 'window (occur-kwic--view-window view))
    (overlay-put overlay 'occur-kwic t)
    (while properties
      (overlay-put overlay (pop properties) (pop properties)))
    overlay))

(defun occur-kwic--draw-view (view)
  "Rebuild VIEW without changing result text or source markers."
  ;; Invalidate before deleting old overlays, since deletion can quit too.
  (setf (occur-kwic--view-width view) nil)
  (occur-kwic--delete-view view)
  (let* ((window (occur-kwic--view-window view))
         (width (window-body-width window))
         (expanded occur-kwic--expanded))
    (unless expanded (set-window-hscroll window 0))
    (dolist (entry occur-kwic--entries)
      (unless (or (eq expanded t) (eq expanded entry))
        (pcase-let* ((`(,start ,end ,padding)
                       (occur-kwic--layout entry width occur-kwic-alignment))
                     (text-begin (occur-kwic--entry-text-begin entry))
                     (row-end (occur-kwic--entry-row-end entry)))
          (when (> start 0)
            (occur-kwic--overlay view text-begin (+ text-begin start)
                                 'invisible 'occur-kwic))
          (when (< (+ text-begin end) row-end)
            (occur-kwic--overlay view (+ text-begin end) row-end
                                 'invisible 'occur-kwic))
          ;; Replacing only the prefix colon keeps padding outside hidden
          ;; text; before-string at an invisible boundary would disappear.
          (when (> padding 0)
            (occur-kwic--overlay view (1- text-begin) text-begin
                                 'display (concat ":" (make-string padding ?\s))))))
      (when (= (occur-kwic--entry-begin entry) (occur-kwic--entry-end entry))
        (let ((position (+ (occur-kwic--entry-text-begin entry)
                           (occur-kwic--entry-begin entry))))
          (occur-kwic--overlay view position (1+ position)
                               'before-string (propertize "|" 'face list-matching-lines-face)))))
    ;; Only a fully drawn view may satisfy the layout cache.
    (setf (occur-kwic--view-width view) width
          (occur-kwic--view-alignment view) occur-kwic-alignment
          (occur-kwic--view-expanded view) expanded)))

(defun occur-kwic--refresh-windows (&optional _changed-window)
  "Maintain independent display state for each window showing this buffer."
  ;; Cropped rows already fit their windows.  In particular, a cursor in
  ;; the uncropped header must not scroll all those rows away at redisplay.
  ;; Full-line views need ordinary scrolling so isearch can expose point.
  (setq-local auto-hscroll-mode
              (and occur-kwic--expanded (default-value 'auto-hscroll-mode)))
  (let ((windows (get-buffer-window-list (current-buffer) nil t)))
    (dolist (view (copy-sequence occur-kwic--views))
      (unless (memq (occur-kwic--view-window view) windows)
        (occur-kwic--delete-view view)
        (setq occur-kwic--views (delq view occur-kwic--views))))
    (dolist (window windows)
      (let ((view (cl-find window occur-kwic--views :key #'occur-kwic--view-window)))
        (unless view
          (setq view (occur-kwic--view-create :window window))
          (push view occur-kwic--views))
        (unless (and (equal (occur-kwic--view-width view) (window-body-width window))
                     (eq (occur-kwic--view-alignment view) occur-kwic-alignment)
                     (eq (occur-kwic--view-expanded view) occur-kwic--expanded))
          (occur-kwic--draw-view view))))))

(defun occur-kwic--isearch-start ()
  "Expose full lines while searching result text.
Isearch tests invisibility in the buffer, including overlays belonging to
other windows, so temporarily expose the text in every result window."
  (setq occur-kwic--expanded t)
  (occur-kwic--refresh-windows))

(defun occur-kwic--isearch-end ()
  "Keep the final search result's full line visible."
  (setq occur-kwic--expanded (occur-kwic--entry-at-point))
  (occur-kwic--refresh-windows))

(defun occur-kwic-toggle-line ()
  "Toggle full-line display for the current result in all its windows."
  (interactive)
  (occur-kwic--refresh-windows)
  (let ((entry (occur-kwic--entry-at-point))
        (view (cl-find (selected-window) occur-kwic--views
                       :key #'occur-kwic--view-window)))
    (unless (and entry view) (user-error "No KWIC result on this line"))
    (setq occur-kwic--expanded (unless (eq occur-kwic--expanded entry) entry))
    (occur-kwic--refresh-windows)))

(defun occur-kwic-set-alignment (alignment)
  "Align match starts, centers or ends according to ALIGNMENT.
Return expanded rows to KWIC display and reset every result window's
horizontal scroll, even when reselecting the current alignment."
  (interactive
   (list (intern (completing-read "Align match: " '("left" "center" "right")
                                  nil t nil nil (symbol-name occur-kwic-alignment)))))
  (unless (memq alignment '(left center right))
    (user-error "Invalid KWIC alignment: %S" alignment))
  (setq-local occur-kwic-alignment alignment)
  (setq occur-kwic--expanded nil)
  (occur-kwic--refresh-windows)
  ;; A cached view need not be redrawn when the same alignment is chosen.
  ;; Its scroll position still needs resetting.
  (dolist (view occur-kwic--views)
    (set-window-hscroll (occur-kwic--view-window view) 0)))

(defun occur-kwic--sort-key (entry kind count)
  "Extract ENTRY's logical context key for KIND and COUNT.
Keys contain strings, nearest to the match first.  A word intersecting
the match contributes only its unmatched prefix or suffix."
  (let* ((text (occur-kwic--entry-text entry))
         (begin (occur-kwic--entry-begin entry))
         (end (occur-kwic--entry-end entry))
         (before (memq kind '(before-words before-characters)))
         (boundary (if before begin end))
         key)
    (pcase kind
      ('source nil)
      ('match (setq key (list (substring text begin end))))
      ((or 'before-characters 'after-characters)
       (let ((part (if before (substring text (max 0 (- begin count)) begin)
                     (substring text end (min (length text) (+ end count))))))
         (setq key (list (if before (concat (reverse (string-to-list part))) part)))))
      ((or 'before-words 'after-words)
       (let* ((spans (occur-kwic--entry-words entry))
              (low 0) (high (length spans)))
         ;; Find the last start before BEGIN or the first end after END.
         (while (< low high)
           (let* ((middle (/ (+ low high) 2)) (span (aref spans middle)))
             (if (if before (< (car span) boundary) (<= (cdr span) boundary))
                 (setq low (1+ middle))
               (setq high middle))))
         (let ((index (if before (1- low) low)))
           (while (and (> count 0) (>= index 0) (< index (length spans)))
             (let ((span (aref spans index)))
               (push (substring text (if before (car span) (max end (car span)))
                                (if before (min begin (cdr span)) (cdr span))) key))
             (setq index (+ index (if before -1 1)) count (1- count))))
         (setq key (nreverse key)))))
    (if occur-kwic-sort-case-fold (mapcar #'downcase key) key)))

(defun occur-kwic--sort-less-p (left right)
  "Compare LEFT and RIGHT (string-tuple . source-ordinal) keys."
  (let ((a (car left)) (b (car right)))
    (while (and a b (equal (car a) (car b)))
      (setq a (cdr a) b (cdr b)))
    (cond ((and a b) (string-lessp (car a) (car b)))
          (a nil) (b t)
          (t (< (cdr left) (cdr right))))))

(defun occur-kwic--row-location (position)
  "Describe POSITION by entry identity and row offset, or header position."
  (save-excursion
    (goto-char position)
    (let ((entry (occur-kwic--entry-at-point)))
      (if entry (cons entry (- position (occur-kwic--entry-row-begin entry)))
        position))))

(defun occur-kwic--location-position (location)
  "Resolve a saved row LOCATION after sorting."
  (if (consp location)
      (min (occur-kwic--entry-row-end (car location))
           (+ (occur-kwic--entry-row-begin (car location)) (cdr location)))
    location))

(defun occur-kwic--reorder (keys)
  "Sort result rows using precomputed KEYS, retaining entry ownership.
Preserve point, window locations, expansion and the Occur arrow by entry.
Rollback text on an error or quit, then rebuild row offsets and overlays."
  (let ((location (occur-kwic--row-location (point)))
        (arrow (and (markerp overlay-arrow-position)
                    (eq (marker-buffer overlay-arrow-position) (current-buffer))
                    (occur-kwic--row-location overlay-arrow-position)))
        (windows (mapcar (lambda (window)
                           (list window
                                 (occur-kwic--row-location (window-point window))
                                 (occur-kwic--row-location (window-start window))))
                         (get-buffer-window-list (current-buffer) nil t)))
        (modified (buffer-modified-p))
        (inhibit-read-only t)
        (inhibit-modification-hooks t)
        (buffer-undo-list t))
    (unwind-protect
        (progn
          (dolist (view occur-kwic--views)
            (setf (occur-kwic--view-width view) nil)
            (occur-kwic--delete-view view))
          (save-restriction
            (goto-char (point-min))
            (forward-line 1)
            (narrow-to-region (point) (point-max))
            (atomic-change-group
              (sort-subr nil #'forward-line #'end-of-line
                         (lambda () (gethash (occur-kwic--entry-at-point) keys))
                         nil #'occur-kwic--sort-less-p))))
      ;; A sort moves text properties, but cannot maintain integer offsets
      ;; or result-local markers.  Repair after success AND after rollback.
      (let ((inhibit-quit t))
        (goto-char (point-min))
        (forward-line 1)
        (while (< (point) (point-max))
          (let ((entry (occur-kwic--entry-at-point)))
            (setf (occur-kwic--entry-row-begin entry) (point)
                  (occur-kwic--entry-text-begin entry) (+ (point) occur-kwic--prefix-width)
                  (occur-kwic--entry-row-end entry) (line-end-position)))
          (forward-line 1))
        (goto-char (occur-kwic--location-position location))
        (when arrow
          (set-marker overlay-arrow-position (occur-kwic--location-position arrow)))
        (dolist (state windows)
          (set-window-start (car state) (occur-kwic--location-position (nth 2 state)) t)
          (set-window-point (car state) (occur-kwic--location-position (nth 1 state))))
        (set-buffer-modified-p modified)
        (occur-kwic--refresh-windows)))))

(defun occur-kwic-sort (kind &optional count)
  "Sort KWIC results by KIND, with up to COUNT context units.
KIND is `before-words', `after-words', `before-characters',
`after-characters', `match' or `source'.  Context keys compare nearest
units first.  Words cut by the match contribute their remaining fragment,
counted as one unit.  Character keys include spaces and punctuation;
COUNT counts Emacs characters, not display columns or grapheme clusters.
Context stays within the saved accessible source line.  Equal keys always
retain original source order.  Use `occur-kwic-sort-case-fold' for case.
Interactively prompt for KIND and COUNT (default 3).  `source' restores
the original order.  Widen a narrowed result buffer before sorting."
  (interactive
   (let* ((kind (intern (completing-read
                        "Sort KWIC: " '("after-words" "before-words" "after-characters"
                                        "before-characters" "match" "source")
                        nil t nil nil (symbol-name (or (car occur-kwic--sort-spec)
                                                       'after-words)))))
          (count (when (memq kind '(before-words after-words before-characters after-characters))
                   (read-number (if (memq kind '(before-words after-words))
                                    "Number of words: " "Number of characters: ")
                                (or (cadr occur-kwic--sort-spec) 3)))))
     (list kind count)))
  (unless (derived-mode-p 'occur-kwic-mode) (user-error "Not a KWIC result buffer"))
  (when (buffer-narrowed-p) (user-error "Widen KWIC results before sorting"))
  (unless (memq kind '(before-words after-words before-characters after-characters match source))
    (user-error "Invalid KWIC sort: %S" kind))
  (when (memq kind '(before-words after-words before-characters after-characters))
    (unless (and (integerp count) (> count 0))
      (user-error "KWIC context count must be a positive integer")))
  (let ((keys (make-hash-table :test #'eq)) (ordinal 0))
    ;; Extract every key before changing result text.  The canonical list
    ;; remains in source/marker-creation order even after repeated sorts.
    (dolist (entry occur-kwic--entries)
      (puthash entry (cons (occur-kwic--sort-key entry kind count) ordinal) keys)
      (setq ordinal (1+ ordinal)))
    (occur-kwic--reorder keys))
  (setq occur-kwic--sort-spec (unless (eq kind 'source) (list kind count))
        mode-line-process (unless (eq kind 'source)
                            (format " [%s%s; %s]" kind (if count (format " %d" count) "")
                                    (if occur-kwic-sort-case-fold "ignore case" "case sensitive"))))
  (force-mode-line-update))

(defun occur-kwic-toggle-sort-case ()
  "Toggle case folding and reapply the current KWIC sort."
  (interactive)
  (let ((previous occur-kwic-sort-case-fold) complete)
    (unwind-protect
        (progn
          (setq-local occur-kwic-sort-case-fold (not previous))
          (apply #'occur-kwic-sort (or occur-kwic--sort-spec '(source)))
          (setq complete t)
          (message "KWIC sorting %s case" (if occur-kwic-sort-case-fold "ignores" "distinguishes")))
      (unless complete (setq occur-kwic-sort-case-fold previous)))))

(defun occur-kwic--no-edit ()
  "Explain why result editing is unavailable."
  (interactive)
  (user-error "KWIC results cannot be edited; edit the source and press g to refresh"))

(defun occur-kwic--check-mode-change ()
  "Prevent interactive entry into Occur Edit, including through M-x."
  (when (or (eq this-command 'occur-edit-mode)
            (eq real-this-command 'occur-edit-mode))
    (occur-kwic--no-edit)))

(defun occur-kwic-rename-buffer ()
  "Give this result buffer a name based on its source."
  (interactive)
  (rename-buffer (format "*Occur KWIC: %s*" (buffer-name occur-kwic--source)) t))

(defvar occur-kwic-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "a" #'occur-kwic-set-alignment)
    (define-key map "v" #'occur-kwic-toggle-line)
    (define-key map "s" #'occur-kwic-sort)
    (define-key map "S" #'occur-kwic-toggle-sort-case)
    (define-key map "e" #'occur-kwic--no-edit)
    (define-key map "n" #'next-error-no-select)
    (define-key map "p" #'previous-error-no-select)
    (define-key map [remap occur-edit-mode] #'occur-kwic--no-edit)
    (define-key map [remap occur-rename-buffer] #'occur-kwic-rename-buffer)
    (define-key map [menu-bar occur] 'undefined)
    map)
  "Keymap for `occur-kwic-mode'.")

(easy-menu-define occur-kwic-menu occur-kwic-mode-map
  "KWIC result menu."
  '("Occur KWIC"
    ["Previous match" occur-prev t]
    ["Next match" occur-next t]
    ["Go to occurrence" occur-mode-goto-occurrence t]
    ["Display occurrence" occur-mode-display-occurrence t]
    ["Alignment..." occur-kwic-set-alignment t]
    ["Toggle full line" occur-kwic-toggle-line t]
    ["Sort..." occur-kwic-sort t]
    ["Ignore case in sort" occur-kwic-toggle-sort-case :style toggle :selected occur-kwic-sort-case-fold]
    ["Edit results (unsupported)" occur-kwic--no-edit nil]
    ["Refresh" revert-buffer t]
    ["Quit" quit-window t]))

(put 'occur-kwic-mode 'no-clone-indirect t)
(define-derived-mode occur-kwic-mode occur-mode "Occur KWIC"
  "Occur navigation with one KWIC row per match.
Use `a' for alignment, `v' for a full line, `s' to sort, `S' to toggle
case-sensitive sorting, and `g' to search again with the same sort.
Result editing is unsupported; edit the source buffer instead."
  (setq-local truncate-lines t)
  (setq-local auto-hscroll-mode nil)
  (setq-local display-line-numbers nil)
  (setq-local overlay-arrow-position nil)
  (setq-local buffer-read-only t)
  (setq-local revert-buffer-function #'occur-kwic--revert)
  (add-to-invisibility-spec 'occur-kwic)
  (add-hook 'window-size-change-functions #'occur-kwic--refresh-windows nil t)
  (add-hook 'window-buffer-change-functions #'occur-kwic--refresh-windows nil t)
  (add-hook 'post-command-hook #'occur-kwic--refresh-windows nil t)
  (add-hook 'isearch-mode-hook #'occur-kwic--isearch-start nil t)
  (add-hook 'isearch-mode-end-hook #'occur-kwic--isearch-end nil t)
  (add-hook 'change-major-mode-hook #'occur-kwic--check-mode-change nil t)
  (add-hook 'change-major-mode-hook #'occur-kwic--cleanup t t)
  (add-hook 'clone-buffer-hook #'occur-kwic--clone-state nil t)
  (add-hook 'kill-buffer-hook #'occur-kwic--cleanup nil t))

(defun occur-kwic--populate (buffer entries source regexp case-fold region alignment)
  "Fill BUFFER with ENTRIES and retain its search and display settings.
SOURCE, REGEXP, CASE-FOLD, REGION and ALIGNMENT describe the search."
  (with-current-buffer buffer
    (occur-kwic--cleanup)
    (occur-kwic-mode)
    (setq occur-kwic--entries entries occur-kwic--source source
          occur-kwic--regexp regexp occur-kwic--case-fold case-fold
          occur-kwic--region
          (and region (with-current-buffer source
                        (cons (copy-marker (car region))
                              (copy-marker (cdr region) t)))))
    (setq-local occur-kwic-alignment alignment)
    (setq-local occur-kwic-sort-case-fold (buffer-local-value 'occur-kwic-sort-case-fold source))
    (setq default-directory (buffer-local-value 'default-directory source))
    (setq occur-kwic--prefix-width
          (1+ (length (number-to-string (occur-kwic--entry-line (car (last entries)))))))
    (let ((inhibit-read-only t) (buffer-undo-list t))
      (widen)
      (erase-buffer)
      (insert (propertize (let ((print-escape-newlines t))
                           (format "%d match%s for %S in buffer: %s\n"
                                  (length entries) (if (= (length entries) 1) "" "es")
                                  regexp (buffer-name source)))
                           'face list-matching-lines-buffer-name-face))
      (dolist (entry entries)
        (let ((row-begin (point))
              (targets (if (fboundp 'occur--targets-start)
                           (occur-kwic--entry-targets entry)
                         ;; Older Occur versions expect a single marker.
                         (caar (occur-kwic--entry-targets entry)))))
          (insert (propertize (format (format "%%%dd:" (1- occur-kwic--prefix-width))
                                      (occur-kwic--entry-line entry))
                               'face list-matching-lines-prefix-face 'occur-prefix t))
          (setf (occur-kwic--entry-row-begin entry) row-begin
                (occur-kwic--entry-text-begin entry) (point))
          (insert (occur-kwic--entry-text entry))
          (setf (occur-kwic--entry-row-end entry) (point))
          (insert "\n")
          (add-text-properties row-begin (point)
                               `(occur-target ,targets occur-kwic-entry ,entry
                                 mouse-face highlight follow-link t
                                 help-echo "RET or mouse-2: go to this match"))
          (let* ((text-begin (occur-kwic--entry-text-begin entry))
                 (begin (+ text-begin (occur-kwic--entry-begin entry)))
                 (end (+ text-begin (occur-kwic--entry-end entry)))
                 (columns (occur-kwic--entry-columns entry))
                 (text (occur-kwic--entry-text entry)))
            ;; Occur moves to the end of its match property.  A property
            ;; on the newline would land on the following result instead.
            (if (and (= begin end) (= end (occur-kwic--entry-row-end entry)))
                (put-text-property (1- begin) begin 'occur-match t)
              (put-text-property begin (if (= begin end) (1+ end) end) 'occur-match t))
            (unless (= begin end)
              (put-text-property begin end 'face list-matching-lines-face))
            (dotimes (index (length text))
              (when (= (aref text index) ?\t)
                (put-text-property (+ text-begin index) (+ text-begin index 1)
                                   'display (make-string (- (aref columns (1+ index))
                                                             (aref columns index)) ?\s)))))))
      ;; Even a programmatic change of major mode cannot make the snapshot
      ;; writable through Occur Edit's after-change hook.
      (put-text-property (point-min) (point-max) 'read-only t)
      (goto-char (point-min))
      (set-buffer-modified-p nil))
    buffer))

(defun occur-kwic--run (source regexp case-fold region alignment &optional buffer sort-settings)
  "Search SOURCE and display KWIC results, optionally reusing BUFFER.
REGEXP, CASE-FOLD, REGION and ALIGNMENT specify the search and layout.
SORT-SETTINGS, if non-nil, is (SORT-SPEC CASE-FOLD) retained on refresh."
  (unless (and (stringp regexp) (not (string-empty-p regexp)))
    (user-error "KWIC requires a nonempty regexp"))
  (unless (buffer-live-p source) (user-error "The source buffer has been killed"))
  (when (eq buffer source) (user-error "Source and result buffers must differ"))
  (unless (memq alignment '(left center right))
    (user-error "Invalid KWIC alignment: %S" alignment))
  ;; Collect first: a regexp error or multiline match leaves old results intact.
  (let* ((region (and region (cons (if (markerp (car region))
                                     (marker-position (car region)) (car region))
                                 (if (markerp (cdr region))
                                     (marker-position (cdr region)) (cdr region)))))
         (entries (occur-kwic--collect source regexp case-fold region)))
    (if (null entries)
        (progn
          (let ((old (or buffer (get-buffer "*Occur KWIC*"))))
            (when (and (buffer-live-p old) (not (eq old source))) (kill-buffer old)))
          (message "No matches for %S" regexp)
          nil)
      (let (started complete)
        (unwind-protect
            (progn
              (unless buffer
                (setq buffer (get-buffer "*Occur KWIC*"))
                (when (eq buffer source)
                  (with-current-buffer buffer (rename-buffer "*Occur KWIC source*" t))
                  (setq buffer nil))
                (setq buffer (or buffer (get-buffer-create "*Occur KWIC*"))))
              (setq started t)
              (occur-kwic--populate buffer entries source regexp case-fold region alignment)
              (when sort-settings
                (with-current-buffer buffer
                  (setq-local occur-kwic-sort-case-fold (cadr sort-settings))
                  (apply #'occur-kwic-sort (or (car sort-settings) '(source)))))
              (display-buffer buffer)
              (with-current-buffer buffer (occur-kwic--refresh-windows))
              (setq complete t))
          (unless complete
            (occur-kwic--discard-result (and started buffer) entries))))
      (setq next-error-last-buffer buffer)
      (with-current-buffer buffer (run-hooks 'occur-kwic-hook))
      (let ((print-escape-newlines t))
        (message "%d match%s for %S" (length entries)
                 (if (= (length entries) 1) "" "es") regexp))
      buffer)))

(defun occur-kwic--revert (_ignore-auto _noconfirm)
  "Rerun the stored search, preserving its name, alignment and sorting."
  (occur-kwic--run occur-kwic--source occur-kwic--regexp occur-kwic--case-fold
                   occur-kwic--region occur-kwic-alignment (current-buffer)
                   (list occur-kwic--sort-spec occur-kwic-sort-case-fold)))

(defun occur-kwic-clone-buffer ()
  "Clone this result snapshot using standard buffer cloning support.
Interactively honor the standard prefix argument for naming the clone."
  (interactive)
  (if (called-interactively-p 'interactive)
      (call-interactively #'clone-buffer)
    (clone-buffer nil t)))

;;;###autoload
(defun occur-kwic (regexp &optional region)
  "Display one KWIC result per non-overlapping match of REGEXP.
Search the current buffer's accessible portion, restricted further to
REGION (a pair of positions) when non-nil.  Interactively use the active
region, if any.  Multiline matches are unsupported and signal an error.
Prefix arguments for context lines or collection are not supported."
  (interactive
   (progn
     (when current-prefix-arg
       (user-error "KWIC does not support context-line or collection prefix arguments"))
     (let ((region (and (use-region-p) (cons (region-beginning) (region-end)))))
       (list (read-regexp "List matches (KWIC): " 'regexp-history-last) region))))
  (occur-kwic--run
   (current-buffer) regexp
   (if (and case-fold-search search-upper-case)
       (isearch-no-upper-case-p regexp t) case-fold-search)
   region occur-kwic-alignment))

(provide 'occur-kwic)
;;; occur-kwic.el ends here
