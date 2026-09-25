# Host-side tools for the agent sandbox's host scripts (system-plan.md
# §9.7-9.8): deterministic helpers only, no LLM runs on the host.
#
# - rbw: Bitwarden CLI used by bin/agent-secret-load to move a secret from
#   the vault into a podman secret for a sidecar (never into the agent
#   container). Chosen because the repo had no Bitwarden CLI yet and rbw
#   is in nixpkgs, keeps the vault unlocked in its own agent (several
#   secrets in a row don't re-prompt) and was checked against its --help
#   (1.15.0: password, --field, --raw JSON; no attachment download, hence
#   base64-in-a-field for binary secrets). One-time user setup is manual:
#   `rbw config set email ...` (+ `rbw config set base_url ...` for a
#   self-hosted server), then `rbw login`.
# - jq: agent-secret-load --notes reads the notes out of `rbw get --raw`.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    rbw
    jq
  ];
}
