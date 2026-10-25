package service

import (
	"encoding/hex"
	"errors"
	"fmt"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"gorm.io/gorm"
)

func backupDebtMode(mode string) string {
	if mode == model.DebtModeLegacy {
		return ""
	}
	return mode
}

func captureDebtBackup(tx *gorm.DB, userID uint, backup *FullBackupData) error {
	if err := tx.Where("user_id = ?", userID).Order("created_at, id").Find(&backup.DebtPlans).Error; err != nil {
		return err
	}
	if err := tx.Where("user_id = ?", userID).Order("created_at, id").Find(&backup.DebtOperations).Error; err != nil {
		return err
	}
	if err := tx.Where("user_id = ?", userID).Order("created_at, id").Find(&backup.DebtAllocations).Error; err != nil {
		return err
	}
	if debtBackupPresent(backup) {
		backup.Version = managedDebtBackupVersion
	}
	return validateDebtBackup(backup)
}

func debtBackupPresent(b *FullBackupData) bool {
	if len(b.DebtPlans)+len(b.DebtOperations)+len(b.DebtAllocations) > 0 {
		return true
	}
	for _, row := range b.Accounts {
		if backupDebtMode(row.DebtTrackingMode) != "" || row.UnplannedDebt != 0 || row.UnappliedPayment != 0 || row.DebtUnclassified != 0 {
			return true
		}
	}
	for _, row := range b.Transactions {
		if row.DebtOperationID != nil {
			return true
		}
	}
	for _, row := range b.AccountLogs {
		if row.DebtOperationID != nil || row.UnplannedDebtDelta != 0 || row.UnappliedDelta != 0 ||
			row.PrincipalPaidDelta != 0 || row.UnclassifiedDelta != 0 {
			return true
		}
	}
	return false
}

type debtBackupGraph struct {
	accounts map[string]model.Account
	plans    map[string]model.DebtPlan
	ops      map[string]model.DebtOperation
	parts    map[string][]model.DebtAllocation
	logs     map[string][]model.AccountLog
	txs      map[string][]model.Transaction
}

func validateDebtBackup(b *FullBackupData) error {
	if !debtBackupPresent(b) {
		return nil
	}
	fail := func() error { return invalidBackupOwnership(errors.New("incomplete or inconsistent debt evidence")) }
	if b.Version != managedDebtBackupVersion || b.SourceUserID == 0 {
		return fail()
	}
	g := debtBackupGraph{accounts: map[string]model.Account{}, plans: map[string]model.DebtPlan{},
		ops: map[string]model.DebtOperation{}, parts: map[string][]model.DebtAllocation{},
		logs: map[string][]model.AccountLog{}, txs: map[string][]model.Transaction{}}
	validID := func(id string) bool { return id != "" && len(id) <= 36 }
	for _, account := range b.Accounts {
		if !validID(account.ID) {
			return fail()
		}
		if _, duplicate := g.accounts[account.ID]; duplicate {
			return fail()
		}
		g.accounts[account.ID] = account
	}
	for _, plan := range b.DebtPlans {
		if !validID(plan.ID) || plan.UserID != b.SourceUserID || plan.Name == "" ||
			!validDebtMoney(plan.OriginalPrincipal) || !validDebtMoney(plan.OpeningPrincipal) ||
			plan.OpeningPrincipal > plan.OriginalPrincipal || (plan.EstimatedInterest != nil && !validDebtMoney(*plan.EstimatedInterest)) {
			return fail()
		}
		if _, duplicate := g.plans[plan.ID]; duplicate {
			return fail()
		}
		if plan.AccountID != nil {
			account, ok := g.accounts[*plan.AccountID]
			if !ok || account.UserID != plan.UserID || account.DebtTrackingMode != model.DebtModeManaged ||
				(plan.Status != "cancelled" && account.DeletedAt.Valid) {
				return fail()
			}
		}
		g.plans[plan.ID] = plan
	}
	keys := map[string]bool{}
	for _, op := range b.DebtOperations {
		if !validID(op.ID) || op.UserID != b.SourceUserID || !validDebtMoney(op.Amount) ||
			!validDebtMoney(op.UnplannedPayment) || !validDebtMoney(op.UnappliedAmount) || op.OccurredAt.IsZero() || op.CreatedAt.IsZero() {
			return fail()
		}
		if _, duplicate := g.ops[op.ID]; duplicate {
			return fail()
		}
		for _, id := range []*string{op.AccountID, op.SourceAccountID} {
			if id != nil {
				account, ok := g.accounts[*id]
				if !ok || account.UserID != op.UserID ||
					(op.Kind != "reversal" && op.ReversedBy == nil && account.DeletedAt.Valid) {
					return fail()
				}
			}
		}
		if op.AccountID != nil && g.accounts[*op.AccountID].DebtTrackingMode != model.DebtModeManaged {
			return fail()
		}
		if op.StandalonePlanID != nil {
			plan, ok := g.plans[*op.StandalonePlanID]
			if !ok || plan.AccountID != nil || op.AccountID != nil {
				return fail()
			}
		}
		if op.RequestKeyHash != nil {
			key, e1 := hex.DecodeString(*op.RequestKeyHash)
			body, e2 := hex.DecodeString(op.RequestHash)
			if e1 != nil || e2 != nil || len(key) != 32 || len(body) != 32 ||
				hex.EncodeToString(key) != *op.RequestKeyHash || hex.EncodeToString(body) != op.RequestHash || keys[*op.RequestKeyHash] {
				return fail()
			}
			keys[*op.RequestKeyHash] = true
		} else if op.RequestHash != "" || op.Kind == "payment" || op.Kind == "allocation" || op.Kind == "plan_open" || op.Kind == "interest_charge" {
			return fail()
		}
		g.ops[op.ID] = op
	}
	seenParts, seenLogs, seenTransactions := map[string]bool{}, map[string]bool{}, map[string]bool{}
	partTotals := map[string]model.DebtAllocation{}
	partCounts, openingCounts := map[string]uint64{}, map[string]int{}
	for _, part := range b.DebtAllocations {
		op, ok := g.ops[part.OperationID]
		plan, exists := g.plans[part.PlanID]
		if !validID(part.ID) || seenParts[part.ID] || part.UserID != b.SourceUserID || !ok || !exists ||
			optionalDebtID(op.AccountID) != optionalDebtID(plan.AccountID) ||
			(plan.AccountID == nil && (op.StandalonePlanID == nil || *op.StandalonePlanID != plan.ID)) {
			return fail()
		}
		seenParts[part.ID] = true
		g.parts[op.ID] = append(g.parts[op.ID], part)
		total := partTotals[plan.ID]
		var err error
		total.PrincipalDelta, err = sumDebtMoney(total.PrincipalDelta, part.PrincipalDelta)
		if err != nil {
			return fail()
		}
		total.InterestDelta, err = sumDebtMoney(total.InterestDelta, part.InterestDelta)
		if err != nil {
			return fail()
		}
		total.PrincipalPaidDelta, err = sumDebtMoney(total.PrincipalPaidDelta, part.PrincipalPaidDelta)
		if err != nil {
			return fail()
		}
		total.InterestPaidDelta, err = sumDebtMoney(total.InterestPaidDelta, part.InterestPaidDelta)
		if err != nil {
			return fail()
		}
		partTotals[plan.ID] = total
		partCounts[plan.ID]++
		if op.Kind == "plan_open" {
			openingCounts[plan.ID]++
			if part.PrincipalDelta != plan.OpeningPrincipal {
				return fail()
			}
		}
	}
	accountTotals := map[string]debtAccountEffect{}
	for _, log := range b.AccountLogs {
		if !validID(log.ID) || seenLogs[log.ID] {
			return fail()
		}
		seenLogs[log.ID] = true
		if log.DebtOperationID == nil {
			if account, ok := g.accounts[log.AccountID]; ok && account.DebtTrackingMode == model.DebtModeManaged {
				return fail()
			}
			continue
		}
		op, ok := g.ops[*log.DebtOperationID]
		account, exists := g.accounts[log.AccountID]
		if !ok || !exists || log.UserID != b.SourceUserID || account.UserID != log.UserID {
			return fail()
		}
		g.logs[op.ID] = append(g.logs[op.ID], log)
		total, err := addDebtAccountEffects(accountTotals[account.ID], debtLogEffect(log))
		if err != nil {
			return fail()
		}
		accountTotals[account.ID] = total
	}
	for _, row := range b.Transactions {
		if !validID(row.ID) || seenTransactions[row.ID] {
			return fail()
		}
		seenTransactions[row.ID] = true
		if row.DebtOperationID != nil {
			op, ok := g.ops[*row.DebtOperationID]
			if !ok || row.UserID != op.UserID {
				return fail()
			}
			g.txs[op.ID] = append(g.txs[op.ID], row)
		} else {
			for _, id := range []*string{&row.AccountID, row.ToAccountID} {
				if id != nil && g.accounts[*id].DebtTrackingMode == model.DebtModeManaged {
					return fail()
				}
			}
		}
	}
	allocated := map[string]money.Amount{}
	for id, op := range g.ops {
		if op.Kind == "reversal" {
			if err := validateDebtReversalEvidence(g, op); err != nil {
				return fail()
			}
		} else {
			if err := validateDebtEffects(op, g.parts[id], g.logs[id], g.txs[id], g.accounts); err != nil {
				return fail()
			}
			if op.ReversalOf != nil {
				return fail()
			}
			if op.ReversedBy != nil {
				reversal, ok := g.ops[*op.ReversedBy]
				if !ok || reversal.Kind != "reversal" || reversal.ReversalOf == nil || *reversal.ReversalOf != id {
					return fail()
				}
			}
		}
		if err := validateDebtProjections(op, g.parts[id], g.txs[id]); err != nil {
			return fail()
		}
		if op.Kind == "allocation" {
			if op.PaymentID == nil {
				return fail()
			}
			parent, ok := g.ops[*op.PaymentID]
			if !ok || (parent.Kind != "payment" && parent.Kind != "transfer_payment") ||
				optionalDebtID(parent.AccountID) != optionalDebtID(op.AccountID) ||
				(parent.ReversedBy != nil && op.ReversedBy == nil) {
				return fail()
			}
			if op.ReversedBy == nil {
				total, err := sumDebtMoney(allocated[parent.ID], op.Amount)
				if err != nil || total > parent.UnappliedAmount {
					return fail()
				}
				allocated[parent.ID] = total
			}
		}
	}
	for id, plan := range g.plans {
		total := partTotals[id]
		if openingCounts[id] != 1 || plan.Version != partCounts[id] ||
			!validDebtMoney(plan.PrincipalBalance) || !validDebtMoney(plan.InterestBalance) ||
			!validDebtMoney(plan.PrincipalPaid) || !validDebtMoney(plan.InterestPaid) ||
			total.PrincipalDelta != plan.PrincipalBalance || total.InterestDelta != plan.InterestBalance ||
			total.PrincipalPaidDelta != plan.PrincipalPaid || total.InterestPaidDelta != plan.InterestPaid ||
			(plan.Status != "active" && plan.Status != "cleared" && plan.Status != "cancelled") {
			return fail()
		}
		if plan.Status == "cancelled" && (plan.PrincipalBalance != 0 || plan.InterestBalance != 0 || plan.PrincipalPaid != 0 || plan.InterestPaid != 0) {
			return fail()
		}
	}
	for id, account := range g.accounts {
		if account.DebtTrackingMode == "" || account.DebtTrackingMode == model.DebtModeLegacy {
			if account.UnplannedDebt != 0 || account.UnappliedPayment != 0 || account.DebtUnclassified != 0 {
				return fail()
			}
			continue
		}
		total := accountTotals[id]
		if account.DebtTrackingMode != model.DebtModeManaged || !IsDebtAccount(account.Type) ||
			!validDebtMoney(account.UnplannedDebt) || !validDebtMoney(account.UnappliedPayment) ||
			total.Balance != account.CurrentBalance || total.Unplanned != account.UnplannedDebt ||
			total.Pending != account.UnappliedPayment || total.Principal != account.TotalPaid || total.Review != account.DebtUnclassified {
			return fail()
		}
		balance, err := sumDebtMoney(account.UnplannedDebt, account.UnappliedPayment.Negate(), account.DebtUnclassified)
		if err != nil {
			return fail()
		}
		openings := 0
		for _, op := range g.ops {
			if op.AccountID != nil && *op.AccountID == id && op.Kind == "account_open" {
				openings++
				if op.Amount != account.InitialBalance || op.ReversedBy != nil {
					return fail()
				}
			}
		}
		if openings != 1 {
			return fail()
		}
		for _, plan := range g.plans {
			if plan.AccountID != nil && *plan.AccountID == id {
				balance, err = sumDebtMoney(balance, plan.PrincipalBalance, plan.InterestBalance)
				if err != nil {
					return fail()
				}
			}
		}
		if balance != account.CurrentBalance {
			return fail()
		}
	}
	return nil
}

func validateDebtReversalEvidence(g debtBackupGraph, reversal model.DebtOperation) error {
	if reversal.ReversalOf == nil || reversal.ReversedBy != nil || len(g.txs[reversal.ID]) != 0 {
		return ErrDebtDependency
	}
	original, ok := g.ops[*reversal.ReversalOf]
	if !ok || original.Kind == "reversal" || original.Kind == "account_open" || original.ReversedBy == nil ||
		*original.ReversedBy != reversal.ID || original.Amount != reversal.Amount ||
		optionalDebtID(original.AccountID) != optionalDebtID(reversal.AccountID) ||
		optionalDebtID(original.SourceAccountID) != optionalDebtID(reversal.SourceAccountID) {
		return ErrDebtDependency
	}
	originalParts := map[string]model.DebtAllocation{}
	for _, row := range g.parts[original.ID] {
		originalParts[row.ID] = row
	}
	if len(originalParts) != len(g.parts[reversal.ID]) {
		return ErrDebtDependency
	}
	for _, row := range g.parts[reversal.ID] {
		if row.ReversalOf == nil {
			return ErrDebtDependency
		}
		part, ok := originalParts[*row.ReversalOf]
		if !ok || row.PlanID != part.PlanID || row.PrincipalDelta != part.PrincipalDelta.Negate() ||
			row.InterestDelta != part.InterestDelta.Negate() || row.PrincipalPaidDelta != part.PrincipalPaidDelta.Negate() ||
			row.InterestPaidDelta != part.InterestPaidDelta.Negate() || row.CashInterest != part.CashInterest.Negate() {
			return ErrDebtDependency
		}
		delete(originalParts, part.ID)
	}
	if len(originalParts) != 0 || len(g.logs[original.ID]) != len(g.logs[reversal.ID]) {
		return ErrDebtDependency
	}
	expected := map[string]debtAccountEffect{}
	for _, log := range g.logs[original.ID] {
		expected[log.AccountID] = debtLogEffect(log).negate()
	}
	for _, log := range g.logs[reversal.ID] {
		want, ok := expected[log.AccountID]
		if !ok || !debtLogEffect(log).equals(want) {
			return ErrDebtDependency
		}
		delete(expected, log.AccountID)
	}
	return nil
}

func restoreDebtBackupTx(tx *gorm.DB, userID uint, backup *FullBackupData) error {
	for _, row := range backup.DebtPlans {
		row.UserID = userID
		if err := tx.Create(&row).Error; err != nil {
			return err
		}
	}
	for _, row := range backup.DebtOperations {
		row.UserID = userID
		if err := tx.Create(&row).Error; err != nil {
			return err
		}
	}
	for _, row := range backup.DebtAllocations {
		row.UserID = userID
		if err := tx.Create(&row).Error; err != nil {
			return err
		}
	}
	return nil
}

func (s *BackupService) rejectDebtBackupIDCollisions(userID uint, backup *FullBackupData) error {
	ids := map[string][]string{"debt_plans": {}, "debt_operations": {}, "debt_allocations": {}}
	for _, row := range backup.DebtPlans {
		ids["debt_plans"] = append(ids["debt_plans"], row.ID)
	}
	for _, row := range backup.DebtOperations {
		ids["debt_operations"] = append(ids["debt_operations"], row.ID)
	}
	for _, row := range backup.DebtAllocations {
		ids["debt_allocations"] = append(ids["debt_allocations"], row.ID)
	}
	for table, values := range ids {
		for start := 0; start < len(values); start += 400 {
			end := start + 400
			if end > len(values) {
				end = len(values)
			}
			var count int64
			if err := s.db.Table(table).Where("user_id <> ? AND id IN ?", userID, values[start:end]).Count(&count).Error; err != nil {
				return err
			}
			if count != 0 {
				return invalidBackupOwnership(fmt.Errorf("debt identifier belongs to another user"))
			}
		}
	}
	return nil
}
