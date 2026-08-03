package money

import (
	"database/sql/driver"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
)

var errInvalidMoney = errors.New("invalid money amount")

const maxExactCents int64 = 1<<53 - 1

// Amount is a public decimal money value backed by integer cents in SQL.
// Keeping the JSON representation decimal preserves the existing API while
// all persistence and explicit arithmetic use the cent helpers below.
type Amount float64

func FromCents(cents int64) Amount {
	if cents > maxExactCents || cents < -maxExactCents {
		return Amount(math.NaN())
	}
	return Amount(float64(cents) / 100)
}

func FromFloat(value float64) (Amount, error) {
	if math.IsNaN(value) || math.IsInf(value, 0) || value > float64(maxExactCents)/100 || value < -float64(maxExactCents)/100 {
		return 0, errInvalidMoney
	}
	return FromCents(int64(math.Round(value * 100))), nil
}

func MustFromFloat(value float64) Amount {
	amount, err := FromFloat(value)
	if err != nil {
		panic(err)
	}
	return amount
}

func (a Amount) Cents() int64 {
	amount, err := FromFloat(float64(a))
	if err != nil {
		return 0
	}
	return int64(math.Round(float64(amount) * 100))
}

func (a Amount) Float64() float64 {
	return float64(FromCents(a.Cents()))
}

func (a Amount) IsValid() bool {
	value := float64(a)
	return !math.IsNaN(value) && !math.IsInf(value, 0) && value <= float64(maxExactCents)/100 && value >= -float64(maxExactCents)/100
}

func (a Amount) Add(other Amount) Amount {
	left, right := a.Cents(), other.Cents()
	if right > 0 && left > maxExactCents-right || right < 0 && left < -maxExactCents-right {
		return Amount(math.NaN())
	}
	return FromCents(left + right)
}

func (a Amount) Sub(other Amount) Amount {
	left, right := a.Cents(), other.Cents()
	if right < 0 && left > maxExactCents+right || right > 0 && left < -maxExactCents+right {
		return Amount(math.NaN())
	}
	return FromCents(left - right)
}

func (a Amount) Negate() Amount {
	return FromCents(-a.Cents())
}

func (a Amount) Divide(divisor int64) Amount {
	if divisor <= 0 {
		return 0
	}
	cents := a.Cents()
	quotient := cents / divisor
	remainder := cents % divisor
	if remainder < 0 {
		remainder = -remainder
	}
	if remainder*2 >= divisor {
		if cents < 0 {
			quotient--
		} else {
			quotient++
		}
	}
	return FromCents(quotient)
}

func (a Amount) MarshalJSON() ([]byte, error) {
	if math.IsNaN(float64(a)) || math.IsInf(float64(a), 0) {
		return nil, errInvalidMoney
	}
	return []byte(formatCents(a.Cents())), nil
}

func (a *Amount) UnmarshalJSON(data []byte) error {
	if a == nil {
		return errInvalidMoney
	}
	data = []byte(strings.TrimSpace(string(data)))
	if len(data) == 0 || data[0] == '"' {
		return errInvalidMoney
	}
	var number json.Number
	if err := json.Unmarshal(data, &number); err != nil {
		return errInvalidMoney
	}
	cents, err := CentsFromDecimalString(number.String())
	if err != nil {
		return err
	}
	amount := FromCents(cents)
	if !amount.IsValid() {
		return errInvalidMoney
	}
	*a = amount
	return nil
}

func (a Amount) Value() (driver.Value, error) {
	if math.IsNaN(float64(a)) || math.IsInf(float64(a), 0) {
		return nil, errInvalidMoney
	}
	return a.Cents(), nil
}

func (a *Amount) Scan(value any) error {
	if a == nil {
		return errInvalidMoney
	}
	var cents int64
	switch typed := value.(type) {
	case int64:
		cents = typed
	case int32:
		cents = int64(typed)
	case int:
		cents = int64(typed)
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) {
			return errInvalidMoney
		}
		cents = int64(math.Round(typed))
	case []byte:
		parsed, err := strconv.ParseInt(string(typed), 10, 64)
		if err != nil {
			return fmt.Errorf("scan money cents: %w", err)
		}
		cents = parsed
	case string:
		parsed, err := strconv.ParseInt(typed, 10, 64)
		if err != nil {
			return fmt.Errorf("scan money cents: %w", err)
		}
		cents = parsed
	default:
		return fmt.Errorf("scan money cents from %T", value)
	}
	amount := FromCents(cents)
	if !amount.IsValid() {
		return errInvalidMoney
	}
	*a = amount
	return nil
}

func (Amount) GormDataType() string {
	return "bigint"
}

func formatCents(cents int64) string {
	sign := ""
	absolute := uint64(cents)
	if cents < 0 {
		sign = "-"
		absolute = uint64(-(cents + 1)) + 1
	}
	return sign + strconv.FormatUint(absolute/100, 10) + "." + fmt.Sprintf("%02d", absolute%100)
}

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

	whole, err := strconv.ParseUint(wholePart, 10, 64)
	if err != nil {
		return 0, errInvalidMoney
	}
	var fractionalCents uint64

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
		fractionalCents, err = strconv.ParseUint(firstTwoDigits, 10, 64)
		if err != nil {
			return 0, err
		}

		if len(fractionalPart) > 2 && fractionalPart[2] >= '5' {
			fractionalCents++
		}
	}
	if fractionalCents == 100 {
		if whole == math.MaxUint64 {
			return 0, errInvalidMoney
		}
		whole++
		fractionalCents = 0
	}

	limit := uint64(math.MaxInt64)
	if sign < 0 {
		limit++
	}
	if whole > limit/100 || (whole == limit/100 && fractionalCents > limit%100) {
		return 0, errInvalidMoney
	}
	absolute := whole*100 + fractionalCents
	if sign > 0 {
		return int64(absolute), nil
	}
	if absolute == uint64(math.MaxInt64)+1 {
		return math.MinInt64, nil
	}
	return -int64(absolute), nil
}

func isDigits(value string) bool {
	for _, ch := range value {
		if ch < '0' || ch > '9' {
			return false
		}
	}
	return true
}
