;;; agent-shell-leak-test.el --- process-leak regression tests -*- lexical-binding: t; -*-

;; Run via tests/emacs/run.sh. Loads the elisp extracted from
;; shared/emacs/agent-shell.nix ($AGENT_SHELL_EL) with stubs for the parts
;; of default.el it references. The production code itself stays
;; dynamically bound, as in default.el.

(require 'ert)
(require 'cl-lib)
(require 'map)

(defmacro my/guard (_label &rest body)
  (declare (indent 1))
  `(ignore-errors ,@body))
(defun agent-shell-cwd () default-directory)

(load (or (getenv "AGENT_SHELL_EL")
          (error "AGENT_SHELL_EL not set; run via tests/emacs/run.sh"))
      nil t t)

;; Fake acp feature so the with-eval-after-load advice installs.
(unless (featurep 'acp)
  (defun acp-shutdown (&rest _args) nil)
  (provide 'acp))

(defvar my/test--script-drain
  "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > \"$RUFLO_ARGS_FILE\"\ncat > /dev/null\nexit 0\n")
(defvar my/test--script-hang
  "#!/usr/bin/env bash\nexec sleep 300\n")

(defun my/test--write-script (path content)
  (with-temp-file path (insert content))
  (set-file-modes path #o755)
  path)

(defmacro my/test--with-bin-dir (dir &rest body)
  (declare (indent 1))
  `(let ((,dir (make-temp-file "agent-shell-test" t)))
     (unwind-protect (progn ,@body)
       (delete-directory ,dir t))))

(defmacro my/test--with-recorded-kills (calls timers &rest body)
  "Record `signal-process' as (PID . SIG) into CALLS, `run-at-time' args into TIMERS."
  (declare (indent 2))
  `(let ((,calls nil) (,timers nil))
     (cl-letf (((symbol-function 'signal-process)
                (lambda (pid sig &rest _) (push (cons pid sig) ,calls) 0))
               ((symbol-function 'run-at-time)
                (lambda (&rest args) (push args ,timers) nil)))
       ,@body)))

(defun my/test--cancel-leak-timers ()
  (dolist (tm (copy-sequence timer-list))
    (when (memq (timer--function tm) '(my/ruflo--reap my/acp--kill-group))
      (cancel-timer tm))))

(defun my/test--wait-dead (proc secs)
  (let ((deadline (+ (float-time) secs)))
    (while (and (process-live-p proc) (< (float-time) deadline))
      (accept-process-output nil 0.1)))
  (not (process-live-p proc)))

;;; Wiring

(ert-deftest my/leak-hooks-and-advice-installed ()
  (should (memq #'my/ruflo-register-session agent-shell-mode-hook))
  (should (memq #'my/acp--kill-all-groups kill-emacs-hook))
  (should (advice-member-p #'my/acp-shutdown--kill-group 'acp-shutdown)))

;;; ruflo session save spawn (bug 1)

(ert-deftest my/ruflo-register-pipe-launch-exits ()
  "Pipe stdin + EOF lets a draining ruflo exit; pty launch never did (RUFLO_BUG.md)."
  (dolist (row '(("plain buffer name" "*agent*")
                 ("unicode + spaces in buffer name" "*agent räum 42*")))
    (cl-destructuring-bind (desc buf-name) row
      (ert-info (desc)
        (my/test--with-bin-dir dir
          (my/test--write-script (expand-file-name "ruflo" dir) my/test--script-drain)
          (let* ((args-file (expand-file-name "args" dir))
                 (exec-path (list dir))
                 (process-environment
                  (cons (concat "RUFLO_ARGS_FILE=" args-file) process-environment))
                 (default-directory (file-name-as-directory dir))
                 (project (file-name-nondirectory (directory-file-name dir))))
            (with-current-buffer (generate-new-buffer buf-name)
              (unwind-protect (my/ruflo-register-session)
                (kill-buffer)))
            (let ((proc (get-process "ruflo-register")))
              (should proc)
              (should-not (process-tty-name proc)) ; tripwire: pty revert = leak
              (should-not (process-query-on-exit-flag proc))
              (should (my/test--wait-dead proc 10)))
            (my/test--cancel-leak-timers)
            (with-temp-buffer
              (insert-file-contents args-file)
              (should (equal (buffer-string)
                             (format "session\nsave\n-n\nagent-shell:%s:%s\n"
                                     project buf-name))))))))))

(ert-deftest my/ruflo-register-reaper-kills-hung-process ()
  (my/test--with-bin-dir dir
    (my/test--write-script (expand-file-name "ruflo" dir) my/test--script-hang)
    (let ((exec-path (list dir))
          (default-directory (file-name-as-directory dir)))
      (with-current-buffer (generate-new-buffer "*agent*")
        (unwind-protect (my/ruflo-register-session) (kill-buffer)))
      (let ((proc (get-process "ruflo-register")))
        (unwind-protect
            (progn
              (should (process-live-p proc))
              (let ((tm (cl-find-if
                         (lambda (tm) (eq (timer--function tm) #'my/ruflo--reap))
                         timer-list)))
                (should tm)
                (should (memq proc (timer--args tm))))
              (my/ruflo--reap proc) ; fire now instead of waiting 30 s
              (should (my/test--wait-dead proc 5)))
          (when (process-live-p proc) (delete-process proc))
          (my/test--cancel-leak-timers))))))

(ert-deftest my/ruflo-register-noop-when-ruflo-absent ()
  (my/test--with-bin-dir dir
    (let ((exec-path (list dir))
          (default-directory (file-name-as-directory dir))
          (before (process-list)))
      (with-current-buffer (generate-new-buffer "*agent*")
        (unwind-protect (should-not (my/ruflo-register-session))
          (kill-buffer)))
      (should (equal before (process-list))))))

(ert-deftest my/ruflo-reap-dead-process-is-noop ()
  (let ((proc (make-process :name "t" :command '("true")
                            :connection-type 'pipe :noquery t)))
    (should (my/test--wait-dead proc 5))
    (my/ruflo--reap proc)))

;;; acp-shutdown group TERM (bug 2)

(ert-deftest my/acp-shutdown-kill-group-arg-shapes ()
  "Rows: (desc client). Absent/malformed clients must no-op without signaling."
  (let ((dead (make-process :name "dead" :command '("true")
                            :connection-type 'pipe :noquery t)))
    (should (my/test--wait-dead dead 5))
    (dolist (row `(("no args" :none)
                   ("nil client" nil)
                   ("client missing :process" ((:other . 1)))
                   ("client with dead process" ((:process . ,dead)))))
      (cl-destructuring-bind (desc client) row
        (ert-info (desc)
          (my/test--with-recorded-kills calls timers
            (if (eq client :none)
                (my/acp-shutdown--kill-group)
              (my/acp-shutdown--kill-group :client client))
            (should-not calls)
            (should-not timers)))))))

(ert-deftest my/acp-shutdown-kill-group-terms-group-and-schedules-kill ()
  (let ((proc (make-process :name "acp-sim" :command '("sleep" "60")
                            :connection-type 'pipe :noquery t)))
    (unwind-protect
        (my/test--with-recorded-kills calls timers
          (my/acp-shutdown--kill-group :client `((:process . ,proc)))
          (let ((pgid (- (process-id proc))))
            (should (equal calls `((,pgid . TERM))))
            (should (equal timers `((5 nil my/acp--kill-group ,pgid))))))
      (delete-process proc))))

(ert-deftest my/acp-shutdown-kill-group-nil-pid-does-not-error ()
  "A live client :process with no OS pid must be skipped, not signal an
error: a `:before' advice error aborts `acp-shutdown' itself."
  (let ((proc (make-network-process :name "srv" :server t :service 0
                                    :host "127.0.0.1" :noquery t)))
    (unwind-protect
        (my/test--with-recorded-kills calls timers
          (my/acp-shutdown--kill-group :client `((:process . ,proc)))
          (should-not calls)
          (should-not timers))
      (delete-process proc))))

;;; kill-emacs-hook sweep

(ert-deftest my/acp-kill-all-groups-matcher ()
  "Rows: (desc command expected-signaled). Matcher keys on argv[0] only,
anchored on the trailing path component."
  (my/test--with-bin-dir dir
    (let ((fake-acp (my/test--write-script
                     (expand-file-name "claude-agent-acp" dir)
                     my/test--script-hang)))
      (dolist (row `(("argv0 ends in /claude-agent-acp" (,fake-acp) t)
                     ("shell-wrapped launch escapes matcher (documented gap)"
                      ("/bin/sh" "-c" "sleep 60") nil)
                     ("unrelated process" ("sleep" "60") nil)))
        (cl-destructuring-bind (desc command expected) row
          (ert-info (desc)
            (let ((proc (make-process :name "row" :command command
                                      :connection-type 'pipe :noquery t)))
              (unwind-protect
                  (my/test--with-recorded-kills calls _timers
                    (my/acp--kill-all-groups)
                    (should (eq (and (assoc (- (process-id proc)) calls) t)
                                expected)))
                (delete-process proc))))))
      ;; pid-less process in process-list: skipped without error
      (let ((net (make-network-process :name "srv" :server t :service 0
                                       :host "127.0.0.1" :noquery t)))
        (unwind-protect
            (my/test--with-recorded-kills calls _timers
              (my/acp--kill-all-groups)
              (should-not calls))
          (delete-process net))))))

;;; acp.el contract (skips unless acp.el findable; set ACP_DIR to enable)

(ert-deftest my/acp-contract-shutdown-shape ()
  "The advice assumes `acp-shutdown' takes `&key client' and the client
stores its proc under :process. Trips on an acp.el bump that changes either."
  (when-let* ((dir (getenv "ACP_DIR")))
    (add-to-list 'load-path dir))
  (skip-unless (locate-library "acp"))
  (require 'find-func)
  (let ((src (with-temp-buffer
               (insert-file-contents (find-library-name "acp"))
               (buffer-string))))
    (should (string-match-p "(cl-defun acp-shutdown (&key client" src))
    (should (string-match-p "(cons :process" src))))

(provide 'agent-shell-leak-test)
;;; agent-shell-leak-test.el ends here
