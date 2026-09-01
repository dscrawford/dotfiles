# shared/home/llm-routing.nix
# Single source of truth for local-llm-router model selection, consumed by
# copilot.nix and emacs/agent-shell.nix. Claude stays the primary model, and
# `overrides` is empty so no model hint maps to a local one.
#
# This map only picks WHICH local model local_model_run uses; it cannot send a
# call back to Claude. server.mjs resolveModel falls through override ->
# requested -> defaultModel, so an unmapped hint still lands on defaultModel.
# Nothing reaches the router unless a caller invokes local_model_run
# explicitly — agent `model:` frontmatter is a separate, remote-only system.
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
      default = { };
      description = "Model-hint -> Ollama model routing map; empty means no hint maps locally.";
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
