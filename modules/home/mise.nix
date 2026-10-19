# mise -- version manager for ruby/node/etc, versions come from each
# project's .tool-versions, not hardcoded here (system-plan.md §5.3) --
# same instance the agent-sandbox image uses internally (§9.3).
{ pkgs, lib, ... }:
let
  # mise's ruby-build backend compiles pinned Rubies from source (it only
  # ships precompiled binaries for node/python/go, not ruby) -- on NixOS
  # that needs a build toolchain and library headers that just aren't on
  # a normal interactive PATH outside a nix-shell (no FHS /usr/include).
  # Reproduced live 2026-10-18 (`mise install ruby@2.5.1` for an old,
  # EOL Ruby the user actually needed): failed at `make -j 12` with
  # "make: command not found" -- `which make autoconf bison pkg-config
  # m4` were all empty on this host even though `gcc` happened to be on
  # PATH already (pulled in incidentally by modules/home/neovim.nix for
  # treesitter, not something this module should rely on).
  #
  # This is the exact same problem modules/nixos/packages/agent-sandbox.nix
  # already solved for the agent sandbox's ruby-build -- list and reasoning
  # copied from there (ruby-build wiki's suggested-build-environment,
  # https://github.com/rbenv/ruby-build/wiki#suggested-build-environment,
  # minus OpenSSL: ruby-build vendors/builds its own OpenSSL from source,
  # confirmed again in this same reproduction -- it downloaded and tried
  # to build openssl-1.1.1w). Declared fully here rather than assumed from
  # other modules/system packages, even where something (gcc, patch, perl)
  # already happens to be present some other way -- this module shouldn't
  # silently depend on neovim.nix or system packages for something it
  # needs itself; duplicate home.packages entries are harmless; nix dedups
  # identical store paths.
  rubyBuildToolchain = with pkgs; [
    gcc
    gnumake
    pkg-config
    autoconf
    bison
    patch
    gnum4
    perl
  ];
  # Plain package names only pull in each package's default ("out") output
  # -- the shared library, no headers. nixpkgs splits headers/pkg-config
  # files into a separate "dev" output for these (same as agent-sandbox.nix
  # confirmed via `nix eval .#legacyPackages.x86_64-linux.<pkg>.outputs`).
  # Ruby's own ./configure links against readline/libyaml(Psych)/
  # libffi(fiddle)/gdbm/ncurses and needs their headers at compile time.
  # libxcrypt has no separate "dev" output (headers ship in "out" already).
  rubyBuildLibs = with pkgs; [ zlib readline libyaml libffi gdbm ncurses ];
in
{
  # Gems install into the mise Ruby as usual (one shared dir per Ruby
  # version, not per project); the agent sandbox reads them from there
  # read-only and installs only missing ones into its own dir (GEM_PATH in
  # modules/nixos/packages/agent-sandbox.nix).
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    # mise defaults `all_compile` (its "always build from source instead of
    # downloading upstream's precompiled binary" setting) to true
    # specifically on NixOS/Alpine (mise.jdx.dev/configuration/
    # settings.html -- called out there as deprecated behavior, mise
    # 2027.8.0 drops this special case) -- presumably because on a plain
    # NixOS, a downloaded precompiled binary just fails to execute (no
    # /lib64/ld-linux-x86-64.so.2). That's no longer true here:
    # modules/nixos/nix-ld.nix already makes precompiled, dynamically-linked
    # binaries runnable system-wide. So mise's own NixOS special-case is now
    # actively counterproductive -- it was defaulting to a slow source
    # compile (needing a hand-declared build toolchain per language, see
    # rubyBuildToolchain below) when a plain downloaded binary would just
    # work. Reproduced live 2026-10-18: `mise install node@24.3.0` and
    # `mise install python@3.14` both fell into source builds and failed on
    # missing build tools (python/make not on PATH) before this was found.
    # Ruby is unaffected by this flag either way -- mise's ruby-build
    # backend has no precompiled-binary path on Linux at all, source build
    # is its only option, which is why rubyBuildToolchain/rubyBuildLibs
    # below still exist and are still needed.
    globalConfig.settings.all_compile = false;
  };

  home.packages = rubyBuildToolchain ++ map (p: p.dev) rubyBuildLibs ++ [
    pkgs.libxcrypt
  ];

  # Adding the libraries above to home.packages only gets their headers/
  # .so/.pc files symlinked into the user's profile directory -- it does
  # NOT make gcc/pkg-config look there. The nixpkgs gcc wrapper's search
  # path is hardcoded at wrap time to its own declared inputs (glibc and
  # its own headers), not to whatever home.packages happens to list; the
  # fix (confirmed working in agent-sandbox.nix's entrypoint, same
  # reasoning applies to a plain interactive shell) is pointing gcc/
  # pkg-config at them explicitly via these standard env vars, which both
  # tools search *in addition to* their hardcoded defaults. Nothing else
  # in this repo sets these (checked), so a plain assignment is fine --
  # no existing value to preserve.
  home.sessionVariables = {
    CPATH = lib.concatMapStringsSep ":" (p: "${p.dev}/include") rubyBuildLibs;
    LIBRARY_PATH = lib.concatMapStringsSep ":" (p: "${lib.getLib p}/lib") rubyBuildLibs;
    PKG_CONFIG_PATH = lib.concatMapStringsSep ":" (p: "${p.dev}/lib/pkgconfig") rubyBuildLibs;
  };
}
