#!/usr/bin/env bash
# Tests for bin/ai with fake `claude` and `agent-vm` that record how they were
# called. Seconds, no VM: run by the `scripts` flake check and `make test`.
# (The agent-sandbox wrapper tests live on the `agent-sandbox` branch.)
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
t() { cur="$1"; }
expect() { if "$@"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL [$cur]: $*"; fi; }

mkdir -p "$tmp/bin" "$tmp/home"
cat >"$tmp/bin/claude" <<FAKE
#!$(command -v bash)
echo "host account=\${CLAUDE_ACCOUNT:-} \$*" >>"$tmp/ai.log"
FAKE
cat >"$tmp/bin/agent-vm" <<FAKE
#!$(command -v bash)
echo "vm \$*" >>"$tmp/ai.log"
FAKE
chmod +x "$tmp/bin/"*

ai() {
  rm -f "$tmp/ai.log"
  (cd "$tmp" && env -i PATH="$tmp/bin:$PATH" AI_CLAUDE="$tmp/bin/claude" HOME="$tmp/home" \
    bash "$repo_root/bin/ai" "$@") >/dev/null 2>&1 || true
}

t "ai: host by default, args passed verbatim"
ai --continue
expect grep -qx 'host account= --continue' "$tmp/ai.log"
ai -- --vm
expect grep -qx 'host account= --vm' "$tmp/ai.log"

t "ai --account"
ai --account work y
expect grep -qx 'host account=work y' "$tmp/ai.log"

t "ai --vm"
ai --vm -c
expect grep -qx 'vm claude -c' "$tmp/ai.log"
ai --account work --vm x
expect grep -qx 'vm claude --account work x' "$tmp/ai.log"

echo "ai tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
