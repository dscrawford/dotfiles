# shared/emacs/lsp.nix
# eglot/LSP, dap-mode debugging, corfu, and language file associations.
{ ... }:
''
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

  (my/guard "dap-mode"
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
            :name "Python :: Run Current File")))

  (my/guard "corfu"
    (setq corfu-auto t
          corfu-auto-delay 0.2
          corfu-auto-prefix 2)
    (global-corfu-mode))

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
''
