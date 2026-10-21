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
  # NOT using programs.mise.globalConfig: it home-manager-symlinks
  # ~/.config/mise/config.toml into /nix/store, read-only -- any later
  # `mise use -g`/`mise install -g` (including this module's own
  # bootstrap below) tries to write INTO that same file and fails with
  # "Read-only file system" (reported live 2026-10-19,
  # `mise use -g go@1.26.9`, then reproduced by the bootstrap itself on
  # the next switch). Tried redirecting writes via a `write_targets`
  # setting first (mise.jdx.dev/configuration.html describes it) --
  # turned out not to exist in the installed mise 2026.10.3 at all
  # ("unknown field in ~/.config/mise/config.toml: settings.write_targets",
  # then the same Read-only error anyway since the real write still landed
  # on the Nix-managed file) -- a stale/future-version doc claim, not
  # verified against the actual binary before relying on it; don't repeat
  # that mistake here. Simplest correct fix: don't manage config.toml
  # through Nix/home-manager AT ALL, so mise owns that file completely
  # and both `mise use -g` and this module's own bootstrap write to a
  # plain, ordinary, writable file -- no split, no second file, no
  # precedence to reason about.
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };

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
  #
  # Set via env var, not globalConfig.settings (see above, this is the
  # replacement for that) -- confirmed live, `MISE_ALL_COMPILE=false mise
  # settings get all_compile` reports `false`, so this one setting doesn't
  # need a config file at all.

  home.packages = rubyBuildToolchain ++ map (p: p.dev) rubyBuildLibs ++ [
    pkgs.libxcrypt
  ];

  # Bootstrap go/node/python globally once, so a fresh install has them
  # immediately instead of needing `mise use -g` by hand first (asked
  # live 2026-10-19). "Stable" here: node's "lts" alias (its actual
  # meaning of "stable" -- the bleeding-edge @latest train is a different,
  # faster-moving thing for node specifically); go/python have no such
  # split, @latest IS their stable release. Writes to the now-plain
  # ~/.config/mise/config.toml (confirmed live: `mise use` resolves and
  # installs, but writes the alias strings themselves to the TOML, not
  # the resolved version -- so this stays "lts"/"latest", tracking
  # upstream, not frozen to today's exact version).
  #
  # Still entryAfter "linkGeneration", even though config.toml is no
  # longer a home-manager-linked file in THIS generation: on the machine
  # this was found on, it still IS one from the previous (broken)
  # generation -- cleanOldGen (part of the "linkGeneration" DAG step,
  # confirmed in the real generated script: it calls cleanOldGen then
  # linkNewGen) is what actually removes that stale symlink. Checking for
  # the file's existence any earlier (e.g. at "writeBoundary", which runs
  # before "linkGeneration") would see the not-yet-cleaned-up old symlink,
  # skip the bootstrap, and leave no config.toml at all once cleanup
  # catches up later in the same run.
  #
  # Guarded by the file's own existence -- same idempotency discipline as
  # shell.nix's codeDirs: runs once ever, so it never fights a version
  # changed later by hand with `mise use -g`.
  home.activation.miseGlobalTools = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [ ! -e "$HOME/.config/mise/config.toml" ]; then
      run ${pkgs.mise}/bin/mise use --global -y node@lts go@latest python@latest
    fi
  '';

  # Claude Code from npm (2026-10-21): the Nix package is immutable and
  # lags npm (2.1.300 vs 2.1.306), while an npm install into a writable
  # prefix updates itself (autoUpdatesChannel=latest, modules/nixos/packages/
  # claude-accounts.nix). The `claude` wrapper prefers ~/.npm-global/bin/claude
  # and falls back to the Nix package, so a failure here only leaves the
  # older version. Node comes from mise (the bootstrap above), npm via
  # `mise exec`. Idempotent: skipped once installed -- updates are Claude
  # Code's own job after that. Never fails the switch (offline, mise down).
  home.activation.claudeCodeNpm = lib.hm.dag.entryAfter [ "miseGlobalTools" ] ''
    if [ ! -x "$HOME/.npm-global/bin/claude" ]; then
      run ${pkgs.mise}/bin/mise exec node@lts -- \
        npm install -g --prefix "$HOME/.npm-global" @anthropic-ai/claude-code \
        || echo "claudeCodeNpm: npm install failed, the Nix claude-code stays in use" >&2
    fi
  '';

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
    MISE_ALL_COMPILE = "false";
  };
}
