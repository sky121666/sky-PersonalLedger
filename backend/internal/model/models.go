package model

import (
	"time"

	"gorm.io/gorm"
)

type User struct {
	ID             uint           `gorm:"primaryKey" json:"id"`
	Username       string         `gorm:"size:50;uniqueIndex;not null" json:"username"`
	PasswordHash   string         `gorm:"size:255;not null" json:"-"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	LastLoginAt    *time.Time     `json:"last_login_at"`
	LoginFailCount int            `gorm:"default:0" json:"-"`
	LockedUntil    *time.Time     `json:"-"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`
}

type Account struct {
	ID             string         `gorm:"primaryKey;size:36" json:"id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	Name           string         `gorm:"size:100;not null" json:"name"`
	Type           string         `gorm:"size:20;not null" json:"type"`
	Icon           string         `gorm:"size:100" json:"icon"`
	Color          string         `gorm:"size:20" json:"color"`
	InitialBalance float64        `gorm:"type:decimal(15,2);default:0" json:"initial_balance"`
	CurrentBalance float64        `gorm:"type:decimal(15,2);default:0" json:"current_balance"`
	PaymentDay     *int           `json:"payment_day"`
	BillingDay     *int           `json:"billing_day"`
	CreditLimit    *float64       `gorm:"type:decimal(15,2)" json:"credit_limit"`
	InterestRate   *float64       `gorm:"type:decimal(5,2)" json:"interest_rate"`
	TotalPaid      float64        `gorm:"type:decimal(15,2);default:0" json:"total_paid"`
	StartDate      *time.Time     `json:"start_date"`
	TargetDate     *time.Time     `json:"target_date"`
	PaidOffAt      *time.Time     `json:"paid_off_at"`
	Remark         string         `gorm:"type:text" json:"remark"`
	IsArchived     bool           `gorm:"default:false" json:"is_archived"`
	SortOrder      int            `gorm:"default:0" json:"sort_order"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`
}

type Category struct {
	ID        string         `gorm:"primaryKey;size:36" json:"id"`
	UserID    uint           `gorm:"not null;index" json:"user_id"`
	Name      string         `gorm:"size:100;not null" json:"name"`
	Type      string         `gorm:"size:20;not null" json:"type"` // income / expense
	Icon      string         `gorm:"size:50" json:"icon"`
	Color     string         `gorm:"size:20" json:"color"`
	IsSystem  bool           `gorm:"default:false" json:"is_system"`
	SortOrder int            `gorm:"default:0" json:"sort_order"`
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

type Transaction struct {
	ID              string         `gorm:"primaryKey;size:36" json:"id"`
	UserID          uint           `gorm:"not null;index" json:"user_id"`
	AccountID       string         `gorm:"size:36;not null;index" json:"account_id"`
	CategoryID      *string        `gorm:"size:36;index" json:"category_id"`
	Type            string         `gorm:"size:20;not null" json:"type"` // income / expense / transfer
	Amount          float64        `gorm:"type:decimal(15,2);not null" json:"amount"`
	TransactionDate time.Time      `gorm:"not null;index" json:"transaction_date"`
	Remark          string         `gorm:"type:text" json:"remark"`
	Images          string         `gorm:"type:text" json:"images"` // JSON array
	ToAccountID     *string        `gorm:"size:36" json:"to_account_id"`
	Source          string         `gorm:"size:50;default:manual" json:"source"`
	ReminderID      *string        `gorm:"size:36;index" json:"reminder_id,omitempty"`
	LendingID       *string        `gorm:"size:36;index" json:"lending_id,omitempty"`
	CreatedAt       time.Time      `json:"created_at"`
	UpdatedAt       time.Time      `json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`

	Account   *Account  `gorm:"foreignKey:AccountID" json:"account,omitempty"`
	ToAccount *Account  `gorm:"foreignKey:ToAccountID" json:"to_account,omitempty"`
	Category  *Category `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
}

type Budget struct {
	ID             string         `gorm:"primaryKey;size:36" json:"id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	CategoryID     *string        `gorm:"size:36;index" json:"category_id"` // nil = total budget
	Amount         float64        `gorm:"type:decimal(15,2);not null" json:"amount"`
	Period         string         `gorm:"size:20;default:monthly" json:"period"`
	AlertThreshold int            `gorm:"default:80" json:"alert_threshold"`
	IsActive       bool           `gorm:"default:true" json:"is_active"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	Category *Category `gorm:"foreignKey:CategoryID" json:"category,omitempty"`
}

type Reminder struct {
	ID             string         `gorm:"primaryKey;size:36" json:"id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	Name           string         `gorm:"size:100" json:"name"`
	AccountID      *string        `gorm:"size:36" json:"account_id"`
	LoanType       string         `gorm:"size:30;default:other" json:"loan_type"`
	PaymentDay     int            `gorm:"not null" json:"payment_day"`
	BillingDay     *int           `json:"billing_day"`
	AdvanceDays    int            `gorm:"default:3" json:"advance_days"`
	Amount         *float64       `gorm:"type:decimal(15,2)" json:"amount"`
	Principal      *float64       `gorm:"type:decimal(15,2)" json:"principal"`
	CurrentBalance *float64       `gorm:"type:decimal(15,2)" json:"current_balance"`
	InterestRate   *float64       `gorm:"type:decimal(5,2)" json:"interest_rate"`
	TotalInterest  *float64       `gorm:"type:decimal(15,2)" json:"total_interest"`
	TotalPaid      float64        `gorm:"type:decimal(15,2);default:0" json:"total_paid"`
	InterestPaid   float64        `gorm:"type:decimal(15,2);default:0" json:"interest_paid"`
	StartDate      *time.Time     `json:"start_date"`
	TargetDate     *time.Time     `json:"target_date"`
	PaidOffAt      *time.Time     `json:"paid_off_at"`
	Color          string         `gorm:"size:20" json:"color"`
	Remark         string         `gorm:"type:text" json:"remark"`
	IsEnabled      bool           `gorm:"default:true" json:"is_enabled"`
	LastNotifiedAt *time.Time     `json:"last_notified_at"`
	Evidence       string         `gorm:"type:text" json:"evidence"` // JSON array of file paths
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	Account *Account `gorm:"foreignKey:AccountID" json:"account,omitempty"`
}

type RefreshToken struct {
	ID        string    `gorm:"primaryKey;size:36" json:"id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	Token     string    `gorm:"size:255;uniqueIndex;not null" json:"-"`
	ExpiresAt time.Time `gorm:"not null" json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

type QuickTemplate struct {
	ID         string         `gorm:"primaryKey;size:36" json:"id"`
	UserID     uint           `gorm:"not null;index" json:"user_id"`
	Name       string         `gorm:"size:100;not null" json:"name"`
	Type       string         `gorm:"size:20;not null" json:"type"`
	Amount     float64        `gorm:"type:decimal(15,2)" json:"amount"`
	AccountID  string         `gorm:"size:36" json:"account_id"`
	CategoryID *string        `gorm:"size:36" json:"category_id"`
	Remark     string         `gorm:"type:text" json:"remark"`
	UsedCount  int            `gorm:"default:0" json:"used_count"`
	LastUsedAt *time.Time     `json:"last_used_at"`
	CreatedAt  time.Time      `json:"created_at"`
	UpdatedAt  time.Time      `json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}

// SystemSetting stores system-wide settings like security entry path
type SystemSetting struct {
	ID        uint      `gorm:"primaryKey" json:"id"`
	Key       string    `gorm:"size:50;uniqueIndex;not null" json:"key"`
	Value     string    `gorm:"type:text" json:"value"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type NotificationSetting struct {
	ID      uint `gorm:"primaryKey" json:"id"`
	UserID  uint `gorm:"uniqueIndex;not null" json:"user_id"`
	Enabled bool `gorm:"default:false" json:"enabled"`

	// 企业微信
	WecomEnabled bool   `gorm:"default:false" json:"wecom_enabled"`
	WecomWebhook string `gorm:"size:500" json:"wecom_webhook"`

	// 钉钉
	DingtalkEnabled bool   `gorm:"default:false" json:"dingtalk_enabled"`
	DingtalkWebhook string `gorm:"size:500" json:"dingtalk_webhook"`
	DingtalkSecret  string `gorm:"size:100" json:"dingtalk_secret"`

	// 邮箱
	EmailEnabled bool   `gorm:"default:false" json:"email_enabled"`
	SmtpHost     string `gorm:"size:100" json:"smtp_host"`
	SmtpPort     int    `gorm:"default:587" json:"smtp_port"`
	SmtpUser     string `gorm:"size:100" json:"smtp_user"`
	SmtpPassword string `gorm:"size:200" json:"-"`
	SmtpFrom     string `gorm:"size:100" json:"smtp_from"`
	EmailTo      string `gorm:"size:200" json:"email_to"`

	// 自定义Webhook
	WebhookEnabled bool   `gorm:"default:false" json:"webhook_enabled"`
	WebhookURL     string `gorm:"size:500" json:"webhook_url"`
	WebhookSecret  string `gorm:"size:100" json:"webhook_secret"`

	// 通知选项
	NotifyPaymentDue   bool `gorm:"default:true" json:"notify_payment_due"`
	NotifyBudgetAlert  bool `gorm:"default:true" json:"notify_budget_alert"`
	NotifyLendingDue   bool `gorm:"default:true" json:"notify_lending_due"`
	NotifyLogin        bool `gorm:"default:true" json:"notify_login"`
	NotifyAnnualReport bool `gorm:"default:true" json:"notify_annual_report"`
	AdvanceDays        int  `gorm:"default:3" json:"advance_days"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Lending struct {
	ID             string         `gorm:"primaryKey;size:36" json:"id"`
	UserID         uint           `gorm:"not null;index" json:"user_id"`
	Type           string         `gorm:"size:20;not null;index" json:"type"`
	ContactName    string         `gorm:"size:100;not null" json:"contact_name"`
	ContactPhone   string         `gorm:"size:50" json:"contact_phone"`
	ContactRemark  string         `gorm:"type:text" json:"contact_remark"`
	Principal      float64        `gorm:"type:decimal(15,2);not null" json:"principal"`
	InterestRate   *float64       `gorm:"type:decimal(5,2)" json:"interest_rate"`
	CurrentBalance float64        `gorm:"type:decimal(15,2);not null" json:"current_balance"`
	TotalRepaid    float64        `gorm:"type:decimal(15,2);default:0" json:"total_repaid"`
	LendDate       time.Time      `gorm:"not null;index" json:"lend_date"`
	DueDate        *time.Time     `json:"due_date"`
	SettledAt      *time.Time     `json:"settled_at"`
	AccountID      *string        `gorm:"size:36" json:"account_id"`
	Remark         string         `gorm:"type:text" json:"remark"`
	Evidence       string         `gorm:"type:text" json:"evidence"`
	IsSettled      bool           `gorm:"default:false;index" json:"is_settled"`
	CreatedAt      time.Time      `json:"created_at"`
	UpdatedAt      time.Time      `json:"updated_at"`
	DeletedAt      gorm.DeletedAt `gorm:"index" json:"-"`

	Account *Account `gorm:"foreignKey:AccountID" json:"account,omitempty"`
}

type LendingRecord struct {
	ID            string         `gorm:"primaryKey;size:36" json:"id"`
	LendingID     string         `gorm:"size:36;not null;index" json:"lending_id"`
	UserID        uint           `gorm:"not null;index" json:"user_id"`
	Type          string         `gorm:"size:20;not null" json:"type"`
	Amount        float64        `gorm:"type:decimal(15,2);not null" json:"amount"`
	RecordDate    time.Time      `gorm:"not null;index" json:"record_date"`
	AccountID     *string        `gorm:"size:36" json:"account_id"`
	TransactionID *string        `gorm:"size:36" json:"transaction_id"`
	Remark        string         `gorm:"type:text" json:"remark"`
	Evidence      string         `gorm:"type:text" json:"evidence"`
	CreatedAt     time.Time      `json:"created_at"`
	UpdatedAt     time.Time      `json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`

	Lending     *Lending     `gorm:"foreignKey:LendingID" json:"lending,omitempty"`
	Account     *Account     `gorm:"foreignKey:AccountID" json:"account,omitempty"`
	Transaction *Transaction `gorm:"foreignKey:TransactionID" json:"transaction,omitempty"`
}

// NotificationLog stores sent notification history
type NotificationLog struct {
	ID        string    `gorm:"primaryKey;size:36" json:"id"`
	UserID    uint      `gorm:"not null;index" json:"user_id"`
	Type      string    `gorm:"size:50;not null;index" json:"type"` // payment_due, lending_due, login, annual_report, budget_alert
	Title     string    `gorm:"size:200" json:"title"`
	Content   string    `gorm:"type:text" json:"content"`
	Channel   string    `gorm:"size:50" json:"channel"`             // wecom, dingtalk, email, webhook
	Status    string    `gorm:"size:20;default:sent" json:"status"` // sent, failed
	Error     string    `gorm:"type:text" json:"error"`
	CreatedAt time.Time `gorm:"index" json:"created_at"`
}
