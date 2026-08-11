# Zellij, substituted for the `tmux` system-plan.md §3/§5.3 originally
# named -- requested explicitly (newer, more popular multiplexer).
# Zellij's native WASM plugin system covers what tmux needed
# tpm/tmux-resurrect/tmux-continuum for, so no plugin-manager equivalent
# is needed here. See docs/superpowers/specs/
# 2026-08-11-shell-zellij-design.md "Tool substitution".
{ ... }:
{
  programs.zellij = {
    enable = true;
    # Matches the upstream default (false) -- set explicitly so the
    # decision is documented, not silently implicit. Auto-attaching to
    # an existing session on every new shell (what enableZshIntegration
    # turns on) is a common tmux-adjacent surprise; opt-in later if
    # actually wanted.
    enableZshIntegration = false;
  };
}
