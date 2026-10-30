# agent-vm: a microVM (own kernel, own Docker) for AI agents that need
# containers, behind a network that leads ONLY to the internet.
#
# Design, threat model and rejected alternatives:
#   docs/superpowers/specs/2026-10-30-agent-vm-design.md
# Daily use: `agent-vm` (bin/agent-vm), docs/AGENT-SANDBOX.md, "agent-vm".
#
# Shape of it:
#
#   host                                       guest (microvm.nix, qemu+KVM)
#   ----                                       -----------------------------
#   agentbr 10.200.0.1/24 ----- vm-agent ----- eth 10.200.0.2/24, NO gateway
#   agent-vm-proxy (sing-box) 10.200.0.1:3128 <-- HTTP(S)_PROXY, docker proxies
#        | drops private/special IPs (see below)
#        v
#   Throne mixed inbound 127.0.0.1:2080  -> the user's own routing rules
#
# Why a PROXY and not NAT: the user's Throne routes part of the traffic
# directly and part through a proxy by its own rules, and a home OpenVPN
# (tun0) joins on some hosts. With NAT the guest's packets would follow the
# host's routing table, i.e. also into the LAN and the VPN. Here the guest
# has no route off-link at all and the host drops everything from agentbr
# except one TCP port, so nothing but the filtering proxy is reachable.
#
# Why the filter is a second sing-box and not Squid/tinyproxy (found live,
# 2026-10-30, checked against a fake SOCKS server): after the `resolve`
# route action sing-box hands the SOCKS upstream the already checked IPv4
# ADDRESS, not the host name. So the address that was tested against the
# private ranges is exactly the one Throne connects to, and DNS rebinding
# (a name that resolves to a public IP for the check and to 172.22.x for
# the connection) cannot work. Squid/tinyproxy pass the NAME on, and
# Throne would resolve it a second time. Side effect: Throne sees IP
# literals, so its DOMAIN rules only match when Throne sniffs TLS SNI /
# HTTP Host on its inbound -- acceptance test in the spec ("a domain that
# is only reachable through Throne's proxy").
{ config, lib, pkgs, ... }:
let
  cfg = config.agentVm;

  hostIp = "10.200.0.1";
  guestIp = "10.200.0.2";
  subnet = "10.200.0.0/24";
  proxyPort = 3128;
  proxyUrl = "http://${hostIp}:${toString proxyPort}";
  noProxy = "localhost,127.0.0.1,${subnet}";
  bridge = "agentbr"; # <= 15 chars (IFNAMSIZ)
  tap = "vm-agent"; # microvm.nix convention: tap names start with vm-
  stateDir = "/var/lib/agent-vm";

  # Everything that must never be reachable through the proxy. `ip_is_private`
  # covers RFC1918, loopback, link-local and ULA; the explicit list adds what
  # it does not: "this network", CGNAT (Tailscale and friends), 169.254/16
  # (cloud metadata), 192.0.0.0/24, 198.18.0.0/15 (benchmarking range --
  # also the usual sing-box FakeIP pool), multicast and reserved.
  filterConfig = pkgs.writeText "agent-vm-proxy.json" (builtins.toJSON {
    log = { level = "warn"; timestamp = true; };
    dns = {
      servers = [{ type = "local"; tag = "local"; }];
    };
    inbounds = [{
      type = "http";
      tag = "vm";
      listen = hostIp;
      listen_port = proxyPort;
    }];
    outbounds = [{
      type = "socks";
      tag = "throne";
      server = cfg.upstream.host;
      server_port = cfg.upstream.port;
    }];
    route = {
      final = "throne";
      default_domain_resolver = "local";
      rules = [
        # IPv4 only: the guest has IPv6 switched off, and one address
        # family keeps the check below simple.
        { action = "resolve"; strategy = "ipv4_only"; }
        { ip_is_private = true; action = "reject"; }
        {
          ip_cidr = [
            "0.0.0.0/8"
            "100.64.0.0/10"
            "169.254.0.0/16"
            "192.0.0.0/24"
            "198.18.0.0/15"
            "224.0.0.0/3"
          ];
          action = "reject";
        }
      ];
    };
  });

  # Ports the host opens on 127.0.0.1 and forwards to the guest.
  forwards = cfg.webPorts;

  # ---- What the guest sees of the host (same PATHS as on the host) -------
  # The guest user is the host user (same name, uid, home) and every share
  # is mounted at its host path. That one rule is what makes
  #   - claude-code sessions shared: it keys transcripts by working
  #     directory, so /home/max/code/x must be /home/max/code/x in the VM;
  #   - paths in logs/stack traces the ones your IDE opens;
  # the same idea as agent-sandbox (docs/AGENT-SANDBOX.md).
  home = config.users.users.${cfg.user}.home;
  claudeRoot = "${home}/.local/share/claude-accounts";
  claudeRules = "${home}/.config/claude-accounts";
  miseInstalls = "${home}/.local/share/mise/installs";

  # Project directories, read-write unless `ro`.
  projectMounts = map (m: { inherit (m) path; readOnly = m.ro; }) cfg.mounts;
  # Claude: ONLY the listed accounts + the shared tree (sessions, history,
  # skills...) + the path->account rules. Each account dir holds that
  # account's login token, so an account that is not listed is not in the
  # VM at all. Accounts' symlinks into shared/ are relative, so they
  # resolve because both are mounted under the same root.
  claudeMounts =
    [{ path = "${claudeRoot}/shared"; readOnly = false; }]
    ++ map (a: { path = "${claudeRoot}/${a}"; readOnly = false; }) cfg.claudeAccounts
    ++ [{ path = claudeRules; readOnly = true; }];
  # Host language runtimes (mise), read-only, like the sandbox mounts them.
  toolMounts = lib.optional cfg.miseInstalls { path = miseInstalls; readOnly = true; };

  allMounts = projectMounts ++ claudeMounts ++ toolMounts;
  mountShares = lib.imap0
    (i: m: {
      tag = "m${toString i}";
      source = m.path;
      mountPoint = m.path;
      proto = "virtiofs";
      inherit (m) readOnly;
    })
    allMounts;

  # Ancestors of a mount point that lie inside the home directory. systemd
  # creates missing mount-point parents as root:root, and a root-owned
  # ~/.local makes every tool that writes there fail (seen with
  # agent-sandbox's podman mounts) -- so the guest creates them first,
  # owned by the user (service agent-mountpoints below).
  ancestorsInHome = p:
    let
      segs = lib.filter (x: x != "") (lib.splitString "/" p);
      upTo = n: "/" + lib.concatStringsSep "/" (lib.take n segs);
    in
    lib.filter (d: lib.hasPrefix "${home}/" d) (map upTo (lib.range 1 (lib.length segs - 1)));
  mountParents = lib.unique (lib.concatMap (m: ancestorsInHome m.path) allMounts);

  dockerProxies = {
    http-proxy = proxyUrl;
    https-proxy = proxyUrl;
    no-proxy = noProxy;
  };
in
{
  options.agentVm = {
    enable = lib.mkEnableOption "the agent microVM (Docker for agents behind a filtering proxy)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "max";
      description = "Host user who may start/stop the VM (polkit) and owns the ssh key for `agent-vm shell`.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "uid of the user inside the VM; must equal the host user's uid (virtiofs shows raw uids).";
    };

    mounts = lib.mkOption {
      default = [ ];
      description = ''
        Host directories mounted into the VM at the SAME path. Fixed at VM
        start (virtiofs shares are part of the qemu command line), so
        changing the list needs `nixos-rebuild switch` and `agent-vm down &&
        agent-vm up`. A directory that does not exist is created (owned by
        the user) -- virtiofsd refuses to start on a missing source.

        READ THIS: a read-write mount is a channel back to the host. The
        VM protects the host SYSTEM and your internal network, not these
        files, nor anything that later runs from them on the host: a
        planted .git/hooks/pre-commit, .envrc, mise.toml, a package.json
        script, an IDE task. Review `git diff` AND hooks before running
        things from a project the agent has written to, or mount it `ro`.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          path = lib.mkOption { type = lib.types.str; example = "/home/max/code/my"; };
          ro = lib.mkOption { type = lib.types.bool; default = false; };
        };
      });
    };

    claudeAccounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "personal" "work" ];
      description = ''
        Claude accounts (dirs under ~/.local/share/claude-accounts, see
        bin/claude-use) visible in the VM. Each holds a login token: an
        account not listed here cannot be stolen from the VM.
      '';
    };

    miseInstalls = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Mount the host's mise runtimes (~/.local/share/mise/installs) read-only, as agent-sandbox does.";
    };

    services = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run PostgreSQL 16 and Redis in the VM from boot (loopback, data on their own disks).";
    };
    servicesDiskMiB = lib.mkOption { type = lib.types.int; default = 10 * 1024; description = "Size of the Postgres data disk."; };

    vcpu = lib.mkOption { type = lib.types.int; default = 4; };
    memoryMiB = lib.mkOption { type = lib.types.int; default = 8192; };
    dockerDiskMiB = lib.mkOption {
      type = lib.types.int;
      default = 40 * 1024;
      description = "Size of the sparse image under /var/lib/docker in the guest.";
    };
    homeDiskMiB = lib.mkOption { type = lib.types.int; default = 20 * 1024; };

    upstream = {
      host = lib.mkOption { type = lib.types.str; default = "127.0.0.1"; };
      port = lib.mkOption {
        type = lib.types.port;
        default = 2080;
        description = "Throne's mixed (SOCKS+HTTP) inbound; 2080 is what it listens on here (checked 2026-10-30).";
      };
    };

    webPorts = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = {
        kandev = 38429; # same port as `kandev start --backend-port` in the sandbox
        terminal = 7681; # ttyd
      };
      description = ''
        name -> port. Each is served in the guest and reachable on the
        host as http://127.0.0.1:<port> (loopback only, host-initiated).
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [ {
    # ---- Network on the host: bridge + tap, nothing routed ---------------
    # systemd-networkd only for these two links: NetworkManager keeps
    # everything else (it is told to ignore them), the networkd units match
    # by interface name only.
    systemd.network.enable = true;
    # NetworkManager is the network-online provider here; networkd must not
    # hold boot waiting for a link it does not manage.
    systemd.network.wait-online.enable = false;
    networking.networkmanager.unmanaged = [ "interface-name:${bridge}" "interface-name:${tap}" ];

    systemd.network.netdevs."30-${bridge}".netdevConfig = {
      Kind = "bridge";
      Name = bridge;
    };
    systemd.network.networks."30-${bridge}" = {
      matchConfig.Name = bridge;
      address = [ "${hostIp}/24" ];
      networkConfig = {
        # The bridge has no carrier until the VM's tap joins it; the proxy
        # needs the address anyway.
        ConfigureWithoutCarrier = true;
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
        # Belt and braces next to the firewall rules below: the kernel
        # does not forward packets that arrive on this link.
        IPv4Forwarding = false;
        IPv6Forwarding = false;
      };
    };
    systemd.network.networks."31-${tap}" = {
      matchConfig.Name = tap;
      networkConfig = {
        Bridge = bridge;
        LinkLocalAddressing = "no";
      };
    };

    # ---- Host firewall: the whole point of the design --------------------
    # The NixOS firewall here is the iptables backend (checked: networking
    # .nftables.enable = false), FORWARD policy ACCEPT. Podman/libvirt add
    # their own FORWARD rules for their own subnets only, which do not
    # match agentbr.
    #
    # INPUT: the global allowedTCPPorts of this host (ssh, LocalSend,
    # KDE Connect...) apply to EVERY interface, including agentbr, so the
    # explicit jump to agentvm-in must come BEFORE the nixos-fw chain.
    # Only replies to host-initiated connections (conntrack) and NEW TCP to
    # hostIp:proxyPort pass. ICMP, DNS, DHCP, everything else the guest
    # starts is dropped.
    # FORWARD: nothing in or out of agentbr (the guest has no gateway, but a
    # compromised guest can set one).
    networking.firewall.extraCommands = ''
      iptables -D INPUT -i ${bridge} -j agentvm-in 2>/dev/null || true
      iptables -F agentvm-in 2>/dev/null || iptables -N agentvm-in
      # Replies to connections the HOST opened (ssh to the guest, the port
      # forwards) come back in on agentbr too. Without this line they were
      # dropped below and `agent-vm up` waited for ssh forever (found live
      # 2026-10-30: ARP resolved, TCP SYN-ACK from the guest vanished).
      # Only ESTABLISHED/RELATED: a connection the guest starts is NEW.
      iptables -A agentvm-in -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -A agentvm-in -p tcp -d ${hostIp} --dport ${toString proxyPort} -j ACCEPT
      iptables -A agentvm-in -j DROP
      iptables -I INPUT 1 -i ${bridge} -j agentvm-in

      iptables -D FORWARD -i ${bridge} -j DROP 2>/dev/null || true
      iptables -D FORWARD -o ${bridge} -j DROP 2>/dev/null || true
      iptables -I FORWARD 1 -i ${bridge} -j DROP
      iptables -I FORWARD 1 -o ${bridge} -j DROP

      ip6tables -D INPUT -i ${bridge} -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -i ${bridge} -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -o ${bridge} -j DROP 2>/dev/null || true
      ip6tables -I INPUT 1 -i ${bridge} -j DROP
      ip6tables -I FORWARD 1 -i ${bridge} -j DROP
      ip6tables -I FORWARD 1 -o ${bridge} -j DROP
    '';
    networking.firewall.extraStopCommands = ''
      iptables -D INPUT -i ${bridge} -j agentvm-in 2>/dev/null || true
      iptables -F agentvm-in 2>/dev/null || true
      iptables -X agentvm-in 2>/dev/null || true
      iptables -D FORWARD -i ${bridge} -j DROP 2>/dev/null || true
      iptables -D FORWARD -o ${bridge} -j DROP 2>/dev/null || true
      ip6tables -D INPUT -i ${bridge} -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -i ${bridge} -j DROP 2>/dev/null || true
      ip6tables -D FORWARD -o ${bridge} -j DROP 2>/dev/null || true
    '';

    # ---- Filtering proxy -------------------------------------------------
    systemd.services.agent-vm-proxy = {
      description = "agent-vm: filtering HTTP proxy in front of Throne (drops private/special IPs)";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-networkd.service" "network.target" ];
      wants = [ "systemd-networkd.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.sing-box}/bin/sing-box run -c ${filterConfig}";
        # The bridge address may not be up yet at boot (networkd races
        # this unit): retry quickly rather than order against an address.
        Restart = "always";
        RestartSec = 2;
        DynamicUser = true;
        # Hardening: it only needs to bind one local address and talk
        # TCP/UDP (DNS) to the outside and to Throne on loopback, plus
        # netlink (see below).
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        # AF_NETLINK is required: sing-box opens a netlink socket at startup
        # (interface monitor). Without it the unit died in 50 ms and
        # restarted every 2 s forever (found live 2026-10-30; reproduced
        # with systemd-run --user -p RestrictAddressFamilies=...).
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
        CapabilityBoundingSet = "";
        SystemCallFilter = [ "@system-service" ];
      };
    };

    # ---- ssh key for `agent-vm shell` (host -> guest only) ---------------
    # The PRIVATE key stays on the host; the guest only gets the public
    # half through a read-only virtiofs share. The guest has no ssh client
    # configuration and no network to use one on.
    systemd.services.agent-vm-ssh-key = {
      description = "agent-vm: ssh key pair for host -> guest shell";
      wantedBy = [ "multi-user.target" ];
      before = [ "microvm@agent.service" ];
      path = [ pkgs.openssh pkgs.coreutils ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        install -d -m755 ${stateDir}
        # share/ is owned by the user: `agent-vm up` writes the filtered
        # gitconfig there. authorized_keys is owned by the same uid as the
        # guest user, which is what sshd's StrictModes wants.
        install -d -m755 -o ${cfg.user} ${stateDir}/share
        if [ ! -f ${stateDir}/id_ed25519 ]; then
          ssh-keygen -q -t ed25519 -N "" -C agent-vm -f ${stateDir}/id_ed25519
        fi
        chown ${cfg.user} ${stateDir}/id_ed25519
        chmod 600 ${stateDir}/id_ed25519
        install -m644 -o ${cfg.user} ${stateDir}/id_ed25519.pub ${stateDir}/share/authorized_keys
      '';
    };

    # ---- Host -> guest port forwards (browser access) --------------------
    # Loopback only, one socket unit per port; the connection is made BY
    # the host, so the guest-to-host firewall stays closed.
    systemd.sockets = lib.mapAttrs'
      (name: port: lib.nameValuePair "agent-vm-fwd-${name}" {
        wantedBy = [ "sockets.target" ];
        listenStreams = [ "127.0.0.1:${toString port}" ];
      })
      forwards;
    # `agent-vm up/down` without sudo: this one unit, nothing else.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "microvm@agent.service" &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';

    # virtiofsd does not start on a missing source, and one missing
    # directory would keep the whole VM down: create them (owned by the
    # user; `d` leaves existing directories and their contents alone).
    systemd.tmpfiles.rules = map (m: "d ${m.path} 0755 ${cfg.user} users -") allMounts;

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "agent-vm" ''
        export AGENT_VM_STATE_DIR=${stateDir}
        export AGENT_VM_GUEST_IP=${guestIp}
        export AGENT_VM_USER=${cfg.user}
        export AGENT_VM_HOME=${home}
        export AGENT_VM_MOUNTS='${lib.concatStringsSep "\n" (map (m: m.path) projectMounts)}'
        export AGENT_VM_PORTS='${lib.concatStringsSep " " (lib.mapAttrsToList (n: p: "${n}=${toString p}") forwards)}'
        export PATH=${lib.makeBinPath [ pkgs.openssh pkgs.coreutils pkgs.curl ]}:$PATH
        exec ${pkgs.bash}/bin/bash ${../../bin/agent-vm} "$@"
      '')
    ];

    # ---- The VM ----------------------------------------------------------
    microvm.vms.agent = {
      autostart = false;
      restartIfChanged = false;
      config = { pkgs, utils, ... }: {
        system.stateVersion = "24.05";

        microvm = {
          hypervisor = "qemu";
          vcpu = cfg.vcpu;
          mem = cfg.memoryMiB;
          interfaces = [{
            type = "tap";
            id = tap;
            mac = "02:00:00:a6:00:01";
          }];
          shares = [
            {
              # The host's /nix/store: the guest's root is built from it, no
              # image to pull (same idea as agent-sandbox). readOnly makes
              # virtiofsd itself pass --readonly. NOT optional: virtiofsd
              # runs as root on the host and microvm.nix only bind-mounts
              # /nix/store read-only INSIDE the guest, while its
              # /nix/.ro-store source mount stays writable -- without this
              # flag root in the guest could rewrite the host's store.
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
              proto = "virtiofs";
              readOnly = true;
            }
            {
              # authorized_keys + the filtered gitconfig (agent-vm up).
              tag = "host-share";
              source = "${stateDir}/share";
              mountPoint = "/mnt/host-share";
              proto = "virtiofs";
              readOnly = true;
            }
          ] ++ mountShares;
          volumes = [
            { image = "docker.img"; mountPoint = "/var/lib/docker"; size = cfg.dockerDiskMiB; }
            { image = "home.img"; mountPoint = home; size = cfg.homeDiskMiB; }
          ] ++ lib.optionals cfg.services [
            # Data of Postgres / Redis (below): the guest's root is a tmpfs,
            # so without a disk each `down` would drop the databases.
            { image = "postgres.img"; mountPoint = "/var/lib/postgresql"; size = cfg.servicesDiskMiB; }
            { image = "redis.img"; mountPoint = "/var/lib/redis-agent"; size = 2048; }
          ];
        };

        # Static address, no gateway, no DNS server: the only reachable
        # thing off this host is the proxy. IPv6 off (the proxy resolves
        # IPv4 only).
        networking.useDHCP = false;
        networking.useNetworkd = true;
        networking.enableIPv6 = false;
        systemd.network.networks."20-lan" = {
          matchConfig.MACAddress = "02:00:00:a6:00:01";
          address = [ "${guestIp}/24" ];
          networkConfig.LinkLocalAddressing = "no";
        };
        networking.proxy = {
          default = proxyUrl;
          noProxy = noProxy;
        };
        # Everything is reachable only from the bridge; the guest firewall
        # still closes all but the service ports.
        networking.firewall.allowedTCPPorts = [ 22 ] ++ builtins.attrValues forwards;

        virtualisation.docker = {
          enable = true;
          # Containers get the proxy through ~/.docker/config.json
          # (DOCKER_CONFIG below); the daemon (pulls) through daemon.json.
          daemon.settings.proxies = dockerProxies;
        };
        environment.etc."agent-docker/config.json".text = builtins.toJSON {
          proxies.default = dockerProxies;
        };

        # The host user, same name/uid/home: see "What the guest sees".
        users.users.${cfg.user} = {
          isNormalUser = true;
          uid = cfg.uid;
          home = home;
          extraGroups = [ "docker" "wheel" ];
          shell = pkgs.bashInteractive;
        };
        # Root inside a throwaway VM is the point (agents install things);
        # the VM's boundary is the hypervisor, not sudo.
        security.sudo.wheelNeedsPassword = false;

        # Ancestors of the mount points, created as the user BEFORE the
        # mounts (see ancestorsInHome). After the home volume is mounted
        # (RequiresMountsFor), before every share mount below it.
        systemd.services.agent-mountpoints = {
          description = "agent-vm: create mount-point parents owned by ${cfg.user}";
          wantedBy = [ "local-fs.target" ];
          before = [ "local-fs.target" ]
            ++ map (m: "${utils.escapeSystemdPath m.path}.mount") allMounts;
          unitConfig = {
            DefaultDependencies = false;
            RequiresMountsFor = home;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "agent-mountpoints" (lib.concatMapStrings
              (d: "${pkgs.coreutils}/bin/install -d -o ${cfg.user} -g users ${lib.escapeShellArg d}\n")
              ([ home ] ++ mountParents));
          };
        };

        # Inbound only: the host's key, copied in through the share. No
        # password login, no root login.
        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          };
          authorizedKeysFiles = [ "/mnt/host-share/authorized_keys" ];
        };

        # Generic Linux binaries (mise runtimes, npm packages with
        # prebuilt binaries) need a dynamic loader on NixOS: the same
        # reason as modules/nixos/nix-ld.nix on the host.
        programs.nix-ld.enable = true;

        # sessionVariables, not variables: those are read by login shells
        # only, and `agent-vm claude` is `ssh host 'cd ... && exec claude'`,
        # a non-login command. sessionVariables go through pam_env, which
        # sshd applies to every session, command or shell.
        environment.sessionVariables = {
          DOCKER_CONFIG = "/etc/agent-docker";
          # Git identity only (user.*, includeIf blocks): written by
          # `agent-vm up` from the host's config. Read as the SYSTEM
          # config so the user's own `git config --global` still wins.
          GIT_CONFIG_SYSTEM = "/mnt/host-share/gitconfig";
        } // lib.optionalAttrs cfg.miseInstalls {
          # Host runtimes, read-only; installs go to the guest's own dir.
          MISE_SHARED_INSTALL_DIRS = miseInstalls;
        } // lib.optionalAttrs cfg.services {
          # Same client variables as in agent-sandbox (agent-services.nix).
          PGHOST = "127.0.0.1";
          PGUSER = "postgres";
          REDIS_URL = "redis://127.0.0.1:6379/0";
        };

        # ---- Postgres + Redis, up from boot ------------------------------
        # Native NixOS services (agent-sandbox has to start them by hand,
        # there is no systemd in its container). Loopback only; role
        # `postgres` without a password, as in the sandbox and in
        # modules/nixos/dev-databases.nix: the VM has no other users and the
        # only way in is the host's key. Postgres 16 like dev-databases.nix
        # (a major upgrade = new cluster dir under /var/lib/postgresql/<major>,
        # the old one stays; move data with pg_upgrade/dump).
        services.postgresql = lib.mkIf cfg.services {
          enable = true;
          package = pkgs.postgresql_16;
          enableTCPIP = false; # listen_addresses below says it explicitly
          settings.listen_addresses = lib.mkForce "127.0.0.1";
          authentication = lib.mkForce ''
            local all all trust
            host all all 127.0.0.1/32 trust
          '';
        };
        # Named "agent" so the state dir is /var/lib/redis-agent (the disk
        # above). AOF + RDB snapshot: a restart must not lose the queue.
        services.redis.servers.agent = lib.mkIf cfg.services {
          enable = true;
          bind = "127.0.0.1";
          port = 6379;
          appendOnly = true;
          save = [ [ 60 1 ] ];
        };

        environment.systemPackages = with pkgs; [
          git curl jq ripgrep fd tmux vim gnumake gcc nodejs python3 mise
          docker-compose
          # The SAME wrapper package as on the host (claude, claude-use, ai):
          # accounts, path rules and the base settings behave identically.
          (callPackage ./packages/claude-accounts.nix { })
          (callPackage ./packages/kandev.nix { })
          ttyd
        ];

        # Terminal in the browser. --check-origin: a page in the user's
        # browser must not be able to open a writable websocket to it
        # (cross-site WebSocket hijacking); the host forward is plain
        # 127.0.0.1, so the Origin of a legitimate tab matches the Host.
        systemd.services.ttyd = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          serviceConfig = {
            User = cfg.user;
            WorkingDirectory = home;
            ExecStart = "${pkgs.ttyd}/bin/ttyd --writable --check-origin --port ${toString forwards.terminal} ${pkgs.bashInteractive}/bin/bash -l";
            Restart = "on-failure";
          };
        };

        systemd.services.kandev = {
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          path = [ pkgs.git pkgs.docker ];
          environment = {
            HOME = home;
            DOCKER_CONFIG = "/etc/agent-docker";
            GIT_CONFIG_SYSTEM = "/mnt/host-share/gitconfig";
          };
          serviceConfig = {
            User = cfg.user;
            WorkingDirectory = home;
            ExecStart = "${pkgs.callPackage ./packages/kandev.nix { }}/bin/kandev start --backend-port ${toString forwards.kandev}";
            Restart = "on-failure";
          };
        };
      };
    };
  } {
    # Separate merge element: systemd.services is also defined above.
    systemd.services = lib.mapAttrs'
      (name: port: lib.nameValuePair "agent-vm-fwd-${name}" {
        serviceConfig = {
          ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd ${guestIp}:${toString port}";
          DynamicUser = true;
          PrivateTmp = true;
        };
      })
      forwards
    // {
      # Do not tie the VM to the host's switch: a running agent session is
      # not restarted by `nixos-rebuild switch`; the new guest config
      # applies on the next `agent-vm down && up`.
      "microvm@agent".overrideStrategy = "asDropin";
      "microvm@agent".requires = [ "agent-vm-ssh-key.service" ];
      "microvm@agent".after = [ "agent-vm-ssh-key.service" "agent-vm-proxy.service" ];
    };
  } ]);
}
