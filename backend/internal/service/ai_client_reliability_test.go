package service

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

func TestAIClientRejectsEmptyAndIncompleteCompletions(t *testing.T) {
	for _, tc := range []struct {
		name, content, finish string
		wantError             bool
	}{
		{"empty", "", "stop", true},
		{"whitespace", " \n\t", "stop", true},
		{"truncated", "partial answer", "length", true},
		{"filtered", "partial answer", "content_filter", true},
		{"tool_call", "partial answer", "tool_calls", true},
		{"completed", "ok", "stop", false},
		{"legacy_without_finish_reason", "ok", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			client := NewOpenAICompatibleClient(&http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) {
				data, _ := json.Marshal(map[string]any{"choices": []any{map[string]any{
					"message": map[string]string{"content": tc.content}, "finish_reason": tc.finish,
				}}})
				return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(string(data))), Header: make(http.Header)}, nil
			})})
			if err := client.TestConnection(context.Background(), "https://example.com", "", "fixture"); (err != nil) != tc.wantError {
				t.Errorf("connection error = %v, want error = %v", err, tc.wantError)
			}
			if _, err := client.GenerateReport(context.Background(), "https://example.com", "", "fixture", "{}", "weekly"); (err != nil) != tc.wantError {
				t.Errorf("generation error = %v, want error = %v", err, tc.wantError)
			}
		})
	}
}

func TestAIReportAcceptsResponseAfterGeneralOutboundTimeout(t *testing.T) {
	if testing.Short() {
		t.Skip("31-second production timeout regression")
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-time.After(31 * time.Second):
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"finish_reason":"stop","message":{"content":"{\"summary\":\"Slow synthetic report\"}"}}]}`))
		case <-r.Context().Done():
		}
	}))
	defer server.Close()
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, server.URL)
	report, err := svc.Generate(userID, GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"})
	if err != nil || report == nil || report.Status != "completed" {
		t.Fatalf("healthy slow report did not complete: %v", err)
	}
	if newSafeOutboundHTTPClient(false).Timeout != 10*time.Second {
		t.Error("AI change must not increase the timeout of other outbound integrations")
	}
}

func TestAIReportTruncationPersistsFailureAndAllowsExplicitRetry(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(`{"choices":[{"finish_reason":"length","message":{"content":"partial explanation"}}]}`)), Header: make(http.Header)}, nil
	})}
	req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
	failed, err := svc.Generate(userID, req)
	if err == nil || failed == nil || failed.Status != "failed" {
		t.Fatal("incomplete output became a successful report")
	}
	stored, err := svc.Get(failed.ID, userID)
	if err != nil || stored.Status != "failed" || stored.ErrorMessage == "" || stored.ContentJSON != "" {
		t.Fatalf("failed state was not persisted: %v", err)
	}
	svc.client.httpClient.Transport = aiContractTransport(func(r *http.Request) (*http.Response, error) {
		return aiContractResponse(`{"summary":"Complete report"}`), nil
	})
	completed, err := svc.Generate(userID, req)
	if err != nil || completed.Status != "completed" || completed.ID == failed.ID {
		t.Fatalf("explicit retry reused failed output: %v", err)
	}
}

func TestAIClientStillHonorsCallerDeadline(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-r.Context().Done():
		case <-time.After(500 * time.Millisecond):
		}
	}))
	defer server.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	client := NewOpenAICompatibleClient(nil, true)
	if _, err := client.GenerateReport(ctx, server.URL, "", "fixture", "{}", "weekly"); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("caller deadline was ignored: %v", err)
	}
}

func TestAIReportTimeoutHasSafeActionableFailureAndCanBeRetried(t *testing.T) {
	for _, tc := range []struct {
		name  string
		cause error
	}{
		{"context", context.DeadlineExceeded},
		{"network", &net.DNSError{Err: "synthetic-private-value", Name: "example.invalid", IsTimeout: true}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			svc, providers, userID := newAIReportTestServices(t)
			seedAIReportFacts(t, providers, userID, "https://example.com")
			calls := 0
			svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) {
				calls++
				return nil, &url.Error{Op: "Post", URL: "https://example.invalid/v1?api_key=synthetic-private-value", Err: tc.cause}
			})}
			req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
			failed, err := svc.Generate(userID, req)
			if err == nil || failed == nil || failed.Status != "failed" || calls != 1 {
				t.Fatal("timeout must persist one failed attempt without automatically retrying")
			}
			if !strings.Contains(failed.ErrorMessage, "超时") || strings.Contains(failed.ErrorMessage, "example.invalid") ||
				strings.Contains(failed.ErrorMessage, "synthetic-private-value") {
				t.Fatal("timeout feedback is not actionable or exposes transport details")
			}
			svc.client.httpClient.Transport = aiContractTransport(func(r *http.Request) (*http.Response, error) {
				calls++
				return aiContractResponse(`{"summary":"合成重试报告"}`), nil
			})
			completed, err := svc.Generate(userID, req)
			if err != nil || completed.Status != "completed" || completed.ID == failed.ID || calls != 2 {
				t.Fatal("explicit retry did not create a new completed report")
			}
		})
	}
}
