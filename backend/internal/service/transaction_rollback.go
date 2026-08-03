package service

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func loadLinkedReminderForRollbackTx(txdb *gorm.DB, tx *model.Transaction) (*model.Reminder, error) {
	if tx.ReminderID == nil || *tx.ReminderID == "" {
		return nil, nil
	}

	var reminder model.Reminder
	if err := txdb.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&reminder, "id = ? AND user_id = ?", *tx.ReminderID, tx.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &reminder, nil
}

// revertReminderPaymentTx reverts reminder and debt-account state atomically
// with the linked transaction deletion.
func (s *TransactionService) revertReminderPaymentTx(txdb *gorm.DB, tx *model.Transaction, reminder *model.Reminder) error {
	if reminder == nil {
		return nil
	}

	amount := tx.Amount
	principalAmount := tx.PrincipalAmount
	if principalAmount == 0 {
		principalAmount = amount
	}
	interestAmount := tx.InterestAmount
	if interestAmount == 0 && amount > principalAmount {
		interestAmount = amount.Sub(principalAmount)
	}

	reminder.TotalPaid = reminder.TotalPaid.Sub(amount)
	if reminder.TotalPaid < 0 {
		reminder.TotalPaid = 0
	}
	reminder.InterestPaid = reminder.InterestPaid.Sub(interestAmount)
	if reminder.InterestPaid < 0 {
		reminder.InterestPaid = 0
	}

	if reminder.CurrentBalance != nil {
		newBalance := reminder.CurrentBalance.Add(principalAmount)
		reminder.CurrentBalance = &newBalance
	}

	if reminder.PaidOffAt != nil && reminder.CurrentBalance != nil && *reminder.CurrentBalance > 0 {
		reminder.PaidOffAt = nil
	}

	result := txdb.Unscoped().Model(&model.Reminder{}).
		Where("id = ? AND user_id = ?", reminder.ID, tx.UserID).
		Updates(map[string]any{
			"total_paid_cents":      reminder.TotalPaid,
			"interest_paid_cents":   reminder.InterestPaid,
			"current_balance_cents": reminder.CurrentBalance,
			"paid_off_at":           reminder.PaidOffAt,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrReminderNotFound
	}

	if reminder.AccountID != nil && *reminder.AccountID != "" {
		var account model.Account
		if err := txdb.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&account, "id = ? AND user_id = ?", *reminder.AccountID, tx.UserID).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrAccountNotFound
			}
			return err
		}
		account.CurrentBalance = account.CurrentBalance.Add(principalAmount)
		account.TotalPaid = account.TotalPaid.Sub(principalAmount)
		if account.TotalPaid < 0 {
			account.TotalPaid = 0
		}
		if account.PaidOffAt != nil && account.CurrentBalance > 0 {
			account.PaidOffAt = nil
		}
		if err := logAccountBalanceChangeTx(
			txdb,
			s.accountLogSvc,
			tx.UserID,
			account.ID,
			"rollback",
			principalAmount,
			principalAmount,
			&tx.ID,
			&reminder.ID,
			nil,
			"撤回还款负债调整",
			true,
		); err != nil {
			return err
		}
		result := txdb.Model(&model.Account{}).
			Where("id = ? AND user_id = ?", account.ID, tx.UserID).
			Updates(map[string]any{
				"current_balance_cents": account.CurrentBalance,
				"total_paid_cents":      account.TotalPaid,
				"paid_off_at":           account.PaidOffAt,
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != 1 {
			return ErrAccountNotFound
		}
	}
	return nil
}

// revertLendingTransactionTx reverts lending totals when a linked transaction is deleted.
func (s *TransactionService) revertLendingTransactionTx(txdb *gorm.DB, tx *model.Transaction) error {
	if tx.LendingID == nil || *tx.LendingID == "" {
		return nil
	}

	var lending model.Lending
	if err := txdb.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&lending, "id = ? AND user_id = ?", *tx.LendingID, tx.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	originalBalance := lending.CurrentBalance
	originalTotalRepaid := lending.TotalRepaid
	originalIsSettled := lending.IsSettled

	isRepayment := (lending.Type == "lend_out" && tx.Type == "income") ||
		(lending.Type == "borrow_in" && tx.Type == "expense")

	if isRepayment {
		lending.TotalRepaid = lending.TotalRepaid.Sub(tx.Amount)
		if lending.TotalRepaid < 0 {
			lending.TotalRepaid = 0
		}
		lending.CurrentBalance = lending.CurrentBalance.Add(tx.Amount)

		if lending.IsSettled && lending.CurrentBalance > 0 {
			lending.IsSettled = false
			lending.SettledAt = nil
		}

		if err := txdb.Where("user_id = ? AND transaction_id = ?", tx.UserID, tx.ID).
			Delete(&model.LendingRecord{}).Error; err != nil {
			return err
		}
	} else {
		lending.CurrentBalance = lending.CurrentBalance.Sub(tx.Amount)
		if lending.CurrentBalance < 0 {
			lending.CurrentBalance = 0
		}
	}

	result := txdb.Unscoped().Model(&model.Lending{}).
		Where(
			"id = ? AND user_id = ? AND current_balance_cents = ? AND total_repaid_cents = ? AND is_settled = ?",
			lending.ID,
			tx.UserID,
			originalBalance.Cents(),
			originalTotalRepaid.Cents(),
			originalIsSettled,
		).
		Updates(map[string]any{
			"current_balance_cents": lending.CurrentBalance,
			"total_repaid_cents":    lending.TotalRepaid,
			"is_settled":            lending.IsSettled,
			"settled_at":            lending.SettledAt,
		})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrConcurrentBalanceUpdate
	}
	return nil
}
