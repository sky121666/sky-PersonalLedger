package handler

import (
	"fmt"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
)

func TestRegisteredRoutesMatchTagTemplateAndExportClients(t *testing.T) {
	router := gin.New()
	authService := service.NewAuthService(
		nil,
		nil,
		nil,
		nil,
		jwt.NewManager("route-contract-secret-with-32-characters", 15, 60),
	)
	SetupRoutesWithGroup(
		router.Group("/api/v1"),
		emptyRouteContractHandlers(),
		authService,
		service.NewAPITokenService(nil),
	)

	registered := make(map[string]bool)
	for _, route := range router.Routes() {
		registered[fmt.Sprintf("%s %s", route.Method, route.Path)] = true
	}

	for _, expected := range []string{
		"GET /api/v1/tags",
		"POST /api/v1/tags",
		"GET /api/v1/tags/:id",
		"PUT /api/v1/tags/:id",
		"DELETE /api/v1/tags/:id",
		"GET /api/v1/templates",
		"POST /api/v1/templates",
		"DELETE /api/v1/templates/:id",
		"POST /api/v1/templates/:id/apply",
		"GET /api/v1/export/transactions/csv",
		"GET /api/v1/imports/transactions",
		"POST /api/v1/imports/transactions/preview",
		"GET /api/v1/imports/transactions/recent",
		"GET /api/v1/imports/transactions/:id",
		"POST /api/v1/imports/transactions/:id/validate",
		"POST /api/v1/imports/transactions/:id/commit",
		"POST /api/v1/imports/transactions/:id/rollback",
	} {
		if !registered[expected] {
			t.Errorf("production route %q is not registered", expected)
		}
	}
}

func emptyRouteContractHandlers() *Handlers {
	return &Handlers{
		Auth:         &AuthHandler{},
		Account:      &AccountHandler{},
		Category:     &CategoryHandler{},
		Transaction:  &TransactionHandler{},
		Import:       &TransactionImportHandler{},
		Budget:       &BudgetHandler{},
		Reminder:     &ReminderHandler{},
		Statistics:   &StatisticsHandler{},
		Template:     &TemplateHandler{},
		Backup:       &BackupHandler{},
		Notification: &NotificationHandler{},
		Lending:      &LendingHandler{},
		Export:       &ExportHandler{},
		System:       &SystemHandler{},
		Upload:       &UploadHandler{},
		AccountLog:   &AccountLogHandler{},
		Tag:          &TagHandler{},
		APIToken:     &APITokenHandler{},
		Setup:        &SetupHandler{},
		Family:       &FamilyHandler{},
		AI:           &AIHandler{},
		Health:       &HealthHandler{},
	}
}
