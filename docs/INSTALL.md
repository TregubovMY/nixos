# Установка

Один и тот же путь для виртуалки и для настоящей машины: загрузиться с
NixOS ISO и запустить `bin/install-host <имя-машины> <диск>`. Данные о
железе заранее не нужны — скрипт снимает их сам (nixos-facter) и кладёт в
`hosts/<имя-машины>/facter.json`.

**Сначала — репетиция в VM** (раздел 1): тот же скрипт и тот же конфиг на
виртуальном диске. Потом — настоящая машина (раздел 2).

## Имена машин

Каждая машина — папка `hosts/<имя>/` (`flake.nix` находит их сам), общее —
в `hosts/common.nix`. Сейчас есть `mimir` (ноутбук). Для новой машины
(например рабочего ПК) просто укажите новое имя — `install-host` создаст
папку сам. Для VM берите отдельное имя (`vm-test`), чтобы отчёт о железе
виртуалки не попал в настоящую машину.

## 1. Репетиция в VM

**Нужно:** KVM, 8 ГБ RAM и 4 ядра под VM, **~60 ГБ** под диск VM (система
с десктопом — 30–40 ГБ, плюс swap = RAM + 2 ГБ).

**virt-manager** (так ставилась первая репетиция):
- новая VM из `latest-nixos-minimal-x86_64-linux.iso`
  (https://channels.nixos.org/nixos-unstable/), диск 60+ ГБ, 8 ГБ RAM;
- «Customize before install»: Firmware — **UEFI с Secure Boot**
  (`…secboot…`); Video — **Virtio** с **3D acceleration**, Display Spice —
  Listen type **None**, **OpenGL** включён (иначе Hyprland без 3D);
- канал `spicevmc` (`com.redhat.spice.0`) — для общего буфера обмена.

Внутри VM, загрузившись с ISO (пользователь `nixos`, sudo без пароля):

```bash
nix-shell -p git --run 'git clone https://github.com/TregubovMY/nixos'
cd nixos
lsblk -d -o NAME,SIZE,MODEL            # диск VM — обычно /dev/vda
bin/install-host vm-test /dev/vda
```

Скрипт спросит: путь диска ещё раз, пароль LUKS (дважды), пароль
пользователя `max`. Первая попытка `nixos-install` может упасть на шаге
загрузчика — так и задумано (создаются ключи Secure Boot, вторая попытка).
**Не пушить** `hosts/vm-test/` — это отчёт о железе виртуалки.

**Если висят таймауты `cache.nixos.org`** (бывает в РФ), до запуска:
```bash
# через прокси, если есть (именно для nix-daemon, переменных shell мало):
sudo systemctl set-environment https_proxy=http://<прокси>:<порт> http_proxy=http://<прокси>:<порт>
sudo systemctl restart nix-daemon
# или зеркало кэша:
echo 'substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://cache.nixos.org' | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
```

### Что проверить в VM

- [ ] Пароль LUKS спрашивается **один раз**.
- [ ] Экран входа → `max` → Hyprland **сразу с панелью DMS** (`dms setup`
      выполняется сам при установке).
- [ ] `systemctl --failed` и `systemctl --user --failed` — пусто.
- [ ] Сеть: `nmcli general status`; `id` → группы `wheel networkmanager libvirtd input`.
- [ ] CapsLock переключает раскладку; Ctrl+←/→, Ctrl+Backspace/Delete в терминале.
- [ ] Скриншоты Print / SUPER+SHIFT+Print, запись SUPER+SHIFT+R,
      перевод SUPER+ALT+T (окно Dialect с переводом выделенного).
- [ ] Выход из сессии — **SUPER+X → выйти**, вход снова — всё поднялось.
- [ ] Secure Boot: `sudo sbctl status` (Setup Mode) →
      `sudo sbctl enroll-keys --microsoft --yes-this-might-brick-my-machine`
      (флаг — только в VM: у неё нет TPM-журнала Option ROM) → перезагрузка →
      `bootctl status` → `Secure Boot: enabled (user)`.
- [ ] Гибернация: `systemctl hibernate` → запуск → пароль LUKS → сессия на месте.
- [ ] Песочница агентов: `agent-sandbox ~/code/<проект> -- claude --version`
      (подробно — README, «Песочница агентов»).

**Пустить агента (Claude) в VM по SSH** для проверки:
`cd ~/code/nixos && git pull && bin/vm-ssh-on` — только в VM, только по
ключу агента, до перезагрузки.

**Особенности VM, не ошибки:** погода DMS не грузится, если open-meteo
заблокирован в сети (нужен прокси, раздел «После установки»); `sudo sbctl
verify` показывает ядра в `/EFI/nixos/` как неподписанные — это норма для
lanzaboote (подписан загрузчик-«заглушка», ядро и initrd он проверяет по
хэшу, а не по подписи); общий буфер через SPICE под Wayland работает в
основном в сторону хост → VM.

## 2. Настоящая машина

1. Записать тот же ISO на флешку, в прошивке включить загрузку с USB в
   режиме **UEFI**; Secure Boot временно выключить (или Setup Mode).
2. Загрузиться, подключить сеть (`nmtui` или кабель).
3. Как в VM, но со своим именем и диском:
   ```bash
   nix-shell -p git --run 'git clone https://github.com/TregubovMY/nixos'
   cd nixos
   lsblk -d -o NAME,SIZE,MODEL
   bin/install-host mimir /dev/nvme0n1      # рабочий ПК — например work-pc
   ```

## 3. После установки (и на VM, и на машине)

1. Перезагрузка без флешки → пароль LUKS → вход `max`.
2. **Secure Boot** (на железе): в прошивке «Reset to Setup Mode», загрузиться,
   `sudo sbctl enroll-keys --microsoft` (**без** `--yes-this-might-brick…`;
   если sbctl отказывается — не форсировать, разобраться), перезагрузка,
   включить Secure Boot, `bootctl status`.
3. **Закоммитить машину** (на железе, не в VM):
   ```bash
   cd ~/code/nixos && git add hosts/mimir && git commit -m "mimir: hardware report" && git push
   ```
4. **Прокси (Throne)**: импорт VLESS-конфига из Bitwarden; маршрутизация —
   по умолчанию direct, через прокси только список доменов (jetbrains,
   open-meteo, anthropic/claude, …), `rnds.pro` и рабочие подсети — direct
   (подробно — `REFERENCE.md`, «Прокси и рабочий VPN»).
5. После прокси — RubyMine: `desktopApps.rubymine.enable = true` в
   `hosts/common.nix`, затем `sudo nixos-rebuild switch --flake .#mimir`.
6. **Рабочий VPN**: `nmcli connection import type openvpn file work.ovpn`.
7. **Календарь**: `dcal account add google`.
8. **Песочницы агентов**: конфиги `work`/`study`/`personal` и первый вход в
   каждой — README, «Песочница агентов».

## Обновление уже установленной системы

```bash
cd ~/code/nixos && git pull
sudo nixos-rebuild switch --flake .#$(hostname)
```
Откат — выбрать предыдущую версию в меню загрузки или
`sudo nixos-rebuild switch --rollback`. Подробнее — `NIX-HOWTO.md`.
