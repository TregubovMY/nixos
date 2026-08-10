# Secrets (sops-nix, GPG key only) Design

## Goal

A minimal `modules/nixos/secrets.nix` (sops-nix) covering the one secret
that stayed after SSH keys and the Throne proxy config moved to Bitwarden
(`system-plan.md` §6/§7, decided 2026-08-10): the GPG key used for signing
git commits. Verified in a throwaway VM using sops-nix's own established
test pattern, not a from-scratch one. Real recipient/key generation stays
a real-install-time step, same "Real Install Boundary" shape as the disk/
boot and Secure Boot plans.

## Context

`system-plan.md` §6 already describes the shape (age key via `ssh-to-age`
from the host's own SSH host key, `secrets/secrets.yaml`, `.sops.yaml`).
Researched sops-nix's actual current state (flake input, module, test
patterns) rather than trusting that section's age — it predates this
session's Bitwarden decision and was written before checking sops-nix's
real test infrastructure.

## The chicken-and-egg problem (why this plan's test differs from disk/boot's and Secure Boot's)

Real `ssh-to-age` derives the age recipient from a host's **own** SSH host
key — which doesn't exist until first boot on a real machine (or a
freshly-generated one each time in a throwaway VM). A real "encrypt
`secrets.yaml` for this recipient" step can't run at Nix-build time against
a VM that hasn't booted yet. Checked whether sops-nix's own test suite
solves this dynamically (matching how disko's `makeDiskoTest` and
lanzaboote's own test were reusable, tested infrastructure) — it does
**not**: `checks/nixos-test.nix` in sops-nix's own repo sidesteps the
problem with a **static, pre-generated** `age-keys.txt` fixture copied into
the VM via `boot.initrd.postDeviceCommands`, tested against a fixed
`secrets.yaml` — not a dynamic ssh-to-age round trip. No public example of
a real dynamic version was found. Building one from scratch would be
disproportionate effort for a plan whose entire payload is one GPG key —
smaller in scope than either of the last two plans, it shouldn't cost more
in novel test-infrastructure work than either did.

**Decision:** reuse sops-nix's own static-fixture test pattern (a real,
proven, upstream-maintained approach — matches this repo's "use existing
solutions" rule) rather than inventing a dynamic ssh-to-age VM test. This
proves the *mechanism* (sops-nix module wiring, activation-time decryption,
secret file materializes at the expected path with the expected content)
without needing the real ssh-to-age chain to exist yet — which it can't,
until `hosts/mimir/` is real.

**What this means is NOT tested by this plan, named explicitly:** the real
`ssh-to-age` derivation from an actual host's actual SSH host key. That's
inherently a real-install-time step (confirmed via real-world sops-nix
deployment write-ups: the documented workflow everywhere is "provision
first with no secrets, get the real host's SSH key, add it as a recipient,
commit `secrets.yaml`, redeploy" — not something available before a host
exists). Matches this repo's now-established pattern of naming, not hiding,
the boundary between "VM-proven mechanism" and "real hardware needed."

## Module

```
modules/nixos/secrets.nix
```
```nix
{ config, ... }:
{
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets."gpg_key" = { };
  # Consumed later (git commit signing config) once a home-manager/user
  # config layer exists — config.sops.secrets."gpg_key".path is the
  # decrypted file's path once that layer is built. Not this plan's job.
}
```
Flake input: `sops-nix = { url = "github:Mic92/sops-nix"; inputs.nixpkgs.follows = "nixpkgs"; };`
Module import: `sops-nix.nixosModules.sops`.

`secrets/secrets.yaml` and `.sops.yaml` are **not** created with real
content by this plan — `.sops.yaml` needs a real recipient (a real host's
age-derived public key) that doesn't exist yet; committing a `secrets.yaml`
encrypted for nobody real would be a hollow gesture. The throwaway test
(below) uses its own separate, disposable fixture — not this pair.

## Test Host

```
hosts/test-secrets/   # throwaway, mirrors the established pattern
  configuration.nix    # imports modules/nixos/secrets.nix, a fixture
                        # secrets.yaml + age key checked in ONLY under
                        # this test's own scope (clearly separate from
                        # the real secrets/secrets.yaml above)
```
Reusing sops-nix's actual `checks/nixos-test.nix` shape: a static test-only
age keypair (generated once, checked in as an obvious test fixture — same
category as lanzaboote's own published test UEFI keys, not a real secret,
same "why this is safe to commit" documentation pattern used for those),
a `secrets/secrets.yaml` fixture encrypted against it containing a dummy
`gpg_key` value, `boot.initrd.postDeviceCommands` seeding the test key into
the VM. Assertion: the decrypted file exists at `config.sops.secrets."gpg_key".path`
with the expected dummy content — proves activation-time decryption really
works in this repo's context.

**No disko/LUKS layout in this test host** — sops-nix's own upstream test
doesn't use one either, and activation-time secret decryption is orthogonal
to disk encryption (sops-nix decrypts *after* the system is already up and
the root filesystem already mounted, regardless of whether that filesystem
sits on LUKS). Mirrors `hosts/test-vm/`'s plain shape (plain `fileSystems`,
no disko) rather than `hosts/test-disko-luks/`'s — pulling disko in here
would test nothing extra and just add build cost.

## Testing

1. `nix flake check --no-build` — eval-only, fast, routine.
2. `nix flake check -L` (or equivalent nixosTest invocation) — the real
   activation-time decryption check, adapted from sops-nix's own test.

## Real Install Boundary

Same shape as the last two plans: nothing here generates a real age key,
nothing derives a real `ssh-to-age` recipient, `secrets/secrets.yaml`
carries no real content, `hosts/mimir/` remains untouched/nonexistent. The
real sequence (documented, not automated by this plan): install `mimir`
for real → get its real SSH host key → `ssh-to-age` → add as a `.sops.yaml`
recipient → `sops secrets/secrets.yaml` to add the real GPG key → commit →
redeploy.
