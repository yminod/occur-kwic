;;; probe-rtl.el --- Exploratory RTL layout measurements -*- lexical-binding: t; -*-

;; Run in a fresh GUI Emacs, without --batch:
;;   emacs -Q -l scripts/probe-rtl.el
;; Exits that process.  Results go to occur-kwic-rtl-probe.tsv in the
;; temporary directory, or to OCCUR_KWIC_RTL_PROBE_LOG when set.
;; Set OCCUR_KWIC_RTL_PROBE_WALK to also time native visual motion.
;; These are experiments, not supported layout implementations or tests.

(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name ".." (file-name-directory load-file-name)))
(require 'occur-kwic)

(defconst occur-kwic-rtl-probe--samples
  `((hebrew "אבג שלום דהו\nאבגדהוז שלום אב\n" "שלום")
    (arabic "عالم مرحبا سلام\nسلام عالم مرحبا في\n" "مرحبا")
    (numbers "אבג 123 שלום דהו\nאבגדהוז שלום 456 אב\n" "שלום")
    (digits "אב 12345 ג\nאבגד 1234567 גה\n" "23")
    (latin "abc אבג def\nlonger abc אבג def tail\n" "c אב")
    (substring "אבגדהוז\nאבגד\n" "בג")
    (arabic-substring "سلسلة\nمسلسل\n" "سل")
    (long ,(concat (make-string 70 ?א) " שלום " (make-string 90 ?ב)
                   "\n" (make-string 90 ?ג) " שלום " (make-string 70 ?ד)
                   "\n") "שלום")))

(defvar occur-kwic-rtl-probe--log nil)

(defun occur-kwic-rtl-probe--mirrored (entry width alignment)
  "Try reversing ENTRY's logical column model, then map its crop back."
  (let* ((copy (copy-occur-kwic--entry entry))
         (columns (occur-kwic--entry-columns entry))
         (length (1- (length columns)))
         (total (aref columns length))
         (reversed (make-vector (1+ length) 0)))
    (dotimes (index (1+ length))
      (aset reversed index (- total (aref columns (- length index)))))
    (setf (occur-kwic--entry-columns copy) reversed
          (occur-kwic--entry-begin copy) (- length (occur-kwic--entry-end entry))
          (occur-kwic--entry-end copy) (- length (occur-kwic--entry-begin entry)))
    (pcase-let ((`(,start ,end ,padding)
                 (occur-kwic--layout copy width alignment)))
      (list (- length end) (- length start) padding))))

(defun occur-kwic-rtl-probe--install (mode)
  "Install experimental MODE overlays and return match display strings."
  (let* ((view (car occur-kwic--views))
         (width (window-body-width (selected-window)))
         strings)
    (occur-kwic--delete-view view)
    (dolist (entry occur-kwic--entries)
      (let* ((text-begin (occur-kwic--entry-text-begin entry))
             (row-end (occur-kwic--entry-row-end entry))
             (begin (occur-kwic--entry-begin entry))
             (end (occur-kwic--entry-end entry))
             (text (occur-kwic--entry-text entry))
             (layout (if (eq mode 'mirror)
                         (occur-kwic-rtl-probe--mirrored
                          entry width occur-kwic-alignment)
                       (occur-kwic--layout entry width occur-kwic-alignment)))
             (start (nth 0 layout)) (stop (nth 1 layout))
             (padding (nth 2 layout)))
        (if (eq mode 'fields)
            (let ((match (propertize (substring text begin end)
                                     'face list-matching-lines-face)))
              ;; Each string is an atomic object to the outer bidi pass.
              ;; Keep the original result text and markers intact.
              (unless (<= start begin end stop)
                (error "Fields probe requires a fully visible nonempty match"))
              (when (> begin 0)
                (occur-kwic--overlay view text-begin (+ text-begin begin)
                                     'display (substring text start begin)))
              (occur-kwic--overlay view (+ text-begin begin) (+ text-begin end)
                                   'display match)
              (when (< end (length text))
                (occur-kwic--overlay view (+ text-begin end) row-end
                                     'display (substring text end stop)))
              (push match strings))
          (when (> start 0)
            (occur-kwic--overlay view text-begin (+ text-begin start)
                                 'invisible 'occur-kwic))
          (when (< (+ text-begin stop) row-end)
            (occur-kwic--overlay view (+ text-begin stop) row-end
                                 'invisible 'occur-kwic))
          (push nil strings))
        (when (> padding 0)
          (occur-kwic--overlay view (1- text-begin) text-begin
                               'display (concat ":" (make-string padding ?\s))))))
    (nreverse strings)))

(defun occur-kwic-rtl-probe--measure (entry string)
  "Measure ENTRY's actual match pixels, optionally in display STRING.
Return (LEFT RIGHT SPANS VISIBLE-ORDER).  Edges are exclusive on the right."
  (let* ((window (selected-window))
         (begin (+ (occur-kwic--entry-text-begin entry)
                   (occur-kwic--entry-begin entry)))
         (end (+ (occur-kwic--entry-text-begin entry)
                 (occur-kwic--entry-end entry)))
         (row (posn-at-point (occur-kwic--entry-row-begin entry) window))
         (y (and row (+ (cdr (posn-x-y row)) (/ (frame-char-height) 2))))
         left right (spans 0) previous-hit previous-position order)
    (unless y (error "Probe row is off screen"))
    (dotimes (x (window-body-width window t))
      (let* ((position (posn-at-x-y x y window))
             (point (and position (posn-point position)))
             (object (and position (posn-string position)))
             (hit (if string (eq (car-safe object) string)
                    (and (integerp point) (<= begin point) (< point end)))))
        (when hit
          (unless previous-hit (cl-incf spans))
          (unless left (setq left x))
          (setq right (1+ x)))
        (when (and (integerp point)
                   (<= (occur-kwic--entry-text-begin entry) point)
                   (< point (occur-kwic--entry-row-end entry))
                   (not (equal point previous-position)))
          (push (- point (occur-kwic--entry-text-begin entry)) order))
        (setq previous-hit hit previous-position point)))
    (list left right spans (nreverse order))))

(defun occur-kwic-rtl-probe--sample (sample mode alignment)
  "Measure SAMPLE in MODE with ALIGNMENT in a single 80-column window."
  (let ((source (generate-new-buffer " *rtl-probe-source*")) result)
    (unwind-protect
        (progn
          (with-current-buffer source (insert (nth 1 sample)))
          (setq result (occur-kwic--run source (nth 2 sample) nil nil alignment))
          (delete-other-windows)
          (switch-to-buffer result)
          ;; Discard the original display-buffer window before installing
          ;; experiments; otherwise redisplay would create a fresh stock view.
          (occur-kwic--refresh-windows)
          (let ((snapshot (buffer-substring-no-properties (point-min) (point-max)))
                (strings (make-list (length occur-kwic--entries) nil)))
            (unless (eq mode 'current)
              (setq-local bidi-paragraph-direction 'left-to-right))
            (cond ((eq mode 'expanded)
                   (setq occur-kwic--expanded t)
                   (occur-kwic--refresh-windows))
                  ((memq mode '(mirror fields))
                   (setq strings (occur-kwic-rtl-probe--install mode))))
            (goto-char (point-min))
            (set-window-start (selected-window) (point-min))
            (redisplay t)
            (cl-loop for entry in occur-kwic--entries for string in strings
                     for index from 1 do
                     (pcase-let ((`(,left ,right ,spans ,order)
                                  (occur-kwic-rtl-probe--measure entry string)))
                       (push (format "%s\t%s\t%s\t%d\t%s\t%s\t%d\t%S\n"
                                     (car sample) mode alignment index
                                     left right spans order)
                             occur-kwic-rtl-probe--log)))
            (unless (equal snapshot (buffer-substring-no-properties (point-min) (point-max)))
              (error "Probe modified result text"))))
      (when (buffer-live-p result) (kill-buffer result))
      (kill-buffer source))))

(defun occur-kwic-rtl-probe--walk-cost ()
  "Measure native visual traversal; this does not implement visual cropping."
  (dolist (size '(50 100 200))
    (let ((buffer (generate-new-buffer " *rtl-probe-walk*")))
      (unwind-protect
          (progn
            (switch-to-buffer buffer)
            (setq-local truncate-lines t)
            (setq-local bidi-paragraph-direction 'left-to-right)
            (insert "x " (make-string size ?א) "\n")
            (goto-char (point-min))
            (redisplay t)
            (let ((start (float-time))
                  (visited (make-hash-table :test 'eql))
                  (steps 0))
              (while (and (< (point) (point-max)) (< steps (+ size 10)))
                (puthash (point) t visited)
                (move-point-visually 1)
                (cl-incf steps))
              (push (format "# visual-walk chars=%d steps=%d unique=%d seconds=%.6f\n"
                            (+ size 3) steps (hash-table-count visited)
                            (- (float-time) start))
                    occur-kwic-rtl-probe--log)))
        (kill-buffer buffer)))))

(defun occur-kwic-rtl-probe--run ()
  "Run exploratory measurements after GUI startup, write log, and exit."
  (let ((status 0)
        (path (or (getenv "OCCUR_KWIC_RTL_PROBE_LOG")
                  (expand-file-name "occur-kwic-rtl-probe.tsv" temporary-file-directory))))
    (condition-case err
        (progn
          (unless (and (not noninteractive) (display-graphic-p))
            (error "Run in a fresh GUI Emacs, without --batch"))
          (set-frame-width (selected-frame) 80)
          (delete-other-windows)
          (push (format "# %s; font=%S; column-pixels=%d; window-columns=%d\n"
                        (replace-regexp-in-string "\n" " " (emacs-version))
                        (frame-parameter nil 'font)
                        (frame-char-width) (window-body-width))
                occur-kwic-rtl-probe--log)
          (push "sample\tmode\talignment\trow\tleft-px\tright-px\tspans\tvisible-logical-offsets\n"
                occur-kwic-rtl-probe--log)
          (dolist (sample occur-kwic-rtl-probe--samples)
            (dolist (mode '(current ltr mirror fields expanded))
              (dolist (alignment '(left center right))
                (occur-kwic-rtl-probe--sample sample mode alignment))))
          ;; Save the display measurements before the traversal experiment.
          ;; Native visual motion can be expensive even for modest lines.
          (with-temp-file path
            (insert (apply #'concat (reverse occur-kwic-rtl-probe--log))))
          (when (getenv "OCCUR_KWIC_RTL_PROBE_WALK")
            (occur-kwic-rtl-probe--walk-cost)))
      (error (setq status 1)
             (push (format "ERROR: %S\n" err) occur-kwic-rtl-probe--log)))
    (with-temp-file path
      (insert (apply #'concat (nreverse occur-kwic-rtl-probe--log))))
    (kill-emacs status)))

(run-at-time 0.3 nil #'occur-kwic-rtl-probe--run)
(run-at-time 45 nil (lambda () (kill-emacs 2)))

;;; probe-rtl.el ends here
