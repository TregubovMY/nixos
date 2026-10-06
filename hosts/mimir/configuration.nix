# Machine "mimir" (the laptop). Everything shared lives in ../common.nix;
# this file only names the machine. Its hardware report, ./facter.json, is
# written by bin/install-host on the machine itself and committed.
{
  imports = [ ../common.nix ];
  networking.hostName = "mimir";
}
