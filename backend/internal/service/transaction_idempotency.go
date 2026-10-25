package service

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"strconv"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

var ErrTransactionIdempotencyConflict = errors.New("该请求标识已用于不同的记账内容，请核对原交易")
var ErrTransactionRequestUnavailable = errors.New("原记账记录已删除或不可用，本次不会重新记账，请先核对明细")

// Reuse the existing atomic request-claim table. The target is the created
// transaction, so backup ownership remapping retains its original identity.
func claimTransactionRequest(tx *gorm.DB, userID uint, req CreateTransactionRequest) (string, bool, error) {
	if len(req.IdempotencyKey) > 128 {
		return "", false, ErrInvalidIdempotencyKey
	}
	payload, err := json.Marshal(req)
	if err != nil {
		return "", false, err
	}
	keyHash, payloadHash := sha256.Sum256([]byte(req.IdempotencyKey)), sha256.Sum256(payload)
	key, fingerprint := hex.EncodeToString(keyHash[:]), hex.EncodeToString(payloadHash[:])
	var existing model.RepaymentRequest
	query := tx.Where("user_id = ? AND operation = ? AND key_hash = ?", userID, "transaction", key)
	err = query.First(&existing).Error
	if err == nil {
		if existing.PayloadHash != fingerprint {
			return "", false, ErrTransactionIdempotencyConflict
		}
		return existing.TargetID, true, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return "", false, err
	}
	// Concurrent first attempts derive the same target and contend on the
	// existing primary key. This does not deduplicate equal transaction content.
	target := uuid.NewSHA1(uuid.NameSpaceOID, []byte("manual:"+strconv.FormatUint(uint64(userID), 10)+":"+key)).String()
	claim := model.RepaymentRequest{UserID: userID, Operation: "transaction", TargetID: target,
		KeyHash: key, PayloadHash: fingerprint}
	result := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&claim)
	if result.Error != nil {
		return "", false, result.Error
	}
	if result.RowsAffected != 0 {
		return target, false, nil
	}
	// A locking read also observes the winner under MySQL REPEATABLE READ.
	if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
		First(&existing, "user_id = ? AND operation = ? AND target_id = ? AND key_hash = ?", userID, "transaction", target, key).Error; err != nil {
		return "", false, err
	}
	if existing.PayloadHash != fingerprint {
		return "", false, ErrTransactionIdempotencyConflict
	}
	return existing.TargetID, true, nil
}
