# Personal Ledger Stabilization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the current Personal Ledger repo so backend data integrity, backup restore, mobile source tracking, and documentation are safe enough for the next release.

**Architecture:** Keep the existing Go/Gin/GORM, Vue, and Flutter structure. Fix the highest-risk defects in place: preserve ignored source files, make restore idempotent with GORM soft deletes, wrap balance-changing transaction writes in a database transaction, normalize CORS behavior, and align docs with the native Flutter client. Do not migrate money fields away from `float64` in this pass; record it as a follow-up because it is a schema/API migration.

**Tech Stack:** Go 1.24, Gin, GORM, SQLite, Vue 3, Vite, TypeScript, Flutter, Riverpod, Dio, GoRouter.

---

## File Structure

- Modify `.gitignore`: narrow the root data ignore rule so `mobile/lib/**/data/*.dart` is no longer ignored.
- Modify `backend/internal/service/backup.go`: use transaction-scoped hard deletes during restore and include account logs in clear order.
- Create `backend/internal/service/backup_test.go`: verify restoring the same backup twice succeeds and does not duplicate active rows.
- Modify `backend/internal/service/transaction.go`: validate account ownership and run create/update/delete balance mutations atomically.
- Modify `backend/internal/repository/transaction.go`: expose the underlying DB for service transactions.
- Modify `backend/internal/repository/account_log.go`: add `CreateWithDB` and make the existing `Create` delegate to it.
- Create `backend/internal/service/transaction_test.go`: cover rollback on missing transfer target and transfer update validation.
- Modify `backend/internal/middleware/middleware.go`: make CORS accept a single config string, trim comma-separated origins, and treat empty as same-origin/originless only.
- Create `backend/internal/middleware/middleware_test.go`: cover empty, wildcard, exact origin, and rejected origin behavior.
- Modify `backend/cmd/server/main.go`: call the updated CORS middleware signature.
- Modify `config.example.yaml`, `docker-compose.yml`, `README.md`: document CORS and current mobile architecture accurately.

---

### Task 1: Fix Ignored Mobile Data Layer Files

**Files:**
- Modify: `.gitignore:26-33`

- [ ] **Step 1: Verify current failure**

Run:
```bash
git check-ignore -v mobile/lib/features/auth/data/auth_repository.dart
```

Expected before the fix: output includes `.gitignore:32:data/`.

- [ ] **Step 2: Update ignore rules**

Change:
```gitignore
data/
backend/data/
```

To:
```gitignore
/data/
/backend/data/
```

- [ ] **Step 3: Verify mobile data source is no longer ignored**

Run:
```bash
git check-ignore -v mobile/lib/features/auth/data/auth_repository.dart; test $? -eq 1
git check-ignore -v mobile/lib/features/transactions/data/transaction_models.dart; test $? -eq 1
```

Expected: both commands exit successfully through `test $? -eq 1`, with no ignore-rule output.

- [ ] **Step 4: Verify root data is still ignored**

Run:
```bash
git check-ignore -v data/ledger.db
git check-ignore -v backend/data/ledger.db
```

Expected: both paths are still ignored by `.gitignore`.

- [ ] **Step 5: Commit**

```bash
git add .gitignore
git commit -m "fix: track flutter data layer sources"
```

---

### Task 2: Make Backup Restore Idempotent With Soft Deletes

**Files:**
- Modify: `backend/internal/service/backup.go:177-314`
- Create: `backend/internal/service/backup_test.go`

- [ ] **Step 1: Add failing restore idempotency test**

Create `backend/internal/service/backup_test.go`:
```go
package service

import (
	"bytes"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestRestoreBackupCanRunTwiceWithSameIDs(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ledger.db")
	db, err := database.Init(dbPath)
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget, repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User)

	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}

	accountID := uuid.NewString()
	categoryID := uuid.NewString()
	txID := uuid.NewString()
	if err := db.Create(&model.Account{ID: accountID, UserID: user.ID, Name: "Cash", Type: "cash"}).Error; err != nil {
		t.Fatalf("create account: %v", err)
	}
	if err := db.Create(&model.Category{ID: categoryID, UserID: user.ID, Name: "Food", Type: "expense"}).Error; err != nil {
		t.Fatalf("create category: %v", err)
	}
	if err := db.Create(&model.Transaction{
		ID: txID, UserID: user.ID, AccountID: accountID, CategoryID: &categoryID,
		Type: "expense", Amount: 12.5, TransactionDate: time.Now(),
	}).Error; err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	backup, err := backupSvc.CreateBackup(user.ID)
	if err != nil {
		t.Fatalf("create backup: %v", err)
	}
	file := writeBackupFile(t, backup)

	if err := backupSvc.RestoreBackup(user.ID, file); err != nil {
		t.Fatalf("first restore: %v", err)
	}
	if err := backupSvc.RestoreBackup(user.ID, file); err != nil {
		t.Fatalf("second restore should not conflict with soft-deleted IDs: %v", err)
	}

	var accountCount int64
	if err := db.Model(&model.Account{}).Where("user_id = ?", user.ID).Count(&accountCount).Error; err != nil {
		t.Fatalf("count accounts: %v", err)
	}
	if accountCount != 1 {
		t.Fatalf("active account count = %d, want 1", accountCount)
	}
}

func writeBackupFile(t *testing.T, backup *FullBackupData) *multipart.FileHeader {
	t.Helper()
	path := filepath.Join(t.TempDir(), "backup.json")
	data, err := json.Marshal(backup)
	if err != nil {
		t.Fatalf("marshal backup: %v", err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatalf("write backup: %v", err)
	}
	return mustFileHeader(t, path)
}

func mustFileHeader(t *testing.T, path string) *multipart.FileHeader {
	t.Helper()
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	part, err := writer.CreateFormFile("file", filepath.Base(path))
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	src, err := os.Open(path)
	if err != nil {
		t.Fatalf("open backup: %v", err)
	}
	defer src.Close()
	if _, err := io.Copy(part, src); err != nil {
		t.Fatalf("copy backup: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}
	request, err := http.NewRequest("POST", "/restore", body)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	request.Header.Set("Content-Type", writer.FormDataContentType())
	if err := request.ParseMultipartForm(32 << 20); err != nil {
		t.Fatalf("parse multipart: %v", err)
	}
	return request.MultipartForm.File["file"][0]
}
```

- [ ] **Step 2: Run test and verify it fails**

Run:
```bash
go test ./internal/service -run TestRestoreBackupCanRunTwiceWithSameIDs -count=1
```

Expected before implementation: failure on second restore with a unique constraint or duplicate primary key error.

- [ ] **Step 3: Implement hard clear inside restore transaction**

In `clearUserDataTx`, use `Unscoped()` for models with `gorm.DeletedAt`, and include account logs:
```go
func (s *BackupService) clearUserDataTx(tx *gorm.DB, userID uint) error {
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.AccountLog{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Transaction{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Budget{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.LendingRecord{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Lending{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Reminder{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.QuickTemplate{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Tag{}).Error; err != nil {
		return err
	}
	if err := tx.Where("user_id = ?", userID).Delete(&model.NotificationSetting{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Category{}).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("user_id = ?", userID).Delete(&model.Account{}).Error; err != nil {
		return err
	}
	return nil
}
```

- [ ] **Step 4: Run backup tests**

Run:
```bash
go test ./internal/service -run TestRestoreBackupCanRunTwiceWithSameIDs -count=1
go test ./...
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/service/backup.go backend/internal/service/backup_test.go
git commit -m "fix: make backup restore idempotent"
```

---

### Task 3: Make Transaction Balance Mutations Atomic

**Files:**
- Modify: `backend/internal/service/transaction.go`
- Modify: `backend/internal/repository/transaction.go`
- Modify: `backend/internal/repository/account_log.go`
- Create: `backend/internal/service/transaction_test.go`

- [ ] **Step 1: Add failing tests for missing transfer target and nil transfer target**

Create `backend/internal/service/transaction_test.go` with focused tests:
```go
package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func newTransactionTestService(t *testing.T) (*TransactionService, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	return NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, accountLogSvc), repos, user.ID
}

func createAccountForTest(t *testing.T, repos *repository.Repositories, userID uint, balance float64) string {
	t.Helper()
	id := uuid.NewString()
	if err := repos.Account.Create(&model.Account{ID: id, UserID: userID, Name: "Wallet", Type: "cash", CurrentBalance: balance}); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return id
}

func TestCreateTransferRollsBackWhenTargetAccountDoesNotExist(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	sourceID := createAccountForTest(t, repos, userID, 100)
	missingTargetID := uuid.NewString()

	_, err := svc.Create(userID, CreateTransactionRequest{
		Type: "transfer", Amount: 30, AccountID: sourceID, ToAccountID: &missingTargetID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err == nil {
		t.Fatal("expected error for missing transfer target")
	}

	source, err := repos.Account.GetByID(sourceID)
	if err != nil {
		t.Fatalf("get source: %v", err)
	}
	if source.CurrentBalance != 100 {
		t.Fatalf("source balance = %v, want 100", source.CurrentBalance)
	}

	list, total, err := repos.Transaction.List(repository.TransactionFilter{UserID: userID, Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(list) != 0 {
		t.Fatalf("transaction was persisted despite failed transfer: total=%d len=%d", total, len(list))
	}
}

func TestUpdateRejectsTransferWithoutTargetAccount(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	tx, err := svc.Create(userID, CreateTransactionRequest{
		Type: "expense", Amount: 10, AccountID: accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create expense: %v", err)
	}

	if _, err := svc.Update(tx.ID, userID, CreateTransactionRequest{
		Type: "transfer", Amount: 10, AccountID: accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	}); err == nil {
		t.Fatal("expected transfer update without target to fail")
	}
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:
```bash
go test ./internal/service -run 'Test(CreateTransferRollsBackWhenTargetAccountDoesNotExist|UpdateRejectsTransferWithoutTargetAccount)' -count=1
```

Expected before implementation: at least one test fails because balance changes are not rolled back or update panics.

- [ ] **Step 3: Expose DB from transaction repository**

Add to `backend/internal/repository/transaction.go`:
```go
func (r *TransactionRepository) DB() *gorm.DB {
	return r.db
}
```

- [ ] **Step 4: Add transaction-aware account log insert**

Add to `backend/internal/repository/account_log.go`:
```go
func (r *AccountLogRepository) CreateWithDB(db *gorm.DB, req *CreateAccountLogRequest) error {
	log := &model.AccountLog{
		ID:            uuid.New().String(),
		UserID:        req.UserID,
		AccountID:     req.AccountID,
		Type:          req.Type,
		Amount:        req.Amount,
		BalanceBefore: req.BalanceBefore,
		BalanceAfter:  req.BalanceAfter,
		TransactionID: req.TransactionID,
		ReminderID:    req.ReminderID,
		LendingID:     req.LendingID,
		Remark:        req.Remark,
		CreatedAt:     time.Now(),
	}
	return db.Create(log).Error
}
```

Then change `Create` to call `CreateWithDB(r.db, req)`.

- [ ] **Step 5: Implement validation and DB transaction in TransactionService**

In `backend/internal/service/transaction.go`, add helpers:
```go
func (s *TransactionService) validateTransactionAccounts(userID uint, req CreateTransactionRequest) error {
	if req.Type == "transfer" {
		if req.ToAccountID == nil || *req.ToAccountID == "" || *req.ToAccountID == req.AccountID {
			return ErrSameAccount
		}
	}
	if err := s.ensureAccountBelongsToUser(req.AccountID, userID); err != nil {
		return err
	}
	if req.Type == "transfer" {
		return s.ensureAccountBelongsToUser(*req.ToAccountID, userID)
	}
	return nil
}

func (s *TransactionService) ensureAccountBelongsToUser(accountID string, userID uint) error {
	account, err := s.accountRepo.GetByID(accountID)
	if err != nil || account.UserID != userID {
		return ErrAccountNotFound
	}
	return nil
}

func parseTransactionDate(value string) (time.Time, error) {
	txDate, err := time.Parse(time.RFC3339, value)
	if err == nil {
		return txDate, nil
	}
	return time.Parse("2006-01-02", value)
}
```

Then wrap `Create` and `Update` in `s.txRepo.DB().Transaction(...)`, and in every balance update use:
```go
result := txdb.Model(&model.Account{}).Where("id = ? AND user_id = ?", accountID, userID).
	Update("current_balance", gorm.Expr("current_balance + ?", delta))
if result.Error != nil {
	return result.Error
}
if result.RowsAffected != 1 {
	return ErrAccountNotFound
}
```

Log account balance changes inside the same `txdb` after reading the account row with `txdb.First(&account, "id = ? AND user_id = ?", accountID, userID)`.

- [ ] **Step 6: Run transaction tests**

Run:
```bash
go test ./internal/service -run 'Test(CreateTransferRollsBackWhenTargetAccountDoesNotExist|UpdateRejectsTransferWithoutTargetAccount)' -count=1
go test ./...
```

Expected: both pass.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/service/transaction.go backend/internal/service/transaction_test.go backend/internal/repository/transaction.go backend/internal/repository/account_log.go
git commit -m "fix: make transaction balance updates atomic"
```

---

### Task 4: Normalize CORS Behavior

**Files:**
- Modify: `backend/internal/middleware/middleware.go:17-55`
- Modify: `backend/cmd/server/main.go:95`
- Create: `backend/internal/middleware/middleware_test.go`

- [ ] **Step 1: Add CORS tests**

Create `backend/internal/middleware/middleware_test.go`:
```go
package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func performCORSRequest(allowedOrigins string, origin string) *httptest.ResponseRecorder {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(CORS(allowedOrigins))
	r.GET("/ping", func(c *gin.Context) { c.String(http.StatusOK, "pong") })

	req := httptest.NewRequest(http.MethodGet, "/ping", nil)
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestCORSEmptyConfigAllowsOriginlessRequestOnly(t *testing.T) {
	if status := performCORSRequest("", "").Code; status != http.StatusOK {
		t.Fatalf("originless status = %d, want 200", status)
	}
	if status := performCORSRequest("", "http://localhost:5173").Code; status != http.StatusForbidden {
		t.Fatalf("browser origin status = %d, want 403", status)
	}
}

func TestCORSWildcardAllowsAnyOrigin(t *testing.T) {
	w := performCORSRequest("*", "http://localhost:5173")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "*" {
		t.Fatalf("allow origin = %q, want *", got)
	}
}

func TestCORSExactOriginList(t *testing.T) {
	allowed := "http://localhost:5173, https://ledger.example.com"
	w := performCORSRequest(allowed, "https://ledger.example.com")
	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "https://ledger.example.com" {
		t.Fatalf("allow origin = %q", got)
	}
	if status := performCORSRequest(allowed, "https://evil.example.com").Code; status != http.StatusForbidden {
		t.Fatalf("rejected origin status = %d, want 403", status)
	}
}
```

- [ ] **Step 2: Implement single-string CORS parser**

Replace the CORS signature with:
```go
func CORS(allowedOrigins string) gin.HandlerFunc {
	origins := parseAllowedOrigins(allowedOrigins)
	allowAll := len(origins) == 1 && origins[0] == "*"
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin == "" {
			setCORSCommonHeaders(c)
			c.Next()
			return
		}
		if allowAll {
			c.Header("Access-Control-Allow-Origin", "*")
			setCORSCommonHeaders(c)
			if c.Request.Method == http.MethodOptions {
				c.AbortWithStatus(http.StatusNoContent)
				return
			}
			c.Next()
			return
		}
		for _, allowed := range origins {
			if allowed == origin {
				c.Header("Access-Control-Allow-Origin", origin)
				setCORSCommonHeaders(c)
				if c.Request.Method == http.MethodOptions {
					c.AbortWithStatus(http.StatusNoContent)
					return
				}
				c.Next()
				return
			}
		}
		c.AbortWithStatus(http.StatusForbidden)
	}
}
```

Add helpers:
```go
func parseAllowedOrigins(value string) []string {
	parts := strings.Split(value, ",")
	origins := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			origins = append(origins, part)
		}
	}
	return origins
}

func setCORSCommonHeaders(c *gin.Context) {
	c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
	c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Accept, Authorization")
	c.Header("Access-Control-Allow-Credentials", "true")
	c.Header("Access-Control-Max-Age", "86400")
}
```

- [ ] **Step 3: Update main.go call site**

Change:
```go
r.Use(middleware.CORS(cfg.CORS.AllowedOrigins))
```

Keep the same call if the signature is `CORS(string)`.

- [ ] **Step 4: Run middleware tests**

Run:
```bash
go test ./internal/middleware -run TestCORS -count=1
go test ./...
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/middleware/middleware.go backend/internal/middleware/middleware_test.go backend/cmd/server/main.go
git commit -m "fix: normalize cors origin handling"
```

---

### Task 5: Align Documentation With Current Mobile Architecture

**Files:**
- Modify: `README.md:99-109`
- Modify: `config.example.yaml`
- Modify: `docker-compose.yml`

- [ ] **Step 1: Update README mobile description**

Replace the client note with:
```markdown
> 📦 **客户端说明**: 当前客户端正在从 Flutter WebView 壳演进为原生 Flutter 应用。核心流程已使用原生页面和 API Client；低频或未迁移功能保留 Legacy WebView 兜底入口。
```

Update the platform table wording:
```markdown
| 🤖 Android | `personal-ledger-xxx-android.apk` | 原生 Flutter 客户端，保留 WebView 兜底 | ✅ 基础测试通过 |
| 🍎 macOS | `personal-ledger-xxx-macos.zip` | 原生 Flutter 客户端，首次需在安全设置中允许 | ✅ 基础测试通过 |
| 🪟 Windows | `personal-ledger-xxx-windows.zip` | 原生 Flutter 客户端，部分低频功能可能通过 WebView 打开 | ⏳ 待完整回归 |
```

- [ ] **Step 2: Document CORS env var**

In `config.example.yaml`, add under `cors` if missing:
```yaml
cors:
  allowed_origins: "" # 留空仅允许同源/无 Origin 请求；开发前端可设为 http://localhost:5173；多个用逗号分隔
```

In `docker-compose.yml`, add a commented env example:
```yaml
# - LEDGER_CORS_ALLOWED_ORIGINS=https://ledger.example.com
```

- [ ] **Step 3: Verify docs do not mention WebView-only client**

Run:
```bash
rg -n "WebView 封装|无需单独开发原生 UI|WebView2" README.md config.example.yaml docker-compose.yml
```

Expected: no stale WebView-only claim remains. `WebView2` may remain only if Windows packaging truly requires it; if native Flutter Windows no longer requires WebView2 for the main shell, remove it from the table.

- [ ] **Step 4: Commit**

```bash
git add README.md config.example.yaml docker-compose.yml
git commit -m "docs: align deployment and client architecture notes"
```

---

### Task 6: Final Verification Gate

**Files:**
- Verify full repo state only.

- [ ] **Step 1: Run backend checks**

```bash
cd backend
go test ./...
go vet ./...
```

Expected: pass.

- [ ] **Step 2: Run web build**

```bash
cd web
npm run build
```

Expected: pass.

- [ ] **Step 3: Run Flutter checks**

```bash
cd mobile
flutter analyze
flutter test
```

Expected: pass.

- [ ] **Step 4: Verify intended untracked files are visible**

Run:
```bash
git status --short
```

Expected: `mobile/lib/**/data/*.dart`, `mobile/test/*.dart`, `mobile/ios/**`, `web/src/api/backup.ts`, and `web/src/api/file.ts` are visible for staging if they are part of the current mobile/native work. Ignored generated folders such as `web/dist`, `web/node_modules`, `mobile/build`, `mobile/.dart_tool`, and `mobile/macos/Pods` remain ignored.

- [ ] **Step 5: Create final stabilization commit**

If previous tasks were not committed separately, commit all stabilization changes:
```bash
git add .gitignore README.md config.example.yaml docker-compose.yml backend/internal mobile/lib mobile/test web/src
git status --short
git commit -m "fix: stabilize ledger data integrity and release docs"
```

---

## Deferred Follow-Up

- Money precision migration: replace `float64` money fields with integer cents or a decimal type. This needs API compatibility review, database migration, import/export migration, and frontend/mobile formatter changes, so it should be a separate plan after stabilization.
- Recurring transaction feature decision: the model still exists but the Web recurring API/view files were empty and deleted. Decide whether to fully remove the schema field or implement the feature later.
- Android wrapper tracking: review whether `mobile/android/gradlew`, `gradlew.bat`, and `gradle-wrapper.jar` should remain ignored for this Flutter project. Do this only after confirming CI builds from a clean checkout.

## Self-Review

- Spec coverage: covers ignored source files, backup restore, transaction atomicity, CORS mismatch, docs mismatch, and final verification.
- Placeholder scan: no placeholder wording is used for required tasks. Deferred items are explicitly out of this stabilization scope.
- Type consistency: task snippets use existing `CreateTransactionRequest`, `FullBackupData`, `repository.NewRepositories`, and model names from the current codebase.
