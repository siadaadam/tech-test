// Package events defines the messages exchanged between the API (producer)
// and the consumer over the queue.
package events

import (
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
)

const AccountAccessed = "account.accessed"

// knownEventTypes is deliberately explicit rather than "any non-empty
// string" - an event of a type the consumer doesn't recognize is exactly
// the kind of poison message that should never be retried into oblivion.
var knownEventTypes = map[string]bool{
	AccountAccessed: true,
}

// Event is the wire format published to the queue and read back by the
// consumer. EventID is the idempotency key: the consumer treats two
// messages with the same EventID as the same logical event no matter how
// many times SQS (or a retrying producer) delivers it.
type Event struct {
	EventID    string    `json:"event_id"`
	EventType  string    `json:"event_type"`
	AccountID  int64     `json:"account_id"`
	OccurredAt time.Time `json:"occurred_at"`
}

func NewAccountAccessed(accountID int64) Event {
	return Event{
		EventID:    uuid.NewString(),
		EventType:  AccountAccessed,
		AccountID:  accountID,
		OccurredAt: time.Now().UTC(),
	}
}

func (e Event) Marshal() ([]byte, error) {
	return json.Marshal(e)
}

// Validate reports whether the event is structurally usable. A message that
// fails validation can never succeed no matter how many times it's
// redelivered, so the consumer routes it straight to the dead-letter queue
// instead of burning retries on it.
func (e Event) Validate() error {
	if _, err := uuid.Parse(e.EventID); err != nil {
		return fmt.Errorf("invalid event_id: %w", err)
	}
	if !knownEventTypes[e.EventType] {
		return fmt.Errorf("unknown event_type %q", e.EventType)
	}
	if e.AccountID <= 0 {
		return fmt.Errorf("account_id must be positive, got %d", e.AccountID)
	}
	if e.OccurredAt.IsZero() {
		return fmt.Errorf("occurred_at must be set")
	}
	return nil
}

func Unmarshal(body []byte) (Event, error) {
	var e Event
	if err := json.Unmarshal(body, &e); err != nil {
		return Event{}, fmt.Errorf("unmarshal event: %w", err)
	}
	return e, nil
}
