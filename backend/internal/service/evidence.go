package service

import (
	"encoding/json"
	"errors"
	"strconv"
	"strings"
)

var (
	ErrInvalidAttachmentEvidence = errors.New("invalid attachment evidence")
	ErrCreateAttachmentEvidence  = errors.New("attachments must be added after record creation")
)

func normalizeCreateAttachmentEvidence(value string) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	paths, _, err := parseStoredUploadReferenceList(value)
	if err != nil {
		return "", ErrInvalidAttachmentEvidence
	}
	if len(paths) != 0 {
		return "", ErrCreateAttachmentEvidence
	}
	return "[]", nil
}

func normalizeAttachmentEvidence(
	value string,
	userID uint,
	category string,
	refAllowed func(string) bool,
) (string, error) {
	if strings.TrimSpace(value) == "" {
		return "", nil
	}
	paths, _, err := parseStoredUploadReferenceList(value)
	if err != nil {
		return "", ErrInvalidAttachmentEvidence
	}

	owner := strconv.FormatUint(uint64(userID), 10)
	normalizedPaths := make([]string, 0, len(paths))
	for _, storedPath := range paths {
		normalized := normalizeStoredUploadReference(storedPath)
		if normalized == "" || strings.Contains(normalized, `\`) {
			return "", ErrInvalidAttachmentEvidence
		}
		parts := strings.Split(normalized, "/")
		if len(parts) != 4 || parts[0] != owner || parts[1] != category || !refAllowed(parts[2]) {
			return "", ErrInvalidAttachmentEvidence
		}
		if sanitizeUploadFilename(parts[3]) != parts[3] {
			return "", ErrInvalidAttachmentEvidence
		}
		normalizedPaths = append(normalizedPaths, normalized)
	}
	encoded, err := json.Marshal(normalizedPaths)
	if err != nil {
		return "", ErrInvalidAttachmentEvidence
	}
	return string(encoded), nil
}

func exactAttachmentRef(expected string) func(string) bool {
	return func(candidate string) bool { return candidate == expected }
}

func lendingRepaymentAttachmentRef(lendingID string) func(string) bool {
	prefix := lendingID + "_repay_"
	return func(candidate string) bool {
		return strings.HasPrefix(candidate, prefix) && len(candidate) > len(prefix) && isSafeUploadPathSegment(candidate)
	}
}
