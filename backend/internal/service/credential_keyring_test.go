package service

import (
	"reflect"
	"testing"

	"github.com/sky/personal-ledger/internal/config"
)

func TestCredentialEncryptionSecretsKeepsLegacyJWTCompatibility(t *testing.T) {
	legacyJWT := "legacy-jwt-secret-with-at-least-32-characters"
	if got := credentialEncryptionSecrets(&config.Config{JWT: config.JWTConfig{Secret: legacyJWT}}); !reflect.DeepEqual(got, []string{legacyJWT}) {
		t.Fatalf("legacy credential keys = %#v, want JWT fallback", got)
	}
}

func TestCredentialEncryptionSecretsOrdersMigrationKeys(t *testing.T) {
	active := "active-credential-key-with-at-least-32-characters"
	legacyJWT := "legacy-jwt-secret-with-at-least-32-characters"
	previous := "previous-credential-key-with-at-least-32-characters"
	cfg := &config.Config{
		JWT: config.JWTConfig{Secret: legacyJWT},
		Credentials: config.CredentialConfig{
			EncryptionKey:         active,
			EncryptionPreviousKey: previous,
		},
	}
	want := []string{active, legacyJWT, previous}
	if got := credentialEncryptionSecrets(cfg); !reflect.DeepEqual(got, want) {
		t.Fatalf("credential keys = %#v, want %#v", got, want)
	}
}

func TestCredentialEncryptionSecretsDeduplicatesFallbacks(t *testing.T) {
	active := "active-credential-key-with-at-least-32-characters"
	cfg := &config.Config{
		JWT: config.JWTConfig{Secret: active},
		Credentials: config.CredentialConfig{
			EncryptionKey:         active,
			EncryptionPreviousKey: active,
		},
	}
	if got := credentialEncryptionSecrets(cfg); !reflect.DeepEqual(got, []string{active}) {
		t.Fatalf("deduplicated credential keys = %#v", got)
	}
}
