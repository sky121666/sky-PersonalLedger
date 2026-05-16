# Recurring Transactions

Decision for the next release: recurring transactions are deferred. The current release should not expose a partial recurring UI or API route. The database model may remain reserved until a full scheduler, preview, edit, pause, and audit flow is implemented.

Required behavior:

- no visible web route for recurring transactions
- no sidebar entry for recurring transactions
- no API documentation claiming recurring support
- existing transaction fields can keep `recurring_id` as a nullable reserved field

Future implementation must include:

- scheduler ownership and retry behavior
- preview before creating generated transactions
- pause/resume and edit semantics
- account log and balance rollback behavior
- import/export and backup restore semantics
