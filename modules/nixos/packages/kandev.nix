# kandev (https://github.com/kdlbs/kandev, AGPL-3.0) -- agent kanban board.
# Not in nixpkgs. Packaged here so it is just another tool inside
# agent-sandbox (one sandbox, boards are programs in it -- decided
# 2026-10-06), replacing the separate kandev-sandbox container that ran
# upstream's Docker image.
#
# Source: upstream's prebuilt npm runtime bundle @kdlbs/runtime-linux-x64,
# version 0.97.0; the hash is the registry's own `dist.integrity`
# (https://registry.npmjs.org/@kdlbs/runtime-linux-x64/0.97.0). The `kandev`
# npm wrapper does nothing but run <bundle>/bin/kandev with
# KANDEV_BUNDLE_DIR set, so the wrapper below does that directly, no Node.
# Built from source would need Go 1.26 + Node 24 + pnpm and embeds the web
# UI at build time -- fallback if this binary stops being acceptable.
#
# All bin/agentctl* helpers stay, including darwin/arm64 ones: kandev
# validates every platform helper at startup (it copies them into
# executors) and refused to start when they were trimmed (earlier WIP).
#
# KANDEV_NO_BROWSER: never try to open a browser from inside the sandbox.
# To update: bump version, take the new `dist.integrity` from the registry.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:

stdenv.mkDerivation rec {
  pname = "kandev";
  version = "0.97.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@kdlbs/runtime-linux-x64/-/runtime-linux-x64-${version}.tgz";
    hash = "sha512-diz8wbTlhv2MIOqgW7Z/jlfPFOmrb0JQu62PRODo6NzTu1sXra7AfnbpwQsEC8iyNIGTslUVqMWnZi8lXiEJ6g==";
  };

  # npm tarballs unpack into package/
  sourceRoot = "package";

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib ];

  dontBuild = true;
  dontStrip = true; # large Go binaries; stripping gains little
  # The darwin helpers are Mach-O, autoPatchelf must not touch them.
  autoPatchelfIgnoreMissingDeps = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/kandev $out/bin
    cp -r . $out/lib/kandev/
    makeWrapper $out/lib/kandev/bin/kandev $out/bin/kandev \
      --set KANDEV_BUNDLE_DIR $out/lib/kandev \
      --set-default KANDEV_NO_BROWSER 1
    runHook postInstall
  '';

  meta = {
    description = "Agent kanban board / orchestrator (prebuilt upstream runtime)";
    homepage = "https://github.com/kdlbs/kandev";
    license = lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "kandev";
  };
}
