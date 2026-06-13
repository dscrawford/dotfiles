# shared/emacs/agent-shell.nix
# copilot, claude-code-ide, and agent-shell elisp.
# Exports two ordered pieces assembled in order by emacs.nix.
{ pkgs, ... }:

{
  copilotCcide =
    ''
      (setq copilot-node-executable "${pkgs.nodejs}/bin/node")
      (require 'copilot)
      (global-set-key (kbd "C-c p") 'copilot-mode)
      (with-eval-after-load 'copilot
        (define-key copilot-completion-map (kbd "TAB") 'copilot-accept-completion)
        (define-key copilot-completion-map (kbd "<tab>") 'copilot-accept-completion))

      (use-package claude-code-ide
        :bind ("C-c a" . claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'eat)
        :config
        (claude-code-ide-emacs-tools-setup))
    '';

  agentShell =
    ''
      (require 'agent-shell)
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
      ;; Pass ruflo MCP server to agent-shell so claude gets ruflo tools inside Emacs
      (setq agent-shell-mcp-servers
            '(((name . "ruflo")
               (command . "ruflo")
               (args . ("mcp" "start")))))
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
      (with-eval-after-load 'agent-shell
        ;; Rebind cycle-session-mode from C-<tab> (conflicts with Emacs) to C-M-<tab>
        (keymap-set agent-shell-mode-map "C-M-<tab>" #'agent-shell-cycle-session-mode)
        (keymap-unset agent-shell-mode-map "C-<tab>")
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
                agent-shell-clipboard-image-handlers)))
    '';
}
