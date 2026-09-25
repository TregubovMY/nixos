#!/usr/bin/env bash
# Tests for bin/agent-secret-load and bin/agent-sidecar, without podman
# or a Bitwarden vault: fake `podman` and `rbw` on PATH. The fake podman
# appends every call (argv joined by spaces) to $FAKE_PODMAN_LOG, stores
# stdin of `secret create` in $FAKE_SECRET_DIR/<name>, and for `build`
# records the file list of the build context — that last one is how the
# "image is built from the commit, not from the working tree" guarantee is
# asserted. A real git repository is used for promote.
#
# Run: bash tests/agent-sidecar-test.sh   (also `make test` and the
# `agent-sandbox-cli` flake check).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
secret_load="$repo_root/bin/agent-secret-load"
sidecar="$repo_root/bin/agent-sidecar"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/secrets" "$tmp/config"
bash_path="$(command -v bash)"

# Shebangs from the running bash, not /usr/bin/env: the flake check runs
# this inside the Nix build sandbox, which has no /usr/bin/env.
echo "#!$bash_path" >"$tmp/bin/podman"
cat >>"$tmp/bin/podman" <<'EOF'
echo "$*" >>"$FAKE_PODMAN_LOG"
case "$1 ${2:-}" in
  "secret create")
    # last argument is "-", the one before it the name
    name="${*: -2:1}"
    cat >"$FAKE_SECRET_DIR/$name"
    ;;
  "secret exists") [ -f "$FAKE_SECRET_DIR/$3" ] ;;
  "image exists") [ "${FAKE_IMAGE:-false}" = true ] ;;
  "container inspect") exit 125 ;;
  "build "*)
    ctx="${*: -1}"
    (cd "$ctx" && find . -type f | sort) >"$FAKE_BUILD_CONTEXT"
    ;;
esac
EOF
echo "#!$bash_path" >"$tmp/bin/rbw"
cat >>"$tmp/bin/rbw" <<'EOF'
# fake vault: item "signer" has password, a field and notes
[ "${FAKE_RBW_FAIL:-false}" = true ] && { echo "rbw: agent locked" >&2; exit 1; }
case "$*" in
  "get signer") echo "s3cret" ;;
  "get --field key-b64 signer") printf 'AAECAw==\n' ;;
  "get --raw signer") echo '{"name":"signer","notes":"line1\nline2"}' ;;
  "get empty") echo "" ;;
  *) echo "rbw: no such entry" >&2; exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/podman" "$tmp/bin/rbw"

export PATH="$tmp/bin:$PATH"
export FAKE_PODMAN_LOG="$tmp/podman.log"
export FAKE_SECRET_DIR="$tmp/secrets"
export FAKE_BUILD_CONTEXT="$tmp/build-context"
export XDG_CONFIG_HOME="$tmp/config"

pass=0
fail=0
current=""
t() { current="$1"; rm -f "$FAKE_PODMAN_LOG" "$FAKE_BUILD_CONTEXT"; }
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$current]: $*" >&2; }
run() {
  local rc=0
  "$@" </dev/null >"$tmp/out" 2>"$tmp/err" || rc=$?
  echo "$rc"
}
expect_rc() {
  if [ "$1" = "$2" ]; then ok; else bad "exit code $1, expected $2; stderr: $(cat "$tmp/err")"; fi
}
expect() { if "$@"; then ok; else bad "assertion failed: $*"; fi; }
log_has() { [ -f "$FAKE_PODMAN_LOG" ] && grep -qF -- "$1" "$FAKE_PODMAN_LOG"; }
no_podman() { [ ! -f "$FAKE_PODMAN_LOG" ]; }

# --- agent-secret-load ---------------------------------------------------

t "password goes to podman secret via stdin, without trailing newline"
rc=$(run bash "$secret_load" signer-pass signer)
expect_rc "$rc" 0
expect log_has "secret create --replace --label agent-sandbox.source=bitwarden signer-pass -"
expect [ "$(cat "$FAKE_SECRET_DIR/signer-pass")" = s3cret ]
expect [ "$(wc -c <"$FAKE_SECRET_DIR/signer-pass")" -eq 6 ]
expect sh -c "! grep -q s3cret '$FAKE_PODMAN_LOG'"

t "field with --base64 is decoded to binary"
rc=$(run bash "$secret_load" signer-key signer --field key-b64 --base64)
expect_rc "$rc" 0
expect [ "$(od -An -tx1 "$FAKE_SECRET_DIR/signer-key" | tr -d ' \n')" = 00010203 ]

t "notes via rbw --raw"
rc=$(run bash "$secret_load" signer-notes signer --notes)
expect_rc "$rc" 0
expect [ "$(cat "$FAKE_SECRET_DIR/signer-notes")" = "$(printf 'line1\nline2')" ]

t "locked vault: no secret is created"
rc=$(FAKE_RBW_FAIL=true run bash "$secret_load" x signer)
expect_rc "$rc" 1
expect no_podman

t "empty value is refused"
rc=$(run bash "$secret_load" x empty)
expect_rc "$rc" 1
expect no_podman

t "unknown item is refused"
rc=$(run bash "$secret_load" x nope)
expect_rc "$rc" 1
expect no_podman

t "bad secret names are refused"
rc=$(run bash "$secret_load" ../x signer)
expect_rc "$rc" 1
rc=$(run bash "$secret_load" .hidden signer)
expect_rc "$rc" 1
expect no_podman

t "--rm deletes the podman secret"
rc=$(run bash "$secret_load" --rm signer-pass)
expect_rc "$rc" 0
expect log_has "secret rm signer-pass"

# --- agent-sidecar -----------------------------------------------------------

project="$tmp/proj"
mkdir -p "$project/services/signer"
git -C "$project" init -q
git -C "$project" config user.email t@example.invalid
git -C "$project" config user.name test
printf 'FROM scratch\n' >"$project/services/signer/Containerfile"
printf 'package main\n' >"$project/services/signer/main.go"
git -C "$project" add -A
git -C "$project" commit -q -m reviewed
reviewed="$(git -C "$project" rev-parse HEAD)"
project="$(cd "$project" && pwd -P)"
hash="$(printf '%s' "$project" | sha256sum | cut -c1-12)"

t "config-dir is outside the project, keyed by the project hash"
rc=$(run bash "$sidecar" config-dir "$project")
expect_rc "$rc" 0
conf_dir="$(cat "$tmp/out")"
expect [ "$conf_dir" = "$XDG_CONFIG_HOME/agent-sandbox/projects/$hash/sidecars" ]
mkdir -p "$conf_dir"
printf 'CONTEXT=services/signer\nSECRETS=signer-key\n' >"$conf_dir/signer.conf"

# the agent now edits the service in the working tree (uncommitted + untracked)
printf 'package main // exfiltrate\n' >"$project/services/signer/main.go"
printf 'evil\n' >"$project/services/signer/untracked.go"

t "promote builds from the commit, not from the working tree"
rc=$(run bash "$sidecar" promote "$project" signer "$reviewed")
expect_rc "$rc" 0
expect log_has "build --label agent-sidecar.commit=$reviewed -t localhost/agent-sidecar-$hash-signer:${reviewed:0:12}"
expect log_has "tag localhost/agent-sidecar-$hash-signer:${reviewed:0:12} localhost/agent-sidecar-$hash-signer:current"
expect grep -qx './main.go' "$FAKE_BUILD_CONTEXT"
expect sh -c "! grep -q untracked '$FAKE_BUILD_CONTEXT'"
expect grep -q "^$reviewed " "$conf_dir/signer.promoted"

t "promote rejects something that is not a commit"
rc=$(run bash "$sidecar" promote "$project" signer no-such-ref)
expect_rc "$rc" 1
expect no_podman

t "config is parsed, never sourced"
# shellcheck disable=SC2016 # the literal $(...) is the point of the test
printf 'CONTEXT=services/signer\nSECRETS=$(touch %s/pwned)\n' "$tmp" >"$conf_dir/evil.conf"
rc=$(FAKE_IMAGE=true run bash "$sidecar" up "$project" evil)
expect_rc "$rc" 1
expect [ ! -e "$tmp/pwned" ]

t "path traversal in CONTEXT is refused"
printf 'CONTEXT=../outside\n' >"$conf_dir/trav.conf"
rc=$(run bash "$sidecar" promote "$project" trav "$reviewed")
expect_rc "$rc" 1

t "up without a promoted image fails"
rc=$(run bash "$sidecar" up "$project" signer)
expect_rc "$rc" 1

t "up with a missing podman secret fails"
rm -f "$FAKE_SECRET_DIR/signer-key"
rc=$(FAKE_IMAGE=true run bash "$sidecar" up "$project" signer)
expect_rc "$rc" 1
expect sh -c "! grep -q '^run ' '$FAKE_PODMAN_LOG'"

t "up starts the sidecar on the internal network with its secret"
printf 'k' >"$FAKE_SECRET_DIR/signer-key"
rc=$(FAKE_IMAGE=true run bash "$sidecar" up "$project" signer)
expect_rc "$rc" 0
expect log_has "network create --ignore --internal agent-sb-$hash"
expect log_has "--network agent-sb-$hash --network-alias signer"
expect log_has "--cap-drop=all --security-opt no-new-privileges --secret signer-key localhost/agent-sidecar-$hash-signer:current"
expect log_has "--name agent-sidecar-$hash-signer"

t "sidecar names must be DNS-safe"
rc=$(run bash "$sidecar" up "$project" 'Bad_Name')
expect_rc "$rc" 1

t "down stops it"
rc=$(run bash "$sidecar" down "$project" signer)
expect_rc "$rc" 0
expect log_has "stop agent-sidecar-$hash-signer"

echo "agent-sidecar/agent-secret-load tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
