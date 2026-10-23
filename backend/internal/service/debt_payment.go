package service

import (
	"fmt"
	"sort"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type DebtPaymentPart struct {
	PlanID         string       `json:"plan_id" binding:"required"`
	Principal      money.Amount `json:"principal"`
	BookedInterest money.Amount `json:"booked_interest"`
	CashInterest   money.Amount `json:"cash_interest"`
}

type DebtPaymentRequest struct {
	AccountID        *string           `json:"account_id"`
	StandalonePlanID *string           `json:"standalone_plan_id"`
	SourceKind       string            `json:"source_kind" binding:"required,oneof=account external"`
	SourceAccountID  *string           `json:"source_account_id"`
	Amount           money.Amount      `json:"amount" binding:"required,gt=0"`
	Allocations      []DebtPaymentPart `json:"allocations"`
	UnplannedAmount  money.Amount      `json:"unplanned_amount"`
	UnappliedAmount  money.Amount      `json:"unapplied_amount"`
	OccurredAt       string            `json:"occurred_at"`
	IdempotencyKey   string            `json:"idempotency_key" binding:"required,max=128"`
}

type DebtAllocateRequest struct {
	Allocations        []DebtPaymentPart `json:"allocations"`
	UnplannedAmount    money.Amount      `json:"unplanned_amount"`
	ReplaceOperationID string            `json:"replace_operation_id"`
	IdempotencyKey     string            `json:"idempotency_key" binding:"required,max=128"`
}

func normalizeDebtParts(parts []DebtPaymentPart, allowCashInterest bool) ([]DebtPaymentPart, money.Amount, money.Amount, error) {
	copyParts := append([]DebtPaymentPart{}, parts...)
	sort.Slice(copyParts, func(i, j int) bool { return copyParts[i].PlanID < copyParts[j].PlanID })
	var total, cashInterest money.Amount
	for i, part := range copyParts {
		if part.PlanID == "" || (i > 0 && copyParts[i-1].PlanID == part.PlanID) ||
			!validDebtMoney(part.Principal) || !validDebtMoney(part.BookedInterest) || !validDebtMoney(part.CashInterest) ||
			(!allowCashInterest && part.CashInterest != 0) {
			return nil, 0, 0, ErrInvalidDebtRequest
		}
		amount, err := sumDebtMoney(part.Principal, part.BookedInterest, part.CashInterest)
		if err != nil || amount <= 0 {
			return nil, 0, 0, ErrInvalidDebtRequest
		}
		total, cashInterest = total.Add(amount), cashInterest.Add(part.CashInterest)
		if !total.IsValid() || !cashInterest.IsValid() {
			return nil, 0, 0, ErrInvalidDebtRequest
		}
	}
	if !total.IsValid() || !cashInterest.IsValid() {
		return nil, 0, 0, ErrInvalidDebtRequest
	}
	return copyParts, total, cashInterest, nil
}

func (s *DebtService) Pay(userID uint, req DebtPaymentRequest) (*model.DebtOperation, error) {
	parts, assigned, cashInterest, err := normalizeDebtParts(req.Allocations, true)
	if err != nil {
		return nil, err
	}
	req.Allocations = parts
	req.AccountID, req.StandalonePlanID = normalizeOptionalString(req.AccountID), normalizeOptionalString(req.StandalonePlanID)
	req.SourceAccountID = normalizeOptionalString(req.SourceAccountID)
	if req.SourceKind == "external" && cashInterest > 0 {
		return nil, fmt.Errorf("%w：当次利息费用需要指定真实付款账户，外部来源暂不支持", ErrInvalidDebtRequest)
	}
	total, totalErr := sumDebtMoney(assigned, req.UnplannedAmount, req.UnappliedAmount)
	if !validDebtMoney(req.Amount) || req.Amount <= 0 || !validDebtMoney(req.UnplannedAmount) ||
		!validDebtMoney(req.UnappliedAmount) || totalErr != nil || total.Cents() != req.Amount.Cents() ||
		(req.AccountID == nil) == (req.StandalonePlanID == nil) ||
		(req.SourceKind != "account" && req.SourceKind != "external") ||
		(req.SourceKind == "account") != (req.SourceAccountID != nil) ||
		(req.StandalonePlanID != nil && (req.UnplannedAmount != 0 || req.UnappliedAmount != 0 ||
			len(parts) != 1 || parts[0].PlanID != *req.StandalonePlanID)) {
		return nil, ErrInvalidDebtRequest
	}
	at, err := debtTime(req.OccurredAt)
	if err != nil {
		return nil, ErrInvalidDebtRequest
	}
	return s.write(userID, "payment", optionalDebtID(req.AccountID)+optionalDebtID(req.StandalonePlanID), req.IdempotencyKey, req,
		func(tx *gorm.DB, op *model.DebtOperation) error {
			op.AccountID, op.StandalonePlanID, op.SourceAccountID = req.AccountID, req.StandalonePlanID, req.SourceAccountID
			op.SourceKind, op.Amount, op.OccurredAt = req.SourceKind, req.Amount, at
			op.UnappliedAmount, op.UnplannedPayment = req.UnappliedAmount, req.UnplannedAmount
			if op.AccountID != nil && op.SourceAccountID != nil && *op.AccountID == *op.SourceAccountID {
				return ErrSameAccount
			}
			if _, err := getAccountsForUserTx(tx, userID, op.AccountID, op.SourceAccountID); err != nil {
				return err
			}
			if err := checkOperationAccountsTx(tx, op); err != nil {
				return err
			}
			reduction := req.Amount.Sub(cashInterest)
			if req.AccountID != nil {
				account, err := debtAccountTx(tx, userID, *req.AccountID)
				if err != nil {
					return err
				}
				if account.DebtTrackingMode != model.DebtModeManaged {
					return ErrManagedDebt
				}
				if reduction > 0 && reduction > account.CurrentBalance {
					return ErrInvalidDebtRequest
				}
			}
			var principal money.Amount
			for _, part := range parts {
				if err := applyDebtAllocationTx(tx, op, model.DebtAllocation{
					PlanID: part.PlanID, PrincipalDelta: part.Principal.Negate(), InterestDelta: part.BookedInterest.Negate(),
					PrincipalPaidDelta: part.Principal, InterestPaidDelta: part.BookedInterest.Add(part.CashInterest),
					CashInterest: part.CashInterest,
				}); err != nil {
					return err
				}
				principal = principal.Add(part.Principal)
			}
			sourceTx, debtTx, err := createDebtPaymentProjectionsTx(tx, op, reduction, cashInterest)
			if err != nil {
				return err
			}
			if op.SourceAccountID != nil {
				delta, err := accountBalanceDeltaTx(tx, userID, *op.SourceAccountID, req.Amount.Negate())
				if err != nil {
					return err
				}
				source, err := debtAccountTx(tx, userID, *op.SourceAccountID)
				if err != nil {
					return err
				}
				var unplanned money.Amount
				if source.DebtTrackingMode == model.DebtModeManaged {
					unplanned = delta
				}
				if err := mutateDebtAccountTx(tx, op, source.ID, delta, unplanned, 0, 0, "source", sourceTx); err != nil {
					return err
				}
			}
			if op.AccountID != nil {
				if err := mutateDebtAccountTx(tx, op, *op.AccountID, reduction.Negate(), req.UnplannedAmount.Negate(),
					req.UnappliedAmount, principal, "debt", debtTx); err != nil {
					return err
				}
			}
			return checkOperationAccountsTx(tx, op)
		})
}

func (s *DebtService) Allocate(userID uint, paymentID string, req DebtAllocateRequest) (*model.DebtOperation, error) {
	parts, assigned, _, err := normalizeDebtParts(req.Allocations, false)
	if err != nil {
		return nil, err
	}
	req.Allocations = parts
	amount := assigned.Add(req.UnplannedAmount)
	if !validDebtMoney(req.UnplannedAmount) || !amount.IsValid() || amount <= 0 {
		return nil, ErrInvalidDebtRequest
	}
	return s.write(userID, "allocation", paymentID, req.IdempotencyKey, req, func(tx *gorm.DB, op *model.DebtOperation) error {
		var payment model.DebtOperation
		if err := tx.First(&payment, "id = ? AND user_id = ?", paymentID, userID).Error; err != nil {
			return ErrDebtNotFound
		}
		if payment.AccountID == nil {
			return ErrDebtDependency
		}
		op.AccountID, op.SourceKind, op.PaymentID = payment.AccountID, "allocation", &payment.ID
		op.Amount, op.UnplannedPayment = amount, req.UnplannedAmount
		op.OccurredAt = payment.OccurredAt
		if _, err := debtAccountTx(tx, userID, *op.AccountID); err != nil {
			return err
		}
		// The first read locates the account; only the locked read authorizes
		// allocation against the payment's current state.
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&payment, "id = ? AND user_id = ?", paymentID, userID).Error; err != nil {
			return ErrDebtNotFound
		}
		if payment.ReversedBy != nil || (payment.Kind != "payment" && payment.Kind != "transfer_payment") ||
			payment.AccountID == nil || *payment.AccountID != *op.AccountID {
			return ErrDebtDependency
		}
		if err := checkDebtAccountTx(tx, userID, *op.AccountID); err != nil {
			return err
		}
		if req.ReplaceOperationID != "" {
			var prior model.DebtOperation
			if err := tx.First(&prior, "id = ? AND user_id = ?", req.ReplaceOperationID, userID).Error; err != nil {
				return ErrDebtNotFound
			}
			if prior.Kind != "allocation" || prior.PaymentID == nil || *prior.PaymentID != payment.ID || prior.ReversedBy != nil {
				return ErrDebtDependency
			}
			if _, err := reverseDebtOperationTx(tx, &prior, nil); err != nil {
				return err
			}
		}
		var children []model.DebtOperation
		if err := tx.Where("user_id = ? AND payment_id = ? AND kind = ? AND reversed_by IS NULL",
			userID, paymentID, "allocation").Find(&children).Error; err != nil {
			return err
		}
		remaining := payment.UnappliedAmount
		for _, child := range children {
			if child.ID != op.ID {
				remaining = remaining.Sub(child.Amount)
			}
		}
		if amount > remaining {
			return ErrInvalidDebtRequest
		}
		var principal money.Amount
		for _, part := range parts {
			if err := applyDebtAllocationTx(tx, op, model.DebtAllocation{PlanID: part.PlanID,
				PrincipalDelta: part.Principal.Negate(), InterestDelta: part.BookedInterest.Negate(),
				PrincipalPaidDelta: part.Principal, InterestPaidDelta: part.BookedInterest}); err != nil {
				return err
			}
			principal = principal.Add(part.Principal)
		}
		if err := mutateDebtAccountTx(tx, op, *op.AccountID, 0, req.UnplannedAmount.Negate(), amount.Negate(),
			principal, "allocation", nil); err != nil {
			return err
		}
		return checkOperationAccountsTx(tx, op)
	})
}

func (s *DebtService) BookInterest(userID uint, planID string, req DebtInterestRequest) (*model.DebtOperation, error) {
	if !validDebtMoney(req.Amount) || req.Amount <= 0 {
		return nil, ErrInvalidDebtRequest
	}
	at, err := debtTime(req.OccurredAt)
	if err != nil {
		return nil, ErrInvalidDebtRequest
	}
	return s.write(userID, "interest_charge", planID, req.IdempotencyKey, req, func(tx *gorm.DB, op *model.DebtOperation) error {
		var plan model.DebtPlan
		if err := tx.First(&plan, "id = ? AND user_id = ?", planID, userID).Error; err != nil {
			return ErrDebtNotFound
		}
		op.AccountID, op.Amount, op.SourceKind, op.OccurredAt = plan.AccountID, req.Amount, "booking", at
		if plan.AccountID == nil {
			op.StandalonePlanID = &plan.ID
		}
		if err := checkOperationAccountsTx(tx, op); err != nil {
			return err
		}
		if err := applyDebtAllocationTx(tx, op, model.DebtAllocation{PlanID: planID, InterestDelta: req.Amount}); err != nil {
			return err
		}
		if op.AccountID != nil {
			id, err := createDebtProjectionTx(tx, op, *op.AccountID, nil, "expense", "debt_interest", req.Amount)
			if err != nil {
				return err
			}
			if err := mutateDebtAccountTx(tx, op, *op.AccountID, req.Amount, 0, 0, 0, "interest", id); err != nil {
				return err
			}
		}
		return checkOperationAccountsTx(tx, op)
	})
}

func createDebtPaymentProjectionsTx(tx *gorm.DB, op *model.DebtOperation, reduction, cashInterest money.Amount) (*string, *string, error) {
	if op.SourceAccountID == nil {
		return nil, nil, nil
	}
	var sourceID, debtID *string
	var err error
	if op.AccountID != nil {
		if reduction > 0 {
			sourceID, err = createDebtProjectionTx(tx, op, *op.SourceAccountID, op.AccountID, "transfer", "debt_payment", reduction)
			debtID = sourceID
		}
	} else {
		var principal money.Amount
		var rows []model.DebtAllocation
		if err = tx.Where("operation_id = ?", op.ID).Find(&rows).Error; err == nil {
			for _, row := range rows {
				principal = principal.Add(row.PrincipalPaidDelta)
			}
			if principal > 0 {
				sourceID, err = createDebtProjectionTx(tx, op, *op.SourceAccountID, nil, "expense", "debt_principal", principal)
			}
			cashInterest = op.Amount.Sub(principal)
		}
	}
	if err != nil {
		return nil, nil, err
	}
	if cashInterest > 0 {
		interestID, err := createDebtProjectionTx(tx, op, *op.SourceAccountID, nil, "expense", "debt_interest", cashInterest)
		if err != nil {
			return nil, nil, err
		}
		if sourceID == nil {
			sourceID = interestID
		}
	}
	return sourceID, debtID, nil
}

func createDebtProjectionTx(tx *gorm.DB, op *model.DebtOperation, accountID string, target *string,
	kind, source string, amount money.Amount) (*string, error) {
	row := model.Transaction{ID: uuid.NewString(), UserID: op.UserID, AccountID: accountID, ToAccountID: target,
		Type: kind, Amount: amount, TransactionDate: op.OccurredAt, Source: source, DebtOperationID: &op.ID,
		Remark: "分期: " + op.Kind}
	if source == "debt_interest" {
		var category model.Category
		if err := tx.Where("user_id = ? AND type = ? AND name = ?", op.UserID, "expense", "利息").
			Attrs(model.Category{ID: uuid.NewString(), UserID: op.UserID, Type: "expense", Name: "利息"}).
			FirstOrCreate(&category).Error; err != nil {
			return nil, err
		}
		row.CategoryID = &category.ID
	}
	if err := tx.Create(&row).Error; err != nil {
		return nil, err
	}
	return &row.ID, nil
}
