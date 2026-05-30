package service

import (
	"bytes"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"github.com/sky/personal-ledger/internal/config"
)

func TestUploadWritesPrivateFile(t *testing.T) {
	oldUmask := syscall.Umask(0)
	defer syscall.Umask(oldUmask)

	uploadPath := t.TempDir()
	svc := NewUploadService(&config.StorageConfig{
		UploadPath:   uploadPath,
		MaxFileSize:  1,
		AllowedTypes: "txt",
	})

	file := newUploadFileHeader(t, "receipt.txt", "private receipt")
	result, err := svc.Upload(7, "transactions", "tx-1", file)
	if err != nil {
		t.Fatalf("upload: %v", err)
	}

	info, err := os.Stat(filepath.Join(uploadPath, result.Path))
	if err != nil {
		t.Fatalf("stat uploaded file: %v", err)
	}
	if mode := info.Mode().Perm(); mode != 0600 {
		t.Fatalf("uploaded file mode = %o, want 0600", mode)
	}
}

func newUploadFileHeader(t *testing.T, filename string, content string) *multipart.FileHeader {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := part.Write([]byte(content)); err != nil {
		t.Fatalf("write form file: %v", err)
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close multipart writer: %v", err)
	}

	request := httptest.NewRequest("POST", "/upload", &body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	if err := request.ParseMultipartForm(int64(body.Len())); err != nil {
		t.Fatalf("parse multipart form: %v", err)
	}
	return request.MultipartForm.File["file"][0]
}
