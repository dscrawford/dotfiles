# shared/emacs/navigation.nix
# M-<up>/M-<down> move by defun. Paragraph motion keys off blank lines, so in
# code it stopped inside a function and skipped past the next one.
{ ... }:
''
  (global-set-key (kbd "M-<up>") 'beginning-of-defun)
  (global-set-key (kbd "M-<down>") 'end-of-defun)

  ;; Wrapped bindings, not scroll-on-jump-advice-add: that macro calls
  ;; advice-add while expanding, i.e. when default.el is byte-compiled.
  (my/guard "scroll-on-jump"
    (require 'scroll-on-jump)
    ;; Both wrappers before either binding: my/guard abandons the rest of the
    ;; body on error, and one animated key out of two is worse than neither.
    (let ((up (scroll-on-jump-interactive 'beginning-of-defun))
          (down (scroll-on-jump-interactive 'end-of-defun)))
      (global-set-key (kbd "M-<up>") up)
      (global-set-key (kbd "M-<down>") down)))
''
