{
  # Minimal flake scoped to the agent-sandbox package only. Not yet
  # merged with the host flake (disko/hyprland/hosts) — that's a
  # separate, not-yet-designed subsystem (see system-plan.md).
  description = "agent-sandbox: podman-песочница для AI coding agents";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # claude-code/opencode/chromium license status in nixpkgs should
        # be double-checked at implementation time (CLAUDE.md: verify,
        # don't assume) — set true defensively so an unfree marking
        # doesn't silently break the build.
        config.allowUnfree = true;
      };
    in
    {
      packages.${system}.agent-sandbox-image =
        import ./modules/nixos/packages/agent-sandbox.nix { inherit pkgs; };
    };
}
