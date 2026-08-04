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
)
