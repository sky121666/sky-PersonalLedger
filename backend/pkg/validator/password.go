package validator

import (
	"errors"
	"unicode"
)

var (
	ErrPasswordTooShort      = errors.New("密码长度至少8位")
	ErrPasswordNoUppercase   = errors.New("密码必须包含至少一个大写字母")
	ErrPasswordNoLowercase   = errors.New("密码必须包含至少一个小写字母")
	ErrPasswordNoDigit       = errors.New("密码必须包含至少一个数字")
	ErrPasswordNoSpecialChar = errors.New("密码必须包含至少一个特殊字符")
)

// ValidatePassword checks if password meets security requirements
func ValidatePassword(password string) error {
	if len(password) < 8 {
		return ErrPasswordTooShort
	}

	var (
		hasUpper   = false
		hasLower   = false
		hasDigit   = false
		hasSpecial = false
	)

	for _, char := range password {
		switch {
		case unicode.IsUpper(char):
			hasUpper = true
		case unicode.IsLower(char):
			hasLower = true
		case unicode.IsDigit(char):
			hasDigit = true
		case unicode.IsPunct(char) || unicode.IsSymbol(char):
			hasSpecial = true
		}
	}

	if !hasUpper {
		return ErrPasswordNoUppercase
	}
	if !hasLower {
		return ErrPasswordNoLowercase
	}
	if !hasDigit {
		return ErrPasswordNoDigit
	}
	if !hasSpecial {
		return ErrPasswordNoSpecialChar
	}

	return nil
}

// ValidatePasswordSimple is a simpler version requiring only 8+ characters
// Use this for backward compatibility or less strict requirements
func ValidatePasswordSimple(password string) error {
	if len(password) < 8 {
		return ErrPasswordTooShort
	}
	return nil
}
