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

  (defun my/scooter-open-in-browser ()
    "Open the current Scooter conversation in the web UI."
    (interactive)
    (let ((id (map-nested-elt (agent-shell--state) '(:session :id))))
      (unless id (user-error "No Scooter session in this buffer"))
      (browse-url (format "%s/?thread=%s" my/scooter-url id))))

  (defun my/scooter-make-agent-config ()
    (agent-shell-make-agent-config
     :identifier 'scooter
     :mode-line-name "Scooter"
     :buffer-name "Scooter"
     :shell-prompt "Scooter> "
     :shell-prompt-regexp "Scooter> "
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
  (global-set-key (kbd "C-c j") #'my/scooter)
''
