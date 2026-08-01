package service

import (
	"errors"
	"sync"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/pkg/logger"
)

const (
	uploadGCInterval = 24 * time.Hour
	uploadGCGrace    = 24 * time.Hour
)

type UploadGarbageCollector struct {
	uploads *UploadService
	users   *repository.UserRepository
	once    sync.Once
}

func NewUploadGarbageCollector(uploads *UploadService, users *repository.UserRepository) *UploadGarbageCollector {
	return &UploadGarbageCollector{uploads: uploads, users: users}
}

func (collector *UploadGarbageCollector) Start() {
	if collector == nil || collector.uploads == nil || collector.users == nil {
		return
	}
	collector.once.Do(func() {
		go func() {
			collector.runAndLog()
			ticker := time.NewTicker(uploadGCInterval)
			defer ticker.Stop()
			for range ticker.C {
				collector.runAndLog()
			}
		}()
	})
}

func (collector *UploadGarbageCollector) RunOnce(now time.Time) (int, error) {
	if collector == nil || collector.uploads == nil || collector.users == nil {
		return 0, nil
	}
	users, err := collector.users.GetAll()
	if err != nil {
		return 0, err
	}
	removedCount := 0
	var runErrors []error
	cutoff := now.Add(-uploadGCGrace)
	for _, user := range users {
		removed, err := collector.uploads.CollectOrphanedFiles(user.ID, cutoff)
		removedCount += len(removed)
		if err != nil {
			runErrors = append(runErrors, err)
		}
	}
	return removedCount, errors.Join(runErrors...)
}

func (collector *UploadGarbageCollector) runAndLog() {
	removed, err := collector.RunOnce(time.Now())
	if err != nil {
		logger.Warnf("upload garbage collection failed: %v", err)
		return
	}
	if removed > 0 {
		logger.Infof("upload garbage collection removed %d orphaned files", removed)
	}
}
