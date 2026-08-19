# shared/home/secrets.nix
# Decrypts secrets.yaml once per session into a tmpfs env file; a guarded hook
# sources it from both interactive shells (bashrc) and non-interactive ones
# (BASH_ENV via home.sessionVariables). Every top-level scalar in the YAML
# becomes an exported variable named after its uppercased key, so adding a
# secret to the YAML needs no change here.
{ config, lib, pkgs, username, enableSecrets ? false, ... }:

let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  homeDir = if isDarwin then "/Users/${username}" else "/home/${username}";
  secretsFile = "${homeDir}/.local/dotfiles/secrets/secrets.yaml";

  # macOS has no /run/user/<uid> tmpfs; fall back to the per-user $TMPDIR
  # (drwx------, APFS). Linux keeps the private /run/user tmpfs.
  runtimeDir =
    if isDarwin then "\${XDG_RUNTIME_DIR:-\${TMPDIR:-/tmp}}"
    else "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}";

  refresh = pkgs.writeShellScriptBin "secret-env-refresh" ''
    set -o pipefail
    umask 077
    # sops finds the age key via $XDG_CONFIG_HOME on Linux, but on macOS it
    # looks under ~/Library/Application Support; pin the actual path so both
    # decrypt. Respect an explicit override if the caller set one.
    export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-${homeDir}/.config/sops/age/keys.txt}"
    f="${runtimeDir}/secret-env.sh"
    tmp="$(mktemp "$f.XXXXXX")" || exit 1
    if ${pkgs.sops}/bin/sops -d "${secretsFile}" 2>/dev/null \
        | ${pkgs.yq}/bin/yq -r '
            to_entries[]
            | select((.value | type) | IN("string", "number", "boolean"))
            | .value |= tostring
            | select(.value != "")
            | "export \(.key | ascii_upcase | gsub("[^A-Z0-9_]"; "_"))=\(.value | @sh)"' > "$tmp"; then
      mv "$tmp" "$f"
    else
      rm -f "$tmp"
      exit 1
    fi
  '';

  # Guard is exported so child shells inherit the variables without
  # re-sourcing. Refresh failure (missing age key) is silent, like the old
  # per-shell decrypt. The env file persists for the login session: after
  # rotating a secret, run `secret-env-refresh` (new shells only) or re-login.
  hook = pkgs.writeText "secret-env-hook.sh" ''
    [ -n "$_SECRET_ENV" ] && return 0
    export _SECRET_ENV=1
    _f="${runtimeDir}/secret-env.sh"
    { [ -f "$_f" ] || ${refresh}/bin/secret-env-refresh; } 2>/dev/null || return 0
    . "$_f"
    unset _f
  '';

  hookPath = "${config.xdg.configHome}/bash/secret-env.sh";
in
{
  options.my.secretEnvHook = lib.mkOption {
    type = lib.types.str;
    default = "";
    internal = true;
    description = "Path to the hook that loads decrypted secrets into the environment.";
  };

  config = lib.mkIf enableSecrets {
    my.secretEnvHook = hookPath;
    xdg.configFile."bash/secret-env.sh".source = hook;
    home.packages = [ refresh ];
    # Reaches GUI-launched processes (Sway -> Emacs -> agent shells), so
    # agent-spawned `bash -c` picks up the hook.
    home.sessionVariables.BASH_ENV = hookPath;
  };
}
