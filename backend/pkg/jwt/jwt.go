package jwt

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

var (
	ErrInvalidToken     = errors.New("invalid token")
	ErrExpiredToken     = errors.New("token has expired")
	ErrInvalidTokenType = errors.New("invalid token type")
)

const (
	tokenTypeAccess  = "access"
	tokenTypeRefresh = "refresh"
	tokenIssuer      = "personal-ledger"
	accessAudience   = "personal-ledger-api"
	refreshAudience  = "personal-ledger-auth"
)

type Claims struct {
	UserID    uint   `json:"user_id"`
	TokenType string `json:"token_type"`
	jwt.RegisteredClaims
}

type Manager struct {
	secretKey     []byte
	accessExpire  time.Duration
	refreshExpire time.Duration
}

func NewManager(secret string, accessExpireMinutes, refreshExpireMinutes int) *Manager {
	return &Manager{
		secretKey:     []byte(secret),
		accessExpire:  time.Duration(accessExpireMinutes) * time.Minute,
		refreshExpire: time.Duration(refreshExpireMinutes) * time.Minute,
	}
}

func (m *Manager) GenerateAccessToken(userID uint) (string, error) {
	claims := Claims{
		UserID:    userID,
		TokenType: tokenTypeAccess,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tokenIssuer,
			Audience:  jwt.ClaimStrings{accessAudience},
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(m.accessExpire)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(m.secretKey)
}

func (m *Manager) GenerateRefreshToken(userID uint) (string, time.Time, error) {
	expiresAt := time.Now().Add(m.refreshExpire)
	claims := Claims{
		UserID:    userID,
		TokenType: tokenTypeRefresh,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    tokenIssuer,
			Audience:  jwt.ClaimStrings{refreshAudience},
			ExpiresAt: jwt.NewNumericDate(expiresAt),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ID:        uuid.New().String(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(m.secretKey)
	return tokenString, expiresAt, err
}

// ValidateToken validates access tokens. It is kept for compatibility with
// existing access-token call sites; refresh tokens are deliberately rejected.
func (m *Manager) ValidateToken(tokenString string) (*Claims, error) {
	return m.ValidateAccessToken(tokenString)
}

func (m *Manager) ValidateAccessToken(tokenString string) (*Claims, error) {
	return m.validateToken(tokenString, tokenTypeAccess, accessAudience)
}

func (m *Manager) ValidateRefreshToken(tokenString string) (*Claims, error) {
	return m.validateToken(tokenString, tokenTypeRefresh, refreshAudience)
}

func (m *Manager) validateToken(tokenString, expectedType, expectedAudience string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		return m.secretKey, nil
	},
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithExpirationRequired(),
		jwt.WithIssuer(tokenIssuer),
	)

	if err != nil {
		if errors.Is(err, jwt.ErrTokenExpired) {
			return nil, ErrExpiredToken
		}
		return nil, ErrInvalidToken
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return nil, ErrInvalidToken
	}
	if claims.TokenType != expectedType {
		return nil, ErrInvalidTokenType
	}
	if !containsAudience(claims.Audience, expectedAudience) {
		return nil, ErrInvalidToken
	}

	return claims, nil
}

func containsAudience(audiences jwt.ClaimStrings, expected string) bool {
	for _, audience := range audiences {
		if audience == expected {
			return true
		}
	}
	return false
}

func (m *Manager) GetAccessExpireSeconds() int {
	return int(m.accessExpire.Seconds())
}

func (m *Manager) GetRefreshExpireSeconds() int {
	return int(m.refreshExpire.Seconds())
}
