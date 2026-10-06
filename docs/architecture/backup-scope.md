# Backup Scope

## Full backup contract (v2.4)

CreateBackup currently emits FullBackupData version 2.4 through an explicit backup codec, independent
of the business API model JSON. It contains the authenticated user's
ledger data:

- profile display fields: nickname, email, avatar, and bio
- accounts, categories, transactions, budgets, reminders, lendings and lending records
- quick templates, tags, family members, AI report history and account/notification logs
- notification preferences represented by the credential-free portable DTO
- an explicit attachments value describing whether file data is included

Restore replaces the user-owned ledger rows represented by the backup. Ownership is rebound to the
authenticated target user, and stored upload references are remapped from source_user_id to that
target user. Backups that mix owners or reference another user's rows are rejected.

Version 2.4 includes an explicit `deleted_at` for every account, category, transaction, budget,
reminder, lending, lending record, template, tag, family member and AI report. `null` denotes an
active row; a timestamp denotes a soft-deleted row. Both active and deleted rows are retained so
historical references and rollback logs remain connected. Missing deletion state in any of these
records is rejected before replacement. Restoring tombstones does not replay balance changes:
account balances, active transactions and spending statistics retain their backed-up state.
Archived accounts, paid-off reminders and settled lending keep their separate state fields.
Disabled budgets, reminders and members remain disabled. Restore also preserves zero-day reminder
advance notice rather than allowing GORM insertion defaults to replace these explicit values.

Every supported envelope must explicitly contain the collections its original exporter emitted:

- v2.1: accounts, categories, transactions, budgets, reminders, lendings, lending_records, templates
  and tags. Family members, AI reports and logs are optional because they were added after the
  earliest 2.1 exporter without changing that version.
- v2.2, v2.3 and v2.4: those nine collections plus family_members, ai_reports, account_logs and
  notification_logs.

Collection `null` and `[]` both explicitly describe an empty database collection. An envelope with
all required collections explicitly empty is a valid intentional empty-ledger restore. A missing
required collection, including a profile-only JSON object, is rejected before profile, database or
file mutations. Optional profile and notification preferences retain their existing behavior.

The 2.1–2.3 codecs remain readable with their original field semantics. Those formats did not
serialize model tombstones. Earlier exporters sometimes excluded deleted rows; later exporters
included them without deletion state. A legacy file cannot distinguish those included deleted rows
from active rows, and restore cannot reconstruct or invent that lost information. Create a new 2.4
backup from the original database when deletion-state preservation is needed. Do not relabel a
legacy JSON file as 2.4.

Creation reads every database collection, profile and notification preference through one database
snapshot. SQLite uses a read transaction whose first SELECT fixes the WAL snapshot; PostgreSQL and
MySQL explicitly request a read-only REPEATABLE READ transaction instead of relying on the server's
default isolation level. MySQL deployments require transactional tables (InnoDB). A concurrent ledger
write may finish during creation, but its account balance, transactions and logs are either all
included or all excluded from that snapshot. A failed query fails creation rather than emitting a
partial backup. The snapshot helper rejects an existing transaction because a nested GORM savepoint
cannot establish a different isolation level.

Creation also takes the attachment maintenance write barrier before opening the database snapshot
and holds it until the attachment contents have been captured. Uploads, deletion, attachment metadata
updates and garbage collection wait for creation to finish, so file contents cannot move while the
database snapshot refers to them. This briefly serializes attachment access, including downloads;
ordinary ledger writes remain available. The barrier has the same single-write-instance requirement
as restore and does not coordinate another process or an operator changing files directly.

## Attachment manifest and restore semantics

When file data is included, every regular file below
upload_root/source_user_id is embedded in the JSON backup. Each attachments entry contains:

- relative_path: canonical slash-separated path relative to the user's directory
- size: decoded byte length
- sha256: SHA-256 of the decoded bytes
- content_base64: complete file contents encoded with standard Base64

Base64 is transport encoding, not encryption. Backup JSON contains recoverable ledger and attachment
data and must be stored and transferred as sensitive data.

Versions 2.3 and 2.4 require the attachments field to be present and make its meaning explicit:

- null means the backup did not include file data; restore preserves the target user's current files
- an array is authoritative; an empty array intentionally replaces current attachments with an empty
  directory
- a missing attachments field is rejected

CreateBackup normally emits an array when an upload service is available, including an empty array
when the user's upload directory is empty. A build without attachment storage support emits null.

Compatibility rules:

- v2.2 requires an attachment array; missing or null is rejected
- v2.1 accepts missing or null and preserves target files, but rejects an attachment array
- unknown versions are rejected before current data is changed

Before changing current data, restore validates and stages the complete manifest. It verifies safe
paths, decoded sizes, SHA-256 digests and Base64, then fsyncs the staged files and directory tree.
The database restore transaction records a permanent desired attachment generation as its final
write. No active attachment directory is renamed before that transaction commits.

After commit, restore moves only forward to the desired generation: it moves the old active
directory aside, activates the staged directory, verifies the internal generation token, and then
removes the previous directory. Each rename and cleanup is followed by a parent-directory fsync.
If activation cannot be proved, the request reports recovery pending instead of a normal success;
the committed stage is retained and startup recovery completes it before routes, schedulers, or
upload GC are enabled. Once the active token is verified, a failure to remove obsolete stage or
previous data is a cleanup warning and is retried without rolling the database or active files back.

Restore/recovery holds the attachment maintenance write barrier. Upload, download, delete, list,
and GC operations hold its read side, so an upload cannot land in a directory being replaced.
Other users' files are never read, replaced, or deleted.

The barrier is process-local. A shared upload root currently supports one write-capable application
instance; multi-replica writers require an external distributed lease and are not a supported
deployment topology.

Empty directories are not represented. Symbolic links and non-regular entries are not followed;
encountering one fails creation. The internal desired-generation setting, restore stage/previous
directories, and generation-token file are operational metadata: they are excluded from backup,
download, upload-reference persistence, and normal GC traversal.

## Notification settings and credentials

Versions 2.3 and 2.4 serialize a dedicated NotificationSettingsBackup DTO containing only portable reminder
preferences: payment-due, budget-alert, lending-due, login and annual-report switches plus advance
days. Delivery enablement, SMTP configuration and recipient identity, endpoint URLs, and shared
credentials are target-instance state and are never serialized.

The 2.3/2.4 JSON preflight rejects notification_settings containing any credential-capable field,
including:

- wecom_webhook
- dingtalk_webhook or dingtalk_secret
- smtp_password
- webhook_url or webhook_secret

Restore updates only those portable preferences and preserves all local delivery configuration and
credentials. When restoring a profile email, an enabled SMTP channel that used the old profile-email
fallback is first pinned to the old local address, preventing the imported profile from silently
redirecting mail. When no target notification row exists, restore creates only the preferences with
all delivery switches disabled and credentials empty. A legacy backup that omits
notification_settings leaves the target row unchanged.

This means a backup/restore is not a credential migration mechanism. Operators must configure and
test notification credentials separately on the target instance.

## Limits and validation

- The serialized backup is limited by storage.restore_max_file_size, 64 MiB by default. Creation and
  restore apply the same bound.
- Each decoded attachment is limited by storage.max_file_size, 10 MiB by default, and total decoded
  attachment bytes must not exceed the restore limit.
- A manifest may contain at most 10,000 files. A relative path may contain at most 4 KiB,
  32 segments, and 255 bytes per segment.
- Streaming JSON preflight allows at most 100,000 total collection records. Transactions,
  account logs, and notification logs are individually capped at 100,000; lending records at
  50,000; every other collection, including attachments, at 10,000. Backup creation applies the
  same preflight, so it cannot emit a file restore would reject.
- Absolute paths, traversal, backslashes, NUL bytes, leading user-ID segments, Windows-reserved or
  illegal names, portable case/Unicode collisions, duplicate paths, file/directory collisions,
  invalid Base64, and size/hash mismatches are rejected before replacement.

Byte-size or record-count violations are reported as HTTP 413 with application code 41300.

## Security exclusions

Full backups do not contain or overwrite:

- username, password hash, login failure/lock state or last-login state
- refresh tokens
- API-token rows, including hashes and prefixes
- AI-provider configuration or encrypted API keys
- internal AI-report ProviderRevision and transaction import fingerprints
- notification endpoints, webhook secrets or SMTP passwords
- system-wide settings
- another user's database rows or upload files

Before upgrade or rollback, verify that the target release supports the backup version and its
attachment semantics. Keep the backup encrypted at rest and do not paste JSON or notification
configuration into tickets or logs.
