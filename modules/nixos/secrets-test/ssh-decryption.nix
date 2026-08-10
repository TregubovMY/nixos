# Vendored + adapted from sops-nix's own upstream test suite
# (checks/nixos-test.nix) — specifically the `age-ssh-keys` test, NOT the
# `ssh-keys` test this plan's brief originally pointed at. See the
# "Deviation from the brief" note below for why.
#
# Source: https://github.com/Mic92/sops-nix
# Pinned rev (matches this repo's flake.lock "sops-nix" input, re-fetched
# fresh from this exact rev rather than trusted from the brief's quote —
# per this repo's "verify against real pinned source" convention):
#   f1406619a3884cd5c47992a70b8b35c9c0fcb4c9
# Fetched: 2026-08-10.
#
# Deviation from the brief: the plan brief quoted upstream's `ssh-keys`
# test (RSA host key, testAssets + "/ssh-key") and described it as
# exercising "a real ssh-to-age conversion". Verified by hand before
# vendoring (per this task's Step 1 instructions) that this description
# doesn't hold: `ssh-to-age` only converts ed25519 keys — running
# upstream's own `ssh-to-age` binary against the RSA fixture fails with
# "got *rsa.PrivateKey key type but: only ed25519 keys are supported".
# With an RSA services.openssh.hostKeys entry, sops-nix's own module
# (modules/sops/default.nix: `age.sshKeyPaths` defaults to the *ed25519*
# hostKeys, `gnupg.sshKeyPaths` defaults to the *rsa* ones) instead routes
# decryption through SOPS_GPG_EXEC / ssh-to-pgp — a different mechanism
# entirely from what this repo's real modules/nixos/secrets.nix configures
# (`sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]`, the age
# path). Vendoring `ssh-keys` as instructed would have produced a test
# that passes while silently proving the wrong mechanism.
#
# Vendored `age-ssh-keys` instead (ed25519 host key), which does exercise
# ssh-to-age, and confirmed by hand: converting fixtures/ssh-key with
# upstream's own `ssh-to-age -private-key` produces an age identity that
# `sops -d` (with SOPS_AGE_KEY_FILE pointed at it) actually uses to decrypt
# fixtures/secrets.yaml, yielding `test_key: test_value`. Simplified from
# upstream's version: dropped `sops.age.keyFile` / `sops.age.generateKey`
# (upstream uses those only to check that appending a second, unrelated,
# freshly-generated age key doesn't break anything — out of scope for what
# this test needs to prove). Kept upstream's secret name `test_key` as-is
# (Step 2 naming choice) rather than re-encrypting a fixture named
# `gpg_key`: simplest option, needs no sops/age re-encryption tooling, and
# this test was never meant to touch the real `gpg_key` secret anyway.
#
# WHY this exists / what it does and does NOT prove: this proves the
# sops-nix *mechanism* — a real SSH host key converted via ssh-to-age into
# a real age identity, used at real NixOS activation time to decrypt a
# real sops-encrypted file — actually works in this repo's context (same
# sops-nix flake input, same nixpkgs). It does NOT prove anything about
# `hosts/test-secrets/` or the real `gpg_key` secret's content: the SSH
# key here (fixtures/ssh-key) is a fixed, published, throwaway upstream CI
# fixture (see fixtures/README.md for why it's safe to commit) standing in
# for a real host's own SSH host key, which doesn't exist yet — no real
# host has been installed (see docs/superpowers/specs/
# 2026-08-10-secrets-design.md, "Real Install Boundary"). Real
# recipient/key generation against a real host key is a real-install-time
# step, not this plan's job.
{
  name = "sops-nix-ssh-decryption";

  nodes.machine =
    { ... }:
    {
      services.openssh.enable = true;
      services.openssh.hostKeys = [
        {
          type = "ed25519";
          path = ./fixtures/ssh-key;
        }
      ];

      sops.defaultSopsFile = ./fixtures/secrets.yaml;
      sops.secrets.test_key = { };
    };

  testScript = ''
    start_all()
    machine.succeed("cat /run/secrets/test_key | grep -q test_value")
  '';
}
