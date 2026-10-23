package service

import (
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
)

type debtAccountEffect struct {
	Balance, Unplanned, Pending, Principal, Review money.Amount
}

func debtLogEffect(log model.AccountLog) debtAccountEffect {
	return debtAccountEffect{Balance: log.BalanceAfter.Sub(log.BalanceBefore), Unplanned: log.UnplannedDebtDelta,
		Pending: log.UnappliedDelta, Principal: log.PrincipalPaidDelta, Review: log.UnclassifiedDelta}
}

func (e debtAccountEffect) negate() debtAccountEffect {
	return debtAccountEffect{e.Balance.Negate(), e.Unplanned.Negate(), e.Pending.Negate(), e.Principal.Negate(), e.Review.Negate()}
}

func (e debtAccountEffect) valid() bool {
	return e.Balance.IsValid() && e.Unplanned.IsValid() && e.Pending.IsValid() && e.Principal.IsValid() && e.Review.IsValid()
}

func (e debtAccountEffect) equals(other debtAccountEffect) bool {
	return e.valid() && other.valid() && e.Balance.Cents() == other.Balance.Cents() &&
		e.Unplanned.Cents() == other.Unplanned.Cents() && e.Pending.Cents() == other.Pending.Cents() &&
		e.Principal.Cents() == other.Principal.Cents() && e.Review.Cents() == other.Review.Cents()
}

func expectedDebtEffects(op model.DebtOperation, parts []model.DebtAllocation,
	transactions []model.Transaction, accounts map[string]model.Account) (map[string]debtAccountEffect, error) {
	expected := make(map[string]debtAccountEffect)
	var principal, interest, cash money.Amount
	for _, part := range parts {
		if part.UserID != op.UserID || part.OperationID != op.ID || part.ReversalOf != nil {
			return nil, ErrDebtDependency
		}
		principal = principal.Add(part.PrincipalPaidDelta)
		interest = interest.Add(part.InterestPaidDelta)
		cash = cash.Add(part.CashInterest)
		if !principal.IsValid() || !interest.IsValid() || !cash.IsValid() {
			return nil, ErrDebtDependency
		}
		switch op.Kind {
		case "payment", "allocation":
			if part.PrincipalDelta.Cents() != part.PrincipalPaidDelta.Negate().Cents() ||
				part.InterestDelta.Cents() != part.InterestPaidDelta.Sub(part.CashInterest).Negate().Cents() ||
				!validDebtMoney(part.PrincipalPaidDelta) || !validDebtMoney(part.InterestPaidDelta) ||
				!validDebtMoney(part.CashInterest) || part.CashInterest > part.InterestPaidDelta {
				return nil, ErrDebtDependency
			}
		case "plan_open":
			if !validDebtMoney(part.PrincipalDelta) || !validDebtMoney(part.InterestDelta) ||
				part.PrincipalPaidDelta != 0 || part.InterestPaidDelta != 0 || part.CashInterest != 0 {
				return nil, ErrDebtDependency
			}
		case "interest_charge":
			if part.PrincipalDelta != 0 || part.InterestDelta != op.Amount ||
				part.PrincipalPaidDelta != 0 || part.InterestPaidDelta != 0 || part.CashInterest != 0 {
				return nil, ErrDebtDependency
			}
		default:
			return nil, ErrDebtDependency
		}
	}
	switch op.Kind {
	case "account_open":
		if op.AccountID == nil || len(parts) != 0 || op.Amount < 0 {
			return nil, ErrDebtDependency
		}
		expected[*op.AccountID] = debtAccountEffect{Balance: op.Amount, Unplanned: op.Amount}
	case "plan_open":
		if len(parts) != 1 {
			return nil, ErrDebtDependency
		}
		if op.AccountID != nil {
			expected[*op.AccountID] = debtAccountEffect{Unplanned: parts[0].PrincipalDelta.Add(parts[0].InterestDelta).Negate()}
		}
	case "interest_charge":
		if len(parts) != 1 || op.Amount <= 0 {
			return nil, ErrDebtDependency
		}
		if op.AccountID != nil {
			expected[*op.AccountID] = debtAccountEffect{Balance: op.Amount}
		}
	case "payment":
		total, sumErr := sumDebtMoney(principal, interest, op.UnplannedPayment, op.UnappliedAmount)
		if sumErr != nil || total.Cents() != op.Amount.Cents() || op.Amount <= 0 ||
			!validDebtMoney(op.UnplannedPayment) || !validDebtMoney(op.UnappliedAmount) {
			return nil, ErrDebtDependency
		}
		if op.SourceKind == "account" && op.SourceAccountID != nil {
			source, ok := accounts[*op.SourceAccountID]
			if !ok || source.UserID != op.UserID {
				return nil, ErrDebtDependency
			}
			delta := op.Amount.Negate()
			if IsDebtAccount(source.Type) {
				delta = op.Amount
			}
			effect := debtAccountEffect{Balance: delta}
			if source.DebtTrackingMode == model.DebtModeManaged {
				effect.Unplanned = delta
			}
			expected[source.ID] = effect
		} else if op.SourceKind != "external" || op.SourceAccountID != nil || cash != 0 {
			return nil, ErrDebtDependency
		}
		if op.AccountID != nil {
			if op.SourceAccountID != nil && *op.AccountID == *op.SourceAccountID {
				return nil, ErrDebtDependency
			}
			expected[*op.AccountID] = debtAccountEffect{Balance: op.Amount.Sub(cash).Negate(),
				Unplanned: op.UnplannedPayment.Negate(), Pending: op.UnappliedAmount, Principal: principal}
		}
	case "allocation":
		total, sumErr := sumDebtMoney(principal, interest, op.UnplannedPayment)
		if op.AccountID == nil || op.PaymentID == nil || cash != 0 ||
			sumErr != nil || total.Cents() != op.Amount.Cents() {
			return nil, ErrDebtDependency
		}
		expected[*op.AccountID] = debtAccountEffect{Unplanned: op.UnplannedPayment.Negate(),
			Pending: op.Amount.Negate(), Principal: principal}
	case "account_change", "transfer_payment":
		if len(parts) != 0 || len(transactions) != 1 || op.SourceTransactionID == nil ||
			transactions[0].ID != *op.SourceTransactionID {
			return nil, ErrDebtDependency
		}
		return managedTransactionEffects(transactions[0], accounts)
	default:
		return nil, ErrDebtDependency
	}
	return expected, nil
}

func validateDebtEffects(op model.DebtOperation, parts []model.DebtAllocation, logs []model.AccountLog,
	transactions []model.Transaction, accounts map[string]model.Account) error {
	expected, err := expectedDebtEffects(op, parts, transactions, accounts)
	if err != nil {
		return err
	}
	if len(logs) != len(expected) {
		return ErrDebtDependency
	}
	seen := make(map[string]bool)
	for _, log := range logs {
		want, ok := expected[log.AccountID]
		if !ok || seen[log.AccountID] || log.UserID != op.UserID || log.DebtOperationID == nil ||
			*log.DebtOperationID != op.ID || !debtLogEffect(log).equals(want) {
			return ErrDebtDependency
		}
		seen[log.AccountID] = true
	}
	return nil
}

func validateDebtOperationTx(tx *gorm.DB, op *model.DebtOperation) error {
	var parts []model.DebtAllocation
	var logs []model.AccountLog
	var transactions []model.Transaction
	if err := tx.Where("operation_id = ? AND user_id = ?", op.ID, op.UserID).Find(&parts).Error; err != nil {
		return err
	}
	if err := tx.Where("debt_operation_id = ? AND user_id = ?", op.ID, op.UserID).Find(&logs).Error; err != nil {
		return err
	}
	if err := tx.Unscoped().Where("debt_operation_id = ? AND user_id = ?", op.ID, op.UserID).Find(&transactions).Error; err != nil {
		return err
	}
	accounts := make(map[string]model.Account)
	for _, log := range logs {
		var account model.Account
		if err := tx.First(&account, "user_id = ? AND id = ?", op.UserID, log.AccountID).Error; err != nil {
			return ErrDebtDependency
		}
		accounts[account.ID] = account
	}
	if op.SourceAccountID != nil {
		var source model.Account
		if err := tx.First(&source, "id = ? AND user_id = ?", *op.SourceAccountID, op.UserID).Error; err != nil {
			return ErrDebtDependency
		}
		accounts[source.ID] = source
	}
	if err := validateDebtProjections(*op, parts, transactions); err != nil {
		return err
	}
	return validateDebtEffects(*op, parts, logs, transactions, accounts)
}
