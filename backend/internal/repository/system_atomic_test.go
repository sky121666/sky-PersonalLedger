package repository

import (
	"errors"
	"os"
	"strconv"
	"strings"
	"sync"
	"testing"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
)

func TestSystemSettingAtomicUpdatePreservesEveryConcurrentChange(t *testing.T) {
	repos, _, _ := newRepositoryTestFixture(t)
	runSystemAtomicUpdate(t, repos.System)
}

func TestSystemAtomicUpdateDatabaseIntegration(t *testing.T) {
	for _, driver := range []string{"postgres", "mysql"} {
		t.Run(driver, func(t *testing.T) {
			dsn := os.Getenv("LEDGER_TEST_" + strings.ToUpper(driver) + "_DSN")
			if dsn == "" {
				t.Skip("isolated database DSN not supplied")
			}
			db, err := database.InitWithConfig(config.DatabaseConfig{Driver: driver, DSN: dsn, MaxOpenConns: 4, MaxIdleConns: 2})
			if err != nil {
				t.Fatal(err)
			}
			sqlDB, err := db.DB()
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = sqlDB.Close() })
			runSystemAtomicUpdate(t, NewSystemRepository(db))
		})
	}
}

func runSystemAtomicUpdate(t *testing.T, repo *SystemRepository) {
	t.Helper()
	key := "a-" + uuid.NewString()
	missingKey := key + "-missing"
	t.Cleanup(func() { _ = repo.Delete(key); _ = repo.Delete(missingKey) })
	if err := repo.Set(key, "0"); err != nil {
		t.Fatal(err)
	}
	const writers = 20
	errorsCh := make(chan error, writers)
	var group sync.WaitGroup
	for i := 0; i < writers; i++ {
		group.Add(1)
		go func() {
			defer group.Done()
			// Separate repository instances must coordinate the same setting.
			err := NewSystemRepository(repo.db).Update(key, func(current string) (string, error) {
				value, err := strconv.Atoi(current)
				return strconv.Itoa(value + 1), err
			})
			errorsCh <- err
		}()
	}
	group.Wait()
	close(errorsCh)
	for err := range errorsCh {
		if err != nil {
			t.Fatal(err)
		}
	}
	value, err := repo.Get(key)
	if err != nil || value != "20" {
		t.Fatalf("atomic counter=%q err=%v", value, err)
	}
	failure := errors.New("cancel update")
	if err := repo.Update(key, func(string) (string, error) { return "bad", failure }); !errors.Is(err, failure) {
		t.Fatal(err)
	}
	value, err = repo.Get(key)
	if err != nil || value != "20" {
		t.Fatal("cancelled update changed persisted value")
	}
	if err := repo.Update(missingKey, func(string) (string, error) { return "bad", failure }); !errors.Is(err, failure) {
		t.Fatal(err)
	}
	value, err = repo.Get(missingKey)
	if err != nil || value != "" {
		t.Fatal("cancelled creation created a setting")
	}
}
