package service

import (
	"sort"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
)

func managedTransactionEffects(row model.Transaction, accounts map[string]model.Account) (map[string]debtAccountEffect, error) {
	cashDeltas := make(map[string]money.Amount)
	switch row.Type {
	case "expense":
		cashDeltas[row.AccountID] = row.Amount.Negate()
	case "income":
		cashDeltas[row.AccountID] = row.Amount
	case "transfer":
		if row.ToAccountID == nil || *row.ToAccountID == row.AccountID {
			return nil, ErrInvalidDebtRequest
		}
		cashDeltas[row.AccountID], cashDeltas[*row.ToAccountID] = row.Amount.Negate(), row.Amount
	default:
		return nil, ErrInvalidDebtRequest
	}
	effects := make(map[string]debtAccountEffect)
	for id, delta := range cashDeltas {
		account, ok := accounts[id]
		if !ok || account.UserID != row.UserID {
			return nil, ErrDebtNotFound
		}
		if IsDebtAccount(account.Type) {
			delta = delta.Negate()
		}
		effect := debtAccountEffect{Balance: delta}
		if account.DebtTrackingMode == model.DebtModeManaged {
			switch {
			case row.Type == "transfer" && row.ToAccountID != nil && id == *row.ToAccountID:
				effect.Pending = row.Amount
			case delta > 0:
				effect.Unplanned = delta
			default:
				// A credit/refund without a plan reference is a real balance
				// change, but is not evidence of principal repayment.
				effect.Review = delta
			}
		}
		effects[id] = effect
	}
	return effects, nil
}

func applyManagedTransactionTx(tx *gorm.DB, row *model.Transaction) (bool, error) {
	accounts := make(map[string]model.Account)
	managed := false
	for _, id := range balanceAccountIDs(row) {
		account, err := debtAccountTx(tx, row.UserID, id)
		if err != nil {
			return false, err
		}
		accounts[id] = *account
		managed = managed || account.DebtTrackingMode == model.DebtModeManaged
	}
	if !managed {
		return false, nil
	}
	if row.DebtOperationID != nil {
		return true, ErrManagedTransactionImmutable
	}
	op := model.DebtOperation{ID: uuid.NewString(), UserID: row.UserID, Kind: "account_change",
		SourceAccountID: &row.AccountID, SourceKind: "transaction", SourceTransactionID: &row.ID,
		Amount: row.Amount, OccurredAt: row.TransactionDate}
	if row.ToAccountID != nil && accounts[*row.ToAccountID].DebtTrackingMode == model.DebtModeManaged {
		op.Kind, op.AccountID, op.UnappliedAmount = "transfer_payment", row.ToAccountID, row.Amount
	} else {
		op.AccountID = &row.AccountID
	}
	if err := checkOperationAccountsStateTx(tx, &op, true); err != nil {
		return true, err
	}
	effects, err := managedTransactionEffects(*row, accounts)
	if err != nil {
		return true, err
	}
	if err := tx.Create(&op).Error; err != nil {
		return true, err
	}
	row.DebtOperationID = &op.ID
	if err := tx.Model(&model.Transaction{}).Where("id = ? AND user_id = ?", row.ID, row.UserID).
		Update("debt_operation_id", op.ID).Error; err != nil {
		return true, err
	}
	ids := make([]string, 0, len(effects))
	for id := range effects {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		if err := mutateDebtAccountEffectTx(tx, &op, id, effects[id], "transaction", &row.ID); err != nil {
			return true, err
		}
	}
	return true, checkOperationAccountsStateTx(tx, &op, true)
}

func rejectLegacyManagedAccountTx(tx *gorm.DB, userID uint, id string) error {
	var account model.Account
	if err := tx.Select("id", "debt_tracking_mode").First(&account, "user_id = ? AND id = ?", userID, id).Error; err != nil {
		return err
	}
	if account.DebtTrackingMode == model.DebtModeManaged {
		return ErrManagedDebt
	}
	return nil
}
