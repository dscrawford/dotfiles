# shared/home/secrets.nix
# Secret-to-environment-variable mapping for sops-nix and the bash export-line
# generation. The generated shell text is exposed via the internal option
# `my.secretExportLines` so the bash module can splice it into bashrcExtra.
{ config, lib, pkgs, username, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";

  # Secret-to-environment-variable mapping for sops-nix
  # Each entry: { secret = "sops_key"; env = "ENV_VAR_NAME"; }
  # Secrets with empty values in sops YAML are silently skipped at shell init.
  secretEnvVars = [
    # AI / IDE
    { secret = "gemini_api_key";    env = "GEMINI_API_KEY";    desc = "Google Gemini API key for Gemini CLI"; }
    # GitHub — gh CLI and API access. Exported under both names on purpose:
    # gh reads GH_TOKEN first and falls back to GITHUB_TOKEN, but most other
    # tooling only looks at GITHUB_TOKEN. Same secret, two entries.
    { secret = "github_token";      env = "GH_TOKEN";          desc = "GitHub PAT for the gh CLI (repo/fork/PR operations)"; }
    { secret = "github_token";      env = "GITHUB_TOKEN";      desc = "GitHub PAT for tooling that only reads GITHUB_TOKEN"; }
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
  options.my.secretExportLines = lib.mkOption {
    type = lib.types.str;
    internal = true;
    description = "Generated bash lines that export secrets as environment variables.";
  };

  config.my.secretExportLines = secretExportLines;
}
