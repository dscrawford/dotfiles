# dotfiles

Nix flake for NixOS hosts (desktop `local`, `terminal`, `terminal-arm`, Kubernetes
nodes `node1`–`node3`) and macOS (nix-darwin), with Home Manager and sops-nix.

## Setup

```bash
git clone --recurse-submodules git@github.com:dscrawford/dotfiles.git ~/.local/dotfiles
git submodule update --init          # if cloned without --recurse-submodules
```

The sops age key is `~/.config/sops/age/keys.txt` (see `secrets/README.md`); without it
any host with `enableSecrets = true` fails to activate.

## Build / Run

**Run `git add -A` before every build.** Flakes ignore untracked files, and the error
won't say so.

```bash
# ?submodules=1 is required for local and the nodes: their tailscale key is in secrets/.
sudo nixos-rebuild switch --flake '.?submodules=1#local'  # desktop
sudo nixos-rebuild switch --flake .#terminal              # terminal-only
sudo nixos-rebuild switch --flake '.?submodules=1#node1'  # node1..node3
sudo nixos-rebuild test --flake '.?submodules=1#local'    # activate, no bootloader entry
darwin-rebuild switch --flake .#terminal-darwin-arm       # or terminal-darwin-x86

deploy-nodes    # desktop only: build locally, switch all nodes over ssh, master first
reboot-nodes    # desktop only, interactive: rolling cordon/drain reboot
nix flake update
```

Cheap gates that don't touch the running system:

```bash
# Evaluates the whole host config (syntax, type, option errors) without building.
nix eval --raw '.?submodules=1#nixosConfigurations.local.config.system.build.toplevel.drvPath'
# Build one component, e.g. after an Emacs change.
nix build --no-link '.?submodules=1#nixosConfigurations.local.config.home-manager.users.daniel.programs.emacs.finalPackage'
```

## Test

No aggregate runner. `bats` is not on `PATH`; use `nix run`.

```bash
nix run nixpkgs#bats -- tests/nix/generators.bats   # generator output pinning
nix run nixpkgs#bats -- tests/hooks/                # claude/hooks/*.sh
./tests/local-llm-mcp/run.sh                        # node --test, Ollama mocked
./tests/ruflo-mcp/run.sh                            # node --test, fake MCP server
./tests/scooter/emacs-e2e.sh                        # agent-shell -> scooter acp -> fake Scooter
./tests/emacs/scroll-nav-run.sh                     # ERT
./tests/emacs/kubed-window-run.sh                   # ERT

nix run nixpkgs#bats -- -f "multiline" tests/hooks/tool-output-filter.bats   # single test
node --test --test-name-pattern "routes" tests/local-llm-mcp/*.test.mjs
```

ERT suites extract elisp via `nix eval --raw --impure --expr '(import ./shared/emacs/<mod>.nix { … })'`
and run `emacs -Q --batch`; they take under a second, so run them all.

## Lint

No formatter or linter is enforced, and the tree fails both `nixfmt --check` and
`statix check`. Don't reformat files you touch; match surrounding style. The real gate
is the `nix eval …drvPath` above plus the relevant tests.

## Code Style

- In Nix `''` strings, escape bash variables as `''${var}` (e.g. `''${OUTPUTS[$i]}` in
  `shared/sway/scripts.nix`), or Nix interpolates them.
- Code explains itself; a comment is a last resort for a workaround or external
  constraint. No inline comments, banners, change narration, or restating code; that
  goes in the commit message. The `comment-density` hook challenges each added comment
  (advisory); the `comment-scout` agent proposes the rewrite that removes it.
- Many small files, organized by feature: 200–400 lines typical, 800 max.
- `shared/emacs/*.nix` are functions returning elisp, assembled in order by
  `shared/emacs/default.nix`; `guard.nix` must stay first.
- Wrap optional-package init in `(my/guard "label" ...)`. Home Manager byte-compiles
  all `extraConfig` into one `default.el`, so an unguarded error skips every later form.
- Expansion-time macros (e.g. `scroll-on-jump-advice-add`) run at Nix build time, not
  startup. Call functions instead.
- In cross-platform Home Manager modules use `lib.optionals` / `lib.optionalString` /
  `lib.mkIf` with `pkgs.stdenv.hostPlatform.isDarwin` / `isLinux`.

## Architecture

```
flake.nix     inputs + host list; delegates to lib/
lib/          mkServer / mkLocal / mkDarwin, exported as flake `lib`
hosts/<host>/ per-machine config + generated hardware-configuration.nix
shared/       cross-host modules; home/ (Home Manager), emacs/, sway/ (HM only)
pkgs/         local packages (local-llm-mcp, ruflo, ruflo-mcp, claude-code, …)
claude/       source for ~/.claude: hooks, agents, rules, skills, settings.json
tests/        bats + node + ERT suites
docs/         research notes and runbooks
secrets/      git submodule (dotfiles-secrets), sops-encrypted
```

- `mkServer {hostname, ip, netInterface, extraModules}`:
  common → server-common → users → boot-common → nix-gc → host.
- `mkLocal {hostname, username, system, gitUser ? null, enableSecrets ? true,
  homeModules, extraModules}`: common → boot-common → nix-gc → local-common →
  `hosts/local/local.nix` → Home Manager.
- `mkDarwin`: same params, `system` required, `enableSecrets ? false`;
  darwin-common → Home Manager.

`node1`–`node3` use `kubeNode` in `flake.nix`, which adds `kubernetes.nix`,
`kube-*.nix`, `iscsi.nix` and the host's hardware/boot files. `kubernetes.nix` registers
`crun` as a second containerd runtime for the KubeServer repo's `RuntimeClass crun`
(Scooter sandboxes): deploy the nodes before pushing a manifest that uses it. `local`
adds `shared/sway`, `gaming.nix`, `easyeffects.nix` as Home Manager modules.

System and Home Manager config are separate layers: `hosts/local/` holds NVIDIA,
PipeWire, greetd, Steam, portals; `shared/sway/` holds user-level Sway.

Emacs is `emacs-pgtk` on Linux, `emacs-30` (darwin-emacs) on macOS. One server per tmux
pane (socket `emacs-$TMUX_PANE`), so init cost is paid per pane: an eager `require` of
a heavy package costs more here than usual.

Every non-empty top-level scalar in `secrets/secrets.yaml` becomes an env var named
after its uppercased key (`secret-env-refresh` + `BASH_ENV`), so renaming a key renames
the var. Gated by `enableSecrets`, off for Darwin and terminal builds.

## Do Not Touch

- `secrets/`: separate private repo. Never decrypt into the worktree or commit plaintext.
- `hosts/*/hardware-configuration.nix`: generated by `nixos-generate-config`.
- `flake.lock`: change only via `nix flake update`.
- `~/.claude/**`: read-only store symlinks, reverted on activation. Edit `claude/`.
- `result*`, `ruvector.db`, `.swarm/`, `.claude-flow/`, `.agent-shell/`: gitignored state.

## Commits & PRs

- Conventional commits (`commit-guard` hook): `<type>[(scope)]: <description>`, type in
  `feat|fix|refactor|docs|test|chore|perf|ci|build|style`, subject ≤72 chars, message
  ≤10 lines. `--amend`, `--fixup`, `-F` bypass the check.
- No attribution or co-author footer.
- Subject states what now holds, not what you did.
- PR bodies show, not tell (`pr-guard` hook): a code block, CLI output, or screenshot is
  required; prose ≤100 words.
- Review the whole branch (`git diff main...HEAD`), not just the last commit.

## Gotchas

- `session-guard` denies `kill`/`pkill`/`killall` reaching sway, Xwayland, greetd,
  systemd or emacs unless the agent started it, plus `swaymsg exit` (without a private
  socket), `loginctl terminate-*`/`kill-*`, `systemctl --user exit`. Kill helpers by `$!`.
- `tests/emacs/run.sh` **fails**: it passes only `pkgs` to `agent-shell.nix`, which has
  required `lib` and `config` since `d857fa9`. Fix its `nix eval` args before trusting it.
- Omitting `?submodules=1` on `local` or the nodes fails with a missing tailscale key
  file, not a submodule error.
- `deploy-nodes` and `reboot-nodes` hit the live cluster and are interactive; never run
  them unattended.
- MCP clients must launch ruflo as `ruflo-mcp` (the supervisor), not `ruflo mcp start`.
  `pkgs/ruflo` pins `nodejs_22`: node 24.19 aborts better-sqlite3 12.x during GC
  (`docs/ruflo-mcp-crash-research.md`).
