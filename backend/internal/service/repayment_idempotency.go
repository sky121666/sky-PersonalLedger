package service

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"

	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

var ErrIdempotencyConflict = errors.New("该请求标识已用于不同的还款内容，请核对原还款记录")
var ErrInvalidIdempotencyKey = errors.New("idempotency_key must be at most 128 bytes")

// Call only after locking the target business row, inside the business transaction.
// A failed financial write rolls this claim back, allowing a corrected retry.
func claimRepaymentRequest(tx *gorm.DB, userID uint, operation, targetID, key string, payload any) (bool, error) {
	if key == "" {
		return false, nil
	}
	if len(key) > 128 {
		return false, ErrInvalidIdempotencyKey
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return false, err
	}
	keyDigest, payloadDigest := sha256.Sum256([]byte(key)), sha256.Sum256(data)
	claim := model.RepaymentRequest{UserID: userID, Operation: operation, TargetID: targetID,
		KeyHash: hex.EncodeToString(keyDigest[:]), PayloadHash: hex.EncodeToString(payloadDigest[:])}
	var existing model.RepaymentRequest
	err = tx.First(&existing, "user_id = ? AND operation = ? AND target_id = ? AND key_hash = ?", userID, operation, targetID, claim.KeyHash).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return false, tx.Create(&claim).Error
	}
	if err != nil {
		return false, err
	}
	if existing.PayloadHash != claim.PayloadHash {
		return false, ErrIdempotencyConflict
	}
	return true, nil
}
