package money

import (
	"errors"
	"strconv"
	"strings"
)

var errInvalidMoney = errors.New("invalid money amount")

func CentsFromDecimalString(value string) (int64, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0, errInvalidMoney
	}

	sign := int64(1)
	if strings.HasPrefix(value, "-") {
		sign = -1
		value = strings.TrimPrefix(value, "-")
	} else if strings.HasPrefix(value, "+") {
		value = strings.TrimPrefix(value, "+")
	}
	if value == "" || value == "." {
		return 0, errInvalidMoney
	}

	parts := strings.Split(value, ".")
	if len(parts) > 2 {
		return 0, errInvalidMoney
	}

	wholePart := parts[0]
	if wholePart == "" {
		wholePart = "0"
	}
	if !isDigits(wholePart) {
		return 0, errInvalidMoney
	}

	whole, err := strconv.ParseInt(wholePart, 10, 64)
	if err != nil {
		return 0, err
	}
	cents := whole * 100

	if len(parts) == 2 {
		fractionalPart := parts[1]
		if fractionalPart != "" && !isDigits(fractionalPart) {
			return 0, errInvalidMoney
		}

		firstTwoDigits := fractionalPart
		if len(firstTwoDigits) > 2 {
			firstTwoDigits = firstTwoDigits[:2]
		}
		for len(firstTwoDigits) < 2 {
			firstTwoDigits += "0"
		}
		fractionalCents, err := strconv.ParseInt(firstTwoDigits, 10, 64)
		if err != nil {
			return 0, err
		}
		cents += fractionalCents

		if len(fractionalPart) > 2 && fractionalPart[2] >= '5' {
			cents++
		}
	}

	return sign * cents, nil
}

func isDigits(value string) bool {
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}
