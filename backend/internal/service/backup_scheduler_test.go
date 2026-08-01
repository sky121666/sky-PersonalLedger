package service

import (
	"errors"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
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

func TestAutoBackupSaveSettingsPreservesLastBackupWhenOmitted(t *testing.T) {
	scheduler, _ := newBackupSchedulerTestSubject(t)
	if err := scheduler.SaveSettings(validAutoBackupSettings("2026-07-12 03:00:00")); err != nil {
		t.Fatalf("seed settings: %v", err)
	}

	if err := scheduler.SaveSettings(&AutoBackupSettings{
		Enabled:    false,
		Frequency:  "weekly",
		Hour:       8,
		MaxBackups: 30,
	}); err != nil {
		t.Fatalf("update settings: %v", err)
	}

	settings, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("GetSettings: %v", err)
	}
	if settings.LastBackup != "2026-07-12 03:00:00" {
		t.Fatalf("LastBackup = %q, want preserved value", settings.LastBackup)
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

func TestAutoBackupCadenceUsesLocalCalendarDates(t *testing.T) {
	location, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatalf("load timezone: %v", err)
	}

	if !autoBackupDue(
		time.Date(2026, time.March, 9, 3, 0, 0, 0, location),
		time.Date(2026, time.March, 8, 3, 0, 0, 0, location),
		"daily",
	) {
		t.Fatal("daily backup was not due on the next local date across DST")
	}
	if autoBackupDue(
		time.Date(2026, time.March, 14, 3, 0, 0, 0, location),
		time.Date(2026, time.March, 8, 3, 0, 0, 0, location),
		"weekly",
	) {
		t.Fatal("weekly backup became due after only six calendar days")
	}
	if !autoBackupDue(
		time.Date(2026, time.March, 15, 3, 0, 0, 0, location),
		time.Date(2026, time.March, 8, 3, 0, 0, 0, location),
		"weekly",
	) {
		t.Fatal("weekly backup was not due after seven calendar days")
	}
	if !autoBackupDue(
		time.Date(2026, time.February, 1, 3, 0, 0, 0, location),
		time.Date(2026, time.January, 31, 3, 0, 0, 0, location),
		"monthly",
	) {
		t.Fatal("monthly backup was not due in the next calendar month")
	}
}

func TestAutoBackupCheckParsesLegacyTimestampInRuntimeTimezone(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "local-time-user")
	location := time.FixedZone("UTC+08", 8*60*60)
	scheduler.now = func() time.Time {
		return time.Date(2026, time.July, 31, 3, 0, 0, 0, location)
	}
	if err := scheduler.SaveSettings(&AutoBackupSettings{
		Enabled:    true,
		Frequency:  "daily",
		Hour:       3,
		MaxBackups: 10,
		LastBackup: "2026-07-30 03:00:00",
	}); err != nil {
		t.Fatalf("save settings: %v", err)
	}

	scheduler.checkAndBackup()

	if files := automaticBackupFiles(t, scheduler.backupPath); len(files) != 1 {
		t.Fatalf("backup files = %v, want one next-day backup", files)
	}
	settings, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("get settings: %v", err)
	}
	if settings.LastBackup != "2026-07-31 03:00:00" {
		t.Fatalf("last backup = %q, want runtime-local timestamp", settings.LastBackup)
	}
}

func TestAutoBackupWritesPrivateBackupFiles(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")

	settings := &AutoBackupSettings{
		Enabled:    true,
		Frequency:  "daily",
		Hour:       3,
		MaxBackups: 10,
	}
	if err := scheduler.performBackup(settings); err != nil {
		t.Fatalf("performBackup: %v", err)
	}
	if settings.LastBackup == "" {
		t.Fatal("LastBackup is empty after successful backup")
	}

	files := automaticBackupFiles(t, scheduler.backupPath)
	if len(files) != 1 {
		t.Fatalf("backup files = %d, want 1", len(files))
	}
	info, err := os.Stat(files[0])
	if err != nil {
		t.Fatalf("stat backup: %v", err)
	}
	if mode := info.Mode().Perm(); mode != 0600 {
		t.Fatalf("backup file mode = %o, want 0600", mode)
	}
	if tempFiles, err := filepath.Glob(filepath.Join(scheduler.backupPath, ".auto_backup_*.tmp-*")); err != nil {
		t.Fatalf("glob temporary backups: %v", err)
	} else if len(tempFiles) != 0 {
		t.Fatalf("temporary backup files = %v, want none", tempFiles)
	}

	persisted, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("GetSettings: %v", err)
	}
	if persisted.LastBackup != settings.LastBackup {
		t.Fatalf("persisted LastBackup = %q, want %q", persisted.LastBackup, settings.LastBackup)
	}
}

func TestAutoBackupWithNoUsersFailsWithoutAdvancingLastBackup(t *testing.T) {
	scheduler, _ := newBackupSchedulerTestSubject(t)
	if err := scheduler.TriggerBackup(); err == nil {
		t.Fatal("TriggerBackup succeeded with no users")
	}

	settings, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("GetSettings: %v", err)
	}
	if settings.LastBackup != "" {
		t.Fatalf("LastBackup = %q, want empty", settings.LastBackup)
	}
	if files := automaticBackupFiles(t, scheduler.backupPath); len(files) != 0 {
		t.Fatalf("backup files = %v, want none", files)
	}
}

func TestAutoBackupUserListFailureDoesNotAdvanceLastBackup(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	sqlDB, err := repos.User.DB().DB()
	if err != nil {
		t.Fatalf("get sql DB: %v", err)
	}
	if err := sqlDB.Close(); err != nil {
		t.Fatalf("close sql DB: %v", err)
	}
	settings := validAutoBackupSettings("2026-07-12 03:00:00")

	if err := scheduler.performBackup(settings); err == nil {
		t.Fatal("performBackup succeeded when users could not be listed")
	}
	assertLastBackupUnchanged(t, settings, "2026-07-12 03:00:00")
}

func TestAutoBackupRollsBackCurrentRunWhenLaterUserFails(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "first")
	createBackupSchedulerTestUser(t, repos, "second")

	wantErr := errors.New("second user backup failed")
	callCount := 0
	scheduler.createBackup = func(uint) (*FullBackupData, error) {
		callCount++
		if callCount == 2 {
			return nil, wantErr
		}
		return &FullBackupData{Version: "test"}, nil
	}
	settings := validAutoBackupSettings("2026-07-12 03:00:00")

	err := scheduler.performBackup(settings)
	if !errors.Is(err, wantErr) {
		t.Fatalf("performBackup error = %v, want %v", err, wantErr)
	}
	assertLastBackupUnchanged(t, settings, "2026-07-12 03:00:00")
	if files := automaticBackupFiles(t, scheduler.backupPath); len(files) != 0 {
		t.Fatalf("partial backup files = %v, want none", files)
	}
}

func TestAutoBackupSerializationFailureDoesNotAdvanceLastBackup(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	wantErr := errors.New("marshal failed")
	scheduler.marshalBackup = func(any, string, string) ([]byte, error) {
		return nil, wantErr
	}
	settings := validAutoBackupSettings("2026-07-12 03:00:00")

	err := scheduler.performBackup(settings)
	if !errors.Is(err, wantErr) {
		t.Fatalf("performBackup error = %v, want %v", err, wantErr)
	}
	assertLastBackupUnchanged(t, settings, "2026-07-12 03:00:00")
	if files := automaticBackupFiles(t, scheduler.backupPath); len(files) != 0 {
		t.Fatalf("backup files = %v, want none", files)
	}
}

func TestAutoBackupWriteFailureDoesNotAdvanceLastBackup(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	wantErr := errors.New("write failed")
	scheduler.writeBackup = func(string, []byte) error { return wantErr }
	settings := validAutoBackupSettings("2026-07-12 03:00:00")

	err := scheduler.performBackup(settings)
	if !errors.Is(err, wantErr) {
		t.Fatalf("performBackup error = %v, want %v", err, wantErr)
	}
	assertLastBackupUnchanged(t, settings, "2026-07-12 03:00:00")
}

func TestAutoBackupDirectoryFailureDoesNotAdvanceLastBackup(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	backupPathFile := filepath.Join(t.TempDir(), "backup-path-file")
	if err := os.WriteFile(backupPathFile, []byte("not a directory"), 0600); err != nil {
		t.Fatalf("write backup path file: %v", err)
	}
	scheduler.backupPath = backupPathFile
	settings := validAutoBackupSettings("2026-07-12 03:00:00")

	if err := scheduler.performBackup(settings); err == nil {
		t.Fatal("performBackup succeeded with a file as backup directory")
	}
	assertLastBackupUnchanged(t, settings, "2026-07-12 03:00:00")
}

func TestAutoBackupSettingsSaveFailureRollsBackCurrentRun(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	if err := repos.User.DB().Migrator().DropTable(&model.SystemSetting{}); err != nil {
		t.Fatalf("drop system settings table: %v", err)
	}
	settings := validAutoBackupSettings("2026-07-12 03:00:00")

	if err := scheduler.performBackup(settings); err == nil {
		t.Fatal("performBackup succeeded when settings could not be saved")
	}
	assertLastBackupUnchanged(t, settings, "2026-07-12 03:00:00")
	if files := automaticBackupFiles(t, scheduler.backupPath); len(files) != 0 {
		t.Fatalf("backup files after settings failure = %v, want none", files)
	}
}

func TestAutoBackupCleanupFailureDoesNotReverseCompleteBackup(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	scheduler.backupPath = filepath.Join(t.TempDir(), "[backups")
	settings := validAutoBackupSettings("")

	if err := scheduler.performBackup(settings); err != nil {
		t.Fatalf("performBackup with retention cleanup warning: %v", err)
	}
	if settings.LastBackup == "" {
		t.Fatal("LastBackup is empty after complete backup")
	}
	entries, err := os.ReadDir(scheduler.backupPath)
	if err != nil {
		t.Fatalf("read backup directory: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("backup directory entries = %d, want 1", len(entries))
	}
}

func TestWriteFileAtomicallyCleansTemporaryFileWhenRenameFails(t *testing.T) {
	dir := t.TempDir()
	target := filepath.Join(dir, "backup.json")
	if err := os.Mkdir(target, 0700); err != nil {
		t.Fatalf("create target directory: %v", err)
	}

	if err := writeFileAtomically(target, []byte(`{"ok":true}`)); err == nil {
		t.Fatal("writeFileAtomically succeeded when target was a directory")
	}
	tempFiles, err := filepath.Glob(filepath.Join(dir, ".backup.json.tmp-*"))
	if err != nil {
		t.Fatalf("glob temporary files: %v", err)
	}
	if len(tempFiles) != 0 {
		t.Fatalf("temporary files = %v, want none", tempFiles)
	}
}

func TestAutoBackupManualAndScheduledTriggersAreSerialized(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	scheduler.createBackup = func(uint) (*FullBackupData, error) {
		return &FullBackupData{Version: "test"}, nil
	}

	var active atomic.Int32
	var maximum atomic.Int32
	scheduler.writeBackup = func(string, []byte) error {
		current := active.Add(1)
		for {
			previous := maximum.Load()
			if current <= previous || maximum.CompareAndSwap(previous, current) {
				break
			}
		}
		time.Sleep(30 * time.Millisecond)
		active.Add(-1)
		return nil
	}

	start := make(chan struct{})
	results := make(chan error, 2)
	go func() {
		<-start
		results <- scheduler.TriggerBackup()
	}()
	go func() {
		<-start
		results <- scheduler.performBackup(validAutoBackupSettings(""))
	}()
	close(start)

	for range 2 {
		if err := <-results; err != nil {
			t.Fatalf("concurrent backup: %v", err)
		}
	}
	if got := maximum.Load(); got != 1 {
		t.Fatalf("maximum concurrent backup writes = %d, want 1", got)
	}
}

func TestAutoBackupCompletionMergesLastBackupIntoLatestSettings(t *testing.T) {
	scheduler, repos := newBackupSchedulerTestSubject(t)
	createBackupSchedulerTestUser(t, repos, "admin")
	initial := validAutoBackupSettings("2026-07-12 03:00:00")
	if err := scheduler.SaveSettings(initial); err != nil {
		t.Fatalf("seed settings: %v", err)
	}
	staleSettings, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("load stale settings: %v", err)
	}

	writeStarted := make(chan struct{})
	continueWrite := make(chan struct{})
	var once sync.Once
	scheduler.writeBackup = func(string, []byte) error {
		once.Do(func() { close(writeStarted) })
		<-continueWrite
		return nil
	}

	result := make(chan error, 1)
	go func() {
		result <- scheduler.performBackup(staleSettings)
	}()
	<-writeStarted

	if err := scheduler.SaveSettings(&AutoBackupSettings{
		Enabled:    false,
		Frequency:  "weekly",
		Hour:       8,
		MaxBackups: 30,
	}); err != nil {
		t.Fatalf("save settings during backup: %v", err)
	}
	close(continueWrite)
	if err := <-result; err != nil {
		t.Fatalf("performBackup: %v", err)
	}

	persisted, err := scheduler.GetSettings()
	if err != nil {
		t.Fatalf("GetSettings: %v", err)
	}
	if persisted.Enabled || persisted.Frequency != "weekly" || persisted.Hour != 8 || persisted.MaxBackups != 30 {
		t.Fatalf("persisted settings = %#v, want concurrent configuration preserved", persisted)
	}
	if persisted.LastBackup == "" || persisted.LastBackup == "2026-07-12 03:00:00" {
		t.Fatalf("LastBackup = %q, want successful backup timestamp", persisted.LastBackup)
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

func createBackupSchedulerTestUser(t *testing.T, repos *repository.Repositories, username string) *model.User {
	t.Helper()
	user := &model.User{Username: username, PasswordHash: "hash"}
	if err := repos.User.Create(user); err != nil {
		t.Fatalf("create user %q: %v", username, err)
	}
	return user
}

func validAutoBackupSettings(lastBackup string) *AutoBackupSettings {
	return &AutoBackupSettings{
		Enabled:    true,
		Frequency:  "daily",
		Hour:       3,
		MaxBackups: 10,
		LastBackup: lastBackup,
	}
}

func automaticBackupFiles(t *testing.T, backupPath string) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join(backupPath, "auto_backup_user*.json"))
	if err != nil {
		t.Fatalf("glob backups: %v", err)
	}
	return files
}

func assertLastBackupUnchanged(t *testing.T, settings *AutoBackupSettings, want string) {
	t.Helper()
	if settings.LastBackup != want {
		t.Fatalf("LastBackup = %q, want unchanged %q", settings.LastBackup, want)
	}
}
