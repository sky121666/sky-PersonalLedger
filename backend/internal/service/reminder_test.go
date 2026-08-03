package service

import (
	"encoding/json"
	"errors"
	"math"
	"sync"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestReminderPatchPreservesOmittedFieldsAndClearsExplicitNull(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	svc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		NewAccountLogService(repos.AccountLog, repos.Account),
	)
	accountID := createTypedAccountForTest(t, repos, userID, "loan", 500)
	principal, balance := money.Amount(500), money.Amount(500)
	billingDay := 5
	reminder, err := svc.Create(userID, CreateReminderRequest{
		Name: "Loan", AccountID: &accountID, LoanType: "loan", PaymentDay: 20,
		BillingDay: &billingDay, Principal: &principal, CurrentBalance: &balance, Remark: "clear me",
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}
	var request PatchReminderRequest
	if err := json.Unmarshal([]byte(`{"billing_day":null,"remark":""}`), &request); err != nil {
		t.Fatalf("decode patch: %v", err)
	}
	updated, err := svc.Patch(reminder.ID, userID, request)
	if err != nil {
		t.Fatalf("patch reminder: %v", err)
	}
	if updated.BillingDay != nil || updated.Remark != "" || updated.Name != reminder.Name {
		t.Fatalf("patched reminder = %#v", updated)
	}
	if updated.CurrentBalance == nil || *updated.CurrentBalance != 500 {
		t.Fatalf("linked balance = %#v, want 500", updated.CurrentBalance)
	}
}

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
	principal := money.Amount(500)
	currentBalance := money.Amount(500)

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

func TestReminderPaymentFromDebtAccountUsesDebtDirectionAndLogsBothAccounts(t *testing.T) {
	txSvc, repos, userID := newTransactionTestService(t)
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
	targetDebtID := createTypedAccountForTest(t, repos, userID, "loan", 500)
	sourceDebtID := createTypedAccountForTest(t, repos, userID, "credit", 100)
	currentBalance := money.Amount(500)
	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:           "Debt transfer",
		AccountID:      &targetDebtID,
		PaymentDay:     15,
		CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	if _, err := reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
		Amount:          120,
		PrincipalAmount: 100,
		InterestAmount:  20,
		AccountID:       &sourceDebtID,
	}); err != nil {
		t.Fatalf("record debt-funded payment: %v", err)
	}
	source, _ := repos.Account.GetByID(sourceDebtID)
	target, _ := repos.Account.GetByID(targetDebtID)
	assertFloatEqual(t, "source debt after payment", source.CurrentBalance, 220)
	assertFloatEqual(t, "target debt after payment", target.CurrentBalance, 400)

	txID := findReminderTransactionID(t, repos, userID, reminder.ID)
	logs, err := repos.AccountLog.GetByTransactionID(userID, txID)
	if err != nil {
		t.Fatalf("get reminder account logs: %v", err)
	}
	if len(logs) != 2 {
		t.Fatalf("reminder account logs = %d, want source and target", len(logs))
	}

	if err := txSvc.Delete(txID, userID); err != nil {
		t.Fatalf("delete reminder transaction: %v", err)
	}
	source, _ = repos.Account.GetByID(sourceDebtID)
	target, _ = repos.Account.GetByID(targetDebtID)
	assertFloatEqual(t, "source debt after rollback", source.CurrentBalance, 100)
	assertFloatEqual(t, "target debt after rollback", target.CurrentBalance, 500)
}

func TestReminderCreateAndUpdateRejectOtherUserAccount(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	otherUser := &model.User{Username: "reminder-other-account-owner", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	otherAccountID := createAccountForTest(t, repos, otherUser.ID, 500)
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)

	if _, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:       "invalid",
		AccountID:  &otherAccountID,
		PaymentDay: 10,
	}); err != ErrAccountNotFound {
		t.Fatalf("create reminder err = %v, want ErrAccountNotFound", err)
	}

	ownedAccountID := createAccountForTest(t, repos, userID, 300)
	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:       "owned",
		AccountID:  &ownedAccountID,
		PaymentDay: 10,
	})
	if err != nil {
		t.Fatalf("create owned reminder: %v", err)
	}
	if _, err := reminderSvc.Update(reminder.ID, userID, CreateReminderRequest{
		Name:       "invalid update",
		AccountID:  &otherAccountID,
		PaymentDay: 10,
	}); err != ErrAccountNotFound {
		t.Fatalf("update reminder err = %v, want ErrAccountNotFound", err)
	}
	unchanged, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get unchanged reminder: %v", err)
	}
	if unchanged.AccountID == nil || *unchanged.AccountID != ownedAccountID {
		t.Fatalf("account id = %v, want %s", unchanged.AccountID, ownedAccountID)
	}
}

func TestDeleteReminderPreservesPaymentTransactionLink(t *testing.T) {
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
	principal := money.Amount(500)
	currentBalance := money.Amount(500)

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
	if tx.ReminderID == nil || *tx.ReminderID != reminder.ID {
		t.Fatalf("transaction reminder_id = %v, want %q", tx.ReminderID, reminder.ID)
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

func TestReminderPaymentRejectsMissingPaymentAccountWithoutMutatingDebt(t *testing.T) {
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
	missingPaymentAccountID := "missing-payment-account"
	principal := money.Amount(500)
	currentBalance := money.Amount(500)

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
		AccountID:       &missingPaymentAccountID,
	}); err == nil {
		t.Fatal("expected missing payment account to fail")
	}

	unchangedReminder, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get unchanged reminder: %v", err)
	}
	assertFloatEqual(t, "reminder current balance", *unchangedReminder.CurrentBalance, 500)
	assertFloatEqual(t, "reminder total paid", unchangedReminder.TotalPaid, 0)
	assertFloatEqual(t, "reminder interest paid", unchangedReminder.InterestPaid, 0)
	if unchangedReminder.PaidOffAt != nil {
		t.Fatal("reminder should not be paid off")
	}

	debtAccount, err := repos.Account.GetByID(debtAccountID)
	if err != nil {
		t.Fatalf("get debt account: %v", err)
	}
	assertFloatEqual(t, "debt account balance", debtAccount.CurrentBalance, 500)

	transactions, total, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(transactions) != 0 {
		t.Fatalf("transactions after failed payment = total %d len %d, want 0", total, len(transactions))
	}
}

func TestReminderPaymentRejectsOtherUserPaymentAccountWithoutMutatingDebt(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	otherUser := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
	debtAccountID := createAccountForTest(t, repos, userID, 500)
	otherPaymentAccountID := createAccountForTest(t, repos, otherUser.ID, 1000)
	principal := money.Amount(500)
	currentBalance := money.Amount(500)

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
		AccountID:       &otherPaymentAccountID,
	}); err == nil {
		t.Fatal("expected other user's payment account to fail")
	}

	unchangedReminder, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get unchanged reminder: %v", err)
	}
	assertFloatEqual(t, "reminder current balance", *unchangedReminder.CurrentBalance, 500)
	assertFloatEqual(t, "reminder total paid", unchangedReminder.TotalPaid, 0)
	assertFloatEqual(t, "reminder interest paid", unchangedReminder.InterestPaid, 0)
	if unchangedReminder.PaidOffAt != nil {
		t.Fatal("reminder should not be paid off")
	}

	debtAccount, err := repos.Account.GetByID(debtAccountID)
	if err != nil {
		t.Fatalf("get debt account: %v", err)
	}
	assertFloatEqual(t, "debt account balance", debtAccount.CurrentBalance, 500)

	otherPaymentAccount, err := repos.Account.GetByID(otherPaymentAccountID)
	if err != nil {
		t.Fatalf("get other payment account: %v", err)
	}
	assertFloatEqual(t, "other payment account balance", otherPaymentAccount.CurrentBalance, 1000)

	transactions, total, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(transactions) != 0 {
		t.Fatalf("transactions after failed payment = total %d len %d, want 0", total, len(transactions))
	}
}

func TestReminderPaymentConcurrentRequestsRejectOverpaymentWithoutNegativeBalances(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		accountLogSvc,
	)
	debtAccountID := createAccountForTest(t, repos, userID, 100)
	paymentAccountID := createAccountForTest(t, repos, userID, 100)
	principal := money.Amount(100)
	currentBalance := money.Amount(100)

	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:           "并发提醒还款",
		AccountID:      &debtAccountID,
		PaymentDay:     15,
		Principal:      &principal,
		CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	start := make(chan struct{})
	errorsByCall := make(chan error, 2)
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			_, err := reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
				Amount:          60,
				PrincipalAmount: 60,
				AccountID:       &paymentAccountID,
			})
			errorsByCall <- err
		}()
	}
	close(start)
	wg.Wait()
	close(errorsByCall)

	var succeeded, rejected int
	for err := range errorsByCall {
		if err == nil {
			succeeded++
		} else {
			rejected++
		}
	}
	if succeeded != 1 || rejected != 1 {
		t.Fatalf("concurrent results = %d succeeded, %d rejected; want 1 and 1", succeeded, rejected)
	}

	updated, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get updated reminder: %v", err)
	}
	assertFloatEqual(t, "reminder current balance", *updated.CurrentBalance, 40)
	assertFloatEqual(t, "reminder total paid", updated.TotalPaid, 60)
	if *updated.CurrentBalance < 0 {
		t.Fatalf("reminder balance = %.2f, want non-negative", *updated.CurrentBalance)
	}

	debtAccount, err := repos.Account.GetByID(debtAccountID)
	if err != nil {
		t.Fatalf("get debt account: %v", err)
	}
	assertFloatEqual(t, "debt account balance", debtAccount.CurrentBalance, 40)
	assertFloatEqual(t, "debt account total paid", debtAccount.TotalPaid, 60)
	if debtAccount.CurrentBalance < 0 {
		t.Fatalf("debt account balance = %.2f, want non-negative", debtAccount.CurrentBalance)
	}

	paymentAccount, err := repos.Account.GetByID(paymentAccountID)
	if err != nil {
		t.Fatalf("get payment account: %v", err)
	}
	assertFloatEqual(t, "payment account balance", paymentAccount.CurrentBalance, 40)

	transactions, total, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 1 || len(transactions) != 1 {
		t.Fatalf("payment transactions = total %d len %d, want 1", total, len(transactions))
	}
	assertFloatEqual(t, "payment transaction amount", transactions[0].Amount, 60)
}

func TestReminderPaymentRejectsUsingDebtAccountAsPaymentSource(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	reminderSvc := NewReminderService(
		repos.Reminder,
		repos.Account,
		repos.Transaction,
		repos.Category,
		NewAccountLogService(repos.AccountLog, repos.Account),
	)
	debtAccountID := createAccountForTest(t, repos, userID, 100)
	principal := money.Amount(100)
	currentBalance := money.Amount(100)
	reminder, err := reminderSvc.Create(userID, CreateReminderRequest{
		Name:           "同账户还款",
		AccountID:      &debtAccountID,
		PaymentDay:     15,
		Principal:      &principal,
		CurrentBalance: &currentBalance,
	})
	if err != nil {
		t.Fatalf("create reminder: %v", err)
	}

	_, err = reminderSvc.RecordPayment(reminder.ID, userID, RecordPaymentRequest{
		Amount:          20,
		PrincipalAmount: 20,
		AccountID:       &debtAccountID,
	})
	if !errors.Is(err, ErrSameAccount) {
		t.Fatalf("same-account payment error = %v, want ErrSameAccount", err)
	}
	unchanged, err := reminderSvc.GetByID(reminder.ID, userID)
	if err != nil {
		t.Fatalf("get reminder: %v", err)
	}
	assertFloatEqual(t, "unchanged reminder balance", *unchanged.CurrentBalance, 100)
	assertFloatEqual(t, "unchanged total paid", unchanged.TotalPaid, 0)
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

func assertFloatEqual[G ~float64, W ~float64 | ~int | ~int64](t *testing.T, label string, got G, want W) {
	t.Helper()
	if math.Abs(float64(got)-float64(want)) > 0.001 {
		t.Fatalf("%s = %.2f, want %.2f", label, float64(got), float64(want))
	}
}
