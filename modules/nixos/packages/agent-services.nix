# Backing services (postgres, redis, ...) that the sandbox starts for the
# agent itself, so it does not hunt /nix/store for initdb or run `redis-server`
# by hand in every task (found in a kandev run, 2026-10-20). Selected per
# sandbox with `service = postgres` lines in the config (bin/agent-sandbox);
# default "postgres redis", `service = none` for neither.
#
# Why processes INSIDE the sandbox container and not sibling podman
# containers (the host's dev-databases.nix way): rootless podman is not
# available inside, and giving the sandbox access to the host's podman socket
# would hand the agent the host. Binaries come from the same /nix/store, so
# nothing is pulled. Data lives in the per-sandbox volume
# agent-services-<name> (mounted at /shared/services), so it survives
# `agent-sandbox down`/`up`; `podman volume rm` is what wipes it.
#
# HOW TO ADD A SERVICE: one more attribute in `services` below, nothing else
# (no change to bin/agent-sandbox, the entrypoint or the tests):
#   packages  store packages to put into the sandbox tools env (clients too)
#   env       client variables exported in every sandbox shell when the
#             service is enabled (so the agent finds it without being told)
#   init      shell, runs before every start; $dir is the service's data dir
#             (persistent). Must be idempotent: create the cluster only when missing
#   run       shell: the server in the FOREGROUND, `exec`-ing it (its pid is
#             recorded and signalled on stop); stdout/stderr go to the log
#   ready     shell, exit 0 when the server accepts connections
#   stop      shell, optional: graceful stop (flush to disk). Default: SIGTERM
# Servers must listen on 127.0.0.1 only (see the docs for reaching them from
# the host: a socat in `autostart` + `publish`).
{ pkgs }:

let
  inherit (pkgs) lib;

  services = {
    postgres =
      let
        pg = pkgs.postgresql;
      in
      {
        packages = [ pg ];
        env = {
          # TCP, not the unix socket: the nixpkgs psql looks for its socket in
          # /run/postgresql, which does not exist here. PGUSER because the
          # only role is `postgres` (a role named after the container user
          # `agent` does not exist, so Rails/psql defaults would fail).
          PGHOST = "127.0.0.1";
          PGUSER = "postgres";
        };
        # One directory per MAJOR version (psqlSchema): a nixpkgs bump to a
        # new major would otherwise fail to start on the old cluster. The old
        # data stays where it is (pg_upgrade by hand); the warning says so.
        init = ''
          pgdata="$dir/${pg.psqlSchema}"
          for other in "$dir"/*/PG_VERSION; do
            [ -e "$other" ] || continue
            case "$other" in "$pgdata"/*) ;; *) echo "agent-service: postgres: older cluster in $(dirname "$other") is NOT used (new major version ${pg.psqlSchema}); migrate with pg_upgrade or dump/restore" >&2 ;; esac
          done
          if [ ! -f "$pgdata/PG_VERSION" ]; then
            # trust auth: loopback inside a private network namespace, same
            # reasoning as modules/nixos/dev-databases.nix (no password).
            ${pg}/bin/initdb -D "$pgdata" -U postgres --auth=trust -E UTF8 --locale=C.UTF-8 >/dev/null
          fi
          # A postmaster.pid left by a killed container: the pid it names
          # belongs to a previous container and may now be anyone's.
          rm -f "$pgdata/postmaster.pid"
        '';
        run = ''
          exec ${pg}/bin/postgres -D "$dir/${pg.psqlSchema}" \
            -c listen_addresses=127.0.0.1 -c port=5432 \
            -c unix_socket_directories=/tmp
        '';
        ready = "${pg}/bin/pg_isready -q -h 127.0.0.1 -p 5432";
        # fast = disconnect clients and checkpoint; SIGTERM ("smart") would
        # wait for an agent's open psql session forever.
        stop = ''${pg}/bin/pg_ctl stop -D "$dir/${pg.psqlSchema}" -m fast -w -t 20'';
      };

    redis =
      let
        redis = pkgs.redis;
      in
      {
        packages = [ redis ];
        env.REDIS_URL = "redis://127.0.0.1:6379/0";
        init = "";
        # AOF every second + RDB snapshot: data survives a restart (the old
        # host plan used `--save 60 1` alone, losing up to a minute on a kill).
        run = ''
          exec ${redis}/bin/redis-server --bind 127.0.0.1 --port 6379 \
            --dir "$dir" --appendonly yes --save "60 1"
        '';
        ready = "[ \"$(${redis}/bin/redis-cli -h 127.0.0.1 ping 2>/dev/null)\" = PONG ]";
        # SHUTDOWN SAVE writes the snapshot before exiting.
        stop = "${redis}/bin/redis-cli -h 127.0.0.1 shutdown save";
      };
  };

  # One script per phase and service, so the dispatcher below stays generic.
  # `set -eu` inside; the dispatcher exports $dir.
  phase = name: p: script: pkgs.writeShellScript "agent-service-${name}-${p}" ''
    set -eu
    ${script}
  '';
  scripts = lib.mapAttrs (name: s: {
    init = phase name "init" s.init;
    run = phase name "run" s.run;
    ready = phase name "ready" s.ready;
    stop = phase name "stop" (s.stop or "");
    hasStop = (s.stop or "") != "";
    env = s.env or { };
  }) services;

  # service-name -> store paths of the four phase scripts, as shell `case` arms.
  arms = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: s: ''
    ${name})
      s_init=${s.init}; s_run=${s.run}; s_ready=${s.ready}; s_stop=${if s.hasStop then s.stop else ""}
      ;;'') scripts);

  envArms = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: s: ''
    ${name})
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (k: v: "echo \"export ${k}=${v}\"") s.env)}
      ;;'') scripts);

  names = lib.concatStringsSep " " (lib.attrNames services);
in
{
  # Everything the services need to be in the sandbox's tools env (servers and clients).
  packages = lib.concatMap (s: s.packages) (lib.attrValues services);

  # agent-service {up|down|status|env|list} [name...]; names default to $AGENT_SERVICES.
  agentService = pkgs.writeShellApplication {
    name = "agent-service";
    runtimeInputs = [ pkgs.coreutils pkgs.util-linux ];
    text = ''
      root=/shared/services
      run_dir=/tmp/agent-services     # /tmp is wiped on `up`: pidfiles never outlive their container
      log_dir="''${XDG_STATE_HOME:-$HOME/.local-state}/services"
      known="${names}"

      load() { # load <name>: set s_* and $dir, or die
        case "$1" in
      ${arms}
          *) echo "agent-service: unknown service '$1' (known: $known)" >&2; return 2 ;;
        esac
        dir="$root/$1"
      }

      alive() { [ -f "$run_dir/$1.pid" ] && kill -0 "$(cat "$run_dir/$1.pid")" 2>/dev/null; }

      start() {
        local n="$1"
        load "$n" || return 2
        if alive "$n"; then echo "agent-service: $n already running"; return 0; fi
        mkdir -p "$dir" "$run_dir" "$log_dir"
        export dir
        "$s_init" || { echo "agent-service: $n: init failed" >&2; return 1; }
        # setsid + closed stdin/out: the process must outlive the `podman exec`
        # session that started it.
        setsid "$s_run" >>"$log_dir/$n.log" 2>&1 </dev/null &
        echo $! >"$run_dir/$n.pid"
        for _ in $(seq 1 60); do
          if "$s_ready" >/dev/null 2>&1; then echo "agent-service: $n ready"; return 0; fi
          alive "$n" || break
          sleep 0.5
        done
        echo "agent-service: $n did not become ready; log $log_dir/$n.log:" >&2
        tail -n 15 "$log_dir/$n.log" >&2 || true
        return 1
      }

      stop() {
        local n="$1"
        load "$n" || return 2
        alive "$n" || return 0
        export dir
        if [ -n "$s_stop" ]; then "$s_stop" >/dev/null 2>&1 || true; else kill "$(cat "$run_dir/$n.pid")" 2>/dev/null || true; fi
        for _ in $(seq 1 40); do alive "$n" || break; sleep 0.5; done
        # exec'd server: the pid file names the server itself.
        if alive "$n"; then kill -KILL "$(cat "$run_dir/$n.pid")" 2>/dev/null || true; fi
        rm -f "$run_dir/$n.pid"
        echo "agent-service: $n stopped"
      }

      cmd="''${1:-}"; [ "$#" -eq 0 ] || shift
      list=("$@")
      if [ "''${#list[@]}" -eq 0 ]; then read -r -a list <<<"''${AGENT_SERVICES:-}"; fi
      rc=0
      case "$cmd" in
        up) for n in "''${list[@]}"; do start "$n" || rc=1; done ;;
        down) for n in "''${list[@]}"; do stop "$n" || rc=1; done ;;
        status) for n in "''${list[@]}"; do if alive "$n"; then echo "$n: running"; else echo "$n: stopped"; rc=1; fi; done ;;
        env) for n in "''${list[@]}"; do
          case "$n" in
      ${envArms}
            *) ;;
          esac
        done ;;
        list) echo "$known" ;;
        *) echo "usage: agent-service {up|down|status|env|list} [name...]   (names default to \$AGENT_SERVICES: ''${AGENT_SERVICES:-none})" >&2; exit 64 ;;
      esac
      exit "$rc"
    '';
  };
}
