package service

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/url"
	pathpkg "path"
	"strings"
	"unicode"

	"github.com/sky/personal-ledger/internal/repository"
)

var ErrEntryPathInvalid = errors.New("入口路径无效：请使用普通路径，且不能使用 API 或静态资源保留路径")

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
		if path == "/" || strings.ContainsAny(path, "?#%\\") || strings.Contains(path, "//") || strings.IndexFunc(path, func(r rune) bool { return unicode.IsSpace(r) || unicode.IsControl(r) }) >= 0 {
			return ErrEntryPathInvalid
		}
		if !strings.HasPrefix(path, "/") {
			path = "/" + path
		}
		path = strings.TrimSuffix(path, "/")
		parsed, err := url.ParseRequestURI(path)
		if err != nil || parsed.Path != path || pathpkg.Clean(path) != path {
			return ErrEntryPathInvalid
		}
		for _, reserved := range []string{"/api", "/assets", "/uploads", "/metrics", "/.well-known", "/favicon.svg", "/favicon.ico", "/manifest.json"} {
			if MatchesEntryPath(path, reserved) {
				return ErrEntryPathInvalid
			}
		}
	}
	return s.repo.Set(KeyEntryPath, path)
}

// DisableEntryPath disables the security entry path
func (s *SystemService) DisableEntryPath() error {
	return s.repo.Set(KeyEntryPath, "")
}

// GenerateRandomPath generates a random entry path
func (s *SystemService) GenerateRandomPath() (string, error) {
	path, err := s.GenerateRandomPathDraft()
	if err != nil {
		return "", err
	}
	return path, s.repo.Set(KeyEntryPath, path)
}

// GenerateRandomPathDraft generates a candidate without changing the saved path.
func (s *SystemService) GenerateRandomPathDraft() (string, error) {
	bytes := make([]byte, 8)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	path := "/" + hex.EncodeToString(bytes)
	return path, nil
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
