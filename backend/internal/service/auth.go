package service

import (
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/jwt"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

var (
	ErrUserExists       = errors.New("user already exists")
	ErrInvalidPassword  = errors.New("invalid password")
	ErrUserLocked       = errors.New("user account is locked")
	ErrInvalidToken     = errors.New("invalid refresh token")
	ErrPasswordTooShort = errors.New("password must be at least 6 characters")
)

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
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

func (s *AuthService) Init(password string) (*AuthResponse, error) {
	if len(password) < 6 {
		return nil, ErrPasswordTooShort
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

	user := &model.User{
		Username:     "admin",
		PasswordHash: string(hash),
	}
	if err := s.userRepo.Create(user); err != nil {
		return nil, err
	}

	// Create default categories
	if err := s.createDefaultCategories(user.ID); err != nil {
		return nil, err
	}

	// Create default accounts
	if err := s.createDefaultAccounts(user.ID); err != nil {
		return nil, err
	}

	return s.generateTokens(user.ID)
}

func (s *AuthService) Login(password string) (*AuthResponse, error) {
	user, err := s.userRepo.GetByUsername("admin")
	if err != nil {
		return nil, ErrInvalidPassword
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
		s.userRepo.Update(user)
		return nil, ErrInvalidPassword
	}

	// Reset fail count on success
	user.LoginFailCount = 0
	user.LockedUntil = nil
	now := time.Now()
	user.LastLoginAt = &now
	s.userRepo.Update(user)

	return s.generateTokens(user.ID)
}

func (s *AuthService) RefreshToken(refreshToken string) (*AuthResponse, error) {
	rt, err := s.refreshTokenRepo.GetByToken(refreshToken)
	if err != nil {
		return nil, ErrInvalidToken
	}

	if rt.ExpiresAt.Before(time.Now()) {
		s.refreshTokenRepo.Delete(rt.ID)
		return nil, ErrInvalidToken
	}

	// Delete old token
	s.refreshTokenRepo.Delete(rt.ID)

	return s.generateTokens(rt.UserID)
}

func (s *AuthService) Logout(userID uint) error {
	return s.refreshTokenRepo.DeleteByUserID(userID)
}

func (s *AuthService) ChangePassword(userID uint, oldPassword, newPassword string) error {
	if len(newPassword) < 6 {
		return ErrPasswordTooShort
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
		Token:     refreshToken,
		ExpiresAt: expiresAt,
	}
	if err := s.refreshTokenRepo.Create(rt); err != nil {
		return nil, err
	}

	return &AuthResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    s.jwtManager.GetAccessExpireSeconds(),
	}, nil
}

func (s *AuthService) createDefaultCategories(userID uint) error {
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

	return s.categoryRepo.CreateBatch(categories)
}

func (s *AuthService) createDefaultAccounts(userID uint) error {
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

	return s.accountRepo.CreateBatch(accounts)
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
