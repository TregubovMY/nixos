# Machine "demiurge". Everything shared lives in ../common.nix; this file only
# names the machine. Its hardware report, ./facter.json, is written by
# bin/install-host on the machine itself and committed.
{
  imports = [ ../common.nix ];
  networking.hostName = "demiurge";

  # Throne (the proxy) is already configured and running on this specific
  # host -- see hosts/common.nix's own comment for why this can't be the
  # shared default (breaks a fresh install's first build on any OTHER
  # host, before ITS Throne exists yet).
  desktopApps.rubymine.enable = true;

  # The agent VM (modules/nixos/agent-vm.nix) sees exactly these host
  # folders, at the same paths (they were the folders of the old
  # agent-sandbox groups my/work-rnds). A read-write mount is a channel back
  # to the host (planted .git/hooks, .envrc...): see the option's text.
  agentVm = {
    mounts = [
      { path = "/home/max/code/my"; }
      { path = "/home/max/code/learn"; }
      { path = "/home/max/code/sfedu"; }
      { path = "/home/max/code/work/rnds"; }
    ];
    claudeAccounts = [ "personal" "work" ];
    # kandev puts its task worktrees here, so they are visible on the host
    # (inside the rw mount of ~/code/work/rnds; not a git repository itself).
    kandevTasksDir = "/home/max/code/work/rnds/.worktrees";
  };
}
