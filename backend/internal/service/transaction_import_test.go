package service

import (
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
)

type transactionImportFixture struct {
	service         *TransactionImportService
	repos           *repository.Repositories
	user            *model.User
	other           *model.User
	account         *model.Account
	expenseCategory *model.Category
}

func newTransactionImportFixture(t *testing.T) transactionImportFixture {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	user := &model.User{Username: "import-owner", PasswordHash: "hash"}
	other := &model.User{Username: "import-other", PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	account := &model.Account{
		ID: uuid.NewString(), UserID: user.ID, Name: "现金", Type: "cash",
		InitialBalance: 100, CurrentBalance: 100,
	}
	if err := repos.Account.Create(account); err != nil {
		t.Fatalf("create account: %v", err)
	}
	category := &model.Category{
		ID: uuid.NewString(), UserID: user.ID, Name: "餐饮", Type: "expense", Icon: "utensils",
	}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	accountLogs := NewAccountLogService(repos.AccountLog, repos.Account)
	transactions := NewTransactionService(
		repos.Transaction, repos.Account, repos.Reminder, repos.Lending, repos.FamilyMember, accountLogs,
	)
	return transactionImportFixture{
		service: NewTransactionImportService(transactions), repos: repos,
		user: user, other: other, account: account, expenseCategory: category,
	}
}

func TestTransactionImportPreviewCommitIdempotencyAndRollback(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	csvData := "日期,类型,分类,金额,账户,备注\n2026-06-15,支出,餐饮,25.50,现金,午餐\n"

	preview, err := fixture.service.Preview(fixture.user.ID, "transactions.csv", strings.NewReader(csvData))
	if err != nil {
		t.Fatalf("preview import: %v", err)
	}
	if preview.TotalRows != 1 || preview.ValidRows != 1 || preview.InvalidRows != 0 || preview.Status != "previewed" {
		t.Fatalf("preview = %#v", preview)
	}
	assertTransactionImportHasNoMutation(t, fixture, 100, 0)

	validated, err := fixture.service.Validate(fixture.user.ID, preview.ID)
	if err != nil || validated.Status != "validated" {
		t.Fatalf("validated preview = %#v, err = %v", validated, err)
	}
	committed, err := fixture.service.Commit(fixture.user.ID, preview.ID)
	if err != nil {
		t.Fatalf("commit import: %v", err)
	}
	if committed.Status != "committed" || committed.CreatedRows != 1 {
		t.Fatalf("committed preview = %#v", committed)
	}
	assertTransactionImportHasNoMutation(t, fixture, 74.5, 1)

	repeated, err := fixture.service.Preview(fixture.user.ID, "transactions.csv", strings.NewReader(csvData))
	if err != nil {
		t.Fatalf("preview repeated import: %v", err)
	}
	if repeated.DuplicateRows != 1 || !repeated.Rows[0].Duplicate {
		t.Fatalf("repeated preview = %#v, want duplicate row", repeated)
	}
	repeatedCommit, err := fixture.service.Commit(fixture.user.ID, repeated.ID)
	if err != nil {
		t.Fatalf("commit repeated import: %v", err)
	}
	if repeatedCommit.CreatedRows != 0 {
		t.Fatalf("repeated import created %d rows, want 0", repeatedCommit.CreatedRows)
	}
	assertTransactionImportHasNoMutation(t, fixture, 74.5, 1)

	if _, err := fixture.service.Rollback(fixture.user.ID, repeated.ID); err != nil {
		t.Fatalf("rollback skipped duplicate session: %v", err)
	}
	assertTransactionImportHasNoMutation(t, fixture, 74.5, 1)
	rolledBack, err := fixture.service.Rollback(fixture.user.ID, preview.ID)
	if err != nil {
		t.Fatalf("rollback import: %v", err)
	}
	if rolledBack.Status != "rolled_back" || rolledBack.RolledBackRows != 1 {
		t.Fatalf("rolled back preview = %#v", rolledBack)
	}
	assertTransactionImportHasNoMutation(t, fixture, 100, 0)
}

func TestTransactionImportInvalidRowsPreventEveryMutation(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	payload := fmt.Sprintf(`{"transactions":[
		{"type":"expense","amount":10,"account_id":%q,"category_id":%q,"transaction_date":"2026-06-15"},
		{"type":"expense","amount":20,"account_id":"missing","category_id":%q,"transaction_date":"2026-06-16"}
	]}`, fixture.account.ID, fixture.expenseCategory.ID, fixture.expenseCategory.ID)

	preview, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
	if err != nil {
		t.Fatalf("preview import: %v", err)
	}
	if preview.ValidRows != 1 || preview.InvalidRows != 1 {
		t.Fatalf("preview = %#v", preview)
	}
	commitPreview, err := fixture.service.Commit(fixture.user.ID, preview.ID)
	if !errors.Is(err, ErrTransactionImportInvalidRows) {
		t.Fatalf("commit error = %v, want ErrTransactionImportInvalidRows", err)
	}
	if commitPreview == nil || commitPreview.InvalidRows != 1 {
		t.Fatalf("commit preview = %#v", commitPreview)
	}
	assertTransactionImportHasNoMutation(t, fixture, 100, 0)
}

func TestTransactionImportSessionIsUserScopedAndCommitIsSingleUse(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	payload := fmt.Sprintf(`[{"type":"expense","amount":10,"account_id":%q,"category_id":%q,"transaction_date":"2026-06-15"}]`, fixture.account.ID, fixture.expenseCategory.ID)
	preview, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
	if err != nil {
		t.Fatalf("preview import: %v", err)
	}
	if _, err := fixture.service.Get(fixture.other.ID, preview.ID); !errors.Is(err, ErrTransactionImportNotFound) {
		t.Fatalf("cross-user get error = %v, want not found", err)
	}

	start := make(chan struct{})
	errorsCh := make(chan error, 2)
	var wait sync.WaitGroup
	for index := 0; index < 2; index++ {
		wait.Add(1)
		go func() {
			defer wait.Done()
			<-start
			_, err := fixture.service.Commit(fixture.user.ID, preview.ID)
			errorsCh <- err
		}()
	}
	close(start)
	wait.Wait()
	close(errorsCh)
	successes := 0
	conflicts := 0
	for err := range errorsCh {
		switch {
		case err == nil:
			successes++
		case errors.Is(err, ErrTransactionImportState):
			conflicts++
		default:
			t.Fatalf("unexpected commit error: %v", err)
		}
	}
	if successes != 1 || conflicts != 1 {
		t.Fatalf("commit results = successes:%d conflicts:%d", successes, conflicts)
	}
	assertTransactionImportHasNoMutation(t, fixture, 90, 1)
}

func TestTransactionImportExpiredSessionReturnsGoneSemantics(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	payload := fmt.Sprintf(`[{"type":"expense","amount":10,"account_id":%q,"category_id":%q,"transaction_date":"2026-06-15"}]`, fixture.account.ID, fixture.expenseCategory.ID)
	preview, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
	if err != nil {
		t.Fatalf("preview import: %v", err)
	}
	if err := fixture.repos.Transaction.DB().Model(&model.TransactionImportBatch{}).
		Where("id = ?", preview.ID).
		Update("expires_at", time.Now().Add(-time.Second)).Error; err != nil {
		t.Fatalf("expire persisted session: %v", err)
	}

	if _, err := fixture.service.Get(fixture.user.ID, preview.ID); !errors.Is(err, ErrTransactionImportExpired) {
		t.Fatalf("expired session error = %v, want ErrTransactionImportExpired", err)
	}
}

func TestTransactionImportSurvivesServiceRestartThroughRollback(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	payload := fmt.Sprintf(`[{"type":"expense","amount":10,"account_id":%q,"category_id":%q,"transaction_date":"2026-06-15"}]`, fixture.account.ID, fixture.expenseCategory.ID)
	preview, err := fixture.service.Preview(fixture.user.ID, "transactions.json", strings.NewReader(payload))
	if err != nil {
		t.Fatalf("preview import: %v", err)
	}

	restarted := NewTransactionImportService(fixture.service.transactions)
	recent, err := restarted.Recent(fixture.user.ID)
	if err != nil {
		t.Fatalf("load recent preview after restart: %v", err)
	}
	if recent == nil || recent.ID != preview.ID {
		t.Fatalf("recent preview = %#v, want %s", recent, preview.ID)
	}
	history, err := restarted.ListRecent(fixture.user.ID, 10)
	if err != nil {
		t.Fatalf("list recent previews: %v", err)
	}
	if len(history) != 1 || history[0].ID != preview.ID || history[0].TotalRows != 1 || len(history[0].Rows) != 0 {
		t.Fatalf("recent history = %#v, want lightweight preview summary", history)
	}
	otherRecent, err := restarted.Recent(fixture.other.ID)
	if err != nil || otherRecent != nil {
		t.Fatalf("other user recent preview = %#v, err = %v", otherRecent, err)
	}
	recovered, err := restarted.Get(fixture.user.ID, preview.ID)
	if err != nil {
		t.Fatalf("recover preview after restart: %v", err)
	}
	if recovered.Status != "previewed" || recovered.ValidRows != 1 {
		t.Fatalf("recovered preview = %#v", recovered)
	}
	committed, err := restarted.Commit(fixture.user.ID, preview.ID)
	if err != nil {
		t.Fatalf("commit recovered preview: %v", err)
	}
	if committed.Status != "committed" || committed.CreatedRows != 1 {
		t.Fatalf("committed preview = %#v", committed)
	}
	assertTransactionImportHasNoMutation(t, fixture, 90, 1)

	restartedAgain := NewTransactionImportService(fixture.service.transactions)
	rolledBack, err := restartedAgain.Rollback(fixture.user.ID, preview.ID)
	if err != nil {
		t.Fatalf("rollback after second restart: %v", err)
	}
	if rolledBack.Status != "rolled_back" || rolledBack.RolledBackRows != 1 {
		t.Fatalf("rolled back preview = %#v", rolledBack)
	}
	assertTransactionImportHasNoMutation(t, fixture, 100, 0)
}

func TestTransactionImportCSVTransferWithoutTargetIsInvalid(t *testing.T) {
	fixture := newTransactionImportFixture(t)
	csvData := "日期,类型,分类,金额,账户,备注\n2026-06-15,转账,,10,现金,转账\n"
	preview, err := fixture.service.Preview(fixture.user.ID, "transactions.csv", strings.NewReader(csvData))
	if err != nil {
		t.Fatalf("preview import: %v", err)
	}
	if preview.InvalidRows != 1 || preview.Rows[0].Valid {
		t.Fatalf("preview = %#v, want invalid transfer", preview)
	}
}

func assertTransactionImportHasNoMutation(t *testing.T, fixture transactionImportFixture, wantBalance float64, wantActiveTransactions int64) {
	t.Helper()
	account, err := fixture.repos.Account.GetByID(fixture.account.ID)
	if err != nil {
		t.Fatalf("load account: %v", err)
	}
	assertFloatEqual(t, "import account balance", account.CurrentBalance, wantBalance)
	var count int64
	if err := fixture.repos.Transaction.DB().Model(&model.Transaction{}).
		Where("user_id = ? AND source = ?", fixture.user.ID, "import").Count(&count).Error; err != nil {
		t.Fatalf("count imported transactions: %v", err)
	}
	if count != wantActiveTransactions {
		t.Fatalf("active imported transactions = %d, want %d", count, wantActiveTransactions)
	}
}
