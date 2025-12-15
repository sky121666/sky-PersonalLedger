package service

import (
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
)

type UploadService struct {
	cfg *config.StorageConfig
}

func NewUploadService(cfg *config.StorageConfig) *UploadService {
	return &UploadService{cfg: cfg}
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
	// Validate file extension
	ext := strings.ToLower(filepath.Ext(file.Filename))
	if ext == "" {
		return nil, fmt.Errorf("file has no extension")
	}
	ext = ext[1:] // remove the dot

	allowedTypes := strings.Split(s.cfg.AllowedTypes, ",")
	allowed := false
	for _, t := range allowedTypes {
		if strings.TrimSpace(t) == ext {
			allowed = true
			break
		}
	}
	if !allowed {
		return nil, fmt.Errorf("file type '%s' is not allowed", ext)
	}

	// Validate file size
	maxSize := s.cfg.MaxFileSize * 1024 * 1024 // Convert MB to bytes
	if file.Size > maxSize {
		return nil, fmt.Errorf("file size exceeds limit of %dMB", s.cfg.MaxFileSize)
	}

	// Create directory structure: uploads/{user_id}/{category}/{ref_id}/
	dirPath := filepath.Join(s.cfg.UploadPath, fmt.Sprintf("%d", userID), category, refID)
	if err := os.MkdirAll(dirPath, 0755); err != nil {
		return nil, fmt.Errorf("failed to create directory: %w", err)
	}

	// Keep original filename, add unique prefix only if file exists
	fileID := uuid.New().String()
	originalName := filepath.Base(file.Filename)
	// Sanitize filename - remove any path separators
	originalName = strings.ReplaceAll(originalName, "/", "_")
	originalName = strings.ReplaceAll(originalName, "\\", "_")

	newFilename := originalName
	fullPath := filepath.Join(dirPath, newFilename)

	// If file exists, add unique suffix
	if _, err := os.Stat(fullPath); err == nil {
		nameWithoutExt := strings.TrimSuffix(originalName, "."+ext)
		newFilename = fmt.Sprintf("%s_%s.%s", nameWithoutExt, fileID[:8], ext)
		fullPath = filepath.Join(dirPath, newFilename)
	}

	// Save file
	src, err := file.Open()
	if err != nil {
		return nil, fmt.Errorf("failed to open uploaded file: %w", err)
	}
	defer src.Close()

	dst, err := os.Create(fullPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create destination file: %w", err)
	}
	defer dst.Close()

	if _, err := io.Copy(dst, src); err != nil {
		return nil, fmt.Errorf("failed to save file: %w", err)
	}

	// Build relative path for storage (relative to upload root)
	relativePath := filepath.Join(fmt.Sprintf("%d", userID), category, refID, newFilename)

	return &UploadResult{
		ID:       fileID,
		Filename: file.Filename,
		Path:     relativePath,
		URL:      "/uploads/" + relativePath,
		Size:     file.Size,
		MimeType: file.Header.Get("Content-Type"),
	}, nil
}

// Delete removes a file
func (s *UploadService) Delete(relativePath string) error {
	fullPath := filepath.Join(s.cfg.UploadPath, relativePath)

	// Security check: ensure path is within upload directory
	absUploadPath, _ := filepath.Abs(s.cfg.UploadPath)
	absFullPath, _ := filepath.Abs(fullPath)
	if !strings.HasPrefix(absFullPath, absUploadPath) {
		return fmt.Errorf("invalid file path")
	}

	return os.Remove(fullPath)
}

// GetFilePath returns the full path to a file
func (s *UploadService) GetFilePath(relativePath string) string {
	return filepath.Join(s.cfg.UploadPath, relativePath)
}

// ListFiles returns all files for a specific entity
func (s *UploadService) ListFiles(userID uint, category string, refID string) ([]string, error) {
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
		if !entry.IsDir() {
			relativePath := filepath.Join(fmt.Sprintf("%d", userID), category, refID, entry.Name())
			files = append(files, relativePath)
		}
	}

	return files, nil
}
