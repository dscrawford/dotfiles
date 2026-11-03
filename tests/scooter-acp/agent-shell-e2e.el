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

(defun e2e-web-services ()
  (let* ((buf (e2e-start :session-id "old"))
         (answers nil)
         (browsed nil)
         (listed nil)
         (browse-url-browser-function (lambda (url &rest _) (setq browsed url))))
    (e2e-wait (lambda () (e2e-has buf "HISTORY-ANSWER")) "history replay for web services")
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt candidates &rest _)
                 (seq-find (lambda (c) (string-prefix-p "Vite dev" c)) (mapcar #'car candidates))))
              ((symbol-function 'read-multiple-choice)
               (lambda (_prompt choices &rest _) (assq (pop answers) choices))))
      (dolist (step '(?c ?b ?s))
        (setq answers (list step))
        (with-current-buffer buf (my/scooter-web-services))
        (e2e-wait (lambda () (null answers)) (format "web service action %c" step))))
    (unless (equal (car kill-ring) (concat (getenv "SCOOTER_URL") "/c/old/vite/"))
      (error "URL not copied: %S" (car kill-ring)))
    (unless (equal browsed (car kill-ring)) (error "URL not browsed: %S" browsed))
    (e2e-wait (lambda ()
                (with-current-buffer buf
                  (my/scooter-request "_scooter/web-services/list"
                                      :on-success (lambda (r) (setq listed (append (map-elt r 'services) nil)))))
                (accept-process-output nil 0.2)
                (map-elt (car listed) 'running))
              "vite to be started")
    (unless (e2e-has buf "my/scooter-web-services") (error "No web service notice:\n%s" (e2e-text buf)))))

(condition-case err
    (progn
      (e2e-new-session-prompt)
      (e2e-load-history-then-push)
      (e2e-web-services)
      (princ "agent-shell e2e: ok\n")
      (kill-emacs 0))
  (error
   (princ (format "agent-shell e2e: FAIL %s\n" (error-message-string err)))
   (kill-emacs 1)))
