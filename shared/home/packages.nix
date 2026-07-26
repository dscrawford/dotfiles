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
    pandoc  # Markdown/document conversion (markdown-mode preview, ox-pandoc)

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
    ruff           # Python linter
    pyright        # Python language server
    statix         # Nix linter
    nil            # Nix language server
    nixfmt         # Nix formatter

    # Rust
    rust-analyzer

    # C/C++
    clang-tools  # clangd language server

    # JavaScript/TypeScript
    typescript
    typescript-language-server

    # Development tools
    openssl
    curl
    gcc
    redis
    ripgrep    # rg — fast search (used by Claude Code)
    fd         # fd — fast find (used by Claude Code)
    dnsutils   # dig, nslookup, nsupdate
    jq         # JSON processing
    gh         # GitHub CLI (PRs, issues, gh api)

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
    gemini-cli
    github-copilot-cli
    nodejs  # Provides npx for keegancsmith/emacs-mcp-server and copilot.el

    # Business / Productivity CLIs
    jira-cli-go                                        # Jira CLI (Go)
    (pkgs.callPackage ../../pkgs/cli-microsoft365 {})     # Microsoft 365 CLI (Outlook, Teams, SharePoint)
    (pkgs.callPackage ../../pkgs/confluence-cli {})        # Confluence CLI
    (pkgs.callPackage ../../pkgs/slack-cli {})             # Slack CLI

    # Other
    # goose-cli  # disabled: broken in nixpkgs-unstable (Rust recursion limit)
  ] ++ lib.optionals isDarwin [
    docker
    docker-buildx
    pngpaste  # Clipboard image paste for agent-shell (macOS equivalent of wl-paste)

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
    pwvucontrol # PipeWire-native mixer with per-app volume (pavucontrol successor)
    alacritty
    discord
    fastfetch
    jetbrains.pycharm-oss
  ];
}
