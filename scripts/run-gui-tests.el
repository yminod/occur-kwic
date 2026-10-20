;;; run-gui-tests.el --- Run redisplay tests in a fresh GUI Emacs -*- lexical-binding: t; -*-

;; Run with: emacs -Q -l scripts/run-gui-tests.el
;; This runner exits its Emacs process when the tests finish.

(when (or noninteractive (not (display-graphic-p)))
  (error "Use a fresh GUI Emacs: emacs -Q -l scripts/run-gui-tests.el"))

(require 'ert)

(defvar occur-kwic-gui-test-log-file
  (or (getenv "OCCUR_KWIC_GUI_TEST_LOG")
      (expand-file-name "occur-kwic-gui-tests.log" temporary-file-directory))
  "File receiving the GUI test log before this Emacs process exits.")

(defun occur-kwic-gui-test--exit (status)
  "Save the test log and exit this Emacs with STATUS."
  (unwind-protect
      (with-current-buffer (get-buffer-create "*Messages*")
        (write-region (point-min) (point-max) occur-kwic-gui-test-log-file nil 'silent))
    (kill-emacs status)))

(defun occur-kwic-gui-test--run (root)
  "Load tests from ROOT, run them after GUI startup, and exit with a log."
  (let ((status 2)
        (debug-on-error nil)
        (ert-debug-on-error nil)
        (message-log-max t))
    (unwind-protect
        (condition-case err
            (progn
              (add-to-list 'load-path root)
              (dolist (name '("occur-kwic-tests.el" "occur-kwic-gui-tests.el"))
                (load (expand-file-name name (expand-file-name "test" root)) nil t t))
              (message "%s; %s" (emacs-version) system-configuration)
              (let ((stats (ert-run-tests-batch "^occur-kwic-gui-test-")))
                (setq status (if (and (zerop (ert-stats-completed-unexpected stats))
                                      (zerop (ert-stats-skipped stats)))
                                 0 1))))
          (error (message "GUI test runner error: %S" err)))
      (occur-kwic-gui-test--exit status))))

;; Allow startup to finish and the frame to be mapped before testing redisplay.
(run-at-time 0.2 nil #'occur-kwic-gui-test--run
             (expand-file-name ".." (file-name-directory load-file-name)))
(run-at-time 30 nil
             (lambda ()
               (message "GUI tests timed out")
               (occur-kwic-gui-test--exit 2)))

;;; run-gui-tests.el ends here
