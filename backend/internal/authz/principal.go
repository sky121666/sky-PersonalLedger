package authz

import "strings"

const (
	CredentialJWT      = "jwt"
	CredentialAPIToken = "api_token"

	ScopeLedgerRead  = "ledger:read"
	ScopeLedgerWrite = "ledger:write"
	ScopeReportRead  = "report:read"
	ScopeUploadRead  = "upload:read"
	ScopeUploadWrite = "upload:write"
)

var AllowedAPITokenScopes = []string{
	ScopeLedgerRead,
	ScopeLedgerWrite,
	ScopeReportRead,
	ScopeUploadRead,
	ScopeUploadWrite,
}

type Principal struct {
	UserID         uint
	CredentialType string
	Scopes         []string
}

func (principal Principal) HasScope(required string) bool {
	if principal.CredentialType == CredentialJWT {
		return true
	}
	for _, scope := range principal.Scopes {
		if strings.EqualFold(strings.TrimSpace(scope), required) {
			return true
		}
	}
	return false
}

func NormalizeScopes(values []string) ([]string, bool) {
	allowed := make(map[string]struct{}, len(AllowedAPITokenScopes))
	for _, scope := range AllowedAPITokenScopes {
		allowed[scope] = struct{}{}
	}
	seen := map[string]struct{}{}
	result := make([]string, 0, len(values))
	for _, value := range values {
		scope := strings.ToLower(strings.TrimSpace(value))
		if scope == "" {
			continue
		}
		if _, exists := allowed[scope]; !exists {
			return nil, false
		}
		if _, duplicate := seen[scope]; duplicate {
			continue
		}
		seen[scope] = struct{}{}
		result = append(result, scope)
	}
	return result, true
}
