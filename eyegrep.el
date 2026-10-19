;;; eyegrep.el --- Helper for eye-grep -*- lexical-binding: t -*-

;; Copyright (C) 2025 Minoru Yasui
;; License: GPL-3+

;;; Usage:

;; Add the following line to your init.el file.
;; (autoload 'eyegrep "eyegrep" "Helper for eye-grep" t)

;;; Commentary:

;; This package centers grep matches to minimize horizontal eye movement.
;; Lines containing control characters may not align correctly.

;; This package targets GNU Emacs 27.1 or later.

;;; Code:

(require 'mule-util)

;;;###autoload
(defun eyegrep (pattern)
  "Center output to assist eye-grep."
  (interactive "sList lines matching pattern: ")
  (unless (and pattern (not (equal pattern "")))
    (error "Eyegrep doesn't work with the empty regexp"))
  (save-excursion
    (goto-char (point-max))
    (let ((active-buf (current-buffer))
          (eyegrep-buf
           (generate-new-buffer (generate-new-buffer-name "*Eyegrep*")))
          ;; Subtract the width of fringes on both sides
          ;; from the frame width.
          (buffer-width (- (window-body-width) 2))
          (line-number-width (length (format "%d" (line-number-at-pos))))
          (match-count 0))
      (goto-char (point-min))
      (let ((result-text-width (- buffer-width line-number-width)))
        (while (re-search-forward pattern nil t)
          (setq match-count (1+ match-count))
          (let* ((line-number-index
                  (format (format "%%%dd:" line-number-width)
                          (line-number-at-pos)))
                 (match-beg (match-beginning 0))
                 (match-marker (set-marker (make-marker) match-beg))
                 (match-str (match-string 0))
                 (match-width (string-width match-str))
                 (margin-width
                  (if (<= result-text-width match-width)
                      0
                    (- (/ (- result-text-width
                             (if (xor (= 0 (mod match-width 2))
                                      (= 1 (mod result-text-width 2)))
                                 0
                               1))
                          2)
                       (/ match-width 2))))
                 (result-text
                  (format "%s%s%s\n"
                          (let ((left-side
                                 (buffer-substring
                                  (max (save-excursion
                                         (goto-char match-beg)
                                         (line-beginning-position))
                                       (- match-beg margin-width))
                                  match-beg)))
                            (while (and (not (string-empty-p left-side))
                                        (< margin-width
                                           (string-width left-side)))
                              (setq left-side (substring left-side 1)))
                            (concat
                             (make-string
                              (- margin-width (string-width left-side)) ? )
                             left-side))
                          (propertize match-str
                                      'face list-matching-lines-face)
                          (let ((end (match-end 0)))
                            (truncate-string-to-width ; mule-util.el
                             (buffer-substring
                              end
                              (min (line-end-position) (+ end margin-width)))
                             margin-width)))))
            (with-current-buffer eyegrep-buf
              (insert (propertize line-number-index
                                  'face list-matching-lines-prefix-face
                                  'occur-prefix t
                                  'occur-target match-marker)
                      (propertize result-text
                                  'occur-target match-marker))))))
      (let ((summary (format "%s match%s"
                             (if (zerop match-count)
                                 "no"
                               (format "%d" match-count))
                             (if (= match-count 1) "" "es"))))
        (message "Searched %s; %s for \"%s\"" active-buf summary pattern)
        (if (zerop match-count)
            (kill-buffer eyegrep-buf)
          (with-current-buffer eyegrep-buf
            (goto-char (point-min))
            (insert (propertize (format "%s for \"%s\" in buffer: %s\n"
                                        summary pattern active-buf)
                                'face 'underline))
            (setq buffer-read-only t)
            (set-buffer-modified-p nil)
            (occur-mode))
          (display-buffer eyegrep-buf))))))

(provide 'eyegrep)

;;; eyegrep.el ends here.
