package jwt

import (
	"errors"
	"testing"
)

func TestGenerateRefreshTokenIsUniqueForSameUserWithinSecond(t *testing.T) {
	manager := NewManager("test-secret-with-enough-length", 15, 60)

	first, _, err := manager.GenerateRefreshToken(1)
	if err != nil {
		t.Fatalf("generate first refresh token: %v", err)
	}
	second, _, err := manager.GenerateRefreshToken(1)
	if err != nil {
		t.Fatalf("generate second refresh token: %v", err)
	}

	if first == second {
		t.Fatal("refresh tokens generated in the same second should be unique")
	}
}

func TestTokenValidatorsEnforceTokenType(t *testing.T) {
	manager := NewManager("test-secret-with-enough-length", 15, 60)

	accessToken, err := manager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}
	refreshToken, _, err := manager.GenerateRefreshToken(1)
	if err != nil {
		t.Fatalf("generate refresh token: %v", err)
	}

	accessClaims, err := manager.ValidateAccessToken(accessToken)
	if err != nil {
		t.Fatalf("validate access token: %v", err)
	}
	if accessClaims.TokenType != tokenTypeAccess {
		t.Fatalf("access token type = %q, want %q", accessClaims.TokenType, tokenTypeAccess)
	}
	if accessClaims.Issuer != tokenIssuer || len(accessClaims.Audience) != 1 || accessClaims.Audience[0] != accessAudience {
		t.Fatalf("access issuer/audience = %q/%v, want %q/%q", accessClaims.Issuer, accessClaims.Audience, tokenIssuer, accessAudience)
	}

	refreshClaims, err := manager.ValidateRefreshToken(refreshToken)
	if err != nil {
		t.Fatalf("validate refresh token: %v", err)
	}
	if refreshClaims.TokenType != tokenTypeRefresh {
		t.Fatalf("refresh token type = %q, want %q", refreshClaims.TokenType, tokenTypeRefresh)
	}
	if refreshClaims.Issuer != tokenIssuer || len(refreshClaims.Audience) != 1 || refreshClaims.Audience[0] != refreshAudience {
		t.Fatalf("refresh issuer/audience = %q/%v, want %q/%q", refreshClaims.Issuer, refreshClaims.Audience, tokenIssuer, refreshAudience)
	}

	if _, err := manager.ValidateAccessToken(refreshToken); !errors.Is(err, ErrInvalidTokenType) {
		t.Fatalf("validate refresh as access error = %v, want %v", err, ErrInvalidTokenType)
	}
	if _, err := manager.ValidateRefreshToken(accessToken); !errors.Is(err, ErrInvalidTokenType) {
		t.Fatalf("validate access as refresh error = %v, want %v", err, ErrInvalidTokenType)
	}
	if _, err := manager.ValidateToken(refreshToken); !errors.Is(err, ErrInvalidTokenType) {
		t.Fatalf("legacy validator accepted refresh token: %v", err)
	}
}
