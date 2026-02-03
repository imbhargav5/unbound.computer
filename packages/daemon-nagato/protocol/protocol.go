// Package protocol implements the binary wire protocol for Nagato <-> Daemon communication.
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
	TypeCommand        = 0x01
	TypeDaemonDecision = 0x02

	// Decision values
	DecisionAckMessage = 0x01
	DecisionDoNotAck   = 0x02

	// Header sizes (excluding the 4-byte length prefix)
	// type(1) + flags(1) + reserved(2) + uuid(16) + payload_len(4) = 24
	CommandHeaderSize        = 24
	DaemonDecisionHeaderSize = 24

	// Length prefix size
	LengthPrefixSize = 4
)

var (
	ErrIncompleteFrame    = errors.New("incomplete frame")
	ErrInvalidFrameType   = errors.New("invalid frame type")
	ErrInvalidDecision    = errors.New("invalid decision value")
	ErrPayloadLenMismatch = errors.New("payload length mismatch")
	ErrCommandIDMismatch  = errors.New("command ID mismatch")
)

// Decision represents the daemon's decision for a command.
type Decision uint8

const (
	AckMessage Decision = DecisionAckMessage
	DoNotAck   Decision = DecisionDoNotAck
)

func (d Decision) String() string {
	switch d {
	case AckMessage:
		return "ACK_MESSAGE"
	case DoNotAck:
		return "DO_NOT_ACK"
	default:
		return fmt.Sprintf("UNKNOWN(%d)", d)
	}
}

// CommandFrame represents a command sent from Nagato to the Daemon.
//
// Wire format:
//
//	[4 bytes: total_len (LE u32)]
//	[1 byte:  type = 0x01]
//	[1 byte:  flags]
//	[2 bytes: reserved]
//	[16 bytes: command_id (UUID)]
//	[4 bytes: payload_len (LE u32)]
//	[N bytes: encrypted_payload]
type CommandFrame struct {
	CommandID        uuid.UUID
	Flags            uint8
	EncryptedPayload []byte
}

// Encode serializes the CommandFrame to wire format.
func (f *CommandFrame) Encode() []byte {
	payloadLen := len(f.EncryptedPayload)
	totalLen := CommandHeaderSize + payloadLen

	buf := make([]byte, LengthPrefixSize+totalLen)

	// Length prefix (excludes itself)
	binary.LittleEndian.PutUint32(buf[0:4], uint32(totalLen))

	// Type
	buf[4] = TypeCommand

	// Flags
	buf[5] = f.Flags

	// Reserved (2 bytes, zeroed)
	buf[6] = 0
	buf[7] = 0

	// Command ID (16 bytes)
	copy(buf[8:24], f.CommandID[:])

	// Payload length
	binary.LittleEndian.PutUint32(buf[24:28], uint32(payloadLen))

	// Payload
	copy(buf[28:], f.EncryptedPayload)

	return buf
}

// DaemonDecisionFrame represents a decision sent from the Daemon to Nagato.
//
// Wire format:
//
//	[4 bytes: total_len (LE u32)]
//	[1 byte:  type = 0x02]
//	[1 byte:  decision]
//	[2 bytes: reserved]
//	[16 bytes: command_id (UUID)]
//	[4 bytes: result_len (LE u32)]
//	[N bytes: result]
type DaemonDecisionFrame struct {
	CommandID uuid.UUID
	Decision  Decision
	Result    []byte
}

// Encode serializes the DaemonDecisionFrame to wire format.
func (f *DaemonDecisionFrame) Encode() []byte {
	resultLen := len(f.Result)
	totalLen := DaemonDecisionHeaderSize + resultLen

	buf := make([]byte, LengthPrefixSize+totalLen)

	// Length prefix (excludes itself)
	binary.LittleEndian.PutUint32(buf[0:4], uint32(totalLen))

	// Type
	buf[4] = TypeDaemonDecision

	// Decision
	buf[5] = uint8(f.Decision)

	// Reserved (2 bytes, zeroed)
	buf[6] = 0
	buf[7] = 0

	// Command ID (16 bytes)
	copy(buf[8:24], f.CommandID[:])

	// Result length
	binary.LittleEndian.PutUint32(buf[24:28], uint32(resultLen))

	// Result
	copy(buf[28:], f.Result)

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

// ParseDaemonDecision parses a DaemonDecisionFrame from raw frame data.
// The data should NOT include the length prefix (use ReadFrame first).
func ParseDaemonDecision(data []byte) (*DaemonDecisionFrame, error) {
	if len(data) < DaemonDecisionHeaderSize {
		return nil, fmt.Errorf("frame too short: got %d bytes, need at least %d", len(data), DaemonDecisionHeaderSize)
	}

	frameType := data[0]
	if frameType != TypeDaemonDecision {
		return nil, fmt.Errorf("%w: expected 0x%02x, got 0x%02x", ErrInvalidFrameType, TypeDaemonDecision, frameType)
	}

	decision := Decision(data[1])
	if decision != AckMessage && decision != DoNotAck {
		return nil, fmt.Errorf("%w: 0x%02x", ErrInvalidDecision, decision)
	}

	// Skip reserved bytes [2:4]

	var commandID uuid.UUID
	copy(commandID[:], data[4:20])

	resultLen := binary.LittleEndian.Uint32(data[20:24])

	expectedLen := DaemonDecisionHeaderSize + int(resultLen)
	if len(data) != expectedLen {
		return nil, fmt.Errorf("%w: header says %d bytes, got %d", ErrPayloadLenMismatch, expectedLen, len(data))
	}

	var result []byte
	if resultLen > 0 {
		result = make([]byte, resultLen)
		copy(result, data[24:])
	}

	return &DaemonDecisionFrame{
		CommandID: commandID,
		Decision:  decision,
		Result:    result,
	}, nil
}

// ParseCommandFrame parses a CommandFrame from raw frame data.
// The data should NOT include the length prefix (use ReadFrame first).
func ParseCommandFrame(data []byte) (*CommandFrame, error) {
	if len(data) < CommandHeaderSize {
		return nil, fmt.Errorf("frame too short: got %d bytes, need at least %d", len(data), CommandHeaderSize)
	}

	frameType := data[0]
	if frameType != TypeCommand {
		return nil, fmt.Errorf("%w: expected 0x%02x, got 0x%02x", ErrInvalidFrameType, TypeCommand, frameType)
	}

	flags := data[1]

	// Skip reserved bytes [2:4]

	var commandID uuid.UUID
	copy(commandID[:], data[4:20])

	payloadLen := binary.LittleEndian.Uint32(data[20:24])

	expectedLen := CommandHeaderSize + int(payloadLen)
	if len(data) != expectedLen {
		return nil, fmt.Errorf("%w: header says %d bytes, got %d", ErrPayloadLenMismatch, expectedLen, len(data))
	}

	var payload []byte
	if payloadLen > 0 {
		payload = make([]byte, payloadLen)
		copy(payload, data[24:])
	}

	return &CommandFrame{
		CommandID:        commandID,
		Flags:            flags,
		EncryptedPayload: payload,
	}, nil
}
