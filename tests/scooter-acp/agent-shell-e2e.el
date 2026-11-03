;;; agent-shell-e2e.el --- agent-shell <-> scooter-acp <-> fake Scooter -*- lexical-binding: t -*-

(require 'agent-shell)
(load (getenv "SCOOTER_EL"))

(defun e2e-wait (pred what)
  (let ((deadline (+ (float-time) 20)))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (unless (funcall pred) (error "Timed out waiting for %s" what))))

(defun e2e-text (buf)
  (with-current-buffer buf (buffer-substring-no-properties (point-min) (point-max))))

(defun e2e-has (buf s)
  (string-match-p (regexp-quote s) (e2e-text buf)))

(defun e2e-start (&rest args)
  (let ((default-directory temporary-file-directory))
    (apply #'agent-shell--start :config (my/scooter-make-agent-config) :no-focus t :new-session t args)))

(defun e2e-new-session-prompt ()
  (let ((buf (e2e-start :session-strategy 'new)))
    (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
    (agent-shell-insert :text "hello scooter" :submit t :no-focus t :shell-buffer buf)
    (e2e-wait (lambda () (e2e-has buf "LIVE-ANSWER")) "the streamed answer")
    (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the turn to end")
    (unless (e2e-has buf "shell: ls /workspace") (error "Tool call title missing:\n%s" (e2e-text buf)))))

(defun e2e-load-history-then-push ()
  (let ((buf (e2e-start :session-id "old")))
    (e2e-wait (lambda () (e2e-has buf "HISTORY-ANSWER")) "history replay")
    (unless (e2e-has buf "HISTORY-QUESTION") (error "Replay dropped the user turn:\n%s" (e2e-text buf)))
    (sleep-for 0.5)
    (with-temp-file (getenv "TRIGGER_FILE") (insert "web"))
    (e2e-wait (lambda () (e2e-has buf "WEB-ANSWER")) "the web-started run")
    (unless (e2e-has buf "WEB-QUESTION") (error "Pushed run lost its prompt:\n%s" (e2e-text buf)))
    (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the push to end")))

(defun e2e-links ()
  (let ((buf (e2e-start :session-id "old"))
        opened copied)
    (e2e-wait (lambda () (e2e-has buf "HISTORY-ANSWER")) "history replay")
    (cl-letf (((symbol-function 'completing-read) (lambda (_p cands &rest _) (caar cands)))
              ((symbol-function 'browse-url) (lambda (url &rest _) (setq opened url)))
              ((symbol-function 'kill-new) (lambda (s &rest _) (setq copied s))))
      (with-current-buffer buf (my/scooter-links))
      (e2e-wait (lambda () opened) "my/scooter-links to open a link")
      (with-current-buffer buf (my/scooter-links t))
      (e2e-wait (lambda () copied) "my/scooter-links to copy a link"))
    (unless (equal opened "https://github.com/o/r/pull/7") (error "Opened %S" opened))
    (unless (equal copied opened) (error "Copied %S" copied))
    (sleep-for 1)
    (with-temp-file (getenv "TRIGGER_FILE") (insert "link"))
    (e2e-wait (lambda () (e2e-has buf "jira: jira issue")) "the live link notice")
    (when (e2e-has buf "Unhandled") (error "Link notice fell through:\n%s" (e2e-text buf)))))

(condition-case err
    (progn
      (e2e-new-session-prompt)
      (e2e-load-history-then-push)
      (e2e-links)
      (princ "agent-shell e2e: ok\n")
      (kill-emacs 0))
  (error
   (princ (format "agent-shell e2e: FAIL %s\n" (error-message-string err)))
   (kill-emacs 1)))
