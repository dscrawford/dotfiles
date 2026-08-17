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
                       ((name . "ALLOWED_SEARCH_ENGINES") (value . "duckduckgo,bing,brave,startpage")))))
              ;; Ollama-backed task offload. Sonnet-tier hints map to the local
              ;; model; opus stays remote — security-scout's pin (2bd9ee8) wants
              ;; the top-tier model, not a local stand-in.
              ((name . "local-llm-router")
               (command . "${pkgs.callPackage ../../pkgs/local-llm-mcp {}}/bin/local-llm-mcp")
               (env . (((name . "LOCAL_LLM_DEFAULT_MODEL") (value . "qwen3:8b"))
                       ((name . "LOCAL_LLM_MODEL_OVERRIDES")
                        (value . "{\"sonnet\":\"qwen3:8b\",\"claude-sonnet-5\":\"qwen3:8b\"}")))))))
      ;; acp-shutdown kills only the acp process; TERM its whole group or
      ;; the claude + MCP-server children leak (RUFLO_BUG.md).
      (defun my/acp--kill-group (pgid)
        (signal-process pgid 'KILL))
      (defun my/acp-shutdown--kill-group (&rest args)
        ;; pid bound before negation: a live process can have a nil pid
        ;; (network process), and a :before-advice error aborts acp-shutdown.
        (when-let* ((client (plist-get args :client))
                    (proc (map-elt client :process))
                    ((process-live-p proc))
                    (pid (process-id proc))
                    (pgid (- pid)))
          (signal-process pgid 'TERM)
          (run-at-time 5 nil #'my/acp--kill-group pgid)))
      (with-eval-after-load 'acp
        (advice-add 'acp-shutdown :before #'my/acp-shutdown--kill-group))
      ;; kill-buffer-hook skips live buffers on Emacs exit; sweep here too.
      (defun my/acp--kill-all-groups ()
        (dolist (proc (process-list))
          (when (string-match-p "/claude-agent-acp\\'"
                                (or (car-safe (process-command proc)) ""))
            (when-let* (((process-live-p proc))
                        (pid (process-id proc)))
              (signal-process (- pid) 'TERM)))))
      (add-hook 'kill-emacs-hook #'my/acp--kill-all-groups)
      (defun my/ruflo--reap (proc)
        (when (process-live-p proc)
          (kill-process proc)))
      (defun my/ruflo-register-session ()
        "Register the current agent-shell session with ruflo for coordination."
        (when (executable-find "ruflo")
          (let* ((cwd (agent-shell-cwd))
                 (project (file-name-nondirectory (directory-file-name cwd)))
                 (buf-name (buffer-name))
                 ;; Pipe stdin + EOF: a pty launch never exits (RUFLO_BUG.md).
                 (proc (make-process
                        :name "ruflo-register"
                        :command (list "ruflo" "session" "save"
                                       "-n" (format "agent-shell:%s:%s" project buf-name))
                        :buffer nil
                        :connection-type 'pipe
                        :noquery t
                        :sentinel #'ignore)))
            ;; Errors if the child already exited (e.g. broken ruflo shim);
            ;; must not abort the mode hook.
            (ignore-errors (process-send-eof proc))
            (run-at-time 30 nil #'my/ruflo--reap proc))))
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
