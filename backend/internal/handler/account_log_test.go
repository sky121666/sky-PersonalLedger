package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

func TestAccountLogHandlerUsesAuthenticatedUserForList(t *testing.T) {
	handler, owner, _, ownerAccount, _ := newAccountLogHandlerTestFixture(t)
	userID := owner.ID

	recorder := performAccountLogHandlerRequest(handler, &userID, "/account-logs")
	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200; body=%s", recorder.Code, recorder.Body.String())
	}

	var got accountLogHandlerResponse
	if err := json.Unmarshal(recorder.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if got.Code != 0 || got.Data.Total != 1 || len(got.Data.List) != 1 {
		t.Fatalf("response = %#v, want one owner log", got)
	}
	if got.Data.List[0].UserID != owner.ID || got.Data.List[0].AccountID != ownerAccount.ID {
		t.Fatalf("returned log = %#v, want owner account log", got.Data.List[0])
	}
}

func TestAccountLogHandlerAccountAccessDoesNotRevealForeignAccount(t *testing.T) {
	handler, owner, _, ownerAccount, otherAccount := newAccountLogHandlerTestFixture(t)
	userID := owner.ID

	allowed := performAccountLogHandlerRequest(handler, &userID, "/account-logs/account/"+ownerAccount.ID)
	if allowed.Code != http.StatusOK {
		t.Fatalf("owner status = %d, want 200; body=%s", allowed.Code, allowed.Body.String())
	}

	foreign := performAccountLogHandlerRequest(handler, &userID, "/account-logs/account/"+otherAccount.ID)
	missing := performAccountLogHandlerRequest(handler, &userID, "/account-logs/account/"+uuid.NewString())
	if foreign.Code != http.StatusNotFound || missing.Code != http.StatusNotFound {
		t.Fatalf("foreign status = %d, missing status = %d; want both 404", foreign.Code, missing.Code)
	}
	if foreign.Body.String() != missing.Body.String() {
		t.Fatalf("foreign body = %s, missing body = %s; want identical responses", foreign.Body.String(), missing.Body.String())
	}

	var got response.Response
	if err := json.Unmarshal(foreign.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode foreign response: %v", err)
	}
	if got.Code != 40401 || got.Message != "account not found" {
		t.Fatalf("foreign response = %#v, want generic account not found", got)
	}
}

func TestAccountLogHandlerRequiresIdentity(t *testing.T) {
	handler, _, _, ownerAccount, _ := newAccountLogHandlerTestFixture(t)
	paths := []string{
		"/account-logs",
		"/account-logs/account/" + ownerAccount.ID,
	}
	for _, path := range paths {
		t.Run(path, func(t *testing.T) {
			recorder := performAccountLogHandlerRequest(handler, nil, path)
			if recorder.Code != http.StatusUnauthorized {
				t.Fatalf("status = %d, want 401; body=%s", recorder.Code, recorder.Body.String())
			}
		})
	}
}

type accountLogHandlerResponse struct {
	Code int `json:"code"`
	Data struct {
		List  []model.AccountLog `json:"list"`
		Total int64              `json:"total"`
	} `json:"data"`
}

func newAccountLogHandlerTestFixture(t *testing.T) (*AccountLogHandler, *model.User, *model.User, *model.Account, *model.Account) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	owner := &model.User{Username: "account-log-owner", PasswordHash: "hash"}
	other := &model.User{Username: "account-log-other", PasswordHash: "hash"}
	if err := repos.User.Create(owner); err != nil {
		t.Fatalf("create owner: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	ownerAccount := createAccountLogHandlerTestAccount(t, repos, owner.ID)
	otherAccount := createAccountLogHandlerTestAccount(t, repos, other.ID)
	createAccountLogHandlerTestLog(t, repos, owner.ID, ownerAccount.ID)
	createAccountLogHandlerTestLog(t, repos, other.ID, otherAccount.ID)

	accountLogService := service.NewAccountLogService(repos.AccountLog, repos.Account)
	return NewAccountLogHandler(accountLogService), owner, other, ownerAccount, otherAccount
}

func createAccountLogHandlerTestAccount(t *testing.T, repos *repository.Repositories, userID uint) *model.Account {
	t.Helper()
	account := &model.Account{
		ID:             uuid.NewString(),
		UserID:         userID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: 100,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return account
}

func createAccountLogHandlerTestLog(t *testing.T, repos *repository.Repositories, userID uint, accountID string) {
	t.Helper()
	if err := repos.AccountLog.Create(&repository.CreateAccountLogRequest{
		UserID:        userID,
		AccountID:     accountID,
		Type:          "income",
		Amount:        25,
		BalanceBefore: 100,
		BalanceAfter:  125,
	}); err != nil {
		t.Fatalf("create account log: %v", err)
	}
}

func performAccountLogHandlerRequest(handler *AccountLogHandler, userID *uint, path string) *httptest.ResponseRecorder {
	router := gin.New()
	router.GET("/account-logs", func(c *gin.Context) {
		if userID != nil {
			c.Set("userID", *userID)
		}
		handler.GetAll(c)
	})
	router.GET("/account-logs/account/:id", func(c *gin.Context) {
		if userID != nil {
			c.Set("userID", *userID)
		}
		handler.GetByAccountID(c)
	})

	request := httptest.NewRequest(http.MethodGet, path, nil)
	recorder := httptest.NewRecorder()
	router.ServeHTTP(recorder, request)
	return recorder
}
