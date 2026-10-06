# mise -- version manager for ruby/node/etc, versions come from each
# project's .tool-versions, not hardcoded here (system-plan.md §5.3) --
# same instance the agent-sandbox image uses internally (§9.3).
{ ... }:
{
  # Gems install into the mise Ruby as usual (one shared dir per Ruby
  # version, not per project); the agent sandbox reads them from there
  # read-only and installs only missing ones into its own dir (GEM_PATH in
  # modules/nixos/packages/agent-sandbox.nix).
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };
}
