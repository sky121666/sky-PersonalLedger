package handler

import (
	"bytes"
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
)

func TestCategoryHandlerCRUDProtectionAndOwnership(t *testing.T) {
	categoryHandler, _, repos, owner, other := newCatalogHandlerFixture(t)

	invalid := performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodPost, "/categories", `{}`)
	assertHandlerStatus(t, invalid, http.StatusBadRequest)
	created := performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodPost, "/categories", `{"name":"Food","type":"expense","icon":"meal"}`)
	assertHandlerStatus(t, created, http.StatusCreated)
	var envelope struct {
		Data model.Category `json:"data"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &envelope); err != nil || envelope.Data.ID == "" {
		t.Fatalf("decode category response: data=%#v err=%v", envelope.Data, err)
	}
	categoryID := envelope.Data.ID

	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodGet, "/categories?type=expense", ""), http.StatusOK)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodGet, "/categories/"+categoryID, ""), http.StatusOK)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, other.ID, http.MethodGet, "/categories/"+categoryID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodPut, "/categories/"+categoryID, `{`), http.StatusBadRequest)
	updated := performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodPut, "/categories/"+categoryID, `{"name":"Dining","color":"#123456"}`)
	assertHandlerStatus(t, updated, http.StatusOK)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodPut, "/categories/missing", `{"name":"Missing"}`), http.StatusNotFound)

	systemCategory := &model.Category{ID: uuid.NewString(), UserID: owner.ID, Name: "System", Type: "expense", IsSystem: true}
	if err := repos.Category.Create(systemCategory); err != nil {
		t.Fatalf("create system category: %v", err)
	}
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodPut, "/categories/"+systemCategory.ID, `{"name":"Changed"}`), http.StatusForbidden)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodDelete, "/categories/"+systemCategory.ID, ""), http.StatusForbidden)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, other.ID, http.MethodDelete, "/categories/"+categoryID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodDelete, "/categories/"+categoryID, ""), http.StatusOK)
	assertHandlerStatus(t, performCategoryHandlerRequest(categoryHandler, owner.ID, http.MethodDelete, "/categories/"+categoryID, ""), http.StatusNotFound)
}

func TestTagHandlerCRUDConflictAndOwnership(t *testing.T) {
	_, tagHandler, _, owner, other := newCatalogHandlerFixture(t)

	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodPost, "/tags", `{}`), http.StatusBadRequest)
	created := performTagHandlerRequest(tagHandler, owner.ID, http.MethodPost, "/tags", `{"name":"food","color":"#111111"}`)
	assertHandlerStatus(t, created, http.StatusCreated)
	var envelope struct {
		Data model.Tag `json:"data"`
	}
	if err := json.Unmarshal(created.Body.Bytes(), &envelope); err != nil || envelope.Data.ID == "" {
		t.Fatalf("decode tag response: data=%#v err=%v", envelope.Data, err)
	}
	tagID := envelope.Data.ID

	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodPost, "/tags", `{"name":"food"}`), http.StatusConflict)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodGet, "/tags", ""), http.StatusOK)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodGet, "/tags/"+tagID, ""), http.StatusOK)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, other.ID, http.MethodGet, "/tags/"+tagID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodPut, "/tags/"+tagID, `{`), http.StatusBadRequest)
	updated := performTagHandlerRequest(tagHandler, owner.ID, http.MethodPut, "/tags/"+tagID, `{"name":"dining","icon":"meal"}`)
	assertHandlerStatus(t, updated, http.StatusOK)

	second := performTagHandlerRequest(tagHandler, owner.ID, http.MethodPost, "/tags", `{"name":"travel"}`)
	assertHandlerStatus(t, second, http.StatusCreated)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodPut, "/tags/"+tagID, `{"name":"travel"}`), http.StatusConflict)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, other.ID, http.MethodDelete, "/tags/"+tagID, ""), http.StatusNotFound)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodDelete, "/tags/"+tagID, ""), http.StatusOK)
	assertHandlerStatus(t, performTagHandlerRequest(tagHandler, owner.ID, http.MethodDelete, "/tags/"+tagID, ""), http.StatusNotFound)
}

func newCatalogHandlerFixture(t *testing.T) (*CategoryHandler, *TagHandler, *repository.Repositories, *model.User, *model.User) {
	t.Helper()
	gin.SetMode(gin.TestMode)
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init catalog handler database: %v", err)
	}
	repos := repository.NewRepositories(db)
	owner := &model.User{Username: "catalog-owner-" + uuid.NewString(), PasswordHash: "hash"}
	other := &model.User{Username: "catalog-other-" + uuid.NewString(), PasswordHash: "hash"}
	if err := repos.User.Create(owner); err != nil {
		t.Fatalf("create owner: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other: %v", err)
	}
	return NewCategoryHandler(service.NewCategoryService(repos.Category)), NewTagHandler(service.NewTagService(repos.Tag)), repos, owner, other
}

func performCategoryHandlerRequest(handler *CategoryHandler, userID uint, method, target, body string) *httptest.ResponseRecorder {
	router := gin.New()
	withUser := catalogUserHandler(userID)
	router.GET("/categories", withUser(handler.List))
	router.POST("/categories", withUser(handler.Create))
	router.GET("/categories/:id", withUser(handler.GetByID))
	router.PUT("/categories/:id", withUser(handler.Update))
	router.DELETE("/categories/:id", withUser(handler.Delete))
	return performCatalogRequest(router, method, target, body)
}

func performTagHandlerRequest(handler *TagHandler, userID uint, method, target, body string) *httptest.ResponseRecorder {
	router := gin.New()
	withUser := catalogUserHandler(userID)
	router.GET("/tags", withUser(handler.List))
	router.POST("/tags", withUser(handler.Create))
	router.GET("/tags/:id", withUser(handler.GetByID))
	router.PUT("/tags/:id", withUser(handler.Update))
	router.DELETE("/tags/:id", withUser(handler.Delete))
	return performCatalogRequest(router, method, target, body)
}

func catalogUserHandler(userID uint) func(gin.HandlerFunc) gin.HandlerFunc {
	return func(action gin.HandlerFunc) gin.HandlerFunc {
		return func(c *gin.Context) {
			c.Set("userID", userID)
			action(c)
		}
	}
}

func performCatalogRequest(router *gin.Engine, method, target, body string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(method, target, bytes.NewBufferString(body))
	if body != "" {
		request.Header.Set("Content-Type", "application/json")
	}
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	return response
}

func assertHandlerStatus(t *testing.T, response *httptest.ResponseRecorder, want int) {
	t.Helper()
	if response.Code != want {
		t.Fatalf("handler status = %d, want %d; body=%s", response.Code, want, response.Body.String())
	}
}
