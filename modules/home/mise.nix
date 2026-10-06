# mise -- version manager for ruby/node/etc, versions come from each
# project's .tool-versions, not hardcoded here (system-plan.md §5.3) --
# same instance the agent-sandbox image uses internally (§9.3).
{ ... }:
{
  # Project gems go into the project (vendor/bundle, relative to the
  # Gemfile) instead of into the mise Ruby: the agent sandbox sees that
  # Ruby read-only, so this is what lets host and sandbox share one set of
  # gems per project (same variable in the sandbox entrypoint,
  # modules/nixos/packages/agent-sandbox.nix). Projects should ignore
  # /vendor/bundle in git (Rails' default .gitignore already does).
  home.sessionVariables.BUNDLE_PATH = "vendor/bundle";

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };
}
