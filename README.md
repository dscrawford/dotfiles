# NixOS Configuration

Daniel's NixOS configuration using flakes for multiple systems. Yes I used Claude to make a lot of this kinda, I just told it to turn all my configs into a flake. I am horrible at documentation and would never write this much detail below.

## Systems

- **local** — NixOS desktop (Sway + Emacs GUI + gaming)
- **terminal** — NixOS terminal-only (x86)
- **terminal-arm** — NixOS terminal-only (aarch64)
- **terminal-darwin-arm** — macOS Apple Silicon
- **terminal-darwin-x86** — macOS Intel
- **node1**, **node2** — Kubernetes cluster nodes with iSCSI

## Features

### Boot Management (`boot-common.nix`)
- Automatically cleans old boot entries (keeps last 5 generations)
- Weekly automatic garbage collection (removes items older than 7 days)
- Supports both GRUB and systemd-boot

### Secrets Management (sops-nix)
- Encrypted secrets using age encryption
- Configuration in `.sops.yaml`
- Encrypted secrets stored in `secrets/secrets.yaml` (safe to commit — decryption requires age key)

## Usage

### NixOS Setup

1. Clone this repository to `~/.local/dotfiles`
2. Set up your age key for secrets (see `secrets/README.md`)
3. Build:

```bash
# Desktop (Sway + Emacs + gaming)
sudo nixos-rebuild switch --flake .#local

# Terminal-only
sudo nixos-rebuild switch --flake .#terminal

# Servers
sudo nixos-rebuild switch --flake .#node1
sudo nixos-rebuild switch --flake .#node2

# Test without activating
sudo nixos-rebuild test --flake .#local
```

### macOS (Darwin) Setup

#### 1. Install Nix with Determinate Installer

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

#### 2. Create your machine's flake

Create a new flake that imports this repo. Replace the values marked with `# <-- CHANGE` below.

The key in `darwinConfigurations` must match your machine's hostname so that `--flake .` works without specifying a config name. Run `scutil --get LocalHostName` to find it.

```nix
# flake.nix
{
  inputs = {
    base-dotfiles.url = "github:dscrawford/dotfiles";
  };

  outputs = { self, base-dotfiles }:
  {
    darwinConfigurations.My-MacBook-Pro = base-dotfiles.lib.mkDarwin {  # <-- CHANGE to your hostname (scutil --get LocalHostName)
      hostname = "My-MacBook-Pro";  # <-- CHANGE to match above
      username = "myuser";          # <-- CHANGE to your macOS username (whoami)
      system = "aarch64-darwin";    # <-- CHANGE to "x86_64-darwin" for Intel Macs
      gitUser = {                   # <-- CHANGE to your git identity
        name = "My Name";
        email = "my@email.com";
      };
    };
  };
}
```

`mkDarwin` also accepts these optional parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `gitUser` | `null` | Git identity attrset `{ name, email }` (uses repo default if null) |
| `enableSecrets` | `false` | Enable sops-nix secret management |
| `homeModules` | `[ ./shared/home.nix ]` | Home Manager modules to import |
| `extraModules` | `[]` | Additional nix-darwin modules (certificates, custom services, etc.) |

Use `extraModules` to add machine-specific nix-darwin config — for example, corporate certificates or extra services:

```nix
darwinConfigurations.My-MacBook-Pro = base-dotfiles.lib.mkDarwin {
  hostname = "My-MacBook-Pro";
  username = "myuser";
  system = "aarch64-darwin";
  extraModules = [
    ./certs.nix  # custom CA certificates, proxy config, etc.
  ];
};
```

#### 3. Build and switch

```bash
# First run — git add so the flake can see all files
git add -A

# Build (nix-darwin must be bootstrapped on first run)
nix run nix-darwin -- switch --flake .  # first time only

# Subsequent rebuilds
darwin-rebuild switch --flake .
```

### Updating Dependencies

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake update nixpkgs
```

> **Note:** Always run `git add -A` before rebuilding — Nix flakes only see tracked files.

## Structure

```
.
├── flake.nix                # Builder functions (mkServer, mkLocal, mkDarwin)
├── shared/
│   ├── common.nix           # Common config for all NixOS systems
│   ├── home.nix             # Cross-platform Home Manager (Linux + macOS)
│   ├── emacs.nix            # Emacs config (pgtk on Linux, emacs-30 on macOS)
│   ├── sway.nix             # Sway window manager (Home Manager module)
│   ├── gaming.nix           # Gaming packages (gamescope, etc.)
│   ├── darwin-common.nix    # macOS system config (nix-darwin)
│   ├── local-common.nix     # NixOS desktop/terminal shared config
│   ├── server-common.nix    # NixOS server shared config
│   ├── boot-common.nix      # Boot and garbage collection
│   ├── kubernetes.nix       # Kubernetes node config
│   ├── users.nix            # User account definitions
│   └── iscsi.nix            # iSCSI storage config
├── hosts/
│   ├── local/               # NixOS desktop (NVIDIA, Sway, PipeWire)
│   ├── node1/               # Kubernetes node 1
│   └── node2/               # Kubernetes node 2
└── secrets/                 # Encrypted secrets (sops-nix, gitignored)
```

## Important Notes

### Boot Configuration
The boot-common.nix module is automatically imported by all systems and handles:
- Limiting boot menu entries to prevent /boot partition from filling up
- Regular cleanup of old Nix store generations

## Maintenance

### Cleaning Up

The configuration includes automatic cleanup, but you can also manually clean:

```bash
# Remove old generations
sudo nix-collect-garbage --delete-older-than 7d

# Remove all old generations (keeps only current)
sudo nix-collect-garbage -d

# Clean up boot entries
sudo nixos-rebuild switch --flake .#local
```

### Checking System Status

```bash
# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# See what's using disk space
nix path-info --recursive --size /run/current-system | sort -nk2
```

## References

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [nix-darwin](https://github.com/LnL7/nix-darwin)
- [Determinate Nix Installer](https://github.com/DeterminateSystems/nix-installer)
- [sops-nix](https://github.com/Mic92/sops-nix)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
