package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/model"
	"github.com/sky/personal-ledger/internal/service"
	"gorm.io/gorm"
)

func r5ProfileRequest(h *AuthHandler, userID uint, avatar string) *httptest.ResponseRecorder {
	router := gin.New()
	router.PUT("/profile", func(c *gin.Context) {
		c.Set("userID", userID)
		h.UpdateProfile(c)
	})
	body, _ := json.Marshal(UpdateProfileRequest{Nickname: "Changed", Avatar: avatar})
	req := httptest.NewRequest(http.MethodPut, "/profile", strings.NewReader(string(body)))
	req.Header.Set("Content-Type", "application/json")
	result := httptest.NewRecorder()
	router.ServeHTTP(result, req)
	return result
}

func assertR5AvatarError(t *testing.T, result *httptest.ResponseRecorder, status, code int, message string) {
	t.Helper()
	var body struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	}
	if err := json.Unmarshal(result.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if result.Code != status || body.Code != code || !strings.Contains(body.Message, message) {
		t.Fatalf("avatar response: status=%d body=%s; want status=%d code=%d message containing %q", result.Code, result.Body.String(), status, code, message)
	}
}

func TestR5AvatarHandlersReturnClientErrors(t *testing.T) {
	for _, operation := range []string{"profile", "member_create", "member_update"} {
		for _, invalid := range []string{"missing", "foreign", "invalid_path"} {
			t.Run(operation+"/"+invalid, func(t *testing.T) {
				_, userID, repos := newFamilyMemberTestHandlerWithRepos(t)
				s := service.NewServices(repos, &config.Config{Storage: config.StorageConfig{UploadPath: t.TempDir()}})
				avatar := fmt.Sprintf("/uploads/%d/avatars/profile/missing.png", userID)
				if invalid == "foreign" {
					avatar = "/uploads/999/avatars/profile/avatar.png"
				}
				if invalid == "invalid_path" {
					avatar = fmt.Sprintf("/uploads/%d/avatars/profile/../avatar.png", userID)
				}
				var result *httptest.ResponseRecorder
				if operation == "profile" {
					result = r5ProfileRequest(NewAuthHandler(s.Auth, nil, nil, nil), userID, avatar)
					user, err := repos.User.GetByID(userID)
					if err != nil {
						t.Fatal(err)
					}
					if user.Avatar != "" || user.Nickname != "" {
						t.Fatal("rejected profile update changed display fields")
					}
				} else {
					method, path := http.MethodPost, "/family/members"
					if operation == "member_update" {
						member := &model.FamilyMember{UserID: userID, Name: "Existing", Avatar: "legacy-icon"}
						if err := repos.FamilyMember.Create(member); err != nil {
							t.Fatal(err)
						}
						method, path = http.MethodPut, "/family/members/"+member.ID
					}
					result = performFamilyMemberRequest(NewFamilyHandler(s.FamilyMember), userID, method, path, map[string]any{"name": "Changed", "avatar": avatar})
					members, err := repos.FamilyMember.GetByUserID(userID)
					if err != nil {
						t.Fatal(err)
					}
					if operation == "member_create" && len(members) != 0 {
						t.Fatal("rejected avatar created a member")
					}
					if operation == "member_update" && (len(members) != 1 || members[0].Avatar != "legacy-icon" || members[0].Name != "Existing") {
						t.Fatal("rejected avatar changed member")
					}
				}
				assertR5AvatarError(t, result, http.StatusBadRequest, 40000, "重新上传")
			})
		}
	}
}

func TestR5ProfileAvatarErrorMapping(t *testing.T) {
	for _, test := range []struct {
		name         string
		err          error
		status, code int
		message      string
	}{
		{"recovery_pending", fmt.Errorf("synthetic recovery: %w", service.ErrAttachmentRecoveryPending), http.StatusServiceUnavailable, 50302, "attachment recovery is pending"},
		{"unexpected_storage_error", errors.New("synthetic storage failure"), http.StatusInternalServerError, 50001, "failed to update profile"},
	} {
		t.Run(test.name, func(t *testing.T) {
			_, userID, repos := newFamilyMemberTestHandlerWithRepos(t)
			s := service.NewServices(repos, &config.Config{Storage: config.StorageConfig{UploadPath: t.TempDir()}})
			name := "r5:profile-service-error"
			if err := repos.User.DB().Callback().Query().Before("gorm:query").Register(name, func(query *gorm.DB) {
				if query.Statement.Table == "users" {
					query.AddError(test.err)
				}
			}); err != nil {
				t.Fatal(err)
			}
			defer repos.User.DB().Callback().Query().Remove(name)
			result := r5ProfileRequest(NewAuthHandler(s.Auth, nil, nil, nil), userID, "")
			assertR5AvatarError(t, result, test.status, test.code, test.message)
		})
	}
}

func TestR5FamilyAvatarRecoveryPending(t *testing.T) {
	result := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(result)
	writeFamilyMemberError(ctx, fmt.Errorf("synthetic recovery: %w", service.ErrAttachmentRecoveryPending))
	assertR5AvatarError(t, result, http.StatusServiceUnavailable, 50302, "attachment recovery is pending")
}
