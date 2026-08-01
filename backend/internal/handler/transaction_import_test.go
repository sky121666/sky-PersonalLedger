package handler

import (
	"bytes"
	"encoding/json"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

type transactionImportHandlerFixture struct {
	handler  *TransactionImportHandler
	repos    *repository.Repositories
	userID   uint
	account  *model.Account
	category *model.Category
}

func TestTransactionImportPreviewRejectsMissingInvalidAndOversizedFiles(t *testing.T) {
	fixture := newTransactionImportHandlerFixture(t)

	missing := performTransactionImportPreviewRequest(fixture.handler, fixture.userID, "", nil)
	if missing.Code != http.StatusBadRequest {
		t.Fatalf("missing file status = %d, want 400; body=%s", missing.Code, missing.Body.String())
	}

	invalid := performTransactionImportPreviewRequest(fixture.handler, fixture.userID, "transactions.txt", []byte("not an import"))
	if invalid.Code != http.StatusUnprocessableEntity || !strings.Contains(invalid.Body.String(), `"code":42210`) {
		t.Fatalf("invalid file response = %d %s, want 42210", invalid.Code, invalid.Body.String())
	}

	oversized := performTransactionImportPreviewRequest(
		fixture.handler,
		fixture.userID,
		"transactions.csv",
		bytes.Repeat([]byte("x"), int(service.MaxTransactionImportFileBytes())+1),
	)
	if oversized.Code != http.StatusRequestEntityTooLarge || !strings.Contains(oversized.Body.String(), `"code":41301`) {
		t.Fatalf("oversized file response = %d %s, want 41301", oversized.Code, oversized.Body.String())
	}
}

func TestTransactionImportCommitReturnsRowErrorsAndSingleUseConflict(t *testing.T) {
	fixture := newTransactionImportHandlerFixture(t)
	invalidPayload := []byte(`[{"type":"expense","amount":10,"account_id":"missing","transaction_date":"2026-06-15"}]`)
	invalidPreview := performTransactionImportPreviewRequest(fixture.handler, fixture.userID, "transactions.json", invalidPayload)
	invalidID := transactionImportIDFromResponse(t, invalidPreview)
	invalidCommit := performTransactionImportActionRequest(fixture.handler, fixture.userID, invalidID, "commit")
	if invalidCommit.Code != http.StatusUnprocessableEntity || !strings.Contains(invalidCommit.Body.String(), `"code":42212`) {
		t.Fatalf("invalid commit response = %d %s, want 42212", invalidCommit.Code, invalidCommit.Body.String())
	}
	if !strings.Contains(invalidCommit.Body.String(), "账户不存在或不属于当前用户") {
		t.Fatalf("invalid commit omitted row diagnostics: %s", invalidCommit.Body.String())
	}

	validPayload := []byte(`[{"type":"expense","amount":10,"account_id":"` + fixture.account.ID + `","category_id":"` + fixture.category.ID + `","transaction_date":"2026-06-15"}]`)
	validPreview := performTransactionImportPreviewRequest(fixture.handler, fixture.userID, "transactions.json", validPayload)
	validID := transactionImportIDFromResponse(t, validPreview)
	committed := performTransactionImportActionRequest(fixture.handler, fixture.userID, validID, "commit")
	if committed.Code != http.StatusOK {
		t.Fatalf("commit response = %d %s, want 200", committed.Code, committed.Body.String())
	}
	repeated := performTransactionImportActionRequest(fixture.handler, fixture.userID, validID, "commit")
	if repeated.Code != http.StatusConflict || !strings.Contains(repeated.Body.String(), `"code":40902`) {
		t.Fatalf("repeated commit response = %d %s, want 40902", repeated.Code, repeated.Body.String())
	}
}

func newTransactionImportHandlerFixture(t *testing.T) transactionImportHandlerFixture {
	t.Helper()
	transactionHandler, repos, userID := newTransactionHandlerForTest(t)
	accountID := createTransactionHandlerAccount(t, repos, userID)
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("load account: %v", err)
	}
	category := &model.Category{
		ID: uuid.NewString(), UserID: userID, Name: "餐饮", Type: "expense",
	}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	return transactionImportHandlerFixture{
		handler: NewTransactionImportHandler(service.NewTransactionImportService(transactionHandler.service)),
		repos:   repos, userID: userID, account: account, category: category,
	}
}

func performTransactionImportPreviewRequest(
	handler *TransactionImportHandler,
	userID uint,
	filename string,
	content []byte,
) *httptest.ResponseRecorder {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	if filename != "" {
		part, err := writer.CreateFormFile("file", filename)
		if err != nil {
			panic(err)
		}
		if _, err := part.Write(content); err != nil {
			panic(err)
		}
	}
	if err := writer.Close(); err != nil {
		panic(err)
	}

	router := gin.New()
	router.POST("/imports/transactions/preview", func(c *gin.Context) {
		c.Set("userID", userID)
		handler.Preview(c)
	})
	request := httptest.NewRequest(http.MethodPost, "/imports/transactions/preview", body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func performTransactionImportActionRequest(
	handler *TransactionImportHandler,
	userID uint,
	id string,
	action string,
) *httptest.ResponseRecorder {
	router := gin.New()
	path := "/imports/transactions/:id/" + action
	router.POST(path, func(c *gin.Context) {
		c.Set("userID", userID)
		switch action {
		case "commit":
			handler.Commit(c)
		case "validate":
			handler.Validate(c)
		case "rollback":
			handler.Rollback(c)
		}
	})
	request := httptest.NewRequest(http.MethodPost, "/imports/transactions/"+id+"/"+action, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func transactionImportIDFromResponse(t *testing.T, response *httptest.ResponseRecorder) string {
	t.Helper()
	if response.Code != http.StatusOK {
		t.Fatalf("preview response = %d %s, want 200", response.Code, response.Body.String())
	}
	var envelope struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &envelope); err != nil {
		t.Fatalf("decode preview response: %v", err)
	}
	if envelope.Data.ID == "" {
		t.Fatalf("preview response omitted id: %s", response.Body.String())
	}
	return envelope.Data.ID
}
