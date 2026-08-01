package service

import (
	"bytes"
	"encoding/json"
)

// Optional preserves the three JSON states required by PATCH semantics:
// omitted (Set=false), explicit null, and a concrete value.
type Optional[T any] struct {
	Set   bool
	Null  bool
	Value T
}

func (field *Optional[T]) UnmarshalJSON(data []byte) error {
	field.Set = true
	if bytes.Equal(bytes.TrimSpace(data), []byte("null")) {
		field.Null = true
		var zero T
		field.Value = zero
		return nil
	}
	field.Null = false
	return json.Unmarshal(data, &field.Value)
}
