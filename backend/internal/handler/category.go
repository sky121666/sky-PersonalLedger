package handler

import (
	"github.com/sky/personal-ledger/internal/middleware"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"

	"github.com/gin-gonic/gin"
)

type CategoryHandler struct {
	service *service.CategoryService
}

func NewCategoryHandler(s *service.CategoryService) *CategoryHandler {
	return &CategoryHandler{service: s}
}

func (h *CategoryHandler) List(c *gin.Context) {
	userID := middleware.GetUserID(c)
	categoryType := c.Query("type")

	categories, err := h.service.List(userID, categoryType)
	if err != nil {
		internalServerError(c, err, "failed to list categories")
		return
	}

	response.Success(c, gin.H{"list": categories})
}

func (h *CategoryHandler) Create(c *gin.Context) {
	userID := middleware.GetUserID(c)

	var req service.CreateCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	category, err := h.service.Create(userID, req)
	if err != nil {
		internalServerError(c, err, "failed to create category")
		return
	}

	response.Created(c, category)
}

func (h *CategoryHandler) GetByID(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	category, err := h.service.GetByID(id, userID)
	if err != nil {
		response.NotFound(c, "category not found")
		return
	}

	response.Success(c, category)
}

func (h *CategoryHandler) Update(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	var req service.UpdateCategoryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	category, err := h.service.Update(id, userID, req)
	if err != nil {
		response.NotFound(c, "category not found")
		return
	}

	response.Success(c, category)
}

func (h *CategoryHandler) Delete(c *gin.Context) {
	userID := middleware.GetUserID(c)
	id := c.Param("id")

	if err := h.service.Delete(id, userID); err != nil {
		response.NotFound(c, "category not found")
		return
	}

	response.Success(c, nil)
}
