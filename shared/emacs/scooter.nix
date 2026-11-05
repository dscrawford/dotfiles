# shared/emacs/scooter.nix
# Scooter conversations in agent-shell, through scooter-mode
# (github.com/chadac-me/scooter-mode, pinned in scooter-mode.nix). Settings come
# from my.scooter (shared/home/scooter.nix).
{ pkgs, config, ... }:

let
  cfg = config.my.scooter;
  scooterMode = import ./scooter-mode.nix { inherit pkgs; };
in
''
  (require 'scooter)
  (require 'scooter-conversation)
  (autoload 'scooter-find-file "scooter-tramp" nil t)
  (with-eval-after-load 'tramp
    (my/guard "scooter-tramp"
      (require 'scooter-tramp)
      (scooter-tramp-enable)))

  (defvar my/scooter-url (or (getenv "SCOOTER_URL") ${builtins.toJSON cfg.url}))
  (defvar my/scooter-server 'home
    "The `scooter-servers' entry for my.scooter.url.")

  (setq scooter-acp-command '("${scooterMode.bridge}/bin/scooter" "acp")
        ;; Long conversations load their last 30 turns, in full.
        scooter-acp-replay-turns 30)
  (unless (string-empty-p my/scooter-url)
    (setq scooter-servers `((,my/scooter-server :url ,my/scooter-url :auth cookie))
          scooter-default-server my/scooter-server))

  (defun my/scooter-buffer-p ()
    "Non-nil in an agent-shell buffer on a Scooter server."
    (when-let* ((state (bound-and-true-p agent-shell--state))
                (id (map-nested-elt state '(:agent-config :identifier))))
      (string-prefix-p "scooter-" (symbol-name id))))

  ;; The bridge we wrote before scooter-mode kept the cookie in a file;
  ;; scooter-mode keeps it in auth-source. Move it over on first use.
  (defvar my/scooter-old-cookie-file
    (expand-file-name "scooter/cookie" (or (getenv "XDG_CONFIG_HOME") "~/.config")))

  (defun my/scooter--import-cookie (&rest _)
    "Save the old bridge's cookie file to auth-source, once."
    (advice-remove 'scooter-auth-headers #'my/scooter--import-cookie)
    (when (and scooter-servers (file-readable-p my/scooter-old-cookie-file))
      (let ((cookie (string-trim (with-temp-buffer
                                   (insert-file-contents my/scooter-old-cookie-file)
                                   (buffer-string)))))
        (unless (string-empty-p cookie)
          (scooter-auth-set-cookie my/scooter-server cookie)))
      (rename-file my/scooter-old-cookie-file (concat my/scooter-old-cookie-file ".imported") t)))
  (advice-add 'scooter-auth-headers :before #'my/scooter--import-cookie)

  ;; agent-shell fetches :icon-name from LobeHub or an https URL. Scooter's mark
  ;; is the 🛴 emoji, drawn as a one-colour silhouette (Noto Emoji, OFL) to sit
  ;; with LobeHub's monochrome icons: white on dark themes, black on light ones.
  (defvar my/scooter-icons
    '((dark . "${./icons/scooter-dark.png}")
      (light . "${./icons/scooter-light.png}")))

  (defun my/scooter--fetch-icon (orig icon-name)
    "Serve the bundled Scooter icon for ICON-NAME \"scooter\"; else call ORIG."
    (if (equal icon-name "scooter")
        (alist-get (if (eq (frame-parameter nil 'background-mode) 'light) 'light 'dark)
                   my/scooter-icons)
      (funcall orig icon-name)))
  (advice-add 'agent-shell--fetch-agent-icon :around #'my/scooter--fetch-icon)

  (defun my/scooter--with-icon (config)
    "Give scooter-mode's agent CONFIG our icon."
    (cons (cons :icon-name "scooter") config))
  (advice-add 'scooter-agent-shell-config :filter-return #'my/scooter--with-icon)

  (defun my/scooter ()
    "Open an agent-shell on Scooter, picking an existing conversation or a new one."
    (interactive)
    (unless scooter-servers
      (user-error "Set my.scooter.url in the dotfiles, or SCOOTER_URL"))
    (agent-shell--dwim :config (scooter-agent-shell-config my/scooter-server) :new-shell t))

  (defun my/scooter--session-status (state)
    "The web UI's status dot for a conversation in STATE, as text."
    (pcase state
      ("awaiting" (propertize "waiting on you" 'face 'warning))
      ("running" (propertize "working" 'face 'success))
      ("idle" (propertize "idle" 'face 'shadow))
      ("failed" (propertize "failed" 'face 'error))
      ("suspended" (propertize state 'face 'shadow))
      (_ "")))

  (defun my/scooter--session-meta (session key)
    (map-nested-elt session (list '_meta 'scooter key)))

  (defun my/scooter--session-starred-p (session)
    (eq t (my/scooter--session-meta session 'starred)))

  (defun my/scooter--session-label (session)
    "SESSION's title, followed by the services it links to."
    (let ((sources (append (my/scooter--session-meta session 'sources) nil)))
      (concat (agent-shell--session-title session)
              (if sources (format " [%s]" (string-join sources ", ")) ""))))

  (defun my/scooter--session-choices (choices)
    "Offer the conversations in the web UI's sidebar, in its order.
  Starred first, then most recently active, labelled with the star, title,
  status and date. Scooter conversations don't live in a local directory,
  so the directory column and the Downloads/temp shell choices are dropped."
    (let* ((sessions (seq-filter (lambda (c) (consp (cdr c))) choices))
           (sessions (append (seq-filter (lambda (c) (my/scooter--session-starred-p (cdr c))) sessions)
                             (seq-remove (lambda (c) (my/scooter--session-starred-p (cdr c))) sessions)))
           (title-width (apply #'max 10 (mapcar (lambda (c) (length (my/scooter--session-label (cdr c))))
                                                sessions))))
      (append
       (delq nil
             (mapcar (lambda (c)
                       (pcase (cdr c)
                         (:new-shell (cons "New Scooter conversation" :new-shell))
                         (:other-shell c)))
                     choices))
       (mapcar
        (lambda (c)
          (let ((session (cdr c)))
            (cons (concat
                   (if (my/scooter--session-starred-p session) (propertize "★ " 'face 'warning) "  ")
                   (propertize (string-pad (my/scooter--session-label session) (1+ title-width))
                               'face 'agent-shell-session-title)
                   (string-pad (my/scooter--session-status (my/scooter--session-meta session 'state)) 15)
                   (propertize (agent-shell--format-session-date
                                (or (map-elt session 'updatedAt) ""))
                               'face 'agent-shell-session-date))
                  session)))
        sessions))))

  (defun my/scooter--conversation-name ()
    "This Scooter buffer's conversation title, or nil."
    (when-let* (((my/scooter-buffer-p))
                (title (map-nested-elt (agent-shell--state) '(:session :title)))
                (title (string-trim (car (split-string title "\n"))))
                ((not (string-empty-p title))))
      (truncate-string-to-width title 60 nil nil "…")))

  (defun my/scooter--project-name (orig)
    "Show the conversation, not the local project, in Scooter headers."
    (or (ignore-errors (my/scooter--conversation-name)) (funcall orig)))
  (advice-add 'agent-shell--project-name :around #'my/scooter--project-name)

  (defun my/scooter--name-buffer (_event)
    "Name the buffer \"Scooter Agent @ <title>\", the prefix agent-shell-workspace
  parses for the agent and the rest it shows in its sidebar. scooter-mode's own
  retitle leaves a buffer renamed this way alone."
    (when-let* ((name (my/scooter--conversation-name)))
      (shell-maker-set-buffer-name
       (current-buffer)
       (generate-new-buffer-name (agent-shell--format-buffer-name "Scooter" name) (buffer-name)))
      (agent-shell--update-header-and-mode-line)))

  (defun my/scooter--setup-buffer ()
    "Pick conversations as the web UI lists them, replay them in full (the
  bridge already caps the replay), and name the buffer after the conversation."
    (when (my/scooter-buffer-p)
      (setq-local agent-shell-session-choices-function #'my/scooter--session-choices)
      (setq-local agent-shell-session-restore-verbosity 'full)
      (agent-shell-subscribe-to :shell-buffer (current-buffer)
                                :event 'session-title-changed
                                :on-event #'my/scooter--name-buffer)))
  (add-hook 'agent-shell-mode-hook #'my/scooter--setup-buffer)

  (with-eval-after-load 'agent-shell
    (my/guard "scooter-agent"
      ;; One agent-shell agent per server, listed in the agent picker (C-c s).
      (when scooter-servers (scooter-agent-shell-register)))
    (define-key agent-shell-mode-map (kbd "C-c C-b") #'scooter-sandbox))
  (global-set-key (kbd "C-c j") #'my/scooter)
  (global-set-key (kbd "C-c J") scooter-command-map)
''
