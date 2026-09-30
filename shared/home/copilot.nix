# shared/home/copilot.nix
# User-level Copilot MCP config: a workspace .mcp.json is only discovered when
# the cwd is that repo, so copilot/agent-shell sessions anywhere else need
# ~/.copilot/mcp-config.json. Servers mirror emacs/agent-shell.nix; model
# routing comes from my.llmRouting (llm-routing.nix). autoStart off: Copilot
# spawns servers on first tool call. hooks/*.json is Copilot's user-level hook
# dir; the comment challenge is the same script Claude Code runs, which reads
# either payload shape.
{ pkgs, config, ... }:

let
  localLlmMcp = pkgs.callPackage ../../pkgs/local-llm-mcp { };
  rufloMcp = pkgs.callPackage ../../pkgs/ruflo-mcp { };
in
{
  home.file.".copilot/mcp-config.json".text = builtins.toJSON {
    mcpServers = {
      # Supervised: a crashed or wedged ruflo becomes a retryable tool error
      # instead of a dead connection for the rest of the session.
      ruflo = {
        command = "${rufloMcp}/bin/ruflo-mcp";
        args = [ ];
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

  home.file.".copilot/hooks/comment-density.json".text = builtins.toJSON {
    version = 1;
    hooks.postToolUse = [
      {
        type = "command";
        bash = "${config.home.homeDirectory}/.claude/hooks/comment-density.sh";
        timeoutSec = 10;
      }
    ];
  };
}
