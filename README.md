# Postgres/Redis Development Environment

## Postgres/Redis для локальной разработки

Общий Postgres 16 + Redis 7 для всех локальных проектов (декларативные
podman-контейнеры, `modules/nixos/dev-databases.nix`) — поднимаются вместе
с системой, ничего не нужно ставить/поднимать вручную на уровне проекта.

- Postgres: `127.0.0.1:5432`, пользователь `postgres`, **без пароля**
  (`POSTGRES_HOST_AUTH_METHOD=trust`) — локальная машина, БД доступна
  только с localhost, реального смысла в пароле нет.
- Redis: `127.0.0.1:6379`, без аутентификации, по той же причине.
- Данные — в `/var/lib/dev-postgres` / `/var/lib/dev-redis` на тестовом
  хосте этого плана; **на реальной машине переносится в
  `/persist/postgres` / `/persist/redis`** (см. `system-plan.md` §4) —
  поправить пути в `dev-databases.nix` при переносе в `hosts/<host>/`.
