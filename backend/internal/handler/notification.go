package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type NotificationHandler struct {
	service *service.NotificationService
}

func NewNotificationHandler(s *service.NotificationService) *NotificationHandler {
	return &NotificationHandler{service: s}
}

func (h *NotificationHandler) Get(c *gin.Context) {
	userID := middleware.GetUserID(c)

	setting, err := h.service.Get(userID)
	if err != nil {
		internalServerError(c, err, "failed to load notification settings")
		return
	}

	response.Success(c, setting)
}

func (h *NotificationHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.NotificationSettingRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	setting, err := h.service.Update(userID, req)
	if err != nil {
		internalServerError(c, err, "failed to update notification settings")
		return
	}

	response.Success(c, setting)
}

type TestWecomRequest struct {
	Webhook string `json:"webhook" binding:"required"`
}

func (h *NotificationHandler) TestWecom(c *gin.Context) {
	var req TestWecomRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	result := h.service.TestWecom(req.Webhook)
	response.Success(c, result)
}

type TestDingtalkRequest struct {
	Webhook string `json:"webhook" binding:"required"`
	Secret  string `json:"secret"`
}

func (h *NotificationHandler) TestDingtalk(c *gin.Context) {
	var req TestDingtalkRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	result := h.service.TestDingtalk(req.Webhook, req.Secret)
	response.Success(c, result)
}

type TestEmailRequest struct {
	SmtpHost     string `json:"smtp_host" binding:"required"`
	SmtpPort     int    `json:"smtp_port"`
	SmtpUser     string `json:"smtp_user" binding:"required"`
	SmtpPassword string `json:"smtp_password"`
	SmtpFrom     string `json:"smtp_from"`
	EmailTo      string `json:"email_to" binding:"required"`
}

func (h *NotificationHandler) TestEmail(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req TestEmailRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	// Get existing password if not provided
	password := req.SmtpPassword
	if password == "" {
		existing, err := h.service.Get(userID)
		if err != nil {
			internalServerError(c, err, "failed to load notification settings")
			return
		}
		if existing != nil {
			password = existing.SmtpPassword
		}
	}

	setting := &model.NotificationSetting{
		SmtpHost:     req.SmtpHost,
		SmtpPort:     req.SmtpPort,
		SmtpUser:     req.SmtpUser,
		SmtpPassword: password,
		SmtpFrom:     req.SmtpFrom,
		EmailTo:      req.EmailTo,
	}
	if setting.SmtpPort == 0 {
		setting.SmtpPort = 587
	}

	result := h.service.TestEmail(setting, userID)
	response.Success(c, result)
}

type TestWebhookRequest struct {
	URL    string `json:"url" binding:"required"`
	Secret string `json:"secret"`
}

func (h *NotificationHandler) TestWebhook(c *gin.Context) {
	var req TestWebhookRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	result := h.service.TestWebhook(req.URL, req.Secret)
	response.Success(c, result)
}
