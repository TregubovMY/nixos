# Sourced (not executed) from bin/agent-sandbox when --gui is passed.
# Appends Wayland socket + GPU device passthrough to the `args` array
# already being built by the caller.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "agent-sandbox --gui: no active Wayland session detected" \
       "(XDG_RUNTIME_DIR/WAYLAND_DISPLAY unset) — run without --gui," \
       "or from inside your Hyprland session." >&2
  exit 1
fi

wayland_socket="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
if [ ! -S "$wayland_socket" ]; then
  echo "agent-sandbox --gui: $wayland_socket is not a socket" >&2
  exit 1
fi

args+=(
  --device /dev/dri
  -e "WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  -e "XDG_RUNTIME_DIR=/run/user/host"
  -v "$wayland_socket:/run/user/host/$WAYLAND_DISPLAY"
  # `/dev/dri/*` nodes are owned root:video, mode 0660 — device access
  # needs group membership, not just the node being present in the
  # container. But `--userns=keep-id` (bin/agent-sandbox) remaps only the
  # *uid* to the host user; it does not carry over the host user's
  # supplementary groups (e.g. `video`), so without this the container
  # process still can't open the passed-through device even though
  # `--device /dev/dri` above put it there. `--group-add keep-groups` is
  # rootless podman's documented fix for exactly this
  # (https://docs.podman.io/en/latest/markdown/podman-run.1.html,
  # `--group-add`) — it maps the host process's actual supplementary
  # groups (including `video`) into the container instead of a synthetic
  # list. Final review, I9a — untested on real hardware (this sandbox has
  # no GPU/podman), but the mechanism is standard and unambiguous.
  --group-add keep-groups
)

# Chromium (one of this image's stated `--gui` use cases) runs its own
# process sandbox that typically can't nest inside rootless podman's
# already-namespaced environment — it needs either `--security-opt
# seccomp=unconfined` on this `podman run` invocation, or `--no-sandbox`
# on Chromium's own command line, to actually launch. Deliberately NOT
# added here: this wrapper is generic (any GUI app, not just Chromium),
# and loosening the container's seccomp profile is a real trade-off that
# shouldn't be silently baked into every `--gui` run for apps that don't
# need it. Recorded here (final review, I9b) so the first real-hardware
# session knows where to look if Chromium fails to launch under --gui
# instead of re-diagnosing from scratch.
