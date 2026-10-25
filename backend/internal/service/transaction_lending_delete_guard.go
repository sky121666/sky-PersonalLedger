package service

import (
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var ErrLendingInitialHasRepayments = errors.New("initial lending transaction still has repayments")

func guardLendingInitialTransactionDeleteTx(txdb *gorm.DB, transaction *model.Transaction) error {
	if transaction.LendingID == nil || *transaction.LendingID == "" {
		return nil
	}
	var lending model.Lending
	if err := txdb.Unscoped().Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&lending, "id = ? AND user_id = ?", *transaction.LendingID, transaction.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil
		}
		return err
	}
	isRepayment := (lending.Type == "lend_out" && transaction.Type == "income") ||
		(lending.Type == "borrow_in" && transaction.Type == "expense")
	if isRepayment {
		return nil
	}
	if lending.TotalRepaid.Cents() > 0 {
		return ErrLendingInitialHasRepayments
	}
	// Records cover repayments without cash transactions and inconsistent legacy totals.
	var records int64
	if err := txdb.Model(&model.LendingRecord{}).
		Where("lending_id = ? AND user_id = ?", lending.ID, transaction.UserID).
		Count(&records).Error; err != nil {
		return err
	}
	if records > 0 {
		return ErrLendingInitialHasRepayments
	}
	return nil
}

func (s *TransactionService) preflightLendingTransactionDeletesTx(txdb *gorm.DB, ids []string, userID uint) error {
	// Inspect the original batch state before any repayment can be reversed.
	for _, id := range ids {
		transaction, err := s.txRepo.GetByIDForUserWithDB(
			txdb.Clauses(clause.Locking{Strength: "UPDATE"}), id, userID,
		)
		if err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrTransactionNotFound
			}
			return err
		}
		if isSystemTransaction(transaction) {
			return ErrSystemTransactionImmutable
		}
		if err := guardLendingInitialTransactionDeleteTx(txdb, transaction); err != nil {
			return err
		}
	}
	return nil
}
