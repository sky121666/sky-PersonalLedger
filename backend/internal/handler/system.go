package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type SystemHandler struct {
	service *service.SystemService
}

func NewSystemHandler(s *service.SystemService) *SystemHandler {
	return &SystemHandler{service: s}
}

// GetEntryPath returns the current security entry path
func (h *SystemHandler) GetEntryPath(c *gin.Context) {
	path, err := h.service.GetEntryPath()
	if err != nil {
		internalServerError(c, err, "failed to load entry path")
		return
	}
	response.Success(c, gin.H{
		"entry_path": path,
		"enabled":    path != "",
	})
}

type SetEntryPathRequest struct {
	EntryPath string `json:"entry_path"`
}

// SetEntryPath sets the security entry path
func (h *SystemHandler) SetEntryPath(c *gin.Context) {
	var req SetEntryPathRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "invalid request")
		return
	}

	if err := h.service.SetEntryPath(req.EntryPath); err != nil {
		internalServerError(c, err, "failed to update entry path")
		return
	}

	path, err := h.service.GetEntryPath()
	if err != nil {
		internalServerError(c, err, "failed to load entry path")
		return
	}
	response.Success(c, gin.H{
		"entry_path": path,
		"enabled":    path != "",
		"message":    "entry path updated",
	})
}

// GenerateEntryPath generates a random entry path
func (h *SystemHandler) GenerateEntryPath(c *gin.Context) {
	path, err := h.service.GenerateRandomPath()
	if err != nil {
		internalServerError(c, err, "failed to generate entry path")
		return
	}
	response.Success(c, gin.H{
		"entry_path": path,
		"enabled":    true,
		"message":    "random entry path generated",
	})
}

// DisableEntryPath disables the security entry path
func (h *SystemHandler) DisableEntryPath(c *gin.Context) {
	if err := h.service.DisableEntryPath(); err != nil {
		internalServerError(c, err, "failed to disable entry path")
		return
	}
	response.Success(c, gin.H{
		"entry_path": "",
		"enabled":    false,
		"message":    "entry path disabled",
	})
}
