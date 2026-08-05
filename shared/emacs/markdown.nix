# shared/emacs/markdown.nix
# markdown-mode: pandoc-backed preview/export, native code-block fontification.
{ pkgs, ... }:
''
  ;; C-c C-c l live-previews in eww, C-c C-c v exports and opens a browser.
  ;; --metadata title= silences pandoc's warning on untitled buffers.
  (setq markdown-command
        "${pkgs.pandoc}/bin/pandoc -f gfm -t html5 -s --highlight-style=pygments --metadata title=preview"
        markdown-fontify-code-blocks-natively t)
''
