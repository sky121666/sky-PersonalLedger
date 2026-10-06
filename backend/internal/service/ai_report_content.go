package service

import (
	"encoding/json"
	"strings"
)

type aiReportContent struct {
	Title       string                `json:"title,omitempty"`
	Summary     string                `json:"summary"`
	Highlights  []string              `json:"highlights,omitempty"`
	Risks       []aiReportRiskContent `json:"risks,omitempty"`
	Suggestions []string              `json:"suggestions,omitempty"`
}

type aiReportRiskContent struct {
	Level  string `json:"level"`
	Title  string `json:"title"`
	Detail string `json:"detail"`
}

func normalizeAIReportContent(content string) (string, error) {
	content = strings.TrimSpace(content)
	if strings.HasPrefix(content, "```json\n") || strings.HasPrefix(content, "```\n") {
		if !strings.HasSuffix(content, "```") {
			return "", ErrAIReportContentInvalid
		}
		content = strings.TrimSpace(content[strings.IndexByte(content, '\n')+1 : len(content)-3])
	}
	var parsed aiReportContent
	if json.Valid([]byte(content)) {
		if !strings.HasPrefix(content, "{") || !validAIReportFieldTypes([]byte(content)) || json.Unmarshal([]byte(content), &parsed) != nil {
			return "", ErrAIReportContentInvalid
		}
	} else {
		// Text remains compatible with older/custom providers; malformed JSON
		// must not be silently relabelled as a successful narrative report.
		if content == "" || strings.HasPrefix(content, "{") || strings.HasPrefix(content, "[") || strings.HasPrefix(content, "```") {
			return "", ErrAIReportContentInvalid
		}
		parsed.Summary = content
	}
	parsed.Summary = strings.TrimSpace(parsed.Summary)
	if parsed.Summary == "" {
		return "", ErrAIReportContentInvalid
	}
	for _, risk := range parsed.Risks {
		if (risk.Level != "low" && risk.Level != "medium" && risk.Level != "high") || strings.TrimSpace(risk.Title) == "" || strings.TrimSpace(risk.Detail) == "" {
			return "", ErrAIReportContentInvalid
		}
	}
	data, err := json.Marshal(parsed)
	if err != nil {
		return "", ErrAIReportContentInvalid
	}
	return string(data), nil
}

// Go's JSON decoder accepts null for scalar strings and string-array elements.
// Check the supplied JSON types before decoding so wrong types cannot become
// empty strings in an apparently successful, cacheable report.
func validAIReportFieldTypes(content []byte) bool {
	var fields map[string]json.RawMessage
	if json.Unmarshal(content, &fields) != nil {
		return false
	}
	if !canonicalAIReportKeys(fields, "title", "summary", "highlights", "suggestions", "risks") {
		return false
	}
	isString := func(value json.RawMessage) bool {
		value = json.RawMessage(strings.TrimSpace(string(value)))
		var decoded string
		return len(value) > 0 && value[0] == '"' && json.Unmarshal(value, &decoded) == nil
	}
	if !isString(fields["summary"]) {
		return false
	}
	if value, exists := fields["title"]; exists && !isString(value) {
		return false
	}
	for _, name := range []string{"highlights", "suggestions", "risks"} {
		value, exists := fields[name]
		if !exists {
			continue
		}
		value = json.RawMessage(strings.TrimSpace(string(value)))
		var items []json.RawMessage
		if len(value) == 0 || value[0] != '[' || json.Unmarshal(value, &items) != nil {
			return false
		}
		for _, item := range items {
			if name != "risks" {
				if !isString(item) {
					return false
				}
				continue
			}
			var risk map[string]json.RawMessage
			if json.Unmarshal(item, &risk) != nil || !canonicalAIReportKeys(risk, "level", "title", "detail") || !isString(risk["level"]) || !isString(risk["title"]) || !isString(risk["detail"]) {
				return false
			}
		}
	}
	return true
}

func canonicalAIReportKeys(fields map[string]json.RawMessage, known ...string) bool {
	for supplied := range fields {
		for _, name := range known {
			// encoding/json matches struct names case-insensitively. Reject
			// aliases so validation and final decoding cannot disagree.
			if supplied != name && strings.EqualFold(supplied, name) {
				return false
			}
		}
	}
	return true
}
