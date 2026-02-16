# NixOS Configuration

Daniel's NixOS configuration using flakes for multiple systems. Yes I used Claude to make a lot of this kinda, I just told it to turn all my configs into a flake. I am horrible at documentation and would never write this much detail below.

## Systems

- **node1** - Kubernetes cluster node with iSCSI support
- **node2** - Kubernetes cluster node with iSCSI support  
- **local** - Local desktop/development machine

## Features

### Boot Management (`boot-common.nix`)
- Automatically cleans old boot entries (keeps last 5 generations)
- Weekly automatic garbage collection (removes items older than 7 days)
- Supports both GRUB and systemd-boot

### Secrets Management (sops-nix)
- Encrypted secrets using age encryption
- Configuration in `.sops.yaml`
- See `secrets/README.md` for usage instructions
- **Note:** The `secrets/` directory is gitignored and not committed

## Usage

### Initial Setup

1. Clone this repository to `~/.local/dotfiles`
2. Set up your age key for secrets (see `secrets/README.md`)
3. Create your secrets files locally (they won't be committed)

### Building Systems

```bash
# Build and switch to the configuration
sudo nixos-rebuild switch --flake .#local    # For local machine
sudo nixos-rebuild switch --flake .#node1    # For node1
sudo nixos-rebuild switch --flake .#node2    # For node2

# Test configuration without activating
sudo nixos-rebuild test --flake .#local

# Check flake for errors
nix flake check
```

### Updating Dependencies

```bash
# Update all inputs
nix flake update

# Update specific input
nix flake update nixpkgs
```

## Structure

```
.
├── flake.nix              # Main flake configuration
├── flake.lock             # Locked dependency versions
├── common.nix             # Common configuration for all systems
├── boot-common.nix        # Boot and garbage collection settings
├── .sops.yaml             # Sops encryption configuration
├── .gitignore             # Git ignore rules
├── secrets/               # Encrypted secrets
│   ├── README.md          # Secrets management documentation
│   └── secrets.yaml       # Encrypted secrets to ingest into your environment
└── hosts/
    ├── node1/             # Node 1 configuration
    ├── node2/             # Node 2 configuration
    └── local/             # Local machine configuration
        ├── local.nix
        ├── home.nix       # Home Manager configuration
        └── ...
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
- [sops-nix](https://github.com/Mic92/sops-nix)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
