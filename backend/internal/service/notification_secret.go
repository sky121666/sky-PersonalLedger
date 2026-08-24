package service

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"io"
	"strings"
)

// Notification credentials have their own envelope and derived key domain, so
// ciphertext cannot be swapped with AI provider credentials even though both
// use the operator-managed credential encryption keyring.
const notificationSecretPrefix = "enc:notification:v1:"

func protectNotificationSecret(plainText string, secret string) (string, error) {
	if plainText == "" || strings.TrimSpace(secret) == "" {
		return plainText, nil
	}

	gcm, err := newNotificationGCM(secret)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	ciphertext := gcm.Seal(nil, nonce, []byte(plainText), nil)
	payload := append(nonce, ciphertext...)
	return notificationSecretPrefix + base64.RawStdEncoding.EncodeToString(payload), nil
}

func revealNotificationSecret(protectedValue string, secret string) (string, error) {
	if protectedValue == "" || !isProtectedNotificationSecret(protectedValue) {
		return protectedValue, nil
	}
	if strings.TrimSpace(secret) == "" {
		return "", errors.New("notification credential encryption key is not configured")
	}

	payload, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(protectedValue, notificationSecretPrefix))
	if err != nil {
		return "", errors.New("invalid encrypted notification credential")
	}
	gcm, err := newNotificationGCM(secret)
	if err != nil {
		return "", err
	}
	if len(payload) <= gcm.NonceSize() {
		return "", errors.New("invalid encrypted notification credential")
	}

	nonce := payload[:gcm.NonceSize()]
	ciphertext := payload[gcm.NonceSize():]
	plainText, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", errors.New("invalid encrypted notification credential")
	}
	return string(plainText), nil
}

func revealNotificationSecretWithKeyring(protectedValue string, keyring credentialKeyring) (string, error) {
	if protectedValue == "" || !isProtectedNotificationSecret(protectedValue) {
		return protectedValue, nil
	}
	for _, secret := range keyring.keys {
		plainText, err := revealNotificationSecret(protectedValue, secret)
		if err == nil {
			return plainText, nil
		}
	}
	return "", errors.New("notification credential cannot be decrypted with the configured keys")
}

func migrateNotificationSecret(protectedValue string, keyring credentialKeyring) (string, bool, error) {
	if protectedValue == "" {
		return protectedValue, false, nil
	}
	if !isProtectedNotificationSecret(protectedValue) {
		migrated, err := protectNotificationSecret(protectedValue, keyring.primary())
		return migrated, migrated != protectedValue, err
	}
	for index, secret := range keyring.keys {
		plainText, err := revealNotificationSecret(protectedValue, secret)
		if err != nil {
			continue
		}
		if index == 0 {
			return protectedValue, false, nil
		}
		migrated, err := protectNotificationSecret(plainText, keyring.primary())
		if err != nil {
			return "", false, err
		}
		return migrated, true, nil
	}
	return "", false, errors.New("notification credential cannot be decrypted with the configured keys")
}

func isProtectedNotificationSecret(value string) bool {
	return strings.HasPrefix(value, notificationSecretPrefix)
}

func newNotificationGCM(secret string) (cipher.AEAD, error) {
	key := sha256.Sum256([]byte("personal-ledger/notification-credentials/v1\x00" + secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
