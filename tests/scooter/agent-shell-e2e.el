;;; agent-shell-e2e.el --- agent-shell <-> scooter acp <-> fake Scooter -*- lexical-binding: t -*-

;; Loads the dotfiles' Scooter config (shared/emacs/scooter.nix) with the
;; pinned agent-shell and scooter-mode, then drives real agent-shell buffers
;; through the real `scooter acp' against tests/scooter/e2e-server.mjs.

(require 'agent-shell)
(load (getenv "SCOOTER_EL"))
(load (expand-file-name "agent-shell-cards-e2e.el" (file-name-directory load-file-name)))
(load (expand-file-name "agent-shell-kanban-e2e.el" (file-name-directory load-file-name)))

;; The fake accepts this cookie; scooter-mode would otherwise ask for one.
(scooter-auth-set-cookie my/scooter-server "good")

(defun e2e-wait (pred what)
  (let ((deadline (+ (float-time) 20)))
    (while (and (not (funcall pred)) (< (float-time) deadline))
      (accept-process-output nil 0.1))
    (unless (funcall pred) (error "Timed out waiting for %s" what))))

(defun e2e-text (buf)
  (with-current-buffer buf (buffer-substring-no-properties (point-min) (point-max))))

(defun e2e-has (buf s)
  ;; Case matters: "ANSWERED" is the reply, "Answered" only the form.
  (let ((case-fold-search nil))
    (string-match-p (regexp-quote s) (e2e-text buf))))

(defun e2e-start (&rest args)
  (let ((default-directory temporary-file-directory))
    (apply #'agent-shell--start :config (scooter-agent-shell-config my/scooter-server)
           :no-focus t :new-session t args)))

(defun e2e-idle (buf what)
  (e2e-wait (lambda () (with-current-buffer buf (not (shell-maker-busy)))) what))

(defconst e2e-png "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

(defun e2e-image-cache-file ()
  (expand-file-name (concat (md5 e2e-png) ".png") (agent-shell-cache-dir "content")))

(defun e2e-config ()
  "The dotfiles wire scooter-mode the way the rest of these tests rely on."
  (unless (file-executable-p (car scooter-acp-command)) (error "Bridge not executable: %S" scooter-acp-command))
  (unless (equal (cdr scooter-acp-command) '("acp")) (error "Bridge arguments: %S" scooter-acp-command))
  (unless (eq scooter-acp-replay-turns 30) (error "Replay cap: %S" scooter-acp-replay-turns))
  (unless (equal (map-elt (scooter-agent-shell-config my/scooter-server) :icon-name) "scooter")
    (error "No Scooter icon on the agent config"))
  (unless (seq-find (lambda (maker) (eq (map-elt (funcall maker) :identifier) 'scooter-home))
                    (if (functionp agent-shell-agent-configs) (funcall agent-shell-agent-configs) agent-shell-agent-configs))
    (error "Scooter is not in the agent picker"))
  (unless (eq (key-binding (kbd "C-c j")) #'my/scooter) (error "C-c j is not my/scooter"))
  (unless (eq (lookup-key (current-global-map) (kbd "C-c J b")) #'scooter-sandbox) (error "C-c J is not scooter-command-map")))

(defun e2e-prompt-with-image (buf)
  (let ((file (expand-file-name "e2e-shot.png" temporary-file-directory)))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert (base64-decode-string e2e-png)))
    (agent-shell-insert :text (format "describe @%s" file) :submit t :no-focus t :shell-buffer buf)
    (e2e-wait (lambda () (e2e-has buf "IMAGE-RECEIVED image/png intact")) "the image prompt to reach Scooter")
    (e2e-idle buf "the image turn to end")))

(defun e2e-new-session-prompt ()
  (let ((buf (e2e-start :session-strategy 'new)))
    (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
    (agent-shell-insert :text "hello scooter" :submit t :no-focus t :shell-buffer buf)
    (e2e-wait (lambda () (e2e-has buf "LIVE-ANSWER")) "the streamed answer")
    (e2e-idle buf "the turn to end")
    (unless (e2e-has buf "shell: ls /workspace") (error "Tool call title missing:\n%s" (e2e-text buf)))
    (e2e-prompt-with-image buf)))

(defun e2e-load-history-then-push ()
  (let ((buf (e2e-start :session-id "old")))
    (e2e-wait (lambda () (e2e-has buf "HISTORY-ANSWER")) "history replay")
    (unless (e2e-has buf "HISTORY-QUESTION") (error "Replay dropped the user turn:\n%s" (e2e-text buf)))
    (e2e-wait (lambda () (string-prefix-p "Scooter Agent @ Fix the login redirect" (buffer-name buf)))
              (format "the buffer to be named after the conversation, not %S" (buffer-name buf)))
    (e2e-wait (lambda () (file-exists-p (e2e-image-cache-file))) "the replayed image")
    (sleep-for 0.5)
    (with-temp-file (getenv "TRIGGER_FILE") (insert "web"))
    (e2e-wait (lambda () (e2e-has buf "WEB-ANSWER")) "the web-started run")
    (unless (e2e-has buf "WEB-QUESTION") (error "Pushed run lost its prompt:\n%s" (e2e-text buf)))
    (when (e2e-has buf "Out of turn") (error "Pushed run arrived out of turn:\n%s" (e2e-text buf)))
    (e2e-idle buf "the push to end")
    (unless (e2e-has buf "scooter-web-services") (error "No web service notice:\n%s" (e2e-text buf)))))

(defun e2e-old-buffer ()
  (seq-find (lambda (b) (equal (map-nested-elt (buffer-local-value 'agent-shell--state b) '(:session :id)) "old"))
            (match-buffers '(derived-mode . agent-shell-mode))))

(defun e2e-sandbox-compact ()
  (let ((buf (e2e-old-buffer))
        (asked nil))
    (with-current-buffer buf
      (unless (eq (key-binding (kbd "C-c C-b")) #'scooter-sandbox) (error "C-c C-b is not scooter-sandbox"))
      (cl-letf (((symbol-function 'completing-read) (lambda (prompt &rest _) (setq asked prompt) "compact"))
                ((symbol-function 'yes-or-no-p) #'always))
        (call-interactively #'scooter-sandbox)
        (e2e-wait (lambda () (e2e-has "*Messages*" "Scooter: compacted 3 turns")) "the compaction result")))
    (unless (string-prefix-p "Fix the login redirect: running" asked) (error "Unexpected sandbox prompt: %s" asked))))

(defun e2e-web-services ()
  (let* ((buf (e2e-old-buffer))
         (browsed nil)
         (browse-url-browser-function (lambda (url &rest _) (setq browsed url))))
    (cl-letf (((symbol-function 'completing-read)
               (lambda (_prompt candidates &rest _)
                 (seq-find (lambda (c) (string-prefix-p "Vite dev" c)) (mapcar #'car candidates)))))
      (dolist (step '(?c ?b ?s))
        (cl-letf (((symbol-function 'read-multiple-choice) (lambda (_prompt choices &rest _) (assq step choices))))
          (with-current-buffer buf (call-interactively #'scooter-web-services)))))
    (unless (equal (car kill-ring) (concat (getenv "SCOOTER_URL") "/c/old/vite/"))
      (error "URL not copied: %S" (car kill-ring)))
    (unless (equal browsed (car kill-ring)) (error "URL not browsed: %S" browsed))
    (let ((vite (seq-find (lambda (s) (equal (alist-get 'name s) "vite"))
                          (scooter-conversation--services my/scooter-server "old"))))
      (unless (eq (alist-get 'running vite) t) (error "vite not started: %S" vite)))))

(defun e2e-links ()
  (let ((buf (e2e-old-buffer))
        opened copied)
    (cl-letf (((symbol-function 'completing-read) (lambda (_p cands &rest _) (caar cands)))
              ((symbol-function 'browse-url) (lambda (url &rest _) (setq opened url)))
              ((symbol-function 'kill-new) (lambda (s &rest _) (setq copied s))))
      (with-current-buffer buf
        (call-interactively #'scooter-links)
        (let ((current-prefix-arg '(4))) (call-interactively #'scooter-links))))
    (unless (equal opened "https://github.com/o/r/pull/7") (error "Opened %S" opened))
    (unless (equal copied opened) (error "Copied %S" copied))
    (with-temp-file (getenv "TRIGGER_FILE") (insert "link"))
    (e2e-wait (lambda () (e2e-has buf "jira: issue")) "the live link notice")))

(defun e2e-picker ()
  "The session picker lists the web UI's conversations, starred first, with no directory."
  (let ((buf (e2e-start :session-strategy 'new))
        choices)
    (e2e-wait (lambda () (map-nested-elt (buffer-local-value 'agent-shell--state buf) '(:session :id))) "session/new")
    (with-current-buffer buf
      (unless (eq agent-shell-session-choices-function #'my/scooter--session-choices)
        (error "Scooter buffers don't use my/scooter--session-choices"))
      (agent-shell--list-sessions
       :state agent-shell--state :cwd "/home/someone/some-project" :buffer buf
       :on-success (lambda (sessions)
                     (setq choices (my/scooter--session-choices
                                    (append '(("New shell" . :new-shell)
                                              ("New Downloads shell" . :downloads-shell)
                                              ("New temp shell" . :temp-shell))
                                            (mapcar (lambda (s) (cons "label" s))
                                                    (agent-shell--sort-sessions-by-recency sessions))))))
       :on-failure (lambda (e _) (error "session/list failed: %S" e))))
    (e2e-wait (lambda () choices) "session/list")
    (let ((tokens (mapcar #'cdr choices))
          (labels (mapcar (lambda (c) (substring-no-properties (car c))) choices)))
      (unless (equal (car choices) '("New Scooter conversation" . :new-shell)) (error "First choice: %S" (car choices)))
      (when (seq-some #'keywordp (cdr tokens)) (error "Directory choices kept: %S" labels))
      (unless (equal (map-elt (cadr tokens) 'sessionId) "pinned") (error "Starred not first: %S" labels))
      (unless (string-match-p "\\`★ Pinned +waiting on you" (cadr labels)) (error "Pinned label: %S" (cadr labels)))
      (unless (seq-some (lambda (l) (string-match-p "Fix the login redirect \\[github\\]" l)) labels)
        (error "Linked sources missing from labels: %S" labels))
      (when (seq-some (lambda (l) (string-match-p "some-project" l)) labels) (error "Directory in labels: %S" labels)))))

(condition-case err
    (progn
      (e2e-config)
      (e2e-picker)
      (e2e-new-session-prompt)
      (e2e-load-history-then-push)
      (e2e-sandbox-compact)
      (e2e-web-services)
      (e2e-links)
      (e2e-cards)
      (e2e-kanban)
      (princ "agent-shell e2e: ok\n")
      (kill-emacs 0))
  (error
   (princ (format "agent-shell e2e: FAIL %s\n" (error-message-string err)))
   (kill-emacs 1)))
