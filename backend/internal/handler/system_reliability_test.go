package handler

import (
	"encoding/json"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
)

func TestEntryPathRejectsUnusablePathsWithoutReplacingSavedPath(t *testing.T) {
	db, err := database.Init(t.TempDir() + "/ledger.db")
	if err != nil {
		t.Fatal(err)
	}
	svc := service.NewSystemService(repository.NewRepositories(db).System)
	if err := svc.SetEntryPath("/saved"); err != nil {
		t.Fatal(err)
	}
	router := gin.New()
	router.PUT("/entry", NewSystemHandler(svc).SetEntryPath)
	for _, path := range []string{"/", "/api", "/api/v1", "/assets", "/assets/app.js", "/uploads", "/metrics", "/.well-known", "/favicon.ico", "/manifest.json", "/foo?x=1", "/foo#hash", "//host", "/foo//bar", "/foo/../bar", "/foo/./bar", "/foo%2fbar", "/%61pi", "/foo\\bar", "/foo bar"} {
		t.Run(path, func(t *testing.T) {
			payload, _ := json.Marshal(gin.H{"entry_path": path})
			req := httptest.NewRequest("PUT", "/entry", strings.NewReader(string(payload)))
			req.Header.Set("Content-Type", "application/json")
			response := httptest.NewRecorder()
			router.ServeHTTP(response, req)
			if response.Code != 400 {
				t.Errorf("status = %d, want 400", response.Code)
			}
			actual, err := svc.GetEntryPath()
			if err != nil || actual != "/saved" {
				t.Errorf("saved path = %q, err %v", actual, err)
			}
		})
	}
}

func TestGenerateEntryPathDraftPreservesSavedPathAndLegacyStillSaves(t *testing.T) {
	db, err := database.Init(t.TempDir() + "/ledger.db")
	if err != nil {
		t.Fatal(err)
	}
	svc := service.NewSystemService(repository.NewRepositories(db).System)
	if err := svc.SetEntryPath("/saved"); err != nil {
		t.Fatal(err)
	}
	router := gin.New()
	router.POST("/generate", NewSystemHandler(svc).GenerateEntryPath)
	for _, draft := range []bool{true, false} {
		url := "/generate"
		if draft {
			url += "?draft=true"
		}
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest("POST", url, nil))
		if response.Code != 200 {
			t.Fatalf("status = %d", response.Code)
		}
		var payload struct {
			Data struct {
				EntryPath string `json:"entry_path"`
			} `json:"data"`
		}
		if err := json.Unmarshal(response.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		actual, err := svc.GetEntryPath()
		if err != nil {
			t.Fatal(err)
		}
		if draft && actual != "/saved" {
			t.Errorf("draft replaced saved path with %q", actual)
		}
		if !draft && actual != payload.Data.EntryPath {
			t.Errorf("legacy generation did not persist path")
		}
	}
}
