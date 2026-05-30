# shared/home.nix
# Home Manager configuration (cross-platform: Linux and macOS)
{ config, lib, pkgs, username, gitUser ? null, enableSecrets ? false, claudeSkills ? {}, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isLinux = pkgs.stdenv.isLinux;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";

  # Secret-to-environment-variable mapping for sops-nix
  # Each entry: { secret = "sops_key"; env = "ENV_VAR_NAME"; }
  # Secrets with empty values in sops YAML are silently skipped at shell init.
  secretEnvVars = [
    # AI / IDE
    { secret = "anthropic_api_key"; env = "ANTHROPIC_API_KEY"; desc = "Anthropic API key for Claude Code and Claude API access"; }
    { secret = "gemini_api_key";    env = "GEMINI_API_KEY";    desc = "Google Gemini API key for Gemini CLI"; }
    # Research MCP servers (firecrawl + exa) for the deep-research skill
    { secret = "firecrawl_api_key"; env = "FIRECRAWL_API_KEY"; desc = "Firecrawl API key for the firecrawl MCP server (web scrape/search/crawl)"; }
    { secret = "exa_api_key";       env = "EXA_API_KEY";       desc = "Exa API key for the exa MCP server (web/research search)"; }
    # Jira — issue tracking and project management (jira-cli-go)
    { secret = "jira_api_token";    env = "JIRA_API_TOKEN";    desc = "Atlassian API token for jira-cli (issue create/view/search)"; }
    # Confluence — wiki and documentation (confluence-cli)
    { secret = "confluence_domain";    env = "CONFLUENCE_DOMAIN";    desc = "Atlassian domain (e.g. myorg.atlassian.net) for confluence-cli"; }
    { secret = "confluence_email";     env = "CONFLUENCE_EMAIL";     desc = "Atlassian account email for confluence-cli basic auth"; }
    { secret = "confluence_api_token"; env = "CONFLUENCE_API_TOKEN"; desc = "Atlassian API token for confluence-cli (page read/create/search)"; }
    # Slack — team messaging (slack-cli)
    { secret = "slack_bot_token";   env = "SLACK_BOT_TOKEN";   desc = "Slack bot token (xoxb-...) for sending messages and reading channels"; }
    # Microsoft 365 — Outlook, Teams, SharePoint, OneDrive (m365 CLI)
    { secret = "m365_tenant_id";     env = "M365_TENANT_ID";     desc = "Azure AD tenant ID for Microsoft 365 CLI authentication"; }
    { secret = "m365_client_id";     env = "M365_CLIENT_ID";     desc = "Azure app registration client ID for Microsoft 365 CLI"; }
    { secret = "m365_client_secret"; env = "M365_CLIENT_SECRET"; desc = "Azure app registration client secret for Microsoft 365 CLI"; }
  ];

  secretsFile = "${homeDir}/.local/dotfiles/secrets/secrets.yaml";

  # Generate bash export lines from a single `sops -d | yq` decryption.
  secretExportLines = ''
    # Decrypt secrets once; silently skip if age key or file is unavailable
    _sops_yaml="$(sops -d ${secretsFile} 2>/dev/null)" || _sops_yaml=""
    if [ -n "$_sops_yaml" ]; then
  '' + lib.concatMapStringsSep "\n" (entry: ''
      # ${entry.desc}
      _val="$(echo "$_sops_yaml" | yq -r '.${entry.secret} // empty')"
      [ -n "$_val" ] && export ${entry.env}="$_val"'') secretEnvVars + ''

      unset _val
    fi
    unset _sops_yaml'';
in
{
  # Basic user info
  home.username = username;
  home.homeDirectory = homeDir;
  home.stateVersion = "23.05";

  # Modular configs
  imports = [
    ./emacs.nix
    ./home/packages.nix
    ./home/skills.nix
  ];

  # Dotfiles and configuration files
  home.file = {
    # MCP server config for Claude Code (keegancsmith/emacs-mcp-server)
    ".claude/.mcp.json".text = builtins.toJSON {
      mcpServers = {
        emacs-mcp = {
          command = "npx";
          args = [ "-y" "@keegancsmith/emacs-mcp-server" ];
        };
        ruflo = {
          command = "ruflo";
          args = [ "mcp" "start" ];
        };
        # Research MCP servers for the deep-research skill. API keys are read
        # from the environment (exported from sops by secretExportLines) via
        # Claude Code's ${VAR} expansion, so no secrets land in the Nix store.
        firecrawl = {
          command = "npx";
          args = [ "-y" "firecrawl-mcp" ];
          env.FIRECRAWL_API_KEY = "\${FIRECRAWL_API_KEY}";
        };
        exa = {
          command = "npx";
          args = [ "-y" "exa-mcp-server" ];
          env.EXA_API_KEY = "\${EXA_API_KEY}";
        };
      };
    };
    # Global gitattributes: strip outputs from .ipynb on commit (all repos)
    ".config/git/attributes".text = "*.ipynb filter=nbstripout diff=ipynb\n";
    # Darwin: user-level nix.conf (Determinate Nix manages the daemon, so nix.settings unavailable)
    ".config/nix/nix.conf" = lib.mkIf isDarwin {
      text = ''
        keep-outputs = true
        keep-derivations = true
      '';
    };
  };

  # PATH additions (replaces manual export in bashrc)
  home.sessionPath = [
    "${homeDir}/.local/bin"
  ] ++ lib.optionals isDarwin [
    "/opt/homebrew/bin"
  ];

  # Environment variables
  home.sessionVariables = {
    EDITOR = "emacsclient";
  } // lib.optionalAttrs isDarwin {
    SHELL = "/run/current-system/sw/bin/bash";
  };

  # SSH — force xterm-256color since eat-truecolor is rarely available on remote hosts
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      SetEnv.TERM = "xterm-256color";
    };
  };

  # Enable home-manager
  programs.home-manager.enable = true;

  # Direnv for development environments
  programs.direnv = {
    enable = true;
    enableBashIntegration = false;
    nix-direnv.enable = true;
    config = {
      global = {
        warn_timeout = "0";
        hide_env_diff = true;
      };
    };
    stdlib = ''
      : "''${direnv_layout_dir:=$PWD/.direnv}"
    '';
  };

  # Bash configuration
  programs.bash = {
    enable = true;
    enableCompletion = true;
    bashrcExtra = ''
      PS1='\u:\W\$ '
      export EDITOR="emacs -nw"
    '' + lib.optionalString isDarwin ''
      export SHELL="/run/current-system/sw/bin/bash"
    '' + lib.optionalString enableSecrets ''

      # Load secrets as environment variables (skip empty/unconfigured ones)
      ${secretExportLines}
    '' + ''

      # Set emacsclient socket name to match the current tmux pane's server
      if [ -n "$TMUX_PANE" ]; then
        export EMACS_SERVER="emacs-$(echo $TMUX_PANE | tr -d %)"
        export EDITOR="emacsclient -s $EMACS_SERVER"
      fi

      # Inside Emacs (eat), open files in a new Emacs window instead of nested instance
      if [ -n "$INSIDE_EMACS" ]; then
        emacs() {
          emacsclient -s "$EMACS_SERVER" -n --eval "(progn (split-window-right) (other-window 1) (find-file \"$(realpath "$1")\"))"
        }
      else
        alias emacs="emacs -nw"
      fi

      # Force xterm-256color for SSH (eat-truecolor rarely available on remote hosts)
      alias ssh='TERM=xterm-256color command ssh'

      # Eat shell integration (directory tracking, etc.)
      [ -n "$EAT_SHELL_INTEGRATION_DIR" ] && source "$EAT_SHELL_INTEGRATION_DIR/bash"
    '';
    initExtra = ''
      if command -v tmux &> /dev/null && [ -t 0 ] && [[ ! "$TERM" =~ screen ]] && [[ ! "$TERM" =~ tmux ]] && [ -z "$TMUX" ] && [ -z "$INSIDE_EMACS" ]; then
         exec tmux -f ${homeDir}/.config/tmux/tmux.conf
      fi

      # Hook direnv into interactive bash (disabled auto-integration to keep it after the interactive guard)
      eval "$(direnv hook bash)"
    '';
  };

  # Tmux configuration
  programs.tmux = {
    enable = true;
    shell = "${pkgs.bash}/bin/bash";
    extraConfig = ''
      set -g default-terminal "screen-256color"
      set-option -g status-position top
      set-option -g default-shell "${pkgs.bash}/bin/bash"
      set-option -g default-command "${pkgs.bash}/bin/bash"
      set-option -g automatic-rename on
      set-option -g automatic-rename-format '#{b:pane_current_path}'
    '';
  };

  # GPG agent (Linux only)
  services.gpg-agent = lib.mkIf isLinux {
    enable = true;
    defaultCacheTtl = 1800;
    enableSshSupport = true;
  };

  # Git configuration
  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      user = if gitUser != null then gitUser else {
        name = "Daniel Crawford";
        email = "daniel.sc.crawford@gmail.com";
      };
      color = {
        ui = "auto";
        branch = true;
        diff = true;
        interactive = true;
        status = true;
        log = true;
      };
      core = {
        pager = "cat";
      };
      filter = {
        nbstripout = {
          clean = "nbstripout";
          smudge = "cat";
          required = true;
        };
      };
      diff = {
        ipynb = {
          textconv = "nbstripout -t";
        };
      };
    };
  };

  # Sync cluster-admin certs from the Kubernetes master (Linux only).
  # Certs are issued by CFSSL with easyCerts; this pulls them to ~/.kube/certs
  # so kubectl works from the local desktop.
  systemd.user.services.kube-cert-sync = lib.mkIf isLinux {
    Unit.Description = "Sync kubectl certs from Kubernetes master";
    Service = {
      Type = "oneshot";
      ExecStart = let
        script = pkgs.writeShellApplication {
          name = "kube-cert-sync";
          runtimeInputs = [ pkgs.openssh pkgs.openssl pkgs.coreutils ];
          text = ''
            KUBE_DIR="${homeDir}/.kube/certs"
            MASTER="host@node1"
            SECRETS="/var/lib/kubernetes/secrets"
            CERTS="ca.pem cluster-admin.pem cluster-admin-key.pem"

            mkdir -p "$KUBE_DIR"

            for cert in $CERTS; do
              # shellcheck disable=SC2029
              ssh "$MASTER" "sudo cat $SECRETS/$cert" > "$KUBE_DIR/$cert.tmp"
              mv "$KUBE_DIR/$cert.tmp" "$KUBE_DIR/$cert"
              chmod 600 "$KUBE_DIR/$cert"
            done

            EXPIRY=$(openssl x509 -in "$KUBE_DIR/cluster-admin.pem" -noout -enddate)
            echo "kube-cert-sync: certs updated, ''${EXPIRY#notAfter=}"
          '';
        };
      in "${script}/bin/kube-cert-sync";
    };
  };

  systemd.user.timers.kube-cert-sync = lib.mkIf isLinux {
    Unit.Description = "Weekly kubectl cert sync from Kubernetes master";
    Timer = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Nix settings (flakes support) - only on Linux, Darwin uses Determinate Nix
  nix = lib.mkIf isLinux {
    settings.experimental-features = [ "nix-command" "flakes" ];
  };
}
