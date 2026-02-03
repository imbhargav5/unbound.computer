// Package client provides the Unix domain socket client for communicating with the daemon.
package client

import (
	"context"
	"errors"
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/unbound-computer/daemon-nagato/protocol"
)

const (
	// Connection retry settings
	MaxRetries  = 3
	RetryDelay  = 500 * time.Millisecond
	ReadBufSize = 4096
)

var (
	ErrNotConnected      = errors.New("not connected to daemon")
	ErrConnectionFailed  = errors.New("failed to connect to daemon")
	ErrTimeout           = errors.New("daemon response timeout")
	ErrCommandIDMismatch = errors.New("command ID mismatch in response")
)

// Client communicates with the daemon over a Unix domain socket.
type Client struct {
	socketPath string
	timeout    time.Duration
	logger     *zap.Logger

	mu   sync.Mutex
	conn net.Conn
	buf  []byte // Read buffer for frame parsing
}

// NewClient creates a new daemon client.
func NewClient(socketPath string, timeout time.Duration, logger *zap.Logger) *Client {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &Client{
		socketPath: socketPath,
		timeout:    timeout,
		logger:     logger,
		buf:        make([]byte, 0, ReadBufSize),
	}
}

// Connect establishes a connection to the daemon socket.
func (c *Client) Connect(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	return c.connectLocked(ctx)
}

func (c *Client) connectLocked(ctx context.Context) error {
	if c.conn != nil {
		return nil // Already connected
	}

	var lastErr error
	for attempt := 1; attempt <= MaxRetries; attempt++ {
		c.logger.Debug("connecting to daemon",
			zap.String("socket", c.socketPath),
			zap.Int("attempt", attempt),
		)

		dialer := net.Dialer{}
		conn, err := dialer.DialContext(ctx, "unix", c.socketPath)
		if err != nil {
			lastErr = err
			c.logger.Warn("connection attempt failed",
				zap.Int("attempt", attempt),
				zap.Error(err),
			)

			if attempt < MaxRetries {
				select {
				case <-ctx.Done():
					return ctx.Err()
				case <-time.After(RetryDelay):
					continue
				}
			}
			continue
		}

		c.conn = conn
		c.buf = c.buf[:0] // Clear buffer
		c.logger.Info("connected to daemon",
			zap.String("socket", c.socketPath),
		)
		return nil
	}

	return fmt.Errorf("%w: %v", ErrConnectionFailed, lastErr)
}

// Disconnect closes the connection to the daemon.
func (c *Client) Disconnect() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.disconnectLocked()
}

func (c *Client) disconnectLocked() {
	if c.conn != nil {
		c.conn.Close()
		c.conn = nil
		c.buf = c.buf[:0]
		c.logger.Debug("disconnected from daemon")
	}
}

// IsConnected returns true if connected to the daemon.
func (c *Client) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.conn != nil
}

// SendAndWait sends a command to the daemon and waits for a decision.
// This is the main interface for the courier to communicate with the daemon.
//
// The method:
// 1. Generates a new command ID (UUID)
// 2. Sends a CommandFrame with the encrypted payload
// 3. Waits for a DaemonDecisionFrame response (with timeout)
// 4. Verifies the command ID matches
// 5. Returns the decision and any result data
func (c *Client) SendAndWait(ctx context.Context, payload []byte) (*Response, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	// Ensure we're connected
	if c.conn == nil {
		if err := c.connectLocked(ctx); err != nil {
			return nil, err
		}
	}

	// Generate command ID
	commandID := uuid.New()

	c.logger.Debug("sending command to daemon",
		zap.String("command_id", commandID.String()),
		zap.Int("payload_len", len(payload)),
	)

	// Build and send CommandFrame
	frame := &protocol.CommandFrame{
		CommandID:        commandID,
		Flags:            0,
		EncryptedPayload: payload,
	}

	encoded := frame.Encode()
	if err := c.writeAll(encoded); err != nil {
		c.disconnectLocked()
		return nil, fmt.Errorf("failed to send command: %w", err)
	}

	// Wait for response with timeout
	response, err := c.readDecision(ctx, commandID)
	if err != nil {
		c.disconnectLocked()
		return nil, err
	}

	c.logger.Debug("received decision from daemon",
		zap.String("command_id", commandID.String()),
		zap.String("decision", response.Decision.String()),
	)

	return response, nil
}

// Response contains the daemon's decision for a command.
type Response struct {
	CommandID uuid.UUID
	Decision  protocol.Decision
	Result    []byte
}

// writeAll writes all bytes to the connection.
func (c *Client) writeAll(data []byte) error {
	deadline := time.Now().Add(c.timeout)
	if err := c.conn.SetWriteDeadline(deadline); err != nil {
		return err
	}

	written := 0
	for written < len(data) {
		n, err := c.conn.Write(data[written:])
		if err != nil {
			return err
		}
		written += n
	}
	return nil
}

// readDecision reads a DaemonDecisionFrame from the connection.
func (c *Client) readDecision(ctx context.Context, expectedID uuid.UUID) (*Response, error) {
	deadline := time.Now().Add(c.timeout)
	if err := c.conn.SetReadDeadline(deadline); err != nil {
		return nil, err
	}

	readBuf := make([]byte, ReadBufSize)

	for {
		// Check context cancellation
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		// Try to parse a complete frame from buffer
		frameData, consumed, err := protocol.ReadFrame(c.buf)
		if err == nil {
			// Successfully parsed a frame
			decision, err := protocol.ParseDaemonDecision(frameData)
			if err != nil {
				return nil, fmt.Errorf("failed to parse decision: %w", err)
			}

			// Remove consumed bytes from buffer
			c.buf = c.buf[consumed:]

			// Verify command ID matches
			if decision.CommandID != expectedID {
				return nil, fmt.Errorf("%w: expected %s, got %s",
					ErrCommandIDMismatch, expectedID, decision.CommandID)
			}

			return &Response{
				CommandID: decision.CommandID,
				Decision:  decision.Decision,
				Result:    decision.Result,
			}, nil
		}

		if !errors.Is(err, protocol.ErrIncompleteFrame) {
			return nil, fmt.Errorf("frame read error: %w", err)
		}

		// Need more data - read from connection
		n, err := c.conn.Read(readBuf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				return nil, ErrTimeout
			}
			return nil, fmt.Errorf("read error: %w", err)
		}

		// Append to buffer
		c.buf = append(c.buf, readBuf[:n]...)
	}
}

// Close closes the client and releases resources.
func (c *Client) Close() error {
	c.Disconnect()
	return nil
}
