package handler

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type UploadHandler struct {
	uploadService *service.UploadService
}

func NewUploadHandler(uploadService *service.UploadService, apiToken *service.APITokenService, authService *service.AuthService) *UploadHandler {
	return &UploadHandler{
		uploadService: uploadService,
	}
}

type UploadRequest struct {
	Category string `form:"category" binding:"required,oneof=transactions lendings reminders"`
	RefID    string `form:"ref_id" binding:"required"`
}

func (h *UploadHandler) UploadAvatar(c *gin.Context) {
	userID := middleware.GetUserID(c)
	h.limitMultipartBody(c)

	file, err := c.FormFile("file")
	if err != nil {
		if isMultipartBodyTooLarge(err) {
			response.Error(c, http.StatusRequestEntityTooLarge, 41300, "file size exceeds configured limit")
			return
		}
		response.BadRequest(c, "file is required")
		return
	}

	result, err := h.uploadService.Upload(userID, "avatars", "profile", file)
	if err != nil {
		h.respondUploadError(c, err)
		return
	}

	response.Success(c, result)
}

func (h *UploadHandler) Upload(c *gin.Context) {
	userID := middleware.GetUserID(c)
	h.limitMultipartBody(c)

	var req UploadRequest
	if err := c.ShouldBind(&req); err != nil {
		if isMultipartBodyTooLarge(err) {
			response.Error(c, http.StatusRequestEntityTooLarge, 41300, "file size exceeds configured limit")
			return
		}
		response.BadRequest(c, "category and ref_id are required")
		return
	}

	file, err := c.FormFile("file")
	if err != nil {
		if isMultipartBodyTooLarge(err) {
			response.Error(c, http.StatusRequestEntityTooLarge, 41300, "file size exceeds configured limit")
			return
		}
		response.BadRequest(c, "file is required")
		return
	}

	result, err := h.uploadService.Upload(userID, req.Category, req.RefID, file)
	if err != nil {
		h.respondUploadError(c, err)
		return
	}

	response.Success(c, result)
}

func (h *UploadHandler) respondUploadError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrUploadFileTooLarge):
		response.Error(c, http.StatusRequestEntityTooLarge, 41300, err.Error())
	case errors.Is(err, service.ErrUploadTypeNotAllowed):
		response.Error(c, http.StatusUnsupportedMediaType, 41500, "file type is not allowed")
	case errors.Is(err, service.ErrUploadContentMismatch):
		response.Error(c, http.StatusUnsupportedMediaType, 41501, "file content does not match its type")
	case errors.Is(err, service.ErrUploadScopeInvalid):
		response.BadRequest(c, "invalid upload scope")
	default:
		internalServerError(c, err, "failed to store uploaded file")
	}
}

func (h *UploadHandler) limitMultipartBody(c *gin.Context) {
	maxFileSize := h.uploadService.MaxFileSizeBytes()
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxFileSize+(1<<20))
}

func isMultipartBodyTooLarge(err error) bool {
	var maxBytesErr *http.MaxBytesError
	return errors.As(err, &maxBytesErr)
}

func (h *UploadHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	path := c.Query("path")
	if path == "" {
		response.BadRequest(c, "path is required")
		return
	}

	if err := h.uploadService.Delete(userID, path); err != nil {
		if errors.Is(err, service.ErrUploadPathInvalid) {
			response.BadRequest(c, "invalid file path")
			return
		}
		if errors.Is(err, service.ErrUploadPathForbidden) {
			response.Forbidden(c, "file path does not belong to current user")
			return
		}
		if errors.Is(err, service.ErrUploadReferenced) {
			response.Error(c, http.StatusConflict, 40901, "file is still referenced")
			return
		}
		if errors.Is(err, os.ErrNotExist) {
			response.NotFound(c, "file not found")
			return
		}
		internalServerError(c, err, "failed to delete uploaded file")
		return
	}

	response.Success(c, gin.H{"message": "file deleted"})
}

func (h *UploadHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	category := c.Query("category")
	refID := c.Query("ref_id")

	if category == "" || refID == "" {
		response.BadRequest(c, "category and ref_id are required")
		return
	}

	files, err := h.uploadService.ListFiles(userID, category, refID)
	if err != nil {
		if errors.Is(err, service.ErrUploadScopeInvalid) {
			response.BadRequest(c, "invalid upload scope")
			return
		}
		internalServerError(c, err, "failed to list uploaded files")
		return
	}

	response.Success(c, gin.H{"files": files})
}

func (h *UploadHandler) Download(c *gin.Context) {
	filePath := c.Query("path")
	if filePath == "" {
		response.BadRequest(c, "path is required")
		return
	}

	userID := middleware.GetUserID(c)
	if userID == 0 {
		response.Unauthorized(c, "unauthorized")
		return
	}

	fullPath, err := h.uploadService.GetUserFilePath(userID, filePath)
	if err != nil {
		if errors.Is(err, service.ErrUploadPathInvalid) {
			response.BadRequest(c, "invalid file path")
			return
		}
		if errors.Is(err, service.ErrUploadPathForbidden) {
			response.Forbidden(c, "file path does not belong to current user")
			return
		}
		if errors.Is(err, os.ErrNotExist) {
			response.NotFound(c, "file not found")
			return
		}
		internalServerError(c, err, "failed to resolve uploaded file")
		return
	}
	filename := filepath.Base(filePath)

	setAttachmentHeader(c, filename)
	c.Header("Content-Type", "application/octet-stream")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Header("Cache-Control", "private, no-store")
	c.File(fullPath)
}
