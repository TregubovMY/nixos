# Podman image for sandboxed AI coding agents (claude-code/opencode).
# Design: system-plan.md §9. Language runtimes (ruby/node/...) are
# deliberately NOT baked in here — mise resolves them per-project at
# container start (see the entrypoint below), so this image stays
# generic across every project instead of needing a rebuild per stack.
{ pkgs }:

let
  # nix-ld: same fix as programs.nix-ld.enable on a real NixOS host
  # (modules/nixos/nix-ld.nix), applied by hand here since this image has
  # no NixOS module system to just flip that option on. Lets ordinary
  # precompiled dynamically-linked Linux binaries (mise's node/python/go
  # downloads) find a real ELF interpreter instead of hitting "cannot
  # execute: required file not found" -- the gap the comment below Ruby's
  # toolchain list used to describe as unfixed. Mechanism (symlink at
  # /lib64/ld-linux-x86-64.so.2 below + NIX_LD/NIX_LD_LIBRARY_PATH in the
  # entrypoint) mirrors nixpkgs' own nixos/modules/programs/nix-ld.nix
  # exactly, not reinvented.
  #
  # Library list is copied verbatim from that same upstream module's
  # `programs.nix-ld.libraries` default (checked against this repo's
  # pinned nixpkgs rev directly, not assumed) -- deliberately kept
  # identical rather than trimmed for image size, so the host and the
  # sandbox resolve foreign binaries against the same baseline and
  # "works on the host" reliably predicts "works in the sandbox" too. If
  # upstream's default list changes, re-sync from there.
  nixLdLibraries = pkgs.lib.makeLibraryPath (with pkgs; [
    zlib
    zstd
    stdenv.cc.cc
    curl
    openssl
    attr
    libssh
    bzip2
    libxml2
    acl
    libsodium
    util-linux
    xz
    systemd
  ]);

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

    # nix-ld env vars (see the `nixLdLibraries`/loader-symlink comments
    # above and in extraCommands below) -- NIX_LD is the *real* glibc
    # dynamic linker nix-ld's shim defers to once it's done its job;
    # NIX_LD_LIBRARY_PATH covers the third-party libs (openssl/zlib/...)
    # a precompiled binary might need beyond glibc itself, which glibc's
    # own ld.so already knows how to find via its own embedded rpath.
    export NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}
    export NIX_LD_LIBRARY_PATH=${nixLdLibraries}

    # notebooklm-py tooling, mirroring modules/nixos/notebooklm-tooling.nix
    # (host-side module) inside the sandbox too -- an agent running in
    # here needs the same escape hatch to drive NotebookLM/yt-dlp as a
    # user working directly on the host. Same two reasons that module
    # documents apply verbatim here: notebooklm-py isn't in nixpkgs (pure
    # PyPI package, `uv tool install` is still a manual one-time step per
    # environment) and Playwright's own Chromium download is a generic
    # Linux build that won't run against this Nix-store-only image
    # (expects FHS paths like /lib64) -- point it at nixpkgs' pre-patched
    # playwright-driver.browsers instead and stop it from trying to
    # download its own build on top.
    export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
    export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

    # `uv tool install` itself isn't baked into the image (same "not
    # declarative, done by hand" boundary as the host module) -- but
    # unlike the host, this container is `--rm` (fresh rootfs every
    # launch), so without redirecting uv's install/shim dirs onto the
    # persistent agent-mise-style volume bin/agent-sandbox mounts at
    # /home/agent/.local/share/uv, `uv tool install "notebooklm-py[browser]"`
    # would have to be repeated on every single container start. Both
    # dirs kept under that one mounted volume (rather than uv's separate
    # default ~/.local/bin for shims) so bin/agent-sandbox only needs one
    # extra -v flag, not two.
    export UV_TOOL_DIR=/home/agent/.local/share/uv/tools
    export UV_TOOL_BIN_DIR=/home/agent/.local/share/uv/bin
    export PATH="$UV_TOOL_BIN_DIR:$PATH"
    mkdir -p "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR"

    # Wire the single per-project credentials volume (bin/agent-sandbox's
    # -v agent-creds-$project_hash:/home/agent/.sandbox-creds) up to the
    # actual paths claude-code/opencode read: ~/.claude (dir),
    # ~/.claude.json (file, NOT inside ~/.claude -- claude-code's own
    # top-level session file, confirmed against its real layout), and
    # ~/.config/opencode (dir). A podman named volume mounts cleanly onto
    # a directory but not onto a lone file, so this symlinks each real
    # path into one shared mounted directory instead of trying to mount
    # the volume three times (which also wouldn't work for the file case
    # at all). `[ -e ... ]` guards make this idempotent across container
    # restarts of the same project once the symlinks exist from a
    # previous run -- container itself is --rm (fresh rootfs every time),
    # only the named volume persists, so without this the entrypoint
    # would otherwise need to recreate the symlinks every single launch
    # regardless, but the guard also makes it safe to re-run by hand.
    mkdir -p /home/agent/.sandbox-creds/claude /home/agent/.sandbox-creds/opencode
    touch /home/agent/.sandbox-creds/claude.json
    [ -e /home/agent/.claude ] || ln -s /home/agent/.sandbox-creds/claude /home/agent/.claude
    [ -e /home/agent/.claude.json ] || ln -s /home/agent/.sandbox-creds/claude.json /home/agent/.claude.json
    mkdir -p /home/agent/.config
    [ -e /home/agent/.config/opencode ] || ln -s /home/agent/.sandbox-creds/opencode /home/agent/.config/opencode

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
    #
    # Append rather than overwrite (final review, M6): a plain `export
    # CPATH=/include` clobbers any value already inherited into the
    # container's environment for the *entire* session, not just the
    # ruby-build compile this was added for — including native-gem builds
    # against a mise-installed toolchain later in the same shell. `:`-
    # appending with `''${VAR:+:$VAR}` (empty-safe: no leading `:` when the
    # var is unset) keeps this fix scoped to "also search these dirs"
    # instead of "only ever search these dirs".
    export CPATH="/include''${CPATH:+:$CPATH}"
    export LIBRARY_PATH="/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export PKG_CONFIG_PATH="/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

    # mise treats `mise.toml`/`.mise.toml` (but not `.tool-versions`) as
    # potentially code-executing config and refuses to use it until it's
    # marked trusted — interactively prompting on a real TTY, or under
    # `set -euo pipefail` in this non-interactive entrypoint, aborting the
    # whole container before the user ever gets a shell. Only
    # `.tool-versions` was exercised end-to-end (Task 6); this was found
    # by static review of mise's trust-prompt behavior for the other two
    # formats (final review, I4). /workspace is always exactly the
    # bind-mounted project dir here (never untrusted host content beyond
    # what the user chose to mount), so pre-trusting it is safe and
    # harmless for `.tool-versions` projects, which don't consult trust
    # at all.
    export MISE_TRUSTED_CONFIG_PATHS=/workspace

    cd /workspace
    # Only run mise install if the project actually pins versions —
    # an agent working on a non-mise project shouldn't wait on this.
    if [ -f .tool-versions ] || [ -f mise.toml ] || [ -f .mise.toml ]; then
      # Degrade, don't die (final review, M5): under `set -euo pipefail` a
      # failing install (bad/unsupported pin, network hiccup) used to kill
      # the container outright, denying the user the one thing they'd need
      # to fix it — a shell inside the sandbox. Falling through to the
      # `mise exec`/bash-login below still works fine for anything the
      # broken toolchain doesn't block.
      mise install || echo "agent-sandbox: mise install failed, continuing" >&2
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
    # notebooklm-py's own runtime deps -- see the entrypoint's
    # PLAYWRIGHT_BROWSERS_PATH/UV_TOOL_DIR comment above for why both are
    # needed (uv installs the PyPI package itself in an isolated venv,
    # playwright-driver.browsers is the NixOS-compatible Chromium build
    # Playwright needs instead of its own FHS-assuming download).
    uv
    playwright-driver.browsers
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
    # `xz`/`unzip`: node's and python's mise backends ship precompiled
    # `.tar.xz` (and some release assets as `.zip`) — without these the
    # download can't even be unpacked, before it gets anywhere near the
    # ELF-interpreter problem (final review, I3) that `nix-ld` below now
    # fixes.
    xz
    unzip

    # See the `nixLdLibraries`/NIX_LD comments above (`let` block) and in
    # extraCommands below — this package provides the actual loader shim
    # binary that gets symlinked to /lib64/ld-linux-x86-64.so.2.
    nix-ld

    # A coding agent's shell needs the same basics any interactive Unix
    # shell needs, not just what ruby-build happens to shell out to —
    # this list was tuned exclusively against ruby-build's needs during
    # Task 6 and nobody had exercised what claude-code/opencode/an agent's
    # own commands reach for (final review, I5). `find`/`xargs` in
    # particular are bread-and-butter for a coding agent; `less` is git's
    # default `core.pager` (git log/diff error out without a pager
    # binary, not just look worse); `ps` is the standard "what's running"
    # check an agent reaches for when something hangs.
    findutils
    diffutils
    less
    procps

    # mise/ruby-build's *precompiled* Ruby binaries are ordinary
    # generic-glibc ELF binaries expecting an FHS layout (dynamic linker
    # at /lib64/ld-linux-x86-64.so.2, etc) — they can't run unmodified in
    # this Nix-store-only image (confirmed during Task 6: "cannot
    # execute: required file not found", the classic missing-ELF-
    # interpreter symptom). ruby-build specifically stays on its
    # *default* behavior (`ruby.compile=true`, i.e. actually compile
    # Ruby from source) rather than switching to nix-ld below (2026-08-13
    # addition, for node/python/go) -- already working and Task 6
    # end-to-end verified, no reason to re-risk a proven path just for
    # consistency with the newer mechanism. This is the standard
    # ruby-build Linux build dependency list (see
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
    mkdir -p etc home/agent tmp lib64
    chmod 1777 tmp

    # The actual nix-ld symlink -- same effect as NixOS's own
    # environment.ldso (nixos/modules/config/ldso.nix, what
    # programs.nix-ld.enable ultimately sets) writing a systemd-tmpfiles
    # `L+` rule for this exact path on a real host, done by hand here
    # since extraCommands is this image's only place to lay down files at
    # fixed filesystem paths (no systemd/tmpfiles inside the container).
    ln -s ${pkgs.nix-ld}/libexec/nix-ld lib64/ld-linux-x86-64.so.2

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
