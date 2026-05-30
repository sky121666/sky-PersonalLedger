package handler

import (
	"mime"
	"path/filepath"
	"strings"
	"unicode"

	"github.com/gin-gonic/gin"
)

func setAttachmentHeader(c *gin.Context, filename string) {
	disposition := mime.FormatMediaType("attachment", map[string]string{
		"filename": safeAttachmentFilename(filename),
	})
	if disposition == "" {
		disposition = `attachment; filename="download"`
	}
	c.Header("Content-Disposition", disposition)
}

func safeAttachmentFilename(filename string) string {
	normalized := strings.ReplaceAll(strings.TrimSpace(filename), "\\", "/")
	base := filepath.Base(normalized)
	if base == "." || base == string(filepath.Separator) {
		base = "download"
	}

	base = strings.Map(func(r rune) rune {
		if r == '/' || r == '\\' || unicode.IsControl(r) {
			return '_'
		}
		return r
	}, base)
	base = strings.TrimSpace(base)
	if base == "" {
		return "download"
	}
	return base
}
