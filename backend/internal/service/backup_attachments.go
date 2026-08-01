package service

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/google/uuid"
	"golang.org/x/text/cases"
	"golang.org/x/text/unicode/norm"
)

const (
	maxBackupAttachmentCount     = 10_000
	maxBackupAttachmentPathBytes = 4 << 10
)

// BackupAttachment contains one regular file below a user's upload directory.
// RelativePath never includes the source user ID, so a restore always maps the
// file into the authenticated target user's directory.
type BackupAttachment struct {
	RelativePath  string `json:"relative_path"`
	Size          int64  `json:"size"`
	SHA256        string `json:"sha256"`
	ContentBase64 string `json:"content_base64"`
}

func (s *BackupService) createBackupAttachments(userID uint) ([]BackupAttachment, error) {
	if !s.hasUploadStorage() {
		return nil, nil
	}

	uploadRoot, err := os.OpenRoot(s.uploadService.cfg.UploadPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return []BackupAttachment{}, nil
		}
		return nil, err
	}
	defer uploadRoot.Close()

	userDirectory := strconv.FormatUint(uint64(userID), 10)
	info, err := uploadRoot.Lstat(userDirectory)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return []BackupAttachment{}, nil
		}
		return nil, err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return nil, fmt.Errorf("user upload directory is not a regular directory")
	}

	userRoot, err := uploadRoot.OpenRoot(userDirectory)
	if err != nil {
		return nil, err
	}
	defer userRoot.Close()

	attachments := make([]BackupAttachment, 0)
	pathSet := newPortableAttachmentPathSet()
	var totalSize int64
	err = fs.WalkDir(userRoot.FS(), ".", func(relativePath string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if relativePath == "." {
			return nil
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("attachment path contains a symbolic link")
		}
		if entry.IsDir() {
			return nil
		}
		if len(attachments) >= maxBackupAttachmentCount {
			return ErrBackupFileTooLarge
		}

		normalizedPath, err := validateBackupAttachmentPath(relativePath)
		if err != nil {
			return err
		}
		if err := pathSet.add(normalizedPath); err != nil {
			return err
		}
		attachment, err := readBackupAttachment(userRoot, normalizedPath, s.uploadService.MaxFileSizeBytes())
		if err != nil {
			return err
		}
		if attachment.Size > s.MaxRestoreBytes()-totalSize {
			return ErrBackupFileTooLarge
		}
		totalSize += attachment.Size
		attachments = append(attachments, attachment)
		return nil
	})
	if err != nil {
		return nil, err
	}

	sort.Slice(attachments, func(i, j int) bool {
		return attachments[i].RelativePath < attachments[j].RelativePath
	})
	return attachments, nil
}

func readBackupAttachment(root *os.Root, relativePath string, maxFileSize int64) (BackupAttachment, error) {
	file, err := root.Open(relativePath)
	if err != nil {
		return BackupAttachment{}, err
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return BackupAttachment{}, err
	}
	if !info.Mode().IsRegular() {
		return BackupAttachment{}, fmt.Errorf("attachment is not a regular file")
	}
	if info.Size() > maxFileSize {
		return BackupAttachment{}, ErrBackupFileTooLarge
	}

	hash := sha256.New()
	var content strings.Builder
	content.Grow(base64.StdEncoding.EncodedLen(int(info.Size())))
	encoder := base64.NewEncoder(base64.StdEncoding, &content)
	written, copyErr := io.Copy(io.MultiWriter(encoder, hash), io.LimitReader(file, maxFileSize+1))
	encodeErr := encoder.Close()
	if copyErr != nil || encodeErr != nil {
		return BackupAttachment{}, errors.Join(copyErr, encodeErr)
	}
	if written > maxFileSize {
		return BackupAttachment{}, ErrBackupFileTooLarge
	}

	return BackupAttachment{
		RelativePath:  relativePath,
		Size:          written,
		SHA256:        hex.EncodeToString(hash.Sum(nil)),
		ContentBase64: content.String(),
	}, nil
}

func (s *BackupService) prepareAttachmentRestore(userID uint, attachments []BackupAttachment) (*attachmentRestorePlan, error) {
	// nil distinguishes a legacy backup (preserve existing files) from a new
	// backup containing an explicit, possibly empty, attachment manifest.
	if attachments == nil {
		return nil, nil
	}
	if !s.hasUploadStorage() {
		return nil, errors.New("upload storage is not configured")
	}
	if len(attachments) > maxBackupAttachmentCount {
		return nil, ErrBackupFileTooLarge
	}
	pathSet := newPortableAttachmentPathSet()
	for _, attachment := range attachments {
		normalizedPath, err := validateBackupAttachmentPath(attachment.RelativePath)
		if err != nil || normalizedPath != attachment.RelativePath {
			return nil, invalidBackupAttachment(errors.Join(err, errors.New("attachment path is not canonical")))
		}
		if err := pathSet.add(normalizedPath); err != nil {
			return nil, invalidBackupAttachment(err)
		}
	}

	if err := os.MkdirAll(s.uploadService.cfg.UploadPath, 0755); err != nil {
		return nil, fmt.Errorf("create upload root: %w", err)
	}
	uploadRoot, err := os.OpenRoot(s.uploadService.cfg.UploadPath)
	if err != nil {
		return nil, err
	}

	plan := &attachmentRestorePlan{
		root:           uploadRoot,
		userDirectory:  strconv.FormatUint(uint64(userID), 10),
		stageDirectory: fmt.Sprintf(".restore-%d-%s", userID, uuid.NewString()),
	}
	if err := uploadRoot.Mkdir(plan.stageDirectory, 0700); err != nil {
		uploadRoot.Close()
		return nil, fmt.Errorf("create attachment restore staging directory: %w", err)
	}

	stageRoot, err := uploadRoot.OpenRoot(plan.stageDirectory)
	if err != nil {
		return nil, errors.Join(err, plan.rollback())
	}

	var totalSize int64
	for _, attachment := range attachments {
		normalizedPath, pathErr := validateBackupAttachmentPath(attachment.RelativePath)
		if pathErr != nil || normalizedPath != attachment.RelativePath {
			err = invalidBackupAttachment(errors.Join(pathErr, errors.New("attachment path is not canonical")))
			break
		}

		// Reuse the upload service's ownership boundary for the final path. The
		// manifest path itself is relative to this user's directory.
		ownedPath := filepath.Join(plan.userDirectory, filepath.FromSlash(normalizedPath))
		if _, ownershipErr := s.uploadService.GetUserFilePath(userID, ownedPath); ownershipErr != nil {
			err = invalidBackupAttachment(ownershipErr)
			break
		}

		if attachment.Size < 0 {
			err = invalidBackupAttachment(errors.New("negative attachment size"))
			break
		}
		maxFileSize := s.uploadService.MaxFileSizeBytes()
		if attachment.Size > maxFileSize || attachment.Size > s.MaxRestoreBytes()-totalSize {
			err = ErrBackupFileTooLarge
			break
		}
		totalSize += attachment.Size

		if writeErr := writeRestoredAttachment(stageRoot, normalizedPath, attachment, maxFileSize); writeErr != nil {
			err = writeErr
			break
		}
	}
	closeErr := stageRoot.Close()
	if err == nil {
		err = closeErr
	} else if closeErr != nil {
		err = errors.Join(err, closeErr)
	}
	if err != nil {
		return nil, errors.Join(err, plan.rollback())
	}
	if err := uploadRoot.Chmod(plan.stageDirectory, 0755); err != nil {
		return nil, errors.Join(err, plan.rollback())
	}
	return plan, nil
}

func writeRestoredAttachment(root *os.Root, relativePath string, attachment BackupAttachment, maxFileSize int64) error {
	if _, err := hex.DecodeString(attachment.SHA256); err != nil || len(attachment.SHA256) != sha256.Size*2 {
		return invalidBackupAttachment(errors.New("invalid attachment sha256"))
	}
	if err := root.MkdirAll(path.Dir(relativePath), 0755); err != nil {
		return fmt.Errorf("create staged attachment directory: %w", err)
	}

	file, err := root.OpenFile(relativePath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		if errors.Is(err, os.ErrExist) {
			return invalidBackupAttachment(errors.New("attachment path collides on this filesystem"))
		}
		return fmt.Errorf("create staged attachment: %w", err)
	}

	hash := sha256.New()
	decoder := base64.NewDecoder(base64.StdEncoding, strings.NewReader(attachment.ContentBase64))
	written, copyErr := io.Copy(io.MultiWriter(file, hash), io.LimitReader(decoder, maxFileSize+1))
	closeErr := file.Close()
	if copyErr != nil {
		var corruptInput base64.CorruptInputError
		if errors.As(copyErr, &corruptInput) || errors.Is(copyErr, io.ErrUnexpectedEOF) {
			return errors.Join(invalidBackupAttachment(copyErr), closeErr)
		}
		return errors.Join(fmt.Errorf("write staged attachment: %w", copyErr), closeErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close staged attachment: %w", closeErr)
	}
	if written > maxFileSize {
		return ErrBackupFileTooLarge
	}
	if written != attachment.Size {
		return invalidBackupAttachment(errors.New("attachment size mismatch"))
	}
	if !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), attachment.SHA256) {
		return invalidBackupAttachment(errors.New("attachment sha256 mismatch"))
	}
	return nil
}

func validateBackupAttachmentPath(value string) (string, error) {
	parts, err := validatePortableBackupRelativePath(value)
	if err != nil {
		return "", err
	}
	// A manifest path is relative to the user directory. A leading numeric
	// segment is therefore never a valid source-user prefix and is rejected to
	// avoid accepting an ambiguously cross-user-shaped path.
	if isASCIIDecimal(parts[0]) {
		return "", errors.New("attachment path includes a user prefix")
	}
	return value, nil
}

func validatePortableBackupRelativePath(value string) ([]string, error) {
	if value == "" || len(value) > maxBackupAttachmentPathBytes || !utf8.ValidString(value) || strings.Contains(value, `\`) {
		return nil, errors.New("invalid attachment path")
	}
	if path.IsAbs(value) || path.Clean(value) != value || value == "." || value == ".." {
		return nil, errors.New("invalid attachment path")
	}
	parts := strings.Split(value, "/")
	if len(parts) > 32 {
		return nil, errors.New("attachment path is too deep")
	}
	for _, part := range parts {
		if !isPortableBackupPathSegment(part) {
			return nil, errors.New("invalid attachment path segment")
		}
	}
	return parts, nil
}

func isPortableBackupPathSegment(value string) bool {
	if value == "" || value == "." || value == ".." || len(value) > 255 || strings.HasSuffix(value, ".") || strings.HasSuffix(value, " ") {
		return false
	}
	for _, character := range value {
		if character < 0x20 || character == 0x7f || strings.ContainsRune(`<>:"/\|?*`, character) {
			return false
		}
	}

	deviceName := value
	if dot := strings.IndexByte(deviceName, '.'); dot >= 0 {
		deviceName = deviceName[:dot]
	}
	deviceName = strings.ToUpper(strings.TrimRight(deviceName, " ."))
	if isWindowsReservedDeviceName(deviceName) {
		return false
	}
	return true
}

func isWindowsReservedDeviceName(value string) bool {
	switch value {
	case "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$":
		return true
	}
	suffix := ""
	if strings.HasPrefix(value, "COM") {
		suffix = strings.TrimPrefix(value, "COM")
	} else if strings.HasPrefix(value, "LPT") {
		suffix = strings.TrimPrefix(value, "LPT")
	} else {
		return false
	}
	switch suffix {
	case "1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³":
		return true
	default:
		return false
	}
}

func isASCIIDecimal(value string) bool {
	if value == "" {
		return false
	}
	for _, character := range value {
		if character < '0' || character > '9' {
			return false
		}
	}
	return true
}

type portableAttachmentPathSet struct {
	files       map[string]string
	directories map[string]string
}

func newPortableAttachmentPathSet() *portableAttachmentPathSet {
	return &portableAttachmentPathSet{
		files:       make(map[string]string),
		directories: make(map[string]string),
	}
}

func (s *portableAttachmentPathSet) add(value string) error {
	fileKey := portableBackupPathKey(value)
	if _, exists := s.files[fileKey]; exists {
		return errors.New("duplicate attachment path after portable normalization")
	}
	if _, requiredAsDirectory := s.directories[fileKey]; requiredAsDirectory {
		return errors.New("attachment file and directory paths collide after portable normalization")
	}

	for directory := path.Dir(value); directory != "."; directory = path.Dir(directory) {
		directoryKey := portableBackupPathKey(directory)
		if _, existsAsFile := s.files[directoryKey]; existsAsFile {
			return errors.New("attachment file and directory paths collide after portable normalization")
		}
		if existing, exists := s.directories[directoryKey]; exists && existing != directory {
			return errors.New("attachment directory paths collide after portable normalization")
		}
		s.directories[directoryKey] = directory
	}

	s.files[fileKey] = value
	return nil
}

func portableBackupPathKey(value string) string {
	return cases.Fold().String(norm.NFC.String(value))
}

func invalidBackupAttachment(cause error) error {
	return fmt.Errorf("%w: invalid attachment manifest: %v", ErrInvalidBackupFormat, cause)
}

func (s *BackupService) hasUploadStorage() bool {
	return s != nil && s.uploadService != nil && s.uploadService.cfg != nil && strings.TrimSpace(s.uploadService.cfg.UploadPath) != ""
}

type attachmentRestorePlan struct {
	root              *os.Root
	userDirectory     string
	stageDirectory    string
	previousDirectory string
	hadPrevious       bool
	activated         bool
	closed            bool
}

func (p *attachmentRestorePlan) activate() error {
	if p == nil || p.activated {
		return nil
	}

	if _, err := p.root.Lstat(p.userDirectory); err == nil {
		p.previousDirectory = fmt.Sprintf(".restore-previous-%s-%s", p.userDirectory, uuid.NewString())
		if err := p.root.Rename(p.userDirectory, p.previousDirectory); err != nil {
			return fmt.Errorf("move current attachment directory aside: %w", err)
		}
		p.hadPrevious = true
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect current attachment directory: %w", err)
	}

	if err := p.root.Rename(p.stageDirectory, p.userDirectory); err != nil {
		var rollbackErr error
		if p.hadPrevious {
			rollbackErr = p.root.Rename(p.previousDirectory, p.userDirectory)
			if rollbackErr == nil {
				p.hadPrevious = false
				p.previousDirectory = ""
			}
		}
		return errors.Join(fmt.Errorf("activate restored attachment directory: %w", err), rollbackErr)
	}

	p.stageDirectory = ""
	p.activated = true
	return nil
}

func (p *attachmentRestorePlan) rollback() error {
	if p == nil || p.closed {
		return nil
	}
	var rollbackErr error
	if p.activated {
		if err := removeRootEntry(p.root, p.userDirectory); err != nil {
			rollbackErr = errors.Join(rollbackErr, fmt.Errorf("remove activated attachment directory: %w", err))
		} else {
			p.activated = false
		}
	}
	if p.hadPrevious && !p.activated {
		if err := p.root.Rename(p.previousDirectory, p.userDirectory); err != nil {
			rollbackErr = errors.Join(rollbackErr, fmt.Errorf("restore previous attachment directory: %w", err))
		} else {
			p.hadPrevious = false
			p.previousDirectory = ""
		}
	}
	if p.stageDirectory != "" {
		if err := removeRootEntry(p.root, p.stageDirectory); err != nil {
			rollbackErr = errors.Join(rollbackErr, fmt.Errorf("remove staged attachment directory: %w", err))
		} else {
			p.stageDirectory = ""
		}
	}
	rollbackErr = errors.Join(rollbackErr, p.close())
	return rollbackErr
}

func (p *attachmentRestorePlan) commit() error {
	if p == nil || p.closed {
		return nil
	}
	var commitErr error
	if p.hadPrevious {
		if err := removeRootEntry(p.root, p.previousDirectory); err != nil {
			commitErr = errors.Join(commitErr, fmt.Errorf("remove previous attachment directory: %w", err))
		} else {
			p.hadPrevious = false
			p.previousDirectory = ""
		}
	}
	if p.stageDirectory != "" {
		if err := removeRootEntry(p.root, p.stageDirectory); err != nil {
			commitErr = errors.Join(commitErr, fmt.Errorf("remove staged attachment directory: %w", err))
		} else {
			p.stageDirectory = ""
		}
	}
	return errors.Join(commitErr, p.close())
}

func (p *attachmentRestorePlan) close() error {
	if p == nil || p.closed || p.root == nil {
		return nil
	}
	p.closed = true
	return p.root.Close()
}

func removeRootEntry(root *os.Root, name string) error {
	if name == "" {
		return nil
	}
	info, err := root.Lstat(name)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	if info.IsDir() && info.Mode()&os.ModeSymlink == 0 {
		return root.RemoveAll(name)
	}
	return root.Remove(name)
}
