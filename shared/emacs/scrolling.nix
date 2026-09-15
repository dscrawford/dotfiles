# shared/emacs/scrolling.nix
# ultra-scroll for the trackpad/wheel, plus the built-in knobs it leaves alone.
{ ... }:
''
  ;; ultra-scroll only remaps the wheel handler, but it switches on
  ;; pixel-scroll-precision-mode, which is what the keyboard settings need.
  (my/guard "ultra-scroll"
    (require 'ultra-scroll)
    (ultra-scroll-mode 1))

  ;; Without interpolate-page, PgUp/PgDn under pixel-scroll-precision-mode land
  ;; on cua-scroll-down/up and jump a full screen with no animation.
  (setq pixel-scroll-precision-interpolate-page t
        ;; 0 recenters point whenever it leaves the window, undoing a scroll.
        scroll-conservatively 3
        fast-but-imprecise-scrolling t) ; skip fontification during fast scroll
''
