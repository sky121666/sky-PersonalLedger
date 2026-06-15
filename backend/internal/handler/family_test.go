package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestFamilyMemberHandlerCreateListUpdateDelete(t *testing.T) {
	handler, userID := newFamilyMemberTestHandler(t)

	createResponse := performFamilyMemberRequest(handler, userID, http.MethodPost, "/family/members", map[string]any{
		"name":         "我",
		"relationship": "self",
		"color":        "#0F766E",
	})
	if createResponse.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", createResponse.Code, createResponse.Body.String())
	}
	created := decodeFamilyMemberResponse(t, createResponse.Body.Bytes())
	memberID := created["id"].(string)
	if memberID == "" {
		t.Fatal("created member id should not be empty")
	}

	listResponse := performFamilyMemberRequest(handler, userID, http.MethodGet, "/family/members", nil)
	if listResponse.Code != http.StatusOK {
		t.Fatalf("list status = %d, body = %s", listResponse.Code, listResponse.Body.String())
	}
	list := decodeFamilyMemberListResponse(t, listResponse.Body.Bytes())
	if len(list) != 1 || list[0]["name"] != "我" {
		t.Fatalf("list = %#v, want created member", list)
	}

	updateResponse := performFamilyMemberRequest(handler, userID, http.MethodPut, "/family/members/"+memberID, map[string]any{
		"name":         "本人",
		"relationship": "self",
		"color":        "#2563EB",
		"is_default":   true,
		"is_enabled":   true,
	})
	if updateResponse.Code != http.StatusOK {
		t.Fatalf("update status = %d, body = %s", updateResponse.Code, updateResponse.Body.String())
	}
	updated := decodeFamilyMemberResponse(t, updateResponse.Body.Bytes())
	if updated["name"] != "本人" {
		t.Fatalf("updated name = %v, want 本人", updated["name"])
	}

	deleteResponse := performFamilyMemberRequest(handler, userID, http.MethodDelete, "/family/members/"+memberID, nil)
	if deleteResponse.Code != http.StatusOK {
		t.Fatalf("delete status = %d, body = %s", deleteResponse.Code, deleteResponse.Body.String())
	}

	listAfterDelete := performFamilyMemberRequest(handler, userID, http.MethodGet, "/family/members", nil)
	list = decodeFamilyMemberListResponse(t, listAfterDelete.Body.Bytes())
	if len(list) != 1 || list[0]["is_enabled"] != false {
		t.Fatalf("deleted member list = %#v, want disabled member retained", list)
	}
}

func TestFamilyMemberHandlerRejectsMissingName(t *testing.T) {
	handler, userID := newFamilyMemberTestHandler(t)

	response := performFamilyMemberRequest(handler, userID, http.MethodPost, "/family/members", map[string]any{
		"name": " ",
	})

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, body = %s", response.Code, response.Body.String())
	}
}

func TestFamilyHandlerSummary(t *testing.T) {
	handler, userID := newFamilyMemberTestHandler(t)

	createResponse := performFamilyMemberRequest(handler, userID, http.MethodPost, "/family/members", map[string]any{
		"name": "我",
	})
	if createResponse.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", createResponse.Code, createResponse.Body.String())
	}

	response := performFamilyMemberRequest(handler, userID, http.MethodGet, "/family/summary?month=2026-05", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("summary status = %d, body = %s", response.Code, response.Body.String())
	}
	data := decodeFamilySummaryResponse(t, response.Body.Bytes())
	if data["month"] != "2026-05" {
		t.Fatalf("summary month = %v, want 2026-05", data["month"])
	}
}

func TestFamilyHandlerStatistics(t *testing.T) {
	handler, userID, repos := newFamilyMemberTestHandlerWithRepos(t)

	createResponse := performFamilyMemberRequest(handler, userID, http.MethodPost, "/family/members", map[string]any{
		"name":         "我",
		"relationship": "self",
		"color":        "#0F766E",
	})
	if createResponse.Code != http.StatusCreated {
		t.Fatalf("create status = %d, body = %s", createResponse.Code, createResponse.Body.String())
	}
	created := decodeFamilyMemberResponse(t, createResponse.Body.Bytes())
	memberID := created["id"].(string)

	category := &model.Category{
		ID:     "category-food",
		UserID: userID,
		Name:   "餐饮",
		Type:   "expense",
		Color:  "#F97316",
	}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	account := &model.Account{
		ID:             "account-cash",
		UserID:         userID,
		Name:           "现金",
		Type:           "cash",
		CurrentBalance: 1000,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	txDate, err := time.ParseInLocation("2006-01-02", "2026-05-12", time.Local)
	if err != nil {
		t.Fatalf("parse date: %v", err)
	}
	if err := repos.Transaction.Create(&model.Transaction{
		ID:              "tx-family-food",
		UserID:          userID,
		AccountID:       account.ID,
		CategoryID:      &category.ID,
		Type:            "expense",
		Amount:          128.5,
		TransactionDate: txDate,
		MemberID:        &memberID,
	}); err != nil {
		t.Fatalf("create transaction: %v", err)
	}
	if err := repos.Transaction.Create(&model.Transaction{
		ID:              "tx-family-system-opening",
		UserID:          userID,
		AccountID:       account.ID,
		CategoryID:      &category.ID,
		Type:            "expense",
		Amount:          520000,
		TransactionDate: txDate,
		Remark:          "期初余额: 房贷",
		Source:          "system",
	}); err != nil {
		t.Fatalf("create system transaction: %v", err)
	}
	lendingID := "family-lending-id"
	if err := repos.Transaction.Create(&model.Transaction{
		ID:              "tx-family-lending",
		UserID:          userID,
		AccountID:       account.ID,
		CategoryID:      &category.ID,
		Type:            "expense",
		Amount:          5000,
		TransactionDate: txDate,
		MemberID:        &memberID,
		Remark:          "借出给朋友",
		Source:          "lending",
		LendingID:       &lendingID,
	}); err != nil {
		t.Fatalf("create lending transaction: %v", err)
	}

	response := performFamilyMemberRequest(handler, userID, http.MethodGet, "/family/statistics?month=2026-05", nil)
	if response.Code != http.StatusOK {
		t.Fatalf("statistics status = %d, body = %s", response.Code, response.Body.String())
	}
	data := decodeFamilyStatisticsResponse(t, response.Body.Bytes())
	if data.Month != "2026-05" || data.TotalExpense != 128.5 {
		t.Fatalf("statistics header = %#v", data)
	}
	if len(data.Members) != 1 || data.Members[0].Name != "我" {
		t.Fatalf("statistics members = %#v", data.Members)
	}
	if len(data.Members[0].Categories) != 1 || data.Members[0].Categories[0].Name != "餐饮" {
		t.Fatalf("statistics categories = %#v", data.Members[0].Categories)
	}
}

func newFamilyMemberTestHandler(t *testing.T) (*FamilyHandler, uint) {
	handler, userID, _ := newFamilyMemberTestHandlerWithRepos(t)
	return handler, userID
}

func newFamilyMemberTestHandlerWithRepos(t *testing.T) (*FamilyHandler, uint, *repository.Repositories) {
	t.Helper()
	gin.SetMode(gin.TestMode)

	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	return NewFamilyHandler(
		service.NewFamilyMemberService(repos.FamilyMember, repos.Transaction).
			WithCategoryRepository(repos.Category),
	), user.ID, repos
}

func performFamilyMemberRequest(handler *FamilyHandler, userID uint, method string, path string, payload any) *httptest.ResponseRecorder {
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set("userID", userID)
		c.Next()
	})
	router.GET("/family/members", handler.ListMembers)
	router.POST("/family/members", handler.CreateMember)
	router.PUT("/family/members/:id", handler.UpdateMember)
	router.DELETE("/family/members/:id", handler.DeleteMember)
	router.GET("/family/summary", handler.Summary)
	router.GET("/family/statistics", handler.Statistics)

	var body *bytes.Reader
	if payload == nil {
		body = bytes.NewReader(nil)
	} else {
		data, _ := json.Marshal(payload)
		body = bytes.NewReader(data)
	}
	request := httptest.NewRequest(method, path, body)
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

type familyStatisticsResponse struct {
	Month        string  `json:"month"`
	TotalExpense float64 `json:"total_expense"`
	Members      []struct {
		MemberID     string  `json:"member_id"`
		Name         string  `json:"name"`
		Relationship string  `json:"relationship"`
		Color        string  `json:"color"`
		ExpenseTotal float64 `json:"expense_total"`
		Count        int     `json:"count"`
		Categories   []struct {
			CategoryID string  `json:"category_id"`
			Name       string  `json:"name"`
			Color      string  `json:"color"`
			Amount     float64 `json:"amount"`
			Count      int     `json:"count"`
		} `json:"categories"`
	} `json:"members"`
}

func decodeFamilyStatisticsResponse(t *testing.T, data []byte) familyStatisticsResponse {
	t.Helper()
	var response struct {
		Code int                      `json:"code"`
		Data familyStatisticsResponse `json:"data"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode family statistics response: %v; body=%s", err, string(data))
	}
	return response.Data
}

func decodeFamilySummaryResponse(t *testing.T, data []byte) map[string]any {
	t.Helper()
	var response struct {
		Code int            `json:"code"`
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode family summary response: %v; body=%s", err, string(data))
	}
	return response.Data
}

func decodeFamilyMemberResponse(t *testing.T, data []byte) map[string]any {
	t.Helper()
	var response struct {
		Code int            `json:"code"`
		Data map[string]any `json:"data"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode family member response: %v; body=%s", err, string(data))
	}
	return response.Data
}

func decodeFamilyMemberListResponse(t *testing.T, data []byte) []map[string]any {
	t.Helper()
	var response struct {
		Code int              `json:"code"`
		Data []map[string]any `json:"data"`
	}
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatalf("decode family member list response: %v; body=%s", err, string(data))
	}
	return response.Data
}
