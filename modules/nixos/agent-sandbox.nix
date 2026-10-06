# Agent sandboxes on the host (system-plan.md §9): the agent-sandbox root
# directory at a stable path, and the two launcher commands on PATH.
#
# /etc/agent-sandbox/rootfs -> the rootfs store path from
# packages/agent-sandbox.nix. bin/agent-sandbox resolves this symlink and
# runs `podman run --rootfs <it>:O` with /nix/store mounted read-only, so
# a `nixos-rebuild switch` is the whole update -- no image to build or
# `podman load`, and the system profile keeps the rootfs (and through it
# every sandbox tool) alive against garbage collection.
#
# The launcher is the repo's bin/ script, copied as-is into a package so
# `agent-sandbox` works from any directory (boards like kandev and dsh run
# inside the sandbox, there is no separate launcher for them any more);
# agent-sandbox-gui.sh sits next to agent-sandbox because agent-sandbox
# sources it from its own directory.
{ pkgs, ... }:
let
  sandbox = import ./packages/agent-sandbox.nix { inherit pkgs; };
  launchers = pkgs.runCommand "agent-sandbox-launchers" { } ''
    mkdir -p $out/bin
    install -m755 ${../../bin/agent-sandbox} $out/bin/agent-sandbox
    install -m644 ${../../bin/agent-sandbox-gui.sh} $out/bin/agent-sandbox-gui.sh
    patchShebangs $out/bin
  '';
in
{
  environment.etc."agent-sandbox/rootfs".source = sandbox.rootfs;
  environment.systemPackages = [ launchers ];
}
