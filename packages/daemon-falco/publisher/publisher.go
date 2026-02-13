// Package publisher provides the transport publisher for Falco.
//
// The publisher receives side-effects from the daemon and publishes them
// through daemon-ably for real-time sync to other devices/clients.
package publisher

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"go.uber.org/zap"

	ablyclient "github.com/unbound-computer/daemon-ably-client/client"
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
	ErrNotConnected   = errors.New("not connected to daemon-ably")
	ErrClosed         = errors.New("publisher closed")
	ErrPublishFailed  = errors.New("publish failed after retries")
	ErrInvalidEvent   = errors.New("event name is required")
	ErrInvalidChannel = errors.New("channel name is required")
)

// Publisher publishes side-effects via daemon-ably.
type Publisher struct {
	client         ipcClient
	channelName    string
	publishTimeout time.Duration
	logger         *zap.Logger

	mu       sync.Mutex
	closed   bool
	closedCh chan struct{}
}

type ipcClient interface {
	Connect(context.Context) error
	Publish(context.Context, string, string, []byte, time.Duration) error
	Close() error
	IsConnected() bool
}

// Options configures the Publisher.
type Options struct {
	// AblySocketPath is the Unix socket path for daemon-ably.
	AblySocketPath string

	// DeviceID identifies this sidecar instance in logs.
	DeviceID string

	// ChannelName is the default channel to publish to.
	ChannelName string

	// PublishTimeout is the timeout for each publish operation.
	PublishTimeout time.Duration

	// Logger is the zap logger instance.
	Logger *zap.Logger
}

// New creates a new publisher.
func New(opts Options) (*Publisher, error) {
	if opts.Logger == nil {
		opts.Logger = zap.NewNop()
	}
	if opts.PublishTimeout <= 0 {
		opts.PublishTimeout = DefaultPublishTimeout
	}

	client, err := ablyclient.New(opts.AblySocketPath)
	if err != nil {
		return nil, err
	}

	return newWithClient(client, opts), nil
}

func newWithClient(client ipcClient, opts Options) *Publisher {
	return &Publisher{
		client:         client,
		channelName:    opts.ChannelName,
		publishTimeout: opts.PublishTimeout,
		logger: opts.Logger.With(
			zap.String("device_id", opts.DeviceID),
		),
		closedCh: make(chan struct{}),
	}
}

// Connect establishes connection to daemon-ably.
func (p *Publisher) Connect(ctx context.Context) error {
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return ErrClosed
	}
	p.mu.Unlock()

	p.logger.Info("connecting to daemon-ably", zap.String("channel", p.channelName))
	if err := p.client.Connect(ctx); err != nil {
		return err
	}
	p.logger.Info("publisher ready", zap.String("channel", p.channelName))
	return nil
}

// Publish publishes a side-effect to daemon-ably.
// Returns nil on success, or an error if the publish failed after retries.
func (p *Publisher) Publish(ctx context.Context, effect *sideeffect.SideEffect) error {
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

// PublishJSON publishes raw JSON payload with the given event name.
func (p *Publisher) PublishJSON(ctx context.Context, eventName string, jsonPayload []byte) error {
	return p.PublishJSONToChannel(ctx, p.channelName, eventName, jsonPayload)
}

// PublishJSONToChannel publishes raw JSON payload to a specific channel.
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
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return ErrClosed
	}
	publishTimeout := p.publishTimeout
	p.mu.Unlock()

	var lastErr error
	for attempt := 1; attempt <= MaxRetries; attempt++ {
		pubCtx, cancel := context.WithTimeout(ctx, publishTimeout)
		err := p.client.Publish(pubCtx, channelName, eventName, payload, publishTimeout)
		cancel()

		if err == nil {
			p.logger.Debug("publish successful",
				zap.String("channel", channelName),
				zap.String("event", eventName),
				zap.Int("attempt", attempt),
			)
			return nil
		}

		if errors.Is(err, ablyclient.ErrClosed) {
			return ErrClosed
		}
		if errors.Is(err, ablyclient.ErrNotConnected) {
			lastErr = ErrNotConnected
		} else {
			lastErr = err
		}

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
	return p.client.Close()
}

// IsConnected returns true if connected to daemon-ably.
func (p *Publisher) IsConnected() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.closed {
		return false
	}
	return p.client.IsConnected()
}
