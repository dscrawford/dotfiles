# shared/emacs.nix
# Emacs configuration for Home Manager
{ config, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
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
      # Enhanced JSON
      json-mode
      terraform-mode
      # Org presentations
      org-present
      # Inline error checking
      flycheck
      # Autocomplete
      corfu
      # Clipboard integration
      xclip
      # Godot development support
      gdscript-mode
      # Quick window switching
      ace-window
      # Window resizing
      windresize
      # Smooth scrolling
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
      # PDF viewing
      pdf-tools
      # Modern modeline
      doom-modeline
      nerd-icons
      # Show available keybindings
      which-key
      # Direnv integration
      envrc
      # Claude Code IDE dependencies
      websocket
      transient
      web-server
      eat
      # Copilot inline completions
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
    ]);
    extraConfig = ''
      ;; GUI cleanup and dark theme
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

      ;; PDF support (deferred until a PDF is opened)
      (add-hook 'pdf-view-mode-hook (lambda () (require 'pdf-tools) (pdf-tools-install :no-query)))

      ;; Modern modeline
      (require 'doom-modeline)
      (doom-modeline-mode 1)
      (setq doom-modeline-icon t)

      ;; Show available keybindings after prefix key press
      (require 'which-key)
      (which-key-mode 1)
      (setq which-key-idle-delay 0.5)

      ;; Direnv integration — automatically load .envrc environments in buffers
      (require 'envrc)
      (envrc-global-mode 1)

      ;; Performance optimizations
      (setq gc-cons-threshold (* 100 1024 1024))  ; 100MB - reduce GC pauses
      (setq read-process-output-max (* 1024 1024))  ; 1MB - faster subprocess communication
      (setq inhibit-compacting-font-caches t)
      (setq-default bidi-display-reordering nil)  ; Disable bidirectional text
      (setq-default bidi-paragraph-direction 'left-to-right)

      ;; Reset GC after startup
      (add-hook 'emacs-startup-hook
        (lambda () (setq gc-cons-threshold (* 50 1024 1024))))

      ;; Run GC when idle
      (run-with-idle-timer 5 t #'garbage-collect)

      (setq backup-directory-alist `(("." . "~/.emacs.d/backups/")))
      (setq make-backup-files t)
      (setq auto-save-file-name-transforms `((".*" "~/.emacs.d/auto-saves/" t)))
      (setq auto-save-default t)
      (setq auto-save-timeout 20)
      (setq auto-save-interval 200)
      (setq lock-file-name-transforms `((".*" "~/.emacs.d/lockfiles/" t)))
      (make-directory "~/.emacs.d/backups/" t)
      (make-directory "~/.emacs.d/auto-saves/" t)
      (make-directory "~/.emacs.d/compile-history/" t)
      (make-directory "~/.emacs.d/lockfiles/" t)

      ;; Persist minibuffer history (shell commands, M-x, etc.) across sessions
      (setq savehist-file "~/.emacs.d/savehist")
      (setq savehist-additional-variables '(shell-command-history search-ring regexp-search-ring))
      (savehist-mode 1)
      (setq find-file-visit-truename t)

      ;; macOS modifier keys
      (when (eq system-type 'darwin)
        (setq mac-option-modifier 'meta)
        (setq mac-command-modifier 'super)
        (setq mac-right-option-modifier 'none))  ; Allow special characters with right Option

      ;; Start Emacs server with unique name per tmux pane
      (require 'server)
      (let ((pane (getenv "TMUX_PANE")))
        (when pane (setq server-name (format "emacs-%s" (replace-regexp-in-string "%" "" pane)))))
      (unless (server-running-p) (server-force-delete) (server-start))

      ;; Copilot inline completions
      (setq copilot-node-executable "${pkgs.nodejs}/bin/node")
      (require 'copilot)
      (global-set-key (kbd "C-c p") 'copilot-mode)
      (with-eval-after-load 'copilot
        (define-key copilot-completion-map (kbd "TAB") 'copilot-accept-completion)
        (define-key copilot-completion-map (kbd "<tab>") 'copilot-accept-completion))

      ;; Claude Code IDE
      (use-package claude-code-ide
        :bind ("C-c a" . claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'eat)
        :config
        (claude-code-ide-emacs-tools-setup))
      ;; Auto-revert buffers when files change on disk
      (global-auto-revert-mode 1)

      ;; Render ANSI color/style codes in compilation buffer
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

      ;; Move between paragraphs (like Ctrl-up/Ctrl-down in terminals)
      (global-set-key (kbd "M-<up>") 'backward-paragraph)
      (global-set-key (kbd "M-<down>") 'forward-paragraph)

      ;; Window navigation
      (windmove-default-keybindings) ; Shift+arrow to move between windows
      (global-set-key (kbd "M-o") 'ace-window) ; M-o to jump to a window by number
      (global-set-key (kbd "C-c w") 'windresize) ; C-c w to enter resize mode, arrows to resize, q to quit

      ;; Eat terminal (pure elisp, fast, less flicker than vterm)
      ;; C-c t spawns a new eat terminal, C-c r lists existing eat sessions
      (require 'eat)
      (eat-compile-terminfo)
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
      (add-hook 'eshell-load-hook #'eat-eshell-mode)
      (add-hook 'eshell-load-hook #'eat-eshell-visual-command-mode)

      ;; Magit
      (require 'magit)
      (global-set-key (kbd "C-c g") 'magit-status)

      ;; Clipboard integration (platform-specific)
      (setq xclip-method (if (eq system-type 'darwin) 'pbpaste 'wl-copy))
      (xclip-mode 1)
      (setq select-enable-clipboard t)
      (when (not (eq system-type 'darwin))
        (setq select-enable-primary t))

      ;; LSP (eglot is built-in to Emacs 29+)
      ;; Automatically start eglot for supported modes
      (add-hook 'nix-mode-hook 'eglot-ensure)
      (add-hook 'python-mode-hook 'eglot-ensure)
      (add-hook 'gdscript-mode-hook 'eglot-ensure)
      ;; Use nil for Nix, pyright for Python, Godot built-in LSP for GDScript
      (with-eval-after-load 'eglot
        (add-to-list 'eglot-server-programs '(nix-mode . ("nil")))
        (add-to-list 'eglot-server-programs '(python-mode . ("pyright-langserver" "--stdio")))
        (add-to-list 'eglot-server-programs '(gdscript-mode . ("localhost" 6005))))

      ;; Flymake for linting (works with eglot)
      (add-hook 'python-mode-hook 'flymake-mode)
      (add-hook 'nix-mode-hook 'flymake-mode)

      ;; Autocomplete
      (setq corfu-auto t)          ;; popup automatically
      (setq corfu-auto-delay 0.2)  ;; after 0.2s
      (setq corfu-auto-prefix 2)   ;; after typing 2 chars
      (global-corfu-mode)

      ;; Flycheck for modes without LSP/Flymake
      (with-eval-after-load 'flycheck
        (setq flycheck-checker-error-threshold 400))

      ;; Jenkinsfile syntax
      (add-to-list 'auto-mode-alist '("Jenkinsfile\\'" . groovy-mode))

      ;; Godot file type associations
      (add-to-list 'auto-mode-alist '("\\.gd\\'" . gdscript-mode))
      (dolist (ext '("\\.tscn\\'" "\\.tres\\'" "\\.godot\\'" "\\.import\\'"))
        (add-to-list 'auto-mode-alist (cons ext 'conf-mode)))
      (with-eval-after-load 'gdscript-mode
        (setq gdscript-use-tab-indents nil)
        (setq gdscript-indent-offset 4)
        (setq gdscript-gdformat-save-enabled nil))
    '';
  };
}
