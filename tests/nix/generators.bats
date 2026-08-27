#!/usr/bin/env bats
# Regression tests for the generator helpers that replaced the hand-written
# sway bindsyms / waybar CSS / k8s node configs. They pin the rendered output
# so an edit to the generators can't silently reorder or drop lines.

setup() {
  cd "$BATS_TEST_DIRNAME/../.."
}

# drop stderr: nix's dirty-tree warning would pollute `run`'s $output
nix_eval() {
  nix eval "$@" 2>/dev/null
}

sway_config() {
  nix eval --raw --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      cfg = import ./shared/sway/config.nix {
        inherit pkgs;
        lib = pkgs.lib;
        workspaceBin = "WS"; wallpaperBin = "WP"; lockBin = "LK";
        volumeBin = "VOL"; recordBin = "REC";
      };
    in cfg.swayConfig
  '
}

waybar_style() {
  nix eval --raw --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
      wb = import ./shared/sway/waybar.nix { inherit pkgs; };
    in wb.style
  '
}

@test "sway: workspace bindsyms cover focus/move-to/switch/move for keys 1-10" {
  local cfg
  cfg="$(sway_config)"

  # table: group | n | expected bindsym line
  while IFS='|' read -r group n want; do
    [ -n "$group" ] || continue
    echo "group=$group n=$n want=$want"
    [[ "$cfg" == *"$want"* ]]
  done <<'EOF'
focus|1|bindsym $mod+F1 exec WS focus 1
focus|9|bindsym $mod+F9 exec WS focus 9
focus|10|bindsym $mod+F10 exec WS focus 10
move-to|1|bindsym $mod+Shift+F1 exec WS move-to 1
move-to|9|bindsym $mod+Shift+F9 exec WS move-to 9
move-to|10|bindsym $mod+Shift+F10 exec WS move-to 10
switch|1|bindsym $mod+1 exec WS switch 1
switch|9|bindsym $mod+9 exec WS switch 9
switch|10|bindsym $mod+0 exec WS switch 10
move|1|bindsym $mod+Shift+1 exec WS move 1
move|9|bindsym $mod+Shift+9 exec WS move 9
move|10|bindsym $mod+Shift+0 exec WS move 10
EOF

  # boundary guard: workspace 10 rides the "0" key; never a literal F0 or +10
  [[ "$cfg" != *"WS focus 0"* ]]
  [[ "$cfg" != *"\$mod+10 "* ]]

  local count
  count="$(grep -c 'exec WS \(focus\|move-to\|switch\|move\) ' <<<"$cfg")"
  [ "$count" -eq 40 ]
}

@test "sway: floating rules render window_role then window_type, adjacent" {
  local cfg want_role want_type
  cfg="$(sway_config)"

  want_role='for_window [window_role="pop-up"] floating enable
for_window [window_role="dialog"] floating enable
for_window [window_role="task_dialog"] floating enable'

  want_type='for_window [window_type="dialog"] floating enable
for_window [window_type="menu"] floating enable
for_window [window_type="splash"] floating enable
for_window [window_type="tooltip"] floating enable
for_window [window_type="utility"] floating enable'

  [[ "$cfg" == *"$want_role"* ]]
  [[ "$cfg" == *"$want_type"* ]]
  [[ "$cfg" == *"$want_role"$'\n'"$want_type"* ]]
}

@test "waybar: module color rules keep the pinned order, not alphabetical" {
  local style want
  style="$(waybar_style)"

  # table: selector | color
  want=""
  while IFS='|' read -r selector color; do
    [ -n "$selector" ] || continue
    want+="${selector} {\n  color: ${color};\n}\n\n"
  done <<'EOF'
#pulseaudio|#8be9fd
#custom-gpu|#ffb86c
#cpu|#ff79c6
#memory|#bd93f9
#custom-disk|#f1fa8c
#network|#50fa7b
#battery|#69ff94
#battery.warning|#ffb86c
#battery.critical|#ff5555
EOF
  want="$(printf '%b' "$want")"
  [[ "$style" == *"$want"* ]]

  # converting moduleColors to an attrset would sort .critical before .warning
  local idx_warning idx_critical
  idx_warning="$(grep -n '#battery\.warning {' <<<"$style" | cut -d: -f1)"
  idx_critical="$(grep -n '#battery\.critical {' <<<"$style" | cut -d: -f1)"
  [ -n "$idx_warning" ]
  [ -n "$idx_critical" ]
  [ "$idx_warning" -lt "$idx_critical" ]
}

@test "flake: kubeNode wires all three k8s hosts plus local/terminal" {
  run nix_eval .#nixosConfigurations --apply builtins.attrNames --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"local"'* ]]
  [[ "$output" == *'"node1"'* ]]
  [[ "$output" == *'"node2"'* ]]
  [[ "$output" == *'"node3"'* ]]
  [[ "$output" == *'"terminal"'* ]]
}

@test "flake: kubeNode default netInterface is eno1, node3 override enp5s0" {
  run nix_eval .#nixosConfigurations.node1.config.networking.interfaces --apply builtins.attrNames --json
  [ "$status" -eq 0 ]
  [ "$output" = '["eno1"]' ]

  run nix_eval .#nixosConfigurations.node3.config.networking.interfaces --apply builtins.attrNames --json
  [ "$status" -eq 0 ]
  [ "$output" = '["enp5s0"]' ]
}

@test "flake: hostName comes from the single shared/common.nix assignment" {
  while IFS='|' read -r attr want; do
    [ -n "$attr" ] || continue
    run nix_eval "$attr" --raw
    [ "$status" -eq 0 ]
    [ "$output" = "$want" ]
  done <<'EOF'
.#nixosConfigurations.node1.config.networking.hostName|node1
.#nixosConfigurations.node2.config.networking.hostName|node2
.#nixosConfigurations.node3.config.networking.hostName|node3
EOF
}

@test "flake: kubeNode host-specific paths exist for every configured node" {
  for hostname in node1 node2 node3; do
    [ -f "hosts/$hostname/hardware-configuration.nix" ]
    [ -f "hosts/$hostname/boot.nix" ]
  done
  [ -f "hosts/node3/nvidia.nix" ]
  [ -f "hosts/node3/storage.nix" ]
}
