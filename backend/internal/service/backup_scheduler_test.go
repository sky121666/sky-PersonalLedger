package service

import (
	"errors"
	"path/filepath"
	"testing"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/repository"
)

func TestAutoBackupSaveSettingsRejectsInvalidValues(t *testing.T) {
	scheduler, _ := newBackupSchedulerTestSubject(t)

	cases := []AutoBackupSettings{
		{Enabled: true, Frequency: "hourly", Hour: 3, MaxBackups: 10},
		{Enabled: true, Frequency: "daily", Hour: -1, MaxBackups: 10},
		{Enabled: true, Frequency: "daily", Hour: 24, MaxBackups: 10},
		{Enabled: true, Frequency: "daily", Hour: 3, MaxBackups: 0},
		{Enabled: true, Frequency: "daily", Hour: 3, MaxBackups: 366},
	}

	for _, tc := range cases {
		settings := tc
		if err := scheduler.SaveSettings(&settings); !errors.Is(err, ErrAutoBackupSettingsInvalid) {
			t.Fatalf("SaveSettings(%#v) err = %v, want ErrAutoBackupSettingsInvalid", tc, err)
		}
	}
}

func TestAutoBackupSaveSettingsTrimsAndPersistsValidValues(t *testing.T) {
	scheduler, _ := newBackupSchedulerTestSubject(t)

	if err := scheduler.SaveSettings(&AutoBackupSettings{
		Enabled:    true,
		Frequency:  " weekly ",
		Hour:       8,
		MaxBackups: 30,
		LastBackup: " 2026-05-30 08:00:00 ",
	}); err != nil {
		t.Fatalf("SaveSettings valid settings: %v", err)
	}

	settings, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("GetSettings: %v", err)
	}
	if !settings.Enabled ||
		settings.Frequency != "weekly" ||
		settings.Hour != 8 ||
		settings.MaxBackups != 30 ||
		settings.LastBackup != "2026-05-30 08:00:00" {
		t.Fatalf("settings = %#v, want normalized saved settings", settings)
	}
}

func TestAutoBackupGetSettingsFallsBackForInvalidStoredSettings(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	if err := repos.System.Set("auto_backup", `{"enabled":true,"frequency":"hourly","hour":99,"max_backups":999}`); err != nil {
		t.Fatalf("seed invalid settings: %v", err)
	}

	settings, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("GetSettings: %v", err)
	}
	if settings.Enabled ||
		settings.Frequency != "daily" ||
		settings.Hour != 3 ||
		settings.MaxBackups != 10 {
		t.Fatalf("settings = %#v, want safe defaults", settings)
	}
}

func newBackupSchedulerTestSubject(t *testing.T) (*BackupScheduler, *repository.Repositories) {
	t.Helper()
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	repos := repository.NewRepositories(db)
	backupSvc := NewBackupService(
		db,
		repos.Account,
		repos.Category,
		repos.Transaction,
		repos.Budget,
		repos.Reminder,
		repos.Lending,
		repos.Template,
		repos.Notification,
		repos.Tag,
		repos.User,
		repos.FamilyMember,
		repos.AIReport,
	)
	return NewBackupScheduler(backupSvc, repos.System, repos.User, t.TempDir()), repos
}
