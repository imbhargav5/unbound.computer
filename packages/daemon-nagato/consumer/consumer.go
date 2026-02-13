// Package consumer provides the command consumer transport for Nagato.
//
// The consumer subscribes to a device-specific channel via daemon-ably and
// forwards encrypted command payloads to the courier.
package consumer

import (
	"context"
	"errors"
	"sync"
	"time"

	"go.uber.org/zap"

	ablyclient "github.com/unbound-computer/daemon-ably-client/client"
)

var (
	ErrNotConnected = errors.New("not connected to daemon-ably")
	ErrClosed       = errors.New("consumer closed")
)

// Message represents a message received from daemon-ably.
type Message struct {
	// ID is the unique message identifier from the message transport.
	ID string

	// Payload is the encrypted command data.
	Payload []byte
}

// Consumer receives messages from a channel through daemon-ably.
type Consumer struct {
	client         transportClient
	channelName    string
	eventName      string
	subscriptionID string
	logger         *zap.Logger

	messages chan *Message
	errors   chan error

	mu              sync.Mutex
	closed          bool
	forwardersReady bool
	closedCh        chan struct{}
	wg              sync.WaitGroup
}

type transportClient interface {
	Connect(context.Context) error
	Subscribe(context.Context, ablyclient.Subscription) error
	PublishAck(context.Context, string, string, []byte, time.Duration) error
	Messages() <-chan *ablyclient.Message
	Errors() <-chan error
	Close() error
	IsConnected() bool
}

// Options configures the Consumer.
type Options struct {
	// AblySocketPath is the Unix socket path for daemon-ably.
	AblySocketPath string

	// ChannelName is the channel to subscribe to.
	ChannelName string

	// EventName is the event name to process.
	// If empty, all events are accepted.
	EventName string

	// SubscriptionID identifies this consumer in daemon-ably.
	SubscriptionID string

	// Logger is the zap logger instance.
	Logger *zap.Logger

	// BufferSize is the size of the message channel buffer.
	// Default is 1 to maintain one-in-flight semantics.
	BufferSize int
}

// New creates a new consumer.
func New(opts Options) (*Consumer, error) {
	if opts.Logger == nil {
		opts.Logger = zap.NewNop()
	}
	if opts.BufferSize <= 0 {
		opts.BufferSize = 1
	}
	if opts.SubscriptionID == "" {
		opts.SubscriptionID = "nagato"
	}

	client, err := ablyclient.New(opts.AblySocketPath)
	if err != nil {
		return nil, err
	}

	return newWithClient(client, opts), nil
}

func newWithClient(client transportClient, opts Options) *Consumer {
	if opts.Logger == nil {
		opts.Logger = zap.NewNop()
	}
	if opts.BufferSize <= 0 {
		opts.BufferSize = 1
	}
	if opts.SubscriptionID == "" {
		opts.SubscriptionID = "nagato"
	}

	return &Consumer{
		client:         client,
		channelName:    opts.ChannelName,
		eventName:      opts.EventName,
		subscriptionID: opts.SubscriptionID,
		logger:         opts.Logger,
		messages:       make(chan *Message, opts.BufferSize),
		errors:         make(chan error, 8),
		closedCh:       make(chan struct{}),
	}
}

// Connect establishes connection and subscribes to the configured channel.
func (c *Consumer) Connect(ctx context.Context) error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return ErrClosed
	}
	c.mu.Unlock()

	c.logger.Info("connecting to daemon-ably",
		zap.String("channel", c.channelName),
		zap.String("event", c.eventName),
	)

	if err := c.client.Connect(ctx); err != nil {
		return err
	}

	if err := c.client.Subscribe(ctx, ablyclient.Subscription{
		SubscriptionID: c.subscriptionID,
		Channel:        c.channelName,
		Event:          c.eventName,
	}); err != nil {
		return err
	}

	c.startForwardersOnce()
	c.logger.Info("consumer subscribed", zap.String("subscription_id", c.subscriptionID))
	return nil
}

// Receive returns the inbound message channel.
func (c *Consumer) Receive() <-chan *Message {
	return c.messages
}

// Publish sends an event on the configured command channel using publish.ack.v1.
func (c *Consumer) Publish(ctx context.Context, eventName string, payload []byte) error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return ErrClosed
	}
	c.mu.Unlock()

	if !c.client.IsConnected() {
		return ErrNotConnected
	}

	return c.client.PublishAck(ctx, c.channelName, eventName, payload, 0)
}

// Errors returns asynchronous transport/protocol errors.
func (c *Consumer) Errors() <-chan error {
	return c.errors
}

// Close shuts down the consumer and releases resources.
func (c *Consumer) Close() error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed = true
	close(c.closedCh)
	c.mu.Unlock()

	c.logger.Info("closing consumer")
	_ = c.client.Close()

	c.wg.Wait()
	close(c.messages)
	close(c.errors)
	return nil
}

// IsConnected reports whether the underlying daemon-ably transport is connected.
func (c *Consumer) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.closed {
		return false
	}
	return c.client.IsConnected()
}

func (c *Consumer) startForwardersOnce() {
	c.mu.Lock()
	if c.forwardersReady {
		c.mu.Unlock()
		return
	}
	c.forwardersReady = true
	c.wg.Add(2)
	c.mu.Unlock()

	go c.forwardMessages()
	go c.forwardErrors()
}

func (c *Consumer) forwardMessages() {
	defer c.wg.Done()

	source := c.client.Messages()
	for {
		select {
		case <-c.closedCh:
			return
		case message := <-source:
			if message == nil {
				continue
			}

			out := &Message{
				ID:      message.MessageID,
				Payload: message.Payload,
			}

			// Intentional blocking semantics preserve one-in-flight behavior.
			select {
			case c.messages <- out:
			case <-c.closedCh:
				return
			}
		}
	}
}

func (c *Consumer) forwardErrors() {
	defer c.wg.Done()

	source := c.client.Errors()
	for {
		select {
		case <-c.closedCh:
			return
		case err := <-source:
			if err == nil {
				continue
			}
			select {
			case c.errors <- err:
			case <-c.closedCh:
				return
			}
		}
	}
}
