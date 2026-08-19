# shared/home/copilot.nix
# User-level Copilot MCP config: a workspace .mcp.json is only discovered when
# the cwd is that repo, so copilot/agent-shell sessions anywhere else need
# ~/.copilot/mcp-config.json. Servers mirror emacs/agent-shell.nix; sonnet-tier
# hints route to the local Ollama model, opus stays remote (security-scout's
# pin, 2bd9ee8). autoStart off: Copilot spawns servers on first tool call.
{ pkgs, ... }:

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
        env = {
          LOCAL_LLM_DEFAULT_MODEL = "qwen3:8b";
          LOCAL_LLM_MODEL_OVERRIDES = builtins.toJSON {
            sonnet = "qwen3:8b";
            claude-sonnet-5 = "qwen3:8b";
          };
        };
        autoStart = false;
      };
    };
  };
}
