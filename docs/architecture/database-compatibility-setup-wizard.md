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

The database layer now runs a versioned migration list. Each migration has a numeric version, a stable name, and an apply function, and successful runs are recorded in `schema_migrations`. The application refuses to open a database whose recorded version is newer than the running binary supports.

Migration v1 still uses GORM `AutoMigrate` to create the initial ledger schema across SQLite, PostgreSQL, and MySQL/MariaDB. Future schema changes should be added as new migration entries instead of editing the historical v1 migration. This keeps upgrade order auditable and avoids hidden schema drift between database engines.

Migration v12 (`repayment_request_idempotency`) adds only `repayment_requests`. Its composite primary
key is `(user_id, operation, target_id, key_hash)`; `payload_hash` binds the key to the accepted
request. Existing balances and ledger rows are unchanged. Reminder payment and lending repayment
accept optional JSON `idempotency_key` (at most 128 bytes). The target is locked before reading or
inserting its claim, and the claim, balances, transaction and logs commit together. SQLite uses the
existing finance write mutex; PostgreSQL/MySQL use the target row lock and the unique primary key.
An exact retry returns HTTP 200 with the current target object and creates no further effects;
changed content under the same scope/key returns HTTP 409/code 40903. Missing or empty keys retain
legacy behavior. Deleted targets remain unavailable and cannot be recreated by replaying a key.

Web clients save a new key and the exact payload in `sessionStorage` before the first submission.
An unconfirmed operation survives dialog reopening and page reload within that browser session;
its original payload remains locked until a retry confirms the result, including for paid-off targets.
After successful payment, a deliberate additional payment needs a new key. Failed transactions do
not consume their server-side keys. This client recovery does not persist across browser sessions.
The backup contract carries completed claims with their ledger state.
The schema guard prevents running a schema-11 binary against an upgraded database. Rollback requires
restoring the pre-upgrade database snapshot with its matching application version; never remove
only the migration record while retaining the new financial history.

Account deletion and reference writes use the same account-lock protocol. Deletion locks the active
account first, then checks historical references in a separate statement before deleting. Reminder
creation/update/rebinding, lending creation, template creation/application and transaction reference
validation lock and recheck active accounts inside their write transaction. Multiple accounts are
locked in sorted ID order. SQLite financial writes share the existing process-local writer mutex;
this guarantee assumes one writable application instance. Recurring transactions currently have
only a model/migration and no API or service write path; their stored references still block deletion.
Unknown reminder-payment database or post-commit read failures return HTTP 500 so clients retain the
pending idempotency key. Only recognized business validation failures are returned as 4xx.

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
8. Done: replace one-shot startup migration with an ordered versioned migration list and migration-name records.
