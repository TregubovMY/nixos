# Sandbox for AI coding agents (claude-code/opencode/dsh), design:
# system-plan.md §9. Since 2026-10-06 this is NOT a container image: it
# returns `tools` (one buildEnv with everything the sandbox offers),
# `entrypoint`, and `rootfs` (a tiny root directory); bin/agent-sandbox runs
# podman with `--rootfs` on it and the host's /nix/store mounted read-only.
# Wired into the host by modules/nixos/agent-sandbox.nix. Language runtimes
# (ruby/node/...) are still not here -- mise resolves them per project at
# start (see the entrypoint), into a shared volume.
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
  # Global mise fallback (MISE_GLOBAL_CONFIG_FILE in the entrypoint): which
  # Go/Node/Python a directory without its own mise config gets. See there.
  miseGlobalConfig = pkgs.writeText "agent-sandbox-mise-global.toml" ''
    [tools]
    go = "1.26"
    node = "24"
    python = "3"
  '';

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
  # Every tool the sandbox offers, as one buildEnv in the host's
  # /nix/store. bin/agent-sandbox mounts /nix/store read-only into the
  # container, so these are the *same* store paths the host already has
  # (claude-code, Node, Playwright's browsers, mise...) -- nothing is
  # copied into podman's image storage any more. That copy was the ~4 GB
  # cost of the old buildLayeredImage (2026-10-06 redesign).
  # extraOutputsToInstall "dev": the headers/pkg-config files of the
  # libraries below (ruby-build needs them, see CPATH in the entrypoint).
  # The `claude` wrapper on its own so the entrypoint can put it FIRST in
  # PATH (see "claude via npm" below).
  claudeAccounts = pkgs.callPackage ./claude-accounts.nix { };
  tools = pkgs.buildEnv {
    name = "agent-sandbox-tools";
    extraOutputsToInstall = [ "dev" ];
    ignoreCollisions = true;
    paths = with pkgs; [
      # kandev board (modules/nixos/packages/kandev.nix): one sandbox, boards inside it
      (callPackage ./kandev.nix { })
      # gh: kandev's GitHub integration (PRs, checks) calls the gh CLI.
      # which: assumed present by many scripts and by agents themselves.
      # socat: forwards a published port to a service that only listens on
      # the container's loopback -- dsh web refuses --host 0.0.0.0 ("would
      # expose remote code execution to the network"), so it runs on
      # 127.0.0.1:3081 and socat exposes it on 3080 (README, agent-sandbox
      # config example). podman's publish only reaches the container's
      # network interface, not its loopback.
      gh
      which
      socat
      # pnpm: dsh installs its plugins with it (`dsh plugin ... add`
      # forwards to pnpm in the profile directory; without pnpm: "pnpm was
      # not found"). python3: the dsh `conductor` skill (llm-dev-template,
      # .dsh/skills/conductor) is a Python script.
      pnpm
      python3
      # dsh-setup: one command to install dsh and its plugins into the
      # sandbox's dsh profile (the profile, ~/.dsh, lives in the per-config
      # home volume, so this is done once per sandbox config). Lists are
      # the pinned files in ./dsh-plugins (core, extra, claude-sdk).
      # agent-install: what `install =` in the sandbox config asks for (env
      # AGENT_INSTALL, bin/agent-sandbox runs this on `up`): Claude Code and
      # dsh into the npm-global volume if missing. Idempotent; Claude Code
      # then updates itself (writable prefix), dsh stays on the pinned rc.
      (writeShellApplication {
        name = "agent-install";
        text = ''
          want=" ''${AGENT_INSTALL:-claude dsh} "
          prefix="''${NPM_CONFIG_PREFIX:-/shared/npm-global}"
          rc=0
          case "$want" in *" claude "*)
            if [ ! -x "$prefix/bin/claude" ]; then
              echo "==> installing Claude Code (npm -g, shared volume; updates itself)"
              npm install -g @anthropic-ai/claude-code || rc=1
            fi ;;
          esac
          case "$want" in *" dsh "*)
            if [ ! -x "$prefix/bin/dsh" ]; then
              echo "==> installing dsh 0.2.0-rc.2 (npm -g, shared volume)"
              npm install -g @deepseek-ai/dsh@0.2.0-rc.2 || rc=1
            fi ;;
          esac
          exit "$rc"
        '';
      })
      (writeShellApplication {
        name = "dsh-setup";
        text = ''
          lists=${./dsh-plugins}
          die() { echo "dsh-setup: $*" >&2; exit 1; }
          if [ "$#" -eq 0 ]; then set -- core; fi
          for l in "$@"; do
            if [ ! -f "$lists/$l.txt" ]; then
              avail=""
              for f in "$lists"/*.txt; do b="''${f##*/}"; avail="$avail ''${b%.txt}"; done
              die "unknown list '$l' (available:$avail)"
            fi
          done
          if ! command -v dsh >/dev/null 2>&1; then
            echo "==> installing dsh 0.2.0-rc.2 (npm -g, shared volume)"
            npm install -g @deepseek-ai/dsh@0.2.0-rc.2
          fi
          failed=()
          for l in "$@"; do
            if [ "$l" = claude-sdk ]; then
              echo "claude-sdk is a gray-zone option (see the header of $lists/claude-sdk.txt):"
              echo "a third-party plugin on the Claude Agent SDK driving your subscription."
              read -r -p "Install it anyway? [yes/N] " ans
              [ "$ans" = yes ] || { echo "skipped"; continue; }
            fi
            echo "==> dsh plugins: $l"
            while IFS= read -r line; do
              spec="''${line%%#*}"
              spec="''${spec#"''${spec%%[![:space:]]*}"}"
              spec="''${spec%"''${spec##*[![:space:]]}"}"
              [ -n "$spec" ] || continue
              echo "--> $spec"
              dsh plugin --profile web add "$spec" || failed+=("$spec")
            done < "$lists/$l.txt"
          done
          if [ "''${#failed[@]}" -gt 0 ]; then
            echo "dsh-setup: failed: ''${failed[*]}" >&2
            exit 1
          fi
          echo "==> done. Restart dsh web (agent-sandbox down/up) to load the plugins."
        '';
      })
        bashInteractive
        coreutils
        gitMinimal
        curl
        ripgrep
        mise
        cacert
        # claude-code behind the account-switching wrapper (claude-accounts.nix):
        # `claude` picks CLAUDE_CONFIG_DIR per account, `claude-use` switches it.
        claudeAccounts
        # Found in a kandev run (2026-10-20): the agent hunted /nix/store for
        # a postgres to run integration tests (initdb/pg_ctl/psql), and had
        # no `file`. Server + client both, same store paths as the host.
        postgresql
        file
        tzdata
        opencode
        chromium
        # notebooklm-py's own runtime deps -- see the entrypoint's
        # PLAYWRIGHT_BROWSERS_PATH/UV_TOOL_DIR comment above for why both are
        # needed (uv installs the PyPI package itself in an isolated venv,
        # playwright-driver.browsers is the NixOS-compatible Chromium build
        # Playwright needs instead of its own FHS-assuming download).
        uv
        playwright-driver.browsers
        # DeepSeek Harness's own runtime -- see the entrypoint's
        # NPM_CONFIG_PREFIX comment above for why this stays an
        # `npm install -g @deepseek-ai/dsh` done by hand rather than a baked-in
        # nixpkgs derivation. `nodejs` here is *only* the interpreter/npm CLI;
        # `dsh` itself is not part of this image's closure.
        nodejs
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

        # Agent-development workflow tooling (llm-dev-template/forge, system-
        # plan.md §9.7). All small, all in nixpkgs, so declared here rather
        # than installed by hand:
        # - gitleaks: the `scrub` step (ticket/review text through
        #   `gitleaks stdin` before an agent sees it) and the lefthook
        #   pre-commit secret scan both run inside this container;
        # - jq: JSON glue for those scripts and for stream-json agent logs;
        # (glab removed 2026-10-06: the GitLab stage hasn't started; add it
        # back together with `agent-sandbox --gitlab-token` usage.)
        # - tmux: interactive agent sessions inside the long-lived per-project
        #   container (`agent-sandbox up`/`attach`) survive a closed terminal.
        gitleaks
        jq
        tmux
        # Project-template tooling (llm-dev-template): OpenSpec CLI for specs
        # (`openspec init/validate/archive`) and lefthook, which runs the
        # template's pre-commit guards (gitleaks, review markers, commitlint).
        # From nixpkgs instead of `npm install -g` / `npx`: pinned with the
        # rest of the image and no download on first commit.
        openspec
        lefthook

        # Language servers for Claude Code's built-in LSP tool (official
        # `gopls-lsp` / `typescript-lsp` plugins from claude-plugins-official)
        # and OpenCode's LSP integration -- each plugin only wraps a server
        # binary that has to be on PATH. Chosen over Serena/code-graph MCP
        # servers as the default code-navigation layer: no MCP, no index, no
        # embeddings, nothing leaves the container. Ruby's `ruby-lsp` is
        # deliberately NOT here: it must match the project's own Ruby (mise)
        # and Gemfile, so it comes from the project's bundle instead.
        gopls
        typescript-language-server
        typescript

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
  };

  entrypoint = pkgs.writeShellScript "agent-sandbox-entrypoint" ''
    set -euo pipefail
    # All sandbox tools live in one buildEnv in the host's /nix/store
    # (mounted read-only); nothing is on any FHS path inside the rootfs,
    # so PATH comes first -- even `id`/`getent` below need it.
    export PATH="${tools}/bin''${PATH:+:$PATH}"

    # bin/agent-sandbox mounts a passwd/group with this user read-only, so
    # this append is only a fallback (other launchers) and must not abort
    # the entrypoint when /etc is not writable.
    if ! id -un > /dev/null 2>&1; then
      { echo "agent:x:$(id -u):$(id -g)::/home/agent:${pkgs.bashInteractive}/bin/bash" >> /etc/passwd; } 2>/dev/null || true
    fi

    export HOME=/home/agent
    export MISE_DATA_DIR=/shared/mise
    # ~/.local itself is created by podman as the parent of the shared
    # volumes mounted under it (mise/uv/npm/local-bin), owned by the
    # container's root, so ~/.local/state can't be created there ("mise
    # WARN ... tracked-configs: Permission denied", VM run). State goes to
    # the home volume's root instead, which belongs to the user.
    export XDG_STATE_HOME=/home/agent/.local-state
    export MISE_STATE_DIR=/home/agent/.local-state/mise
    # Found live 2026-10-07: on a project with no .tool-versions/mise.toml,
    # `mise install` below is skipped entirely and `mise exec --` is a bare
    # passthrough that never touches MISE_STATE_DIR either -- nothing ever
    # created this directory. bin/agent-sandbox's `autostart` (kandev/dsh/
    # socat for board configs) redirects into
    # /home/agent/.local-state/autostart.log via a backgrounded `podman exec
    # -d ... /agent-entrypoint sh -c "$cmd >> .../autostart.log"` -- with the
    # parent directory missing, that redirect fails with "No such file or
    # directory" before $cmd ever runs, `sh -c` exits non-zero, and because
    # it's backgrounded (`-d`), nothing surfaces the failure anywhere: no
    # log file, no running service, no error visible from the host. Symptom
    # was exactly that -- kandev/dsh ports never came up, autostart.log
    # didn't exist at all. mkdir unconditionally, independent of whether
    # mise ever runs for this project.
    mkdir -p "$XDG_STATE_HOME"
    # Gems: reuse everything installed on the host, install only what's
    # missing. The host's mise Rubies (and the gems installed into them)
    # are mounted read-only (bin/agent-sandbox, MISE_SHARED_INSTALL_DIRS),
    # so gems can't be installed there; GEM_HOME is the sandbox's own dir
    # (in this config's home volume) and GEM_PATH's trailing ':' appends
    # Ruby's default gem dirs, i.e. the host Ruby's -- Rubygems searches
    # GEM_HOME first, then the host's, and installs into GEM_HOME
    # (checked: `GEM_PATH="x:" ruby -e 'puts Gem.path'`). Not shared the
    # other way on purpose: a sandbox writing into gems the host later
    # runs would be a way out of the sandbox. (Replaced vendor/bundle in
    # projects, 2026-10-06 -- one shared dir instead of one per project.)
    export GEM_HOME=/home/agent/.local-state/gems
    export GEM_PATH="$GEM_HOME:"
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
    # /shared/uv, `uv tool install "notebooklm-py[browser]"`
    # would have to be repeated on every single container start. Both
    # dirs kept under that one mounted volume (rather than uv's separate
    # default ~/.local/bin for shims) so bin/agent-sandbox only needs one
    # extra -v flag, not two.
    export UV_TOOL_DIR=/shared/uv/tools
    export UV_TOOL_BIN_DIR=/shared/uv/bin
    export PATH="$UV_TOOL_BIN_DIR:$PATH"
    mkdir -p "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR"

    # DeepSeek Harness (`dsh`, npm package `@deepseek-ai/dsh`) -- same
    # category of dependency as notebooklm-py above: not in nixpkgs
    # (published 2026-08-13, and upstream's own README says "developer
    # preview ... THERE WILL BE COMPATIBILITY-BREAKING CHANGES"), so a
    # pinned Nix derivation would go stale by design, not by neglect. Reuses
    # the exact same pattern as uv-tool-install rather than inventing a new
    # one: `nodejs` in `contents` below is only the runtime `npm install -g
    # @deepseek-ai/dsh` needs, the install itself stays a manual one-time
    # step per environment (see README) -- and NPM_CONFIG_PREFIX points at a
    # path under the persistent agent-npm-global volume (bin/agent-sandbox)
    # so that one-time install survives this container being --rm, same as
    # UV_TOOL_DIR/UV_TOOL_BIN_DIR above survives via agent-uv-tools.
    export NPM_CONFIG_PREFIX=/shared/npm-global
    export PATH="$NPM_CONFIG_PREFIX/bin:$PATH"
    mkdir -p "$NPM_CONFIG_PREFIX"

    # ~/.local/bin: where tools put hand-installed binaries (pip --user,
    # release binaries). It's the per-project home's own directory now (the
    # shared agent-local-bin volume that used to sit here was dropped
    # 2026-10-06 with its only user, the Multica daemon). Prebuilt glibc
    # binaries run via the nix-ld shim configured above.
    export PATH="/home/agent/.local/bin:$PATH"
    mkdir -p /home/agent/.local/bin

    # Claude's login and sessions are NOT wired here: the `claude` wrapper
    # (claude-accounts.nix) points CLAUDE_CONFIG_DIR at the account
    # directory that bin/agent-sandbox mounts from the host, so host and
    # sandbox share logins and sessions. opencode keeps its config in the
    # per-sandbox home volume as it is (~/.config/opencode).

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
    # (Paths were /include, /lib in the old buildLayeredImage, which merged
    # every package into the image root; now they are the tool env's.)
    export CPATH="${tools}/include''${CPATH:+:$CPATH}"
    export LIBRARY_PATH="${tools}/lib''${LIBRARY_PATH:+:$LIBRARY_PATH}"
    export PKG_CONFIG_PATH="${tools}/lib/pkgconfig''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

    # mise treats `mise.toml`/`.mise.toml` (but not `.tool-versions`) as
    # potentially code-executing config and refuses it until trusted --
    # prompting on a TTY, or aborting this non-interactive entrypoint under
    # `set -e` before the user ever gets a shell. AGENT_MOUNTS (set by
    # bin/agent-sandbox, ':'-separated host paths mounted at the same path
    # inside) are exactly the directories the user chose to give the sandbox,
    # so trusting them adds nothing an agent there could not already do.
    # kandev (autostart) checks agent worktrees out under ~/.kandev/tasks,
    # outside every AGENT_MOUNTS path, so their mise.toml would be untrusted
    # and mise would refuse them (go/node/ruby silently missing, found live
    # 2026-10-20). Same trust level as the project mounts: an agent can write
    # a mise.toml into either.
    export MISE_TRUSTED_CONFIG_PATHS="''${AGENT_MOUNTS:-}:/home/agent/.kandev"
    # Shims on PATH for EVERY process, not just those started through the
    # `mise exec` below: kandev spawns its terminals and agents itself
    # (autostart -> kandev -> agentctl -> sh), so they never pass through
    # `mise exec`; without the shims dir `go`/`node`/`ruby` were "command not
    # found" there (found live 2026-10-20). A shim resolves the version from
    # the cwd's .tool-versions/mise.toml, else from the global fallback
    # below. `mise exec` still prepends the exact versions for the commands
    # that go through it, so this only adds coverage.
    export PATH="$MISE_DATA_DIR/shims:$PATH"
    # Go: mise's go plugin exports GOROOT of the version it resolved for the
    # directory the container was started in (the host's 1.26.9), which then
    # broke every other Go the shims resolve (a project pinning 1.27.3 got
    # "compile: version mismatch"; the agent worked around it with
    # `unset GOROOT` and a hand-built PATH to /home/max/.local/share/mise/...).
    # `go` finds its own root from the binary's location.
    export MISE_GO_SET_GOROOT=false
    unset GOROOT
    # `gofmt` and other secondary binaries of host-provided installs had no
    # shim ("gofmt: command not found" although go was there): shims are
    # created by `reshim`, which nothing ran for the read-only installs.
    mise reshim >/dev/null 2>&1 || true
    # tzdata for tools that read TZDIR rather than /usr/share/zoneinfo.
    export TZDIR=${pkgs.tzdata}/share/zoneinfo
    # Host git identity (generated, mounted by bin/agent-sandbox); no ssh in
    # here, so say so clearly instead of "cannot run ssh: No such file".
    export GIT_CONFIG_SYSTEM=/etc/agent-gitconfig
    export GIT_SSH_COMMAND='echo "ssh is not available in the sandbox: fetch/pull/push are done by the user on the host" >&2; false'
    # claude via npm: `npm install -g @anthropic-ai/claude-code` lands in
    # $NPM_CONFIG_PREFIX/bin (a persistent volume, writable, so Claude Code
    # self-updates; autoUpdatesChannel=stable in claude-accounts.nix). That
    # dir is on PATH ahead of the Nix wrapper, so a bare `claude` (and kandev's
    # CLAUDE_CODE_EXECUTABLE=$(command -v claude)) would skip the account
    # selection. Put the wrapper first again; it execs the npm binary when
    # present, else the Nix one.
    export PATH="${claudeAccounts}/bin:$PATH"
    # Fallback for directories with no mise config (a worktree whose
    # mise.toml is untracked, e.g. crypton's: only go.mod is checked out).
    # Major/minor prefixes, not exact pins: they match whatever the host's
    # read-only installs (MISE_SHARED_INSTALL_DIRS) provide, so a host Go
    # bump does not need an edit here; a project's own pin always wins.
    export MISE_GLOBAL_CONFIG_FILE=${miseGlobalConfig}

    # AGENT_WORKDIR (set by `bin/agent-sandbox` to the cwd you ran it from,
    # or -C) is where the command starts. Done here, not with `podman exec
    # -w`, because this entrypoint cd's unconditionally and runs `mise
    # install` for the directory it lands in: a subdirectory or worktree
    # carries its own .tool-versions, so mise has to resolve versions there.
    # It must be inside one of AGENT_MOUNTS and free of `..`, so the flag
    # cannot start an agent somewhere outside the project view.
    first_mount="''${AGENT_MOUNTS%%:*}"
    workdir="''${AGENT_WORKDIR:-$first_mount}"
    inside=0
    old_ifs="$IFS"; IFS=:
    for m in ''${AGENT_MOUNTS:-}; do
      case "$workdir/" in "$m"/*) inside=1 ;; esac
    done
    IFS="$old_ifs"
    if [ "$inside" = 0 ]; then
      echo "agent-sandbox: AGENT_WORKDIR must be inside one of the sandbox's directories (''${AGENT_MOUNTS:-none}): $workdir" >&2
      exit 64
    fi
    case "/$workdir/" in
      */../*)
        echo "agent-sandbox: AGENT_WORKDIR must not contain '..': $workdir" >&2
        exit 64
        ;;
    esac
    if [ ! -d "$workdir" ]; then
      echo "agent-sandbox: AGENT_WORKDIR does not exist: $workdir" >&2
      exit 66
    fi
    cd "$workdir"
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
    # Only wrap in `mise exec` when this directory has its own mise config.
    # With the global fallback config (MISE_GLOBAL_CONFIG_FILE above) `mise
    # exec` is no longer a no-op on a config-less directory: it would
    # prepend the fallback go/node/python to PATH ahead of the shims, and
    # every process started from here (kandev -> its worktrees) would then
    # ignore each worktree's own pin (seen live 2026-10-20: node 24.22
    # instead of the project's 24.3.0). Without the wrapper the shims alone
    # resolve per directory: the pin if there is one, the fallback if not.
    if [ -f .tool-versions ] || [ -f mise.toml ] || [ -f .mise.toml ]; then
      runner="mise exec --"
    else
      runner=""
    fi
    if [ "$#" -eq 0 ]; then
      exec $runner ${pkgs.bashInteractive}/bin/bash -l
    else
      exec $runner "$@"
    fi
  '';
in
# No container image any more. The sandbox root is this tiny directory in
# /nix/store, used directly by `podman run --rootfs <dir>:O` (O = overlay:
# podman can create its mount points without touching the store), with the
# host's /nix/store bind-mounted read-only so every symlink below and every
# tool in `tools` resolves. Updates are a normal `nixos-rebuild switch`;
# no `nix build` + `podman load` step, no layers, no duplicate store.
#
# What has to be at fixed FHS paths, and why:
# - lib64/ld-linux-x86-64.so.2 -> nix-ld: precompiled binaries mise
#   downloads (node/python/go) need an ELF interpreter at the standard
#   path; same as programs.nix-ld on the host (modules/nixos/nix-ld.nix).
# - bin/sh, usr/bin/env: scripts' shebangs.
# - etc/passwd, etc/group: podman appends the user's entry
#   (--passwd-entry) and getpwuid() needs the files to exist.
# - etc/ssl/certs/ca-certificates.crt: ruby-build's vendored OpenSSL scans
#   FHS cert locations and ignores SSL_CERT_FILE (found in the old image's
#   end-to-end test; same bundle as SSL_CERT_FILE, not a copy).
# - agent-entrypoint: stable path for `podman exec` (exec doesn't run an
#   entrypoint, bin/agent-sandbox calls this explicitly).
# - tmp: mount point (tmpfs); see below for why home/agent is NOT one.
let
  rootfs = pkgs.runCommand "agent-sandbox-rootfs" { } ''
    # No home/agent here on purpose: an existing mount point makes podman
    # "copy up" its owner and mode (root, read-only in the store) onto the
    # fresh agent-home volume, which the user then can't write to (seen in
    # the VM). Absent, podman creates it in the overlay and the volume
    # stays owned by the keep-id user.
    mkdir -p $out/{bin,usr/bin,lib64,etc/ssl/certs,tmp,nix/store,run,dev,proc,sys}
    ln -s ${pkgs.nix-ld}/libexec/nix-ld $out/lib64/ld-linux-x86-64.so.2
    ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/sh
    ln -s ${pkgs.bashInteractive}/bin/bash $out/bin/bash
    ln -s ${pkgs.coreutils}/bin/env $out/usr/bin/env
    ln -s ${entrypoint} $out/agent-entrypoint
    # No tzdata anywhere in a bare rootfs: Ruby's tzinfo (Rails) failed with
    # "no zoneinfo" in a kandev run (2026-10-20) and the agent patched it
    # with a TracePoint hack. Plain FHS path, same store tzdata as TZDIR.
    mkdir -p $out/usr/share
    ln -s ${pkgs.tzdata}/share/zoneinfo $out/usr/share/zoneinfo
    # Mount point for the generated git identity (bin/agent-sandbox).
    touch $out/etc/agent-gitconfig
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt $out/etc/ssl/certs/ca-certificates.crt
    echo "root:x:0:0:root:/root:/bin/sh" > $out/etc/passwd
    printf 'root:x:0:\nusers:x:100:\nnogroup:x:65534:\n' > $out/etc/group
    touch $out/etc/hosts $out/etc/resolv.conf $out/etc/hostname
    # podman creates this symlink itself if missing, which fails on a
    # root-owned store directory ("creating /etc/mtab symlink: permission
    # denied", first run in the VM) -- so it ships in the rootfs.
    ln -s /proc/mounts $out/etc/mtab
    # Same story for podman's /run/.containerenv bind-mount target: it must
    # already exist, podman can't create files in the store directory.
    touch $out/run/.containerenv
    # ...and for --init (agent-sandbox up): podman mounts catatonit here.
    touch $out/run/podman-init
  '';
in
{
  inherit rootfs tools entrypoint;
}
