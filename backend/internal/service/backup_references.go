package service

import (
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
)

// normalizeBackupForRestore verifies that a per-user backup does not contain
// rows owned by multiple users, then remaps stored upload references to the
// authenticated restore target. Attachment file paths in the manifest are
// already relative to the user directory; database fields still use the
// upload API's {user_id}/scope/ref/file representation.
func normalizeBackupForRestore(backup *FullBackupData, targetUserID uint) error {
	if backup == nil {
		return ErrInvalidBackupFormat
	}

	sourceUserID := backup.SourceUserID
	acceptUserID := func(candidate uint) error {
		if candidate == 0 {
			return nil
		}
		if sourceUserID == 0 {
			sourceUserID = candidate
			return nil
		}
		if candidate != sourceUserID {
			return errors.New("backup contains data from multiple users")
		}
		return nil
	}

	for i := range backup.Accounts {
		if err := acceptUserID(backup.Accounts[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Categories {
		if err := acceptUserID(backup.Categories[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Transactions {
		if err := acceptUserID(backup.Transactions[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Budgets {
		if err := acceptUserID(backup.Budgets[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Reminders {
		if err := acceptUserID(backup.Reminders[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for _, lending := range backup.Lendings {
		if lending == nil {
			return invalidBackupOwnership(errors.New("backup contains a null lending"))
		}
		if err := acceptUserID(lending.UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for _, record := range backup.LendingRecords {
		if record == nil {
			return invalidBackupOwnership(errors.New("backup contains a null lending record"))
		}
		if err := acceptUserID(record.UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Templates {
		if err := acceptUserID(backup.Templates[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Tags {
		if err := acceptUserID(backup.Tags[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.FamilyMembers {
		if err := acceptUserID(backup.FamilyMembers[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.AIReports {
		if err := acceptUserID(backup.AIReports[i].UserID); err != nil {
			return invalidBackupOwnership(err)
		}
	}
	if err := visitBackupStoredUploadReferences(backup, func(value string) error {
		reference, recognized, err := parseStoredUploadReference(value)
		if err != nil {
			return err
		}
		if recognized {
			return acceptUserID(reference.owner)
		}
		return nil
	}); err != nil {
		return invalidBackupOwnership(err)
	}

	backup.SourceUserID = sourceUserID
	if sourceUserID == 0 {
		if err := normalizeBackupAttachmentScopes(backup, targetUserID); err != nil {
			return invalidBackupOwnership(err)
		}
		return nil
	}

	var err error
	if backup.UserProfile != nil {
		backup.UserProfile.Avatar, err = remapStoredUploadReference(backup.UserProfile.Avatar, sourceUserID, targetUserID)
		if err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Transactions {
		backup.Transactions[i].Images, err = remapStoredUploadReferenceList(backup.Transactions[i].Images, sourceUserID, targetUserID)
		if err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.Reminders {
		backup.Reminders[i].Evidence, err = remapStoredUploadReferenceList(backup.Reminders[i].Evidence, sourceUserID, targetUserID)
		if err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for _, lending := range backup.Lendings {
		lending.Evidence, err = remapStoredUploadReferenceList(lending.Evidence, sourceUserID, targetUserID)
		if err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for _, record := range backup.LendingRecords {
		record.Evidence, err = remapStoredUploadReferenceList(record.Evidence, sourceUserID, targetUserID)
		if err != nil {
			return invalidBackupOwnership(err)
		}
	}
	for i := range backup.FamilyMembers {
		backup.FamilyMembers[i].Avatar, err = remapStoredUploadReference(backup.FamilyMembers[i].Avatar, sourceUserID, targetUserID)
		if err != nil {
			return invalidBackupOwnership(err)
		}
	}
	if err := normalizeBackupAttachmentScopes(backup, targetUserID); err != nil {
		return invalidBackupOwnership(err)
	}
	return nil
}

func normalizeBackupAttachmentScopes(backup *FullBackupData, userID uint) error {
	for index := range backup.Transactions {
		normalized, err := normalizeTransactionAttachmentImages(backup.Transactions[index].ID, userID, backup.Transactions[index].Images)
		if err != nil {
			return err
		}
		backup.Transactions[index].Images = normalized
	}
	for index := range backup.Reminders {
		normalized, err := normalizeAttachmentEvidence(
			backup.Reminders[index].Evidence,
			userID,
			"reminders",
			exactAttachmentRef(backup.Reminders[index].ID),
		)
		if err != nil {
			return err
		}
		backup.Reminders[index].Evidence = normalized
	}
	for _, lending := range backup.Lendings {
		normalized, err := normalizeAttachmentEvidence(lending.Evidence, userID, "lendings", exactAttachmentRef(lending.ID))
		if err != nil {
			return err
		}
		lending.Evidence = normalized
	}
	for _, record := range backup.LendingRecords {
		normalized, err := normalizeAttachmentEvidence(
			record.Evidence,
			userID,
			"lendings",
			lendingRepaymentAttachmentRef(record.LendingID),
		)
		if err != nil {
			return err
		}
		record.Evidence = normalized
	}
	return nil
}

func remapStoredUploadReferenceList(value string, sourceUserID uint, targetUserID uint) (string, error) {
	if strings.TrimSpace(value) == "" {
		return value, nil
	}

	paths, jsonArray, err := parseStoredUploadReferenceList(value)
	if err != nil {
		return "", err
	}
	if jsonArray {
		for i := range paths {
			remapped, err := remapStoredUploadReference(paths[i], sourceUserID, targetUserID)
			if err != nil {
				return "", err
			}
			paths[i] = remapped
		}
		data, err := json.Marshal(paths)
		return string(data), err
	}

	for i := range paths {
		candidate := strings.TrimSpace(paths[i])
		remapped, err := remapStoredUploadReference(candidate, sourceUserID, targetUserID)
		if err != nil {
			return "", err
		}
		paths[i] = remapped
	}
	return strings.Join(paths, ","), nil
}

func remapStoredUploadReference(value string, sourceUserID uint, targetUserID uint) (string, error) {
	if value == "" {
		return value, nil
	}
	reference, recognized, err := parseStoredUploadReference(value)
	if err != nil {
		return "", err
	}
	if !recognized {
		return value, nil
	}
	if sourceUserID == 0 || reference.owner != sourceUserID {
		return "", errors.New("backup references another user's upload")
	}
	target := strconv.FormatUint(uint64(targetUserID), 10)
	if reference.absoluteURL {
		return "/uploads/" + target + "/" + reference.suffix, nil
	}
	return target + "/" + reference.suffix, nil
}

type storedUploadReference struct {
	owner       uint
	suffix      string
	absoluteURL bool
}

func parseStoredUploadReference(value string) (storedUploadReference, bool, error) {
	if value == "" {
		return storedUploadReference{}, false, nil
	}
	trimmed := strings.TrimSpace(value)
	if trimmed != value && looksLikeStoredUploadReference(trimmed) {
		return storedUploadReference{}, true, errors.New("internal upload reference contains surrounding whitespace")
	}

	if strings.HasPrefix(value, "/uploads/") {
		owner, suffix, ok := strings.Cut(strings.TrimPrefix(value, "/uploads/"), "/")
		if !ok {
			return storedUploadReference{}, true, errors.New("internal upload reference has no relative suffix")
		}
		ownerID, err := parseStoredUploadOwner(owner)
		if err != nil {
			return storedUploadReference{}, true, err
		}
		if _, err := validatePortableBackupRelativePath(suffix); err != nil {
			return storedUploadReference{}, true, fmt.Errorf("invalid internal upload suffix: %w", err)
		}
		return storedUploadReference{owner: ownerID, suffix: suffix, absoluteURL: true}, true, nil
	}

	owner, suffix, ok := strings.Cut(value, "/")
	if !ok || !isASCIIDecimal(owner) {
		if separator := strings.IndexByte(value, '\\'); separator > 0 && isASCIIDecimal(value[:separator]) {
			return storedUploadReference{}, true, errors.New("internal upload reference uses a backslash separator")
		}
		return storedUploadReference{}, false, nil
	}
	ownerID, err := parseStoredUploadOwner(owner)
	if err != nil {
		return storedUploadReference{}, true, err
	}
	if _, err := validatePortableBackupRelativePath(suffix); err != nil {
		return storedUploadReference{}, true, fmt.Errorf("invalid internal upload suffix: %w", err)
	}
	return storedUploadReference{owner: ownerID, suffix: suffix}, true, nil
}

func parseStoredUploadOwner(value string) (uint, error) {
	if !isASCIIDecimal(value) {
		return 0, errors.New("internal upload reference has an invalid owner")
	}
	parsed, err := strconv.ParseUint(value, 10, strconv.IntSize)
	if err != nil || parsed == 0 || strconv.FormatUint(parsed, 10) != value {
		return 0, errors.New("internal upload reference has a non-canonical owner")
	}
	return uint(parsed), nil
}

func looksLikeStoredUploadReference(value string) bool {
	if strings.HasPrefix(value, "/uploads/") {
		return true
	}
	separator := strings.IndexAny(value, `/\`)
	return separator > 0 && isASCIIDecimal(value[:separator])
}

func visitBackupStoredUploadReferences(backup *FullBackupData, visit func(string) error) error {
	if backup.UserProfile != nil {
		if err := visit(backup.UserProfile.Avatar); err != nil {
			return err
		}
	}
	for i := range backup.Transactions {
		if err := visitStoredUploadReferenceList(backup.Transactions[i].Images, visit); err != nil {
			return err
		}
	}
	for i := range backup.Reminders {
		if err := visitStoredUploadReferenceList(backup.Reminders[i].Evidence, visit); err != nil {
			return err
		}
	}
	for _, lending := range backup.Lendings {
		if lending == nil {
			continue
		}
		if err := visitStoredUploadReferenceList(lending.Evidence, visit); err != nil {
			return err
		}
	}
	for _, record := range backup.LendingRecords {
		if record == nil {
			continue
		}
		if err := visitStoredUploadReferenceList(record.Evidence, visit); err != nil {
			return err
		}
	}
	for i := range backup.FamilyMembers {
		if err := visit(backup.FamilyMembers[i].Avatar); err != nil {
			return err
		}
	}
	return nil
}

func visitStoredUploadReferenceList(value string, visit func(string) error) error {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	paths, _, err := parseStoredUploadReferenceList(value)
	if err != nil {
		return err
	}
	for _, storedPath := range paths {
		if err := visit(strings.TrimSpace(storedPath)); err != nil {
			return err
		}
	}
	return nil
}

func parseStoredUploadReferenceList(value string) ([]string, bool, error) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil, false, nil
	}
	if strings.HasPrefix(trimmed, "[") || trimmed == "null" {
		var rawPaths []json.RawMessage
		if err := json.Unmarshal([]byte(trimmed), &rawPaths); err != nil {
			return nil, true, errors.New("internal upload reference array is invalid")
		}
		paths := make([]string, len(rawPaths))
		for index, rawPath := range rawPaths {
			if err := json.Unmarshal(rawPath, &paths[index]); err != nil {
				return nil, true, errors.New("internal upload reference array must contain only strings")
			}
		}
		return paths, true, nil
	}
	if json.Valid([]byte(trimmed)) {
		return nil, false, errors.New("internal upload reference JSON must be an array")
	}
	return strings.Split(value, ","), false, nil
}

func invalidBackupOwnership(cause error) error {
	return fmt.Errorf("%w: invalid per-user backup: %v", ErrInvalidBackupFormat, cause)
}
