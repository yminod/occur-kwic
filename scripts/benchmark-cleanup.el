;;; benchmark-cleanup.el --- Bounded cleanup comparisons -*- lexical-binding: t; -*-

;; Run with: emacs -Q --batch -l scripts/benchmark-cleanup.el
;; Synthetic input only.  No large result lines or GUI redisplay.

(require 'cl-lib)
(load (expand-file-name "../occur-kwic.el" (file-name-directory load-file-name)) nil t)

(defun occur-kwic-benchmark--old-release (entries &optional _newest-first)
  "Release ENTRIES in the previous oldest-first order for comparison."
  (dolist (entry entries)
    (dolist (target (occur-kwic--entry-targets entry))
      (set-marker (car target) nil)
      (set-marker (cdr target) nil))))

(defun occur-kwic-benchmark--milliseconds (function)
  "Time FUNCTION in milliseconds, including any garbage collection."
  (let ((start (float-time)))
    (funcall function)
    (* 1000 (- (float-time) start))))

(defun occur-kwic-benchmark--trial (count release &optional buffer-kill foreign)
  "Time releasing COUNT matches with RELEASE.
BUFFER-KILL includes result text, properties, and overlays.  FOREIGN adds
newer, unrelated markers in the source before timing."
  (with-temp-buffer
    (insert (if buffer-kill (apply #'concat (make-list count "X\n"))
              (make-string count ?X)))
    (let* ((source (current-buffer))
           (entries (occur-kwic--collect source "X" nil nil))
           (result (and buffer-kill (generate-new-buffer " *kwic cleanup benchmark*")))
           (other-markers (and foreign (cl-loop repeat (* 2 count) collect (copy-marker 1)))))
      (unwind-protect
          (progn
            (when result
              (occur-kwic--populate result entries source "X" nil nil 'left)
              (set-window-buffer (selected-window) result)
              (with-current-buffer result (occur-kwic--refresh-windows)))
            (garbage-collect)
            (prog1
                (occur-kwic-benchmark--milliseconds
                 (lambda ()
                   (if result
                       (cl-letf (((symbol-function 'occur-kwic--release-entries) release))
                         (kill-buffer result))
                     (funcall release entries))))
              ;; Keep unrelated markers live throughout the timed call.
              (when other-markers
                (cl-assert (eq (marker-buffer (car other-markers)) source)))))
        (when (buffer-live-p result) (kill-buffer result))))))

(let ((current-release (symbol-function 'occur-kwic--release-entries)))
  (princ (format "Emacs %s; interpreted functions; median of three trials (ms)\n" emacs-version))
  (dolist (spec '(("source markers" 2500) ("source markers" 5000)
                  ("source markers" 10000) ("source markers" 20000)
                  ("buffer kill with overlays" 5000 t)
                  ("source markers with newer foreign markers" 5000 nil t)))
    (let (old new)
      (dotimes (_ 3)
        (push (apply #'occur-kwic-benchmark--trial (nth 1 spec)
                     #'occur-kwic-benchmark--old-release (nthcdr 2 spec)) old)
        (push (apply #'occur-kwic-benchmark--trial (nth 1 spec)
                     current-release (nthcdr 2 spec)) new))
      (princ (format "%s, matches=%d: old %.3f, current %.3f\n"
                     (car spec) (nth 1 spec)
                     (nth 1 (sort old #'<)) (nth 1 (sort new #'<)))))))

;;; benchmark-cleanup.el ends here
