#!/usr/bin/env bash
# Tests for bin/agent-sandbox, run without podman: a fake `podman` on
# PATH records the argv it was called with (one argument per line) and
# exits with $FAKE_PODMAN_EXIT, so every test asserts on the exact podman
# invocation the wrapper builds. Real podman behaviour (keep-id, volumes,
# --init, loopback publishing) is covered by the manual checklist in
# README.md, not here — this covers the wrapper's own logic: argument
# parsing, the environment allowlist, --workdir validation, exit-code
# passthrough, up/exec/down wiring.
#
# Run: bash tests/agent-sandbox-test.sh   (also: `make test`, and the
# `agent-sandbox-cli` flake check, which additionally runs shellcheck).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$repo_root/bin/agent-sandbox"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
# Shebang taken from the running bash, not /usr/bin/env: the flake check
# runs this inside the Nix build sandbox, which has no /usr/bin/env.
echo "#!$(command -v bash)" >"$tmp/bin/podman"
cat >>"$tmp/bin/podman" <<'EOF'
# `podman container inspect -f {{.State.Running}} NAME` is the wrapper's
# liveness probe for the `up` container; answer it from $FAKE_RUNNING
# without recording it as "the" invocation.
if [ "${1:-}" = container ] && [ "${2:-}" = inspect ]; then
  if [ "${FAKE_RUNNING:-false}" = true ]; then echo true; exit 0; fi
  exit 125
fi
# `podman network exists NAME`: the project's sidecar network, from
# $FAKE_NETWORK; also a probe, not recorded.
if [ "${1:-}" = network ] && [ "${2:-}" = exists ]; then
  [ "${FAKE_NETWORK:-false}" = true ] && exit 0
  exit 1
fi
printf '%s\n' "$@" >"$FAKE_PODMAN_LOG"
exit "${FAKE_PODMAN_EXIT:-0}"
EOF
chmod +x "$tmp/bin/podman"

export PATH="$tmp/bin:$PATH"
export FAKE_PODMAN_LOG="$tmp/podman.log"

project="$tmp/proj"
mkdir -p "$project/.worktrees/feature/KEY-1-slug" "$tmp/outside"
ln -s "$tmp/outside" "$project/escape-link"
project="$(cd "$project" && pwd -P)"
hash="$(printf '%s' "$project" | sha256sum | cut -c1-12)"

pass=0
fail=0
current=""

t() { current="$1"; rm -f "$FAKE_PODMAN_LOG"; }
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$current]: $*" >&2; }

# Run the wrapper with a clean, controlled environment: only PATH and the
# fake-podman knobs survive, plus whatever the test passes explicitly.
# stdin from /dev/null so the TTY branch is deterministic (never a TTY).
run() {
  local rc=0
  env -i PATH="$PATH" HOME="$tmp" FAKE_PODMAN_LOG="$FAKE_PODMAN_LOG" \
    FAKE_PODMAN_EXIT="${FAKE_PODMAN_EXIT:-0}" FAKE_RUNNING="${FAKE_RUNNING:-false}" FAKE_NETWORK="${FAKE_NETWORK:-false}" \
    "$@" </dev/null >"$tmp/out" 2>"$tmp/err" || rc=$?
  echo "$rc"
}

log_has() { [ -f "$FAKE_PODMAN_LOG" ] && grep -qxF -- "$1" "$FAKE_PODMAN_LOG"; }
log_lacks() { ! { [ -f "$FAKE_PODMAN_LOG" ] && grep -qxF -- "$1" "$FAKE_PODMAN_LOG"; }; }
log_seq() {
  # consecutive lines $1 $2 appear in order (a flag followed by its value)
  [ -f "$FAKE_PODMAN_LOG" ] && awk -v a="$1" -v b="$2" 'prev == a && $0 == b { f = 1 } { prev = $0 } END { exit !f }' "$FAKE_PODMAN_LOG"
}
expect_rc() {
  if [ "$1" = "$2" ]; then ok; else bad "exit code $1, expected $2; stderr: $(cat "$tmp/err")"; fi
}
expect() { if "$@"; then ok; else bad "assertion failed: $*"; fi; }

# --- one-shot mode --------------------------------------------------------

t "one-shot builds podman run with project mount and command"
rc=$(run bash "$script" "$project" -- echo hi)
expect_rc "$rc" 0
expect log_has run
expect log_has --rm
expect log_seq -v "$project:/workspace"
expect log_seq -v "agent-creds-$hash:/home/agent/.sandbox-creds"
expect log_seq -v "agent-local-bin:/home/agent/.local/bin"
expect log_seq agent-sandbox:latest echo
expect log_lacks --
expect log_has -i
expect log_lacks -it

t "no sidecar network: plain bridge networking"
rc=$(run bash "$script" "$project" -- true)
expect log_has --network=bridge
expect log_lacks "agent-sb-$hash"

t "sidecar network exists: agent joins it next to the default network"
rc=$(FAKE_NETWORK=true run bash "$script" up "$project")
expect_rc "$rc" 0
expect log_seq --network podman
expect log_seq --network "agent-sb-$hash"
expect log_lacks --network=bridge

t "env allowlist: service tokens in the host env never reach the container"
rc=$(run JIRA_API_TOKEN=j GITLAB_TOKEN=g GITLAB_PRIVATE_TOKEN=p GITHUB_TOKEN=h \
  AWS_SECRET_ACCESS_KEY=a ANTHROPIC_API_KEY=k bash "$script" "$project" -- true)
expect_rc "$rc" 0
expect log_seq -e ANTHROPIC_API_KEY
for v in JIRA_API_TOKEN GITLAB_TOKEN GITLAB_PRIVATE_TOKEN GITHUB_TOKEN AWS_SECRET_ACCESS_KEY; do
  expect log_lacks "$v"
done
expect log_lacks --env-host
expect log_lacks --env-file
# every -e in the invocation is from the allowlist
bad_env=$(awk 'prev == "-e" && $0 !~ /^(ANTHROPIC_API_KEY|DEEPSEEK_API_KEY|GITLAB_TOKEN|AGENT_WORKDIR=.*|WAYLAND_DISPLAY=.*|XDG_RUNTIME_DIR=.*)$/ { print } { prev = $0 }' "$FAKE_PODMAN_LOG")
expect [ -z "$bad_env" ]

t "env allowlist: unset keys are not forwarded as empty"
rc=$(run bash "$script" "$project" -- true)
expect log_lacks ANTHROPIC_API_KEY
expect log_lacks DEEPSEEK_API_KEY

t "--gitlab-token forwards GITLAB_TOKEN only when asked"
rc=$(run GITLAB_TOKEN=g bash "$script" --gitlab-token "$project" -- true)
expect_rc "$rc" 0
expect log_seq -e GITLAB_TOKEN

t "--gitlab-token without GITLAB_TOKEN fails before podman"
rc=$(run bash "$script" --gitlab-token "$project" -- true)
expect_rc "$rc" 1
expect [ ! -f "$FAKE_PODMAN_LOG" ]

t "exit code of the agent is passed through"
rc=$(FAKE_PODMAN_EXIT=7 run bash "$script" "$project" -- false)
expect_rc "$rc" 7

t "--workdir relative to the project"
rc=$(run bash "$script" --workdir .worktrees/feature/KEY-1-slug "$project" -- pwd)
expect_rc "$rc" 0
expect log_seq -e AGENT_WORKDIR=/workspace/.worktrees/feature/KEY-1-slug

t "--workdir as absolute host path inside the project"
rc=$(run bash "$script" --workdir "$project/.worktrees/feature/KEY-1-slug" "$project" -- pwd)
expect_rc "$rc" 0
expect log_seq -e AGENT_WORKDIR=/workspace/.worktrees/feature/KEY-1-slug

t "--workdir outside the project is rejected"
rc=$(run bash "$script" --workdir "$tmp/outside" "$project" -- pwd)
expect_rc "$rc" 1
expect [ ! -f "$FAKE_PODMAN_LOG" ]

t "--workdir escaping via .. is rejected"
rc=$(run bash "$script" --workdir ../outside "$project" -- pwd)
expect_rc "$rc" 1

t "--workdir escaping via symlink is rejected"
rc=$(run bash "$script" --workdir escape-link "$project" -- pwd)
expect_rc "$rc" 1

t "--workdir that does not exist is rejected"
rc=$(run bash "$script" --workdir nope "$project" -- pwd)
expect_rc "$rc" 1

t "--no-tty never requests a TTY"
rc=$(run bash "$script" --no-tty "$project" -- true)
expect log_has -i
expect log_lacks -it

t "unknown option is rejected"
rc=$(run bash "$script" --frobnicate "$project")
expect_rc "$rc" 1

t "--help exits 0"
rc=$(run bash "$script" --help)
expect_rc "$rc" 0

# --- up / exec / attach / down / status ------------------------------------

t "up starts a named, labelled, detached container"
rc=$(run bash "$script" up --publish 3080:3080 "$project")
expect_rc "$rc" 0
expect log_has -d
expect log_has --init
expect log_seq --name "agent-sandbox-$hash"
expect log_seq --label "agent-sandbox.project=$project"
expect log_seq -p 127.0.0.1:3080:3080
expect log_seq agent-sandbox:latest sleep
expect log_has infinity

t "up is a no-op when already running"
rc=$(FAKE_RUNNING=true run bash "$script" up "$project")
expect_rc "$rc" 0
expect [ ! -f "$FAKE_PODMAN_LOG" ]

t "up rejects --workdir and a command"
rc=$(run bash "$script" up --workdir .worktrees "$project")
expect_rc "$rc" 1
rc=$(run bash "$script" up "$project" -- bash)
expect_rc "$rc" 1

t "--publish must be numeric host:container and is loopback-only"
rc=$(run bash "$script" up --publish 0.0.0.0:3080 "$project")
expect_rc "$rc" 1
rc=$(run bash "$script" up --publish abc "$project")
expect_rc "$rc" 1

t "--shared-root is only valid for up"
rc=$(run bash "$script" --shared-root "$project" -- true)
expect_rc "$rc" 1

t "exec requires the up container"
rc=$(run bash "$script" exec "$project" -- true)
expect_rc "$rc" 1
expect [ ! -f "$FAKE_PODMAN_LOG" ]

t "exec runs through the entrypoint with workdir and passes the exit code"
rc=$(FAKE_RUNNING=true FAKE_PODMAN_EXIT=3 run bash "$script" exec --workdir .worktrees/feature/KEY-1-slug "$project" -- claude -p hi)
expect_rc "$rc" 3
expect log_has exec
expect log_seq -e AGENT_WORKDIR=/workspace/.worktrees/feature/KEY-1-slug
expect log_seq "agent-sandbox-$hash" /agent-entrypoint
expect log_seq /agent-entrypoint claude
expect log_lacks -it

t "exec without a command is rejected"
rc=$(FAKE_RUNNING=true run bash "$script" exec "$project")
expect_rc "$rc" 1

t "attach always asks for a TTY"
rc=$(FAKE_RUNNING=true run bash "$script" attach "$project")
expect_rc "$rc" 0
expect log_has -it
expect log_seq "agent-sandbox-$hash" /agent-entrypoint

t "attach rejects up-time options"
rc=$(FAKE_RUNNING=true run bash "$script" attach --gui "$project")
expect_rc "$rc" 1

t "down stops the project container"
rc=$(run bash "$script" down "$project")
expect_rc "$rc" 0
expect log_seq stop "agent-sandbox-$hash"

t "status lists labelled containers"
rc=$(run bash "$script" status)
expect_rc "$rc" 0
expect log_has ps
expect log_seq --filter label=agent-sandbox.project

echo "agent-sandbox tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
