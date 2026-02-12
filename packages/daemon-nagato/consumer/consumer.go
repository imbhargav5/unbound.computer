// Package consumer provides the Ably message consumer for Nagato.
//
// The consumer subscribes to a device-specific Ably channel and receives
// encrypted command payloads from remote clients.
package consumer

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"

	"github.com/ably/ably-go/ably"
	"go.uber.org/zap"
)

var (
	ErrNotConnected = errors.New("not connected to Ably")
	ErrClosed       = errors.New("consumer closed")
)

// Message represents a message received from Ably.
type Message struct {
	// ID is the unique message identifier from Ably.
	ID string

	// Payload is the encrypted command data.
	Payload []byte
}

// Consumer receives messages from an Ably channel.
type Consumer struct {
	client      *ably.Realtime
	channel     *ably.RealtimeChannel
	channelName string
	eventName   string
	logger      *zap.Logger

	messages chan *Message
	errors   chan error

	mu       sync.Mutex
	closed   bool
	closedCh chan struct{}
	unsub    func()
	cancelFn context.CancelFunc
}

// Options configures the Consumer.
type Options struct {
	// BrokerSocketPath is the Unix socket path for local Ably token broker.
	BrokerSocketPath string

	// BrokerToken authenticates Nagato to the local token broker.
	BrokerToken string

	// DeviceID identifies this client in Ably token requests.
	DeviceID string

	// ChannelName is the Ably channel to subscribe to.
	ChannelName string

	// EventName is the Ably event name to process.
	// If empty, all events are accepted.
	EventName string

	// Logger is the zap logger instance.
	Logger *zap.Logger

	// BufferSize is the size of the message channel buffer.
	// Default is 1 to maintain one-in-flight semantics.
	BufferSize int
}

// New creates a new Ably consumer.
func New(opts Options) (*Consumer, error) {
	if opts.Logger == nil {
		opts.Logger = zap.NewNop()
	}
	if opts.BufferSize <= 0 {
		opts.BufferSize = 1 // One-in-flight by default
	}

	client, err := ably.NewRealtime(
		ably.WithClientID(opts.DeviceID),
		ably.WithAuthCallback(func(ctx context.Context, _ ably.TokenParams) (ably.Tokener, error) {
			return requestBrokerToken(
				ctx,
				opts.BrokerSocketPath,
				opts.BrokerToken,
				opts.DeviceID,
				"daemon_nagato",
			)
		}),
		ably.WithAutoConnect(false), // We'll connect manually
	)
	if err != nil {
		return nil, err
	}

	return &Consumer{
		client:      client,
		channelName: opts.ChannelName,
		eventName:   opts.EventName,
		logger:      opts.Logger,
		messages:    make(chan *Message, opts.BufferSize),
		errors:      make(chan error, 1),
		closedCh:    make(chan struct{}),
	}, nil
}

// Connect establishes connection to Ably and subscribes to the channel.
func (c *Consumer) Connect(ctx context.Context) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed {
		return ErrClosed
	}

	c.logger.Info("connecting to Ably",
		zap.String("channel", c.channelName),
	)

	// Connect to Ably
	c.client.Connect()

	// Wait for connection
	connCtx, cancel := context.WithCancel(ctx)
	c.cancelFn = cancel

	connected := make(chan struct{})
	var connErr error

	c.client.Connection.OnAll(func(change ably.ConnectionStateChange) {
		c.logger.Debug("connection state change",
			zap.Any("previous", change.Previous),
			zap.Any("current", change.Current),
		)

		switch change.Current {
		case ably.ConnectionStateConnected:
			select {
			case connected <- struct{}{}:
			default:
			}
		case ably.ConnectionStateFailed:
			connErr = change.Reason
			select {
			case connected <- struct{}{}:
			default:
			}
		}
	})

	select {
	case <-connCtx.Done():
		return connCtx.Err()
	case <-connected:
		if connErr != nil {
			return connErr
		}
	}

	c.logger.Info("connected to Ably",
		zap.String("connection_id", c.client.Connection.ID()),
	)

	// Get channel and attach
	c.channel = c.client.Channels.Get(c.channelName)

	if err := c.channel.Attach(ctx); err != nil {
		return err
	}

	c.logger.Info("attached to channel",
		zap.String("channel", c.channelName),
	)

	// Subscribe to all messages
	unsub, err := c.channel.SubscribeAll(ctx, c.handleMessage)
	if err != nil {
		return err
	}
	c.unsub = unsub

	c.logger.Info("subscribed to channel",
		zap.String("channel", c.channelName),
	)

	return nil
}

// handleMessage processes incoming Ably messages.
func (c *Consumer) handleMessage(msg *ably.Message) {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	c.mu.Unlock()

	c.logger.Debug("received message",
		zap.String("id", msg.ID),
		zap.String("name", msg.Name),
	)

	if c.eventName != "" && msg.Name != c.eventName {
		c.logger.Debug("skipping non-command event",
			zap.String("id", msg.ID),
			zap.String("name", msg.Name),
			zap.String("expected_event", c.eventName),
		)
		return
	}

	// Extract payload - Ably messages can have various data types
	var payload []byte
	switch data := msg.Data.(type) {
	case []byte:
		payload = data
	case string:
		payload = []byte(data)
	default:
		marshaled, err := json.Marshal(data)
		if err != nil {
			c.logger.Error("unexpected message data type",
				zap.String("id", msg.ID),
				zap.Any("data_type", data),
				zap.Error(err),
			)
			return
		}
		payload = marshaled
		c.logger.Debug("marshaled structured message data",
			zap.String("id", msg.ID),
			zap.Int("payload_len", len(payload)),
		)
	}

	message := &Message{
		ID:      msg.ID,
		Payload: payload,
	}

	// Send to channel - this blocks if buffer is full (backpressure)
	select {
	case c.messages <- message:
	case <-c.closedCh:
		return
	}
}

// Receive returns a channel for receiving messages.
// Only one message is delivered at a time (one-in-flight guarantee).
func (c *Consumer) Receive() <-chan *Message {
	return c.messages
}

// Publish sends a message to the currently attached channel.
func (c *Consumer) Publish(ctx context.Context, eventName string, payload []byte) error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return ErrClosed
	}
	if c.channel == nil {
		c.mu.Unlock()
		return ErrNotConnected
	}
	channel := c.channel
	c.mu.Unlock()

	return channel.Publish(ctx, eventName, payload)
}

// Errors returns a channel for receiving errors.
func (c *Consumer) Errors() <-chan error {
	return c.errors
}

// Close shuts down the consumer and releases resources.
func (c *Consumer) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.closed {
		return nil
	}
	c.closed = true
	close(c.closedCh)

	c.logger.Info("closing consumer")

	if c.unsub != nil {
		c.unsub()
	}

	if c.cancelFn != nil {
		c.cancelFn()
	}

	if c.channel != nil {
		ctx := context.Background()
		if err := c.channel.Detach(ctx); err != nil {
			c.logger.Warn("error detaching channel", zap.Error(err))
		}
	}

	if c.client != nil {
		c.client.Close()
	}

	close(c.messages)
	close(c.errors)

	return nil
}

// ConnectionState returns the current Ably connection state.
func (c *Consumer) ConnectionState() ably.ConnectionState {
	if c.client == nil {
		return ably.ConnectionStateInitialized
	}
	return c.client.Connection.State()
}

// IsConnected returns true if connected to Ably.
func (c *Consumer) IsConnected() bool {
	return c.ConnectionState() == ably.ConnectionStateConnected
}

type brokerTokenRequest struct {
	BrokerToken string `json:"broker_token"`
	Audience    string `json:"audience"`
	DeviceID    string `json:"device_id"`
}

type brokerTokenResponse struct {
	OK           bool            `json:"ok"`
	TokenDetails json.RawMessage `json:"token_details"`
	Error        string          `json:"error"`
}

type brokerTokenDetails struct {
	Token      string `json:"token"`
	Expires    int64  `json:"expires"`
	ClientID   string `json:"clientId"`
	Issued     int64  `json:"issued"`
	Capability string `json:"capability"`
}

func requestBrokerToken(
	ctx context.Context,
	socketPath string,
	brokerToken string,
	deviceID string,
	audience string,
) (*ably.TokenDetails, error) {
	requestPayload, err := json.Marshal(brokerTokenRequest{
		BrokerToken: brokerToken,
		Audience:    audience,
		DeviceID:    deviceID,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to serialize broker request: %w", err)
	}

	dialer := net.Dialer{}
	conn, err := dialer.DialContext(ctx, "unix", socketPath)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Ably broker socket: %w", err)
	}
	defer conn.Close()

	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	if _, err := conn.Write(requestPayload); err != nil {
		return nil, fmt.Errorf("failed to write broker request: %w", err)
	}
	if unixConn, ok := conn.(*net.UnixConn); ok {
		_ = unixConn.CloseWrite()
	}

	responsePayload, err := io.ReadAll(conn)
	if err != nil {
		return nil, fmt.Errorf("failed to read broker response: %w", err)
	}

	var response brokerTokenResponse
	if err := json.Unmarshal(responsePayload, &response); err != nil {
		return nil, fmt.Errorf("invalid broker response: %w", err)
	}
	if !response.OK {
		if response.Error == "" {
			return nil, errors.New("broker rejected token request")
		}
		return nil, fmt.Errorf("broker rejected token request: %s", response.Error)
	}

	var tokenDetails brokerTokenDetails
	if err := json.Unmarshal(response.TokenDetails, &tokenDetails); err != nil {
		return nil, fmt.Errorf("invalid broker token details payload: %w", err)
	}
	if tokenDetails.Token == "" {
		return nil, errors.New("broker response missing token")
	}

	return &ably.TokenDetails{
		Token:      tokenDetails.Token,
		Expires:    tokenDetails.Expires,
		ClientID:   tokenDetails.ClientID,
		Issued:     tokenDetails.Issued,
		Capability: tokenDetails.Capability,
	}, nil
}
