# shared/emacs/markdown.nix
# markdown-mode: pandoc-backed preview/export, native code-block fontification.
{ pkgs, ... }:
''
  ;; Markdown — pandoc renders GitHub-flavored markdown for preview/export:
  ;;   C-c C-c l  live preview in eww (in-Emacs, re-renders on save)
  ;;   C-c C-c v  export to HTML and open in browser
  ;; -s emits a standalone page; --metadata title= silences pandoc's
  ;; missing-title warning for untitled buffers.
  (setq markdown-command
        "${pkgs.pandoc}/bin/pandoc -f gfm -t html5 -s --highlight-style=pygments --metadata title=preview"
        markdown-fontify-code-blocks-natively t)
''
