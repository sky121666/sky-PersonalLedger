package repository

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
	"gorm.io/gorm"
)

func TestUserAndCategoryRepositoriesPersistAndScopeData(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)

	owner.Nickname = "Owner"
	if err := repos.User.Update(owner); err != nil {
		t.Fatalf("update user: %v", err)
	}
	byID, err := repos.User.GetByID(owner.ID)
	if err != nil || byID.Nickname != "Owner" {
		t.Fatalf("get user by id = %#v, err=%v", byID, err)
	}
	byName, err := repos.User.GetByUsername(owner.Username)
	if err != nil || byName.ID != owner.ID {
		t.Fatalf("get user by username = %#v, err=%v", byName, err)
	}
	count, err := repos.User.Count()
	if err != nil || count != 2 {
		t.Fatalf("user count = %d, err=%v; want 2", count, err)
	}
	all, err := repos.User.GetAll()
	if err != nil || len(all) != 2 || repos.User.DB() == nil {
		t.Fatalf("all users = %#v, err=%v", all, err)
	}

	categories := []model.Category{
		{ID: uuid.NewString(), UserID: owner.ID, Name: "Later", Type: "expense", SortOrder: 2},
		{ID: uuid.NewString(), UserID: owner.ID, Name: "First", Type: "income", SortOrder: 1},
		{ID: uuid.NewString(), UserID: other.ID, Name: "Other", Type: "expense"},
	}
	if err := repos.Category.CreateBatch(categories); err != nil {
		t.Fatalf("create categories: %v", err)
	}
	ownerCategories, err := repos.Category.GetByUserID(owner.ID, "")
	if err != nil || len(ownerCategories) != 2 || ownerCategories[0].Name != "First" {
		t.Fatalf("owner categories = %#v, err=%v", ownerCategories, err)
	}
	income, err := repos.Category.GetByUserID(owner.ID, "income")
	if err != nil || len(income) != 1 || income[0].Name != "First" {
		t.Fatalf("income categories = %#v, err=%v", income, err)
	}
	category, err := repos.Category.GetByID(categories[0].ID)
	if err != nil {
		t.Fatalf("get category: %v", err)
	}
	category.Name = "Updated"
	if err := repos.Category.Update(category); err != nil {
		t.Fatalf("update category: %v", err)
	}
	if err := repos.Category.Delete(category.ID); err != nil {
		t.Fatalf("delete category: %v", err)
	}
	if _, err := repos.Category.GetByID(category.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("deleted category error = %v, want record not found", err)
	}
	if err := repos.Category.DeleteAllByUserID(owner.ID); err != nil {
		t.Fatalf("delete owner categories: %v", err)
	}
	remaining, err := repos.Category.GetByUserID(other.ID, "")
	if err != nil || len(remaining) != 1 || repos.Category.DB() == nil {
		t.Fatalf("other categories = %#v, err=%v", remaining, err)
	}
}

func TestAccountRepositoryProtectsBalancesAndUserOwnership(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	active := &model.Account{ID: uuid.NewString(), UserID: owner.ID, Name: "Active", Type: "cash", CurrentBalance: 1250, SortOrder: 2}
	zero := &model.Account{ID: uuid.NewString(), UserID: owner.ID, Name: "Zero", Type: "cash", SortOrder: 1}
	otherAccount := &model.Account{ID: uuid.NewString(), UserID: other.ID, Name: "Other", Type: "cash"}
	if err := repos.Account.CreateBatch([]model.Account{*active, *zero, *otherAccount}); err != nil {
		t.Fatalf("create accounts: %v", err)
	}

	accounts, err := repos.Account.GetByUserID(owner.ID, false)
	if err != nil || len(accounts) != 2 || accounts[0].ID != zero.ID {
		t.Fatalf("owner accounts = %#v, err=%v", accounts, err)
	}
	if err := repos.Account.UpdateMetadataForUser(active.ID, owner.ID, map[string]any{"name": "Renamed"}); err != nil {
		t.Fatalf("update safe account metadata: %v", err)
	}
	if err := repos.Account.UpdateMetadataForUser(active.ID, owner.ID, map[string]any{"current_balance_cents": 0}); !errors.Is(err, ErrUnsafeAccountFieldUpdate) {
		t.Fatalf("unsafe balance update error = %v", err)
	}
	if err := repos.Account.UpdateMetadataForUser(active.ID, other.ID, map[string]any{"name": "Stolen"}); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user update error = %v", err)
	}
	if err := repos.Account.DeleteForUserIfBalanceAllows(active.ID, owner.ID); !errors.Is(err, ErrAccountBalancePreventsDeletion) {
		t.Fatalf("active balance delete error = %v", err)
	}
	if err := repos.Account.UpdateMetadataForUser(active.ID, owner.ID, map[string]any{"is_archived": true}); err != nil {
		t.Fatalf("archive account: %v", err)
	}
	if err := repos.Account.DeleteForUserIfBalanceAllows(active.ID, owner.ID); err != nil {
		t.Fatalf("delete archived account: %v", err)
	}
	if err := repos.Account.DeleteForUserIfBalanceAllows(zero.ID, owner.ID); err != nil {
		t.Fatalf("delete zero account: %v", err)
	}
	if err := repos.Account.DeleteForUserIfBalanceAllows(otherAccount.ID, owner.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user delete error = %v", err)
	}

	history, err := repos.Account.GetByUserIDForHistory(owner.ID)
	if err != nil || len(history) != 2 {
		t.Fatalf("owner account history = %#v, err=%v", history, err)
	}
	if err := repos.Account.UpdateSortOrder([]string{otherAccount.ID}); err != nil {
		t.Fatalf("update sort order: %v", err)
	}
	loaded, err := repos.Account.GetByID(otherAccount.ID)
	if err != nil || loaded.SortOrder != 0 || repos.Account.DB() == nil {
		t.Fatalf("sorted account = %#v, err=%v", loaded, err)
	}
	if err := repos.Account.DeleteAllByUserID(other.ID); err != nil {
		t.Fatalf("delete other accounts: %v", err)
	}
}

func TestRefreshTokenRepositoryConsumesExactlyOnceAndExpires(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	now := time.Now().UTC().Truncate(time.Second)
	valid := &model.RefreshToken{ID: uuid.NewString(), UserID: owner.ID, Token: "valid", ExpiresAt: now.Add(time.Hour)}
	expired := &model.RefreshToken{ID: uuid.NewString(), UserID: owner.ID, Token: "expired", ExpiresAt: now.Add(-time.Hour)}
	otherToken := &model.RefreshToken{ID: uuid.NewString(), UserID: other.ID, Token: "other", ExpiresAt: now.Add(time.Hour)}
	for _, token := range []*model.RefreshToken{valid, expired, otherToken} {
		if err := repos.RefreshToken.Create(token); err != nil {
			t.Fatalf("create refresh token %q: %v", token.Token, err)
		}
	}
	loaded, err := repos.RefreshToken.GetByToken("valid")
	if err != nil || loaded.ID != valid.ID {
		t.Fatalf("get valid token = %#v, err=%v", loaded, err)
	}
	if consumed, err := repos.RefreshToken.Consume("valid", other.ID, now); err != nil || consumed {
		t.Fatalf("cross-user consume = %v, err=%v", consumed, err)
	}
	if consumed, err := repos.RefreshToken.Consume("expired", owner.ID, now); err != nil || consumed {
		t.Fatalf("expired consume = %v, err=%v", consumed, err)
	}
	if consumed, err := repos.RefreshToken.Consume("valid", owner.ID, now); err != nil || !consumed {
		t.Fatalf("valid consume = %v, err=%v", consumed, err)
	}
	if consumed, err := repos.RefreshToken.Consume("valid", owner.ID, now); err != nil || consumed {
		t.Fatalf("second consume = %v, err=%v", consumed, err)
	}
	if err := repos.RefreshToken.UpdateToken(otherToken.ID, "rotated"); err != nil {
		t.Fatalf("rotate token: %v", err)
	}
	if _, err := repos.RefreshToken.GetByToken("rotated"); err != nil {
		t.Fatalf("get rotated token: %v", err)
	}
	if err := repos.RefreshToken.DeleteExpired(); err != nil {
		t.Fatalf("delete expired tokens: %v", err)
	}
	if _, err := repos.RefreshToken.GetByToken("expired"); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("expired token error = %v", err)
	}
	if err := repos.RefreshToken.DeleteByUserID(other.ID); err != nil {
		t.Fatalf("delete user's tokens: %v", err)
	}
	if err := repos.RefreshToken.Delete(otherToken.ID); err != nil {
		t.Fatalf("idempotent token delete: %v", err)
	}
}

func TestAPITokenRepositoryRevokesAndThrottlesMetadataWrites(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	ownerToken := &model.APIToken{UserID: owner.ID, Name: "owner", Token: "owner-hash", TokenPrefix: "owner", Scopes: "ledger:read"}
	otherToken := &model.APIToken{UserID: other.ID, Name: "other", Token: "other-hash", TokenPrefix: "other", Scopes: "ledger:read"}
	for _, token := range []*model.APIToken{ownerToken, otherToken} {
		if err := repos.APIToken.Create(token); err != nil {
			t.Fatalf("create api token: %v", err)
		}
	}
	if err := repos.APIToken.UpdateToken(ownerToken.ID, "owner-hash-rotated"); err != nil {
		t.Fatalf("rotate api token: %v", err)
	}
	loaded, err := repos.APIToken.FindByToken("owner-hash-rotated")
	if err != nil || loaded.ID != ownerToken.ID {
		t.Fatalf("find api token = %#v, err=%v", loaded, err)
	}
	if err := repos.APIToken.UpdateLastUsed(ownerToken.ID); err != nil {
		t.Fatalf("update last used: %v", err)
	}
	first, err := repos.APIToken.FindByToken("owner-hash-rotated")
	if err != nil || first.LastUsedAt == nil {
		t.Fatalf("first last-used = %#v, err=%v", first, err)
	}
	if err := repos.APIToken.UpdateLastUsed(ownerToken.ID); err != nil {
		t.Fatalf("throttled last used: %v", err)
	}
	second, err := repos.APIToken.FindByToken("owner-hash-rotated")
	if err != nil || second.LastUsedAt == nil || !second.LastUsedAt.Equal(*first.LastUsedAt) {
		t.Fatalf("throttled last-used changed: first=%v second=%v err=%v", first.LastUsedAt, second.LastUsedAt, err)
	}
	if err := repos.APIToken.Delete(ownerToken.ID, other.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user revoke error = %v", err)
	}
	if err := repos.APIToken.Delete(ownerToken.ID, owner.ID); err != nil {
		t.Fatalf("revoke owner token: %v", err)
	}
	if _, err := repos.APIToken.FindByToken("owner-hash-rotated"); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("revoked token lookup error = %v", err)
	}
	tokens, err := repos.APIToken.FindByUserID(other.ID)
	if err != nil || len(tokens) != 1 || repos.APIToken.DB() == nil {
		t.Fatalf("other api tokens = %#v, err=%v", tokens, err)
	}
}

func TestSystemNotificationAndDedupeRepositories(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)

	value, err := repos.System.Get("entry_path")
	if err != nil || value != "" {
		t.Fatalf("missing system setting = %q, err=%v", value, err)
	}
	if err := repos.System.Set("entry_path", "first"); err != nil {
		t.Fatalf("create system setting: %v", err)
	}
	if err := repos.System.Set("entry_path", "updated"); err != nil {
		t.Fatalf("update system setting: %v", err)
	}
	value, err = repos.System.Get("entry_path")
	if err != nil || value != "updated" {
		t.Fatalf("updated system setting = %q, err=%v", value, err)
	}
	if err := repos.System.Delete("entry_path"); err != nil {
		t.Fatalf("delete system setting: %v", err)
	}

	ownerSetting := &model.NotificationSetting{UserID: owner.ID, Enabled: true, SmtpHost: "mail.example", SmtpPassword: "old"}
	if err := repos.Notification.Upsert(ownerSetting); err != nil {
		t.Fatalf("create notification setting: %v", err)
	}
	ownerSetting.Enabled = false
	ownerSetting.SmtpHost = "new.example"
	if err := repos.Notification.Upsert(ownerSetting); err != nil {
		t.Fatalf("update notification setting: %v", err)
	}
	loadedSetting, err := repos.Notification.GetByUserID(owner.ID)
	if err != nil || loadedSetting.Enabled || loadedSetting.SmtpHost != "new.example" {
		t.Fatalf("notification setting = %#v, err=%v", loadedSetting, err)
	}
	loadedSetting.SmtpPassword = "rotated"
	loadedSetting.DingtalkSecret = "ding"
	loadedSetting.WebhookSecret = "hook"
	loadedSetting.SmtpHost = "must-not-change"
	if err := repos.Notification.UpdateSecrets(loadedSetting); err != nil {
		t.Fatalf("update notification secrets: %v", err)
	}
	loadedSetting, err = repos.Notification.GetByUserID(owner.ID)
	if err != nil || loadedSetting.SmtpPassword != "rotated" || loadedSetting.SmtpHost != "new.example" {
		t.Fatalf("narrow secret update = %#v, err=%v", loadedSetting, err)
	}
	otherSetting := model.NotificationSetting{UserID: other.ID, SmtpPassword: "other-old"}
	if err := repos.Notification.Create(&otherSetting); err != nil {
		t.Fatalf("create other notification setting: %v", err)
	}
	otherSetting.SmtpPassword = "other-new"
	if err := repos.Notification.UpdateSecretsBatch([]model.NotificationSetting{*loadedSetting, otherSetting}); err != nil {
		t.Fatalf("batch update secrets: %v", err)
	}
	if err := repos.Notification.UpdateSecretsBatch(nil); err != nil {
		t.Fatalf("empty secret batch: %v", err)
	}
	settings, err := repos.Notification.GetAll()
	if err != nil || len(settings) != 2 {
		t.Fatalf("notification settings = %#v, err=%v", settings, err)
	}
	loadedSetting.Enabled = true
	if err := repos.Notification.Update(loadedSetting); err != nil {
		t.Fatalf("direct notification update: %v", err)
	}

	sent, err := repos.NotificationLog.HasSent(owner.ID, "budget", "email", "2026-08")
	if err != nil || sent {
		t.Fatalf("initial dedupe result = %v, err=%v", sent, err)
	}
	if err := repos.NotificationLog.Record(owner.ID, "budget", "email", "2026-08", "Budget", "Body", "failed", "offline"); err != nil {
		t.Fatalf("record failed notification: %v", err)
	}
	if sent, err = repos.NotificationLog.HasSent(owner.ID, "budget", "email", "2026-08"); err != nil || sent {
		t.Fatalf("failed notification dedupe = %v, err=%v", sent, err)
	}
	if err := repos.NotificationLog.Record(owner.ID, "budget", "email", "2026-08", "Budget", "Body", "sent", ""); err != nil {
		t.Fatalf("record sent notification: %v", err)
	}
	if sent, err = repos.NotificationLog.HasSent(owner.ID, "budget", "email", "2026-08"); err != nil || !sent {
		t.Fatalf("sent notification dedupe = %v, err=%v", sent, err)
	}
	if sent, err = repos.NotificationLog.HasSent(owner.ID, "budget", "email", "2026-09"); err != nil || sent {
		t.Fatalf("different dedupe key = %v, err=%v", sent, err)
	}
}

func TestFamilyAndTemplateRepositoriesEnforceOwnership(t *testing.T) {
	repos, owner, other := newRepositoryTestFixture(t)
	first := &model.FamilyMember{UserID: owner.ID, Name: "First", IsDefault: true, SortOrder: 2}
	second := &model.FamilyMember{UserID: owner.ID, Name: "Second", IsDefault: true, SortOrder: 1}
	otherMember := &model.FamilyMember{UserID: other.ID, Name: "Other", IsDefault: true}
	for _, member := range []*model.FamilyMember{first, second, otherMember} {
		if err := repos.FamilyMember.Create(member); err != nil {
			t.Fatalf("create family member: %v", err)
		}
	}
	if err := repos.FamilyMember.ClearDefault(owner.ID, second.ID); err != nil {
		t.Fatalf("clear family defaults: %v", err)
	}
	members, err := repos.FamilyMember.GetByUserID(owner.ID)
	if err != nil || len(members) != 2 || !members[0].IsDefault || members[0].ID != second.ID {
		t.Fatalf("owner family members = %#v, err=%v", members, err)
	}
	count, err := repos.FamilyMember.CountByUserID(owner.ID)
	if err != nil || count != 2 {
		t.Fatalf("family count = %d, err=%v", count, err)
	}
	loadedMember, err := repos.FamilyMember.GetByID(first.ID)
	if err != nil {
		t.Fatalf("get family member: %v", err)
	}
	loadedMember.Name = "Renamed"
	if err := repos.FamilyMember.Update(loadedMember); err != nil {
		t.Fatalf("update family member: %v", err)
	}

	template := &model.QuickTemplate{ID: uuid.NewString(), UserID: owner.ID, Name: "Lunch", Type: "expense", Amount: 2500}
	if err := repos.Template.Create(template); err != nil {
		t.Fatalf("create template: %v", err)
	}
	if _, err := repos.Template.GetByIDForUser(template.ID, other.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user template read error = %v", err)
	}
	usedAt := time.Now().UTC().Truncate(time.Second)
	if err := repos.Template.IncrementUsageWithDB(repos.Account.DB(), template.ID, owner.ID, usedAt); err != nil {
		t.Fatalf("increment template usage: %v", err)
	}
	if err := repos.Template.IncrementUsageWithDB(repos.Account.DB(), template.ID, other.ID, usedAt); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user template increment error = %v", err)
	}
	loadedTemplate, err := repos.Template.GetByID(template.ID)
	if err != nil || loadedTemplate.UsedCount != 1 {
		t.Fatalf("loaded template = %#v, err=%v", loadedTemplate, err)
	}
	loadedTemplate.Name = "Dinner"
	if err := repos.Template.Update(loadedTemplate); err != nil {
		t.Fatalf("update template: %v", err)
	}
	ownerTemplates, err := repos.Template.GetByUserID(owner.ID)
	if err != nil || len(ownerTemplates) != 1 || ownerTemplates[0].Name != "Dinner" {
		t.Fatalf("owner templates = %#v, err=%v", ownerTemplates, err)
	}
	if err := repos.Template.DeleteForUser(template.ID, other.ID); !errors.Is(err, gorm.ErrRecordNotFound) {
		t.Fatalf("cross-user template delete error = %v", err)
	}
	if err := repos.Template.DeleteForUser(template.ID, owner.ID); err != nil {
		t.Fatalf("delete owner template: %v", err)
	}
	if err := repos.Template.DeleteAllByUserID(owner.ID); err != nil {
		t.Fatalf("delete all templates: %v", err)
	}
}

func newRepositoryTestFixture(t *testing.T) (*Repositories, *model.User, *model.User) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init repository test database: %v", err)
	}
	repos := NewRepositories(db)
	owner := &model.User{Username: "repository-owner-" + uuid.NewString(), PasswordHash: "hash"}
	other := &model.User{Username: "repository-other-" + uuid.NewString(), PasswordHash: "hash"}
	if err := repos.User.Create(owner); err != nil {
		t.Fatalf("create owner: %v", err)
	}
	if err := repos.User.Create(other); err != nil {
		t.Fatalf("create other user: %v", err)
	}
	return repos, owner, other
}
