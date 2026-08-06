# shared/emacs/agent-shell.nix
# claude-code-ide and agent-shell elisp, as two ordered pieces that
# emacs.nix assembles in order.
{ pkgs, ... }:

{
  claudeCodeIde =
    ''
      ;; No my/guard: use-package's :catch already demotes errors in its body.
      (use-package claude-code-ide
        :bind ("C-c a" . claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'eat)
        :config
        (claude-code-ide-emacs-tools-setup))
    '';

  agentShell =
    ''
      (my/guard "agent-shell" (require 'agent-shell))
      (global-set-key (kbd "C-c s") 'agent-shell)
      ;; Always prompt for session on start so we can resume from another session
      (setq agent-shell-session-strategy 'prompt)
      ;; Central ~/.emacs.d/agent-shell/<project>/ rather than per-project
      ;; .agent-shell/, so transcripts survive repo cleanups.
      (setq agent-shell-dot-subdir-function
            (lambda (subdir)
              (let ((project (file-name-nondirectory
                              (directory-file-name (agent-shell-cwd)))))
                (expand-file-name
                 (concat "agent-shell/" project "/" subdir "/")
                 user-emacs-directory))))
      (setq agent-shell-anthropic-claude-acp-command
            '("${pkgs.callPackage ../../pkgs/claude-agent-acp {}}/bin/claude-agent-acp"))
      (setq agent-shell-preferred-agent-config 'anthropic-claude)
      (setq agent-shell-show-context-usage-indicator t)
      ;; Agent sidebar. Deliberately NOT `agent-shell-workspace-toggle', which
      ;; spawns an "Agents" tab and forces buffer isolation -- too much ceremony
      ;; alongside per-project tabs. Bound globally because the package's own
      ;; docs bind via `agent-shell-command-map', which has never existed.
      (my/guard "agent-shell-workspace" (require 'agent-shell-workspace))
      (global-set-key (kbd "C-c S") 'agent-shell-workspace-sidebar-toggle)
      ;; The only MCP source for agent-shell sessions: they read neither
      ;; ~/.claude/.mcp.json nor `claude mcp` user scope.
      (setq agent-shell-mcp-servers
            '(((name . "ruflo")
               (command . "ruflo")
               (args . ("mcp" "start")))
              ((name . "emacs-mcp")
               (command . "npx")
               (args . ("-y" "@keegancsmith/emacs-mcp-server")))
              ;; Version pinned so npx serves it from cache rather than
              ;; re-checking the registry on every session start.
              ((name . "web-search")
               (command . "npx")
               (args . ("-y" "open-websearch@1.2.0"))
               (env . (((name . "MODE") (value . "stdio"))
                       ((name . "DEFAULT_SEARCH_ENGINE") (value . "duckduckgo"))
                       ((name . "ALLOWED_SEARCH_ENGINES") (value . "duckduckgo,bing,brave,startpage")))))))
      (defun my/ruflo-register-session ()
        "Register the current agent-shell session with ruflo for coordination."
        (when (executable-find "ruflo")
          (let* ((cwd (agent-shell-cwd))
                 (project (file-name-nondirectory (directory-file-name cwd)))
                 (buf-name (buffer-name)))
            (start-process "ruflo-register" nil "ruflo" "session" "save"
                           "-n" (format "agent-shell:%s:%s" project buf-name)))))
      (add-hook 'agent-shell-mode-hook #'my/ruflo-register-session)
      ;; Clipboard image support (not upstream). MIME types are checked first so
      ;; text clipboard falls through to yank. The guard sits INSIDE
      ;; with-eval-after-load so it covers the deferred load too: this body pokes
      ;; at three private upstream functions and is the likeliest thing here to
      ;; break on a bump.
      (with-eval-after-load 'agent-shell
        (my/guard "agent-shell-config"
          ;; C-<tab> conflicts with Emacs.
          (keymap-set agent-shell-mode-map "C-M-<tab>" #'agent-shell-cycle-session-mode)
          (keymap-unset agent-shell-mode-map "C-<tab>")
          ;; Model-switch shim (C-c C-v): claude-agent-acp implements
          ;; session/set_config_option but not session/set_model, and agent-shell
          ;; falls back to the latter when no "model" config option is in session
          ;; state. Current pins do advertise it, so this normally defers upstream.
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
                 ;; Only method-not-found means the agent wants set_model; retry
                 ;; via orig-fn (un-advised, so no loop). Other errors surface.
                 :on-failure (lambda (acp-error raw-message)
                               (cond ((equal -32601 (map-elt acp-error 'code))
                                      (apply orig-fn args))
                                     (on-failure
                                      (funcall on-failure acp-error raw-message))
                                     (t
                                      (message "Failed to change model: %s" acp-error))))))))
          (advice-add 'agent-shell--config-option-set-model-id :around
                      #'my/agent-shell-set-model-via-config-option)
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
          (when (executable-find "pngpaste")
            (push (list (cons :command "pngpaste")
                        (cons :save (lambda (file-path)
                                      (let ((exit-code (call-process "pngpaste" nil nil nil file-path)))
                                        (unless (zerop exit-code)
                                          (error "No image in clipboard (pngpaste exit %d)" exit-code))))))
                  agent-shell-clipboard-image-handlers))))
    '';
}
