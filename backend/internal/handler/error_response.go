package handler

import (
	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/pkg/response"
)

func internalServerError(c *gin.Context, err error, message string) {
	_ = c.Error(err)
	response.InternalError(c, message)
}
