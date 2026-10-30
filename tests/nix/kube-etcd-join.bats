#!/usr/bin/env bats

setup_file() {
  cd "$BATS_TEST_DIRNAME/../.."
  export SCRIPTS="$BATS_FILE_TMPDIR/scripts.json"
  nix eval --json '.?submodules=1#nixosConfigurations' --apply '
    cs: builtins.listToAttrs (map (n: {
      name = n;
      value = { inherit (cs.${n}.config.systemd.services.etcd) preStart postStart; };
    }) [ "node1" "node2" "node3" ])' > "$SCRIPTS" 2>/dev/null
}

node_script() {
  python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]])' "$SCRIPTS" "$1" "$2" \
    | sed -e "s#/run/etcd/join.env#$tmp/run/etcd/join.env#g" \
          -e "s#/var/lib/kubernetes/secrets#$tmp/secrets#g" \
          -e "s#sleep [0-9]*#sleep 0#g"
}

setup() {
  tmp="$(mktemp -d)"
  export tmp
  mkdir -p "$tmp/bin" "$tmp/run/etcd" "$tmp/data" "$tmp/secrets"
  echo x > "$tmp/secrets/etcd.pem"
  echo x > "$tmp/secrets/etcd-key.pem"
  export ETCD_DATA_DIR="$tmp/data"
  node_script node2 preStart > "$tmp/pre.sh"
  node_script node2 postStart > "$tmp/post.sh"

  # Fixture rows are "id|status|name|peers|clients|learner", rendered as the etcdctl table.
  cat > "$tmp/bin/etcdctl" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$tmp/calls"
for a in "$@"; do case "$a" in --endpoints=*) ep="${a#--endpoints=}";; esac; done
host="${ep#https://}"; host="${host%:2379}"
table() {
  echo "+----+--------+------+------------+--------------+------------+"
  echo "| ID | STATUS | NAME | PEER ADDRS | CLIENT ADDRS | IS LEARNER |"
  echo "+----+--------+------+------------+--------------+------------+"
  awk -F'|' '{ printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5, $6 }' "$1"
  echo "+----+--------+------+------------+--------------+------------+"
}
case " $* " in
  *" member list "*)
    [ -f "$tmp/down.$host" ] && exit 1
    [ -f "$tmp/list-fail-after-add" ] && [ -f "$tmp/added" ] && exit 1
    if [ -f "$tmp/members.$host" ]; then table "$tmp/members.$host"; else table "$tmp/members"; fi ;;
  *" member add "*)
    [ -f "$tmp/fail-add" ] && { echo "etcdserver: unhealthy cluster" >&2; exit 1; }
    touch "$tmp/added"; cp "$tmp/members.after-add" "$tmp/members" ;;
  *" member remove "*) touch "$tmp/removed" ;;
  *" member promote "*)
    n=$(( $(cat "$tmp/promote-tries" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$tmp/promote-tries"
    [ -f "$tmp/promoted-elsewhere" ] && { sed -i 's/|true$/|false/' "$tmp/members"; echo "not a learner" >&2; exit 1; }
    [ "$n" -ge "${PROMOTE_AFTER:-1}" ] || { echo "can only promote a learner member which is in sync" >&2; exit 1; } ;;
  *" member update "*) [ -f "$tmp/fail-update" ] && exit 1 ;;
esac
exit 0
STUB
  chmod +x "$tmp/bin/etcdctl"
  export PATH="$tmp/bin:$PATH"

  node1="aaa|started|node1|https://192.168.0.2:2380|https://192.168.0.2:2379|false"
  node2_unstarted="bbb|unstarted||https://192.168.0.4:2380||true"
  node2_learner="bbb|started|node2|https://192.168.0.4:2380|https://192.168.0.4:2379|true"
  node2_voter="bbb|started|node2|https://192.168.0.4:2380|https://192.168.0.4:2379|false"
}

teardown() {
  rm -rf "$tmp"
}

join_env() { sed -n 's/^ETCD_INITIAL_CLUSTER=//p' "$tmp/run/etcd/join.env"; }
members() { printf '%s\n' "$@" > "$tmp/members"; }
after_add() { printf '%s\n' "$@" > "$tmp/members.after-add"; }

@test "pre-start: existing data dir means no cluster calls, and a stale join env is removed" {
  mkdir -p "$tmp/data/member"
  echo "ETCD_INITIAL_CLUSTER=stale=x" > "$tmp/run/etcd/join.env"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$tmp/calls" ]
  [ ! -f "$tmp/run/etcd/join.env" ]
}

@test "pre-start: fails fast when certmgr has not issued the etcd cert" {
  : > "$tmp/secrets/etcd-key.pem"
  mkdir -p "$tmp/data/member"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"certmgr has not issued"* ]]
}

@test "pre-start: empty data dir adds itself as a learner and writes the join env" {
  members "$node1"
  after_add "$node1" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q -- "member add node2 --learner --peer-urls=https://192.168.0.4:2380" "$tmp/calls"
  [ ! -f "$tmp/removed" ]
  [ "$(join_env)" = "node1=https://192.168.0.2:2380,node2=https://192.168.0.4:2380" ]
  [ "$(sed -n 2p "$tmp/run/etcd/join.env")" = "ETCD_INITIAL_CLUSTER_STATE=existing" ]
  [ "$(wc -l < "$tmp/run/etcd/join.env")" -eq 2 ]
}

@test "pre-start: a wiped node still registered is removed and re-added as a learner" {
  members "$node1" "$node2_voter"
  after_add "$node1" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q -- "member remove bbb" "$tmp/calls"
  grep -q -- "member add node2 --learner" "$tmp/calls"
  [ "$(join_env)" = "node1=https://192.168.0.2:2380,node2=https://192.168.0.4:2380" ]
}

@test "pre-start: a registration found by peer URL among several URLs is also replaced" {
  members "$node1" "ccc|started|old-name|https://10.0.0.4:2380,https://192.168.0.4:2380|https://192.168.0.4:2379|false"
  after_add "$node1" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 0 ]
  grep -q -- "member remove ccc" "$tmp/calls"
}

@test "pre-start: a peer with several URLs yields one name=url pair per URL" {
  members "aaa|started|node1|https://192.168.0.2:2380,https://10.0.0.2:2380|https://192.168.0.2:2379|false"
  after_add "aaa|started|node1|https://192.168.0.2:2380,https://10.0.0.2:2380|https://192.168.0.2:2379|false" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 0 ]
  [ "$(join_env)" = "node1=https://192.168.0.2:2380,node1=https://10.0.0.2:2380,node2=https://192.168.0.4:2380" ]
}

@test "pre-start: another unstarted, unnamed member is named from its peer URL" {
  members "$node1" "ccc|unstarted||https://192.168.0.6:2380||true"
  after_add "$node1" "ccc|unstarted||https://192.168.0.6:2380||true" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 0 ]
  [ "$(join_env)" = "node1=https://192.168.0.2:2380,node3=https://192.168.0.6:2380,node2=https://192.168.0.4:2380" ]
}

@test "pre-start: an unnamed member at an unknown address fails the unit" {
  members "$node1"
  after_add "$node1" "0ff|unstarted||https://192.168.0.99:2380||true" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot name member 0ff"* ]]
  [ ! -f "$tmp/run/etcd/join.env" ]
}

@test "pre-start: falls through to the next peer when the first is down" {
  touch "$tmp/down.192.168.0.2"
  members "$node1"
  after_add "$node1" "$node2_unstarted"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 0 ]
  grep -q -- "--endpoints=https://192.168.0.6:2379 member add node2" "$tmp/calls"
  ! grep -q -- "--endpoints=https://192.168.0.2:2379 member add" "$tmp/calls"
}

@test "pre-start: no reachable member leaves the static initial cluster in place" {
  touch "$tmp/down.192.168.0.2" "$tmp/down.192.168.0.6"
  run bash -e "$tmp/pre.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$tmp/run/etcd/join.env" ]
  ! grep -q "member add" "$tmp/calls"
}

@test "pre-start: a failing member add fails the unit without a join env" {
  members "$node1"
  touch "$tmp/fail-add"
  run bash -e "$tmp/pre.sh"
  [ "$status" -ne 0 ]
  [ ! -f "$tmp/run/etcd/join.env" ]
}

@test "pre-start: a member list failing after the add fails the unit without a join env" {
  members "$node1"
  after_add "$node1" "$node2_unstarted"
  touch "$tmp/list-fail-after-add"
  run bash -e "$tmp/pre.sh"
  [ "$status" -ne 0 ]
  [ ! -f "$tmp/run/etcd/join.env" ]
}

@test "pre-start: each node asks only the other two" {
  for pair in "node1|192.168.0.2|192.168.0.4 192.168.0.6" "node3|192.168.0.6|192.168.0.2 192.168.0.4"; do
    IFS='|' read -r n self others <<<"$pair"
    s="$(node_script $n preStart)"
    [ "$(grep -o 'for peer in [^;]*' <<<"$s")" = "for peer in $others" ]
  done
}

@test "post-start: a learner is promoted once in sync" {
  members "$node1" "$node2_learner"
  PROMOTE_AFTER=3 run bash -e "$tmp/post.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(grep -c "member promote bbb" "$tmp/calls")" -eq 3 ]
  ! grep -q "member update" "$tmp/calls"
}

@test "post-start: a learner someone else promoted stops retrying" {
  members "$node1" "$node2_learner"
  touch "$tmp/promoted-elsewhere"
  run bash -e "$tmp/post.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -c "member promote bbb" "$tmp/calls")" -eq 1 ]
}

@test "post-start: a learner that never syncs gives up after 180 attempts" {
  members "$node1" "$node2_learner"
  PROMOTE_AFTER=100000 run bash -e "$tmp/post.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not catch up"* ]]
  [ "$(grep -c "member promote bbb" "$tmp/calls")" -eq 180 ]
}

@test "post-start: a lone member still advertising etcd.local gets its peer URL repaired" {
  members "aaa|started|127.0.0.1|https://etcd.local:2380|https://192.168.0.2:2379|false"
  run bash -e "$tmp/post.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q -- "member update aaa --peer-urls=https://192.168.0.4:2380" "$tmp/calls"
  ! grep -q "member promote" "$tmp/calls"
}

@test "post-start: a wrong peer URL is repaired before promotion" {
  members "$node1" "bbb|started|node2|https://etcd.local:2380|https://192.168.0.4:2379|true"
  run bash -e "$tmp/post.sh"
  [ "$status" -eq 0 ]
  u=$(grep -n "member update bbb" "$tmp/calls" | cut -d: -f1)
  p=$(grep -n "member promote bbb" "$tmp/calls" | head -1 | cut -d: -f1)
  [ "$u" -lt "$p" ]
}

@test "post-start: a failing peer URL update fails the unit before any promote" {
  members "$node1" "bbb|started|node2|https://etcd.local:2380|https://192.168.0.4:2379|true"
  touch "$tmp/fail-update"
  run bash -e "$tmp/post.sh"
  [ "$status" -ne 0 ]
  ! grep -q "member promote" "$tmp/calls"
}

@test "post-start: a voting member with the right peer URL does nothing" {
  members "$node1" "$node2_voter"
  run bash -e "$tmp/post.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -vc "member list" "$tmp/calls")" -eq 0 ]
}

@test "post-start: several members and none named us fails the unit" {
  members "$node1" "ccc|started|node3|https://192.168.0.6:2380|https://192.168.0.6:2379|false"
  run bash -e "$tmp/post.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot find this member"* ]]
}
