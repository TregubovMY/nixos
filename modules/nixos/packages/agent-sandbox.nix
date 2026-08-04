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
  #
  # Checked `dockerTools.fakeNss` (nixpkgs' purpose-built helper for
  # "getpwuid()/getgrgid() needs to succeed in a minimal image") before
  # writing this by hand, per CLAUDE.md "Искать готовые решения" — it
  # doesn't fit: `fakeNss.extraPasswdLines` bakes specific uid/gid lines
  # in at *build* time (see nixpkgs pkgs/by-name/fa/fakeNss/package.nix),
  # but the whole problem here is that the uid is only known at *run*
  # time (`--userns=keep-id` maps to whatever the host user's uid is,
  # which varies per machine/user). So the entry has to be synthesized by
  # the entrypoint script at container start, not by the image build —
  # fakeNss can't help with that. This append-to-/etc/passwd-at-runtime
  # approach, made writable via `extraCommands` below, mirrors the
  # well-documented OpenShift "Support Arbitrary User IDs" pattern:
  # https://docs.openshift.com/container-platform/4.16/openshift_images/create-images.html#images-create-guide-openshift_create-images
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
# buildLayeredImage (not buildImage, as an earlier draft of system-plan.md
# §9.3 said) — buildLayeredImage splits contents into one layer per store
# path (deduped by nix-store-closure popularity), so rebuilding this image
# after e.g. bumping just claude-code only pushes/loads the layers that
# actually changed instead of one monolithic layer for the whole image.
# Confirmed real for this image: contents pulls in the full chromium
# closure (largest single dependency here), and layering keeps that as
# its own cacheable layer independent of the smaller, more frequently
# bumped packages (claude-code, opencode, mise). system-plan.md §9.3 was
# updated to match.
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
    mkdir -p etc home/agent tmp
    chmod 1777 tmp

    # $HOME needs to be writable by whatever arbitrary host uid
    # `--userns=keep-id` maps us to (not just the build-time owner).
    chmod 777 home/agent

    # /etc/passwd must exist *and* be writable by an arbitrary uid for the
    # entrypoint's `getpwuid()` workaround above to succeed at runtime —
    # world-writable is fine here: this is a single-purpose sandbox image
    # with one real user (whichever uid podman maps us to), not a
    # multi-tenant system where that would be a meaningful privilege
    # boundary. `touch` first since none of this image's `contents`
    # happen to ship a /etc/passwd of their own.
    touch etc/passwd
    chmod 666 etc/passwd
  '';

  config = {
    Entrypoint = [ "${entrypoint}" ];
    WorkingDir = "/workspace";
  };
}
