package middleware

import (
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

type setupStatusStub struct {
	initialized bool
	err         error
}

func (s setupStatusStub) IsInitialized() (bool, error) {
	return s.initialized, s.err
}

func TestRequireSetupAccess(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name        string
		checker     setupStatusStub
		configured  string
		provided    string
		remoteAddr  string
		wantStatus  int
		wantReached bool
	}{
		{
			name:        "allows direct loopback when token is not configured",
			remoteAddr:  "127.0.0.1:12345",
			wantStatus:  http.StatusNoContent,
			wantReached: true,
		},
		{
			name:       "rejects remote request when token is not configured",
			remoteAddr: "192.0.2.10:12345",
			wantStatus: http.StatusForbidden,
		},
		{
			name:        "accepts configured token from remote request",
			configured:  "a-long-random-setup-token",
			provided:    "a-long-random-setup-token",
			remoteAddr:  "192.0.2.10:12345",
			wantStatus:  http.StatusNoContent,
			wantReached: true,
		},
		{
			name:       "rejects wrong configured token even on loopback",
			configured: "a-long-random-setup-token",
			provided:   "wrong-token",
			remoteAddr: "127.0.0.1:12345",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:        "does not require setup token after initialization",
			checker:     setupStatusStub{initialized: true},
			configured:  "a-long-random-setup-token",
			remoteAddr:  "192.0.2.10:12345",
			wantStatus:  http.StatusNoContent,
			wantReached: true,
		},
		{
			name:       "fails closed when initialization status cannot be read",
			checker:    setupStatusStub{err: errors.New("database unavailable")},
			remoteAddr: "127.0.0.1:12345",
			wantStatus: http.StatusInternalServerError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			reached := false
			router := gin.New()
			router.POST("/setup", RequireSetupAccess(tt.checker, tt.configured), func(c *gin.Context) {
				reached = true
				c.Status(http.StatusNoContent)
			})

			request := httptest.NewRequest(http.MethodPost, "/setup", nil)
			request.RemoteAddr = tt.remoteAddr
			request.Header.Set("X-Forwarded-For", "127.0.0.1")
			if tt.provided != "" {
				request.Header.Set(setupTokenHeader, tt.provided)
			}
			responseRecorder := httptest.NewRecorder()

			router.ServeHTTP(responseRecorder, request)

			if responseRecorder.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d; body=%s", responseRecorder.Code, tt.wantStatus, responseRecorder.Body.String())
			}
			if reached != tt.wantReached {
				t.Fatalf("handler reached = %v, want %v", reached, tt.wantReached)
			}
		})
	}
}

func TestIsDirectLoopbackRequest(t *testing.T) {
	for _, remoteAddr := range []string{"127.0.0.1:8080", "[::1]:8080", "::1"} {
		if !isDirectLoopbackRequest(remoteAddr) {
			t.Fatalf("expected %q to be loopback", remoteAddr)
		}
	}
	for _, remoteAddr := range []string{"192.0.2.1:8080", "example.com:8080", ""} {
		if isDirectLoopbackRequest(remoteAddr) {
			t.Fatalf("expected %q not to be loopback", remoteAddr)
		}
	}
}
