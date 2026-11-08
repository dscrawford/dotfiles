# ssh into a Scooter conversation's sandbox: scooter-ssh [ssh options] <conversation-id> [command]
# The pipe is `scooter-acp --tunnel`, so SCOOTER_URL and the session cookie apply.
state="${SCOOTER_SSH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scooter/ssh}"
mkdir -p "$state"
chmod 700 "$state"
if [ ! -s "$state/id_ed25519" ]; then
  ssh-keygen -q -t ed25519 -N "" -C scooter-sandbox -f "$state/id_ed25519"
fi
exec ssh \
  -o User="${SCOOTER_SSH_USER:-root}" \
  -o IdentityFile="$state/id_ed25519" \
  -o IdentitiesOnly=yes \
  -o UserKnownHostsFile="$state/known_hosts" \
  -o StrictHostKeyChecking=accept-new \
  -o LogLevel=ERROR \
  -o ServerAliveInterval=30 \
  -o ProxyCommand="'${SCOOTER_ACP:-scooter-acp}' --tunnel %n" \
  "$@"
