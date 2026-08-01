package service

import (
	"archive/zip"
	"bytes"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"unicode"
)

var canonicalUploadMIME = map[string]string{
	"jpg":  "image/jpeg",
	"jpeg": "image/jpeg",
	"png":  "image/png",
	"gif":  "image/gif",
	"webp": "image/webp",
	"pdf":  "application/pdf",
	"doc":  "application/msword",
	"docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
	"xls":  "application/vnd.ms-excel",
	"xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
	"txt":  "text/plain",
}

var declaredUploadMIMEAliases = map[string][]string{
	"jpg":  {"image/jpeg", "image/pjpeg"},
	"jpeg": {"image/jpeg", "image/pjpeg"},
	"png":  {"image/png"},
	"gif":  {"image/gif"},
	"webp": {"image/webp"},
	"pdf":  {"application/pdf"},
	"doc":  {"application/msword", "application/vnd.ms-office"},
	"docx": {"application/vnd.openxmlformats-officedocument.wordprocessingml.document"},
	"xls":  {"application/vnd.ms-excel", "application/msexcel", "application/x-msexcel"},
	"xlsx": {"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"},
	"txt":  {"text/plain"},
}

func isKnownUploadExtension(extension string) bool {
	_, exists := canonicalUploadMIME[extension]
	return exists
}

func isAllowedAvatarExtension(extension string) bool {
	switch extension {
	case "jpg", "jpeg", "png", "webp":
		return true
	default:
		return false
	}
}

func IsSafeStoredAvatar(path string) bool {
	extension := strings.ToLower(strings.TrimPrefix(filepath.Ext(path), "."))
	if !isAllowedAvatarExtension(extension) {
		return false
	}
	actualType, err := detectUploadContentType(path)
	return err == nil && actualContentMatchesExtension(actualType, extension)
}

func isConfiguredUploadExtensionAllowed(configured string, extension string) bool {
	for _, value := range strings.Split(configured, ",") {
		if strings.EqualFold(strings.TrimSpace(strings.TrimPrefix(value, ".")), extension) {
			return true
		}
	}
	return false
}

func sanitizeUploadFilename(filename string) string {
	normalized := strings.ReplaceAll(strings.TrimSpace(filename), "\\", "/")
	base := filepath.Base(normalized)
	base = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || r == '/' || r == '\\' {
			return '_'
		}
		return r
	}, base)
	base = strings.TrimSpace(base)
	if base == "" || base == "." || base == ".." {
		return "upload"
	}
	if len(base) > 240 {
		extension := filepath.Ext(base)
		stemLimit := 240 - len(extension)
		if stemLimit < 1 {
			return "upload"
		}
		base = base[:stemLimit] + extension
	}
	return base
}

func validateUploadContent(path string, extension string, declaredContentType string) (string, error) {
	declaredType, _, err := mime.ParseMediaType(strings.TrimSpace(declaredContentType))
	if err != nil || declaredType == "" || !matchesAnyMIME(declaredType, declaredUploadMIMEAliases[extension]) {
		return "", ErrUploadContentMismatch
	}

	actualType, err := detectUploadContentType(path)
	if err != nil {
		return "", err
	}
	if !actualContentMatchesExtension(actualType, extension) {
		return "", ErrUploadContentMismatch
	}
	return canonicalUploadMIME[extension], nil
}

func matchesAnyMIME(value string, allowed []string) bool {
	for _, candidate := range allowed {
		if strings.EqualFold(value, candidate) {
			return true
		}
	}
	return false
}

func detectUploadContentType(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	header := make([]byte, 512)
	read, err := file.Read(header)
	if err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	if read == 0 {
		return "", ErrUploadContentMismatch
	}
	header = header[:read]
	if len(header) >= 8 && bytes.Equal(header[:8], []byte{0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1}) {
		return "application/x-ole-storage", nil
	}

	detected, _, err := mime.ParseMediaType(http.DetectContentType(header))
	if err != nil {
		return "", ErrUploadContentMismatch
	}
	if detected == "application/zip" {
		return detectOfficeZIPType(path)
	}
	return detected, nil
}

func detectOfficeZIPType(path string) (string, error) {
	archive, err := zip.OpenReader(path)
	if err != nil {
		return "", ErrUploadContentMismatch
	}
	defer archive.Close()

	hasContentTypes := false
	hasWord := false
	hasWorkbook := false
	if len(archive.File) > 10000 {
		return "", ErrUploadContentMismatch
	}
	for _, entry := range archive.File {
		name := filepath.ToSlash(entry.Name)
		switch {
		case name == "[Content_Types].xml":
			hasContentTypes = true
		case strings.HasPrefix(name, "word/"):
			hasWord = true
		case strings.HasPrefix(name, "xl/"):
			hasWorkbook = true
		}
	}
	if !hasContentTypes || hasWord == hasWorkbook {
		return "", ErrUploadContentMismatch
	}
	if hasWord {
		return canonicalUploadMIME["docx"], nil
	}
	return canonicalUploadMIME["xlsx"], nil
}

func actualContentMatchesExtension(actualType string, extension string) bool {
	switch extension {
	case "doc", "xls":
		return actualType == "application/x-ole-storage"
	default:
		return actualType == canonicalUploadMIME[extension]
	}
}

func publishStagedUpload(stagedPath string, destinationPath string) error {
	source, err := os.Open(stagedPath)
	if err != nil {
		return err
	}
	defer source.Close()

	destination, err := os.OpenFile(destinationPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(destination, source)
	closeErr := destination.Close()
	if copyErr != nil || closeErr != nil {
		_ = os.Remove(destinationPath)
		if copyErr != nil {
			return copyErr
		}
		return closeErr
	}
	return nil
}
