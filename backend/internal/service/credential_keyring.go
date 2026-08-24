package service

import (
	"strings"

	"github.com/sky/personal-ledger/internal/config"
)

// credentialKeyring keeps the active encryption key first, followed by
// read-only fallback keys accepted during a migration window.
type credentialKeyring struct {
	keys []string
}

func newCredentialKeyring(values ...string) credentialKeyring {
	keys := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		if strings.TrimSpace(value) == "" {
			continue
		}
		if _, exists := seen[value]; exists {
			continue
		}
		seen[value] = struct{}{}
		keys = append(keys, value)
	}
	return credentialKeyring{keys: keys}
}

func (k credentialKeyring) primary() string {
	if len(k.keys) == 0 {
		return ""
	}
	return k.keys[0]
}

// credentialEncryptionSecrets returns the active key first. Deployments that
// have not configured an independent key retain the legacy JWT-derived key.
// Once an independent key is configured, the current JWT secret remains a
// migration fallback for ciphertext written by older releases.
func credentialEncryptionSecrets(cfg *config.Config) []string {
	if cfg == nil {
		return nil
	}
	values := make([]string, 0, 3)
	if strings.TrimSpace(cfg.Credentials.EncryptionKey) != "" {
		values = append(values, cfg.Credentials.EncryptionKey, cfg.JWT.Secret)
	} else {
		values = append(values, cfg.JWT.Secret)
	}
	values = append(values, cfg.Credentials.EncryptionPreviousKey)
	return newCredentialKeyring(values...).keys
}
