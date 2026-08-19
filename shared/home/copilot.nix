# shared/home/copilot.nix
# User-level Copilot MCP config: a workspace .mcp.json is only discovered when
# the cwd is that repo, so copilot/agent-shell sessions anywhere else need
# ~/.copilot/mcp-config.json. Servers mirror emacs/agent-shell.nix; model
# routing comes from my.llmRouting (llm-routing.nix). autoStart off: Copilot
# spawns servers on first tool call.
{ pkgs, config, ... }:

let
  localLlmMcp = pkgs.callPackage ../../pkgs/local-llm-mcp { };
in
{
  home.file.".copilot/mcp-config.json".text = builtins.toJSON {
    mcpServers = {
      ruflo = {
        command = "ruflo";
        args = [ "mcp" "start" ];
        autoStart = false;
      };
      local-llm-router = {
        command = "${localLlmMcp}/bin/local-llm-mcp";
        args = [ ];
        env = config.my.llmRouting.env;
        autoStart = false;
      };
    };
  };
}
