package money

import "testing"

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
	for _, input := range []string{"", ".", "12.3.4", "12x", "1.x"} {
		if _, err := CentsFromDecimalString(input); err == nil {
			t.Fatalf("CentsFromDecimalString(%q) succeeded, want error", input)
		}
	}
}
