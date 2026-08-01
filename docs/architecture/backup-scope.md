# Backup Scope

## Full backup contract (v2.2)

`FullBackupData` version 2.2 contains the authenticated user's ledger data:

- profile display fields (`nickname`, `email`, `avatar`, and `bio`)
- accounts, including archived accounts
- categories
- transactions
- budgets
- reminders
- lendings and lending records
- quick templates
- tags
- family members
- AI report history
- non-secret notification settings
- a complete attachment manifest for the user's upload directory

Restore replaces the user-owned ledger rows above. Ownership is rebound to the
authenticated target user, and stored upload references in profile avatars,
family-member avatars, transactions, reminders, lendings, and lending records
are remapped from `source_user_id` to that target user. Backups that mix owners
or reference rows owned by another user are rejected.

## Attachment manifest and restore semantics

Every regular file below `<upload_root>/<source_user_id>/` is embedded in the
JSON backup. Each `attachments` entry contains:

- `relative_path`: a canonical `/`-separated path relative to the user's
  directory; it never contains the source user ID
- `size`: the decoded byte length
- `sha256`: the SHA-256 digest of the decoded bytes, encoded as hexadecimal
- `content_base64`: the complete file contents encoded with standard Base64

Base64 is transport encoding, not encryption. Backup JSON therefore contains
the user's ledger data and attachment contents in recoverable form and must be
stored and transferred as sensitive data.

Before changing current data, restore validates and stages the complete
manifest. It verifies canonical ownership-safe paths, decoded sizes, SHA-256
digests, and Base64 encoding. The staged directory is swapped into
`<upload_root>/<authenticated_user_id>/` together with the database restore;
on failure, the service rolls back the database changes and attempts to restore
the previous attachment directory. Files belonging to other users are never
read, replaced, or deleted.

Manifest presence is significant:

- v2.2 emits `"attachments": []` when the user's upload directory is empty;
  restoring it intentionally replaces any current attachments with an empty
  directory
- v2.2 requires `attachments` to be an array; a missing or `null` manifest is
  rejected
- v2.1 accepts a missing or `null` `attachments` field and preserves the target
  user's current files; v2.1 backups containing an attachment array are
  rejected
- unknown backup versions are rejected before any current data is changed

Empty directories are not represented. Symbolic links and other non-regular
filesystem entries are not followed or backed up; encountering one fails
backup creation instead of silently exporting data outside the user's upload
directory.

## Limits and validation

- The entire serialized backup is limited by
  `storage.restore_max_file_size` (64 MiB by default). Creation validates the
  generated JSON against this limit, and restore bounds both the uploaded file
  size and bytes read.
- Each decoded attachment is limited by `storage.max_file_size` (10 MiB by
  default), and the sum of decoded attachment sizes must not exceed the restore
  limit. Because Base64 expands data, the whole-JSON limit can be reached first.
- A manifest may contain at most 10,000 files. A relative path may contain at
  most 4 KiB, 32 segments, and 255 bytes per segment.
- Restore performs a streaming JSON preflight before allocating model slices.
  It allows at most 100,000 total collection records, with per-collection
  limits of 100,000 transactions, 50,000 lending records, and 10,000 records
  for each other collection (including attachments). Backup creation applies
  the same preflight so it cannot emit a file that restore would reject.
- Absolute paths, traversal, backslashes, NUL bytes, leading user-ID segments,
  Windows-reserved or illegal names, portable case/Unicode collisions,
  duplicate paths, file/directory collisions, invalid Base64, and size or hash
  mismatches are rejected before current user data is replaced.

Backup creation and restore report byte-size or record-count limit failures as
HTTP 413 with application code `41300`.

## Notification credentials and legacy settings

Notification settings are included, but `dingtalk_secret`, `smtp_password`,
and `webhook_secret` are excluded from JSON. When notification settings are
present in a backup, restore updates the serializable fields while retaining
those three credentials already stored for the target user. If the target has
no notification row, the restored row is created with those credentials empty.
A legacy backup that omits `notification_settings` leaves the target row
unchanged.

Endpoint fields such as WeCom, DingTalk, and custom webhook URLs are currently
serializable settings and remain in the backup; operators must account for any
secret material embedded in such URLs.

## Security exclusions

Full backups do not contain or overwrite:

- username, password hash, login failure/lock state, or last-login state
- refresh tokens
- API-token rows, including token hashes and prefixes
- AI-provider configuration or encrypted API keys
- system-wide settings
- the three notification credentials listed above
- any other user's database rows or upload files
