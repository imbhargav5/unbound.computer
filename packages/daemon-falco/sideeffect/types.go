// Package sideeffect defines the side-effect types that mirror Armin's SideEffect enum.
package sideeffect

import "encoding/json"

// Type represents the type of side-effect.
type Type string

const (
	// Repository side-effects
	RepositoryCreated Type = "repository_created"
	RepositoryDeleted Type = "repository_deleted"

	// Session side-effects
	SessionCreated Type = "session_created"
	SessionClosed  Type = "session_closed"
	SessionDeleted Type = "session_deleted"
	SessionUpdated Type = "session_updated"

	// Message side-effects
	MessageAppended Type = "message_appended"

	// Session state side-effects
	AgentStatusChanged   Type = "agent_status_changed"
	RuntimeStatusUpdated Type = "runtime_status_updated"

	// Outbox side-effects
	OutboxEventsSent  Type = "outbox_events_sent"
	OutboxEventsAcked Type = "outbox_events_acked"
)

// SideEffect represents a side-effect emitted by Armin.
// The JSON payload is decoded based on the Type field.
type SideEffect struct {
	Type Type `json:"type"`

	// Channel overrides the default publisher channel when present.
	Channel string `json:"channel,omitempty"`

	// Event overrides the default event name when present.
	Event string `json:"event,omitempty"`

	// Payload is the optional data body to publish instead of the full envelope.
	Payload json.RawMessage `json:"payload,omitempty"`

	// ObjectSet fields
	ObjectKey string `json:"object_key,omitempty"`

	// Repository fields
	RepositoryID string `json:"repository_id,omitempty"`

	// Session fields
	SessionID string `json:"session_id,omitempty"`

	// Message fields
	MessageID string `json:"message_id,omitempty"`

	// Agent status fields
	Status string `json:"status,omitempty"`

	// Outbox fields
	BatchID string `json:"batch_id,omitempty"`
}

// AgentStatus values
const (
	AgentStatusIdle    = "idle"
	AgentStatusRunning = "running"
	AgentStatusWaiting = "waiting"
	AgentStatusError   = "error"
)
