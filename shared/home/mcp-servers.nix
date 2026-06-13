# shared/home/mcp-servers.nix
# MCP server config for Claude Code (keegancsmith/emacs-mcp-server)
{ ... }:

{
  home.file.".claude/.mcp.json".text = builtins.toJSON {
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
}
