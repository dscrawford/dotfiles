# shared/emacs/jupyter.nix
# ein (Jupyter notebooks) and inferior Python shell elisp.
{ ... }:
''
  (require 'ein)
  (require 'ein-log)
  (require 'ein-notebook)
  ;; Display image outputs (matplotlib, etc.) inline in notebook buffers
  (setq ein:output-area-inlined-images t)
  ;; ein notebook keybindings:
  ;; Fix ein's broken M-up/M-down stubs (cause infinite recursion via max-lisp-eval-depth)
  ;; Rebind M-up/M-down to paragraph movement (same as global) so notebooks feel like normal files
  ;; Cell navigation: C-c C-p / C-c C-n (ein built-in, always works)
  (with-eval-after-load 'ein-notebook
    (keymap-set ein:notebook-mode-map "M-<up>" #'backward-paragraph)
    (keymap-set ein:notebook-mode-map "M-<down>" #'forward-paragraph)
    ;; C-c C-h: toggle cell output visibility
    (keymap-set ein:notebook-mode-map "C-c C-h" #'ein:cell-toggle-output))
  ;; Structural cell folding via outline-minor-mode
  (add-hook 'ein:notebook-mode-hook #'outline-minor-mode)
  ;; Reuse the current window instead of splitting/popping a new one.
  ;; ein uses `pop-to-buffer' for both the notebooklist (ein:run) and for
  ;; opening a notebook, so `display-buffer-alist' can force same-window.
  ;; "*ein:notebooklist ...*" -> notebooklist; "*ein: url/path*" -> notebook
  ;; worksheets (the trailing space distinguishes them from notebooklist).
  (add-to-list 'display-buffer-alist
               '("\\*ein:notebooklist " (display-buffer-same-window)))
  (add-to-list 'display-buffer-alist
               '("\\*ein: " (display-buffer-same-window)))

  ;; Inferior Python (run-python) — enable native readline completion for corfu
  ;; PYTHON_BASIC_REPL disables pyrepl (which needs a real terminal) so
  ;; Python falls back to readline-based completion that Emacs can drive.
  (setq python-shell-completion-native-enable t
        python-shell-interpreter "python3")
  (setenv "PYTHON_BASIC_REPL" "1")
''
