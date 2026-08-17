# shared/home/packages.nix
# Cross-platform package declarations for Home Manager
{ lib, pkgs, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;

  claude-agent-acp = pkgs.callPackage ../../pkgs/claude-agent-acp {};
  rufloPackage = pkgs.callPackage ../../pkgs/ruflo {};
in
{
  home.packages = with pkgs; [
    # Fonts
    nerd-fonts.symbols-only

    # Utilities
    zip
    unzip
    cachix
    virtualenv
    docker-compose
    atool
    httpie
    yq
    gnupg
    cacert
    sops
    lynx
    pandoc

    # Python
    (python3.withPackages (ps: with ps; [
      # Core data science
      numpy pandas scipy scikit-learn matplotlib seaborn plotly
      # Jupyter
      jupyter ipykernel debugpy
      # File formats
      openpyxl xlsxwriter fastparquet pyarrow
      # Cloud / storage
      fsspec s3fs boto3
      # Databricks
      databricks-sql-connector
      # Tooling
      pip black requests
    ]))
    nbstripout
    uv
    poetry

    # Linting tools
    ruff
    pyright
    statix
    nil
    nixfmt

    # Rust
    rust-analyzer

    # C/C++
    clang-tools

    # JavaScript/TypeScript
    typescript
    typescript-language-server

    # Development tools
    openssl
    curl
    gcc
    redis
    ripgrep
    fd
    dnsutils
    jq
    gh

    # Cloud & Kubernetes
    kubectl
    awscli2
    kubernetes-helm
    argo-rollouts
    argocd

    # Database
    postgresql

    # IDE
    (pkgs.callPackage ../../pkgs/claude-code {})
    rufloPackage
    claude-agent-acp
    (pkgs.callPackage ../../pkgs/local-llm-mcp {})
    gemini-cli
    github-copilot-cli
    nodejs  # npx, for emacs-mcp-server

    # Business / Productivity CLIs
    jira-cli-go
    (pkgs.callPackage ../../pkgs/cli-microsoft365 {})
    (pkgs.callPackage ../../pkgs/confluence-cli {})
    (pkgs.callPackage ../../pkgs/slack-cli {})

    # goose-cli  # disabled: broken in nixpkgs-unstable (Rust recursion limit)
  ] ++ lib.optionals isDarwin [
    docker
    docker-buildx
    pngpaste  # clipboard image paste for agent-shell (macOS wl-paste)

  ] ++ lib.optionals isLinux [
    xclip
    zsync
    appstream
    appimage-run
    simplescreenrecorder
    nghttp2
    libidn2
    rtmpdump
    libpsl
    krb5
    keyutils

    # GUI Applications (Linux)
    firefox
    chromium
    brave
    spotify
    gimp
    vlc
    mpv
    pwvucontrol
    alacritty
    # Corrupted/garbled UI regions on NVIDIA+Wayland. settings.json's
    # chromiumSwitches only accepts 13 Windows/macOS keys, so this override is
    # the only way to pass a flag. Electron 37 also negotiates dmabuf v3 while
    # sway offers v5, so it never gets modifier feedback.
    (pkgs.discord.override { commandLineArgs = "--disable-gpu-rasterization"; })
    fastfetch
    # pycharm-oss dropped: unmaintained in nixpkgs and flagged insecure
    # (NIXPKGS-2026-2269) after the 2026-08 channel bump.
    jetbrains.pycharm
  ];
}
