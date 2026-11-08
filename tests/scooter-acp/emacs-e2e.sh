#!/usr/bin/env bash
# Drives the pinned agent-shell (shared/emacs/custom-packages.nix) against
# scooter-acp and a fake Scooter. Builds an Emacs with those packages on first run.
# Sandbox files go through a local sshd behind websocat, as a Scooter sandbox's ssh service does.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
tmp=$(mktemp -d)
trap 'kill "${server:-}" "${sshd:-}" 2>/dev/null || true; rm -rf "$tmp"' EXIT

nixpkgs="let flake = builtins.getFlake \"git+file://$root\"; in import flake.inputs.nixpkgs { system = builtins.currentSystem; }"
emacs=$(nix build --no-link --print-out-paths --impure --expr "
  let pkgs = $nixpkgs;
  in (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (epkgs:
    let custom = import $root/shared/emacs/custom-packages.nix { inherit pkgs epkgs; };
    in [ custom.acp custom.shell-maker custom.agent-shell ])")
openssh=$(nix build --no-link --print-out-paths --impure --expr "($nixpkgs).openssh.out")
websocat=$(nix build --no-link --print-out-paths --impure --expr "($nixpkgs).websocat.out")

mkdir -p "$tmp/bridge/bin"
printf '#!/bin/sh\nexec node %s/pkgs/scooter-acp/src/main.mjs "$@" 2>>%s\n' "$root" "$tmp/bridge.log" > "$tmp/bridge/bin/scooter-acp"
printf '#!/bin/sh\nSCOOTER_ACP=%s PATH=%s/bin:$PATH exec bash -euo pipefail %s/pkgs/scooter-acp/scooter-ssh.sh "$@"\n' \
  "$tmp/bridge/bin/scooter-acp" "$openssh" "$root" > "$tmp/bridge/bin/scooter-ssh"
chmod +x "$tmp/bridge/bin/scooter-acp" "$tmp/bridge/bin/scooter-ssh"
echo "_oauth2_proxy=good" > "$tmp/cookie"
{
  nix eval --raw --impure --expr '(import ./shared/emacs/guard.nix { })'
  echo
  nix eval --raw --impure --expr "(import ./shared/emacs/scooter.nix {
    pkgs.callPackage = _: _: \"$tmp/bridge\";
    config.my.scooter = { url = \"\"; cookieFile = \"$tmp/cookie\"; };
  })"
} > "$tmp/scooter.el"

export SANDBOX_DIR="$tmp/sandbox"
mkdir -p "$SANDBOX_DIR" "$tmp/sshd" "$tmp/.local/state/scooter/ssh"
printf 'line one\nline two\n' > "$SANDBOX_DIR/hello.txt"
"$openssh/bin/ssh-keygen" -q -t ed25519 -N "" -f "$tmp/sshd/host_key"
"$openssh/bin/ssh-keygen" -q -t ed25519 -N "" -f "$tmp/.local/state/scooter/ssh/id_ed25519"
cp "$tmp/.local/state/scooter/ssh/id_ed25519.pub" "$tmp/sshd/authorized_keys"
# A locked account (root in a Scooter sandbox) only gets in through PAM.
cat > "$tmp/sshd/config" <<CONF
HostKey $tmp/sshd/host_key
PidFile none
AuthenticationMethods publickey
AuthorizedKeysFile $tmp/sshd/authorized_keys
StrictModes no
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM $([ "$(id -u)" = 0 ] && echo yes || echo no)
Subsystem sftp internal-sftp
CONF
export SSH_BACKEND_PORT=$((20000 + RANDOM % 20000))
"$websocat/bin/websocat" --binary --exit-on-eof "ws-l:127.0.0.1:$SSH_BACKEND_PORT" \
  exec:"$openssh/bin/sshd" --exec-args -i -e -f "$tmp/sshd/config" 2> "$tmp/sshd/log" &
sshd=$!

export TRIGGER_FILE="$tmp/trigger"
node tests/scooter-acp/e2e-server.mjs > "$tmp/url" &
server=$!
for _ in $(seq 50); do [ -s "$tmp/url" ] && break; sleep 0.1; done

SCOOTER_URL=$(cat "$tmp/url") SCOOTER_EL="$tmp/scooter.el" HOME="$tmp" \
  "$emacs/bin/emacs" -Q --batch -l tests/scooter-acp/agent-shell-e2e.el || {
    echo "--- bridge log"; cat "$tmp/bridge.log"; echo "--- sshd log"; cat "$tmp/sshd/log"; exit 1; }
