package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestCreateBackupMapsOversizedBackupToRequestEntityTooLarge(t *testing.T) {
	handler, _, userID := newCreateBackupHandlerForTest(t, strings.Repeat("x", 2048), 512)

	response := performCreateBackupRequest(handler, userID)

	assertBackupCreateError(t, response, http.StatusRequestEntityTooLarge, 41300, backupUploadTooLargeMessage)
}

func TestCreateBackupKeepsUnexpectedErrorsAsInternalServerError(t *testing.T) {
	handler, repos, userID := newCreateBackupHandlerForTest(t, "", 0)
	sqlDB, err := repos.Account.DB().DB()
	if err != nil {
		t.Fatalf("get sql db: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql db: %v", err)
	}

	response := performCreateBackupRequest(handler, userID)

	assertBackupCreateError(t, response, http.StatusInternalServerError, 50001, "failed to create backup")
}

func newCreateBackupHandlerForTest(t *testing.T, bio string, maxRestoreBytes int64) (*BackupHandler, *repository.Repositories, uint) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "backup-create", PasswordHash: "hash", Bio: bio}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	backupService := service.NewBackupService(
		db,
		repos.Account,
		repos.Category,
		repos.Transaction,
		repos.Budget,
		repos.Reminder,
		repos.Lending,
		repos.Template,
		repos.Notification,
		repos.Tag,
		repos.User,
		repos.FamilyMember,
		repos.AIReport,
		maxRestoreBytes,
	)
	return NewBackupHandler(backupService, nil), repos, user.ID
}

func performCreateBackupRequest(handler *BackupHandler, userID uint) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/backup", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Create(c)
	})
	request := httptest.NewRequest(http.MethodGet, "/backup", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func assertBackupCreateError(t *testing.T, recorder *httptest.ResponseRecorder, wantStatus, wantCode int, wantMessage string) {
	t.Helper()
	if recorder.Code != wantStatus {
		t.Fatalf("status = %d, want %d; body=%s", recorder.Code, wantStatus, recorder.Body.String())
	}
	var body struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(recorder.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode response body: %v; body=%s", err, recorder.Body.String())
	}
	if body.Code != wantCode || body.Message != wantMessage {
		t.Fatalf("response = %#v, want code=%d message=%q", body, wantCode, wantMessage)
	}
}
