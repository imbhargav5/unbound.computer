package client

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
)

const (
	opPublishRequest    = "publish.v1"
	opPublishAckRequest = "publish.ack.v1"
	opPublishAck        = "publish.ack.v1"
	opSubscribe         = "subscribe.v1"
	opSubscribeAck      = "subscribe.ack.v1"
	opMessage           = "message.v1"

	defaultDialTimeout   = 3 * time.Second
	defaultAckTimeout    = 5 * time.Second
	defaultMaxFrameBytes = 2 * 1024 * 1024
	envMaxFrameBytes     = "DAEMON_ABLY_MAX_FRAME_BYTES"
)

var (
	ErrClosed       = errors.New("ably client closed")
	ErrNotConnected = errors.New("ably client not connected")
	ErrTimeout      = errors.New("ably client request timed out")
)

// Message is an inbound subscription message pushed from daemon-ably.
type Message struct {
	SubscriptionID string
	MessageID      string
	Channel        string
	Event          string
	Payload        []byte
	ReceivedAtMS   int64
}

// Subscription defines a channel/event binding to receive messages from daemon-ably.
type Subscription struct {
	SubscriptionID string
	Channel        string
	Event          string
}

type requestAck struct {
	RequestID string `json:"request_id"`
	OK        bool   `json:"ok"`
	Error     string `json:"error,omitempty"`
}

type publishRequest struct {
	Op         string `json:"op"`
	RequestID  string `json:"request_id"`
	Channel    string `json:"channel"`
	Event      string `json:"event"`
	PayloadB64 string `json:"payload_b64"`
	TimeoutMS  int64  `json:"timeout_ms,omitempty"`
}

type publishAck struct {
	Op string `json:"op"`
	requestAck
}

type subscribeRequest struct {
	Op             string `json:"op"`
	RequestID      string `json:"request_id"`
	SubscriptionID string `json:"subscription_id"`
	Channel        string `json:"channel"`
	Event          string `json:"event,omitempty"`
}

type subscribeAck struct {
	Op string `json:"op"`
	requestAck
}

type messageEnvelope struct {
	Op             string `json:"op"`
	SubscriptionID string `json:"subscription_id"`
	MessageID      string `json:"message_id"`
	Channel        string `json:"channel"`
	Event          string `json:"event"`
	PayloadB64     string `json:"payload_b64"`
	ReceivedAtMS   int64  `json:"received_at_ms"`
}

type operationEnvelope struct {
	Op string `json:"op"`
}

// Client is a reconnecting NDJSON client for daemon-ably.
type Client struct {
	socketPath string
	dialFn     func(context.Context) (net.Conn, error)

	mu            sync.Mutex
	conn          net.Conn
	closed        bool
	reconnecting  bool
	pending       map[string]chan requestAck
	subscriptions map[string]Subscription

	writeMu       sync.Mutex
	maxFrameBytes int
	messages      chan *Message
	errors        chan error
}

// New builds a new client bound to the daemon-ably socket path.
func New(socketPath string) (*Client, error) {
	if socketPath == "" {
		return nil, fmt.Errorf("socket path is required")
	}

	maxFrameBytes, err := maxFrameBytesFromEnv()
	if err != nil {
		return nil, err
	}

	dialFn := func(ctx context.Context) (net.Conn, error) {
		dialer := net.Dialer{}
		return dialer.DialContext(ctx, "unix", socketPath)
	}

	return &Client{
		socketPath:    socketPath,
		dialFn:        dialFn,
		maxFrameBytes: maxFrameBytes,
		pending:       make(map[string]chan requestAck),
		subscriptions: make(map[string]Subscription),
		messages:      make(chan *Message, 32),
		errors:        make(chan error, 8),
	}, nil
}

func newWithDial(
	socketPath string,
	dialFn func(context.Context) (net.Conn, error),
) (*Client, error) {
	if socketPath == "" {
		return nil, fmt.Errorf("socket path is required")
	}
	if dialFn == nil {
		return nil, fmt.Errorf("dial function is required")
	}

	return &Client{
		socketPath:    socketPath,
		dialFn:        dialFn,
		maxFrameBytes: defaultMaxFrameBytes,
		pending:       make(map[string]chan requestAck),
		subscriptions: make(map[string]Subscription),
		messages:      make(chan *Message, 32),
		errors:        make(chan error, 8),
	}, nil
}

// Connect establishes the local IPC connection if needed.
func (c *Client) Connect(ctx context.Context) error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return ErrClosed
	}
	if c.conn != nil {
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	return c.dialAndStart(ctx)
}

// Publish sends a publish.v1 request and waits for a publish.ack.v1.
func (c *Client) Publish(
	ctx context.Context,
	channel string,
	event string,
	payload []byte,
	timeout time.Duration,
) error {
	return c.publish(ctx, opPublishRequest, channel, event, payload, timeout)
}

// PublishAck sends a publish.ack.v1 request and waits for a publish.ack.v1.
func (c *Client) PublishAck(
	ctx context.Context,
	channel string,
	event string,
	payload []byte,
	timeout time.Duration,
) error {
	return c.publish(ctx, opPublishAckRequest, channel, event, payload, timeout)
}

func (c *Client) publish(
	ctx context.Context,
	op string,
	channel string,
	event string,
	payload []byte,
	timeout time.Duration,
) error {
	if channel == "" {
		return fmt.Errorf("channel is required")
	}
	if event == "" {
		return fmt.Errorf("event is required")
	}

	if timeout <= 0 {
		timeout = defaultAckTimeout
	}

	if err := c.ensureConnected(ctx); err != nil {
		return err
	}

	requestID := uuid.NewString()
	ack, err := c.sendAndAwaitAck(ctx, publishRequest{
		Op:         op,
		RequestID:  requestID,
		Channel:    channel,
		Event:      event,
		PayloadB64: base64.StdEncoding.EncodeToString(payload),
		TimeoutMS:  timeout.Milliseconds(),
	}, requestID)
	if err != nil {
		// Single retry after reconnect attempt.
		if errors.Is(err, ErrNotConnected) {
			if reconnectErr := c.ensureConnected(ctx); reconnectErr == nil {
				retryRequestID := uuid.NewString()
				ack, err = c.sendAndAwaitAck(ctx, publishRequest{
					Op:         op,
					RequestID:  retryRequestID,
					Channel:    channel,
					Event:      event,
					PayloadB64: base64.StdEncoding.EncodeToString(payload),
					TimeoutMS:  timeout.Milliseconds(),
				}, retryRequestID)
			}
		}
		if err != nil {
			return err
		}
	}

	if !ack.OK {
		if ack.Error == "" {
			return fmt.Errorf("publish rejected")
		}
		return fmt.Errorf("publish rejected: %s", ack.Error)
	}

	return nil
}

// Subscribe registers a subscription on daemon-ably and replays it after reconnect.
func (c *Client) Subscribe(ctx context.Context, sub Subscription) error {
	if sub.SubscriptionID == "" {
		return fmt.Errorf("subscription id is required")
	}
	if sub.Channel == "" {
		return fmt.Errorf("subscription channel is required")
	}

	if err := c.ensureConnected(ctx); err != nil {
		return err
	}

	requestID := uuid.NewString()
	ack, err := c.sendAndAwaitAck(ctx, subscribeRequest{
		Op:             opSubscribe,
		RequestID:      requestID,
		SubscriptionID: sub.SubscriptionID,
		Channel:        sub.Channel,
		Event:          sub.Event,
	}, requestID)
	if err != nil {
		return err
	}
	if !ack.OK {
		if ack.Error == "" {
			return fmt.Errorf("subscription rejected")
		}
		return fmt.Errorf("subscription rejected: %s", ack.Error)
	}

	c.mu.Lock()
	if !c.closed {
		c.subscriptions[sub.SubscriptionID] = sub
	}
	c.mu.Unlock()

	return nil
}

// Messages returns decoded inbound subscription messages.
func (c *Client) Messages() <-chan *Message {
	return c.messages
}

// Errors returns asynchronous connection/protocol errors.
func (c *Client) Errors() <-chan error {
	return c.errors
}

// IsConnected reports whether the local daemon-ably socket is currently connected.
func (c *Client) IsConnected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.conn != nil && !c.closed
}

// Close tears down the client.
func (c *Client) Close() error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed = true
	conn := c.conn
	c.conn = nil
	pending := c.pending
	c.pending = make(map[string]chan requestAck)
	c.mu.Unlock()

	if conn != nil {
		_ = conn.Close()
	}

	for _, ch := range pending {
		select {
		case ch <- requestAck{OK: false, Error: ErrClosed.Error()}:
		default:
		}
	}

	return nil
}

func (c *Client) ensureConnected(ctx context.Context) error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return ErrClosed
	}
	if c.conn != nil {
		c.mu.Unlock()
		return nil
	}
	c.mu.Unlock()

	return c.dialAndStart(ctx)
}

func (c *Client) dialAndStart(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}

	dialCtx := ctx
	if _, hasDeadline := ctx.Deadline(); !hasDeadline {
		var cancel context.CancelFunc
		dialCtx, cancel = context.WithTimeout(ctx, defaultDialTimeout)
		defer cancel()
	}

	conn, err := c.dialFn(dialCtx)
	if err != nil {
		return fmt.Errorf("failed to connect to daemon-ably socket %s: %w", c.socketPath, err)
	}

	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		_ = conn.Close()
		return ErrClosed
	}
	if c.conn != nil {
		c.mu.Unlock()
		_ = conn.Close()
		return nil
	}
	c.conn = conn
	c.mu.Unlock()

	go c.readLoop(conn)
	go c.restoreSubscriptions()
	return nil
}

func (c *Client) sendAndAwaitAck(ctx context.Context, payload any, requestID string) (requestAck, error) {
	if requestID == "" {
		return requestAck{}, fmt.Errorf("request id is required")
	}

	ackCh := make(chan requestAck, 1)
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return requestAck{}, ErrClosed
	}
	if c.conn == nil {
		c.mu.Unlock()
		return requestAck{}, ErrNotConnected
	}
	c.pending[requestID] = ackCh
	c.mu.Unlock()

	if err := c.writeJSON(payload); err != nil {
		c.mu.Lock()
		delete(c.pending, requestID)
		c.mu.Unlock()
		return requestAck{}, err
	}

	waitCtx := ctx
	if waitCtx == nil {
		waitCtx = context.Background()
	}
	if _, hasDeadline := waitCtx.Deadline(); !hasDeadline {
		var cancel context.CancelFunc
		waitCtx, cancel = context.WithTimeout(waitCtx, defaultAckTimeout)
		defer cancel()
	}

	select {
	case ack := <-ackCh:
		return ack, nil
	case <-waitCtx.Done():
		c.mu.Lock()
		delete(c.pending, requestID)
		c.mu.Unlock()
		if errors.Is(waitCtx.Err(), context.DeadlineExceeded) {
			return requestAck{}, ErrTimeout
		}
		return requestAck{}, waitCtx.Err()
	}
}

func (c *Client) writeJSON(payload any) error {
	bytes, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("failed to encode transport payload: %w", err)
	}
	bytes = append(bytes, '\n')

	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	c.mu.Lock()
	conn := c.conn
	closed := c.closed
	c.mu.Unlock()
	if closed {
		return ErrClosed
	}
	if conn == nil {
		return ErrNotConnected
	}

	if _, err := conn.Write(bytes); err != nil {
		return ErrNotConnected
	}
	return nil
}

func (c *Client) readLoop(conn net.Conn) {
	scanner := bufio.NewScanner(conn)
	maxFrameBytes := c.maxFrameBytes
	if maxFrameBytes <= 0 {
		maxFrameBytes = defaultMaxFrameBytes
	}
	initialBufferCap := 64 * 1024
	if maxFrameBytes < initialBufferCap {
		initialBufferCap = maxFrameBytes
	}
	scanner.Buffer(make([]byte, 0, initialBufferCap), maxFrameBytes)

	for scanner.Scan() {
		line := scanner.Bytes()
		if err := c.handleLine(line); err != nil {
			c.emitError(err)
		}
	}

	if err := scanner.Err(); err != nil {
		if errors.Is(err, bufio.ErrTooLong) {
			c.emitError(fmt.Errorf("transport frame exceeds max size of %d bytes", maxFrameBytes))
		} else {
			c.emitError(fmt.Errorf("transport read error: %w", err))
		}
	}

	c.handleDisconnect(conn)
}

func (c *Client) handleLine(line []byte) error {
	var op operationEnvelope
	if err := json.Unmarshal(line, &op); err != nil {
		return fmt.Errorf("invalid transport envelope: %w", err)
	}

	switch op.Op {
	case opPublishAck:
		var ack publishAck
		if err := json.Unmarshal(line, &ack); err != nil {
			return fmt.Errorf("invalid publish ack: %w", err)
		}
		c.resolvePending(ack.RequestID, ack.requestAck)
	case opSubscribeAck:
		var ack subscribeAck
		if err := json.Unmarshal(line, &ack); err != nil {
			return fmt.Errorf("invalid subscribe ack: %w", err)
		}
		c.resolvePending(ack.RequestID, ack.requestAck)
	case opMessage:
		var msg messageEnvelope
		if err := json.Unmarshal(line, &msg); err != nil {
			return fmt.Errorf("invalid message envelope: %w", err)
		}
		payload, err := base64.StdEncoding.DecodeString(msg.PayloadB64)
		if err != nil {
			return fmt.Errorf("invalid message payload: %w", err)
		}
		out := &Message{
			SubscriptionID: msg.SubscriptionID,
			MessageID:      msg.MessageID,
			Channel:        msg.Channel,
			Event:          msg.Event,
			Payload:        payload,
			ReceivedAtMS:   msg.ReceivedAtMS,
		}
		select {
		case c.messages <- out:
		default:
			// Preserve one-in-flight consumers by blocking when receiver is slow.
			c.messages <- out
		}
	default:
		// Ignore unknown op types for forward-compatibility.
	}

	return nil
}

func (c *Client) resolvePending(requestID string, ack requestAck) {
	if requestID == "" {
		return
	}

	c.mu.Lock()
	pending := c.pending[requestID]
	delete(c.pending, requestID)
	c.mu.Unlock()

	if pending == nil {
		return
	}

	select {
	case pending <- ack:
	default:
	}
}

func (c *Client) handleDisconnect(readConn net.Conn) {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return
	}
	if c.conn != readConn {
		c.mu.Unlock()
		return
	}
	_ = c.conn.Close()
	c.conn = nil

	pending := c.pending
	c.pending = make(map[string]chan requestAck)

	if c.reconnecting {
		c.mu.Unlock()
		for _, ch := range pending {
			select {
			case ch <- requestAck{OK: false, Error: ErrNotConnected.Error()}:
			default:
			}
		}
		return
	}
	c.reconnecting = true
	c.mu.Unlock()

	for _, ch := range pending {
		select {
		case ch <- requestAck{OK: false, Error: ErrNotConnected.Error()}:
		default:
		}
	}

	go c.reconnectLoop()
}

func (c *Client) reconnectLoop() {
	backoff := 200 * time.Millisecond
	for {
		c.mu.Lock()
		if c.closed {
			c.reconnecting = false
			c.mu.Unlock()
			return
		}
		if c.conn != nil {
			c.reconnecting = false
			c.mu.Unlock()
			return
		}
		c.mu.Unlock()

		ctx, cancel := context.WithTimeout(context.Background(), defaultDialTimeout)
		err := c.dialAndStart(ctx)
		cancel()
		if err == nil {
			c.mu.Lock()
			c.reconnecting = false
			c.mu.Unlock()
			c.emitError(fmt.Errorf("daemon-ably reconnected"))
			return
		}

		c.emitError(fmt.Errorf("daemon-ably reconnect failed: %w", err))
		time.Sleep(backoff)
		if backoff < 3*time.Second {
			backoff *= 2
			if backoff > 3*time.Second {
				backoff = 3 * time.Second
			}
		}
	}
}

func (c *Client) restoreSubscriptions() {
	c.mu.Lock()
	if c.closed || c.conn == nil {
		c.mu.Unlock()
		return
	}
	subscriptions := make([]Subscription, 0, len(c.subscriptions))
	for _, sub := range c.subscriptions {
		subscriptions = append(subscriptions, sub)
	}
	c.mu.Unlock()

	for _, sub := range subscriptions {
		ctx, cancel := context.WithTimeout(context.Background(), defaultAckTimeout)
		requestID := uuid.NewString()
		ack, err := c.sendAndAwaitAck(ctx, subscribeRequest{
			Op:             opSubscribe,
			RequestID:      requestID,
			SubscriptionID: sub.SubscriptionID,
			Channel:        sub.Channel,
			Event:          sub.Event,
		}, requestID)
		cancel()
		if err != nil {
			c.emitError(fmt.Errorf("failed to restore subscription %s: %w", sub.SubscriptionID, err))
			continue
		}
		if !ack.OK {
			if ack.Error == "" {
				c.emitError(fmt.Errorf("failed to restore subscription %s: rejected", sub.SubscriptionID))
			} else {
				c.emitError(fmt.Errorf("failed to restore subscription %s: %s", sub.SubscriptionID, ack.Error))
			}
		}
	}
}

func (c *Client) emitError(err error) {
	if err == nil {
		return
	}
	select {
	case c.errors <- err:
	default:
	}
}

func maxFrameBytesFromEnv() (int, error) {
	raw := os.Getenv(envMaxFrameBytes)
	if raw == "" {
		return defaultMaxFrameBytes, nil
	}
	size, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("invalid %s: %w", envMaxFrameBytes, err)
	}
	if size <= 0 {
		return 0, fmt.Errorf("%s must be positive", envMaxFrameBytes)
	}
	return size, nil
}
