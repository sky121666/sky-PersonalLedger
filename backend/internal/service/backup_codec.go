package service

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
)

const currentBackupVersion = "2.4"

// backupV24 is a storage contract independent of the business API's JSON.
// Explicit fields prevent newly added model fields or associations from silently
// entering backups. In particular credentials, ImportFingerprint and
// ProviderRevision are intentionally absent.
type backupV24 struct {
	Version              string                      `json:"version"`
	ExportedAt           time.Time                   `json:"exported_at"`
	SourceUserID         uint                        `json:"source_user_id,omitempty"`
	UserProfile          *UserProfileBackup          `json:"user_profile,omitempty"`
	Accounts             []backupAccount             `json:"accounts"`
	Categories           []backupCategory            `json:"categories"`
	Transactions         []backupTransaction         `json:"transactions"`
	Budgets              []backupBudget              `json:"budgets"`
	Reminders            []backupReminder            `json:"reminders"`
	Lendings             []*backupLending            `json:"lendings"`
	LendingRecords       []*backupLendingRecord      `json:"lending_records"`
	Templates            []backupQuickTemplate       `json:"templates"`
	Tags                 []backupTag                 `json:"tags"`
	FamilyMembers        []backupFamilyMember        `json:"family_members"`
	AIReports            []backupAIReport            `json:"ai_reports"`
	AccountLogs          []backupAccountLog          `json:"account_logs"`
	NotificationLogs     []backupNotificationLog     `json:"notification_logs"`
	NotificationSettings *NotificationSettingsBackup `json:"notification_settings,omitempty"`
	Attachments          []BackupAttachment          `json:"attachments"`
}

// A missing deleted_at is different from the explicit null denoting an active
// row. Only 2.4 uses this field; legacy backups never contained tombstones.
type backupDeletedAt struct {
	value   gorm.DeletedAt
	present bool
}

func (d backupDeletedAt) MarshalJSON() ([]byte, error) { return json.Marshal(d.value) }
func (d *backupDeletedAt) UnmarshalJSON(data []byte) error {
	if err := json.Unmarshal(data, &d.value); err != nil {
		return err
	}
	d.present = true
	return nil
}

// All current producers (HTTP exports and scheduled backups) marshal this same
// service value. Legacy values retain their original model JSON representation.
func (b FullBackupData) MarshalJSON() ([]byte, error) {
	if b.Version != currentBackupVersion {
		type legacy FullBackupData
		return json.Marshal(legacy(b))
	}
	wire := backupV24{
		Version: b.Version, ExportedAt: b.ExportedAt, SourceUserID: b.SourceUserID,
		UserProfile: b.UserProfile, NotificationSettings: b.NotificationSettings,
		Attachments: b.Attachments,
	}
	wire.Accounts = mapBackupSlice(b.Accounts, encodeBackupAccount)
	wire.Categories = mapBackupSlice(b.Categories, encodeBackupCategory)
	wire.Transactions = mapBackupSlice(b.Transactions, encodeBackupTransaction)
	wire.Budgets = mapBackupSlice(b.Budgets, encodeBackupBudget)
	wire.Reminders = mapBackupSlice(b.Reminders, encodeBackupReminder)
	wire.Lendings = mapBackupPointerSlice(b.Lendings, encodeBackupLending)
	wire.LendingRecords = mapBackupPointerSlice(b.LendingRecords, encodeBackupLendingRecord)
	wire.Templates = mapBackupSlice(b.Templates, encodeBackupQuickTemplate)
	wire.Tags = mapBackupSlice(b.Tags, encodeBackupTag)
	wire.FamilyMembers = mapBackupSlice(b.FamilyMembers, encodeBackupFamilyMember)
	wire.AIReports = mapBackupSlice(b.AIReports, encodeBackupAIReport)
	wire.AccountLogs = mapBackupSlice(b.AccountLogs, encodeBackupAccountLog)
	wire.NotificationLogs = mapBackupSlice(b.NotificationLogs, encodeBackupNotificationLog)
	return json.Marshal(wire)
}

func (b *FullBackupData) UnmarshalJSON(data []byte) error {
	// Restore runs streaming preflight before this allocation. This method also
	// supports decoding exported service values without changing business models.
	var version struct {
		Version string `json:"version"`
	}
	if err := json.Unmarshal(data, &version); err != nil {
		return err
	}
	if version.Version != currentBackupVersion {
		type legacy FullBackupData
		var decoded legacy
		if err := json.Unmarshal(data, &decoded); err != nil {
			return err
		}
		*b = FullBackupData(decoded)
		return nil
	}
	var wire backupV24
	if err := json.Unmarshal(data, &wire); err != nil {
		return err
	}
	if err := wire.validateTombstones(); err != nil {
		return err
	}
	decoded := FullBackupData{
		Version: wire.Version, ExportedAt: wire.ExportedAt, SourceUserID: wire.SourceUserID,
		UserProfile: wire.UserProfile, NotificationSettings: wire.NotificationSettings,
		Attachments: wire.Attachments,
	}
	decoded.Accounts = mapBackupSlice(wire.Accounts, decodeBackupAccount)
	decoded.Categories = mapBackupSlice(wire.Categories, decodeBackupCategory)
	decoded.Transactions = mapBackupSlice(wire.Transactions, decodeBackupTransaction)
	decoded.Budgets = mapBackupSlice(wire.Budgets, decodeBackupBudget)
	decoded.Reminders = mapBackupSlice(wire.Reminders, decodeBackupReminder)
	decoded.Lendings = mapBackupPointerSlice(wire.Lendings, decodeBackupLending)
	decoded.LendingRecords = mapBackupPointerSlice(wire.LendingRecords, decodeBackupLendingRecord)
	decoded.Templates = mapBackupSlice(wire.Templates, decodeBackupQuickTemplate)
	decoded.Tags = mapBackupSlice(wire.Tags, decodeBackupTag)
	decoded.FamilyMembers = mapBackupSlice(wire.FamilyMembers, decodeBackupFamilyMember)
	decoded.AIReports = mapBackupSlice(wire.AIReports, decodeBackupAIReport)
	decoded.AccountLogs = mapBackupSlice(wire.AccountLogs, decodeBackupAccountLog)
	decoded.NotificationLogs = mapBackupSlice(wire.NotificationLogs, decodeBackupNotificationLog)
	*b = decoded
	return nil
}

func (b backupV24) validateTombstones() error {
	for i, row := range b.Accounts {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("accounts[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Categories {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("categories[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Transactions {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("transactions[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Budgets {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("budgets[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Reminders {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("reminders[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Lendings {
		if row == nil || !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("lendings[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.LendingRecords {
		if row == nil || !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("lending_records[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Templates {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("templates[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.Tags {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("tags[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.FamilyMembers {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("family_members[%d] requires an explicit deleted_at", i))
		}
	}
	for i, row := range b.AIReports {
		if !row.DeletedAt.present {
			return invalidBackupJSON(fmt.Errorf("ai_reports[%d] requires an explicit deleted_at", i))
		}
	}
	return nil
}

func mapBackupSlice[A, B any](rows []A, convert func(A) B) []B {
	if rows == nil {
		return nil
	}
	mapped := make([]B, len(rows))
	for i, row := range rows {
		mapped[i] = convert(row)
	}
	return mapped
}

func mapBackupPointerSlice[A, B any](rows []*A, convert func(A) B) []*B {
	if rows == nil {
		return nil
	}
	mapped := make([]*B, len(rows))
	for i, row := range rows {
		if row != nil {
			value := convert(*row)
			mapped[i] = &value
		}
	}
	return mapped
}

type backupAccount struct {
	ID             string          `json:"id"`
	UserID         uint            `json:"user_id"`
	Name           string          `json:"name"`
	Type           string          `json:"type"`
	Icon           string          `json:"icon"`
	Color          string          `json:"color"`
	InitialBalance money.Amount    `json:"initial_balance"`
	CurrentBalance money.Amount    `json:"current_balance"`
	PaymentDay     *int            `json:"payment_day"`
	BillingDay     *int            `json:"billing_day"`
	CreditLimit    *money.Amount   `json:"credit_limit"`
	InterestRate   *float64        `json:"interest_rate"`
	TotalPaid      money.Amount    `json:"total_paid"`
	StartDate      *time.Time      `json:"start_date"`
	TargetDate     *time.Time      `json:"target_date"`
	PaidOffAt      *time.Time      `json:"paid_off_at"`
	Remark         string          `json:"remark"`
	IsArchived     bool            `json:"is_archived"`
	SortOrder      int             `json:"sort_order"`
	CreatedAt      time.Time       `json:"created_at"`
	UpdatedAt      time.Time       `json:"updated_at"`
	DeletedAt      backupDeletedAt `json:"deleted_at"`
}

func encodeBackupAccount(row model.Account) backupAccount {
	return backupAccount{
		ID:             row.ID,
		UserID:         row.UserID,
		Name:           row.Name,
		Type:           row.Type,
		Icon:           row.Icon,
		Color:          row.Color,
		InitialBalance: row.InitialBalance,
		CurrentBalance: row.CurrentBalance,
		PaymentDay:     row.PaymentDay,
		BillingDay:     row.BillingDay,
		CreditLimit:    row.CreditLimit,
		InterestRate:   row.InterestRate,
		TotalPaid:      row.TotalPaid,
		StartDate:      row.StartDate,
		TargetDate:     row.TargetDate,
		PaidOffAt:      row.PaidOffAt,
		Remark:         row.Remark,
		IsArchived:     row.IsArchived,
		SortOrder:      row.SortOrder,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupAccount(row backupAccount) model.Account {
	return model.Account{
		ID:             row.ID,
		UserID:         row.UserID,
		Name:           row.Name,
		Type:           row.Type,
		Icon:           row.Icon,
		Color:          row.Color,
		InitialBalance: row.InitialBalance,
		CurrentBalance: row.CurrentBalance,
		PaymentDay:     row.PaymentDay,
		BillingDay:     row.BillingDay,
		CreditLimit:    row.CreditLimit,
		InterestRate:   row.InterestRate,
		TotalPaid:      row.TotalPaid,
		StartDate:      row.StartDate,
		TargetDate:     row.TargetDate,
		PaidOffAt:      row.PaidOffAt,
		Remark:         row.Remark,
		IsArchived:     row.IsArchived,
		SortOrder:      row.SortOrder,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      row.DeletedAt.value,
	}
}

type backupCategory struct {
	ID        string          `json:"id"`
	UserID    uint            `json:"user_id"`
	Name      string          `json:"name"`
	Type      string          `json:"type"`
	Icon      string          `json:"icon"`
	Color     string          `json:"color"`
	IsSystem  bool            `json:"is_system"`
	SortOrder int             `json:"sort_order"`
	CreatedAt time.Time       `json:"created_at"`
	UpdatedAt time.Time       `json:"updated_at"`
	DeletedAt backupDeletedAt `json:"deleted_at"`
}

func encodeBackupCategory(row model.Category) backupCategory {
	return backupCategory{
		ID:        row.ID,
		UserID:    row.UserID,
		Name:      row.Name,
		Type:      row.Type,
		Icon:      row.Icon,
		Color:     row.Color,
		IsSystem:  row.IsSystem,
		SortOrder: row.SortOrder,
		CreatedAt: row.CreatedAt,
		UpdatedAt: row.UpdatedAt,
		DeletedAt: backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupCategory(row backupCategory) model.Category {
	return model.Category{
		ID:        row.ID,
		UserID:    row.UserID,
		Name:      row.Name,
		Type:      row.Type,
		Icon:      row.Icon,
		Color:     row.Color,
		IsSystem:  row.IsSystem,
		SortOrder: row.SortOrder,
		CreatedAt: row.CreatedAt,
		UpdatedAt: row.UpdatedAt,
		DeletedAt: row.DeletedAt.value,
	}
}

type backupTransaction struct {
	ID              string          `json:"id"`
	UserID          uint            `json:"user_id"`
	AccountID       string          `json:"account_id"`
	CategoryID      *string         `json:"category_id"`
	Type            string          `json:"type"`
	Amount          money.Amount    `json:"amount"`
	PrincipalAmount money.Amount    `json:"principal_amount,omitempty"`
	InterestAmount  money.Amount    `json:"interest_amount,omitempty"`
	TransactionDate time.Time       `json:"transaction_date"`
	Remark          string          `json:"remark"`
	Images          string          `json:"images"`
	Tags            string          `json:"tags"`
	ToAccountID     *string         `json:"to_account_id"`
	MemberID        *string         `json:"member_id,omitempty"`
	PaidByMemberID  *string         `json:"paid_by_member_id,omitempty"`
	Source          string          `json:"source"`
	ReminderID      *string         `json:"reminder_id,omitempty"`
	LendingID       *string         `json:"lending_id,omitempty"`
	RecurringID     *string         `json:"recurring_id,omitempty"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
	DeletedAt       backupDeletedAt `json:"deleted_at"`
}

func encodeBackupTransaction(row model.Transaction) backupTransaction {
	return backupTransaction{
		ID:              row.ID,
		UserID:          row.UserID,
		AccountID:       row.AccountID,
		CategoryID:      row.CategoryID,
		Type:            row.Type,
		Amount:          row.Amount,
		PrincipalAmount: row.PrincipalAmount,
		InterestAmount:  row.InterestAmount,
		TransactionDate: row.TransactionDate,
		Remark:          row.Remark,
		Images:          row.Images,
		Tags:            row.Tags,
		ToAccountID:     row.ToAccountID,
		MemberID:        row.MemberID,
		PaidByMemberID:  row.PaidByMemberID,
		Source:          row.Source,
		ReminderID:      row.ReminderID,
		LendingID:       row.LendingID,
		RecurringID:     row.RecurringID,
		CreatedAt:       row.CreatedAt,
		UpdatedAt:       row.UpdatedAt,
		DeletedAt:       backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupTransaction(row backupTransaction) model.Transaction {
	return model.Transaction{
		ID:              row.ID,
		UserID:          row.UserID,
		AccountID:       row.AccountID,
		CategoryID:      row.CategoryID,
		Type:            row.Type,
		Amount:          row.Amount,
		PrincipalAmount: row.PrincipalAmount,
		InterestAmount:  row.InterestAmount,
		TransactionDate: row.TransactionDate,
		Remark:          row.Remark,
		Images:          row.Images,
		Tags:            row.Tags,
		ToAccountID:     row.ToAccountID,
		MemberID:        row.MemberID,
		PaidByMemberID:  row.PaidByMemberID,
		Source:          row.Source,
		ReminderID:      row.ReminderID,
		LendingID:       row.LendingID,
		RecurringID:     row.RecurringID,
		CreatedAt:       row.CreatedAt,
		UpdatedAt:       row.UpdatedAt,
		DeletedAt:       row.DeletedAt.value,
	}
}

type backupBudget struct {
	ID             string          `json:"id"`
	UserID         uint            `json:"user_id"`
	CategoryID     *string         `json:"category_id"`
	MemberID       *string         `json:"member_id,omitempty"`
	Amount         money.Amount    `json:"amount"`
	Period         string          `json:"period"`
	AlertThreshold int             `json:"alert_threshold"`
	IsActive       bool            `json:"is_active"`
	CreatedAt      time.Time       `json:"created_at"`
	UpdatedAt      time.Time       `json:"updated_at"`
	DeletedAt      backupDeletedAt `json:"deleted_at"`
}

func encodeBackupBudget(row model.Budget) backupBudget {
	return backupBudget{
		ID:             row.ID,
		UserID:         row.UserID,
		CategoryID:     row.CategoryID,
		MemberID:       row.MemberID,
		Amount:         row.Amount,
		Period:         row.Period,
		AlertThreshold: row.AlertThreshold,
		IsActive:       row.IsActive,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupBudget(row backupBudget) model.Budget {
	return model.Budget{
		ID:             row.ID,
		UserID:         row.UserID,
		CategoryID:     row.CategoryID,
		MemberID:       row.MemberID,
		Amount:         row.Amount,
		Period:         row.Period,
		AlertThreshold: row.AlertThreshold,
		IsActive:       row.IsActive,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      row.DeletedAt.value,
	}
}

type backupReminder struct {
	ID             string          `json:"id"`
	UserID         uint            `json:"user_id"`
	Name           string          `json:"name"`
	AccountID      *string         `json:"account_id"`
	LoanType       string          `json:"loan_type"`
	PaymentDay     int             `json:"payment_day"`
	BillingDay     *int            `json:"billing_day"`
	AdvanceDays    int             `json:"advance_days"`
	Amount         *money.Amount   `json:"amount"`
	Principal      *money.Amount   `json:"principal"`
	CurrentBalance *money.Amount   `json:"current_balance"`
	InterestRate   *float64        `json:"interest_rate"`
	TotalInterest  *money.Amount   `json:"total_interest"`
	TotalPaid      money.Amount    `json:"total_paid"`
	InterestPaid   money.Amount    `json:"interest_paid"`
	StartDate      *time.Time      `json:"start_date"`
	TargetDate     *time.Time      `json:"target_date"`
	PaidOffAt      *time.Time      `json:"paid_off_at"`
	Color          string          `json:"color"`
	Remark         string          `json:"remark"`
	IsEnabled      bool            `json:"is_enabled"`
	LastNotifiedAt *time.Time      `json:"last_notified_at"`
	Evidence       string          `json:"evidence"`
	CreatedAt      time.Time       `json:"created_at"`
	UpdatedAt      time.Time       `json:"updated_at"`
	DeletedAt      backupDeletedAt `json:"deleted_at"`
}

func encodeBackupReminder(row model.Reminder) backupReminder {
	return backupReminder{
		ID:             row.ID,
		UserID:         row.UserID,
		Name:           row.Name,
		AccountID:      row.AccountID,
		LoanType:       row.LoanType,
		PaymentDay:     row.PaymentDay,
		BillingDay:     row.BillingDay,
		AdvanceDays:    row.AdvanceDays,
		Amount:         row.Amount,
		Principal:      row.Principal,
		CurrentBalance: row.CurrentBalance,
		InterestRate:   row.InterestRate,
		TotalInterest:  row.TotalInterest,
		TotalPaid:      row.TotalPaid,
		InterestPaid:   row.InterestPaid,
		StartDate:      row.StartDate,
		TargetDate:     row.TargetDate,
		PaidOffAt:      row.PaidOffAt,
		Color:          row.Color,
		Remark:         row.Remark,
		IsEnabled:      row.IsEnabled,
		LastNotifiedAt: row.LastNotifiedAt,
		Evidence:       row.Evidence,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupReminder(row backupReminder) model.Reminder {
	return model.Reminder{
		ID:             row.ID,
		UserID:         row.UserID,
		Name:           row.Name,
		AccountID:      row.AccountID,
		LoanType:       row.LoanType,
		PaymentDay:     row.PaymentDay,
		BillingDay:     row.BillingDay,
		AdvanceDays:    row.AdvanceDays,
		Amount:         row.Amount,
		Principal:      row.Principal,
		CurrentBalance: row.CurrentBalance,
		InterestRate:   row.InterestRate,
		TotalInterest:  row.TotalInterest,
		TotalPaid:      row.TotalPaid,
		InterestPaid:   row.InterestPaid,
		StartDate:      row.StartDate,
		TargetDate:     row.TargetDate,
		PaidOffAt:      row.PaidOffAt,
		Color:          row.Color,
		Remark:         row.Remark,
		IsEnabled:      row.IsEnabled,
		LastNotifiedAt: row.LastNotifiedAt,
		Evidence:       row.Evidence,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      row.DeletedAt.value,
	}
}

type backupLending struct {
	ID             string          `json:"id"`
	UserID         uint            `json:"user_id"`
	Type           string          `json:"type"`
	ContactName    string          `json:"contact_name"`
	ContactPhone   string          `json:"contact_phone"`
	ContactRemark  string          `json:"contact_remark"`
	Principal      money.Amount    `json:"principal"`
	InterestRate   *float64        `json:"interest_rate"`
	CurrentBalance money.Amount    `json:"current_balance"`
	TotalRepaid    money.Amount    `json:"total_repaid"`
	LendDate       time.Time       `json:"lend_date"`
	DueDate        *time.Time      `json:"due_date"`
	SettledAt      *time.Time      `json:"settled_at"`
	AccountID      *string         `json:"account_id"`
	Remark         string          `json:"remark"`
	Evidence       string          `json:"evidence"`
	IsSettled      bool            `json:"is_settled"`
	CreatedAt      time.Time       `json:"created_at"`
	UpdatedAt      time.Time       `json:"updated_at"`
	DeletedAt      backupDeletedAt `json:"deleted_at"`
}

func encodeBackupLending(row model.Lending) backupLending {
	return backupLending{
		ID:             row.ID,
		UserID:         row.UserID,
		Type:           row.Type,
		ContactName:    row.ContactName,
		ContactPhone:   row.ContactPhone,
		ContactRemark:  row.ContactRemark,
		Principal:      row.Principal,
		InterestRate:   row.InterestRate,
		CurrentBalance: row.CurrentBalance,
		TotalRepaid:    row.TotalRepaid,
		LendDate:       row.LendDate,
		DueDate:        row.DueDate,
		SettledAt:      row.SettledAt,
		AccountID:      row.AccountID,
		Remark:         row.Remark,
		Evidence:       row.Evidence,
		IsSettled:      row.IsSettled,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupLending(row backupLending) model.Lending {
	return model.Lending{
		ID:             row.ID,
		UserID:         row.UserID,
		Type:           row.Type,
		ContactName:    row.ContactName,
		ContactPhone:   row.ContactPhone,
		ContactRemark:  row.ContactRemark,
		Principal:      row.Principal,
		InterestRate:   row.InterestRate,
		CurrentBalance: row.CurrentBalance,
		TotalRepaid:    row.TotalRepaid,
		LendDate:       row.LendDate,
		DueDate:        row.DueDate,
		SettledAt:      row.SettledAt,
		AccountID:      row.AccountID,
		Remark:         row.Remark,
		Evidence:       row.Evidence,
		IsSettled:      row.IsSettled,
		CreatedAt:      row.CreatedAt,
		UpdatedAt:      row.UpdatedAt,
		DeletedAt:      row.DeletedAt.value,
	}
}

type backupLendingRecord struct {
	ID            string          `json:"id"`
	LendingID     string          `json:"lending_id"`
	UserID        uint            `json:"user_id"`
	Type          string          `json:"type"`
	Amount        money.Amount    `json:"amount"`
	RecordDate    time.Time       `json:"record_date"`
	AccountID     *string         `json:"account_id"`
	TransactionID *string         `json:"transaction_id"`
	Remark        string          `json:"remark"`
	Evidence      string          `json:"evidence"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
	DeletedAt     backupDeletedAt `json:"deleted_at"`
}

func encodeBackupLendingRecord(row model.LendingRecord) backupLendingRecord {
	return backupLendingRecord{
		ID:            row.ID,
		LendingID:     row.LendingID,
		UserID:        row.UserID,
		Type:          row.Type,
		Amount:        row.Amount,
		RecordDate:    row.RecordDate,
		AccountID:     row.AccountID,
		TransactionID: row.TransactionID,
		Remark:        row.Remark,
		Evidence:      row.Evidence,
		CreatedAt:     row.CreatedAt,
		UpdatedAt:     row.UpdatedAt,
		DeletedAt:     backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupLendingRecord(row backupLendingRecord) model.LendingRecord {
	return model.LendingRecord{
		ID:            row.ID,
		LendingID:     row.LendingID,
		UserID:        row.UserID,
		Type:          row.Type,
		Amount:        row.Amount,
		RecordDate:    row.RecordDate,
		AccountID:     row.AccountID,
		TransactionID: row.TransactionID,
		Remark:        row.Remark,
		Evidence:      row.Evidence,
		CreatedAt:     row.CreatedAt,
		UpdatedAt:     row.UpdatedAt,
		DeletedAt:     row.DeletedAt.value,
	}
}

type backupQuickTemplate struct {
	ID         string          `json:"id"`
	UserID     uint            `json:"user_id"`
	Name       string          `json:"name"`
	Type       string          `json:"type"`
	Amount     money.Amount    `json:"amount"`
	AccountID  string          `json:"account_id"`
	CategoryID *string         `json:"category_id"`
	Remark     string          `json:"remark"`
	UsedCount  int             `json:"used_count"`
	LastUsedAt *time.Time      `json:"last_used_at"`
	CreatedAt  time.Time       `json:"created_at"`
	UpdatedAt  time.Time       `json:"updated_at"`
	DeletedAt  backupDeletedAt `json:"deleted_at"`
}

func encodeBackupQuickTemplate(row model.QuickTemplate) backupQuickTemplate {
	return backupQuickTemplate{
		ID:         row.ID,
		UserID:     row.UserID,
		Name:       row.Name,
		Type:       row.Type,
		Amount:     row.Amount,
		AccountID:  row.AccountID,
		CategoryID: row.CategoryID,
		Remark:     row.Remark,
		UsedCount:  row.UsedCount,
		LastUsedAt: row.LastUsedAt,
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
		DeletedAt:  backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupQuickTemplate(row backupQuickTemplate) model.QuickTemplate {
	return model.QuickTemplate{
		ID:         row.ID,
		UserID:     row.UserID,
		Name:       row.Name,
		Type:       row.Type,
		Amount:     row.Amount,
		AccountID:  row.AccountID,
		CategoryID: row.CategoryID,
		Remark:     row.Remark,
		UsedCount:  row.UsedCount,
		LastUsedAt: row.LastUsedAt,
		CreatedAt:  row.CreatedAt,
		UpdatedAt:  row.UpdatedAt,
		DeletedAt:  row.DeletedAt.value,
	}
}

type backupTag struct {
	ID        string          `json:"id"`
	UserID    uint            `json:"user_id"`
	Name      string          `json:"name"`
	Color     string          `json:"color"`
	Icon      string          `json:"icon"`
	IsSystem  bool            `json:"is_system"`
	UsedCount int             `json:"used_count"`
	CreatedAt time.Time       `json:"created_at"`
	UpdatedAt time.Time       `json:"updated_at"`
	DeletedAt backupDeletedAt `json:"deleted_at"`
}

func encodeBackupTag(row model.Tag) backupTag {
	return backupTag{
		ID:        row.ID,
		UserID:    row.UserID,
		Name:      row.Name,
		Color:     row.Color,
		Icon:      row.Icon,
		IsSystem:  row.IsSystem,
		UsedCount: row.UsedCount,
		CreatedAt: row.CreatedAt,
		UpdatedAt: row.UpdatedAt,
		DeletedAt: backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupTag(row backupTag) model.Tag {
	return model.Tag{
		ID:        row.ID,
		UserID:    row.UserID,
		Name:      row.Name,
		Color:     row.Color,
		Icon:      row.Icon,
		IsSystem:  row.IsSystem,
		UsedCount: row.UsedCount,
		CreatedAt: row.CreatedAt,
		UpdatedAt: row.UpdatedAt,
		DeletedAt: row.DeletedAt.value,
	}
}

type backupFamilyMember struct {
	ID           string          `json:"id"`
	UserID       uint            `json:"user_id"`
	Name         string          `json:"name"`
	Relationship string          `json:"relationship"`
	Avatar       string          `json:"avatar"`
	Color        string          `json:"color"`
	SortOrder    int             `json:"sort_order"`
	IsDefault    bool            `json:"is_default"`
	IsEnabled    bool            `json:"is_enabled"`
	CreatedAt    time.Time       `json:"created_at"`
	UpdatedAt    time.Time       `json:"updated_at"`
	DeletedAt    backupDeletedAt `json:"deleted_at"`
}

func encodeBackupFamilyMember(row model.FamilyMember) backupFamilyMember {
	return backupFamilyMember{
		ID:           row.ID,
		UserID:       row.UserID,
		Name:         row.Name,
		Relationship: row.Relationship,
		Avatar:       row.Avatar,
		Color:        row.Color,
		SortOrder:    row.SortOrder,
		IsDefault:    row.IsDefault,
		IsEnabled:    row.IsEnabled,
		CreatedAt:    row.CreatedAt,
		UpdatedAt:    row.UpdatedAt,
		DeletedAt:    backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupFamilyMember(row backupFamilyMember) model.FamilyMember {
	return model.FamilyMember{
		ID:           row.ID,
		UserID:       row.UserID,
		Name:         row.Name,
		Relationship: row.Relationship,
		Avatar:       row.Avatar,
		Color:        row.Color,
		SortOrder:    row.SortOrder,
		IsDefault:    row.IsDefault,
		IsEnabled:    row.IsEnabled,
		CreatedAt:    row.CreatedAt,
		UpdatedAt:    row.UpdatedAt,
		DeletedAt:    row.DeletedAt.value,
	}
}

type backupAIReport struct {
	ID            string          `json:"id"`
	UserID        uint            `json:"user_id"`
	ReportType    string          `json:"report_type"`
	PeriodStart   time.Time       `json:"period_start"`
	PeriodEnd     time.Time       `json:"period_end"`
	Status        string          `json:"status"`
	SnapshotJSON  string          `json:"snapshot_json"`
	ContentJSON   string          `json:"content_json"`
	ProviderID    string          `json:"provider_id"`
	ProviderName  string          `json:"provider_name"`
	Model         string          `json:"model"`
	PromptVersion string          `json:"prompt_version"`
	ErrorMessage  string          `json:"error_message,omitempty"`
	CreatedAt     time.Time       `json:"created_at"`
	UpdatedAt     time.Time       `json:"updated_at"`
	DeletedAt     backupDeletedAt `json:"deleted_at"`
}

func encodeBackupAIReport(row model.AIReport) backupAIReport {
	return backupAIReport{
		ID:            row.ID,
		UserID:        row.UserID,
		ReportType:    row.ReportType,
		PeriodStart:   row.PeriodStart,
		PeriodEnd:     row.PeriodEnd,
		Status:        row.Status,
		SnapshotJSON:  row.SnapshotJSON,
		ContentJSON:   row.ContentJSON,
		ProviderID:    row.ProviderID,
		ProviderName:  row.ProviderName,
		Model:         row.Model,
		PromptVersion: row.PromptVersion,
		ErrorMessage:  row.ErrorMessage,
		CreatedAt:     row.CreatedAt,
		UpdatedAt:     row.UpdatedAt,
		DeletedAt:     backupDeletedAt{value: row.DeletedAt, present: true},
	}
}

func decodeBackupAIReport(row backupAIReport) model.AIReport {
	return model.AIReport{
		ID:            row.ID,
		UserID:        row.UserID,
		ReportType:    row.ReportType,
		PeriodStart:   row.PeriodStart,
		PeriodEnd:     row.PeriodEnd,
		Status:        row.Status,
		SnapshotJSON:  row.SnapshotJSON,
		ContentJSON:   row.ContentJSON,
		ProviderID:    row.ProviderID,
		ProviderName:  row.ProviderName,
		Model:         row.Model,
		PromptVersion: row.PromptVersion,
		ErrorMessage:  row.ErrorMessage,
		CreatedAt:     row.CreatedAt,
		UpdatedAt:     row.UpdatedAt,
		DeletedAt:     row.DeletedAt.value,
	}
}

type backupAccountLog struct {
	ID            string       `json:"id"`
	UserID        uint         `json:"user_id"`
	AccountID     string       `json:"account_id"`
	Type          string       `json:"type"`
	Amount        money.Amount `json:"amount"`
	BalanceBefore money.Amount `json:"balance_before"`
	BalanceAfter  money.Amount `json:"balance_after"`
	TransactionID *string      `json:"transaction_id,omitempty"`
	ReminderID    *string      `json:"reminder_id,omitempty"`
	LendingID     *string      `json:"lending_id,omitempty"`
	Remark        string       `json:"remark"`
	CreatedAt     time.Time    `json:"created_at"`
}

func encodeBackupAccountLog(row model.AccountLog) backupAccountLog {
	return backupAccountLog{
		ID:            row.ID,
		UserID:        row.UserID,
		AccountID:     row.AccountID,
		Type:          row.Type,
		Amount:        row.Amount,
		BalanceBefore: row.BalanceBefore,
		BalanceAfter:  row.BalanceAfter,
		TransactionID: row.TransactionID,
		ReminderID:    row.ReminderID,
		LendingID:     row.LendingID,
		Remark:        row.Remark,
		CreatedAt:     row.CreatedAt,
	}
}

func decodeBackupAccountLog(row backupAccountLog) model.AccountLog {
	return model.AccountLog{
		ID:            row.ID,
		UserID:        row.UserID,
		AccountID:     row.AccountID,
		Type:          row.Type,
		Amount:        row.Amount,
		BalanceBefore: row.BalanceBefore,
		BalanceAfter:  row.BalanceAfter,
		TransactionID: row.TransactionID,
		ReminderID:    row.ReminderID,
		LendingID:     row.LendingID,
		Remark:        row.Remark,
		CreatedAt:     row.CreatedAt,
	}
}

type backupNotificationLog struct {
	ID        string    `json:"id"`
	UserID    uint      `json:"user_id"`
	Type      string    `json:"type"`
	Title     string    `json:"title"`
	Content   string    `json:"content"`
	Channel   string    `json:"channel"`
	Status    string    `json:"status"`
	Error     string    `json:"error"`
	CreatedAt time.Time `json:"created_at"`
}

func encodeBackupNotificationLog(row model.NotificationLog) backupNotificationLog {
	return backupNotificationLog{
		ID:        row.ID,
		UserID:    row.UserID,
		Type:      row.Type,
		Title:     row.Title,
		Content:   row.Content,
		Channel:   row.Channel,
		Status:    row.Status,
		Error:     row.Error,
		CreatedAt: row.CreatedAt,
	}
}

func decodeBackupNotificationLog(row backupNotificationLog) model.NotificationLog {
	return model.NotificationLog{
		ID:        row.ID,
		UserID:    row.UserID,
		Type:      row.Type,
		Title:     row.Title,
		Content:   row.Content,
		Channel:   row.Channel,
		Status:    row.Status,
		Error:     row.Error,
		CreatedAt: row.CreatedAt,
	}
}
