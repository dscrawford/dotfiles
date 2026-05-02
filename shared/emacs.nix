# shared/emacs.nix
# Emacs configuration for Home Manager
{ config, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  bashPath = "${pkgs.bash}/bin/bash";
in
{
  programs.emacs = {
    enable = true;
    package = if isDarwin then pkgs.emacs-30 else pkgs.emacs-pgtk;
    extraPackages = epkgs: (with epkgs; [
      nix-mode
      magit
      yaml
      yaml-mode
      markdown-mode
      ox-pandoc
      use-package
      emacsql
      dockerfile-mode
      # Jenkinsfile syntax
      groovy-mode
      json-mode
      terraform-mode
      typescript-mode
      web-mode
      org-present
      flycheck
      corfu
      xclip
      rust-mode
      gdscript-mode
      ace-window
      windresize
      (trivialBuild {
        pname = "ultra-scroll";
        version = "0-unstable-2025";
        src = pkgs.fetchFromGitHub {
          owner = "jdtsmith";
          repo = "ultra-scroll";
          rev = "08758c6772c5fbce54fb74fb5cce080b6425c6ce";
          hash = "sha256-hKgwjs4qZikbvHKjWIJFlkI/4LXR6qovCoTBM5miVr8=";
        };
      })
      pdf-tools
      doom-modeline
      nerd-icons
      which-key
      envrc
      websocket
      transient
      web-server
      eat
      exec-path-from-shell
      dap-mode
      ein
      copilot
      (trivialBuild {
        pname = "claude-code-ide";
        version = "0-unstable-2025";
        src = pkgs.fetchFromGitHub {
          owner = "manzaltu";
          repo = "claude-code-ide.el";
          rev = "5f12e60c6d2d1802c8c1b7944bbdf935d5db1364";
          hash = "sha256-tivRvgfI/8XBRImE3wuZ1UD0t2dNWYscv3Aa53BmHZE=";
        };
        packageRequires = with epkgs; [ websocket transient web-server ];
      })
      acp
      (trivialBuild {
        pname = "shell-maker";
        version = "0-unstable-2025";
        src = pkgs.fetchFromGitHub {
          owner = "xenodium";
          repo = "shell-maker";
          rev = "6377cbdb49248d670170f1c8dbe045648063583e";
          hash = "sha256-KeC3NN0wR3yxwekuLxwb9EsRQZoIcS1EK89yL/LGUWw=";
        };
      })
      (trivialBuild {
        pname = "agent-shell";
        version = "0-unstable-2025";
        src = pkgs.fetchFromGitHub {
          owner = "xenodium";
          repo = "agent-shell";
          rev = "1e5d17598d191386ee02998199b77d0f70866820";
          hash = "sha256-a9W5hEm36Wrueh/dCuwmT2rBUY+1R0ysr48jFOloeWo=";
        };
        packageRequires = with epkgs; [ shell-maker acp ];
      })
    ]);
    extraConfig = ''
      (tool-bar-mode -1)
      (menu-bar-mode -1)
      (scroll-bar-mode -1)
      (load-theme 'modus-vivendi t)

      ;; Org-mode: inline images and presentations
      (setq org-startup-with-inline-images t)
      (add-hook 'org-present-mode-hook
        (lambda ()
          (org-display-inline-images)
          (setq-local face-remapping-alist '((default (:height 1.5) variable-pitch)
                                             (header-line (:height 4.0) variable-pitch)
                                             (org-document-title (:height 2.0) org-document-title)))))
      (add-hook 'org-present-mode-quit-hook
        (lambda ()
          (org-remove-inline-images)
          (setq-local face-remapping-alist nil)))

      ;; Tab bar — named by project/directory
      (tab-bar-mode 1)
      (defun my/tab-bar-name ()
        (let ((project (project-current)))
          (if project
              (file-name-nondirectory (directory-file-name (project-root project)))
            (file-name-nondirectory (directory-file-name default-directory)))))
      (setq tab-bar-tab-name-function #'my/tab-bar-name)
      (require 'ultra-scroll)
      (ultra-scroll-mode 1)

      ;; PDF support
      (pdf-tools-install :no-query)

      (require 'doom-modeline)
      (doom-modeline-mode 1)
      (setq doom-modeline-icon t)

      (require 'which-key)
      (which-key-mode 1)
      (setq which-key-idle-delay 0.5)

      (require 'envrc)
      (envrc-global-mode 1)
      ;; envrc: debounce re-exports when switching buffers rapidly
      (setq envrc-none-lighter nil   ; hide "none" in modeline for non-direnv buffers
            envrc-show-summary-in-minibuffer nil) ; reduce minibuffer noise

      ;; Performance optimizations
      (setq gc-cons-threshold (* 100 1024 1024)   ; 100MB - reduce GC pauses
            read-process-output-max (* 1024 1024)  ; 1MB - faster subprocess communication
            inhibit-compacting-font-caches t
            fast-but-imprecise-scrolling t          ; skip fontification during fast scroll
            jit-lock-defer-time 0.05               ; defer font-lock 50ms — keeps typing snappy
            process-adaptive-read-buffering nil)    ; don't delay reading subprocess output
      (setq-default bidi-display-reordering nil    ; Disable bidirectional text
                    bidi-paragraph-direction 'left-to-right)
      ;; so-long-mode: gracefully handle files with very long lines (AI-generated, minified, etc.)
      (global-so-long-mode 1)

      ;; Reset GC after startup
      (add-hook 'emacs-startup-hook
        (lambda () (setq gc-cons-threshold (* 50 1024 1024))))

      ;; Run GC when idle
      (run-with-idle-timer 5 t #'garbage-collect)

      (setq backup-directory-alist `(("." . "~/.emacs.d/backups/"))
            make-backup-files t
            auto-save-file-name-transforms `((".*" "~/.emacs.d/auto-saves/" t))
            auto-save-default t
            auto-save-timeout 20
            auto-save-interval 200
            lock-file-name-transforms `((".*" "~/.emacs.d/lockfiles/" t)))
      (make-directory "~/.emacs.d/backups/" t)
      (make-directory "~/.emacs.d/auto-saves/" t)
      (make-directory "~/.emacs.d/compile-history/" t)
      (make-directory "~/.emacs.d/lockfiles/" t)

      ;; Persist minibuffer history (shell commands, M-x, etc.) across sessions
      (setq savehist-file "~/.emacs.d/savehist"
            savehist-additional-variables '(shell-command-history search-ring regexp-search-ring))
      (savehist-mode 1)
      (setq find-file-visit-truename t)

      ;; Persist safe-variable declarations (press ! at the prompt to trust permanently)
      (setq custom-file "~/.emacs.d/custom.el")
      (when (file-exists-p custom-file) (load custom-file))

      ;; Ediff: use single frame (no separate control window)
      (setq ediff-window-setup-function 'ediff-setup-windows-plain)

      ;; macOS modifier keys
      (when (eq system-type 'darwin)
        (setq mac-option-modifier 'meta
              mac-command-modifier 'super
              mac-right-option-modifier 'none))  ; Allow special characters with right Option

      ;; Start Emacs server with unique name per tmux pane
      (require 'server)
      (let ((pane (getenv "TMUX_PANE")))
        (when pane (setq server-name (format "emacs-%s" (replace-regexp-in-string "%" "" pane)))))
      (unless (server-running-p) (server-force-delete) (server-start))

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
      (require 'ein)
      (require 'ein-log)
      (require 'ein-notebook)
      ;; ein notebook keybindings:
      ;; Fix ein's broken M-up/M-down stubs (cause infinite recursion via max-lisp-eval-depth)
      ;; Rebind M-up/M-down to paragraph movement (same as global) so notebooks feel like normal files
      ;; Cell navigation: C-c C-p / C-c C-n (ein built-in, always works)
      (with-eval-after-load 'ein-notebook
        (keymap-set ein:notebook-mode-map "M-<up>" #'backward-paragraph)
        (keymap-set ein:notebook-mode-map "M-<down>" #'forward-paragraph))

      ;; Inferior Python (run-python) — enable native readline completion for corfu
      ;; PYTHON_BASIC_REPL disables pyrepl (which needs a real terminal) so
      ;; Python falls back to readline-based completion that Emacs can drive.
      (setq python-shell-completion-native-enable t
            python-shell-interpreter "python3")
      (setenv "PYTHON_BASIC_REPL" "1")

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
            '("${pkgs.callPackage ../pkgs/claude-agent-acp {}}/bin/claude-agent-acp"))
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

      ;; Auto-revert: pick up external edits (AI tools, git, etc.) quickly
      (setq auto-revert-interval 1                ; check every 1s instead of 5s
            auto-revert-avoid-polling t            ; use inotify/kqueue instead of polling
            auto-revert-check-vc-info nil          ; don't re-check VC on every revert (faster)
            auto-revert-verbose nil                ; don't spam *Messages* on every revert
            revert-without-query '(".*"))          ; never prompt "file changed, revert?" — just do it
      (global-auto-revert-mode 1)

      (require 'ansi-color)
      (add-hook 'compilation-filter-hook 'ansi-color-compilation-filter)

      ;; Compile — per-directory history stored in ~/.emacs.d/compile-history/
      (defvar my/compile-history-dir "~/.emacs.d/compile-history/")
      (defun my/compile-history-file ()
        (let ((dir (replace-regexp-in-string "/" "!" (abbreviate-file-name default-directory))))
          (expand-file-name dir my/compile-history-dir)))
      (defun my/compile-history-load ()
        (let ((file (my/compile-history-file)))
          (when (file-exists-p file)
            (with-temp-buffer (insert-file-contents file)
              (read (current-buffer))))))
      (defun my/compile-history-save (history)
        (make-directory my/compile-history-dir t)
        (with-temp-file (my/compile-history-file)
          (prin1 history (current-buffer))))
      (defun my/compile ()
        "Compile with per-directory command history."
        (interactive)
        (let* ((history (my/compile-history-load))
               (default (or (car history) compile-command))
               (cmd (read-string (format "Compile [%s]: " default) nil 'history default)))
          (my/compile-history-save (delete-dups (cons cmd history)))
          (compile cmd)))
      (global-set-key (kbd "C-c C-k") 'my/compile)

      (global-set-key (kbd "M-<up>") 'backward-paragraph)
      (global-set-key (kbd "M-<down>") 'forward-paragraph)

      (windmove-default-keybindings)
      (global-set-key (kbd "M-o") 'ace-window)
      (global-set-key (kbd "C-c w") 'windresize)

      ;; Use Home Manager bash for all shell operations
      (setq shell-file-name "${bashPath}"
            explicit-shell-file-name "${bashPath}")
      (add-to-list 'exec-path "${pkgs.bash}/bin")
      (setenv "SHELL" "${bashPath}")

      ;; Ensure /run/wrappers/bin (setuid wrappers: sudo, ping, etc.) is first in PATH
      (when (eq system-type 'gnu/linux)
        (add-to-list 'exec-path "/run/wrappers/bin")
        (setenv "PATH" (concat "/run/wrappers/bin:" (getenv "PATH"))))

      ;; On macOS GUI, inherit PATH from login shell (GUI apps don't get shell PATH)
      (when (and (eq system-type 'darwin) (display-graphic-p))
        (require 'exec-path-from-shell)
        (setq exec-path-from-shell-shell-name "${bashPath}")
        (exec-path-from-shell-initialize))

      ;; Eat terminal (pure elisp, fast, less flicker than vterm)
      ;; C-c t spawns a new eat terminal, C-c r lists existing eat sessions
      (require 'eat)
      (setq eat-shell "${bashPath}")

      (advice-add 'eat-emacs-mode :after (lambda (&rest _) (setq-local cursor-type 'box)))
      (global-set-key (kbd "C-c t") #'(lambda () (interactive) (let ((current-prefix-arg '(4))) (call-interactively 'eat))))
      (global-set-key (kbd "C-c r") #'(lambda () (interactive)
        (let ((eat-buffers (cl-remove-if-not
                            (lambda (buf) (with-current-buffer buf (derived-mode-p 'eat-mode)))
                            (buffer-list))))
          (if eat-buffers
              (switch-to-buffer (completing-read "Select eat session: "
                                                 (mapcar #'buffer-name eat-buffers) nil t))
            (message "No eat sessions open")))))
      ;; Send modifier+arrow keys to the terminal in eat semi-char mode.
      ;; By default these fall through to global-map (left-word etc.),
      ;; but eat resets cursor to match terminal state, causing visual glitch.
      (dolist (key '("M-<left>" "M-<right>" "M-<up>" "M-<down>"
                     "C-<left>" "C-<right>" "C-<up>" "C-<down>"))
        (define-key eat-semi-char-mode-map (kbd key) #'eat-self-input))
      ;; Bracketed paste for eat — wrap yanked text so shell treats it as one input
      (defun my/eat-yank-with-bracketed-paste ()
        "Yank into eat using bracketed paste so multiline text isn't executed line-by-line."
        (interactive)
        (let ((text (or (current-kill 0 t) "")))
          (eat-term-send-string eat-terminal "\e[200~")
          (eat-term-send-string eat-terminal text)
          (eat-term-send-string eat-terminal "\e[201~")))
      (with-eval-after-load 'eat
        (define-key eat-semi-char-mode-map (kbd "C-c C-y") #'my/eat-yank-with-bracketed-paste))

      (add-hook 'eshell-load-hook #'eat-eshell-mode)
      (add-hook 'eshell-load-hook #'eat-eshell-visual-command-mode)

      (require 'magit)
      (global-set-key (kbd "C-c g") 'magit-status)

      (setq xclip-method (if (eq system-type 'darwin) 'pbpaste 'wl-copy))
      (xclip-mode 1)
      (setq select-enable-clipboard t)
      (unless (eq system-type 'darwin)
        (setq select-enable-primary t))

      ;; LSP (eglot is built-in to Emacs 29+)
      ;; Automatically start eglot and flymake for supported modes
      ;; gdscript-mode omitted from flymake — diagnostics via Godot LSP connection
      (dolist (hook '(nix-mode-hook python-mode-hook gdscript-mode-hook
                      js-mode-hook typescript-mode-hook web-mode-hook
                      rust-mode-hook c-mode-hook c++-mode-hook))
        (add-hook hook 'eglot-ensure))
      (dolist (hook '(nix-mode-hook python-mode-hook
                      js-mode-hook typescript-mode-hook web-mode-hook
                      rust-mode-hook c-mode-hook c++-mode-hook))
        (add-hook hook 'flymake-mode))
      ;; Language servers: nil (Nix), pyright (Python), typescript-language-server (JS/TS),
      ;; rust-analyzer (Rust), clangd (C/C++)
      (with-eval-after-load 'eglot
        (add-to-list 'eglot-server-programs '(nix-mode . ("nil")))
        (add-to-list 'eglot-server-programs '(python-mode . ("pyright-langserver" "--stdio")))
        (add-to-list 'eglot-server-programs '(gdscript-mode . ("localhost" 6005)))
        (add-to-list 'eglot-server-programs '((js-mode typescript-mode web-mode) . ("typescript-language-server" "--stdio")))
        (add-to-list 'eglot-server-programs '(rust-mode . ("rust-analyzer")))
        (add-to-list 'eglot-server-programs '((c-mode c++-mode) . ("clangd"))))

      (require 'dap-mode)
      (require 'dap-python)
      (setq dap-python-debugger 'debugpy
            dap-python-executable "python3")
      (dap-auto-configure-mode 1)

      ;; Debug keybindings — C-c d prefix
      (dolist (bind '(("d" . dap-debug)
                     ("b" . dap-breakpoint-toggle)
                     ("n" . dap-next)
                     ("i" . dap-step-in)
                     ("o" . dap-step-out)
                     ("c" . dap-continue)
                     ("r" . dap-ui-repl)
                     ("q" . dap-disconnect)
                     ("e" . dap-eval-thing-at-point)))
        (global-set-key (kbd (format "C-c d %s" (car bind))) (cdr bind)))

      ;; Default debug template for Python files
      (dap-register-debug-template "Python :: Run Current File"
        (list :type "python"
              :args ""
              :cwd nil
              :program nil
              :request "launch"
              :name "Python :: Run Current File"))

      (setq corfu-auto t
            corfu-auto-delay 0.2
            corfu-auto-prefix 2)
      (global-corfu-mode)

      (with-eval-after-load 'flycheck
        (setq flycheck-checker-error-threshold 400))

      ;; Jenkinsfile syntax
      (add-to-list 'auto-mode-alist '("Jenkinsfile\\'" . groovy-mode))

      ;; JavaScript/TypeScript file associations (.js uses built-in js-mode)
      (add-to-list 'auto-mode-alist '("\\.tsx\\'" . web-mode))
      (add-to-list 'auto-mode-alist '("\\.jsx\\'" . web-mode))
      (add-to-list 'auto-mode-alist '("\\.ts\\'" . typescript-mode))
      (with-eval-after-load 'web-mode
        ;; JSX content type for proper React syntax in .tsx/.jsx
        (add-to-list 'web-mode-content-types-alist '("jsx" . "\\.tsx\\'"))
        (add-to-list 'web-mode-content-types-alist '("jsx" . "\\.jsx\\'"))
        (setq web-mode-markup-indent-offset 2
              web-mode-code-indent-offset 2
              web-mode-css-indent-offset 2))

      ;; Godot file type associations
      (add-to-list 'auto-mode-alist '("\\.gd\\'" . gdscript-mode))
      (dolist (ext '("\\.tscn\\'" "\\.tres\\'" "\\.godot\\'" "\\.import\\'"))
        (add-to-list 'auto-mode-alist (cons ext 'conf-mode)))
      (with-eval-after-load 'gdscript-mode
        (setq gdscript-use-tab-indents nil
              gdscript-indent-offset 4
              gdscript-gdformat-save-enabled nil))
    '';
  };
}
