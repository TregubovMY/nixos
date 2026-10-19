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
}
