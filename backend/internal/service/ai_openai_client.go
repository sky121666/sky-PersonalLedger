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
)

type OpenAICompatibleClient struct {
	httpClient           *http.Client
	allowPrivateNetworks bool
}

func NewOpenAICompatibleClient(httpClient *http.Client, allowPrivateNetworks ...bool) *OpenAICompatibleClient {
	allowPrivate := len(allowPrivateNetworks) > 0 && allowPrivateNetworks[0]
	if httpClient == nil {
		httpClient = newSafeOutboundHTTPClient(allowPrivate)
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
		"max_tokens": 8,
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

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 2<<20)).Decode(&result); err != nil {
		return err
	}
	if len(result.Choices) == 0 {
		return errors.New("ai provider returned empty choices")
	}
	return nil
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

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 2<<20)).Decode(&result); err != nil {
		return "", err
	}
	if len(result.Choices) == 0 {
		return "", errors.New("ai provider returned empty choices")
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
		" Return one JSON object without Markdown fences. Required summary is a non-empty string. Optional title is a string; highlights and suggestions are arrays of strings; risks is an array of objects with level (low, medium or high), non-empty title and detail. Never fabricate missing history, transactions or budget settings."
}
