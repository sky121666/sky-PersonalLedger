package handler

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type TagHandler struct {
	svc *service.TagService
}

func NewTagHandler(svc *service.TagService) *TagHandler {
	return &TagHandler{svc: svc}
}

func (h *TagHandler) Create(c *gin.Context) {
	userID := c.GetUint("userID")

	var req service.CreateTagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	tag, err := h.svc.Create(userID, req)
	if err != nil {
		if err == service.ErrTagExists {
			response.Error(c, http.StatusConflict, 40901, err.Error())
			return
		}
		internalServerError(c, err, "failed to create tag")
		return
	}

	response.Created(c, tag)
}

func (h *TagHandler) List(c *gin.Context) {
	userID := c.GetUint("userID")

	tags, err := h.svc.List(userID)
	if err != nil {
		internalServerError(c, err, "failed to list tags")
		return
	}

	response.Success(c, tags)
}

func (h *TagHandler) GetByID(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	tag, err := h.svc.GetByID(id, userID)
	if err != nil {
		response.NotFound(c, "tag not found")
		return
	}

	response.Success(c, tag)
}

func (h *TagHandler) Update(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var req service.CreateTagRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	tag, err := h.svc.Update(id, userID, req)
	if err != nil {
		if err == service.ErrTagNotFound {
			response.NotFound(c, "tag not found")
			return
		}
		if err == service.ErrTagExists {
			response.Error(c, http.StatusConflict, 40901, err.Error())
			return
		}
		internalServerError(c, err, "failed to update tag")
		return
	}

	response.Success(c, tag)
}

func (h *TagHandler) Delete(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	if err := h.svc.Delete(id, userID); err != nil {
		if err == service.ErrTagNotFound {
			response.NotFound(c, "tag not found")
			return
		}
		internalServerError(c, err, "failed to delete tag")
		return
	}

	response.Success(c, nil)
}
