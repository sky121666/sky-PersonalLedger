package service

import (
	"bytes"
	"encoding/json"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/repository"
	"gorm.io/gorm"
)

func TestAIReportRevisionBindsConfigurationUsedBeforeReportCreation(t *testing.T) {
	oldServer, oldCalls := newCountingAIReportServer(t)
	newServer, newCalls := newCountingAIReportServer(t)
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, oldServer.URL)
	db := providers.repo.DB()
	changed := atomic.Bool{}
	const callback = "test:change_provider_before_report_creation"
	if err := db.Callback().Query().After("gorm:query").Register(callback, func(query *gorm.DB) {
		if query.Statement.Table != "ai_reports" || !changed.CompareAndSwap(false, true) {
			return
		}
		// This runs after the last provider read and the cache SELECT, before
		// report.Create. A CreatedAt >= UpdatedAt test incorrectly accepts the
		// resulting old-provider report on the next Generate call.
		if err := db.Model(&model.AIProvider{}).Where("user_id = ?", userID).
			Updates(map[string]any{"name": "Changed before report creation", "base_url": newServer.URL}).Error; err != nil {
			query.AddError(err)
		}
	}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Callback().Query().Remove(callback) })
	req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
	first, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if !changed.Load() || first.ProviderName != "Fake AI" || oldCalls.Load() != 1 || newCalls.Load() != 0 {
		t.Fatalf("concurrency fixture did not change configuration between read and creation: changed=%v old=%d new=%d name=%q",
			changed.Load(), oldCalls.Load(), newCalls.Load(), first.ProviderName)
	}
	second, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if first.ID == second.ID || second.ProviderName != "Changed before report creation" || oldCalls.Load() != 1 || newCalls.Load() != 1 {
		t.Fatalf("old provider report was reused after configuration change: same=%v old=%d new=%d name=%q",
			first.ID == second.ID, oldCalls.Load(), newCalls.Load(), second.ProviderName)
	}
	var firstStored, secondStored model.AIReport
	if err := db.First(&firstStored, "id = ?", first.ID).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.First(&secondStored, "id = ?", second.ID).Error; err != nil {
		t.Fatal(err)
	}
	if len(firstStored.ProviderRevision) != 64 || len(secondStored.ProviderRevision) != 64 || firstStored.ProviderRevision == secondStored.ProviderRevision {
		t.Fatal("reports did not preserve their distinct configuration revisions")
	}
	third, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if third.ID != second.ID || newCalls.Load() != 1 {
		t.Fatal("unchanged new provider configuration must reuse the new report")
	}
}

func TestAIReportProviderRevisionStaysOutOfBackupAndRestore(t *testing.T) {
	server, calls := newCountingAIReportServer(t)
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, server.URL)
	req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
	first, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	db := providers.repo.DB()
	var persisted model.AIReport
	if err := db.First(&persisted, "id = ?", first.ID).Error; err != nil {
		t.Fatal(err)
	}
	if len(persisted.ProviderRevision) != 64 {
		t.Fatal("fixture report has no stored provider revision")
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(db, repos.Account, repos.Category, repos.Transaction, repos.Budget,
		repos.Reminder, repos.Lending, repos.Template, repos.Notification, repos.Tag, repos.User, repos.FamilyMember, repos.AIReport)
	backup, err := backupSvc.CreateBackup(userID)
	if err != nil {
		t.Fatal(err)
	}
	raw, err := json.Marshal(backup)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte("provider_revision")) || bytes.Contains(raw, []byte(persisted.ProviderRevision)) {
		t.Fatal("backup exported internal provider revision")
	}
	response, err := json.Marshal(first)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(response, []byte("provider_revision")) || bytes.Contains(response, []byte(persisted.ProviderRevision)) {
		t.Fatal("report API exported internal provider revision")
	}
	// Even a supplied internal field cannot bless an imported historical report
	// as reusable against this instance's provider configuration.
	var portable map[string]any
	if err := json.Unmarshal(raw, &portable); err != nil {
		t.Fatal(err)
	}
	portable["ai_reports"].([]any)[0].(map[string]any)["provider_revision"] = persisted.ProviderRevision
	raw, err = json.Marshal(portable)
	if err != nil {
		t.Fatal(err)
	}
	if err := backupSvc.RestoreBackup(userID, writeRawBackupFile(t, raw)); err != nil {
		t.Fatal(err)
	}
	var restored model.AIReport
	if err := db.First(&restored, "id = ?", first.ID).Error; err != nil {
		t.Fatal(err)
	}
	if restored.ProviderRevision != "" || restored.SnapshotJSON != persisted.SnapshotJSON || restored.ContentJSON != persisted.ContentJSON {
		t.Fatal("restore imported internal revision or changed historical report content")
	}
	regenerated, err := svc.Generate(userID, req)
	if err != nil {
		t.Fatal(err)
	}
	if regenerated.ID == first.ID || calls.Load() != 2 {
		t.Fatal("a restored report without a provider revision must regenerate instead of satisfying the cache")
	}
}

func TestAIProviderRevisionTracksConfigurationNotUpdateClock(t *testing.T) {
	provider := model.AIProvider{Name: "Provider", ProviderType: "openai_compatible", BaseURL: "https://example.com",
		Model: "model", Enabled: true, APIKeyCiphertext: "encrypted-fixture"}
	original := aiProviderRevision(&provider)
	if len(original) != 64 || strings.Contains(original, "encrypted-fixture") {
		t.Fatal("provider revision must be a bounded digest")
	}
	mutations := []func(*model.AIProvider){
		func(p *model.AIProvider) { p.Name = "new name" },
		func(p *model.AIProvider) { p.ProviderType = "other" },
		func(p *model.AIProvider) { p.BaseURL = "https://other.example.com" },
		func(p *model.AIProvider) { p.Model = "new model" },
		func(p *model.AIProvider) { p.Enabled = false },
		func(p *model.AIProvider) { p.APIKeyCiphertext = "other-encrypted-fixture" },
	}
	for index, change := range mutations {
		altered := provider
		change(&altered)
		if aiProviderRevision(&altered) == original {
			t.Fatalf("configuration mutation %d did not invalidate revision", index)
		}
	}
	provider.UpdatedAt = provider.UpdatedAt.AddDate(1, 0, 0)
	if aiProviderRevision(&provider) != original {
		t.Fatal("a clock-only update should not change the configuration revision")
	}
}
