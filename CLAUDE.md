# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# NixOS desktop (full: Sway + Emacs + gaming)
sudo nixos-rebuild switch --flake .#local

# NixOS terminal-only
sudo nixos-rebuild switch --flake .#terminal

# NixOS servers
sudo nixos-rebuild switch --flake .#node1
sudo nixos-rebuild switch --flake .#node2

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
mkLocal:  common.nix → boot-common.nix → local-common.nix → local.nix → Home Manager(home.nix + optional modules)
mkDarwin: darwin-common.nix → Home Manager(home.nix + optional modules)
```

Desktop (`local`) adds `sway.nix` and `gaming.nix` as extra Home Manager modules. Terminal configs use only `home.nix`.

### Key Files

- **`shared/home.nix`** — Cross-platform (Linux/macOS) Home Manager config. Uses `isDarwin`/`isLinux` conditionals for platform-specific packages, paths, and services.
- **`shared/emacs.nix`** — Emacs configuration imported by home.nix. Uses `emacs-pgtk` on Linux, `emacs-30` (via darwin-emacs overlay) on macOS.
- **`shared/sway.nix`** — Sway window manager dotfiles, scripts (workspace.sh, wallpaper.sh, lock.sh, volume.sh), and Waybar config. Home Manager level only.
- **`hosts/local/local.nix`** — System-level desktop config: NVIDIA drivers, Sway system packages, PipeWire audio, Steam, greetd, XDG portals. Cannot be merged with shared/sway.nix (different NixOS module layers).

### Cross-Platform Patterns

- `pkgs.stdenv.isDarwin` / `pkgs.stdenv.isLinux` for conditional logic in Home Manager modules
- `lib.optionals` / `lib.optionalString` / `lib.mkIf` for conditional includes
- `gitUser ? null` — optional parameter with fallback default
- `enableSecrets ? true` for NixOS, `? false` for Darwin

### Secrets (sops-nix)

- Encryption: age keys defined in `.sops.yaml`
- Encrypted secrets: `secrets/secrets.yaml`
- User key location: `~/.config/sops/age/keys.txt`
- Gated by `enableSecrets` flag — disabled for Darwin and terminal-only builds

### Emacs Architecture

- Per-tmux-pane Emacs servers: socket named `emacs-<pane_id>` based on `$TMUX_PANE`
- `$INSIDE_EMACS` check prevents tmux auto-start inside Emacs eat terminals
- `emacsclient` wrapper in bashrc uses `-s $EMACS_SERVER` for pane-specific connections
- Compile history stored per-directory in `~/.emacs.d/compile-history/` (using `!` as path separator)
- All Emacs temp files redirected to `~/.emacs.d/` subdirectories: `backups/`, `auto-saves/`, `lockfiles/`

### Nix String Escaping

In `''` (multiline) strings, bash variables need `''${var}` escaping to prevent Nix interpolation. Example: `''${OUTPUTS[$i]}` in sway.nix scripts.
