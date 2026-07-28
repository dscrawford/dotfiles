# shared/emacs/guard.nix
# Init resilience: a guard macro so one broken optional package can't abort the
# rest of the configuration.
#
# Home Manager compiles the whole of programs.emacs.extraConfig into a single
# default.el (modules/programs/emacs.nix -> epkgs.trivialBuild), so every module
# assembled by emacs.nix shares one `load'. An unhandled error anywhere skips
# every remaining form in the file — a failing (pdf-tools-install) on darwin
# took out doom-modeline, which-key, envrc, savehist and server-start with it.
#
# Keep `defun' and `defvar' outside the guard: defining them cannot fail, and
# top-level definitions byte-compile without "not known to be defined" warnings.
# Note that `use-package' already wraps its own body this way (:catch defaults
# to on), so use-package forms need no guard.
{ ... }:
''
  (defmacro my/guard (label &rest body)
    "Evaluate BODY, demoting any error to a warning tagged with LABEL.
  Keeps an optional package from aborting the rest of the init file. Failures
  land in *Warnings*, deferred until startup finishes. Errors still propagate
  under `debug-on-error', so emacs --debug-init reaches the real signal point."
    (declare (indent 1) (debug t))
    ;; The label goes in the message text, not just the warning type:
    ;; `display-warning' renders only the car of a list type, so a bare
    ;; (emacs-init LABEL) type would show as "(emacs-init)" and lose it.
    ;; The list form still keys `warning-suppress-types' per package.
    (let ((err (make-symbol "err")))
      `(condition-case-unless-debug ,err
           (progn ,@body)
         (error
          (display-warning (list 'emacs-init (intern ,label))
                           (format "%s disabled: %s"
                                   ,label (error-message-string ,err))
                           :error)))))
''
