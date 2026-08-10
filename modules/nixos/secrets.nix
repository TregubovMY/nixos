# Minimal sops-nix wiring for the one secret that survived the move to
# Bitwarden (system-plan.md §6/§7, 2026-08-10) — the GPG key used to sign
# git commits. SSH keys and the Throne proxy config went to Bitwarden
# instead; sops-nix's remaining scope is this narrow on purpose, not an
# oversight.
#
# sops.age.sshKeyPaths derives the age decryption key from the host's own
# SSH host key (ssh-to-age) — this only works once a real host has
# generated one, which hosts/mimir/ hasn't (doesn't exist yet). This
# module is complete and buildable without that: secrets/secrets.yaml with
# real content, and .sops.yaml with a real recipient, are added as a
# real-install-time follow-up (see docs/superpowers/specs/
# 2026-08-10-secrets-design.md "Real Install Boundary") — not this plan's
# job. Verified via a vendored, adapted copy of sops-nix's own
# `age-ssh-keys` test instead (see modules/nixos/secrets-test/), which
# proves the mechanism without needing a real host's key to exist. Not
# upstream's `ssh-keys` test (RSA host key) — that one exercises
# sops.gnupg.sshKeyPaths (ssh-to-pgp), a different mechanism from the
# sops.age.sshKeyPaths this module actually uses; see
# modules/nixos/secrets-test/ssh-decryption.nix's header for why.
{ ... }:
{
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # Consumed later (git commit signing config) once a home-manager/user
  # config layer exists — config.sops.secrets."gpg_key".path is the
  # decrypted file's path once that layer is built. Not this plan's job.
  sops.secrets."gpg_key" = { };
}
