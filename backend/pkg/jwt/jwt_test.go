package jwt

import "testing"

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
