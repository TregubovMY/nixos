#!/usr/bin/env bash
# Test harness for quick-translate.sh: shadows `trans` and `wl-copy` with
# fake executables on PATH so the test doesn't need real network access or
# a real Wayland clipboard — verifies the script's own logic (direction
# detection, loop behavior, clipboard-copy call), not translate-shell's or
# wl-clipboard's correctness.
set -euo pipefail

fail() { echo "FAIL: $1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Fake `trans`: echoes back "[LANG] query" so the test can assert which
# direction the script picked, without hitting the real network.
cat > "$tmp/trans" <<'EOF'
#!/usr/bin/env bash
# Usage in real trans: trans -brief :LANG "text". Args here: -brief :LANG text
lang="${2#:}"
echo "[$lang] $3"
EOF
chmod +x "$tmp/trans"

# Fake `wl-copy`: records what it was given via stdin, so the test can
# assert the translation was actually copied to the clipboard.
cat > "$tmp/wl-copy" <<EOF
#!/usr/bin/env bash
cat > "$tmp/clipboard.txt"
EOF
chmod +x "$tmp/wl-copy"

export PATH="$tmp:$PATH"
script="$(cd "$(dirname "$0")" && pwd)/quick-translate.sh"

# Test 1: Cyrillic input -> ru->en direction
out="$(printf 'привет\n.exit\n' | bash "$script")"
echo "$out" | grep -q '\[en\] привет' || fail "cyrillic input should translate to en, got: $out"

# Test 2: Latin input -> en->ru direction
out="$(printf 'hello\n.exit\n' | bash "$script")"
echo "$out" | grep -q '\[ru\] hello' || fail "latin input should translate to ru, got: $out"

# Test 3: result gets copied to the clipboard
printf 'hello\n.exit\n' | bash "$script" > /dev/null
[ -f "$tmp/clipboard.txt" ] || fail "wl-copy was never called"
grep -q '\[ru\] hello' "$tmp/clipboard.txt" || fail "clipboard content wrong: $(cat "$tmp/clipboard.txt")"

# Test 4: .exit terminates cleanly (script must not hang / must exit 0)
printf '.exit\n' | timeout 5 bash "$script" || fail "script did not exit cleanly on .exit"

# Test 5: EOF (no .exit) also terminates cleanly
printf 'hello\n' | timeout 5 bash "$script" > /dev/null || fail "script did not exit cleanly on EOF"

echo "All tests passed."
