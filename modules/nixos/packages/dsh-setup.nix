# dsh-setup: one command to install dsh and its plugins into a dsh profile
# (npm -g, then `dsh plugin --profile web add <spec>` for each line of the
# pinned lists in ./dsh-plugins: core, extra, claude-sdk). Used by the agent
# VM (agent-vm.nix), so the pinned dsh version and the plugin handling live
# in one place.
{ writeShellApplication }:
writeShellApplication {
  name = "dsh-setup";
  text = ''
    lists=${./dsh-plugins}
    die() { echo "dsh-setup: $*" >&2; exit 1; }
    if [ "$#" -eq 0 ]; then set -- core; fi
    for l in "$@"; do
      if [ ! -f "$lists/$l.txt" ]; then
        avail=""
        for f in "$lists"/*.txt; do b="''${f##*/}"; avail="$avail ''${b%.txt}"; done
        die "unknown list '$l' (available:$avail)"
      fi
    done
    if ! command -v dsh >/dev/null 2>&1; then
      echo "==> installing dsh 0.2.0-rc.2 (npm -g, shared volume)"
      npm install -g @deepseek-ai/dsh@0.2.0-rc.2
    fi
    failed=()
    for l in "$@"; do
      if [ "$l" = claude-sdk ]; then
        echo "claude-sdk is a gray-zone option (see the header of $lists/claude-sdk.txt):"
        echo "a third-party plugin on the Claude Agent SDK driving your subscription."
        read -r -p "Install it anyway? [yes/N] " ans
        [ "$ans" = yes ] || { echo "skipped"; continue; }
      fi
      echo "==> dsh plugins: $l"
      while IFS= read -r line; do
        spec="''${line%%#*}"
        spec="''${spec#"''${spec%%[![:space:]]*}"}"
        spec="''${spec%"''${spec##*[![:space:]]}"}"
        [ -n "$spec" ] || continue
        echo "--> $spec"
        dsh plugin --profile web add "$spec" || failed+=("$spec")
      done < "$lists/$l.txt"
    done
    if [ "''${#failed[@]}" -gt 0 ]; then
      echo "dsh-setup: failed: ''${failed[*]}" >&2
      exit 1
    fi
    echo "==> done. Restart dsh web (agent-vm shell sudo systemctl restart dsh-web) to load the plugins."
  '';
}
