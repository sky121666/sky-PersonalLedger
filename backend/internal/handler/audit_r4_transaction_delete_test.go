package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
)

func TestAuditR4TransactionDeleteConflictAndRecovery(t *testing.T) {
	for _, lendingType := range []string{"lend_out", "borrow_in"} {
		for _, batch := range []bool{false, true} {
			name := lendingType + "/single"
			if batch {
				name = lendingType + "/batch"
			}
			t.Run(name, func(t *testing.T) {
				h, repos, userID := newTransactionHandlerForTest(t)
				db, err := repos.Transaction.DB().DB()
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = db.Close() })
				accountSvc := service.NewAccountService(repos.Account)
				account, err := accountSvc.Create(userID, service.CreateAccountRequest{
					Name: "R4 handler cash", Type: "cash", InitialBalance: 1000,
				})
				if err != nil {
					t.Fatal(err)
				}
				lendingSvc := service.NewLendingService(repos.Lending, repos.Account, repos.Transaction,
					repos.Category, service.NewAccountLogService(repos.AccountLog, repos.Account))
				lending, err := lendingSvc.Create(userID, service.CreateLendingRequest{
					Type: lendingType, Principal: 100, ContactName: "R4 handler contact",
					LendDate: "2026-10-01", AccountID: &account.ID, CreateTransaction: true,
				})
				if err != nil {
					t.Fatal(err)
				}
				list, err := h.service.List(userID, service.ListTransactionRequest{})
				if err != nil || len(list.List) != 1 {
					t.Fatalf("initial lending transaction: list=%+v err=%v", list, err)
				}
				initialID := list.List[0].ID
				if _, err := lendingSvc.RecordRepayment(lending.ID, userID, service.RecordRepaymentRequest{
					Amount: 40, RecordDate: "2026-10-02", AccountID: &account.ID, CreateTransaction: true,
				}); err != nil {
					t.Fatal(err)
				}
				records, err := lendingSvc.GetRecords(lending.ID, userID)
				if err != nil || len(records) != 1 || records[0].TransactionID == nil {
					t.Fatalf("repayment record: records=%+v err=%v", records, err)
				}
				repaymentID := *records[0].TransactionID
				var res *httptest.ResponseRecorder
				if batch {
					res = auditR4BatchRequest(h, userID, []string{repaymentID, initialID})
				} else {
					res = performTransactionDeleteRequest(h, userID, initialID)
				}
				if res.Code != http.StatusConflict {
					t.Fatalf("unsafe lending deletion status=%d body=%s; want 409", res.Code, res.Body.String())
				}
				var body struct {
					Code    int    `json:"code"`
					Message string `json:"message"`
				}
				if err := json.Unmarshal(res.Body.Bytes(), &body); err != nil {
					t.Fatal(err)
				}
				if body.Code != 40906 || !strings.Contains(body.Message, "还款") ||
					!strings.Contains(body.Message, "初始流水") || !strings.Contains(body.Message, "单独") {
					t.Errorf("conflict must identify lending repayment and safe next step in Chinese: %+v", body)
				}
				current, err := accountSvc.GetByID(account.ID, userID)
				if err != nil {
					t.Fatal(err)
				}
				wantCash := int64(94000)
				if lendingType == "borrow_in" {
					wantCash = 106000
				}
				if current.CurrentBalance.Cents() != wantCash {
					t.Errorf("conflict mutated cash: %v", current.CurrentBalance)
				}
				for _, id := range []string{repaymentID, initialID} {
					if _, err := h.service.GetByID(id, userID); err != nil {
						t.Fatalf("conflict removed transaction %s: %v", id, err)
					}
					res := performTransactionDeleteRequest(h, userID, id)
					if res.Code != http.StatusOK {
						t.Fatalf("safe reverse-order deletion status=%d body=%s", res.Code, res.Body.String())
					}
				}
				final, err := lendingSvc.GetByID(lending.ID, userID)
				if err != nil {
					t.Fatal(err)
				}
				if final.CurrentBalance.Cents() != 0 || final.TotalRepaid.Cents() != 0 || final.IsSettled {
					t.Fatalf("safe reversal changed expected lending state: %+v", final)
				}
			})
		}
	}
}

func auditR4BatchRequest(h *TransactionHandler, userID uint, ids []string) *httptest.ResponseRecorder {
	body, err := json.Marshal(BatchDeleteRequest{IDs: ids})
	if err != nil {
		panic(err)
	}
	router := gin.New()
	router.POST("/transactions/batch-delete", func(c *gin.Context) {
		c.Set("userID", userID)
		h.BatchDelete(c)
	})
	request := httptest.NewRequest(http.MethodPost, "/transactions/batch-delete", bytes.NewReader(body))
	request.Header.Set("Content-Type", "application/json")
	result := httptest.NewRecorder()
	router.ServeHTTP(result, request)
	return result
}
