package service

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
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
	return createTypedAccountForTest(t, repos, userID, "cash", balance)
}

func createTypedAccountForTest(t *testing.T, repos *repository.Repositories, userID uint, accountType string, balance float64) string {
	t.Helper()
	id := uuid.NewString()
	if err := repos.Account.Create(&model.Account{
		ID:             id,
		UserID:         userID,
		Name:           "Wallet " + accountType,
		Type:           accountType,
		CurrentBalance: balance,
	}); err != nil {
		t.Fatalf("create account: %v", err)
	}
	return id
}

func TestDebtAccountTransactionsUseLiabilityBalanceDirection(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createTypedAccountForTest(t, repos, userID, "credit", 100)

	expense, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          40,
		AccountID:       accountID,
		TransactionDate: "2026-07-31T10:00:00",
	})
	if err != nil {
		t.Fatalf("create credit expense: %v", err)
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get credit account after expense: %v", err)
	}
	assertFloatEqual(t, "credit balance after expense", account.CurrentBalance, 140)
	expenseLog := requireAccountLog(t, repos, userID, expense.ID, accountID, "expense")
	assertFloatEqual(t, "credit expense log before", expenseLog.BalanceBefore, 100)
	assertFloatEqual(t, "credit expense log after", expenseLog.BalanceAfter, 140)

	income, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "income",
		Amount:          15,
		AccountID:       accountID,
		TransactionDate: "2026-07-31T11:00:00",
	})
	if err != nil {
		t.Fatalf("create credit income: %v", err)
	}
	account, err = repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get credit account after income: %v", err)
	}
	assertFloatEqual(t, "credit balance after income", account.CurrentBalance, 125)
	incomeLog := requireAccountLog(t, repos, userID, income.ID, accountID, "income")
	assertFloatEqual(t, "credit income log before", incomeLog.BalanceBefore, 140)
	assertFloatEqual(t, "credit income log after", incomeLog.BalanceAfter, 125)

	if err := svc.Delete(income.ID, userID); err != nil {
		t.Fatalf("delete credit income: %v", err)
	}
	account, err = repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get credit account after income rollback: %v", err)
	}
	assertFloatEqual(t, "credit balance after income rollback", account.CurrentBalance, 140)

	if err := svc.Delete(expense.ID, userID); err != nil {
		t.Fatalf("delete credit expense: %v", err)
	}
	account, err = repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get credit account after expense rollback: %v", err)
	}
	assertFloatEqual(t, "credit balance after expense rollback", account.CurrentBalance, 100)
}

func TestTransfersBetweenAssetAndDebtAccountsUseRepaymentDirection(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	assetID := createTypedAccountForTest(t, repos, userID, "cash", 500)
	debtID := createTypedAccountForTest(t, repos, userID, "credit", 200)

	repayment, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          50,
		AccountID:       assetID,
		ToAccountID:     &debtID,
		TransactionDate: "2026-07-31T12:00:00",
	})
	if err != nil {
		t.Fatalf("create debt repayment transfer: %v", err)
	}
	asset, err := repos.Account.GetByID(assetID)
	if err != nil {
		t.Fatalf("get asset after repayment: %v", err)
	}
	debt, err := repos.Account.GetByID(debtID)
	if err != nil {
		t.Fatalf("get debt after repayment: %v", err)
	}
	assertFloatEqual(t, "asset after repayment", asset.CurrentBalance, 450)
	assertFloatEqual(t, "debt after repayment", debt.CurrentBalance, 150)
	debtRepaymentLog := requireAccountLog(t, repos, userID, repayment.ID, debtID, "transfer_in")
	assertFloatEqual(t, "debt repayment log after", debtRepaymentLog.BalanceAfter, 150)

	cashAdvance, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          30,
		AccountID:       debtID,
		ToAccountID:     &assetID,
		TransactionDate: "2026-07-31T13:00:00",
	})
	if err != nil {
		t.Fatalf("create cash advance transfer: %v", err)
	}
	asset, err = repos.Account.GetByID(assetID)
	if err != nil {
		t.Fatalf("get asset after cash advance: %v", err)
	}
	debt, err = repos.Account.GetByID(debtID)
	if err != nil {
		t.Fatalf("get debt after cash advance: %v", err)
	}
	assertFloatEqual(t, "asset after cash advance", asset.CurrentBalance, 480)
	assertFloatEqual(t, "debt after cash advance", debt.CurrentBalance, 180)
	debtAdvanceLog := requireAccountLog(t, repos, userID, cashAdvance.ID, debtID, "transfer_out")
	assertFloatEqual(t, "debt cash advance log after", debtAdvanceLog.BalanceAfter, 180)

	if err := svc.Delete(cashAdvance.ID, userID); err != nil {
		t.Fatalf("delete cash advance: %v", err)
	}
	if err := svc.Delete(repayment.ID, userID); err != nil {
		t.Fatalf("delete repayment: %v", err)
	}
	asset, _ = repos.Account.GetByID(assetID)
	debt, _ = repos.Account.GetByID(debtID)
	assertFloatEqual(t, "asset after transfer rollbacks", asset.CurrentBalance, 500)
	assertFloatEqual(t, "debt after transfer rollbacks", debt.CurrentBalance, 200)
}

func TestAccountChangeAggregationUsesStoredDebtBalanceDirection(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	assetID := createTypedAccountForTest(t, repos, userID, "cash", 500)
	debtID := createTypedAccountForTest(t, repos, userID, "credit", 100)
	for _, req := range []CreateTransactionRequest{
		{Type: "expense", Amount: 40, AccountID: debtID, TransactionDate: "2026-07-10T10:00:00"},
		{Type: "income", Amount: 15, AccountID: debtID, TransactionDate: "2026-07-11T10:00:00"},
		{Type: "transfer", Amount: 50, AccountID: assetID, ToAccountID: &debtID, TransactionDate: "2026-07-12T10:00:00"},
	} {
		if _, err := svc.Create(userID, req); err != nil {
			t.Fatalf("create account change transaction: %v", err)
		}
	}

	start := time.Date(2026, time.July, 1, 0, 0, 0, 0, time.Local)
	end := start.AddDate(0, 1, 0).Add(-time.Nanosecond)
	changes, err := repos.Transaction.SumBalanceDeltaByAccount(userID, start, end)
	if err != nil {
		t.Fatalf("sum account balance changes: %v", err)
	}
	byAccount := make(map[string]float64, len(changes))
	for _, change := range changes {
		byAccount[change.AccountID] = change.BalanceDelta
	}
	assertFloatEqual(t, "debt account aggregated balance delta", byAccount[debtID], -25)
	assertFloatEqual(t, "asset account aggregated balance delta", byAccount[assetID], -50)
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

func TestWebUTCTransactionDatesUseLocalCalendarBoundaries(t *testing.T) {
	originalLocal := time.Local
	time.Local = time.FixedZone("Asia/Shanghai", 8*60*60)
	t.Cleanup(func() { time.Local = originalLocal })

	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)

	may31, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-05-30T16:00:00.000Z",
		Remark:          "May 31 local midnight",
	})
	if err != nil {
		t.Fatalf("create May 31 web transaction: %v", err)
	}
	june1, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          20,
		AccountID:       accountID,
		TransactionDate: "2026-05-31T16:00:00.000Z",
		Remark:          "June 1 local midnight",
	})
	if err != nil {
		t.Fatalf("create June 1 web transaction: %v", err)
	}

	if got := may31.TransactionDate.Format("2006-01-02 15:04 -07:00"); got != "2026-05-31 00:00 +08:00" {
		t.Fatalf("May 31 stored date = %q, want local midnight", got)
	}
	if got := june1.TransactionDate.Format("2006-01-02 15:04 -07:00"); got != "2026-06-01 00:00 +08:00" {
		t.Fatalf("June 1 stored date = %q, want local midnight", got)
	}

	result, err := svc.List(userID, ListTransactionRequest{
		Page:      1,
		PageSize:  20,
		StartDate: "2026-05-31",
		EndDate:   "2026-05-31",
	})
	if err != nil {
		t.Fatalf("list May 31 transactions: %v", err)
	}
	if result.Total != 1 || len(result.List) != 1 || result.List[0].ID != may31.ID {
		t.Fatalf("May 31 list = total %d rows %#v, want only %s", result.Total, result.List, may31.ID)
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

func TestTransactionListIncludesFractionalEndOfDay(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)

	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          12.34,
		AccountID:       accountID,
		TransactionDate: "2026-07-31T23:59:59.500000",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	result, err := svc.List(userID, ListTransactionRequest{
		Page:      1,
		PageSize:  20,
		StartDate: "2026-07-31",
		EndDate:   "2026-07-31",
	})
	if err != nil {
		t.Fatalf("list transactions: %v", err)
	}
	if result.Total != 1 || len(result.List) != 1 || result.List[0].ID != transaction.ID {
		t.Fatalf("list = total %d rows %#v, want fractional end-of-day transaction %s", result.Total, result.List, transaction.ID)
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

func TestTransactionTagUsedCountFollowsCRUDLifecycle(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	for _, name := range []string{"food", "keep", "travel"} {
		createTransactionTagForTest(t, repos, userID, name, 0)
	}
	other := &model.User{Username: "other-tag-owner", PasswordHash: "hash"}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	createTransactionTagForTest(t, repos, other.ID, "food", 7)

	first, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
		Tags:            `["food", " food ", "keep"]`,
	})
	if err != nil {
		t.Fatalf("create first tagged transaction: %v", err)
	}
	requireTransactionTagUsedCount(t, repos, userID, "food", 1)
	requireTransactionTagUsedCount(t, repos, userID, "keep", 1)
	requireTransactionTagUsedCount(t, repos, other.ID, "food", 7)

	second, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          15,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T13:00:00",
		Tags:            `["food"]`,
	})
	if err != nil {
		t.Fatalf("create second tagged transaction: %v", err)
	}
	requireTransactionTagUsedCount(t, repos, userID, "food", 2)

	if _, err := svc.Update(first.ID, userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T14:00:00",
		Tags:            `["keep", "travel", "travel"]`,
	}); err != nil {
		t.Fatalf("update tagged transaction: %v", err)
	}
	requireTransactionTagUsedCount(t, repos, userID, "food", 1)
	requireTransactionTagUsedCount(t, repos, userID, "keep", 1)
	requireTransactionTagUsedCount(t, repos, userID, "travel", 1)

	if err := svc.Delete(first.ID, userID); err != nil {
		t.Fatalf("delete tagged transaction: %v", err)
	}
	requireTransactionTagUsedCount(t, repos, userID, "food", 1)
	requireTransactionTagUsedCount(t, repos, userID, "keep", 0)
	requireTransactionTagUsedCount(t, repos, userID, "travel", 0)

	if err := svc.DeleteBatch([]string{second.ID}, userID); err != nil {
		t.Fatalf("batch delete tagged transaction: %v", err)
	}
	requireTransactionTagUsedCount(t, repos, userID, "food", 0)
	requireTransactionTagUsedCount(t, repos, other.ID, "food", 7)
}

func TestCreateTransactionRollsBackWhenTagUsageUpdateFails(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	createTransactionTagForTest(t, repos, userID, "food", 0)
	db := repos.Transaction.DB()
	callbackName := "test:fail_transaction_tag_usage_update"
	forcedErr := errors.New("forced transaction tag usage update failure")
	if err := db.Callback().Update().Before("gorm:update").Register(callbackName, func(tx *gorm.DB) {
		if tx.Statement.Schema != nil && tx.Statement.Schema.Table == "tags" {
			tx.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatalf("register callback: %v", err)
	}
	t.Cleanup(func() { _ = db.Callback().Update().Remove(callbackName) })

	_, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
		Tags:            `["food"]`,
	})
	if !errors.Is(err, forcedErr) {
		t.Fatalf("create error = %v, want forced tag update failure", err)
	}

	var transactionCount int64
	if err := db.Model(&model.Transaction{}).Where("user_id = ?", userID).Count(&transactionCount).Error; err != nil {
		t.Fatalf("count transactions: %v", err)
	}
	if transactionCount != 0 {
		t.Fatalf("transaction count after rollback = %d, want 0", transactionCount)
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account after rollback: %v", err)
	}
	assertFloatEqual(t, "account balance after tag usage rollback", account.CurrentBalance, 100)
	requireTransactionTagUsedCount(t, repos, userID, "food", 0)
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

func TestUpdateRejectsManagedTransactions(t *testing.T) {
	lendingID := "lending-id"
	reminderID := "reminder-id"
	emptyID := ""
	tests := []struct {
		name       string
		source     string
		lendingID  *string
		reminderID *string
	}{
		{name: "lending source", source: "lending"},
		{name: "normalized reminder source", source: " REMINDER "},
		{name: "lending association", source: "manual", lendingID: &lendingID},
		{name: "reminder association", source: "manual", reminderID: &reminderID},
		{name: "present empty association", source: "manual", lendingID: &emptyID},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			svc, repos, userID := newTransactionTestService(t)
			accountID := createAccountForTest(t, repos, userID, 100)
			transaction := &model.Transaction{
				ID:              uuid.NewString(),
				UserID:          userID,
				AccountID:       accountID,
				Type:            "expense",
				Amount:          10,
				TransactionDate: time.Now(),
				Remark:          "managed",
				Source:          tt.source,
				LendingID:       tt.lendingID,
				ReminderID:      tt.reminderID,
			}
			if err := repos.Transaction.Create(transaction); err != nil {
				t.Fatalf("create managed transaction: %v", err)
			}

			_, err := svc.Update(transaction.ID, userID, CreateTransactionRequest{
				Type:            "expense",
				Amount:          25,
				AccountID:       accountID,
				TransactionDate: "2026-07-31T12:00:00",
				Remark:          "changed",
			})
			if !errors.Is(err, ErrManagedTransactionImmutable) {
				t.Fatalf("update err = %v, want ErrManagedTransactionImmutable", err)
			}

			stored, err := svc.GetByID(transaction.ID, userID)
			if err != nil {
				t.Fatalf("get managed transaction after rejected update: %v", err)
			}
			if stored.Amount != 10 || stored.Remark != "managed" {
				t.Fatalf("managed transaction changed after rejected update: %#v", stored)
			}
		})
	}
}

func TestUpdateAndDeleteRejectSystemTransaction(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction := &model.Transaction{
		ID:              uuid.NewString(),
		UserID:          userID,
		AccountID:       accountID,
		Type:            "income",
		Amount:          100,
		TransactionDate: time.Now(),
		Remark:          "期初余额: Cash",
		Source:          " SYSTEM ",
	}
	if err := repos.Transaction.Create(transaction); err != nil {
		t.Fatalf("create system transaction: %v", err)
	}

	_, err := svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "income",
		Amount:          200,
		AccountID:       accountID,
		TransactionDate: "2026-07-31T12:00:00",
	})
	if !errors.Is(err, ErrSystemTransactionImmutable) {
		t.Fatalf("update error = %v, want ErrSystemTransactionImmutable", err)
	}
	if err := svc.Delete(transaction.ID, userID); !errors.Is(err, ErrSystemTransactionImmutable) {
		t.Fatalf("delete error = %v, want ErrSystemTransactionImmutable", err)
	}

	stored, err := svc.GetByID(transaction.ID, userID)
	if err != nil {
		t.Fatalf("get system transaction after rejected mutations: %v", err)
	}
	if stored.Amount != 100 {
		t.Fatalf("system transaction amount = %.2f, want 100", stored.Amount)
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account after rejected system mutations: %v", err)
	}
	assertFloatEqual(t, "account balance after rejected system mutations", account.CurrentBalance, 100)
}

func TestUpdateAllowsManualTransaction(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-31T10:00:00",
		Remark:          "before",
	})
	if err != nil {
		t.Fatalf("create manual transaction: %v", err)
	}

	updated, err := svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          25,
		AccountID:       accountID,
		TransactionDate: "2026-07-31T12:00:00",
		Remark:          "after",
	})
	if err != nil {
		t.Fatalf("update manual transaction: %v", err)
	}
	if updated.Amount != 25 || updated.Remark != "after" {
		t.Fatalf("updated manual transaction = %#v", updated)
	}
}

func TestUpdateRejectsOtherUserCategoryWithoutChangingLedger(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	otherUser := &model.User{Username: "other-category-owner", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	otherCategory := &model.Category{
		ID:     uuid.NewString(),
		UserID: otherUser.ID,
		Name:   "Other expense",
		Type:   "expense",
	}
	if err := repos.Category.Create(otherCategory); err != nil {
		t.Fatalf("create other category: %v", err)
	}

	_, err = svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          25,
		AccountID:       accountID,
		CategoryID:      &otherCategory.ID,
		TransactionDate: "2026-07-13T13:00:00",
	})
	if !errors.Is(err, ErrCategoryNotFound) {
		t.Fatalf("update err = %v, want ErrCategoryNotFound", err)
	}

	stored, err := svc.GetByID(transaction.ID, userID)
	if err != nil {
		t.Fatalf("get transaction after rejected update: %v", err)
	}
	assertFloatEqual(t, "transaction amount after rejected update", stored.Amount, 10)
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account after rejected update: %v", err)
	}
	assertFloatEqual(t, "account balance after rejected update", account.CurrentBalance, 90)
}

func TestUpdateRejectsCategoryTypeMismatch(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}
	expenseCategory := &model.Category{
		ID:     uuid.NewString(),
		UserID: userID,
		Name:   "Expense",
		Type:   "expense",
	}
	if err := repos.Category.Create(expenseCategory); err != nil {
		t.Fatalf("create category: %v", err)
	}

	_, err = svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "income",
		Amount:          25,
		AccountID:       accountID,
		CategoryID:      &expenseCategory.ID,
		TransactionDate: "2026-07-13T13:00:00",
	})
	if !errors.Is(err, ErrCategoryTypeMismatch) {
		t.Fatalf("update err = %v, want ErrCategoryTypeMismatch", err)
	}
}

func TestUpdateRejectsOtherUserMemberOnTransfer(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	sourceID := createAccountForTest(t, repos, userID, 100)
	targetID := createAccountForTest(t, repos, userID, 20)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       sourceID,
		TransactionDate: "2026-07-13T12:00:00",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	otherUser := &model.User{Username: "other-member-owner", PasswordHash: "hash"}
	if err := repos.User.Create(otherUser); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	member, err := NewFamilyMemberService(repos.FamilyMember).Create(otherUser.ID, CreateFamilyMemberRequest{Name: "Other"})
	if err != nil {
		t.Fatalf("create other member: %v", err)
	}

	_, err = svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "transfer",
		Amount:          15,
		AccountID:       sourceID,
		ToAccountID:     &targetID,
		MemberID:        &member.ID,
		TransactionDate: "2026-07-13T13:00:00",
	})
	if !errors.Is(err, ErrFamilyMemberNotFound) {
		t.Fatalf("update err = %v, want ErrFamilyMemberNotFound", err)
	}
}

func TestUpdateRejectsInvalidAmount(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	_, err = svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          0,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T13:00:00",
	})
	if !errors.Is(err, ErrInvalidTransactionAmount) {
		t.Fatalf("update err = %v, want ErrInvalidTransactionAmount", err)
	}
}

func TestUpdateRecordsRollbackAndReplacementAccountLogs(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	transaction, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
	})
	if err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	if _, err := svc.Update(transaction.ID, userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          20,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T13:00:00",
	}); err != nil {
		t.Fatalf("update transaction: %v", err)
	}

	logs, err := repos.AccountLog.GetByTransactionID(userID, transaction.ID)
	if err != nil {
		t.Fatalf("get update account logs: %v", err)
	}
	if len(logs) != 3 {
		t.Fatalf("update account logs = %d, want original, rollback and replacement: %#v", len(logs), logs)
	}
	wantFlows := map[[2]float64]bool{
		{100, 90}: false,
		{90, 100}: false,
		{100, 80}: false,
	}
	for _, log := range logs {
		key := [2]float64{log.BalanceBefore, log.BalanceAfter}
		if _, expected := wantFlows[key]; expected {
			wantFlows[key] = true
		}
	}
	for flow, found := range wantFlows {
		if !found {
			t.Fatalf("missing account log flow %.2f -> %.2f: %#v", flow[0], flow[1], logs)
		}
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

	rollback := requireAccountLog(t, repos, userID, tx.ID, accountID, "rollback")
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

	sourceRollback := requireAccountLog(t, repos, userID, tx.ID, sourceID, "rollback")
	assertFloatEqual(t, "source rollback balance before", sourceRollback.BalanceBefore, 70)
	assertFloatEqual(t, "source rollback balance after", sourceRollback.BalanceAfter, 100)

	targetRollback := requireAccountLog(t, repos, userID, tx.ID, targetID, "rollback")
	assertFloatEqual(t, "target rollback balance before", targetRollback.BalanceBefore, 50)
	assertFloatEqual(t, "target rollback balance after", targetRollback.BalanceAfter, 20)
}

func TestDeleteBatchRollsBackAllTransactionsWhenOneIDIsMissing(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 100)
	first, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          10,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T12:00:00",
	})
	if err != nil {
		t.Fatalf("create first transaction: %v", err)
	}
	second, err := svc.Create(userID, CreateTransactionRequest{
		Type:            "expense",
		Amount:          15,
		AccountID:       accountID,
		TransactionDate: "2026-07-13T13:00:00",
	})
	if err != nil {
		t.Fatalf("create second transaction: %v", err)
	}

	err = svc.DeleteBatch([]string{first.ID, "missing-transaction", second.ID}, userID)
	if !errors.Is(err, ErrTransactionNotFound) {
		t.Fatalf("DeleteBatch err = %v, want ErrTransactionNotFound", err)
	}
	for _, id := range []string{first.ID, second.ID} {
		if _, err := svc.GetByID(id, userID); err != nil {
			t.Fatalf("transaction %s missing after rolled-back batch: %v", id, err)
		}
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get account: %v", err)
	}
	assertFloatEqual(t, "account balance after rolled-back batch", account.CurrentBalance, 75)
}

func TestAccountBalanceDeltaStaysAtMinorUnitPrecision(t *testing.T) {
	svc, repos, userID := newTransactionTestService(t)
	accountID := createAccountForTest(t, repos, userID, 0)
	db := repos.Transaction.DB()

	for range 1000 {
		if err := svc.updateAccountBalanceTx(db, userID, accountID, 0.01); err != nil {
			t.Fatalf("add cent balance: %v", err)
		}
	}
	account, err := repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get accumulated account: %v", err)
	}
	if account.CurrentBalance != 10 {
		t.Fatalf("accumulated balance = %.17f, want 10.00", account.CurrentBalance)
	}

	for range 1000 {
		if err := svc.updateAccountBalanceTx(db, userID, accountID, -0.01); err != nil {
			t.Fatalf("subtract cent balance: %v", err)
		}
	}
	account, err = repos.Account.GetByID(accountID)
	if err != nil {
		t.Fatalf("get zeroed account: %v", err)
	}
	if account.CurrentBalance != 0 {
		t.Fatalf("zeroed balance = %.17f, want 0.00", account.CurrentBalance)
	}
}

func createTransactionTagForTest(t *testing.T, repos *repository.Repositories, userID uint, name string, usedCount int) {
	t.Helper()
	if err := repos.Tag.Create(&model.Tag{UserID: userID, Name: name, UsedCount: usedCount}); err != nil {
		t.Fatalf("create tag %q for user %d: %v", name, userID, err)
	}
}

func requireTransactionTagUsedCount(t *testing.T, repos *repository.Repositories, userID uint, name string, want int) {
	t.Helper()
	tag, err := repos.Tag.GetByName(userID, name)
	if err != nil {
		t.Fatalf("get tag %q for user %d: %v", name, userID, err)
	}
	if tag.UsedCount != want {
		t.Fatalf("tag %q for user %d used_count = %d, want %d", name, userID, tag.UsedCount, want)
	}
}

func requireAccountLog(t *testing.T, repos *repository.Repositories, userID uint, transactionID string, accountID string, logType string) model.AccountLog {
	t.Helper()
	logs, err := repos.AccountLog.GetByTransactionID(userID, transactionID)
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
