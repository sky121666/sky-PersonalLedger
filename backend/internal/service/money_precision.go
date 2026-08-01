package service

import (
	"math"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// roundMoney keeps the existing JSON number contract while enforcing the
// database's decimal(15,2) minor-unit precision in Go calculations.
func roundMoney(value float64) float64 {
	return math.Round(value*100) / 100
}

func roundedCurrentBalanceDelta(db *gorm.DB, delta float64) clause.Expr {
	if db.Dialector.Name() == "postgres" {
		return gorm.Expr(
			"ROUND(current_balance + CAST(? AS numeric), 2)",
			delta,
		)
	}
	return gorm.Expr("ROUND(current_balance + ?, 2)", delta)
}

func roundedDebtBalanceAfterPayment(
	db *gorm.DB,
	principalPaid float64,
) clause.Expr {
	if db.Dialector.Name() == "postgres" {
		return gorm.Expr(
			"CASE WHEN current_balance > CAST(? AS numeric) THEN ROUND(current_balance - CAST(? AS numeric), 2) ELSE 0 END",
			principalPaid,
			principalPaid,
		)
	}
	return gorm.Expr(
		"CASE WHEN current_balance > ? THEN ROUND(current_balance - ?, 2) ELSE 0 END",
		principalPaid,
		principalPaid,
	)
}

func roundedTotalPaidDelta(db *gorm.DB, delta float64) clause.Expr {
	if db.Dialector.Name() == "postgres" {
		return gorm.Expr("ROUND(total_paid + CAST(? AS numeric), 2)", delta)
	}
	return gorm.Expr("ROUND(total_paid + ?, 2)", delta)
}
