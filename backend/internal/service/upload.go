package service

import (
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"gorm.io/gorm"
)

var ErrUploadPathForbidden = errors.New("file path does not belong to current user")
var ErrUploadPathInvalid = errors.New("invalid file path")
var ErrUploadScopeInvalid = errors.New("invalid upload scope")
var ErrUploadFileTooLarge = errors.New("file size exceeds configured limit")
var ErrUploadTypeNotAllowed = errors.New("file type is not allowed")
var ErrUploadContentMismatch = errors.New("file content does not match its extension or declared type")
var ErrUploadReferenced = errors.New("file is still referenced")

const defaultMaxUploadBytes int64 = 10 << 20

type UploadService struct {
	cfg *config.StorageConfig
	db  *gorm.DB
}

func NewUploadService(cfg *config.StorageConfig, databases ...*gorm.DB) *UploadService {
	service := &UploadService{cfg: cfg}
	if len(databases) > 0 {
		service.db = databases[0]
	}
	return service
}

func (s *UploadService) MaxFileSizeBytes() int64 {
	if s == nil || s.cfg == nil || s.cfg.MaxFileSize <= 0 {
		return defaultMaxUploadBytes
	}
	return s.cfg.MaxFileSize << 20
}

type UploadResult struct {
	ID       string `json:"id"`
	Filename string `json:"filename"`
	Path     string `json:"path"`
	URL      string `json:"url"`
	Size     int64  `json:"size"`
	MimeType string `json:"mime_type"`
}

// Upload saves a file and returns the result
// category: transactions, lendings, reminders
// refID: the ID of the related entity
func (s *UploadService) Upload(userID uint, category string, refID string, file *multipart.FileHeader) (*UploadResult, error) {
	if file == nil || s == nil || s.cfg == nil {
		return nil, errors.New("file is required")
	}
	category, refID, err := normalizeUploadScope(category, refID)
	if err != nil {
		return nil, err
	}

	originalName := sanitizeUploadFilename(file.Filename)
	ext := strings.ToLower(filepath.Ext(originalName))
	if ext == "" {
		return nil, ErrUploadTypeNotAllowed
	}
	ext = ext[1:] // remove the dot

	if !isConfiguredUploadExtensionAllowed(s.cfg.AllowedTypes, ext) || !isKnownUploadExtension(ext) {
		return nil, ErrUploadTypeNotAllowed
	}
	if category == "avatars" && !isAllowedAvatarExtension(ext) {
		return nil, ErrUploadTypeNotAllowed
	}

	// Validate file size
	maxSize := s.MaxFileSizeBytes()
	if file.Size > maxSize {
		return nil, ErrUploadFileTooLarge
	}

	// Create directory structure: uploads/{user_id}/{category}/{ref_id}/
	dirPath := filepath.Join(s.cfg.UploadPath, fmt.Sprintf("%d", userID), category, refID)
	if err := os.MkdirAll(dirPath, 0700); err != nil {
		return nil, fmt.Errorf("failed to create directory: %w", err)
	}

	// Keep the original filename when it can be claimed atomically. Concurrent
	// uploads fall back to a server-generated suffix; never use a Stat-then-open
	// sequence because another request can claim the path between those calls.
	src, err := file.Open()
	if err != nil {
		return nil, fmt.Errorf("failed to open uploaded file: %w", err)
	}
	defer src.Close()

	tempFile, err := os.CreateTemp(dirPath, ".upload-*.tmp")
	if err != nil {
		return nil, fmt.Errorf("failed to create upload staging file: %w", err)
	}
	tempPath := tempFile.Name()
	defer os.Remove(tempPath)
	written, copyErr := io.Copy(tempFile, io.LimitReader(src, maxSize+1))
	closeErr := tempFile.Close()
	if copyErr != nil {
		return nil, fmt.Errorf("failed to save file: %w", copyErr)
	}
	if closeErr != nil {
		return nil, fmt.Errorf("failed to close uploaded file: %w", closeErr)
	}
	if written > maxSize {
		return nil, ErrUploadFileTooLarge
	}

	canonicalMIME, err := validateUploadContent(tempPath, ext, file.Header.Get("Content-Type"))
	if err != nil {
		return nil, err
	}

	fileID := uuid.New().String()
	newFilename := originalName
	fullPath := filepath.Join(dirPath, newFilename)
	err = publishStagedUpload(tempPath, fullPath)
	if errors.Is(err, os.ErrExist) {
		nameWithoutExt := strings.TrimSuffix(originalName, filepath.Ext(originalName))
		newFilename = fmt.Sprintf("%s_%s.%s", nameWithoutExt, fileID, ext)
		fullPath = filepath.Join(dirPath, newFilename)
		err = publishStagedUpload(tempPath, fullPath)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to create unique destination file: %w", err)
	}

	// Build relative path for storage (relative to upload root)
	relativePath := filepath.ToSlash(filepath.Join(fmt.Sprintf("%d", userID), category, refID, newFilename))

	return &UploadResult{
		ID:       fileID,
		Filename: originalName,
		Path:     relativePath,
		URL:      "/uploads/" + relativePath,
		Size:     written,
		MimeType: canonicalMIME,
	}, nil
}

// Delete removes a file owned by the current user.
func (s *UploadService) Delete(userID uint, relativePath string) error {
	fullPath, err := s.GetUserFilePath(userID, relativePath)
	if err != nil {
		return err
	}

	referenced, err := s.IsReferenced(userID, relativePath)
	if err != nil {
		return err
	}
	if referenced {
		return ErrUploadReferenced
	}

	return os.Remove(fullPath)
}

// GetUserFilePath returns a full path only when the relative path belongs to the user.
func (s *UploadService) GetUserFilePath(userID uint, relativePath string) (string, error) {
	cleanPath := filepath.Clean(relativePath)
	if cleanPath == "." ||
		filepath.IsAbs(cleanPath) ||
		strings.HasPrefix(cleanPath, ".."+string(os.PathSeparator)) ||
		cleanPath == ".." {
		return "", ErrUploadPathInvalid
	}

	userPrefix := filepath.Join(fmt.Sprintf("%d", userID))
	if cleanPath == userPrefix {
		return "", ErrUploadPathInvalid
	}
	if !strings.HasPrefix(cleanPath, userPrefix+string(os.PathSeparator)) {
		return "", ErrUploadPathForbidden
	}

	fullPath := filepath.Join(s.cfg.UploadPath, cleanPath)

	// Security check: ensure path is within upload directory
	absUploadPath, err := filepath.Abs(s.cfg.UploadPath)
	if err != nil {
		return "", ErrUploadPathInvalid
	}
	absFullPath, err := filepath.Abs(fullPath)
	if err != nil {
		return "", ErrUploadPathInvalid
	}
	if absFullPath != absUploadPath && !strings.HasPrefix(absFullPath, absUploadPath+string(os.PathSeparator)) {
		return "", ErrUploadPathInvalid
	}
	resolvedUploadPath, err := filepath.EvalSymlinks(absUploadPath)
	if err != nil {
		return "", err
	}
	resolvedAncestor, err := closestResolvedUploadAncestor(absFullPath)
	if err != nil {
		return "", err
	}
	if resolvedAncestor != resolvedUploadPath && !strings.HasPrefix(resolvedAncestor, resolvedUploadPath+string(os.PathSeparator)) {
		return "", ErrUploadPathInvalid
	}

	if resolvedFullPath, err := filepath.EvalSymlinks(absFullPath); err == nil {
		return resolvedFullPath, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	return absFullPath, nil
}

func closestResolvedUploadAncestor(path string) (string, error) {
	candidate := path
	for {
		resolved, err := filepath.EvalSymlinks(candidate)
		if err == nil {
			return resolved, nil
		}
		if !errors.Is(err, os.ErrNotExist) {
			return "", err
		}
		parent := filepath.Dir(candidate)
		if parent == candidate {
			return "", ErrUploadPathInvalid
		}
		candidate = parent
	}
}

// GetFilePath returns the full path to a file
func (s *UploadService) GetFilePath(relativePath string) string {
	return filepath.Join(s.cfg.UploadPath, relativePath)
}

// ListFiles returns all files for a specific entity
func (s *UploadService) ListFiles(userID uint, category string, refID string) ([]string, error) {
	category, refID, err := normalizeUploadScope(category, refID)
	if err != nil {
		return nil, err
	}

	dirPath := filepath.Join(s.cfg.UploadPath, fmt.Sprintf("%d", userID), category, refID)

	entries, err := os.ReadDir(dirPath)
	if err != nil {
		if os.IsNotExist(err) {
			return []string{}, nil
		}
		return nil, err
	}

	var files []string
	for _, entry := range entries {
		if !entry.IsDir() && !strings.HasPrefix(entry.Name(), ".upload-") {
			relativePath := filepath.Join(fmt.Sprintf("%d", userID), category, refID, entry.Name())
			files = append(files, filepath.ToSlash(relativePath))
		}
	}

	return files, nil
}

func normalizeUploadScope(category string, refID string) (string, string, error) {
	category = strings.TrimSpace(category)
	refID = strings.TrimSpace(refID)
	if !isSafeUploadPathSegment(category) || !isSafeUploadPathSegment(refID) {
		return "", "", ErrUploadScopeInvalid
	}
	return category, refID, nil
}

func isSafeUploadPathSegment(value string) bool {
	if value == "" ||
		value == "." ||
		value == ".." ||
		filepath.IsAbs(value) ||
		strings.ContainsAny(value, `/\`) {
		return false
	}
	return filepath.Clean(value) == value
}
