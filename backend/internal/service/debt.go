package service

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/money"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var (
	ErrInvalidDebtRequest = errors.New("分期请求无效，请核对金额、目标及付款来源")
	ErrDebtNotFound       = errors.New("分期或债务操作不存在")
	ErrDebtReconciliation = errors.New("账户与分期明细不一致，请先核对；本次未扣款")
	ErrManagedDebt        = errors.New("此账户使用多分期模式，请使用分期付款或撤销入口")
	ErrDebtDependency     = errors.New("操作已撤销或仍有有效依赖，请先核对相关操作")
)

type DebtService struct{ db *gorm.DB }

func NewDebtService(db *gorm.DB) *DebtService { return &DebtService{db: db} }

type CreateDebtPlanRequest struct {
	Name              string        `json:"name" binding:"required,max=100"`
	Scope             string        `json:"scope" binding:"required,oneof=account standalone"`
	AccountID         *string       `json:"account_id"`
	OriginalPrincipal money.Amount  `json:"original_principal"`
	OpeningPrincipal  money.Amount  `json:"opening_principal"`
	BookedInterest    money.Amount  `json:"booked_interest"`
	EstimatedInterest *money.Amount `json:"estimated_interest"`
	IdempotencyKey    string        `json:"idempotency_key" binding:"required,max=128"`
}

type DebtInterestRequest struct {
	Amount         money.Amount `json:"amount" binding:"required,gt=0"`
	OccurredAt     string       `json:"occurred_at"`
	IdempotencyKey string       `json:"idempotency_key" binding:"required,max=128"`
}

type DebtReverseRequest struct {
	IdempotencyKey string `json:"idempotency_key" binding:"required,max=128"`
}

func validDebtMoney(amount money.Amount) bool {
	return amount.IsValid() && amount >= 0
}

func debtTime(value string) (time.Time, error) {
	if value == "" {
		return time.Now(), nil
	}
	return parseTransactionDate(value)
}

func (s *DebtService) write(userID uint, kind, target, key string, payload any,
	build func(*gorm.DB, *model.DebtOperation) error) (*model.DebtOperation, error) {
	if strings.TrimSpace(key) == "" || len(key) > 128 {
		return nil, ErrInvalidIdempotencyKey
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, ErrInvalidDebtRequest
	}
	keySum, bodySum := sha256.Sum256([]byte(kind+"\x00"+target+"\x00"+key)), sha256.Sum256(raw)
	keyHash, bodyHash := hex.EncodeToString(keySum[:]), hex.EncodeToString(bodySum[:])
	var result *model.DebtOperation
	err = financeWriteTransaction(s.db, func(tx *gorm.DB) error {
		if err := lockDebtUserTx(tx, userID); err != nil {
			return err
		}
		var existing model.DebtOperation
		err := tx.Where("user_id = ? AND request_key_hash = ?", userID, keyHash).First(&existing).Error
		if err == nil {
			if existing.RequestHash != bodyHash {
				return ErrIdempotencyConflict
			}
			result = &existing
			return nil
		}
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
		op := &model.DebtOperation{ID: uuid.NewString(), UserID: userID, Kind: kind, SourceKind: "none",
			RequestKeyHash: &keyHash, RequestHash: bodyHash, OccurredAt: time.Now()}
		if err := tx.Create(op).Error; err != nil {
			return err
		}
		if err := build(tx, op); err != nil {
			return err
		}
		if err := tx.Save(op).Error; err != nil {
			return err
		}
		result = op
		return nil
	})
	return result, err
}

// Lock before debt reads, including idempotency lookup. Dedicated debt writes
// and import reversals use user -> accounts -> operations -> plans.
func lockDebtUserTx(tx *gorm.DB, userID uint) error {
	_, err := repository.NewUserRepository(tx).GetByIDForUpdate(userID)
	return err
}

func seedManagedDebtAccountTx(tx *gorm.DB, account *model.Account) error {
	op := model.DebtOperation{ID: uuid.NewString(), UserID: account.UserID, Kind: "account_open",
		AccountID: &account.ID, SourceKind: "opening", Amount: account.InitialBalance, OccurredAt: time.Now()}
	if account.InitialBalance > 0 {
		var opening model.Transaction
		if err := tx.First(&opening, "user_id = ? AND account_id = ? AND source = ?",
			account.UserID, account.ID, "system").Error; err != nil {
			return err
		}
		op.SourceTransactionID = &opening.ID
		if err := tx.Model(&opening).Update("debt_operation_id", op.ID).Error; err != nil {
			return err
		}
	}
	if err := tx.Create(&op).Error; err != nil {
		return err
	}
	return tx.Create(&model.AccountLog{ID: uuid.NewString(), UserID: account.UserID, AccountID: account.ID,
		Type: "adjustment", Amount: account.InitialBalance, BalanceAfter: account.InitialBalance,
		TransactionID:   op.SourceTransactionID,
		DebtOperationID: &op.ID, DebtEffectRole: "opening", UnplannedDebtDelta: account.InitialBalance,
		Remark: "新账户多分期追踪期初", CreatedAt: time.Now()}).Error
}

func debtAccountTx(tx *gorm.DB, userID uint, id string) (*model.Account, error) {
	var account model.Account
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&account, "id = ? AND user_id = ?", id, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrDebtNotFound
		}
		return nil, err
	}
	return &account, nil
}

func checkDebtAccountTx(tx *gorm.DB, userID uint, id string) error {
	return checkDebtAccountStateTx(tx, userID, id, false)
}

func checkDebtAccountStateTx(tx *gorm.DB, userID uint, id string, allowReview bool) error {
	var account model.Account
	if err := tx.First(&account, "id = ? AND user_id = ?", id, userID).Error; err != nil {
		return ErrDebtNotFound
	}
	if account.DebtTrackingMode != model.DebtModeManaged || !IsDebtAccount(account.Type) {
		return ErrManagedDebt
	}
	var plans []model.DebtPlan
	if err := tx.Where("user_id = ? AND account_id = ?", userID, id).Find(&plans).Error; err != nil {
		return err
	}
	total, sumErr := sumDebtMoney(account.UnplannedDebt, account.UnappliedPayment.Negate(), account.DebtUnclassified)
	if sumErr != nil {
		return ErrDebtReconciliation
	}
	if account.UnplannedDebt < 0 || account.UnappliedPayment < 0 {
		return ErrDebtReconciliation
	}
	for _, plan := range plans {
		if !validDebtMoney(plan.PrincipalBalance) || !validDebtMoney(plan.InterestBalance) {
			return ErrDebtReconciliation
		}
		total, sumErr = sumDebtMoney(total, plan.PrincipalBalance, plan.InterestBalance)
		if sumErr != nil {
			return ErrDebtReconciliation
		}
	}
	if !total.IsValid() || total.Cents() != account.CurrentBalance.Cents() {
		return ErrDebtReconciliation
	}
	if !allowReview && account.DebtUnclassified != 0 {
		return ErrDebtReconciliation
	}
	return nil
}

func (s *DebtService) CheckAccount(userID uint, id string) error {
	return withConsistentReadSnapshot(s.db, func(tx *gorm.DB) error { return checkDebtAccountTx(tx, userID, id) })
}

func (s *DebtService) GetPlan(userID uint, id string) (*model.DebtPlan, error) {
	var plan model.DebtPlan
	if err := s.db.First(&plan, "id = ? AND user_id = ?", id, userID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrDebtNotFound
		}
		return nil, err
	}
	return &plan, nil
}

func (s *DebtService) ListPlans(userID uint, accountID string) ([]model.DebtPlan, error) {
	plans := make([]model.DebtPlan, 0)
	query := s.db.Where("user_id = ?", userID)
	if accountID != "" {
		query = query.Where("account_id = ?", accountID)
	}
	return plans, query.Order("created_at, id").Find(&plans).Error
}

func (s *DebtService) GetOperation(userID uint, id string) (*model.DebtOperation, error) {
	var op model.DebtOperation
	if err := s.db.First(&op, "user_id = ? AND id = ?", userID, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrDebtNotFound
		}
		return nil, err
	}
	return &op, nil
}

func (s *DebtService) ListOperations(userID uint, accountID string) ([]model.DebtOperation, error) {
	return s.ListOperationsFiltered(userID, DebtOperationFilter{AccountID: accountID})
}

type DebtOperationFilter struct {
	AccountID      string `form:"account_id"`
	PlanID         string `form:"plan_id"`
	StandaloneOnly bool   `form:"standalone_only"`
	Before         string `form:"before"`
}

func (s *DebtService) ListOperationsFiltered(userID uint, filter DebtOperationFilter) ([]model.DebtOperation, error) {
	rows := make([]model.DebtOperation, 0)
	err := withConsistentReadSnapshot(s.db, func(snapshot *gorm.DB) error {
		if filter.PlanID != "" {
			var plan model.DebtPlan
			if err := snapshot.First(&plan, "id = ? AND user_id = ?", filter.PlanID, userID).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return ErrDebtNotFound
				}
				return err
			}
		}
		scope := func() *gorm.DB {
			query := snapshot.Model(&model.DebtOperation{}).Where("user_id = ?", userID)
			if filter.AccountID != "" {
				query = query.Where("account_id = ?", filter.AccountID)
			}
			if filter.StandaloneOnly {
				query = query.Where("account_id IS NULL")
			}
			if filter.PlanID != "" {
				allocations := snapshot.Model(&model.DebtAllocation{}).Select("operation_id").
					Where("user_id = ? AND plan_id = ?", userID, filter.PlanID)
				query = query.Where("(standalone_plan_id = ? OR id IN (?))", filter.PlanID, allocations)
			}
			return query
		}
		query := scope()
		if filter.Before != "" {
			var cursor model.DebtOperation
			if err := scope().Where("id = ?", filter.Before).First(&cursor).Error; err != nil {
				if errors.Is(err, gorm.ErrRecordNotFound) {
					return ErrDebtNotFound
				}
				return err
			}
			query = query.Where("(created_at < ? OR (created_at = ? AND id < ?))",
				cursor.CreatedAt, cursor.CreatedAt, cursor.ID)
		}
		return query.Order("created_at DESC, id DESC").Limit(100).Find(&rows).Error
	})
	return rows, err
}

type DebtOperationDetails struct {
	Operation         model.DebtOperation    `json:"operation"`
	Allocations       []model.DebtAllocation `json:"allocations"`
	Effects           []model.AccountLog     `json:"account_effects"`
	Transactions      []model.Transaction    `json:"transactions"`
	UnallocatedAmount money.Amount           `json:"unallocated_amount"`
	ActiveAllocations []model.DebtOperation  `json:"active_allocations"`
}

func (s *DebtService) OperationDetails(userID uint, id string) (*DebtOperationDetails, error) {
	result := &DebtOperationDetails{ActiveAllocations: make([]model.DebtOperation, 0)}
	err := withConsistentReadSnapshot(s.db, func(tx *gorm.DB) error {
		if err := tx.First(&result.Operation, "user_id = ? AND id = ?", userID, id).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return ErrDebtNotFound
			}
			return err
		}
		op := result.Operation
		if (op.Kind == "payment" || op.Kind == "transfer_payment") && op.ReversedBy == nil {
			if err := tx.Where("user_id = ? AND payment_id = ? AND kind = ? AND reversed_by IS NULL",
				userID, id, "allocation").Order("created_at, id").Find(&result.ActiveAllocations).Error; err != nil {
				return err
			}
			result.UnallocatedAmount = op.UnappliedAmount
			for _, allocation := range result.ActiveAllocations {
				result.UnallocatedAmount = result.UnallocatedAmount.Sub(allocation.Amount)
			}
			if !validDebtMoney(result.UnallocatedAmount) {
				return ErrDebtDependency
			}
		}
		if err := tx.Where("user_id = ? AND operation_id = ?", userID, id).Order("created_at, id").Find(&result.Allocations).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ? AND debt_operation_id = ?", userID, id).Order("created_at, id").Find(&result.Effects).Error; err != nil {
			return err
		}
		return tx.Unscoped().Where("user_id = ? AND debt_operation_id = ?", userID, id).Order("created_at, id").Find(&result.Transactions).Error
	})
	return result, err
}

func (s *DebtService) CreatePlan(userID uint, req CreateDebtPlanRequest) (*model.DebtPlan, error) {
	accountID := normalizeOptionalString(req.AccountID)
	if strings.TrimSpace(req.Name) == "" || len([]rune(req.Name)) > 100 ||
		(req.Scope != "account" && req.Scope != "standalone") ||
		(req.Scope == "account") != (accountID != nil) ||
		!validDebtMoney(req.OriginalPrincipal) || !validDebtMoney(req.OpeningPrincipal) ||
		!validDebtMoney(req.BookedInterest) || req.OpeningPrincipal > req.OriginalPrincipal ||
		(req.EstimatedInterest != nil && !validDebtMoney(*req.EstimatedInterest)) {
		return nil, ErrInvalidDebtRequest
	}
	op, err := s.write(userID, "plan_open", optionalDebtID(accountID), req.IdempotencyKey, req,
		func(tx *gorm.DB, op *model.DebtOperation) error {
			total := req.OpeningPrincipal.Add(req.BookedInterest)
			if !total.IsValid() {
				return ErrInvalidDebtRequest
			}
			op.AccountID = accountID
			if accountID != nil {
				if _, err := debtAccountTx(tx, userID, *accountID); err != nil {
					return err
				}
				if err := checkDebtAccountTx(tx, userID, *accountID); err != nil {
					return err
				}
				if err := mutateDebtAccountTx(tx, op, *accountID, 0, total.Negate(), 0, 0, "classification", nil); err != nil {
					return err
				}
			}
			plan := model.DebtPlan{ID: uuid.NewString(), UserID: userID, AccountID: accountID, Name: strings.TrimSpace(req.Name),
				OriginalPrincipal: req.OriginalPrincipal, OpeningPrincipal: req.OpeningPrincipal,
				EstimatedInterest: req.EstimatedInterest, Status: "active"}
			if err := tx.Create(&plan).Error; err != nil {
				return err
			}
			if accountID == nil {
				op.StandalonePlanID = &plan.ID
			}
			if err := applyDebtAllocationTx(tx, op, model.DebtAllocation{PlanID: plan.ID,
				PrincipalDelta: req.OpeningPrincipal, InterestDelta: req.BookedInterest}); err != nil {
				return err
			}
			return checkOperationAccountsTx(tx, op)
		})
	if err != nil {
		return nil, err
	}
	var allocation model.DebtAllocation
	if err := s.db.First(&allocation, "operation_id = ? AND user_id = ?", op.ID, userID).Error; err != nil {
		return nil, err
	}
	return s.GetPlan(userID, allocation.PlanID)
}

func optionalDebtID(value *string) string {
	if value == nil {
		return "standalone"
	}
	return *value
}

func applyDebtAllocationTx(tx *gorm.DB, op *model.DebtOperation, effect model.DebtAllocation) error {
	var plan model.DebtPlan
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&plan, "id = ? AND user_id = ?", effect.PlanID, op.UserID).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrDebtNotFound
		}
		return err
	}
	if plan.Status == "cancelled" || optionalDebtID(plan.AccountID) != optionalDebtID(op.AccountID) ||
		(plan.AccountID == nil && (op.StandalonePlanID == nil || *op.StandalonePlanID != plan.ID)) {
		return ErrInvalidDebtRequest
	}
	principal := plan.PrincipalBalance.Add(effect.PrincipalDelta)
	interest := plan.InterestBalance.Add(effect.InterestDelta)
	paid := plan.PrincipalPaid.Add(effect.PrincipalPaidDelta)
	interestPaid := plan.InterestPaid.Add(effect.InterestPaidDelta)
	for _, value := range []money.Amount{principal, interest, paid, interestPaid} {
		if !validDebtMoney(value) {
			return ErrInvalidDebtRequest
		}
	}
	status := "active"
	if principal == 0 && interest == 0 {
		status = "cleared"
	}
	result := tx.Model(&model.DebtPlan{}).Where("id = ? AND user_id = ? AND version = ?", plan.ID, op.UserID, plan.Version).
		Updates(map[string]any{"principal_balance_cents": principal, "interest_balance_cents": interest,
			"principal_paid_cents": paid, "interest_paid_cents": interestPaid, "status": status, "version": plan.Version + 1})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrConcurrentBalanceUpdate
	}
	effect.ID, effect.UserID, effect.OperationID = uuid.NewString(), op.UserID, op.ID
	return tx.Create(&effect).Error
}

func mutateDebtAccountTx(tx *gorm.DB, op *model.DebtOperation, accountID string,
	balanceDelta, unplannedDelta, pendingDelta, principalPaidDelta money.Amount, role string, transactionID *string) error {
	return mutateDebtAccountEffectTx(tx, op, accountID, debtAccountEffect{
		Balance: balanceDelta, Unplanned: unplannedDelta, Pending: pendingDelta, Principal: principalPaidDelta,
	}, role, transactionID)
}

func mutateDebtAccountEffectTx(tx *gorm.DB, op *model.DebtOperation, accountID string,
	effect debtAccountEffect, role string, transactionID *string) error {
	account, err := debtAccountTx(tx, op.UserID, accountID)
	if err != nil {
		return err
	}
	balance := account.CurrentBalance.Add(effect.Balance)
	unplanned := account.UnplannedDebt.Add(effect.Unplanned)
	pending := account.UnappliedPayment.Add(effect.Pending)
	paid := account.TotalPaid.Add(effect.Principal)
	review := account.DebtUnclassified.Add(effect.Review)
	if !balance.IsValid() || !review.IsValid() || !validDebtMoney(unplanned) || !validDebtMoney(pending) || !validDebtMoney(paid) {
		return ErrDebtDependency
	}
	if account.DebtTrackingMode != model.DebtModeManaged && (effect.Unplanned != 0 || effect.Pending != 0 || effect.Principal != 0 || effect.Review != 0) {
		return ErrManagedDebt
	}
	result := tx.Model(&model.Account{}).Where("id = ? AND user_id = ? AND current_balance_cents = ?",
		accountID, op.UserID, account.CurrentBalance.Cents()).Updates(map[string]any{
		"current_balance_cents": balance, "unplanned_debt_cents": unplanned, "unapplied_payment_cents": pending,
		"debt_unclassified_cents": review,
		"total_paid_cents":        paid, "paid_off_at": debtPaidOffAt(account, balance),
	})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected != 1 {
		return ErrConcurrentBalanceUpdate
	}
	return tx.Create(&model.AccountLog{ID: uuid.NewString(), UserID: op.UserID, AccountID: accountID, Type: "adjustment",
		Amount: op.Amount, BalanceBefore: account.CurrentBalance, BalanceAfter: balance, TransactionID: transactionID,
		DebtOperationID: &op.ID, DebtEffectRole: role, UnplannedDebtDelta: effect.Unplanned, UnappliedDelta: effect.Pending,
		PrincipalPaidDelta: effect.Principal, UnclassifiedDelta: effect.Review,
		Remark: "分期操作: " + op.Kind, CreatedAt: time.Now()}).Error
}

func debtPaidOffAt(account *model.Account, balance money.Amount) *time.Time {
	if !IsDebtAccount(account.Type) {
		return account.PaidOffAt
	}
	if balance > 0 {
		return nil
	}
	if account.PaidOffAt != nil {
		return account.PaidOffAt
	}
	now := time.Now()
	return &now
}

func checkOperationAccountsTx(tx *gorm.DB, op *model.DebtOperation) error {
	return checkOperationAccountsStateTx(tx, op, false)
}

func checkOperationAccountsStateTx(tx *gorm.DB, op *model.DebtOperation, allowReview bool) error {
	ids := []string{}
	for _, id := range []*string{op.AccountID, op.SourceAccountID} {
		if id != nil {
			ids = append(ids, *id)
		}
	}
	sort.Strings(ids)
	for _, id := range ids {
		account, err := debtAccountTx(tx, op.UserID, id)
		if err != nil {
			return err
		}
		if account.DebtTrackingMode == model.DebtModeManaged {
			if err := checkDebtAccountStateTx(tx, op.UserID, id, allowReview); err != nil {
				return err
			}
		}
	}
	return nil
}
