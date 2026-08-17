# shared/home/ollama.nix
# Renders as a systemd user service on Linux, launchd agent on macOS (Metal
# needs no flag); backs local-llm-router. Desktop overrides package in flake.nix.
{ ... }:

{
  services.ollama = {
    enable = true;
    # Explicit loopback pin so an upstream default change can't widen the
    # unauthenticated API beyond localhost.
    host = "127.0.0.1";
    port = 11434;
  };
}
