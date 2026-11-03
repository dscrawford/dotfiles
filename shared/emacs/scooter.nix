# shared/emacs/scooter.nix
# Scooter conversations as an agent-shell agent, through pkgs/scooter-acp.
# Settings come from my.scooter (shared/home/scooter.nix).
{ pkgs, config, ... }:

let
  cfg = config.my.scooter;
  bridge = pkgs.callPackage ../../pkgs/scooter-acp { };
in
''
  (defvar my/scooter-url (or (getenv "SCOOTER_URL") ${builtins.toJSON cfg.url}))
  (defvar my/scooter-cookie-file ${builtins.toJSON cfg.cookieFile})
  (defvar my/scooter-acp-command "${bridge}/bin/scooter-acp")

  (defun my/scooter-set-cookie (cookie)
    "Save the oauth2-proxy session COOKIE copied from the browser's devtools."
    (interactive (list (read-passwd "Scooter _oauth2_proxy cookie: ")))
    (make-directory (file-name-directory my/scooter-cookie-file) t)
    (with-file-modes #o600
      (with-temp-file my/scooter-cookie-file
        (insert (string-trim cookie) "\n")))
    (set-file-modes my/scooter-cookie-file #o600)
    (message "Saved Scooter cookie to %s" my/scooter-cookie-file))

  (cl-defun my/scooter-request (method &key params on-success)
    "Send extension METHOD to this buffer's scooter-acp with PARAMS plus sessionId.
  ON-SUCCESS gets the decoded result."
    (let ((state (agent-shell--state)))
      (unless (eq (map-nested-elt state '(:agent-config :identifier)) 'scooter)
        (user-error "Not a Scooter agent-shell buffer"))
      (acp-send-request
       :client (map-elt state :client)
       :request `((:method . ,method)
                  (:params . ((sessionId . ,(map-nested-elt state '(:session :id)))
                              ,@params)))
       :buffer (current-buffer)
       :on-success (or on-success #'ignore)
       :on-failure (lambda (acp-error _raw)
                     (message "Scooter %s failed: %s" method (map-elt acp-error 'message))))))

  (defun my/scooter-open-in-browser ()
    "Open the current Scooter conversation in the web UI."
    (interactive)
    (let ((id (map-nested-elt (agent-shell--state) '(:session :id))))
      (unless id (user-error "No Scooter session in this buffer"))
      (browse-url (format "%s/?thread=%s" my/scooter-url id))))

  (defun my/scooter--web-service-candidate (service)
    (cons (format "%-24s %-8s %s"
                  (map-elt service 'displayName)
                  (if (map-elt service 'running) "running" "stopped")
                  (map-elt service 'url))
          service))

  (defun my/scooter-web-service-act (service)
    "Browse, copy, start or stop SERVICE from _scooter/web-services/list."
    (let* ((name (map-elt service 'name))
           (url (map-elt service 'url))
           (running (map-elt service 'running))
           (toggle (if running "stop" "start"))
           (choice (car (read-multiple-choice
                         (format "%s (%s)" (map-elt service 'displayName) url)
                         `((?b "browse" "open in the browser")
                           (?c "copy" "copy the URL to the kill ring")
                           (?s ,toggle ,(format "%s the service" toggle)))))))
      (pcase choice
        (?b (browse-url url))
        (?c (kill-new url) (message "Copied %s" url))
        (?s (my/scooter-request (format "_scooter/web-services/%s" toggle)
                                :params `((name . ,name))
                                :on-success (apply-partially #'message "Scooter: %s %s requested" toggle name))))))

  (defun my/scooter-web-services ()
    "Pick a web service of this Scooter conversation to open, copy, start or stop."
    (interactive)
    (my/scooter-request
     "_scooter/web-services/list"
     :on-success
     (lambda (result)
       (let ((services (append (map-elt result 'services) nil)))
         (if services
             (run-at-time 0 nil #'my/scooter--web-services-pick (current-buffer) services)
           (message "This Scooter conversation declares no web services"))))))

  (defun my/scooter--web-services-pick (buffer services)
    (with-current-buffer buffer
      (let* ((candidates (mapcar #'my/scooter--web-service-candidate services))
             (pick (completing-read "Web service: " candidates nil t)))
        (my/scooter-web-service-act (cdr (assoc pick candidates))))))
  (defun my/scooter--sandbox-done (action result)
    (let-alist result
      (message "Scooter: %s"
               (pcase action
                 ("resize" (format "sandbox size %s applies on the next restart" .size))
                 ("compact" (if .compacted (format "compacted %s turns" .summarizedTurns)
                              (or .reason "nothing to compact")))
                 (_ (format "%s done" action))))))

  (defun my/scooter--sandbox-call (action &optional params)
    (my/scooter-request (concat "_scooter/sandbox/" action)
                        :params params
                        :on-success (apply-partially #'my/scooter--sandbox-done action)))

  (defun my/scooter--sandbox-describe (status)
    (let-alist status
      (format "%s: %s%s, %s, %s%s"
              (or .conversation.title "Scooter")
              (or .conversation.status "unknown")
              (if .ready.ready " (ready)" "")
              (or .conversation.visibility "shared")
              (if .resources.resources.limits.cpu
                  (format "%s CPU, %s" .resources.resources.limits.cpu .resources.resources.limits.memory)
                "default size")
              (if .resources.pendingRestart ", restart pending" ""))))

  (defun my/scooter--sandbox-actions (status)
    (let-alist status
      (delq nil (list (and .sizes.sizes "resize")
                      (if (equal .conversation.status "running") "suspend" "resume")
                      "restart" "compact" "rename"
                      (if .conversation.starred "unstar" "star")
                      (if (equal .conversation.visibility "private") "make shared" "make private")))))

  (defun my/scooter--sandbox-run (choice status)
    (let-alist status
      (pcase choice
        ("resize"
         (my/scooter--sandbox-call
          "resize" `((size . ,(completing-read "Sandbox size: "
                                               (mapcar (lambda (s) (symbol-name (car s))) .sizes.sizes)
                                               nil t nil nil .sizes.default)))))
        ((or "suspend" "resume") (my/scooter--sandbox-call choice))
        ("restart"
         (when (yes-or-no-p "Restart the sandbox? Processes running in it are lost. ")
           (my/scooter--sandbox-call "restart")))
        ("compact"
         (when (yes-or-no-p "Compact the conversation into a summary? ")
           (my/scooter--sandbox-call "compact")))
        ("rename"
         (my/scooter--sandbox-call "rename" `((title . ,(read-string "Title: " .conversation.title)))))
        ("star" (my/scooter--sandbox-call "star" '((starred . t))))
        ("unstar" (my/scooter--sandbox-call "star" '((starred . :false))))
        ("make shared"
         (when (yes-or-no-p "Make this private conversation shared? What it fetched while private becomes visible. ")
           (my/scooter--sandbox-call "visibility" '((visibility . "shared")))))
        ("make private" (my/scooter--sandbox-call "visibility" '((visibility . "private")))))))

  (defun my/scooter--sandbox-menu (buffer status)
    (with-current-buffer buffer
      (my/scooter--sandbox-run
       (completing-read (concat (my/scooter--sandbox-describe status) " > ")
                        (my/scooter--sandbox-actions status) nil t)
       status)))

  (defun my/scooter--sandbox-menu-later (buffer status)
    (run-at-time 0 nil #'my/scooter--sandbox-menu buffer status))

  (defun my/scooter-sandbox ()
    "Show this Scooter conversation's sandbox and pick an action for it."
    (interactive)
    (my/scooter-request "_scooter/sandbox/status"
                        :on-success (apply-partially #'my/scooter--sandbox-menu-later (current-buffer))))

  (defun my/scooter-make-agent-config ()
    (agent-shell-make-agent-config
     :identifier 'scooter
     :mode-line-name "Scooter"
     :buffer-name "Scooter"
     :shell-prompt "Scooter> "
     :shell-prompt-regexp "Scooter> "
     :notification-handler #'my/scooter--on-notification
     :client-maker
     (lambda (buffer)
       (agent-shell--make-acp-client
        :command my/scooter-acp-command
        :environment-variables (list (concat "SCOOTER_URL=" my/scooter-url)
                                     (concat "SCOOTER_COOKIE_FILE=" my/scooter-cookie-file))
        :context-buffer buffer))))

  (defun my/scooter ()
    "Open an agent-shell on Scooter, picking an existing conversation or a new one."
    (interactive)
    (when (string-empty-p my/scooter-url)
      (user-error "Set my.scooter.url in the dotfiles, or SCOOTER_URL"))
    (unless (file-exists-p my/scooter-cookie-file)
      (call-interactively #'my/scooter-set-cookie))
    (agent-shell--dwim :config (my/scooter-make-agent-config) :new-shell t))

  (defun my/scooter--replay-full-history ()
    "Show loaded Scooter conversations in full; scooter-acp caps the replay."
    (when (eq (map-nested-elt (agent-shell--state) '(:agent-config :identifier)) 'scooter)
      (setq-local agent-shell-session-restore-verbosity 'full)))
  (add-hook 'agent-shell-mode-hook #'my/scooter--replay-full-history)

  (defvar my/scooter--base-agent-configs nil)
  (defun my/scooter--agent-configs ()
    (append (if (functionp my/scooter--base-agent-configs)
                (funcall my/scooter--base-agent-configs)
              my/scooter--base-agent-configs)
            (list #'my/scooter-make-agent-config)))

  (with-eval-after-load 'agent-shell
    (my/guard "scooter-agent"
      (unless (or (string-empty-p my/scooter-url)
                  (eq agent-shell-agent-configs #'my/scooter--agent-configs))
        (setq my/scooter--base-agent-configs agent-shell-agent-configs
              agent-shell-agent-configs #'my/scooter--agent-configs))))
  (with-eval-after-load 'agent-shell
    (define-key agent-shell-mode-map (kbd "C-c C-b") #'my/scooter-sandbox))
  (global-set-key (kbd "C-c j") #'my/scooter)

  (defun my/scooter--link-line (link)
    (format "%s: %s" (map-elt link 'source) (map-elt link 'label)))

  (defun my/scooter--pick-link (links copy)
    (let* ((candidates (mapcar (lambda (l) (cons (my/scooter--link-line l) l))
                               (seq-filter (lambda (l) (map-elt l 'url)) links)))
           (url (and candidates
                     (map-elt (cdr (assoc (completing-read (if copy "Copy Scooter link: " "Open Scooter link: ")
                                                           candidates nil t)
                                          candidates))
                              'url))))
      (cond ((not url) (message "No links on this Scooter conversation"))
            (copy (kill-new url) (message "Copied %s" url))
            (t (browse-url url)))))

  (defun my/scooter--links-received (copy result)
    (run-at-time 0 nil #'my/scooter--pick-link (append (map-elt result 'links) nil) copy))

  (defun my/scooter-links (&optional copy)
    "Open a resource linked to this Scooter conversation.
  With prefix arg COPY, copy its URL instead."
    (interactive "P")
    (my/scooter-request "_scooter/links"
                        :on-success (apply-partially #'my/scooter--links-received copy)))

  (defvar-local my/scooter--link-notices 0)
  (defun my/scooter--on-notification (args)
    "Show scooter-acp's _scooter/links_changed as a notice in the shell buffer."
    (let ((state (map-elt args :state))
          (notification (map-elt args :acp-notification)))
      (when (equal (map-elt notification 'method) "_scooter/links_changed")
        (with-current-buffer (map-elt state :buffer)
          (agent-shell--update-fragment
           :state state
           :block-id (format "scooter-links-%d" (cl-incf my/scooter--link-notices))
           :label-left (propertize "Linked" 'font-lock-face 'agent-shell-section-heading)
           :body (mapconcat (lambda (l) (format "- [%s](%s)" (my/scooter--link-line l) (or (map-elt l 'url) "")))
                            (map-nested-elt notification '(params added)) "\n")
           :expanded t
           :above-last-prompt (not (shell-maker-busy))))
        t)))
  ${import ./scooter-cards.nix { }}
''
