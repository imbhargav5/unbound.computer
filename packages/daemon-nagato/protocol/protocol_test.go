package protocol

import (
	"bytes"
	"testing"

	"github.com/google/uuid"
)

func TestCommandFrameEncodeDecode(t *testing.T) {
	original := &CommandFrame{
		CommandID:        uuid.New(),
		Flags:            0x00,
		EncryptedPayload: []byte("test payload data"),
	}

	encoded := original.Encode()

	// Parse the frame
	data, consumed, err := ReadFrame(encoded)
	if err != nil {
		t.Fatalf("ReadFrame failed: %v", err)
	}
	if consumed != len(encoded) {
		t.Errorf("consumed %d bytes, expected %d", consumed, len(encoded))
	}

	decoded, err := ParseCommandFrame(data)
	if err != nil {
		t.Fatalf("ParseCommandFrame failed: %v", err)
	}

	if decoded.CommandID != original.CommandID {
		t.Errorf("CommandID mismatch: got %s, want %s", decoded.CommandID, original.CommandID)
	}
	if decoded.Flags != original.Flags {
		t.Errorf("Flags mismatch: got %d, want %d", decoded.Flags, original.Flags)
	}
	if !bytes.Equal(decoded.EncryptedPayload, original.EncryptedPayload) {
		t.Errorf("Payload mismatch: got %v, want %v", decoded.EncryptedPayload, original.EncryptedPayload)
	}
}

func TestDaemonDecisionFrameEncodeDecode(t *testing.T) {
	tests := []struct {
		name     string
		decision Decision
		result   []byte
	}{
		{"ack with result", AckMessage, []byte("result data")},
		{"ack without result", AckMessage, nil},
		{"do not ack with result", DoNotAck, []byte("error message")},
		{"do not ack without result", DoNotAck, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			original := &DaemonDecisionFrame{
				CommandID: uuid.New(),
				Decision:  tt.decision,
				Result:    tt.result,
			}

			encoded := original.Encode()

			data, consumed, err := ReadFrame(encoded)
			if err != nil {
				t.Fatalf("ReadFrame failed: %v", err)
			}
			if consumed != len(encoded) {
				t.Errorf("consumed %d bytes, expected %d", consumed, len(encoded))
			}

			decoded, err := ParseDaemonDecision(data)
			if err != nil {
				t.Fatalf("ParseDaemonDecision failed: %v", err)
			}

			if decoded.CommandID != original.CommandID {
				t.Errorf("CommandID mismatch: got %s, want %s", decoded.CommandID, original.CommandID)
			}
			if decoded.Decision != original.Decision {
				t.Errorf("Decision mismatch: got %v, want %v", decoded.Decision, original.Decision)
			}
			if !bytes.Equal(decoded.Result, original.Result) {
				t.Errorf("Result mismatch: got %v, want %v", decoded.Result, original.Result)
			}
		})
	}
}

func TestReadFrameIncomplete(t *testing.T) {
	frame := &CommandFrame{
		CommandID:        uuid.New(),
		EncryptedPayload: []byte("test"),
	}
	encoded := frame.Encode()

	// Test with partial data
	for i := 0; i < len(encoded)-1; i++ {
		_, _, err := ReadFrame(encoded[:i])
		if err != ErrIncompleteFrame {
			t.Errorf("ReadFrame with %d bytes: got %v, want ErrIncompleteFrame", i, err)
		}
	}

	// Complete frame should work
	_, _, err := ReadFrame(encoded)
	if err != nil {
		t.Errorf("ReadFrame with complete data failed: %v", err)
	}
}

func TestReadFrameMultipleFrames(t *testing.T) {
	frame1 := &CommandFrame{
		CommandID:        uuid.New(),
		EncryptedPayload: []byte("first"),
	}
	frame2 := &CommandFrame{
		CommandID:        uuid.New(),
		EncryptedPayload: []byte("second"),
	}

	// Concatenate two frames
	buf := append(frame1.Encode(), frame2.Encode()...)

	// Read first frame
	data1, consumed1, err := ReadFrame(buf)
	if err != nil {
		t.Fatalf("ReadFrame 1 failed: %v", err)
	}

	decoded1, err := ParseCommandFrame(data1)
	if err != nil {
		t.Fatalf("ParseCommandFrame 1 failed: %v", err)
	}
	if decoded1.CommandID != frame1.CommandID {
		t.Errorf("Frame 1 CommandID mismatch")
	}

	// Read second frame from remaining buffer
	data2, _, err := ReadFrame(buf[consumed1:])
	if err != nil {
		t.Fatalf("ReadFrame 2 failed: %v", err)
	}

	decoded2, err := ParseCommandFrame(data2)
	if err != nil {
		t.Fatalf("ParseCommandFrame 2 failed: %v", err)
	}
	if decoded2.CommandID != frame2.CommandID {
		t.Errorf("Frame 2 CommandID mismatch")
	}
}

func TestParseInvalidFrameType(t *testing.T) {
	frame := &CommandFrame{
		CommandID:        uuid.New(),
		EncryptedPayload: []byte("test"),
	}
	encoded := frame.Encode()

	data, _, _ := ReadFrame(encoded)

	// Try to parse as DaemonDecision (wrong type)
	_, err := ParseDaemonDecision(data)
	if err == nil {
		t.Error("expected error for wrong frame type")
	}
}

func TestParseInvalidDecision(t *testing.T) {
	frame := &DaemonDecisionFrame{
		CommandID: uuid.New(),
		Decision:  AckMessage,
	}
	encoded := frame.Encode()

	// Corrupt the decision byte
	encoded[5] = 0xFF

	data, _, _ := ReadFrame(encoded)
	_, err := ParseDaemonDecision(data)
	if err == nil {
		t.Error("expected error for invalid decision value")
	}
}

func TestEmptyPayload(t *testing.T) {
	original := &CommandFrame{
		CommandID:        uuid.New(),
		Flags:            0x00,
		EncryptedPayload: nil,
	}

	encoded := original.Encode()
	data, _, err := ReadFrame(encoded)
	if err != nil {
		t.Fatalf("ReadFrame failed: %v", err)
	}

	decoded, err := ParseCommandFrame(data)
	if err != nil {
		t.Fatalf("ParseCommandFrame failed: %v", err)
	}

	if len(decoded.EncryptedPayload) != 0 {
		t.Errorf("expected empty payload, got %v", decoded.EncryptedPayload)
	}
}

func TestDecisionString(t *testing.T) {
	tests := []struct {
		decision Decision
		expected string
	}{
		{AckMessage, "ACK_MESSAGE"},
		{DoNotAck, "DO_NOT_ACK"},
		{Decision(0xFF), "UNKNOWN(255)"},
	}

	for _, tt := range tests {
		if got := tt.decision.String(); got != tt.expected {
			t.Errorf("Decision(%d).String() = %q, want %q", tt.decision, got, tt.expected)
		}
	}
}
