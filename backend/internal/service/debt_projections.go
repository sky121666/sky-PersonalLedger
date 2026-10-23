package service

import (
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
)

func sumDebtMoney(values ...money.Amount) (money.Amount, error) {
	var total money.Amount
	for _, value := range values {
		if !value.IsValid() {
			return 0, ErrInvalidDebtRequest
		}
		total = total.Add(value)
		if !total.IsValid() {
			return 0, ErrInvalidDebtRequest
		}
	}
	return total, nil
}

func addDebtAccountEffects(a, b debtAccountEffect) (debtAccountEffect, error) {
	var result debtAccountEffect
	for _, item := range []struct {
		target *money.Amount
		a, b   money.Amount
	}{
		{&result.Balance, a.Balance, b.Balance}, {&result.Unplanned, a.Unplanned, b.Unplanned},
		{&result.Pending, a.Pending, b.Pending}, {&result.Principal, a.Principal, b.Principal},
		{&result.Review, a.Review, b.Review},
	} {
		value, err := sumDebtMoney(item.a, item.b)
		if err != nil {
			return result, err
		}
		*item.target = value
	}
	return result, nil
}

type debtProjection struct {
	account, target, kind, source string
	amount                        money.Amount
}

func validateDebtProjections(op model.DebtOperation, parts []model.DebtAllocation, rows []model.Transaction) error {
	if op.Kind == "account_change" || op.Kind == "transfer_payment" {
		if len(rows) != 1 || op.SourceTransactionID == nil || rows[0].ID != *op.SourceTransactionID ||
			op.SourceAccountID == nil || rows[0].AccountID != *op.SourceAccountID || rows[0].Amount != op.Amount ||
			op.SourceKind != "transaction" {
			return ErrDebtDependency
		}
		if op.Kind == "transfer_payment" && (rows[0].Type != "transfer" || rows[0].ToAccountID == nil ||
			op.AccountID == nil || *rows[0].ToAccountID != *op.AccountID || op.UnappliedAmount != op.Amount) {
			return ErrDebtDependency
		}
		if rows[0].DeletedAt.Valid != (op.ReversedBy != nil) {
			return ErrDebtDependency
		}
		return nil
	}
	expected := []debtProjection{}
	if op.Kind == "account_open" && op.Amount > 0 {
		if op.AccountID == nil || op.SourceTransactionID == nil || len(rows) != 1 ||
			rows[0].ID != *op.SourceTransactionID {
			return ErrDebtDependency
		}
		expected = append(expected, debtProjection{account: *op.AccountID, kind: "expense", source: "system", amount: op.Amount})
	}
	if op.Kind == "interest_charge" && op.AccountID != nil {
		expected = append(expected, debtProjection{account: *op.AccountID, kind: "expense", source: "debt_interest", amount: op.Amount})
	}
	if op.Kind == "payment" && op.SourceAccountID != nil {
		var principal, cash money.Amount
		for _, part := range parts {
			var err error
			principal, err = sumDebtMoney(principal, part.PrincipalPaidDelta)
			if err != nil {
				return err
			}
			cash, err = sumDebtMoney(cash, part.CashInterest)
			if err != nil {
				return err
			}
		}
		if op.AccountID != nil {
			reduction := op.Amount.Sub(cash)
			if reduction > 0 {
				expected = append(expected, debtProjection{account: *op.SourceAccountID, target: *op.AccountID,
					kind: "transfer", source: "debt_payment", amount: reduction})
			}
		} else {
			if principal > 0 {
				expected = append(expected, debtProjection{account: *op.SourceAccountID, kind: "expense",
					source: "debt_principal", amount: principal})
			}
			cash = op.Amount.Sub(principal)
		}
		if cash > 0 {
			expected = append(expected, debtProjection{account: *op.SourceAccountID, kind: "expense",
				source: "debt_interest", amount: cash})
		}
	}
	if len(rows) != len(expected) {
		return ErrDebtDependency
	}
	used := map[int]bool{}
	for _, row := range rows {
		if row.UserID != op.UserID || row.DebtOperationID == nil || *row.DebtOperationID != op.ID ||
			row.DeletedAt.Valid != (op.ReversedBy != nil) {
			return ErrDebtDependency
		}
		matched := false
		for i, want := range expected {
			target := ""
			if row.ToAccountID != nil {
				target = *row.ToAccountID
			}
			if !used[i] && row.AccountID == want.account && target == want.target && row.Type == want.kind &&
				row.Source == want.source && row.Amount == want.amount {
				used[i], matched = true, true
				break
			}
		}
		if !matched {
			return ErrDebtDependency
		}
	}
	return nil
}
