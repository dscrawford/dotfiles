# shared/emacs/python.nix
# Inferior Python shell elisp.
#
# Previously also held ein (Emacs IPython Notebook) config; ein is unmaintained
# upstream, so it was dropped. Notebooks are handled outside Emacs — the jupyter
# and nbstripout packages in shared/home/packages.nix are unaffected.
{ ... }:
''
  ;; Inferior Python (run-python) — enable native readline completion for corfu
  ;; PYTHON_BASIC_REPL disables pyrepl (which needs a real terminal) so
  ;; Python falls back to readline-based completion that Emacs can drive.
  (setq python-shell-completion-native-enable t
        python-shell-interpreter "python3")
  (setenv "PYTHON_BASIC_REPL" "1")
''
