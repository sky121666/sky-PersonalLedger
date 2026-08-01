package service

import "testing"

func TestMatchesEntryPathRequiresPathSegmentBoundary(t *testing.T) {
	for _, requestPath := range []string{"/secret", "/secret/", "/secret/assets/app.js"} {
		if !MatchesEntryPath(requestPath, "/secret") {
			t.Fatalf("request path %q should match", requestPath)
		}
	}
	for _, requestPath := range []string{"/", "/secret-evil", "/secre"} {
		if MatchesEntryPath(requestPath, "/secret") {
			t.Fatalf("request path %q should not match", requestPath)
		}
	}
}
