# mise -- version manager for ruby/node/etc, versions come from each
# project's .tool-versions, not hardcoded here (system-plan.md §5.3) --
# same instance the agent-sandbox image uses internally (§9.3).
{ ... }:
{
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };
}
