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

(defconst e2e-png "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

(defun e2e-image-cache-file ()
  (expand-file-name (concat (md5 e2e-png) ".png") (agent-shell-cache-dir "content")))

(defun e2e-prompt-with-image (buf)
  (let ((file (expand-file-name "e2e-shot.png" temporary-file-directory)))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert (base64-decode-string e2e-png)))
    (agent-shell-insert :text (format "describe @%s" file) :submit t :no-focus t :shell-buffer buf)
    (e2e-wait (lambda () (e2e-has buf "IMAGE-RECEIVED image/png intact")) "the image prompt to reach Scooter")
    (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the image turn to end")))

(defun e2e-new-session-prompt ()
  (let ((buf (e2e-start :session-strategy 'new)))
    (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
    (agent-shell-insert :text "hello scooter" :submit t :no-focus t :shell-buffer buf)
    (e2e-wait (lambda () (e2e-has buf "LIVE-ANSWER")) "the streamed answer")
    (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the turn to end")
    (unless (e2e-has buf "shell: ls /workspace") (error "Tool call title missing:\n%s" (e2e-text buf)))
    (e2e-prompt-with-image buf)))

(defun e2e-load-history-then-push ()
  (let ((buf (e2e-start :session-id "old")))
    (e2e-wait (lambda () (e2e-has buf "HISTORY-ANSWER")) "history replay")
    (unless (e2e-has buf "HISTORY-QUESTION") (error "Replay dropped the user turn:\n%s" (e2e-text buf)))
    (e2e-wait (lambda () (file-exists-p (e2e-image-cache-file))) "the replayed image")
    (sleep-for 0.5)
    (with-temp-file (getenv "TRIGGER_FILE") (insert "web"))
    (e2e-wait (lambda () (e2e-has buf "WEB-ANSWER")) "the web-started run")
    (unless (e2e-has buf "WEB-QUESTION") (error "Pushed run lost its prompt:\n%s" (e2e-text buf)))
    (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) "the push to end")))

(condition-case err
    (progn
      (e2e-new-session-prompt)
      (e2e-load-history-then-push)
      (princ "agent-shell e2e: ok\n")
      (kill-emacs 0))
  (error
   (princ (format "agent-shell e2e: FAIL %s\n" (error-message-string err)))
   (kill-emacs 1)))
