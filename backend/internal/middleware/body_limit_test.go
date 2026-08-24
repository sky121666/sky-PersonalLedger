package middleware

import (
	"bytes"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestLimitJSONBodyRejectsContentLengthBeforeHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	called := false
	router := gin.New()
	router.Use(LimitRequestBody(16))
	router.POST("/json", func(c *gin.Context) {
		called = true
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodPost, "/json", strings.NewReader(`{"password":"this-is-too-long"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413; body=%s", response.Code, response.Body.String())
	}
	if called {
		t.Fatal("oversized request reached handler")
	}
}

func TestLimitJSONBodyRejectsChunkedBodyBeforeHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	called := false
	router := gin.New()
	router.Use(LimitRequestBody(16))
	router.POST("/json", func(c *gin.Context) {
		called = true
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodPost, "/json", io.NopCloser(strings.NewReader(`{"refresh_token":"this-is-too-long"}`)))
	request.ContentLength = -1
	request.TransferEncoding = []string{"chunked"}
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413; body=%s", response.Code, response.Body.String())
	}
	if called {
		t.Fatal("oversized chunked request reached handler")
	}
}

func TestLimitRequestBodyCannotBeBypassedWithNonJSONContentType(t *testing.T) {
	gin.SetMode(gin.TestMode)
	for _, contentType := range []string{"text/plain", ""} {
		t.Run(contentType, func(t *testing.T) {
			called := false
			router := gin.New()
			router.Use(LimitRequestBody(16))
			router.POST("/json", func(c *gin.Context) {
				called = true
				c.Status(http.StatusNoContent)
			})

			request := httptest.NewRequest(http.MethodPost, "/json", strings.NewReader(`{"password":"this-is-too-long"}`))
			if contentType != "" {
				request.Header.Set("Content-Type", contentType)
			}
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)

			if response.Code != http.StatusRequestEntityTooLarge {
				t.Fatalf("status = %d, want 413; body=%s", response.Code, response.Body.String())
			}
			if called {
				t.Fatal("oversized request reached handler")
			}
		})
	}
}

func TestLimitJSONBodyRestoresAllowedBodyAndLeavesMultipartAlone(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(LimitRequestBody(64, "/body"))
	router.POST("/body", func(c *gin.Context) {
		body, err := io.ReadAll(c.Request.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		c.String(http.StatusOK, string(body))
	})

	for _, test := range []struct {
		name        string
		contentType string
		body        string
	}{
		{name: "json", contentType: "application/json; charset=utf-8", body: `{"ok":true}`},
		{name: "structured json", contentType: "application/problem+json", body: `{"ok":true}`},
		{name: "text plain", contentType: "text/plain", body: `{"ok":true}`},
		{name: "missing content type", contentType: "", body: `{"ok":true}`},
		{name: "multipart bypass", contentType: "multipart/form-data; boundary=test", body: strings.Repeat("x", 128)},
	} {
		t.Run(test.name, func(t *testing.T) {
			request := httptest.NewRequest(http.MethodPost, "/body", bytes.NewBufferString(test.body))
			request.Header.Set("Content-Type", test.contentType)
			response := httptest.NewRecorder()
			router.ServeHTTP(response, request)
			if response.Code != http.StatusOK || response.Body.String() != test.body {
				t.Fatalf("status/body = %d/%q, want 200/%q", response.Code, response.Body.String(), test.body)
			}
		})
	}
}

func TestLimitRequestBodyDoesNotExemptMultipartOnOrdinaryRoute(t *testing.T) {
	gin.SetMode(gin.TestMode)
	called := false
	router := gin.New()
	router.Use(LimitRequestBody(16, "/upload"))
	router.POST("/json", func(c *gin.Context) {
		called = true
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodPost, "/json", strings.NewReader(strings.Repeat("x", 32)))
	request.Header.Set("Content-Type", "multipart/form-data; boundary=test")
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("status = %d, want 413; body=%s", response.Code, response.Body.String())
	}
	if called {
		t.Fatal("multipart content type bypassed ordinary route body limit")
	}
}
