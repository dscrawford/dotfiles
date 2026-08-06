# shared/emacs/packages.nix
# Base ELPA packages plus custom GitHub-sourced packages, in load order.
{ pkgs, epkgs }:

let
  custom = import ./custom-packages.nix { inherit pkgs epkgs; };
in
with epkgs; [
  nix-mode
  magit
  yaml
  yaml-mode
  markdown-mode
  ox-pandoc
  use-package
  emacsql
  dockerfile-mode
  # Jenkinsfile syntax
  groovy-mode
  json-mode
  terraform-mode
  typescript-mode
  web-mode
  org-present
  flycheck
  corfu
  xclip
  rust-mode
  gdscript-mode
  ace-window
  windresize
  ultra-scroll
  pdf-tools
  doom-modeline
  nerd-icons
  which-key
  envrc
  websocket
  transient
  web-server
  eat
  exec-path-from-shell
  dap-mode
  custom.claude-code-ide
  custom.acp
  custom.shell-maker
  custom.agent-shell
  custom.agent-shell-workspace
]
