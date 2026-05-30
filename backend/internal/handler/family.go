package handler

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/response"
)

type FamilyHandler struct {
	memberService *service.FamilyMemberService
}

func NewFamilyHandler(memberService *service.FamilyMemberService) *FamilyHandler {
	return &FamilyHandler{memberService: memberService}
}

func (h *FamilyHandler) ListMembers(c *gin.Context) {
	userID := c.GetUint("userID")

	members, err := h.memberService.List(userID)
	if err != nil {
		response.InternalError(c, err.Error())
		return
	}
	response.Success(c, members)
}

func (h *FamilyHandler) CreateMember(c *gin.Context) {
	userID := c.GetUint("userID")

	var req service.CreateFamilyMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	member, err := h.memberService.Create(userID, req)
	if err != nil {
		writeFamilyMemberError(c, err)
		return
	}
	response.Created(c, member)
}

func (h *FamilyHandler) UpdateMember(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	var req service.UpdateFamilyMemberRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	member, err := h.memberService.Update(id, userID, req)
	if err != nil {
		writeFamilyMemberError(c, err)
		return
	}
	response.Success(c, member)
}

func (h *FamilyHandler) DeleteMember(c *gin.Context) {
	userID := c.GetUint("userID")
	id := c.Param("id")

	if err := h.memberService.Delete(id, userID); err != nil {
		writeFamilyMemberError(c, err)
		return
	}
	response.Success(c, nil)
}

func (h *FamilyHandler) Summary(c *gin.Context) {
	userID := c.GetUint("userID")
	month := c.Query("month")

	summary, err := h.memberService.Summary(userID, month)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	response.Success(c, summary)
}

func (h *FamilyHandler) Statistics(c *gin.Context) {
	userID := c.GetUint("userID")
	month := c.Query("month")

	statistics, err := h.memberService.Statistics(userID, month)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}
	response.Success(c, statistics)
}

func writeFamilyMemberError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, service.ErrFamilyMemberNotFound):
		response.NotFound(c, err.Error())
	case errors.Is(err, service.ErrFamilyMemberNameEmpty):
		response.BadRequest(c, err.Error())
	default:
		response.Error(c, http.StatusInternalServerError, 50001, err.Error())
	}
}
