package middleware

import (
	"bytes"
	"errors"
	"io"
	"mime"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/pkg/response"
)

const requestBodyTooLargeCode = 41300

// LimitRequestBody bounds ordinary requests before Gin binds them. Multipart
// imports, uploads, and restores keep their larger route-specific limits.
// The limit intentionally does not trust Content-Type because ShouldBindJSON
// parses JSON even when clients send text/plain or no media type.
func LimitRequestBody(maxBytes int64, multipartExemptPaths ...string) gin.HandlerFunc {
	multipartExemptions := make(map[string]struct{}, len(multipartExemptPaths))
	for _, path := range multipartExemptPaths {
		multipartExemptions[path] = struct{}{}
	}
	return func(c *gin.Context) {
		if maxBytes <= 0 || requestHasNoBody(c.Request) || isDedicatedMultipartRequest(c.Request, multipartExemptions) {
			c.Next()
			return
		}

		if c.Request.ContentLength > maxBytes {
			respondRequestBodyTooLarge(c)
			return
		}

		limited := io.LimitReader(c.Request.Body, maxBytes+1)
		body, err := io.ReadAll(limited)
		if err != nil {
			if errors.Is(err, http.ErrBodyReadAfterClose) {
				response.BadRequest(c, "invalid request body")
			} else {
				response.BadRequest(c, "failed to read request body")
			}
			c.Abort()
			return
		}
		if int64(len(body)) > maxBytes {
			respondRequestBodyTooLarge(c)
			return
		}

		_ = c.Request.Body.Close()
		c.Request.Body = io.NopCloser(bytes.NewReader(body))
		c.Request.ContentLength = int64(len(body))
		c.Next()
	}
}

func isDedicatedMultipartRequest(request *http.Request, exemptPaths map[string]struct{}) bool {
	if request == nil || request.Method != http.MethodPost || !isMultipartMediaType(request.Header.Get("Content-Type")) {
		return false
	}
	_, exempt := exemptPaths[request.URL.Path]
	return exempt
}

func isMultipartMediaType(value string) bool {
	mediaType, _, err := mime.ParseMediaType(strings.TrimSpace(value))
	if err != nil {
		return false
	}
	return strings.EqualFold(mediaType, "multipart/form-data")
}

func requestHasNoBody(request *http.Request) bool {
	return request == nil || request.Body == nil || request.Body == http.NoBody
}

func respondRequestBodyTooLarge(c *gin.Context) {
	response.Error(c, http.StatusRequestEntityTooLarge, requestBodyTooLargeCode, "request body exceeds configured limit")
	c.Abort()
}
