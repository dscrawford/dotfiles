# shared/emacs/server.nix
# The Emacs server: one per tmux pane, and one per Emacs.
{ ... }:
''
  (require 'server)
  (let ((pane (getenv "TMUX_PANE")))
    (when pane (setq server-name (format "emacs-%s" (replace-regexp-in-string "%" "" pane)))))
  ;; Every Emacs runs its own server: scooter-mode's bridge asks the Emacs that
  ;; launched it for auth headers via emacsclient -s server-name. If another
  ;; Emacs already owns the name, take a unique one rather than going without.
  (when (server-running-p)
    (setq server-name (format "%s-%d" server-name (emacs-pid))))
  (server-force-delete)
  (server-start)
''
