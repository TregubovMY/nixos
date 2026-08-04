# Podman image for sandboxed AI coding agents (claude-code/opencode).
# Design: system-plan.md §9. Language runtimes (ruby/node/...) are
# deliberately NOT baked in here — mise resolves them per-project at
# container start (see the entrypoint below), so this image stays
# generic across every project instead of needing a rebuild per stack.
{ pkgs }:

let
  # podman's `--userns=keep-id` runs the container's process under the
  # *host* uid — but this minimal image's /etc/passwd only knows about
  # the uid baked in at build time, so tools that call getpwuid() (git,
  # bash prompt, mise) fail with "I have no name!" for any other host
  # uid. Standard fix: synthesize the missing /etc/passwd entry for
  # whatever uid we're actually running as, before doing anything else.
  # Verify this is still the recommended approach before relying on it —
  # see CLAUDE.md "Искать готовые решения" — nixpkgs' dockerTools gains
  # new helpers for this periodically (e.g. `dockerTools.fakeNss`).
  entrypoint = pkgs.writeShellScript "agent-sandbox-entrypoint" ''
    set -euo pipefail

    if ! getent passwd "$(id -u)" > /dev/null 2>&1; then
      echo "agent:x:$(id -u):$(id -g)::/home/agent:${pkgs.bashInteractive}/bin/bash" >> /etc/passwd
    fi

    export HOME=/home/agent
    export MISE_DATA_DIR=/home/agent/.local/share/mise
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    cd /workspace
    # Only run mise install if the project actually pins versions —
    # an agent working on a non-mise project shouldn't wait on this.
    if [ -f .tool-versions ] || [ -f mise.toml ] || [ -f .mise.toml ]; then
      mise install
    fi

    if [ "$#" -eq 0 ]; then
      exec ${pkgs.bashInteractive}/bin/bash -l
    else
      exec "$@"
    fi
  '';
in
pkgs.dockerTools.buildLayeredImage {
  name = "agent-sandbox";
  tag = "latest";

  contents = with pkgs; [
    bashInteractive
    coreutils
    gitMinimal
    curl
    ripgrep
    mise
    cacert
    claude-code
    opencode
    chromium
    dockerTools.usrBinEnv
    dockerTools.binSh
  ];

  extraCommands = ''
    mkdir -p home/agent tmp
    chmod 1777 tmp
  '';

  config = {
    Entrypoint = [ "${entrypoint}" ];
    WorkingDir = "/workspace";
  };
}
