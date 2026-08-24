package service

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/jwt"
	"github.com/sky/personal-ledger/pkg/validator"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

var (
	ErrUserExists       = errors.New("user already exists")
	ErrInvalidPassword  = errors.New("invalid password")
	ErrUserLocked       = errors.New("user account is locked")
	ErrInvalidToken     = errors.New("invalid refresh token")
	ErrPasswordTooShort = errors.New("password must be at least 8 characters")
)

var authInitMu sync.Mutex

type AuthService struct {
	userRepo         *repository.UserRepository
	refreshTokenRepo *repository.RefreshTokenRepository
	categoryRepo     *repository.CategoryRepository
	accountRepo      *repository.AccountRepository
	jwtManager       *jwt.Manager
}

func NewAuthService(
	userRepo *repository.UserRepository,
	refreshTokenRepo *repository.RefreshTokenRepository,
	categoryRepo *repository.CategoryRepository,
	accountRepo *repository.AccountRepository,
	jwtManager *jwt.Manager,
) *AuthService {
	return &AuthService{
		userRepo:         userRepo,
		refreshTokenRepo: refreshTokenRepo,
		categoryRepo:     categoryRepo,
		accountRepo:      accountRepo,
		jwtManager:       jwtManager,
	}
}

type AuthResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token,omitempty"`
	ExpiresIn    int    `json:"expires_in"`
}

func (s *AuthService) Init(password string) (*AuthResponse, error) {
	if err := validator.ValidatePasswordSimple(password); err != nil {
		return nil, err
	}

	count, err := s.userRepo.Count()
	if err != nil {
		return nil, err
	}
	if count > 0 {
		return nil, ErrUserExists
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), 12)
	if err != nil {
		return nil, err
	}

	authInitMu.Lock()
	defer authInitMu.Unlock()

	var userID uint
	if err := s.userRepo.DB().Transaction(func(tx *gorm.DB) error {
		var count int64
		if err := tx.Model(&model.User{}).Count(&count).Error; err != nil {
			return err
		}
		if count > 0 {
			return ErrUserExists
		}

		user := &model.User{
			Username:     "admin",
			PasswordHash: string(hash),
		}
		if err := tx.Create(user).Error; err != nil {
			if isUniqueUserConstraintError(err) {
				return ErrUserExists
			}
			return err
		}

		if err := s.createDefaultCategoriesTx(tx, user.ID); err != nil {
			return err
		}
		if err := s.createDefaultAccountsTx(tx, user.ID); err != nil {
			return err
		}

		userID = user.ID
		return nil
	}); err != nil {
		return nil, err
	}

	return s.generateTokens(userID)
}

func (s *AuthService) Login(password string) (*AuthResponse, error) {
	user, err := s.userRepo.GetByUsername("admin")
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrInvalidPassword
		}
		return nil, fmt.Errorf("load login user: %w", err)
	}

	// Check if locked
	if user.LockedUntil != nil && user.LockedUntil.After(time.Now()) {
		return nil, ErrUserLocked
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password)); err != nil {
		// Increment fail count
		user.LoginFailCount++
		if user.LoginFailCount >= 5 {
			lockUntil := time.Now().Add(15 * time.Minute)
			user.LockedUntil = &lockUntil
		}
		if err := s.userRepo.Update(user); err != nil {
			return nil, fmt.Errorf("persist failed login state: %w", err)
		}
		return nil, ErrInvalidPassword
	}

	// Reset fail count on success
	user.LoginFailCount = 0
	user.LockedUntil = nil
	now := time.Now()
	user.LastLoginAt = &now
	if err := s.userRepo.Update(user); err != nil {
		return nil, fmt.Errorf("persist successful login state: %w", err)
	}

	return s.generateTokens(user.ID)
}

func (s *AuthService) RefreshToken(refreshToken string) (*AuthResponse, error) {
	normalizedToken := strings.TrimSpace(refreshToken)
	if normalizedToken == "" {
		return nil, ErrInvalidToken
	}
	claims, err := s.jwtManager.ValidateRefreshToken(normalizedToken)
	if err != nil {
		return nil, ErrInvalidToken
	}

	if claims.UserID == 0 {
		return nil, ErrInvalidToken
	}

	var response *AuthResponse
	err = s.userRepo.DB().Transaction(func(txdb *gorm.DB) error {
		repo := repository.NewRefreshTokenRepository(txdb)
		now := time.Now()
		consumed, err := repo.Consume(hashRefreshToken(normalizedToken), claims.UserID, now)
		if err != nil {
			return err
		}
		if !consumed {
			// One-time migration path for refresh tokens stored in plaintext by
			// releases before token hashing was introduced.
			consumed, err = repo.Consume(normalizedToken, claims.UserID, now)
			if err != nil {
				return err
			}
		}
		if !consumed {
			return ErrInvalidToken
		}
		response, err = s.generateTokensWithRepository(claims.UserID, repo)
		return err
	})
	if err != nil {
		return nil, err
	}
	return response, nil
}

func (s *AuthService) Logout(userID uint) error {
	return s.refreshTokenRepo.DeleteByUserID(userID)
}

func (s *AuthService) ChangePassword(userID uint, oldPassword, newPassword string) error {
	if err := validator.ValidatePasswordSimple(newPassword); err != nil {
		return err
	}

	user, err := s.userRepo.GetByID(userID)
	if err != nil {
		return err
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(oldPassword)); err != nil {
		return ErrInvalidPassword
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(newPassword), 12)
	if err != nil {
		return err
	}

	user.PasswordHash = string(hash)
	if err := s.userRepo.Update(user); err != nil {
		return err
	}

	// Invalidate all tokens
	return s.refreshTokenRepo.DeleteByUserID(userID)
}

func (s *AuthService) IsInitialized() (bool, error) {
	count, err := s.userRepo.Count()
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (s *AuthService) GetJWTManager() *jwt.Manager {
	return s.jwtManager
}

func (s *AuthService) generateTokens(userID uint) (*AuthResponse, error) {
	return s.generateTokensWithRepository(userID, s.refreshTokenRepo)
}

func (s *AuthService) generateTokensWithRepository(userID uint, refreshTokens *repository.RefreshTokenRepository) (*AuthResponse, error) {
	accessToken, err := s.jwtManager.GenerateAccessToken(userID)
	if err != nil {
		return nil, err
	}

	refreshToken, expiresAt, err := s.jwtManager.GenerateRefreshToken(userID)
	if err != nil {
		return nil, err
	}

	rt := &model.RefreshToken{
		ID:        uuid.New().String(),
		UserID:    userID,
		Token:     hashRefreshToken(refreshToken),
		ExpiresAt: expiresAt,
	}
	if err := refreshTokens.Create(rt); err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    s.jwtManager.GetAccessExpireSeconds(),
	}, nil
}

func hashRefreshToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

func (s *AuthService) createDefaultCategories(userID uint) error {
	return s.createDefaultCategoriesTx(s.categoryRepo.DB(), userID)
}

func (s *AuthService) createDefaultCategoriesTx(tx *gorm.DB, userID uint) error {
	type categoryDef struct {
		Name  string
		Icon  string
		Color string
	}

	expenseCategories := []categoryDef{
		{"餐饮", "🍽️", "#FF6B6B"},
		{"交通", "🚗", "#4ECDC4"},
		{"购物", "🛒", "#FFE66D"},
		{"居住", "🏠", "#F38181"},
		{"娱乐", "🎮", "#95E1D3"},
		{"医疗", "💊", "#AA96DA"},
		{"通讯", "📞", "#0984E3"},
		{"还款", "💳", "#8B5CF6"},
		{"其他", "📝", "#636E72"},
	}

	incomeCategories := []categoryDef{
		{"工资", "💰", "#27AE60"},
		{"理财", "📈", "#3498DB"},
		{"其他", "💵", "#95A5A6"},
	}

	var categories []model.Category

	for i, cat := range expenseCategories {
		categories = append(categories, model.Category{
			ID:        uuid.New().String(),
			UserID:    userID,
			Name:      cat.Name,
			Type:      "expense",
			Icon:      cat.Icon,
			Color:     cat.Color,
			IsSystem:  true,
			SortOrder: i,
		})
	}

	for i, cat := range incomeCategories {
		categories = append(categories, model.Category{
			ID:        uuid.New().String(),
			UserID:    userID,
			Name:      cat.Name,
			Type:      "income",
			Icon:      cat.Icon,
			Color:     cat.Color,
			IsSystem:  true,
			SortOrder: i,
		})
	}

	return tx.Create(&categories).Error
}

func (s *AuthService) createDefaultAccounts(userID uint) error {
	return s.createDefaultAccountsTx(s.accountRepo.DB(), userID)
}

func (s *AuthService) createDefaultAccountsTx(tx *gorm.DB, userID uint) error {
	type accountDef struct {
		Name  string
		Type  string
		Icon  string
		Color string
	}

	defaultAccounts := []accountDef{
		{"现金", "cash", "banknote", "#10B981"},
		{"银行卡", "bank_card", "landmark", "#3B82F6"},
		{"支付宝", "alipay", "circle-dot", "#1677FF"},
		{"微信", "wechat", "message-circle", "#07C160"},
	}

	var accounts []model.Account
	for i, acc := range defaultAccounts {
		accounts = append(accounts, model.Account{
			ID:        uuid.New().String(),
			UserID:    userID,
			Name:      acc.Name,
			Type:      acc.Type,
			Icon:      acc.Icon,
			Color:     acc.Color,
			SortOrder: i,
		})
	}

	return tx.Create(&accounts).Error
}

func isUniqueUserConstraintError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, gorm.ErrDuplicatedKey) {
		return true
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "unique") && strings.Contains(message, "user")
}

func (s *AuthService) GetUserByID(userID uint) (*model.User, error) {
	return s.userRepo.GetByID(userID)
}

func (s *AuthService) UserExists() bool {
	count, err := s.userRepo.Count()
	if err != nil {
		return false
	}
	return count > 0
}

type UserProfile struct {
	ID          uint   `json:"id"`
	Username    string `json:"username"`
	Nickname    string `json:"nickname"`
	Email       string `json:"email"`
	Avatar      string `json:"avatar"`
	Bio         string `json:"bio"`
	CreatedAt   string `json:"created_at"`
	LastLoginAt string `json:"last_login_at,omitempty"`
}

func (s *AuthService) GetProfile(userID uint) (*UserProfile, error) {
	user, err := s.userRepo.GetByID(userID)
	if err != nil {
		return nil, err
	}

	profile := &UserProfile{
		ID:        user.ID,
		Username:  user.Username,
		Nickname:  user.Nickname,
		Email:     user.Email,
		Avatar:    user.Avatar,
		Bio:       user.Bio,
		CreatedAt: user.CreatedAt.Format("2006-01-02"),
	}
	if user.LastLoginAt != nil {
		profile.LastLoginAt = user.LastLoginAt.Format("2006-01-02 15:04:05")
	}
	return profile, nil
}

func (s *AuthService) UpdateProfile(userID uint, nickname, email, avatar, bio string) (*UserProfile, error) {
	user, err := s.userRepo.GetByID(userID)
	if err != nil {
		return nil, err
	}

	user.Nickname = nickname
	user.Email = email
	user.Avatar = avatar
	user.Bio = bio

	if err := s.userRepo.Update(user); err != nil {
		return nil, err
	}

	return s.GetProfile(userID)
}

var _ = gorm.ErrRecordNotFound // ensure gorm is imported
