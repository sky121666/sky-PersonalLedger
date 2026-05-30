package handler

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestSetAttachmentHeaderSanitizesUnsafeFilename(t *testing.T) {
	gin.SetMode(gin.TestMode)
	response := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(response)

	setAttachmentHeader(c, "reports/\r\nX-Injected: yes\\summary\".csv")

	header := response.Header().Get("Content-Disposition")
	if strings.ContainsAny(header, "\r\n") {
		t.Fatalf("content disposition contains line break: %q", header)
	}
	if strings.Contains(header, "X-Injected") {
		t.Fatalf("content disposition contains injected header text: %q", header)
	}
	if !strings.HasPrefix(header, "attachment;") {
		t.Fatalf("content disposition = %q, want attachment", header)
	}
	if !strings.Contains(header, "filename=") {
		t.Fatalf("content disposition = %q, want filename parameter", header)
	}
}
