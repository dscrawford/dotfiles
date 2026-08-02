# shared/emacs/agent-shell.nix
# copilot, claude-code-ide, and agent-shell elisp.
# Exports two ordered pieces assembled in order by emacs.nix.
{ pkgs, ... }:

{
  copilotCcide =
    ''
      (my/guard "copilot"
        (setq copilot-node-executable "${pkgs.nodejs}/bin/node")
        (require 'copilot)
        (global-set-key (kbd "C-c p") 'copilot-mode)
        (with-eval-after-load 'copilot
          (define-key copilot-completion-map (kbd "TAB") 'copilot-accept-completion)
          (define-key copilot-completion-map (kbd "<tab>") 'copilot-accept-completion)))

      ;; No my/guard here: use-package's :catch defaults to on, so it already
      ;; demotes errors in its own body to a warning.
      (use-package claude-code-ide
        :bind ("C-c a" . claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'eat)
        :config
        (claude-code-ide-emacs-tools-setup))
    '';

  agentShell =
    ''
      ;; Only the require can signal here — the setq forms below set variables
      ;; whether or not the package loaded, and defcustom won't clobber them.
      (my/guard "agent-shell" (require 'agent-shell))
      (global-set-key (kbd "C-c s") 'agent-shell)
      ;; Always prompt for session on start so we can resume from another session
      (setq agent-shell-session-strategy 'prompt)
      ;; Centralize agent-shell data in ~/.emacs.d/agent-shell/<project>/
      ;; instead of per-project .agent-shell/ so transcripts survive repo
      ;; cleanups and are easy to search across all projects.
      (setq agent-shell-dot-subdir-function
            (lambda (subdir)
              (let ((project (file-name-nondirectory
                              (directory-file-name (agent-shell-cwd)))))
                (expand-file-name
                 (concat "agent-shell/" project "/" subdir "/")
                 user-emacs-directory))))
      ;; Point agent-shell to the nix-built claude-agent-acp binary
      (setq agent-shell-anthropic-claude-acp-command
            '("${pkgs.callPackage ../../pkgs/claude-agent-acp {}}/bin/claude-agent-acp"))
      ;; Default to Claude so agent selection prompt is skipped
      (setq agent-shell-preferred-agent-config 'anthropic-claude)
      ;; Show color-coded context window usage in the header
      (setq agent-shell-show-context-usage-indicator t)
      ;; Agent sidebar: agents grouped by project with status, session titles,
      ;; and tiling. C-c S toggles it as a plain side window in the current
      ;; frame. Deliberately NOT `agent-shell-workspace-toggle', which spawns
      ;; an "Agents" tab, deletes other windows for its own layout, and turns
      ;; on buffer isolation -- too much ceremony alongside per-project tabs.
      ;; That command is still there if the full workspace is ever wanted.
      ;;
      ;; Bound globally next to C-c s: the package's own docs bind via
      ;; `agent-shell-command-map', which agent-shell has never defined, and
      ;; C-c w is taken by windresize.
      (my/guard "agent-shell-workspace" (require 'agent-shell-workspace))
      (global-set-key (kbd "C-c S") 'agent-shell-workspace-sidebar-toggle)
      ;; MCP servers passed to claude via ACP. agent-shell sessions do NOT read
      ;; ~/.claude/.mcp.json or `claude mcp` user scope — this list is the only
      ;; source, so keep it in sync with shared/home/mcp-servers.nix.
      (setq agent-shell-mcp-servers
            '(((name . "ruflo")
               (command . "ruflo")
               (args . ("mcp" "start")))
              ((name . "emacs-mcp")
               (command . "npx")
               (args . ("-y" "@keegancsmith/emacs-mcp-server")))
              ;; Free multi-engine web search for the deep-research skill.
              ;; Version pinned so npx serves it from cache instead of
              ;; re-checking the registry on every session start.
              ((name . "web-search")
               (command . "npx")
               (args . ("-y" "open-websearch@1.2.0"))
               (env . (((name . "MODE") (value . "stdio"))
                       ((name . "DEFAULT_SEARCH_ENGINE") (value . "duckduckgo"))
                       ((name . "ALLOWED_SEARCH_ENGINES") (value . "duckduckgo,bing,brave,startpage")))))))
      ;; Register agent-shell sessions with ruflo for orchestration
      (defun my/ruflo-register-session ()
        "Register the current agent-shell session with ruflo for coordination."
        (when (executable-find "ruflo")
          (let* ((cwd (agent-shell-cwd))
                 (project (file-name-nondirectory (directory-file-name cwd)))
                 (buf-name (buffer-name)))
            (start-process "ruflo-register" nil "ruflo" "session" "save"
                           "-n" (format "agent-shell:%s:%s" project buf-name)))))
      (add-hook 'agent-shell-mode-hook #'my/ruflo-register-session)
      ;; Clipboard image support for agent-shell (not included upstream)
      ;; Checks MIME types first so text clipboard falls through to yank
      ;; Guarded inside with-eval-after-load, not around it: this body reaches
      ;; into agent-shell-mode-map and three private upstream functions, so it
      ;; is the likeliest form here to break on an upstream bump. The guard sits
      ;; inside so it covers both the inline case (agent-shell already required
      ;; above) and the deferred case (that require failed and agent-shell loads
      ;; later). Without it a rename upstream would take out every section that
      ;; follows this one in default.el.
      (with-eval-after-load 'agent-shell
        (my/guard "agent-shell-config"
          ;; Rebind cycle-session-mode from C-<tab> (conflicts with Emacs) to C-M-<tab>
          (keymap-set agent-shell-mode-map "C-M-<tab>" #'agent-shell-cycle-session-mode)
          (keymap-unset agent-shell-mode-map "C-<tab>")
          ;; ACP model-switch shim (C-c C-v). claude-agent-acp implements
          ;; session/set_config_option {configId:"model"} but not session/set_model
          ;; (rejected with -32601, which left model switches hanging). Upstream
          ;; agent-shell only sends set_config_option when a "model"-category config
          ;; option is present in session state; when it's absent it falls back to
          ;; the rejected set_model. Current pins do advertise the option, so this
          ;; advice normally defers to upstream -- it reroutes only when the option
          ;; is missing from state.
          (defun my/agent-shell-set-model-via-config-option (orig-fn &rest args)
            (if (agent-shell--config-option-by-category (agent-shell--state) "model")
                (apply orig-fn args)
              (let ((model-id (plist-get args :model-id))
                    (on-success (plist-get args :on-success))
                    (on-failure (plist-get args :on-failure)))
                (agent-shell--set-session-config-option
                 :config-id "model"
                 :value model-id
                 :on-success (lambda ()
                               (map-put! (map-elt (agent-shell--state) :session)
                                         :model-id model-id)
                               (message "Model: %s" model-id)
                               (when on-success (funcall on-success)))
                 ;; Only method-not-found means "agent wants set_model instead"
                 ;; (e.g. a non-Claude agent): retry via the upstream path (orig-fn
                 ;; is the un-advised function, so no loop). Other errors (invalid
                 ;; model, dead session) surface instead of being re-sent. acp.el
                 ;; runs this callback in the shell buffer, so buffer-local state
                 ;; is intact.
                 :on-failure (lambda (acp-error raw-message)
                               (cond ((equal -32601 (map-elt acp-error 'code))
                                      (apply orig-fn args))
                                     (on-failure
                                      (funcall on-failure acp-error raw-message))
                                     (t
                                      (message "Failed to change model: %s" acp-error))))))))
          (advice-add 'agent-shell--config-option-set-model-id :around
                      #'my/agent-shell-set-model-via-config-option)
          ;; Wayland (Linux): wl-paste
          (when (executable-find "wl-paste")
            (push (list (cons :command "wl-paste")
                        (cons :save (lambda (file-path)
                                      (let ((types (with-temp-buffer
                                                     (call-process "wl-paste" nil t nil "--list-types")
                                                     (buffer-string))))
                                        (unless (string-match-p "image/png" types)
                                          (error "No image in clipboard"))
                                        (let ((exit-code (call-process "wl-paste" nil `(:file ,file-path) nil
                                                                        "-t" "image/png")))
                                          (unless (zerop exit-code)
                                            (error "wl-paste failed with exit code %d" exit-code)))))))
                  agent-shell-clipboard-image-handlers))
          ;; macOS: pngpaste
          (when (executable-find "pngpaste")
            (push (list (cons :command "pngpaste")
                        (cons :save (lambda (file-path)
                                      (let ((exit-code (call-process "pngpaste" nil nil nil file-path)))
                                        (unless (zerop exit-code)
                                          (error "No image in clipboard (pngpaste exit %d)" exit-code))))))
                  agent-shell-clipboard-image-handlers))))
    '';
}
