# shared/emacs/guard.nix
# Home Manager compiles all of extraConfig into one default.el, so an unhandled
# error anywhere skips every remaining form in the file. my/guard demotes such
# errors to warnings. Keep `defun'/`defvar' outside it (they cannot fail, and
# top-level definitions avoid byte-compile warnings); `use-package' forms need
# no guard either, since :catch defaults to on.
{ ... }:
''
  (defmacro my/guard (label &rest body)
    "Evaluate BODY, demoting any error to a warning tagged with LABEL.
  Keeps an optional package from aborting the rest of the init file. Failures
  land in *Warnings*, deferred until startup finishes. Errors still propagate
  under `debug-on-error', so emacs --debug-init reaches the real signal point."
    (declare (indent 1) (debug t))
    ;; Label repeated in the message text: `display-warning' renders only the
    ;; car of a list type. The list form still keys `warning-suppress-types'.
    (let ((err (make-symbol "err")))
      `(condition-case-unless-debug ,err
           (progn ,@body)
         (error
          (display-warning (list 'emacs-init (intern ,label))
                           (format "%s disabled: %s"
                                   ,label (error-message-string ,err))
                           :error)))))
''
