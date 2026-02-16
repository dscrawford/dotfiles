# Local Desktop Configuration

This directory contains the NixOS configuration for the local desktop computer.

## Structure

```
hosts/local/
├── README.md                    # This file
├── hardware-configuration.nix   # Auto-generated hardware config
├── local-common.nix             # Overrides for common.nix (disables server features)
├── local.nix                    # Desktop-specific configuration
└── home.nix                     # Home Manager user configuration
```

## Features

### Desktop Environment
- **Window Manager**: i3
- **Desktop Manager**: XFCE (minimal, no window manager)
- **Display Manager**: Default session is xfce+i3
- **Graphics**: NVIDIA proprietary driver (version 590.48.01)

### Audio
- PipeWire with ALSA, PulseAudio, and JACK support
- 32-bit ALSA support for compatibility

### Gaming
- Steam with gamemode support
- ALVR for VR (Quest/SteamVR)
- Xbox controller support (xpadneo)
- Extensive udev rules for VR headsets and Steam controllers

### Hardware Support
- NVIDIA GPU with CUDA toolkit
- Bluetooth with A2DP support
- Docker virtualization
- NTFS filesystem support (dual-boot friendly)

### Desktop Applications
- Flatpak support with GTK portal
- GNOME Keyring for credential management
- Printing support (CUPS)
- Video capture tools (v4l-utils, guvcview)

## Building

To build the configuration without applying it:

```bash
nix build .#nixosConfigurations.local.config.system.build.toplevel
```

## Applying the Configuration

⚠️ **Important**: Always test build first before switching!

```bash
# From the dotfiles directory
sudo nixos-rebuild switch --flake .#local
```

## Differences from Server Configuration

The local configuration differs from the server configuration in several ways:

1. **No Server Services**: Disabled fail2ban, tailscale, certmgr
2. **Firewall**: Disabled for desktop convenience (can be re-enabled if needed)
3. **SSH**: Allows password authentication and X11 forwarding
4. **No NFS Server**: Client support disabled (no kubernetes/longhorn requirements)
5. **Desktop Stack**: Full XFCE + i3 + NVIDIA + gaming support

## Customization

### Adding/Removing Features

Edit `hosts/local/local.nix` to modify desktop-specific settings:
- Gaming software (Steam, ALVR)
- Desktop environment components
- Hardware drivers
- Application packages

### Overriding Common Settings

Edit `hosts/local/local-common.nix` to override settings from `common.nix`:
- Network configuration
- Security settings
- System services

### User Configuration (Home Manager)

Edit `hosts/local/home.nix` to manage user-level configuration:
- User packages (browsers, IDEs, games)
- Dotfiles (bash, git, emacs, tmux)
- Development tools (direnv, language servers)
- Services (gpg-agent)

Home Manager configurations are per-user and rebuild automatically with the system.

### Hardware Changes

If you change hardware, regenerate the hardware configuration:

```bash
sudo nixos-generate-config --show-hardware-config > hosts/local/hardware-configuration.nix
```

## Home Manager

Home Manager is integrated as a NixOS module, meaning user configurations are managed alongside system configurations.

### What's Included

The `home.nix` file includes:

**Applications:**
- Browsers: Firefox, Chromium, Brave
- Development: PyCharm OSS, kubectl, Python tools
- Communication: Discord, Vesktop
- Media: Spotify, VLC, Pavucontrol
- Gaming: Lutris, Wine, Prismlauncher, Heroic

**Development Tools:**
- Emacs with packages (magit, nix-mode, markdown-mode, etc.)
- Git with configuration
- Tmux with custom config
- Direnv with nix-direnv
- Bash with custom PATH and tmux auto-start

**Services:**
- GPG agent with SSH support

### Managing Dotfiles

By default, dotfiles are managed by Home Manager's program options (e.g., `programs.git`, `programs.bash`). 

To add custom dotfiles to the repository:

1. Create a directory in `hosts/local/` (e.g., `hosts/local/dotfiles/`)
2. Add your files there
3. Reference them in `home.nix`:
   ```nix
   home.file.".bashrc".source = ./dotfiles/bashrc;
   ```

### SOPS Secrets (Optional)

To enable SOPS for secret management, uncomment the SOPS section in `home.nix` and:

1. Install age: `nix-shell -p age`
2. Generate a key: `age-keygen -o ~/.config/sops/age/keys.txt`
3. Create `hosts/local/secrets.yaml` with your secrets
4. Encrypt: `sops hosts/local/secrets.yaml`

### Managing .emacs.d

The `.emacs.d` directory can be managed in three ways:

1. **Add to repository** (recommended for reproducibility):
   ```bash
   cp -r ~/.emacs.d hosts/local/emacs.d
   git add hosts/local/emacs.d
   ```
   Then uncomment and update in `home.nix`:
   ```nix
   home.file.".emacs.d".source = ./emacs.d;
   ```

2. **Keep it separate** (current default): Manage manually outside of Nix

3. **Use impure build**: Keep the absolute path and build with `--impure`

## Module Loading Order

The mkLocal function in flake.nix loads modules in this order:

1. `common.nix` - Base system configuration
2. `local-common.nix` - Override server-oriented settings
3. `local.nix` - Desktop-specific configuration  
4. `hardware-configuration.nix` - Hardware detection
5. `home-manager` module - User-level configuration for specified user

Later modules can override settings from earlier ones using `lib.mkForce`.

## Maintenance

### Updating Hardware Configuration

If you upgrade hardware (CPU, GPU, storage), update the hardware configuration:

```bash
sudo nixos-generate-config --show-hardware-config > hosts/local/hardware-configuration.nix
git add hosts/local/hardware-configuration.nix
```

### Updating NVIDIA Driver

The NVIDIA driver version is pinned in `local.nix`. To update:

1. Find the new driver version at https://nixos.wiki/wiki/Nvidia
2. Update the version and sha256 hashes in `local.nix`
3. Test build before switching

### VPN Configuration

OpenVPN is configured but disabled by default. To use:

1. Place your .ovpn file at `/root/nixos/openvpn/homeVPN.ovpn`
2. Start manually: `sudo systemctl start openvpn-homeVPN`
3. To auto-start, change `autoStart = true` in `local.nix`

## Troubleshooting

### Build Fails with "path does not exist"

Make sure all new files are added to git:

```bash
git add hosts/local/
```

Nix flakes only see files tracked by git.

### NVIDIA Driver Issues

If you have display issues after switching:

1. Check kernel compatibility with your NVIDIA driver version
2. Try the latest driver: `hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.latest;`
3. Check logs: `journalctl -b | grep nvidia`

### Steam/Gaming Issues

Ensure 32-bit support is enabled:
- `hardware.graphics.enable32Bit = true`
- `services.pipewire.alsa.support32Bit = true`

### Docker Permission Issues

Add your user to the docker group and reboot:

```bash
sudo usermod -aG docker $USER
```
