package repository

import (
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestAuthenticationUpdatesPreserveConcurrentProfileAndClearLockState(t *testing.T) {
	repos, owner, _ := newRepositoryTestFixture(t)
	staleProfile := *owner
	lockedUntil := time.Now().UTC().Add(time.Hour).Truncate(time.Second)
	if err := repos.User.UpdatePasswordHash(owner.ID, "rotated-password-hash"); err != nil {
		t.Fatal(err)
	}
	if err := repos.User.RecordFailedLogin(owner.ID, 3, &lockedUntil); err != nil {
		t.Fatal(err)
	}
	staleProfile.Nickname = "Updated display name"
	if err := repos.User.UpdateProfile(&staleProfile); err != nil {
		t.Fatal(err)
	}
	current, err := repos.User.GetByID(owner.ID)
	if err != nil || current.PasswordHash != "rotated-password-hash" || current.LoginFailCount != 3 || current.LockedUntil == nil {
		t.Fatalf("stale profile overwrote authentication state: %#v err=%v", current, err)
	}
	at := time.Now().UTC().Truncate(time.Second)
	if err := repos.User.RecordSuccessfulLogin(owner.ID, at); err != nil {
		t.Fatal(err)
	}
	if err := repos.User.DB().Transaction(func(tx *gorm.DB) error {
		locked, err := NewUserRepository(tx).GetByIDForUpdate(owner.ID)
		if err != nil {
			return err
		}
		if locked.Nickname != staleProfile.Nickname || locked.PasswordHash != "rotated-password-hash" ||
			locked.LoginFailCount != 0 || locked.LockedUntil != nil || locked.LastLoginAt == nil || !locked.LastLoginAt.Equal(at) {
			t.Fatalf("successful login did not preserve profile/reset auth state: %#v", locked)
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if err := repos.User.UpdatePasswordHash(owner.ID+1000, "unowned"); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("missing user password update appeared successful: %v", err)
	}
	if _, err := repos.User.GetByID(owner.ID + 1000); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatal(err)
	}
	if _, err := repos.User.GetByUsername("absent-user"); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatal(err)
	}
}

func TestRefreshSessionDeletionPreservesIndependentAndOtherUserSessions(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	expiry := time.Now().Add(time.Hour)
	family := &model.RefreshToken{ID: uuid.NewString(), UserID: owner.ID, Token: "rotated-family", ExpiresAt: expiry}
	independent := &model.RefreshToken{ID: uuid.NewString(), UserID: owner.ID, Token: "independent-new-login", ExpiresAt: expiry}
	otherUser := &model.RefreshToken{ID: uuid.NewString(), UserID: other.ID, Token: "other-user", ExpiresAt: expiry}
	for _, token := range []*model.RefreshToken{family, independent, otherUser} {
		if err := repos.RefreshToken.Create(token); err != nil {
			t.Fatal(err)
		}
	}
	deleted, err := repos.RefreshToken.DeleteSession(other.ID, family.ID, family.Token, "legacy-original")
	if err != nil || deleted {
		t.Fatalf("different user's request deleted family: deleted=%v err=%v", deleted, err)
	}
	deleted, err = repos.RefreshToken.DeleteSession(owner.ID, family.ID, "old-hash", "old-original")
	if err != nil || !deleted {
		t.Fatalf("rotated family not revoked: deleted=%v err=%v", deleted, err)
	}
	deleted, err = repos.RefreshToken.DeleteSession(owner.ID, family.ID, "old-hash", "old-original")
	if err != nil || deleted {
		t.Fatalf("repeated revocation reported an active session: deleted=%v err=%v", deleted, err)
	}
	for _, token := range []*model.RefreshToken{independent, otherUser} {
		if _, err := repos.RefreshToken.GetByToken(token.Token); err != nil {
			t.Fatalf("unrelated login revoked: %v", err)
		}
	}
	if _, err := repos.RefreshToken.GetByToken(family.Token); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("revoked family remains active: %v", err)
	}
}
