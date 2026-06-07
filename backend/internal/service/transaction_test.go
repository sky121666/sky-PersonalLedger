package service

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

func newTransactionTestService(t *testing.T) (*TransactionService, *repository.Repositories, uint) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	accountLogSvc := NewAccountLogService(repos.AccountLog, repos.Account)
	return NewTransactionService(repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogSvc), repos, user.ID
}

func createAccountForTest(t *testing.T, repos *repository.Repositories, userID uint, balance float64) string {
	t.Helper()
	id := uuid.NewString()
	if err := repos.Account.Create(&model.Account{
		ID:             id,
		UserID:         userID,
		Name:           "Wallet",
		Type:           "cash",
		CurrentBalance: balance,
	}); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return id
}

func TestParseTransactionDateAcceptsFlutterLocalIsoString(t *testing.T) {
	got, err := parseTransactionDate("2026-05-18T04:42:29.878007")
	if err != nil {
		t.Fatalf("parse flutter local iso date: %v", err)
	}

	if got.Year() != 2026 || got.Month() != time.May || got.Day() != 18 {
		t.Fatalf("date = %v, want 2026-05-18", got)
	}
	if got.Hour() != 4 || got.Minute() != 42 || got.Second() != 29 {
		t.Fatalf("time = %v, want 04:42:29", got)
	}
}

func TestSumByDayUsesStoredLocalDate(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)

	_, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          12.34,
		AccountID:       accountID,
		TransactionDate: "2026-05-18T04:42:29.878007",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	start, _ := time.ParseInLocation("2006-01-02", "2026-05-01", time.Local)
	end, _ := time.ParseInLocation("2006-01-02 15:04:05", "2026-05-31 23:59:59", time.Local)
	daily, err := repos.Transaction.SumByDay(userID, start, end)
	if err != nil {
		t.Fatalf("sum by day: %v", err)
	}

	if len(daily) != 1 {
		t.Fatalf("daily len = %d, want 1: %#v", len(daily), daily)
	}
	if daily[0].Date != "2026-05-18" {
		t.Fatalf("daily date = %q, want 2026-05-18", daily[0].Date)
	}
}

func TestTransactionListExcludesSystemRowsByDefault(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)

	_, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          12.34,
		AccountID:       accountID,
		TransactionDate: "2026-05-18T04:42:29.878007",
		Remark:          "早餐",
	})
	if err != nil {
		t.Fatalf("create manual transaction: %v", err)
	}
	if err := repos.Transaction.Create(&model.Transaction{
		ID:              uuid.NewString(),
		UserID:          userID,
		AccountID:       accountID,
		Type:            "income",
		Amount:          100,
		TransactionDate: time.Date(2026, time.May, 18, 9, 0, 0, 0, time.Local),
		Remark:          "期初余额: Wallet",
		Source:          "system",
	}); err != nil {
		t.Fatalf("create system transaction: %v", err)
	}

	cleanList, cleanTotal, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:   userID,
		Page:     1,
		PageSize: 20,
	})
	if err != nil {
		t.Fatalf("list clean transactions: %v", err)
	}
	if cleanTotal != 1 || len(cleanList) != 1 || cleanList[0].Source == "system" {
		t.Fatalf("clean list = total %d rows %#v, want only manual row", cleanTotal, cleanList)
	}

	allList, allTotal, err := repos.Transaction.List(repository.TransactionFilter{
		UserID:        userID,
		IncludeSystem: true,
		Page:          1,
		PageSize:      20,
	})
	if err != nil {
		t.Fatalf("list all transactions: %v", err)
	}
	if allTotal != 2 || len(allList) != 2 {
		t.Fatalf("all list = total %d len %d, want 2", allTotal, len(allList))
	}
}

func TestTransactionStatisticsExcludeSystemRows(t *testing.T) {
	_, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	day := time.Date(2026, time.May, 18, 9, 0, 0, 0, time.Local)

	for _, tx := range []model.Transaction{
		{
			ID:              uuid.NewString(),
			UserID:          userID,
			AccountID:       accountID,
			Type:            "expense",
			Amount:          20,
			TransactionDate: day,
			Remark:          "午餐",
			Source:          "manual",
		},
		{
			ID:              uuid.NewString(),
			UserID:          userID,
			AccountID:       accountID,
			Type:            "income",
			Amount:          1000,
			TransactionDate: day,
			Remark:          "期初余额: Wallet",
			Source:          "system",
		},
	} {
		if err := repos.Transaction.Create(&tx); err != nil {
			t.Fatalf("create transaction: %v", err)
		}
	}

	start := time.Date(2026, time.May, 1, 0, 0, 0, 0, time.Local)
	end := time.Date(2026, time.May, 31, 23, 59, 59, 0, time.Local)
	sum, err := repos.Transaction.SumByDateRange(userID, start, end)
	if err != nil {
		t.Fatalf("sum by date range: %v", err)
	}
	if sum.Income != 0 || sum.Expense != 20 || sum.Count != 1 {
		t.Fatalf("sum = income %.2f expense %.2f count %d, want only manual expense", sum.Income, sum.Expense, sum.Count)
	}
}

func TestCreateTransferRollsBackWhenTargetAccountDoesNotExist(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	sourceID := createAccountForTest(t, repos, userID, 100)
	missingTargetID := uuid.NewString()

	_, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          30,
		AccountID:       sourceID,
		ToAccountID:     &missingTargetID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err == nil {
		t.Fatal("expected error for missing transfer target")
	}

	source, err := repos.Account.GetByID(sourceID)
	if err != nil {
		t.Fatalf("get source: %v", err)
	}
	if source.CurrentBalance != 100 {
		t.Fatalf("source balance = %v, want 100", source.CurrentBalance)
	}

	list, total, err := repos.Transaction.List(repository.TransactionFilter{UserID: userID, Page: 1, PageSize: 20})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if total != 0 || len(list) != 0 {
		t.Fatalf("transaction was persisted despite failed transfer: total=%d len=%d", total, len(list))
	}
}

func TestCreateTransactionPersistsFamilyMemberFields(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	memberSvc := NewFamilyMemberService(repos.FamilyMember)
	member, err := memberSvc.Create(userID, CreateFamilyMemberRequest{Name: "我", Relationship: "self"})
	if err != nil {
		t.Fatalf("create member: %v", err)
	}
	payer, err := memberSvc.Create(userID, CreateFamilyMemberRequest{Name: "家人", Relationship: "spouse"})
	if err != nil {
		t.Fatalf("create payer: %v", err)
	}

	tx, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          12.5,
		AccountID:       accountID,
		MemberID:        &member.ID,
		PaidByMemberID:  &payer.ID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	if tx.MemberID == nil || *tx.MemberID != member.ID {
		t.Fatalf("member_id = %v, want %s", tx.MemberID, member.ID)
	}
	if tx.PaidByMemberID == nil || *tx.PaidByMemberID != payer.ID {
		t.Fatalf("paid_by_member_id = %v, want %s", tx.PaidByMemberID, payer.ID)
	}
}

func TestCreateTransactionRejectsOtherUserFamilyMember(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	otherUser := &model.User{Username: "other", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	memberSvc := NewFamilyMemberService(repos.FamilyMember)
	otherMember, err := memberSvc.Create(otherUser.ID, CreateFamilyMemberRequest{Name: "其他人"})
	if err != nil {
		t.Fatalf("create other member: %v", err)
	}

	if _, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          12.5,
		AccountID:       accountID,
		MemberID:        &otherMember.ID,
		TransactionDate: time.Now().Format(time.RFC3339),
	}); err != ErrFamilyMemberNotFound {
		t.Fatalf("create err = %v, want ErrFamilyMemberNotFound", err)
	}
}

func TestUpdateRejectsTransferWithoutTargetAccount(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	tx, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create expense: %v", err)
	}

	if _, err := svc.Update(tx.ID, userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	}); err == nil {
		t.Fatal("expected transfer update without target to fail")
	}
}

func TestDeleteIncomeRecordsRollbackBalanceAfter(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	tx, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "income",
		Amount:          40,
		AccountID:       accountID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create income: %v", err)
	}

	if err := svc.Delete(tx.ID, userID); err != nil {
		t.Fatalf("delete income: %v", err)
	}

	rollback := requireAccountLog(t, repos, tx.ID, accountID, "rollback")
	assertFloatEqual(t, "rollback income balance before", rollback.BalanceBefore, 140)
	assertFloatEqual(t, "rollback income balance after", rollback.BalanceAfter, 100)
}

func TestDeleteTransferRecordsDirectionalRollbackBalances(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	sourceID := createAccountForTest(t, repos, userID, 100)
	targetID := createAccountForTest(t, repos, userID, 20)
	tx, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          30,
		AccountID:       sourceID,
		ToAccountID:     &targetID,
		TransactionDate: time.Now().Format(time.RFC3339),
	})
	if err != nil {
		t.Fatalf("create transfer: %v", err)
	}

	if err := svc.Delete(tx.ID, userID); err != nil {
		t.Fatalf("delete transfer: %v", err)
	}

	sourceRollback := requireAccountLog(t, repos, tx.ID, sourceID, "rollback")
	assertFloatEqual(t, "source rollback balance before", sourceRollback.BalanceBefore, 70)
	assertFloatEqual(t, "source rollback balance after", sourceRollback.BalanceAfter, 100)

	targetRollback := requireAccountLog(t, repos, tx.ID, targetID, "rollback")
	assertFloatEqual(t, "target rollback balance before", targetRollback.BalanceBefore, 50)
	assertFloatEqual(t, "target rollback balance after", targetRollback.BalanceAfter, 20)
}

func requireAccountLog(t *testing.T, repos *repository.Repositories, transactionID string, accountID string, logType string) model.AccountLog {
	t.Helper()
	logs, err := repos.AccountLog.GetByTransactionID(transactionID)
	if err != nil {
		t.Fatalf("get account logs: %v", err)
	}
	for _, log := range logs {
		if log.AccountID == accountID && log.Type == logType {
			return log
		}
	}
	t.Fatalf("missing account log transaction_id=%s account_id=%s type=%s", transactionID, accountID, logType)
	return model.AccountLog{}
}
