# Money Precision

Current state: public API fields remain decimal JSON numbers, while persisted monetary values use signed `BIGINT` minor units (cents). Core additions, subtractions, comparisons, aggregates, budgets, reports, imports, reminders, lending, and account logs operate through `money.Amount` cent helpers.

Schema migration v8 adds parallel `*_cents` columns and backfills them with half-away-from-zero rounding. It supports SQLite, PostgreSQL, and MySQL without changing the public JSON field names or numeric representation.

The legacy decimal columns are intentionally retained as a rollback snapshot. New application writes target only the cent columns.

Migration guardrails:

- Monetary model fields must use `money.Amount`; rates and percentages may remain `float64`.
- Raw SQL must reference the `*_cents` physical columns and pass integer cent parameters.
- Import/export and API responses preserve decimal numbers at the boundary.
- Migration fixtures cover positive and negative fractional-cent rounding and nullable values.

Rollback procedure:

1. Stop writes and take a database backup.
2. Copy each cent column back into its retained legacy column using `legacy = cents / 100.0` with the database's decimal cast.
3. Run the previous application version.
4. Keep the cent columns until the rollback has been verified; dropping them is a separate destructive migration.

Because the previous application cannot see writes made only to cent columns, rolling back without step 2 would lose post-migration monetary updates.
