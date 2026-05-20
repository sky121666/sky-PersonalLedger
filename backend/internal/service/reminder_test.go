package service

import (
	"math"
	"testing"

	"github.com/sky/personal-ledger/internal/repository"
)

func TestReminderPaymentUsesPrincipalForDebtBalanceAndRollback(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
	debtAccountID := createAccountForTest(t, repos, userID, 500)
	paymentAccountID := createAccountForTest(t, repos, userID, 1000)
	principal := 500.0
	currentBalance := 500.0

	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:           "车贷",
		AccountID:      &debtAccountID,
		PaymentDay:     15,
		Principal:      &principal,
		CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	if _, err := reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
		Amount:          120,
		PrincipalAmount: 100,
		InterestAmount:  20,
		AccountID:       &paymentAccountID,
	}); err != nil {
		t.Fatalf("record payment: %v", err)
	}

	updatedReminder, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get updated reminder: %v", err)
	}
	assertFloatEqual(t, "reminder current balance", *updatedReminder.CurrentBalance, 400)
	assertFloatEqual(t, "reminder total paid", updatedReminder.TotalPaid, 120)
	assertFloatEqual(t, "reminder interest paid", updatedReminder.InterestPaid, 20)

	debtAccount, err := repos.Account.GetByID(debtAccountID)
	if err != nil {
		t.Fatalf("get debt account: %v", err)
	}
	assertFloatEqual(t, "debt account balance", debtAccount.CurrentBalance, 400)

	paymentAccount, err := repos.Account.GetByID(paymentAccountID)
	if err != nil {
		t.Fatalf("get payment account: %v", err)
	}
	assertFloatEqual(t, "payment account balance", paymentAccount.CurrentBalance, 880)

	txID := findReminderTransactionID(t, repos, userID, reminder.ID)
	if err := txSvc.Delete(txID, userID); err != nil {
		t.Fatalf("delete reminder transaction: %v", err)
	}

	rolledBackReminder, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get rolled back reminder: %v", err)
	}
	assertFloatEqual(t, "rolled back reminder current balance", *rolledBackReminder.CurrentBalance, 500)
	assertFloatEqual(t, "rolled back reminder total paid", rolledBackReminder.TotalPaid, 0)
	assertFloatEqual(t, "rolled back reminder interest paid", rolledBackReminder.InterestPaid, 0)
	if rolledBackReminder.PaidOffAt != nil {
		t.Fatal("rolled back reminder should not stay paid off")
	}

	rolledBackDebtAccount, err := repos.Account.GetByID(debtAccountID)
	if err != nil {
		t.Fatalf("get rolled back debt account: %v", err)
	}
	assertFloatEqual(t, "rolled back debt account balance", rolledBackDebtAccount.CurrentBalance, 500)

	rolledBackPaymentAccount, err := repos.Account.GetByID(paymentAccountID)
	if err != nil {
		t.Fatalf("get rolled back payment account: %v", err)
	}
	assertFloatEqual(t, "rolled back payment account balance", rolledBackPaymentAccount.CurrentBalance, 1000)
}

func TestDeleteReminderDetachesPaymentTransactions(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
	debtAccountID := createAccountForTest(t, repos, userID, 500)
	paymentAccountID := createAccountForTest(t, repos, userID, 1000)
	principal := 500.0
	currentBalance := 500.0

	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:           "房贷",
		AccountID:      &debtAccountID,
		PaymentDay:     20,
		Principal:      &principal,
		CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	if _, err := reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
		Amount:          120,
		PrincipalAmount: 100,
		InterestAmount:  20,
		AccountID:       &paymentAccountID,
	}); err != nil {
		t.Fatalf("record payment: %v", err)
	}
	txID := findReminderTransactionID(t, repos, userID, reminder.ID)

	if err := reminderSvc.Delete(reminder.ID, userID); err != nil {
		t.Fatalf("delete reminder: %v", err)
	}

	tx, err := repos.Transaction.GetByID(txID)
	if err != nil {
		t.Fatalf("get reminder payment transaction after reminder delete: %v", err)
	}
	if tx.ReminderID != nil {
		t.Fatalf("transaction reminder_id = %q, want nil", *tx.ReminderID)
	}

	paymentAccount, err := repos.Account.GetByID(paymentAccountID)
	if err != nil {
		t.Fatalf("get payment account: %v", err)
	}
	assertFloatEqual(t, "payment account balance", paymentAccount.CurrentBalance, 880)

	debtAccount, err := repos.Account.GetByID(debtAccountID)
	if err != nil {
		t.Fatalf("get debt account: %v", err)
	}
	assertFloatEqual(t, "debt account balance", debtAccount.CurrentBalance, 400)
}

func findReminderTransactionID(t *testing.T, repos *repository.Repositories, userID uint, reminderID string) string {
	t.Helper()
	transactions, total, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total == 0 {
		t.Fatal("expected reminder payment transaction")
	}
	for _, tx := range transactions {
		if tx.ReminderID != nil && *tx.ReminderID == reminderID {
			return tx.ID
		}
	}
	t.Fatalf("no transaction linked to reminder %s", reminderID)
	return ""
}

func assertFloatEqual(t *testing.T, label string, got float64, want float64) {
	t.Helper()
	if math.Abs(got-want) > 0.001 {
		t.Fatalf("%s = %.2f, want %.2f", label, got, want)
	}
}
