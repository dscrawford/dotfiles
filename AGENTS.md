# dotfiles

Nix flake configuring NixOS hosts (desktop, terminal, three Kubernetes nodes) and
macOS via nix-darwin, with Home Manager for user config (Emacs, Sway, shell) and
sops-nix for secrets.

## Setup

```bash
git clone --recurse-submodules git@github.com:dscrawford/dotfiles.git ~/.local/dotfiles
git submodule update --init          # if cloned without --recurse-submodules
```

The age key for sops lives at `~/.config/sops/age/keys.txt` (see `secrets/README.md`).
Without it, any host built with `enableSecrets = true` fails to activate.

## Build / Run

**Run `git add -A` before every build.** Flakes only see git-tracked files, so a new
file that is untracked is invisible to the build and the error will not say so.

```bash
# NixOS desktop (Sway + Emacs + gaming). ?submodules=1 because its tailscale auth
# key lives in the secrets submodule, which a plain flake ref omits.
sudo nixos-rebuild switch --flake '.?submodules=1#local'

sudo nixos-rebuild switch --flake .#terminal              # terminal-only
sudo nixos-rebuild switch --flake '.?submodules=1#node1'  # node1..node3
sudo nixos-rebuild test --flake '.?submodules=1#local'    # build + activate, no bootloader entry

darwin-rebuild switch --flake .#terminal-darwin-arm       # macOS
darwin-rebuild switch --flake .#terminal-darwin-x86

deploy-nodes    # desktop only: build locally, switch all nodes over ssh, master first
reboot-nodes    # desktop only, interactive: rolling cordon/drain reboot
nix flake update
```

Cheap gates that do not touch the running system:

```bash
# Evaluates the whole host config (catches syntax, type, and option errors) without building.
nix eval --raw '.?submodules=1#nixosConfigurations.local.config.system.build.toplevel.drvPath'

# Build one component instead of the world — e.g. after an Emacs change.
nix build --no-link '.?submodules=1#nixosConfigurations.local.config.home-manager.users.daniel.programs.emacs.finalPackage'
```

## Test

No aggregate runner; each suite is invoked directly. `bats` is not on `PATH` — use `nix run`.

```bash
nix run nixpkgs#bats -- tests/nix/generators.bats        # generator output pinning
nix run nixpkgs#bats -- tests/hooks/prompt-router.bats tests/hooks/tool-output-filter.bats
./tests/local-llm-mcp/run.sh                             # node --test, Ollama mocked
./tests/emacs/scroll-nav-run.sh                          # ERT, elisp extracted from the nix modules
```

Single test:

```bash
nix run nixpkgs#bats -- -f "multiline" tests/hooks/tool-output-filter.bats
node --test --test-name-pattern "routes" tests/local-llm-mcp/*.test.mjs
```

Emacs suites extract their elisp with `nix eval --raw --impure --expr '(import ./shared/emacs/<mod>.nix { })'`
and run it under `emacs -Q --batch`; the whole suite is sub-second, so run all of it.

## Lint & Typecheck

No formatter or linter is enforced, and **the tree is not clean under either** —
`nixfmt --check` fails on most files and `statix check` warns on existing code.
Do not reformat files you touch; match the surrounding style instead.

The real gate is evaluation: `nix eval ...drvPath` above, then the relevant test suite.

## Code Style & Conventions

- Nix `''` strings: bash variables need `''${var}`, or Nix interpolates them — e.g.
  `''${OUTPUTS[$i]}` in `shared/sway/scripts.nix`.
- Comment only non-obvious constraints or gotchas. No banners, no change narration, no
  restating the code — that belongs in the commit message. A `comment-density` PostToolUse
  hook flags runs of 3+ comment lines.
- Many small files over few large ones: 200–400 lines typical, 800 max. Organize by
  feature, not by type.
- `shared/emacs/*.nix` modules are functions returning elisp strings, assembled in order by
  `shared/emacs/default.nix`. Evaluation order matters; `guard.nix` must stay first.
- Wrap optional-package init in `(my/guard "label" ...)`. Home Manager compiles all of
  `extraConfig` into one byte-compiled `default.el`, so an unguarded error skips every
  remaining form in the file.
- Macros that act at expansion time (e.g. `scroll-on-jump-advice-add`) run at Nix build
  time in that byte-compiled `default.el`, not at startup. Call functions instead.
- Prefer `lib.optionals` / `lib.optionalString` / `lib.mkIf` and
  `pkgs.stdenv.hostPlatform.isDarwin` / `isLinux` for conditionals in cross-platform
  Home Manager modules.

## Architecture

```
flake.nix          inputs + host list; delegates to lib/
lib/               mkServer / mkLocal / mkDarwin builders, exported as flake `lib`
hosts/<host>/      per-machine config + generated hardware-configuration.nix
shared/            modules shared across hosts
  home/            cross-platform Home Manager (bash, git, tmux, ssh, ollama, …)
  emacs/           elisp modules assembled by default.nix
  sway/            Sway + waybar, Home Manager level only
pkgs/              locally packaged software (local-llm-mcp, ruflo, claude-code, …)
claude/            source for ~/.claude — hooks, agents, rules, skills, settings.json
tests/             bats + node + ERT suites
docs/              research notes and runbooks
secrets/           git submodule (dotfiles-secrets), sops-encrypted
```

Three builders in `lib/`, exported as the flake's `lib` for external flakes to reuse:

- `mkServer` — NixOS servers. Params `hostname`, `ip`, `netInterface`, `extraModules`.
- `mkLocal` — NixOS desktop/terminal with Home Manager. Params `hostname`, `username`,
  `system`, `gitUser` (`? null`), `enableSecrets` (`? true`), `homeModules`, `extraModules`.
- `mkDarwin` — macOS via nix-darwin. Same params as `mkLocal`, plus required `system`, and
  `enableSecrets ? false`.

```
mkServer: common.nix → server-common.nix → users.nix → boot-common.nix → host
mkLocal:  common.nix → boot-common.nix → local-common.nix → local.nix → Home Manager
mkDarwin: darwin-common.nix → Home Manager
```

`node1`–`node3` go through the `kubeNode` helper in `flake.nix`, which adds
`kubernetes.nix`, `kube-cert-renew.nix`, `kube-stale-mount-recovery.nix`, `iscsi.nix` plus
the host's hardware and boot files. `local` adds `shared/sway`, `shared/gaming.nix`, and
`shared/easyeffects.nix` as Home Manager modules; terminal configs use only `shared/home`.

`shared/emacs/` uses `emacs-pgtk` on Linux and `emacs-30` (darwin-emacs overlay) on macOS.
`shared/sway/default.nix` wires `scripts.nix` (workspace, wallpaper, lock, volume, record),
`waybar.nix`, and `config.nix`.

System-level and Home-Manager-level config cannot be merged (different module layers):
`hosts/local/local.nix` holds NVIDIA, PipeWire, greetd, Steam, XDG portals; `shared/sway/`
holds the user-level Sway config.

### Emacs runtime

- One server per tmux pane, socket `emacs-$TMUX_PANE`; the `emacsclient` wrapper in bashrc
  passes `-s $EMACS_SERVER`.
- An `$INSIDE_EMACS` check keeps tmux from auto-starting inside Emacs `eat` terminals.
- Compile history is per-directory under `~/.emacs.d/compile-history/`, `!` as the path
  separator. Backups, auto-saves, and lockfiles are all redirected under `~/.emacs.d/`.

### Secrets (sops-nix)

- `secrets/` is a submodule of [dotfiles-secrets](https://github.com/dscrawford/dotfiles-secrets);
  age recipients live in `secrets/.sops.yaml`, the user key in `~/.config/sops/age/keys.txt`.
- Every non-empty top-level scalar in `secrets/secrets.yaml` becomes an env var named after
  its uppercased key, via `secret-env-refresh` plus a `BASH_ENV` hook.
- Gated by `enableSecrets` — off for Darwin and terminal-only builds.

## Boundaries / Do Not Touch

- `secrets/` — separate private repo, sops-encrypted. Never decrypt into the worktree,
  never commit plaintext.
- `hosts/*/hardware-configuration.nix` — machine-generated by `nixos-generate-config`.
- `flake.lock` — change only via `nix flake update`.
- `~/.claude/**` — generated read-only store symlinks. Edit `claude/` and rebuild instead;
  direct edits are silently reverted on next activation.
- `result`, `result-*`, `ruvector.db`, `.swarm/`, `.claude-flow/`, `.agent-shell/` —
  build output and agent runtime state, gitignored.

## Commits & PRs

- Conventional commits, enforced by the `commit-guard` PreToolUse hook: subject
  `<type>[(scope)]: <description>` with type in `feat|fix|refactor|docs|test|chore|perf|ci|build|style`,
  subject ≤72 chars, whole message ≤10 lines. `--amend`, `--fixup`, `-F` bypass the check.
- No attribution or co-author footer in commit messages.
- Subject describes the change in the repo's voice: state what now holds, not what you did.
- For a PR, diff the whole branch (`git diff main...HEAD`), not just the last commit.

## Gotchas

- `tests/emacs/run.sh` currently **fails**: it calls `agent-shell.nix` with only `pkgs`,
  but that module has required `lib` and `config` arguments since commit `d857fa9`. Fix the
  runner's `nix eval` args before trusting it. `tests/emacs/scroll-nav-run.sh` is unaffected.
- Omitting `?submodules=1` on `local` or the nodes yields a confusing failure about a
  missing tailscale key file, not a submodule error.
- One Emacs server per tmux pane (socket `emacs-$TMUX_PANE`), so init cost is paid per pane
  — eager `require` of a heavy package is measurably worse here than in a single-instance setup.
- `deploy-nodes` and `reboot-nodes` act on the live cluster and are interactive; never run
  them unattended.
- Renaming a key in `secrets/secrets.yaml` silently renames the exported env var.
