#!/usr/bin/env bash
# Tests for bin/agent-sandbox and bin/claude-use, run without podman: a fake
# `podman` on PATH records the argv of each call into a file named after the
# podman verb ($FAKE_PODMAN_LOG.run, .exec, .stop, .ps), so every test asserts
# on the exact invocation the wrapper builds. Real podman behaviour (keep-id,
# volumes, --init, loopback publishing) is covered by the manual checklist in
# docs/AGENT-SANDBOX.md, not here -- this covers the wrapper's own logic: config
# parsing, finding the sandbox for the cwd, the environment allowlist, the
# working directory, exit-code passthrough, up/down wiring, and the account
# resolution of claude-use.
#
# Run: bash tests/agent-sandbox-test.sh   (also: `make test`, and the
# `agent-sandbox-cli` flake check, which additionally runs shellcheck).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$repo_root/bin/agent-sandbox"
claude_use="$repo_root/bin/claude-use"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
# Shebang taken from the running bash, not /usr/bin/env: the flake check
# runs this inside the Nix build sandbox, which has no /usr/bin/env.
echo "#!$(command -v bash)" >"$tmp/bin/podman"
cat >>"$tmp/bin/podman" <<'EOF'
# `podman container inspect -f {{.State.Running}} NAME` is the wrapper's
# liveness probe; answer it from $FAKE_RUNNING without recording it.
if [ "${1:-}" = container ] && [ "${2:-}" = inspect ]; then
  if [ "${FAKE_RUNNING:-false}" = true ]; then echo true; exit 0; fi
  exit 125
fi
printf '%s\n' "$@" >"$FAKE_PODMAN_LOG.$1"
# `-d` of `run` (start) always succeeds; the exit code applies to the
# command the user runs (exec) so passthrough can be tested.
if [ "$1" = exec ]; then exit "${FAKE_PODMAN_EXIT:-0}"; fi
exit 0
EOF
chmod +x "$tmp/bin/podman"

export PATH="$tmp/bin:$PATH"
export FAKE_PODMAN_LOG="$tmp/podman"

# Two project trees and a place outside both.
mkdir -p "$tmp/code/my/app/sub" "$tmp/code/my/other" "$tmp/code/work/rnds/svc" \
  "$tmp/code/shared" "$tmp/outside" "$tmp/home"
my="$(cd "$tmp/code/my" && pwd -P)"
rnds="$(cd "$tmp/code/work/rnds" && pwd -P)"
shared="$(cd "$tmp/code/shared" && pwd -P)"
outside="$(cd "$tmp/outside" && pwd -P)"

# Stand-in for the Nix-built sandbox rootfs (a directory with
# /agent-entrypoint); the wrapper resolves it like the real symlink.
mkdir -p "$tmp/rootfs-real"
touch "$tmp/rootfs-real/agent-entrypoint"
ln -s "$tmp/rootfs-real" "$tmp/rootfs-link"
rootfs="$tmp/rootfs-link"
rootfs_real="$(cd "$tmp/rootfs-real" && pwd -P)"

# HOME is $tmp/home inside run(), so configs live in $tmp/home/.config/....
cfgdir="$tmp/home/.config/agent-sandbox/projects"
mkdir -p "$cfgdir"
cat >"$cfgdir/my.conf" <<EOF
# comment line
rw      = $my     # trailing comment
ro      = $shared
publish = 3080:3080
env     = RAILS_ENV=development
EOF
printf 'rw = %s\n' "$rnds" >"$cfgdir/work.conf"

pass=0
fail=0
current=""
cur=run # which recorded podman verb the log_* helpers look at

t() { current="$1"; rm -f "$FAKE_PODMAN_LOG".*; cur=run; }
use() { cur="$1"; }
ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL [$current]: $*" >&2; }

# Run the wrapper with a clean, controlled environment: only PATH and the
# fake-podman knobs survive, plus whatever the test passes explicitly.
# stdin from /dev/null so the TTY branch is deterministic (never a TTY).
# CWD sets the directory the command runs in.
run() {
  local rc=0
  (cd "${CWD:-$tmp}" && env -i PATH="$PATH" HOME="$tmp/home" TMPDIR="$tmp" FAKE_PODMAN_LOG="$FAKE_PODMAN_LOG" \
    AGENT_SANDBOX_ROOTFS="$rootfs" FAKE_PODMAN_EXIT="${FAKE_PODMAN_EXIT:-0}" FAKE_RUNNING="${FAKE_RUNNING:-false}" \
    "$@" </dev/null >"$tmp/out" 2>"$tmp/err") || rc=$?
  echo "$rc"
}

logf() { echo "$FAKE_PODMAN_LOG.$cur"; }
log_has() { [ -f "$(logf)" ] && grep -qxF -- "$1" "$(logf)"; }
log_lacks() { ! log_has "$1"; }
log_seq() {
  # consecutive lines $1 $2 appear in order (a flag followed by its value)
  [ -f "$(logf)" ] && awk -v a="$1" -v b="$2" 'prev == a && $0 == b { f = 1 } { prev = $0 } END { exit !f }' "$(logf)"
}
expect_rc() {
  if [ "$1" = "$2" ]; then ok; else bad "exit code $1, expected $2; stderr: $(cat "$tmp/err")"; fi
}
expect() { if "$@"; then ok; else bad "assertion failed: $*"; fi; }
err_has() { grep -qF -- "$1" "$tmp/err"; }

# --- enter: start if needed, then run the command --------------------------

t "enter from a project subdir: starts the sandbox, runs the command there"
rc=$(CWD="$my/app/sub" run bash "$script" -- echo hi)
expect_rc "$rc" 0
expect log_has run
expect log_has --rm
expect log_has -d
expect log_has --init
expect log_seq --name agent-sandbox-cfg-my
# projects at their own host path, no /workspace
expect log_seq -v "$my:$my"
expect log_seq -v "$shared:$shared:ro"
expect log_seq -e "AGENT_MOUNTS=$my:$shared"
expect log_lacks "$my:/workspace"
expect log_seq -v agent-home-my:/home/agent
expect log_seq -v agent-mise-my:/shared/mise
expect log_seq -v agent-uv-tools-my:/shared/uv
expect log_seq -v agent-npm-global-my:/shared/npm-global
expect log_seq -v agent-cache-my:/home/agent/.cache
expect log_seq -e RAILS_ENV=development
expect log_seq -p 127.0.0.1:3080:3080
expect log_seq --rootfs "$rootfs_real:O"
expect log_seq "$rootfs_real:O" /agent-entrypoint
expect log_seq -v /nix/store:/nix/store:ro
expect log_seq -v "$tmp/home/.cache/agent-sandbox/tmp-my:/tmp"
expect log_seq -v "$tmp/agent-sandbox/passwd:/etc/passwd:ro"
use exec
expect log_has -i
expect log_lacks -it
expect log_seq -e "AGENT_WORKDIR=$my/app/sub"
expect log_seq agent-sandbox-cfg-my /agent-entrypoint
expect log_seq /agent-entrypoint echo
expect log_lacks --

t "enter when already running: no new container"
rc=$(CWD="$my/app" FAKE_RUNNING=true run bash "$script" -- true)
expect_rc "$rc" 0
expect [ ! -f "$(logf)" ]
use exec
expect log_seq -e "AGENT_WORKDIR=$my/app"

t "the sandbox is picked by the cwd; the longest matching mount wins"
printf 'rw = %s\nrw = %s\n' "$rnds" "$my/other" >"$cfgdir/mixed.conf"
rc=$(CWD="$my/other" run bash "$script" -- true)
expect_rc "$rc" 0
expect log_seq --name agent-sandbox-cfg-mixed
rc=$(CWD="$my/app" run bash "$script" -- true)
expect log_seq --name agent-sandbox-cfg-my
rm "$cfgdir/mixed.conf"

t "work sandbox for a work directory"
rc=$(CWD="$rnds/svc" run bash "$script" -- true)
expect_rc "$rc" 0
expect log_seq --name agent-sandbox-cfg-work
expect log_seq -e "AGENT_MOUNTS=$rnds"

t "no sandbox covers the cwd"
rc=$(CWD="$outside" run bash "$script" -- true)
expect_rc "$rc" 1
expect err_has "no sandbox config covers"
expect [ ! -f "$(logf)" ]

t "a broken unrelated config does not break the search"
printf 'bogus = 1\n' >"$cfgdir/broken.conf"
rc=$(CWD="$my/app" run bash "$script" -- true)
expect_rc "$rc" 0
rm "$cfgdir/broken.conf"

t "explicit @name from outside starts at its first project"
rc=$(CWD="$outside" run bash "$script" @my -- true)
expect_rc "$rc" 0
use exec
expect log_seq -e "AGENT_WORKDIR=$my"

t "-C picks the start directory inside the sandbox"
rc=$(CWD="$outside" run bash "$script" -C "$my/other" @my -- true)
expect_rc "$rc" 0
use exec
expect log_seq -e "AGENT_WORKDIR=$my/other"

t "-C outside the sandbox's directories is rejected"
rc=$(CWD="$my" run bash "$script" -C "$outside" @my -- true)
expect_rc "$rc" 1
expect [ ! -f "$(logf)" ]

t "exit code of the command is passed through"
rc=$(CWD="$my" FAKE_PODMAN_EXIT=7 run bash "$script" -- false)
expect_rc "$rc" 7

t "--no-tty never requests a TTY"
rc=$(CWD="$my" run bash "$script" --no-tty -- true)
use exec
expect log_has -i
expect log_lacks -it

t "env allowlist: service tokens in the host env never reach the container"
rc=$(CWD="$my" run JIRA_API_TOKEN=j GITLAB_TOKEN=g GITLAB_PRIVATE_TOKEN=p GITHUB_TOKEN=h \
  AWS_SECRET_ACCESS_KEY=a ANTHROPIC_API_KEY=k bash "$script" -- true)
expect_rc "$rc" 0
expect log_seq -e ANTHROPIC_API_KEY
for v in JIRA_API_TOKEN GITLAB_TOKEN GITLAB_PRIVATE_TOKEN GITHUB_TOKEN AWS_SECRET_ACCESS_KEY; do
  expect log_lacks "$v"
done
expect log_lacks --env-host
expect log_lacks --env-file
# every -e in the invocation is from the allowlist
bad_env=$(awk 'prev == "-e" && $0 !~ /^(ANTHROPIC_API_KEY|DEEPSEEK_API_KEY|GITLAB_TOKEN|AGENT_MOUNTS=.*|RAILS_ENV=.*|WAYLAND_DISPLAY=.*|XDG_RUNTIME_DIR=.*|MISE_SHARED_INSTALL_DIRS=.*|CLAUDE_ACCOUNT.*)$/ { print } { prev = $0 }' "$(logf)")
expect [ -z "$bad_env" ]

t "env allowlist: unset keys are not forwarded as empty"
rc=$(CWD="$my" run bash "$script" -- true)
expect log_lacks ANTHROPIC_API_KEY
expect log_lacks DEEPSEEK_API_KEY

t "--gitlab-token forwards GITLAB_TOKEN only when asked"
rc=$(CWD="$my" run GITLAB_TOKEN=g bash "$script" --gitlab-token -- true)
expect_rc "$rc" 0
expect log_seq -e GITLAB_TOKEN

t "--gitlab-token without GITLAB_TOKEN fails before podman"
rc=$(CWD="$my" run bash "$script" --gitlab-token -- true)
expect_rc "$rc" 1
expect [ ! -f "$(logf)" ]

t "--gui on an already running sandbox is refused"
rc=$(CWD="$my" FAKE_RUNNING=true run bash "$script" --gui -- true)
expect_rc "$rc" 1
expect err_has "fixed when the sandbox is created"

t "host mise installs mounted read-only at the same path"
mkdir -p "$tmp/home/.local/share/mise/installs"
mise_inst="$(cd "$tmp/home/.local/share/mise/installs" && pwd -P)"
rc=$(CWD="$my" run bash "$script" -- true)
expect_rc "$rc" 0
expect log_seq -v "$mise_inst:$mise_inst:ro"
expect log_seq -e "MISE_SHARED_INSTALL_DIRS=$mise_inst"

# --- up / down / status -----------------------------------------------------

t "up starts a named, labelled, detached container"
rc=$(CWD="$my" run bash "$script" up)
expect_rc "$rc" 0
expect log_has -d
expect log_has --init
expect log_seq --name agent-sandbox-cfg-my
expect log_seq --label agent-sandbox.name=my
expect log_seq /agent-entrypoint sleep
expect log_has infinity

t "up is a no-op when already running"
rc=$(CWD="$my" FAKE_RUNNING=true run bash "$script" up)
expect_rc "$rc" 0
expect [ ! -f "$(logf)" ]

t "up rejects a command and run-only options"
rc=$(CWD="$my" run bash "$script" up -- bash)
expect_rc "$rc" 1
rc=$(CWD="$my" run bash "$script" up -C "$my")
expect_rc "$rc" 1

t "config autostart: commands start detached in the new container"
printf 'rw = %s\nautostart = kandev start --backend-port 38429\n' "$rnds" >"$cfgdir/board.conf"
rc=$(run bash "$script" up @board)
expect_rc "$rc" 0
use exec
expect log_seq -d agent-sandbox-cfg-board
expect log_has "kandev start --backend-port 38429 >> /home/agent/.local-state/autostart.log 2>&1"
rm "$cfgdir/board.conf"

t "down stops the container"
rc=$(CWD="$my" run bash "$script" down)
expect_rc "$rc" 0
use stop
expect log_seq stop agent-sandbox-cfg-my
rc=$(run bash "$script" down @work)
expect log_seq stop agent-sandbox-cfg-work

t "down/status take no options"
rc=$(CWD="$my" run bash "$script" down --gui)
expect_rc "$rc" 1

t "status lists labelled containers"
rc=$(run bash "$script" status)
expect_rc "$rc" 0
use ps
expect log_has ps
expect log_seq --filter label=agent-sandbox.name

# --- config errors ----------------------------------------------------------

t "config: missing file"
rc=$(run bash "$script" up @nope)
expect_rc "$rc" 1

t "config: bad name"
rc=$(run bash "$script" up @../etc)
expect_rc "$rc" 1

t "config: unknown key rejected, including the removed dir/mount names"
for k in typo dir mount mount_ro; do
  printf 'rw = %s\n%s = %s\n' "$my" "$k" "$my" >"$cfgdir/bad.conf"
  rc=$(run bash "$script" up @bad)
  expect_rc "$rc" 1
  expect [ ! -f "$(logf)" ]
done
rm "$cfgdir/bad.conf"

t "config: no rw directory"
printf 'env = A=1\n' >"$cfgdir/nodir.conf"
rc=$(run bash "$script" up @nodir)
expect_rc "$rc" 1
rm "$cfgdir/nodir.conf"

t "config: refuses to mount the whole home"
printf 'rw = %s\nrw = ~\n' "$my" >"$cfgdir/home.conf"
rc=$(run bash "$script" up @home)
expect_rc "$rc" 1
expect [ ! -f "$(logf)" ]
rm "$cfgdir/home.conf"

t "config: refuses a config that lives inside a mounted dir"
mkdir -p "$my/.cfg/agent-sandbox/projects"
printf 'rw = %s\n' "$my" >"$my/.cfg/agent-sandbox/projects/inner.conf"
rc=$(run env XDG_CONFIG_HOME="$my/.cfg" bash "$script" up @inner)
expect_rc "$rc" 1
expect [ ! -f "$(logf)" ]
rm -r "$my/.cfg"

t "config: publish must be numeric"
printf 'rw = %s\npublish = 0.0.0.0:80\n' "$my" >"$cfgdir/pub.conf"
rc=$(run bash "$script" up @pub)
expect_rc "$rc" 1
rm "$cfgdir/pub.conf"

t "rootfs: missing rootfs fails with a hint, podman not run"
rc=$(CWD="$my" run env AGENT_SANDBOX_ROOTFS="$tmp/nope" bash "$script" -- true)
expect_rc "$rc" 1
expect [ ! -f "$(logf)" ]

t "--help exits 0, unknown option is rejected"
rc=$(run bash "$script" --help)
expect_rc "$rc" 0
rc=$(run bash "$script" --frobnicate)
expect_rc "$rc" 1

# --- Claude accounts in the sandbox ---------------------------------------

croot="$tmp/home/.local/share/claude-accounts"

t "account: root mounted, default account passed"
mkdir -p "$croot/work" "$croot/personal" "$croot/shared"
croot_real="$(cd "$croot" && pwd -P)"
printf 'rw = %s\naccount = work\n' "$rnds" >"$cfgdir/work.conf"
rc=$(CWD="$rnds" run bash "$script" -- true)
expect_rc "$rc" 0
expect log_seq -v "$croot_real:$croot_real"
expect log_seq -e "CLAUDE_ACCOUNTS_ROOT=$croot_real"
expect log_seq -e CLAUDE_ACCOUNT_DEFAULT=work

t "account: unknown account in the config is rejected"
printf 'rw = %s\naccount = nope\n' "$rnds" >"$cfgdir/work.conf"
rc=$(CWD="$rnds" run bash "$script" -- true)
expect_rc "$rc" 1
expect err_has "account 'nope' does not exist"
expect [ ! -f "$(logf)" ]

t "account: config account without any root is rejected"
rm -r "$croot"
printf 'rw = %s\naccount = work\n' "$rnds" >"$cfgdir/work.conf"
rc=$(CWD="$rnds" run bash "$script" -- true)
expect_rc "$rc" 1
expect [ ! -f "$(logf)" ]

t "account: no account configured, no root: starts fine"
printf 'rw = %s\n' "$rnds" >"$cfgdir/work.conf"
rc=$(CWD="$rnds" run bash "$script" -- true)
expect_rc "$rc" 0
expect log_lacks CLAUDE_ACCOUNT_DEFAULT=work

# --- claude-use -------------------------------------------------------------

cu() { # claude-use in a clean environment; CWD as above
  local rc=0
  (cd "${CWD:-$tmp}" && env -i PATH="$PATH" HOME="$tmp/home" CLAUDE_ACCOUNTS_ROOT="$croot" "$@" \
    >"$tmp/out" 2>"$tmp/err") || rc=$?
  echo "$rc"
}
cu_out() { cat "$tmp/out"; }

t "claude-use --add creates accounts with shared symlinks"
rc=$(cu bash "$claude_use" --add personal)
expect_rc "$rc" 0
rc=$(cu bash "$claude_use" --add work)
expect_rc "$rc" 0
expect [ -L "$croot/work/projects" ]
expect [ "$(readlink "$croot/work/projects")" = "../shared/projects" ]
expect [ -d "$croot/shared/projects" ]
expect [ "$(readlink "$croot/personal/projects")" = "../shared/projects" ]
rc=$(cu bash "$claude_use" --add "Bad Name")
expect_rc "$rc" 1
rc=$(cu bash "$claude_use" --add shared)
expect_rc "$rc" 1

t "claude-use: settings.json/CLAUDE.md are copied at --add, not linked"
echo '{"a":1}' >"$croot/personal/settings.json"
rc=$(cu bash "$claude_use" --add third)
expect [ -f "$croot/third/settings.json" ]
expect [ ! -L "$croot/third/settings.json" ]

t "claude-use: rules pick the account by cwd (longest prefix), default otherwise"
mkdir -p "$tmp/home/.config/claude-accounts"
printf 'default = personal\n%s = work\n' "$rnds" >"$tmp/home/.config/claude-accounts/rules"
rc=$(CWD="$rnds/svc" cu bash "$claude_use" dir)
expect_rc "$rc" 0
expect [ "$(cu_out)" = "$croot/work" ]
rc=$(CWD="$outside" cu bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/personal" ]

t "claude-use: a prefix match is a path match, not a string match"
mkdir -p "$tmp/code/work/rnds-other"
rc=$(CWD="$tmp/code/work/rnds-other" cu bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/personal" ]

t "claude-use: override beats rules, --auto clears it, \$CLAUDE_ACCOUNT beats override"
rc=$(CWD="$rnds" cu bash "$claude_use" personal)
expect_rc "$rc" 0
rc=$(CWD="$rnds" cu bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/personal" ]
rc=$(CWD="$rnds" cu env CLAUDE_ACCOUNT=work bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/work" ]
rc=$(CWD="$rnds" cu bash "$claude_use" --auto)
rc=$(CWD="$rnds" cu bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/work" ]

t "claude-use: sandbox default sits between override and rules"
rc=$(CWD="$outside" cu env CLAUDE_ACCOUNT_DEFAULT=work bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/work" ]
rc=$(CWD="$outside" cu bash "$claude_use" personal)
rc=$(CWD="$outside" cu env CLAUDE_ACCOUNT_DEFAULT=work bash "$claude_use" dir)
expect [ "$(cu_out)" = "$croot/personal" ]
rc=$(cu bash "$claude_use" --auto)

t "claude-use: unknown account is an error, not a silent fallback"
rc=$(cu bash "$claude_use" nope)
expect_rc "$rc" 1
rc=$(cu env CLAUDE_ACCOUNT=zzz bash "$claude_use" dir)
expect_rc "$rc" 1
rm "$tmp/home/.config/claude-accounts/rules"
rc=$(CWD="$outside" cu bash "$claude_use" dir)
expect_rc "$rc" 1

t "claude-use --import moves ~/.claude into the layout, only with --yes"
rm -rf "$croot"
mkdir -p "$tmp/home/.claude/projects/-x" "$tmp/home/.claude/skills"
echo tok >"$tmp/home/.claude/.credentials.json"
echo '{}' >"$tmp/home/.claude.json"
echo '{"s":1}' >"$tmp/home/.claude/settings.json"
touch "$tmp/home/.claude/projects/-x/s.jsonl"
rc=$(cu bash "$claude_use" --import personal)
expect_rc "$rc" 1
expect [ -f "$tmp/home/.claude/.credentials.json" ]
rc=$(cu bash "$claude_use" --import personal --yes)
expect_rc "$rc" 0
expect [ -f "$croot/personal/.credentials.json" ]
expect [ -f "$croot/personal/.claude.json" ]
expect [ -f "$croot/shared/projects/-x/s.jsonl" ]
expect [ -f "$croot/personal/settings.json" ]
expect [ ! -e "$tmp/home/.claude/.credentials.json" ]
expect [ ! -e "$tmp/home/.claude.json" ]

echo "agent-sandbox tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
