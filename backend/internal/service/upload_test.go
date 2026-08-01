package service

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"mime"
	"mime/multipart"
	"net/http/httptest"
	"net/textproto"
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/model"
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

func TestUploadRejectsFileLargerThanConfiguredLimit(t *testing.T) {
	uploadPath := t.TempDir()
	svc := NewUploadService(&config.StorageConfig{
		UploadPath:   uploadPath,
		MaxFileSize:  1,
		AllowedTypes: "txt",
	})
	file := newUploadFileHeader(t, "oversized.txt", string(bytes.Repeat([]byte("x"), (1<<20)+1)))

	_, err := svc.Upload(7, "transactions", "tx-oversized", file)
	if !errors.Is(err, ErrUploadFileTooLarge) {
		t.Fatalf("upload error = %v, want ErrUploadFileTooLarge", err)
	}
	if _, statErr := os.Stat(filepath.Join(uploadPath, "7", "transactions", "tx-oversized", "oversized.txt")); !os.IsNotExist(statErr) {
		t.Fatalf("oversized upload left a file behind: %v", statErr)
	}
}

func TestUploadRejectsExtensionAndSignatureMismatch(t *testing.T) {
	uploadPath := t.TempDir()
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: uploadPath, MaxFileSize: 1, AllowedTypes: "png",
	})
	file := newUploadFileHeaderWithType(t, "receipt.png", []byte("<html><script>alert(1)</script></html>"), "image/png")

	_, err := svc.Upload(7, "transactions", "tx-mismatch", file)
	if !errors.Is(err, ErrUploadContentMismatch) {
		t.Fatalf("upload error = %v, want ErrUploadContentMismatch", err)
	}
	entries, readErr := os.ReadDir(filepath.Join(uploadPath, "7", "transactions", "tx-mismatch"))
	if readErr != nil {
		t.Fatalf("read upload directory: %v", readErr)
	}
	if len(entries) != 0 {
		t.Fatalf("rejected upload left files behind: %#v", entries)
	}
}

func TestUploadRejectsDeclaredMIMEThatConflictsWithContent(t *testing.T) {
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "png",
	})
	file := newUploadFileHeaderWithType(t, "receipt.png", minimalPNG(), "image/jpeg")

	if _, err := svc.Upload(7, "transactions", "tx-declared-mismatch", file); !errors.Is(err, ErrUploadContentMismatch) {
		t.Fatalf("upload error = %v, want ErrUploadContentMismatch", err)
	}
}

func TestAvatarUploadAllowsOnlyJPEGPNGAndWebP(t *testing.T) {
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "jpg,jpeg,png,gif,webp",
	})
	gif := newUploadFileHeaderWithType(t, "animated.gif", []byte("GIF89a\x01\x00\x01\x00"), "image/gif")

	if _, err := svc.Upload(7, "avatars", "profile", gif); !errors.Is(err, ErrUploadTypeNotAllowed) {
		t.Fatalf("avatar upload error = %v, want ErrUploadTypeNotAllowed", err)
	}
	png := newUploadFileHeaderWithType(t, "avatar.png", minimalPNG(), "image/png")
	result, err := svc.Upload(7, "avatars", "profile", png)
	if err != nil {
		t.Fatalf("upload png avatar: %v", err)
	}
	if result.MimeType != "image/png" {
		t.Fatalf("avatar mime = %q, want image/png", result.MimeType)
	}
}

func TestOfficeUploadValidatesContainerKind(t *testing.T) {
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "docx,xlsx",
	})
	document := officeZIP(t, "word/document.xml")
	docx := newUploadFileHeaderWithType(
		t,
		"report.docx",
		document,
		"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
	)
	if _, err := svc.Upload(7, "transactions", "tx-docx", docx); err != nil {
		t.Fatalf("upload valid docx: %v", err)
	}
	xlsxSpoof := newUploadFileHeaderWithType(
		t,
		"report.xlsx",
		document,
		"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
	)
	if _, err := svc.Upload(7, "transactions", "tx-xlsx", xlsxSpoof); !errors.Is(err, ErrUploadContentMismatch) {
		t.Fatalf("spoofed xlsx error = %v, want ErrUploadContentMismatch", err)
	}
}

func TestUploadDeleteRejectsReferencedFile(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := db.Create(user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "png",
	}, db)
	result, err := svc.Upload(user.ID, "avatars", "profile", newUploadFileHeaderWithType(t, "avatar.png", minimalPNG(), "image/png"))
	if err != nil {
		t.Fatalf("upload avatar: %v", err)
	}
	if err := db.Model(user).Update("avatar", result.URL).Error; err != nil {
		t.Fatalf("reference avatar: %v", err)
	}

	if err := svc.Delete(user.ID, result.Path); !errors.Is(err, ErrUploadReferenced) {
		t.Fatalf("delete referenced file error = %v, want ErrUploadReferenced", err)
	}
	if err := db.Model(user).Update("avatar", "").Error; err != nil {
		t.Fatalf("clear avatar reference: %v", err)
	}
	if err := svc.Delete(user.ID, result.Path); err != nil {
		t.Fatalf("delete unreferenced file: %v", err)
	}
}

func TestUploadGarbageCollectionKeepsReferencesAndRemovesOldOrphans(t *testing.T) {
	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	user := &model.User{Username: "admin", PasswordHash: "hash"}
	if err := db.Create(user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	svc := NewUploadService(&config.StorageConfig{
		UploadPath: t.TempDir(), MaxFileSize: 1, AllowedTypes: "txt",
	}, db)
	referenced, err := svc.Upload(user.ID, "reminders", "reminder-1", newUploadFileHeader(t, "keep.txt", "keep"))
	if err != nil {
		t.Fatalf("upload referenced file: %v", err)
	}
	orphaned, err := svc.Upload(user.ID, "reminders", "reminder-1", newUploadFileHeader(t, "remove.txt", "remove"))
	if err != nil {
		t.Fatalf("upload orphaned file: %v", err)
	}
	evidence, _ := json.Marshal([]string{referenced.Path})
	if err := db.Create(&model.Reminder{
		ID: uuid.NewString(), UserID: user.ID, Name: "Bill", PaymentDay: 1, Evidence: string(evidence),
	}).Error; err != nil {
		t.Fatalf("create reminder reference: %v", err)
	}
	old := time.Now().Add(-48 * time.Hour)
	for _, path := range []string{referenced.Path, orphaned.Path} {
		if err := os.Chtimes(svc.GetFilePath(path), old, old); err != nil {
			t.Fatalf("age upload %q: %v", path, err)
		}
	}

	removed, err := svc.CollectOrphanedFiles(user.ID, time.Now().Add(-24*time.Hour))
	if err != nil {
		t.Fatalf("collect orphaned files: %v", err)
	}
	if len(removed) != 1 || removed[0] != orphaned.Path {
		t.Fatalf("removed files = %#v, want %#v", removed, []string{orphaned.Path})
	}
	if _, err := os.Stat(svc.GetFilePath(referenced.Path)); err != nil {
		t.Fatalf("referenced file was removed: %v", err)
	}
	if _, err := os.Stat(svc.GetFilePath(orphaned.Path)); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("orphaned file still exists: %v", err)
	}
}

func newUploadFileHeader(t *testing.T, filename string, content string) *multipart.FileHeader {
	return newUploadFileHeaderWithType(t, filename, []byte(content), mime.TypeByExtension(filepath.Ext(filename)))
}

func newUploadFileHeaderWithType(t *testing.T, filename string, content []byte, contentType string) *multipart.FileHeader {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	header := make(textproto.MIMEHeader)
	header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="file"; filename="%s"`, filename))
	header.Set("Content-Type", contentType)
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := part.Write(content); err != nil {
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

func minimalPNG() []byte {
	return []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 0, 0, 0, 0, 'I', 'H', 'D', 'R'}
}

func officeZIP(t *testing.T, contentPath string) []byte {
	t.Helper()
	var body bytes.Buffer
	writer := zip.NewWriter(&body)
	for _, name := range []string{"[Content_Types].xml", contentPath} {
		part, err := writer.Create(name)
		if err != nil {
			t.Fatalf("create zip entry: %v", err)
		}
		if _, err := part.Write([]byte("<xml/>")); err != nil {
			t.Fatalf("write zip entry: %v", err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}
	return body.Bytes()
}
