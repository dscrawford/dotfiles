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
      # Free multi-engine web search + content extraction for the
      # deep-research skill (replaces the paid firecrawl/exa servers).
      # No API key; scrapes public engine results, so bursts can get blocked.
      web-search = {
        command = "npx";
        args = [ "-y" "open-websearch@latest" ];
        env = {
          MODE = "stdio";
          DEFAULT_SEARCH_ENGINE = "duckduckgo";
          ALLOWED_SEARCH_ENGINES = "duckduckgo,bing,brave,startpage";
        };
      };
    };
  };
}
