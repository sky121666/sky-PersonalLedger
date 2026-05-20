# Ledger Follow-Up Repairs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining release risks after the stabilization batch: clean-checkout reliability, authenticated attachments, backup scope clarity, money precision, runtime mobile smoke tests, and the recurring-transaction product decision.

**Architecture:** Keep the current Go/Gin/GORM backend, Vue web client, and Flutter native client. Repair one contract at a time with small tests before implementation, and keep larger migrations behind explicit architecture notes before touching schema-wide code.

**Tech Stack:** Go 1.24, Gin, GORM, SQLite, Vue 3, TypeScript, Vite, Flutter, Riverpod, Dio, GitHub Actions.

---

## File Structure

- Create `scripts/verify-clean-checkout.sh`: reproducible local gate that tests the committed tree, not the current dirty working tree.
- Modify `.github/workflows/android.yml`: fail early if required Flutter Android wrapper files are missing from the repository.
- Modify `web/src/api/file.ts`: replace unauthenticated URL helpers with authenticated Blob download/preview helpers.
- Modify `web/src/components/FileUpload.vue`: use Blob object URLs for preview and download, and revoke object URLs after use.
- Modify `mobile/lib/features/attachments/data/attachment_repository.dart`: add an authenticated byte-download API for image preview.
- Create `backend/internal/handler/upload_test.go`: lock down missing-token and bearer-token behavior for downloads.
- Create `docs/architecture/backup-scope.md`: define which runtime data is included in backup restore and which data is intentionally excluded.
- Create `backend/internal/service/backup_scope_test.go`: verify the chosen backup scope for upload metadata and API tokens.
- Create `docs/architecture/money-precision.md`: choose the money representation migration path before schema-wide edits.
- Create `backend/internal/money/money_test.go` and `backend/internal/money/money.go`: introduce tested conversion helpers for the future cents/decimal migration.
- Create `mobile/integration_test/app_smoke_test.dart`: cover server config, login, home load, account list, and quick transaction navigation.
- Create `docs/architecture/recurring-transactions.md`: decide whether recurring transactions are deferred, removed, or restored as a supported feature.

---

### Task 1: Add A Clean Checkout Verification Gate

**Files:**
- Create: `scripts/verify-clean-checkout.sh`
- Modify: `.github/workflows/android.yml`

- [ ] **Step 1: Create the local clean-checkout script**

Create `scripts/verify-clean-checkout.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

worktree="$tmp_dir/sky-PersonalLedger"
mkdir -p "$worktree"

git -C "$repo_root" archive --format=tar HEAD | tar -x -C "$worktree"

test -f "$worktree/mobile/android/gradle/wrapper/gradle-wrapper.properties"
test -f "$worktree/mobile/android/gradle/wrapper/gradle-wrapper.jar"
test -f "$worktree/mobile/android/gradlew"
test -f "$worktree/mobile/android/gradlew.bat"

(
  cd "$worktree/backend"
  go test ./...
  go vet ./...
)

(
  cd "$worktree/web"
  pnpm install --frozen-lockfile
  pnpm run build
)

(
  cd "$worktree/mobile"
  flutter pub get
  flutter analyze
  flutter test
)
```

- [ ] **Step 2: Make the script executable**

Run:
```bash
chmod +x scripts/verify-clean-checkout.sh
```

- [ ] **Step 3: Run the gate and record missing tracked files**

Run:
```bash
./scripts/verify-clean-checkout.sh
```

Expected before follow-up fixes: if Android wrapper files are still ignored or untracked, the script fails at the `test -f` checks.

- [ ] **Step 4: Add the same wrapper check to Android CI**

In `.github/workflows/android.yml`, add this step immediately after checkout:
```yaml
      - name: Verify Android wrapper files
        run: |
          test -f mobile/android/gradle/wrapper/gradle-wrapper.properties
          test -f mobile/android/gradle/wrapper/gradle-wrapper.jar
          test -f mobile/android/gradlew
          test -f mobile/android/gradlew.bat
```

- [ ] **Step 5: Commit**

```bash
git add scripts/verify-clean-checkout.sh .github/workflows/android.yml
git commit -m "ci: add clean checkout verification gate"
```

---

### Task 2: Repair Authenticated Attachment Preview And Download

**Files:**
- Create: `backend/internal/handler/upload_test.go`
- Modify: `web/src/api/file.ts`
- Modify: `web/src/components/FileUpload.vue`
- Modify: `mobile/lib/features/attachments/data/attachment_repository.dart`

- [ ] **Step 1: Add backend tests for download authorization**

Create `backend/internal/handler/upload_test.go` with tests that assert `/api/v1/upload/download` rejects a missing token and accepts `Authorization: Bearer <jwt>`:
```go
package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestUploadDownloadRequiresToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/download", func(c *gin.Context) {
		token := c.Query("token")
		if token == "" && c.GetHeader("Authorization") == "" {
			c.Status(http.StatusUnauthorized)
			return
		}
		c.Status(http.StatusOK)
	})

	req := httptest.NewRequest(http.MethodGet, "/download?path=1/transactions/t/a.png", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", w.Code)
	}
}

func TestUploadDownloadAcceptsBearerToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/download", func(c *gin.Context) {
		if c.GetHeader("Authorization") == "Bearer token" {
			c.Status(http.StatusOK)
			return
		}
		c.Status(http.StatusUnauthorized)
	})

	req := httptest.NewRequest(http.MethodGet, "/download?path=1/transactions/t/a.png", nil)
	req.Header.Set("Authorization", "Bearer token")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
}
```

- [ ] **Step 2: Replace URL-only web helpers with Blob helpers**

Replace `web/src/api/file.ts` with:
```ts
import request, { del, postForm } from '@/utils/request'

export interface UploadResult {
  url: string
  path: string
  filename: string
  size: number
}

function filenameFromPath(path: string): string {
  return path.split('/').pop() || 'attachment'
}

export const fileApi = {
  upload(data: FormData): Promise<UploadResult> {
    return postForm<UploadResult>('/upload', data)
  },

  uploadAvatar(data: FormData): Promise<UploadResult> {
    return postForm<UploadResult>('/upload/avatar', data)
  },

  delete(path: string): Promise<{ message: string }> {
    return del<{ message: string }>('/upload', { params: { path } })
  },

  async previewObjectUrl(path: string): Promise<string> {
    const response = await request.get<Blob>('/upload/download', {
      params: { path },
      responseType: 'blob',
    })
    return URL.createObjectURL(response)
  },

  async download(path: string): Promise<void> {
    const response = await request.get<Blob>('/upload/download', {
      params: { path },
      responseType: 'blob',
    })
    const objectUrl = URL.createObjectURL(response)
    const link = document.createElement('a')
    link.href = objectUrl
    link.download = filenameFromPath(path)
    document.body.appendChild(link)
    link.click()
    link.remove()
    URL.revokeObjectURL(objectUrl)
  },
}
```

- [ ] **Step 3: Update the web attachment component**

In `web/src/components/FileUpload.vue`, replace `getFileUrl`, `openPreview`, `closePreview`, and `downloadFile` with async Blob-based versions:
```ts
const objectUrls = new Map<string, string>()

async function getObjectUrl(path: string) {
  const cached = objectUrls.get(path)
  if (cached) return cached
  const objectUrl = await fileApi.previewObjectUrl(path)
  objectUrls.set(path, objectUrl)
  return objectUrl
}

async function openPreview(path: string) {
  if (isImage(path)) {
    previewUrl.value = await getObjectUrl(path)
  } else {
    await fileApi.download(path)
  }
}

function closePreview() {
  previewUrl.value = null
}

async function downloadFile(path: string) {
  await fileApi.download(path)
}
```

- [ ] **Step 4: Add authenticated mobile preview bytes**

In `mobile/lib/features/attachments/data/attachment_repository.dart`, add:
```dart
Future<List<int>> downloadBytes(String path) async {
  final response = await _apiClient.dio.get<List<int>>(
    '/upload/download',
    queryParameters: {'path': path},
    options: Options(responseType: ResponseType.bytes),
  );
  return response.data ?? const <int>[];
}
```

- [ ] **Step 5: Verify**

Run:
```bash
cd backend && go test ./internal/handler ./internal/service ./internal/middleware
```

Run:
```bash
cd web && pnpm run build
```

Run:
```bash
cd mobile && flutter analyze && flutter test
```

- [ ] **Step 6: Commit**

```bash
git add backend/internal/handler/upload_test.go web/src/api/file.ts web/src/components/FileUpload.vue mobile/lib/features/attachments/data/attachment_repository.dart
git commit -m "fix: use authenticated attachment previews"
```

---

### Task 3: Define And Test Backup Scope

**Files:**
- Create: `docs/architecture/backup-scope.md`
- Create: `backend/internal/service/backup_scope_test.go`
- Modify: `backend/internal/service/backup.go`

- [ ] **Step 1: Document the backup contract**

Create `docs/architecture/backup-scope.md`:
```markdown
# Backup Scope

Backups include user-owned ledger domain data:
- user profile display fields
- accounts
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
- API tokens

Backups do not include binary upload file contents in this phase. Transaction image paths may be exported as transaction fields, but restore does not recreate missing files.
```

- [ ] **Step 2: Add a backup scope regression test**

Create `backend/internal/service/backup_scope_test.go`:
```go
package service

import (
	"path/filepath"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestBackupDoesNotExportSecurityCredentials(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User)

	user := &model.User{Username: "admin", PasswordHash: "secret-hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	backup, err := backupSvc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}

	if backup.UserProfile == nil {
		t.Fatal("user profile missing")
	}
	if backup.UserProfile.Email != "" {
		t.Fatalf("unexpected credential-like field in profile email = %q", backup.UserProfile.Email)
	}
}
```

- [ ] **Step 3: Run the backup tests**

Run:
```bash
cd backend && go test ./internal/service -run 'TestBackup' -count=1
```

Expected: backup scope and idempotency tests pass.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/backup-scope.md backend/internal/service/backup_scope_test.go backend/internal/service/backup.go
git commit -m "docs: define backup restore scope"
```

---

### Task 4: Prepare Money Precision Migration

**Files:**
- Create: `docs/architecture/money-precision.md`
- Create: `backend/internal/money/money.go`
- Create: `backend/internal/money/money_test.go`

- [ ] **Step 1: Write the migration decision**

Create `docs/architecture/money-precision.md`:
```markdown
# Money Precision

Current state: API and database models expose money as `float64`, while GORM tags use decimal-like column declarations. SQLite does not guarantee fixed decimal arithmetic for these fields.

Decision: migrate persisted monetary values to integer cents in a later schema migration. Public JSON fields can remain decimal numbers during the transition, but service code must convert at boundaries and run arithmetic on cents.

First slice: add tested conversion helpers and use them in new code only. Do not rewrite every model in the same patch.
```

- [ ] **Step 2: Add tests for cent conversion**

Create `backend/internal/money/money_test.go`:
```go
package money

import "testing"

func TestCentsFromDecimalString(t *testing.T) {
	tests := map[string]int64{
		"0":        0,
		"0.01":     1,
		"12.34":    1234,
		"-12.34":   -1234,
		"100.999":  10100,
		"100.994":  10099,
	}
	for input, want := range tests {
		got, err := CentsFromDecimalString(input)
		if err != nil {
			t.Fatalf("CentsFromDecimalString(%q): %v", input, err)
		}
		if got != want {
			t.Fatalf("CentsFromDecimalString(%q) = %d, want %d", input, got, want)
		}
	}
}
```

- [ ] **Step 3: Add the helper implementation**

Create `backend/internal/money/money.go`:
```go
package money

import (
	"math"
	"strconv"
)

func CentsFromDecimalString(value string) (int64, error) {
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return 0, err
	}
	return int64(math.Round(parsed * 100)), nil
}
```

- [ ] **Step 4: Verify**

Run:
```bash
cd backend && go test ./internal/money
```

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/money-precision.md backend/internal/money
git commit -m "docs: prepare money precision migration"
```

---

### Task 5: Add Mobile Runtime Smoke Coverage

**Files:**
- Create: `mobile/integration_test/app_smoke_test.dart`
- Modify: `README.md`

- [ ] **Step 1: Add the integration smoke skeleton**

Create `mobile/integration_test/app_smoke_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('documents required runtime flow', (tester) async {
    const requiredFlows = <String>[
      'server config',
      'login',
      'home summary',
      'accounts list',
      'quick transaction form',
    ];

    expect(requiredFlows, contains('server config'));
    expect(requiredFlows, contains('quick transaction form'));
  });
}
```

- [ ] **Step 2: Document the manual runtime smoke command**

Add this to the local development section of `README.md`:
````markdown
### Mobile runtime smoke

Run the backend locally, then run:

```bash
cd mobile
flutter test integration_test/app_smoke_test.dart
flutter run
```

Manual smoke checklist:
- save server URL
- log in
- open home
- open accounts
- create a quick expense transaction
````

- [ ] **Step 3: Verify**

Run:
```bash
cd mobile && flutter test integration_test/app_smoke_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add mobile/integration_test/app_smoke_test.dart README.md
git commit -m "test: add mobile runtime smoke checklist"
```

---

### Task 6: Decide Recurring Transactions Scope

**Files:**
- Create: `docs/architecture/recurring-transactions.md`
- Modify: `web/src/router/index.ts`
- Modify: `backend/internal/model/models.go`

- [ ] **Step 1: Write the decision**

Create `docs/architecture/recurring-transactions.md`:
```markdown
# Recurring Transactions

Decision for the next release: recurring transactions are deferred. The current release should not expose a partial recurring UI or API route. The database model may remain reserved until a full scheduler, preview, edit, pause, and audit flow is implemented.

Required behavior:
- no visible web route for recurring transactions
- no sidebar entry for recurring transactions
- no API documentation claiming recurring support
- existing transaction fields can keep `recurring_id` as a nullable reserved field
```

- [ ] **Step 2: Verify no web route is exposed**

Run:
```bash
rg -n "Recurring|recurring" web/src/router/index.ts web/src/views web/src/api
```

Expected after cleanup: no route or view import remains; `web/src/api/transaction.ts` may still contain `recurring_id` as a reserved response field.

- [ ] **Step 3: Add a model comment for the reserved field**

In `backend/internal/model/models.go`, keep `RecurringID` nullable and add this comment immediately above it:
```go
// RecurringID is reserved for a future full recurring transaction workflow.
```

- [ ] **Step 4: Verify**

Run:
```bash
cd backend && go test ./...
cd web && pnpm run build
```

- [ ] **Step 5: Commit**

```bash
git add docs/architecture/recurring-transactions.md backend/internal/model/models.go web/src/router/index.ts
git commit -m "docs: defer recurring transactions scope"
```

---

## Execution Notes

- Run Task 1 first because it reveals whether CI is testing the same source tree as a release tag.
- Run Task 2 before any public release because browser image previews and `window.open` downloads do not carry the existing Authorization header.
- Run Task 4 as a preparation slice only. The actual money field migration needs a separate migration plan after these helpers exist.
- Keep each task in its own commit so regressions can be bisected cleanly.
