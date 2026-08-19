# shared/home/llm-routing.nix
# Single source of truth for local-llm-router model selection, consumed by
# copilot.nix and emacs/agent-shell.nix. Claude stays the primary model: the
# router only intercepts the tiers listed in `overrides`, everything else
# (opus included — security-scout's pin, 2bd9ee8) goes remote.
#
# Downstream flakes building on this repo's mkLocal/mkDarwin override via any
# homeModule, e.g.:
#   { my.llmRouting.defaultModel = "llama3.3:70b"; }
#   { my.llmRouting.overrides = { sonnet = "..."; haiku = "..."; }; }
{ lib, config, ... }:

let
  cfg = config.my.llmRouting;
in
{
  options.my.llmRouting = {
    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3-coder:30b";
      description = "Ollama model the router uses when no override matches.";
    };

    overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        sonnet = cfg.defaultModel;
        claude-sonnet-5 = cfg.defaultModel;
      };
      defaultText = lib.literalExpression
        ''{ sonnet = cfg.defaultModel; claude-sonnet-5 = cfg.defaultModel; }'';
      description = "Model-hint -> Ollama model routing map; unlisted hints stay remote.";
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      internal = true;
      readOnly = true;
      description = "Rendered environment for local-llm-mcp server definitions.";
    };
  };

  config.my.llmRouting.env = {
    LOCAL_LLM_DEFAULT_MODEL = cfg.defaultModel;
    LOCAL_LLM_MODEL_OVERRIDES = builtins.toJSON cfg.overrides;
  };
}
