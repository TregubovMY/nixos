# `claude` wrapper + `claude-use`: several Claude accounts, switched with
# one command (design and file layout: the header of bin/claude-use).
#
# The wrapper REPLACES the plain claude-code in PATH rather than sitting
# next to it: every launcher (a shell, the Hyprland keybind, an IDE, an
# orchestrator inside agent-sandbox) must pick the account the same way, and
# a shell alias would only cover interactive zsh. It only exports
# CLAUDE_CONFIG_DIR and execs the real binary -- no behaviour of claude-code
# itself is changed. claude-code is taken from the `claudeCode` argument so
# the sandbox and the host wrap the same store path.
{ pkgs, claudeCode ? pkgs.claude-code }:
let
  # Common settings for EVERY account, host and sandbox alike: merged into
  # each account's settings.json before each launch (claude-use sync; these
  # keys win, the account's other keys stay). Declarative on purpose: one
  # place in git instead of editing settings.json per account by hand.
  # - attribution: empty strings drop the "Co-Authored-By: Claude" trailer and
  #   the PR footer; no session URL in commits (requested 2026-10-20).
  # - model: Sonnet 5.5 by default.
  # - permissions.defaultMode "auto": auto mode (a classifier approves routine
  #   actions, asks on risky ones) instead of prompting for each.
  baseSettings = pkgs.writeText "claude-base-settings.json" (builtins.toJSON {
    attribution = {
      commit = "";
      pr = "";
      sessionUrl = false;
    };
    model = "claude-sonnet-5-5";
    permissions.defaultMode = "auto";
  });
in
pkgs.runCommand "claude-accounts" { } ''
  mkdir -p $out/bin
  install -m755 ${../../../bin/claude-use} $out/bin/claude-use
  install -m755 ${../../../bin/ai} $out/bin/ai
  patchShebangs $out/bin

  cat > $out/bin/claude <<'EOF'
  #!${pkgs.bash}/bin/bash
  CLAUDE_CONFIG_DIR="$(@out@/bin/claude-use dir)" || exit 1
  export CLAUDE_CONFIG_DIR
  CLAUDE_BASE_SETTINGS=@base@ PATH=@jq@/bin:$PATH @out@/bin/claude-use sync "$CLAUDE_CONFIG_DIR" || true
  exec @claude@ "$@"
  EOF
  substituteInPlace $out/bin/claude \
    --replace-fail @out@ $out \
    --replace-fail @claude@ ${claudeCode}/bin/claude \
    --replace-fail @base@ ${baseSettings} \
    --replace-fail @jq@ ${pkgs.jq}
  chmod +x $out/bin/claude
''
