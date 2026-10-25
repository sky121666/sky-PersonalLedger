package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
)

func TestReminderFinancialConflictsAreActionable(t *testing.T) {
	for _, scenario := range []string{"binding", "divergent", "undo", "batch_undo"} {
		t.Run(scenario, func(t *testing.T) {
			txHandler, repos, userID := newTransactionHandlerForTest(t)
			svc := service.NewReminderService(repos.Reminder, repos.Account, repos.Transaction, repos.Category,
				service.NewAccountLogService(repos.AccountLog, repos.Account))
			handler := NewReminderHandler(svc)
			debt := model.Account{ID: uuid.NewString(), UserID: userID, Type: "loan", Name: "Synthetic debt", CurrentBalance: 500}
			cash := model.Account{ID: uuid.NewString(), UserID: userID, Type: "cash", Name: "Synthetic cash", CurrentBalance: 1000}
			for _, a := range []*model.Account{&debt, &cash} {
				if err := repos.Account.Create(a); err != nil {
					t.Fatal(err)
				}
			}
			r, err := svc.Create(userID, service.CreateReminderRequest{Name: "Synthetic reminder", AccountID: &debt.ID, PaymentDay: 15})
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.RecordPayment(r.ID, userID, service.RecordPaymentRequest{Amount: 100, AccountID: &cash.ID}); err != nil {
				t.Fatal(err)
			}
			var tx model.Transaction
			db := repos.Transaction.DB()
			if err := db.Where("reminder_id = ?", r.ID).First(&tx).Error; err != nil {
				t.Fatal(err)
			}
			var res *httptest.ResponseRecorder
			switch scenario {
			case "undo", "batch_undo":
				if err := db.Model(&model.Reminder{}).Where("id = ?", r.ID).Update("account_id", nil).Error; err != nil {
					t.Fatal(err)
				}
				if scenario == "undo" {
					res = performTransactionDeleteRequest(txHandler, userID, tx.ID)
				} else {
					res = performTransactionBatchDeleteRequest(txHandler, userID, tx.ID)
				}
			default:
				method, body := http.MethodPatch, `{"account_id":null}`
				action := handler.Update
				if scenario == "divergent" {
					if err := db.Model(&model.Account{}).Where("id = ?", debt.ID).Update("current_balance_cents", 30000).Error; err != nil {
						t.Fatal(err)
					}
					method, body, action = http.MethodPost, `{"amount":100,"account_id":"`+cash.ID+`"}`, handler.RecordPayment
				}
				router := gin.New()
				router.Handle(method, "/reminders/:id", func(c *gin.Context) {
					c.Set("userID", userID)
					action(c)
				})
				req := httptest.NewRequest(method, "/reminders/"+r.ID, strings.NewReader(body))
				req.Header.Set("Content-Type", "application/json")
				res = httptest.NewRecorder()
				router.ServeHTTP(res, req)
			}
			if res.Code != http.StatusConflict || !strings.Contains(res.Body.String(), "核对") {
				t.Fatalf("conflict must provide a review action: %d %s", res.Code, res.Body.String())
			}
		})
	}
}
