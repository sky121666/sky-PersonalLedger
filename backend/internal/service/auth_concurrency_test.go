package service

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/model"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

func TestAuthLoginRejectsVerificationFromBeforePasswordChange(t *testing.T) {
	for _, password := range []string{"LedgerOldPassword123!", "incorrect-password"} {
		t.Run(password, func(t *testing.T) {
			svc, repos := newAuthServiceForTest(t)
			const oldPassword = "LedgerOldPassword123!"
			const newPassword = "LedgerNewPassword123!"
			if _, err := svc.Init(oldPassword); err != nil {
				t.Fatal(err)
			}
			user, err := repos.User.GetByUsername("admin")
			if err != nil {
				t.Fatal(err)
			}
			changed := false
			var changeErr error
			db := repos.User.DB()
			name := "test:change-password-after-login-read"
			if err := db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
				if changed || query.Statement.Table != "users" {
					return
				}
				changed = true
				changeErr = svc.ChangePassword(user.ID, oldPassword, newPassword)
			}); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })

			response, loginErr := svc.Login(password)
			if !changed || changeErr != nil || !errors.Is(loginErr, ErrInvalidPassword) || response != nil {
				t.Fatalf("changed=%v change=%v login=%v returnedTokens=%v", changed, changeErr, loginErr, response != nil)
			}
			stored, err := repos.User.GetByID(user.ID)
			if err != nil {
				t.Fatal(err)
			}
			if bcrypt.CompareHashAndPassword([]byte(stored.PasswordHash), []byte(newPassword)) != nil {
				t.Fatal("concurrent login reverted the new password")
			}
			var tokens int64
			if err := db.Model(&model.RefreshToken{}).Where("user_id = ?", user.ID).Count(&tokens).Error; err != nil {
				t.Fatal(err)
			}
			if tokens != 0 {
				t.Fatalf("stale login created %d refresh tokens after password revocation", tokens)
			}
		})
	}
}

func TestAuthProfileUpdatePreservesConcurrentPasswordChange(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	const oldPassword = "LedgerOldPassword123!"
	const newPassword = "LedgerNewPassword123!"
	if _, err := svc.Init(oldPassword); err != nil {
		t.Fatal(err)
	}
	user, err := repos.User.GetByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	changed := false
	var changeErr error
	db := repos.User.DB()
	name := "test:change-password-after-profile-read"
	if err := db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
		if changed || query.Statement.Table != "users" {
			return
		}
		changed = true
		changeErr = svc.ChangePassword(user.ID, oldPassword, newPassword)
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })
	profile, err := svc.UpdateProfile(user.ID, "New display name", "new@example.test", "", "New bio")
	if err != nil || changeErr != nil {
		t.Fatalf("profile update=%v password change=%v", err, changeErr)
	}
	stored, err := repos.User.GetByID(user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if profile.Nickname != "New display name" || stored.Email != "new@example.test" ||
		bcrypt.CompareHashAndPassword([]byte(stored.PasswordHash), []byte(newPassword)) != nil {
		t.Fatal("profile and password changes did not both survive")
	}
}

func TestAuthPasswordChangeRollsBackWhenSessionRevocationFails(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	const oldPassword = "LedgerOldPassword123!"
	tokens, err := svc.Init(oldPassword)
	if err != nil {
		t.Fatal(err)
	}
	user, err := repos.User.GetByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	forcedErr := errors.New("forced refresh revocation failure")
	db := repos.User.DB()
	name := "test:fail-password-session-revocation"
	if err := db.Callback().Delete().Before("gorm:delete").Register(name, func(query *gorm.DB) {
		if query.Statement.Table == "refresh_tokens" {
			query.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatal(err)
	}
	err = svc.ChangePassword(user.ID, oldPassword, "LedgerNewPassword123!")
	_ = db.Callback().Delete().Remove(name)
	if !errors.Is(err, forcedErr) {
		t.Fatalf("change error=%v, want revocation failure", err)
	}
	stored, err := repos.User.GetByID(user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.PasswordHash != user.PasswordHash {
		t.Fatal("failed password change left the new password committed")
	}
	if _, err := svc.RefreshToken(tokens.RefreshToken); err != nil {
		t.Fatalf("failed password change partially revoked the existing session: %v", err)
	}
}

func TestAuthLoginRollsBackStateWhenSessionCreationFails(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	if _, err := svc.Init("LedgerPassword123!"); err != nil {
		t.Fatal(err)
	}
	user, err := repos.User.GetByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	if err := repos.User.RecordFailedLogin(user.ID, 3, nil); err != nil {
		t.Fatal(err)
	}
	forcedErr := errors.New("forced refresh token creation failure")
	db := repos.User.DB()
	name := "test:fail-login-session-creation"
	if err := db.Callback().Create().Before("gorm:create").Register(name, func(query *gorm.DB) {
		if query.Statement.Table == "refresh_tokens" {
			query.AddError(forcedErr)
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Create().Remove(name) })
	response, err := svc.Login("LedgerPassword123!")
	if !errors.Is(err, forcedErr) || response != nil {
		t.Fatalf("login=%v returnedTokens=%v", err, response != nil)
	}
	stored, err := repos.User.GetByID(user.ID)
	if err != nil {
		t.Fatal(err)
	}
	if stored.LoginFailCount != 3 || stored.LastLoginAt != nil {
		t.Fatal("failed session creation left successful login state committed")
	}
}

func TestAuthConcurrentFailedLoginsAccumulateAndLock(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	if _, err := svc.Init("LedgerPassword123!"); err != nil {
		t.Fatal(err)
	}
	const attempts = 5
	var initialReads atomic.Int32
	allRead := make(chan struct{})
	db := repos.User.DB()
	name := "test:concurrent-login-initial-reads"
	if err := db.Callback().Query().After("gorm:query").Register(name, func(query *gorm.DB) {
		if query.Statement.Table != "users" {
			return
		}
		read := initialReads.Add(1)
		if read == attempts {
			close(allRead)
		}
		if read <= attempts {
			<-allRead
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Query().Remove(name) })
	var wg sync.WaitGroup
	errorsFromLogin := make(chan error, attempts)
	for index := 0; index < attempts; index++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := svc.Login("incorrect-password")
			errorsFromLogin <- err
		}()
	}
	wg.Wait()
	close(errorsFromLogin)
	for err := range errorsFromLogin {
		if !errors.Is(err, ErrInvalidPassword) {
			t.Fatalf("concurrent login error=%v", err)
		}
	}
	user, err := repos.User.GetByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	if user.LoginFailCount != attempts || user.LockedUntil == nil || !user.LockedUntil.After(time.Now()) {
		t.Fatalf("concurrent failures=%d locked=%v", user.LoginFailCount, user.LockedUntil != nil)
	}
}

func TestAuthPasswordChangeRevokesRefreshIssuedWhileChangeStarts(t *testing.T) {
	svc, repos := newAuthServiceForTest(t)
	const oldPassword = "LedgerOldPassword123!"
	tokens, err := svc.Init(oldPassword)
	if err != nil {
		t.Fatal(err)
	}
	user, err := repos.User.GetByUsername("admin")
	if err != nil {
		t.Fatal(err)
	}
	db := repos.User.DB()
	refreshInside := make(chan struct{})
	finishRefresh := make(chan struct{})
	changeStarted := make(chan struct{})
	var firstCreate atomic.Bool
	var observeChange atomic.Bool
	createName := "test:pause-refresh-issuance"
	queryName := "test:observe-password-change-start"
	if err := db.Callback().Create().Before("gorm:create").Register(createName, func(query *gorm.DB) {
		if query.Statement.Table == "refresh_tokens" && firstCreate.CompareAndSwap(false, true) {
			close(refreshInside)
			<-finishRefresh
		}
	}); err != nil {
		t.Fatal(err)
	}
	if err := db.Callback().Query().After("gorm:query").Register(queryName, func(query *gorm.DB) {
		if query.Statement.Table == "users" && observeChange.CompareAndSwap(true, false) {
			close(changeStarted)
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_ = db.Callback().Create().Remove(createName)
		_ = db.Callback().Query().Remove(queryName)
	})
	type refreshResult struct {
		response *AuthResponse
		err      error
	}
	refreshed := make(chan refreshResult, 1)
	go func() {
		response, err := svc.RefreshToken(tokens.RefreshToken)
		refreshed <- refreshResult{response, err}
	}()
	<-refreshInside
	observeChange.Store(true)
	changed := make(chan error, 1)
	go func() { changed <- svc.ChangePassword(user.ID, oldPassword, "LedgerNewPassword123!") }()
	<-changeStarted
	close(finishRefresh)
	result := <-refreshed
	if result.err != nil {
		t.Fatalf("refresh before revocation: %v", result.err)
	}
	if err := <-changed; err != nil {
		t.Fatalf("change password: %v", err)
	}
	if _, err := svc.RefreshToken(result.response.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("concurrent old-session refresh survived password change: %v", err)
	}
}
