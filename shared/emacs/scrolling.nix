# shared/emacs/scrolling.nix
# ultra-scroll for the trackpad/wheel, plus the built-in knobs it leaves alone.
{ ... }:
''
  ;; ultra-scroll only remaps the wheel handler, but it switches on
  ;; pixel-scroll-precision-mode, which is what the keyboard settings need.
  (my/guard "ultra-scroll"
    (require 'ultra-scroll)
    (ultra-scroll-mode 1))

  ;; This mouse reports a constant 150px per click, not real pixel deltas, so
  ;; ultra-scroll teleports it. Trackpads vary, and keep the direct path.
  ;; The shared 0.1s suits a page jump but lags behind a spinning wheel.
  (defvar my/wheel-scroll-time 0.05)
  (defun my/ultra-scroll-interpolate-mouse (fn event &optional arg)
    (if-let* ((delta (nth 4 event))
              (_ (eq (device-class last-event-frame last-event-device) 'mouse))
              (window (mwheel-event-window event))
              (origin (selected-window)))
        (let ((pixel-scroll-precision-interpolation-total-time my/wheel-scroll-time))
          (with-selected-window (if (framep window) (frame-selected-window window) window)
            (condition-case nil
                (pixel-scroll-precision-interpolate (round (cdr delta)) origin 1)
              ((beginning-of-buffer end-of-buffer) nil))))
      (funcall fn event arg)))
  (advice-add 'ultra-scroll :around #'my/ultra-scroll-interpolate-mouse)

  ;; Without interpolate-page, PgUp/PgDn under pixel-scroll-precision-mode land
  ;; on cua-scroll-down/up and jump a full screen with no animation.
  (setq pixel-scroll-precision-interpolate-page t
        ;; 0 recenters point whenever it leaves the window, undoing a scroll.
        scroll-conservatively 3
        fast-but-imprecise-scrolling t) ; skip fontification during fast scroll
''
