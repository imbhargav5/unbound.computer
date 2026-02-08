// Package publisher provides the Ably publisher for Falco.
//
// The publisher receives side-effects from the daemon and publishes them
// to Ably for real-time sync to other devices/clients.
package publisher

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/ably/ably-go/ably"
	"go.uber.org/zap"

	"github.com/unbound-computer/daemon-falco/sideeffect"
)

const (
	// Default publish timeout
	DefaultPublishTimeout = 5 * time.Second

	// Retry settings
	MaxRetries = 3
	RetryDelay = 500 * time.Millisecond
)

var (
	ErrNotConnected   = errors.New("not connected to Ably")
	ErrClosed         = errors.New("publisher closed")
	ErrPublishFailed  = errors.New("publish failed after retries")
	ErrInvalidEvent   = errors.New("event name is required")
	ErrInvalidChannel = errors.New("channel name is required")
)

// Publisher publishes side-effects to Ably.
type Publisher struct {
	client         *ably.Realtime
	channel        *ably.RealtimeChannel
	channels       map[string]*ably.RealtimeChannel
	channelName    string
	publishTimeout time.Duration
	logger         *zap.Logger

	mu       sync.Mutex
	closed   bool
	closedCh chan struct{}
}

// Options configures the Publisher.
type Options struct {
	// AblyKey is the Ably API key.
	AblyKey string

	// ChannelName is the Ably channel to publish to.
	ChannelName string

	// PublishTimeout is the timeout for each publish operation.
	PublishTimeout time.Duration

	// Logger is the zap logger instance.
	Logger *zap.Logger
}

// New creates a new Ably publisher.
func New(opts Options) (*Publisher, error) {
	if opts.Logger == nil {
		opts.Logger = zap.NewNop()
	}
	if opts.PublishTimeout <= 0 {
		opts.PublishTimeout = DefaultPublishTimeout
	}

	client, err := ably.NewRealtime(
		ably.WithKey(opts.AblyKey),
		ably.WithAutoConnect(false),
	)
	if err != nil {
		return nil, err
	}

	return &Publisher{
		client:         client,
		channels:       make(map[string]*ably.RealtimeChannel),
		channelName:    opts.ChannelName,
		publishTimeout: opts.PublishTimeout,
		logger:         opts.Logger,
		closedCh:       make(chan struct{}),
	}, nil
}

// Connect establishes connection to Ably.
func (p *Publisher) Connect(ctx context.Context) error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		return ErrClosed
	}

	p.logger.Info("connecting to Ably",
		zap.String("channel", p.channelName),
	)

	// Connect to Ably
	p.client.Connect()

	// Wait for connection
	connected := make(chan struct{})
	var connErr error

	p.client.Connection.OnAll(func(change ably.ConnectionStateChange) {
		p.logger.Debug("connection state change",
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
	case <-ctx.Done():
		return ctx.Err()
	case <-connected:
		if connErr != nil {
			return connErr
		}
	}

	p.logger.Info("connected to Ably",
		zap.String("connection_id", p.client.Connection.ID()),
	)

	// Get default channel
	p.channel = p.getChannelLocked(p.channelName)

	p.logger.Info("publisher ready",
		zap.String("channel", p.channelName),
	)

	return nil
}

// Publish publishes a side-effect to Ably.
// Returns nil on success, or an error if the publish failed after retries.
func (p *Publisher) Publish(ctx context.Context, effect *sideeffect.SideEffect) error {
	// Serialize side-effect to JSON
	payload, err := json.Marshal(effect)
	if err != nil {
		return err
	}

	eventName := string(effect.Type)
	if effect.Event != "" {
		eventName = effect.Event
	}
	if eventName == "" {
		return ErrInvalidEvent
	}

	channelName := p.channelName
	if effect.Channel != "" {
		channelName = effect.Channel
	}
	if channelName == "" {
		return ErrInvalidChannel
	}

	publishPayload := payload
	if len(effect.Payload) > 0 {
		publishPayload = effect.Payload
	}

	p.logger.Debug("publishing side-effect",
		zap.String("channel", channelName),
		zap.String("type", eventName),
		zap.String("session_id", effect.SessionID),
		zap.Int("payload_len", len(publishPayload)),
	)

	return p.publishToChannel(ctx, channelName, eventName, publishPayload)
}

// PublishJSON publishes raw JSON payload to Ably with the given event name.
func (p *Publisher) PublishJSON(ctx context.Context, eventName string, jsonPayload []byte) error {
	return p.PublishJSONToChannel(ctx, p.channelName, eventName, jsonPayload)
}

// PublishJSONToChannel publishes raw JSON payload to a specific Ably channel.
func (p *Publisher) PublishJSONToChannel(
	ctx context.Context,
	channelName string,
	eventName string,
	jsonPayload []byte,
) error {
	if channelName == "" {
		return ErrInvalidChannel
	}
	if eventName == "" {
		return ErrInvalidEvent
	}

	p.logger.Debug("publishing JSON",
		zap.String("channel", channelName),
		zap.String("event", eventName),
		zap.Int("payload_len", len(jsonPayload)),
	)

	return p.publishToChannel(ctx, channelName, eventName, jsonPayload)
}

func (p *Publisher) publishToChannel(
	ctx context.Context,
	channelName string,
	eventName string,
	payload []byte,
) error {
	channel, publishTimeout, err := p.channelForPublish(channelName)
	if err != nil {
		return err
	}

	// Retry loop
	var lastErr error
	for attempt := 1; attempt <= MaxRetries; attempt++ {
		pubCtx, cancel := context.WithTimeout(ctx, publishTimeout)

		err := channel.Publish(pubCtx, eventName, payload)
		cancel()

		if err == nil {
			p.logger.Debug("publish successful",
				zap.String("channel", channelName),
				zap.String("event", eventName),
				zap.Int("attempt", attempt),
			)
			return nil
		}

		lastErr = err
		p.logger.Warn("publish attempt failed",
			zap.String("channel", channelName),
			zap.String("event", eventName),
			zap.Int("attempt", attempt),
			zap.Error(err),
		)

		if attempt < MaxRetries {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-p.closedCh:
				return ErrClosed
			case <-time.After(RetryDelay):
			}
		}
	}

	p.logger.Error("publish failed after retries",
		zap.String("channel", channelName),
		zap.String("event", eventName),
		zap.Int("max_retries", MaxRetries),
		zap.Error(lastErr),
	)

	if lastErr != nil {
		return fmt.Errorf("%w: %v", ErrPublishFailed, lastErr)
	}
	return ErrPublishFailed
}

func (p *Publisher) channelForPublish(channelName string) (*ably.RealtimeChannel, time.Duration, error) {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		return nil, 0, ErrClosed
	}
	if p.channel == nil {
		return nil, 0, ErrNotConnected
	}

	channel := p.getChannelLocked(channelName)
	return channel, p.publishTimeout, nil
}

func (p *Publisher) getChannelLocked(channelName string) *ably.RealtimeChannel {
	if channelName == "" {
		channelName = p.channelName
	}
	if ch, ok := p.channels[channelName]; ok {
		return ch
	}
	ch := p.client.Channels.Get(channelName)
	p.channels[channelName] = ch
	return ch
}

// Close shuts down the publisher and releases resources.
func (p *Publisher) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.closed {
		return nil
	}
	p.closed = true
	close(p.closedCh)

	p.logger.Info("closing publisher")

	if p.client != nil {
		p.client.Close()
	}

	return nil
}

// IsConnected returns true if connected to Ably.
func (p *Publisher) IsConnected() bool {
	p.mu.Lock()
	defer p.mu.Unlock()

	if p.client == nil {
		return false
	}
	return p.client.Connection.State() == ably.ConnectionStateConnected
}
