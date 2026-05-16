# Backup Scope

Backups include user-owned ledger domain data:

- user profile display fields
- accounts, including archived accounts
- categories
- transactions
- budgets
- reminders
- lendings and lending records
- quick templates
- tags
- notification settings

Backups do not include security credentials:

- password hashes
- refresh tokens
- API token hashes or API token prefixes

Backups do not include binary upload file contents in this phase. Transaction image paths may be exported as transaction fields, but restore does not recreate missing files.

Restore replaces the user-owned ledger domain rows listed above for the selected user. It must not overwrite password hashes, login lock state, refresh tokens, API tokens, system settings, or uploaded file bytes.
