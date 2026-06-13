# shared/emacs/ui.nix
# UI, theme, org, tab-bar, performance, file management, server elisp.
{ ... }:
''
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
''
