package repository

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestAIRepositoriesManageProvidersAndReusableReports(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	provider := &model.AIProvider{UserID: owner.ID, Name: "Local", BaseURL: "https://ai.example/v1", Model: "model-a", Enabled: true}
	otherProvider := &model.AIProvider{UserID: other.ID, Name: "Other", BaseURL: "https://other.example/v1", Model: "model-b"}
	for _, item := range []*model.AIProvider{provider, otherProvider} {
		if err := repos.AIProvider.Create(item); err != nil {
			t.Fatalf("create provider: %v", err)
		}
		if item.ID == "" {
			t.Fatal("provider id was not generated")
		}
	}
	loadedProvider, err := repos.AIProvider.GetByID(provider.ID)
	if err != nil || loadedProvider.Name != "Local" {
		t.Fatalf("provider = %#v, err=%v", loadedProvider, err)
	}
	loadedProvider.Name = "Updated"
	if err := repos.AIProvider.Update(loadedProvider); err != nil {
		t.Fatalf("update provider: %v", err)
	}
	providers, err := repos.AIProvider.GetByUserID(owner.ID)
	if err != nil || len(providers) != 1 || providers[0].Name != "Updated" || repos.AIProvider.DB() == nil {
		t.Fatalf("owner providers = %#v, err=%v", providers, err)
	}
	allProviders, err := repos.AIProvider.GetAll()
	if err != nil || len(allProviders) != 2 {
		t.Fatalf("all providers = %#v, err=%v", allProviders, err)
	}
	loadedProvider.APIKeyCiphertext = "cipher-owner"
	otherProvider.APIKeyCiphertext = "cipher-other"
	if err := repos.AIProvider.UpdateSecretsBatch([]model.AIProvider{*loadedProvider, *otherProvider}); err != nil {
		t.Fatalf("batch update provider secrets: %v", err)
	}
	if err := repos.AIProvider.UpdateSecretsBatch(nil); err != nil {
		t.Fatalf("empty provider secret batch: %v", err)
	}
	rotatedProvider, err := repos.AIProvider.GetByID(provider.ID)
	if err != nil || rotatedProvider.APIKeyCiphertext != "cipher-owner" || rotatedProvider.Name != "Updated" {
		t.Fatalf("rotated provider = %#v, err=%v", rotatedProvider, err)
	}

	periodStart := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	periodEnd := time.Date(2026, 1, 31, 23, 59, 59, 0, time.UTC)
	completed := &model.AIReport{
		UserID: owner.ID, ReportType: "monthly", PeriodStart: periodStart, PeriodEnd: periodEnd,
		Status: "completed", ProviderID: provider.ID, Model: "model-a", PromptVersion: "v1", ContentJSON: "{}",
	}
	pending := &model.AIReport{
		UserID: owner.ID, ReportType: "monthly", PeriodStart: periodStart, PeriodEnd: periodEnd,
		Status: "pending", ProviderID: provider.ID, Model: "model-a", PromptVersion: "v1",
	}
	otherReport := &model.AIReport{
		UserID: other.ID, ReportType: "monthly", PeriodStart: periodStart, PeriodEnd: periodEnd,
		Status: "completed", ProviderID: otherProvider.ID, Model: "model-b", PromptVersion: "v1",
	}
	for _, report := range []*model.AIReport{completed, pending, otherReport} {
		if err := repos.AIReport.Create(report); err != nil {
			t.Fatalf("create report: %v", err)
		}
		if report.ID == "" {
			t.Fatal("report id was not generated")
		}
	}
	reusable, err := repos.AIReport.GetReusableCompleted(owner.ID, "monthly", periodStart, periodEnd, provider.ID, "model-a", "v1")
	if err != nil || reusable.ID != completed.ID {
		t.Fatalf("reusable report = %#v, err=%v", reusable, err)
	}
	if _, err := repos.AIReport.GetReusableCompleted(owner.ID, "monthly", periodStart, periodEnd, provider.ID, "model-a", "v2"); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("mismatched reusable report error = %v", err)
	}
	loadedReport, err := repos.AIReport.GetByID(completed.ID)
	if err != nil {
		t.Fatalf("get report: %v", err)
	}
	loadedReport.ContentJSON = `{"summary":"updated"}`
	if err := repos.AIReport.Update(loadedReport); err != nil {
		t.Fatalf("update report: %v", err)
	}
	reports, err := repos.AIReport.GetByUserID(owner.ID)
	if err != nil || len(reports) != 2 {
		t.Fatalf("owner reports = %#v, err=%v", reports, err)
	}
	if err := repos.AIReport.Delete(pending); err != nil {
		t.Fatalf("delete report: %v", err)
	}
	if err := repos.AIProvider.Delete(loadedProvider); err != nil {
		t.Fatalf("delete provider: %v", err)
	}
}

func TestBudgetAndReminderRepositoriesScopeAssociatedData(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	account := &model.Account{ID: uuid.NewString(), UserID: owner.ID, Name: "Card", Type: "credit"}
	otherAccount := &model.Account{ID: uuid.NewString(), UserID: other.ID, Name: "Other", Type: "cash"}
	if err := repos.Account.CreateBatch([]model.Account{*account, *otherAccount}); err != nil {
		t.Fatalf("create accounts: %v", err)
	}
	category := &model.Category{ID: uuid.NewString(), UserID: owner.ID, Name: "Food", Type: "expense"}
	if err := repos.Category.Create(category); err != nil {
		t.Fatalf("create category: %v", err)
	}
	member := &model.FamilyMember{UserID: owner.ID, Name: "Owner"}
	if err := repos.FamilyMember.Create(member); err != nil {
		t.Fatalf("create member: %v", err)
	}
	categoryID := category.ID
	memberID := member.ID
	total := &model.Budget{ID: uuid.NewString(), UserID: owner.ID, Amount: 100000, Period: "monthly", IsActive: true}
	categoryBudget := &model.Budget{ID: uuid.NewString(), UserID: owner.ID, CategoryID: &categoryID, Amount: 25000, Period: "monthly", IsActive: true}
	memberBudget := &model.Budget{ID: uuid.NewString(), UserID: owner.ID, MemberID: &memberID, Amount: 40000, Period: "monthly", IsActive: true}
	otherBudget := &model.Budget{ID: uuid.NewString(), UserID: other.ID, Amount: 999999, Period: "monthly"}
	for _, budget := range []*model.Budget{total, categoryBudget, memberBudget, otherBudget} {
		if err := repos.Budget.Create(budget); err != nil {
			t.Fatalf("create budget: %v", err)
		}
	}
	loadedTotal, err := repos.Budget.GetTotalBudget(owner.ID)
	if err != nil || loadedTotal.ID != total.ID {
		t.Fatalf("total budget = %#v, err=%v", loadedTotal, err)
	}
	loadedCategory, err := repos.Budget.GetByScope(owner.ID, &categoryID, nil)
	if err != nil || loadedCategory.ID != categoryBudget.ID {
		t.Fatalf("category budget = %#v, err=%v", loadedCategory, err)
	}
	loadedMember, err := repos.Budget.GetByScope(owner.ID, nil, &memberID)
	if err != nil || loadedMember.ID != memberBudget.ID {
		t.Fatalf("member budget = %#v, err=%v", loadedMember, err)
	}
	budgets, err := repos.Budget.GetByUserID(owner.ID)
	if err != nil || len(budgets) != 3 {
		t.Fatalf("owner budgets = %#v, err=%v", budgets, err)
	}
	loadedCategory.Amount = 30000
	if err := repos.Budget.Update(loadedCategory); err != nil {
		t.Fatalf("update budget: %v", err)
	}
	if byID, err := repos.Budget.GetByID(categoryBudget.ID); err != nil || byID.Amount != 30000 {
		t.Fatalf("updated budget = %#v, err=%v", byID, err)
	}
	if err := repos.Budget.Delete(memberBudget.ID); err != nil {
		t.Fatalf("delete budget: %v", err)
	}
	if err := repos.Budget.DeleteAllByUserID(owner.ID); err != nil {
		t.Fatalf("delete owner budgets: %v", err)
	}

	accountID := account.ID
	otherAccountID := otherAccount.ID
	ownerReminder := &model.Reminder{ID: uuid.NewString(), UserID: owner.ID, Name: "Card bill", AccountID: &accountID, PaymentDay: 20, IsEnabled: true}
	otherReminder := &model.Reminder{ID: uuid.NewString(), UserID: other.ID, Name: "Other bill", AccountID: &otherAccountID, PaymentDay: 10, IsEnabled: true}
	for _, reminder := range []*model.Reminder{ownerReminder, otherReminder} {
		if err := repos.Reminder.Create(reminder); err != nil {
			t.Fatalf("create reminder: %v", err)
		}
	}
	loadedReminder, err := repos.Reminder.GetByID(ownerReminder.ID)
	if err != nil || loadedReminder.Account == nil {
		t.Fatalf("reminder with account = %#v, err=%v", loadedReminder, err)
	}
	if _, err := repos.Reminder.GetByIDForUser(ownerReminder.ID, other.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user reminder read error = %v", err)
	}
	reminders, err := repos.Reminder.GetByUserID(owner.ID)
	if err != nil || len(reminders) != 1 || reminders[0].Account == nil {
		t.Fatalf("owner reminders = %#v, err=%v", reminders, err)
	}
	accountReminders, err := repos.Reminder.ListByAccountID(owner.ID, account.ID)
	if err != nil || len(accountReminders) != 1 {
		t.Fatalf("account reminders = %#v, err=%v", accountReminders, err)
	}
	loadedReminder.Name = "Updated bill"
	if err := repos.Reminder.Update(loadedReminder); err != nil {
		t.Fatalf("update reminder: %v", err)
	}
	if err := repos.Reminder.Delete(ownerReminder.ID); err != nil {
		t.Fatalf("delete reminder: %v", err)
	}
	if err := repos.Reminder.DeleteAllByUserID(other.ID); err != nil {
		t.Fatalf("delete other reminders: %v", err)
	}
}

func TestLendingAndAccountLogRepositoriesPreserveAuditHistory(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	account := &model.Account{ID: uuid.NewString(), UserID: owner.ID, Name: "Wallet", Type: "cash", CurrentBalance: 10000}
	otherAccount := &model.Account{ID: uuid.NewString(), UserID: other.ID, Name: "Other", Type: "cash"}
	if err := repos.Account.CreateBatch([]model.Account{*account, *otherAccount}); err != nil {
		t.Fatalf("create accounts: %v", err)
	}
	accountID := account.ID
	active := &model.Lending{ID: uuid.NewString(), UserID: owner.ID, Type: "lend", ContactName: "Alice", Principal: 5000, CurrentBalance: 5000, LendDate: time.Now().Add(-24 * time.Hour), AccountID: &accountID}
	settled := &model.Lending{ID: uuid.NewString(), UserID: owner.ID, Type: "borrow", ContactName: "Bob", Principal: 2000, CurrentBalance: 0, LendDate: time.Now().Add(-48 * time.Hour), IsSettled: true}
	otherLending := &model.Lending{ID: uuid.NewString(), UserID: other.ID, Type: "lend", ContactName: "Other", Principal: 9000, CurrentBalance: 9000, LendDate: time.Now()}
	for _, lending := range []*model.Lending{active, settled, otherLending} {
		if err := repos.Lending.Create(lending); err != nil {
			t.Fatalf("create lending: %v", err)
		}
	}
	loaded, err := repos.Lending.GetByID(active.ID)
	if err != nil || loaded.Account == nil {
		t.Fatalf("lending with account = %#v, err=%v", loaded, err)
	}
	open, err := repos.Lending.GetByUserID(owner.ID, false)
	if err != nil || len(open) != 1 || open[0].ID != active.ID {
		t.Fatalf("open lendings = %#v, err=%v", open, err)
	}
	all, err := repos.Lending.GetByUserID(owner.ID, true)
	if err != nil || len(all) != 2 {
		t.Fatalf("all lendings = %#v, err=%v", all, err)
	}
	loaded.ContactRemark = "updated"
	if err := repos.Lending.Update(loaded); err != nil {
		t.Fatalf("update lending: %v", err)
	}
	record := &model.LendingRecord{ID: uuid.NewString(), LendingID: active.ID, UserID: owner.ID, Type: "repayment", Amount: 1000, RecordDate: time.Now(), AccountID: &accountID}
	if err := repos.Lending.CreateRecord(record); err != nil {
		t.Fatalf("create lending record: %v", err)
	}
	records, err := repos.Lending.GetRecordsByLendingID(active.ID)
	if err != nil || len(records) != 1 || records[0].Account == nil {
		t.Fatalf("lending records = %#v, err=%v", records, err)
	}
	if byID, err := repos.Lending.GetRecordByID(record.ID); err != nil || byID.Account == nil {
		t.Fatalf("lending record by id = %#v, err=%v", byID, err)
	}
	if err := repos.Lending.DeleteRecord(record.ID); err != nil {
		t.Fatalf("delete lending record: %v", err)
	}
	if err := repos.Lending.Delete(settled.ID); err != nil {
		t.Fatalf("delete settled lending: %v", err)
	}
	if err := repos.Lending.DeleteAllByUserID(owner.ID); err != nil {
		t.Fatalf("delete owner lendings: %v", err)
	}

	transactionID := "audit-transaction"
	if err := repos.AccountLog.Create(&CreateAccountLogRequest{
		UserID: owner.ID, AccountID: account.ID, Type: "income", Amount: 500,
		BalanceBefore: 10000, BalanceAfter: 10500, TransactionID: &transactionID, Remark: "audit",
	}); err != nil {
		t.Fatalf("create account log: %v", err)
	}
	logs, total, err := repos.AccountLog.GetByUserID(owner.ID, 1, 20)
	if err != nil || total != 1 || len(logs) != 1 || logs[0].Account == nil {
		t.Fatalf("user account logs = %#v total=%d err=%v", logs, total, err)
	}
	transactionLogs, err := repos.AccountLog.GetByTransactionID(owner.ID, transactionID)
	if err != nil || len(transactionLogs) != 1 {
		t.Fatalf("transaction account logs = %#v, err=%v", transactionLogs, err)
	}
	otherLogs, err := repos.AccountLog.GetByTransactionID(other.ID, transactionID)
	if err != nil || len(otherLogs) != 0 {
		t.Fatalf("cross-user transaction logs = %#v, err=%v", otherLogs, err)
	}
}
