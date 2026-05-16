# Money Precision

Current state: API and database models expose money as `float64`, while GORM tags use decimal-like column declarations. SQLite does not guarantee fixed decimal arithmetic for these fields.

Decision: migrate persisted monetary values to integer cents in a later schema migration. Public JSON fields can remain decimal numbers during the transition, but service code must convert at boundaries and run arithmetic on cents.

First slice: add tested conversion helpers and use them in new code only. Do not rewrite every model in the same patch.

Migration guardrails:

- New balance arithmetic should avoid adding or subtracting `float64` values.
- Import/export should preserve the public decimal representation until clients are migrated.
- The schema migration must include a rollback plan and fixture data with fractional cents.
