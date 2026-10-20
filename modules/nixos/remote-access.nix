# Входящий доступ к этой машине: SSH, удалённый экран (VNC), приём файлов
# (LocalSend). Запрошено live 2026-10-20: "откроем порты по умолчанию, но
# чтобы без пароля (желательно временного) никто не подключился и не
# задудосил". Как пользоваться — docs/DAILY-WORKFLOW.md, «Удалённый доступ».
#
# Принцип: порт в firewall открыт всегда, но за ним либо ничего не слушает
# (VNC — только пока вы сами запустили `remote-screen`, и на нём одноразовый
# пароль), либо слушает сервис, который без секрета не пускает (SSH — только
# по ключу; LocalSend — каждый входящий файл нужно подтвердить + PIN в
# настройках приложения). Так открытый порт сам по себе ничего не отдаёт.
#
# KDE Connect сам открывает свои порты (programs.kdeconnect в
# desktop-apps.nix) — здесь его нет.
{ config, lib, pkgs, ... }:
let
  cfg = config.remoteAccess;

  # TCP: ssh, wayvnc. TCP+UDP: LocalSend (UDP — обнаружение устройств в LAN,
  # TCP — сама передача по TLS).
  sshPort = 22;
  vncPort = 5900;
  localsendPort = 53317;

  # Приватные диапазоны RFC 1918 + link-local. IPv6 сознательно не трогаем:
  # ни один из трёх сервисов не обещает работу по v6 в LAN, а лишнее правило
  # — лишняя поверхность.
  lanRanges = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "169.254.0.0/16" ];

  # TCP/UDP-порты, которые открываем (протокол, порт).
  openPorts = [
    { proto = "tcp"; port = sshPort; }
    { proto = "tcp"; port = vncPort; }
    { proto = "tcp"; port = localsendPort; }
    { proto = "udp"; port = localsendPort; }
  ];

  # Запуск `wayvnc` с одноразовым паролем и свежим сертификатом.
  # Почему скрипт, а не systemd-сервис с постоянным паролем:
  # - пароль живёт только пока идёт сеанс (и пока не истёк таймер) — "временный
  #   пароль" из запроса; пароль в git/конфиге не лежит вообще;
  # - порт 5900 слушает только на время сеанса;
  # - wayvnc 0.10 при enable_auth=true требует ещё certificate_file и
  #   private_key_file (TLS), поэтому сертификат генерируется заново на сеанс
  #   (`man wayvnc`, "enable_auth"). Без шифрования пароль по сети не пойдёт.
  # - по умолчанию создаётся отдельный headless-монитор VNC-1, а не снимается
  #   живой экран: стриминг физического вывода у wayvnc ненадёжен ("серый/
  #   пустой экран", any1/wayvnc#326, system-plan.md §5.1.1). `--real` — на
  #   свой страх и риск.
  # `hyprctl keyword monitor` в Hyprland 0.56 с Lua-конфигом не работает
  # ("non-legacy parsers. Use eval"), поэтому разрешение не задаётся:
  # headless-вывод и так создаётся как 1920x1080@60 (проверено live).
  remoteScreen = pkgs.writeShellApplication {
    name = "remote-screen";
    runtimeInputs = with pkgs; [ wayvnc hyprland openssl coreutils iproute2 ];
    text = ''
      duration=1h
      real=0
      view_only=0
      output=VNC-1

      usage() {
        cat <<'EOF'
      remote-screen [-t ВРЕМЯ] [--real] [--view-only]

      Поднимает VNC-сервер (wayvnc) на порту ${toString vncPort} с одноразовым
      паролем и закрывает его через ВРЕМЯ (по умолчанию 1h; формат как у
      timeout: 30m, 2h) или по Ctrl-C.

        -t ВРЕМЯ      сколько держать сеанс открытым
        --real        отдавать настоящий экран (по умолчанию — отдельный
                      виртуальный монитор VNC-1: так стабильнее)
        --view-only   только смотреть, без управления мышью/клавиатурой
      EOF
      }

      while [ $# -gt 0 ]; do
        case "$1" in
          -t) duration="''${2:?-t требует значение, например 30m}"; shift 2 ;;
          --real) real=1; shift ;;
          --view-only) view_only=1; shift ;;
          -h|--help) usage; exit 0 ;;
          *) usage >&2; exit 2 ;;
        esac
      done

      if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
        echo "remote-screen: запускать нужно из сессии Hyprland (нет HYPRLAND_INSTANCE_SIGNATURE)" >&2
        exit 1
      fi

      dir="$(mktemp -d "''${XDG_RUNTIME_DIR:-/tmp}/remote-screen.XXXXXX")"
      chmod 700 "$dir"
      cleanup() {
        if [ "$real" = 0 ]; then hyprctl output remove "$output" >/dev/null 2>&1 || true; fi
        rm -rf "$dir"
      }
      trap cleanup EXIT INT TERM

      # 12 hex = 48 бит: перебор по сети за час сеанса нереален, а пароль
      # ещё можно продиктовать голосом без ошибок. Дольше сеанс — длиннее
      # окно для перебора, поэтому по умолчанию 1h.
      password="$(openssl rand -hex 6)"
      openssl req -x509 -newkey rsa:3072 -nodes -days 1 \
        -subj "/CN=$(hostname)" \
        -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null

      {
        echo "address=0.0.0.0"
        echo "port=${toString vncPort}"
        echo "enable_auth=true"
        echo "username=remote"
        echo "password=$password"
        echo "certificate_file=$dir/cert.pem"
        echo "private_key_file=$dir/key.pem"
      } > "$dir/wayvnc.conf"

      args=(-C "$dir/wayvnc.conf")
      [ "$view_only" = 1 ] && args+=(--disable-input)
      if [ "$real" = 0 ]; then
        hyprctl output create headless "$output" >/dev/null
        args+=(-o "$output")
      fi

      echo "Адреса этой машины:"
      ip -4 -o addr show scope global | awk '{print "  " $4}' | cut -d/ -f1
      echo "Порт:     ${toString vncPort}"
      echo "Логин:    remote"
      echo "Пароль:   $password   (одноразовый, пропадёт при остановке)"
      echo "Сеанс закроется через $duration или по Ctrl-C."

      # timeout, а не sleep+kill: код возврата не важен, важно, что
      # trap cleanup всё равно сработает.
      timeout "$duration" wayvnc "''${args[@]}" || true
    '';
  };
in
{
  options.remoteAccess.lanOnly = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Принимать подключения к SSH/VNC/LocalSend только из частных сетей
      (192.168/16, 10/8, 172.16/12), а не из любого адреса. Частные диапазоны
      — не граница доверия (в кафе тоже 192.168.x.x), но отсекают весь
      интернет-фон; сами сервисы защищены паролем/ключом независимо от этого.
    '';
  };

  config = {
    services.openssh = {
      enable = true;
      # Порты открываем сами ниже (с ограничением по источнику).
      openFirewall = false;
      settings = {
        # Только по ключу: пароль по ssh перебирают ботами, ключ — нет.
        # Публичный ключ класть в ~/.ssh/authorized_keys руками (в git не
        # попадает, как и остальные данные доступа — README.md, «Секреты»).
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [ "max" ];
        MaxAuthTries = 3;
        LoginGraceTime = 20;
      };
    };

    # Защита от перебора/долбёжки: после нескольких неудач IP банится
    # firewall'ом. Джейл sshd включается сам, когда включён openssh;
    # bantime-increment растит срок бана за повторы.
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      bantime-increment = {
        enable = true;
        maxtime = "48h";
      };
    };

    networking.firewall = if cfg.lanOnly then {
      # Не allowedTCPPorts: они открывают порт для всех адресов. Правила
      # добавляются в конец цепочки nixos-fw перед финальным refuse.
      extraCommands = lib.concatStringsSep "\n" (
        # Контейнеры песочницы агентов (podman) ходят через интерфейсы
        # podman*: в 10.0.0.0/8 они тоже попадают, а агенту ходить на ssh/
        # vnc хоста незачем — режем до разрешающих правил.
        (map (p: "iptables -A nixos-fw -i podman+ -p ${p.proto} --dport ${toString p.port} -j nixos-fw-refuse") openPorts)
        ++ lib.concatMap (r:
          map (p: "iptables -A nixos-fw -s ${r} -p ${p.proto} --dport ${toString p.port} -j nixos-fw-accept") openPorts
        ) lanRanges
      );
    } else {
      allowedTCPPorts = [ sshPort vncPort localsendPort ];
      allowedUDPPorts = [ localsendPort ];
    };

    environment.systemPackages = [ remoteScreen ];
  };
}
