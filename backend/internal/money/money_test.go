package money

import (
	"encoding/json"
	"math"
	"testing"
)

func TestCentsFromDecimalString(t *testing.T) {
	tests := map[string]int64{
		"0":       0,
		"0.01":    1,
		"12.34":   1234,
		"-12.34":  -1234,
		"100.999": 10100,
		"100.994": 10099,
		" .99 ":   99,
		"12.":     1200,
		"-0.005":  -1,
	}
	for input, want := range tests {
		got, err := CentsFromDecimalString(input)
		if err != nil {
			t.Fatalf("CentsFromDecimalString(%q): %v", input, err)
		}
		if got != want {
			t.Fatalf("CentsFromDecimalString(%q) = %d, want %d", input, got, want)
		}
	}
}

func TestCentsFromDecimalStringRejectsInvalidInput(t *testing.T) {
	for _, input := range []string{"", ".", "12.3.4", "12x", "1.x", "92233720368547758.08", "-92233720368547758.09"} {
		if _, err := CentsFromDecimalString(input); err == nil {
			t.Fatalf("CentsFromDecimalString(%q) succeeded, want error", input)
		}
	}
}

func TestAmountJSONPreservesDecimalNumberContract(t *testing.T) {
	var amount Amount
	if err := json.Unmarshal([]byte("12.345"), &amount); err != nil {
		t.Fatalf("unmarshal amount: %v", err)
	}
	if amount.Cents() != 1235 {
		t.Fatalf("amount cents = %d, want 1235", amount.Cents())
	}
	encoded, err := json.Marshal(amount)
	if err != nil {
		t.Fatalf("marshal amount: %v", err)
	}
	if string(encoded) != "12.35" {
		t.Fatalf("encoded amount = %s, want decimal JSON number", encoded)
	}
	if err := json.Unmarshal([]byte(`"12.34"`), &amount); err == nil {
		t.Fatal("quoted money value should be rejected")
	}
}

func TestAmountArithmeticUsesCents(t *testing.T) {
	oneTenth := MustFromFloat(0.1)
	twoTenths := MustFromFloat(0.2)
	if got := oneTenth.Add(twoTenths); got.Cents() != 30 {
		t.Fatalf("0.10 + 0.20 = %d cents, want 30", got.Cents())
	}
	if got := MustFromFloat(10).Sub(MustFromFloat(3.33)); got.Cents() != 667 {
		t.Fatalf("10.00 - 3.33 = %d cents, want 667", got.Cents())
	}
	if got := MustFromFloat(-1).Divide(8); got.Cents() != -13 {
		t.Fatalf("-1.00 / 8 = %d cents, want -13", got.Cents())
	}
	if got := FromCents(maxExactCents).Add(FromCents(1)); got.IsValid() {
		t.Fatal("overflowing exact-cent range should produce an invalid amount")
	}
}

func TestAmountSQLValueAndScanUseIntegerCents(t *testing.T) {
	value, err := MustFromFloat(12.34).Value()
	if err != nil {
		t.Fatalf("money value: %v", err)
	}
	if value != int64(1234) {
		t.Fatalf("sql value = %#v, want int64(1234)", value)
	}
	var scanned Amount
	if err := scanned.Scan(int64(-1234)); err != nil {
		t.Fatalf("scan money: %v", err)
	}
	if scanned.Cents() != -1234 {
		t.Fatalf("scanned cents = %d, want -1234", scanned.Cents())
	}
	if err := scanned.Scan(math.NaN()); err == nil {
		t.Fatal("scanning NaN should fail")
	}
}

func TestFormatCentsHandlesMinimumInt64(t *testing.T) {
	if got := formatCents(math.MinInt64); got != "-92233720368547758.08" {
		t.Fatalf("format min cents = %q", got)
	}
	got, err := CentsFromDecimalString("-92233720368547758.08")
	if err != nil || got != math.MinInt64 {
		t.Fatalf("parse minimum cents = %d, %v", got, err)
	}
}
