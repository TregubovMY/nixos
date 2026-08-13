# nix-ld: lets ordinary precompiled, dynamically-linked Linux binaries
# run on NixOS despite there being no real FHS layout (no
# /lib64/ld-linux-x86-64.so.2 by default -- NixOS ships an intentional
# stub loader there instead, nixos/modules/config/stub-ld.nix, that fails
# loudly on exactly this). Concretely fixes modules/home/mise.nix: mise's
# node/python/go backends download upstream precompiled binaries by
# default, which otherwise fail with "cannot execute: required file not
# found" (missing ELF interpreter) -- confirmed live in
# modules/nixos/packages/agent-sandbox.nix's own from-scratch container,
# which has no NixOS module system and needed the same fix hand-rolled
# there instead of this one-line toggle. This is the upstream-maintained
# module (nixos/modules/programs/nix-ld.nix), not a hand-rolled
# workaround -- one flag, default library set already covers the common
# cases (openssl/zlib/curl/glibc's own C++ runtime/...).
{
  programs.nix-ld.enable = true;
}
