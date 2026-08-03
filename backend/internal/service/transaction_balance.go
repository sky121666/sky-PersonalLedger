package service

import (
	"errors"
	"sort"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

func (s *TransactionService) applyBalanceChangesTx(txdb *gorm.DB, tx *model.Transaction, logChange bool) error {
	if err := lockBalanceAccountsTx(txdb, tx); err != nil {
		return err
	}

	switch tx.Type {
	case "expense":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "expense", tx.Amount.Negate(), nil, nil, "支出", logChange)
	case "income":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "income", tx.Amount, nil, nil, "收入", logChange)
	case "transfer":
		if tx.ToAccountID == nil || *tx.ToAccountID == "" {
			return ErrSameAccount
		}
		if err := s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "transfer_out", tx.Amount.Negate(), nil, nil, "转出", logChange); err != nil {
			return err
		}
		return s.applyTransactionAccountDeltaTx(txdb, tx, *tx.ToAccountID, "transfer_in", tx.Amount, nil, nil, "转入", logChange)
	default:
		return nil
	}
}

func lockBalanceAccountsTx(txdb *gorm.DB, transactions ...*model.Transaction) error {
	accountOwners := make(map[string]uint)
	for _, transaction := range transactions {
		for _, accountID := range balanceAccountIDs(transaction) {
			accountOwners[accountID] = transaction.UserID
		}
	}

	accountIDs := make([]string, 0, len(accountOwners))
	for accountID := range accountOwners {
		accountIDs = append(accountIDs, accountID)
	}
	sort.Strings(accountIDs)
	for _, accountID := range accountIDs {
		var account model.Account
		if err := txdb.Clauses(clause.Locking{Strength: "UPDATE"}).
			Select("id").
			First(&account, "id = ? AND user_id = ?", accountID, accountOwners[accountID]).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrAccountNotFound
			}
			return err
		}
	}
	return nil
}

func balanceAccountIDs(tx *model.Transaction) []string {
	if tx == nil || tx.AccountID == "" {
		return nil
	}

	accountIDs := []string{tx.AccountID}
	if tx.Type == "transfer" && tx.ToAccountID != nil && *tx.ToAccountID != "" && *tx.ToAccountID != tx.AccountID {
		accountIDs = append(accountIDs, *tx.ToAccountID)
	}
	sort.Strings(accountIDs)
	return accountIDs
}

// accountBalanceDeltaTx converts the ordinary asset-account cash-flow sign
// into the stored balance convention. Asset balances represent money held;
// debt balances represent money owed, so the same cash flow has the opposite
// effect for debt accounts.
func accountBalanceDeltaTx(txdb *gorm.DB, userID uint, accountID string, cashFlowDelta money.Amount) (money.Amount, error) {
	var account model.Account
	if err := txdb.Select("type").First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return 0, ErrAccountNotFound
		}
		return 0, err
	}
	if IsDebtAccount(account.Type) {
		return cashFlowDelta.Negate(), nil
	}
	return cashFlowDelta, nil
}

func (s *TransactionService) applyTransactionAccountDeltaTx(
	txdb *gorm.DB,
	tx *model.Transaction,
	accountID string,
	logType string,
	cashFlowDelta money.Amount,
	reminderID *string,
	lendingID *string,
	remark string,
	logChange bool,
) error {
	balanceDelta, err := accountBalanceDeltaTx(txdb, tx.UserID, accountID, cashFlowDelta)
	if err != nil {
		return err
	}
	return applyAccountBalanceMutationTx(
		txdb,
		s.accountLogSvc,
		tx.UserID,
		accountID,
		logType,
		tx.Amount,
		balanceDelta,
		&tx.ID,
		reminderID,
		lendingID,
		remark,
		logChange,
	)
}

func (s *TransactionService) revertBalanceChangesTx(txdb *gorm.DB, tx *model.Transaction, logChange bool) error {
	if err := lockBalanceAccountsTx(txdb, tx); err != nil {
		return err
	}

	switch tx.Type {
	case "expense":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "rollback", tx.Amount, tx.ReminderID, tx.LendingID, "撤回支出", logChange)
	case "income":
		return s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "rollback", tx.Amount.Negate(), tx.ReminderID, tx.LendingID, "撤回收入", logChange)
	case "transfer":
		if err := s.applyTransactionAccountDeltaTx(txdb, tx, tx.AccountID, "rollback", tx.Amount, nil, nil, "撤回转出", logChange); err != nil {
			return err
		}
		if tx.ToAccountID != nil && *tx.ToAccountID != "" {
			return s.applyTransactionAccountDeltaTx(txdb, tx, *tx.ToAccountID, "rollback", tx.Amount.Negate(), nil, nil, "撤回转入", logChange)
		}
		return nil
	default:
		return nil
	}
}

func (s *TransactionService) updateAccountBalanceTx(txdb *gorm.DB, userID uint, accountID string, delta money.Amount) error {
	return updateAccountBalanceForUserTx(txdb, accountID, userID, delta)
}

func applyAccountBalanceMutationTx(
	txdb *gorm.DB,
	accountLogSvc *AccountLogService,
	userID uint,
	accountID string,
	logType string,
	amount money.Amount,
	balanceDelta money.Amount,
	transactionID *string,
	reminderID *string,
	lendingID *string,
	remark string,
	logChange bool,
) error {
	if err := logAccountBalanceChangeTx(
		txdb,
		accountLogSvc,
		userID,
		accountID,
		logType,
		amount,
		balanceDelta,
		transactionID,
		reminderID,
		lendingID,
		remark,
		logChange,
	); err != nil {
		return err
	}
	return updateAccountBalanceForUserTx(txdb, accountID, userID, balanceDelta)
}

func logAccountBalanceChangeTx(
	txdb *gorm.DB,
	accountLogSvc *AccountLogService,
	userID uint,
	accountID string,
	logType string,
	amount money.Amount,
	balanceDelta money.Amount,
	transactionID *string,
	reminderID *string,
	lendingID *string,
	remark string,
	enabled bool,
) error {
	if !enabled || accountLogSvc == nil {
		return nil
	}

	var account model.Account
	if err := txdb.First(&account, "id = ? AND user_id = ?", accountID, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrAccountNotFound
		}
		return err
	}

	balanceBefore := account.CurrentBalance
	return accountLogSvc.logRepo.CreateWithDB(txdb, &repository.CreateAccountLogRequest{
		UserID:        userID,
		AccountID:     accountID,
		Type:          logType,
		Amount:        amount,
		BalanceBefore: balanceBefore,
		BalanceAfter:  balanceBefore.Add(balanceDelta),
		TransactionID: transactionID,
		ReminderID:    reminderID,
		LendingID:     lendingID,
		Remark:        remark,
	})
}
