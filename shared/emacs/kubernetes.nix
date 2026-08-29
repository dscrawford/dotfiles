# shared/emacs/kubernetes.nix
# kubed: browse cluster resources by namespace under C-c k. Every command
# shells out to kubectl, so it inherits whatever context ~/.kube/config points
# at (kube-cert-sync keeps that working from the desktop).
{ pkgs, ... }:
''
  ;; kubed-prefix-map is autoloaded as a keymap, so binding it here does not
  ;; pull kubed in until the first C-c k.
  (global-set-key (kbd "C-c k") 'kubed-prefix-map)

  (setq kubed-kubectl-program "${pkgs.kubectl}/bin/kubectl"
        ;; Upstream defaults this to yaml-ts-mode, whose tree-sitter grammar
        ;; this config does not install; yaml-mode is what packages.nix has.
        kubed-yaml-setup-hook '(yaml-mode view-mode))
''
