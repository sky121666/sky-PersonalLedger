package service

import (
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestValidateOutboundURLSecureDefaults(t *testing.T) {
	for _, rawURL := range []string{
		"http://example.com/hook",
		"https://127.0.0.1/hook",
		"https://[::1]/hook",
		"https://169.254.169.254/latest/meta-data",
		"https://10.0.0.1/hook",
		"https://user:secret@example.com/hook",
		"file:///etc/passwd",
	} {
		if err := validateOutboundURL(rawURL, false); !errors.Is(err, ErrOutboundAddressNotAllowed) {
			t.Fatalf("validateOutboundURL(%q) error = %v, want ErrOutboundAddressNotAllowed", rawURL, err)
		}
	}

	for _, rawURL := range []string{
		"https://api.openai.com/v1",
		"https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=test",
	} {
		if err := validateOutboundURL(rawURL, false); err != nil {
			t.Fatalf("validateOutboundURL(%q) error = %v, want nil", rawURL, err)
		}
	}
}

func TestValidateOutboundURLPrivateNetworkOptIn(t *testing.T) {
	for _, rawURL := range []string{
		"http://localhost:11434",
		"http://127.0.0.1:8080/v1",
		"https://10.0.0.5/hook",
	} {
		if err := validateOutboundURL(rawURL, true); err != nil {
			t.Fatalf("validateOutboundURL(%q) error = %v, want nil", rawURL, err)
		}
	}
}

func TestBlockedOutboundIPRanges(t *testing.T) {
	for _, rawIP := range []string{
		"127.0.0.1",
		"10.0.0.1",
		"100.64.0.1",
		"169.254.169.254",
		"192.168.1.1",
		"198.18.0.1",
		"::1",
		"fc00::1",
		"fe80::1",
		"64:ff9b::a00:1",
	} {
		if !isBlockedOutboundIP(net.ParseIP(rawIP)) {
			t.Fatalf("IP %s should be blocked", rawIP)
		}
	}
	for _, rawIP := range []string{"1.1.1.1", "8.8.8.8", "2606:4700:4700::1111"} {
		if isBlockedOutboundIP(net.ParseIP(rawIP)) {
			t.Fatalf("IP %s should be allowed", rawIP)
		}
	}
}

func TestSafeOutboundHTTPClientBlocksLoopbackByDefault(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	_, err := newSafeOutboundHTTPClient(false).Get(server.URL)
	if !errors.Is(err, ErrOutboundAddressNotAllowed) {
		t.Fatalf("GET loopback error = %v, want ErrOutboundAddressNotAllowed", err)
	}
}

func TestSafeOutboundHTTPClientAllowsExplicitLoopbackOptIn(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()

	response, err := newSafeOutboundHTTPClient(true).Get(server.URL)
	if err != nil {
		t.Fatalf("GET opted-in loopback server: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("status = %d, want %d", response.StatusCode, http.StatusNoContent)
	}
}
