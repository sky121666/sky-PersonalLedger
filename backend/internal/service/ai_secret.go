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

const aiSecretPrefix = "enc:v1:"

func protectAISecret(plainText string, secret string) (string, error) {
	value := strings.TrimSpace(plainText)
	if value == "" || strings.TrimSpace(secret) == "" {
		return value, nil
	}

	gcm, err := newAIGCM(secret)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}

	ciphertext := gcm.Seal(nil, nonce, []byte(value), nil)
	payload := append(nonce, ciphertext...)
	return aiSecretPrefix + base64.RawStdEncoding.EncodeToString(payload), nil
}

func revealAISecret(protectedValue string, secret string) (string, error) {
	value := strings.TrimSpace(protectedValue)
	if value == "" || !strings.HasPrefix(value, aiSecretPrefix) {
		return value, nil
	}
	if strings.TrimSpace(secret) == "" {
		return "", errors.New("ai secret encryption key is not configured")
	}

	payload, err := base64.RawStdEncoding.DecodeString(strings.TrimPrefix(value, aiSecretPrefix))
	if err != nil {
		return "", err
	}
	gcm, err := newAIGCM(secret)
	if err != nil {
		return "", err
	}
	if len(payload) <= gcm.NonceSize() {
		return "", errors.New("invalid ai secret payload")
	}
	nonce := payload[:gcm.NonceSize()]
	ciphertext := payload[gcm.NonceSize():]
	plainText, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", err
	}
	return string(plainText), nil
}

func revealAISecretWithKeyring(protectedValue string, keyring credentialKeyring) (string, error) {
	value := strings.TrimSpace(protectedValue)
	if value == "" || !strings.HasPrefix(value, aiSecretPrefix) {
		return value, nil
	}
	for _, secret := range keyring.keys {
		plainText, err := revealAISecret(value, secret)
		if err == nil {
			return plainText, nil
		}
	}
	return "", errors.New("ai credential cannot be decrypted with the configured keys")
}

func migrateAISecret(protectedValue string, keyring credentialKeyring) (string, bool, error) {
	value := strings.TrimSpace(protectedValue)
	if value == "" {
		return value, value != protectedValue, nil
	}
	if !strings.HasPrefix(value, aiSecretPrefix) {
		migrated, err := protectAISecret(value, keyring.primary())
		return migrated, migrated != protectedValue, err
	}
	for index, secret := range keyring.keys {
		plainText, err := revealAISecret(value, secret)
		if err != nil {
			continue
		}
		if index == 0 {
			return value, value != protectedValue, nil
		}
		migrated, err := protectAISecret(plainText, keyring.primary())
		if err != nil {
			return "", false, err
		}
		return migrated, true, nil
	}
	return "", false, errors.New("ai credential cannot be decrypted with the configured keys")
}

func newAIGCM(secret string) (cipher.AEAD, error) {
	key := sha256.Sum256([]byte(secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
