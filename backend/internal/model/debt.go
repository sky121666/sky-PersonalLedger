package model

import (
	"time"

	"github.com/sky/personal-ledger/internal/money"
)

const (
	DebtModeLegacy  = "legacy"
	DebtModeManaged = "managed"
)

type DebtPlan struct {
	ID                string        `gorm:"primaryKey;size:36" json:"id"`
	UserID            uint          `gorm:"not null;index" json:"user_id"`
	AccountID         *string       `gorm:"size:36;index" json:"account_id"`
	Name              string        `gorm:"size:100;not null" json:"name"`
	OriginalPrincipal money.Amount  `gorm:"column:original_principal_cents;not null" json:"original_principal"`
	OpeningPrincipal  money.Amount  `gorm:"column:opening_principal_cents;not null" json:"opening_principal"`
	PrincipalBalance  money.Amount  `gorm:"column:principal_balance_cents;not null" json:"principal_balance"`
	InterestBalance   money.Amount  `gorm:"column:interest_balance_cents;not null;default:0" json:"interest_balance"`
	EstimatedInterest *money.Amount `gorm:"column:estimated_interest_cents" json:"estimated_interest"`
	PrincipalPaid     money.Amount  `gorm:"column:principal_paid_cents;not null;default:0" json:"principal_paid"`
	InterestPaid      money.Amount  `gorm:"column:interest_paid_cents;not null;default:0" json:"interest_paid"`
	Status            string        `gorm:"size:16;not null" json:"status"`
	Version           uint64        `gorm:"not null;default:0" json:"version"`
	CreatedAt         time.Time     `json:"created_at"`
	UpdatedAt         time.Time     `json:"updated_at"`
}

// DebtOperation retains the original target even if the surrounding UI changes.
// Financial payloads are immutable; reversal is a new operation with opposite effects.
type DebtOperation struct {
	ID                  string       `gorm:"primaryKey;size:36" json:"id"`
	UserID              uint         `gorm:"not null;index;uniqueIndex:idx_debt_request,priority:1" json:"user_id"`
	Kind                string       `gorm:"size:30;not null" json:"kind"`
	AccountID           *string      `gorm:"size:36;index" json:"account_id"`
	StandalonePlanID    *string      `gorm:"size:36;index" json:"standalone_plan_id"`
	SourceAccountID     *string      `gorm:"size:36" json:"source_account_id"`
	SourceKind          string       `gorm:"size:20;not null" json:"source_kind"`
	Amount              money.Amount `gorm:"column:amount_cents;not null;default:0" json:"amount"`
	UnplannedPayment    money.Amount `gorm:"column:unplanned_payment_cents;not null;default:0" json:"unplanned_payment"`
	UnappliedAmount     money.Amount `gorm:"column:unapplied_amount_cents;not null;default:0" json:"unapplied_amount"`
	PaymentID           *string      `gorm:"size:36;index" json:"payment_id"`
	SourceTransactionID *string      `gorm:"size:36;uniqueIndex" json:"source_transaction_id"`
	ReversalOf          *string      `gorm:"size:36;uniqueIndex" json:"reversal_of"`
	ReversedBy          *string      `gorm:"size:36" json:"reversed_by"`
	RequestKeyHash      *string      `gorm:"size:64;uniqueIndex:idx_debt_request,priority:2" json:"request_key_hash"`
	RequestHash         string       `gorm:"size:64" json:"request_hash"`
	OccurredAt          time.Time    `json:"occurred_at"`
	CreatedAt           time.Time    `json:"created_at"`
}

type DebtAllocation struct {
	ID                 string       `gorm:"primaryKey;size:36" json:"id"`
	UserID             uint         `gorm:"not null;index" json:"user_id"`
	OperationID        string       `gorm:"size:36;not null;index" json:"operation_id"`
	PlanID             string       `gorm:"size:36;not null;index" json:"plan_id"`
	PrincipalDelta     money.Amount `gorm:"column:principal_delta_cents;not null;default:0" json:"principal_delta"`
	InterestDelta      money.Amount `gorm:"column:interest_delta_cents;not null;default:0" json:"interest_delta"`
	PrincipalPaidDelta money.Amount `gorm:"column:principal_paid_delta_cents;not null;default:0" json:"principal_paid_delta"`
	InterestPaidDelta  money.Amount `gorm:"column:interest_paid_delta_cents;not null;default:0" json:"interest_paid_delta"`
	CashInterest       money.Amount `gorm:"column:cash_interest_cents;not null;default:0" json:"cash_interest"`
	ReversalOf         *string      `gorm:"size:36;uniqueIndex" json:"reversal_of"`
	CreatedAt          time.Time    `json:"created_at"`
}
