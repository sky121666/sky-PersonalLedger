package main

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sky/personal-ledger/internal/config"
	"github.com/sky/personal-ledger/internal/database"
	"github.com/sky/personal-ledger/internal/repository"
	"github.com/sky/personal-ledger/internal/service"
	"github.com/sky/personal-ledger/pkg/jwt"
)

func TestValidateJWTSecretRejectsPublicPlaceholders(t *testing.T) {
	for _, secret := range []string{
		"",
		"change-this-secret",
		"change-this-to-a-random-secret-key",
		"please-change-this-to-a-random-secret-key",
		"your-secret-key-change-in-production",
		"your-jwt-secret-change-this-in-production",
	} {
		t.Run(secret, func(t *testing.T) {
			err := validateJWTSecret(secret)
			if err == nil {
				t.Fatal("expected placeholder JWT secret to be rejected")
			}
			if !strings.Contains(err.Error(), "LEDGER_JWT_SECRET") {
				t.Fatalf("error = %q, want LEDGER_JWT_SECRET guidance", err.Error())
			}
		})
	}
}

func TestValidateJWTSecretAcceptsStrongSecret(t *testing.T) {
	if err := validateJWTSecret("ledger-secret-with-at-least-32-characters"); err != nil {
		t.Fatalf("validate strong secret: %v", err)
	}
}

func TestValidateCredentialEncryptionKeys(t *testing.T) {
	if err := validateCredentialEncryption(config.CredentialConfig{}); err != nil {
		t.Fatalf("legacy fallback configuration should remain valid: %v", err)
	}
	if err := validateCredentialEncryption(config.CredentialConfig{
		EncryptionKey:         "active-credential-key-with-at-least-32-characters",
		EncryptionPreviousKey: "previous-credential-key-with-at-least-32-characters",
	}); err != nil {
		t.Fatalf("strong credential encryption keys rejected: %v", err)
	}
	for _, credentials := range []config.CredentialConfig{
		{EncryptionKey: "short"},
		{EncryptionPreviousKey: "short"},
	} {
		if err := validateCredentialEncryption(credentials); err == nil {
			t.Fatalf("short credential encryption key accepted: %#v", credentials)
		}
	}
}

func TestValidateSetupToken(t *testing.T) {
	if err := validateSetupToken(""); err != nil {
		t.Fatalf("empty setup token should keep loopback-only setup available: %v", err)
	}
	if err := validateSetupToken("short-token"); err == nil {
		t.Fatal("expected short configured setup token to be rejected")
	}
	if err := validateSetupToken("setup-token-with-at-least-32-characters"); err != nil {
		t.Fatalf("long setup token should be accepted: %v", err)
	}
}

func TestValidateStorageLimits(t *testing.T) {
	valid := config.StorageConfig{MaxFileSize: 10, RestoreMaxFileSize: 64}
	if err := validateStorageLimits(valid); err != nil {
		t.Fatalf("validate storage defaults: %v", err)
	}
	for _, invalid := range []config.StorageConfig{
		{MaxFileSize: 0, RestoreMaxFileSize: 64},
		{MaxFileSize: 10, RestoreMaxFileSize: 0},
		{MaxFileSize: 1025, RestoreMaxFileSize: 64},
		{MaxFileSize: 10, RestoreMaxFileSize: 4097},
	} {
		if err := validateStorageLimits(invalid); err == nil {
			t.Fatalf("expected invalid storage limits to be rejected: %#v", invalid)
		}
	}
}

func TestEnsureStorageDirectoriesCreatesPrivateWritablePaths(t *testing.T) {
	root := t.TempDir()
	uploads := filepath.Join(root, "nested", "uploads")
	backups := filepath.Join(root, "nested", "backups")
	if err := ensureStorageDirectories(config.StorageConfig{UploadPath: uploads, BackupPath: backups}); err != nil {
		t.Fatalf("ensure storage directories: %v", err)
	}
	for _, path := range []string{uploads, backups} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatalf("stat storage directory: %v", err)
		}
		if !info.IsDir() || info.Mode().Perm() != 0700 {
			t.Fatalf("storage path %s mode = %v, want private directory", path, info.Mode())
		}
		probe, err := os.CreateTemp(path, ".probe-*")
		if err != nil {
			t.Fatalf("storage path is not writable: %v", err)
		}
		probe.Close()
		os.Remove(probe.Name())
	}
}

func TestEnsureStorageDirectoriesTightensExistingPaths(t *testing.T) {
	root := t.TempDir()
	uploads := filepath.Join(root, "uploads")
	backups := filepath.Join(root, "backups")
	for _, path := range []string{uploads, backups} {
		if err := os.Mkdir(path, 0755); err != nil {
			t.Fatalf("create existing storage directory: %v", err)
		}
		if err := os.Chmod(path, 0755); err != nil {
			t.Fatalf("set broad storage permissions: %v", err)
		}
		nested := filepath.Join(path, "legacy")
		if err := os.Mkdir(nested, 0755); err != nil {
			t.Fatalf("create broad nested storage directory: %v", err)
		}
		if err := os.Chmod(nested, 0755); err != nil {
			t.Fatalf("set broad nested storage permissions: %v", err)
		}
		file := filepath.Join(nested, "legacy.dat")
		if err := os.WriteFile(file, []byte("legacy"), 0644); err != nil {
			t.Fatalf("create broad legacy storage file: %v", err)
		}
		if err := os.Chmod(file, 0644); err != nil {
			t.Fatalf("set broad legacy file permissions: %v", err)
		}
	}

	if err := ensureStorageDirectories(config.StorageConfig{UploadPath: uploads, BackupPath: backups}); err != nil {
		t.Fatalf("secure existing storage directories: %v", err)
	}
	for _, path := range []string{uploads, backups} {
		info, err := os.Stat(path)
		if err != nil {
			t.Fatalf("stat storage directory: %v", err)
		}
		if got := info.Mode().Perm(); got != 0700 {
			t.Fatalf("storage path %s mode = %o, want 700", path, got)
		}
		nestedInfo, err := os.Stat(filepath.Join(path, "legacy"))
		if err != nil {
			t.Fatalf("stat nested storage directory: %v", err)
		}
		if nestedInfo.Mode().Perm() != 0700 {
			t.Fatalf("nested storage mode = %v, want 700", nestedInfo.Mode())
		}
		fileInfo, err := os.Stat(filepath.Join(path, "legacy", "legacy.dat"))
		if err != nil {
			t.Fatalf("stat legacy storage file: %v", err)
		}
		if fileInfo.Mode().Perm() != 0600 {
			t.Fatalf("legacy storage file mode = %v, want 600", fileInfo.Mode())
		}
	}
}

func TestEnsureStorageDirectoriesRejectsFilePath(t *testing.T) {
	path := filepath.Join(t.TempDir(), "not-a-directory")
	if err := os.WriteFile(path, []byte("file"), 0600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	if err := ensureStorageDirectories(config.StorageConfig{BackupPath: path}); err == nil {
		t.Fatal("file-backed storage path was accepted")
	}
}

func TestEnsureStorageDirectoriesRejectsSymlinkLeaf(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "target")
	if err := os.Mkdir(target, 0755); err != nil {
		t.Fatalf("create symlink target: %v", err)
	}
	link := filepath.Join(root, "uploads")
	if err := os.Symlink(target, link); err != nil {
		t.Skipf("symlinks are unavailable: %v", err)
	}
	if err := ensureStorageDirectories(config.StorageConfig{UploadPath: link}); err == nil {
		t.Fatal("symlink-backed upload path was accepted")
	}
	info, err := os.Stat(target)
	if err != nil {
		t.Fatalf("stat symlink target: %v", err)
	}
	if got := info.Mode().Perm(); got != 0755 {
		t.Fatalf("rejected symlink target mode = %o, want unchanged 755", got)
	}
}

func TestEnsureStorageDirectoriesRejectsRelativeSymlinkEscapeBeforeCreation(t *testing.T) {
	workingDirectory := t.TempDir()
	outside := t.TempDir()
	if err := os.Symlink(outside, filepath.Join(workingDirectory, "escape")); err != nil {
		t.Skipf("symlinks are unavailable: %v", err)
	}
	t.Chdir(workingDirectory)
	if err := ensureStorageDirectories(config.StorageConfig{BackupPath: filepath.Join("escape", "backups")}); err == nil {
		t.Fatal("relative storage path resolving outside the working directory was accepted")
	}
	if _, err := os.Stat(filepath.Join(outside, "backups")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("rejected storage path created content outside working directory: %v", err)
	}
}

func TestValidateStorageDirectoryPathRejectsParentTraversal(t *testing.T) {
	if _, err := validateStorageDirectoryPath(filepath.Join("..", "backups")); err == nil {
		t.Fatal("parent-traversing storage path was accepted")
	}
}

func TestValidateStorageDirectoryPathRejectsWorkingDirectory(t *testing.T) {
	if _, err := validateStorageDirectoryPath("."); err == nil {
		t.Fatal("working directory was accepted as a storage root")
	}
}

func TestValidateJSONBodyLimit(t *testing.T) {
	for _, valid := range []int64{1024, 1 << 20, 64 << 20} {
		if err := validateJSONBodyLimit(valid); err != nil {
			t.Fatalf("valid limit %d rejected: %v", valid, err)
		}
	}
	for _, invalid := range []int64{0, 1023, (64 << 20) + 1} {
		if err := validateJSONBodyLimit(invalid); err == nil {
			t.Fatalf("invalid limit %d accepted", invalid)
		}
	}
}

func TestRequestLoggerOmitsQueryValues(t *testing.T) {
	gin.SetMode(gin.TestMode)
	var output bytes.Buffer
	previousWriter := gin.DefaultWriter
	gin.DefaultWriter = &output
	t.Cleanup(func() { gin.DefaultWriter = previousWriter })

	router := gin.New()
	router.Use(newRequestLogger())
	router.GET("/probe", func(c *gin.Context) { c.Status(http.StatusNoContent) })
	router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/probe?token=super-secret", nil))

	logged := output.String()
	if strings.Contains(logged, "super-secret") || strings.Contains(logged, "token=") {
		t.Fatalf("request logger exposed query: %s", logged)
	}
	if !strings.Contains(logged, "/probe") {
		t.Fatalf("request logger omitted path: %s", logged)
	}

	output.Reset()
	router.GET("/error", func(c *gin.Context) {
		_ = c.Error(errors.New("test error"))
		c.Status(http.StatusInternalServerError)
	})
	router.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/error", nil))
	if logged := output.String(); !strings.HasSuffix(logged, "\n") {
		t.Fatalf("request logger output does not end with a newline: %q", logged)
	}
}

func TestValidateObservabilityRequiresStrongTokenWhenEnabled(t *testing.T) {
	if err := validateObservability(config.ObservabilityConfig{}); err != nil {
		t.Fatalf("disabled metrics should not require credentials: %v", err)
	}
	if err := validateObservability(config.ObservabilityConfig{MetricsEnabled: true, MetricsToken: "short"}); err == nil {
		t.Fatal("enabled metrics accepted a short token")
	}
	if err := validateObservability(config.ObservabilityConfig{
		MetricsEnabled: true,
		MetricsToken:   "metrics-token-with-at-least-32-characters",
	}); err != nil {
		t.Fatalf("enabled metrics rejected a strong token: %v", err)
	}
}

func TestValidateProductionCORSRejectsWildcardInRelease(t *testing.T) {
	err := validateProductionCORS("release", " * ")
	if err == nil {
		t.Fatal("expected wildcard CORS to be rejected in release mode")
	}
	if !strings.Contains(err.Error(), "LEDGER_CORS_ALLOWED_ORIGINS") {
		t.Fatalf("error = %q, want CORS env guidance", err.Error())
	}
}

func TestValidateProductionCORSAllowsEmptyReleaseConfig(t *testing.T) {
	if err := validateProductionCORS("release", ""); err != nil {
		t.Fatalf("empty release CORS should allow same-site deployment: %v", err)
	}
}

func TestValidateProductionCORSAllowsWildcardInDebug(t *testing.T) {
	if err := validateProductionCORS("debug", "*"); err != nil {
		t.Fatalf("debug wildcard CORS should remain available for local development: %v", err)
	}
}

func TestHTTPServerHasResourceTimeouts(t *testing.T) {
	server := newHTTPServer(":0", http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	if server.ReadHeaderTimeout <= 0 || server.ReadTimeout <= 0 || server.WriteTimeout <= 0 || server.IdleTimeout <= 0 {
		t.Fatalf("server timeouts must all be positive: %#v", server)
	}
	if server.MaxHeaderBytes <= 0 {
		t.Fatalf("max header bytes = %d, want positive limit", server.MaxHeaderBytes)
	}
}

func TestConfigureTrustedProxiesDisablesForwardedHeadersByDefault(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	if err := configureTrustedProxies(router, ""); err != nil {
		t.Fatalf("configure trusted proxies: %v", err)
	}
	var clientIP string
	router.GET("/", func(c *gin.Context) {
		clientIP = c.ClientIP()
		c.Status(http.StatusNoContent)
	})
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	request.RemoteAddr = "198.51.100.10:12345"
	request.Header.Set("X-Forwarded-For", "127.0.0.1")
	router.ServeHTTP(httptest.NewRecorder(), request)
	if clientIP != "198.51.100.10" {
		t.Fatalf("client IP = %q, want direct peer IP", clientIP)
	}
}

func TestConfigureTrustedProxiesRejectsInvalidValue(t *testing.T) {
	gin.SetMode(gin.TestMode)
	if err := configureTrustedProxies(gin.New(), "not a proxy"); err == nil {
		t.Fatal("expected invalid trusted proxy to be rejected")
	}
}

func TestSetupUploadFilesRejectsOtherUserPrivateFile(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	writeServerUploadFixture(t, uploadPath, "2/transactions/t/b.txt", "other user attachment")

	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)
	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}

	router := gin.New()
	setupUploadFiles(router, uploadPath, authService, nil)

	request := httptest.NewRequest(http.MethodGet, "/uploads/2/transactions/t/b.txt", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", response.Code, response.Body.String())
	}
}

func TestSetupUploadFilesRejectsDirectoryRequests(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	writeServerUploadFixture(t, uploadPath, "1/transactions/t/a.txt", "ledger attachment")

	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)
	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}

	router := gin.New()
	setupUploadFiles(router, uploadPath, authService, nil)

	request := httptest.NewRequest(http.MethodGet, "/uploads/1/transactions/t/", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", response.Code, response.Body.String())
	}
}

func TestSetupUploadFilesNeverServesRestoreGenerationToken(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	writeServerUploadFixture(t, uploadPath, "1/.ledger-restore-generation", "internal-generation")

	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)
	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}
	router := gin.New()
	setupUploadFiles(router, uploadPath, authService, nil)

	request := httptest.NewRequest(http.MethodGet, "/uploads/1/.ledger-restore-generation", nil)
	request.Header.Set("Authorization", "Bearer "+token)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)
	if response.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404; body=%s", response.Code, response.Body.String())
	}
}

func TestSetupUploadFilesDoesNotAcceptJWTInQueryString(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	writeServerUploadFixture(t, uploadPath, "1/transactions/t/a.txt", "ledger attachment")

	jwtManager := jwt.NewManager("test-secret", 15, 60)
	authService := service.NewAuthService(nil, nil, nil, nil, jwtManager)
	token, err := jwtManager.GenerateAccessToken(1)
	if err != nil {
		t.Fatalf("generate access token: %v", err)
	}
	router := gin.New()
	setupUploadFiles(router, uploadPath, authService, nil)

	request := httptest.NewRequest(http.MethodGet, "/uploads/1/transactions/t/a.txt?token="+token, nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401; body=%s", response.Code, response.Body.String())
	}
}

func TestSetupUploadFilesServesOnlyValidatedPublicAvatars(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	avatarDirectory := filepath.Join(uploadPath, "1", "avatars", "profile")
	if err := os.MkdirAll(avatarDirectory, 0700); err != nil {
		t.Fatalf("create avatar directory: %v", err)
	}
	if err := os.WriteFile(
		filepath.Join(avatarDirectory, "avatar.png"),
		[]byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 0, 0, 0, 0, 'I', 'H', 'D', 'R'},
		0600,
	); err != nil {
		t.Fatalf("write png avatar: %v", err)
	}
	if err := os.WriteFile(filepath.Join(avatarDirectory, "avatar.gif"), []byte("GIF89a\x01\x00\x01\x00"), 0600); err != nil {
		t.Fatalf("write gif avatar: %v", err)
	}

	router := gin.New()
	setupUploadFiles(router, uploadPath, service.NewAuthService(nil, nil, nil, nil, jwt.NewManager("test-secret", 15, 60)), nil)

	pngResponse := httptest.NewRecorder()
	router.ServeHTTP(pngResponse, httptest.NewRequest(http.MethodGet, "/uploads/1/avatars/profile/avatar.png", nil))
	if pngResponse.Code != http.StatusOK {
		t.Fatalf("png status = %d, want 200; body=%s", pngResponse.Code, pngResponse.Body.String())
	}
	if pngResponse.Header().Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("png response omitted nosniff header")
	}

	gifResponse := httptest.NewRecorder()
	router.ServeHTTP(gifResponse, httptest.NewRequest(http.MethodGet, "/uploads/1/avatars/profile/avatar.gif", nil))
	if gifResponse.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("gif status = %d, want 415; body=%s", gifResponse.Code, gifResponse.Body.String())
	}
}

func TestSetupUploadFilesRejectsSymlinkEscape(t *testing.T) {
	gin.SetMode(gin.TestMode)
	uploadPath := t.TempDir()
	avatarDirectory := filepath.Join(uploadPath, "1", "avatars", "profile")
	if err := os.MkdirAll(avatarDirectory, 0700); err != nil {
		t.Fatalf("create avatar directory: %v", err)
	}
	outside := filepath.Join(t.TempDir(), "outside.png")
	if err := os.WriteFile(outside, []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, 0600); err != nil {
		t.Fatalf("write outside file: %v", err)
	}
	if err := os.Symlink(outside, filepath.Join(avatarDirectory, "avatar.png")); err != nil {
		t.Fatalf("create symlink: %v", err)
	}
	router := gin.New()
	setupUploadFiles(router, uploadPath, service.NewAuthService(nil, nil, nil, nil, jwt.NewManager("test-secret", 15, 60)), nil)

	response := httptest.NewRecorder()
	router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/uploads/1/avatars/profile/avatar.png", nil))
	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", response.Code, response.Body.String())
	}
}

func TestSetupStaticFilesRejectsAssetsDirectoryRequests(t *testing.T) {
	gin.SetMode(gin.TestMode)
	webPath := t.TempDir()
	writeServerWebFixture(t, webPath, "assets/app.js", "console.log('ok')")
	writeServerWebFixture(t, webPath, "index.html", "<div id=\"app\"></div>")

	router := gin.New()
	setupStaticFiles(router, webPath, newServerSystemService(t), "test-cookie-secret")

	request := httptest.NewRequest(http.MethodGet, "/assets/", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	if response.Code != http.StatusForbidden {
		t.Fatalf("status = %d, want 403; body=%s", response.Code, response.Body.String())
	}
}

func TestSetupStaticFilesUsesExactEntryBoundaryAndSignedCookie(t *testing.T) {
	gin.SetMode(gin.TestMode)
	webPath := t.TempDir()
	writeServerWebFixture(t, webPath, "index.html", "<div id=\"app\"></div>")
	systemService := newServerSystemService(t)
	if err := systemService.SetEntryPath("/secret-entry"); err != nil {
		t.Fatalf("set entry path: %v", err)
	}
	router := gin.New()
	setupStaticFiles(router, webPath, systemService, "test-cookie-secret")

	prefixRequest := httptest.NewRequest(http.MethodGet, "/secret-entry-evil", nil)
	prefixResponse := httptest.NewRecorder()
	router.ServeHTTP(prefixResponse, prefixRequest)
	if prefixResponse.Code != http.StatusNotFound {
		t.Fatalf("prefix-confusion status = %d, want 404", prefixResponse.Code)
	}

	entryRequest := httptest.NewRequest(http.MethodGet, "https://ledger.example/secret-entry", nil)
	entryResponse := httptest.NewRecorder()
	router.ServeHTTP(entryResponse, entryRequest)
	if entryResponse.Code != http.StatusOK {
		t.Fatalf("entry status = %d, want 200; body=%s", entryResponse.Code, entryResponse.Body.String())
	}
	cookies := entryResponse.Result().Cookies()
	if len(cookies) != 1 {
		t.Fatalf("entry cookies = %d, want 1", len(cookies))
	}
	cookie := cookies[0]
	if cookie.Name != "entry_verified" || !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("entry cookie attributes are not hardened: %#v", cookie)
	}
	if cookie.Value != entryAccessCookieValue("test-cookie-secret", "/secret-entry") {
		t.Fatalf("entry cookie value is not the expected signature")
	}

	authorizedRequest := httptest.NewRequest(http.MethodGet, "/", nil)
	authorizedRequest.AddCookie(cookie)
	authorizedResponse := httptest.NewRecorder()
	router.ServeHTTP(authorizedResponse, authorizedRequest)
	if authorizedResponse.Code != http.StatusOK {
		t.Fatalf("signed-cookie status = %d, want 200", authorizedResponse.Code)
	}

	forgedRequest := httptest.NewRequest(http.MethodGet, "/", nil)
	forgedRequest.AddCookie(&http.Cookie{Name: "entry_verified", Value: "forged"})
	forgedResponse := httptest.NewRecorder()
	router.ServeHTTP(forgedResponse, forgedRequest)
	if forgedResponse.Code != http.StatusNotFound {
		t.Fatalf("forged-cookie status = %d, want 404", forgedResponse.Code)
	}
}

func writeServerUploadFixture(t *testing.T, uploadPath string, relativePath string, content string) {
	t.Helper()

	fullPath := filepath.Join(uploadPath, relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		t.Fatalf("create fixture directory: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte(content), 0600); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}

func writeServerWebFixture(t *testing.T, webPath string, relativePath string, content string) {
	t.Helper()

	fullPath := filepath.Join(webPath, relativePath)
	if err := os.MkdirAll(filepath.Dir(fullPath), 0755); err != nil {
		t.Fatalf("create web fixture directory: %v", err)
	}
	if err := os.WriteFile(fullPath, []byte(content), 0600); err != nil {
		t.Fatalf("write web fixture: %v", err)
	}
}

func newServerSystemService(t *testing.T) *service.SystemService {
	t.Helper()

	db, err := database.Init(filepath.Join(t.TempDir(), "ledger.db"))
	if err != nil {
		t.Fatalf("init db: %v", err)
	}
	return service.NewSystemService(repository.NewRepositories(db).System)
}
