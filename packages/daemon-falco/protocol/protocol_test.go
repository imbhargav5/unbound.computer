package protocol

import (
	"bytes"
	"testing"

	"github.com/google/uuid"
)

func TestSideEffectFrameEncodeDecode(t *testing.T) {
	original := &SideEffectFrame{
		EffectID:    uuid.New(),
		Flags:       0x00,
		JSONPayload: []byte(`{"type":"session_created","session_id":"abc-123"}`),
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

	decoded, err := ParseSideEffect(data)
	if err != nil {
		t.Fatalf("ParseSideEffect failed: %v", err)
	}

	if decoded.EffectID != original.EffectID {
		t.Errorf("EffectID mismatch: got %s, want %s", decoded.EffectID, original.EffectID)
	}
	if decoded.Flags != original.Flags {
		t.Errorf("Flags mismatch: got %d, want %d", decoded.Flags, original.Flags)
	}
	if !bytes.Equal(decoded.JSONPayload, original.JSONPayload) {
		t.Errorf("Payload mismatch: got %v, want %v", decoded.JSONPayload, original.JSONPayload)
	}
}

func TestPublishAckFrameEncodeDecode(t *testing.T) {
	tests := []struct {
		name     string
		status   PublishStatus
		errorMsg string
	}{
		{"success no message", Success, ""},
		{"failed with message", Failed, "connection timeout"},
		{"failed no message", Failed, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			original := &PublishAckFrame{
				EffectID:     uuid.New(),
				Status:       tt.status,
				ErrorMessage: tt.errorMsg,
			}

			encoded := original.Encode()

			data, consumed, err := ReadFrame(encoded)
			if err != nil {
				t.Fatalf("ReadFrame failed: %v", err)
			}
			if consumed != len(encoded) {
				t.Errorf("consumed %d bytes, expected %d", consumed, len(encoded))
			}

			decoded, err := ParsePublishAck(data)
			if err != nil {
				t.Fatalf("ParsePublishAck failed: %v", err)
			}

			if decoded.EffectID != original.EffectID {
				t.Errorf("EffectID mismatch: got %s, want %s", decoded.EffectID, original.EffectID)
			}
			if decoded.Status != original.Status {
				t.Errorf("Status mismatch: got %v, want %v", decoded.Status, original.Status)
			}
			if decoded.ErrorMessage != original.ErrorMessage {
				t.Errorf("ErrorMessage mismatch: got %q, want %q", decoded.ErrorMessage, original.ErrorMessage)
			}
		})
	}
}

func TestReadFrameIncomplete(t *testing.T) {
	frame := &SideEffectFrame{
		EffectID:    uuid.New(),
		JSONPayload: []byte(`{"type":"test"}`),
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
	frame1 := &SideEffectFrame{
		EffectID:    uuid.New(),
		JSONPayload: []byte(`{"type":"first"}`),
	}
	frame2 := &SideEffectFrame{
		EffectID:    uuid.New(),
		JSONPayload: []byte(`{"type":"second"}`),
	}

	// Concatenate two frames
	buf := append(frame1.Encode(), frame2.Encode()...)

	// Read first frame
	data1, consumed1, err := ReadFrame(buf)
	if err != nil {
		t.Fatalf("ReadFrame 1 failed: %v", err)
	}

	decoded1, err := ParseSideEffect(data1)
	if err != nil {
		t.Fatalf("ParseSideEffect 1 failed: %v", err)
	}
	if decoded1.EffectID != frame1.EffectID {
		t.Errorf("Frame 1 EffectID mismatch")
	}

	// Read second frame from remaining buffer
	data2, _, err := ReadFrame(buf[consumed1:])
	if err != nil {
		t.Fatalf("ReadFrame 2 failed: %v", err)
	}

	decoded2, err := ParseSideEffect(data2)
	if err != nil {
		t.Fatalf("ParseSideEffect 2 failed: %v", err)
	}
	if decoded2.EffectID != frame2.EffectID {
		t.Errorf("Frame 2 EffectID mismatch")
	}
}

func TestParseInvalidFrameType(t *testing.T) {
	frame := &SideEffectFrame{
		EffectID:    uuid.New(),
		JSONPayload: []byte(`{"type":"test"}`),
	}
	encoded := frame.Encode()

	data, _, _ := ReadFrame(encoded)

	// Try to parse as PublishAck (wrong type)
	_, err := ParsePublishAck(data)
	if err == nil {
		t.Error("expected error for wrong frame type")
	}
}

func TestParseInvalidStatus(t *testing.T) {
	frame := &PublishAckFrame{
		EffectID: uuid.New(),
		Status:   Success,
	}
	encoded := frame.Encode()

	// Corrupt the status byte
	encoded[5] = 0xFF

	data, _, _ := ReadFrame(encoded)
	_, err := ParsePublishAck(data)
	if err == nil {
		t.Error("expected error for invalid status value")
	}
}

func TestEmptyPayload(t *testing.T) {
	original := &SideEffectFrame{
		EffectID:    uuid.New(),
		Flags:       0x00,
		JSONPayload: nil,
	}

	encoded := original.Encode()
	data, _, err := ReadFrame(encoded)
	if err != nil {
		t.Fatalf("ReadFrame failed: %v", err)
	}

	decoded, err := ParseSideEffect(data)
	if err != nil {
		t.Fatalf("ParseSideEffect failed: %v", err)
	}

	if len(decoded.JSONPayload) != 0 {
		t.Errorf("expected empty payload, got %v", decoded.JSONPayload)
	}
}

func TestPublishStatusString(t *testing.T) {
	tests := []struct {
		status   PublishStatus
		expected string
	}{
		{Success, "SUCCESS"},
		{Failed, "FAILED"},
		{PublishStatus(0xFF), "UNKNOWN(255)"},
	}

	for _, tt := range tests {
		if got := tt.status.String(); got != tt.expected {
			t.Errorf("PublishStatus(%d).String() = %q, want %q", tt.status, got, tt.expected)
		}
	}
}
