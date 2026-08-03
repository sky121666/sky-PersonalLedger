package service

import (
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// roundMoney normalizes an API amount to the integer minor-unit boundary.
func roundMoney(value money.Amount) money.Amount {
	return money.FromCents(value.Cents())
}

func roundedCurrentBalanceDelta(_ *gorm.DB, delta money.Amount) clause.Expr {
	return gorm.Expr("current_balance_cents + ?", delta.Cents())
}

func roundedDebtBalanceAfterPayment(
	_ *gorm.DB,
	principalPaid money.Amount,
) clause.Expr {
	cents := principalPaid.Cents()
	return gorm.Expr(
		"CASE WHEN current_balance_cents > ? THEN current_balance_cents - ? ELSE 0 END",
		cents,
		cents,
	)
}

func roundedTotalPaidDelta(_ *gorm.DB, delta money.Amount) clause.Expr {
	return gorm.Expr("total_paid_cents + ?", delta.Cents())
}
