package service

import (
	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func (s *DebtService) Reverse(userID uint, operationID string, req DebtReverseRequest) (*model.DebtOperation, error) {
	return s.write(userID, "reversal", operationID, req.IdempotencyKey, req, func(tx *gorm.DB, reversal *model.DebtOperation) error {
		var original model.DebtOperation
		if err := tx.First(&original, "id = ? AND user_id = ?", operationID, userID).Error; err != nil {
			return ErrDebtNotFound
		}
		_, err := reverseDebtOperationTx(tx, &original, reversal)
		return err
	})
}

func reverseDebtOperationTx(tx *gorm.DB, original *model.DebtOperation, reversal *model.DebtOperation) (*model.DebtOperation, error) {
	if _, err := getAccountsForUserTx(tx, original.UserID, original.AccountID, original.SourceAccountID); err != nil {
		return nil, err
	}
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		First(original, "id = ? AND user_id = ?", original.ID, original.UserID).Error; err != nil {
		return nil, err
	}
	if original.ReversedBy != nil || original.Kind == "reversal" || original.Kind == "account_open" {
		return nil, ErrDebtDependency
	}
	if err := checkOperationAccountsStateTx(tx, original, true); err != nil {
		return nil, err
	}
	if err := validateDebtOperationTx(tx, original); err != nil {
		return nil, err
	}
	if original.Kind == "payment" || original.Kind == "transfer_payment" {
		var children []model.DebtOperation
		if err := tx.Where("user_id = ? AND payment_id = ? AND kind = ? AND reversed_by IS NULL",
			original.UserID, original.ID, "allocation").Order("created_at DESC, id DESC").Find(&children).Error; err != nil {
			return nil, err
		}
		for i := range children {
			if _, err := reverseDebtOperationTx(tx, &children[i], nil); err != nil {
				return nil, err
			}
		}
	}
	var effects []model.DebtAllocation
	if err := tx.Where("user_id = ? AND operation_id = ?", original.UserID, original.ID).
		Order("plan_id, id").Find(&effects).Error; err != nil {
		return nil, err
	}
	if original.Kind == "plan_open" {
		for _, effect := range effects {
			var plan model.DebtPlan
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				First(&plan, "id = ? AND user_id = ?", effect.PlanID, original.UserID).Error; err != nil {
				return nil, err
			}
			var dependencies int64
			if err := tx.Table("debt_allocations AS a").
				Joins("JOIN debt_operations AS o ON o.id = a.operation_id AND o.user_id = a.user_id").
				Where("a.user_id = ? AND a.plan_id = ? AND o.id <> ? AND o.kind <> ? AND o.reversed_by IS NULL",
					original.UserID, effect.PlanID, original.ID, "reversal").Count(&dependencies).Error; err != nil {
				return nil, err
			}
			if dependencies != 0 {
				return nil, ErrDebtDependency
			}
		}
	}
	if reversal == nil {
		reversal = &model.DebtOperation{ID: uuid.NewString(), UserID: original.UserID, Kind: "reversal"}
	}
	reversal.AccountID, reversal.StandalonePlanID = original.AccountID, original.StandalonePlanID
	reversal.SourceAccountID, reversal.SourceKind = original.SourceAccountID, "reversal"
	reversal.Amount, reversal.PaymentID, reversal.ReversalOf = original.Amount, original.PaymentID, &original.ID
	// Corrections remove the original effective transaction from its period;
	// CreatedAt retains the time the correction was actually recorded.
	reversal.OccurredAt = original.OccurredAt
	if err := tx.Save(reversal).Error; err != nil {
		return nil, err
	}
	for _, effect := range effects {
		if err := applyDebtAllocationTx(tx, reversal, model.DebtAllocation{
			PlanID: effect.PlanID, PrincipalDelta: effect.PrincipalDelta.Negate(), InterestDelta: effect.InterestDelta.Negate(),
			PrincipalPaidDelta: effect.PrincipalPaidDelta.Negate(), InterestPaidDelta: effect.InterestPaidDelta.Negate(),
			CashInterest: effect.CashInterest.Negate(), ReversalOf: &effect.ID,
		}); err != nil {
			return nil, err
		}
		if original.Kind == "plan_open" {
			result := tx.Model(&model.DebtPlan{}).Where(
				"id = ? AND user_id = ? AND principal_balance_cents = 0 AND interest_balance_cents = 0 AND principal_paid_cents = 0 AND interest_paid_cents = 0",
				effect.PlanID, original.UserID).Update("status", "cancelled")
			if result.Error != nil {
				return nil, result.Error
			}
			if result.RowsAffected != 1 {
				return nil, ErrDebtDependency
			}
		}
	}
	var logs []model.AccountLog
	if err := tx.Where("user_id = ? AND debt_operation_id = ?", original.UserID, original.ID).
		Order("account_id, created_at DESC, id DESC").Find(&logs).Error; err != nil {
		return nil, err
	}
	if original.SourceAccountID != nil && len(logs) == 0 {
		return nil, ErrDebtDependency
	}
	for _, log := range logs {
		if err := mutateDebtAccountEffectTx(tx, reversal, log.AccountID, debtLogEffect(log).negate(),
			"reversal", log.TransactionID); err != nil {
			return nil, err
		}
	}
	if err := tx.Where("user_id = ? AND debt_operation_id = ?", original.UserID, original.ID).
		Delete(&model.Transaction{}).Error; err != nil {
		return nil, err
	}
	result := tx.Model(&model.DebtOperation{}).Where("id = ? AND user_id = ? AND reversed_by IS NULL", original.ID, original.UserID).
		Update("reversed_by", reversal.ID)
	if result.Error != nil {
		return nil, result.Error
	}
	if result.RowsAffected != 1 {
		return nil, ErrDebtDependency
	}
	if err := checkOperationAccountsStateTx(tx, original, true); err != nil {
		return nil, err
	}
	return reversal, nil
}
