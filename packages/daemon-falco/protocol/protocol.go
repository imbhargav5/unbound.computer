// Package protocol implements the binary wire protocol for Falco <-> Daemon communication.
//
// All frames use little-endian byte order.
package protocol

import (
	"encoding/binary"
	"errors"
	"fmt"

	"github.com/google/uuid"
)

const (
	// Frame type identifiers
	TypeSideEffect = 0x03
	TypePublishAck = 0x04

	// Publish status values
	StatusSuccess = 0x01
	StatusFailed  = 0x02

	// Header sizes (excluding the 4-byte length prefix)
	// type(1) + flags(1) + reserved(2) + uuid(16) + payload_len(4) = 24
	SideEffectHeaderSize = 24
	PublishAckHeaderSize = 24

	// Length prefix size
	LengthPrefixSize = 4
)

var (
	ErrIncompleteFrame    = errors.New("incomplete frame")
	ErrInvalidFrameType   = errors.New("invalid frame type")
	ErrInvalidStatus      = errors.New("invalid status value")
	ErrPayloadLenMismatch = errors.New("payload length mismatch")
)

// PublishStatus represents the result of publishing a side-effect.
type PublishStatus uint8

const (
	Success PublishStatus = StatusSuccess
	Failed  PublishStatus = StatusFailed
)

func (s PublishStatus) String() string {
	switch s {
	case Success:
		return "SUCCESS"
	case Failed:
		return "FAILED"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", s)
	}
}

// SideEffectFrame represents a side-effect sent from the Daemon to Falco.
//
// Wire format:
//
//	[4 bytes: total_len (LE u32)]
//	[1 byte:  type = 0x03]
//	[1 byte:  flags]
//	[2 bytes: reserved]
//	[16 bytes: effect_id (UUID)]
//	[4 bytes: payload_len (LE u32)]
//	[N bytes: json_payload]
type SideEffectFrame struct {
	EffectID    uuid.UUID
	Flags       uint8
	JSONPayload []byte
}

// Encode serializes the SideEffectFrame to wire format.
func (f *SideEffectFrame) Encode() []byte {
	payloadLen := len(f.JSONPayload)
	totalLen := SideEffectHeaderSize + payloadLen

	buf := make([]byte, LengthPrefixSize+totalLen)

	// Length prefix (excludes itself)
	binary.LittleEndian.PutUint32(buf[0:4], uint32(totalLen))

	// Type
	buf[4] = TypeSideEffect

	// Flags
	buf[5] = f.Flags

	// Reserved (2 bytes, zeroed)
	buf[6] = 0
	buf[7] = 0

	// Effect ID (16 bytes)
	copy(buf[8:24], f.EffectID[:])

	// Payload length
	binary.LittleEndian.PutUint32(buf[24:28], uint32(payloadLen))

	// Payload
	copy(buf[28:], f.JSONPayload)

	return buf
}

// PublishAckFrame represents an acknowledgment sent from Falco to the Daemon.
//
// Wire format:
//
//	[4 bytes: total_len (LE u32)]
//	[1 byte:  type = 0x04]
//	[1 byte:  status (0x01=SUCCESS, 0x02=FAILED)]
//	[2 bytes: reserved]
//	[16 bytes: effect_id (UUID)]
//	[4 bytes: error_len (LE u32)]
//	[N bytes: error_message]
type PublishAckFrame struct {
	EffectID     uuid.UUID
	Status       PublishStatus
	ErrorMessage string
}

// Encode serializes the PublishAckFrame to wire format.
func (f *PublishAckFrame) Encode() []byte {
	errorLen := len(f.ErrorMessage)
	totalLen := PublishAckHeaderSize + errorLen

	buf := make([]byte, LengthPrefixSize+totalLen)

	// Length prefix (excludes itself)
	binary.LittleEndian.PutUint32(buf[0:4], uint32(totalLen))

	// Type
	buf[4] = TypePublishAck

	// Status
	buf[5] = uint8(f.Status)

	// Reserved (2 bytes, zeroed)
	buf[6] = 0
	buf[7] = 0

	// Effect ID (16 bytes)
	copy(buf[8:24], f.EffectID[:])

	// Error length
	binary.LittleEndian.PutUint32(buf[24:28], uint32(errorLen))

	// Error message
	if errorLen > 0 {
		copy(buf[28:], []byte(f.ErrorMessage))
	}

	return buf
}

// ReadFrame attempts to parse a complete frame from the buffer.
// Returns the frame data (excluding length prefix), bytes consumed, and any error.
// If the buffer doesn't contain a complete frame, returns ErrIncompleteFrame.
func ReadFrame(buf []byte) (data []byte, consumed int, err error) {
	if len(buf) < LengthPrefixSize {
		return nil, 0, ErrIncompleteFrame
	}

	frameLen := binary.LittleEndian.Uint32(buf[0:4])
	totalLen := LengthPrefixSize + int(frameLen)

	if len(buf) < totalLen {
		return nil, 0, ErrIncompleteFrame
	}

	return buf[LengthPrefixSize:totalLen], totalLen, nil
}

// ParseSideEffect parses a SideEffectFrame from raw frame data.
// The data should NOT include the length prefix (use ReadFrame first).
func ParseSideEffect(data []byte) (*SideEffectFrame, error) {
	if len(data) < SideEffectHeaderSize {
		return nil, fmt.Errorf("frame too short: got %d bytes, need at least %d", len(data), SideEffectHeaderSize)
	}

	frameType := data[0]
	if frameType != TypeSideEffect {
		return nil, fmt.Errorf("%w: expected 0x%02x, got 0x%02x", ErrInvalidFrameType, TypeSideEffect, frameType)
	}

	flags := data[1]

	// Skip reserved bytes [2:4]

	var effectID uuid.UUID
	copy(effectID[:], data[4:20])

	payloadLen := binary.LittleEndian.Uint32(data[20:24])

	expectedLen := SideEffectHeaderSize + int(payloadLen)
	if len(data) != expectedLen {
		return nil, fmt.Errorf("%w: header says %d bytes, got %d", ErrPayloadLenMismatch, expectedLen, len(data))
	}

	var payload []byte
	if payloadLen > 0 {
		payload = make([]byte, payloadLen)
		copy(payload, data[24:])
	}

	return &SideEffectFrame{
		EffectID:    effectID,
		Flags:       flags,
		JSONPayload: payload,
	}, nil
}

// ParsePublishAck parses a PublishAckFrame from raw frame data.
// The data should NOT include the length prefix (use ReadFrame first).
func ParsePublishAck(data []byte) (*PublishAckFrame, error) {
	if len(data) < PublishAckHeaderSize {
		return nil, fmt.Errorf("frame too short: got %d bytes, need at least %d", len(data), PublishAckHeaderSize)
	}

	frameType := data[0]
	if frameType != TypePublishAck {
		return nil, fmt.Errorf("%w: expected 0x%02x, got 0x%02x", ErrInvalidFrameType, TypePublishAck, frameType)
	}

	status := PublishStatus(data[1])
	if status != Success && status != Failed {
		return nil, fmt.Errorf("%w: 0x%02x", ErrInvalidStatus, status)
	}

	// Skip reserved bytes [2:4]

	var effectID uuid.UUID
	copy(effectID[:], data[4:20])

	errorLen := binary.LittleEndian.Uint32(data[20:24])

	expectedLen := PublishAckHeaderSize + int(errorLen)
	if len(data) != expectedLen {
		return nil, fmt.Errorf("%w: header says %d bytes, got %d", ErrPayloadLenMismatch, expectedLen, len(data))
	}

	var errorMsg string
	if errorLen > 0 {
		errorMsg = string(data[24:])
	}

	return &PublishAckFrame{
		EffectID:     effectID,
		Status:       status,
		ErrorMessage: errorMsg,
	}, nil
}
