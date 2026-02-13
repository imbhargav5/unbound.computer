// Package courier implements the main orchestration loop for Nagato.
//
// The courier is responsible for:
// 1. Receiving messages from Ably (one at a time)
// 2. Forwarding encrypted payloads to the daemon
// 3. Waiting for the daemon's decision
// 4. Handling timeout fail-open behavior
//
// # Key Invariants
//
//   - One-in-flight: Only one message is processed at a time
//   - ACK-gated: Messages are only considered processed when daemon responds OR timeout occurs (fail-open)
//   - Content-agnostic: Payloads are never inspected or modified
//   - Crash-safe: No persistent state; recovery handled by Ably message redelivery
package courier

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/unbound-computer/daemon-nagato/client"
	"github.com/unbound-computer/daemon-nagato/config"
	"github.com/unbound-computer/daemon-nagato/consumer"
	"github.com/unbound-computer/daemon-nagato/protocol"
)

const (
	// Error recovery delays
	ConnectionErrorDelay = time.Second
	ProtocolErrorDelay   = 100 * time.Millisecond

	// Event emitted by the machine after command handling.
	RemoteCommandAckEvent = "remote.command.ack.v1"
)

const (
	AckStatusAccepted = "accepted"
	AckStatusRejected = "rejected"
	AckStatusTimeout  = "timeout"
)

var (
	ErrShutdown = errors.New("courier shutdown")
)

type commandAckPayload struct {
	SchemaVersion int    `json:"schema_version"`
	CommandID     string `json:"command_id"`
	Status        string `json:"status"`
	CreatedAtMS   int64  `json:"created_at_ms"`
	ResultB64     string `json:"result_b64,omitempty"`
}

// Courier orchestrates message flow between Ably and the daemon.
type Courier struct {
	cfg      *config.Config
	consumer *consumer.Consumer
	daemon   *client.Client
	logger   *zap.Logger

	mu       sync.Mutex
	running  bool
	cancelFn context.CancelFunc
}

// New creates a new Courier instance.
func New(cfg *config.Config, logger *zap.Logger) (*Courier, error) {
	if logger == nil {
		logger = zap.NewNop()
	}

	// Create Ably consumer
	cons, err := consumer.New(consumer.Options{
		AblySocketPath: cfg.AblySocketPath,
		ChannelName:    cfg.ChannelName,
		EventName:      cfg.EventName,
		SubscriptionID: cfg.ConsumerName,
		Logger:         logger.Named("consumer"),
		BufferSize:     1, // One-in-flight
	})
	if err != nil {
		return nil, err
	}

	// Create daemon client
	daemonClient := client.NewClient(
		cfg.SocketPath,
		cfg.DaemonTimeout,
		logger.Named("daemon"),
	)

	return &Courier{
		cfg:      cfg,
		consumer: cons,
		daemon:   daemonClient,
		logger:   logger,
	}, nil
}

// Run starts the courier loop.
// This blocks until the context is cancelled or an unrecoverable error occurs.
func (c *Courier) Run(ctx context.Context) error {
	c.mu.Lock()
	if c.running {
		c.mu.Unlock()
		return errors.New("courier already running")
	}
	c.running = true

	ctx, cancel := context.WithCancel(ctx)
	c.cancelFn = cancel
	c.mu.Unlock()

	defer func() {
		c.mu.Lock()
		c.running = false
		c.cancelFn = nil
		c.mu.Unlock()
	}()

	c.logger.Info("starting courier",
		zap.String("device_id", c.cfg.DeviceID),
		zap.String("channel", c.cfg.ChannelName),
		zap.String("event", c.cfg.EventName),
		zap.String("socket", c.cfg.SocketPath),
		zap.String("consumer", c.cfg.ConsumerName),
		zap.Duration("timeout", c.cfg.DaemonTimeout),
	)

	// Connect to Ably
	if err := c.consumer.Connect(ctx); err != nil {
		return err
	}
	defer c.consumer.Close()

	// Connect to daemon
	if err := c.daemon.Connect(ctx); err != nil {
		c.logger.Warn("initial daemon connection failed, will retry",
			zap.Error(err),
		)
		// Don't fail - we'll retry on each message
	}
	defer c.daemon.Close()

	c.logger.Info("courier started, entering main loop")

	// Main loop
	return c.runLoop(ctx)
}

// runLoop is the main message processing loop.
func (c *Courier) runLoop(ctx context.Context) error {
	messages := c.consumer.Receive()

	for {
		select {
		case <-ctx.Done():
			c.logger.Info("courier shutting down",
				zap.Error(ctx.Err()),
			)
			return ErrShutdown

		case msg, ok := <-messages:
			if !ok {
				c.logger.Info("message channel closed")
				return ErrShutdown
			}

			if err := c.processMessage(ctx, msg); err != nil {
				c.logger.Error("error processing message",
					zap.String("message_id", msg.ID),
					zap.Error(err),
				)

				// Apply error recovery delay
				select {
				case <-ctx.Done():
					return ErrShutdown
				case <-time.After(ProtocolErrorDelay):
				}
			}
		}
	}
}

// processMessage handles a single message from Ably.
func (c *Courier) processMessage(ctx context.Context, msg *consumer.Message) error {
	c.logger.Debug("processing message",
		zap.String("message_id", msg.ID),
		zap.Int("payload_len", len(msg.Payload)),
	)

	// Ensure daemon connection
	if !c.daemon.IsConnected() {
		c.logger.Debug("reconnecting to daemon")
		if err := c.daemon.Connect(ctx); err != nil {
			c.logger.Error("failed to connect to daemon",
				zap.Error(err),
			)
			// Message will be redelivered by Ably on reconnect
			return err
		}
	}

	// Send to daemon and wait for decision
	commandID, response, err := c.daemon.SendAndWait(ctx, msg.Payload)
	if err != nil {
		// Check if it's a timeout (fail-open)
		if errors.Is(err, client.ErrTimeout) {
			c.logger.Warn("daemon timeout, applying fail-open",
				zap.String("message_id", msg.ID),
				zap.Duration("timeout", c.cfg.DaemonTimeout),
			)
			c.publishAck(ctx, commandID, msg.ID, AckStatusTimeout, nil)
			// Fail-open: consider message processed to prevent blocking
			// The daemon may have processed it but failed to respond
			return nil
		}

		// Other errors
		c.logger.Error("daemon communication error",
			zap.String("message_id", msg.ID),
			zap.Error(err),
		)
		return err
	}

	// Log daemon's decision
	switch response.Decision {
	case protocol.AckMessage:
		c.logger.Info("daemon processed message successfully",
			zap.String("message_id", msg.ID),
		)
		c.publishAck(ctx, response.CommandID, msg.ID, AckStatusAccepted, response.Result)

	case protocol.DoNotAck:
		c.logger.Warn("daemon rejected message",
			zap.String("message_id", msg.ID),
		)
		c.publishAck(ctx, response.CommandID, msg.ID, AckStatusRejected, response.Result)
		// Message may be redelivered depending on Ably configuration

	default:
		c.logger.Error("unexpected decision",
			zap.String("message_id", msg.ID),
			zap.Uint8("decision", uint8(response.Decision)),
		)
	}

	return nil
}

func (c *Courier) publishAck(
	ctx context.Context,
	commandID uuid.UUID,
	ablyMessageID string,
	status string,
	result []byte,
) {
	if commandID == uuid.Nil {
		c.logger.Warn("skipping command ack publish due to missing command_id",
			zap.String("ably_message_id", ablyMessageID),
			zap.String("status", status),
		)
		return
	}

	payload := commandAckPayload{
		SchemaVersion: 1,
		CommandID:     commandID.String(),
		Status:        status,
		CreatedAtMS:   time.Now().UnixMilli(),
	}
	if len(result) > 0 {
		payload.ResultB64 = base64.StdEncoding.EncodeToString(result)
	}

	encoded, err := json.Marshal(payload)
	if err != nil {
		c.logger.Warn("failed to encode command ack payload",
			zap.String("ably_message_id", ablyMessageID),
			zap.String("command_id", commandID.String()),
			zap.Error(err),
		)
		return
	}

	if err := c.consumer.Publish(ctx, RemoteCommandAckEvent, encoded); err != nil {
		c.logger.Warn("failed to publish command ack",
			zap.String("ably_message_id", ablyMessageID),
			zap.String("command_id", commandID.String()),
			zap.String("status", status),
			zap.Error(err),
		)
	}
}

// Stop gracefully stops the courier.
func (c *Courier) Stop() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cancelFn != nil {
		c.logger.Info("stopping courier")
		c.cancelFn()
	}
}

// IsRunning returns true if the courier is currently running.
func (c *Courier) IsRunning() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.running
}
