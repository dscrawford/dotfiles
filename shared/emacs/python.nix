# shared/emacs/python.nix
# Inferior Python shell elisp. Notebooks are handled outside Emacs (no ein).
{ ... }:
''
  ;; PYTHON_BASIC_REPL disables pyrepl (it needs a real terminal), leaving the
  ;; readline completion Emacs can actually drive.
  (setq python-shell-completion-native-enable t
        python-shell-interpreter "python3")
  (setenv "PYTHON_BASIC_REPL" "1")
''
