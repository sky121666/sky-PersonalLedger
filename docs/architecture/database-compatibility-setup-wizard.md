# Database Compatibility And Setup Wizard

## Goal

The app should keep SQLite as the zero-dependency default, while allowing self-hosted installs to choose a stronger database during first setup.

Support order:

1. SQLite: default, single-user or lightweight private deployments.
2. PostgreSQL: recommended for long-running server and multi-device use.
3. MySQL/MariaDB: supported for self-hosted deployments that already operate MySQL.

## Current Implementation

The backend now loads database driver config, opens the selected GORM dialect, runs `AutoMigrate`, then registers all API routes. Runtime database compatibility is available for SQLite, PostgreSQL, MySQL, and MariaDB.

The web app now treats first setup as a pre-login flow:

- Uninitialized backend -> `/setup`
- Initialized backend -> `/login`
- Authenticated user -> main app

SQLite remains the default config:

```yaml
database:
  driver: sqlite
  path: ./data/ledger.db
  dsn: ""
```

PostgreSQL/MySQL are persisted as `database.dsn`. The setup API can accept either an advanced DSN or structured host/port/database/username/password fields and build the DSN server-side.

## Proposed Config

```yaml
database:
  driver: sqlite
  path: ./data/ledger.db
  dsn: ""
  max_open_conns: 0
  max_idle_conns: 0
```

Examples:

```yaml
database:
  driver: postgres
  dsn: postgres://ledger:password@db:5432/ledger?sslmode=disable&TimeZone=Asia/Shanghai
```

```yaml
database:
  driver: mysql
  dsn: ledger:password@tcp(db:3306)/ledger?charset=utf8mb4&parseTime=True&loc=Local
```

Environment variables:

- `LEDGER_DATABASE_DRIVER`
- `LEDGER_DATABASE_PATH`
- `LEDGER_DATABASE_DSN`
- `LEDGER_DATABASE_MAX_OPEN_CONNS`
- `LEDGER_DATABASE_MAX_IDLE_CONNS`
- `LEDGER_SETUP_CONFIG_PATH`

## Setup Wizard Flow

Current flow:

1. Load config and open the configured database.
2. If no user exists, route the browser to `/setup` before login.
3. User tests the current database connection or enters a new database config. Server databases can be entered through structured fields, with advanced DSN available as an escape hatch.
4. If the user applies a new database config, the backend writes local YAML config and returns `restart_required: true`. Existing YAML sections are preserved; only `database` is replaced.
5. After restart, the backend connects to the selected database and runs schema migration.
6. User sets the first access password through the existing `/api/v1/auth/init` endpoint.
7. App switches to normal authenticated mode.

Setup APIs:

- Done: `GET /api/v1/setup/status`
- Done: `POST /api/v1/setup/test-database`
- Done: `POST /api/v1/setup/apply`
- Done: structured PostgreSQL/MySQL setup input with DSN generation and secret-safe responses.
- Reused: `POST /api/v1/auth/init`

Database testing and config apply are disabled after setup completes. The backend intentionally does not hot-switch databases; applying a different database config requires restart.

## Storage Rules

For local binary installs, the wizard can write a mounted local config file such as `data/config.yaml`.

For Docker installs, `LEDGER_SETUP_CONFIG_PATH` should point at a mounted path such as `/data/config.yaml`; otherwise the generated config can be written inside the container filesystem and be lost on recreate.

## Migration Strategy

Phase 1 keeps GORM `AutoMigrate`, but the database layer now records a schema version in `schema_migrations` and refuses to open a database whose recorded version is newer than the running application. This does not replace real migration files, but it prevents old binaries from silently mutating a newer schema.

Phase 2 should introduce versioned migrations before production PostgreSQL/MySQL support is marked stable. This avoids hidden schema drift between database engines.

## Compatibility Notes

- SQLite remains the default because it is easy to back up and needs no external service.
- PostgreSQL should be the recommended server option for reliability and concurrent access.
- MySQL/MariaDB has been verified against schema migration, first init, default data creation, transaction creation, list readback, overview, trend statistics, and backup settings on a local MySQL instance.
- Backup and restore must stay database-agnostic at the application data level.

## Verification

Local database matrix verification:

```bash
./scripts/verify-database-matrix.sh
```

By default the script starts temporary PostgreSQL and MySQL containers with Docker. CI can pass DSNs directly and skip local container creation:

```bash
RUN_LOCAL_DATABASE_CONTAINERS=0 \
LEDGER_TEST_POSTGRES_DSN='postgres://ledger:ledger@127.0.0.1:5432/ledger_test?sslmode=disable&TimeZone=UTC' \
LEDGER_TEST_MYSQL_DSN='ledger:ledger@tcp(127.0.0.1:3306)/ledger_test?charset=utf8mb4&parseTime=True&loc=UTC' \
./scripts/verify-database-matrix.sh
```

`scripts/verify-clean-checkout.sh` keeps the database matrix optional behind `RUN_DATABASE_MATRIX=1` so normal local clean checks do not require Docker.

GitHub runs `.github/workflows/backend-database.yml` for backend/database changes. The workflow is guarded with `github.server_url == 'https://github.com'` so Forgejo does not attempt to execute GitHub Actions services.

## Implementation Batches

1. Done: add database driver config and dialect selection, keep SQLite default.
2. Done: add PostgreSQL/MySQL/MariaDB driver selection behind config.
3. Done: add setup status, database connection test, and pre-login setup route.
4. Done: add config persistence for local installs and Docker guidance for env-based installs.
5. Done: add user-friendly structured database form before login while preserving advanced DSN mode.
6. Keep `/api/v1/auth/init` for the first access password until a true no-database bootstrap mode is introduced.
7. Done: add schema version guard plus PostgreSQL/MySQL database matrix verification script and GitHub workflow.
