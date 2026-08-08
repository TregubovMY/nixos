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

**Two LUKS2 containers, not one.** First draft put swap inside the root
container as a btrfs subvolume swapfile — reconsidered after research turned
up a real, documented problem: resume-from-hibernate through a btrfs
swapfile under `boot.initrd.systemd.enable` has a history of breaking
outright (nixpkgs issue #213122; a later Discourse thread from Sept 2025
suggests newer NixOS auto-detects the resume offset via EFI variables and
fixes this, but only when the swapfile isn't under `/home`, and community
consensus still leans toward treating btrfs-swapfile hibernate as
version-fragile). A **separate, dedicated swap partition** — not inside
btrfs at all — sidesteps that whole bug class and is the traditional,
well-trodden `resume=`-based mechanism. Confirmed against the [NixOS
wiki's Swap page](https://wiki.nixos.org/wiki/Swap): "If you want to use
hibernation, use a regular Full Disk Encryption with a fixed key.
Alternatively, you can encrypt the swap partition separately" — both
options it names are the ones weighed here.

This reopens "should swap get its own LUKS container," but not with a
second interactive password prompt: NixOS's initrd LUKS unlock automatically
retries an already-entered passphrase against later
`boot.initrd.luks.devices` entries, so as long as both containers are
formatted with the **same** passphrase, boot still only prompts once. A
real-world config search turned up the same pattern used manually
(`cryptsetup luksFormat` twice, "enter the same password" both times) — this
isn't a novel trick. It also avoids the alternative some guides suggest (a
keyfile for the swap container stored on the already-unlocked root
filesystem): that keyfile would sit in the initrd/boot area, readable by
anyone with physical access, undermining part of the point of encrypting
swap in the first place.

Layout:
```
GPT
├── ESP (1024M, vfat, /boot) — unencrypted, required: UEFI firmware must
│   read the bootloader before any LUKS unlock happens
├── LUKS2 "cryptroot" (rest of disk minus swap) — interactive passphrase
│   prompt at every boot (no TPM/clevis — unnecessary for a personal
│   machine with physical access, adds attack surface/complexity for no
│   real gain here)
│   └── btrfs, subvolumes:
│       ├── root  → /
│       ├── home  → /home
│       └── nix   → /nix
└── LUKS2 "cryptswap" (size ≥ physical RAM, 34G — matching the old config's
    number, adjust the module call if `mimir`'s actual RAM differs) — same
    passphrase as cryptroot, auto-unlocked by the initrd's passphrase retry
    (not a second prompt in practice; NOT `randomEncryption` — confirmed via
    disko's own issue tracker (#604) and the NixOS wiki that random-key
    swap encryption makes hibernation impossible outright, since the key
    doesn't survive a reboot)
    └── content.type = "swap", resumeDevice = true — disko's built-in flag
        for exactly this case, which declaratively sets `boot.resumeDevice`
        (see Hibernate below).
```

Swap stays encrypted either way — unencrypted swap on an otherwise encrypted
system is a real hole (secrets decrypted in RAM can get paged to disk in
plaintext), so that was never on the table.

## Hibernate (resume from suspend-to-disk)

Required. Read disko's own `lib/types/swap.nix` source directly (not just
docs/blog posts, per `CLAUDE.md`) to confirm how `resumeDevice = true` really
works: it sets `boot.resumeDevice = config.device;`, where `device` is
whatever block device disko threads down to this content block. For a plain
partition that's the partition itself; nested under a `luks` content block
(as here), disko's compositional model threads the **decrypted LUKS mapper
device** (e.g. `/dev/mapper/cryptswap`) down to the child content the same
way it already does for `luks → btrfs` (the officially documented,
widely-used pattern) — so `boot.resumeDevice` should end up correctly
pointing at the mapper device, not the raw encrypted partition.

**Honest caveat:** every committed example found (disko's own `example/`
directory, several public nixos-config repos) shows `resumeDevice`/
`randomEncryption` on a **bare** swap partition, or `luks → btrfs`/
`luks → filesystem` nesting — never `luks → swap` with `resumeDevice`
combined in one committed, working example. The mechanism is sound by
disko's own generic composition model and there's no code-level reason it
wouldn't work, but it isn't something to take on faith either. This is
exactly what the VM verification step exists for — Testing below explicitly
checks the *built* system's actual `boot.resumeDevice` value, not just that
the config evaluates.

If it turns out not to work as designed, the documented fallback (from the
NixOS wiki) is `swapDevices.*.encrypted.blkDev` — a NixOS-level option that
wires LUKS-encrypted swap independently of disko's swap-content type. Not
pursued as the first approach since mixing disko-level and NixOS-level disk
description for the same partition is messier than keeping disko as the
single source of truth, but noted here as a known escape hatch rather than
leaving a dead end if `resumeDevice` under `luks` doesn't pan out.

A full suspend-to-disk-and-resume cycle is realistically only trustworthy on
actual hardware — a QEMU attempt in the throwaway VM is worth doing as a
best-effort sanity check (confirming the built kernel params look right, and
that suspend-to-disk doesn't immediately error out), but isn't treated as
equivalent to a real-hardware pass.

## File Structure

```
modules/nixos/
  disko-luks-btrfs.nix   # { device, swapSize ? "34G", ... }: parameterized
                          # disko module — GPT → ESP → two LUKS2 containers
                          # (root: btrfs root/home/nix; swap: dedicated
                          # partition, same passphrase, resumeDevice = true).
                          # Reused by both the throwaway verification host
                          # below and the real hosts/mimir/ (created later).
  boot.nix                # systemd-boot + boot.initrd.systemd.enable
                          # (needed for a working LUKS unlock prompt under
                          # the modern systemd-based initrd). No separate
                          # luks.nix — disko already registers both LUKS
                          # devices (boot.initrd.luks.devices) from the
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
put a placeholder `hardware-configuration.nix` under `hosts/mimir/` so `nix
flake check` had something to evaluate — rejected on reconsideration,
because a placeholder file sitting in the real host's directory is exactly
the kind of thing that could get forgotten and mistaken for real content.
Proving the disko/boot modules work via a throwaway VM host (the same
pattern already established by `hosts/test-vm/` for the dev-databases plan)
avoids that risk entirely, and gives the parameterized module a second,
*real* caller from day one — not just a hypothetical future second machine.

## Testing (per CLAUDE.md's disk-budget-aware dev cycle — nothing here touches `/dev/sdb`)

1. `nix flake check`
2. `nixos-rebuild dry-build --flake .#test-disko-luks`
3. The disko layout itself (ESP + two LUKS2 containers + btrfs subvolumes +
   swap) run against a virtual qcow2 disk (8G, sparse) — confirms the
   partition table and both LUKS containers actually come up as described,
   independent of the full VM boot. Confirm the second LUKS unlock really is
   silent given a matching passphrase (not a second prompt).
4. `nixos-rebuild build-vm --flake .#test-disko-luks` — confirms systemd-boot
   loads and the LUKS passphrase prompt appears against the virtual disk.
   Inspect the built system's activated `boot.resumeDevice`/kernel params to
   confirm they point at the swap LUKS mapper device as expected (see the
   Hibernate caveat above — this is the step that actually settles it).
   Best-effort: attempt a QEMU suspend-to-disk/resume cycle too.

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
4. Real `nixos-install`, entering the **same** LUKS passphrase for both
   containers when prompted. Then a real hibernate test — the one thing that
   can only be confirmed on actual hardware, not before.

This design's implementation plan ends at "verified in a throwaway VM" —
step 4 here is out of scope until explicitly requested.
