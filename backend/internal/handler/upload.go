package handler

import (
	"errors"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type UploadHandler struct {
	uploadService *service.UploadService
	apiToken      *service.APITokenService
	authService   *service.AuthService
}

func NewUploadHandler(uploadService *service.UploadService, apiToken *service.APITokenService, authService *service.AuthService) *UploadHandler {
	return &UploadHandler{
		uploadService: uploadService,
		apiToken:      apiToken,
		authService:   authService,
	}
}

type UploadRequest struct {
	Category string `form:"category" binding:"required,oneof=transactions lendings reminders"`
	RefID    string `form:"ref_id" binding:"required"`
}

func (h *UploadHandler) UploadAvatar(c *gin.Context) {
	userID := middleware.GetUserID(c)

	file, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file is required")
		return
	}

	result, err := h.uploadService.Upload(userID, "avatars", "profile", file)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	response.Success(c, result)
}

func (h *UploadHandler) Upload(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req UploadRequest
	if err := c.ShouldBind(&req); err != nil {
		response.BadRequest(c, "category and ref_id are required")
		return
	}

	file, err := c.FormFile("file")
	if err != nil {
		response.BadRequest(c, "file is required")
		return
	}

	result, err := h.uploadService.Upload(userID, req.Category, req.RefID, file)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	response.Success(c, result)
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
		response.InternalError(c, err.Error())
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
		response.InternalError(c, err.Error())
		return
	}

	response.Success(c, gin.H{"files": files})
}

func (h *UploadHandler) Serve(c *gin.Context) {
	// Get the file path from URL parameter
	filePath := c.Param("filepath")
	if filePath == "" {
		response.BadRequest(c, "file path is required")
		return
	}

	fullPath := h.uploadService.GetFilePath(filePath)

	// Check if file exists
	c.File(fullPath)
}

func (h *UploadHandler) Download(c *gin.Context) {
	filePath := c.Query("path")
	if filePath == "" {
		response.BadRequest(c, "path is required")
		return
	}

	token := c.Query("token")
	if token == "" {
		authHeader := c.GetHeader("Authorization")
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			token = parts[1]
		}
	}
	if token == "" {
		response.Unauthorized(c, "missing authorization token")
		return
	}

	var userID uint
	if claims, err := h.authService.GetJWTManager().ValidateToken(token); err == nil {
		userID = claims.UserID
	} else {
		if h.apiToken == nil {
			response.Unauthorized(c, "invalid token")
			return
		}
		apiTokenUserID, apiErr := h.apiToken.ValidateToken(token)
		if apiErr != nil {
			response.Unauthorized(c, "invalid token")
			return
		}
		userID = apiTokenUserID
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
		response.InternalError(c, err.Error())
		return
	}
	filename := filepath.Base(filePath)

	setAttachmentHeader(c, filename)
	c.Header("Content-Type", "application/octet-stream")
	c.File(fullPath)
}

func (h *UploadHandler) ServeStatic(uploadPath string) gin.HandlerFunc {
	return func(c *gin.Context) {
		filePath := c.Param("filepath")
		fullPath := filepath.Join(uploadPath, filePath)
		c.File(fullPath)
	}
}
