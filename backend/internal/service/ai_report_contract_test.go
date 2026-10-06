package service

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/sky/personal-ledger/internal/repository"
)

type aiContractTransport func(*http.Request) (*http.Response, error)

func (f aiContractTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func aiContractResponse(content string) *http.Response {
	data, _ := json.Marshal(map[string]any{"choices": []any{map[string]any{"message": map[string]string{"content": content}}}})
	return &http.Response{StatusCode: http.StatusOK, Body: io.NopCloser(strings.NewReader(string(data))), Header: make(http.Header)}
}

func TestAIReportTypesProduceDistinctTasksAndBoundOutput(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	seen := make(map[string]bool)
	svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) {
		var payload map[string]any
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			t.Fatal(err)
		}
		messages := payload["messages"].([]any)
		system := messages[0].(map[string]any)["content"].(string)
		if seen[system] {
			t.Error("different report types sent the same task")
		}
		seen[system] = true
		if payload["max_tokens"] != float64(4096) {
			t.Errorf("output token bound = %v, want 4096", payload["max_tokens"])
		}
		return aiContractResponse(`{"summary":"Valid synthetic report"}`), nil
	})}
	for _, kind := range []string{"weekly", "family", "budget", "anomaly"} {
		if _, err := svc.Generate(userID, GenerateAIReportRequest{ReportType: kind, PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}); err != nil {
			t.Fatal(err)
		}
	}
	if len(seen) != 4 {
		t.Errorf("distinct task count=%d, want 4", len(seen))
	}
}

func TestAIReportInvalidStructuredContentNeverCompletesOrCaches(t *testing.T) {
	for _, content := range []string{"null", "[]", "{}", `"not a report"`, `{"summary":123}`, `{"summary":" "}`, `{"summary":"Valid","risks":["wrong type"]}`,
		`{"summary":"Valid","title":null}`, `{"summary":"Valid","highlights":null}`,
		`{"summary":"Valid","highlights":[null]}`, `{"summary":"Valid","suggestions":null}`,
		`{"summary":"Valid","suggestions":[null]}`, `{"summary":"Valid","risks":null}`,
		`{"summary":"Valid","Highlights":[null]}`, `{"summary":"Valid","title":"ok","TITLE":null}`,
		`{"summary":"Valid","risks":[{"level":"low","title":"ok","detail":"fine","DETAIL":null}]}`} {
		t.Run(content, func(t *testing.T) {
			svc, providers, userID := newAIReportTestServices(t)
			seedAIReportFacts(t, providers, userID, "https://example.com")
			calls := 0
			svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) { calls++; return aiContractResponse(content), nil })}
			req := GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"}
			for i := 0; i < 2; i++ {
				report, err := svc.Generate(userID, req)
				if err == nil || report == nil || report.Status != "failed" {
					t.Fatalf("invalid content became reusable success; error=%v", err)
				}
			}
			if calls != 2 {
				t.Errorf("invalid result was cached: calls=%d", calls)
			}
		})
	}
}

func TestAIReportPlainTextAndFencedJSONRemainCompatible(t *testing.T) {
	for _, content := range []string{"Useful plain text financial explanation.", "```json\n{\"summary\":\"Useful structured explanation\"}\n```"} {
		t.Run(content, func(t *testing.T) {
			svc, providers, userID := newAIReportTestServices(t)
			seedAIReportFacts(t, providers, userID, "https://example.com")
			svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) { return aiContractResponse(content), nil })}
			report, err := svc.Generate(userID, GenerateAIReportRequest{ReportType: "weekly", PeriodStart: "2026-05-18", PeriodEnd: "2026-05-24"})
			if err != nil {
				t.Fatal(err)
			}
			var parsed struct {
				Summary string `json:"summary"`
			}
			if err := json.Unmarshal([]byte(report.ContentJSON), &parsed); err != nil || strings.TrimSpace(parsed.Summary) == "" || strings.Contains(parsed.Summary, "```") {
				t.Fatalf("compatible content was not normalized: %s, %v", report.ContentJSON, err)
			}
		})
	}
}

func TestAIReportGenerationHasUserFrequencyLimit(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	calls := 0
	svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) {
		calls++
		return aiContractResponse(`{"summary":"Valid synthetic report"}`), nil
	})}
	for i := 0; i < 7; i++ {
		day := time.Date(2026, 5, 1+i, 0, 0, 0, 0, time.Local).Format("2006-01-02")
		_, err := svc.Generate(userID, GenerateAIReportRequest{ReportType: "weekly", PeriodStart: day, PeriodEnd: day})
		if i < 6 && err != nil {
			t.Fatal(err)
		}
		if i == 6 && err == nil {
			t.Error("seventh provider attempt in a minute was not limited")
		}
	}
	if calls != 6 {
		t.Errorf("provider calls=%d, want 6", calls)
	}
}

func TestAIReportCompletionPreservesUserDisableAndLatestRunRecord(t *testing.T) {
	svc, providers, userID := newAIReportTestServices(t)
	seedAIReportFacts(t, providers, userID, "https://example.com")
	started, proceed, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var once sync.Once
	svc.client.httpClient = &http.Client{Transport: aiContractTransport(func(r *http.Request) (*http.Response, error) {
		once.Do(func() { close(started) })
		<-proceed
		return aiContractResponse(`{"summary":"Valid synthetic report"}`), nil
	})}
	repos := repository.NewRepositories(providers.repo.DB())
	scheduler := NewAIReportScheduler(svc, repos.System, repos.User)
	scheduler.now = func() time.Time { return time.Date(2026, 5, 30, 8, 0, 0, 0, time.Local) }
	if err := scheduler.SaveSettings(&AIReportScheduleSettings{Enabled: true, WeeklyEnabled: true, Hour: 8}); err != nil {
		t.Fatal(err)
	}
	go func() { scheduler.CheckAndGenerate(); close(finished) }()
	select {
	case <-started:
	case <-time.After(5 * time.Second):
		t.Fatal("provider never started")
	}
	changed, err := scheduler.GetSettings()
	if err != nil {
		t.Fatal(err)
	}
	changed.Enabled, changed.WeeklyEnabled, changed.Hour = false, false, 18
	if err := scheduler.SaveSettings(changed); err != nil {
		t.Fatal(err)
	}
	close(proceed)
	select {
	case <-finished:
	case <-time.After(5 * time.Second):
		t.Fatal("generation never finished")
	}
	current, err := scheduler.GetSettings()
	if err != nil {
		t.Fatal(err)
	}
	if current.Enabled || current.WeeklyEnabled || current.Hour != 18 || current.LastWeeklyRun != "2026-05-30" {
		t.Fatalf("completion overwrote user configuration or lost run record: %+v", current)
	}
	// A form read before generation must not erase a newer runtime record.
	changed.Hour = 19
	changed.LastWeeklyRun = ""
	if err := scheduler.SaveSettings(changed); err != nil {
		t.Fatal(err)
	}
	current, err = scheduler.GetSettings()
	if err != nil || current.Hour != 19 || current.LastWeeklyRun != "2026-05-30" {
		t.Fatalf("stale user form reset runtime record: %+v %v", current, err)
	}
}
