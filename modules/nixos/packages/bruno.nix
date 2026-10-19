# Bruno (https://github.com/usebruno/bruno, MIT) -- API client.
# nixpkgs ships 4.0.0, which rejects newer collections with "The collection
# is not valid (neither bruno.json nor opencollection.yml found)":
# opencollection.yml support came with a later upstream release. Hence the
# latest upstream release here (2026-10-19: v4.2.1).
#
# Source: upstream's official x86_64 AppImage from GitHub Releases
# (https://github.com/usebruno/bruno/releases/tag/v4.2.1). Building from
# source was rejected: it's an Electron npm monorepo (nixpkgs builds it via
# buildNpmPackage with a hand-maintained npmDepsHash), far heavier than
# wrapping the prebuilt release; fallback if the AppImage stops working.
# To update: bump version, take the new hash with
#   nix store prefetch-file <AppImage url>
{ lib, appimageTools, fetchurl }:

let
  pname = "bruno";
  version = "4.2.1";
  src = fetchurl {
    url = "https://github.com/usebruno/bruno/releases/download/v${version}/bruno_${version}_x86_64_linux.AppImage";
    hash = "sha256-9rd9wyLdV7lTeBWJpEaIcjzzwGo1E8XDTQd8111kqUE=";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  meta = {
    description = "API client (latest upstream AppImage)";
    homepage = "https://www.usebruno.com";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "bruno";
  };
}
