package service

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"strings"
)

const (
	maxBackupTotalRecordCount = 100_000
	maxBackupJSONDepth        = 64
	maxBackupTopLevelFields   = 128
)

var backupCollectionRecordLimits = map[string]int{
	"accounts":          10_000,
	"categories":        10_000,
	"transactions":      100_000,
	"budgets":           10_000,
	"reminders":         10_000,
	"lendings":          10_000,
	"lending_records":   50_000,
	"templates":         10_000,
	"tags":              10_000,
	"family_members":    10_000,
	"ai_reports":        10_000,
	"account_logs":      100_000,
	"notification_logs": 100_000,
	"attachments":       maxBackupAttachmentCount,
}

var backupJSONTopLevelFields = map[string]string{
	"version":               "version",
	"exported_at":           "exported_at",
	"source_user_id":        "source_user_id",
	"user_profile":          "user_profile",
	"accounts":              "accounts",
	"categories":            "categories",
	"transactions":          "transactions",
	"budgets":               "budgets",
	"reminders":             "reminders",
	"lendings":              "lendings",
	"lending_records":       "lending_records",
	"templates":             "templates",
	"tags":                  "tags",
	"family_members":        "family_members",
	"ai_reports":            "ai_reports",
	"account_logs":          "account_logs",
	"notification_logs":     "notification_logs",
	"notification_settings": "notification_settings",
	"attachments":           "attachments",
}

var backupJSONStructFieldAliases = map[string]string{
	"Version":              "version",
	"ExportedAt":           "exported_at",
	"SourceUserID":         "source_user_id",
	"UserProfile":          "user_profile",
	"Accounts":             "accounts",
	"Categories":           "categories",
	"Transactions":         "transactions",
	"Budgets":              "budgets",
	"Reminders":            "reminders",
	"Lendings":             "lendings",
	"LendingRecords":       "lending_records",
	"Templates":            "templates",
	"Tags":                 "tags",
	"FamilyMembers":        "family_members",
	"AIReports":            "ai_reports",
	"AccountLogs":          "account_logs",
	"NotificationLogs":     "notification_logs",
	"NotificationSettings": "notification_settings",
	"Attachments":          "attachments",
}

type backupAttachmentsJSONState uint8

const (
	backupAttachmentsMissing backupAttachmentsJSONState = iota
	backupAttachmentsNull
	backupAttachmentsArray
)

type backupJSONEnvelope struct {
	version                             string
	attachmentsState                    backupAttachmentsJSONState
	notificationCredentialFieldsPresent bool
}

// preflightBackupJSON tokenizes the envelope and every collection before the
// large model slices are allocated by json.Unmarshal. Counts are checked
// before each element is scanned, so dense arrays fail close to their limit.
func preflightBackupJSON(data []byte) (backupJSONEnvelope, error) {
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.UseNumber()

	opening, err := decoder.Token()
	if err != nil {
		return backupJSONEnvelope{}, invalidBackupJSON(err)
	}
	if delimiter, ok := opening.(json.Delim); !ok || delimiter != '{' {
		return backupJSONEnvelope{}, invalidBackupJSON(errors.New("backup root must be an object"))
	}

	envelope := backupJSONEnvelope{attachmentsState: backupAttachmentsMissing}
	seenKnownFields := make(map[string]struct{}, len(backupCollectionRecordLimits)+1)
	totalRecords := 0
	topLevelFields := 0

	for decoder.More() {
		topLevelFields++
		if topLevelFields > maxBackupTopLevelFields {
			return backupJSONEnvelope{}, invalidBackupJSON(errors.New("too many top-level fields"))
		}

		keyToken, err := decoder.Token()
		if err != nil {
			return backupJSONEnvelope{}, invalidBackupJSON(err)
		}
		key, ok := keyToken.(string)
		if !ok {
			return backupJSONEnvelope{}, invalidBackupJSON(errors.New("invalid top-level field name"))
		}
		if canonicalKey, known := canonicalBackupJSONField(key); known {
			if key != canonicalKey {
				return backupJSONEnvelope{}, invalidBackupJSON(fmt.Errorf("non-canonical %s field", canonicalKey))
			}
			if _, duplicate := seenKnownFields[canonicalKey]; duplicate {
				return backupJSONEnvelope{}, invalidBackupJSON(fmt.Errorf("duplicate %s field", canonicalKey))
			}
			seenKnownFields[canonicalKey] = struct{}{}
		}

		collectionLimit, isCollection := backupCollectionRecordLimits[key]

		switch {
		case key == "version":
			versionToken, err := decoder.Token()
			if err != nil {
				return backupJSONEnvelope{}, invalidBackupJSON(err)
			}
			version, ok := versionToken.(string)
			if !ok || len(version) > 16 {
				return backupJSONEnvelope{}, invalidBackupJSON(errors.New("invalid backup version"))
			}
			envelope.version = version

		case key == "attachments":
			state, err := scanBackupCollection(decoder, key, collectionLimit, &totalRecords)
			if err != nil {
				return backupJSONEnvelope{}, err
			}
			envelope.attachmentsState = state

		case key == "notification_settings":
			credentialsPresent, err := scanBackupNotificationSettings(decoder)
			if err != nil {
				return backupJSONEnvelope{}, err
			}
			envelope.notificationCredentialFieldsPresent = credentialsPresent

		case isCollection:
			if _, err := scanBackupCollection(decoder, key, collectionLimit, &totalRecords); err != nil {
				return backupJSONEnvelope{}, err
			}

		default:
			if err := skipBackupJSONValue(decoder, 1); err != nil {
				return backupJSONEnvelope{}, invalidBackupJSON(err)
			}
		}
	}

	closing, err := decoder.Token()
	if err != nil {
		return backupJSONEnvelope{}, invalidBackupJSON(err)
	}
	if delimiter, ok := closing.(json.Delim); !ok || delimiter != '}' {
		return backupJSONEnvelope{}, invalidBackupJSON(errors.New("invalid backup object"))
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		if err == nil {
			err = errors.New("trailing JSON value")
		}
		return backupJSONEnvelope{}, invalidBackupJSON(err)
	}

	switch envelope.version {
	case "2.1":
		if envelope.attachmentsState == backupAttachmentsArray {
			return backupJSONEnvelope{}, invalidBackupJSON(errors.New("backup version 2.1 cannot contain an attachment manifest"))
		}
	case "2.2":
		if envelope.attachmentsState != backupAttachmentsArray {
			return backupJSONEnvelope{}, invalidBackupJSON(errors.New("backup version 2.2 requires an attachment array"))
		}
	case "2.3":
		// Version 2.3 makes attachment inclusion explicit: null means the
		// backup did not include file data, while an array is an authoritative
		// attachment manifest (including an intentionally empty one).
		if envelope.attachmentsState == backupAttachmentsMissing {
			return backupJSONEnvelope{}, invalidBackupJSON(errors.New("backup version 2.3 requires an explicit attachment value"))
		}
		if envelope.notificationCredentialFieldsPresent {
			return backupJSONEnvelope{}, invalidBackupJSON(errors.New("backup version 2.3 cannot contain notification credentials"))
		}
	default:
		return backupJSONEnvelope{}, invalidBackupJSON(errors.New("unsupported backup version"))
	}

	return envelope, nil
}

func scanBackupNotificationSettings(decoder *json.Decoder) (bool, error) {
	opening, err := decoder.Token()
	if err != nil {
		return false, invalidBackupJSON(err)
	}
	if opening == nil {
		return false, nil
	}
	if delimiter, ok := opening.(json.Delim); !ok || delimiter != '{' {
		return false, invalidBackupJSON(errors.New("notification_settings must be an object or null"))
	}

	credentialsPresent := false
	for decoder.More() {
		keyToken, err := decoder.Token()
		if err != nil {
			return false, invalidBackupJSON(err)
		}
		key, ok := keyToken.(string)
		if !ok {
			return false, invalidBackupJSON(errors.New("invalid notification setting field name"))
		}
		if isNotificationCredentialBackupField(key) {
			credentialsPresent = true
		}
		if err := skipBackupJSONValue(decoder, 1); err != nil {
			return false, invalidBackupJSON(err)
		}
	}
	closing, err := decoder.Token()
	if err != nil {
		return false, invalidBackupJSON(err)
	}
	if delimiter, ok := closing.(json.Delim); !ok || delimiter != '}' {
		return false, invalidBackupJSON(errors.New("invalid notification_settings object"))
	}
	return credentialsPresent, nil
}

func isNotificationCredentialBackupField(value string) bool {
	for _, field := range []string{
		"wecom_webhook", "WecomWebhook",
		"dingtalk_webhook", "DingtalkWebhook",
		"dingtalk_secret", "DingtalkSecret",
		"smtp_password", "SmtpPassword",
		"webhook_url", "WebhookURL",
		"webhook_secret", "WebhookSecret",
	} {
		if strings.EqualFold(value, field) {
			return true
		}
	}
	return false
}

func canonicalBackupJSONField(value string) (string, bool) {
	if canonical, exists := backupJSONTopLevelFields[value]; exists {
		return canonical, true
	}
	for _, canonical := range backupJSONTopLevelFields {
		if strings.EqualFold(value, canonical) {
			return canonical, true
		}
	}
	for alias, canonical := range backupJSONStructFieldAliases {
		if strings.EqualFold(value, alias) {
			return canonical, true
		}
	}
	return "", false
}

func scanBackupCollection(decoder *json.Decoder, field string, limit int, totalRecords *int) (backupAttachmentsJSONState, error) {
	opening, err := decoder.Token()
	if err != nil {
		return backupAttachmentsMissing, invalidBackupJSON(err)
	}
	if opening == nil {
		return backupAttachmentsNull, nil
	}
	delimiter, ok := opening.(json.Delim)
	if !ok || delimiter != '[' {
		return backupAttachmentsMissing, invalidBackupJSON(fmt.Errorf("%s must be an array or null", field))
	}

	count := 0
	for decoder.More() {
		count++
		*totalRecords++
		if count > limit {
			return backupAttachmentsMissing, backupRecordLimitError(field, limit)
		}
		if *totalRecords > maxBackupTotalRecordCount {
			return backupAttachmentsMissing, backupRecordLimitError("total", maxBackupTotalRecordCount)
		}
		if err := skipBackupJSONValue(decoder, 1); err != nil {
			return backupAttachmentsMissing, invalidBackupJSON(err)
		}
	}

	closing, err := decoder.Token()
	if err != nil {
		return backupAttachmentsMissing, invalidBackupJSON(err)
	}
	if delimiter, ok := closing.(json.Delim); !ok || delimiter != ']' {
		return backupAttachmentsMissing, invalidBackupJSON(fmt.Errorf("invalid %s array", field))
	}
	return backupAttachmentsArray, nil
}

func skipBackupJSONValue(decoder *json.Decoder, depth int) error {
	if depth > maxBackupJSONDepth {
		return errors.New("backup JSON is too deeply nested")
	}
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, ok := token.(json.Delim)
	if !ok {
		return nil
	}

	switch delimiter {
	case '{':
		for decoder.More() {
			key, err := decoder.Token()
			if err != nil {
				return err
			}
			if _, ok := key.(string); !ok {
				return errors.New("invalid object field name")
			}
			if err := skipBackupJSONValue(decoder, depth+1); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim('}') {
			return errors.New("invalid JSON object")
		}
		return nil

	case '[':
		for decoder.More() {
			if err := skipBackupJSONValue(decoder, depth+1); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil {
			return err
		}
		if closing != json.Delim(']') {
			return errors.New("invalid JSON array")
		}
		return nil

	default:
		return errors.New("unexpected JSON delimiter")
	}
}

func invalidBackupJSON(cause error) error {
	return fmt.Errorf("%w: %v", ErrInvalidBackupFormat, cause)
}

func backupRecordLimitError(field string, limit int) error {
	return fmt.Errorf("%w: %w: %s exceeds %d records", ErrInvalidBackupFormat, ErrBackupRecordLimitExceeded, field, limit)
}
