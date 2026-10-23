package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const aiReportRequestTimeout = 45 * time.Second

type OpenAICompatibleClient struct {
	httpClient           *http.Client
	allowPrivateNetworks bool
}

func NewOpenAICompatibleClient(httpClient *http.Client, allowPrivateNetworks ...bool) *OpenAICompatibleClient {
	allowPrivate := len(allowPrivateNetworks) > 0 && allowPrivateNetworks[0]
	if httpClient == nil {
		httpClient = newSafeOutboundHTTPClient(allowPrivate)
		// Keep the safe dial/redirect policy, but allow the report service's
		// full response budget without changing other outbound integrations.
		httpClient.Timeout = aiReportRequestTimeout
	}
	return &OpenAICompatibleClient{httpClient: httpClient, allowPrivateNetworks: allowPrivate}
}

func NormalizeOpenAIChatCompletionsURL(baseURL string) string {
	normalized := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	parsed, err := url.Parse(normalized)
	if err == nil && strings.EqualFold(parsed.Host, "api.deepseek.com") && (parsed.Path == "" || parsed.Path == "/") {
		return normalized + "/chat/completions"
	}
	switch {
	case strings.HasSuffix(normalized, "/chat/completions"):
		return normalized
	case strings.HasSuffix(normalized, "/v1"):
		return normalized + "/chat/completions"
	default:
		return normalized + "/v1/chat/completions"
	}
}

func (c *OpenAICompatibleClient) TestConnection(ctx context.Context, baseURL string, apiKey string, model string) error {
	payload := map[string]any{
		"model": model,
		"messages": []map[string]string{
			{"role": "user", "content": "Reply with ok."},
		},
		"max_tokens": 32,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	endpoint := NormalizeOpenAIChatCompletionsURL(baseURL)
	if err := validateOutboundURL(endpoint, c.allowPrivateNetworks); err != nil {
		return ErrAIProviderBaseURLInvalid
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if strings.TrimSpace(apiKey) != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("ai provider returned status %d", resp.StatusCode)
	}

	_, err = readAICompletion(resp.Body)
	return err
}

func (c *OpenAICompatibleClient) GenerateReport(ctx context.Context, baseURL string, apiKey string, model string, snapshotJSON string, reportType string) (string, error) {
	payload := map[string]any{
		"model": model,
		"messages": []map[string]string{
			{
				"role":    "system",
				"content": aiReportTaskPrompt(reportType),
			},
			{
				"role":    "user",
				"content": snapshotJSON,
			},
		},
		"temperature": 0.2,
		"max_tokens":  4096,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	endpoint := NormalizeOpenAIChatCompletionsURL(baseURL)
	if err := validateOutboundURL(endpoint, c.allowPrivateNetworks); err != nil {
		return "", ErrAIProviderBaseURLInvalid
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	if strings.TrimSpace(apiKey) != "" {
		req.Header.Set("Authorization", "Bearer "+apiKey)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusMultipleChoices {
		return "", fmt.Errorf("ai provider returned status %d", resp.StatusCode)
	}

	return readAICompletion(resp.Body)
}

func readAICompletion(body io.Reader) (string, error) {
	var result struct {
		Choices []struct {
			FinishReason string `json:"finish_reason"`
			Message      struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(io.LimitReader(body, 2<<20)).Decode(&result); err != nil {
		return "", err
	}
	if len(result.Choices) == 0 {
		return "", errors.New("ai provider returned empty choices")
	}
	// Older compatible providers omit this field. Explicitly incomplete or
	// non-text completions must not become successful, cacheable reports.
	if reason := result.Choices[0].FinishReason; reason != "" && reason != "stop" {
		return "", errors.New("ai provider did not finish a complete text response")
	}
	content := strings.TrimSpace(result.Choices[0].Message.Content)
	if content == "" {
		return "", errors.New("ai provider returned empty content")
	}
	return content, nil
}

func aiReportTaskPrompt(reportType string) string {
	tasks := map[string]string{
		"weekly":  "Summarize the selected week's cash flow and spending. Distinguish weekly totals from the explicit monthly budget period.",
		"monthly": "Review the selected month's cash flow, category composition and budget progress.",
		"family":  "Analyze household member spending and member budgets, preserving each anonymous member identity.",
		"budget":  "Explain allowance usage, remaining amounts and over-budget categories for the explicit budget period. Unknown allowances are not zero.",
		"anomaly": "Identify only risks supported by supplied aggregates. Do not claim transaction-level outliers or historical comparisons absent from the facts.",
	}
	return "You are a financial analysis assistant for a private household ledger. Use only the provided facts. Report type: " + reportType + ". " + tasks[reportType] +
		" budget.over_budget_categories is an alert list that also includes near-limit categories; membership alone does not mean overspending or overlapping budgets." +
		" Determine overspending only when spent > amount. When spent equals amount the budget is exhausted; when spent is below amount it is within budget even if an alert threshold is reached." +
		" Write every narrative field (title, summary, highlights, risk title and detail, suggestions) in Simplified Chinese. Keep JSON keys and supplied factual identifiers unchanged." +
		" Return one JSON object without Markdown fences. Required summary is a non-empty string. Optional title is a string; highlights and suggestions are arrays of strings; risks is an array of objects with level (low, medium or high), non-empty title and detail. Never fabricate missing history, transactions or budget settings."
}
