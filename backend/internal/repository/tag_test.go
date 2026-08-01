package repository

import (
	"path/filepath"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
)

func TestTagRepositoryUsageCountAdjustmentsAreScopedDeduplicatedAndClamped(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := NewRepositories(db)
	owner := &model.User{Username: "tag-usage-owner", PasswordHash: "hash"}
	other := &model.User{Username: "tag-usage-other", PasswordHash: "hash"}
	if err := repos.User.Create(owner); err != nil {
		t.Fatalf("create owner: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}

	for _, tag := range []*model.Tag{
		{UserID: owner.ID, Name: "food"},
		{UserID: owner.ID, Name: "travel", UsedCount: 2},
		{UserID: other.ID, Name: "food", UsedCount: 7},
	} {
		if err := repos.Tag.Create(tag); err != nil {
			t.Fatalf("create tag %q for user %d: %v", tag.Name, tag.UserID, err)
		}
	}

	if err := repos.Tag.IncrementUsedCountsByNames(owner.ID, []string{"travel", "food", "food", "missing", ""}); err != nil {
		t.Fatalf("increment tag usage: %v", err)
	}
	assertRepositoryTagUsedCount(t, repos.Tag, owner.ID, "food", 1)
	assertRepositoryTagUsedCount(t, repos.Tag, owner.ID, "travel", 3)
	assertRepositoryTagUsedCount(t, repos.Tag, other.ID, "food", 7)

	if err := repos.Tag.DecrementUsedCountsByNames(owner.ID, []string{"food", "food"}); err != nil {
		t.Fatalf("decrement duplicate tag usage: %v", err)
	}
	if err := repos.Tag.DecrementUsedCountsByNames(owner.ID, []string{"food"}); err != nil {
		t.Fatalf("decrement zero tag usage: %v", err)
	}
	assertRepositoryTagUsedCount(t, repos.Tag, owner.ID, "food", 0)
	assertRepositoryTagUsedCount(t, repos.Tag, other.ID, "food", 7)
}

func assertRepositoryTagUsedCount(t *testing.T, repo *TagRepository, userID uint, name string, want int) {
	t.Helper()
	tag, err := repo.GetByName(userID, name)
	if err != nil {
		t.Fatalf("get tag %q for user %d: %v", name, userID, err)
	}
	if tag.UsedCount != want {
		t.Fatalf("tag %q for user %d used_count = %d, want %d", name, userID, tag.UsedCount, want)
	}
}
