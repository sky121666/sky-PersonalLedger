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

func newAIGCM(secret string) (cipher.AEAD, error) {
	key := sha256.Sum256([]byte(secret))
	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
