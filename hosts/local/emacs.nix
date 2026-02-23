# hosts/local/emacs.nix
# Emacs configuration for Home Manager
{ pkgs, ... }:

{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-nox;
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
      # Inline error checking
      flycheck
      # Clipboard integration for emacs-nox
      xclip
      # Godot development support
      gdscript-mode
      # Quick window switching
      ace-window
      # Claude Code IDE dependencies
      websocket
      transient
      web-server
      eat
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
      (setq backup-directory-alist `(("." . "~/.saves")))

      ;; Start Emacs server for emacsclient (needed by emacs-mcp-server)
      (server-start)

      ;; Claude Code IDE
      (use-package claude-code-ide
        :bind ("C-c a" . claude-code-ide-menu)
        :custom
        (claude-code-ide-terminal-backend 'eat)
        :config
        (claude-code-ide-emacs-tools-setup))
      ;; Auto-revert buffers when files change on disk
      (global-auto-revert-mode 1)

      ;; Window navigation
      (windmove-default-keybindings) ; Shift+arrow to move between windows
      (global-set-key (kbd "M-o") 'ace-window) ; M-o to jump to a window by number

      ;; Clipboard integration (wl-copy/wl-paste for Wayland)
      (setq xclip-method 'wl-copy)
      (xclip-mode 1)
      (setq select-enable-clipboard t)
      (setq select-enable-primary t)

      ;; Inline error checking
      (global-flycheck-mode)
      (setq flycheck-python-ruff-executable "ruff")
      (with-eval-after-load 'flycheck
        (setq flycheck-checker-error-threshold 400))

      ;; Godot file type associations
      (with-eval-after-load 'gdscript-mode
        ;; GDScript files (.gd)
        (add-to-list 'auto-mode-alist '("\\.gd\\'" . gdscript-mode))

        ;; Godot scene files (.tscn) - treat as conf/text mode with syntax
        (add-to-list 'auto-mode-alist '("\\.tscn\\'" . conf-mode))

        ;; Godot resource files (.tres) - treat as conf/text mode
        (add-to-list 'auto-mode-alist '("\\.tres\\'" . conf-mode))

        ;; Godot project files (.godot)
        (add-to-list 'auto-mode-alist '("\\.godot\\'" . conf-mode))

        ;; Godot import files (.import)
        (add-to-list 'auto-mode-alist '("\\.import\\'" . conf-mode))

        ;; GDScript mode configuration
        (setq gdscript-use-tab-indents nil)  ; Use spaces instead of tabs
        (setq gdscript-indent-offset 4)      ; 4 spaces per indent level
        (setq gdscript-gdformat-save-enabled nil)) ; Disable auto-format on save (optional)
    '';
  };
}
