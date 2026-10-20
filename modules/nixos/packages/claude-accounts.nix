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
pkgs.runCommand "claude-accounts" { } ''
  mkdir -p $out/bin
  install -m755 ${../../../bin/claude-use} $out/bin/claude-use
  patchShebangs $out/bin

  cat > $out/bin/claude <<'EOF'
  #!${pkgs.bash}/bin/bash
  CLAUDE_CONFIG_DIR="$(@out@/bin/claude-use dir)" || exit 1
  export CLAUDE_CONFIG_DIR
  exec @claude@ "$@"
  EOF
  substituteInPlace $out/bin/claude \
    --replace-fail @out@ $out \
    --replace-fail @claude@ ${claudeCode}/bin/claude
  chmod +x $out/bin/claude
''
