package service

import (
	"crypto/rand"
	"encoding/hex"
	"strings"

	"github.com/sky/personal-ledger/internal/repository"
)

const (
	KeyEntryPath = "security_entry_path"
)

type SystemService struct {
	repo *repository.SystemRepository
}

func NewSystemService(repo *repository.SystemRepository) *SystemService {
	return &SystemService{repo: repo}
}

// GetEntryPath returns the security entry path, empty string means disabled
func (s *SystemService) GetEntryPath() (string, error) {
	return s.repo.Get(KeyEntryPath)
}

// SetEntryPath sets the security entry path
func (s *SystemService) SetEntryPath(path string) error {
	// Normalize path: ensure starts with /, remove trailing /
	path = strings.TrimSpace(path)
	if path != "" {
		if !strings.HasPrefix(path, "/") {
			path = "/" + path
		}
		path = strings.TrimSuffix(path, "/")
	}
	return s.repo.Set(KeyEntryPath, path)
}

// DisableEntryPath disables the security entry path
func (s *SystemService) DisableEntryPath() error {
	return s.repo.Set(KeyEntryPath, "")
}

// GenerateRandomPath generates a random entry path
func (s *SystemService) GenerateRandomPath() (string, error) {
	bytes := make([]byte, 8)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	path := "/" + hex.EncodeToString(bytes)
	return path, s.repo.Set(KeyEntryPath, path)
}

// ValidateEntryPath checks if the given path matches the configured entry path
func (s *SystemService) ValidateEntryPath(requestPath string) (bool, error) {
	entryPath, err := s.repo.Get(KeyEntryPath)
	if err != nil {
		return false, err
	}

	// If no entry path configured, allow all
	if entryPath == "" {
		return true, nil
	}

	return MatchesEntryPath(requestPath, entryPath), nil
}

func MatchesEntryPath(requestPath string, entryPath string) bool {
	requestPath = strings.TrimSpace(requestPath)
	entryPath = strings.TrimSuffix(strings.TrimSpace(entryPath), "/")
	if entryPath == "" {
		return true
	}
	return requestPath == entryPath || strings.HasPrefix(requestPath, entryPath+"/")
}
