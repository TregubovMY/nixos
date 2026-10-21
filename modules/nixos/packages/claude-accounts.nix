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
  # Browser for the agent (playwright MCP), registered in every account by
  # claude-use sync (CLAUDE_BASE_MCP). Same on the host and in the sandbox:
  # - Chromium from nixpkgs (the NixOS-compatible build), not Playwright's own
  #   download;
  # - headless unless a Wayland session is passed in (a sandbox started with
  #   `agent-sandbox --gui` / a host Hyprland session) -> a visible window;
  #   PLAYWRIGHT_MCP_HEADLESS=1 forces headless even then;
  # - --no-sandbox only inside agent-sandbox: Chromium's own sandbox cannot
  #   nest in rootless podman (the container is the boundary there).
  playwrightMcp = pkgs.writeShellScript "playwright-mcp-launcher" ''
    args=(--executable-path ${pkgs.chromium}/bin/chromium)
    [ -z "''${AGENT_SANDBOX_NAME:-}" ] || args+=(--no-sandbox)
    if [ -n "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${PLAYWRIGHT_MCP_HEADLESS:-}" ]; then
      export NIXOS_OZONE_WL=1
    else
      args+=(--headless)
    fi
    exec ${pkgs.playwright-mcp}/bin/playwright-mcp "''${args[@]}" "$@"
  '';
  baseMcp = pkgs.writeText "claude-base-mcp.json" (builtins.toJSON {
    mcpServers.playwright = {
      type = "stdio";
      command = "${playwrightMcp}";
      args = [ ];
    };
  });

  baseSettings = pkgs.writeText "claude-base-settings.json" (builtins.toJSON {
    attribution = {
      commit = "";
      pr = "";
      sessionUrl = false;
    };
    model = "claude-sonnet-5-5";
    # Self-updating npm install in the sandbox follows the latest channel
    # (chosen 2026-10-21 over "stable", which is ~1 week behind).
    autoUpdatesChannel = "latest";
    # Permissions (2026-10-21). The sandbox (agent-sandbox) is the real
    # boundary; these rules are the second line and apply in EVERY mode,
    # bypass included (deny always wins). allow = only universal local git
    # operations (read-only commands need no rule, language tools belong in
    # the project's .claude/settings.json; the rest goes through auto mode);
    # deny = what an agent must not do even inside the sandbox; ask = publishing and destructive/container
    # commands, only after the user confirms (no ssh in the sandbox).
    # Arrays are replaced, not merged, by claude-use sync: this list wins
    # over an account's own permissions.allow/deny.
    permissions = {
      defaultMode = "auto";
      allow = [
        "Bash(git add:*)" "Bash(git commit:*)" "Bash(git stash:*)"
        "Bash(git switch:*)" "Bash(git checkout:*)" "Bash(git branch:*)"
        "Bash(openspec:*)"
      ];
      # ask = allowed only after the user confirms each time (deny > ask > allow).
      ask = [
        "Bash(git push:*)" "Bash(git reset --hard:*)" "Bash(git clean:*)"
        "Bash(git worktree remove:*)" "Bash(podman:*)" "Bash(docker:*)"
      ];
      deny = [
        "Read(~/.ssh/**)" "Read(./.env)" "Read(./.env.*)" "Read(./**/.env)" "Read(./**/.env.*)"
        "Read(./**/*.pem)" "Read(./**/*.key)" "Read(./secrets/**)"
        "Edit(~/.config/agent-sandbox/**)" "Edit(~/.local/share/claude-accounts/*/.credentials.json)"
        "Bash(git config --global:*)"
        "Bash(sudo:*)" "Bash(nixos-rebuild:*)"
        "Bash(rm -rf /:*)" "Bash(rm -rf ~:*)" "Bash(rm -rf $HOME:*)" "Bash(chmod -R 777:*)"
      ];
    };
    # Token diet (2026-10-20, analysis of session transcripts): the 1M window
    # means autocompact only fires near 967K, so sessions grew to 400-960K and
    # every call re-read all of it. Compact at ~370K instead; drop what is
    # loaded into every request and never used (claude.ai-synced skills,
    # connectors, the Artifact tool, rarely-used bundled skills).
    env.CLAUDE_CODE_AUTO_COMPACT_WINDOW = "400000";
    syncClaudeAiSkills = false;
    disableClaudeAiConnectors = true;
    enableArtifact = false;
    skillOverrides = {
      artifact-design = "off";
      artifact-diagramming = "off";
      artifact-capabilities = "off";
      dataviz = "off";
      keybindings-help = "off";
      fewer-permission-prompts = "off";
      loop = "off";
      plugin-authoring = "off";
      schedule = "user-invocable-only";
      claude-in-chrome = "user-invocable-only";
      code-review = "user-invocable-only";
      simplify = "user-invocable-only";
      security-review = "user-invocable-only";
      init = "user-invocable-only";
      run = "user-invocable-only";
      claude-api = "user-invocable-only";
    };
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
  CLAUDE_BASE_SETTINGS=@base@ CLAUDE_BASE_MCP=@mcp@ PATH=@jq@/bin:$PATH @out@/bin/claude-use sync "$CLAUDE_CONFIG_DIR" || true
  # npm install (sandbox: $NPM_CONFIG_PREFIX, a writable volume -> Claude Code
  # self-updates) wins over the immutable Nix store binary; absent -> Nix one.
  npm_claude="''${NPM_CONFIG_PREFIX:-$HOME/.npm-global}/bin/claude"
  if [ -x "$npm_claude" ]; then exec "$npm_claude" "$@"; fi
  exec @claude@ "$@"
  EOF
  substituteInPlace $out/bin/claude \
    --replace-fail @out@ $out \
    --replace-fail @claude@ ${claudeCode}/bin/claude \
    --replace-fail @base@ ${baseSettings} \
    --replace-fail @mcp@ ${baseMcp} \
    --replace-fail @jq@ ${pkgs.jq}
  chmod +x $out/bin/claude
''
