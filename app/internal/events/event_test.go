package events

import (
	"testing"
	"time"
)

func TestNewAccountAccessedIsValid(t *testing.T) {
	e := NewAccountAccessed(42)
	if err := e.Validate(); err != nil {
		t.Fatalf("expected freshly constructed event to be valid, got: %v", err)
	}
}

func TestValidateRejectsBadEventID(t *testing.T) {
	e := NewAccountAccessed(1)
	e.EventID = "not-a-uuid"
	if err := e.Validate(); err == nil {
		t.Fatal("expected error for non-UUID event_id")
	}
}

func TestValidateRejectsUnknownEventType(t *testing.T) {
	e := NewAccountAccessed(1)
	e.EventType = "account.deleted-by-mistake"
	if err := e.Validate(); err == nil {
		t.Fatal("expected error for unknown event_type")
	}
}

func TestValidateRejectsNonPositiveAccountID(t *testing.T) {
	e := NewAccountAccessed(1)
	e.AccountID = 0
	if err := e.Validate(); err == nil {
		t.Fatal("expected error for non-positive account_id")
	}
}

func TestValidateRejectsZeroOccurredAt(t *testing.T) {
	e := NewAccountAccessed(1)
	e.OccurredAt = time.Time{}
	if err := e.Validate(); err == nil {
		t.Fatal("expected error for zero occurred_at")
	}
}

func TestUnmarshalRejectsGarbage(t *testing.T) {
	if _, err := Unmarshal([]byte("not json")); err == nil {
		t.Fatal("expected error unmarshaling garbage input")
	}
}
