package observability

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestMetricsRequireTokenAndUseRouteTemplates(t *testing.T) {
	gin.SetMode(gin.TestMode)
	registry := NewRegistry(nil)
	router := gin.New()
	router.Use(registry.Middleware())
	router.GET("/items/:id", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	router.GET("/metrics", registry.Handler("metrics-secret-at-least-32-characters"))

	request := httptest.NewRequest(http.MethodGet, "/items/private-id?token=secret-query", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusNoContent {
		t.Fatalf("item status = %d", response.Code)
	}

	unauthorized := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	unauthorizedResponse := httptest.NewRecorder()
	router.ServeHTTP(unauthorizedResponse, unauthorized)
	if unauthorizedResponse.Code != http.StatusUnauthorized || unauthorizedResponse.Header().Get("WWW-Authenticate") != "Bearer" {
		t.Fatalf("unauthorized metrics = %d headers=%v", unauthorizedResponse.Code, unauthorizedResponse.Header())
	}

	authorized := httptest.NewRequest(http.MethodGet, "/metrics", nil)
	authorized.Header.Set("Authorization", "Bearer metrics-secret-at-least-32-characters")
	authorizedResponse := httptest.NewRecorder()
	router.ServeHTTP(authorizedResponse, authorized)
	if authorizedResponse.Code != http.StatusOK {
		t.Fatalf("metrics status = %d body=%s", authorizedResponse.Code, authorizedResponse.Body.String())
	}
	body := authorizedResponse.Body.String()
	for _, required := range []string{
		`ledger_http_requests_total{method="GET",route="/items/:id",status="204"} 1`,
		"ledger_http_request_duration_seconds_bucket",
		"ledger_http_requests_in_flight",
		"ledger_process_uptime_seconds",
		"ledger_go_goroutines",
		"ledger_go_memory_alloc_bytes",
	} {
		if !strings.Contains(body, required) {
			t.Fatalf("metrics missing %q:\n%s", required, body)
		}
	}
	for _, forbidden := range []string{"private-id", "secret-query", "metrics-secret"} {
		if strings.Contains(body, forbidden) {
			t.Fatalf("metrics leaked %q:\n%s", forbidden, body)
		}
	}
}

func TestRequestLabelsUsePrometheusEscapingExactlyOnce(t *testing.T) {
	labels := requestLabels(requestKey{
		method: "GE\\T",
		route:  "/items/\"quoted\"\nnext",
		status: http.StatusOK,
	})
	want := `method="GE\\T",route="/items/\"quoted\"\nnext",status="200"`
	if labels != want {
		t.Fatalf("labels = %q, want %q", labels, want)
	}
}

func TestObserveBoundsUnknownHTTPMethods(t *testing.T) {
	registry := NewRegistry(nil)
	registry.observe("ATTACKER-METHOD-ONE", "unmatched", http.StatusNotFound, 0)
	registry.observe("ATTACKER-METHOD-TWO", "unmatched", http.StatusNotFound, 0)

	registry.mu.RLock()
	defer registry.mu.RUnlock()
	if len(registry.requests) != 1 {
		t.Fatalf("unknown methods created %d metric series, want 1", len(registry.requests))
	}
	key := requestKey{method: "OTHER", route: "unmatched", status: http.StatusNotFound}
	if registry.requests[key].count != 2 {
		t.Fatalf("bounded unknown method count = %d, want 2", registry.requests[key].count)
	}
}
