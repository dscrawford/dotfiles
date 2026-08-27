# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# NixOS desktop (full: Sway + Emacs + gaming)
sudo nixos-rebuild switch --flake .#local

# NixOS terminal-only
sudo nixos-rebuild switch --flake .#terminal

# NixOS servers (node1, node2, node3)
sudo nixos-rebuild switch --flake .#node1

# macOS (nix-darwin)
darwin-rebuild switch --flake .#terminal-darwin-arm
darwin-rebuild switch --flake .#terminal-darwin-x86

# Test without activating
sudo nixos-rebuild test --flake .#local

# Update flake inputs
nix flake update
```

**Important**: Run `git add -A` before rebuilding — Nix flakes only see tracked files.

## Architecture

### Builder Functions (flake.nix)

Three builder functions create all system configurations:

- **`mkServer`** — NixOS servers (Kubernetes nodes). Params: `hostname`, `ip`, `extraModules`.
- **`mkLocal`** — NixOS desktop/terminal systems with Home Manager. Params: `hostname`, `username`, `system`, `gitUser`, `enableSecrets`, `homeModules`, `extraModules`.
- **`mkDarwin`** — macOS systems with Home Manager via nix-darwin. Same params as mkLocal plus required `system`.

These are exported via `lib = { inherit mkServer mkLocal mkDarwin; }` for use by external flakes.

### Configuration Composition

```
mkServer: common.nix → server-common.nix → users.nix → boot-common.nix → host-specific
mkLocal:  common.nix → boot-common.nix → local-common.nix → local.nix → Home Manager(shared/home + optional modules)
mkDarwin: darwin-common.nix → Home Manager(shared/home + optional modules)
```

The k8s nodes (`node1`–`node3`) are built through the `kubeNode` helper in flake.nix, which adds the shared cluster modules (`kubernetes.nix`, `kube-cert-renew.nix`, `kube-stale-mount-recovery.nix`, `iscsi.nix`) plus each host's hardware and boot files. Desktop (`local`) adds `shared/sway`, `shared/gaming.nix`, and `shared/easyeffects.nix` as extra Home Manager modules. Terminal configs use only `shared/home`.

### Key Files

- **`shared/home/`** — Cross-platform (Linux/macOS) Home Manager config. `default.nix` holds the core config and imports the per-tool modules beside it (bash, git, tmux, ssh, packages, ollama, llm-routing, …). Uses `isDarwin`/`isLinux` conditionals for platform-specific packages, paths, and services.
- **`shared/emacs/`** — Emacs configuration imported by shared/home. `default.nix` assembles the sibling files, which are plain functions returning elisp strings (evaluation order is significant). Uses `emacs-pgtk` on Linux, `emacs-30` (via darwin-emacs overlay) on macOS.
- **`shared/sway/`** — Sway window manager config. `default.nix` wires `scripts.nix` (workspace.sh, wallpaper.sh, lock.sh, volume.sh, record.sh), `waybar.nix`, and `config.nix` together. Home Manager level only.
- **`hosts/local/local.nix`** — System-level desktop config: NVIDIA drivers, Sway system packages, PipeWire audio, Steam, greetd, XDG portals. Cannot be merged with shared/sway (different NixOS module layers).

### Cross-Platform Patterns

- `pkgs.stdenv.hostPlatform.isDarwin` / `pkgs.stdenv.hostPlatform.isLinux` for conditional logic in Home Manager modules
- `lib.optionals` / `lib.optionalString` / `lib.mkIf` for conditional includes
- `gitUser ? null` — optional parameter with fallback default
- `enableSecrets ? true` for NixOS, `? false` for Darwin

### Secrets (sops-nix)

- `secrets/` is a git submodule ([dotfiles-secrets](https://github.com/dscrawford/dotfiles-secrets)); clone with `--recurse-submodules` or run `git submodule update --init`
- Encryption: age recipients defined in `secrets/.sops.yaml`; downstream users point the submodule at their own repo
- Encrypted secrets: `secrets/secrets.yaml` — every non-empty top-level scalar is exported as an env var named after its uppercased key (via `secret-env-refresh` + BASH_ENV hook)
- User key location: `~/.config/sops/age/keys.txt`
- Gated by `enableSecrets` flag — disabled for Darwin and terminal-only builds

### Emacs Architecture

- Per-tmux-pane Emacs servers: socket named `emacs-<pane_id>` based on `$TMUX_PANE`
- `$INSIDE_EMACS` check prevents tmux auto-start inside Emacs eat terminals
- `emacsclient` wrapper in bashrc uses `-s $EMACS_SERVER` for pane-specific connections
- Compile history stored per-directory in `~/.emacs.d/compile-history/` (using `!` as path separator)
- All Emacs temp files redirected to `~/.emacs.d/` subdirectories: `backups/`, `auto-saves/`, `lockfiles/`

### Nix String Escaping

In `''` (multiline) strings, bash variables need `''${var}` escaping to prevent Nix interpolation. Example: `''${OUTPUTS[$i]}` in shared/sway/scripts.nix.
