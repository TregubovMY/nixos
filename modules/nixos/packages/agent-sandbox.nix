# Podman image for sandboxed AI coding agents (claude-code/opencode).
# Design: system-plan.md §9. Language runtimes (ruby/node/...) are
# deliberately NOT baked in here — mise resolves them per-project at
# container start (see the entrypoint below), so this image stays
# generic across every project instead of needing a rebuild per stack.
{ pkgs }:

let
  # podman's `--userns=keep-id` runs the container's process under the
  # *host* uid — but this minimal image's /etc/passwd only knows about
  # the uid baked in at build time, so tools that call getpwuid() (git,
  # bash prompt, mise) fail with "I have no name!" for any other host
  # uid. Standard fix: synthesize the missing /etc/passwd entry for
  # whatever uid we're actually running as, before doing anything else.
  #
  # Checked `dockerTools.fakeNss` (nixpkgs' purpose-built helper for
  # "getpwuid()/getgrgid() needs to succeed in a minimal image") before
  # writing this by hand, per CLAUDE.md "Искать готовые решения" — it
  # doesn't fit: `fakeNss.extraPasswdLines` bakes specific uid/gid lines
  # in at *build* time (see nixpkgs pkgs/by-name/fa/fakeNss/package.nix),
  # but the whole problem here is that the uid is only known at *run*
  # time (`--userns=keep-id` maps to whatever the host user's uid is,
  # which varies per machine/user). So the entry has to be synthesized by
  # the entrypoint script at container start, not by the image build —
  # fakeNss can't help with that. This append-to-/etc/passwd-at-runtime
  # approach, made writable via `extraCommands` below, mirrors the
  # well-documented OpenShift "Support Arbitrary User IDs" pattern:
  # https://docs.openshift.com/container-platform/4.16/openshift_images/create-images.html#images-create-guide-openshift_create-images
  entrypoint = pkgs.writeShellScript "agent-sandbox-entrypoint" ''
    set -euo pipefail

    if ! getent passwd "$(id -u)" > /dev/null 2>&1; then
      echo "agent:x:$(id -u):$(id -g)::/home/agent:${pkgs.bashInteractive}/bin/bash" >> /etc/passwd
    fi

    export HOME=/home/agent
    export MISE_DATA_DIR=/home/agent/.local/share/mise
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    # `dockerTools.buildLayeredImage`'s `contents` merges every listed
    # package's outputs into shared top-level dirs (/bin, /lib, /include,
    # /lib/pkgconfig, ...) via symlinks — confirmed directly: `zlib.dev`
    # in `contents` below does put a `/include/zlib.h -> /nix/store/...`
    # symlink in the image. But gcc (even the Nix-wrapped one baked into
    # this image) does NOT search `/include`/`/lib` by default — its
    # search path is hardcoded at wrap time to the specific store paths
    # of its own declared inputs (glibc, its own headers), which don't
    # include whatever `.dev` packages this image happens to list.
    # Found during Task 6 end-to-end testing: ruby-build's OpenSSL build
    # failed with "zlib.h: No such file or directory" even though
    # `zlib.dev` was present in the image and `/include/zlib.h` resolved
    # fine by hand — gcc simply wasn't told to look there. CPATH/
    # LIBRARY_PATH are plain-gcc (and generic Unix toolchain) environment
    # variables that get searched in addition to the hardcoded defaults,
    # so pointing them at the buildLayeredImage-merged dirs fixes this
    # for every current and future `.dev`/library package in `contents`
    # at once, instead of patching each individual build tool's flags.
    # PKG_CONFIG_PATH is the pkg-config equivalent, for anything in the
    # Ruby build (or an agent's own project build) that looks up its
    # dependencies that way instead of a bare compile check.
    export CPATH=/include
    export LIBRARY_PATH=/lib
    export PKG_CONFIG_PATH=/lib/pkgconfig

    cd /workspace
    # Only run mise install if the project actually pins versions —
    # an agent working on a non-mise project shouldn't wait on this.
    if [ -f .tool-versions ] || [ -f mise.toml ] || [ -f .mise.toml ]; then
      mise install
    fi

    # `exec "$@"` alone would run the bare command with an unmodified
    # PATH — `mise install` above only *installs* the pinned runtime
    # under $MISE_DATA_DIR, it doesn't put it on PATH by itself (mise
    # needs either its shims dir on PATH or `mise exec`/`mise activate`
    # to resolve it). Task 6 end-to-end testing caught this: without
    # `mise exec --`, `ruby check.rb` in a project pinning ruby via
    # .tool-versions failed with "ruby: not found" even though
    # `mise install` had just succeeded. `mise exec --` resolves the
    # current directory's pinned tool versions onto PATH for the
    # wrapped command; on a project with no mise config it's a no-op
    # passthrough, so this is safe for non-mise projects too.
    if [ "$#" -eq 0 ]; then
      exec mise exec -- ${pkgs.bashInteractive}/bin/bash -l
    else
      exec mise exec -- "$@"
    fi
  '';
in
# buildLayeredImage (not buildImage, as an earlier draft of system-plan.md
# §9.3 said) — buildLayeredImage splits contents into one layer per store
# path (deduped by nix-store-closure popularity), so rebuilding this image
# after e.g. bumping just claude-code only pushes/loads the layers that
# actually changed instead of one monolithic layer for the whole image.
# Confirmed real for this image: contents pulls in the full chromium
# closure (largest single dependency here), and layering keeps that as
# its own cacheable layer independent of the smaller, more frequently
# bumped packages (claude-code, opencode, mise). system-plan.md §9.3 was
# updated to match.
pkgs.dockerTools.buildLayeredImage {
  name = "agent-sandbox";
  tag = "latest";

  contents = with pkgs; [
    bashInteractive
    coreutils
    gitMinimal
    curl
    ripgrep
    mise
    cacert
    claude-code
    opencode
    chromium
    dockerTools.usrBinEnv
    dockerTools.binSh
    # `coreutils` does NOT include sed/grep/awk/tar/gzip (those are
    # separate GNU projects/packages in nixpkgs). mise's ruby-build
    # backend shells out to all of these when compiling a pinned Ruby
    # version from source. Found missing during Task 6 end-to-end
    # testing: ruby-build failed with "sed: command not found" /
    # "awk: command not found" etc.
    gnused
    gnugrep
    gawk
    gnutar
    gzip

    # mise/ruby-build's *precompiled* Ruby binaries are ordinary
    # generic-glibc ELF binaries expecting an FHS layout (dynamic linker
    # at /lib64/ld-linux-x86-64.so.2, etc) — they can't run unmodified in
    # this Nix-store-only image (confirmed during Task 6: "cannot
    # execute: required file not found", the classic missing-ELF-
    # interpreter symptom). Rather than build an FHS/nix-ld compat shim
    # (a bigger, fragile piece of surface area — has to keep matching
    # whatever glibc mise's upstream binaries were built against), we
    # keep mise on its *default* behavior (`ruby.compile=true`, i.e.
    # actually compile Ruby from source via ruby-build) and give it a
    # real toolchain to do that with. This is the standard ruby-build
    # Linux build dependency list (see
    # https://github.com/rbenv/ruby-build/wiki#suggested-build-environment),
    # minus OpenSSL — ruby-build vendors/builds its own OpenSSL from
    # source rather than linking the system one (observed directly: it
    # downloads and builds openssl-3.0.18 as part of the Ruby build).
    gcc
    gnumake
    pkg-config
    autoconf
    bison
    patch
    gnum4
    zlib
    readline
    libyaml
    libffi
    gdbm
    ncurses
    libxcrypt

    # The plain package names above (zlib, readline, ...) only pull in
    # each package's default output — the runtime shared library (.so),
    # no headers. nixpkgs splits headers/pkg-config files into a
    # separate "dev" output for these (confirmed via `nix eval
    # .#legacyPackages.x86_64-linux.<pkg>.outputs`: zlib/readline/
    # libyaml/libffi/gdbm/ncurses all report "... dev ..."), which
    # `contents` does NOT include automatically. Found missing one layer
    # deeper still in the same Task 6 pass, after the `perl` fix above
    # got OpenSSL's `./config` step to run: `make` on OpenSSL then
    # failed with "crypto/comp/c_zlib.c:36:11: fatal error: zlib.h: No
    # such file or directory" — OpenSSL is built with zlib support
    # (`zlib-dynamic` in the ./config invocation) and needs the header
    # at compile time even though it only *links* the .so at runtime.
    # Same reasoning applies to Ruby's own ./configure, which links
    # against readline/libyaml(Psych)/libffi(fiddle)/gdbm/ncurses and
    # needs their headers too. libxcrypt is deliberately not listed here
    # — `nix eval` shows it has no separate "dev" output (headers ship
    # in "out" already).
    zlib.dev
    readline.dev
    libyaml.dev
    libffi.dev
    gdbm.dev
    ncurses.dev

    # ruby-build's vendored OpenSSL build (see comment above — it builds
    # its own OpenSSL rather than linking a system one) invokes OpenSSL's
    # `./config`, which is itself a Perl script. Found missing during
    # this same Task 6 end-to-end pass, one layer deeper than the
    # gcc/make/etc list above: the build got past `Downloading
    # openssl-3.0.18.tar.gz` and failed at the `./config` step with
    # "env: 'perl': No such file or directory" (exit 127). Not in the
    # ruby-build wiki's suggested-build-environment list because that
    # list assumes a full-FHS Linux distro where perl is normally
    # already present; this minimal Nix-store-only image has to name it
    # explicitly.
    perl
  ];

  extraCommands = ''
    mkdir -p etc home/agent tmp
    chmod 1777 tmp

    # $HOME needs to be writable by whatever arbitrary host uid
    # `--userns=keep-id` maps us to (not just the build-time owner).
    chmod 777 home/agent

    # /etc/passwd must exist *and* be writable by an arbitrary uid for the
    # entrypoint's `getpwuid()` workaround above to succeed at runtime —
    # world-writable is fine here: this is a single-purpose sandbox image
    # with one real user (whichever uid podman maps us to), not a
    # multi-tenant system where that would be a meaningful privilege
    # boundary. `touch` first since none of this image's `contents`
    # happen to ship a /etc/passwd of their own.
    touch etc/passwd
    chmod 666 etc/passwd

    # `SSL_CERT_FILE` (exported by the entrypoint above) covers
    # Nix-aware software (curl, git, mise itself — all built against
    # openssl configured to honor that env var). It does NOT cover
    # ruby-build's *vendored* OpenSSL build: its `make install_ssldirs`
    # step does its own hardcoded scan of conventional FHS cert
    # locations (/etc/ssl/certs and similar) and hard-fails with
    # "Could not find OpenSSL certificates on this system" if none
    # exist — confirmed during this same Task 6 pass, as the very next
    # error after the zlib.dev fix got OpenSSL to build successfully.
    # Standard fix for exactly this class of problem in minimal/
    # Nix-store-only container images: populate the conventional
    # Debian/Ubuntu path (/etc/ssl/certs/ca-certificates.crt) so
    # non-Nix-aware software that only knows to look at FHS locations
    # finds a cert bundle there too, symlinked to the same cacert
    # store path SSL_CERT_FILE already points at (one bundle, two
    # discovery mechanisms — not a second copy to keep in sync).
    mkdir -p etc/ssl/certs
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
  '';

  config = {
    Entrypoint = [ "${entrypoint}" ];
    WorkingDir = "/workspace";
  };
}
