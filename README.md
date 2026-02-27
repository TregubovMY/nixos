[Hyprland на NixOS (издание 20XX) | Flakes + Home Manager](https://www.youtube.com/watch?v=7QLhCgDMqgw)

https://www.youtube.com/watch?v=bKx7V917b2Q&list=PLCQqUlIAw2cCuc3gRV9jIBGHeekVyBUnC&index=9


https://github.com/silentz/arch-linux-install-guide

disco: https://github.com/nix-community/disko/tree/master

```
sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko/latest -- --mode destroy,format,mount /tmp/disko.nix
```

```
nixos-install --flake /mnt/etc/nixos@mimir
```
