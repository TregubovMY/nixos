# Managed settings of Claude Code on the HOST (/etc/claude-code/managed-settings.json).
#
# Why (review 2026-11-02, finding C1): the whole ~/.local/share/claude-accounts
# tree is mounted read-write into every agent-sandbox and into agent-vm
# (bin/agent-sandbox, modules/nixos/agent-vm.nix) so sessions and logins are
# shared. An agent inside can therefore edit an account's settings.json /
# .claude.json -- and anything it plants there is read by the NEXT `claude`
# started on the host, outside the sandbox. Two of the keys that run code:
# - hooks: shell commands on SessionStart etc.
#   -> allowManagedHooksOnly = true: only hooks from managed settings run
#   (there are none), so user/project/plugin hooks are ignored.
# - mcpServers (in .claude.json): a stdio MCP server is a command to run.
#   -> allowManagedMcpServersOnly + allowedMcpServers with the ONE server we
#   register ourselves (playwright, claude-use sync), matched by its command
#   (`serverCommand`) and NOT by name: the docs say plainly that a serverName
#   entry is no security control, the user (here: the agent) chooses names.
#   Docs: https://code.claude.com/docs/en/managed-mcp.md
# Other command-running keys (statusLine, apiKeyHelper, ...) are stripped from
# the account files by `claude-use sync` itself (bin/claude-use).
#
# allowManagedPermissionRulesOnly is NOT set here on purpose: the host's
# allow/ask/deny lists live in the account settings (claude-accounts.nix) and
# would stop applying. Not covered by this file: transcripts in shared/projects
# (a forged transcript can steer `claude --continue`) -- see docs/AGENT-SANDBOX.md.
#
# Applies to Claude Code started on the host. The sandbox rootfs and the VM
# have their own /etc (the VM writes its own managed-settings.json).
{ pkgs, ... }:
let
  claudeAccounts = pkgs.callPackage ./packages/claude-accounts.nix { };
in
{
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON {
    allowManagedHooksOnly = true;
    allowManagedMcpServersOnly = true;
    allowedMcpServers = [{ serverCommand = [ claudeAccounts.playwrightMcp ]; }];
  };
}
