# Disk & Boot Foundation Design — host `mimir`

## Goal

Declarative disk partitioning and boot for the real target machine (`mimir`,
disk `/dev/sdb`, user `max`) — disko + LUKS2 full-disk encryption + systemd-boot.
This is the foundation everything else (Hyprland desktop, home-manager,
secrets, package list) will sit on top of, per `system-plan.md` §2-4.

**Out of scope for this design** (deliberately deferred, not forgotten):
- Secure Boot / lanzaboote — separate design/plan later, once this boots reliably.
- `hosts/mimir/` itself and the real `hardware-configuration.nix` — created only
  as an explicit, separate step immediately before real installation (see
  "Real install boundary" below). This design's deliverable is the reusable
  modules plus a throwaway VM host that proves they work, not the real host
  directory.
- Hyprland, home-manager, sops-nix, the package list — separate designs.

## Context

`.trash/configuration.nix`/`disko.nix`/`flake.nix`/`home.nix` (retired from
git tracking, still on disk) are an earlier, unfinished attempt at this same
host: hostname `mimir`, disk `/dev/sdb`, user `max` — confirmed still correct.
That attempt never reached a real install and had **no LUKS** (plain GPT +
btrfs). This design ports its disk layout and adds LUKS2, per the confirmed
requirement in `system-plan.md` §2.

## Disk Architecture

**One LUKS2 container, not several.** Considered splitting `/home` into its
own LUKS container (independent unlock/passphrase) — rejected: on a
single-user laptop with physical access, a second passphrase prompt at boot
buys nothing, and btrfs subvolumes already provide the isolation (independent
snapshots, no shared-partition resize headaches) that separate LUKS
containers would otherwise be used for. One container, one passphrase prompt,
btrfs subvolumes inside — the standard, well-trodden pattern.

Layout:
```
GPT
├── ESP (1024M, vfat, /boot) — unencrypted, required: UEFI firmware must
│   read the bootloader before any LUKS unlock happens
└── LUKS2 container (rest of disk) — unlocked by passphrase, interactive
    prompt at every boot (no TPM/clevis auto-unlock — unnecessary for a
    personal machine with physical access, and adds an attack surface/
    complexity this doesn't need)
    └── btrfs, subvolumes:
        ├── root  → /
        ├── home  → /home
        ├── nix   → /nix
        └── swap  → swapfile subvolume (disko's native `swap.swapfile`
                     support), size ≥ physical RAM for hibernate (34G,
                     matching the old config's number — adjust the module
                     call if `mimir`'s actual RAM differs)
```

Swap stays **inside** the LUKS container — unencrypted swap on an otherwise
encrypted system is a real hole (secrets decrypted in RAM can get paged to
disk in plaintext), so this isn't a place to cut a corner.

## Hibernate (resume from suspend-to-disk)

Required. This is the one piece of real, unavoidable complexity in this
design: the resume offset for a btrfs swapfile can only be computed **after**
the swapfile physically exists on disk (`btrfs inspect-internal
map-swapfile`), which means it cannot be determined at eval-time, in a
`dry-build`, or even in `build-vm` against a throwaway disk — there is no
swapfile to inspect until a real (or realistic virtual) install has actually
happened.

Handling: this design's modules don't attempt resume configuration. It's a
**documented post-install step** (part of the implementation plan's real-install
task, not this design's reusable modules):
1. After first real boot, run `btrfs inspect-internal map-swapfile -r
   <path-to-swapfile>` to get the physical offset.
2. Add `boot.resumeDevice = "/dev/mapper/<luks-mapped-name>";` and
   `boot.kernelParams = [ "resume=/dev/mapper/<luks-mapped-name>"
   "resume_offset=<N>" ];` to `hosts/mimir/configuration.nix`.
3. `nixos-rebuild switch` to apply, then test hibernate for real.

A best-effort hibernate check inside the throwaway VM (QEMU does support
suspend-to-disk) is worth attempting during verification, but the real test
is on actual hardware — this is called out explicitly, not silently assumed
to work.

## File Structure

```
modules/nixos/
  disko-luks-btrfs.nix   # { device, swapSize ? "34G", ... }: parameterized
                          # disko module — GPT → ESP → LUKS2 → btrfs
                          # (root/home/nix/swap-subvolume). Reused by both
                          # the throwaway verification host below and the
                          # real hosts/mimir/ (created later).
  boot.nix                # systemd-boot + boot.initrd.systemd.enable
                          # (needed for a working LUKS unlock prompt under
                          # the modern systemd-based initrd). No separate
                          # luks.nix — disko already registers the LUKS
                          # device (boot.initrd.luks.devices) from the
                          # disk-layout module's own description; nothing
                          # LUKS-specific is left to configure at this layer.
hosts/
  test-disko-luks/        # throwaway, mirrors the existing hosts/test-vm/
    configuration.nix     # pattern — imports the two modules above with
                          # device = "/dev/vda". This is where the entire
                          # verification cycle below runs. Never touches
                          # real hardware.
```

`hosts/mimir/` is **not** created by this design/plan. Why: an earlier draft
of this design put a placeholder `hardware-configuration.nix` under
`hosts/mimir/` so `nix flake check` had something to evaluate — rejected on
reconsideration, because a placeholder file sitting in the real host's
directory is exactly the kind of thing that could get forgotten and mistaken
for real content. Proving the disko/boot modules work via a throwaway VM host
(the same pattern already established by `hosts/test-vm/` for the
dev-databases plan) avoids that risk entirely, and gives the parameterized
module a second, *real* caller from day one — not just a hypothetical future
second machine.

## Testing (per CLAUDE.md's disk-budget-aware dev cycle — nothing here touches `/dev/sdb`)

1. `nix flake check`
2. `nixos-rebuild dry-build --flake .#test-disko-luks`
3. The disko layout itself (ESP + LUKS2 + btrfs + subvolumes) run against a
   virtual qcow2 disk (8G, sparse) — confirms the partition table and LUKS
   container actually come up as described, independent of the full VM boot.
4. `nixos-rebuild build-vm --flake .#test-disko-luks` — confirms systemd-boot
   loads and the LUKS passphrase prompt actually appears against the virtual
   disk. Best-effort: attempt a QEMU suspend-to-disk/resume cycle here too.

## Real Install Boundary

Per `CLAUDE.md`'s core rule, nothing in this design or its implementation
plan touches `/dev/sdb` or runs `nixos-install` for real. Once the modules
above are built and pass every step above, the real install is a separate,
explicitly-requested follow-up:
1. Generate `hosts/mimir/hardware-configuration.nix` for real, on `mimir`
   itself, via `nixos-generate-config`.
2. Write `hosts/mimir/disk-config.nix` (calls `disko-luks-btrfs.nix` with
   `device = "/dev/sdb"`) and `hosts/mimir/configuration.nix` (hostName,
   timeZone `Europe/Moscow`, locale `ru_RU.UTF-8`, user `max`, imports the
   two files above plus `boot.nix`) — a few minutes of work once the modules
   are proven.
3. Register `nixosConfigurations.mimir` in the root `flake.nix`.
4. Real `nixos-install`, then the hibernate resume-offset step above.

This design's implementation plan ends at "verified in a throwaway VM" —
step 4 here is out of scope until explicitly requested.
