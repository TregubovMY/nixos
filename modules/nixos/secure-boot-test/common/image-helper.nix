# Vendored, byte-for-byte copy of lanzaboote's
# nix/tests/lanzaboote/common/image-helper.nix (pinned rev
# 7c9a54a7f87b4539ddbd8bda09a8a5f5f9361aa9, matching this repo's
# flake.lock — see ../systemd-initrd.nix for the full provenance note). No
# path literals here, so no adjustment was needed.
#
# Generates the Python testScript prefix that boots the machine off a
# qcow2 overlay of the repart-built image (rather than the test framework's
# usual root-over-9p share), then reboots once so systemd-boot's
# auto-enrollment of the ESP's baked-in UEFI auth variables actually runs
# before the real assertions in systemd-initrd.nix's testScript execute.
{ machine, ... }:
''
  import os
  import subprocess
  import tempfile

  tmp_disk_image = tempfile.NamedTemporaryFile()

  subprocess.run([
    "${machine.virtualisation.qemu.package}/bin/qemu-img",
    "create",
    "-f",
    "qcow2",
    "-b",
    "${machine.system.build.image}/${machine.image.fileName}",
    "-F",
    "raw",
    tmp_disk_image.name,
  ])

  # Set NIX_DISK_IMAGE so that the qemu script finds the right disk image.
  os.environ['NIX_DISK_IMAGE'] = tmp_disk_image.name

  # Enroll keys via systemd-boot by rebooting
  ${machine.networking.hostName}.start(allow_reboot=True)
  ${machine.networking.hostName}.connected = False
''
